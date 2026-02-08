# HammerForge Spec

Last updated: February 8, 2026

This document describes HammerForge's architecture and data flow.

## Goals
- Fast in-editor greyboxing with brush workflows.
- Editor responsiveness by avoiding live CSG.
- Reliable bake pipeline and clean data model.
- Modular codebase with clear separation of concerns.

## Architecture

HammerForge uses a coordinator + subsystems pattern. `LevelRoot` is a thin coordinator that owns all container nodes, exported properties, and signals, and delegates work to 8 `RefCounted` subsystem classes. Each subsystem receives a reference to `LevelRoot` in its constructor.

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

### Other Modules

- `addons/hammerforge/paint/*`: floor paint grid, layers, tools, inference, geometry synthesis, reconciliation, heightmap integration
- `addons/hammerforge/hflevel_io.gd`: variant encoding/decoding for .hflevel format
- `addons/hammerforge/map_io.gd`: .map file import/export
- `addons/hammerforge/prefab_factory.gd`: advanced shape generation (wedges, prisms, platonic solids, etc.)

### Paint Subsystem (`addons/hammerforge/paint/`)

| Script | class_name | Responsibility |
|--------|------------|----------------|
| `hf_paint_grid.gd` | `HFPaintGrid` | Grid storage, coordinate conversion |
| `hf_paint_layer.gd` | `HFPaintLayer` | Layer data: bitset + material_ids + blend_weights + heightmap |
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
| `hf_blend.gdshader` | -- | Two-material blend shader (UV2 blend map) |
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

## Brush Workflow
- Draw creates DraftBrush nodes in DraftBrushes.
- Subtract brushes are staged in PendingCuts until Apply Cuts.
- Extrude Up/Down picks a face via `FaceSelector`, creates a preview brush along the face normal, and commits a new DraftBrush on release. Uses `HFExtrudeTool` (RefCounted).
- Bake builds a temporary CSG tree from DraftBrushes + CommittedCuts and outputs BakedGeometry.

## Floor Paint System

Data
- Grid -> Layer -> Chunked storage (bitset + material_ids + blend_weights).
- Each layer optionally has a `heightmap: Image` and `height_scale: float`.
- Paint layers are stored under PaintLayers.

Tools
- Brush, Erase, Rect, Line, Bucket, Blend (enum `HFStroke.Tool`, values 0-5).
- Blend tool writes per-cell material_id and blend_weight to already-filled cells.

Brush Shape
- Square: fills every cell in the radius range (full box).
- Circle: clips corners using Euclidean distance check.

Generation (flat layers -- no heightmap)
- Floors: greedy rectangle merge -> DraftBrush boxes.
- Walls: boundary edges + merged segments -> DraftBrush boxes.

Generation (heightmap layers)
- Floors: per-cell displaced quads via `HFHeightmapSynth` -> ArrayMesh -> MeshInstance3D.
- Per-chunk blend image (Image FORMAT_RF) built from cell blend weights.
- Blend shader (`hf_blend.gdshader`) mixes two materials via UV2-sampled blend map.
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

## Entities
- Entities live under LevelRoot/Entities or are tagged `is_entity`.
- Entities are selectable but excluded from bake.
- Definitions come from `addons/hammerforge/entities.json`.

## Persistence (.hflevel)
- Stores brushes, entities, level settings, materials palette, and paint layers.
- Brush records include face data (materials, UVs, paint layers).
- Paint layers include grid settings, chunk size, bitset data, `material_ids`, `blend_weights`.
- Optional per-layer: `heightmap_b64` (base64 PNG), `height_scale`. Missing keys = no heightmap (backward-compatible).

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
- Pending subtract brushes rendered in orange-red with high emission (`_make_pending_cut_material()`), visually distinct from applied cuts (standard red via `_make_brush_material()`).
- Shader-based editor grid with follow mode.
- Direct typed calls between plugin/dock/LevelRoot (no duck-typing).
