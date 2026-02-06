# HammerForge MVP Guide

Last updated: February 6, 2026

This guide is for contributors implementing or extending the MVP.

## Goals
- Fast in-editor greyboxing with draft brushes.
- Bake to optimized meshes only when needed.
- Keep editor responsiveness high (no live CSG while editing).

## Core Systems

Brush workflow
- DraftBrush nodes represent all authored geometry.
- PendingCuts allow staging subtract operations.
- Bake builds a temporary CSG tree, generates meshes and collision, then discards the CSG.

Floor paint
- Paint layers store grid occupancy in chunked bitsets.
- Geometry synthesis runs per dirty chunk:
  - Greedy rectangles for floors.
  - Boundary edges and merged segments for walls.
- Stable IDs are used to reconcile generated nodes without churn.

Face materials + surface paint
- DraftBrush faces store material indices, UVs, and paint layers.
- Materials are managed by a shared palette (MaterialManager).
- Surface paint writes per-face weight images and updates previews.

Entities
- Entities live under LevelRoot/Entities or `is_entity` meta.
- Entities are excluded from bake.
- Definitions are loaded from `addons/hammerforge/entities.json`.

## High-Level Flow
1. Input is handled by the EditorPlugin.
2. LevelRoot forwards paint input based on Paint Target:
   - Floor: HFPaintTool updates layers and requests synth + reconcile.
   - Surface: SurfacePaint updates per-face paint layers.
3. Face selection routes to FaceSelector for per-face actions (materials/UV).
4. Bake assembles DraftBrushes (including generated paint geometry) into mesh output.

## Testing Checklist
- Create and resize draft brushes (Draw tool).
- Apply/clear/commit subtract cuts.
- Bake (with and without chunking).
- Enable Paint Mode and test Floor Paint tab Brush/Erase/Line/Rect/Bucket.
- Verify live paint preview while dragging.
- Switch paint layers and ensure isolation.
- Create a material resource (.tres/.material) in `materials/` and add it to the palette.
- Enable Face Select Mode and assign materials to faces.
- Edit UVs and ensure preview updates.
- Surface paint on a face with two layers and verify blending (Paint Target = Surface).
- Toggle Use Face Materials and compare bake output.
- Save and load .hflevel and verify paint data persists.
- Drag entities from the palette and check selection/exclusion from bake.

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
