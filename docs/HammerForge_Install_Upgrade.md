# HammerForge Install + Upgrade

Last updated: February 15, 2026

This guide covers installing, upgrading, and recovering the HammerForge plugin in Godot 4.6+.

## Requirements
- Godot Engine 4.6 (stable) or newer.
- A 3D scene in your project to host `LevelRoot`.

## Install
1. Copy `addons/hammerforge` into your project.
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
3. Open any 3D scene and click in the viewport to auto-create `LevelRoot`.
4. Verify the dock appears, a `LevelRoot` node exists in the scene tree, and the Build tab shows brush tools and grid snap controls.

## Upgrade
1. Close Godot.
2. Back up your project (including `.hflevel` files).
3. Replace the existing `addons/hammerforge` folder with the new version.
4. Reopen the project and re-enable the plugin if prompted.
5. Open a 3D scene and click the viewport to ensure `LevelRoot` is active.

## Cache Reset (Recovery)
If the plugin fails to load, the dock is missing, or tools behave incorrectly:
1. Close Godot.
2. Delete the project cache folder `./.godot/editor`.
3. Reopen the project and enable the plugin again.
4. If resources look stale, delete `./.godot/imported` and reopen.

## Compatibility Notes
- HammerForge expects Godot 4.6+.
- New `.hflevel` fields are backward compatible. Missing keys fall back to defaults on load.
- `.glb` export requires a successful bake first.

## Migration Checklist
Use this when jumping across versions that modify the data model or bake pipeline:
1. Back up your project and any `.hflevel` files.
2. Open a level and run **Validate Level** (use **Validate + Fix** if needed).
3. Save the level to update new fields in the `.hflevel`.
4. Run a bake and a dry run to confirm expected counts.
5. Export a `.glb` if your pipeline depends on it.
