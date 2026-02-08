# Development Guide

Last updated: February 8, 2026

This document covers local setup, codebase structure, and how to test features.

## Requirements
- Godot Engine 4.6 (stable).
- A 3D scene to host `LevelRoot`.

## Local Setup
1. Open the project in Godot.
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
3. Open any 3D scene and click in the viewport to auto-create `LevelRoot`.

## Codebase Structure

```
addons/hammerforge/
  plugin.gd              EditorPlugin entry point, input routing
  level_root.gd          Thin coordinator (~1,100 lines), delegates to subsystems
  input_state.gd         Drag/paint state machine (HFInputState)
  dock.gd + dock.tscn    UI dock, tool state, tooltips, status bar
  shortcut_hud.gd        Context-sensitive shortcut overlay (dynamic per mode)
  brush_instance.gd      DraftBrush node
  baker.gd               CSG -> mesh bake pipeline
  face_data.gd           Per-face materials, UVs, paint layers
  material_manager.gd    Shared materials palette
  face_selector.gd       Raycast face selection
  hf_extrude_tool.gd     Extrude Up/Down tool (face click + drag to extend brushes)
  surface_paint.gd       Per-face surface paint tool
  uv_editor.gd           UV editing dock
  hflevel_io.gd          Variant encoding/decoding for .hflevel
  map_io.gd              .map import/export
  prefab_factory.gd      Advanced shape generation

  systems/               Subsystem classes (RefCounted)
    hf_grid_system.gd      Editor grid management
    hf_entity_system.gd    Entity definitions and placement
    hf_brush_system.gd     Brush CRUD, cuts, materials, picking
    hf_drag_system.gd      Drag lifecycle, preview, axis locking
    hf_bake_system.gd      Bake orchestration (single/chunked)
    hf_paint_system.gd     Floor + surface paint, layer CRUD
    hf_state_system.gd     State capture/restore, settings
    hf_file_system.gd      .hflevel/.map/.glTF I/O, threaded writes

  paint/                 Floor paint subsystem
    hf_paint_grid.gd       Grid storage
    hf_paint_layer.gd      Layer data (bitset + material_ids + blend_weights + heightmap)
    hf_paint_layer_manager.gd  Layer management
    hf_paint_tool.gd       Paint tool input handling (routes to heightmap synth when layer has heightmap)
    hf_inference_engine.gd Inference for paint operations
    hf_geometry_synth.gd   Greedy meshing for flat floors/walls
    hf_heightmap_synth.gd  Heightmap-displaced mesh generation (SurfaceTool, per-vertex displacement)
    hf_heightmap_io.gd     Heightmap load/generate/serialize (base64 PNG, FastNoiseLite)
    hf_reconciler.gd       Stable-ID reconciliation (floors, walls, heightmap floors)
    hf_generated_model.gd  Data model (FloorRect, WallSeg, HeightmapFloor)
    hf_stroke.gd           Stroke types (brush/erase/rect/line/bucket/blend)
    hf_connector_tool.gd   Ramp/stair mesh generation between layers
    hf_foliage_populator.gd MultiMeshInstance3D procedural scatter (height/slope filtering)
    hf_blend.gdshader      Two-material blend shader (UV2 blend map, default colors, cell grid overlay)
```

### Architecture Conventions

- **Subsystems are RefCounted.** Each receives a `LevelRoot` reference in `_init()` and accesses container nodes and properties through `root.*`.
- **No circular preloads.** Subsystem files must not `preload("../level_root.gd")`. Use raw ints for default parameters and `root.EnumName.*` at runtime.
- **LevelRoot is the public API.** Its methods are thin one-line delegates to subsystems. External callers (`plugin.gd`, `dock.gd`) always go through `LevelRoot`.
- **Input state machine.** `HFDragSystem` owns the `HFInputState` instance. Drag state transitions are explicit (`begin_drag` -> `advance_to_height` -> `end_drag`). Extrude uses `begin_extrude` -> `end_extrude`.
- **Direct typed calls.** `plugin.gd` and `dock.gd` use typed references (`LevelRoot`, `DockType`) with direct method calls instead of `has_method`/`call`.
- **Undo/redo dynamic dispatch.** The `_commit_state_action` pattern in `dock.gd` intentionally uses string method names for undo/redo -- this is the one exception to the typed-calls rule.
- **Bake owner assignment.** Use `_assign_owner_recursive()` (not `_assign_owner()`) for baked geometry so all descendants get proper editor ownership. Always call it *after* the container is added to the scene tree.

### CI

The project has a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs on push and PR to `main`:
- `gdformat --check` -- verifies formatting
- `gdlint` -- checks lint rules (configured in `.gdlintrc`)

Run locally before pushing:
```
gdformat --check addons/hammerforge/
gdlint addons/hammerforge/
```

## Materials Resources
HammerForge expects Godot material resources (`.tres` or `.material`) in the palette.

Create one quickly:
1. In the FileSystem dock, right-click `materials/` (or any folder).
2. Select `New Resource` -> `StandardMaterial3D` (or `ShaderMaterial`).
3. Save it as `materials/test_mat.tres`.

Then click `Add` in the Materials tab and choose that resource.

## Manual Test Checklist
Brush workflow
- Draw an Add brush and confirm resize handles work.
- Draw a Subtract brush and apply cuts.
- Press U to enter Extrude Up, click a brush face, drag up, release -- confirm new brush appears.
- Press J to enter Extrude Down, click a brush face, drag up, release -- confirm new brush extends downward.
- Right-click during extrude drag to cancel and confirm preview is removed.
- Verify undo removes the extruded brush.

Face materials + UVs
- Add a material to the palette and assign it to multiple faces.
- Toggle Face Select Mode and ensure face selection only works when enabled.
- Open UV tab and drag points; confirm preview updates.

Surface paint
- Enable Paint Mode.
- In Surface Paint tab, set `Paint Target = Surface`.
- Assign a texture to a layer and paint on a face.
- Switch layers and verify isolated weights.

Floor paint
- In Floor Paint tab, use Brush/Erase/Rect/Line/Bucket on a layer.
- Switch brush shape between Square and Circle; confirm Square fills a box and Circle clips corners.
- Confirm live preview while dragging.

Heightmap + blend
- Paint cells on a layer, then import a heightmap (PNG/EXR) or generate noise.
- Verify displaced mesh appears under `Generated/HeightmapFloors`.
- Adjust Height Scale spinner and confirm mesh updates.
- Select Blend tool, paint blend weights on filled cells.
- Verify two-material blend shader responds to per-cell blend weights.
- Create two layers at different Y heights and generate a ramp/stair connector between them.
- Populate foliage on a heightmap layer and verify MultiMesh scatter respects height/slope.

Bake
- Bake with default settings.
- Toggle `Use Face Materials` and confirm bake output swaps to per-face materials.
- Bake with heightmap floors and confirm baked output includes heightmap meshes with trimesh collision.

Save/Load
- Save `.hflevel`.
- Reload and verify materials palette, face data, and paint layers are restored.
- Reload and verify heightmap data, material_ids, blend_weights, and height_scale persist.

Editor UX
- Toggle Draw/Select/Extrude Up/Extrude Down tools and verify shortcut HUD updates.
- Press U/J and verify toolbar button toggles and HUD shows extrude shortcuts.
- Start a brush drag and confirm HUD shows "Dragging Base" shortcuts.
- Press X/Y/Z and confirm HUD shows axis lock state.
- Enable Paint Mode and verify HUD shows paint shortcuts (B/E/R/L/K).
- Press B/E/R/L/K in Paint Mode and confirm paint tool selector updates.
- Hover dock controls (snap buttons, bake options, etc.) and verify tooltips appear.
- Select brushes and confirm "Sel: N brushes" appears in status bar.
- Trigger a bake error and confirm red status text auto-clears after 5 seconds.
- Draw a Subtract brush and confirm it appears in orange-red (pending), then Apply Cuts and confirm it turns standard red.

## Troubleshooting
- If paint affects floors while trying to surface paint, set `Paint Target = Surface`.
- If previews look incorrect, delete `LevelRoot/Generated` and repaint.
- If heightmap meshes don't appear, confirm the active layer has a heightmap assigned (Import or Generate).
- If blend shader shows only one material, ensure blend weights have been painted with the Blend tool.
- Heightmap floors use a blend shader with default green/brown terrain colors and a cell grid overlay. To customize: select a HeightmapFloor MeshInstance3D, edit the ShaderMaterial, and set `material_a`/`material_b` textures or adjust `color_a`/`color_b`/`grid_opacity`.
