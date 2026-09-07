# Free Transform — Rotate, Flip, and Array

Design document. 7 September 2026.

## Problem

HammerForge cannot rotate a brush. Every brush is authored axis-aligned, so a
diagonal wall, an angled ramp, or a rotunda is unreachable except by hand-placing
`CUSTOM` faces through the polygon or path tool.

This is not a plumbing gap. The plumbing is already built:

- `baker.gd` bakes through `brush.global_transform.basis` and `.origin`, so
  rotated brushes already bake correctly.
- `hf_snap_system.gd` puts snap candidates through `global_transform`, so snapping
  already carries rotation.
- `hflevel_io.gd` serialises a full `Basis` per brush, so rotation already
  round-trips through save and load.
- `brush_gizmo_plugin.gd` draws handles from `global_transform.basis`, so the
  gizmos already track rotation.
- `hf_brush_system.gd` already defends the operations that cannot cope:
  `_check_axis_aligned_box()` refuses hollow, clip, and carve on a rotated brush.

What is missing is the authoring layer. There is no command, hotkey, menu entry,
or dock control anywhere in the plugin that changes a brush's basis.
`FaceData.adjust_uvs_for_rotation()` and
`HFBrushSystem._adjust_face_uvs_for_rotation()` were both written for this
feature and have no callers today.

## Scope

Three capabilities, one new subsystem, and the UI surfaces that reach them.

1. **Rotate** a selection by a snapped or typed angle, about a chosen axis and pivot.
2. **Flip** a selection across an axis-aligned plane through a chosen pivot.
3. **Radial and grid arrays** in the duplicator, which become useful the moment
   rotation exists.

Out of scope: modal mouse-drag rotation (a gesture, not a transform — it belongs
with the drag system and needs interactive validation this pass cannot give it),
live symmetry mode, and non-axis-aligned mirror planes.

## Architecture

### `systems/hf_transform_system.gd` — `HFTransformSystem`

A `RefCounted` subsystem constructed with the `LevelRoot` reference, matching the
other twenty-one subsystems. It owns every transform computation and touches
nodes only through the brush and entity systems it is given.

```
rotate(brush_ids, entity_paths, axis_index, angle_rad, pivot) -> int
flip(brush_ids, entity_paths, axis_index, pivot) -> int
reset_rotation(brush_ids) -> int
resolve_pivot(brush_ids, entity_paths, mode, custom) -> Vector3
selection_bounds(brush_ids, entity_paths) -> AABB
```

Each mutating call returns the number of objects it changed, so callers can skip
an undo entry for a no-op.

**Rotation** is a rigid, determinant `+1` transform. For each brush it composes

```
R           = Basis(axis, angle)
origin'     = pivot + R * (origin - pivot)
basis'      = R * basis
```

Local face data is untouched — the primitive regenerates identically in local
space and the world geometry rotates through the basis. This is why rotation
needs no geometry surgery and why the baker already handles it.

When `root.texture_lock` is on, each face's `adjust_uvs_for_rotation()` is called
so the texture stays pinned in world space, matching the semantics the property
already has for translation and resize. This wires up the two existing dead
functions.

**Flip** is a reflection, determinant `-1`, and that is the whole difficulty: a
negative-determinant basis inverts triangle winding at bake time, so the brush
would render inside out. The fix keeps the world geometry exact while restoring
handedness. With `R` the world reflection and `H` a reflection along one local
axis:

```
basis'' = R * basis * H          (det +1 again: -1 * -1)
verts'  = H * verts              (H is an involution, so H * H = I)
```

`basis'' * verts' = R * basis * H * H * verts = R * basis * verts`, so the world
position of every vertex is exactly the mirror of where it was, and the basis is
right-handed. Reflecting the local vertices reverses their winding, so each face's
vertex order is reversed to restore the clockwise-from-outside winding the whole
codebase depends on.

`H` is chosen as the reflection along the local axis most aligned with the world
mirror normal. For a brush that is already axis-aligned this makes `H` the
identity-preserving choice that leaves a box a box.

Face data follows the geometry in one of two ways:

- **Authoritative faces** (`shape == CUSTOM`): `local_verts` are reflected by `H`
  and reversed in place, then `ensure_geometry()` recomputes normals and bounds.
  Per-face material, UV, paint, and displacement data stay attached to the same
  `FaceData` object, which is exactly right — that face moved, it did not swap.
- **Parametric shapes**: the face list regenerates from the primitive, so per-face
  data is re-attached by matching world-space face centroids before and after
  through the same mirror. A box keeps its resize handles and its per-face
  materials still land on the faces they were painted on.

**Reset rotation** snaps a brush's basis back to identity while keeping its
origin. It is the escape hatch that makes hollow, clip, and carve reachable again
after a rotation, and it is the honest answer to the guards those operations
already carry.

**Pivot** resolution is a pure function of the selection with four modes:
selection centre, world origin, active (first) object, and a caller-supplied
point.

### `LevelRoot` surface

Two new persisted settings, alongside the existing `texture_lock` and `axis_lock`:

- `rotate_snap_degrees: float = 15.0` — the step for hotkey rotation.
- `transform_pivot_mode: int = 0` — selection centre, world origin, or active.

Both are captured and restored by `hf_state_system.gd` so they survive undo and
save, following `texture_lock` exactly.

Three delegates, shaped like the existing `nudge_managed_nodes`, because
`HFUndoHelper.commit()` dispatches undo by method name on `LevelRoot`:

```
rotate_managed_nodes(brush_ids, entity_paths, axis_index, angle_deg, pivot_mode)
flip_managed_nodes(brush_ids, entity_paths, axis_index, pivot_mode)
reset_managed_rotation(brush_ids)
```

Each wraps its work in `begin_signal_batch()` / `end_signal_batch()` like the
other bulk mutations. Each takes five arguments or fewer, which keeps them on
`HFUndoHelper`'s undoable path rather than its direct-call fallback.

### Entities

An entity is a `Node3D`, so rotating one rotates its transform: position about
the pivot, basis by `R`. That is uniform and correct for every entity class.

One special case earns its place. Entity classes that store a yaw in
`entity_data["angle"]` — `player_start` among them — have that value consumed by
quick play and by the runtime, independently of node rotation. When the rotation
is about the Y axis, the stored angle is advanced by the same amount, and under a
flip it is reflected. Entities without an `angle` key are unaffected.

### `hf_duplicator.gd` — array modes

`HFDuplicator` today generates copies at a progressive linear offset. It gains two
siblings that reuse the same instance tracking, tagging, and teardown:

```
generate_radial(brush_system, count, axis_index, total_angle_deg, pivot)
generate_grid(brush_system, counts: Vector3i, spacing: Vector3)
```

Both build on `brush_system.build_duplicate_info()`, which already carries the
full `Transform3D`, so a radial copy is the source info with its transform
composed through the same rotation the transform system uses. There is one
rotation implementation, not two.

A `mode` field joins `count` and `offset` in `to_dict()` / `from_dict()`, with
the linear mode as the default so existing saved duplicators load unchanged.

### Command surfaces

The feature is reachable from every surface the codebase already establishes for
an edit action, wired the same way `merge` and `clip` are:

- `hf_keymap.gd`: `rotate_ccw` (R), `rotate_cw` (Shift+R), `flip_selection`
  (Shift+M), `reset_rotation` (Alt+R), each in a new "Transform" category. R is
  already `paint_ramp`, which `plugin_input_router.gd` dispatches only when paint
  mode is active, so the transform checks are placed after the paint block in the
  same ladder: in paint mode R still picks the ramp tool, and everywhere else it
  rotates. Shift+M and Alt+R are unbound today; Ctrl+Shift+M (merge) and
  Ctrl+Shift+R (carve) do not collide because `matches()` compares every modifier.
- `plugin_edit_actions.gd`: `rotate_selected`, `flip_selected`,
  `reset_rotation_selected`, each collecting brush ids and entity paths from the
  selection exactly as `nudge_selected` does, then committing through
  `HFUndoHelper`.
- `plugin_commands.gd`: dispatch entries so the toolbar, palette, context menu,
  and radial menu all reach the same code.
- `plugin_shortcuts.gd`: the new actions join the scope-guard claim ladder.
- `ui/hf_context_toolbar.gd`: a Transform group in the brush-selected context.
- `ui/hf_viewport_context_menu.gd`: entries in the brush section.
- `ui/selection_tools_builder.gd`: a Transform sub-header with axis, pivot, and
  angle controls, the three buttons, and the array-mode controls.

The rotation axis comes from the existing `axis_lock` when one is set and
defaults to Y otherwise, which is the axis a level designer wants in almost every
case and reuses a concept the editor already teaches.

## Error handling

Every path returns an `int` count or an `HFOpResult`, following the codebase's
no-exceptions convention.

- An empty selection returns zero and commits no undo entry.
- A zero angle returns zero and commits no undo entry.
- `resolve_pivot` on an empty selection returns `Vector3.ZERO` rather than
  dividing by zero.
- Brushes that vanish mid-operation are skipped, matching `nudge_brushes_by_id`.
- Hollow, clip, and carve keep refusing rotated brushes through the existing
  `_check_axis_aligned_box`. Rotation makes those guards reachable for the first
  time, so the guard messages and the new **Reset Rotation** command are now a
  real workflow rather than dead defence.

## Testing

Headless GUT suites, since every operation is geometry and data.

`tests/test_transform_system.gd`
- Rotation composes: four 90° rotations about any axis return the original
  transform within epsilon.
- Rotation is rigid: the basis stays orthonormal and determinant `+1` after
  arbitrary angles.
- Pivot modes place the result where they claim to.
- Flip twice about the same plane is the identity, for boxes and for `CUSTOM`
  brushes.
- Flip leaves the basis determinant positive and every face wound clockwise from
  outside.
- Flipped world vertex positions equal the mirror of the originals.
- Per-face materials survive a flip on both the authoritative and parametric
  paths.
- Texture lock on rotation moves `uv_rotation` and clears `custom_uvs`; texture
  lock off leaves both alone.
- Entity position, basis, and `entity_data["angle"]` all follow.
- Empty and degenerate selections are no-ops.

`tests/test_transform_array.gd`
- Radial array places `count` copies at the expected angles about the pivot.
- Grid array places `counts.x * counts.y * counts.z` copies at the expected
  spacings.
- `clear_instances` removes exactly what the new modes created.
- `to_dict` / `from_dict` round-trips the mode, and a dictionary without a mode
  key loads as linear.

Integration coverage
- A rotated brush bakes to world-space vertices matching the transform.
- A rotated brush survives a `.hflevel` save and load with its basis intact.
- Undo and redo restore the pre-rotation transform.
- Hollow, clip, and carve refuse a rotated brush with their existing messages,
  and accept it again after Reset Rotation.

Boundary coverage in the existing `tests/test_plugin_*.gd` and keymap suites for
the new actions and dispatch entries.

## Risks

**Winding.** Mirroring is the one operation in this design that can produce
inside-out geometry, and inside-out geometry is invisible until bake. The design
handles it structurally by keeping the basis determinant positive rather than by
patching normals afterwards, and the test suite asserts winding directly rather
than asserting that a mirror "looks right".

**Parametric face re-attachment.** Matching faces by world centroid is exact for
the axis-aligned mirrors this design supports, and the tests pin it. If a shape
regenerates a different face count the match degrades to leaving data on its
original index, which is the current behaviour and no worse than today.

**Reachable guards.** Rotation makes three previously unreachable error paths
reachable by ordinary use. That is a feature — the guards were written for this —
but it means hollow, clip, and carve will start refusing work for users who
rotate. Reset Rotation is the answer, and it is surfaced everywhere the
transform commands are.

## Verification

Yellow, red, and purple passes over the finished work:

- **Yellow** — build it test-first, then run the full GUT suite, `gdformat`, and
  `gdlint` clean.
- **Red** — attack the result deliberately: degenerate selections, non-orthonormal
  bases, scaled parents, brushes inside groups and prefabs, brush entities,
  displacement faces, painted faces, double flips, 360° rotations, save and load
  round trips, undo and redo, and the interaction with every operation that
  assumes axis alignment. Failures become tests before they become fixes.
- **Purple** — fold the red findings back in, re-run everything, and update the
  changelog, roadmap, and user documentation to match what actually shipped.
