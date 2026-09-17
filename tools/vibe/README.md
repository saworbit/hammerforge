# Vibe testing

Exploratory scenarios that drive a **real** `LevelRoot` the way a mapper does,
and report anything that does not look right.

This is not the GUT suite and is not trying to be. The suite asserts known
behaviour and gates every commit. These scenarios go looking for behaviour
nobody has written down yet: they run long sequences, feed edges and nonsense to
things that take numbers, round-trip levels through every format, and check
structural facts that should hold no matter what happened. They are a sweep you
run deliberately.

## Running it

```bash
python tools/vibe/run_vibe.py                 # everything
python tools/vibe/run_vibe.py geometry cost   # named scenarios
python tools/vibe/run_vibe.py --list
```

Logs land in `.vibe/<scenario>.log` (git-ignored). Exit code is **1 when
something new was flagged**, 0 otherwise.

Godot is found via `$GODOT`, the `PATH`, or `C:/Godot/godot.cmd`. On Windows
through the Bash tool, `cmd //c "C:\Godot\godot.cmd ..."` is the invocation that
works.

Direct, without the Python wrapper — fine for one scenario, but see the warning
about hangs below:

```bash
godot --headless -s res://tools/vibe/hf_vibe_runner.gd --path . -- geometry
```

## What the output means

Each scenario says three kinds of thing:

| | meaning | fails the run |
|---|---|---|
| plain line | this is what happened, recorded so the next reader knows the ground was covered | no |
| `FLAG` | this looks wrong and has no issue yet | **yes** |
| `KNOWN #n` | this looks wrong and is already reported as issue `n` | no |

Nothing asserts. A scenario reports; a human judges. That is the whole design —
an exploratory run that stops at the first surprise stops exploring, and half
these observations are only obviously wrong once someone who knows the editor
looks at them.

`KNOWN` entries are kept deliberately rather than deleted once filed. A scenario
that stops exercising a defect stops noticing when the fix lands, and stops
noticing when it comes back. When an issue closes, check the `KNOWN` still
reproduces; if it does not, turn it into a plain assertion in `tests/` and drop
it from here.

## The scenarios

| id | covers |
|---|---|
| `geometry` | face winding on every primitive; what bevel does to a brush; clip and merge refusals |
| `round-trip` | a level with per-face appearance, entities, wiring, visgroups, a generator and a displacement, through undo and through `.hflevel` |
| `map-io` | `.map` export in both formats, re-import, Valve 220 texture axes checked against their own face planes, import against seven malformed files |
| `displacement` | displacement lifecycle and input validation; whether a sculpt survives |
| `limits` | arrays, generators, prefabs, visgroups and paint layers at zero, negative, absurd, empty and duplicate |
| `chaos` | 300 randomised operations with structural invariants checked after each one |
| `cost` | faces, build time and `.hflevel` size for one brush of each shape |
| `transform` | rotate/flip/reset round trips, mirror winding, pivots, and where texture lock puts a texture |
| `structures` | the four generators: winding at their defaults, schema ranges, regenerate as a no-op |
| `cutting` | clip, carve, hollow, inset and arrays, measured by volume rather than by what they report |
| `entities` | naming, duplication, deletion, and what the I/O wired to an entity does when its name moves |
| `appearance` | material slots, UV params, projections and paint layers at their edges |
| `persistence` | `capture_state`/`restore_state` round trips, repeated restores, and malformed state |
| `housekeeping` | visgroup and group names, the cordon, and the paint layer list |
| `terrain` | heightmap scale and region settings at their edges, and the playtest/glTF exports |
| `vertex` | vertex moves, edge splits, merges and the convexity check that gates them |
| `prefabs` | prefab capture, `.hfprefab` round trip, placement, and the instance registry |
| `validation` | what `validate_level()` reports, and what it says nothing about |
| `settings` | grid, rotate-snap and bake settings at their edges, and through a state round trip |
| `groups` | group names, membership after a delete, and where groups differ from visgroups |
| `materials` | palette slots, the remap when one is removed, and the usage tracker |
| `bake` | what a bake produces: geometry, idempotence, and the flags that exclude brushes |
| `previews` | clip, carve, hollow, array and structure ghosts: leaks, bad inputs, and what counts them |
| `cordon` | what the cordon excludes from a bake, and what an ill-formed cordon AABB does |
| `spawn` | spawn validation against the layer the bake actually put the collision on |
| `lifecycle` | what survives a `restore_state` that should not: counters, registries and selection |
| `placement` | resize and nudge at their edges, against what the create path allows |
| `definitions` | `entities.json` and the I/O preset file, malformed and at their edges |
| `operations` | whether each `can_*()` rule is also enforced by the operation it guards |
| `draw-tools` | polygon and path tool geometry: winding either way round, degenerate input, settings out of range |
| `viewport-tools` | extrude, decal and measure: what their scene nodes do to the count, the save and the bake |
| `runtime-io` | `HFIORuntime` against malformed metadata and input names that collide with `Node` methods |
| `prefs` | the prefs and keymap files: malformed values, silent resets, rebinds that collide |
| `snapping` | which snap candidate wins, and whether the cached face geometry keeps up with the brush |
| `undo-collation` | whether the undo collation window can carry state from one level root to another |
| `painted-faces` | what a painted face keeps of the material it was painted over |
| `status-board` | what the status board says against what the level is, and a half-missing palette |
| `atlas` | the material atlas packer at its size limits, and what a failed pack does to the caller |
| `scatter` | what a scattered instance is oriented to, how many one click makes, and what the scene keeps |
| `selection-filter` | which faces each bulk filter reaches, and which faces no filter reaches at all |
| `timeline` | the glyph and colour an operation gets on the timeline, and whether Replay can be clicked |
| `shortcut-surfaces` | whether the HUD, the coach marks and the tooltips still tell the truth after a rebind |
| `connectors` | what the live connector path costs per stroke, and whether the paint grid follows the level |
| `examples` | what loading an example does to the level already in the scene, and whether it can be undone |
| `heightmap-io` | what a heightmap loses going through the `.hflevel`'s base64 PNG, in world units |
| `regions` | what the region eviction loop frees against what it thinks it freed |
| `quick-property` | whether the quick popup and the dock control behind it agree on range and step |
| `dock-undo` | which dock commands change the level without registering an undo step |
| `dock-settings` | what an exported settings file carries back onto the level, and what a hand-edited one does |
| `uv-defaults` | whether a brush's faces are born with a projection that can show a texture |
| `surface-paint` | where a surface paint stroke lands against where the cursor was, and what one costs |
| `dock-cordon` | whether the cordon spins can hold the cordon the level was given |
| `playtest-spawn` | where the playtest player's feet end up against the spawn the validator approved |
| `entity-props` | what a colour or vector entity property is after a save, a load and a `.map` export |
| `bake-materials` | whether per-face materials reach the baked mesh with the settings a level starts with |
| `dock-ranges` | whether each dock spin and the level property behind it agree about the legal range |
| `brush-sides` | whether a cylinder or a cone is built with the number of sides it was asked for |
| `map-uv-tail` | whether the UV tail of an exported `.map` face means what the face means |
| `uv-canvas` | where the UV editor draws a real face's UVs, and what dragging one does |
| `tool-registry` | what the custom-tool scan constructs, and what the registry does with an unknown id |
| `material-library` | whether the documented Save/Load material library can be reached, and what it keeps |
| `viewport-drop` | what the viewport accepts as a drop, and how a saved brush preset is named |
| `change-tracker` | which native edits the brush change tracker notices, and which it does not |
| `heightmap-convert` | what Convert to Heightmap produces, what it costs, and which settings it honours |
| `numeric-entry` | whether a dimension typed during a draw drag reaches the preview |
| `generator-ranges` | every generator setting one step outside the range its own schema declares |
| `outline-bounds` | whether each shape's selection outline is the size of the brush it is drawn around |
| `console-log` | what the Console log buffer keeps, drops, collapses and hands to Copy |
| `console-controls` | whether every switch on the Console's Controls tab reaches the setting it names |
| `console-actions` | whether a Status board action leaves the level in the state it reported |
| `paint-grid` | the paint grid's world/cell arithmetic, the layer list, and the ids it mints |
| `paint-inference` | what the opt-in paint cleanup does to the cells a stroke just painted |
| `paint-multilayer` | whether painting on one floor layer keeps the geometry of the layers under it |
| `material-browser` | what the material browser calls a favourite, and what its filters reach |
| `array-layout` | whether the two ways of counting an array's copies give the same answer |
| `io-presets-panel` | what the wiring panel's Save preset button adds to the list, and how it comes out |
| `prefab-links` | whether cycling a variant leaves an instance where it was, and what it does to overrides |
| `validate-fix` | what Validate + Fix reports against what it repaired and what is left |
| `chaos-systems` | randomised registry operations, with dangling references checked after each |
| `dock-undo-two` | undo coverage for the structure, library, terrain slot and surface paint commands |
| `io-visualizer` | what the wiring overlay draws against what the level stores, and what notices a dangling wire |
| `drag-create` | whether the brush a drag produces is the size and place the drag rectangle described |
| `level-scale` | what an undo step, a save, a validate and a bake cost as a level grows |
| `playtest-scene` | what the exported playtest scene contains, read back off disk |
| `bake-options` | the nine optional bake toggles against what each one puts in the baked container |
| `visibility-workflow` | which operations agree that a hidden brush is hidden |
| `chaos-io` | randomised edits with a save/load, a state round trip and a `.map` round trip along the way |
| `material-persistence` | whether a material made in the editor survives a `.hflevel` save |
| `generator-geometry` | every generator across its schema's legal range, each piece checked |
| `autosave-history` | whether the autosave rotation keeps the number of backups it says, and whose |
| `level-io-types` | which Variant types survive the `.hflevel` encoder |
| `prefab-materials` | whether a prefab carries the materials it was built with, or just slot numbers |
| `bake-equivalence` | whether `bake_dirty()` produces the geometry a full bake would |
| `scene-weight` | what a level costs inside the `.tscn` it lives in, before and after a bake |
| `examples-integrity` | whether each shipped example builds a level that validates and holds its invariants |
| `world-scale` | whether the drawing defaults, the generators, the examples and the player agree on how big a person is |
| `far-origin` | whether a brush built far from the origin is the brush built at it |
| `uv-justify` | where each Justify mode puts a face's texture, measured off the face |
| `texture-continuity` | whether a texture runs across a wall built from several brushes |
| `two-levels` | what a second level in the same project does to the first |
| `build-a-room` | one map built end to end: hollow, doorway, corridor, texture, light, bake, playtest |
| `bake-chunking` | whether a level a mapper would build ever reaches the chunked bake |
| `scale-leftovers` | defaults elsewhere in the plugin that are still on the pre-#625 scale |
| `undo-depth` | forty mixed edits, undone all the way back and redone, diffed at every step |
| `material-palette` | what the 150-material prototype palette costs a level, and the way back out |
| `map-real-world` | a `.map` written by another editor: what survives import, and the export after it |
| `scene-reopen` | what a level is after being packed into its `.tscn` and opened again |
| `command-surfaces` | every action a surface can emit against the dispatcher that runs it |
| `op-results` | which refusals carry a reason to the mapper, and which are silent |
| `prefab-library` | the prefab library panel: its list, filters, names and what it does with a bad file |
| `brush-entities` | brushes tied to an entity class: naming, wiring, saving and what the exports make of them |
| `missing-files` | what a level does when a file it points at is taken away |
| `docs-truth` | what the guide, the tutorial and the feature pages claim, against the running plugin |
| `navmesh` | whether the baked navmesh has polygons over the floor, and whose agent settings |
| `runtime-entities` | whether a trigger, a button and a door do at runtime what their definitions promise |
| `ship-runtime` | what a `LevelRoot` does, keeps and costs on the branch a built game takes |
| `big-level` | a 900-brush map priced at every step: build, save, validate, bake, draw calls |
| `unicode-names` | non-ASCII and punctuation in every kind of name, through every format |
| `props-and-models` | what happens to a `prop_static`'s Scene property, and what the scatter picker accepts |
| `bake-optimisation` | what Use multimesh and Generate occluders do to a level built to need them |
| `collision-layers` | what layer and mask the bake writes, and who still collides with it |
| `level-instancing` | what a level saved as a scene and instanced twice into a parent is |
| `lighting` | what the baked geometry gives a `LightmapGI`, and what it still needs by hand |
| `subtractive-bake` | what one subtract brush does to the materials and the cost of the whole bake |
| `map-quality` | the defects a real map has, against what Validate looks for |
| `save-as` | whether saving an unchanged level to a second path writes a second file |
| `surface-response` | what a raycast can learn about the material of the surface it hit |
| `team-workflow` | what a level looks like to version control: diff size, readability, merge |
| `session-leaks` | whether a long run of ordinary edits gives back the nodes and objects it took |
| `build-outdoors` | a whole outdoor level: terrain, ground textures, a building, bake, playtest |
| `bulk-edits` | the Build tab's transforms and selections applied to 200 brushes at once |
| `map-units` | whether a `.map` crossing between this editor and a Quake-family one keeps its size |
| `detail-brushes` | what tying clutter to `func_detail` does to the node count and the draw calls |
| `gltf-export` | what `export_baked_gltf` writes for a real level, read back off disk |
| `streamed-world-bake` | whether a bake of a streamed world covers the parts that are not resident |
| `walkability` | whether a body the size of the playtest player can walk the level that was baked |

## Adding a scenario

Subclass the scenario base in `tools/vibe/scenarios/`, then add the path to
`SCENARIOS` in `hf_vibe_runner.gd` and the id to `SCENARIOS` in `run_vibe.py`.

Extend it **by path**. `hf_vibe_scenario.gd` has no `class_name`, so
`extends HFVibeScenario` only resolves while a stale
`.godot/global_script_class_cache.cfg` still holds the name — it passes all
session and fails to parse on a clean checkout, and CI does not run the sweep so
nothing says otherwise.

```gdscript
@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

func id() -> String:
	return "my-area"

func summary() -> String:
	return "one line about what this covers"

func run() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	note("brushes", root.brush_system.get_live_brush_count())
	if something_looks_wrong:
		flag("what looked wrong", "the detail a reader needs")
```

`HFVibeScenario` gives you `fresh_root()`, `frame()`, `box()`, `note()`,
`flag()`, `known()` and `diff_levels()`. `HFVibe` has the heavier helpers:
`describe_level()`, `check_invariants()`, `inward_face_count()`,
`local_extent()`, `settle_save()`, `write_text()`, `file_size()`.

### A scenario that could not run is not a scenario that found nothing

The runner grades each scenario on its exit code, and a scenario that hits a
GDScript error still reaches `quit(0)`. So a broken one reported **clean**, which
is worse than reporting a failure, because in the summary it is indistinguishable
from a real pass.

`prefab-links` called `set_override()` for two releases after that mechanism was
removed. It errored on the line, the whole override section was dead, and every
sweep said clean. `status-board` was worse: it had already written the detector
for the defect it was hitting, and the throw unwound the scenario past its own
`flag()` call, because GDScript has no exception handling. Both were found by
grading on the error rather than by anybody reading a log (#739).

A run whose output carries a `SCRIPT ERROR` line is now graded `script error`, or
`flagged + script error` when it also found something, and the sweep exits 1
either way. `SCRIPT ERROR` and not the engine's broader `ERROR:`, because
scenarios provoke engine errors on purpose: a missing file, a refused load and a
malformed payload are things they exist to try. Of the 142 logs in `.vibe/` at
the time, thirteen carried an `ERROR:` and two carried a `SCRIPT ERROR`.

There is deliberately no way to mark a script error as expected. A scenario that
needs one is a scenario asking to be silenced, and that is how a detector stops
detecting. `python tools/vibe/run_vibe.py --selftest` checks the grading still
grades, and CI runs it beside the repository's other guards.

### A clean scenario is a result too

Several of these found nothing. `previews` confirms no ghost is counted as a brush,
reaches the save, or reaches the bake; `lifecycle` confirms `restore_state()`
resets the visgroup, group and prefab registries and the face selection, and
that brush ids cannot collide the way prefab instance ids can; `spawn` records
what the validator actually measures; and `materials` confirms the palette remap
is correct in all three brush containers. Those are kept. A scenario that only
exists while it is failing cannot tell you when something stops being true, and
the notes are where the next reader finds out the ground was already covered.
`build-a-room`, `far-origin` and `docs-truth` are the newest of them.
The newest clean scenarios are `session-leaks`, `bulk-edits`, `unicode-names`,
`gltf-export`, `streamed-world-bake` and `big-level`.
`session-leaks` runs 200 create/delete cycles, 25 re-bakes, 100 undo round trips
and 100 preview show/hides and every one of them gives back every node, orphan
and object it took — which is the answer to "the editor gets slow over an
evening" and is worth having written down. `bulk-edits` applies a nudge, a
rotation, a retexture, a visgroup hide and a delete to 200 brushes at once: all
correct, all fast, and four 90-degree turns about a pivot come back to within
5e-6 of the start. `unicode-names` puts accented, Cyrillic, CJK, emoji and
punctuated names through entity names, visgroups, groups, the `.hflevel`, the
`.map` export and re-import, and through non-ASCII *filenames*, and loses
nothing.

`gltf-export` takes a textured room out through `export_baked_gltf()` and reads
it back with Godot's own importer: the geometry is there, it is the size of the
level, every surface carries a UV channel and the four material names survive.
`streamed-world-bake` settles the suspicion that a bake of a streamed world
would have holes where the evicted regions were -- it covers 252.9 of the 256
units painted. `big-level` prices a 900-brush map and finds a linear curve with
no cliff in it: 141 ms to build, 68 ms to validate, 581 ms to save into 47 KB,
1391 ms for a full bake and 0 ms for a `bake_dirty()` with nothing dirty.

`walkability` is two thirds clean and worth reading for the two thirds. Floor
seams hold in all three collision modes and a doorway one tenth of a unit wider
than the player is passable; only the stairs fail, and they fail at five
centimetres as surely as at twenty-five, which is what says the step height is
not the variable.
`build-a-room` runs a whole first evening -- hollow a room, carve a doorway, run
a corridor to a second room, texture twenty brushes, place a light and a spawn,
group and visgroup the shell, validate, bake, export the playtest scene -- and
finds nothing wrong at any step. `far-origin` settles the suspicion that the
plugin's absolute float epsilons must fail a long way out: they do not, at any
distance to 32768, through both file formats. `docs-truth` reads the user guide
and the tutorial wizard against the running plugin and finds them accurate --
the guide explains the #625 scale change rather than being stale on it, every
shortcut it names is bound, and every entity class it names is offered.

`undo-collation` and `snapping` are the older two. The undo helper's
collation window lives in `static var`s, which looked like it would carry one
level's captured state into the next level's action, and it does not -- the tag
carries the brush id, and two roots in one session mint different id prefixes.
The snap system's per-brush face cache keeps up with a vertex move, and grid
snap does not shadow a corner that is genuinely nearer. Written down so the next
reader does not have to work either of them out again.

Several `note()` lines exist purely to close off a suspicion — that built-in I/O
presets are handed out by reference, for instance, which is safe only because a
`const` Dictionary is read-only in Godot 4. Writing down why something is *not*
a finding is worth as much as writing down a finding.

### What makes a good scenario

The findings that hold up have all come from the same few shapes:

- **Round trips.** Build something, put it through a transform that claims to be
  lossless, diff it. Data loss is silent by construction — the operation reports
  success and the level is just poorer.
- **Invariants after every step.** Not at the end. Checking after each operation
  names the one that broke it, which is most of the debugging.
- **Independent verification.** Do not take a subsystem's word for its own
  correctness. `validate_convexity()` said a bevelled brush was broken; the
  finding only became real after computing the face normals directly and
  confirming two of them pointed inward.
- **Downstream consequences.** An out-of-range input accepted quietly is worth
  little on its own. It is worth a lot when you then show what it does three
  operations later — an unbounded bevel radius is a shrug until a carve uses the
  inflated bounds and scatters unrelated brushes half a million units away.
- **Cost, measured.** "That seems like a lot of faces" is not a finding. "One
  sphere is 129 KB and 424 ms per autosave, against 1.2 KB and 18 ms for a box"
  is.

## Traps

Every one of these has cost a wasted run.

- **`_initialize()` is too early.** The tree is not up. Defer:
  `_run.call_deferred()`, then `await process_frame`.
- **`_ready()` is a frame late.** After `add_child()`, every `root.*_system` is
  null until you `await tree.process_frame` once. `fresh_root()` does it for you.
- **A script error hangs the run forever.** GDScript has no exception handling,
  so `quit()` never runs and the engine sits there. Use `run_vibe.py`, which
  times each scenario out. If you do hang one:
  `taskkill //F //FI "IMAGENAME eq godot*"`.
- **`save_hflevel()` is threaded, and `_process` is off headless.** It only runs
  under `Engine.is_editor_hint()`. Pump `root._process_hflevel_saves()` until
  `root.file_system._hflevel_thread` is null — `HFVibe.settle_save()` does this.
  Polling for the file to exist instead **races the writer**: the destination is
  briefly absent partway through the atomic replace, so the load that follows
  fails for no visible reason and looks like a bug in the loader.
- **Several operations are async.** `bake_dirty`, `bake_selected` and
  `commit_cuts` need `await`, or you get "Trying to call an async function
  without await" and a hang.
- **Signatures that bite.** `rotate_managed_nodes` / `flip_managed_nodes` take a
  trailing `pivot`. `apply_noise` takes a `FastNoiseLite`, not a float. The
  `FaceData` property is `material_idx`, not `material_index`. Generator records
  come from `generator_system.capture()`.
- **A typed local assigned from parsed JSON is a runtime error, not a fallback.**
  `var entries: Array = data.get("entities", [])` takes the whole function down
  when the value is a String, skipping every fallback below it. This is a defect
  shape worth hunting (#370, #380) and a trap when a scenario does the same.
- **Default `Array` and `Dictionary` parameters are shared between calls.** A
  helper written `func collect(node, out: Array = [])` accumulates across every
  call in the run, which looks like the code under test producing six copies of
  one answer. Pass a fresh `[]` at every call site.
- **A bare headless `LevelRoot` has no change tracker.** `HFBrushChangeTracker`
  lives on the plugin, so writing `brush.global_position` directly never tags the
  brush dirty and `bake_dirty()` correctly rebuilds nothing. Drive edits through
  the `LevelRoot` API (`nudge_brushes_by_id`, `rotate_managed_nodes`,
  `tag_brush_dirty`) or the scenario measures the harness.
- **`HFVibe.settle_save()` is a coroutine.** Calling it without `await` returns
  immediately and the file is measured before the writer has finished, which
  reads as a save that wrote nothing.
- **A scenario member named `_tree` shadows the base class's `SceneTree`.**
  `Member "_tree" is not a function` is what that looks like.
- **`Transform3D` has no `applied_to()`.** `HFDuplicator.CopyPlacement` does, and
  the array preview and the array builder both take `CopyPlacement` objects, not
  raw transforms. Build them with `HFDuplicator.linear_placements()` and friends.
- **`export_map`'s Valve key is `"valve220"`.** Any unrecognised string falls
  back to classic Quake without saying so, which reads as "the two formats
  produce identical files".
- **Brush ids carry a per-session prefix.** Two runs of the same build produce
  different ids, so never diff on them. `HFVibe.describe_brushes()` leaves them
  out.
- **A `match` arm can name several actions at once.** `"extrude_up",
  "tool_extrude_up", "tool_extrude":` is one arm and three names. A scan that
  reads the first name off each arm reports the other two as unhandled, which is
  a scenario producing findings about itself.
- **Godot's output is UTF-8 and the Windows console is not.** `run_vibe.py`
  passes `encoding="utf-8", errors="replace"`; without it a single non-ASCII
  character anywhere in a scenario's output took the whole run down with a
  `UnicodeDecodeError` that read as the scenario having crashed.
- **A scenario that writes into `res://` has to clean up after itself.**
  `prefab-library` and `missing-files` both drive surfaces that read a real
  directory. Anything left behind turns up in the next run's counts and in
  `git status`. Keep the list of paths written and remove them at the end.
- **Headless is not `Engine.is_editor_hint()`**, so a fresh root treats itself as
  the running game and deferred-starts a playtest. Its `CharacterBody3D` is then
  in the physics space, and a scenario that raycasts -- the spawn validator, for
  one -- hits the player rather than the level. Set `auto_spawn_player = false`.
- **The project is on metric scale.** The playtest player is 1.6 units tall and a
  default drawn brush is 2. A scenario written with 512-unit rooms is building a
  level 300 players across, which makes navmesh bakes enormous, occluder counts
  meaningless and every cost number a measurement of nothing. `world-scale` has
  the table.
- **`auto_spawn_player` has to be off before `add_child()`.** `_ready()` reads it
  once and queues `_start_playtest()` with `call_deferred()`, so
  `root.auto_spawn_player = false` on the line after `fresh_root()` is too late:
  a whole extra bake runs and a `CharacterBody3D` lands in the physics space,
  where every raycast the scenario makes can hit it instead of the level. This is
  why `HFVibe.make_root()` takes the flag and sets it itself, defaulting to off —
  pass `fresh_root("Level", true)` for the playtest scenarios.
- **The live draft brushes carry their own picking collision, on layer 1.** A ray
  fired after a bake finds the editor's pick bodies rather than the baked world
  unless the drafts are removed first, which reads as "the collision is there" in
  exactly the cases where it is not.
- **A freed root's collision does not leave the physics space on the frame
  `queue_free()` is called.** Three cases in a loop, each building a floor at the
  origin, measure the first case's floor three times. Put each case somewhere
  else in space rather than trying to free between them.
- **`save_hflevel()` skips a write whose payload hashes the same as the last one,
  whatever path it is given (#688).** A scenario that saves twice without editing
  in between measures a file that was never written. Change the level between
  saves, or pass `force`.
- **The paint reconciler has three holders, not one.** `floors_root` takes flat
  floor rects from the brush paint path, `heightmap_floors_root` takes displaced
  terrain chunks, `walls_root` takes the skirts. Looking in only the first reads
  as "the terrain built nothing".
- **`create_brush_from_info()` clamps a collapsed axis to 0.1.** A scenario that
  asks for a zero-extent brush to test a validator gets a thin one, and the
  validator correctly says nothing. Write `size` on the node to make a real one.
- **`rotate_managed_nodes()` takes five arguments**, and the first is brush *ids*:
  `(brush_ids, entity_paths, axis_index, angle_degrees, pivot)`.
- **`run_vibe.py`'s own stdout has to be reconfigured to UTF-8.** Godot's output
  is UTF-8 and the Windows console is cp1252; `run_scenario` already decodes with
  `errors="replace"`, and printing the decoded line back out was still taking the
  whole run down with a `UnicodeEncodeError` after the findings were already in
  the log file.
- **Check findings against the open PRs before filing.** `main` can be well
  behind a stack of fixes. `git diff main...origin/<branch>` over the file you
  are looking at is the check; several confirmed reproductions on `main` were
  already fixed on an unmerged branch.
