# Demo Media

Last updated: September 6, 2026

## Current approach: generated stills

Screenshots are generated from a committed scene rather than captured by hand,
so they can be regenerated whenever geometry, materials, or defaults change.

```bash
# 1. Build the showcase level (headless, writes samples/hf_demo_showcase.tscn)
godot --headless -s res://tools/build_showcase_scene.gd --path .

# 2. Render the stills into docs/images/ (must NOT be headless)
godot --path . -s res://tools/capture_showcase.gd
```

Step 2 requires a real rendering context: under `--headless` the dummy renderer
writes blank images, and the script refuses to run rather than emit them.

Current output, all 1920x1080 and referenced from `README.md`:

| File | Shot |
|------|------|
| `docs/images/showcase_hero.png` | Elevated three-quarter view of the whole block-out |
| `docs/images/showcase_doorway.png` | Interior view through the doorway into the corridor |
| `docs/images/showcase_materials.png` | Platform and ramp with four prototype materials |

Edit `LAYOUT` in `tools/build_showcase_scene.gd` to change the level, or `SHOTS`
in `tools/capture_showcase.gd` to change framing. The level AABB is
x -17..31, y -1..10, z -15..13; elevated cameras must clear the 10-unit walls
or the nearest corner fills the frame.

## Editor UI screenshots

The interface shots and the how-it-works strip are captured by
`addons/hf_docshot`, a dev-only editor plugin. It opens the showcase scene,
drives the editor's own 3D camera, cycles the dock tabs, switches main screens,
and writes the images before quitting.

```bash
HF_DOCSHOT=1 godot --editor --path .
```

The plugin is inert unless `HF_DOCSHOT=1`, so leaving it enabled costs nothing
during normal editing.

### Composing the shot

Screenshots are product shots, not screenshots of a dev checkout. Before
capturing, the plugin composes the editor:

- **The onboarding guide card is suppressed.** It otherwise fills the top ~40%
  of the dock with "Step 1 of 2" tutorial chrome. Turn it off first:
  `godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --show-welcome=false`
- **Godot's own docks are hidden** (Scene, FileSystem, Inspector). They are not
  HammerForge UI: the Inspector shows a column of truncated bake property
  labels, and the FileSystem shows repository files. Hiding them roughly
  doubles the viewport width. This is done live, because Godot clamps dock
  splitter offsets written into `editor_layout.cfg`.
- **The selection is cleared** after the camera is placed, so the transform
  gizmo does not sit in the middle of the level.
- **The scene is verified active.** `open_scene_from_path` alone is not enough;
  the project main scene can reclaim the tab, so the capture retries until
  `get_edited_scene_root().scene_file_path` matches.

Before capturing for publication, strip the contributor MCP server from the
environment so it does not appear in the editor's main-screen bar, and clear the
open-scene list so the tab bar is not cluttered. Back both files up first:

- `project.godot` — remove `res://addons/godot_mcp/plugin.cfg` from
  `[editor_plugins] enabled` and the `MCPRuntimeProbe` autoload.
- `.godot/editor/editor_layout.cfg` — set `open_scenes=PackedStringArray()` and
  `current_scene=""`.

Restore both afterwards. The MCP server is build tooling for contributors; it is
not part of HammerForge and must not appear in user-facing screenshots.

Output:

| File | Shot |
|------|------|
| `ui_editor_3d.png` | Dock, viewport toolbar, scene tree and inspector |
| `ui_dock_build.png` / `ui_dock_paint.png` / `ui_dock_objects.png` / `ui_dock_test.png` | Each dock mode |
| `ui_console.png` | The Console status board |
| `seq_1_draw.png` … `seq_4_test.png` | The four-step how-it-works strip (cropped) |

Three editor behaviours the plugin has to work around, all commented in the
script: the editor restores its previous session *after* `_enter_tree`, so the
showcase must be opened late or it loses the active tab; opening a level hands
the main screen back to the HammerForge plugin, so each screen is re-selected
immediately before its own capture; and `F`-to-frame never reaches the viewport,
so the editor camera is positioned directly.

## Not covered by the stills

Nothing currently captures the bake pipeline running, or any interaction that
only makes sense in motion (dragging a brush out, extruding a face). Those still
need a screen recording.

## Video clips (deferred)

Screen-recorded clips were planned in February 2026 and never produced. They are
deferred rather than dropped; stills cover the immediate "what does this look
like" gap. If clips are revisited, keep them at 1280x720 or 1920x1080 and name
them `demo_<topic>_vX.Y.Z.mp4` in this directory.
