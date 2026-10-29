"""The bridge's wire format: a 4-byte big-endian length, then UTF-8 JSON.

The editor end is `addons/hammerforge/mcp/hf_mcp_protocol.gd`. Both follow
`docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`.
"""

from __future__ import annotations

import asyncio
import json
import math
import struct

MAX_REQUEST_BYTES = 1 << 20
MAX_RESPONSE_BYTES = 16 << 20
MAX_JSON_DEPTH = 64

_HEADER = struct.Struct(">I")


class FrameError(Exception):
    """A frame that cannot be sent or read. `code` matches the bridge's codes."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def encode_frame(message: dict, max_bytes: int = MAX_REQUEST_BYTES) -> bytes:
    try:
        # allow_nan off: NaN and Infinity are not JSON, and Godot's parser
        # refuses the whole frame rather than the one number.
        _check_json(message)
        text = json.dumps(
            message, ensure_ascii=False, separators=(",", ":"), allow_nan=False
        )
        body = text.encode()
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise FrameError(
            "invalid_argument",
            "A request must be UTF-8 JSON with finite numbers and at most "
            f"{MAX_JSON_DEPTH} nested containers",
        ) from None
    if len(body) > max_bytes:
        raise FrameError(
            "frame_too_large",
            f"A request of {len(body)} bytes is over the {max_bytes} byte limit",
        )
    return _HEADER.pack(len(body)) + body


async def read_frame(
    reader: asyncio.StreamReader, max_bytes: int = MAX_RESPONSE_BYTES
) -> dict:
    """Read one message. Raises `asyncio.IncompleteReadError` on a closed socket."""
    header = await reader.readexactly(_HEADER.size)
    (size,) = _HEADER.unpack(header)
    if size > max_bytes:
        raise FrameError(
            "frame_too_large",
            f"A frame of {size} bytes is over the {max_bytes} byte limit",
        )
    body = await reader.readexactly(size)
    try:
        message = json.loads(body.decode())
        _check_json(message)
    except (UnicodeError, ValueError, RecursionError):
        # Do not echo the received body; a broken hello may contain a token.
        raise FrameError(
            "bad_request",
            "A frame must be UTF-8 JSON with finite numbers and at most "
            f"{MAX_JSON_DEPTH} nested containers",
        ) from None
    if not isinstance(message, dict):
        raise FrameError("bad_request", "A frame must hold one JSON object")
    return message


def _check_json(value: object) -> None:
    # Iterators keep memory proportional to depth, even for a large brush list.
    # Use an explicit bound rather than the interpreter's recursion limit,
    # which differs across Python versions. Cycles also hit this bound.
    stack = [iter((value,))]
    while stack:
        try:
            item = next(stack[-1])
        except StopIteration:
            stack.pop()
            continue
        if isinstance(item, float) and not math.isfinite(item):
            raise ValueError("non-finite number")
        if isinstance(item, (dict, list, tuple)):
            if len(stack) > MAX_JSON_DEPTH:
                raise ValueError("JSON nesting limit exceeded")
            stack.append(iter(item.values() if isinstance(item, dict) else item))
