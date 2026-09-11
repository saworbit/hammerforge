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

## Adding a scenario

Subclass `HFVibeScenario` in `tools/vibe/scenarios/`, then add the path to
`SCENARIOS` in `hf_vibe_runner.gd` and the id to `SCENARIOS` in `run_vibe.py`.

```gdscript
@tool
extends HFVibeScenario

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
