---
description: "Measured costs of picking, editing, baking, saving and opening a HammerForge level from 100 to 3,000 brushes, and the limits the code enforces."
---

# HammerForge Performance and Limits

Last updated: October 23, 2026

How HammerForge's own work grows with the size of a level, measured rather than
guessed, and the caps the code puts on single operations. Every time and size on
this page comes from one run of
[`tools/benchmark_level_scale.gd`](https://github.com/saworbit/hammerforge/blob/main/tools/benchmark_level_scale.gd)
on the machine named below, on 22 October 2026, except **Bake by layout** and
**Round brushes**, which come from a second run on 23 October; the few figures
worked out from them say how. Run it on your own machine: the numbers move with the hardware,
and the shape is what carries over.

## The short version

- **Nothing caps the number of brushes in a level.** The Status board's
  **Geometry budget** and the dock's health label are advice. They turn amber
  above 100 brushes and entities, past which placing a brush took longer than a
  frame, and red above 1,000, where undoing one took over a tenth of a second.
- **What grows with brush count is the pause after placing or undoing.** Resizing
  one brush took 0.40 ms at 100 brushes and 4.87 ms at 3,000, and the check after
  it 1.62 ms at 3,000: it looks at the brushes the step touched, where it used to
  walk every brush, 296 ms at 3,000
  ([#1619](https://github.com/saworbit/hammerforge/issues/1619)). Placing a brush
  and undoing one record the whole level: 163 ms and 199 ms at 3,000, and the
  undo's check still walks every brush, because that undo rebuilds them all.
- **Picking stays cheap.** A hover pick took 2.58 ms a mouse move at 3,000 brushes.
- **A full bake took 237 ms at 1,000 brushes and 848 ms at 3,000**, headless. In
  the editor the default bake also waits for one editor frame every 8 brushes:
  376 frames at 3,000.
- **Chunking and Bake Changed did not shorten the bake consistently.** Both took
  about as long as a plain full bake and waited through the same frames.
- **Save a big scene as `.scn`.** At 3,000 brushes the `.scn` was 928 KB against
  10,440 KB of `.tscn`, and opened in 953 ms against 2,543 ms. It keeps its link
  to the `.hflevel`, and Save Scene As carries the level file's record across.
- **An agent's calls over the bridge grow slowly with the level:** 3 ms a call
  at 111 brushes and 48 ms at 1,600. A placement records only what it made, near
  2 ms at any size; the cuts, stairs and wires still record the whole level
  ([#1786](https://github.com/saworbit/hammerforge/issues/1786)).
- **Save Level and autosave stop the editor while they take the level:** 179 ms
  at 1,000 brushes and 566 ms at 3,000, every five minutes by default.

## How it was measured

| | |
|---|---|
| Machine | AMD Ryzen 9 5900X, 12 cores and 24 threads; 31.9 GiB of memory as Godot reports it |
| OS | Windows 11 Home, version 10.0.26300 |
| Godot | 4.7-stable (official), 5b4e0cb0f, run headless |
| HammerForge | `main` at a6348abf, with the change that adds this page, which also stops a bake rereading two settings once for every brush |
| Date | 22 October 2026 |
| Run time | 364.8 s for the whole run |

```
godot --headless -s res://tools/benchmark_level_scale.gd --path . -- --counts=100,300,1000,3000 --repeats=5
```

- **The level** is N box brushes, 2 m on a side, on a 4 m grid. No materials, no
  entities, no cuts, and the default bake settings. A real level with textures,
  cuts and entities costs more than this; read these figures as the floor.
- **Each figure is the median of 5 runs.** Within a run a pick is the mean of 50
  pointer positions, and an edit the mean of 10.
- **Headless, so nothing is drawn.** Every time is HammerForge's work and Godot's
  under it, with no rendering. Where the editor adds frames of its own, the
  tables count the frames rather than time them, because a frame's length
  depends on the editor's frame rate and on what is on screen.
- **The machine was a desktop in use**, with other Godot processes running beside
  the benchmark, so read small differences between two cells with care.
- **Sizes are in KB of 1,024 bytes.**

Without arguments the script measures 100, 300 and 1,000 brushes with 3 runs
each. `--counts=` takes a comma list of brush counts, `--repeats=` the runs
per figure, and `--only=` the parts to measure (`picks`, `edits`, `bakes`,
`files`, `round`). It writes only into a folder of its own under `user://`, which it
removes when it ends, and never touches the editor's preferences.

## Picking

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Pointer positions over a brush, of 50 | 24 | 30 | 28 | 32 |
| Hover pick, one mouse move (ms) | 0.09 | 0.33 | 0.50 | 2.58 |
| Click pick (ms) | 0.18 | 0.46 | 0.93 | 4.42 |

The Select tool picks on every mouse move with no button held, and a click picks
once. Both test each brush's world box before the exact test
([#1387](https://github.com/saworbit/hammerforge/issues/1387)), so they stay well
inside a frame. The camera sat above one corner of the grid and the pointer
swept across the view; the first row says how many of the 50 positions were
over a brush.

## Editing

Measured again on 23 October 2026 with `--only=edits --repeats=5`, on the same
machine, after the change check stopped walking every brush
([#1619](https://github.com/saworbit/hammerforge/issues/1619)).

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Resize one brush, with its undo step (ms) | 0.40 | 0.62 | 1.80 | 4.87 |
| Place one brush, with its undo step (ms) | 4.32 | 14.1 | 53.3 | 163 |
| Undo that placement (ms) | 5.41 | 16.9 | 64.5 | 199 |
| Change check after the resize (ms) | 1.17 | 1.18 | 1.32 | 1.62 |
| Change check after the placement (ms) | 1.84 | 3.51 | 9.61 | 26.9 |
| Change check after its undo (ms) | 6.30 | 19.2 | 69.1 | 212 |

- **Resize one brush** is a handle drag as it commits: one undo step that records
  only that brush.
- **Place one brush** is drawing a box. Its undo step records the whole level,
  because a new brush changes which brushes exist, and **Undo** puts the whole
  level back. Deleting records the whole level in the same way.
- **Change check** is the pass the plugin runs after every step that lands in the
  undo history, Undo and Redo included (`HFBrushChangeTracker.reconcile_step()`),
  so that a change Godot's own gizmo, Inspector or undo made reaches Bake Changed
  and the level's records. It compares the brushes the step can have touched with
  what they were: the selection, what HammerForge's own commands tagged, and what
  an undone or redone step changed. A brush a command made is taken in without
  the rest. When it cannot tell, as after an undo that rebuilt every brush, it
  compares every brush, and a bake compares every brush first when a check since
  the last full one looked at only some. It compared every brush after every
  step until #1619: 8.21 ms at 100 brushes and 296 ms at 3,000.

The pause after an edit is the edit and the check together. Adding the two rows:

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Resize, then the check (ms) | 1.57 | 1.80 | 3.12 | 6.49 |
| Place, then the check (ms) | 6.16 | 17.6 | 62.9 | 190 |
| Undo a placement, then the check (ms) | 11.7 | 36.1 | 134 | 411 |

A resize and its check fit in one frame at 60 frames a second, 16.7 ms, at every
size measured. Placing a brush fits at 100 brushes and not at 300, and undoing
one is about a tenth of a second at 1,000. Those are the thresholds the Status
board's **Geometry budget**, the dock's health label and its brush count use:
amber above 100 brushes and entities, red above 1,000.
They were 50 and 100, which turned the count red at a size where nothing measured
here is slow.

## A session over the bridge

Measured on 23 October 2026 on the same machine with
[`tools/benchmark_bridge_session.gd`](https://github.com/saworbit/hammerforge/blob/main/tools/benchmark_bridge_session.gd)
([#1652](https://github.com/saworbit/hammerforge/issues/1652)), from one run with
other Godot processes running beside it.

```
godot --headless -s res://tools/benchmark_bridge_session.gd --path . -- --scale=1
```

It drives the bridge's dispatcher directly, with no socket, and builds a town
the way an agent would: per room a floor, four walls, a doorway cut, a flight of
stairs, a lamp, a trigger tied to `trigger_once` and a door tied to `func_door`,
wired, the floor painted, and a count read back. That is 15 calls a room, and
`--scale=1` is 100 rooms, 1,500 calls. Each figure is the mean per call over the
100 calls up to that count.

| Calls | 100 | 300 | 500 | 700 | 1,000 | 1,500 |
|---|--:|--:|--:|--:|--:|--:|
| Brushes | 111 | 320 | 533 | 751 | 1,071 | 1,600 |
| Whole call (ms) | 2.7 | 8.9 | 13.9 | 20.8 | 30.0 | 47.6 |
| Slowest call (ms) | 21.0 | 44.5 | 67.2 | 94.6 | 135.0 | 203.5 |
| Undo record (ms) | 1.3 | 6.6 | 10.8 | 16.6 | 24.2 | 39.0 |
| Undo record of one solid placement (ms) | 0.17 | 0.47 | 0.77 | 1.08 | 1.57 | 2.48 |
| The change and its answer (ms) | 1.0 | 1.0 | 1.0 | 1.1 | 1.2 | 1.4 |
| Change check after it (ms) | 2.0 | 5.8 | 9.0 | 13.3 | 19.0 | 29.4 |

- **A placement records only what it made**, so its undo record stays near
  2 ms at every size: 2.48 ms at 1,600 brushes. Before
  [#1786](https://github.com/saworbit/hammerforge/issues/1786) it recorded the
  whole level, and a call took 165 ms at 1,600 brushes against 48 ms now.
- **What still grows is the undo record of the rest:** a room's cut, its stairs
  and its wire record the whole level, as deleting does, and those three make up
  most of the 39 ms.
- **The change itself stays near 2 ms** at every size.
- **The change check** is the plugin's pass after every step, as under Editing.
- **The slowest call** in a block is one call, and moves the most from run to
  run: 203 ms in the block up to 1,500 calls, against a mean of 48 ms.
- All 1,500 calls were answered. At the end, saving the level took 1,162 ms until
  the file was written, and opening it again 1,684 ms.

`--scale=` takes a fraction or a multiple of the 100 rooms. The script saves into
`user://` and removes the file when it ends.

## Baking

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Full bake (ms) | 19.8 | 80.2 | 237 | 848 |
| Full bake, chunked at the recommended size (ms) | 25.9 | 80.5 | 191 | 808 |
| Bake Changed, one brush moved (ms) | 19.4 | 61.9 | 207 | 832 |
| CSG bake, the path a level with a cut takes (ms) | 13.5 | 59.8 | 122 | 593 |

**Bake shape**

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Full bake, frames it waits through | 14 | 39 | 126 | 376 |
| Full bake, chunked at the recommended size, frames it waits through | 14 | 39 | 126 | 376 |
| Recommended chunk size (m) | 9.50 | 17.5 | 31.5 | 54.5 |
| Chunks that bake makes | 16 | 16 | 16 | 16 |
| Bake Changed, one brush moved, frames it waits through | 14 | 39 | 126 | 376 |
| CSG bake, the path a level with a cut takes, frames it waits through | 2 | 2 | 2 | 2 |

- **Full bake** is timed from the call to its answer. That is longer than the
  **Last bake** the dock shows, which leaves out the frames the bake waits for
  and the passes after the mesh is built.
- **Frames it waits through.** With **Use Face Materials** on and no cuts, the
  default, a bake hands a frame back to the editor every 8 brushes so the editor
  stays responsive. Headless such a frame is close to free. In the editor each
  one is a whole editor frame, so the wait there is the time above plus that
  many frames.
- **Chunking** at the size the Status board recommends, a quarter of the level's
  longest side, made 16 chunks at every count. It took 191 ms against 237 ms at
  1,000 brushes and 808 ms against 848 ms at 3,000, was slower at 100 (25.9 ms
  against 19.8 ms), and waited through the same frames. It splits the baked mesh
  into pieces the renderer can cull one at a time, which a big level wants in the
  game; it did not shorten the bake consistently.
- **Bake Changed** after one brush moved took about as long as a full bake (207 ms
  against 237 ms at 1,000 brushes, 832 ms against 848 ms at 3,000) and waited
  through the same frames, because when anything has changed it rebuilds the
  whole level. What it saves is the bake when nothing has.
- **The CSG path**, which a level takes once it holds a cut, was faster on this
  level: 593 ms at 3,000 brushes, and 2 frames. These boxes do not touch, which
  is the easiest case CSG has. A level of brushes that overlap and cut each other
  is not measured here.

The bake time estimate in the Test tab assumes 2 ms a brush until a bake has
run. Measured here the bake took between 0.198 ms a brush (19.8 ms for 100) and
0.283 ms a brush (848 ms for 3,000), before the editor's frames. After a bake the
estimate is the dock's **Last bake** divided by the brushes that bake took, times
the brushes in the level now. A Bake Selected took only its selection, so one
brush baked alone gives one brush's time, not a share of the level's
([#1590](https://github.com/saworbit/hammerforge/issues/1590)).

### Bake by layout

The boxes above stand apart, the easiest case the CSG boolean has. A second run
on 23 October, on the same machine, packed the same boxes 2 m apart so each
shares a face with its neighbours, and baked them both ways; then it gave the
spaced boxes a 1 m cut into the top corner of every tenth
([#1624](https://github.com/saworbit/hammerforge/issues/1624)).
`--only=layouts` runs it.

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Touching boxes, face material bake (ms) | 22.2 | 70.2 | 209 | 648 |
| Touching boxes, CSG bake (ms) | 29.7 | 86.8 | 285 | 899 |
| Spaced boxes, a cut in every tenth, bake (ms) | 29.3 | 136 | 1,004 | 9,324 |

- **Touching boxes** turn the comparison round: the face material path, which
  **Use Face Materials** picks when there is no cut, was faster at every count,
  648 ms against 899 ms at 3,000. On spaced boxes the CSG path was faster, 593 ms
  against 848 ms. The face material path still hands the editor a frame every 8
  brushes (376 frames at 3,000) and CSG two in all, so in the editor the face
  path's wait is the time plus those frames.
- **A level with a cut** bakes on the CSG path whatever Use Face Materials says,
  because the face path has no boolean step. One cut in ten boxes took 1.0 s at
  1,000 brushes and 9.3 s at 3,000, ten times the touching boxes' CSG bake: the
  boolean's cost grows with the cuts as well as the brushes. A cut that cuts no
  solid brush still sends the bake this way, and Validate finds one.
- Not measured: brushes that overlap, and cuts through touching walls.

### Round brushes

Since #1613 every round brush goes into the CSG bake as its own faces, built in
GDScript, which matches its shape exactly. That cost about 1.8 ms per 128-face
sphere at every bake. The operand is kept now, by brush, and reused while
neither the brush's faces nor the materials they resolve to change
([#1628](https://github.com/saworbit/hammerforge/issues/1628)). The same run,
before and after, with `--only=round`:

| Brushes | 100 | 300 |
|---|--:|--:|
| CSG bake, 16-sided spheres set flat, operand built each bake (ms) | 365 | 1,109 |
| CSG bake, the same, operand kept (ms) | 208 | 744 |
| CSG bake, 16-sided spheres smoothed, operand built each bake (ms) | 789 | 2,429 |
| CSG bake, the same, operand kept (ms) | 632 | 2,421 |

Each figure is the median of three bakes, so it is the bake after the first.
The first bake of a session builds every operand. The flat spheres now bake in
the time Godot's own primitives took, 205 ms for 100. The smoothed ones gain
less: putting the shading back after the boolean
([#1612](https://github.com/saworbit/hammerforge/issues/1612)) is most of their
time.

## Files

**Sizes**

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| .hflevel, compressed (KB) | 4.45 | 11.1 | 32.7 | 94.8 |
| .hflevel, plain (KB) | 478 | 1,426 | 4,746 | 14,240 |
| .tscn, Brushes and bake (KB) | 338 | 1,012 | 3,373 | 10,440 |
| .scn, Brushes and bake (KB) | 34.9 | 98.2 | 317 | 928 |
| .tscn, Brushes only (KB) | 200 | 595 | 1,976 | 5,934 |
| .scn, Brushes only (KB) | 15.1 | 40.8 | 130 | 386 |
| .tscn, Baked geometry only (KB) | 141 | 420 | 1,400 | 4,509 |
| .scn, Baked geometry only (KB) | 21.1 | 58.5 | 188 | 544 |

**Saving**

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Save .hflevel, compressed, editor blocked (ms) | 13.7 | 65.6 | 179 | 566 |
| Save .hflevel, compressed, until written (ms) | 86.2 | 294 | 970 | 2,898 |
| Save .hflevel, plain, editor blocked (ms) | 23.7 | 59.7 | 208 | 556 |
| Save .hflevel, plain, until written (ms) | 99.2 | 325 | 1,018 | 3,298 |
| Save .tscn, Brushes and bake (ms) | 57.4 | 131 | 536 | 1,601 |
| Save .scn, Brushes and bake (ms) | 47.1 | 87.7 | 381 | 1,312 |
| Save .tscn, Brushes only (ms) | 42.1 | 95.8 | 358 | 1,388 |
| Save .scn, Brushes only (ms) | 46.9 | 112 | 254 | 1,213 |
| Save .tscn, Baked geometry only (ms) | 9.36 | 19.5 | 34.9 | 176 |
| Save .scn, Baked geometry only (ms) | 3.66 | 5.00 | 12.1 | 51.5 |

**Opening**

| Brushes | 100 | 300 | 1,000 | 3,000 |
|---|--:|--:|--:|--:|
| Open .tscn, Brushes and bake (ms) | 75.0 | 231 | 739 | 2,543 |
| Open .scn, Brushes and bake (ms) | 34.1 | 101 | 254 | 953 |
| Open .tscn, Brushes only (ms) | 64.8 | 174 | 509 | 1,787 |
| Open .scn, Brushes only (ms) | 34.4 | 112 | 361 | 915 |
| Open .tscn, Baked geometry only (ms) | 116 | 329 | 1,309 | 3,721 |
| Open .scn, Baked geometry only (ms) | 93.4 | 299 | 1,194 | 2,752 |
| Load .hflevel, compressed (ms) | 118 | 305 | 1,193 | 3,215 |
| Load .hflevel, plain (ms) | 111 | 315 | 1,141 | 3,169 |

### `.scn` or `.tscn`

A binary `.scn` was about a tenth the size of the same scene as `.tscn` (34.9 KB
against 338 KB at 100 brushes, 928 KB against 10,440 KB at 3,000) and opened
faster (953 ms against 2,543 ms at 3,000). The price is that a
`.scn` is not text: a diff shows nothing, and two people's changes to it cannot
be merged. Keep `.tscn` while the scene is reviewed and merged like code, and
switch with **Scene > Save Scene As...** once the level is too big for that to
matter. The benchmark saves a `.scn` compressed, as the editor does when its
**Compress Binary Resources** setting (FileSystem > On Save) is on.

A level saved as `.scn` keeps both halves of its link to its `.hflevel`. The scene
holds the `.hflevel` path, and a Save Level from a level opened out of a `.scn`
records that `.scn` in the file, so the level is told about its own file and
autosaves to it as it would from a `.tscn` (see
[Which File Opens](HammerForge_Data_Portability.md#which-file-opens-the-tscn-wins)).
`tests/test_scene_contents_choice.gd` saves a level as a compressed `.scn`, opens
it and checks both, and checks that a **Baked geometry only** `.scn` loads its
brushes from the `.hflevel` it names.

**Save Scene As carries the record.** With autosave on, saving the scene under a
new name writes the `.hflevel` at once, so it names the `.scn` and later
autosaves go on as before. A level switched with autosave off, or in an older
version, still names the `.tscn`: autosave refuses to write over it and says so once.
Press **Save Level** once and the file names the `.scn`.

### Scene Keeps

[What the Scene Keeps](HammerForge_Data_Portability.md#what-the-scene-keeps)
decides what Ctrl+S writes.

- **Brushes and bake**, the default, is the largest scene and needs no other file.
- **Brushes only** leaves the bake out: 386 KB against 928 KB as `.scn` at 3,000
  brushes. Bake again after opening it to have geometry.
- **Baked geometry only** is the quickest to save (51.5 ms as `.scn` at 3,000) and
  the slowest to open, because the brushes are rebuilt from the `.hflevel` when it
  opens: 2,752 ms as `.scn` against 953 ms for **Brushes and bake**.

### The `.hflevel`

Compressed, the default, the `.hflevel` was 94.8 KB at 3,000 brushes; plain it
was 14,240 KB. Save Level stops the editor while it takes the level (566 ms at
3,000 brushes) and then writes on another thread, so the file was on disk after
2,898 ms. Autosave runs the same save every 5 minutes by default, set from 1 to
60. Loading a `.hflevel` into an empty level took 3,215 ms at 3,000 brushes.

## A big level

- **Split the map into scenes.** The check after every edit, the whole-level undo
  steps and Save Level all work over one level's brushes, so each level pays for
  its own brushes rather than for the whole map's.
- **Save the scene as `.scn`** once nobody needs to merge it, then press
  **Save Level**.
- **Chunk the bake for the game**, not for a shorter bake.
- **Expect Bake Changed to take as long as Bake** whenever anything has changed.
- **Lengthen the autosave interval** (Console > Controls, **Autosave every
  (min)**) if its pause gets in the way.

## Limits the code enforces

These are caps in the code, not measurements. Past its value each one refuses,
clamps or falls back to something simpler, as the table says, rather than slowing
down. There is no cap on the brushes or entities in a level.

| Limit | Value | Where |
|---|---|---|
| Brushes one array makes | 256 | `MAX_COPY_BRUSHES`, `hf_duplicator.gd` |
| Steps in a staircase or a spiral staircase | 128 | `MAX_STEPS`, `hf_stairs_builder.gd` and `hf_spiral_stairs_builder.gd` |
| Brushes in one flight of stairs, landings and nosings included | 128 | `MAX_PIECES`, `hf_stairs_builder.gd` |
| Panels in a dome (rings x segments) | 256 | `MAX_PANELS`, `hf_dome_builder.gd` |
| Segments in an arched door frame | 2 to 64 | `MIN_SEGMENTS`, `MAX_SEGMENTS`, `hf_door_frame_builder.gd` |
| Sides of a ring's tube | 3 to 32 | `MIN_TUBE_SEGMENTS`, `MAX_TUBE_SEGMENTS`, `hf_ring_builder.gd` |
| Segments of a round brush | 64 | `MAX_ROUND_BRUSH_SEGMENTS`, `brush_instance.gd` |
| Faces of a brush Hollow, Carve or Intersect will work on | 128 | `MAX_BOOLEAN_PLANES`, `hf_convex_clip.gd` |
| How deep one Extrude goes | 256, past which a typed depth is refused | `MAX_EXTRUDE_HEIGHT`, `hf_extrude_tool.gd` |
| Thinnest band a trim profile is cut into | 1 cm, so a fine Trim Segments can give fewer strips | `MIN_BAND`, `hf_trim_profile.gd` |
| Cuts tried when splitting a concave outline | 256 | `MAX_CUTS`, `hf_polygon_split.gd` |
| Material surfaces in one brush's editor preview | 200, past which it draws its plain mesh | `MAX_PREVIEW_SURFACES`, `brush_instance.gd` |
| Faces of a brush that snapping aims at | 64, past which it snaps to the brush's box | `MAX_SNAP_FACES`, `hf_snap_system.gd` |
| Cut overlays drawn at once | 50 | `MAX_PREVIEWS`, `systems/hf_subtract_preview.gd` |
| Cuts given a live CSG preview at once | 8 | `MAX_CSG_SUBTRACTORS`, `systems/hf_subtract_preview.gd` |
| Carve and intersect previews drawn at once | 50 | `MAX_PREVIEWS`, `systems/hf_carve_preview.gd` |
| Bake chunk size | 0 (off), or 1 to 16,384 | `MIN_BAKE_CHUNK_SIZE`, `MAX_BAKE_CHUNK_SIZE`, `level_root.gd` |
| Material atlas | 4,096 px | `MAX_ATLAS_SIZE`, `hf_material_atlas.gd` |
| Lightmap Scale of a brush or a visgroup | 0.125 to 8 | `MIN_LIGHTMAP_SCALE`, `MAX_LIGHTMAP_SCALE`, `hf_bake_split.gd` |
| Texture layers blended over one face | 8 | `MAX_PAINT_LAYERS`, `surface_paint.gd`; `MAX_SURFACE_PAINT_LAYERS`, `level_root.gd` |
| Cells one bucket fill covers | 500,000 | `MAX_BUCKET_FILL_CELLS`, `paint/hf_paint_tool.gd` |
| Paint cell index, either axis | 100,000 from the origin | `CELL_LIMIT`, `systems/hf_paint_system.gd` |
| Cells one rectangle paint call covers | 65,536 | `MAX_RECT_CELLS`, `systems/hf_paint_system.gd` |
| Paint region size, and streaming memory budget | 64 to 4,096 cells; 32 to 8,192 MB | `systems/hf_paint_system.gd` |
| Instances one scatter stroke places | 50,000 | `MAX_SCATTER_INSTANCES`, `paint/hf_scatter_brush.gd` |
| Autosave interval, and backups kept | 1 to 60 minutes; 1 to 50 | `level_root.gd` |
| Changes in one agent `hf_batch` | 100 | `BATCH_LIMIT`, `mcp/hf_mcp_dispatcher.gd` |
| Agent request, and response | 1 MiB; 16 MiB | `MAX_REQUEST_BYTES`, `MAX_RESPONSE_BYTES`, `mcp/hf_mcp_protocol.gd` |

Paths are under `addons/hammerforge/`.
