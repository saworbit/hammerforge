# Agent Bridge (MCP)

The Agent Bridge lets an AI agent that speaks the Model Context Protocol build in
the level you have open in the Godot editor. You ask it for a room, a corridor or
a fix, and it places and changes brushes the way you would, each change one step
in the editor's undo history. Claude Code, Claude Desktop and any other MCP
client that runs a local server over stdio can use it.

It has two parts. The listener is in the HammerForge addon and is off until you
turn it on. The server, `hammerforge-mcp`, is a small Python program your MCP
client starts. It lives in the repository's
[hammerforge_mcp/](https://github.com/saworbit/hammerforge/tree/main/hammerforge_mcp)
folder and is not in the Asset Library download.

The bridge is in the addon on the `main` branch. HammerForge 0.3.2 and earlier do
not have it. On `main` the addon still calls itself 0.3.2, so `--check` and
`hf_get_status` say "HammerForge 0.3.2" ([#1044](https://github.com/saworbit/hammerforge/issues/1044)).

## What it can and cannot do

An agent on the bridge can make a starter level, place, move, turn, resize,
delete and extrude brushes, paint them with palette materials, stand the player
spawn, place, move, retune, wire, unwire and delete lights, sounds, props and
logic entities, make a brush a trigger, a door or a button and wire it, list
brushes, materials and entities, check the level, take screenshots, bake, and
undo its own steps.

It cannot save your scene, open or delete files, run the game, change project
settings, or reach anything outside the open level. The one file it writes is the
bake it makes when you ask it to bake.

## How it keeps your work safe

- **Off until you say.** You tick a box to turn it on. It is off again every time
  the editor starts.
- **This machine only.** It listens on `127.0.0.1`. A new random token is made
  each time you turn it on, and written to `.godot/hammerforge_mcp/` in your
  project, a folder only your user can read. Git and exports leave `.godot/` out.
- **Every change is one undo step.** Each one is named `MCP: ...` in the editor's
  history, so Ctrl+Z takes it back like any of your own. A change that fails part
  way leaves the level as it was.
- **The agent only undoes its own work.** `hf_undo` takes back the agent's last
  `MCP: ...` step, and refuses once you have touched the level since, even if you
  undid what you did.
- **It stays on the level it was given.** Switch to another scene tab and the
  agent's next change is refused until it looks again with `hf_get_status`.

## Set it up

You need Python 3.10 or newer, and an MCP client.

1. **Install the server.**

    ```bash
    pip install "git+https://github.com/saworbit/hammerforge.git#subdirectory=hammerforge_mcp"
    ```

    That installs the server from `main`, for the addon on `main`. The server
    is versioned with the addon, so with a released HammerForge put its tag
    after `.git`, `@v` and the version in `addons/hammerforge/plugin.cfg`, such
    as `hammerforge.git@v0.3.3#subdirectory=hammerforge_mcp`. Step 3's
    `--check` says when the two are apart, and prints the line to install.
    From a clone of the repository, `pip install ./hammerforge_mcp` does the same.
    With [uv](https://docs.astral.sh/uv/) you can skip installing and let your
    client run `uvx --from "git+https://github.com/saworbit/hammerforge.git#subdirectory=hammerforge_mcp" hammerforge-mcp`.

2. **Turn the bridge on.** Open your project in the Godot editor. In the
   HammerForge dock, open the **Test** tab, then **Agent Bridge**, and tick
   **Allow agent connections (MCP)**. The lamp turns amber and the line beside it
   says which port it listens on.

3. **Check the server can reach it.**

    ```bash
    hammerforge-mcp --check --project /path/to/your/godot/project
    ```

    `--project` is the folder with `project.godot` in it. The check says which
    scene and level the bridge is on, or what is wrong and how to fix it. Then it
    prints the lines to add the server to a client, with the full path of the
    Python it runs under. Use those: a client started from the desktop does not
    read your shell's PATH, so a bare `hammerforge-mcp` may not be found.

4. **Add it to your client.** For Claude Code, run the `claude mcp add` line the
   check printed. It adds the server for you in that folder. If that command will
   not run in your shell, save the JSON block as `.mcp.json` in the project's root
   instead; Claude Code asks you to approve it the first time. It holds your
   machine's paths, so keep it out of git. For
   Claude Desktop, put the JSON block in `claude_desktop_config.json` and restart
   it. Other clients that read an `mcpServers` block take the same one.

The lamp turns green when an agent connects.

## Ask it for something

The server offers three prompts your client can list. In Claude Code they are in
the `/` menu, and arguments follow separated by spaces:
`/mcp__hammerforge__block_out_room 20 12 6` asks for a room 20 m wide, 12 m deep
and 6 m tall.

- **Block out a room** (`block_out_room`, with width, depth and height): floor,
  walls, ceiling, a doorway and the spawn in one undo step. The prompt works out
  every size and centre, so the agent has no arithmetic to get wrong.
- **Review the level** (`review_level`): checks the level, looks at it, and lists
  what to fix, without changing anything.
- **Bake for a playtest** (`bake_for_playtest`): fixes what the check reports,
  bakes, and says how to confirm the game runs that bake.

Plain requests work too. Some that go well:

- "Make a 20 by 12 metre hall, 6 metres tall, with a doorway in each short wall."
- "Put a 2 metre wide ramp from the floor up to the ledge at y 3 on the east side."
- "Paint the floor with the darkest grey in the palette, and the walls with the orange one."
- "Something looks off near the stairs. Take a screenshot there and tell me what."
- "Undo that last change and try it with the walls half a metre thinner."

Say sizes in metres. The agent is told the rest of the conventions.

## Watch what it does

- The **Agent Bridge** lamp is amber while it waits, green with an agent
  connected, and red if it could not start.
- The line beside the lamp says what is running now, such as "Running: bake".
- The line under it says what the agent last did, such as "Last: place brush,
  14 ms", or why it was refused, such as "Last: undo refused: undo_conflict".
- Each change is in the editor's undo history as `MCP: place brush`,
  `MCP: batch (6 ops)` and so on.
- The server logs one line per call to stderr. `--log-file` writes them to a file
  as well, and `--log-level DEBUG` adds the arguments of each call. The token is
  never logged.

## What the agent can call

| Tool | What it does |
|---|---|
| `hf_get_status` | Which editor, scene and level the bridge is on, the revision, counts, grid and camera |
| `hf_create_starter` | Make a level in the open scene: floor, sun and spawn |
| `hf_place_brush` | Place a brush: shape, size, position, union or subtract, and a name if you want one |
| `hf_transform_brush` | Move a brush to a position, turn it to an angle, or both |
| `hf_resize_brush` | Give a brush a new size about its centre |
| `hf_delete_brush` | Delete a brush |
| `hf_extrude_face` | Add a box on one face of a brush, the way the Extrude tool does |
| `hf_assign_material` | Put a palette material on a brush, or on some of its faces |
| `hf_set_spawn` | Stand the player spawn on a floor point, facing a yaw |
| `hf_place_entity` | Place a light, sound, prop or logic entity, with its properties or a preset |
| `hf_transform_entity` | Move an entity, aim it, or both |
| `hf_set_entity_properties` | Change an entity's properties or apply a preset, checked as placing checks them |
| `hf_delete_entity` | Delete an entity and the wires aimed at it |
| `hf_add_entity_output` | Wire an entity's output to an input on a named target, such as a timer to a light's Toggle, or a trigger to a lamp |
| `hf_remove_entity_output` | Take a wire back by its place in the source's outputs |
| `hf_set_brush_entity` | Make a brush a trigger, a door, a button or a wall, with a name to wire to |
| `hf_get_brushes` | List brushes with their faces, filtered by id or by a box |
| `hf_get_materials` | List the level's material palette, by id and name |
| `hf_get_entities` | List the level's point entities, the spawn included, with their properties and wiring; a brush made an entity is listed by `hf_get_brushes` |
| `hf_validate` | List what HammerForge would warn about before a bake, naming the brush each is about |
| `hf_viewport_screenshot` | A picture of the viewport, or a clean one framed on some brushes or a box from a side you choose, or from a camera you place, leaving out brushes or cuts, or showing only the bake |
| `hf_batch` | Up to 100 changes as one undo step, all or nothing |
| `hf_bake` | Bake, and write `<scene>_mcp.tscn` with the bake id on its root |
| `hf_undo` | Take back the agent's last step, never anyone else's |
| `hf_redo` | Put back the step `hf_undo` took |

Conventions: Godot's Y-up, metres, world space. `size` is the full extent on each
axis and `position` is the brush's centre. With snapping on, which is the default,
sizes snap to whole grid steps and an unrotated brush's lowest corner lands on the
grid. A face is named by its index, by a world side such as `"+y"`, or by a normal
such as `{"normal": [0, 1, 0]}`.

The tool descriptions carry these too:

- A `wedge`'s tall, vertical face is on -x, and its slope rises toward -x. To face
  a ramp another way, pass `rotation_degrees` to `hf_place_brush`, or turn it after
  with `hf_transform_brush`. `hf_place_brush` also takes a `material` and, for a
  pyramid or a round shape, `sides`: on a sphere, ellipsoid, capsule or torus,
  the segments round it.
- Round shapes stand along Y. A cylinder's `size.y` is its height. A torus lies
  flat, its `size.y` the thickness of its tube.
- A spawn at `yaw_degrees` 0 faces -Z, and a positive yaw turns it toward -X. The
  answer's `spawn.facing` gives the direction.
- `hf_set_spawn` takes where the feet go, and the `suggested_position` and
  `clear_place` in its answer are feet too, so either can be passed straight back.
  Its check finds a floor built from brushes before the first bake as well.
- With snapping on, a brush whose size is an odd number of half grid steps moves
  off the centre asked for, because its lowest corner snaps. The answer's
  `snapped` is true only when something moved, with `requested` beside what was
  applied. Pass `"snap": false` for a piece that has to sit centred on another,
  such as a ball on a pillar.

## Build for the player

`hf_get_status` gives an agent the playtest player's numbers under `player`, read
from the player's own script. The playtest player Test Level drops in is:

| | |
|---|---|
| Capsule | 0.35 m radius, 1.6 m tall |
| Eye | about 1.8 m above the feet |
| Tallest step it walks up | 0.4 m |
| Jump | about 2.2 m high |
| Steepest slope it walks | 45 degrees |
| Walk, sprint | 6.5 m/s, 10 m/s |

The tool description tells an agent what they mean for stairs, walkways and
doors: risers at most 0.4 m, a parapet below eye height if the player should see
over it, and doorways taller than the player and wider than the capsule.
`hf_validate` checks the first and last against the same numbers: brush stairs
whose risers are over the step, doorways the player does not fit through, and
wedge ramps too steep to walk up, each naming both brushes, at any angle the
pieces are turned together, and a spiral of box steps each turned its own way
([#1095](https://github.com/saworbit/hammerforge/issues/1095)). It does not check
sight lines. A game with its own controller may need other numbers.

## Bake for a playtest

`hf_bake` bakes the level and writes `<scene>_mcp.tscn` beside the level's own
scene, or `res://hammerforge_mcp_bake.tscn` for a scene never saved. Each bake
replaces the last. It never touches `<scene>_game.tscn`, the file **Export Game
Scene** writes.

The answer gives the bake's `bake_id` and the file's `res://` path. The baked
scene's root carries the same id, so whatever runs it can check it got that bake:

```gdscript
var bake: Dictionary = get_tree().current_scene.get_meta("hammerforge_bake")
print(bake.bake_id, " from revision ", bake.source_revision)
```

`hf_get_status` says `bake_current: false` as soon as anything changes the level
after the bake. Bake again before the next run.

A bake applies the level's pending subtract cuts. No undo step records that, so
after a bake that applied cuts the agent cannot undo back past it. You still can,
with the editor's own history.

The starter level's floor goes into `<scene>_mcp.tscn` with the level. It is a
large CSG box with collision, top at y = 0, the same one the editor shows and Test
Level runs, so a game loading the file has ground beyond the brushes.

## When something goes wrong

The agent sees each refusal as a code and a message saying what to do. The ones
you are most likely to meet:

| Code | What it means | What to do |
|---|---|---|
| `bridge_off` | The editor is closed, the box is not ticked, or `--project` names another folder | Tick **Allow agent connections (MCP)**. If the editor crashed, open it again and tick the box. Check `--project` is the folder with `project.godot` |
| `bridge_unavailable` | The connection dropped during a call | Check the editor is open and the box still ticked. The agent can retry |
| `auth_failed` | The token in the discovery file is not the open editor's | Two editors open on one project can do this. Close one, then untick and tick the box |
| `unsupported_bridge_version` | The server and the addon are from different versions | Update whichever is older |
| `target_changed` | You switched scene or level since the agent last looked | The agent calls `hf_get_status` and carries on with the open one |
| `no_level` | The open scene has no HammerForge level | Ask for a starter level, or open a scene that has one |
| `undo_conflict`, `redo_conflict` | The step is not the agent's, or you changed the level since | Use the editor's own undo for your work |
| `busy` | Another command is still running | Wait. `hf_get_status` says what and for how long |
| `bake_busy` | A bake is already running | Wait for it to finish |
| `bake_failed`, `export_failed` | The bake did not finish, or its file could not be written | Read the warnings in the answer, and the editor's Output panel |
| `screenshot_unavailable` | The editor has no picture to give | Screenshots need an editor with a window. A headless editor cannot draw |
| `no_bake` | A screenshot asked to show the bake, and the level has none | The agent bakes first with `hf_bake` |
| `timeout` | No answer in time | The editor may still be working. The answer gives an `operation_id`; the same change sent with it returns the first answer instead of running twice |
| `internal_error` | A script error in the editor | See the Output panel, and report it with what you asked for |

`hammerforge-mcp --check` is the quickest way to see whether the server can
reach the editor at all. It connects beside a working agent, not in its place,
and can only read status, so it is safe to run while an agent builds.

## Limits

| What | Limit |
|---|---|
| One request | 1 MiB |
| One answer | 16 MiB |
| Changes in one `hf_batch` | 100 |
| Brushes in one `hf_get_brushes` answer | 2000 (200 unless asked) |
| Screenshot size | 64 to 1920 wide, 64 to 1080 tall (1280 by 720 unless asked) |
| Brushes one screenshot leaves out | 1000 |
| One extrude | 256 m |
| Positions and sizes | 100000 m on each axis |
| An `operation_id` | 128 characters of `A-Z a-z 0-9 . _ : -` |
| Answers kept for retries | the last 256 changes that went through |
| Time before the server gives up | 15 s for status, 60 s for validate and screenshots, 900 s for a bake, 30 s for the rest |

Your client may stop waiting sooner than the server does. A long bake still
finishes in the editor, and `hf_get_status` says when it has.

## Known limits

- A screenshot needs an editor with a window. A headless editor answers
  `screenshot_unavailable` straight away.
- After the agent's `hf_undo`, the editor's Ctrl+Shift+Z may not redo that step.
  Use `hf_redo`, or the editor's History dock
  ([#1028](https://github.com/saworbit/hammerforge/issues/1028)). The dock's own
  Undo button has the same limit.
- One level per scene. Hollow, clip, merge, carve, floor paint, cordons,
  generators and prefabs are not on the bridge yet. A brush made an entity stays
  one: `hf_set_brush_entity` changes its class, and only `hf_undo` or the dock's
  Untie makes it plain again. It ties one brush at a time, and a brush entity's
  own properties cannot be set yet
  ([#1105](https://github.com/saworbit/hammerforge/issues/1105)).
- A plain screenshot is the editor's own view, with its grid, axis lines and
  selection over the level. A focused or camera shot draws without them. The
  brushes still draw as the editor shows them, see-through, unless the shot asks
  for `show: "baked"`, which draws the last bake instead.
- `hf_get_status` answers as soon as the editor reads it, but a bake holds the
  editor while it builds the level's mesh, so a status sent then waits until the
  bake next lets a frame go by.
- `hf_get_status` gives the counts from the last `hf_validate`, with
  `validation_revision`, the revision it ran at. When that is behind `revision`,
  call `hf_validate` for current ones.
- A change a script makes without the undo history does not move the revision,
  so the agent cannot tell it happened.
