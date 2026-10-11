"""The phase 3 review's fixes in the real editor: pending cuts and the revision, a
replayed bake, and a scene tab closed mid-bake."""

import time

from mcp_vibe import LEVEL

DESCRIPTION = "cuts move the revision, a replayed bake, a tab closed mid-bake"
START_SCENE = "level"
WINDOWED = False


async def run(v):
    await v.call("hf_get_status")
    await v.call("hf_place_brush", {"size": [8, 4, 8], "position": [0, 2, 0]})
    cut = await v.call(
        "hf_place_brush",
        {"size": [2, 2, 2], "position": [0, 1, 0], "operation": "subtract"},
    )
    v.expect(
        cut.get("ok") and cut["result"]["brush"]["pending"],
        "the cut waits in PendingCuts",
        cut,
    )
    baked = await v.call("hf_bake")
    v.expect(baked.get("ok"), "the bake answers ok", baked)
    v.expect(
        baked.get("revision") == cut.get("revision", -9) + 1,
        "applying the cut moved the revision by one",
        [cut.get("revision"), baked.get("revision")],
    )
    v.expect(
        baked.get("result", {}).get("current"),
        "and the bake is current at it",
        baked.get("result"),
    )
    undone = await v.call("hf_undo")
    v.expect(
        undone.get("error", {}).get("code") == "undo_conflict",
        "undo refuses past the applied cut",
        undone,
    )

    first = await v.call("hf_bake", {"operation_id": "vibe-bake-1"})
    await v.call("hf_place_brush", {"size": [1, 1, 1], "position": [6, 0.5, 6]})
    replayed = await v.call("hf_bake", {"operation_id": "vibe-bake-1"})
    v.expect(
        replayed.get("replayed")
        and replayed["result"]["bake_id"] == first["result"]["bake_id"],
        "the same id replays the bake",
        replayed,
    )
    v.expect(
        replayed["result"]["current"] is False,
        "and says it is no longer current",
        replayed["result"],
    )

    v.order("close_on_bake")
    started = time.monotonic()
    closed = await v.call("hf_bake")
    took = time.monotonic() - started
    v.note("the bake with the tab closed", closed.get("error", {}).get("code") or "ok")
    v.expect(took < 30, "it answered rather than hung", took)
    v.expect(
        v.order("scene") != "LevelRoot", "the level's tab is closed", v.order("scene")
    )
    free = await v.call("hf_get_status")
    v.expect(
        free.get("ok") and free["result"]["busy"] == "",
        "the bridge is free afterwards",
        free,
    )
    v.order("open", path=LEVEL)
    again = await v.call("hf_get_status")
    v.expect(
        again["result"]["target"]["level_root_path"] == ".",
        "reattached to the reopened level",
        again,
    )
    placed = await v.call(
        "hf_place_brush", {"size": [1, 1, 1], "position": [-6, 0.5, -6]}
    )
    v.expect(placed.get("ok"), "a change lands on it", placed)
