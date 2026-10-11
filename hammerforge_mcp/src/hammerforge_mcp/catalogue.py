"""The fixed tool catalogue: names, words for the agent, and how long each may take.

The list never changes while the server runs. A tool the editor's bridge does not
know yet answers `unknown_method`, so a newer server against an older addon
fails loudly rather than guessing.
"""

from __future__ import annotations

from dataclasses import dataclass

from mcp.types import ToolAnnotations

CONVENTIONS = (
    "Godot Y-up, metres. Positions are world-space. Size is full extents. "
    "Rotation is degrees, Euler XYZ order. Snapping follows the current grid "
    "unless overridden: with snap on, size snaps to whole grid steps and an "
    "unrotated brush's lowest corner lands on the grid."
)

ONE_STEP = (
    "It is one undo step named 'MCP: ...' in the editor. A retry with the same "
    "operation_id returns the first answer instead of running again; one is made "
    "for you if you leave it out."
)

SHAPES = (
    "box",
    "cylinder",
    "sphere",
    "cone",
    "wedge",
    "pyramid",
    "prism_tri",
    "prism_pent",
    "ellipsoid",
    "capsule",
    "torus",
    "tetrahedron",
    "octahedron",
    "dodecahedron",
    "icosahedron",
)

#: Codes that mean the bridge itself failed rather than the level said no.
PROTOCOL_ERRORS = frozenset(
    {
        "bad_request",
        "unknown_method",
        "frame_too_large",
        "auth_failed",
        "unsupported_bridge_version",
        "internal_error",
    }
)

DEFAULT_TIMEOUT = 30.0


@dataclass(frozen=True)
class ToolSpec:
    name: str
    title: str
    description: str
    mutating: bool
    annotations: ToolAnnotations
    timeout: float = DEFAULT_TIMEOUT


def _read_only(title: str) -> ToolAnnotations:
    return ToolAnnotations(title=title, read_only_hint=True, open_world_hint=False)


def _change(
    title: str, *, destructive: bool = False, idempotent: bool = False
) -> ToolAnnotations:
    return ToolAnnotations(
        title=title,
        read_only_hint=False,
        destructive_hint=destructive,
        idempotent_hint=idempotent,
        open_world_hint=False,
    )


_SPECS = [
    ToolSpec(
        name="hf_get_status",
        title="Get status",
        description=(
            "Which editor, scene and HammerForge level the bridge is working on "
            "(target_id), the scene revision, brush and entity counts, the grid "
            "size, the editor camera, and whether the editor is busy. Call it first, "
            "and again after a target_changed error to work on what is open now. "
            "Every answer carries the revision; a change you did not make moves it."
        ),
        mutating=False,
        annotations=_read_only("Get status"),
        timeout=15.0,
    ),
    ToolSpec(
        name="hf_place_brush",
        title="Place a brush",
        description=(
            "Add a brush to the level. shape is one of "
            + ", ".join(SHAPES)
            + ". operation 'union' adds solid; 'subtract' cuts a hole and is "
            "applied at bake time. Returns the brush with its brush_id, bounds and "
            "faces (world normals and centres). " + CONVENTIONS + " " + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Place a brush"),
    ),
]

TOOLS: dict[str, ToolSpec] = {spec.name: spec for spec in _SPECS}
