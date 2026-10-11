"""The client end of the bridge: one connection to the editor, many waiters.

A reader task takes every frame off the connection and hands each response to
the call waiting under its id, so a status call answers while a long bake is
still running instead of queueing behind it. Writes share a lock, so two frames
never interleave. The editor still runs one change at a time; this only stops
the client adding a second queue in front of its own.

A dropped connection fails every waiting call, and each is retried once, with
the same `operation_id` for a change, so a change the editor already made comes
back from its cache instead of being made twice.

A change that timed out may still run: the editor reads it off the socket when
it gets to it. So the `operation_id` of every change left without an answer is
kept, and the same change asked for again gets the same id. Whichever copy runs
second is answered from the editor's cache.
"""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import json
import logging
import uuid
from collections import OrderedDict
from pathlib import Path

from hammerforge_mcp import __version__
from hammerforge_mcp.discovery import DiscoveryError, read_discovery
from hammerforge_mcp.framing import FrameError, encode_frame, read_frame

log = logging.getLogger(__name__)

BRIDGE_VERSION = 1
CLIENT_NAME = "hammerforge-mcp"
LOCALHOST = "127.0.0.1"

#: How many unanswered changes to remember. Far more than an agent leaves.
UNANSWERED_LIMIT = 64

_TIMEOUTS = (asyncio.TimeoutError, TimeoutError)
_LOST = (ConnectionError, asyncio.IncompleteReadError, OSError)


class BridgeError(Exception):
    """The bridge could not get an answer. `code` says why, in the bridge's terms."""

    def __init__(self, code: str, message: str, details: dict | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.details = details or {}


class _ConnectionLost(ConnectionError):
    """The connection went while a call waited. The call may be retried."""


class Bridge:
    def __init__(
        self,
        project: Path,
        *,
        discovery: Path | None = None,
        client_version: str = __version__,
        connect_timeout: float = 5.0,
    ) -> None:
        self.project = Path(project)
        #: The discovery file, when it is not the project's own.
        self.discovery = discovery
        self.client_version = client_version
        self.connect_timeout = connect_timeout
        #: What the editor said when it let us in.
        self.welcome: dict | None = None
        #: The editor, scene and level the next change must still be aimed at.
        self.target_id: str | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._reading: asyncio.Task | None = None
        self._waiters: dict[str, asyncio.Future] = {}
        self._connect_lock = asyncio.Lock()
        self._write_lock = asyncio.Lock()
        self._attach_lock = asyncio.Lock()
        self._ids = itertools.count(1)
        #: Which connection this is. A call that failed on an older one must not
        #: close the one another call has just opened.
        self._generation = 0
        #: A change's method and arguments -> the operation_id it was sent with,
        #: for changes that never got an answer.
        self._unanswered: OrderedDict[str, str] = OrderedDict()

    @property
    def connected(self) -> bool:
        return (
            self._writer is not None
            and not self._writer.is_closing()
            and self._reading is not None
            and not self._reading.done()
        )

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

        A change's response carries the `operation_id` it went with, made here
        when the caller gave none. Raises `BridgeError` when there is no response
        to return: the bridge is off, the token is wrong, the editor went away,
        or it took too long.
        """
        key = _change_key(method, params) if mutating else ""
        if mutating and operation_id is None:
            operation_id = self._unanswered.get(key) or uuid.uuid4().hex
        if method != "hf_get_status" and self.target_id is None:
            # Attach before the first change, so it is aimed at the level the
            # editor has open now and not whatever it has open when it lands.
            async with self._attach_lock:
                if self.target_id is None:
                    await self._call_once("hf_get_status", {}, None, timeout)
        try:
            response = await self._call_once(method, params, operation_id, timeout)
        except BridgeError as exc:
            if mutating and exc.code in ("timeout", "bridge_unavailable"):
                self._remember_unanswered(key, operation_id)
                exc.details.setdefault("operation_id", operation_id)
            raise
        if mutating:
            self._unanswered.pop(key, None)
            response.setdefault("operation_id", operation_id)
        return response

    def _remember_unanswered(self, key: str, operation_id: str | None) -> None:
        if operation_id is None:
            return
        self._unanswered[key] = operation_id
        self._unanswered.move_to_end(key)
        while len(self._unanswered) > UNANSWERED_LIMIT:
            self._unanswered.popitem(last=False)

    async def _call_once(
        self, method: str, params: dict, operation_id: str | None, timeout: float
    ) -> dict:
        lost: BaseException | None = None
        for attempt in (1, 2):
            request: dict = {
                "type": "request",
                # A string: Godot reads every JSON number as a float, so 7
                # would come back as 7.0.
                "id": f"r{next(self._ids)}",
                "method": method,
                "params": params,
            }
            if operation_id is not None:
                request["operation_id"] = operation_id
            if method != "hf_get_status" and self.target_id:
                request["expect_target"] = self.target_id
            generation = self._generation
            try:
                await self._ensure_connected()
                generation = self._generation
                response = await self._send_and_wait(request, timeout)
            except _TIMEOUTS:
                hint = (
                    f" Send it again with operation_id {operation_id} and it will "
                    "not run twice."
                    if operation_id
                    else ""
                )
                raise BridgeError(
                    "timeout",
                    f"{method} did not answer within {timeout:g} s. The editor may "
                    "still be working on it: hf_get_status says what it is busy with."
                    + hint,
                ) from None
            except FrameError as exc:
                await self._drop(generation)
                raise BridgeError(exc.code, str(exc)) from None
            except BridgeError:
                await self._drop(generation)
                raise
            except _LOST as exc:
                await self._drop(generation)
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

    async def _send_and_wait(self, request: dict, timeout: float) -> dict:
        future: asyncio.Future = asyncio.get_running_loop().create_future()
        self._waiters[request["id"]] = future
        try:
            async with self._write_lock:
                writer = self._writer
                if writer is None:
                    raise _ConnectionLost("not connected")
                writer.write(encode_frame(request))
                await writer.drain()
            return await asyncio.wait_for(future, timeout)
        finally:
            self._waiters.pop(request["id"], None)

    async def _read_loop(self, reader: asyncio.StreamReader) -> None:
        """Hand each response to its waiter until the connection goes."""
        try:
            while True:
                message = await read_frame(reader)
                kind = message.get("type")
                if kind == "response":
                    waiter = self._waiters.get(str(message.get("id")))
                    if waiter is not None and not waiter.done():
                        waiter.set_result(message)
                    else:
                        log.debug("an answer nobody waits for: %s", message.get("id"))
                elif kind == "error":
                    # The editor closes the connection after one of these.
                    error = message.get("error") or {}
                    self._fail_all(
                        BridgeError(
                            str(error.get("code", "bad_request")),
                            str(
                                error.get("message", "The editor closed the connection")
                            ),
                            error.get("details") or {},
                        )
                    )
                    return
                else:
                    log.debug("ignoring a %s frame", kind)
        except FrameError as exc:
            self._fail_all(exc)
        except _LOST as exc:
            self._fail_all(
                _ConnectionLost(str(exc) or "the editor closed the connection")
            )

    def _fail_all(self, exc: BaseException) -> None:
        for waiter in list(self._waiters.values()):
            if not waiter.done():
                waiter.set_exception(exc)

    async def _ensure_connected(self) -> None:
        async with self._connect_lock:
            if self.connected:
                return
            await self._drop()
            await self._connect()

    async def _connect(self) -> None:
        try:
            found = read_discovery(self.project, path=self.discovery)
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
        hello = {
            "type": "hello",
            "bridge_version": BRIDGE_VERSION,
            "token": found.token,
            "client": {"name": CLIENT_NAME, "version": self.client_version},
        }
        try:
            writer.write(encode_frame(hello))
            await writer.drain()
            reply = await asyncio.wait_for(read_frame(reader), self.connect_timeout)
        except (*_TIMEOUTS, *_LOST) as exc:
            writer.close()
            raise ConnectionError("the editor did not answer the hello") from exc
        if reply.get("type") != "welcome":
            writer.close()
            error = reply.get("error") or {}
            raise BridgeError(
                str(error.get("code", "bad_request")),
                str(error.get("message", "The editor refused the connection")),
                error.get("details") or {},
            )
        self.welcome = reply
        self._generation += 1
        self._reader, self._writer = reader, writer
        self._reading = asyncio.create_task(self._read_loop(reader))
        log.info(
            "connected to HammerForge %s on port %d",
            reply.get("hammerforge_version", "?"),
            found.port,
        )

    async def _drop(self, generation: int | None = None) -> None:
        """Close the connection, or only the one `generation` names if it is
        still the current one."""
        if generation is not None and generation != self._generation:
            return
        reading, writer = self._reading, self._writer
        self._reading = None
        self._reader = None
        self._writer = None
        self._fail_all(_ConnectionLost("the connection was closed"))
        if reading is not None and not reading.done():
            reading.cancel()
            with contextlib.suppress(asyncio.CancelledError, *_LOST):
                await reading
        if writer is not None:
            writer.close()
            with contextlib.suppress(*_LOST):
                await writer.wait_closed()


def _change_key(method: str, params: dict) -> str:
    return json.dumps([method, params], sort_keys=True, separators=(",", ":"))
