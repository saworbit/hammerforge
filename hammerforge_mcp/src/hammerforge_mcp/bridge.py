"""The client end of the bridge: one connection to the editor, one request at a time.

The editor runs one command at a time anyway, so a lock here keeps request and
answer paired without a table of waiters. A dropped connection is retried once,
with the same `operation_id` for a change, so a change the editor already made
comes back from its cache instead of being made twice.
"""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import logging
import uuid
from pathlib import Path

from hammerforge_mcp import __version__
from hammerforge_mcp.discovery import DiscoveryError, read_discovery
from hammerforge_mcp.framing import FrameError, encode_frame, read_frame

log = logging.getLogger(__name__)

BRIDGE_VERSION = 1
CLIENT_NAME = "hammerforge-mcp"
LOCALHOST = "127.0.0.1"

_TIMEOUTS = (asyncio.TimeoutError, TimeoutError)
_LOST = (ConnectionError, asyncio.IncompleteReadError, OSError)


class BridgeError(Exception):
    """The bridge could not get an answer. `code` says why, in the bridge's terms."""

    def __init__(self, code: str, message: str, details: dict | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.details = details or {}


class Bridge:
    def __init__(
        self,
        project: Path,
        *,
        client_version: str = __version__,
        connect_timeout: float = 5.0,
    ) -> None:
        self.project = Path(project)
        self.client_version = client_version
        self.connect_timeout = connect_timeout
        #: What the editor said when it let us in.
        self.welcome: dict | None = None
        #: The editor, scene and level the next change must still be aimed at.
        self.target_id: str | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._lock = asyncio.Lock()
        self._ids = itertools.count(1)

    @property
    def connected(self) -> bool:
        return self._writer is not None and not self._writer.is_closing()

    async def close(self) -> None:
        await self._drop()

    async def call(
        self,
        method: str,
        params: dict,
        *,
        mutating: bool,
        timeout: float,
        operation_id: str | None = None,
    ) -> dict:
        """Send one request and return the editor's response, ok or not.

        Raises `BridgeError` when there is no response to return: the bridge is
        off, the token is wrong, the editor went away, or it took too long.
        """
        async with self._lock:
            if mutating and operation_id is None:
                operation_id = uuid.uuid4().hex
            if method != "hf_get_status" and self.target_id is None:
                # Attach before the first change, so it is aimed at the level the
                # editor has open now and not whatever it has open when it lands.
                await self._call_once("hf_get_status", {}, None, timeout)
            return await self._call_once(method, params, operation_id, timeout)

    async def _call_once(
        self, method: str, params: dict, operation_id: str | None, timeout: float
    ) -> dict:
        request: dict = {
            "type": "request",
            # A string: Godot reads every JSON number as a float, so 7 would
            # come back as 7.0.
            "id": f"r{next(self._ids)}",
            "method": method,
            "params": params,
        }
        if operation_id is not None:
            request["operation_id"] = operation_id
        if method != "hf_get_status" and self.target_id:
            request["expect_target"] = self.target_id
        lost: BaseException | None = None
        for attempt in (1, 2):
            try:
                await self._ensure_connected()
                response = await asyncio.wait_for(self._exchange(request), timeout)
            except _TIMEOUTS:
                await self._drop()
                raise BridgeError(
                    "timeout",
                    f"{method} did not answer within {timeout:g} s. The editor may "
                    "still be working on it: hf_get_status says what it is busy with.",
                ) from None
            except FrameError as exc:
                await self._drop()
                raise BridgeError(exc.code, str(exc)) from None
            except _LOST as exc:
                await self._drop()
                lost = exc
                log.warning(
                    "lost the editor during %s (try %d): %s", method, attempt, exc
                )
                continue
            if response.get("ok") and response.get("target_id"):
                self.target_id = str(response["target_id"])
            return response
        raise BridgeError(
            "bridge_unavailable",
            f"Lost the connection to the editor during {method}: {lost}. "
            "Check the editor is still open and the bridge is still ticked.",
        )

    async def _exchange(self, request: dict) -> dict:
        assert self._reader is not None and self._writer is not None
        self._writer.write(encode_frame(request))
        await self._writer.drain()
        while True:
            message = await read_frame(self._reader)
            kind = message.get("type")
            if kind == "response" and message.get("id") == request["id"]:
                return message
            if kind == "error":
                error = message.get("error") or {}
                raise BridgeError(
                    str(error.get("code", "bad_request")),
                    str(error.get("message", "The editor closed the connection")),
                    error.get("details") or {},
                )
            log.debug("ignoring a %s frame while waiting for %s", kind, request["id"])

    async def _ensure_connected(self) -> None:
        if self.connected:
            return
        try:
            found = read_discovery(self.project)
        except DiscoveryError as exc:
            raise BridgeError("bridge_off", str(exc)) from None
        if found.bridge_version != BRIDGE_VERSION:
            raise BridgeError(
                "unsupported_bridge_version",
                f"The editor speaks bridge version {found.bridge_version} and this "
                f"server speaks {BRIDGE_VERSION}. Update whichever is older.",
            )
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(LOCALHOST, found.port), self.connect_timeout
            )
        except (*_TIMEOUTS, OSError) as exc:
            raise ConnectionError(f"no answer on {LOCALHOST}:{found.port}") from exc
        self._reader, self._writer = reader, writer
        hello = {
            "type": "hello",
            "bridge_version": BRIDGE_VERSION,
            "token": found.token,
            "client": {"name": CLIENT_NAME, "version": self.client_version},
        }
        writer.write(encode_frame(hello))
        await writer.drain()
        try:
            reply = await asyncio.wait_for(read_frame(reader), self.connect_timeout)
        except _TIMEOUTS as exc:
            await self._drop()
            raise ConnectionError("the editor did not answer the hello") from exc
        if reply.get("type") == "welcome":
            self.welcome = reply
            log.info(
                "connected to HammerForge %s on port %d",
                reply.get("hammerforge_version", "?"),
                found.port,
            )
            return
        await self._drop()
        error = reply.get("error") or {}
        raise BridgeError(
            str(error.get("code", "bad_request")),
            str(error.get("message", "The editor refused the connection")),
            error.get("details") or {},
        )

    async def _drop(self) -> None:
        writer = self._writer
        self._reader = None
        self._writer = None
        if writer is None:
            return
        writer.close()
        with contextlib.suppress(*_LOST):
            await writer.wait_closed()
