<!-- HammerForge design spec derived from user requirements -->
# HammerForge: FPS Level Editor Addon Design Spec

## Overview
- **Target:** Godot 4.6+ editor plugin for FPS level creation (Quake-style).  
- **Promise:** Browser-free, single-tool workflow—draft brushes, bake-time CSG, entities, optimization, and playtesting without leaving the editor.  
- **Delivery:** Asset Library install → enable plugin → add `LevelRoot.tscn` → edit instantly with presets for FPS gameplay.

## Status (Jan 31, 2026)
**Implemented**
- DraftBrush workflow with add/subtract, pending cuts, bake-time CSG.
- Wireframe draft previews for complex shapes (pyramids, prisms, platonic solids).
- Viewport face-handle gizmo for resizing brushes with undo/redo.
- Gizmo snapping respects `grid_snap` during handle drags.
- Chunked baking via `LevelRoot.bake_chunk_size` (default 32).
- Entities container (`LevelRoot/Entities`) and `is_entity` meta for selection-only nodes excluded from bake.
- Entity definitions JSON loaded by the dock (`res://addons/hammerforge/entities.json`).
- DraftEntity schema-driven properties with Inspector dropdowns (stored under `data/`, backward-compatible `entity_data/`).
- Entity previews (billboards/meshes) spawned in the editor from `entities.json` preview metadata.

**Planned**
- Autosave, .hflevel storage, import/export, and advanced optimization (LOD, navmesh, lightmap, multi-threaded merges).

## Why This Wins
| Goal | HammerForge Response |
| --- | --- |
| Immediate setup | <1 minute: enable plugin, create LevelRoot, ready brush/entity workflow. |
| Familiar workflow | Dock + toolbar mimic Hammer/Radiant; viewport brush handles (entity palette planned). |
| Performance | Chunked baking today; MultiMesh previews, compute merges, LOD/navmesh/collision automation planned. |
| Modularity | Toggleable modules (Terrain, Prefabs, AIPath) plus extensible signals/hooks/api for community tools. |
| Future-proofing | GDExtension stubs for C++ acceleration, glTF/Map/USD import-export, Godot 5-ready codebase. |

## Architecture Diagram

```
HammerForge (EditorPlugin)
├── UI Layer
│   ├── Dock (Brush/Entities/Textures/Settings)
│   └── Toolbar & Viewport Overlays (grid, gizmos, shortcuts)
├── Core Layer (LevelRoot Node, autoload)
│   ├── BrushSystem       # Draft brush ops, raycast placement, texture paint
│   ├── EntitySystem      # JSON FGD parser, instancer, signals
│   ├── OptimizationSystem# Chunk baker, navmesh/lightmap/collision/LOD
│   └── PreviewSystem     # FPS flycam, lighting preview, hot-reload
├── Modules (toggleable)
│   ├── TerrainModule     # Heightmap sculpt/paint
│   ├── PrefabModule      # Modular asset palette + LOD
│   └── AIPathModule      # Navmesh/path editing helpers
└── Storage
    └── .hflevel file storing brushes, entities, metadata (binary + JSON)
```

Note: Diagram includes planned modules; current implementation focuses on BrushSystem, Baker, and the Entities container.

## Core Features

### Brush Editing
- Add/subtract brushes (box, cylinder) with CAD-style drag: base drag + height stage.
- Editing uses DraftBrush nodes for speed; CSG is generated only during Bake.
- Viewport brush gizmo handles allow face-resize of DraftBrushes with undo/redo.
- Resize handles snap to `grid_snap` for consistent sizing.
- Subtract brushes can be staged as pending cuts and applied on demand.
- Grid/snap options (1–64 units), quick Create Floor for raycast placement.
- Undo/redo history panel (beta); autosave `.hflevel` planned.
- Chunked baking via `bake_chunk_size` (default 32); advanced culling/merge planned.

### Entity Placement
- Entities live under `LevelRoot/Entities` or are tagged `is_entity` (selection-only, excluded from bake).
- JSON entity definitions are stored in `res://addons/hammerforge/entities.json` and loaded by the dock (palette UI planned).
- DraftEntity exposes schema-driven Inspector properties via `entity_type` and persists values in the scene.
- Signals, instanced scenes, and palette tooling are planned additions.

### Optimization & Baking
- Chunked baking groups DraftBrushes by grid using `bake_chunk_size` (default 32) and bakes each chunk separately.
- Bake builds a temporary CSG tree per chunk to generate static meshes.
- Collision baking uses Add brushes only (Subtract brushes are excluded).
- Each chunk becomes a BakedChunk_x_y_z under BakedGeometry with MeshInstance3D + StaticBody3D.
- LOD, navmesh, lightmap, and merge optimizations are planned.
- Versioned saves and incremental rebuilds are planned.

### Preview/Playtesting
- Planned: embedded FPS flycam, quick play, and bake-and-run loop.

### Imports/Exports
- Planned: .map (TrenchBroom), glTF, and USD import/export.

### Optional Modules
Planned modules and scalability targets:

| Module | Purpose | FPS Value | Scalability |
| --- | --- | --- | --- |
| TerrainModule | Heightmap sculpt/paint with GPU clipmaps | Outdoor FPS maps | 64km seamless terrains |
| PrefabModule | Drag-droppable modular assets | Rapid reuse of crates, lights | Auto LOD, instancing |
| AIPathModule | Navmesh editing helpers | Smarter enemy movement | Chunk-streamed path data |

## UI / UX Layout

### Quadrant Viewports
Planned optional 2x2 SubViewport layout: Top/Front/Side orthographic + 3D perspective. Current workflow uses Godot's native 4-view layout.


- **Dock (Left-Upper):** Tool (Draw/Select), Paint Mode, Active Material, Shape Palette, Sides, Mode (Add/Subtract), Size, Grid, Physics Layer, Quadrant View toggle, Create Floor, Apply/Clear Cuts, Bake.  
- **Toolbar (Spatial Editor):** Mode switches (Brush/Object/Texture), Bake, Play FPS, Undo/Redo icons.  
- **Viewport Overlays:** Grid (toggle), brush ghost (green wireframe), hover selection highlight, snap lines, gizmo handles for resizing/rotating brushes and entities.  
- **Shortcuts:** `X/Y/Z` axis locks, `Shift` square base, `Shift+Alt` cube, `Alt` height-only, `Delete` remove, `Ctrl+D` duplicate.  
- **Performance HUD:** Live brush count label with green/yellow/red thresholds.  
- **First-run Wizard (planned):** Guides creation of `LevelRoot.tscn`, loads a sample FPS arena, sets defaults.
- **Mobile-friendly (planned):** Touch gestures and DPI scaling for tablets.

## Implementation Highlights

### Plugin Entry Point (`addons/hammerforge/plugin.gd`)
```gdscript
@tool
extends EditorPlugin

func _enter_tree():
    add_custom_type("LevelRoot", "Node3D",
        preload("level_root.gd"),
        preload("icon.png"))
    dock = preload("dock.tscn").instantiate()
    add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
    # toolbar + gizmo setup
    make_visible(false)

func _handles(type):
    return type == "LevelRoot"
```

### Brush Placement (`addons/hammerforge/level_root.gd`)
```gdscript
var hit = _raycast(active_camera, mouse_pos)
if hit:
    var snapped = _snap_point(hit.position)
    var brush = _create_brush(shape, size, operation, sides)
    brush.global_position = snapped + Vector3(0, size.y * 0.5, 0)
    _add_brush_to_draft(brush)
```

### Chunked Baking (`addons/hammerforge/level_root.gd`)
```gdscript
var chunks: Dictionary = {}
_collect_chunk_brushes(draft_brushes_node, bake_chunk_size, chunks, "brushes")
for coord in chunks:
    var temp_csg = CSGCombiner3D.new()
    _append_brush_list_to_csg(chunks[coord]["brushes"], temp_csg)
    var baked_chunk = baker.bake_from_csg(temp_csg, bake_material_override, layer, layer)
    baked_chunk.name = "BakedChunk_%s_%s_%s" % [coord.x, coord.y, coord.z]
```

### Entity Definitions (`addons/hammerforge/entities.json`)
```json
{"class":"Door","node":"Door3D","props":{"speed":200}}
```
- Definitions are loaded by the dock; palette UI and instancing are planned.

## Storage Format
Planned format (not yet implemented):
- `.hflevel`: custom binary + JSON that records brushes, entities, metadata, and module state.  
- Autosaves every 5 minutes via `ResourceSaver`.  
- Supports versioning for diff-only rebake and undo.  
- Preview scenes stored under `addons/hammerforge/levels/`.

## Extensibility
- **Modules folder:** e.g., `modules/terrain/` includes its own `EditorPlugin` subclass toggled from settings.  
- **Hooks:** Signals like `brush_placed(pos, normal)` let modules and user tool scripts respond.  
- **API:** `HammerForge.add_tool("MyBrush", script_path)` to register community tools.  
- **GDExtension Stubs:** Provide hooks for rewriting performance-critical systems in C++ for Godot 5.

## Deployment & Metadata
- Directory: `addons/hammerforge/` with `plugin.cfg` (name=HammerForge, version=1.0).  
- License: MIT.  
- Asset Library metadata: Categories = 3D Tools, Tags = fps, level-editor, brush.  
- Package as ZIP for submission to `godotengine.org/asset-library`.  
- Auto-update compatibility via Godot plugin manager.

## File Layout (Current)
```text
C:/hammerforge/
|-- addons/
|   `-- hammerforge/
|       |-- plugin.cfg
|       |-- plugin.gd
|       |-- level_root.gd
|       |-- dock.gd
|       |-- dock.tscn
|       |-- baker.gd
|       |-- brush_instance.gd
|       |-- brush_gizmo_plugin.gd
|       |-- brush_manager.gd
|       |-- prefab_factory.gd
|       |-- brush_preset.gd
|       |-- brush_prefab.gd
|       |-- shortcut_hud.gd
|       |-- shortcut_hud.tscn
|       |-- editor_grid.gdshader
|       |-- entities.json
|       |-- presets/
|       |-- _archive/
|-- docs/
|-- HammerForge_SPEC.md
```

## UX Mockups (Text)
- **Viewport shot:** room filled with brushes; overlay shows viewport grid, brush ghost, and gizmo.  
- **Dock snippet:** Brush tab shows shape buttons (`Box 16x8`, `Cyl`), subtract toggle, size slider, active material picker, paint toggle.  
- **Toolbar snippet:** `[Brush Mode] [Snap 16] [Bake] [Play]`.

## Reliability & Testing
- Planned: performance benchmarks (1M tris, FPS targets) and chunk streaming metrics.
- Undo/redo uses EditorUndoRedoManager for supported actions; autosave is planned.
- Diagnostic logs exist today; popups and parsing error fallbacks are planned.

## Roadmap
| Phase | Duration | Deliverable |
| --- | --- | --- |
| MVP | 1–2w | Brush placement, draft preview, dock, simple bake |
| Core | 2–4w | Entity integration, optimizer, FPS preview |
| Polish | 2w | UI/shortcuts, import/export, modules |
| Release | 1w | Asset Library submission, docs/video |

## Next Actions
1. Scaffold plugin folder per file layout above; start with `plugin.gd`, `level_root.gd`, and dock scene.  
2. Build brush/editor prototype (Phase 1) using DraftBrush previews and bake-time CSG as reference.  
3. Later phases cover entity parser, optimizer, preview, and modules.

























