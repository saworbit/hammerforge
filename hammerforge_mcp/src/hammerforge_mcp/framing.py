"""The bridge's wire format: a 4-byte big-endian length, then UTF-8 JSON.

The editor end is `addons/hammerforge/mcp/hf_mcp_protocol.gd`. Both follow
`docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`.
"""

from __future__ import annotations

import asyncio
import json
import struct

MAX_REQUEST_BYTES = 1 << 20
MAX_RESPONSE_BYTES = 16 << 20

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
        text = json.dumps(
            message, ensure_ascii=False, separators=(",", ":"), allow_nan=False
        )
    except ValueError as exc:
        raise FrameError("invalid_argument", f"Numbers must be finite: {exc}") from exc
    body = text.encode()
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
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise FrameError("bad_request", f"Not JSON: {exc}") from exc
    if not isinstance(message, dict):
        raise FrameError("bad_request", "A frame must hold one JSON object")
    return message
