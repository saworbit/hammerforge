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

## Adding a scenario

Subclass the scenario base in `tools/vibe/scenarios/`, then add the path to
`SCENARIOS` in `hf_vibe_runner.gd` and the id to `SCENARIOS` in `run_vibe.py`.

Extend it **by path**. `hf_vibe_scenario.gd` has no `class_name`, so
`extends HFVibeScenario` only resolves while a stale
`.godot/global_script_class_cache.cfg` still holds the name � it passes all
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

### A clean scenario is a result too

Four of these found nothing. `previews` confirms no ghost is counted as a brush,
reaches the save, or reaches the bake; `lifecycle` confirms `restore_state()`
resets the visgroup, group and prefab registries and the face selection, and
that brush ids cannot collide the way prefab instance ids can; `spawn` records
what the validator actually measures; and `materials` confirms the palette remap
is correct in all three brush containers. Those are kept. A scenario that only
exists while it is failing cannot tell you when something stops being true, and
the notes are where the next reader finds out the ground was already covered.

Several `note()` lines exist purely to close off a suspicion � that built-in I/O
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
- **`Transform3D` has no `applied_to()`.** `HFDuplicator.CopyPlacement` does, and
  the array preview and the array builder both take `CopyPlacement` objects, not
  raw transforms. Build them with `HFDuplicator.linear_placements()` and friends.
- **`export_map`'s Valve key is `"valve220"`.** Any unrecognised string falls
  back to classic Quake without saying so, which reads as "the two formats
  produce identical files".
- **Brush ids carry a per-session prefix.** Two runs of the same build produce
  different ids, so never diff on them. `HFVibe.describe_brushes()` leaves them
  out.
- **Check findings against the open PRs before filing.** `main` can be well
  behind a stack of fixes. `git diff main...origin/<branch>` over the file you
  are looking at is the check; several confirmed reproductions on `main` were
  already fixed on an unmerged branch.
