# hammerforge-mcp

An MCP server that lets an agent build in a live HammerForge level in the Godot
editor. It talks to the bridge inside the HammerForge addon over a loopback socket.

## Turn the bridge on

1. Open your project in the Godot editor with HammerForge enabled.
2. In the HammerForge dock, open the **Test** tab, then **Agent Bridge**.
3. Tick **Allow agent connections (MCP)**. The lamp turns amber and the line
   under it says which port it listens on.

The bridge is off again every time the editor starts. It listens on `127.0.0.1`
only, makes a new token each time it is turned on, and writes that token to
`.godot/hammerforge_mcp.json` in your project. Godot's own `.gitignore` covers
`.godot/`, and an export never includes it.

## Run the server

With [uv](https://docs.astral.sh/uv/):

```bash
uvx --from "git+https://github.com/saworbit/hammerforge#subdirectory=hammerforge_mcp" hammerforge-mcp --project /path/to/your/godot/project
```

`--project` is the folder with `project.godot` in it. `HAMMERFORGE_PROJECT` does
the same job. Without either, the current folder is used.

To add it to Claude Code:

```bash
claude mcp add hammerforge -- uvx --from "git+https://github.com/saworbit/hammerforge#subdirectory=hammerforge_mcp" hammerforge-mcp --project /path/to/your/godot/project
```

Logs go to stderr. `--log-file` writes them to a file as well.

## What an agent can do

| Tool | What it does |
|---|---|
| `hf_get_status` | Which editor, scene and level the bridge is on, the revision, counts, grid and camera |
| `hf_place_brush` | Place a brush: shape, size, position, union or subtract, snapped to the grid unless told not to |

Conventions: Godot Y-up, metres, world space. `size` is full extents and
`position` is the brush centre. With snapping on, size snaps to whole grid steps
and an unrotated brush's lowest corner lands on the grid.

Every change is one undo step named `MCP: ...` in the editor's history. Each
mutating call carries an `operation_id`, and a retry with the same one returns
the first answer instead of running again. The server makes one for you if you
leave it out.

If the editor moves to another scene or level, the next change is refused with
`target_changed`. Call `hf_get_status` to work on the new one.

## Develop

```bash
cd hammerforge_mcp
uv venv
uv pip install -e ".[test]"
uv run pytest
```

The design is in
[docs/superpowers/specs/2026-10-11-mcp-bridge-design.md](../docs/superpowers/specs/2026-10-11-mcp-bridge-design.md).
