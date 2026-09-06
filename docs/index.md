# HammerForge

**Brush-based level editor for Godot 4.7+**

Draw rooms, carve doors, paint terrain, and bake to optimized meshes — all
inside the Godot editor.

![Interior of a HammerForge level: a colonnaded hall leading to a raised dais, with a galleried upper level](images/showcase_hero.png)

HammerForge is a single `addons/` folder. No external tools, no custom builds,
no export plugins. Drop it in, enable, draw.

!!! warning "Early alpha"
    This is a solo hobby project. It's buggy and rough around the edges.
    Testing and issue reports are genuinely welcome.

## How it works

| Step | | |
|---|---|---|
| **1. Draw a floor** | Drag a base, click to set height. | ![Step 1](images/seq_1_draw.png) |
| **2. Raise the walls** | Add walls, leave a gap for the door. | ![Step 2](images/seq_2_walls.png) |
| **3. Detail and materials** | Platform, ramp, pillars, prototype textures. | ![Step 3](images/seq_3_detail.png) |
| **4. Test it** | The Console checks, then bakes and plays. | ![Step 4](images/seq_4_test.png) |

## Inside the editor

HammerForge has its own dock, main-screen entry, and viewport tools.

![The HammerForge dock and viewport inside the Godot editor](images/ui_editor_3d.png)

The dock changes mode with the task — Build, Paint, Objects, and Test each
swap the controls and the viewport hint.

=== "Build"
    ![Build tab](images/ui_dock_build.png)

=== "Paint"
    ![Paint tab](images/ui_dock_paint.png)

=== "Objects"
    ![Objects tab](images/ui_dock_objects.png)

=== "Test"
    ![Test tab](images/ui_dock_test.png)

## The Console

A status board for the level: geometry budget, bake state, material palette,
spawn points, autosave and session log.

![The HammerForge Console status board](images/ui_console.png)

## Everything is configurable, and every switch says why

The Console's **Controls** tab is the whole settings surface in one place —
grouped by what a setting actually affects, with a one-line reason under each
switch rather than a bare label. There is a search box, and descriptions can be
turned off once you know your way around.

![The HammerForge Console Controls tab, showing the Viewport, Bake and Safety net groups](images/ui_console_controls.png)

Three groups, because there are only three questions worth separating:

- **Viewport** — *what you see while building. None of these change the level.*
  Grid and snapping, the shortcut HUD, subtract preview, texture lock, cordon.
  Safe to change mid-build; nothing here touches what ships.
- **Bake** — *how drafts become the meshes and collision that ship.* Mesh
  merging, LODs, UV unwrapping, lightmap UV2, navmesh, MultiMesh instancing.
  These are the trade-offs between bake time and frame time, and each one says
  which way it costs you.
- **Safety net** — *what survives a crash, and what tells you why one happened.*
  Autosave interval, how many backups to keep, save compression, debug logging.

The header line above the tabs is live: brush count, entity count and vertex
total for the open level, re-checked on demand.

## Next steps

- [Install and Upgrade](HammerForge_Install_Upgrade.md)
- [User Guide](HammerForge_UserGuide.md)
- [Features and Reference](features.md)
