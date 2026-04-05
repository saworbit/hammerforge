# HammerForge Texture and Materials

Last updated: March 28, 2026

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

### Using Prototype Textures (Quick Start)
For rapid prototyping without creating custom materials:
1. Open the Paint tab in the dock.
2. Click **Refresh Prototypes** in the Materials section.
3. 150 built-in SVG textures are added to the palette (15 patterns x 10 colors).
4. Browse textures visually in the **Material Browser** thumbnail grid — filter by pattern, color, or search text.
5. Click a thumbnail to select it, then click **Assign to Selected Faces** (or right-click → "Apply to Selected Faces").
6. Alternatively, press **T** to use the **Texture Picker** — click any face to sample its material.

For full details, see [Prototype Textures](HammerForge_Prototype_Textures.md).

### Creating Custom Materials
1. In the FileSystem dock, right-click a folder (e.g. `materials/`).
2. Choose `New Resource` -> `StandardMaterial3D` (or `ShaderMaterial`).
3. Save it as a `.tres` file (example: `materials/test_mat.tres`).

You can then click `Add` in the Paint tab → Materials section and pick that resource.

## Materials Palette & Visual Browser
The Paint tab → Materials section hosts a **visual material browser** (`HFMaterialBrowser`) that replaces the old text-only list.

### Visual Browser
The browser displays a scrollable thumbnail grid (64px cells, 5 columns). Each cell shows the actual texture preview with a short label. Features:
- **Search bar**: live text filtering by material name.
- **Pattern filter**: dropdown with 15 patterns + "All".
- **Color swatches**: 10 clickable color buttons + "All" to filter by color.
- **View toggle**: Prototypes (only built-in), Palette (all loaded), Favorites (starred only).
- **Hover preview**: hovering a thumbnail temporarily applies that material to selected faces in the viewport.
- **Right-click context menu**: Apply to Selected Faces, Apply to Whole Brush, Toggle Favorite, Copy Name.
- **Status bar**: "X of Y materials" with filter feedback.

### Workflow
1. Click `Add` to load a material resource, or click `Refresh Prototypes` to load all 150 built-in textures.
2. Browse the thumbnail grid — use filters and search to narrow down.
3. Click a thumbnail to select it as the current material.
4. Enable `Face Select Mode` and click faces in the viewport (Select tool).
5. Click `Assign to Selected Faces` (or right-click the thumbnail → "Apply to Selected Faces").

### Texture Picker (Eyedropper)
Press **T** to activate the texture picker. Click any face in the viewport to sample its assigned material — the browser selection updates to match. Useful for "what material is this?" queries and quick material matching.

### Favorites
Right-click any thumbnail and choose "Toggle Favorite". Switch the view toggle to "Favorites" to see only starred materials. Favorites persist within the editor session.

Notes:
- Per-face materials override the DraftBrush material for preview and face-material bake.
- The palette is saved in `.hflevel`.
- **Library persistence**: the palette can be saved to / loaded from a JSON library file via `MaterialManager.save_library()` / `load_library()`. This preserves the material list across projects. Missing or unloadable materials are preserved as `null` placeholder slots to keep palette indices stable.
- **Usage tracking**: `MaterialManager` tracks which materials are referenced by brushes. Use `find_unused_materials()` to identify palette entries that are no longer in use.

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
- Face selection supports marquee/box selection across multiple brushes (added in the Improved Selection & Multi-Select wave). Lasso selection is not supported.
- Face-material bake ignores subtract/pending cuts.
- Surface paint is per-face and does not share weights across faces.
- Preview materials are rebuilt per face and can be heavy on very large brush counts.
- Favorites are stored in the browser instance and do not persist across editor restarts (future: save to user prefs).
- Hover preview applies to the first surface override material slot only; multi-material faces may not preview accurately.

## See Also
- [Prototype Textures](HammerForge_Prototype_Textures.md) -- 150 built-in SVG textures for greyboxing.

## Suggested Testing
- Click Refresh Prototypes and confirm 150 materials appear in the browser grid with thumbnails.
- Use pattern filter, color swatches, and search bar to narrow the grid. Verify counts in the status label.
- Switch between Prototypes / Palette / Favorites views.
- Right-click a thumbnail → Toggle Favorite. Switch to Favorites view and confirm it appears.
- Hover a thumbnail with faces selected and confirm temporary material preview in viewport.
- Press T (Texture Picker) and click a face — confirm the browser selection updates.
- Right-click → Apply to Selected Faces and confirm assignment.
- Right-click → Apply to Whole Brush and confirm all faces change.
- Right-click → Copy Name and confirm clipboard contents.
- Assign different materials to multiple faces and verify preview rebuild.
- Edit UVs and confirm the preview updates.
- Paint two layers and confirm blend behavior.
- Save and load `.hflevel` and verify face data is restored.
- Toggle `Use Face Materials` and compare bake output.
