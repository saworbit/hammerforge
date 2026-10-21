"""Floor paint over the bridge, by cell, through the editor's own undo (#1299)."""

DESCRIPTION = (
    "floor paint: the layers listed, a rectangle painted and erased, its walls "
    "raised, a room stamped, a connector confirmed between two layers, each one "
    "step; a person's Ctrl+Z taking the raise back; hf_undo and hf_redo; "
    "refusals that change nothing"
)
START_SCENE = "level"
WINDOWED = False


async def _run(v, command, params):
    return await v.call("hf_run_command", {"command": command, "params": params})


async def _layers(v):
    listed = await v.call("hf_list_commands")
    for entry in listed.get("result", {}).get("commands", []):
        if entry["command"] == "paint_ramp":
            return entry.get("paint_layers")
    return None


async def run(v):
    layers = await _layers(v)
    v.expect(
        isinstance(layers, list) and len(layers) == 1 and layers[0]["index"] == 0,
        "the listing names the level's one paint layer",
        layers,
    )

    painted = await _run(v, "paint_ramp", {"from": [0, 0], "to": [5, 3]})
    result = painted.get("result", {})
    v.expect(
        painted.get("ok")
        and result.get("cells") == 24
        and result.get("cells_changed") == 24,
        "a rectangle of 24 cells is painted",
        painted,
    )
    v.note("bounds", result.get("bounds"))
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: ramp / rect", "one step named for it", history
    )
    layers = await _layers(v)
    v.expect(
        isinstance(layers, list) and layers[0].get("cells") == 24,
        "the listing counts the painted cells",
        layers,
    )

    erased = await _run(v, "paint_ramp", {"from": [5, 3], "filled": False})
    v.expect(
        erased.get("ok") and erased["result"].get("cells_changed") == 1,
        "one cell erased when to is absent",
        erased,
    )

    raised = await _run(v, "paint_raise", {"from": [0, 0], "to": [2, 3], "height": 4.0})
    v.expect(
        raised.get("ok")
        and raised["result"].get("raised") == 12
        and raised["result"].get("heights_changed") == 12,
        "the walls round twelve cells are raised to 4 m",
        raised,
    )

    # A person's Ctrl+Z takes the agent's raise back like any other step.
    v.order("manager_undo")
    again = await _run(v, "paint_raise", {"from": [0, 0], "to": [2, 3], "height": 3.0})
    v.expect(
        again.get("ok") and again["result"].get("heights_changed") == 12,
        "after Ctrl+Z, setting 3 m pins twelve cells to the default height",
        again,
    )
    unchanged = await _run(
        v, "paint_raise", {"from": [0, 0], "to": [2, 3], "height": 3.0}
    )
    v.expect(
        unchanged.get("ok")
        and unchanged["result"].get("heights_changed") == 0
        and unchanged["result"].get("no_change")
        and unchanged.get("revision") == again.get("revision"),
        "the same pinned height again changes nothing and records no step",
        unchanged,
    )

    room = await _run(
        v, "paint_room", {"at": [10, 0], "width": 3, "depth": 2, "height": 2.5}
    )
    v.expect(
        room.get("ok")
        and room["result"].get("cells") == 6
        and room["result"].get("raised") == 6
        and room["result"].get("to") == [12, 1],
        "a room is stamped and raised in one step",
        room,
    )
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: stamp painted room",
        "named for the room",
        history,
    )

    undone = await v.call("hf_undo")
    v.expect(
        undone.get("ok") and undone["result"]["undone"] == "MCP: stamp painted room",
        "hf_undo takes the room back",
        undone,
    )
    redone = await v.call("hf_redo")
    v.expect(redone.get("ok"), "hf_redo stamps it again", redone)

    nothing = await _run(v, "paint_raise", {"from": [40, 40], "height": 2.0})
    v.expect(
        nothing.get("error", {}).get("code") == "operation_failed",
        "a raise over nothing painted is refused",
        nothing,
    )
    missing = await _run(v, "paint_ramp", {"from": [0, 0], "layer": "nope"})
    v.expect(
        missing.get("error", {}).get("code") == "invalid_argument"
        and missing["error"].get("details", {}).get("param") == "params.layer",
        "a layer the level does not have is refused by name",
        missing,
    )

    # A second layer, painted beside the first, and the connector between them.
    v.order("add_paint_layer", layer_y=3.0)
    layers = await _layers(v)
    v.expect(
        isinstance(layers, list) and len(layers) == 2,
        "the listing shows the layer the person added",
        layers,
    )
    if not (isinstance(layers, list) and len(layers) == 2):
        return
    upper = layers[1]["name"]
    beside = await _run(v, "paint_ramp", {"layer": upper, "from": [6, 0], "to": [7, 3]})
    v.expect(beside.get("ok"), f"a floor painted on {upper} by name", beside)
    joined = await _run(
        v, "paint_confirm_connector", {"layer": 0, "from": [5, 0], "to": [5, 2]}
    )
    connectors = joined.get("result", {}).get("connectors", [])
    v.expect(
        joined.get("ok")
        and len(connectors) == 1
        and connectors[0]["from_layer"] == 0
        and connectors[0]["to_layer"] == 1,
        "one connector is confirmed along the shared edge",
        joined,
    )
    twice = await _run(
        v, "paint_confirm_connector", {"layer": 0, "from": [5, 0], "to": [5, 2]}
    )
    v.expect(
        twice.get("error", {}).get("code") == "operation_failed",
        "confirming it again is refused",
        twice,
    )
    undone = await v.call("hf_undo")
    v.expect(
        undone.get("ok")
        and undone["result"]["undone"] == "MCP: confirm paint connector",
        "hf_undo takes the connector back",
        undone,
    )
    status = await v.call("hf_get_status")
    v.note("status after", status.get("result", {}).get("counts"))
