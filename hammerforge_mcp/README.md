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
other users on the machine. If the editor cannot close that folder, it does not
start the bridge. Godot's own `.gitignore` covers
`.godot/`, and an export never includes it.

## Run the server

With [uv](https://docs.astral.sh/uv/):

```bash
uvx --from "git+https://github.com/saworbit/hammerforge#subdirectory=hammerforge_mcp" hammerforge-mcp --project /path/to/your/godot/project
```

`--project` is the folder with `project.godot` in it. `HAMMERFORGE_PROJECT` does
the same job. Without either, the current folder is used.

That runs the server from `main`, for the addon on `main`. The server is
versioned with the addon, so with a released HammerForge put its tag after the
repository: `hammerforge@v0.4.0#subdirectory=hammerforge_mcp`.

`hammerforge-mcp --check --project <folder>` connects once, says which scene and
level the bridge is on or what is wrong, says when this server is not the one for
the editor's HammerForge and which to install, and prints the lines to add the
server to Claude Code or Claude Desktop with this interpreter's full path.

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
| `hf_place_brush` | Place a brush: shape, size, position, a solid brush (`union`) or a cut brush (`subtract`), and optionally a material, a rotation, sides and a name, snapped to the grid unless told not to |
| `hf_get_brushes` | List brushes with their faces and the structure each is a piece of, filtered by id or by a box |
| `hf_get_materials` | List the level's material palette, by id and name |
| `hf_get_entities` | List the level's point entities, the spawn included, with their properties and wiring; a brush made an entity is listed by `hf_get_brushes` |
| `hf_transform_brush` | Move a brush to a position, turn it to an angle, or both |
| `hf_resize_brush` | Give a brush a new size about its centre |
| `hf_delete_brush` | Delete a brush |
| `hf_extrude_face` | Add a box on one face of a brush, or a prism of the face when it is not a rectangle, the way the Extrude tool does |
| `hf_assign_material` | Put a palette material on a brush, or on some of its faces |
| `hf_set_spawn` | Stand the player spawn on a floor point, facing a yaw |
| `hf_place_entity` | Place a light, sound, prop or logic entity, with its properties or a preset |
| `hf_transform_entity` | Move an entity, aim it, or both |
| `hf_set_entity_properties` | Change an entity's properties, a brush entity's by its `brush_id`, or apply a preset, checked as placing checks them |
| `hf_delete_entity` | Delete an entity and the wires aimed at it |
| `hf_add_entity_output` | Wire an entity's output to an input on a named target, such as a timer to a light's Toggle, or a trigger to a lamp |
| `hf_remove_entity_output` | Take a wire back by its place in the source's outputs |
| `hf_set_brush_entity` | Make brushes one trigger, door, button, wall, detail or clip brush, with a name to wire to, or untie them |
| `hf_get_cordons` | List the cordons a partial bake is cut to: each one's index, name, corners and switch, and the level's switch for all of them |
| `hf_set_cordon` | Add a cordon round brushes or at a box, or move, rename or switch one by index, or switch every cordon on or off |
| `hf_remove_cordon` | Take a cordon out by index; the level always keeps one |
| `hf_create_starter` | Make a level in the open scene: floor, sun and spawn |
| `hf_undo` | Take back the agent's last step, never anyone else's |
| `hf_redo` | Put back the step `hf_undo` took |
| `hf_bake` | Bake the whole level, or with `cordons: true` only what the cordons take, and write `<scene>_mcp.tscn` for a game or gda to load, with the bake id on its root |
| `hf_measure` | Measure brushes, faces, entities and points: sizes and volume, the gap between two (0 when touching, negative when overlapping), the gap along each axis, and the angle between two faces |
| `hf_plan` | A top down plan of the level drawn from its brushes, as a PNG or as SVG in metres: solids filled, cuts hatched, entities by kind, wires and cordons, one floor at a time by a height band. Works from a headless editor |
| `hf_validate` | List what HammerForge would warn about before a bake, naming the brush each is about |
| `hf_viewport_screenshot` | A PNG of the viewport, or a clean one framed on some brushes or a box from a side you choose, or from a camera you place, leaving out brushes or cuts, or showing only the bake |
| `hf_list_commands` | List the palette commands an agent can run, with what each takes and its params, the prefab library and the level's paint layers |
| `hf_run_command` | Run a palette command on named brushes: hollow, clip, clip to a face, carve, merge, intersect, snap to grid, build stairs, arches, spiral stairs, domes, rings or door frames, change or detach one, place a prefab from the library, switch or propagate a placed one, move to floor or ceiling, reset rotation; or paint floor by cell: a rectangle painted or erased, its walls raised, a room stamped, a connector between two layers confirmed |
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

Command replies list only targets whose brush data changed in `changed`.
An unchanged structure update keeps its pieces, revision and undo history;
the next `hf_undo` still reaches the preceding change.

Paint rectangle replies distinguish `cells_changed` (filled bits flipped)
from `materials_changed` (material ids changed). `heights_changed` counts new
or changed wall-height overrides, including a new override at the default.
A material-only paint can record a step with `cells_changed: 0`. With region
streaming enabled, a paint command loads the regions it writes before it
checks them, so paint streamed out to disk counts and `hf_undo` restores it
([#1502](https://github.com/saworbit/hammerforge/issues/1502)).

Every change is one undo step named `MCP: ...` in the editor's history. A call
that changes nothing records no step, leaves the revision where it was and
answers `no_change: true`. Each mutating call carries an `operation_id`, and a
retry with the same one returns the first answer instead of running again. The
server makes one for you if you leave it out. `hf_undo`, `hf_redo` and `hf_bake`
get a new one every call, since a second undo is usually meant: after a timeout,
pass the id it gave to retry.

If the editor moves to another scene or level, the next change is refused with
`target_changed`. Call `hf_get_status` to work on the new one.

## The building guide

`skills/hammerforge-building/` is a guide an agent loads before it builds: the
working loop (plan as numbers, build in a few batches, then measure, validate and
look), the conventions in one place, what each read costs, the answers that mean
a plan went wrong, and a worked example with the numbers it should measure. It is
in the skill format coding agents load. Copy the folder into your agent's skills
folder; for Claude Code that is `.claude/skills/` in your project or
`~/.claude/skills/`. A client that does not load skills can read the same pages
as MCP resources: `hammerforge://guide`, and `hammerforge://guide/<page>` for
`conventions`, `costs`, `warning-signs` and `worked-example`.

## Hand a bake to gda

`hf_bake` writes the scene a game loads and says which bake it is. To run it
and check what it does, use [gda](https://github.com/aigengame/godot-agent), or
any runtime that can load a scene from the project:

1. Call `hf_bake`. The answer has `bake_id`, `source_revision`, and
   `artifact.path` (a `res://` path) with `artifact.absolute_path` beside it.
2. Run that `res://` path in the same project: `gda daemon start --scene` with
   it starts the game on it, for gda's live tools. Live mode needs Godot 4.6 or
   later, and adds an autoload to `project.godot` that `gda daemon uninstall`
   takes out again.
3. In the running game, the scene's root carries the bake as metadata:
   `get_tree().current_scene.get_meta("hammerforge_bake")` is
   `{bake_id, source_revision, target_id, baked_at, partial}`, with the `cordons`
   it was cut to when `partial` is true. Check `bake_id` is the one `hf_bake`
   gave you before trusting what you see.
4. `hf_get_status` says `bake_current: false` once anything changes the level
   after that bake; a whole bake stays current across cordon changes, which it
   set aside, a partial one does not. Bake again before the next run.

A bake applies the level's pending subtract cuts. They go in first as a step of
their own, `MCP: apply pending cuts`, which moves the revision and which
`hf_undo` takes back; the bake itself records nothing. With no pending cuts,
this preparation records no step and leaves the revision unchanged.

The file is `<scene>_mcp.tscn` beside the level's own scene, and each bake
replaces it. It never touches `<scene>_game.tscn`, which Export Game Scene writes.

`hf_bake` with `cordons: true` bakes only what the switched-on cordons take, into
the same file, for a run of one part of the level. Its metadata says
`partial: true`.

The starter level's floor goes into that file with the level, so a game loading
it has ground beyond the brushes. The guide's Known limits list what testing found.

## Develop

```bash
cd hammerforge_mcp
uv venv
uv pip install -e ".[test]"
uv run pytest
```

The design is in
[docs/superpowers/specs/2026-10-11-mcp-bridge-design.md](../docs/superpowers/specs/2026-10-11-mcp-bridge-design.md).
