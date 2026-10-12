import json
import re

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


async def test_place_passes_material_rotation_and_sides_when_given():
    # Each one cost an op per brush on top of the place (#1039).
    bridge = FakeBridge({"hf_place_brush": _ok({})})
    async with Client(build_server(bridge)) as client:
        await client.call_tool(
            "hf_place_brush",
            {
                "size": [2, 4, 2],
                "position": [0, 2, 0],
                "shape": "cylinder",
                "material": "brick",
                "rotation_degrees": [0, 90, 0],
                "sides": 8,
            },
        )
        too_many = await client.call_tool(
            "hf_place_brush",
            {"size": [2, 4, 2], "position": [0, 2, 0], "sides": 65},
        )
    params = bridge.calls[0]["params"]
    assert params["material"] == "brick"
    assert params["rotation_degrees"] == [0.0, 90.0, 0.0]
    assert params["sides"] == 8
    assert too_many.is_error is True, "65 sides never reaches the editor"
    assert len(bridge.calls) == 1


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
    "hf_place_entity": {"entity_class": "light_point", "position": [0, 0, 0]},
    "hf_get_entities": {},
    "hf_transform_entity": {"entity": "Entities/lamp", "position": [0, 0, 0]},
    "hf_set_entity_properties": {"entity": "Entities/lamp", "properties": {}},
    "hf_delete_entity": {"entity": "Entities/lamp"},
    "hf_add_entity_output": {
        "entity": "Entities/tick",
        "output_name": "OnTimer",
        "target_name": "lamp",
        "input_name": "Toggle",
    },
    "hf_remove_entity_output": {"entity": "Entities/tick", "index": 0},
    "hf_set_brush_entity": {"brush_ids": ["b"], "entity_class": "trigger_once"},
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
        "hf_place_entity",
        "hf_transform_entity",
        "hf_set_entity_properties",
        "hf_delete_entity",
        "hf_add_entity_output",
        "hf_remove_entity_output",
        "hf_set_brush_entity",
    }


def _ops_from_text(text: str) -> list[dict]:
    """The batch a literal agent builds from the room prompt's op lines."""
    ops = []
    for line in text.splitlines():
        found = re.match(r"\s+- [^:]+: (hf_\w+)(.*)$", line)
        if not found:
            continue
        tool, rest = found.groups()
        params: dict = {}
        operation = re.search(r"operation (\w+)", rest)
        if operation:
            params["operation"] = operation.group(1)
        for key, vec in re.findall(r"(size|position) (\[[^\]]+\])", rest):
            params[key] = json.loads(vec)
        if "snap false" in rest:
            params["snap"] = False
        ops.append({"tool": tool, "params": params})
    return ops


def _box(op: dict) -> tuple[list[float], list[float]]:
    size, centre = op["params"]["size"], op["params"]["position"]
    return (
        [c - s / 2 for c, s in zip(centre, size, strict=True)],
        [c + s / 2 for c, s in zip(centre, size, strict=True)],
    )


async def test_the_example_prompts_are_listed_and_named_tools_exist():
    async with Client(build_server(FakeBridge({}))) as client:
        listed = [p.name for p in (await client.list_prompts()).prompts]
        texts = {}
        for name in listed:
            got = await client.get_prompt(name, {})
            texts[name] = got.messages[0].content.text
    assert listed == ["block_out_room", "review_level", "bake_for_playtest"]
    assert "16 m wide" in texts["block_out_room"]
    for name, body in texts.items():
        named = set(re.findall(r"\bhf_[a-z_]+", body))
        assert named, name
        assert named <= set(TOOLS), f"{name} names {named - set(TOOLS)}"


async def test_the_room_prompt_says_exactly_the_batch_the_editor_takes():
    from hammerforge_mcp.prompts import room_bounds, room_ops

    bridge = FakeBridge({"hf_batch": _ok({"results": []})})
    async with Client(build_server(bridge)) as client:
        got = await client.get_prompt(
            "block_out_room", {"width": "10", "depth": "8", "height": "3"}
        )
        text = got.messages[0].content.text
        # Read back the way an agent reads it, and sent through the real schema.
        literal = _ops_from_text(text)
        sent = await client.call_tool("hf_batch", {"ops": literal})
    ops = [op for _, op in room_ops(10, 8, 3)]
    assert literal == ops, "the text says exactly the ops"
    assert sent.is_error is False, sent.content[0].text
    assert bridge.calls[0]["params"]["ops"] == ops

    labelled = dict(room_ops(10, 8, 3))
    floor, ceiling = _box(labelled["floor"]), _box(labelled["ceiling"])
    # On the ground, not in it: the starter floor's top is at 0, and a room floor
    # whose top was there too z-fought with it over the whole room (#1052).
    t = floor[1][1] - floor[0][1]
    assert floor[0][1] == 0, "the floor stands on y = 0"
    assert ceiling[0][1] == t + 3, (
        "the ceiling's underside is the height above the floor"
    )
    for side, axis, inner in (("-z", 2, -4), ("+z", 2, 4), ("-x", 0, -5), ("+x", 0, 5)):
        low, high = _box(labelled[f"wall {side}"])
        face = high[axis] if inner < 0 else low[axis]
        assert face == inner, f"wall {side} stands on the room's edge"
        assert (low[1], high[1]) == (t, t + 3), f"wall {side} spans floor to ceiling"
    # The x walls fit between the z walls; the z walls cover the corners.
    assert _box(labelled["wall -x"])[1][2] == _box(labelled["wall +z"])[0][2]
    assert _box(labelled["wall -z"])[0][0] == _box(labelled["wall -x"])[0][0]
    door_low, door_high = _box(labelled["doorway"])
    wall_low, wall_high = _box(labelled["wall -z"])
    assert labelled["doorway"]["params"]["operation"] == "subtract"
    assert door_low[2] < wall_low[2] and door_high[2] > wall_high[2], "through the wall"
    assert door_low[1] == t and door_high[1] < t + 3, (
        "from the floor, under the ceiling"
    )
    assert "snap" not in labelled["spawn"]["params"], "set spawn takes no snap"
    assert labelled["spawn"]["params"]["position"] == [0, t, 0], "on the room's floor"
    # The framing holds the room's solid brushes; the doorway's cutter reaches past
    # the wall on purpose, so it cuts clean through.
    bounds = room_bounds(10, 8, 3)
    solids = ("floor", "ceiling", "wall -z", "wall +z", "wall -x", "wall +x")
    for label in solids:
        low, high = _box(labelled[label])
        assert all(b <= v for b, v in zip(bounds["min"], low, strict=True))
        assert all(v <= b for b, v in zip(bounds["max"], high, strict=True))


async def test_a_room_the_doorway_does_not_fit_is_refused_in_words():
    from mcp.shared.exceptions import MCPError

    cases = {"height": "2", "width": "0.5", "depth": "-4"}
    async with Client(build_server(FakeBridge({}))) as client:
        for name, value in [*cases.items(), ("width", "wide"), ("depth", "nan")]:
            with pytest.raises(MCPError) as caught:
                await client.get_prompt("block_out_room", {name: value})
            assert name in str(caught.value) and "metres" in str(caught.value)


async def test_place_entity_reaches_the_editor_alone_and_in_a_batch():
    bridge = FakeBridge({"hf_place_entity": _ok({}), "hf_batch": _ok({"results": []})})
    op = {
        "entity_class": "light_spot",
        "position": [0, 3, 0],
        "properties": {"energy": 2},
    }
    async with Client(build_server(bridge)) as client:
        alone = await client.call_tool("hf_place_entity", op)
        batched = await client.call_tool(
            "hf_batch", {"ops": [{"tool": "hf_place_entity", "params": op}]}
        )
    assert alone.is_error is False, alone.content[0].text
    assert batched.is_error is False, batched.content[0].text
    assert bridge.calls[0]["params"]["entity_class"] == "light_spot"
    assert bridge.calls[0]["params"]["properties"] == {"energy": 2}
    sent = bridge.calls[1]["params"]["ops"][0]["params"]
    assert sent["entity_class"] == "light_spot"


async def test_a_screenshot_takes_a_view_a_camera_and_what_to_leave_out():
    # Focus shots always looked the way the editor's camera did, so the inside of
    # a closed room or the far side of a wall could not be seen (#1040).
    bridge = FakeBridge({"hf_viewport_screenshot": _ok({})})
    box = {"min": [0, 0, 0], "max": [4, 3, 4]}
    async with Client(build_server(bridge)) as client:
        await client.call_tool(
            "hf_viewport_screenshot",
            {"focus": {"bounds": box, "look_from": "top"}, "hide": ["b1"]},
        )
        await client.call_tool(
            "hf_viewport_screenshot",
            {"focus": {"brush_ids": ["b1"], "look_from": [1, 2, 3]}},
        )
        await client.call_tool(
            "hf_viewport_screenshot",
            {
                "camera": {"position": [2, 1.8, 2], "look_at": [2, 1.8, 0]},
                "hide_cuts": True,
            },
        )
        sideways = await client.call_tool(
            "hf_viewport_screenshot",
            {"focus": {"bounds": box, "look_from": "sideways"}},
        )
    first, second, third = (call["params"] for call in bridge.calls)
    assert first["focus"]["look_from"] == "top"
    assert first["hide"] == ["b1"]
    assert second["focus"]["look_from"] == [1.0, 2.0, 3.0]
    assert third["camera"] == {"position": [2.0, 1.8, 2.0], "look_at": [2.0, 1.8, 0.0]}
    assert third["hide_cuts"] is True
    assert "look_from" not in third, "absent stays absent"
    assert sideways.is_error is True, "a side that is not one never reaches the editor"


async def test_entity_edits_reach_the_editor_alone_and_in_a_batch():
    # An entity could only be taken back with hf_undo, and only while it was the
    # agent's last step (#1082). Wiring had no tool at all (#1083).
    edits = {
        "hf_transform_entity": {"entity": "Entities/lamp", "position": [1, 2, 3]},
        "hf_set_entity_properties": {
            "entity": "Entities/lamp",
            "properties": {"energy": 3},
        },
        "hf_delete_entity": {"entity": "Entities/lamp"},
        "hf_add_entity_output": {
            "entity": "$0.entity",
            "output_name": "OnTimer",
            "target_name": "lamp_1",
            "input_name": "Toggle",
            "delay": 0.5,
        },
    }
    bridge = FakeBridge({name: _ok({}) for name in [*edits, "hf_batch"]})
    async with Client(build_server(bridge)) as client:
        for name, args in edits.items():
            result = await client.call_tool(name, args)
            assert result.is_error is False, (name, result.content[0].text)
        batched = await client.call_tool(
            "hf_batch",
            {"ops": [{"tool": name, "params": args} for name, args in edits.items()]},
        )
        backwards = await client.call_tool(
            "hf_add_entity_output", {**edits["hf_add_entity_output"], "delay": -1}
        )
    assert batched.is_error is False, batched.content[0].text
    assert backwards.is_error is True, "a negative delay never reaches the editor"
    wire = bridge.calls[3]["params"]
    assert wire == {
        "entity": "$0.entity",
        "output_name": "OnTimer",
        "target_name": "lamp_1",
        "input_name": "Toggle",
        "parameter": "",
        "delay": 0.5,
        "fire_once": False,
    }
    ops = bridge.calls[4]["params"]["ops"]
    assert [op["tool"] for op in ops] == list(edits)
    assert ops[0]["params"] == {"entity": "Entities/lamp", "position": [1.0, 2.0, 3.0]}


async def test_place_brush_passes_a_name_alone_and_in_a_batch():
    # Every brush was Box_12 or Wedge_3, so nobody could tell the gate from the
    # parapet (#1086).
    bridge = FakeBridge({"hf_place_brush": _ok({}), "hf_batch": _ok({"results": []})})
    op = {"size": [4, 4, 1], "position": [0, 2, 0], "name": "Gate"}
    async with Client(build_server(bridge)) as client:
        await client.call_tool("hf_place_brush", op)
        await client.call_tool(
            "hf_batch", {"ops": [{"tool": "hf_place_brush", "params": op}]}
        )
        blank = await client.call_tool("hf_place_brush", {**op, "name": ""})
    assert bridge.calls[0]["params"]["name"] == "Gate"
    assert bridge.calls[1]["params"]["ops"][0]["params"]["name"] == "Gate"
    assert blank.is_error is True, "an empty name never reaches the editor"


async def test_a_screenshot_can_show_the_bake():
    # Every shot drew the brushes, so a bake's result could not be looked at (#1084).
    bridge = FakeBridge({"hf_viewport_screenshot": _ok({})})
    box = {"min": [0, 0, 0], "max": [4, 3, 4]}
    async with Client(build_server(bridge)) as client:
        await client.call_tool(
            "hf_viewport_screenshot", {"focus": {"bounds": box}, "show": "baked"}
        )
        await client.call_tool("hf_viewport_screenshot", {"focus": {"bounds": box}})
        wrong = await client.call_tool(
            "hf_viewport_screenshot", {"focus": {"bounds": box}, "show": "both"}
        )
    assert bridge.calls[0]["params"]["show"] == "baked"
    assert "show" not in bridge.calls[1]["params"], "the default stays unsaid"
    assert wrong.is_error is True


async def test_brush_entities_and_unwiring_reach_the_editor_alone_and_in_a_batch():
    # An agent could not make a trigger, a door or a button (#1098), or take a
    # wire back once it was not its last step (#1096).
    edits = {
        "hf_set_brush_entity": {
            "brush_ids": ["$0.brush_id"],
            "entity_class": "trigger_once",
            "name": "hall_trigger",
        },
        "hf_add_entity_output": {
            "brush_id": "$1.brush_id",
            "output_name": "OnStartTouch",
            "target_name": "lamp_1",
            "input_name": "TurnOn",
        },
        "hf_remove_entity_output": {"brush_id": "$1.brush_id", "index": 0},
    }
    bridge = FakeBridge({name: _ok({}) for name in [*edits, "hf_batch"]})
    async with Client(build_server(bridge)) as client:
        for name, args in edits.items():
            result = await client.call_tool(name, args)
            assert result.is_error is False, (name, result.content[0].text)
        batched = await client.call_tool(
            "hf_batch",
            {"ops": [{"tool": name, "params": args} for name, args in edits.items()]},
        )
        backwards = await client.call_tool(
            "hf_remove_entity_output", {"entity": "Entities/tick", "index": -1}
        )
        unnamed = await client.call_tool(
            "hf_set_brush_entity",
            {"brush_ids": ["b"], "entity_class": "func_door", "name": ""},
        )
    assert batched.is_error is False, batched.content[0].text
    assert backwards.is_error is True, "a negative index never reaches the editor"
    assert unnamed.is_error is True, "a blank name never reaches the editor"
    assert bridge.calls[0]["params"] == edits["hf_set_brush_entity"]
    wire = bridge.calls[1]["params"]
    assert "entity" not in wire, "a source left out stays out, for the editor to check"
    assert wire["brush_id"] == "$1.brush_id"
    assert bridge.calls[2]["params"] == {"brush_id": "$1.brush_id", "index": 0}
    ops = bridge.calls[3]["params"]["ops"]
    assert [op["tool"] for op in ops] == list(edits)


async def test_ties_unties_and_brush_entity_properties_reach_the_editor():
    # An agent could tie one brush at a time and never untie one, and could not
    # set a brush entity's own properties (#1105).
    edits = {
        "hf_set_brush_entity": {
            "brush_ids": ["b1", "b2"],
            "entity_class": "func_door",
            "name": "gate",
        },
        "hf_set_entity_properties": {"brush_id": "b1", "properties": {"speed": 5}},
    }
    untie = {"brush_ids": ["b1"], "entity_class": "none"}
    bridge = FakeBridge({name: _ok({}) for name in [*edits, "hf_batch"]})
    async with Client(build_server(bridge)) as client:
        for name, args in edits.items():
            result = await client.call_tool(name, args)
            assert result.is_error is False, (name, result.content[0].text)
        untied = await client.call_tool("hf_set_brush_entity", untie)
        batched = await client.call_tool(
            "hf_batch",
            {"ops": [{"tool": name, "params": args} for name, args in edits.items()]},
        )
        # The editor refuses a repeat by name, and neither source or both.
        twice = await client.call_tool(
            "hf_set_brush_entity", {"brush_ids": ["b1", "b1"], "entity_class": "none"}
        )
        neither = await client.call_tool(
            "hf_set_entity_properties", {"properties": {"speed": 5}}
        )
        refused = [
            await client.call_tool(
                "hf_set_brush_entity", {"brush_ids": [], "entity_class": "func_door"}
            ),
            await client.call_tool(
                "hf_set_brush_entity", {"brush_ids": [""], "entity_class": "func_door"}
            ),
            await client.call_tool(
                "hf_set_brush_entity", {"brush_id": "b1", "entity_class": "func_door"}
            ),
            await client.call_tool(
                "hf_set_brush_entity", {"brush_ids": "b1", "entity_class": "func_door"}
            ),
            await client.call_tool(
                "hf_batch",
                {
                    "ops": [
                        {
                            "tool": "hf_set_brush_entity",
                            "params": {"brush_ids": [], "entity_class": "none"},
                        }
                    ]
                },
            ),
        ]
    assert untied.is_error is False, untied.content[0].text
    assert batched.is_error is False, batched.content[0].text
    assert twice.is_error is False and neither.is_error is False
    assert [result.is_error for result in refused] == [True] * len(refused)
    assert len(bridge.calls) == 6, "no refused call reached the editor"
    assert bridge.calls[0]["params"] == edits["hf_set_brush_entity"]
    assert bridge.calls[1]["params"] == edits["hf_set_entity_properties"]
    assert bridge.calls[2]["params"] == untie, "no name for an untie"
    ops = bridge.calls[3]["params"]["ops"]
    assert [op["params"] for op in ops] == list(edits.values())
    assert bridge.calls[5]["params"] == {"properties": {"speed": 5}}
