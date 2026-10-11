"""Example prompts the server lists, so a client can offer them as starting points.

Each is one user message that names the tools to call and the conventions they
use. The room prompt works out every size and centre itself, since an agent left
to do that arithmetic is where a block-out most often goes wrong.
"""

from __future__ import annotations

WALL = 1.0
DOOR_WIDTH = 1.0
DOOR_HEIGHT = 2.2


def _n(value: float) -> str:
    """A number as an agent should send it: 16, not 16.0."""
    return f"{value:g}"


def _v(*values: float) -> str:
    return "[" + ", ".join(_n(value) for value in values) + "]"


def block_out_room(width: float = 16, depth: float = 12, height: float = 4) -> str:
    w, d, h, t = float(width), float(depth), float(height), WALL
    lines = [
        f"Block out a room in the open HammerForge level, {_n(w)} m wide (x), "
        f"{_n(d)} m deep (z) and {_n(h)} m tall inside, with a doorway in the "
        "wall facing -z.",
        "",
        "1. Call hf_get_status. If it has no level, call hf_create_starter.",
        "2. Make the room in one hf_batch, every op with snap false so the sizes "
        "are exact. Sizes are full extents and positions are centres, in metres, "
        "Y up. The ops, in order:",
        f"   - floor: hf_place_brush size {_v(w + 2 * t, t, d + 2 * t)} "
        f"position {_v(0, -t / 2, 0)}",
        f"   - ceiling: hf_place_brush size {_v(w + 2 * t, t, d + 2 * t)} "
        f"position {_v(0, h + t / 2, 0)}",
        f"   - wall -z: hf_place_brush size {_v(w + 2 * t, h, t)} "
        f"position {_v(0, h / 2, -(d + t) / 2)}",
        f"   - wall +z: hf_place_brush size {_v(w + 2 * t, h, t)} "
        f"position {_v(0, h / 2, (d + t) / 2)}",
        f"   - wall -x: hf_place_brush size {_v(t, h, d)} "
        f"position {_v(-(w + t) / 2, h / 2, 0)}",
        f"   - wall +x: hf_place_brush size {_v(t, h, d)} "
        f"position {_v((w + t) / 2, h / 2, 0)}",
        f"   - doorway: hf_place_brush operation subtract size "
        f"{_v(DOOR_WIDTH, DOOR_HEIGHT, 2 * t)} "
        f"position {_v(0, DOOR_HEIGHT / 2, -(d + t) / 2)}",
        f"   - spawn: hf_set_spawn position {_v(0, 0, 0)}",
        "3. Call hf_validate. Fix what it reports, or tell me why you left it.",
        "4. Take an hf_viewport_screenshot with focus bounds "
        f"{{min: {_v(-(w / 2 + t), -t, -(d / 2 + t))}, "
        f"max: {_v(w / 2 + t, h + t, d / 2 + t)}}} and tell me what you see.",
        "",
        "The whole room is one undo step, so if it looks wrong, hf_undo takes it "
        "back and you can try again.",
    ]
    return "\n".join(lines)


def review_level() -> str:
    return "\n".join(
        [
            "Review the open HammerForge level and change nothing.",
            "",
            "1. Call hf_get_status for the scene, level and counts.",
            "2. Call hf_validate. Each finding names a brush_id or an entity.",
            "3. Call hf_get_brushes with include_faces false for the layout.",
            "4. Take an hf_viewport_screenshot of the whole level, and one with "
            "focus brush_ids for each brush hf_validate names.",
            "5. Tell me what you found, errors first, each with its brush_id, what "
            "is wrong and the change that would fix it. Make none of them until "
            "I say so.",
        ]
    )


def bake_for_playtest() -> str:
    return "\n".join(
        [
            "Get the open HammerForge level ready for a playtest.",
            "",
            "1. Call hf_validate. Fix the errors; ask me before you delete a brush.",
            "2. Call hf_bake. It writes <scene>_mcp.tscn beside the level's scene.",
            "3. Give me artifact.path (a res:// path) and the bake_id.",
            "4. Tell me how to check the playtest runs this bake: in the running "
            'game, get_tree().current_scene.get_meta("hammerforge_bake").bake_id '
            "is that bake_id.",
            "",
            "If hf_get_status later says bake_current is false, the level changed "
            "after the bake: bake again before the next run.",
        ]
    )


#: name -> (title, description, function), in the order a client lists them.
PROMPTS = {
    "block_out_room": (
        "Block out a room",
        "Floor, walls, ceiling, a doorway and the spawn in one undo step, with "
        "every size and centre worked out.",
        block_out_room,
    ),
    "review_level": (
        "Review the level",
        "Validate, list the brushes, look at it, and report what to fix without "
        "changing anything.",
        review_level,
    ),
    "bake_for_playtest": (
        "Bake for a playtest",
        "Validate, bake to <scene>_mcp.tscn, and say how to check the game runs "
        "that bake.",
        bake_for_playtest,
    ),
}
