"""Palette commands over the bridge: hollow, clip, carve, merge, a structure, undo."""

DESCRIPTION = (
    "palette commands: list, hollow, clip, carve, merge, stairs, each one step; "
    "one that changes nothing makes no step (#1365); "
    "a person's Ctrl+Z ends the agent's undo chain"
)
START_SCENE = "level"
WINDOWED = False


async def _box(v, position, size):
    placed = await v.call("hf_place_brush", {"size": size, "position": position})
    v.expect(placed.get("ok"), f"place a box at {position}", placed)
    return placed["result"]["brush"]["brush_id"]


async def _run(v, command, brush_ids=None, params=None):
    args = {"command": command}
    if brush_ids is not None:
        args["brush_ids"] = brush_ids
    if params is not None:
        args["params"] = params
    return await v.call("hf_run_command", args)


async def run(v):
    listed = await v.call("hf_list_commands")
    v.expect(listed.get("ok"), "the editor lists its palette commands", listed)
    ids = [entry["command"] for entry in listed["result"]["commands"]]
    for command in ("hollow", "clip", "carve", "merge", "create_arch"):
        v.expect(command in ids, f"{command} is on the bridge", ids)
    v.note("commands", ids)

    room = await _box(v, [0, 2, 0], [6, 4, 6])
    hollowed = await _run(v, "hollow", [room], {"thickness": 0.5})
    v.expect(
        hollowed.get("ok") and len(hollowed["result"]["made"]) == 6,
        "hollow shells the room into six walls",
        hollowed,
    )
    history = v.order("history")
    v.expect(history["current_name"] == "MCP: hollow", "one step named for it", history)

    block = await _box(v, [20, 2, 0], [4, 4, 4])
    clipped = await _run(v, "clip", [block], {"axis": "x"})
    v.expect(
        clipped.get("ok") and len(clipped["result"]["made"]) == 2,
        "clip splits a block in two",
        clipped,
    )

    target = await _box(v, [40, 2, 0], [4, 4, 4])
    carver = await _box(v, [42, 2, 0], [2, 2, 2])
    carved = await _run(v, "carve", [carver])
    v.expect(
        carved.get("ok") and target in carved["result"]["removed"],
        "carve cuts the block the carver overlaps",
        carved,
    )

    left = await _box(v, [60, 2, 0], [4, 4, 4])
    right = await _box(v, [64, 2, 0], [4, 4, 4])
    merged = await _run(v, "merge", [left, right])
    v.expect(
        merged.get("ok") and "brush" in merged["result"],
        "merge makes one brush of two",
        merged,
    )

    stairs = await _run(
        v,
        "create_arch",
        None,
        {"type": "stairs", "position": [80, 0, 0], "settings": {"steps": 5}},
    )
    v.expect(
        stairs.get("ok") and len(stairs["result"]["made"]) == 5,
        "stairs build one brush per step",
        stairs,
    )

    # A command with nothing to do: no step, the revision where it was, and the
    # agent's undo chain still ends at the stairs (#1365).
    square = await _run(v, "reset_rotation", [merged["result"]["brush"]["brush_id"]])
    v.expect(
        square.get("ok")
        and square["result"].get("no_change") is True
        and square["result"]["changed"] == []
        and square.get("revision") == stairs.get("revision"),
        "reset rotation on a square brush says it changed nothing and keeps the revision",
        square,
    )
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: create structure",
        "and records no step",
        history,
    )

    missing = await _run(v, "merge", [left, "no_such_brush"])
    v.expect(
        missing.get("error", {}).get("code") == "brush_not_found",
        "a brush that is not there refuses the command",
        missing,
    )

    undone = await v.call("hf_undo")
    v.expect(
        undone.get("ok") and undone["result"]["undone"] == "MCP: create structure",
        "hf_undo takes back the stairs",
        undone,
    )
    again = await v.call("hf_undo")
    v.expect(
        again.get("ok") and again["result"]["undone"] == "MCP: merge brushes",
        "and then the merge",
        again,
    )

    # A person's Ctrl+Z between two agent steps ends the agent's undo chain.
    v.order("manager_undo")
    refused = await v.call("hf_undo")
    v.expect(
        refused.get("error", {}).get("code") == "undo_conflict",
        "hf_undo refuses after a person's Ctrl+Z",
        refused,
    )
