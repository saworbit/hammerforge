# hammerforge-mcp

An MCP server that lets an agent build in a live HammerForge level in the Godot
editor. It talks to the bridge inside the HammerForge addon over a loopback socket.

The [Agent Bridge guide](../docs/HammerForge_Agent_Bridge.md) is the user's page:
setting it up, what to ask, what each refusal means, and the limits.

## Turn the bridge on

1. Open your project in the Godot editor with HammerForge enabled.
2. In the HammerForge dock, open the **Test** tab, then **Agent Bridge**.
3. Tick **Allow agent connections (MCP)**. The lamp turns amber and the line
   under it says which port it listens on.

The bridge is off again every time the editor starts. It listens on `127.0.0.1`
only, makes a new token each time it is turned on, and writes that token to
`.godot/hammerforge_mcp/discovery.json` in your project, in a folder closed to
other users on the machine. Godot's own `.gitignore` covers
`.godot/`, and an export never includes it.

## Run the server

With [uv](https://docs.astral.sh/uv/):

```bash
uvx --from "git+https://github.com/saworbit/hammerforge#subdirectory=hammerforge_mcp" hammerforge-mcp --project /path/to/your/godot/project
```

`--project` is the folder with `project.godot` in it. `HAMMERFORGE_PROJECT` does
the same job. Without either, the current folder is used.

`hammerforge-mcp --check --project <folder>` connects once, says which scene and
level the bridge is on or what is wrong, and prints the lines to add the server to
Claude Code or Claude Desktop with this interpreter's full path.

To add it to Claude Code:

```bash
claude mcp add hammerforge -- uvx --from "git+https://github.com/saworbit/hammerforge#subdirectory=hammerforge_mcp" hammerforge-mcp --project /path/to/your/godot/project
```

Logs go to stderr, one line per call. `--log-file` writes them to a file as
well, and `--log-level DEBUG` adds each call's arguments. The token is never
logged.

The server also lists three prompts: `block_out_room`, `review_level` and
`bake_for_playtest`.

## What an agent can do

| Tool | What it does |
|---|---|
| `hf_get_status` | Which editor, scene and level the bridge is on, the revision, counts, grid and camera |
| `hf_place_brush` | Place a brush: shape, size, position, union or subtract, snapped to the grid unless told not to |
| `hf_get_brushes` | List brushes with their faces, filtered by id or by a box |
| `hf_get_materials` | List the level's material palette, by id and name |
| `hf_transform_brush` | Move a brush to a position, turn it to an angle, or both |
| `hf_resize_brush` | Give a brush a new size about its centre |
| `hf_delete_brush` | Delete a brush |
| `hf_extrude_face` | Add a box on one face of a brush, the way the Extrude tool does |
| `hf_assign_material` | Put a palette material on a brush, or on some of its faces |
| `hf_set_spawn` | Stand the player spawn on a floor point, facing a yaw |
| `hf_create_starter` | Make a level in the open scene: floor, sun and spawn |
| `hf_undo` | Take back the agent's last step, never anyone else's |
| `hf_redo` | Put back the step `hf_undo` took |
| `hf_bake` | Bake, and write `<scene>_mcp.tscn` for a game or Didi to load, with the bake id on its root |
| `hf_validate` | List what HammerForge would warn about before a bake, naming the brush each is about |
| `hf_viewport_screenshot` | A PNG of the viewport, or of a camera framed on some brushes or a box |
| `hf_batch` | Up to 100 changes as one undo step, all or nothing |

A face is named by its index, by a world side such as `"+y"`, or by
`{"normal": [x, y, z]}`. A side or normal picks the face pointing most nearly that
way, and two faces that tie are refused rather than guessed between.

`hf_undo` and `hf_redo` only move the agent's own `MCP: ...` steps, and refuse
once anything else has touched the level since the agent's last answer, even a
change that was then undone.

Conventions: Godot Y-up, metres, world space. `size` is full extents and
`position` is the brush centre. With snapping on, size snaps to whole grid steps
and an unrotated brush's lowest corner lands on the grid.

Every change is one undo step named `MCP: ...` in the editor's history. Each
mutating call carries an `operation_id`, and a retry with the same one returns
the first answer instead of running again. The server makes one for you if you
leave it out. `hf_undo`, `hf_redo` and `hf_bake` get a new one every call, since a
second undo is usually meant: after a timeout, pass the id it gave to retry.

If the editor moves to another scene or level, the next change is refused with
`target_changed`. Call `hf_get_status` to work on the new one.

## Hand a bake to Didi

`hf_bake` writes the scene a game loads and says which bake it is:

1. Call `hf_bake`. The answer has `bake_id`, `source_revision`, and
   `artifact.path` (a `res://` path) with `artifact.absolute_path` beside it.
2. Give Didi that `res://` path to run, in the same project.
3. In the running game, the scene's root carries the bake as metadata:
   `get_tree().current_scene.get_meta("hammerforge_bake")` is
   `{bake_id, source_revision, target_id, baked_at}`. Check `bake_id` is the one
   `hf_bake` gave you before trusting what you see.
4. `hf_get_status` says `bake_current: false` once anything changes the level
   after that bake. Bake again before the next run.

A bake applies the level's pending subtract cuts. No undo step records that, so
it moves the revision, and `hf_undo` then refuses to reach back past it.

The file is `<scene>_mcp.tscn` beside the level's own scene, and each bake
replaces it. It never touches `<scene>_game.tscn`, which Export Game Scene writes.

## Develop

```bash
cd hammerforge_mcp
uv venv
uv pip install -e ".[test]"
uv run pytest
```

The design is in
[docs/superpowers/specs/2026-10-11-mcp-bridge-design.md](../docs/superpowers/specs/2026-10-11-mcp-bridge-design.md).
