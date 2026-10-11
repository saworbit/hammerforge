"""Example prompts the server lists, so a client can offer them as starting points.

Each is one user message that names the tools to call and the conventions they
use. The room prompt works out every size and centre itself, since an agent left
to do that arithmetic is where a block-out most often goes wrong. Its ops are
built as data first, so a test can send exactly what the prompt says through the
batch schema.
"""

from __future__ import annotations

import math
from typing import Annotated

from mcp.shared.exceptions import MCPError
from mcp.types import INVALID_PARAMS
from pydantic import Field

WALL = 1.0
DOOR_WIDTH = 1.0
DOOR_HEIGHT = 2.2


def _n(value: float) -> str:
    """A number as an agent should send it: 16, not 16.0, and exact to a micron."""
    text = f"{round(value, 6):.6f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def _v(values: list[float]) -> str:
    return "[" + ", ".join(_n(value) for value in values) + "]"


def room_ops(width: float, depth: float, height: float) -> list[tuple[str, dict]]:
    """The room as batch ops: (what it is, {tool, params}). Inside is width by
    depth by height, the floor's top at y = 0, walls WALL thick around it."""
    w, d, h, t = float(width), float(depth), float(height), WALL

    def place(size: list[float], position: list[float], **extra) -> dict:
        params = {"size": size, "position": position, "snap": False, **extra}
        return {"tool": "hf_place_brush", "params": params}

    return [
        ("floor", place([w + 2 * t, t, d + 2 * t], [0, -t / 2, 0])),
        ("ceiling", place([w + 2 * t, t, d + 2 * t], [0, h + t / 2, 0])),
        ("wall -z", place([w + 2 * t, h, t], [0, h / 2, -(d + t) / 2])),
        ("wall +z", place([w + 2 * t, h, t], [0, h / 2, (d + t) / 2])),
        ("wall -x", place([t, h, d], [-(w + t) / 2, h / 2, 0])),
        ("wall +x", place([t, h, d], [(w + t) / 2, h / 2, 0])),
        (
            "doorway",
            place(
                [DOOR_WIDTH, DOOR_HEIGHT, 2 * t],
                [0, DOOR_HEIGHT / 2, -(d + t) / 2],
                operation="subtract",
            ),
        ),
        ("spawn", {"tool": "hf_set_spawn", "params": {"position": [0, 0, 0]}}),
    ]


def room_bounds(width: float, depth: float, height: float) -> dict:
    """The box the room fills, walls included, for a framed screenshot."""
    w, d, h, t = float(width), float(depth), float(height), WALL
    return {
        "min": [-(w / 2 + t), -t, -(d / 2 + t)],
        "max": [w / 2 + t, h + t, d / 2 + t],
    }


def _op_line(label: str, op: dict) -> str:
    params = op["params"]
    words = [f"   - {label}: {op['tool']}"]
    if params.get("operation"):
        words.append(f"operation {params['operation']}")
    if "size" in params:
        words.append(f"size {_v(params['size'])}")
    words.append(f"position {_v(params['position'])}")
    if "snap" in params:
        words.append("snap false")
    return " ".join(words)


#: The smallest room the doorway fits, and the largest worth a prompt.
ROOM_LIMITS = {"width": (2.0, 1000.0), "depth": (2.0, 1000.0), "height": (3.0, 1000.0)}


def _metres(name: str, text: str) -> float:
    """A prompt argument, which MCP sends as text, as metres within its limits.

    Refused with a message the user sees, rather than the bare internal error a
    failed type check becomes on the way out of a prompt.
    """
    low, high = ROOM_LIMITS[name]
    try:
        value = float(text)
    except (TypeError, ValueError):
        value = math.nan
    if not (low <= value <= high):
        raise MCPError(
            INVALID_PARAMS,
            f"{name} is {text!r}: give a number of metres from {low:g} to {high:g}"
            + (" (the doorway is 2.2 m tall)" if name == "height" else ""),
        )
    return value


def block_out_room(
    width: Annotated[str, Field(description="Inside width along x, in metres")] = "16",
    depth: Annotated[str, Field(description="Inside depth along z, in metres")] = "12",
    height: Annotated[
        str, Field(description="Inside height in metres, at least 3")
    ] = "4",
) -> str:
    width = _metres("width", width)
    depth = _metres("depth", depth)
    height = _metres("height", height)
    bounds = room_bounds(width, depth, height)
    lines = [
        f"Block out a room in the open HammerForge level, {_n(width)} m wide (x), "
        f"{_n(depth)} m deep (z) and {_n(height)} m tall inside, with a doorway in "
        "the wall facing -z.",
        "",
        "1. Call hf_get_status. If it has no level, call hf_create_starter.",
        "2. Make the room in one hf_batch with these ops, in this order, exactly as "
        "written. Sizes are full extents and positions are centres, in metres, Y up. "
        "snap false keeps each size exact; the spawn op takes no snap.",
        *(_op_line(label, op) for label, op in room_ops(width, depth, height)),
        "3. Call hf_validate. Fix what it reports, or tell me why you left it.",
        "4. Take an hf_viewport_screenshot with focus bounds "
        f"{{min: {_v(bounds['min'])}, max: {_v(bounds['max'])}}} and tell me what "
        "you see. Brushes draw see-through in the editor, and the doorway shows as "
        "a cut volume in the -z wall until hf_bake applies it, so a wall without a "
        "hole yet is expected.",
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
