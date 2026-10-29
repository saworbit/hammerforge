"""The client end of the bridge: one connection to the editor, many waiters.

A reader task takes every frame off the connection and hands each response to
the call waiting under its id, so a status call answers while a long bake is
still running instead of queueing behind it. Writes share a lock, so two frames
never interleave. The editor still runs one change at a time; this only stops
the client adding a second queue in front of its own.

A dropped connection fails every waiting call, and each is retried once, with
the same `operation_id` for a change, so a change the editor already made comes
back from its cache instead of being made twice.

A change that timed out or was cancelled may still run: the editor reads it off
the socket when it gets to it. So the `operation_id` of every sent change left
without an answer is kept for the same arguments on the same target. The copy
that runs second is answered from the editor's cache. Each is kept on its own:
a repeat takes the oldest one that no other call is sending, and an answer
clears only its own id, so a separate edit with the same arguments never makes
an earlier one's retry look new. Not for undo, redo and
bake, whose arguments do not say which change they are: a second undo is as
likely meant as another undo, so it gets a new id unless the caller passes the
old one.
"""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import json
import logging
import uuid
from collections import Counter, OrderedDict
from dataclasses import dataclass
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

#: Changes whose arguments do not say which change they are. A repeat of one is
#: not taken for a retry; a caller that means a retry passes the operation_id.
NOT_RETRIED_BY_ARGUMENTS = frozenset({"hf_undo", "hf_redo", "hf_bake"})

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


@dataclass
class _CallState:
    # Once written, a cancelled or failed change may still run in the editor.
    sent: bool = False
    target_id: str | None = None


class Bridge:
    def __init__(
        self,
        project: Path,
        *,
        discovery: Path | None = None,
        client_version: str = __version__,
        connect_timeout: float = 5.0,
        observer: bool = False,
    ) -> None:
        self.project = Path(project)
        #: Ask for status beside the agent rather than in its place. The editor
        #: answers an observer status and nothing else (#1060).
        self.observer = observer
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
        self._target_response = 0
        #: Which connection this is. A call that failed on an older one must not
        #: close the one another call has just opened.
        self._generation = 0
        #: operation_id -> (the change's method and arguments, original target),
        #: for changes that never got an answer, oldest first. Never reused on
        #: another level.
        self._unanswered: OrderedDict[str, tuple[str, str | None]] = OrderedDict()
        #: How many calls are sending each operation_id now. A repeat does not
        #: take an unanswered id another call is already retrying.
        self._sending: Counter[str] = Counter()

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
        or it took too long. The timeout covers attachment, connection, writes,
        reconnect and response. Cancellation stops waiting, not an edit already
        sent. Use explicit ids for identical edits that can interleave.
        """
        by_arguments = mutating and method not in NOT_RETRIED_BY_ARGUMENTS
        key = _change_key(method, params) if by_arguments else ""
        if mutating and operation_id is None:
            operation_id = (
                self._unanswered_retry(key) if by_arguments else None
            ) or uuid.uuid4().hex
        state = _CallState()
        if operation_id is not None:
            self._sending[operation_id] += 1
        try:
            # One budget for attaching, connecting, waiting to write, draining,
            # reconnecting and reading. A timeout also removes an unsent waiter.
            response = await asyncio.wait_for(
                self._call_attached(method, params, operation_id, state), timeout
            )
        except _TIMEOUTS:
            if by_arguments and state.sent:
                self._remember_unanswered(key, operation_id, state.target_id)
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
                {"operation_id": operation_id} if mutating else {},
            ) from None
        except asyncio.CancelledError:
            if by_arguments and state.sent:
                self._remember_unanswered(key, operation_id, state.target_id)
            raise
        except BridgeError as exc:
            if mutating and state.sent:
                if by_arguments:
                    self._remember_unanswered(key, operation_id, state.target_id)
                # A connection-level failure reaches several callers. Each
                # must report its own id, without changing another's exception.
                raise BridgeError(
                    exc.code, str(exc), {**exc.details, "operation_id": operation_id}
                ) from None
            raise
        finally:
            if operation_id is not None:
                self._sending[operation_id] -= 1
                if self._sending[operation_id] <= 0:
                    del self._sending[operation_id]
        # An answer settles only its own change, never another one's retry.
        if by_arguments and self._unanswered.get(operation_id) == (
            key,
            state.target_id,
        ):
            del self._unanswered[operation_id]
        if mutating:
            response.setdefault("operation_id", operation_id)
        return response

    async def _call_attached(
        self, method: str, params: dict, operation_id: str | None, state: _CallState
    ) -> dict:
        if method != "hf_get_status" and self.target_id is None:
            async with self._attach_lock:
                if self.target_id is None:
                    await self._call_once("hf_get_status", {}, None, _CallState())
        return await self._call_once(method, params, operation_id, state)

    def _unanswered_retry(self, key: str) -> str | None:
        """The oldest unanswered change with these arguments on this target
        that no other call is sending now."""
        for operation_id, remembered in self._unanswered.items():
            if (
                remembered == (key, self.target_id)
                and operation_id not in self._sending
            ):
                return operation_id
        return None

    def _remember_unanswered(
        self, key: str, operation_id: str | None, target_id: str | None
    ) -> None:
        if operation_id is None:
            return
        self._unanswered[operation_id] = (key, target_id)
        self._unanswered.move_to_end(operation_id)
        while len(self._unanswered) > UNANSWERED_LIMIT:
            self._unanswered.popitem(last=False)

    async def _call_once(
        self, method: str, params: dict, operation_id: str | None, state: _CallState
    ) -> dict:
        lost: BaseException | None = None
        # A status running alongside this call may attach to another scene.
        # Retries must keep the original target as well as the operation id.
        state.target_id = self.target_id
        for attempt in (1, 2):
            request_number = next(self._ids)
            request: dict = {
                "type": "request",
                # A string: Godot reads every JSON number as a float, so 7
                # would come back as 7.0.
                "id": f"r{request_number}",
                "method": method,
                "params": params,
            }
            if operation_id is not None:
                request["operation_id"] = operation_id
            if method != "hf_get_status" and state.target_id:
                request["expect_target"] = state.target_id
            try:
                frame = encode_frame(request)
            except FrameError as exc:
                # Too big, or not JSON: never sent, so the connection is as good
                # as it was, and other calls may be using it.
                raise BridgeError(exc.code, str(exc)) from None
            generation = self._generation
            try:
                await self._ensure_connected()
                generation = self._generation
                response = await self._send_and_wait(request["id"], frame, state)
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
            if (
                response.get("ok")
                and response.get("target_id")
                and method in ("hf_get_status", "hf_create_starter")
                and request_number > self._target_response
            ):
                # Ordinary reads and changes cannot reattach an old target
                # when their replies arrive after a newer status answer.
                self.target_id = response["target_id"]
                self._target_response = request_number
            return response
        raise BridgeError(
            "bridge_unavailable",
            f"Lost the connection to the editor during {method}: {lost}. "
            "Check the editor is still open and the bridge is still ticked.",
        )

    async def _send_and_wait(
        self, request_id: str, frame: bytes, state: _CallState
    ) -> dict:
        future: asyncio.Future = asyncio.get_running_loop().create_future()
        self._waiters[request_id] = future
        try:
            async with self._write_lock:
                if future.done():
                    # The connection this was meant for went while it waited to
                    # write, and maybe another came up. Not sent: the retry sends
                    # it once, on that one. Raises the lost connection.
                    return future.result()
                writer = self._writer
                if writer is None:
                    raise _ConnectionLost("not connected")
                state.sent = True
                writer.write(frame)
                await writer.drain()
            return await future
        finally:
            self._waiters.pop(request_id, None)
            if not future.done():
                future.cancel()
            elif not future.cancelled():
                # A disconnect may fail the waiter while the caller is still
                # draining or waiting for the lock, then cancellation wins.
                future.exception()

    async def _read_loop(self, reader: asyncio.StreamReader) -> None:
        """Hand each response to its waiter until the connection goes."""
        try:
            while True:
                message = await read_frame(reader)
                kind = message.get("type")
                if kind == "response":
                    _validate_response(message)
                    waiter = self._waiters.get(str(message.get("id")))
                    if waiter is not None and not waiter.done():
                        waiter.set_result(message)
                    else:
                        log.debug("an answer nobody waits for: %s", message.get("id"))
                elif kind == "error":
                    # The editor closes the connection after one of these.
                    self._fail_all(_response_error(message))
                    return
                else:
                    raise FrameError("bad_request", "Unexpected bridge frame type")
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
        if self.observer:
            hello["role"] = "observer"
        accepted = False
        try:
            writer.write(encode_frame(hello))
            await writer.drain()
            reply = await asyncio.wait_for(read_frame(reader), self.connect_timeout)
            if reply.get("type") == "error":
                raise _response_error(reply)
            if reply.get("type") != "welcome":
                raise FrameError("bad_request", "Expected a bridge welcome frame")
            version = reply.get("bridge_version")
            if isinstance(version, bool) or version != BRIDGE_VERSION:
                raise BridgeError(
                    "unsupported_bridge_version",
                    "The editor's welcome does not match this server's bridge "
                    f"version {BRIDGE_VERSION}. Update whichever is older.",
                )
            accepted = True
        except (*_TIMEOUTS, *_LOST) as exc:
            raise ConnectionError("the editor did not answer the hello") from exc
        finally:
            # Includes cancellation and malformed frames. Until accepted this
            # writer belongs to the handshake, so _drop cannot close it.
            if not accepted:
                writer.close()
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
        try:
            if reading is not None and not reading.done():
                reading.cancel()
                # wait, not await: the reader's own CancelledError stays in its
                # task, and a cancel of the caller still goes through.
                await asyncio.wait({reading})
        finally:
            if writer is not None:
                writer.close()
        if writer is not None:
            with contextlib.suppress(*_LOST):
                await writer.wait_closed()


def _change_key(method: str, params: dict) -> str:
    try:
        return json.dumps(
            [method, params], sort_keys=True, separators=(",", ":"), allow_nan=False
        )
    except (TypeError, ValueError, RecursionError):
        raise BridgeError(
            "invalid_argument", "Tool arguments must be finite JSON values"
        ) from None


def _response_error(message: dict) -> BridgeError:
    error = message.get("error")
    if (
        not isinstance(error, dict)
        or not isinstance(error.get("code"), str)
        or not error["code"]
        or not isinstance(error.get("message"), str)
        or not isinstance(error.get("details", {}), dict)
    ):
        raise FrameError("bad_request", "Malformed bridge error envelope")
    return BridgeError(error["code"], error["message"], error.get("details", {}))


def _validate_response(message: dict) -> None:
    revision = message.get("revision")
    if (
        not isinstance(message.get("id"), str)
        or not message["id"]
        or not isinstance(message.get("ok"), bool)
        or not isinstance(message.get("target_id"), str)
        or isinstance(revision, bool)
        or not isinstance(revision, (int, float))
        or revision < 0
        or revision != int(revision)
        or ("replayed" in message and not isinstance(message["replayed"], bool))
    ):
        raise FrameError("bad_request", "Malformed bridge response envelope")
    if message["ok"]:
        if not isinstance(message.get("result"), dict):
            raise FrameError("bad_request", "A bridge result must be an object")
    else:
        _response_error(message)
