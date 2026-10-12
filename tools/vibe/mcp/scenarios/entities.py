"""Entities an agent placed steps ago: move, retune, wire, unwire and delete
(#1082, #1083, #1096), a brush made a trigger that lights the lamp (#1098), and
a two leaf door tied in one call, given a speed, and the trigger untied (#1105)."""

DESCRIPTION = (
    "a named brush, then a lamp and a timer moved, retuned, wired, deleted; "
    "a trigger wired to the lamp and unwired; a two leaf door given a speed; "
    "the trigger untied"
)
START_SCENE = "level"
WINDOWED = False


async def run(v):
    status = await v.call("hf_get_status")
    v.expect(status.get("ok"), "attached", status)

    gate = await v.call(
        "hf_place_brush", {"size": [4, 4, 1], "position": [0, 2, 0], "name": "Gate"}
    )
    v.expect(
        gate.get("ok") and gate["result"]["brush"]["name"] == "Gate",
        "a brush placed with a name has it (#1086)",
        gate,
    )

    placed = await v.call(
        "hf_batch",
        {
            "ops": [
                {
                    "tool": "hf_place_entity",
                    "params": {
                        "entity_class": "logic_timer",
                        "position": [0, 1, 0],
                        "name": "tick",
                    },
                },
                {
                    "tool": "hf_place_entity",
                    "params": {
                        "entity_class": "light_point",
                        "position": [0, 3, 0],
                        "name": "lamp_1",
                    },
                },
                {
                    "tool": "hf_add_entity_output",
                    "params": {
                        "entity": "$0.entity",
                        "output_name": "OnTimer",
                        "target_name": "lamp_1",
                        "input_name": "Toggle",
                    },
                },
            ]
        },
    )
    v.expect(placed.get("ok"), "a timer and a lamp, wired, in one batch", placed)
    results = placed.get("result", {}).get("results", [])
    tick = results[0]["result"]["entity"]["entity"] if results else ""
    lamp = results[1]["result"]["entity"]["entity"] if len(results) > 1 else ""

    # Something else in between, so hf_undo can no longer take the lamp back.
    await v.call("hf_place_brush", {"size": [8, 1, 8], "position": [0, -0.5, 0]})

    moved = await v.call("hf_transform_entity", {"entity": lamp, "position": [3, 3, 0]})
    v.expect(
        moved.get("ok") and moved["result"]["entity"]["position"] == [3.0, 3.0, 0.0],
        "the lamp moves two steps later",
        moved,
    )
    brighter = await v.call(
        "hf_set_entity_properties", {"entity": lamp, "properties": {"energy": 3}}
    )
    v.expect(
        brighter.get("ok")
        and brighter["result"]["entity"]["properties"]["energy"] == 3.0,
        "and is retuned",
        brighter,
    )
    wrong = await v.call(
        "hf_set_entity_properties", {"entity": lamp, "properties": {"glow": 1}}
    )
    v.expect(
        wrong.get("error", {}).get("code") == "invalid_argument",
        "a property a light does not have is refused",
        wrong,
    )

    listed = await v.call("hf_get_entities")
    wires = {
        e["name"]: e["outputs"] for e in listed.get("result", {}).get("entities", [])
    }
    v.expect(
        len(wires.get("tick", [])) == 1 and wires["tick"][0]["target_name"] == "lamp_1",
        "hf_get_entities lists the timer's wire",
        wires,
    )

    deleted = await v.call("hf_delete_entity", {"entity": lamp})
    v.expect(deleted.get("ok"), "the lamp is deleted", deleted)
    after = await v.call("hf_get_entities")
    wires = {
        e["name"]: e["outputs"] for e in after.get("result", {}).get("entities", [])
    }
    v.expect(
        "lamp_1" not in wires and wires.get("tick") == [],
        "with the wire aimed at it",
        wires,
    )
    undone = await v.call("hf_undo")
    v.expect(undone.get("ok"), "hf_undo takes the delete back", undone)
    back = await v.call("hf_get_entities")
    paths = [e["entity"] for e in back.get("result", {}).get("entities", [])]
    v.expect(lamp in paths, "the lamp is back at its path", paths)
    v.note("timer", tick)

    gate_id = gate["result"]["brush"]["brush_id"] if gate.get("ok") else ""
    trigger = await v.call(
        "hf_set_brush_entity",
        {
            "brush_ids": [gate_id],
            "entity_class": "trigger_once",
            "name": "hall_trigger",
        },
    )
    v.expect(
        trigger.get("ok")
        and trigger["result"]["brushes"][0]["brush_entity"]["name"] == "hall_trigger",
        "a brush is made a trigger_once (#1098)",
        trigger,
    )
    lit = await v.call(
        "hf_add_entity_output",
        {
            "brush_id": gate_id,
            "output_name": "OnStartTouch",
            "target_name": "lamp_1",
            "input_name": "TurnOn",
        },
    )
    v.expect(lit.get("ok"), "and its OnStartTouch wired to the lamp", lit)
    wrong_class = await v.call(
        "hf_set_brush_entity", {"brush_ids": [gate_id], "entity_class": "light_point"}
    )
    v.expect(
        wrong_class.get("error", {}).get("code") == "invalid_argument"
        and "func_door" in wrong_class["error"]["message"],
        "a point class is refused with the brush classes",
        wrong_class,
    )
    listed = await v.call("hf_get_brushes", {"brush_ids": [gate_id]})
    brush = listed.get("result", {}).get("brushes", [{}])[0]
    v.expect(
        (brush.get("brush_entity") or {}).get("outputs", [{}])[0].get("input_name")
        == "TurnOn",
        "hf_get_brushes lists the trigger's wire",
        brush.get("brush_entity"),
    )

    unwired = await v.call("hf_remove_entity_output", {"entity": tick, "index": 0})
    v.expect(
        unwired.get("ok") and unwired["result"]["entity"]["outputs"] == [],
        "the timer's wire, several steps old, is taken back (#1096)",
        unwired,
    )
    past = await v.call("hf_remove_entity_output", {"entity": tick, "index": 0})
    v.expect(
        past.get("error", {}).get("code") == "invalid_argument",
        "an index it no longer has is refused",
        past,
    )

    leaves = await v.call(
        "hf_batch",
        {
            "ops": [
                {
                    "tool": "hf_place_brush",
                    "params": {"size": [2, 3, 0.25], "position": [5, 1.5, 0]},
                },
                {
                    "tool": "hf_place_brush",
                    "params": {"size": [2, 3, 0.25], "position": [7, 1.5, 0]},
                },
                {
                    "tool": "hf_set_brush_entity",
                    "params": {
                        "brush_ids": ["$0.brush_id", "$1.brush_id"],
                        "entity_class": "func_door",
                        "name": "gate",
                    },
                },
            ]
        },
    )
    results = leaves.get("result", {}).get("results", [])
    door = results[2]["result"]["brushes"] if len(results) > 2 else []
    v.expect(
        leaves.get("ok")
        and [b["brush_entity"]["name"] for b in door] == ["gate", "gate"],
        "two leaves tied as one door in one call (#1105)",
        leaves,
    )
    leaf_ids = [b["brush_id"] for b in door]
    faster = await v.call(
        "hf_set_entity_properties",
        {"brush_id": leaf_ids[-1] if leaf_ids else "", "properties": {"speed": 5}},
    )
    v.expect(
        faster.get("ok")
        and faster["result"]["brush"]["brush_entity"]["properties"]["speed"] == 5.0,
        "the door is given a speed by one leaf's brush_id",
        faster,
    )
    listed = await v.call(
        "hf_get_brushes", {"brush_ids": leaf_ids, "include_faces": False}
    )
    speeds = [
        (b.get("brush_entity") or {}).get("properties", {}).get("speed")
        for b in listed.get("result", {}).get("brushes", [])
    ]
    v.expect(speeds == [5.0, 5.0], "and both leaves have it", speeds)
    undeclared = await v.call(
        "hf_set_entity_properties",
        {"brush_id": gate_id, "properties": {"start_disabled": True}},
    )
    v.expect(
        undeclared.get("error", {}).get("code") == "invalid_argument",
        "a property the trigger does not declare is refused",
        undeclared,
    )

    untied = await v.call(
        "hf_set_brush_entity", {"brush_ids": [gate_id], "entity_class": "none"}
    )
    v.expect(untied.get("ok"), "the trigger, tied steps ago, is untied", untied)
    plain = await v.call(
        "hf_get_brushes", {"brush_ids": [gate_id], "include_faces": False}
    )
    brushes = plain.get("result", {}).get("brushes", [{}])
    v.expect(
        plain.get("ok") and brushes[0].get("brush_entity", "missing") is None,
        "and hf_get_brushes lists it as plain",
        plain,
    )
