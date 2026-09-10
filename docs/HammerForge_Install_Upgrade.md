---
description: "Install HammerForge into a Godot 4.7+ project, enable the plugin, and upgrade an existing install without losing level data."
---

# HammerForge Install + Upgrade

Last updated: September 10, 2026

This guide covers installing, upgrading, and recovering HammerForge for Godot 4.7+.

## Requirements

- Godot Engine 4.7 stable or newer.
- A 3D scene in your project to host `LevelRoot`.

## Install HammerForge

1. Copy `addons/hammerforge` into your project.
2. Enable **HammerForge** in **Project → Project Settings → Plugins**.
3. Open any 3D scene. In the empty-state banner, choose **Create Starter** for a floor, sunlight, and player spawn, or **Create Empty** for only `LevelRoot`.
4. Verify **HammerForge** appears in the main-screen switcher at the top of the editor, beside **2D**, **3D** and **Script**, wearing the HammerForge mark. Opening it shows the Console.
5. Verify the left dock is titled **HammerForge** and shows **Build**, **Paint**, **Objects**, and **Test**, with **Draw**, **Select**, **Paint**, **More**, and **Help** in the primary toolbar.
6. Draw a brush, then use **Test → Test Level (Bake + Play)** to verify the complete workflow.

An intentional left-click with Draw active can create an empty root. Camera navigation, right-clicks, and other passive viewport input do not modify the scene.

## Upgrade

1. Close Godot.
2. Back up your project, including `.hflevel` and `.hfprefab` files.
3. Replace the existing `addons/hammerforge` folder with the new version.
4. Reopen the project and re-enable the plugin if prompted.
5. Open a level and run **Test → Check Only**, followed by **Test Level**, to verify validation, bake, and play.

## Cache Reset (Recovery)

If the plugin fails to load, the dock is missing, or tools behave incorrectly:

1. Close Godot.
2. Delete the project cache folder `.godot/editor`.
3. Reopen the project and enable the plugin again.
4. If resources still look stale, delete `.godot/imported` and reopen.

## Compatibility Notes

- HammerForge targets Godot 4.7+.
- New `.hflevel` fields are backward compatible; missing keys fall back to defaults.
- `.glb` export requires a successful bake first.
- No editor bridge or MCP server is vendored in this repository, and none is required to use HammerForge.

## Migration Checklist

1. Back up the project and authored level/prefab files.
2. Open a level and run **Test → Check Only**; apply offered fixes deliberately.
3. Save the level to persist newly introduced fields.
4. Run **Bake Only** and **Test Level** to confirm geometry and runtime behavior.
5. Export a `.glb` if your downstream pipeline depends on it.
