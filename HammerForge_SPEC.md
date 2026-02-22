# HammerForge Spec

Last updated: February 22, 2026

This document describes HammerForge's architecture and data flow.

## Goals
- Fast in-editor greyboxing with brush workflows.
- Editor responsiveness by avoiding live CSG.
- Reliable bake pipeline and clean data model.
- Modular codebase with clear separation of concerns.

## Architecture

HammerForge uses a coordinator + subsystems pattern. `LevelRoot` is a thin coordinator that owns all container nodes, exported properties, and signals, and delegates work to 10 `RefCounted` subsystem classes. Each subsystem receives a reference to `LevelRoot` in its constructor.

### Signals
- `bake_started` -- emitted when a bake begins.
- `bake_progress(value: float, label: String)` -- emitted during bake with progress 0..1 and a short label.
- `bake_finished(success: bool)` -- emitted when a bake completes.
- `grid_snap_changed(value: float)` -- emitted when grid snap is updated.

### Core Scripts

| Script | Role |
|--------|------|
| `plugin.gd` | EditorPlugin entry point, input routing, undo/redo |
| `level_root.gd` | Thin coordinator: containers, exports, signals, delegates to subsystems |
| `dock.gd` + `dock.tscn` | UI dock: tool state, materials palette, paint controls |
| `input_state.gd` | Drag/paint/extrude state machine (`Mode` enum: IDLE, DRAG_BASE, DRAG_HEIGHT, SURFACE_PAINT, EXTRUDE) |
| `hf_extrude_tool.gd` | Extrude Up/Down tool (face pick + drag to extend brushes) |
| `brush_instance.gd` | DraftBrush node (authored geometry) |
| `baker.gd` | CSG -> mesh bake pipeline |
| `face_data.gd` | Per-face materials, UVs, and paint layers |
| `material_manager.gd` | Shared materials palette |
| `face_selector.gd` | Raycast face selection helper |
| `surface_paint.gd` | Per-face surface paint tool |
| `uv_editor.gd` + `uv_editor.tscn` | UV editing dock control |

### Subsystems (`addons/hammerforge/systems/`)

| Subsystem | class_name | Responsibility |
|-----------|------------|----------------|
| `hf_grid_system.gd` | `HFGridSystem` | Editor grid setup, visibility, transform, axis-plane intersection |
| `hf_entity_system.gd` | `HFEntitySystem` | Entity definitions, placement, capture/restore |
| `hf_brush_system.gd` | `HFBrushSystem` | Brush CRUD, picking, pending/committed cuts, materials, face selection |
| `hf_drag_system.gd` | `HFDragSystem` | Drag lifecycle, preview management, axis locking, height computation. Owns `HFInputState` |
| `hf_bake_system.gd` | `HFBakeSystem` | Bake orchestration (single/chunked), CSG assembly, navmesh, collision |
| `hf_paint_system.gd` | `HFPaintSystem` | Floor paint input, surface paint, paint layer CRUD, face selection |
| `hf_state_system.gd` | `HFStateSystem` | State capture/restore, settings, paint layer serialization |
| `hf_file_system.gd` | `HFFileSystem` | .hflevel save/load, .map import/export, glTF export, threaded I/O |
| `hf_validation_system.gd` | `HFValidationSystem` | Validation, dependency checks, auto-fix helpers |
| `hf_visgroup_system.gd` | `HFVisgroupSystem` | Visgroups (visibility groups), brush/entity grouping |

### Other Modules

- `addons/hammerforge/paint/*`: floor paint grid, layers, tools, inference, geometry synthesis, reconciliation, heightmap integration
- `addons/hammerforge/paint/hf_region_manager.gd`: region streaming helpers (region bounds, radius, index)
- `addons/hammerforge/hflevel_io.gd`: variant encoding/decoding for .hflevel format
- `addons/hammerforge/map_io.gd`: .map file import/export
- `addons/hammerforge/prefab_factory.gd`: advanced shape generation (wedges, prisms, platonic solids, etc.)

### Paint Subsystem (`addons/hammerforge/paint/`)

| Script | class_name | Responsibility |
|--------|------------|----------------|
| `hf_paint_grid.gd` | `HFPaintGrid` | Grid storage, coordinate conversion |
| `hf_paint_layer.gd` | `HFPaintLayer` | Layer data: bitset + material_ids + blend_weights (+ _2/_3) + heightmap |
| `hf_paint_layer_manager.gd` | `HFPaintLayerManager` | Multi-layer management, active layer |
| `hf_paint_tool.gd` | `HFPaintTool` | Paint input, stroke handling, routes to appropriate synth |
| `hf_stroke.gd` | `HFStroke` | Stroke data (cells, timing, tool type, brush shape) |
| `hf_geometry_synth.gd` | `HFGeometrySynth` | Greedy meshing for flat floors/walls |
| `hf_heightmap_synth.gd` | `HFHeightmapSynth` | Heightmap-displaced mesh generation (SurfaceTool) |
| `hf_heightmap_io.gd` | `HFHeightmapIO` | Load/generate/serialize heightmaps (base64 PNG) |
| `hf_generated_model.gd` | `HFGeneratedModel` | Data model: FloorRect, WallSeg, HeightmapFloor |
| `hf_reconciler.gd` | `HFGeneratedReconciler` | Stable-ID node reconciliation (floors, walls, heightmap floors) |
| `hf_connector_tool.gd` | `HFConnectorTool` | Ramp/stair mesh generation between layers |
| `hf_foliage_populator.gd` | `HFFoliagePopulator` | MultiMeshInstance3D procedural scatter |
| `hf_blend.gdshader` | -- | Four-slot blend shader (UV2 blend map, RGB weights) |
| `hf_inference_engine.gd` | `HFInferenceEngine` | Inference for paint operations |

## Node Hierarchy
```
LevelRoot (Node3D)
- DraftBrushes
- PendingCuts
- CommittedCuts
- MaterialManager
- PaintLayers
- SurfacePaint
- Generated
  - Floors
  - Walls
  - HeightmapFloors
- Entities
- BakedGeometry
```

## Visgroups + Grouping

### Visgroups (Visibility Groups)
- Named groups (e.g. "walls", "detail") with per-group show/hide.
- Membership stored on nodes via `node.set_meta("visgroups", PackedStringArray)`. A node can belong to multiple visgroups.
- A node in ANY hidden visgroup becomes hidden (Hammer semantics). Nodes not in any visgroup are always visible.
- `HFVisgroupSystem` manages CRUD, membership, visibility refresh, and serialization.
- Visgroups persist in `.hflevel` via `capture_visgroups()` / `restore_visgroups()`.

### Grouping
- Persistent groups that select and move together.
- Single group per node via `node.set_meta("group_id", group_name)`.
- Clicking a grouped node expands selection to all group members.
- Ctrl+G groups selection, Ctrl+U ungroups.
- Groups persist in `.hflevel` via `capture_groups()` / `restore_groups()`.

## Texture Lock
- When `texture_lock` is enabled (default), moving or resizing a brush automatically compensates face UV offset and scale.
- Per-projection-axis math in `face_data.gd:adjust_uvs_for_transform()`:
  - PLANAR_X: projects (z, y), PLANAR_Y: projects (x, z), PLANAR_Z: projects (x, y).
  - BOX_UV resolves to the planar axis matching the face normal.
  - CYLINDRICAL is skipped (complex, future enhancement).
- Position compensation: `uv_offset -= projected_delta * uv_scale`.
- Size compensation: `uv_scale *= inverse_size_ratio` per projection axis.
- Hook in `hf_brush_system.gd:set_brush_transform_by_id()` captures old transform, applies new, then adjusts UVs.

## Cordon (Partial Bake)
- Restricts bake to an AABB region. Brushes outside the cordon are skipped.
- Properties on LevelRoot: `cordon_enabled: bool`, `cordon_aabb: AABB`.
- Filter applied in `hf_bake_system.gd`: `collect_chunk_brushes()`, `append_brush_list_to_csg()`, `_append_face_bake_container()`.
- Helper `_brush_in_cordon()` computes brush world AABB and tests intersection with `cordon_aabb`.
- "Set from Selection" computes merged AABB of selected brushes + 1.0 margin.
- Yellow wireframe visualization via ImmediateMesh (12 AABB edge lines, unshaded, no depth test).
- Cordon settings persist in `.hflevel`.

## Brush Workflow
- Draw creates DraftBrush nodes in DraftBrushes.
- Subtract brushes are staged in PendingCuts until Apply Cuts.
- Extrude Up/Down picks a face via `FaceSelector`, creates a preview brush along the face normal, and commits a new DraftBrush on release. Uses `HFExtrudeTool` (RefCounted).
- Bake builds a temporary CSG tree from DraftBrushes + CommittedCuts and outputs BakedGeometry. If cordon is enabled, only brushes intersecting the cordon AABB are included.
- Undo/redo actions prefer brush IDs and state snapshots over long-lived Node references.

## Floor Paint System

Data
- Grid -> Layer -> Chunked storage (bitset + material_ids + blend_weights + blend_weights_2 + blend_weights_3).
- Each layer optionally has a `heightmap: Image` and `height_scale: float`.
- Paint layers are stored under PaintLayers.

Tools
- Brush, Erase, Rect, Line, Bucket, Blend (enum `HFStroke.Tool`, values 0-5).
- Blend tool writes per-cell blend weights to slots B/C/D on already-filled cells.

Brush Shape
- Square: fills every cell in the radius range (full box).
- Circle: clips corners using Euclidean distance check.

Generation (flat layers -- no heightmap)
- Floors: greedy rectangle merge -> DraftBrush boxes.
- Walls: boundary edges + merged segments -> DraftBrush boxes.

Generation (heightmap layers)
- Floors: per-cell displaced quads via `HFHeightmapSynth` -> ArrayMesh -> MeshInstance3D.
- Per-chunk blend image (Image FORMAT_RGBA8) built from cell blend weights (RGB = slots B/C/D).
- Blend shader (`hf_blend.gdshader`) mixes four slots via UV2-sampled blend map (slot A implicit).
- Walls: still use flat `HFGeometrySynth` (no heightmap displacement on walls).

Reconciliation
- Stable IDs for generated geometry (floors, walls, heightmap floors).
- Dirty chunk scoping to avoid unnecessary churn.
- `Generated/HeightmapFloors` container for MeshInstance3D nodes.

Auto-Connectors
- `HFConnectorTool` generates ramp or stair ArrayMesh between two cells on different layers.
- Ramp: sloped quad strip. Stairs: horizontal treads + vertical risers.

Foliage Populator
- `HFFoliagePopulator` scatters instances via MultiMeshInstance3D.
- Filters by height range, slope threshold; configurable density, scale, rotation, seed.

## Region Streaming (Floor Paint)
- Floor paint chunks are grouped into regions (default 512x512 cells).
- Streaming loads regions within a radius of the cursor and unloads distant regions.
- Region files (`.hfr`) store per-region chunk data to keep `.hflevel` small.
- Region index is stored in the `.hflevel` state under `terrain_regions`.

## Entities
- Entities live under LevelRoot/Entities or are tagged `is_entity`.
- Entities are selectable but excluded from bake.
- Definitions come from `addons/hammerforge/entities.json`.

## Persistence (.hflevel)
- Stores brushes, entities, level settings, materials palette, and paint layers.
- Brush records include face data (materials, UVs, paint layers), visgroup membership, and group_id.
- Entity records include visgroup membership and group_id.
- Paint layers include grid settings, chunk size, bitset data, `material_ids`, `blend_weights` (+ _2/_3), and terrain slot settings.
- Optional per-layer: `heightmap_b64` (base64 PNG), `height_scale`. Missing keys = no heightmap (backward-compatible).
- Level settings include `texture_lock`, `cordon_enabled`, `cordon_aabb_pos`, `cordon_aabb_size`.
- Visgroup definitions and group registry stored in state via `capture_visgroups()` / `capture_groups()`.

## Bake Pipeline
- Temporary CSG tree for DraftBrushes (including generated flat floors/walls).
- Heightmap floor meshes are duplicated directly into baked output (bypass CSG) with trimesh collision shapes.
- Chunked baking (default `bake_chunk_size = 32`): groups brushes by grid coordinate, bakes each chunk independently.
- Owner assignment uses `_assign_owner_recursive()` after the baked container is added to the tree (avoids premature owner errors during chunked bake).
- Optional mesh merging, LODs, lightmap UV2, navmesh.
- Optional face-material bake (per-face materials, no CSG).
- Collision uses Add brushes only.
- Navmesh defaults: `cell_height = 0.25` (matches Godot NavigationServer3D map default).

## Face Materials + Surface Paint
Face data is stored per DraftBrush face with material assignment, UV projection, and optional paint layers.
Surface paint is a per-face splat system. It updates preview materials and can be baked using the face-material bake option.

## Data Flow

```
plugin.gd (input)
  -> level_root.gd (coordinator)
    -> hf_drag_system.gd    (draw tool: drag lifecycle + preview)
    -> hf_extrude_tool.gd   (extrude up/down: face pick + drag + commit)
    -> hf_brush_system.gd   (brush CRUD, pending cuts, materials)
    -> hf_paint_system.gd   (floor + surface paint)
    -> hf_bake_system.gd    (CSG assembly + mesh output)
    -> hf_state_system.gd   (undo/redo state capture)
    -> hf_file_system.gd    (persistence, threaded I/O)
    -> hf_grid_system.gd    (editor grid)
    -> hf_entity_system.gd  (entity placement)
    -> hf_visgroup_system.gd (visgroups + grouping)
```

All public methods on `LevelRoot` are thin one-line delegates to the appropriate subsystem. This preserves the existing API so `plugin.gd` and `dock.gd` call `root.bake()`, `root.begin_drag()`, etc. without change.

## Input State Machine

`input_state.gd` (`HFInputState`) replaces 18+ loose state variables with an explicit `Mode` enum:

| Mode | Description |
|------|-------------|
| `IDLE` | No active operation |
| `DRAG_BASE` | Drawing the base rectangle of a new brush |
| `DRAG_HEIGHT` | Setting the height of a new brush |
| `SURFACE_PAINT` | Actively painting on a brush face |
| `EXTRUDE` | Actively extruding a face up or down |

Transitions: `begin_drag()` -> `advance_to_height()` -> `end_drag()` / `cancel()`. Extrude: `begin_extrude()` -> `end_extrude()` / `cancel()`.

## Editor UX
- Theme-aware dock styling with comprehensive tooltips on all controls.
- Context-sensitive shortcut HUD overlay (8 views: draw idle, dragging base, adjusting height, select, extrude idle, extruding active, floor paint, surface paint). Displays current axis lock. Updated via `plugin.gd` -> `shortcut_hud.gd:update_context()`.
- Paint tool keyboard shortcuts (B/E/R/L/K) active when Paint Mode is enabled.
- Selection count in status bar, updated on every selection change.
- Color-coded status bar: errors in red (auto-clear 5s), warnings in yellow, success messages auto-clear after 3s.
- Bake progress bar with chunk status updates.
- Pending subtract brushes rendered in orange-red with high emission (`_make_pending_cut_material()`), visually distinct from applied cuts (standard red via `_make_brush_material()`).
- Shader-based editor grid with follow mode.
- Grouping shortcuts: Ctrl+G (group selection), Ctrl+U (ungroup).
- Direct typed calls between plugin/dock/LevelRoot (no duck-typing).

## Validation + Diagnostics
- Validate Level scans for missing materials, zero-size brushes, invalid face indices, and paint layers without grids.
- Auto-fix clears invalid face selections, resets invalid face material indices, and rebuilds missing layer grids.
- Bake Dry Run reports counts and chunking without generating geometry.
- Performance panel shows active brush count, paint memory, bake chunk count, and last bake time.

## Testing

Unit tests use the [GUT](https://github.com/bitwes/Gut) framework and run headless via CI.

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `test_visgroup_system.gd` | 18 | Visgroup CRUD, visibility toggle, membership, round-trip serialization |
| `test_grouping.gd` | 9 | Group creation, meta storage, ungroup, regroup, serialization |
| `test_texture_lock.gd` | 10 | UV offset/scale compensation for PLANAR_X/Y/Z, BOX_UV, CYLINDRICAL |
| `test_cordon_filter.gd` | 10 | AABB intersection, cordon-filtered collection, chunk_coord utility |

Tests use root shim scripts (dynamically created GDScript) to provide the LevelRoot interface without circular preload dependencies. Configuration in `.gutconfig.json`.
