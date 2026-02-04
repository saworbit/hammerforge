# HammerForge MVP Guide

Last updated: February 5, 2026

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

Entities
- Entities live under LevelRoot/Entities or `is_entity` meta.
- Entities are excluded from bake.
- Definitions are loaded from `addons/hammerforge/entities.json`.

## High-Level Flow
1. Input is handled by the EditorPlugin.
2. LevelRoot forwards paint input to HFPaintTool when Paint Mode is enabled.
3. PaintTool updates paint layers and requests geometry synth + reconcile.
4. Bake assembles DraftBrushes (including generated paint geometry) into mesh output.

## Testing Checklist
- Create and resize draft brushes (Draw tool).
- Apply/clear/commit subtract cuts.
- Bake (with and without chunking).
- Enable Paint Mode and test Brush/Erase/Line/Rect/Bucket.
- Verify live paint preview while dragging.
- Switch paint layers and ensure isolation.
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
- Material painting
- Numeric input during draw
- Additional import/export pipelines
