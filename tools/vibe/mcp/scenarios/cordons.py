"""Cordons set over the bridge, followed by the real dock and the editor's undo."""

DESCRIPTION = (
    "cordons: one moved by index and one added round a brush, each one step; the "
    "dock shows them, and a person's spin nudge after keeps the agent's bounds; "
    "Ctrl+Z takes edits back; a refused batch leaves the cordons as they were "
    "(#1300); a bake cut to them says it is partial, and one without is whole (#1317)"
)
START_SCENE = "level"
WINDOWED = False


async def _cordons(v):
    listed = await v.call("hf_get_cordons", {})
    return listed.get("result", {}).get("cordons", [])


async def run(v):
    moved = await v.call(
        "hf_set_cordon",
        {
            "index": 0,
            "bounds": {"min": [-10, -2, -10], "max": [10, 6, 10]},
            "name": "Hall",
        },
    )
    if not v.expect(moved.get("ok"), "cordon 0 moves to a box by index", moved):
        return
    v.expect(
        moved["result"]["enabled"] and moved["result"]["partial_bake"],
        "a cordon given a place switches cordons on",
        moved["result"],
    )
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: set cordon", "one step named for it", history
    )
    dock = v.order("dock_cordons")
    v.expect(
        dock.get("items") == ["Hall"]
        and dock.get("enabled") is True
        and dock.get("min") == [-10, -2, -10]
        and dock.get("max") == [10, 6, 10],
        "the dock shows the agent's cordon, name, bounds and switch",
        dock,
    )

    # The #968 trap: a dock still showing the old bounds writes all six back on
    # one nudge. Told of the edit, it moves min x alone.
    v.order("dock_cordon_nudge")
    cordons = await _cordons(v)
    v.expect(
        len(cordons) == 1
        and cordons[0]["min"] == [-9, -2, -10]
        and cordons[0]["max"] == [10, 6, 10],
        "a person's spin nudge after the agent's edit keeps the agent's bounds",
        cordons,
    )

    placed = await v.call("hf_place_brush", {"size": [4, 2, 4], "position": [40, 1, 0]})
    if not v.expect(placed.get("ok"), "a far brush to cordon", placed):
        return
    brush_id = placed["result"]["brush"]["brush_id"]
    added = await v.call("hf_set_cordon", {"brush_ids": [brush_id], "name": "Far room"})
    v.expect(
        added.get("ok")
        and added["result"]["added"]
        and added["result"]["cordon"]["index"] == 1
        and added["result"]["cordon"]["min"] == [37, -1, -3],
        "a cordon is added round the brush, grown by a unit",
        added,
    )
    dock = v.order("dock_cordons")
    v.expect(dock.get("items") == ["Hall", "Far room"], "the dock lists both", dock)

    # A person's Ctrl+Z takes the agent's add back like any other step.
    v.order("manager_undo")
    cordons = await _cordons(v)
    v.expect(
        len(cordons) == 1, "a person's Ctrl+Z takes the added cordon back", cordons
    )
    dock = v.order("dock_cordons")
    v.expect(dock.get("items") == ["Hall"], "and the dock follows the undo", dock)

    before = await _cordons(v)
    refused = await v.call(
        "hf_batch",
        {
            "ops": [
                {
                    "tool": "hf_set_cordon",
                    "params": {"bounds": {"min": [0, 0, 0], "max": [1, 1, 1]}},
                },
                {"tool": "hf_remove_cordon", "params": {"index": 0}},
                {"tool": "hf_set_cordon", "params": {"enabled": False}},
                {"tool": "hf_delete_brush", "params": {"brush_id": "nope"}},
            ]
        },
    )
    v.expect(
        not refused.get("ok")
        and refused["error"]["code"] == "batch_failed"
        and refused["error"]["details"]["index"] == 3,
        "a batch whose last op is refused fails",
        refused,
    )
    v.expect(
        await _cordons(v) == before,
        "and leaves the cordons as they were",
        refused.get("error", {}).get("details"),
    )

    # A bake cut to the cordons in the real editor, then a whole one (#1317).
    partial = await v.call("hf_bake", {"cordons": True})
    names = [c.get("name") for c in partial.get("result", {}).get("cordons", [])]
    v.expect(
        partial.get("ok") and partial["result"]["partial"] and names == ["Hall"],
        "a bake cut to the cordons says so and names them",
        partial,
    )
    status = await v.call("hf_get_status", {})
    last = status.get("result", {}).get("last_bake") or {}
    v.expect(last.get("partial") is True, "status's last bake is partial", last)
    whole = await v.call("hf_bake", {})
    v.expect(
        whole.get("ok") and whole["result"]["partial"] is False,
        "a bake without cordons is whole",
        whole,
    )
