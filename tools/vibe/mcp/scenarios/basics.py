"""Attach, place, the revision against a human's undo and edit, tab switches, off."""

import time

from mcp_vibe import DISCOVERY, LEVEL, OTHER

DESCRIPTION = "status, place, the revision, a human edit, tab switches, turning it off"
START_SCENE = "level"
WINDOWED = False


async def run(v):
    status = await v.call("hf_get_status")
    v.expect(status.get("ok"), "status answers", status)
    v.expect(
        status["result"]["target"]["level_root_path"] == ".",
        "the scene's root is the level",
        status["result"]["target"],
    )
    panel = v.order("panel")
    v.expect(
        panel["ticked"] and panel["text"] == "Agent connected",
        "the panel says connected",
        panel,
    )

    placed = await v.call(
        "hf_place_brush", {"size": [4, 3, 4], "position": [0, 1.5, 0]}
    )
    v.expect(placed.get("ok"), "place a brush", placed)
    history = v.order("history")
    v.expect(
        history["current_name"] == "MCP: place brush", "one step named for it", history
    )
    panel = v.order("panel")
    v.expect(
        panel["last"].startswith("Last: place brush"),
        "the panel says what it did",
        panel,
    )

    # Nothing the editor does by itself afterwards moves the revision.
    time.sleep(2.0)
    later = await v.call("hf_get_status")
    v.expect(
        later["revision"] == placed["revision"],
        "the revision holds still",
        later["revision"],
    )
    v.expect(
        later["result"]["last_agent_revision"] == placed["revision"],
        "status remembers the agent's last answer",
        later["result"]["last_agent_revision"],
    )

    # A person's edit ends the agent's undo chain.
    v.order("human_nudge")
    refused = await v.call("hf_undo")
    v.expect(
        refused.get("error", {}).get("code") == "undo_conflict",
        "hf_undo refuses after a person's edit",
        refused,
    )

    # Another tab, then back.
    v.order("open", path=OTHER)
    stale = await v.call("hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]})
    v.expect(
        stale.get("error", {}).get("code") == "target_changed",
        "a change after a tab switch is refused",
        stale,
    )
    other = await v.call("hf_get_status")
    v.expect(
        other["result"]["target"]["level_root_path"] is None,
        "the other tab has no level",
        other,
    )
    none = await v.call("hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]})
    v.expect(
        none.get("error", {}).get("code") == "no_level",
        "and a place there is no_level",
        none,
    )
    v.order("open", path=LEVEL)
    back = await v.call("hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]})
    v.expect(
        back.get("error", {}).get("code") == "target_changed",
        "back again is a change too",
        back,
    )
    again = await v.call("hf_get_status")
    v.expect(
        again.get("ok") and again["result"]["counts"]["brushes"] == 1,
        "reattached, one brush",
        again,
    )

    # Off.
    v.order("disable")
    v.expect(not DISCOVERY.exists(), "unticking deletes the discovery file", None)
    gone = await v.call("hf_get_status")
    v.expect(
        gone.get("error", {}).get("code") == "bridge_off",
        "and the server says bridge_off",
        gone,
    )
