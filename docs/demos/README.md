---
description: "How HammerForge's screenshots and demo video are generated, and the harness that records the editor being driven by a real mouse."
---

# Demo Media

Last updated: September 7, 2026

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
| `docs/images/showcase_hero.png` | Interior down the colonnade toward the dais |
| `docs/images/showcase_overview.png` | The level from above, showing the window bays and towers |
| `docs/images/showcase_gallery.png` | Low view up through the columns to the gallery |

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
python tools/capture_ui.py
```

The plugin is **not** enabled in `project.godot`. The wrapper enables it for the
duration of the run and removes it again, because an `EditorPlugin` that reads
an environment variable and can call `get_tree().quit()` should not load during
normal editing -- a stray `HF_DOCSHOT=1` would otherwise close your editor
mid-work. The env var remains as a second gate for anyone enabling the plugin
by hand.

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

Use the wrapper rather than editing anything by hand:

```bash
python tools/capture_ui.py
```

It suppresses the onboarding card, cuts `project.godot` back to the HammerForge
plugin alone so nothing you have enabled locally appears in the editor's
main-screen bar, resets the open-scene list so the tab bar is not cluttered,
runs the capture, and puts both files back.

The swap is recoverable, not merely careful. It refuses to start if either
tracked file already has uncommitted changes, so it never backs up an
already-mutated file; backups carry a marker, so a run that dies before
restoring is healed by the next invocation instead of stacking a second swap on
top; and restoration runs from a `finally` block, so it survives exceptions and
Ctrl-C. Whatever else you have enabled is your own tooling, not part of
HammerForge, and must not appear in user-facing screenshots.

Output:

| File | Shot |
|------|------|
| `ui_editor_3d.png` | Dock, viewport toolbar, scene tree and inspector |
| `ui_dock_build.png` / `ui_dock_paint.png` / `ui_dock_objects.png` / `ui_dock_test.png` | Each dock mode |
| `ui_console.png` | The Console status board |
| `ui_console_controls.png` | The Console Controls tab: every setting, grouped |
| `seq_1_draw.png` … `seq_4_test.png` | The four-step how-it-works strip (cropped) |

Three editor behaviours the plugin has to work around, all commented in the
script: the editor restores its previous session *after* `_enter_tree`, so the
showcase must be opened late or it loses the active tab; opening a level hands
the main screen back to the HammerForge plugin, so each screen is re-selected
immediately before its own capture; and `F`-to-frame never reaches the viewport,
so the editor camera is positioned directly.

## Captures are not byte-stable

Re-running a capture with no changes still produces slightly different PNGs.
The Console header carries a live `Checked HH:MM:SS` timestamp, and antialiasing
around dock text varies with layout timing, so a few kilobytes shift each run.

Only commit regenerated images when something actually changed. `git restore
docs/images/` discards a no-op run.

## Not covered by the stills

Stills cannot show a gesture. Drawing a brush, dragging a cut through a wall and
extruding a face only make sense in motion, which is what the clip below covers.
The bake pipeline running is still not captured anywhere.

## Video clips

| File | Shows |
|------|-------|
| `carve_a_doorway.mp4` | An empty grid to a played level: three walls drawn, a cut brush dragged through the far one, the cut applied, then Test Level and a first-person walk up to the doorway. 55s, 1280x720, no audio. |

Derived assets, both committed and both regenerated from the clip:

| File | Use |
|------|-----|
| `../images/demo_carve_a_doorway.gif` | The README. GitHub does not play a repository MP4 inline, so the README carries a 19-second GIF of the cut and the playtest, linking to the full clip on the docs site. |
| `../images/demo_carve_a_doorway_poster.png` | The `poster` frame for the `<video>` element on the docs home page. Without it the browser shows frame one, which is an empty grid. |

```bash
# GIF for the README: the cut, the apply, and the playtest.
ffmpeg -ss 36 -t 19.4 -i docs/demos/carve_a_doorway.mp4   -vf "fps=12,scale=640:-1:flags=lanczos,palettegen=max_colors=128:stats_mode=diff" palette.png
ffmpeg -ss 36 -t 19.4 -i docs/demos/carve_a_doorway.mp4 -i palette.png   -lavfi "fps=12,scale=640:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"   docs/images/demo_carve_a_doorway.gif

# Poster frame.
ffmpeg -ss 43.5 -i docs/demos/carve_a_doorway.mp4 -frames:v 1   docs/images/demo_carve_a_doorway_poster.png
```

### Recording harness

The clip is produced by driving the real editor with the real OS mouse while OBS
captures the editor window.

```bash
# OBS must be running with obs-websocket enabled. The password is read from the
# environment and never written to a file.
OBS_WS_PASSWORD=... tools/record_demo_video.sh carve_a_doorway

# Rehearse without recording, for iterating on geometry and timing.
HF_DRY=1 tools/record_demo_video.sh carve_a_doorway
```

| File | Role |
|------|------|
| `tools/record_demo_video.sh` | Orchestrates a take: environment swap, editor launch, beat resolution, OBS, encode. |
| `tools/beats/*.beats` | The timeline for one demo, one action per line. |
| `tools/mouse_beats.ps1` | Plays a resolved beat file against the real mouse and keyboard. |
| `tools/obs_ctl.py` | obs-websocket v5 client: point a capture at a window, record, and the diagnostics for when it captures the wrong one. |
| `tools/win_rect.ps1` | Win32 window geometry. `GetClientRect` plus `ClientToScreen`, because Godot's own window position is relative to the current screen. |

The environment swap is delegated to `capture_ui.py` rather than reimplemented,
so there is one copy of the crash-safe backup and restore rather than two.

#### Writing beats

Coordinates are resolved against the live editor just before playback:

| Placeholder | Means |
|-------------|-------|
| `w(x,y,z)` | A point in the level, projected to viewport pixels by the editor's own camera. |
| `up(h)` | Extrude the brush being drawn to `h` units tall. |
| `vx(f)` / `vy(f)` | A fraction of the 3D viewport. |
| `cx(px)` / `cy(px)` | Pixels from the window's client origin, for dock buttons and the viewport toolbar, which are outside the 3D viewport. |

`w()` exists because screen fractions cannot say where a brush lands in the
level. A room drawn against them is only ever as good as the guess, and the
first attempt at this demo produced walls in the wrong places and a cut brush
that missed the wall entirely.

`up()` is a pixel gesture rather than a height, because the draw tool derives
height from mouse travel: `grid_snap + pixels_up / height_pixels_per_unit`,
snapped to the grid. The resolver reads both numbers from the editor at runtime
rather than hard-coding them.

#### Why it refuses to run alongside another editor

`capture_ui.py` rewrites `project.godot` for the duration of a take. Any editor
already holding that file raises a "files have been modified outside Godot"
dialog -- a real window, of the same window class, which sits on top of the
playtest and gets recorded instead of it. A second editor can also save the
project back at a different engine version. The harness therefore checks for
other Godot processes and stops; `HF_ALLOW_STRAY_EDITOR=1` overrides it.

#### Godot behaviours it has to work around

- **The editor window stops presenting frames when a playtest launches.** A
  capture left pointing at it goes black, so the take has to cut to the
  playtest window.
- **The playtest window is owned by the editor for about twelve seconds** before
  the game's own process takes it over, and the handover destroys the window
  being captured. Everything worth showing has to happen inside that window,
  which is why the walk is short and the clip cuts when it does.
- **Two windows answer to the playtest's title** during that period, under one
  identical `title:class:exe` string. `capture --index` picks between them.
- **OBS falls back by the field named in `priority`** when the exact window is
  gone -- class hands back any other Godot window, executable hands back the
  editor. Neither is what you want, so the default is left alone.

## Planned clips

Ranked by what they prove rather than by how impressive they look. Each is one
beat file and one run -- the work is designing the beats, not recording.

| | Clip | What it answers |
|---|---|---|
| 1 | **Entities and I/O** -- a trigger wired to a door: place both, connect them, playtest, walk into the trigger, the door opens | "Why not just use CSG boxes?" It is the only clip that proves HammerForge makes a *playable level* rather than geometry |
| 2 | **Paint floors and terrain** -- paint a heightmap floor, blend a second material in, drop an auto-connector ramp, then walk it | "Is this just grey boxes?" Painting is a gesture; a still cannot show it, which is the whole argument for video |
| 3 | **Reshaping** -- vertex editing and face extrude: drag a vertex, pull a wall out, make a wedge | "Am I locked into boxes?" Answered in about twenty seconds, and cheap to script |
| 4 | **Texturing a blockout** -- palette, eyedropper, surface paint | The biggest visual before/after available, and the best thumbnail of the set |
| 5 | **Bake: what you actually get** -- collision modes, navmesh, the Console's geometry budget | The question a serious adopter asks. Better as documentation than as a video |

### The playtest ceiling

The playtest window lives about **nine seconds** before Godot hands it back to
the editor and destroys the window being captured. `carve_a_doorway` therefore
ends on roughly five usable seconds of gameplay, and the walk had to be cut
short to fit. Every "...and then play it" ending hits the same limit.

The fix is to stop treating a clip as one take: **record the editor work and the
playtest as two captures and concatenate them.** The harness already knows how
to drive the editor, wait for the playtest window and record either one, so this
is plumbing rather than new capability. Worth building before clips 1 and 2,
both of which want a long look at the running level.

### Publishing

Clips go on the HammerForge YouTube channel (a brand account, so it can be
handed over without moving the videos) and are linked from `docs/index.md`.

Keep them in one playlist with consistent titles -- `HammerForge: <verb> <thing>`.
YouTube weights playlists and session watch-time, so four related sixty-second
clips outperform four unrelated ones.

### Also outstanding

- The Apply step does not land in the published `carve_a_doorway` take: the
  toolbar still reads "1 to review" at 44s. The doorway appears anyway because
  Test Level applies pending cuts at bake, so the clip is honest, but the beat
  is missing. One line in the beat file and a re-record.
- The YouTube channel needs phone verification before description links become
  clickable.

## Audio

Clips are encoded with `-an`. A window-scoped screen capture says nothing about
what the machine's speakers were playing, and these demos have no narration, so
the track is dropped rather than shipped silent-by-luck.
