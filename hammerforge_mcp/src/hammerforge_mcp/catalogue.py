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
    ToolSpec(
        name="hf_get_brushes",
        title="List brushes",
        description=(
            "The level's brushes, union brushes first, then pending cuts, then "
            "committed cuts (frozen; the change tools refuse them): brush_id, shape, "
            "union or subtract, whether it is a pending cut, position, "
            "rotation_degrees, size, world bounds, material_id, and each face's "
            "index, world normal, centre and material. Filter by brush_ids or by "
            "bounds ({min, max}, keeps brushes that overlap); include_faces false "
            "leaves the faces out; limit is 1 to 2000 (200 by default). Ids that "
            "match nothing are listed in missing. " + CONVENTIONS
        ),
        mutating=False,
        annotations=_read_only("List brushes"),
    ),
    ToolSpec(
        name="hf_get_materials",
        title="List materials",
        description=(
            "The level's material palette: each material's id (its resource path, "
            "or palette:N for one saved inside the scene), its name and its slot. "
            "hf_assign_material takes an id or a name from here."
        ),
        mutating=False,
        annotations=_read_only("List materials"),
    ),
    ToolSpec(
        name="hf_transform_brush",
        title="Move or turn a brush",
        description=(
            "Move a brush to a position, turn it to rotation_degrees, or both. "
            "Both are absolute, not steps: the same call twice leaves it where the "
            "first put it. It turns about its own centre. "
            + CONVENTIONS
            + " "
            + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Move or turn a brush", idempotent=True),
    ),
    ToolSpec(
        name="hf_resize_brush",
        title="Resize a brush",
        description=(
            "Give a brush a new size, keeping its centre (then snapped, see "
            "below). A custom brush (merged, clipped, bevelled or drawn as a "
            "polygon) keeps its own faces, so it is refused with "
            "unsupported_shape. " + CONVENTIONS + " " + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Resize a brush", idempotent=True),
    ),
    ToolSpec(
        name="hf_delete_brush",
        title="Delete a brush",
        description=(
            "Delete a brush, and the entity wires aimed at it. hf_undo brings it "
            "back with the same brush_id. " + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Delete a brush", destructive=True),
    ),
    ToolSpec(
        name="hf_extrude_face",
        title="Extrude a face",
        description=(
            "Add a new box on one face of a brush, as wide as the face and "
            "distance deep along its normal, as the Extrude tool does. The source "
            "brush is left as it was. face is an index, a world side "
            "('+x', '-x', '+y', '-y', '+z', '-z'), or {normal: [x, y, z]}; a side "
            "or normal picks the face pointing most nearly that way, within about "
            "45 degrees, and a tie is refused as ambiguous_face. distance is above "
            "0 and at most 256, snapped to the grid unless snap is false. " + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Extrude a face"),
    ),
    ToolSpec(
        name="hf_assign_material",
        title="Paint a material",
        description=(
            "Put a material from the palette on a brush: every face, or only the "
            "faces listed (each an index, a side or {normal}). material is an id "
            "or a name from hf_get_materials; two materials with the same name are "
            "refused as ambiguous_material. " + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Paint a material", idempotent=True),
    ),
    ToolSpec(
        name="hf_set_spawn",
        title="Place the player spawn",
        description=(
            "Put the player spawn where the player's feet should stand, making "
            "one if the level has none, and optionally face it yaw_degrees about "
            "Y. Says whether it ends up inside a brush and where the nearest clear "
            "place is. validation looks for the floor in baked collision, so before "
            "the first bake it can say the spawn is floating. Godot Y-up, metres, "
            "world space. " + ONE_STEP
        ),
        mutating=True,
        annotations=_change("Place the player spawn", idempotent=True),
    ),
    ToolSpec(
        name="hf_create_starter",
        title="Create a starter level",
        description=(
            "Make a HammerForge level in the open scene: a LevelRoot with a floor "
            "whose top is at y = 0, a sun, and a player spawn. Refused with "
            "level_exists if the scene has one already. The answer's target_id is "
            "the new level, and later calls work on it; spawn_feet is the floor "
            "point the spawn stands on, the kind of position hf_set_spawn takes. "
            "One undo step."
        ),
        mutating=True,
        annotations=_change("Create a starter level"),
    ),
    ToolSpec(
        name="hf_undo",
        title="Undo the agent's last step",
        description=(
            "Take back the last 'MCP: ...' step. Refused with undo_conflict when "
            "the top step is not the agent's, when anything else changed the "
            "level after the agent's last answer (even a change that was then "
            "undone), or when the editor has moved to another scene or level since: "
            "it never takes back somebody else's work. Each call is a new undo: "
            "after a timeout, pass the operation_id it gave to learn what it did "
            "rather than undo a second step."
        ),
        mutating=True,
        annotations=_change("Undo the agent's last step", destructive=True),
    ),
    ToolSpec(
        name="hf_bake",
        title="Bake the level",
        description=(
            "Bake the level and write the scene a game, or Didi, loads: "
            "<scene>_mcp.tscn beside the level's own scene "
            "(res://hammerforge_mcp_bake.tscn for a scene never saved). It never "
            "touches <scene>_game.tscn. The answer gives bake_id, source_revision, "
            "the artifact's res:// and absolute paths, and warnings; the exported "
            "scene's root carries the same bake_id and source_revision as "
            "hammerforge_bake metadata, so whatever loads it can check. A bake is "
            "not an undo step. It moves the revision only when it applies pending "
            "subtract cuts, and then hf_undo refuses: no undo step records the cut "
            "going in. hf_get_status's bake_current says whether the level still "
            "matches the last bake. Refused with bake_busy while another bake runs. "
            "A repeat without an operation_id bakes again; pass the id from a "
            "timeout to get that bake's answer instead."
        ),
        mutating=True,
        annotations=_change("Bake the level"),
        timeout=900.0,
    ),
    ToolSpec(
        name="hf_validate",
        title="Check the level",
        description=(
            "Everything HammerForge would warn about before a bake: bake checks "
            "(thin or huge brushes, open edges, floating cuts and more), the "
            "spawn's layout, and Validate's findings, each with type, severity "
            "(info, warning, error), message, the brush_id or entity it is about "
            "(and other_brush_id when it is about two brushes, such as a "
            "micro_gap), and a fix name where there is one. Counts by severity "
            "too. Changes nothing."
        ),
        mutating=False,
        annotations=_read_only("Check the level"),
        timeout=60.0,
    ),
    ToolSpec(
        name="hf_viewport_screenshot",
        title="Take a screenshot",
        description=(
            "A PNG of the level. Without focus, what the editor's 3D viewport "
            "shows, scaled to fit width x height (64 to 1920 by 64 to 1080, "
            "1280x720 by default). With focus {brush_ids: [...]} or {bounds: {min, "
            "max}}, a camera looking the way the editor's does, backed off until "
            "all of it is in view. The editor's own camera never moves. Refused "
            "with screenshot_unavailable when the editor has no display."
        ),
        mutating=False,
        annotations=_read_only("Take a screenshot"),
        timeout=60.0,
    ),
    ToolSpec(
        name="hf_batch",
        title="Make several changes as one",
        description=(
            "Run up to 100 changes as one undo step, all or nothing: each op is "
            "{tool, params} for hf_place_brush, hf_transform_brush, "
            "hf_resize_brush, hf_delete_brush, hf_extrude_face, hf_assign_material "
            "or hf_set_spawn, checked against what the ops before it left. A "
            "string '$N.brush_id' in any op's params is replaced with the brush "
            "op N made, N earlier than that op. If any op is refused, nothing is "
            "kept and the answer is batch_failed with its index and error."
        ),
        mutating=True,
        annotations=_change("Make several changes as one", destructive=True),
    ),
    ToolSpec(
        name="hf_redo",
        title="Redo the agent's step",
        description=(
            "Put back the 'MCP: ...' step hf_undo took away, on the same terms: "
            "refused with redo_conflict if the step is not the agent's or the "
            "level changed since."
        ),
        mutating=True,
        annotations=_change("Redo the agent's step", destructive=True),
    ),
]

TOOLS: dict[str, ToolSpec] = {spec.name: spec for spec in _SPECS}
