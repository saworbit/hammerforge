"""The dock's Create Starter, and the agent's undo against the editor's own keys."""

import time

DESCRIPTION = "Create Starter is one step; hf_undo against Ctrl+Z and Ctrl+Shift+Z"
START_SCENE = "other"
WINDOWED = False


async def _count(v) -> int:
    listed = await v.call("hf_get_brushes", {"include_faces": False})
    return listed["result"]["total"]


async def run(v):
    history = v.order("dock_create_starter")
    v.expect(
        len(history.get("names", [])) == 1,
        "the dock's Create Starter is one step",
        history,
    )

    await v.call("hf_get_status")
    a = await v.call("hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]})
    b = await v.call("hf_place_brush", {"size": [2, 2, 2], "position": [4, 1, 0]})
    v.expect(a.get("ok") and b.get("ok"), "place A and B", [a, b])
    undone = await v.call("hf_undo")
    v.expect(
        undone.get("result", {}).get("undone") == "MCP: place brush",
        "hf_undo takes B back",
        undone,
    )
    v.expect(await _count(v) == 1, "one brush left", None)

    v.order("manager_undo")
    time.sleep(1.0)
    v.expect(await _count(v) == 0, "Ctrl+Z then takes A back", None)
    v.order("manager_redo")
    time.sleep(1.0)
    v.expect(await _count(v) == 1, "Ctrl+Shift+Z puts A back", None)
    v.order("manager_redo")
    time.sleep(1.0)
    v.known(
        1028,
        await _count(v) == 2,
        "a second Ctrl+Shift+Z puts back B, which hf_undo took",
        v.order("history"),
    )
    redone = await v.call("hf_redo")
    v.note("hf_redo after that", redone.get("result") or redone.get("error"))
