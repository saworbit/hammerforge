# Command registry

Draft 2026-10-17, for review. Issue #1265. Builds on the agent bridge
(`2026-10-11-mcp-bridge-design.md`) and on four changes the plan assumes are on
main first: #1257 (Merge plans once per press), #1262 (undo manager stand-in,
undo and keymap sweeps), #1266 (plugin source greps become behaviour tests) and
#1267 (Carve checks for an overlap before its dialog).

## What it is

One table describes every command a HammerForge surface can run. Each entry
says what the command is called, where it is listed, what it needs selected,
whether it needs a level, and, when an agent may run it, how it runs with
explicit brush ids and parameters instead of a selection and a dialog.

```
palette, toolbar, viewport menu, radial menu      keys (plugin_input_router.gd)
        |                                                 |
        |  metadata: label, category, needs level,        |  guard numbers
        |  selection requirement                          |
        v                                                 v
             HFCommandRegistry (addons/hammerforge/hf_command_registry.gd)
        |                                                 |
HFPluginCommands.execute()                        HFMcpCommands (mcp/)
   the interactive forms, one match arm each        the parameter forms:
   (reads the selection and the dock,               check(root, targets, params)
    opens dialogs)                                   -> {ok, scope_ids, apply}
        |                                                 |
        +----------- LevelRoot facade (can_*, *_by_id) ---+
                                                          |
                                     HFMcpDispatcher: hf_list_commands, hf_run_command
                                     (target, revision, operation_id, MCP: undo step, hf_batch)
```

## Decisions

Decided from evidence, with the reasoning kept here. The issue asked the first
four.

| Topic | Issue says | This design | Why |
|---|---|---|---|
| 1. Tool shape | "One generic tool, or typed per-command tools generated from the registry" | Two generic tools, `hf_list_commands` and `hf_run_command`. The 25 typed tools stay as they are | See "Tool shape" below |
| 2. Explicit ids | Take brush ids, refuse an id it cannot resolve rather than fall back to the selection | `brush_ids` and `entities` arguments, resolved by the bridge's own readers before anything changes. One bad id refuses the whole command. A parameter form takes a LevelRoot and nothing else, so it cannot reach the selection | See "Explicit targets" below |
| 3. Dialog actions | A parameter form that never opens a dialog, same validation | Each parameter form calls the same `can_*` facade check the interactive form calls before its dialog, then the facade call. Every dialog today guards an undoable change, so the agent's call is the confirmation; what the dialog would have said comes back in the answer | See "Parameter forms" below |
| 4. Keymap labels | Move labels and categories into the specs without breaking tests that grep plugin source | `HFKeymap.get_action_label()` and `get_category()` keep their signatures and read the registry. No test reads `hf_keymap.gd` as text. The greps of plugin source read `plugin_commands.gd` arm text and the three surface methods in `plugin.gd`, and neither changes | See "Keymap labels and categories" below |
| The `match` | "One registry of command specs replaces the match" | The registry replaces the four metadata lists. The 94 arm bodies stay in `HFPluginCommands.execute()` as the interactive forms, behind a registry gate | What is duplicated today is the metadata, not the bodies. The bodies are what `tests/test_palette_action_sweep.gd` runs in ten states; moving them changes every surface and gains an agent nothing |
| Undo name | not covered | `MCP: ` plus the label in lower case: `MCP: hollow`, `MCP: merge brushes`, `MCP: create structure` | The prefix is what `hf_undo` checks. Labels are unique among bound actions (`test_no_two_actions_share_a_label`) |
| New ids | not covered | Ids never change. `create_arch` stays `create_arch`, labelled Create Structure | A user's keymap file is keyed by id, and `HFKeymap._validated()` drops a key it does not know |
| Commands with effects outside the level | not covered | Not on the bridge: Quick Save Prefab, its linked form, and Push to Source | They write files under `res://`, which no undo step records and `hf_undo` cannot take back |

### Tool shape

Three shapes were weighed.

- **A. Generic pair (chosen).** `hf_list_commands` returns each bridge command
  with its label, category, description, targets and a JSON Schema for its
  parameters. `hf_run_command` takes `command`, `brush_ids`, `entities`,
  `params` and `operation_id`. The Python server relays both and knows no
  command by name.
- **B. Typed tools built when the server starts**, from a registry read off the
  editor.
- **C. Typed tools generated at build time** into the Python package.

Why A:

- **The server cannot see the registry when the client asks for tools.** The
  Python bridge connects on the first call (`bridge.py` `_ensure_connected()`),
  and the editor may not be running when the client lists tools. B would list
  no command tools in that case.
- **New tools mid-session do not reach most clients.** MCP SDK 2.3 can add a
  tool at run time (`MCPServer.add_tool`), but in the 2026-07-28 protocol a
  `notifications/tools/list_changed` reaches a client only through a
  `subscriptions/listen` stream the client opened (`mcp/server/connection.py`,
  `NotifyOnlyOutbound`, which drops it otherwise). A client that lists tools
  once never sees B's late tools.
- **The SDK builds a tool from a Python function's signature.** B and C need a
  function and a pydantic model per command. The SDK calls the function with
  each argument's name as a keyword, so a parameter cannot be aliased and a
  name like `class` or `from` cannot be one (found in the 11 October sweep;
  that is why the bridge says `entity_class` and `look_from`). A generic
  `params` object carries any key.
- **Drift between the two halves.** C fixes the command list in the Python
  package. The server is installed from a git commit with `uvx`, so an addon
  newer than the server would have commands no tool names, and an older addon
  would be offered tools it answers with `unknown_method`. A pass-through
  server is right for any addon that speaks bridge version 1.
- **Test and context cost.** Each typed tool is a Python function, an input
  model, a batch op model in `BATCH_PARAMS`, a row in two tables that
  `test_catalogue.py` holds to the catalogue, and a cross-check in
  `test_limits.py`. Every tool's schema and description is in the agent's
  context on every turn; the 25 today run to a paragraph each. A says the same
  in two tools and one listing the agent asks for when it needs it.

What A costs, and what answers it:

- The client cannot check `params` against a schema. The editor checks every
  parameter anyway, as it does for the typed tools, and names the one that is
  wrong in `details.param` (`params.thickness`). The bridge never trusted the
  client's checks.
- The agent has to find the commands. The server's instructions and the
  `hf_run_command` description name the first build's commands and say to call
  `hf_list_commands` for parameters. A pytest checks each id the description
  names is a registry id.

### Explicit targets

`hf_run_command` takes `brush_ids` (array of strings) and `entities` (array of
entity paths, as `hf_get_entities` gives them). Each command's bridge entry says
how many of each it takes.

- Every brush id goes through `HFMcpTools._read_brush()`, the reader every
  brush tool uses: an empty id is refused before any lookup (the brush system's
  slow path matches a brush with no id), an unknown id is `brush_not_found`, a
  committed cut is `brush_not_found` with `committed: true`. Every entity goes
  through `_read_entity()`.
- An id listed twice is `invalid_argument`. Too few or too many is
  `invalid_argument` naming `brush_ids`, with the count the command takes.
  Entities given to a command that takes brushes only is `invalid_argument`
  naming `entities`.
- All of this runs in the check, before the capture. A refusal touches nothing,
  and the whole command is refused: no partial run on the ids that did resolve.
- **No fallback, by construction.** A parameter form is
  `check_<form>(root, targets, params)`. It gets no plugin, so it has no
  selection, no dock, no Face Select memory, no axis lock and no pivot mode to
  read. Today Clip to Face falls back to the selection saved on entering Face
  Select when the live one is empty (`clip_target_brush_ids()`), and Hollow and
  Clip take the first selected node and ignore the rest. None of that is
  reachable from the bridge. A test runs a command with a made-up id while a box
  is selected in a real plugin (`tests/support/plugin_stand_in.gd`) and checks
  the refusal, the box, and the selection.

`$N.brush_id` in an `hf_batch` op works inside `brush_ids` already:
`_resolve_refs()` walks arrays.

### Parameter forms

A parameter form is the command's work with every input explicit.

1. **Same validation.** The check calls the facade check the interactive form
   calls before its dialog: `can_hollow_brush`, `can_clip_brush`,
   `can_carve_brush` (#1267), `can_merge_brushes`, `can_build_generator`,
   `plane_splits_brush`. A refusal is `operation_failed` with the result's
   `user_text()`, the words the palette shows. A test per command runs one
   refused case through the palette and through the bridge and compares the
   text.
2. **Dock values become parameters**, with the dock's own range and default.
   Hollow's thickness is 0.05 to 128, default 0.25, the numbers
   `selection_tools_builder.gd` gives its SpinBox; the build makes that SpinBox
   read them from the registry, so the two cannot drift. Clip's axis is the
   palette's Y unless given. A structure's type and settings are what the
   Structure section's widgets hold.
3. **No dialog, no preview, no toast.** Every dialog today guards a change undo
   takes back: Hollow, Clip, Carve, Delete of three or more, and the second
   press of a structure Update over painted faces. The agent's call is the
   confirmation, and `hf_undo` takes it back. What the dialog said comes back in
   the answer: the pieces made, the split position used, and `warnings`, the
   `user_message` lines at warning level and up the facade emitted during the
   run (as `hf_bake` collects them). That carries the "sculpt cannot follow this
   cut" warning (#871) with no code per command.
4. **Stricter on types than the dock.** The dock cannot send a string for a
   number or an unknown setting. An agent can, and `HFGeneratorSchema.merge()`
   would turn the first into the default with a log line and drop the second.
   The bridge refuses both with `invalid_argument` before the facade sees them.
5. **Synchronous.** `hf_batch` calls each op's `apply` without awaiting it. A
   command whose work awaits (Commit Cuts, Quick Bake, Bake Preview) is not on
   the bridge.

### Keymap labels and categories

- `HFKeymap.get_action_label(action)` and `HFKeymap.get_category(action)` stay
  public statics with the same signatures. Their bodies read the registry. An
  unknown name still falls back to `action.capitalize()` and `"Editing"`
  (`test_shortcut_dialog.gd` asks for the first).
- `HFKeymap` keeps the bindings, `action_mode()`, the conflict warnings and
  `GODOT_3D_DEFAULTS`. The `LABELS` table and the category rules go.
- Tests call these functions; none reads `hf_keymap.gd` as text
  (`grep -rn hf_keymap.gd tests/` finds only preloads). The vibe scenario
  `command-surfaces` does read it, for the label table, and moves to the
  registry in the build.
- The plugin source greps (`test_plugin_commands.gd`,
  `test_cutting_commands.gd`, `test_transform_commands.gd`,
  `test_bugfix_regressions.gd`, `test_selection_gesture.gd`) look for arm text
  such as `"clip_to_face":` and `plugin._clip_to_face_plane_selected(root)`, for
  `_managed_action_surface_allowed(root, action)` and `HFPluginCommands.execute`
  in the three surface methods of `plugin.gd`, and for
  `HFPluginSelectionState.managed_surface_action_requirement` in `plugin.gd`.
  None of that text changes. #1266 converts most of them anyway; any it keeps
  survives.

## Registry

`addons/hammerforge/hf_command_registry.gd`, `class_name HFCommandRegistry`,
pure data and lookups. No plugin, dock or node references, so the dispatcher can
preload it without reaching the editor.

```gdscript
const COMMANDS := [
	{
		"id": "hollow",
		"label": "Hollow",
		"category": "Editing",
		"needs_level": true,
		"selection": {"brushes_only": true, "minimum": 1, "label": "Hollow"},
		"bridge": {
			"form": "hollow",
			"description": "Shell one brush into walls of thickness, inward from its faces ...",
			"targets": {"brushes": [1, 1], "entities": false},
			"params": [
				{"key": "thickness", "type": "float", "min": 0.05, "max": 128.0,
				 "step": 0.05, "default": 0.25, "description": "Wall thickness in metres"},
			],
			"undo": "level",
		},
	},
	...
]
```

| Field | Meaning | Replaces |
|---|---|---|
| `id` | The action name every surface sends. Unique, never renamed | the arm names |
| `label` | What the palette and the rebind dialog call it | `HFKeymap` `LABELS`, and the capitalised fallback for the 38 arms that had no label |
| `category` | The palette and rebind dialog group | `HFKeymap.get_category()` rules |
| `needs_level` | The palette refuses it with no level rather than make one | `HFPluginCommands.requires_existing_root()` list |
| `selection` | `{}` or the exact dictionary `managed_surface_action_requirement()` returns today: `brushes_only`, `minimum`, `label`, `allow_faces`, `mixed_only` | the chain in `HFPluginSelectionState.managed_surface_action_requirement()` |
| `guard_only` | True for `apply_context_material`, the one id the guard knows that `execute()` never runs (the material quick apply calls it) | |
| `bridge` | Absent for a palette-only command | |
| `bridge.form` | The name of `HFMcpCommands.check_<form>` | |
| `bridge.description` | What the agent reads in `hf_list_commands` | |
| `bridge.targets` | `brushes: [min, max]` (max -1 for no cap), `entities: bool`. Never asks for fewer than `selection.minimum` | |
| `bridge.params` | Fields in `HFGeneratorSchema`'s shape (`key`, `type`, `min`, `max`, `step`, `default`, `description`, `options`), plus the types the bridge needs: `vec3`, `axis` (`"x"`, `"y"`, `"z"`), `face` (as `hf_extrude_face` takes it), `string` | |
| `bridge.undo` | `scope`: changes only the named targets and adds or removes nothing, so the step records those brushes. `level`: anything else inside `capture_state()` | |

Lookups: `ids()`, `has(id)`, `find(id) -> Dictionary`, `label(id)`,
`category(id)`, `needs_level(id)`, `selection(id)`, `bridge_ids()`,
`bridge(id)`, `listing() -> Array` (what `hf_list_commands` answers, the params
as JSON Schema), `field(id, key)`.

`TOOL_SWITCH_ACTIONS` stays in `plugin_commands.gd`. It is what `execute()` does
before an arm, not something a mapper or an agent sees, and
`test_plugin_commands.gd` reads the constant.

The table is one `const` of dictionaries. gdformat moves a comment that sits
between wrapped dictionary entries into one of them, so the table carries no
comments between entries; the reasons live in each `bridge.description` or in
the file header.

## Surfaces

Nothing a mapper sees changes. Labels, categories, order, toasts and guard
behaviour are pinned by a golden table taken from the current code before the
change (plan step 1).

| Surface | Today | After |
|---|---|---|
| Hotkey palette, rebind dialog | `keymap.grouped_actions()` and `HFKeymap.get_action_label()` | The same calls, reading the registry |
| Palette dispatch | `_on_hotkey_palette_action()`: `requires_existing_root`, the managed guard, `execute()` | The same three, reading the registry |
| Context toolbar, viewport menu, radial menu | Their own short labels and tooltips, then `execute()` | Unchanged. Their strings are layout, not metadata |
| `execute()` | `match` with no default arm | First line: an id the registry does not know is logged with `HFLog.warn` and runs nothing. A registry id with no arm reaches a default arm that calls `push_error`, so the palette sweep fails on it |
| Keys, `plugin_input_router.gd` | Its own guard calls with numbers that repeat the selection requirement (`_guard_hammerforge_shortcut(root, true, 2, "Merge")`) | The numbers come from `HFCommandRegistry.selection(id)`. Its labels, its order, its PASS and STOP answers to Godot and its #927 yield stay as they are |
| Global keys, `plugin_shortcuts.gd` | Delete, Duplicate, Copy and Nudge claimed with `(false, 1)` | Unchanged |

The router's toast labels ("Move to Floor") and the palette guard's ("Move To
Floor", from `capitalize()`) differ today. The first build keeps both, so no
toast text moves. Making them one is a follow-up.

## Bridge

### hf_list_commands

Read-only. Answers with no scene or level open, as status does: it reads only
the registry. Result:

```json
{"commands": [
  {"command": "hollow", "label": "Hollow", "category": "Editing",
   "description": "...", "targets": {"brushes": {"min": 1, "max": 1}, "entities": false},
   "params": {"type": "object", "properties": {"thickness": {"type": "number",
     "minimum": 0.05, "maximum": 128, "default": 0.25, "description": "..."}},
     "required": [], "additionalProperties": false},
   "undo": "level"}
]}
```

`create_arch` adds `settings_by_type`: a JSON Schema object per structure type
from `HFGeneratorSystem.settings_schema(type)`, since the keys depend on the
type.

### hf_run_command

```json
{"command": "hollow", "brush_ids": ["1234_5"], "params": {"thickness": 0.5},
 "operation_id": "..."}
```

The dispatcher handles it beside the `MUTATING` lookup in `_run_tool()`:

1. `command` must be a bridge id. Otherwise `unknown_command` (new code), whose
   details list the bridge ids; a palette-only id says it is not on the bridge.
2. Targets and parameters are read and checked against the entry (types,
   ranges, required, unknown keys refused).
3. `HFMcpCommands.check_<form>(root, targets, params)` runs the facade checks
   and returns `{ok, scope_ids, apply}`, the contract every `HFMcpTools`
   `_check_<tool>` already has.
4. `_run_mutation()` runs it: capture, apply, commit `MCP: <label>` with
   `commit_completed()`, or restore. `scope_ids` is the targets for an `undo:
   scope` command and `[]` for `level`.

Everything the bridge promises carries over because nothing new sits between
the request and `_run_mutation()`:

- **operation_id replay.** The fingerprint is `{method, params, expect_target}`
  and the params hold the command, targets and parameters.
- **Agent-only undo.** The step is named `MCP: ...` and `_settle()` records the
  agent revision.
- **target_changed.** Checked before `_run_tool()`, as for every change.
- **All-or-nothing `hf_batch`.** An op may be `{tool: "hf_run_command", params:
  {...}}`. Its check runs against what the earlier ops left, its apply inside
  the batch's one capture. Every first-build command keeps its effects inside
  `capture_state()` (brushes, entities, paint, generator, hollow and prefab
  records), so a later refusal restores it.

The answer:

```json
{"command": "hollow", "label": "Hollow",
 "made": [{"brush_id": "1234_9", ...}], "removed": ["1234_5"],
 "changed": [], "warnings": [], "split_position": null}
```

- `made` and `removed` come from the managed brush ids and entity paths before
  and after the apply, read off the nodes (not through
  `get_brush_info_from_node()`, which writes an id onto a brush without one).
  The facade's `HFOpResult` carries no ids, which is why the bridge design
  deferred hollow, clip and merge; the diff answers it for every command at
  once. `made` brushes come without faces, to keep a dome's answer small;
  `hf_get_brushes` gives them.
- When exactly one brush is made, the answer also has `brush`, so
  `$N.brush_id` names a merge's result in a batch.
- `changed` lists the surviving targets after a `scope` command.
- Extra keys per command are in the table below.

New error code: `unknown_command` (domain). Everything else is an existing
code: `brush_not_found`, `entity_not_found`, `invalid_argument`,
`operation_failed`, `no_level`, `no_edited_scene`, `target_changed`,
`operation_id_conflict`, `batch_failed`.

### Python

`catalogue.py` gains the two tools. `hf_list_commands` is read-only;
`hf_run_command` is `destructive_hint` (it can delete and merge), not
idempotent, 30 s timeout. `server.py` gets two thin relays and a `RunCommandOp`
in the batch union with `RunCommandParams(command, brush_ids, entities,
params)`. `command` is a string matching `^[a-z_0-9]+$`; `params` is an open
object. A newer server against an addon without the tools gets
`unknown_method`, as the catalogue says it should.

## First build

The ROADMAP's "Not yet on the bridge" list, against what a registry of palette
actions can deliver:

| ROADMAP item | First build | Why |
|---|---|---|
| hollow | `hollow` | |
| clip | `clip`, `clip_to_face` | |
| merge | `merge` | |
| carve | `carve` | |
| generators | `create_arch` (Create Structure) | Update and Detach of an existing structure are follow-ups |
| prefabs | `cycle_variant`, `propagate_prefab` | Placing a prefab is a drag and drop, not a palette action. Saving and Push to Source write files undo cannot see |
| floor paint | none | The palette's Raise, Stamp Room and Confirm Connector act on the last painted rectangle, the hovered cell and a mouse drag (`hf_paint_tool.gd` `stamp_room_from_last_rect`, `begin_height_gesture`). There is nothing to parameterise until the paint system has calls in cell space |
| cordons | none | Not a palette action. Cordons are level settings outside `capture_state()`, so the wrapper and `hf_batch` would need a full-state capture first |

Also on the bridge, as the first forms the plumbing is proven with:
`move_to_floor`, `move_to_ceiling`, `reset_rotation`. They take ids, call one
facade method, and are `undo: scope`.

| Command | Targets | Params | Check | Apply | Undo | Answer extras |
|---|---|---|---|---|---|---|
| `move_to_floor`, `move_to_ceiling` | brushes, 1 or more | none | targets | `move_brushes_to_floor/ceiling(ids)` | scope | |
| `reset_rotation` | brushes, 1 or more | none | targets | `reset_managed_rotation(ids)` | scope | |
| `hollow` | brushes, exactly 1 | `thickness` 0.05 to 128, default 0.25 | `can_hollow_brush(id, t)` | `hollow_brush_by_id(id, t)` | level | `thickness` |
| `clip` | brushes, exactly 1 | `axis` default `y`; `position` (world, along the axis) default `default_clip_position(id, axis)` | `can_clip_brush(id, axis, pos)` | `clip_brush_by_id(id, axis, pos)` | level | `split_position` after snapping |
| `clip_to_face` | brushes, 1 or more | `plane_brush_id`, `plane_face` (face selector) | the face resolves, `face_world_plane()` has a normal, `plane_splits_brush()` for at least one target | `clip_brushes_by_plane(cuttable, plane)` | level | `skipped` (targets the plane misses) |
| `carve` | brushes, 1 or more (the carvers) | none | `can_carve_brush(id)` (#1267) for each; refused when none cuts | `carve_with_brush(id)` for each that cuts, in one step (the palette makes one step per carver) | level | `skipped` |
| `merge` | brushes, 2 or more | none | `can_merge_brushes(ids)`, planning once as #1257 settles it | `merge_brushes_by_ids(ids)` | level | `brush` |
| `create_arch` | none | `type` (one of `HFGeneratorSystem.known_types()`), `settings` (that type's keys; unknown keys refused; enum by index or label), `position` (vec3, required), `rotation_degrees` (vec3, default 0, Euler XYZ) | `can_build_generator(type, settings)`: schema ranges and the builder's own rules | `create_generator(type, settings, placement)` | level | `generator_id`, `settings` as applied |
| `cycle_variant` | 1 brush or entity, a piece of a prefab instance | none | the node carries `hf_prefab_instance` | `prefab_system.cycle_variant(instance_id)` | level | `variant` |
| `propagate_prefab` | 1 brush or entity, a piece of a linked instance | none | the node carries `hf_prefab_source`; refused when no linked instance takes it | `prefab_system.propagate_from_source(source)` | level | `instances` |

`hf_get_brushes` and `hf_get_entities` gain `prefab`: `null`, or `{instance_id,
source, variant, linked}`, so an agent can find a prefab's pieces.

## Coverage

- **The palette sweep** reads its actions from `HFCommandRegistry.ids()` (less
  the guard-only id) instead of parsing `plugin_commands.gd`. It keeps
  `assert_gt(actions.size(), 80)` and checks every keymap action is a registry
  id. A registry id with no arm hits the default arm's `push_error`, which the
  sweep fails on in every state. After #1262 it also undoes and redoes each
  action through the undo stand-in.
- **A bridge command sweep**, `tests/test_mcp_command_sweep.gd`, takes every
  `bridge_ids()` entry through the dispatcher in edge states: no level, a
  made-up id, a committed cut, a pending cut, a generator piece, a brush entity,
  a displaced brush, a deleted brush's id, an entity alone, a selection in a
  real plugin that names other brushes. Each case must raise no script error. A
  refusal must leave `capture_state()` as it was and add no step. A success must
  add exactly one step named `MCP: ...`, undo must give back `capture_state()`
  from before, and redo the state from after with the same brush ids. A new
  bridge entry is swept without being listed.
- **A surface test** presses every context toolbar button and viewport menu
  item through signal watchers, reads the radial menu's `SEGMENTS` and the
  keymap's actions, and checks each id it gets is a registry id.

## Testing

1. Golden table (plan step 1): every arm id and `apply_context_material`, with
   `needs_level`, `selection`, label, category and keymap mode, taken from the
   current functions into `tests/fixtures/command_registry_golden.json`. Passes
   before the change and after it. Deleted at the end of the build, once the
   registry is the only copy.
2. Registry invariants (`tests/test_command_registry.gd`): unique ids; every
   keymap action is an id; every bridge entry has a description, known param
   types, defaults inside their ranges, targets no looser than `selection`,
   `undo` of `scope` or `level`, `needs_level` true; `listing()` is valid JSON
   Schema in the words the bridge uses (`minimum`, `maximum`, `enum`, never
   pydantic's `gt` or `le`).
3. Dispatcher tests (`tests/test_mcp_dispatcher_commands.gd`) per command:
   success, refusal parity with the palette's text, one step, undo and redo,
   save and reload through `.hflevel`, `operation_id` replay, and for every
   numeric param a value one step past each bound refused naming
   `params.<key>`.
4. Batch: a hollow then a refused clip gives `batch_failed`, the level as it
   was, no step; a merge's `brush` feeds `$1.brush_id`.
5. pytest: the two tools relay; `RunCommandOp` in a batch; each id the
   description names is a registry id (read from `hf_command_registry.gd`); the
   README and guide tables list both tools; `test_limits.py` passes unchanged.
6. Smoke: `tools/mcp_bridge_smoke.py` lists commands, runs `move_to_floor` on
   the box it places, and undoes it.
7. Vibe, real editor and real server: hollow a room, clip it, carve a doorway,
   merge two blocks, build stairs, cycle a prefab variant, each undone with
   `hf_undo`, and the same done from the palette for comparison.

## Pre-mortem

Three months on, this went wrong. The likeliest ways, and how each fails safe:

1. **A label, category or toast changed.** The palette shows another name or
   group, or a toast reads differently. The golden table pins every value
   before the change and the build does not pass until the registry reproduces
   it. Toast labels are left as each surface has them.
2. **A surface sends an id the registry lacks.** The button does nothing. The
   gate logs a warning naming the id, and the surface test presses every button
   and menu item. Fails safe: nothing runs.
3. **A registry id has no arm.** The default arm's `push_error` fails the
   palette sweep in every state.
4. **A parameter form reads the selection or the dock.** It cannot: it gets a
   LevelRoot only. The made-up-id test with a live selection would see it.
5. **A parameter form takes another check than the palette.** The parity test
   per command compares refusal text. Both call one `can_*` function, so a
   change to the rule changes both.
6. **The bridge undoes a human's work through a command.** `undo` and `redo`
   are palette-only and a registry test refuses a bridge entry for them, for
   `quick_play`, `quick_bake`, `validate_level` and `commit_cuts`. Every bridge
   run goes through `_run_mutation()`, so its step is `MCP: ...` and `hf_undo`'s
   three rules hold. The command sweep checks one step per run.
7. **A batch keeps half a command.** Only commands whose effects are inside
   `capture_state()` are on the bridge (registry test on `undo`), and a batch
   test fails a later op after a hollow.
8. **Python and the editor disagree on the commands.** The server names none
   but the examples in one description, which a pytest holds to the registry.
   An older addon answers `unknown_method`, which the server shows as an error.
9. **The prerequisite changes are not what this assumed.** #1257 might cache by
   ids rather than take a plan; #1267 might name its check otherwise. The plan
   reads their merged code at step 0 and the merge and carve forms call what is
   there. If #1257 has not landed, merge plans twice over the bridge, as the
   palette does today.
10. **The registry file fights gdformat.** No comments between entries. After
    formatting, `git diff --stat` must show only the intended files.
11. **A command that changes nothing still records a step** (Move to Floor on a
    brush on the floor). Same as the palette today. Documented, not fixed.
12. **The editor stalls on a big command.** A dome or a merge of round brushes
    runs on the main thread, as from the palette. `capture_state()` is 39 ms at
    900 brushes. The 30 s timeout is the client's limit.

## Out of scope

- Floor paint, cordons and placing a prefab from the library (see First
  build). Each needs facade work first and gets its own issue.
- Quick Save Prefab, Save as Live-Linked Prefab and Push to Source on the
  bridge (they write files undo cannot see).
- Structure Update and Detach; Clip by an arbitrary plane; setting a named
  prefab variant.
- Duplicate, Delete, Group, Ungroup, Rotate and Flip on the bridge (typed tools
  cover delete and absolute rotation; the rest wait for a need).
- Face selection commands (UV Justify, Apply to Brush, Apply Last Texture,
  Select Similar), selection commands, tool and mode switches, view toggles,
  vertex editing, Quick Play, Quick Bake, Bake Preview, Validate, Commit Cuts,
  Undo and Redo.
- Rewriting the 94 arms as table entries; changing `plugin_shortcuts.gd`;
  changing the router beyond where its guard numbers come from; one toast label
  per command.
- Typed per-command tools and `list_changed` notifications.
- Renaming any id.
- More than one LevelRoot per scene.

## Found along the way

What the issue says that the code does not bear out:

- **`create_arch` opens no dialog.** It reads the dock's Structure section (type
  dropdown and the schema-built fields) and places the structure at the
  selection's pivot and facing (`dock_brush_handler.gd` `on_create_structure`,
  `create_placement`). With a generated piece selected it becomes Update, whose
  second press over painted faces is the only confirmation. The parameter form
  replaces widget reads, not a dialog.
- **Delete opens a confirmation too**, for three or more objects. Merge opens
  none.
- **Not every item on the ROADMAP list is a palette action.** Cordons and
  prefab placement are not in the `match` at all, and the floor paint actions
  have no inputs to parameterise. The acceptance line "Every action on the
  ROADMAP's not-yet list can be run by an agent" cannot be met by a registry of
  palette actions. Proposed: this issue covers hollow, clip, merge, carve,
  structures and prefab variants; floor paint, cordons and prefab placement
  become their own issues.
- **"Without a hand-written tool" is true of the tool, not the command.** A new
  palette action needs no MCP tool, schema or Python change to reach the bridge,
  but its parameter form is still GDScript someone writes, because the
  interactive form reads the selection and the dock. The criterion would read
  better as "without a new MCP tool or any Python change".
- **The metadata lives in five places, not four.** `plugin_input_router.gd`
  repeats every selection minimum in its own guard calls. And `HFKeymap`'s
  labels and categories cover only the 58 bound actions. The 36 unbound arms
  have no label, and two bound ones (`grid_increase`, `grid_decrease`) fall
  back to a capitalised id.
