# HammerForge Texture and Materials

Last updated: February 25, 2026

This document describes the per-face material system, UV editing tools, and surface paint workflow.

## Overview
HammerForge supports per-face materials on DraftBrushes. Each face stores:
- A material index (from a shared palette).
- UV projection settings or explicit UVs.
- Optional paint layers with per-pixel weights.

Surface paint is separate from floor paint. Floor paint is a grid-based system that generates geometry. Surface paint is a per-face splat system that updates DraftBrush previews and optional face-material baking.

## Data Model (FaceData)
Face data lives on each DraftBrush in `faces` and is serialized into `.hflevel`.

- `material_idx`: Index into `MaterialManager.materials`.
- `uv_projection`: Projection enum (planar X/Y/Z, box, cylindrical).
- `uv_scale`, `uv_offset`, `uv_rotation`: Projection transform.
- `custom_uvs`: Optional explicit UVs (per vertex).
- `paint_layers`: Array of paint layers.

Paint layer fields:
- `texture`: Texture2D for the layer.
- `weight_image`: Image storing weights (R channel).
- `blend_mode`: Overlay, Multiply, Add.
- `opacity`: Layer opacity.

## Getting Materials
Materials are Godot resources stored as `.tres` or `.material` files.

Quick ways to get one:
1. In the FileSystem dock, right-click a folder (e.g. `materials/`).
2. Choose `New Resource` -> `StandardMaterial3D` (or `ShaderMaterial`).
3. Save it as a `.tres` file (example: `materials/test_mat.tres`).

You can then click `Add` in the Paint tab → Materials section and pick that resource.

## Materials Palette
The Paint tab → Materials section hosts the palette used by face assignment.

Workflow:
1. Click `Add` to load a material resource.
2. Enable `Face Select Mode`.
3. Click faces in the viewport (Select tool).
4. Click `Assign to Selected Faces`.

Notes:
- Per-face materials override the DraftBrush material for preview and face-material bake.
- The palette is saved in `.hflevel`.

## UV Editor
The Paint tab → UV Editor section shows a simple per-face UV editor.

Workflow:
1. Select a face (Face Select Mode).
2. Use drag handles to move UV points.
3. Click `Reset Projected UVs` to regenerate UVs from the projection mode.

Notes:
- If no custom UVs exist, projected UVs are generated automatically.
- UV edits trigger preview rebuilds on the owning DraftBrush.

## Surface Paint (3D)
Surface paint uses the Paint tab → Surface Paint section with target set to `Surface`.

Workflow:
1. Enable Paint Mode.
2. Paint tab → Surface Paint section: set `Paint Target = Surface`.
3. Select a layer and pick a texture.
4. Paint on faces in the viewport.

Controls:
- `Radius (UV)` scales the brush relative to the face UV space.
- `Strength` controls weight accumulation.
- `Layer` selects which weight image is painted.

Notes:
- Weights are stored per face as images (default 256x256).
- Surface paint updates the DraftBrush preview immediately.
- Surface paint does not modify floor paint layers.
- If paint affects floors, set `Paint Target = Surface` in the Paint tab → Surface Paint section.

## Bake Integration
A bake option `Use Face Materials` switches the bake pipeline to per-face materials.

Behavior:
- Each face is grouped by its assigned material.
- Faces are baked directly from face data (no CSG).
- Subtract brushes are ignored in face-material bake.

When to use:
- Use face-material bake for quick previews and texture checks.
- Use CSG bake for boolean cuts and full brush set integration.

## Serialization (.hflevel)
`.hflevel` saves include:
- Materials palette.
- Per-brush face data (materials, UVs, paint layers).
- Floor paint layers (unchanged).

Paint weights are stored as embedded PNG bytes (base64) per layer.

## Known Limitations
- Face selection is per-brush and does not support lasso/marquee selection.
- Face-material bake ignores subtract/pending cuts.
- Surface paint is per-face and does not share weights across faces.
- Preview materials are rebuilt per face and can be heavy on very large brush counts.

## Suggested Testing
- Assign different materials to multiple faces and verify preview rebuild.
- Edit UVs and confirm the preview updates.
- Paint two layers and confirm blend behavior.
- Save and load `.hflevel` and verify face data is restored.
- Toggle `Use Face Materials` and compare bake output.
