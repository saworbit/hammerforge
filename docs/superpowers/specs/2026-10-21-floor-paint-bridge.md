# Floor paint on the agent bridge

2026-10-21. Issue #1299. Builds on the command registry
(`2026-10-17-command-registry-design.md`), whose first build left floor paint
off the bridge because the palette's paint commands act on the last painted
rectangle, the hovered cell and a mouse drag.

## What it is

Floor paint is cells on a layer: a `HFPaintLayer` holds a bitset of filled cells
in chunks, a material id per cell, a wall height per cell where the Raise
gesture set one, and the level keeps the connector definitions the mapper
confirmed between two layers. The generated floors and walls under
`LevelRoot/Generated` are rebuilt from the cells by the reconciler, chunk by
chunk. Everything above is inside `capture_state()` (`paint_layers`,
`paint_active_layer`, `paint_connectors`), which is why the palette's paint
actions are one `restore_state` undo step each.

Two layers:

1. **Cell-space calls on `HFPaintSystem`**, with no screen, camera or mouse in
   them. Each writes the layer, consumes the chunks it dirtied and reconciles
   them through the same reconciler the tool uses, so the generated geometry
   follows at once, as it does after a stroke.
2. **Bridge forms** in `HFCommandRegistry`, executed by `HFMcpCommands` through
   the dispatcher's `_run_mutation()`, so each run is one `MCP: ...` step,
   `hf_undo` takes it back, and each may be an `hf_batch` op.

## The system calls

`addons/hammerforge/systems/hf_paint_system.gd`. A cell is `Vector2i(x, z)`:
the paint grid's second axis is world Z. A rectangle is two corners, inclusive,
in any order. Each call answers `{ok, error, ...}` and changes nothing when it
refuses.

| Call | What it does in cells |
|---|---|
| `paint_cells(layer_index, from, to, filled, material_id = -1)` | Sets every cell of the rectangle to `filled`. With a material id and `filled`, writes it on each cell as the Blend tool does. Answers `changed`, the cells whose bit flipped, and `cells`, the rectangle's count |
| `raise_cells(layer_index, from, to, height)` | Sets the wall height of every filled cell in the rectangle, what `confirm_height_gesture()` does for the last stroke's footprint. Unfilled cells are left alone. Refuses when the rectangle holds no filled cell. Answers `raised` (filled cells) and `changed` (heights that moved) |
| `stamp_room(layer_index, at, width, depth, height = -1.0)` | `paint_cells` of the `width` by `depth` rectangle whose lowest corner is `at`, then `raise_cells` of it when `height` is given: what `stamp_room_from_last_rect()` does with the last rectangle's size at the hovered cell, with the size and the corner named |
| `confirm_connectors(layer_index, from, to, to_layer_index = -1)` | The connector candidates the tool would show as ghosts after painting those cells on that layer (`HFAutoConnector.defs_for_touched_cells()` with the level's connector mode, stair height and width), kept as confirmed definitions, what `confirm_connector_ghosts()` does. `to_layer_index` keeps only the candidates that join that layer. One already confirmed is counted, not added twice. Refuses when nothing touches another layer |

Also: `paint_layer_at(index)`, `find_paint_layer(name)` (display name, then
id) and `describe_paint_layers()`, which is what the listing shows an agent.

Limits: a cell index within 100000 of the origin on each axis, and at most
65536 cells in one rectangle (`MAX_RECT_CELLS`), so one call cannot take the
editor away for minutes. A call is refused while the Paint tool is in the
middle of a stroke or a height gesture.

Region streaming: when it is on, the regions the rectangle touches are loaded
and pinned for the call and released after, as a stroke does through
`handle_paint_input()`.

What stays one implementation: the rectangle's cells come from
`HFPaintTool.rect_cells()`, which the tool's own Rect stroke, its preview and
`stamp_room_from_last_rect()` use too; the connector settings are synced from
the level in one place (`_sync_connector_settings()`), for strokes and for the
bridge; and confirming a definition is `HFPaintTool.add_connector_defs()`,
which `confirm_connector_ghosts()` now calls for its pending ghosts. The per-cell
writes are `HFPaintLayer.set_cell()`, `set_cell_material()` and
`set_wall_height()`, the primitives the tool writes through as well.

What the calls do not do: run inference cleanup (a Paint-tab option the plugin
hands the tool per stroke; the bridge has no dock), apply the mirror axes, or
touch the tool's memory of the last stroke (`_last_committed_cells`,
`_last_rect_size`, the pending ghosts). A mapper's Y after an agent's paint
still raises the mapper's last stroke, not the agent's rectangle; the agent has
`paint_raise`.

## The forms

The answer's `made`, `removed` and `changed` are the brush lists every
`hf_run_command` answer carries (empty here: generated floors are not brushes),
so a paint answer counts its cells under its own names.

Registry ids are never renamed, so the forms sit on the palette entries that
are their human surface. The Rect tool's entry is `paint_ramp`, labelled
"Ramp / Rect".

| Command (id) | Form | Params | Answer extras |
|---|---|---|---|
| `paint_ramp` | `paint_rect` | `layer`, `from` (required), `to`, `filled` (default true), `material` (0 to 255, with filled cells only) | `layer`, `from`, `to`, `filled`, `cells`, `cells_changed`, `material`, `bounds` |
| `paint_raise` | `raise_rect` | `layer`, `from` (required), `to`, `height` (required, 0.25 to 256 m) | `layer`, `from`, `to`, `height`, `raised`, `heights_changed` |
| `paint_room` | `stamp_room` | `layer`, `at` (required), `width` and `depth` (1 to 256 cells, default 4, the tool's own first rectangle), `height` (0.25 to 256 m; the default wall height if absent) | `layer`, `at`, `from`, `to`, `width`, `depth`, `height`, `cells`, `cells_changed`, `raised`, `bounds` |
| `paint_confirm_connector` | `confirm_connector` | `layer`, `from` (required), `to`, `to_layer` | `layer`, `from`, `to`, `to_layer`, `connectors` (each one's `from_layer`, `to_layer`, `from_cell`, `to_cell`, `type`, `width_cells`), `added`, `already` |

Two parameter types join `PARAM_TYPES`:

- `cell`: `[x, z]`, two whole numbers, each within 100000 of the origin.
  `to` defaults to `from`, so one cell is a rectangle of one.
- `layer`: a layer's index from 0, or its name (display name, then id). Absent
  means the level's active paint layer, the one the Paint tab shows, which is
  level state (`paint_active_layer`), not the editor's selection. The answer's
  `layer` says which was used: `{index, id, name}`.

`bounds` is the rectangle in world metres, `{min: [x, y, z], max: [x, y, z]}`
on the floor's top (`layer_y` plus the floor thickness), so an agent can stand
a spawn or a brush on what it painted.

`hf_list_commands` gives each paint entry `paint_layers`: every layer's
`index`, `id`, `name`, `layer_y`, `cell_size` and `cells` (filled), read off the
level the bridge is on, or `[]` with no level open.

Refusals, all before anything is captured, so nothing changes and no step is
added:

- `invalid_argument` naming `params.layer` or `params.to_layer` for a layer the
  level does not have (the message lists the ones it has), `params.to` for a
  rectangle over `MAX_RECT_CELLS`, `params.material` given with `filled: false`,
  and the usual type and range refusals naming the param.
- `operation_failed` while the Paint tool is mid-stroke or mid-gesture; for
  `paint_raise` over no painted cell; for `paint_confirm_connector` with one
  layer, with no boundary at those cells, or with every candidate already
  confirmed.

A `paint_ramp` that changes nothing (the cells were already so) is not a
refusal: it answers `cells_changed: 0` and records a step, as every bridge command
does, so an agent's step count stays one per call.

## One undo step

Each run goes through `_run_mutation()`: `capture_state()` before, the form's
apply, `HFUndoHelper.commit_completed()` with `restore_state` either way. The
state holds the paint layers with their chunks, materials and wall heights, the
active layer and the connector definitions, so `hf_undo` puts back the cells, the
heights and the connectors together, and `restore_paint_layers()` rebuilds the
generated geometry. `tests/test_undo_sweep.gd` already holds the palette's paint
actions to the same comparison.

## Out of scope

- Brush, Line, Bucket and Blend strokes, mirror axes and inference cleanup on
  the bridge: each is a gesture or a dock option, and a rectangle covers what an
  agent lays out.
- Adding, removing, renaming or moving a layer, heightmaps, terrain slots and
  sculpting.
- Reading the cells back (`hf_get_brushes` does not list generated floors);
  the listing's `paint_layers` gives counts and the answers give bounds.
- Picking a connector's type per call: the level's connector mode, stair height
  and width apply, as they do to a stroke's ghosts.
- Typed MCP tools for paint; the Python server relays `hf_run_command` and
  names the commands only as examples.
