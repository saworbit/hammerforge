<!-- HammerForge design spec derived from user requirements -->
# HammerForge: FPS Level Editor Addon Design Spec

## Overview
- **Target:** Godot 4.3+ editor plugin for FPS level creation (Quake-style).  
- **Promise:** Browser-free, single-tool workflow—brush CSG, entities, optimization, and playtesting without leaving the editor.  
- **Delivery:** Asset Library install → enable plugin → add `LevelRoot.tscn` → edit instantly with presets for FPS gameplay.

## Why This Wins
| Goal | HammerForge Response |
| --- | --- |
| Immediate setup | <1 minute: enable plugin, create LevelRoot, ready brush/entity workflow. |
| Familiar workflow | Dock + toolbar mimic Hammer/Radiant; viewport brush handles and entity palette. |
| Performance | Chunked baking, MultiMesh preview, compute shader merges, LOD/navmesh/collision auto generation for 10k+ brushes. |
| Modularity | Toggleable modules (Terrain, Prefabs, AIPath) plus extensible signals/hooks/api for community tools. |
| Future-proofing | GDExtension stubs for C++ acceleration, glTF/Map/USD import-export, Godot 5-ready codebase. |

## Architecture Diagram

```
HammerForge (EditorPlugin)
├── UI Layer
│   ├── Dock (Brush/Entities/Textures/Settings)
│   └── Toolbar & Viewport Overlays (grid, gizmos, shortcuts)
├── Core Layer (LevelRoot Node, autoload)
│   ├── BrushSystem       # CSG ops, raycast placement, texture paint
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

## Core Features

### Brush Editing
- Add/subtract brushes (box, cylinder) with CAD-style drag: base drag + height stage.
- Subtract brushes can be staged as pending cuts and applied on demand.
- Grid/snap options (1–64 units), quick Create Floor for raycast placement.
- Undo/redo buffer + history panels; autosave `.hflevel` every 5 minutes.
- On-the-fly chunk culling (256 brushes/mesh), compute-shader merging, diff-only rebakes.

### Entity Placement
- Palette driven: drag player start, doors, triggers, or custom props defined via JSON FGD-like files.
- Signals (e.g., `brush_placed`, `entity_spawned`) allow modules/extensions to react.
- Instanced scene support ensures performance and hierarchy clarity.

### Optimization & Baking
- Chunk-level baking (configurable e.g., 128m tiles) merges visible faces, auto-culls hidden geometry.
- Generates `NavMeshInstance3D`, `LightmapGI`, collision meshes, LODs, and multi-threaded merge tasks.
- Chunk scenes combine `StaticBody3D` + optimized meshes for runtime.
- Versioned saves support incremental builds and reconstruction.

### Preview/Playtesting
- Embedded FPS flycam (WASD + mouse) with physics/wireframe toggles.
- Auto-spawns player, syncs settings with target gameplay (footstep surfaces, bullet materials).
- One-click build & play (Ctrl+B) that bakes changed chunks and starts playable scene within editor viewport.

### Imports/Exports
- Supports `.map` (TrenchBroom), glTF (Blender), USD to blend workflows.
- Lossless round-tripping ensures edits stay consistent.

### Optional Modules
| Module | Purpose | FPS Value | Scalability |
| --- | --- | --- | --- |
| TerrainModule | Heightmap sculpt/paint with GPU clipmaps | Outdoor FPS maps | 64km seamless terrains |
| PrefabModule | Drag-droppable modular assets | Rapid reuse of crates, lights | Auto LOD, instancing |
| AIPathModule | Navmesh editing helpers | Smarter enemy movement | Chunk-streamed path data |

## UI / UX Layout

- **Dock (Left-Upper):** Tool (Draw/Select), Paint Mode, Active Material, Mode (Add/Subtract), Shape, Size, Grid, Physics Layer, Create Floor, Apply/Clear Cuts, Bake.  
- **Toolbar (Spatial Editor):** Mode switches (Brush/Object/Texture), Bake, Play FPS, Undo/Redo icons.  
- **Viewport Overlays:** Grid (toggle), brush ghost (green wireframe), hover selection highlight, snap lines, gizmo handles for resizing/rotating brushes and entities.  
- **Shortcuts:** `X/Y/Z` axis locks, `Shift` square base, `Shift+Alt` cube, `Alt` height-only, `Delete` remove, `Ctrl+D` duplicate.  
- **Performance HUD:** Live brush count label with green/yellow/red thresholds.  
- **First-run Wizard:** Guides creation of `LevelRoot.tscn`, loads sample FPS arena, sets defaults.  
- **Mobile-friendly:** Touch gestures, DPI scaling for tablets.

## Implementation Highlights

### Plugin Entry Point (`addons/hammerforge/plugin.gd`)
```gdscript
@tool
extends EditorPlugin

func _enter_tree():
    add_custom_type("LevelRoot", "Node3D",
        preload("level_root.gd"),
        preload("icon.svg"))
    dock = preload("dock.tscn").instantiate()
    add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
    # toolbar + gizmo setup
    make_visible(false)

func _handles(type):
    return type == "LevelRoot"
```

### Brush Placement (`brush_system.gd`)
```gdscript
var space_state = get_world_3d().direct_space_state
var query = PhysicsRayQueryParameters3D.from_viewport(viewport, mouse_pos)
var hit = space_state.intersect_ray(query)
if hit:
    var brush = BrushInstance3D.new(hit.position, size, shape)
    level_root.add_brush(brush)
    brush.mesh = generate_convex_hull()
```

### Optimization/Baking (`optimizer.gd`)
```gdscript
await RenderingServer.viewport_set_update_mode(sub_viewport, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
var chunks = chunk_brushes(brushes, 128.0)
for chunk in chunks:
    var mesh = merge_meshes(chunk.brushes, materials)
    var static_body = StaticBody3D.new_with_mesh(mesh)
    chunk_scene.add_child(static_body)
    # add NavMeshInstance3D, LightmapGI
```

### Entity System (FGD JSON)
```json
{"class":"Door","node":"Door3D","props":{"speed":200}}
```
- Parser instantiates nodes, assigns signals/props.

## Storage Format
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

## File Layout Proposal
```
C:/hammerforge/
├── addons/
│   └── hammerforge/
│       ├── plugin.cfg
│       ├── plugin.gd
│       ├── level_root.gd
│       ├── brush_system/
│       │   ├── brush_system.gd
│       │   ├── brush_gizmo_plugin.gd
│       │   └── brush_preview.tscn
│       ├── entity_system/
│       │   ├── entity_system.gd
│       │   └── fgd/
│       ├── optimizer/
│       │   └── optimizer.gd
│       ├── preview_system/
│       └── dock.tscn
├── icon.svg
├── project.godot
└── docs/
    └── design/
        └── HammerForge_SPEC.md
```

## UX Mockups (Text)
- **Viewport shot:** room filled with brushes; overlay shows viewport grid, brush ghost, and gizmo.  
- **Dock snippet:** Brush tab shows shape buttons (`Box 16x8`, `Cyl`), subtract toggle, size slider, active material picker, paint toggle.  
- **Toolbar snippet:** `[Brush Mode] [Snap 16] [Bake] [Play]`.

## Reliability & Testing
- Benchmarks for 1M tris with FPS graph; chunk streaming ensures 60–144 FPS even on large scenes.  
- Undo/redo powered by `EditorUndoRedoManager`; autosave ensures resilience.  
- Diagnostic logs + popups for parsing errors fallback to wireframe preview.

## Roadmap
| Phase | Duration | Deliverable |
| --- | --- | --- |
| MVP | 1–2w | Brush placement, CSG preview, dock, simple bake |
| Core | 2–4w | Entity integration, optimizer, FPS preview |
| Polish | 2w | UI/shortcuts, import/export, modules |
| Release | 1w | Asset Library submission, docs/video |

## Next Actions
1. Scaffold plugin folder per file layout above; start with `plugin.gd`, `level_root.gd`, and dock scene.  
2. Build brush/editor prototype (Phase 1) using Godot’s CSG demo as reference.  
3. Later phases cover entity parser, optimizer, preview, and modules.
