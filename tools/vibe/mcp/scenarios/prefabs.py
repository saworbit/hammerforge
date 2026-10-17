"""A prefab placed from the library over the bridge, through the editor's own undo."""

DESCRIPTION = (
    "prefabs: two boxes saved into a scratch library, listed, placed turned and "
    "placed linked, each one step; a piece names its copy; a person's Ctrl+Z and "
    "the agent's undo and redo take placements back (#1301)"
)
START_SCENE = "level"
WINDOWED = False


async def _box(v, position, size):
    placed = await v.call("hf_place_brush", {"size": size, "position": position})
    v.expect(placed.get("ok"), f"place a box at {position}", placed)
    return placed["result"]["brush"]["brush_id"]


async def _place(v, params):
    return await v.call("hf_run_command", {"command": "place_prefab", "params": params})


async def _count(v):
    listed = await v.call("hf_get_brushes", {"include_faces": False})
    return len(listed.get("result", {}).get("brushes", []))


async def run(v):
    big = await _box(v, [0, 2, 0], [4, 4, 4])
    small = await _box(v, [4, 1, 0], [2, 2, 2])
    saved = v.order("prefab_library", brush_ids=[big, small], name="vibe_crate")
    if not v.expect(
        str(saved).endswith("vibe_crate.hfprefab"), "a person saves a prefab", saved
    ):
        return

    listed = await v.call("hf_list_commands")
    entry = next(
        (
            command
            for command in listed.get("result", {}).get("commands", [])
            if command["command"] == "place_prefab"
        ),
        {},
    )
    library = entry.get("prefabs", [])
    v.expect(
        [item.get("name") for item in library] == ["vibe_crate"]
        and library[0].get("brushes") == 2,
        "the listing gives the library",
        library,
    )

    before = await _count(v)
    turned = await _place(
        v,
        {
            "prefab": "vibe_crate",
            "position": [30, 0, 0],
            "rotation_degrees": [0, 90, 0],
        },
    )
    v.expect(
        turned.get("ok") and len(turned["result"]["made"]) == 2,
        "a turned copy is placed",
        turned,
    )
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: place prefab", "one step named for it", history
    )
    if turned.get("ok"):
        piece = turned["result"]["made"][0]
        v.expect(
            (piece.get("prefab") or {}).get("instance_id")
            == turned["result"]["instance_id"],
            "a placed piece names its copy",
            piece,
        )

    # A person's Ctrl+Z takes the agent's placement back like any other step.
    v.order("manager_undo")
    v.expect(await _count(v) == before, "a person's Ctrl+Z takes the copy back")

    linked = await _place(
        v, {"prefab": "vibe_crate", "position": [0, 0, 30], "linked": True}
    )
    v.expect(
        linked.get("ok") and linked["result"]["linked"],
        "a linked copy is placed",
        linked,
    )
    undone = await v.call("hf_undo")
    v.expect(
        undone.get("ok") and undone["result"]["undone"] == "MCP: place prefab",
        "hf_undo takes the placement back",
        undone,
    )
    v.expect(await _count(v) == before, "and its pieces with it")
    redone = await v.call("hf_redo")
    v.expect(redone.get("ok"), "hf_redo puts it back", redone)
    v.expect(await _count(v) == before + 2, "both pieces")

    unknown = await _place(v, {"prefab": "barrel", "position": [0, 0, 0]})
    v.expect(
        unknown.get("error", {}).get("code") == "invalid_argument"
        and "vibe_crate" in unknown.get("error", {}).get("message", ""),
        "a name the library does not hold is refused, naming what it holds",
        unknown,
    )
