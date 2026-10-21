# HammerForge

Brush-based level editing inside the Godot editor. Draw rooms, carve doorways,
paint terrain and bake to optimised meshes without leaving Godot.

Requires Godot 4.7 or newer.

## Enable it

This folder is the whole plugin.

If it is already at `res://addons/hammerforge/`, turn it on under
**Project > Project Settings > Plugins** and tick **Enable**. There is no need to
restart the editor.

Installing by hand? Copy this `hammerforge` folder into your project's `addons/`
folder first, so it ends up at `res://addons/hammerforge/`. Nothing outside that
path is needed.

## Your first level

A **HammerForge** entry appears in the main screen switcher beside 2D, 3D and
Script. A dock appears on the left.

1. **Create Starter Level** in the dock gives you a floor, a sun and a player
   spawn.
2. In **Build**, choose **Draw** and drag in the viewport to set the base, then
   click again to set the height.
3. **Test > Test Level (Bake + Play)** checks the level, bakes it, and drops you
   in with a first-person controller.

The Console, in the HammerForge main screen, reports anything wrong with a level
before you bake it.

## Upgrading

Replace this whole folder with the new version.

That means anything you add inside it is lost when you upgrade, so keep your own
editor tools in `res://hammerforge_tools/` instead. HammerForge scans that folder
on startup and it sits outside the plugin, so an upgrade cannot delete it.

## What this plugin writes

Inside your project, and only when you use the features that need them:

- `res://.hammerforge/` for autosaves and editor scratch state
- `res://hammerforge_entities.json` for your entity definitions, if you add any
- `res://prefabs/` for prefabs you save

## Links

- Documentation: <https://saworbit.github.io/hammerforge/>
- Source and issues: <https://github.com/saworbit/hammerforge>

Licensed under the MIT License. A copy ships as `LICENSE` beside this file.
