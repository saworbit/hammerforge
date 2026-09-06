# HammerForge

**Brush-based level editor for Godot 4.7+**

Draw rooms, carve doors, paint terrain, and bake to optimized meshes — all
inside the Godot editor.

![A HammerForge block-out viewed from above](images/showcase_hero.png)

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

## Next steps

- [Install and Upgrade](HammerForge_Install_Upgrade.md)
- [User Guide](HammerForge_UserGuide.md)
- [Features and Reference](features.md)
