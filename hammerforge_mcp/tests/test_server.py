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


async def test_numbers_that_are_not_json_never_reach_the_editor():
    bridge = FakeBridge({"hf_place_brush": _ok({})})
    async with Client(build_server(bridge)) as client:
        for size in ([float("nan"), 1, 1], [1e999, 1, 1], [True, 1, 1]):
            result = await client.call_tool(
                "hf_place_brush", {"size": size, "position": [0, 0, 0]}
            )
            assert result.is_error is True, size
    assert bridge.calls == []


async def test_the_operation_id_is_in_the_answer():
    answer = _ok({})
    answer["operation_id"] = "op-7"
    bridge = FakeBridge({"hf_place_brush": answer})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool(
            "hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]}
        )
    assert result.structured_content["operation_id"] == "op-7"


#: The fewest arguments each tool accepts.
MINIMAL_ARGS = {
    "hf_get_status": {},
    "hf_place_brush": {"size": [1, 1, 1], "position": [0, 0, 0]},
    "hf_get_brushes": {},
    "hf_get_materials": {},
    "hf_transform_brush": {"brush_id": "b", "position": [0, 0, 0]},
    "hf_resize_brush": {"brush_id": "b", "size": [1, 1, 1]},
    "hf_delete_brush": {"brush_id": "b"},
    "hf_extrude_face": {"brush_id": "b", "face": "+y", "distance": 1},
    "hf_assign_material": {"brush_id": "b", "material": "m"},
    "hf_set_spawn": {"position": [0, 0, 0]},
    "hf_create_starter": {},
    "hf_undo": {},
    "hf_redo": {},
    "hf_bake": {},
    "hf_validate": {},
    "hf_viewport_screenshot": {},
    "hf_batch": {"ops": [{"tool": "hf_delete_brush", "params": {"brush_id": "b"}}]},
}


async def test_every_tool_reaches_the_editor_with_its_mutating_flag():
    assert set(MINIMAL_ARGS) == set(TOOLS), "a test argument set for every tool"
    bridge = FakeBridge({name: _ok({}) for name in TOOLS})
    async with Client(build_server(bridge)) as client:
        for name, args in MINIMAL_ARGS.items():
            result = await client.call_tool(name, args)
            assert result.is_error is False, (name, result.content)
    sent = {call["method"]: call["mutating"] for call in bridge.calls}
    for name, spec in TOOLS.items():
        assert sent[name] is spec.mutating, name


async def test_the_three_face_selectors_pass_through():
    bridge = FakeBridge({"hf_extrude_face": _ok({}), "hf_assign_material": _ok({})})
    async with Client(build_server(bridge)) as client:
        for face in (2, "-x", {"normal": [0, 1, 0]}):
            args = {"brush_id": "b", "face": face, "distance": 1}
            result = await client.call_tool("hf_extrude_face", args)
            assert result.is_error is False, face
        await client.call_tool(
            "hf_assign_material",
            {
                "brush_id": "b",
                "material": "m",
                "faces": [0, "+y", {"normal": [1, 0, 0]}],
            },
        )
    faces = [call["params"]["face"] for call in bridge.calls[:3]]
    assert faces == [2, "-x", {"normal": [0.0, 1.0, 0.0]}]
    assert bridge.calls[3]["params"]["faces"] == [0, "+y", {"normal": [1.0, 0.0, 0.0]}]


async def test_a_face_selector_that_is_none_of_the_three_is_refused():
    bridge = FakeBridge({"hf_extrude_face": _ok({})})
    async with Client(build_server(bridge)) as client:
        for face in (True, "up", -1, {"normal": [0, 1]}):
            args = {"brush_id": "b", "face": face, "distance": 1}
            result = await client.call_tool("hf_extrude_face", args)
            assert result.is_error is True, face
    assert bridge.calls == []


async def test_optional_fields_are_left_out_when_absent():
    bridge = FakeBridge(
        {
            "hf_transform_brush": _ok({}),
            "hf_get_brushes": _ok({}),
            "hf_set_spawn": _ok({}),
        }
    )
    async with Client(build_server(bridge)) as client:
        await client.call_tool(
            "hf_transform_brush", {"brush_id": "b", "rotation_degrees": [0, 90, 0]}
        )
        await client.call_tool(
            "hf_get_brushes", {"bounds": {"min": [0, 0, 0], "max": [1, 1, 1]}}
        )
        await client.call_tool("hf_set_spawn", {"position": [1, 0, 1]})
    transform, listing, spawn = (call["params"] for call in bridge.calls)
    assert "position" not in transform
    assert transform["rotation_degrees"] == [0.0, 90.0, 0.0]
    assert listing["bounds"] == {"min": [0.0, 0.0, 0.0], "max": [1.0, 1.0, 1.0]}
    assert "brush_ids" not in listing
    assert "yaw_degrees" not in spawn


async def test_a_screenshot_is_an_image_the_model_can_see():
    shot = {"mime_type": "image/png", "data": "iVBORw0KGgo="}
    answer = _ok({"image": shot, "width": 64, "height": 36})
    bridge = FakeBridge({"hf_viewport_screenshot": answer})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool(
            "hf_viewport_screenshot",
            {"width": 64, "height": 64, "focus": {"brush_ids": ["b1"]}},
        )
    assert result.is_error is False
    image = result.content[0]
    assert image.type == "image"
    assert image.data == "iVBORw0KGgo="
    assert image.mime_type == "image/png"
    assert "data" not in result.structured_content["result"]["image"]
    assert result.structured_content["result"]["width"] == 64
    assert bridge.calls[0]["params"]["focus"] == {"brush_ids": ["b1"]}


async def test_a_screenshot_refusal_has_no_image():
    bridge = FakeBridge({"hf_viewport_screenshot": _failed("screenshot_unavailable")})
    async with Client(build_server(bridge)) as client:
        result = await client.call_tool("hf_viewport_screenshot", {})
    assert result.is_error is False
    assert result.content[0].type == "text"
    assert result.structured_content["error"]["code"] == "screenshot_unavailable"


async def test_a_batch_carries_its_ops_and_refuses_an_unknown_tool():
    bridge = FakeBridge({"hf_batch": _ok({"results": []})})
    ops = [
        {
            "tool": "hf_place_brush",
            "params": {"size": [1, 1, 1], "position": [0, 0, 0]},
        },
        {
            "tool": "hf_transform_brush",
            "params": {"brush_id": "$0.brush_id", "position": [1, 0, 0]},
        },
    ]
    async with Client(build_server(bridge)) as client:
        good = await client.call_tool("hf_batch", {"ops": ops})
        bad = await client.call_tool(
            "hf_batch", {"ops": [{"tool": "hf_undo", "params": {}}]}
        )
    assert good.is_error is False
    assert bad.is_error is True
    assert bridge.calls[0]["params"]["ops"] == ops
    assert len(bridge.calls) == 1


async def test_a_batch_op_is_checked_like_the_tool_it_names():
    bridge = FakeBridge({"hf_batch": _ok({"results": []})})
    refused = [
        [{"tool": "hf_place_brush", "params": {"size": [1, 1], "position": [0, 0, 0]}}],
        [{"tool": "hf_place_brush", "params": {"size": [1, 1, 1]}}],
        [{"tool": "hf_resize_brush", "params": {"brush_id": "b", "size": [0, 1, 1]}}],
        [{"tool": "hf_delete_brush", "params": {"brush_id": "b", "bogus": 1}}],
        [{"tool": "hf_extrude_face", "params": {"brush_id": "b", "face": "+q"}}],
    ]
    async with Client(build_server(bridge)) as client:
        for ops in refused:
            result = await client.call_tool("hf_batch", {"ops": ops})
            assert result.is_error is True, ops
        good = await client.call_tool(
            "hf_batch",
            {
                "ops": [
                    {
                        "tool": "hf_extrude_face",
                        "params": {
                            "brush_id": "$0.brush_id",
                            "face": {"normal": [0, 1, 0]},
                            "distance": 2,
                        },
                    },
                    {"tool": "hf_set_spawn", "params": {"position": [0, 0, 0]}},
                ]
            },
        )
    assert good.is_error is False
    assert len(bridge.calls) == 1, "only the good batch reached the editor"
    sent = bridge.calls[0]["params"]["ops"]
    assert sent[0]["params"]["face"] == {"normal": [0.0, 1.0, 0.0]}
    assert "yaw_degrees" not in sent[1]["params"], "absent stays absent"


async def test_each_batch_op_takes_what_its_tool_takes():
    from hammerforge_mcp.server import BATCH_PARAMS

    async with Client(build_server(FakeBridge({}))) as client:
        listed = {tool.name: tool for tool in (await client.list_tools()).tools}
    for name, model in BATCH_PARAMS.items():
        alone = set(listed[name].input_schema["properties"]) - {"operation_id"}
        assert set(model.model_fields) == alone, name
        required = set(listed[name].input_schema.get("required", []))
        in_batch = {k for k, f in model.model_fields.items() if f.is_required()}
        assert in_batch == required, name
    # The editor's MUTATING list: the changes that go through the one wrapper.
    assert set(BATCH_PARAMS) == {
        "hf_place_brush",
        "hf_transform_brush",
        "hf_resize_brush",
        "hf_delete_brush",
        "hf_extrude_face",
        "hf_assign_material",
        "hf_set_spawn",
    }
