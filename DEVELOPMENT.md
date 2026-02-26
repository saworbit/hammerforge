# Development Guide

Last updated: February 26, 2026

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
  plugin.gd              EditorPlugin entry point, input routing, sticky LevelRoot discovery
  level_root.gd          Thin coordinator (~1,100 lines), delegates to subsystems
  input_state.gd         Drag/paint state machine (HFInputState)
  dock.gd + dock.tscn    UI dock (4 tabs: Brush, Paint, Entities, Manage), collapsible sections
  shortcut_hud.gd        Context-sensitive shortcut overlay (dynamic per mode)
  brush_instance.gd      DraftBrush node
  baker.gd               CSG -> mesh bake pipeline
  face_data.gd           Per-face materials, UVs, paint layers
  material_manager.gd    Shared materials palette
  face_selector.gd       Raycast face selection
  hf_extrude_tool.gd     Extrude Up/Down tool (face click + drag to extend brushes)
  surface_paint.gd       Per-face surface paint tool
  uv_editor.gd           UV editing dock
  highlight.gdshader     Selection highlight shader (wireframe, unshaded, alpha)
  hflevel_io.gd          Variant encoding/decoding for .hflevel
  map_io.gd              .map import/export
  prefab_factory.gd      Advanced shape generation

  ui/                    Reusable UI components
    collapsible_section.gd HFCollapsibleSection: toggle-header VBoxContainer for dock sections

  systems/               Subsystem classes (RefCounted)
    hf_grid_system.gd      Editor grid management
    hf_entity_system.gd    Entity definitions, placement, Entity I/O connections
    hf_brush_system.gd     Brush CRUD, cuts, materials, picking, hollow, clip, tie/untie
    hf_drag_system.gd      Drag lifecycle, preview, axis locking
    hf_bake_system.gd      Bake orchestration (single/chunked)
    hf_paint_system.gd     Floor + surface paint, layer CRUD
    hf_state_system.gd     State capture/restore, settings
    hf_file_system.gd      .hflevel/.map/.glTF I/O, threaded writes
    hf_validation_system.gd Validation and dependency checks
    hf_visgroup_system.gd  Visgroups (visibility groups) + brush/entity grouping

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
- **Sticky LevelRoot discovery.** `plugin.gd` keeps `active_root` sticky: `_edit()` does not null it when non-LevelRoot nodes are selected. `_handles()` returns true for any node when a LevelRoot exists (deep recursive search). `dock.gd` mirrors this pattern.
- **Collapsible sections.** Use `HFCollapsibleSection.create("Name", start_expanded)` from `ui/collapsible_section.gd` for dock sections. Paint, Manage, and Entity I/O tab contents are built programmatically in `_build_paint_tab()`, `_build_manage_tab()`, and `_build_entity_io_section()`.
- **Signal-driven dock sync.** Setting controls (checkboxes, spinboxes) in the dock push values to LevelRoot via `toggled`/`value_changed` signal connections. `_process()` no longer polls 17 properties every frame. Perf panel updates every 30 frames; paint/material sync every 10 frames; disabled hints are flag-driven.
- **Input decomposition.** `_forward_3d_gui_input()` in `plugin.gd` is a ~50-line dispatcher that routes to focused handlers: `_handle_paint_input()`, `_handle_keyboard_input()`, `_handle_rmb_cancel()`, `_handle_select_mouse()`, `_handle_extrude_mouse()`, `_handle_draw_mouse()`, `_handle_mouse_motion()`. Shared `_get_nudge_direction()` is used by both `_forward_3d_gui_input()` and `_shortcut_input()`.
- **Brush/material caching.** `hf_brush_system.gd` uses `_brush_cache: Dictionary` for O(1) brush ID lookup, `_brush_count: int` for O(1) count, and `_material_cache: Dictionary` for material instance reuse. All CRUD methods maintain these caches.
- **Undo/redo dynamic dispatch.** The `_commit_state_action` pattern in `dock.gd` intentionally uses string method names for undo/redo -- this is the one exception to the typed-calls rule.
- **Undo/redo helper.** Use `HFUndoHelper` for editor actions to ensure consistent history and state snapshot restores.
- **Undo/redo stability.** Prefer brush IDs and `create_brush_from_info()` for undo instead of storing Node references in history.
- **Bake owner assignment.** Use `_assign_owner_recursive()` (not `_assign_owner()`) for baked geometry so all descendants get proper editor ownership. Always call it *after* the container is added to the scene tree.
- **Shader files.** Prefer standalone `.gdshader` files over inline GLSL strings in GDScript (e.g. `highlight.gdshader` for the selection wireframe shader). Use `preload("file.gdshader")` to load them.

### CI

The project has a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs on push and PR to `main`:
- `gdformat --check` -- verifies formatting
- `gdlint` -- checks lint rules (configured in `.gdlintrc`)
- **GUT unit tests** -- 245 tests across 15 test files (runs Godot headless)

Run locally before pushing:
```
gdformat --check addons/hammerforge/
gdlint addons/hammerforge/
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

### Unit Tests (GUT)

Tests live in `tests/` and use the [GUT](https://github.com/bitwes/Gut) framework (installed in `addons/gut/`).

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `test_visgroup_system.gd` | 18 | Visgroup CRUD, visibility, membership, serialization |
| `test_grouping.gd` | 9 | Group creation, meta, ungroup, regroup, serialization |
| `test_texture_lock.gd` | 10 | UV offset/scale compensation for all projection types |
| `test_cordon_filter.gd` | 10 | AABB intersection, cordon-filtered collection, chunk_coord |
| `test_hollow_tool.gd` | 10 | Hollow creation (6 walls), thickness validation, material/operation preservation |
| `test_clip_tool.gd` | 16 | Axis splitting (X/Y/Z), size correctness, property preservation (material, visgroups, group_id, brush_entity_class), edge rejection |
| `test_brush_entity.gd` | 16 | Tie/untie entity classes, structural brush filtering, bake collection exclusion, brush info round-trip |
| `test_entity_io.gd` | 21 | Entity I/O CRUD (add/remove/get outputs), find by name, get_all_connections, serialization, default values |
| `test_justify_uv.gd` | 10 | UV justify modes (fit/center/left/right/top/bottom), zero-range safety, offset accumulation |
| `test_brush_info_roundtrip.gd` | 19 | Brush info capture/restore with visgroups, group_id, brush_entity_class, material, move floor/ceiling argument safety |
| `test_face_data.gd` | 15 | FaceData to_dict/from_dict round-trip, ensure_geometry, triangulate, box_projection_axis |
| `test_paint_layer.gd` | 32 | Cell bit storage, chunk management, material IDs, blend weights, dirty tracking, heightmap, memory |
| `test_heightmap_io.gd` | 12 | Base64 encode/decode round-trip, noise generation (FastNoiseLite), determinism |
| `test_hflevel_io.gd` | 32 | Variant encode/decode (Vector2/3, Transform3D, Basis, Color), payload build/parse, full pipeline |
| `test_brush_shapes.gd` | 15 | Box face generation, normals, vertex bounds, triangulation, serialization, prism mesh |

Run all tests:
```
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

If you see "class_names not imported", run `godot --headless --import --path .` first to register GUT classes.

Configuration is in `.gutconfig.json` (test directory, prefix, exit behavior).

**Writing new tests:**
- Add files in `tests/` with the `test_` prefix and `.gd` suffix.
- Extend `GutTest`. Use `before_each()` / `after_each()` for setup/teardown.
- Use root shim scripts (dynamically created GDScript) to provide the LevelRoot interface without circular preload. See existing tests for the pattern.
- Keep tests focused: one behavior per test function.

## Materials Resources
HammerForge expects Godot material resources (`.tres` or `.material`) in the palette.

Create one quickly:
1. In the FileSystem dock, right-click `materials/` (or any folder).
2. Select `New Resource` -> `StandardMaterial3D` (or `ShaderMaterial`).
3. Save it as `materials/test_mat.tres`.

Then click `Add` in the Paint tab → Materials section and choose that resource.

## Manual Test Checklist

Visgroups
- Create a visgroup "walls" from the Manage tab.
- Add 2 brushes to the visgroup and toggle visibility off -- confirm those 2 brushes hide.
- Toggle visibility on -- confirm brushes reappear.
- Create a second visgroup, add a brush to both, hide one -- confirm brush is hidden.
- Save and reload `.hflevel` -- confirm visgroup names and membership persist.

Grouping
- Select 2 brushes and press Ctrl+G -- confirm a group is created.
- Click one grouped brush -- confirm all group members are selected.
- Press Ctrl+U -- confirm brushes are ungrouped and select independently.
- Save and reload -- confirm group persists.

Texture Lock
- Place a textured brush with Texture Lock enabled (Brush tab checkbox).
- Resize the brush via gizmo -- confirm UV alignment stays consistent.
- Move the brush -- confirm UVs track the movement.
- Disable Texture Lock and resize -- confirm UVs shift with the resize.

Cordon (Partial Bake)
- Enable cordon in the Manage tab.
- Set a small AABB around 1 of 3 brushes (or use "Set from Selection").
- Confirm yellow wireframe appears in the viewport.
- Bake -- confirm only the brush inside the cordon appears in baked output.
- Disable cordon and bake -- confirm all brushes appear.

Wave 2 Tools
- Select a brush and press Ctrl+H -- confirm it converts to 6 wall brushes (hollow).
- Adjust wall thickness spinner before hollowing and confirm different thicknesses.
- Select a brush and press Shift+X -- confirm it splits into two brushes along the Y axis.
- During a base drag, type "64" then Enter -- confirm the brush base is 64 units.
- During height adjustment, type "32" then Enter -- confirm the brush height is 32 units.
- Select brushes, choose func_detail from dropdown, click Tie -- confirm cyan tint overlay appears.
- Select tied brushes, click Untie -- confirm tint is removed.
- Tie brushes as trigger_once -- confirm orange tint overlay appears.
- Bake with func_detail brushes -- confirm they are excluded from structural bake output.
- Select a brush and press Ctrl+Shift+F -- confirm it snaps to nearest surface below.
- Select a brush and press Ctrl+Shift+C -- confirm it snaps to nearest surface above.
- In Face Select Mode, select faces and use Justify Fit/Center/Left/Right/Top/Bottom.
- Select an entity, open Entity I/O section, fill Output/Target/Input, click Add -- confirm connection appears in list.
- Select the connection in the list and click Remove -- confirm it is removed.
- Select a different entity -- confirm the I/O list updates to show that entity's connections.
- Save .hflevel with entity I/O connections, reload, and confirm connections persist.

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
- Open Paint tab → UV Editor section and drag points; confirm preview updates.

Surface paint
- Enable Paint Mode.
- In Paint tab → Surface Paint section, set `Paint Target = Surface`.
- Assign a texture to a layer and paint on a face.
- Switch layers and verify isolated weights.

Floor paint
- In Paint tab → Floor Paint section, use Brush/Erase/Rect/Line/Bucket on a layer.
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
- Set `bake_chunk_size > 0` and confirm the progress bar updates with chunk status.
- Run Bake Dry Run and confirm counts match expected brushes and chunks.

Validation + Settings
- Run Validate Level on a clean scene and confirm no issues.
- Create a zero-size brush and confirm Validate + Fix repairs it.
- Export settings, change grid snap or bake options, then import and confirm values restore.
- Confirm autosave history files are created under `res://.hammerforge/autosave_history` and old files are pruned.

Performance Panel
- Confirm brush count, paint memory, chunk count, and last bake time update after a bake.

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
