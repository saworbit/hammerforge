# HammerForge Spec

Last updated: March 23, 2026

This document describes HammerForge's architecture and data flow.

## Goals
- Fast in-editor greyboxing with brush workflows.
- Editor responsiveness by avoiding live CSG.
- Reliable bake pipeline and clean data model.
- Modular codebase with clear separation of concerns.

## Architecture

HammerForge uses a coordinator + subsystems pattern. `LevelRoot` is a thin coordinator that owns all container nodes, exported properties, and signals, and delegates work to 10 `RefCounted` subsystem classes. Each subsystem receives a reference to `LevelRoot` in its constructor.

### Signals (Central Registry)
All signals are defined on `LevelRoot`. Subsystems emit them via `root.<signal>.emit(...)`. UI and other consumers subscribe instead of polling.

| Signal | Description |
|--------|-------------|
| `bake_started` | Emitted when a bake begins |
| `bake_progress(value, label)` | Progress 0..1 with short label during bake |
| `bake_finished(success)` | Emitted when a bake completes |
| `grid_snap_changed(value)` | Grid snap updated |
| `brush_added(brush_id)` | A brush was created |
| `brush_removed(brush_id)` | A brush was deleted |
| `brush_changed(brush_id)` | A brush was modified (transform, material, etc.) |
| `entity_added(node)` | An entity was added |
| `entity_removed(node)` | An entity was removed |
| `selection_changed(brush_ids)` | Brush selection changed |
| `paint_layer_changed(layer_index)` | A paint layer was modified |
| `state_saved()` | `.hflevel` save completed |
| `state_loaded()` | `.hflevel` load completed |
| `autosave_failed(error_message)` | Threaded autosave write failed |

### Core Scripts

| Script | Role |
|--------|------|
| `plugin.gd` | EditorPlugin entry point, input routing, undo/redo, sticky LevelRoot discovery |
| `level_root.gd` | Thin coordinator: containers, exports, signals, delegates to subsystems |
| `dock.gd` + `dock.tscn` | UI dock (4 tabs: Brush, Paint, Entities, Manage), collapsible sections, tool state |
| `ui/collapsible_section.gd` | Reusable `HFCollapsibleSection` toggle-header VBoxContainer |
| `input_state.gd` | Drag/paint/extrude state machine (`Mode` enum: IDLE, DRAG_BASE, DRAG_HEIGHT, SURFACE_PAINT, EXTRUDE) |
| `hf_extrude_tool.gd` | Extrude Up/Down tool (face pick + drag to extend brushes) |
| `brush_instance.gd` | DraftBrush node (authored geometry) |
| `baker.gd` | CSG -> mesh bake pipeline |
| `face_data.gd` | Per-face materials, UVs, and paint layers |
| `material_manager.gd` | Shared materials palette (+ library persistence, usage tracking) |
| `hf_entity_def.gd` | Data-driven entity definition system (JSON + built-in defaults) |
| `hf_gesture.gd` | Gesture tracker base class (update/commit/cancel pattern) |
| `undo_helper.gd` | Undo/redo helper with command collation support |
| `face_selector.gd` | Raycast face selection helper |
| `surface_paint.gd` | Per-face surface paint tool |
| `uv_editor.gd` + `uv_editor.tscn` | UV editing dock control |
| `hf_keymap.gd` | Customizable keyboard shortcuts (JSON load/save, action → binding mapping) |
| `hf_user_prefs.gd` | Cross-session user preferences (`user://hammerforge_prefs.json`) |

### Subsystems (`addons/hammerforge/systems/`)

| Subsystem | class_name | Responsibility |
|-----------|------------|----------------|
| `hf_grid_system.gd` | `HFGridSystem` | Editor grid setup, visibility, transform, axis-plane intersection |
| `hf_entity_system.gd` | `HFEntitySystem` | Entity definitions, placement, capture/restore, Entity I/O connections |
| `hf_brush_system.gd` | `HFBrushSystem` | Brush CRUD, picking, pending/committed cuts, materials, face selection, hollow, clip, tie/untie. O(1) brush ID cache and material instance cache |
| `hf_drag_system.gd` | `HFDragSystem` | Drag lifecycle, preview management, axis locking, height computation. Owns `HFInputState` |
| `hf_bake_system.gd` | `HFBakeSystem` | Bake orchestration (single/chunked), CSG assembly, navmesh, collision |
| `hf_paint_system.gd` | `HFPaintSystem` | Floor paint input, surface paint, paint layer CRUD, face selection |
| `hf_state_system.gd` | `HFStateSystem` | State capture/restore, settings, paint layer serialization, transactions (begin/commit/rollback) |
| `hf_file_system.gd` | `HFFileSystem` | .hflevel save/load, .map import/export, glTF export, threaded I/O, autosave failure reporting |
| `hf_validation_system.gd` | `HFValidationSystem` | Validation, dependency checks, auto-fix helpers |
| `hf_visgroup_system.gd` | `HFVisgroupSystem` | Visgroups (visibility groups), brush/entity grouping |

### Other Modules

- `addons/hammerforge/ui/collapsible_section.gd`: `HFCollapsibleSection` -- reusable collapsible section with toggle-header button
- `addons/hammerforge/highlight.gdshader`: selection highlight shader (wireframe, unshaded, alpha)
- `addons/hammerforge/hf_prototype_textures.gd`: `HFPrototypeTextures` -- 150 built-in SVG textures (15 patterns x 10 colors) with static catalog API
- `addons/hammerforge/textures/prototypes/`: embedded SVG texture library for greyboxing
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
| `hf_paint_tool.gd` | `HFPaintTool` | Paint input, stroke handling, routes to appropriate synth. Shared `build_heightmap_model()` for heightmap reconciliation |
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
- **Hollow** (Ctrl+H): converts a solid brush into 6 wall brushes with configurable thickness.
- **Clip** (Shift+X): splits a brush along an axis-aligned plane into two new brushes. Preserves material, brush entity class, visgroups, and group ID.
- **Move to Floor/Ceiling** (Ctrl+Shift+F/C): raycasts against other brush AABBs to snap selection vertically.
- **Numeric input**: type exact dimensions during drag or extrude (Enter applies, Backspace edits).
- **UV Justify**: fit/center/left/right/top/bottom alignment modes for selected faces.
- Bake builds a temporary CSG tree from DraftBrushes + CommittedCuts and outputs BakedGeometry. If cordon is enabled, only brushes intersecting the cordon AABB are included. Brush entity classes `func_detail` and `trigger_*` are excluded from structural bake.
- Undo/redo actions prefer brush IDs and state snapshots over long-lived Node references.
- **Command collation**: `HFUndoHelper` supports a `collation_tag` parameter. Consecutive actions with the same tag and same `full_state` scope within 1 second merge into one undo entry via `MERGE_ENDS` (nudge, resize, paint). Mismatched `full_state` breaks the collation window.
- **Transactions**: `HFStateSystem` provides `begin_transaction()` / `commit_transaction()` / `rollback_transaction()` for atomic multi-step operations. The transaction captures a state snapshot on begin and restores it on rollback.

## Entity Definitions

Entity types and brush entity classes are data-driven via `HFEntityDef` (`hf_entity_def.gd`):
- Loaded from `entities.json` at `entity_defs_path` (default: `res://addons/hammerforge/entities.json`).
- Falls back to built-in defaults (func_detail, func_wall, trigger_once, trigger_multiple).
- Each definition has: `classname`, `description`, `color`, `is_brush_entity`, `properties`, `scene_path`.
- `HFEntityDef.load_definitions(path)` returns `Array[HFEntityDef]`.
- `filter_brush_entities()` / `filter_point_entities()` for filtering by type.
- Dock brush entity class dropdown is populated from definitions, not hardcoded.
- **Planned: Declarative property forms** — the `properties` array on each definition will support typed entries (e.g., `{name, type, default, label}`) that auto-generate dock controls when an entity is selected. Inspired by QuArK's `:form` system where `Typ` fields determine UI widgets. This would let users define custom entity types with editable properties entirely through JSON.

## Gesture Tracker

`HFGesture` (`hf_gesture.gd`) is a base class for encapsulated input gestures:
- Holds `root`, `camera`, `start_position`, `current_position`, `numeric_buffer`.
- Subclasses override `update(event)`, `commit()`, `cancel()`.
- `handle_numeric_key(keycode)` routes digit/period/backspace/enter to the numeric buffer.
- New tools should subclass `HFGesture` to be self-contained (own state, no global mode enum needed).

## Material Manager

`MaterialManager` (`material_manager.gd`) manages the shared material palette:
- **Library persistence**: `save_library(path)` / `load_library(path)` serialize material resource paths to JSON.
- **Usage tracking**: `record_usage()` / `release_usage()` / `rebuild_usage()` track which materials are used by brushes.
- **Cleanup**: `find_unused_materials()` returns palette materials not used by any brush.
- **Prototype textures**: `HFPrototypeTextures.load_all_into(manager)` batch-loads 150 built-in SVG textures as `StandardMaterial3D` resources. The dock exposes this via the "Load Prototypes" button in the Paint tab → Materials section.

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

### Entity I/O (Input/Output Connections)
- Source-style trigger/target system modeled after Hammer/Source entity I/O.
- Connections stored as `entity_io_outputs` meta (Array of Dictionaries) on entity nodes.
- Each connection: `{output_name, target_name, input_name, parameter, delay, fire_once}`.
- `HFEntitySystem` provides: `add_entity_output()`, `remove_entity_output()`, `get_entity_outputs()`, `find_entities_by_name()`, `get_all_connections()`.
- `find_entities_by_name()` searches both `entities_node` and `draft_brushes_node` for target resolution.
- I/O connections are serialized with entity info in `.hflevel` saves and undo/redo state via `capture_entity_info()` / `restore_entity_from_info()`.
- Dock UI: collapsible "Entity I/O" section in Entities tab with fields for Output, Target, Input, Parameter, Delay, Fire Once. Add/Remove buttons and connection ItemList. Auto-refreshes on entity selection change.

### Brush Entity Classes
- Brushes can be tagged with a `brush_entity_class` meta: `func_detail`, `func_wall`, `trigger_once`, `trigger_multiple`.
- Tie/Untie via `HFBrushSystem.tie_brushes_to_entity()` / `untie_brushes_from_entity()`.
- `func_detail` and `trigger_*` brushes are excluded from structural bake via `_is_structural_brush()` in `HFBakeSystem`.
- Visual indicators: `func_detail` = cyan tint, `trigger_*` = orange tint (semi-transparent overlay in `brush_instance.gd`).

## Persistence (.hflevel)
- Stores brushes, entities, level settings, materials palette, and paint layers.
- Brush records include face data (materials, UVs, paint layers), visgroup membership, group_id, and `brush_entity_class`.
- Entity records include visgroup membership, group_id, and `io_outputs` (Entity I/O connections).
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

`plugin.gd`'s `_forward_3d_gui_input()` is a ~50-line dispatcher that routes to focused handlers: `_handle_paint_input()`, `_handle_keyboard_input()`, `_handle_rmb_cancel()`, `_handle_select_mouse()`, `_handle_extrude_mouse()`, `_handle_draw_mouse()`, `_handle_mouse_motion()`. A shared `_get_nudge_direction()` helper is used by both `_forward_3d_gui_input()` and `_shortcut_input()`.

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

## Dock UI
The dock uses 4 tabs with collapsible sections for visual hierarchy:

| Tab | Contents |
|-----|----------|
| **Brush** | Shape, size, grid snap, quick snap presets, material picker, operation mode (Add/Sub), texture lock |
| **Paint** | 7 collapsible sections: Floor Paint, Heightmap, Blend & Terrain, Regions, Materials (with Load Prototypes), UV Editor, Surface Paint |
| **Entities** | Entity palette with drag-and-drop, Create DraftEntity, Entity Properties, Entity I/O connections (collapsible sections) |
| **Manage** | Bake, Actions (floor/cuts/clear), File, Presets, History, Settings, Performance, plus Visgroups & Cordon (inserted programmatically) |

- **Brush tab** includes contextual **Selection Tools** section (hollow, clip, move, tie, duplicator) visible when brushes are selected.
- Tab contents built programmatically in `_build_paint_tab()`, `_build_manage_tab()`, and `_build_selection_tools_section()` using `HFCollapsibleSection`.
- Collapsible sections have HSeparator, 4px indented content, and persisted collapsed state. All 18 sections tracked in `_all_sections` dict.
- "No LevelRoot" banner and autosave warning defined in dock.tscn.
- Compact toolbar: single-char labels (D, S, +, -, P, ▲, ▼) with descriptive tooltips. VSeparator before extrude buttons.
- **Signal-driven sync**: Setting controls push values via `toggled`/`value_changed` signals. Paint layers, materials, surface paint, and face selection sync instantly via `paint_layer_changed`, `material_list_changed`, `face_selection_changed`, `selection_changed` signals. Initial sync on root connect populates materials and surface paint. Perf panel throttled to every 30 frames; disabled hints are flag-driven. Form label widths standardized to 70px.

## LevelRoot Discovery
- `plugin.gd` uses sticky `active_root`: selecting non-LevelRoot nodes does not null the reference.
- `_handles()` returns true for any node when a LevelRoot exists in the scene (deep recursive search).
- `_edit()` only nulls `active_root` when the root node is removed from the tree.
- `dock.gd` mirrors the sticky pattern and uses `_find_level_root_in()` for deep tree search.

## Customizable Keymaps

All keyboard shortcuts are data-driven via `HFKeymap` (`hf_keymap.gd`). Plugin loads bindings from `user://hammerforge_keymap.json` (or built-in defaults). Each binding maps an action name (e.g. `"hollow"`) to `{keycode, ctrl, shift, alt}`. Plugin uses `_keymap.matches(action, event)` instead of hardcoded `KEY_*` checks. Toolbar labels and tooltips pull display strings from the keymap.

## User Preferences

`HFUserPrefs` (`hf_user_prefs.gd`) stores cross-session application-scoped preferences in `user://hammerforge_prefs.json`. Separate from per-level settings on LevelRoot. Includes: default grid snap, autosave interval, recent files (max 10, MRU), collapsed section states, last tool ID, HUD visibility.

## Tag-Based Invalidation

LevelRoot maintains dirty tags for selective reconciliation:
- `tag_brush_dirty(brush_id)` — marks a specific brush as needing rebuild.
- `tag_paint_dirty(chunk_coord)` — marks a paint chunk as dirty.
- `tag_full_reconcile()` — marks entire scene for full rebuild (structural changes like hollow/clip).
- `consume_dirty_tags()` — returns and clears all tags (called by reconciler).

Brush system calls these on create/delete/transform/hollow/clip. Tags are guarded with `has_method()` for test shim compatibility.

## Signal Batching

LevelRoot supports batched signal emission for multi-brush operations:
- `begin_signal_batch()` / `end_signal_batch()` with depth-counted nesting.
- During batch, signals are queued. On flush, brush add/remove/change signals coalesce into a single `selection_changed` emission.
- Transactions auto-batch: `begin_transaction()` calls `begin_signal_batch()`; `commit_transaction()` calls `end_signal_batch()`.
- `discard_signal_batch()` drops queued signals on rollback.

## Tool Poll System

`HFEditorTool` exposes `can_activate(root)` and `get_poll_fail_reason(root)`. `HFGesture` exposes `can_start(root)`. Dock uses these to gray out buttons and set tooltips. Plugin guards keyboard shortcuts with early-exit when poll fails (e.g. Hollow requires selection).

## Declarative Tool Settings

External tools expose `get_settings_schema()` → Array of `{name, type, label, default, min, max, options}`. Supported types: `bool`, `int`, `float`, `string`, `enum`, `color`. Dock `rebuild_tool_settings()` auto-generates controls from the schema. `get_setting(key)` / `set_setting(key, val)` for storage.

## Editor UX
- Theme-aware dock styling with comprehensive tooltips on all controls.
- Context-sensitive shortcut HUD overlay (8 views: draw idle, dragging base, adjusting height, select, extrude idle, extruding active, floor paint, surface paint). Displays current axis lock. Updated via `plugin.gd` -> `shortcut_hud.gd:update_context()`.
- **Customizable keyboard shortcuts** -- all bindings data-driven via `HFKeymap` JSON.
- **Status bar mode indicator** -- shows active mode (Draw/Select/Extrude/Paint) with live state updates.
- **Tool poll** -- buttons gray out with tooltip when action can't run (e.g. Hollow with no selection).
- Paint tool keyboard shortcuts (B/E/R/L/K) active when Paint Mode is enabled.
- Selection count in status bar, updated on every selection change.
- Color-coded status bar: errors in red (auto-clear 5s), warnings in yellow, success messages auto-clear after 3s.
- Bake progress bar with chunk status updates.
- Pending subtract brushes rendered in orange-red with high emission (`_make_pending_cut_material()`), visually distinct from applied cuts (standard red via `_make_brush_material()`).
- Shader-based editor grid with follow mode.
- Grouping shortcuts: Ctrl+G (group selection), Ctrl+U (ungroup).
- Brush operations: Ctrl+H (hollow), Shift+X (clip), Ctrl+Shift+F (floor), Ctrl+Shift+C (ceiling).
- Direct typed calls between plugin/dock/LevelRoot (no duck-typing).
- O(1) brush ID lookup and brush count via `_brush_cache` / `_brush_count` in `HFBrushSystem`.
- Material instance caching in `HFBrushSystem` (composite key: operation/solid/unshaded).
- Persistent cordon `ImmediateMesh` reused via `clear_surfaces()` (no per-call allocation).
- Selection highlight uses external `highlight.gdshader` (no inline GLSL strings).

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
| `test_keymap.gd` | 16 | Default bindings, key matching (simple/ctrl/shift/ctrl+shift), modifier rejection, display strings, rebinding, JSON roundtrip |
| `test_user_prefs.gd` | 9 | Default values, get/set prefs, section collapse state, recent files (add/dedup/max 10), JSON roundtrip |
| `test_dirty_tags.gd` | 11 | Brush dirty tags, paint chunk tags, full reconcile flag, consume-clears, signal batch queue/flush/discard/nesting |
| `test_prototype_textures.gd` | 27 | Catalog constants, path generation, texture existence, material persistence (resource_path), batch loading into MaterialManager |

Total: **371 tests** across **23 files**.

Tests use root shim scripts (dynamically created GDScript) to provide the LevelRoot interface without circular preload dependencies. Configuration in `.gutconfig.json`.
