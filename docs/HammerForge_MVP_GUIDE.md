# HammerForge MVP Guide

Last updated: February 15, 2026

This guide is for contributors implementing or extending the MVP.

## Goals
- Fast in-editor greyboxing with draft brushes.
- Bake to optimized meshes only when needed.
- Keep editor responsiveness high (no live CSG while editing).
- Modular architecture with clear subsystem boundaries.

## Architecture Overview

HammerForge uses a **coordinator + subsystems** pattern:

- **`plugin.gd`** handles editor input and routes to `LevelRoot`.
- **`level_root.gd`** is a thin coordinator (~1,100 lines) that owns containers, exports, and signals. All public methods delegate to one of 8 subsystem classes.
- **Subsystems** (`systems/*.gd`) are `RefCounted` classes that do the real work. Each receives a `LevelRoot` reference in its constructor.
- **`input_state.gd`** is a state machine managing drag/paint modes.

See [DEVELOPMENT.md](../DEVELOPMENT.md) for the full file tree and architecture conventions.

## Core Systems

### Brush Workflow (`HFBrushSystem` + `HFDragSystem` + `HFExtrudeTool`)
- DraftBrush nodes represent all authored geometry.
- `HFDragSystem` manages the two-stage draw lifecycle (base drag -> height click) and owns the `HFInputState` instance.
- `HFExtrudeTool` handles face extrusion: picks a face via `FaceSelector`, shows a preview, and commits a new DraftBrush on release. Supports Up (along face normal) and Down (opposite).
- `HFBrushSystem` handles brush CRUD, pending/committed cuts, materials, and picking.
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
- Foliage populator (`HFFoliagePopulator`) scatters MultiMeshInstance3D with height/slope filtering.
- Stable IDs are used to reconcile generated nodes without churn.

### Face Materials + Surface Paint (`HFPaintSystem`)
- DraftBrush faces store material indices, UVs, and paint layers.
- Materials are managed by a shared palette (MaterialManager).
- Surface paint writes per-face weight images and updates previews.

### Bake (`HFBakeSystem`)
- Assembles DraftBrushes (including generated flat paint geometry) into mesh output via CSG.
- Heightmap floor meshes are duplicated directly into baked output (bypass CSG) with trimesh collision.
- Supports single and chunked baking modes.
- Optional: mesh merging, LODs, lightmap UV2, navmesh, collision.

### Entities (`HFEntitySystem`)
- Entities live under LevelRoot/Entities or `is_entity` meta.
- Entities are excluded from bake.
- Definitions are loaded from `addons/hammerforge/entities.json`.

### Persistence (`HFFileSystem` + `HFStateSystem`)
- `HFStateSystem` captures and restores brush/entity/paint/settings state for undo/redo.
- `HFFileSystem` handles .hflevel save/load, .map import/export, and glTF export with threaded I/O.

## High-Level Flow
1. Input is handled by `plugin.gd` (EditorPlugin) with typed references to `LevelRoot` and the dock.
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
- Enable Paint Mode and test Floor Paint tab Brush/Erase/Line/Rect/Bucket.
- Switch brush shape (Square/Circle) and verify radius fills correctly for each.
- Test paint tool shortcuts: B/E/R/L/K in Paint Mode.
- Verify live paint preview while dragging.
- Switch paint layers and ensure isolation.
- Import a heightmap (PNG/EXR) or generate procedural noise on a paint layer.
- Verify displaced mesh appears under `Generated/HeightmapFloors`.
- Adjust Height Scale and Layer Y spinboxes; confirm mesh updates.
- Select Blend tool, choose Blend Slot B/C/D, paint blend weights on filled cells; verify four-slot shader blending.
- Bake with heightmap floors and confirm baked output includes heightmap meshes with trimesh collision.
- Save and load .hflevel with heightmap data; verify heightmap, material_ids, blend_weights, and terrain slot settings persist.
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

## CI
Run `gdformat --check addons/hammerforge/` and `gdlint addons/hammerforge/` locally. These same checks run automatically on push/PR via `.github/workflows/ci.yml`.

## Diagnostics
- Enable Debug Logs in the dock for runtime tracing.
- Capture exit-time errors with:

```powershell
Start-Process -FilePath "C:\Godot\Godot_v4.6-stable_win64.exe" `
  -ArgumentList '--editor','--path','C:\hammerforge' `
  -RedirectStandardOutput "C:\Godot\godot_stdout.log" `
  -RedirectStandardError "C:\Godot\godot_stderr.log" `
  -NoNewWindow
```

## Known Issues (current)
- Viewport drag-marquee selection is disabled.
- Multi-select can cap at 2 items in the viewport.

## Next Steps
- Numeric input during draw
- Material atlasing and compression
- Additional import/export pipelines
