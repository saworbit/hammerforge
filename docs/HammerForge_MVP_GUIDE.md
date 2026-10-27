---
description: "The shortest path from an empty Godot scene to a playable blockout: draw brushes, cut openings, paint surfaces, bake and test."
---

# HammerForge MVP Guide

Last updated: October 22, 2026

This guide is for contributors implementing or extending the MVP.

## Goals
- Fast in-editor greyboxing with draft brushes.
- Bake to optimized meshes only when needed.
- Keep editor responsiveness high (no live CSG while editing).
- Modular architecture with clear subsystem boundaries.

## Architecture Overview

HammerForge uses a **coordinator + subsystems** pattern:

- **`plugin.gd`** coordinates editor integration and routes to `LevelRoot`. Viewport arbitration, native RMB ownership, native object/Face Select pointer handling, EditorSelection synchronization and managed scope guards, undoable managed edit actions, entity/brush/prefab/material viewport drops (taken over the viewport by `ui/hf_viewport_drop_target.gd`, because an `EditorPlugin` gets no drop calls), paint/draw/extrude pointer handling, Repeat Last Brush (`plugin_brush_stamp.gd`), typed Offset and Pick Pivot (`plugin_transform_tools.gd`), Wrap (`plugin_uv_wrap.gd`), numeric dimension entry, keyboard dispatch, vertex input, HUD state, command dispatch, overlay lifecycle/drawing, quick properties, and coach marks delegate to focused `plugin_*.gd` modules. It retains sticky `active_root` discovery with deep recursive tree search.
- **`level_root.gd`** is the coordinator that owns containers, exports, and signals. Public methods delegate to subsystem classes; continued decomposition is tracked in the roadmap. Default UX is Draw → material → entity → bake → Test Level; power-user overlays are opt-in.
- **Subsystems** (`systems/*.gd`) are `RefCounted` classes that do the real work. Each receives a `LevelRoot` reference in its constructor.
- **Runtime boundary**: `LevelRoot` eagerly initializes only brush, entity, bake, paint, and file systems in export templates. Editor-only systems are loaded dynamically when `Engine.is_editor_hint()` or the `editor` feature is present, keeping the authoring graph out of exported games while preserving headless editor tests.
- **`input_state.gd`** is a state machine managing drag/paint modes.
- **`dock.gd`** presents 4 tabs (Build, Paint, Objects, Test) with programmatic, persisted collapsible sections. Tab workflows, file operations, visgroups/cordon, and signal wiring delegate to focused `dock_*_handler.gd` and `dock_connections.gd` modules while compatibility callbacks remain thin. `dock_tool_memory.gd` keeps the Build tab's and the Structure section's settings in the user preferences between sessions. Selection tools appear contextually in Build when brushes are selected. The primary toolbar exposes Draw, Select, Paint, More, and Help.

See [DEVELOPMENT.md](https://github.com/saworbit/hammerforge/blob/main/DEVELOPMENT.md) for the full file tree and architecture conventions.

## Core Systems

### Brush Workflow (`HFBrushSystem` + `HFDragSystem` + `HFExtrudeTool`)
- DraftBrush nodes represent all authored geometry.
- `HFDragSystem` manages the two-stage draw lifecycle (base drag -> height click) and owns the `HFInputState` instance. Ctrl+Z cancels an unfinished draw or extrusion before changing committed history.
- `HFGridSystem` owns the construction plane. Draw hits use `snap_draw_hit()` to preserve a held plane's exact coordinate on the hits `_raycast()` marks `CONSTRUCTION_PLANE_HIT`, never on a face or physics hit; Grid Up/Down, Reset and Align are transient view commands with no undo step.
- `HFDragSystem.draw_start()` works out where a draw starts and what it is on: the grid, a floor, a raised face, a slope, or with Draw on Face (L) the face itself, which lays the brush's base in that face's own axes. The draw, Repeat and the hover preview (`systems/hf_draw_hover.gd`, the tinted face and the cross at the snapped point) all read it.
- `HFExtrudeTool` handles face extrusion: picks a face via `FaceSelector`, shows a preview, and commits a new DraftBrush on release. Supports Up (along face normal) and Down (opposite).
- `HFBrushSystem` handles brush CRUD, pending/committed cuts, materials, picking, hollow, clip, tie/untie, move floor/ceiling, snap to grid, and UV justify. `give_active_material(info)` gives a new brush the level's Active Material unless it names one or is a Cutout; every Draw, Polygon, Path and structure piece goes through it. Failable operations (hollow, clip, delete) return `HFOpResult` with actionable fix hints.
- `HFSnapSystem` provides centralized Grid, Vertex, Center, Edge-midpoint, and Perpendicular snapping. `_snap_point()` delegates to it. A drag asks `drag_grid_on()` and `drag_grid_step()`, through `LevelRoot.drag_grid_step()`, so the snap-invert hold (Ctrl) flips grid snap for a draw, a resize handle or a vertex drag, and `vertex_near_screen()` finds another brush's vertex for a vertex or handle drag to land on.
- Polygon and Path send their first point through the shared exact-surface raycast and `_snap_point()` pipeline. Subsequent points intersect the horizontal plane established by the first point before using the same snap pipeline.
- Polygon cuts a concave outline into convex brushes with `hf_polygon_split.gd`. Path lays its walls, trim, stairs and railings along `hf_path_sweep.gd`'s mitred corner cuts, samples a curved span with `hf_path_curve.gd`, and cuts a trim profile into convex bands with `hf_trim_profile.gd`.
- `HFNumberFormat`, `HFSizeLabels` and `HFSelectionReadout` print lengths to the grid step and draw the sizes at the cursor, on the selection and in Selection Info.
- `HFInputState` exposes `get_drag_dimensions()` for live W x H x D display during drag gestures.
- PendingCuts allow staging subtract operations before applying.

### Floor Paint (`HFPaintSystem` + `paint/*.gd`)
- Paint layers store grid occupancy in chunked bitsets with per-cell material_ids and blend weights (`blend_weights`, `blend_weights_2`, `blend_weights_3`).
- Layers optionally have heightmaps (Image FORMAT_RF) for vertex displacement.
- Geometry synthesis runs per dirty chunk:
  - Flat layers: greedy rectangles for floors, boundary edges + merged segments for walls.
  - Heightmap layers: per-cell displaced quads via `HFHeightmapSynth`, walls still flat.
- Per-chunk blend images drive a four-slot shader (`hf_blend.gdshader`).
- Blend tool paints material blend weights (slots B/C/D) on already-filled cells.
- Auto-connectors (`HFConnectorTool`) generate ramp/stair meshes between layers.
- Scatter (`HFScatterBrush`) places `MultiMeshInstance3D` content with height/slope filtering, a density preview and an instance budget.
- Stable IDs are used to reconcile generated nodes without churn.

### Face Materials + Surface Paint (`HFPaintSystem`)
- DraftBrush faces store material indices, UVs, and paint layers.
- Materials are managed by a shared palette (`MaterialManager`) with library persistence (Save Library and Load Library in the Paint tab, written as JSON resource paths).
- `HFPrototypeTextures` provides 150 built-in SVG textures (15 patterns x 10 colors) loadable via the "Refresh Prototypes" button for rapid material testing.
- Surface paint writes per-face weight images and updates previews.
- `FaceData.smoothing_group` makes faces shade as one surface; `hf_smoothing.gd` (`HFSmoothing`) works out the normals for every bake path and the preview. `FaceData.uv_group` links faces into one surface that edits keep aligned.
- The UV tools beside the UV Editor: the Face projection, Wrap (`hf_uv_wrap.gd`), the Texture Gizmo (`hf_texture_gizmo.gd`) and Apply Picked Look (Alt+T).

### Undo/Redo (`HFUndoHelper` + `HFStateSystem`)
- `HFUndoHelper.commit()` wraps all editor actions with state snapshot restore on undo.
- **Command collation**: pass a `collation_tag` for rapid operations (nudge, resize, paint). Consecutive actions with the same tag and same `full_state` scope within 1 second merge into one undo entry via `MERGE_ENDS`.
- **State-tracked scaffolding**: `capture_state()` / `restore_state()` covers brushes, entities, paint layers, TempFloor, and DefaultSun. All scaffolding created by **Create Starter** round-trips through undo/redo.

### Entity Definitions (`HFEntityDef`)
- Entity types and brush entity classes are data-driven via `hf_entity_def.gd`.
- Loaded from `entities.json` or built-in defaults (func_detail, func_wall, trigger_once, trigger_multiple), overlaid with `res://hammerforge_entities.json` when present.
- The dock brush entity dropdown and the point entity palette are both populated from that merged set, not hardcoded and not from separate files.

### Bake (`HFBakeSystem`)
- Assembles DraftBrushes (including generated flat paint geometry) into mesh output via CSG.
- Heightmap floor meshes are duplicated directly into baked output (bypass CSG) with trimesh collision.
- Supports single and chunked baking modes.
- Optional: mesh merging, LODs, lightmap UV2, navmesh, collision.
- `HFBakeSplit` (`hf_bake_split.gd`) splits each mesh by the Cast Shadows and Lightmap Scale its brushes ask for, on every bake path. A stair with Ramp collision gets a `RampCollision` body in place of its steps' collision, from `ramp_plan()`.
- Every round brush goes into the CSG as its own faces, and the smoothing is put back on what the boolean made.
- Post-processing carries tied brush entities (`func_detail`, `func_wall`, doors, buttons and triggers) and their I/O metadata into runtime output without treating them as structural CSG. A `func_clip` becomes a convex hull on a `StaticBody3D` with no mesh.
- Playtest export adds a player at the active spawn, preserves reparented world transforms, assigns recursive ownership to nested geometry/collision, and wires entity I/O when present.

### Entities (`HFEntitySystem`)
- Entities live under LevelRoot/Entities or `is_entity` meta.
- Entities are excluded from bake.
- Definitions are loaded from `addons/hammerforge/entities.json`.
- **Entity I/O**: Source-style input/output connections stored as `entity_io_outputs` meta. Fields: output_name, target_name, input_name, parameter, delay, fire_once. Managed via `add_entity_output()`, `remove_entity_output()`, `get_entity_outputs()`. Connections serialize with point and tied-brush entity info in `.hflevel`, bake output, and playtest exports.

### Cut Preview (`HFSubtractPreview`)
- `RefCounted` subsystem showing the live CSG cut between overlapping additive and subtractive DraftBrushes. It pairs only the brushes the bake cuts, by `HFBakeSystem.is_structural_brush()`: a brush entity is never cut, and a cutter tied to a class cuts nothing.
- Uses live CSG intersection meshes when available, with an AABB wireframe as a fast fallback. The wireframe is one shared unit-box outline from `HFOutlineUtil`, placed per box with `aabb_box_transform()`.
- Debounced rebuild (0.15s), MeshInstance3D pool (max 50 entries).
- Connects to `brush_added`, `brush_removed`, `brush_changed` signals for automatic updates.
- Toggle via `show_subtract_preview` export on LevelRoot. Persisted in state settings.

### Prefabs (`HFPrefab` and the prefab library)
- `HFPrefab` captures brush + entity selections with transforms relative to the group centroid.
- `capture_from_selection()` computes centroid, strips brush_id/group_id, stores infos as dictionaries.
- `instantiate()` assigns new IDs, offsets transforms by placement position, remaps entity I/O connections.
- `save_to_file()` / `load_from_file()` use JSON with `HFLevelIO` encoding for Godot types.
- The prefab library (`ui/hf_prefab_library.gd`, a dock section) scans `res://prefabs/` and provides drag-and-drop.
- Plugin handles `"hammerforge_prefab"` drop type with raycast + snap + undo/redo.
- Instance bookkeeping resolves brushes across DraftBrushes, PendingCuts, and CommittedCuts without adding frozen cutters to the editable brush cache. Point entities and tied brush entities resolve through `HFEntitySystem`. Missing recorded members produce warnings during removal and source updates.

### Tutorial Wizard (`HFTutorialWizard`)
- 2-step Draw → Test Level guide replacing the static welcome panel.
- Each step listens for a specific LevelRoot signal (brush_added, paint_layer_changed, entity_added, bake_finished).
- Optional validation (e.g. step 2 checks that the brush operation is SUBTRACTION).
- Progress persisted via `tutorial_step` in user prefs; resumes on editor restart.
- Dock `highlight_tab()` flashes the relevant tab on each step.

### Brush Operations (`HFBrushSystem` extended)
- **Hollow** (Ctrl+H): shells the brush into one wall per face, deletes the original. Any convex brush at any rotation, so a cylinder becomes a tube. Same `progressive_remainder` loop as carve, run against the brush's own inset planes.
- **Structure** (Ctrl+Shift+A): the Build tab's Structure section builds an **arch**, a flight of **stairs** (straight or turning at a landing), a **spiral staircase**, a **dome**, a **ring** or a **door frame** from a handful of numbers, one brush per piece, centred on the selection, or standing on the world origin when nothing is selected. A **Trim Run** is built along wall faces picked in Face Select instead. Named presets per type live in `res://hammerforge_presets/structure_presets.json` (`hf_structure_presets.gd`). The settings shown are the chosen builder's own: each describes itself through `HFGeneratorSchema` and the dock builds the controls from that.
- Every structure is created through `HFGeneratorSystem`, which records the settings so it can be rebuilt later from the same section — where you moved it to, and after telling you how many pieces a rebuild would overwrite.
- **Clip** (Shift+X): splits a brush along a plane through `HFConvexClip`. Any convex brush at any rotation; a piece that is still an axis-aligned box, one face on each side holding that side's four corners and no side under 0.1, is emitted as a BOX so it keeps its handles. Any other piece, a thinner one included, is CUSTOM and keeps its faces. **Clip to Face Plane** (Shift+Alt+X) cuts along a selected face's plane. Preserves material, entity class, visgroups, group ID.
- **Intersect** (Ctrl+Shift+I): keeps the volume 2+ selected brushes share, as one brush built from the first.
- **Merge** (Ctrl+Shift+M): combines 2+ selected brushes into a single brush. Applies full transform (rotation/scale) to face vertices, preserves per-brush materials via per-face material indices.
- **Rotate** (R / Shift+R) and **Flip** (Shift+M): `HFTransformSystem` turns and mirrors brushes and entities. Mirroring folds the reflection through a local axis so the basis keeps a positive determinant and geometry never bakes inside out. A negative scale set with Godot's own gizmo or typed into the Inspector is folded off the same way, so a brush cannot be left mirrored by either route; the brush stays exactly where it is and keeps the texturing on the same faces, and the scale field reads positive afterwards. **Reset Rotation** (Alt+R) clears a rotation, folding a quarter turn into `size` so nothing moves, and leaves any scale set with Godot's own gizmo alone. Hollow, clip and carve all work in a brush's own frame, so it is a tidying command rather than a prerequisite for any of them. **Apply Rotation and Scale** folds both into the brush's shape. **Mirror Copy** (Alt+M) adds mirrored copies across the ticked axes. **Offset** (Alt+G) moves by a typed amount, and **Pick Pivot** (Alt+P) sets the point they turn and mirror about (`hf_pivot_marker.gd` draws it).
- **Snap to Grid** (Ctrl+B): puts each brush's bounds corner, each entity, or in vertex mode each vertex on the grid.
- **Convert to Brushes** (`hf_brush_conversion.gd`): a convex mesh or a CSG primitive becomes a brush where it stands.
- **Grow and Shrink** (Ctrl+] and Ctrl+[, `hf_selection_grow.gd`): faces by shared edges, brushes by touching shapes.
- **Tie/Untie**: tag brushes as brush entity classes (`func_detail`, `func_wall`, `func_clip`, `func_door`, `func_button`, `door_basic`, `trigger_once`, `trigger_multiple`). Tagged brushes get color-coded overlays and may be excluded from structural bake.
- **Move to Floor/Ceiling** (Ctrl+Shift+F/C): moves the selection straight down or up as one piece until it touches a shown brush.
- **UV Justify**: fit/center/left/right/top/bottom/stretch/tile alignment for selected faces.

### Persistence (`HFFileSystem` + `HFStateSystem`)
- `HFStateSystem` captures and restores brush/entity/paint/settings state for undo/redo.
- `HFFileSystem` handles .hflevel save/load, .map import/export, and glTF export with threaded I/O. Queued writes run in request order, a malformed `.map` is refused before the level is touched, and a failed region sidecar fails the save.
- A `.hflevel` gets the same treatment. `HFStateSystem.restore_state()` checks the shape of a state before it clears anything, so a truncated or hand-edited file leaves the level as it was and says why rather than emptying it and then failing. One brush or entity entry it cannot read is skipped and counted; the load goes ahead.
- See [Data Portability](HammerForge_Data_Portability.md) for fidelity boundaries and save-safety behaviour.

## High-Level Flow
1. `plugin.gd` owns the EditorPlugin lifecycle and delegates input to focused `plugin_*.gd` adapters. The coordinator keeps typed `LevelRoot` and dock references; the static adapters receive the plugin as `Object` to avoid a circular script dependency.
2. `LevelRoot` delegates to the appropriate subsystem:
   - Draw tool -> `HFDragSystem` (drag lifecycle + preview)
   - Extrude Up/Down -> `HFExtrudeTool` (face pick + drag + commit)
   - Select tool -> `HFBrushSystem` (picking + selection)
   - Paint (floor) -> `HFPaintSystem` -> `HFPaintTool` (layers + synth + reconcile)
   - Paint (surface) -> `HFPaintSystem` -> `SurfacePaint` (per-face weight images)
   - Face selection -> `HFBrushSystem` -> `FaceSelector`
   - Bake -> `HFBakeSystem` (CSG assembly + mesh output)
   - Save/load -> `HFFileSystem` (threaded I/O)
3. State changes go through `HFStateSystem` for undo/redo capture.

## Testing Checklist
- Create and resize draft brushes (Draw tool).
- Extrude Up (U) and Extrude Down (J) on brush faces; confirm new brushes appear with correct orientation.
- Right-click during extrude to cancel; confirm preview is removed.
- Apply/clear/commit subtract cuts.
- Verify pending cuts appear orange-red, applied cuts turn standard red.
- Bake (with and without chunking).
- Enable Paint Mode and test Paint tab → Floor Paint section Brush/Erase/Line/Rect/Bucket.
- Switch brush shape (Square/Circle) and verify radius fills correctly for each.
- Test paint tool shortcuts: B/E/R/L/K in Paint Mode.
- Verify live paint preview while dragging.
- Switch paint layers and ensure isolation.
- Enable Region Streaming, paint across regions, and verify `.hfr` files are created on save.
- Import a heightmap (PNG/EXR) or generate procedural noise on a paint layer.
- Verify displaced mesh appears under `Generated/HeightmapFloors`.
- Adjust Height Scale and Layer Y spinboxes; confirm mesh updates.
- Select Blend tool, choose Blend Slot B/C/D, paint blend weights on filled cells; verify four-slot shader blending.
- Bake with heightmap floors and confirm baked output includes heightmap meshes with trimesh collision.
- Save and load .hflevel with heightmap data; verify heightmap, material_ids, blend_weights, and terrain slot settings persist.
- Click Refresh Prototypes in Paint tab → Materials section; confirm 150 prototype textures appear in the palette.
- Assign a prototype texture to faces and verify preview updates.
- Create a material resource (.tres/.material) in `materials/` and add it to the palette.
- Enable Face Select Mode and assign materials to faces.
- Edit UVs and ensure preview updates.
- Surface paint on a face with two layers and verify blending (Paint Target = Surface).
- Toggle Use Face Materials and compare bake output.
- Drag entities from the palette and check selection/exclusion from bake.
- Verify shortcut HUD updates when switching tools/modes.
- Verify tooltips appear on all dock controls.
- Verify selection count appears in status bar.
- Trigger a bake failure and confirm red error message with auto-clear.
- Click **Create Starter** in the empty-state banner; confirm floor, sun, and spawn appear. Undo/redo and verify all three round-trip.
- Run **Test Level** after Create Starter; confirm playtest lighting matches editor sun angle.

## CI
Run `python tools/run_local_checks.py` locally, as [CONTRIBUTING.md](https://github.com/saworbit/hammerforge/blob/main/CONTRIBUTING.md#running-checks-locally) describes. CI runs the same checks on push and PR via `.github/workflows/ci.yml`.

## Diagnostics
- Enable Debug Logs in the Test tab → Settings section for runtime tracing.
- Capture exit-time errors with the PowerShell command in [CONTRIBUTING.md](https://github.com/saworbit/hammerforge/blob/main/CONTRIBUTING.md#errors-printed-as-the-editor-closes).

## Resolved Issues
- ~~Viewport drag-marquee selection is disabled.~~ Marquee selection for brushes, entities, and faces was added in the Improved Selection & Multi-Select wave.
- ~~Multi-select can cap at 2 items in the viewport.~~ Multi-select works for arbitrary counts via marquee or Ctrl+Click.

## Next Steps
- Additional import/export pipelines
- The rest is in the [Roadmap](https://github.com/saworbit/hammerforge/blob/main/ROADMAP.md).
