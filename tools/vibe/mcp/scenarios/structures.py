"""A structure changed and detached over the bridge, through the editor's own undo."""

DESCRIPTION = (
    "structures: stairs built, grown and turned plain by generator_id, each one "
    "step; a piece names its structure; undo and redo through the editor; a batch "
    "that builds and detaches by reference (#1302)"
)
START_SCENE = "level"
WINDOWED = False


async def _run(v, command, params):
    return await v.call("hf_run_command", {"command": command, "params": params})


async def _structure_of(v, brush_id):
    listed = await v.call(
        "hf_get_brushes", {"brush_ids": [brush_id], "include_faces": False}
    )
    if not listed.get("ok") or not listed["result"]["brushes"]:
        return "missing"
    return listed["result"]["brushes"][0].get("structure")


async def run(v):
    built = await _run(
        v,
        "create_arch",
        {
            "type": "stairs",
            "position": [0, 0, 0],
            "settings": {"steps": 4, "width": 3.0, "fill": "open"},
        },
    )
    if not v.expect(built.get("ok"), "stairs are built", built):
        return
    generator_id = built["result"]["generator_id"]
    first = built["result"]["made"][0]["brush_id"]
    structure = await _structure_of(v, first)
    v.expect(
        isinstance(structure, dict) and structure.get("generator_id") == generator_id,
        "a piece names its structure",
        structure,
    )

    grown = await _run(
        v, "update_structure", {"generator_id": generator_id, "settings": {"steps": 6}}
    )
    settings = grown.get("result", {}).get("settings", {})
    v.expect(
        grown.get("ok")
        and len(grown["result"]["made"]) == 6
        and settings.get("width") == 3.0
        and settings.get("fill") == 1,
        "an update grows the flight and keeps the settings it was not given",
        grown,
    )
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: update structure",
        "one step named for it",
        history,
    )

    # A person's Ctrl+Z takes the agent's update back like any other step.
    v.order("manager_undo")
    listed = await v.call("hf_get_brushes", {"include_faces": False})
    steps = [
        brush
        for brush in listed.get("result", {}).get("brushes", [])
        if (brush.get("structure") or {}).get("generator_id") == generator_id
    ]
    v.expect(len(steps) == 4, "a person's Ctrl+Z puts the four steps back", len(steps))

    # The settings it has, on steps nobody touched: nothing is rebuilt (#1368).
    same = await _run(v, "update_structure", {"generator_id": generator_id})
    kept = sorted(brush["brush_id"] for brush in steps)
    after = await v.call("hf_get_brushes", {"include_faces": False})
    now = sorted(
        brush["brush_id"]
        for brush in after.get("result", {}).get("brushes", [])
        if (brush.get("structure") or {}).get("generator_id") == generator_id
    )
    v.expect(
        same.get("ok")
        and same["result"].get("no_change") is True
        and not same["result"]["made"]
        and now == kept,
        "an update that changes nothing keeps every step and its id",
        same,
    )

    turned = await _run(
        v,
        "update_structure",
        {"generator_id": generator_id, "settings": {"rise": 0.25}},
    )
    v.expect(turned.get("ok"), "a second update names the same structure", turned)
    piece = turned.get("result", {}).get("made", [{}])[0].get("brush_id", "")

    detached = await _run(v, "detach_structure", {"generator_id": generator_id})
    v.expect(
        detached.get("ok") and len(detached["result"]["detached"]) == 4,
        "detach leaves the four steps as plain brushes",
        detached,
    )
    v.expect(await _structure_of(v, piece) is None, "a detached piece names none")

    undone = await v.call("hf_undo")
    v.expect(
        undone.get("ok") and undone["result"]["undone"] == "MCP: detach structure",
        "hf_undo takes back the detach",
        undone,
    )
    back = await _structure_of(v, piece)
    v.expect(
        isinstance(back, dict) and back.get("generator_id") == generator_id,
        "and the piece is a structure's again",
        back,
    )
    redone = await v.call("hf_redo")
    v.expect(redone.get("ok"), "hf_redo detaches it again", redone)
    v.expect(
        await _structure_of(v, piece) is None,
        "a redone detach leaves no structure on the piece",
    )

    again = await _run(v, "update_structure", {"generator_id": "no_such_structure"})
    v.expect(
        again.get("error", {}).get("code") == "invalid_argument",
        "an id that names no structure is refused",
        again,
    )

    batch = await v.call(
        "hf_batch",
        {
            "ops": [
                {
                    "tool": "hf_run_command",
                    "params": {
                        "command": "create_arch",
                        "params": {
                            "type": "stairs",
                            "position": [20, 0, 0],
                            "settings": {"steps": 3},
                        },
                    },
                },
                {
                    "tool": "hf_run_command",
                    "params": {
                        "command": "detach_structure",
                        "params": {"generator_id": "$0.generator_id"},
                    },
                },
            ]
        },
    )
    v.expect(
        batch.get("ok")
        and len(batch["result"]["results"][1]["result"]["detached"]) == 3,
        "a batch builds stairs and detaches them by reference",
        batch,
    )
    status = await v.call("hf_get_status")
    v.note("status after", status.get("result", {}).get("counts"))
