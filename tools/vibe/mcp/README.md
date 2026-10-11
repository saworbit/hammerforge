# MCP vibe testing

Scenarios that drive the Agent Bridge the way it is really used: a real Godot
editor with HammerForge, the real `hammerforge-mcp` over stdio, and a helper
plugin standing in for the person at the editor. The person presses Ctrl+Z, edits
something, opens another scene tab, saves, closes a tab mid-bake.

GUT tests the dispatcher with a stand-in host and undo histories. That cannot see
what only the editor does: its undo manager, its frames, its scene tabs. The bugs
these runs found are the reason they exist:

- A headless editor never sends `RenderingServer.frame_post_draw`, so the first
  screenshot code hung the bridge's queue.
- Undo straight on a scene's `UndoRedo` leaves Ctrl+Shift+Z behind (#1028).
- The dock's Create Starter was two undo steps, and its pieces lost their owners
  on redo.

## Running it

```bash
python tools/vibe/mcp/run_mcp_vibe.py                 # the headless scenarios
python tools/vibe/mcp/run_mcp_vibe.py bake review     # named ones
python tools/vibe/mcp/run_mcp_vibe.py --windowed      # and the one that opens a window
python tools/vibe/mcp/run_mcp_vibe.py --list
```

It needs the `mcp` package (`python -m pip install -r requirements-ci.txt`) and
Godot 4.7, found by `--godot`, `$GODOT`, the `PATH`, or `C:/Godot/godot.cmd`.
Each scenario starts its own editor, which takes a minute or so.

Close any editor open on this checkout first, or run it in a worktree of its own.
It refuses to start while another editor here has the bridge on.

Exit code 1 when something was flagged or a scenario could not run.

## What a run does to the checkout

For each scenario, and undone after it whatever happens:

- `editor_helper/` is copied to `addons/hf_mcp_vibe/`, and enabled in
  `project.godot`. The original is kept in `.vibe/mcp/project.godot.bak` and put
  back after. A run that was killed leaves the backup, and the next run restores
  from it first.
- Two scratch scenes go in `res://vibe_mcp_scratch/`: `level.tscn`, a bare
  LevelRoot, and `other.tscn`, with no level. The folder is deleted after, and
  git ignores it.
- A windowed editor can rewrite tracked `.import` files. Any it changed that were
  clean before the run are reverted.

Logs and screenshots stay in `.vibe/mcp/`: `<scenario>.editor.log`, and the PNGs
the `prompts` scenario saves for you to look at.

## Output

| | means | fails the run |
|---|---|---|
| `ok` | held | no |
| `FLAG` | did not hold, and nobody filed it | yes |
| `known` | filed as the issue named, and still so | no |
| `note` | worth reading, not a check | no |

When a `known` line turns `ok`, the issue may be fixed: check it and close it.

## Scenarios

| Name | What it does |
|---|---|
| `basics` | Status and place, the revision holding still, a person's edit ending the agent's undo chain, tab switches, unticking the box |
| `undo` | The dock's Create Starter as one step, and `hf_undo` against Ctrl+Z and Ctrl+Shift+Z (#1028) |
| `room` | Starter, walls, a cut, paint, extrude, a turn, the spawn, undo rules, then save and reload |
| `bake` | A room in one batch, validate, bake to `<scene>_mcp.tscn`, current and stale |
| `review` | Pending cuts moving the revision, a replayed bake, a scene tab closed mid-bake |
| `prompts` | Each example prompt's tools as an agent reads them, with screenshots. Opens a window |

## Writing one

A scenario is a module in `scenarios/` with `DESCRIPTION`, `START_SCENE`
(`"level"` or `"other"`), `WINDOWED`, and `async def run(v)`. Add its name to
`SCENARIOS` in `run_mcp_vibe.py`. `v` gives you:

- `await v.call(tool, args)`: the tool's structured answer, with the raw MCP
  blocks under `_blocks`.
- `await v.prompt(name, args)`: an example prompt's text.
- `v.order(op, **args)`: the person at the editor. The ops are in
  `editor_helper/vibe_plugin.gd`: `history`, `brushes`, `panel`, `open`,
  `save_as`, `reload`, `undo` (the scene history directly, as the dock's button
  does), `manager_undo` and `manager_redo` (Ctrl+Z and Ctrl+Shift+Z),
  `human_nudge`, `human_hide_floor`, `dock_create_starter`, `close_on_bake`,
  `disable`.
- `v.expect(condition, what, seen)`, `v.known(issue, condition, what, seen)`,
  `v.note(label, value)`, and `v.save_image(answer, filename)`.

## Not covered yet

- **Nothing runs it automatically.** CI lints it and loads the helper, but runs no
  scenario (#1054). Run it by hand after changing a tool's arguments or answers.
- **It does not play the level.** The scenarios check the bridge's answers and the
  editor's state. Whether a player can climb what an agent built, or see over it,
  took a separate review: HammerForge's `PlaytestFPS` walked routes through the
  baked scene, and cameras at its eye were placed in a Test Level run (#1045,
  #1046). A scenario that does that would belong here.

## Traps

- A headless editor draws nothing. A screenshot there answers
  `screenshot_unavailable`, which is a pass; the picture needs `--windowed`.
- `order()` blocks the event loop while the helper answers. Do not hold a tool
  call open across one unless the point is to see what the editor does
  meanwhile.
- The helper reads its order file every frame. On Windows a write can meet its
  read, so writes retry.
- A brush count includes cuts and committed cuts. The starter's floor is a plain
  node, not a brush.
