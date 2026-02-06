# Development Guide

Last updated: February 6, 2026

This document covers local setup, where material resources live, and how to test new features.

## Requirements
- Godot Engine 4.6 (stable).
- A 3D scene to host `LevelRoot`.

## Local Setup
1. Open the project in Godot.
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
3. Open any 3D scene and click in the viewport to auto-create `LevelRoot`.

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
- Confirm live preview while dragging.

Bake
- Bake with default settings.
- Toggle `Use Face Materials` and confirm bake output swaps to per-face materials.

Save/Load
- Save `.hflevel`.
- Reload and verify materials palette, face data, and paint layers are restored.

## Troubleshooting
- If paint affects floors while trying to surface paint, set `Paint Target = Surface`.
- If previews look incorrect, delete `LevelRoot/Generated` and repaint.
