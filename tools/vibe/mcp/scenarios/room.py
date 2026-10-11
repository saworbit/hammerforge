"""An agent builds a room from nothing, paints it, and it survives save and reload."""

DESCRIPTION = (
    "starter, walls, a cut, paint, extrude, spawn, undo rules, save and reload"
)
START_SCENE = "other"
WINDOWED = False
SAVED = "res://vibe_mcp_scratch/room_saved.tscn"


async def run(v):
    status = await v.call("hf_get_status")
    v.expect(
        status["result"]["target"]["level_root_path"] is None, "no level yet", status
    )
    made = await v.call("hf_create_starter")
    v.expect(
        made.get("ok") and made["result"]["floor_top"] == 0.0,
        "a starter, floor top at 0",
        made,
    )
    history = v.order("history")
    v.expect(
        history.get("names") == ["MCP: create starter"], "one step for it", history
    )

    walls = [
        ([0, 2, -6], [12, 4, 1]),
        ([0, 2, 6], [12, 4, 1]),
        ([-6, 2, 0], [1, 4, 12]),
        ([6, 2, 0], [1, 4, 12]),
    ]
    ids = []
    for position, size in walls:
        placed = await v.call("hf_place_brush", {"size": size, "position": position})
        v.expect(placed.get("ok"), f"a wall at {position}", placed)
        ids.append(placed["result"]["brush"]["brush_id"])
    door = await v.call(
        "hf_place_brush",
        {"size": [2, 3, 2], "position": [0, 1.5, 6], "operation": "subtract"},
    )
    v.expect(
        door.get("ok") and door["result"]["brush"]["pending"],
        "the doorway waits as a cut",
        door,
    )

    materials = (await v.call("hf_get_materials"))["result"]["materials"]
    v.expect(len(materials) > 0, "the editor's palette has materials", len(materials))
    brick = next((m for m in materials if "brick" in m["name"]), materials[0])
    painted = await v.call(
        "hf_assign_material", {"brush_id": ids[0], "material": brick["id"]}
    )
    v.expect(painted.get("ok"), "paint a wall", painted)
    top = await v.call(
        "hf_assign_material",
        {"brush_id": ids[1], "material": brick["name"], "faces": ["+y"]},
    )
    v.expect(top.get("ok"), "paint one face, by name", top)
    ledge = await v.call(
        "hf_extrude_face", {"brush_id": ids[0], "face": "+y", "distance": 1}
    )
    v.expect(
        ledge.get("ok") and ledge["result"]["brush"]["size"] == [12.0, 1.0, 1.0],
        "extrude the wall's top",
        ledge,
    )
    turned = await v.call(
        "hf_transform_brush",
        {
            "brush_id": ledge["result"]["brush"]["brush_id"],
            "rotation_degrees": [0, 15, 0],
        },
    )
    v.expect(turned.get("ok"), "turn the ledge", turned)
    spawn = await v.call("hf_set_spawn", {"position": [0, 0, 0], "yaw_degrees": 180})
    v.expect(
        spawn.get("ok") and not spawn["result"]["inside_brush"],
        "the spawn stands clear",
        spawn,
    )

    undone = await v.call("hf_undo")
    v.expect(
        undone.get("result", {}).get("undone") == "MCP: set spawn",
        "undo the spawn",
        undone,
    )
    redone = await v.call("hf_redo")
    v.expect(redone.get("ok"), "and redo it", redone)

    v.order("human_hide_floor")
    refused = await v.call("hf_undo")
    v.expect(
        refused.get("error", {}).get("code") == "undo_conflict",
        "undo refuses after a person's edit",
        refused,
    )
    v.order("undo")
    still = await v.call("hf_undo")
    v.expect(
        still.get("error", {}).get("code") == "undo_conflict",
        "and still refuses once the person undid it",
        still,
    )

    listed = (await v.call("hf_get_brushes"))["result"]
    # The starter's floor is a plain node, not a brush.
    v.expect(
        listed["total"] == 6,
        "six brushes: four walls, the cut, the ledge",
        listed["total"],
    )
    v.order("save_as", path=SAVED)
    v.order("reload", path=SAVED)
    reloaded = await v.call("hf_get_status")
    v.note("after reload", reloaded["result"]["target"])
    after = (await v.call("hf_get_brushes"))["result"]
    before_ids = sorted(b["brush_id"] for b in listed["brushes"])
    after_ids = sorted(b["brush_id"] for b in after["brushes"])
    v.expect(
        before_ids == after_ids,
        "the same brush ids after save and reload",
        [before_ids, after_ids],
    )
    by_id = {b["brush_id"]: b for b in after["brushes"]}
    moved = [
        b["brush_id"]
        for b in listed["brushes"]
        if by_id.get(b["brush_id"], {}).get("position") != b["position"]
        or by_id.get(b["brush_id"], {}).get("size") != b["size"]
    ]
    v.expect(not moved, "every brush kept its place and size", moved)
    wall = by_id.get(ids[0], {})
    v.expect(
        all(f["material_id"] == brick["id"] for f in wall.get("faces", [])),
        "the painted wall kept its material",
        [f["material_id"] for f in wall.get("faces", [])],
    )
