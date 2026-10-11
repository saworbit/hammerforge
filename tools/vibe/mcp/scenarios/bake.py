"""A room in one batch, validated, baked to the artifact Didi loads, and stale after."""

import asyncio

from mcp_vibe import REPO

DESCRIPTION = (
    "batch a room, validate, bake to <scene>_mcp.tscn, status during and after"
)
START_SCENE = "level"
WINDOWED = False
ARTIFACT = REPO / "vibe_mcp_scratch" / "level_mcp.tscn"


async def run(v):
    ops = [
        {
            "tool": "hf_place_brush",
            "params": {"size": [16, 1, 16], "position": [0, -0.5, 0]},
        },
        {
            "tool": "hf_place_brush",
            "params": {"size": [16, 4, 1], "position": [0, 2, -8]},
        },
        {
            "tool": "hf_place_brush",
            "params": {"size": [16, 4, 1], "position": [0, 2, 8]},
        },
        {
            "tool": "hf_place_brush",
            "params": {"size": [1, 4, 16], "position": [-8, 2, 0]},
        },
        {
            "tool": "hf_place_brush",
            "params": {"size": [1, 4, 16], "position": [8, 2, 0]},
        },
        {"tool": "hf_set_spawn", "params": {"position": [0, 0, 0]}},
    ]
    batch = await v.call("hf_batch", {"ops": ops})
    v.expect(batch.get("ok"), "a room in one batch", batch)
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: batch (6 ops)",
        "one step named for it",
        history,
    )
    checked = await v.call("hf_validate")
    v.expect(checked.get("ok"), "validate answers", checked)
    v.note("validate", checked.get("result", {}).get("counts"))

    baking = asyncio.ensure_future(v.call("hf_bake"))
    await asyncio.sleep(0.05)
    during = await v.call("hf_get_status")
    v.note("status during the bake, busy", during["result"]["busy"])
    baked = await baking
    v.expect(baked.get("ok"), "the bake answers ok", baked)
    result = baked.get("result", {})
    v.expect(
        result.get("artifact", {}).get("path")
        == "res://vibe_mcp_scratch/level_mcp.tscn",
        "the artifact is beside the scene",
        result.get("artifact"),
    )
    text = (
        ARTIFACT.read_text(encoding="utf-8", errors="replace")
        if ARTIFACT.is_file()
        else ""
    )
    v.expect(
        result.get("bake_id", "?") in text,
        "the artifact carries its bake id",
        result.get("bake_id"),
    )
    v.expect(
        not (REPO / "vibe_mcp_scratch" / "level_game.tscn").exists(),
        "the scene's _game.tscn is left alone",
        None,
    )
    fresh = await v.call("hf_get_status")
    v.expect(
        fresh["result"]["bake_current"],
        "status calls the bake current",
        fresh["result"].get("last_bake"),
    )
    await v.call("hf_place_brush", {"size": [1, 1, 1], "position": [3, 0.5, 3]})
    stale = await v.call("hf_get_status")
    v.expect(
        not stale["result"]["bake_current"],
        "a change makes it stale",
        stale["result"].get("last_bake"),
    )

    shot = await v.call("hf_viewport_screenshot", {"width": 320, "height": 180})
    v.expect(
        shot.get("error", {}).get("code") == "screenshot_unavailable",
        "a headless editor says it has no picture, at once",
        shot,
    )
    undone = await v.call("hf_undo")
    v.expect(
        undone.get("ok"), "undo after a bake still works: a bake is not a step", undone
    )
