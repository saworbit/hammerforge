# HammerForge MVP: Step-by-Step Guide

This guide walks through building the **HammerForge** MVP for Godot 4.6 (released January 26, 2026). The target is a minimal editor addon that exposes CAD-style brush creation (drag base + height), box/cylinder brushes, staged CSG add/subtract, a dock UI, selection, and a one-click bake that turns the combination into optimized static geometry with collision.

---

## Target & Scope
* **Engine:** Godot 4.6 stable.
* **Focus:** In-editor blockout for FPS rooms (<5 minutes to mock up); one-click bake to performant static meshes.
* **Files:** ~15 core files in `res://addons/hammerforge/`.
* **Outcome:** Step-by-step deliverables described below cover setup, UI, brush placement, CSG, bake, and testing.

## Time Breakdown

| Step | Time | Milestone |
| --- | --- | --- |
| 1–3 | 30 min | Addon loads in editor |
| 4–6 | 1 h | Dock UI + LevelRoot node |
| 7–9 | 2–3 h | Click-to-place brush creation |
| 10–12 | 3–4 h | CSG operations + bake logic |
| 13 | 1 h | Test/polish one-room FPS blockout |
| **Total** | ~1 day | Playable MVP |

## Prerequisites
1. Download Godot 4.6 stable from [godotengine.org/download](https://godotengine.org/download).  
2. Know GDScript and the EditorPlugin API.  
3. Create an empty 3D project via **File ▶ New Project ▶ 3D Rendering ▶ Forward+**.

## File Layout (create under `res://addons/hammerforge/`)

```
addons/
└── hammerforge/
    ├── plugin.cfg
    ├── plugin.gd          # EditorPlugin entry (adds LevelRoot, dock, captures viewport input)
    ├── icon.png           # 64×64 plugin icon
    ├── dock.tscn          # Dock UI scene
    ├── dock.gd            # Dock query/bake controls (tool, shape, grid, floor)
    ├── level_root.gd      # Root node that manages CSG brushes and baking
    ├── shortcut_hud.tscn  # On-screen shortcut legend (editor UI)
    ├── shortcut_hud.gd    # HUD script for layout + label
    ├── editor_grid.gdshader # Shader-based editor grid
    ├── brush_instance.gd  # Semi-transparent CSG brush shape
    ├── brush_manager.gd   # Brush lifecycle helper
    └── baker.gd           # Bake helper that creates meshes + collision
```

## Step-by-Step Build

1. **plugin.cfg** – Define the Godot plugin block with `name`, `author`, `version`, and `script="plugin.gd"`. This exposes the addon in **Project ▶ Project Settings ▶ Plugins**.

2. **plugin.gd** – Create a `@tool` `EditorPlugin` that:
   * Registers `LevelRoot` as a custom type.
   * Instantiates and docks `dock.tscn` to the left viewport.
   * Forwards 3D input to handle CAD-style dragging (base → height).
   * Auto-creates `LevelRoot` on the first click if missing.

3. **Dock scene + script** – Build `dock.tscn` with:
   * Tool selector (Draw/Select), Add/Subtract, Shape (Box/Cylinder).
   * Size, Grid Snap, Create Floor, Apply Cuts, Clear Pending Cuts, Bake, Clear.
   * `dock.gd` exposes `get_operation()`, `get_brush_size()`, `get_shape()`, `get_grid_snap()`.
   * The script keeps a reference to `LevelRoot` in the current scene.

4. **LevelRoot** – `level_root.gd` extends `Node3D`, sets up a `CSGCombiner3D`, a `PendingCuts` node, a `BrushManager`, and a `Baker`.
   * LevelRoot can be a single node in the scene; it creates helper children on _ready().
   * CAD-style draw flow: drag to set base, release to set height, click to commit.
   * `place_brush(mouse_pos, operation, size)` can still place a default brush.
   * Subtract brushes are staged until `Apply Cuts` or Bake.
   * Commit Cuts bakes and neutralizes subtract materials so carved faces match.
   * `bake()` delegates to `Baker` to convert CSG into baked meshes + collision.
   * `clear_brushes()` empties the manager and queues existing brushes.

5. **BrushInstance** – `brush_instance.gd` is a transparent `CSGBox3D` with exported `brush_size` and `brush_operation`, automatic color/transparency, and size/operation setters.

6. **BrushManager** – Simple helper that tracks brush instances for cleanup (used from `LevelRoot.clear_brushes()`).

7. **Baker** – Pulls the generated mesh from `CSGCombiner3D`, creates a `MeshInstance3D`, and attaches a `StaticBody3D` with a `CollisionShape3D` based on the trimesh.

8. **Grid Snap** – `LevelRoot` snaps hit positions to `grid_snap` (default 16). Expose `grid_snap` from the dock UI for quick control.

9. **Dock Bindings** – Bind the dock spinboxes to call `LevelRoot.place_brush` with the desired size, and `OptionButton` selection to toggle between `CSGShape3D.OPERATION_UNION` and `OPERATION_SUBTRACTION`.

10. **Bake & Clear Buttons** – Bake button executes `LevelRoot.bake()`, Clear removes existing brushes (and resets the CSG combiner if needed).

11. **Preview Scene** – Open any 3D scene, click once to auto-create `LevelRoot`, then use **Create Floor** for a collidable surface.

12. **Optional Extras** – Selection mode, duplicate/drag/nudge, numeric input overlay, and ortho views.

13. **Test** – In the editor:
    * Use Draw tool to click-drag a base, release, then click to set height.
    * Use Subtract mode to place cut shapes, then click **Apply Cuts**.
    * Click Bake: a static `MeshInstance3D` + `StaticBody3D` appears with collision.
    * Add an FPS controller (e.g., `SRCoders FPS Controller` from Asset Library) and hit Play to move around the baked room.

## Post-MVP UX Upgrades

These are quality-of-life improvements added after the MVP core:

1. **Editor Theme Binding** â€“ Dock inherits `EditorInterface.get_base_control().theme`, with live theme refresh.
2. **Quick Snap Presets** â€“ Toggle buttons for 1/2/4/8/16/32/64 with a shared ButtonGroup.
3. **Shortcut HUD** â€“ On-screen cheat sheet in the 3D viewport, toggleable from the dock.
4. **Dynamic Editor Grid** â€“ Shader-based PlaneMesh that follows the active axis and snap size.

## Troubleshooting Notes

* **CSG slow** – keep brush counts low (<50) during editing; the bake step produces the optimized mesh that is used at runtime.
* **No hit detected** – ensure a floor mesh exists and is not excluded from the raycast.
* **Plugin not showing** – confirm `plugin.cfg` is loaded and the addon is enabled under **Project ▶ Project Settings ▶ Plugins**.

## Next Steps After MVP

1. Introduce entity palette & FGD parsing (Phase 2 core).  
2. Improve optimization (chunked baker, LOD, navmesh).  
3. Add UI polish and import/export support.  
4. Package for the Asset Library (MIT license, metadata, ZIP).
