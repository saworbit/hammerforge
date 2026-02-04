# HammerForge User Guide

Last updated: February 5, 2026

This guide covers the current HammerForge workflow in Godot 4.6: brush-based greyboxing, bake, entities, and floor paint.

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

Paint Mode (floor paint)
- Enables paint input in the viewport.
- Paint Tool: Brush, Erase, Rect, Line, Bucket.
- Paint Radius: brush radius in grid cells.
- Paint Layer: choose active layer, add/remove layers.

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

## Brush Creation (CAD style)
1) Base drag: click and drag to define the base.
2) Height stage: release mouse, move up/down, click to commit.

Modifier keys
- Shift: square base.
- Shift + Alt: cube.
- Alt: height-only.
- X/Y/Z: axis locks.
- Right-click: cancel.

## Floor Paint
1. Enable Paint Mode.
2. Choose tool and radius.
3. Paint in the viewport.

Notes
- Live preview updates while dragging.
- Bucket fills a contiguous region (click filled to erase).
- Generated geometry appears under `LevelRoot/Generated`.
- Generated floors/walls are DraftBrush nodes and are included in Bake.

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

Generated floor paint brushes are included in the bake.

## Save/Load (.hflevel)
- Save .hflevel stores brushes, entities, settings, and paint layers.
- Load .hflevel restores them.
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

Paint preview looks wrong
- Regenerate by deleting `LevelRoot/Generated` and paint again.

Dock not showing
- Restart Godot after enabling the plugin.
