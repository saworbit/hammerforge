# HammerForge MVP Guide

Last updated: February 7, 2026

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

### Brush Workflow (`HFBrushSystem` + `HFDragSystem`)
- DraftBrush nodes represent all authored geometry.
- `HFDragSystem` manages the two-stage draw lifecycle (base drag -> height click) and owns the `HFInputState` instance.
- `HFBrushSystem` handles brush CRUD, pending/committed cuts, materials, and picking.
- PendingCuts allow staging subtract operations before applying.

### Floor Paint (`HFPaintSystem` + `paint/*.gd`)
- Paint layers store grid occupancy in chunked bitsets.
- Geometry synthesis runs per dirty chunk:
  - Greedy rectangles for floors.
  - Boundary edges and merged segments for walls.
- Stable IDs are used to reconcile generated nodes without churn.

### Face Materials + Surface Paint (`HFPaintSystem`)
- DraftBrush faces store material indices, UVs, and paint layers.
- Materials are managed by a shared palette (MaterialManager).
- Surface paint writes per-face weight images and updates previews.

### Bake (`HFBakeSystem`)
- Assembles DraftBrushes (including generated paint geometry) into mesh output.
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
   - Select tool -> `HFBrushSystem` (picking + selection)
   - Paint (floor) -> `HFPaintSystem` -> `HFPaintTool` (layers + synth + reconcile)
   - Paint (surface) -> `HFPaintSystem` -> `SurfacePaint` (per-face weight images)
   - Face selection -> `HFBrushSystem` -> `FaceSelector`
   - Bake -> `HFBakeSystem` (CSG assembly + mesh output)
   - Save/load -> `HFFileSystem` (threaded I/O)
3. State changes go through `HFStateSystem` for undo/redo capture.

## Testing Checklist
- Create and resize draft brushes (Draw tool).
- Apply/clear/commit subtract cuts.
- Verify pending cuts appear orange-red, applied cuts turn standard red.
- Bake (with and without chunking).
- Enable Paint Mode and test Floor Paint tab Brush/Erase/Line/Rect/Bucket.
- Test paint tool shortcuts: B/E/R/L/K in Paint Mode.
- Verify live paint preview while dragging.
- Switch paint layers and ensure isolation.
- Create a material resource (.tres/.material) in `materials/` and add it to the palette.
- Enable Face Select Mode and assign materials to faces.
- Edit UVs and ensure preview updates.
- Surface paint on a face with two layers and verify blending (Paint Target = Surface).
- Toggle Use Face Materials and compare bake output.
- Save and load .hflevel and verify paint data persists.
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
