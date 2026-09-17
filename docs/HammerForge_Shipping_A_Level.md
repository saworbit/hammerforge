---
description: "Taking a finished HammerForge level into a game: which file is the level, how to export a game scene, what to turn off, and how to light it."
---

# Shipping a Level

Last updated: September 17, 2026

Every other guide covers building a level. This one covers the last hour of its
life: turning the thing you have been editing into something a game loads.

## The short version

1. Bake the level with the options below.
2. Press **Export Game Scene** in **Test > Advanced Bake**.
3. Load the `.tscn` it writes from your game. That is the level.

Everything under here is why, and what to do when the short version is not
enough.

## Which file is the level

A HammerForge level lives in three files, and they do different jobs.

| File | What it holds | Who reads it |
|---|---|---|
| `<level>.tscn` | The editing scene: the `LevelRoot`, the source brushes, the baked geometry | You, in the editor |
| `<level>.hflevel` | The canonical save: brushes, faces, materials, entities, visgroups, settings | HammerForge, on load |
| `<level>_game.tscn` | The export: baked geometry and real entity nodes | **Your game** |

The first two are the source. Keep both in version control — see
[Data Portability](HammerForge_Data_Portability.md), which also explains what
happens when they disagree.

The third is the build output. It is the one your game loads, and it is
disposable: export it again whenever the level changes.

## Why not load the level scene directly

You can, and for a greybox it is fine. The reasons not to, for a real game:

- It carries every source brush as a `DraftBrush` node alongside the baked
  geometry. The game pays to load nodes it will never draw.
- It carries a `LevelRoot`, which is an editor tool. It builds subsystems at
  `_ready()` that a game has no use for.
- Entity markers stay markers. A `light_point` is a `Node3D` with an editor
  preview on it, not an `OmniLight3D`. **A level scene has no lights in it.**

That last one is the important one. Turning markers into the real Godot nodes
they stand for is what the export is for.

## What the export writes

**Export Game Scene** bakes, then writes a `.tscn` next to your level scene
named after it. It contains:

- the baked geometry and its collision;
- `Nonstructural`, holding `func_detail` meshes and the `Area3D` for every
  trigger volume;
- every point entity as the real node its class names: `light_point` as an
  `OmniLight3D`, `light_spot` as a `SpotLight3D`, `logic_timer` as a `Timer`,
  `prop_static` as the scene its Scene property points at;
- an `HFIODispatcher`, when any entity has I/O wiring, which connects the graph
  at `_ready()`.

It does not contain a player, a fallback sun or a debug environment. **Export
Playtest Build** adds those three, which is what makes it a playtest.

## Lighting

The export gives you real `Light3D` nodes. What it does not do is bake lighting,
because that is Godot's job and it needs a node HammerForge never adds.

For baked lighting:

1. Turn on **Lightmap UV2** in the bake options before exporting. Without it the
   meshes have no UV2 and a `LightmapGI` bakes them black. If the unwrap fails,
   the Console says so and names the mesh — do not ignore that line.
2. Open the exported scene, add a `LightmapGI` node, and press **Bake Lightmaps**
   in Godot's toolbar.
3. Re-export only when the geometry changes, and re-bake lightmaps after.

For real-time lighting, do nothing extra. The lights are already there.

`bake_lightmap_texel_size` (default `0.1`) is the lightmap density. Smaller is
sharper and slower to bake.

## Bake options for a shipped level

The defaults are tuned for editing, where a fast bake matters more than a fast
frame. For an export:

| Option | Editing | Shipping | Why |
|---|---|---|---|
| Merge meshes | off | **on** | One draw call instead of one per brush |
| Generate LODs | off | **on** | Costs bake time once, saves frame time forever |
| Lightmap UV2 | off | **on**, if you bake lighting | Nothing else produces UV2 |
| Use face materials | on | on | This is what keeps your texturing |
| Navmesh | off | on, if anything pathfinds | See the agent settings below |
| Occluders | off | on, for interiors | Occlusion culling needs them |
| Chunk size | 0 | above ~100 brushes | Lets Godot cull parts of the level |

Merge meshes and per-face materials work together: merging combines the meshes,
and the materials stay as separate surfaces on the merged mesh.

One thing to know: a level with **any** subtractive brush in it falls back to the
CSG bake path, which resolves one material per brush rather than one per face. A
toast says so and names how many cutters caused it. Until that is fixed, a level
that needs both cuts and per-face texturing has to choose.

## Things to turn off

**`auto_spawn_player`** is off by default and should stay off for a shipped
level. On, and outside the editor, a `LevelRoot` adds a debug FPS controller with
its own camera — beside whatever player your game has. It is also gated on the
build being a debug build, so a release export never takes it whatever the
property says.

**Remote reload** is gated the same way. It polls for an editor lock file, which
only makes sense while somebody is editing.

Neither applies to the exported game scene, which has no `LevelRoot` in it at
all. They matter if you load the level's own `.tscn` directly.

## Wiring that runs

A trigger volume raises its own outputs: `trigger_once` and `trigger_multiple`
fire `OnStartTouch` when a body enters and `OnEndTouch` when one leaves.

Everything else is yours to raise, because it depends on something your game
decides. Pressing a button is the usual case:

```gdscript
# In your player's interact code, once you know what was pressed.
HFIORuntime.fire_on(button_node, "OnPressed")
```

The playtest player does exactly this on its Use key, so **Test Level** is a
working demonstration of the whole loop.

See [the I/O section of the User Guide](HammerForge_UserGuide.md) for how an
input reaches its target and what a class can declare about it.

## Navmesh

If anything in your game pathfinds, turn **Navmesh** on before exporting, and set
the agent settings to your actual agent. Six of them are in the Manage tab: cell
size and height, agent height and radius, and **Agent Climb / Slope**.

The climb is the one to check. It is the tallest step an agent will walk up, and
the plugin builds stairs itself — the auto-connector's default step and Godot's
default max climb are both `0.25`, so they sit exactly on each other. Raise the
step for a chunkier stair without raising the climb and nothing that follows the
navmesh can use the staircase. Bake Check says so when the two disagree.

The playtest player is separate and has its own `max_step_height`, defaulting to
`0.4`. A game with its own character controller needs its own step-up; Godot's
`CharacterBody3D` has none built in.

## Checklist

Before you call a level done:

- [ ] Level check is green, or you know why it is not
- [ ] A `player_start` exists where you want the player to arrive
- [ ] The level bakes with no warnings you have not read
- [ ] Bake options set for shipping, not for editing
- [ ] **Export Game Scene**, not Export Playtest Build
- [ ] The exported scene loads in your game with no second player in it
- [ ] Lightmaps baked, if you are baking lighting
- [ ] `.tscn` and `.hflevel` both committed; the exported scene need not be
