import json

import pytest
from mcp import Client

from hammerforge_mcp.bridge import BridgeError
from hammerforge_mcp.catalogue import TOOLS
from hammerforge_mcp.server import build_server

pytestmark = pytest.mark.anyio


class FakeBridge:
    """Answers each method with a canned response, or raises a canned error."""

    def __init__(self, answers: dict) -> None:
        self.answers = answers
        self.calls: list[dict] = []

    async def call(self, method, params, *, mutating, timeout, operation_id=None):
        self.calls.append(
            {
                "method": method,
                "params": params,
                "mutating": mutating,
                "timeout": timeout,
                "operation_id": operation_id,
            }
        )
        answer = self.answers[method]
        if isinstance(answer, Exception):
            raise answer
        return answer


def _ok(result: dict) -> dict:
    return {
        "type": "response",
        "id": "r1",
        "ok": True,
        "result": result,
        "revision": 7,
        "target_id": "1:2:3",
        "replayed": False,
    }


def _failed(code: str) -> dict:
    return {
        "type": "response",
        "id": "r1",
        "ok": False,
        "error": {"code": code, "message": "nope", "details": {"param": "size"}},
        "revision": 7,
        "target_id": "1:2:3",
    }


async def test_the_catalogue_is_exactly_what_is_listed():
    async with Client(build_server(FakeBridge({}))) as client:
        listed = (await client.list_tools()).tools
    assert {tool.name for tool in listed} == set(TOOLS)
    by_name = {tool.name: tool for tool in listed}
    status = by_name["hf_get_status"]
    assert status.annotations.read_only_hint is True
    assert status.annotations.open_world_hint is False
    place = by_name["hf_place_brush"]
    assert place.annotations.read_only_hint is False
    assert place.annotations.destructive_hint is False
    assert "Godot Y-up, metres" in place.description
    assert place.output_schema is not None
    size = place.input_schema["properties"]["size"]
    assert size["minItems"] == 3 and size["maxItems"] == 3


async def test_a_good_answer_is_structured_and_in_the_text():
    bridge = FakeBridge({"hf_place_brush": _ok({"brush": {"brush_id": "b1"}})})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool(
            "hf_place_brush", {"size": [4, 3, 4], "position": [0, 1.5, 0]}
        )
    assert result.is_error is False
    assert result.structured_content["ok"] is True
    assert result.structured_content["result"]["brush"]["brush_id"] == "b1"
    assert result.structured_content["revision"] == 7
    assert json.loads(result.content[0].text) == result.structured_content
    call = bridge.calls[0]
    assert call["mutating"] is True
    assert call["params"] == {
        "size": [4.0, 3.0, 4.0],
        "position": [0.0, 1.5, 0.0],
        "shape": "box",
        "operation": "union",
        "snap": True,
    }


async def test_an_operation_id_is_passed_through():
    bridge = FakeBridge({"hf_place_brush": _ok({})})
    async with Client(build_server(bridge)) as client:
        await client.call_tool(
            "hf_place_brush",
            {"size": [1, 1, 1], "position": [0, 0, 0], "operation_id": "op-1"},
        )
    assert bridge.calls[0]["operation_id"] == "op-1"


async def test_a_domain_error_is_a_result_not_an_error():
    bridge = FakeBridge({"hf_place_brush": _failed("invalid_argument")})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool(
            "hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]}
        )
    assert result.is_error is False
    assert result.structured_content["ok"] is False
    assert result.structured_content["error"]["code"] == "invalid_argument"


async def test_a_protocol_error_is_an_error():
    bridge = FakeBridge({"hf_get_status": _failed("internal_error")})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool("hf_get_status", {})
    assert result.is_error is True


async def test_a_bridge_failure_is_an_error_that_says_what_to_do():
    bridge = FakeBridge(
        {"hf_get_status": BridgeError("bridge_off", "The bridge is off. Tick it.")}
    )
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool("hf_get_status", {})
    assert result.is_error is True
    assert "Tick it" in result.content[0].text


async def test_bad_arguments_never_reach_the_editor():
    bridge = FakeBridge({"hf_place_brush": _ok({})})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool(
            "hf_place_brush", {"size": [1, 1], "position": [0, 0, 0]}
        )
    assert result.is_error is True
    assert bridge.calls == []


async def test_timeouts_come_from_the_catalogue():
    bridge = FakeBridge({"hf_get_status": _ok({})})
    async with Client(build_server(bridge)) as client:
        await client.call_tool("hf_get_status", {})
    assert bridge.calls[0]["timeout"] == TOOLS["hf_get_status"].timeout
    assert bridge.calls[0]["mutating"] is False
