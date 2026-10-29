import asyncio
import struct

import pytest

from hammerforge_mcp.framing import MAX_JSON_DEPTH, FrameError, encode_frame, read_frame


def _reader_with(data: bytes) -> asyncio.StreamReader:
    reader = asyncio.StreamReader()
    reader.feed_data(data)
    reader.feed_eof()
    return reader


def test_frame_is_big_endian_length_then_json():
    frame = encode_frame({"a": "é"})
    (size,) = struct.unpack(">I", frame[:4])
    assert size == len(frame) - 4
    assert frame[4:] == '{"a":"é"}'.encode()


def test_oversized_request_is_refused():
    with pytest.raises(FrameError) as caught:
        encode_frame({"a": "x" * 100}, max_bytes=10)
    assert caught.value.code == "frame_too_large"


@pytest.mark.anyio
async def test_round_trip():
    message = {"type": "request", "id": "r1", "params": {"size": [1, 2, 3]}}
    assert await read_frame(_reader_with(encode_frame(message))) == message


@pytest.mark.anyio
async def test_two_frames_read_in_order():
    reader = _reader_with(encode_frame({"id": "a"}) + encode_frame({"id": "b"}))
    assert (await read_frame(reader))["id"] == "a"
    assert (await read_frame(reader))["id"] == "b"


@pytest.mark.anyio
async def test_declared_length_over_the_limit():
    with pytest.raises(FrameError) as caught:
        await read_frame(_reader_with(b"\x7f\xff\xff\xff"), max_bytes=64)
    assert caught.value.code == "frame_too_large"


@pytest.mark.anyio
async def test_not_json_and_not_an_object():
    for body in (b"{nope", b"[1, 2]"):
        with pytest.raises(FrameError) as caught:
            await read_frame(_reader_with(struct.pack(">I", len(body)) + body))
        assert caught.value.code == "bad_request"


@pytest.mark.anyio
async def test_a_closed_socket_mid_frame():
    with pytest.raises(asyncio.IncompleteReadError):
        await read_frame(_reader_with(b"\x00\x00\x00\x10{"))


def test_nan_and_infinity_are_refused_before_they_are_sent():
    for value in (float("nan"), float("inf")):
        with pytest.raises(FrameError) as caught:
            encode_frame({"size": [value, 1, 1]})
        assert caught.value.code == "invalid_argument"


@pytest.mark.parametrize("value", [object(), {1, 2}, "\ud800"])
def test_unsendable_values_are_argument_errors(value):
    with pytest.raises(FrameError) as caught:
        encode_frame({"value": value})
    assert caught.value.code == "invalid_argument"


@pytest.mark.anyio
@pytest.mark.parametrize(
    "body",
    [
        b'{"n": NaN}',
        b'{"n": Infinity}',
        b'{"n": -Infinity}',
        b'{"n": 1e9999}',
        b'{"n": -1e9999}',
        b'{"n":'
        + b"[" * (MAX_JSON_DEPTH + 1)
        + b"0"
        + b"]" * (MAX_JSON_DEPTH + 1)
        + b"}",
    ],
)
async def test_invalid_inbound_numbers_and_nesting_are_frame_errors(body):
    with pytest.raises(FrameError) as caught:
        await read_frame(_reader_with(struct.pack(">I", len(body)) + body))
    assert caught.value.code == "bad_request"


def test_too_deep_outbound_json_is_an_argument_error():
    value = []
    for _ in range(MAX_JSON_DEPTH + 1):
        value = [value]
    with pytest.raises(FrameError) as caught:
        encode_frame({"value": value})
    assert caught.value.code == "invalid_argument"


@pytest.mark.anyio
async def test_json_at_the_depth_limit_round_trips():
    value = 1
    for _ in range(MAX_JSON_DEPTH - 1):
        value = [value]
    message = {"value": value}
    assert await read_frame(_reader_with(encode_frame(message))) == message
