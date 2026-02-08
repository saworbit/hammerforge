# HammerForge User Guide

Last updated: February 7, 2026

This guide covers the current HammerForge workflow in Godot 4.6: brush-based greyboxing, bake, entities, floor paint, and per-face materials/UVs.

## Quick Start
1. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
2. Open any 3D scene.
3. Click in the 3D viewport to auto-create `LevelRoot`.
4. Optional: Click Create Floor for a temporary collidable surface.
5. Draw brushes, then Bake for output geometry.

## LevelRoot
`LevelRoot` is required because it owns the containers and systems HammerForge uses:
- DraftBrushes, PendingCuts, CommittedCuts
- PaintLayers and Generated (floors/walls)
- Entities
- Baker and paint systems

If missing, HammerForge creates it automatically on first viewport click.

## Dock Controls (overview)
Tool
- Draw: create brushes.
- Select: select existing brushes. Delete removes them.

Paint Mode (floor + surface)
- Enables paint input in the viewport.
- Paint Target is global and decides whether strokes affect Floor or Surface.
- Floor Paint tab: Brush, Erase, Rect, Line, Bucket, Blend.
- Floor Paint tab: Brush shape (Square or Circle), radius in grid cells, and layer picker.
- Floor Paint tab: Heightmap Import/Generate, Height Scale, Layer Y, Blend Strength controls.
- Surface Paint tab: Paint Target, layers, texture picker, radius/strength.

Materials (per-face)
- Materials palette: add/remove materials.
- Materials are Godot resources (.tres/.material). Create via FileSystem -> New Resource -> StandardMaterial3D or ShaderMaterial, then save under `materials/`.
- Face Select Mode toggles face selection in the viewport.
- Assign to Selected Faces applies the palette material to selected faces.

UV Editor
- Displays UVs for the primary selected face.
- Drag points to edit UVs or reset to projected UVs.

Paint (surface paint)
- Paint Target: Floor or Surface.
- Surface paint layers: choose layer, pick texture, adjust radius/strength.

Brush workflow
- Mode: Add or Subtract.
- Shape: choose from the palette.
- Sides: for pyramids/prisms.
- Size X/Y/Z: defaults for new brushes.
- Grid Snap: snap increment.
- Quick Snap: preset buttons.

Bake
- Merge Meshes, Generate LODs, Lightmap UV2 + Texel Size.
- Bake Navmesh with cell/agent settings.

Other
- Show HUD, Show Grid, Follow Grid.
- Debug Logs toggles HammerForge logs.
- History panel (beta).
- Playtest bakes and runs the scene.

Status bar
- Shows current status ("Ready", "Baking...", errors in red, warnings in yellow).
- Errors auto-clear after 5 seconds, success messages after 3 seconds.
- Displays selection count ("Sel: N brushes") when brushes are selected.
- Live brush count with color-coded performance warnings.

## Shortcut HUD
The on-screen shortcut overlay updates dynamically based on your current tool and mode. Toggle it via the Show HUD checkbox in the Build tab. It shows:

| Context | Shortcuts Shown |
|---------|----------------|
| Draw (idle) | Click+Drag, Shift/Alt modifiers, X/Y/Z axis lock, Ctrl+Scroll size, Ctrl+D, Delete |
| Draw (dragging base) | Shift: Square, Alt+Shift: Cube, Click: Height stage, Right-click: Cancel |
| Draw (adjusting height) | Mouse: Change height, Click: Confirm, Right-click: Cancel |
| Select | Click/Shift/Ctrl selection, Escape, Delete, Ctrl+D, Arrow nudge |
| Floor Paint | Click+Drag, B/E/R/L/K tool shortcuts |
| Surface Paint | Click+Drag, radius/strength info |

The HUD also shows current axis lock state (e.g. "[X Locked]").

## Brush Creation (CAD style)
1) Base drag: click and drag to define the base.
2) Height stage: release mouse, move up/down, click to commit.

Modifier keys
- Shift: square base.
- Shift + Alt: cube.
- Alt: height-only.
- X/Y/Z: axis locks (shown in HUD as "[X Locked]" etc.).
- Right-click: cancel.

General keyboard shortcuts
- Delete: remove selected brushes.
- Ctrl+D: duplicate selected brushes.
- Arrow keys: nudge selected brushes (XZ plane).
- PageUp/PageDown: nudge selected brushes (Y axis).
- Escape: clear selection.
- Ctrl+Scroll: adjust brush size.

Paint tool shortcuts (active when Paint Mode is enabled)
- B: Brush tool.
- E: Erase tool.
- R: Rectangle tool.
- L: Line tool.
- K: Bucket fill tool.

## Floor Paint
1. Enable Paint Mode.
2. Open the Floor Paint tab.
3. Choose tool, brush shape (Square or Circle), radius, and layer.
4. Paint in the viewport.

Notes
- **Brush Shape**: Square fills a full box of cells; Circle clips corners using Euclidean distance.
- Live preview updates while dragging.
- Bucket fills a contiguous region (click filled to erase).
- Generated geometry appears under `LevelRoot/Generated`.
- Generated flat floors/walls are DraftBrush nodes and are included in Bake.

### Heightmap Terrain
Heightmaps add vertical displacement to painted floors:
1. Paint cells on a layer using Brush/Rect/Line/Bucket.
2. Click **Import** to load a PNG/EXR heightmap, or **Generate** for procedural noise.
3. Adjust **Height Scale** to control displacement amplitude.
4. Adjust **Layer Y** to set the base height of the layer.

When a layer has a heightmap, its floors are generated as displaced MeshInstance3D nodes (not DraftBrush). These live under `Generated/HeightmapFloors` and are baked directly (bypassing CSG) with trimesh collision shapes.

### Material Blending
The Blend tool paints per-cell material blend weights on filled cells:
1. Fill cells first (Brush/Rect/etc.).
2. Switch to the **Blend** tool.
3. Adjust **Blend Strength** (0.0-1.0) in the dock.
4. Paint over filled cells to set blend weights.

Blend weights drive a two-material shader (`hf_blend.gdshader`). The shader mixes `material_a` and `material_b` based on a per-chunk blend map sampled on the UV2 channel.

## Face Materials and UVs
1. Open the Materials tab.
2. Click `Add` to load a material resource into the palette (example: `materials/test_mat.tres`).
3. Enable `Face Select Mode`.
4. Use the Select tool and click faces in the viewport.
5. Click `Assign to Selected Faces`.

UV editing:
- Open the UV tab after selecting a face.
- Drag UV points to edit.
- Use `Reset Projected UVs` to regenerate UVs from projection.

Notes:
- Face data is stored per DraftBrush face.
- Materials and UVs persist in `.hflevel` saves.

## Surface Paint (3D)
1. Enable Paint Mode.
2. Open the Surface Paint tab and set `Paint Target = Surface` (if needed).
3. Pick a layer and assign a texture.
4. Paint in the viewport.

Notes:
- Radius is in UV space (0.0 to 1.0).
- Surface paint updates the DraftBrush preview immediately.
- Surface paint is separate from floor paint layers.
- If paint affects the floor, set `Paint Target = Surface` in the Surface Paint tab.

## Entities (early)
- Place nodes under `LevelRoot/Entities` or set meta `is_entity = true`.
- Entities are selectable and excluded from bake.
- Entity palette supports drag-and-drop placement.

Entity definitions live in `res://addons/hammerforge/entities.json`.
Example (billboard preview):

```json
{
  "light_point": {
    "class": "OmniLight3D",
    "preview": {
      "type": "billboard",
      "path": "res://addons/hammerforge/icon.png",
      "color": "#ffff00"
    },
    "properties": [
      {"name": "range", "type": "float", "default": 10.0},
      {"name": "energy", "type": "float", "default": 1.0},
      {"name": "color", "type": "color", "default": "#ffffff"}
    ]
  }
}
```

## Bake Output
Bake creates `BakedGeometry`:
- If chunked baking is enabled, it adds `BakedChunk_x_y_z` nodes.
- Each chunk has a MeshInstance3D and StaticBody3D (trimesh) for collision.

Generated flat floor paint brushes are included in the CSG bake. Heightmap floor meshes are duplicated directly into the baked output with trimesh collision shapes (they bypass CSG since they are already ArrayMesh).

Use Face Materials (optional):
- Enables per-face material baking without CSG.
- Subtract brushes are ignored in this mode.

## Save/Load (.hflevel)
- Save .hflevel stores brushes, entities, settings, materials palette, face data, and paint layers.
- Paint layer data includes per-chunk `material_ids`, `blend_weights`, optional `heightmap_b64`, and `height_scale`.
- Load .hflevel restores them. Missing heightmap/material fields default to zero (backward-compatible).
- Autosave can write to a configurable path.

## Capturing Exit-Time Errors
PowerShell command:

```powershell
Start-Process -FilePath "C:\Godot\Godot_v4.6-stable_win64.exe" `
  -ArgumentList '--editor','--path','C:\hammerforge' `
  -RedirectStandardOutput "C:\Godot\godot_stdout.log" `
  -RedirectStandardError "C:\Godot\godot_stderr.log" `
  -NoNewWindow
```

## Troubleshooting
No brushes appear
- Ensure HammerForge is enabled.
- Select LevelRoot.
- Use Create Floor so raycasts hit something.

Subtract does nothing
- Subtract only affects Add brushes and is visible after Bake.
- Pending cuts appear in bright orange-red; once applied they turn standard red.

Paint preview looks wrong
- Regenerate by deleting `LevelRoot/Generated` and paint again.

Dock not showing
- Restart Godot after enabling the plugin.

Face selection not working
- Enable Face Select Mode in the Materials tab.
- Use the Select tool (not Draw).

Material fails to load
- Material `.tres` files must not have a UTF-8 BOM. If Godot reports "Expected '['" on a `.tres` file, re-save it without BOM (or create a fresh one via FileSystem -> New Resource -> StandardMaterial3D).

Heightmap mesh not appearing
- Ensure the active layer has a heightmap assigned (use Import or Generate in the Floor Paint tab).
- Confirm cells are painted first -- heightmap only displaces filled cells.

Blend shader shows only one material
- Paint blend weights using the Blend tool on already-filled cells.
- Verify the blend_map texture is generated (requires cells with non-zero blend weights).
