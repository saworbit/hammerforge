# Command registry

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One table describes every palette command. The palette, toolbar,
menus and keys read their metadata from it, and an agent can list the commands
the bridge runs and run one with explicit brush ids and parameters: hollow,
clip, clip to face, carve, merge, create structure, cycle prefab variant,
propagate prefab, and move to floor, move to ceiling and reset rotation.

**Architecture:** `HFCommandRegistry` is a `const` table with lookups. The
four metadata lists (`requires_existing_root`, `managed_surface_action_requirement`,
`HFKeymap` labels and categories) become reads of it, and the router takes its
guard numbers from it. `HFPluginCommands.execute()` keeps its arms as the
interactive forms behind a registry gate. The bridge gets `hf_list_commands`
and `hf_run_command`; each bridge entry names a parameter form in
`HFMcpCommands`, `check_<form>(root, targets, params) -> {ok, scope_ids,
apply}`, run by the dispatcher's existing `_run_mutation()` and `_batch()`.

**Tech stack:** GDScript (Godot 4.7, GUT 9.6), Python 3.10+ (`mcp>=2.3,<3`,
pytest).

**Spec:** `docs/superpowers/specs/2026-10-17-command-registry-design.md`.
Builds on the bridge (`2026-10-11-mcp-bridge-design.md`).

## Global constraints

- Main already holds #1257, #1262, #1266 and #1267. Step 0 checks.
- New scripts reference other classes through `const X = preload(...)`, never a
  bare global class name (fresh-clone parse rule). `hf_keymap.gd` and
  `plugin_selection_state.gd` preload the registry the same way.
- Every new `.gd` gets its `.uid` from `godot --headless --import`. A probe
  script that is deleted loses its `.uid` too.
- No visible change for a mapper: labels, categories, palette order, toasts and
  toolbar and menu strings stay byte-identical. The golden table holds this
  until step 13.
- A parameter form takes `root`, `targets` and `params`. It never takes the
  plugin, the dock or the host, and never calls `HFUndoHelper` or an undo
  manager: the dispatcher records the one step.
- No comments between entries of the registry's `COMMANDS` table (gdformat
  moves them into an entry). After every `gdformat`, normalise to LF and check
  `git diff --stat` shows only the files the step meant.
- Tier 1 only: run the scripts that cover the change, one `-gselect` pattern
  per run, and read the script and test counts in the summary:
  `cmd //c "C:\Godot\godot.cmd --headless --path C:/hf-wt-registry -s res://addons/gut/gut_cmdln.gd -gselect=<pattern> -gexit" > C:/hf-wt-registry/gut_x.log 2>&1`
- Free every node a test makes. Copy and Quick Save Prefab touch the
  developer's clipboard and `res://prefabs/`; any test that drives them sets
  them aside as `test_palette_action_sweep.gd` does.
- Lint as CI does: `gdformat --check addons/hammerforge/ tests/ tools/ hammerforge_tools/`,
  `gdlint addons/hammerforge/ tools/ hammerforge_tools/`,
  `python tools/check_script_warnings.py`, and ruff over `hammerforge_mcp/`.
- Each step ends at a checkpoint: its Tier 1 runs green and its mutation check
  done. In the builder batch nothing is committed and `CHANGELOG.md` is not
  touched; whoever opens the PR adds the one dated line.
- Prose in docs and comments: plain short sentences, no em or en dashes.

## Review focus

1. **A made-up brush id while the plugin has a selection.** `hf_run_command`
   refuses with `brush_not_found`, nothing moves, and the selection is what it
   was. Test in step 6, against a real plugin.
2. **Carve where only some carvers cut.** The ones that cut carve in one step,
   the rest come back in `skipped`. Carve where none cut is refused and adds no
   step. Test in step 7.
3. **A command inside `hf_batch` and a later op refused.** The level equals the
   capture, the hollow's walls are gone, and there is no step. Test in step 10.
4. **Create Structure with a string for a number, an unknown setting, and a
   setting out of range.** Each is `invalid_argument` naming
   `params.settings.<key>`; none reaches `HFGeneratorSchema.merge()`, which
   would have quietly used the default. Test in step 8.
5. **`hf_undo` after a command, then after a human edit.** The first takes the
   command back; the second conflicts, as for every bridge step. Test in step 6.
6. **A palette label or category after the move.** The golden table compares
   all 95 ids. Step 3.

---

### Task 0: Preconditions and baseline

- [ ] **Step 1: Read what landed.** `git log --oneline origin/main` shows #1257,
  #1262, #1266 and #1267. Read `HFPluginEditActions.carve_selected` and
  `merge_selected` as merged, and the facade they call now. Write down:
  - the name and signature of the carve overlap check (#1267 proposes
    `can_carve_brush(brush_id)`),
  - how a merge plans once (#1257: a plan passed from `can_merge_brushes()` to
    `merge_brushes_by_ids()`, or a cache keyed by ids, transforms and face
    counts), and what a caller must do to plan once.
- [ ] **Step 2: List what still reads plugin source.**
  `grep -rn "get_file_as_string" tests/ tools/vibe/ | grep -E "plugin_commands|plugin_selection_state|plugin_input_router|hf_keymap|plugin.gd"`.
  For each hit, note what text it needs. Steps 3 to 5 must keep that text or
  rewrite the test to the new contract.
- [ ] **Step 3: Import and baseline.**
  `cmd //c "C:\Godot\godot.cmd --headless --import --path C:/hf-wt-registry" > C:/hf-wt-registry/import.log 2>&1`,
  then Tier 1 runs of `test_keymap`, `test_shortcut`, `test_hotkey_palette`,
  `test_plugin_commands`, `test_selection_features`, `test_mcp_dispatcher` and
  `test_palette_action_sweep` (about 77 s). Record script and test counts.

### Task 1: Golden table of today's metadata

**Files:**
- Create: `tests/fixtures/command_registry_golden.json`
- Create: `tests/test_command_registry_golden.gd` (+ `.uid`)

The fixture is made once from the current code, so the registry has something
exact to match.

- [ ] **Step 1: Generate.** A throwaway test (not imported, so no `.uid`, and
  deleted after) builds, for each of the 94 arm ids and
  `apply_context_material`:
  `{needs_level: HFPluginCommands.requires_existing_root(id), selection:
  HFPluginSelectionState.managed_surface_action_requirement(id), label:
  HFKeymap.get_action_label(id), category: HFKeymap.get_category(id), mode:
  HFKeymap.action_mode(id), bound: default keymap has id}`, and writes it with
  `JSON.stringify(data, "\t", true)`. The 94 ids come from the arm regex the
  sweep uses today, run this once.
- [ ] **Step 2: The golden test.** Reads the fixture and compares each field
  for each id against the same four functions. Plus: the hotkey palette's rows
  (built through `HFHotkeyPalette` with the default keymap) list the same
  categories in the same order with the same labels as the fixture says.
- [ ] **Step 3: Run it.** `-gselect=test_command_registry_golden`: green on
  today's code. Mutation: change one label in `HFKeymap.LABELS`, see it fail,
  put it back.
- [ ] **Checkpoint.**

### Task 2: The registry

**Files:**
- Create: `addons/hammerforge/hf_command_registry.gd` (+ `.uid`)
- Create: `tests/test_command_registry.gd` (+ `.uid`)

**Interfaces (produces):**

```gdscript
class_name HFCommandRegistry extends RefCounted
const COMMANDS := [ {id, label, category, needs_level, selection, guard_only?, bridge?}, ... ]
const PARAM_TYPES := ["float", "int", "bool", "enum", "vec3", "axis", "face", "string"]
static func ids() -> PackedStringArray          # every id, guard-only included
static func dispatched_ids() -> PackedStringArray  # ids execute() runs
static func has(id: String) -> bool
static func find(id: String) -> Dictionary      # {} when unknown
static func label(id: String) -> String         # "" when unknown
static func category(id: String) -> String      # "" when unknown
static func needs_level(id: String) -> bool
static func selection(id: String) -> Dictionary # a copy; {} when none
static func bridge_ids() -> PackedStringArray
static func bridge(id: String) -> Dictionary    # {} for a palette-only id
static func field(id: String, key: String) -> Dictionary
static func params_json_schema(id: String) -> Dictionary
static func listing() -> Array                  # what hf_list_commands answers
```

- [ ] **Step 1: Failing tests.** In `test_command_registry.gd`:
  ids unique; `dispatched_ids()` is the 94 arm ids from the fixture and `ids()`
  adds `apply_context_material`; every default keymap action is an id; for
  every fixture id, `needs_level`, `selection`, `label` and `category` equal the
  fixture; labels unique among bound actions; `find("nope")` is `{}`;
  `selection()` returns a copy (mutating it leaves the table alone).
- [ ] **Step 2: Run, see them fail** (script missing).
- [ ] **Step 3: Write the table.** 95 entries, values copied from the fixture.
  No `bridge` entries yet. Lookups walk `COMMANDS` once into a static
  dictionary on first use.
- [ ] **Step 4: Import, run.** `-gselect=test_command_registry` (picks up the
  golden test too): both green.
- [ ] **Checkpoint.**

### Task 3: Point the four lists at the registry

**Files:**
- Modify: `addons/hammerforge/plugin_commands.gd`: `requires_existing_root()`
  returns `HFCommandRegistry.needs_level(action)`. First line of `execute()`
  after the null check: an id the registry does not dispatch is logged
  (`HFLog.warn("No HammerForge command '%s'" % action)`) and returns. A `_:`
  arm at the end of the `match` calls `push_error` naming the id. Arm text is
  not touched. `TOOL_SWITCH_ACTIONS` stays.
- Modify: `addons/hammerforge/plugin_selection_state.gd`:
  `managed_surface_action_requirement()` returns `HFCommandRegistry.selection(action)`.
- Modify: `addons/hammerforge/hf_keymap.gd`: `get_action_label()` returns the
  registry label, else `action.capitalize().replace("_", " ")`.
  `get_category()` returns the registry category, else `"Editing"`. `LABELS`
  and the category rules go.
- Test: `tests/test_plugin_commands.gd` gains: `execute(plugin, "no_such")`
  logs the warning and runs nothing (the plugin stand-in, a level, its
  `capture_state()` compared). The default arm cannot be reached from a test
  without a fake registry id, so step 4's sweep is what checks it.

- [ ] **Step 1: Change the three bodies and the gate.**
- [ ] **Step 2: Run** `-gselect=test_command_registry`, `-gselect=test_keymap`,
  `-gselect=test_shortcut` (dialog, surfaces, HUD layout), `-gselect=test_hotkey_palette`,
  `-gselect=test_selection`, `-gselect=test_plugin_commands`,
  `-gselect=test_cutting_commands`, `-gselect=test_transform_commands`,
  `-gselect=test_structure_dock_commands`, `-gselect=test_editor_shared_helpers`,
  and every script step 0 listed as reading these files.
- [ ] **Step 3: Mutation.** Change hollow's registry label: the golden test and
  `test_shortcut_dialog` fail. Drop `clip_to_face` from the registry: the
  palette press logs the warning and the golden test fails. Restore.
- [ ] **Checkpoint.**

### Task 4: Surfaces and the palette sweep read the registry

**Files:**
- Create: `tests/test_command_surfaces.gd` (+ `.uid`)
- Modify: `tests/test_palette_action_sweep.gd`: `dispatch_actions()` returns
  `Array(HFCommandRegistry.dispatched_ids())`. `COMMANDS_PATH` goes. The header
  says where the actions come from now.
- Modify: `tools/vibe/scenarios/command_surfaces.gd`: handled actions and labels
  from the registry, not from source text.

- [ ] **Step 1: Surface test.** Build the plugin with `PluginStandIn.build()`.
  Press every `Button` under the context toolbar that emits `action_requested`
  (`btn.pressed.emit()`, signal watched), press every item of the viewport
  context menu (`id_pressed.emit(id)` for each item id), read
  `HFRadialMenu.SEGMENTS`, and read the default keymap's actions. Each id seen
  is `HFCommandRegistry.has()`. At least one id from each surface was seen.
- [ ] **Step 2: Run** `-gselect=test_command_surfaces`, then the sweep,
  `-gselect=test_palette_action_sweep` (about 77 s). Same case count as the
  step 0 baseline.
- [ ] **Step 3: Mutation.** Rename the `"merge"` arm to `"merge_x"`: the sweep
  fails on the default arm's error for `merge` in every state. Restore.
- [ ] **Step 4: Vibe.** `python tools/vibe/run_vibe.py command-surfaces` reports
  the same handled count as before, and no new FLAG.
- [ ] **Checkpoint.**

### Task 5: The router takes its guard numbers from the registry

**Files:**
- Modify: `addons/hammerforge/plugin_input_router.gd`: each
  `_guard_hammerforge_shortcut(root, <brushes_only>, <minimum>, "<Label>")` for
  delete, duplicate, copy, paste, group, ungroup, hollow, move to floor, move to
  ceiling, clip, carve and merge reads `brushes_only` and `minimum` from
  `HFCommandRegistry.selection(<id>)`. The label literal, the order, and the
  PASS and STOP returns stay. Nudge has no registry entry and keeps `(false, 1)`.

- [ ] **Step 1: Change the twelve calls** through one helper,
  `_registry_guard(plugin, root, id, label) -> int`.
- [ ] **Step 2: Run** #1262's keymap sweep (find its script name at step 0),
  `-gselect=test_viewport_key_consume`, `-gselect=test_plugin_shortcuts`,
  `-gselect=test_bugfix_regressions`.
- [ ] **Step 3: Mutation.** Set merge's `minimum` to 1 in the registry: the
  keymap sweep or a router test merging one brush fails (if neither does, add a
  router test that Ctrl+Shift+M with one brush selected toasts "Merge needs at
  least 2 selected" and changes nothing). Restore.
- [ ] **Checkpoint.**

### Task 6: Bridge plumbing and the first three forms

**Files:**
- Create: `addons/hammerforge/mcp/hf_mcp_commands.gd` (+ `.uid`),
  `class_name HFMcpCommands`
- Modify: `addons/hammerforge/mcp/hf_mcp_dispatcher.gd`, `hf_mcp_protocol.gd`
  (`E_UNKNOWN_COMMAND := "unknown_command"`)
- Modify: `addons/hammerforge/hf_command_registry.gd`: `bridge` entries for
  `move_to_floor`, `move_to_ceiling`, `reset_rotation` (targets brushes 1 or
  more, no params, `undo: "scope"`)
- Create: `tests/test_mcp_dispatcher_commands.gd` (+ `.uid`)

**Interfaces (produces):**

```gdscript
class_name HFMcpCommands extends RefCounted
var tools: HFMcpTools                      # the dispatcher's, for _read_brush, _read_entity, _resolve_face, brush_dict
func _init(mcp_tools: HFMcpTools)
func read_targets(root: Node, spec: Dictionary, params: Dictionary) -> Dictionary
    # {ok, brushes: Array[DraftBrush], brush_ids: Array, entities: Array} or a refusal
func read_params(spec: Dictionary, given) -> Dictionary
    # {ok, value: Dictionary} with defaults filled, or invalid_argument naming params.<key>
func check(root: Node, command: String, params: Dictionary) -> Dictionary
    # {ok, scope_ids, apply} or a refusal; apply returns {ok, result}
func check_move_to_floor(root, targets, args) -> Dictionary
func check_move_to_ceiling(root, targets, args) -> Dictionary
func check_reset_rotation(root, targets, args) -> Dictionary
```

Dispatcher: `is_known_method()` takes `hf_list_commands` and `hf_run_command`.
`hf_list_commands` is answered before the target check, like status, with
`{commands: HFCommandRegistry.listing()}`, and is added to `READ_ONLY`.
`hf_run_command` goes through the busy guard and the cache like any change; in
`_run_tool()` it calls `commands.check(_root, params["command"], params)` and
then `_run_mutation(id, label.to_lower(), scope_ids, apply)`. The apply wraps
the form's apply: ids and entity paths before and after, the `user_message`
lines at level 1 and up collected, and the answer built as the spec says
(`command`, `label`, `made` without faces, `removed`, `changed`, `warnings`,
`brush` when exactly one was made, plus the form's extras).

- [ ] **Step 1: Failing tests** in `test_mcp_dispatcher_commands.gd`:
  - `hf_list_commands` with no scene lists exactly the three ids, each with a
    JSON Schema `params` holding no `gt`, `ge`, `lt` or `le`.
  - `hf_run_command` with `command: "nope"` and with `"tool_draw"` gives
    `unknown_command`, the second saying it is not on the bridge; no step.
  - Move to floor on a raised box: one step named `MCP: move to floor`, the box
    rests on the floor, `changed` holds it; `hf_undo` puts it back; `hf_redo`
    again; save and reload keeps it.
  - `brush_ids` empty, missing, with `""`, with a made-up id, with a committed
    cut, with an id twice, and `entities` given: each the code the spec names,
    `capture_state()` unchanged, no step.
  - One good id and one made-up id: refused, the good box not moved.
  - Same `operation_id` twice gives `replayed: true` and one step; same id with
    other `brush_ids` gives `operation_id_conflict`.
  - A command, then a foreign action committed on the undo stand-in, then
    `hf_undo`: `undo_conflict`.
  - `expect_target` of another level: `target_changed`.
- [ ] **Step 2: No fallback, against a real plugin.** In the same file, build
  `PluginStandIn.build(parent, scene_root)` over the scene the dispatcher's
  `HostStandIn` points at. Select box A through the plugin. Run move to floor
  with `[made-up]`: refused, A not moved, the plugin's selection still `[A]`.
  Run it with `[B]`: B moved, A not, selection still `[A]`.
- [ ] **Step 3: Run, see them fail. Implement. Import. Run**
  `-gselect=test_mcp_dispatcher` (all dispatcher suites) and
  `-gselect=test_command_registry`.
- [ ] **Step 4: Mutation.** Make `read_targets` skip an unknown id instead of
  refusing: the one-good-one-bad test fails. Restore.
- [ ] **Checkpoint.**

### Task 7: Hollow, Clip, Clip to Face, Carve, Merge

**Files:** `hf_mcp_commands.gd`, `hf_command_registry.gd` (five `bridge`
entries, descriptions in full), `tests/test_mcp_dispatcher_commands.gd`, and
`addons/hammerforge/ui/selection_tools_builder.gd`: the hollow thickness
SpinBox takes min, max, step and default from
`HFCommandRegistry.field("hollow", "thickness")`, so the dock and the bridge
share one range.

Forms, as the spec's table says:

- `check_hollow`: one brush; `thickness`; `root.can_hollow_brush(id, t)`;
  apply `hollow_brush_by_id(id, t)`; extras `thickness`.
- `check_clip`: one brush; `axis` (`"y"` default, to 0/1/2), `position`
  (default `root.default_clip_position(id, axis)`); `can_clip_brush(id, axis,
  pos)`; apply `clip_brush_by_id(id, axis, pos)`; extras `split_position` as the
  facade used it (snapped to the grid as `can_clip_brush` snaps it; read the
  facade at build time and echo what it applied).
- `check_clip_to_face`: brushes 1 or more; `plane_brush_id` through
  `_read_brush`, `plane_face` through `_resolve_face`; `face_world_plane()`
  must have a normal; targets the plane splits (`plane_splits_brush`) form
  `cuttable`, none is refused with the palette's words; apply
  `clip_brushes_by_plane(cuttable, plane)`; extras `skipped`.
- `check_carve`: brushes 1 or more; the #1267 check for each; none cutting is
  refused with the palette's words; apply `carve_with_brush(id)` for each that
  cuts; extras `skipped`.
- `check_merge`: brushes 2 or more, brushes only; `can_merge_brushes(ids)` and
  `merge_brushes_by_ids(ids)` called the way #1257 makes one plan per press.

- [ ] **Step 1: Failing tests,** each with `capture_state()` compared on every
  refusal, and every refusal the check makes carrying no `details.rolled_back`
  (it was refused before anything was captured):
  - Hollow a box: six walls in `made`, the box in `removed`, one step, undo and
    redo with the same ids, save and reload. Thickness 0.01 and 200 refused
    naming `params.thickness`; a string refused. A refused hollow (a thickness
    the box cannot take) gives `operation_failed` with the same text the palette
    toasts for that box (drive the palette through the plugin stand-in and
    catch `root.user_message`).
  - Clip a 4 m tall box: two pieces, `split_position` 2. Axis `"x"` with a
    position; a position outside the box refused with the palette's text.
  - Clip to face: two boxes, the plane of one face of a third through one of
    them only: that one cut, the other in `skipped`. A plane through neither:
    refused. `plane_face: "+y"` on a 45 degree turned box is `ambiguous_face`.
  - Carve: a carver over two boxes and a second carver over nothing: one step,
    the second in `skipped`. A carver over nothing alone: refused, no step
    (the #1267 behaviour on the bridge).
  - Merge two touching boxes: `brush` in the answer, both sources in `removed`.
    One id refused (`invalid_argument`, needs 2). Two touching 64-sided
    cylinders refused with the palette's text, and planned once (use #1257's
    test seam to count plans).
  - Every numeric param: one step past each bound refused naming it.
- [ ] **Step 2: Run, see them fail. Implement. Run** `-gselect=test_mcp_dispatcher_commands`,
  `-gselect=test_merge`, `-gselect=test_cutting_commands`, `-gselect=test_hollow`
  (tool, edit warning), `-gselect=test_live_hollow`, `-gselect=test_carve_tool`,
  `-gselect=test_clip` (tool, default split, to face plane), and the dock
  test that builds the hollow SpinBox (`grep -rln hollow_thickness tests/`).
- [ ] **Step 3: Mutation.** Drop the `can_hollow_brush` call from
  `check_hollow`. The facade then refuses inside apply with the same words, so
  the text still matches; what changes is that the level was captured and
  restored, and the answer carries `details.rolled_back`. The refusal tests
  assert a check refusal has no `rolled_back`, so this fails. Restore. Make
  carve apply every carver: the skipped test fails. Restore.
- [ ] **Checkpoint.**

### Task 8: Create Structure

**Files:** `hf_mcp_commands.gd`, `hf_command_registry.gd` (`create_arch`
bridge entry), `hf_command_registry.gd` `listing()` adds `settings_by_type`,
`tests/test_mcp_dispatcher_commands.gd`.

- `check_create_arch`: no targets. `type` one of
  `HFGeneratorSystem.known_types()`. `settings` an object: each key must be in
  `HFGeneratorSystem.settings_schema(type)`; a float or int field takes a
  finite number, a bool field a bool, an enum field an index in range or one of
  its option labels (case-insensitive, turned into the index). Missing keys take
  the schema defaults. Then `can_build_generator(type, settings)`. `position`
  required vec3, `rotation_degrees` optional vec3 (Euler XYZ). Apply
  `create_generator(type, settings, Transform3D(Basis.from_euler(rad, EULER_ORDER_XYZ), position))`.
  Extras: `generator_id` (the record the apply added, found by comparing
  generator ids before and after), `settings` as applied.

- [ ] **Step 1: Failing tests:**
  - Stairs at a position with two settings changed: the pieces in `made`, a
    `generator_id`, one step `MCP: create structure`; undo removes the pieces
    and the record; redo brings both back; save and reload keeps the record.
  - Each type in `known_types()` builds with no settings given.
  - A string for `rise`, a key `rize`, `rise: 5000`, an enum index out of range:
    `invalid_argument` naming `params.settings.<key>`, and nothing in the log
    from `HFGeneratorSchema._coerce`.
  - A combination the builder refuses (an arch wall thicker than its radius):
    `operation_failed` with the same text the dock's status line shows for
    those settings (`HFDockBrushHandler.on_create_structure` on a dock built as
    `test_structure_dock_commands.gd` builds one).
  - `hf_list_commands` gives `settings_by_type` for every known type, each
    field with its range.
- [ ] **Step 2: Run, fail, implement, run** `-gselect=test_mcp_dispatcher_commands`,
  `-gselect=test_live_generator_commands`, `-gselect=test_structure_dock_commands`.
- [ ] **Step 3: Mutation.** Let unknown keys through to `merge()`: the `rize`
  test fails. Restore.
- [ ] **Checkpoint.**

### Task 9: Prefab variant and propagate

**Files:** `hf_mcp_commands.gd`, `hf_command_registry.gd` (two entries),
`hf_mcp_tools.gd` (`prefab` on `brush_dict()` and `entity_dict()`),
`tests/test_mcp_dispatcher_commands.gd`, `tests/test_mcp_dispatcher_read.gd`.

- `check_cycle_variant`: one brush or entity carrying `hf_prefab_instance`
  (`HFPluginPrefabCommands.INSTANCE_META`; read the constant, do not spell it);
  otherwise `invalid_argument` naming the target. Apply
  `root.prefab_system.cycle_variant(instance_id)`; `""` back is
  `operation_failed`. Extras `variant`.
- `check_propagate_prefab`: one brush or entity carrying `hf_prefab_source`.
  Apply `propagate_from_source(source)`; 0 back is `operation_failed` with the
  palette's words. Extras `instances`.
- `prefab`: `null`, or `{instance_id, source, variant, linked}` read off the
  node's metadata and the instance record.

- [ ] **Step 1: Failing tests.** A prefab with two variants placed in the
  level (as `test_plugin_prefab_commands.gd` sets one up): cycle gives the other
  variant, one step, undo gives the first back. A plain box refused. Two linked
  instances, one edited and pushed by the test through the prefab system
  directly, then propagate from the other: `instances` 1. No linked instance:
  refused. `hf_get_brushes` shows `prefab` on the pieces and `null` elsewhere.
- [ ] **Step 2: Run, fail, implement, run** `-gselect=test_mcp_dispatcher`,
  `-gselect=test_plugin_prefab_commands`, `-gselect=test_prefab`.
- [ ] **Checkpoint.**

### Task 10: hf_batch takes hf_run_command

**Files:** `hf_mcp_dispatcher.gd` (`_batch()` accepts `tool: "hf_run_command"`
and runs `commands.check()` for it), `tests/test_mcp_dispatcher_batch.gd`.

- [ ] **Step 1: Failing tests:** place two boxes, merge them with
  `brush_ids: ["$0.brush_id", "$1.brush_id"]`, then hollow `$2.brush_id`: one
  step `MCP: batch (4 ops)`, the walls there. Place a box, hollow it, then clip
  a made-up id: `batch_failed` at index 2, `capture_state()` as before, no step.
  An op naming an unknown command: `batch_failed` at its index.
- [ ] **Step 2: Run, fail, implement, run** `-gselect=test_mcp_dispatcher_batch`.
- [ ] **Step 3: Mutation.** Restore only when the failing op itself applied (the
  bug the bridge review caught once): the hollow-then-bad-clip test fails.
  Restore.
- [ ] **Checkpoint.**

### Task 11: The bridge command sweep

**Files:** Create `tests/test_mcp_command_sweep.gd` (+ `.uid`); add its time
to `tests/.durations.json` if it runs over a few seconds.

- [ ] **Step 1: Write it.** `use_parameters(Array(HFCommandRegistry.bridge_ids()))`.
  States: no level, made-up id, committed cut, pending cut, generator piece,
  brush entity, displaced brush, a deleted brush's id, an entity alone, two
  boxes. For each command in each state, targets are what the state offers and
  params are the entry's defaults (plus a `position` and a `type` where
  required, read from the entry). Checks: no script error or `push_error`; a
  refusal leaves `capture_state()` equal and the step count the same; a success
  adds exactly one step whose name starts `MCP: `, undo gives back
  `capture_state()` from before, redo the state from after with the same brush
  ids. No orphans.
- [ ] **Step 2: Run** `-gselect=test_mcp_command_sweep`. Anything it finds is
  fixed in the form or filed with a `KNOWN` entry, as the palette sweep does.
- [ ] **Step 3: Mutation.** Make one form call `HFUndoHelper.commit` itself:
  the one-step check fails. Restore.
- [ ] **Checkpoint.**

### Task 12: Python server, pytest, smoke

**Files:** `hammerforge_mcp/src/hammerforge_mcp/{catalogue,server}.py`,
`hammerforge_mcp/tests/{test_server,test_catalogue}.py`,
`hammerforge_mcp/README.md`, `docs/HammerForge_Agent_Bridge.md` (tool table),
`tools/mcp_bridge_smoke.py`.

- `hf_list_commands`: read-only, 30 s. `hf_run_command(command, brush_ids=None,
  entities=None, params=None, operation_id=None)`: `destructive_hint`, not
  idempotent, 30 s. `command` is `str` with pattern `^[a-z_0-9]+$`; `params` is
  `dict[str, Any] | None`. Every `Field` before any `BeforeValidator` in an
  `Annotated` (the pydantic bound trap).
- The description names the first build's commands and says to call
  `hf_list_commands` for parameters. `INSTRUCTIONS` says the same in one line.
- `RunCommandParams` and `RunCommandOp` join `BATCH_PARAMS` and the `BatchOp`
  union.

- [ ] **Step 1: Failing pytest:** both tools listed with their annotations;
  `hf_run_command` relays `command`, `brush_ids`, `params` and the
  `operation_id`, and leaves out what was not given; a batch op with
  `tool: "hf_run_command"` validates and an extra key is refused; every command
  id the description names is an `"id": "..."` in
  `addons/hammerforge/hf_command_registry.gd`; the README and guide tables list
  both tools (the existing table tests).
- [ ] **Step 2: Implement. Run** `python -m pytest hammerforge_mcp` and ruff.
- [ ] **Step 3: Smoke.** `tools/mcp_bridge_smoke.py` lists commands, runs
  `move_to_floor` on its box, and undoes it. Run it as CI does.
- [ ] **Checkpoint.**

### Task 13: Retire the golden table, docs, checks, vibe

- [ ] **Step 1: Retire.** Delete `tests/test_command_registry_golden.gd`, its
  `.uid`, and the fixture. The registry is the one copy now;
  `test_command_registry.gd` keeps the invariants (unique ids, keymap actions
  present, bound labels unique, bridge entries well formed, no bridge entry for
  `undo`, `redo`, `quick_play`, `quick_bake`, `validate_level`, `commit_cuts`).
- [ ] **Step 2: Docs.** Grep for the old facts and fix only lines now false:
  ROADMAP's Agent Bridge "Not yet on the bridge" line (left: floor paint,
  cordons, prefab placement, more than one level per scene); the guide's tool
  table, "What it can and cannot do" and Known limits; `hammerforge_mcp/README.md`;
  `DEVELOPMENT.md` module map (`hf_command_registry.gd`,
  `mcp/hf_mcp_commands.gd`) and its line on the palette sweep reading the
  `match`; `HammerForge_SPEC.md`'s bridge section. No test counts.
- [ ] **Step 3: Checks.** The two CI lint commands verbatim, LF normalised,
  `git diff --stat` reviewed, `python tools/check_script_warnings.py`,
  `python tools/check_uid_parity.py`, ruff, pytest.
- [ ] **Step 4: Vibe.** Real editor, real `hammerforge-mcp`: hollow a room box,
  clip it, carve a doorway, merge two blocks, build stairs and a dome, cycle a
  prefab variant; `hf_undo` each; do the same from the palette and compare the
  levels. A human Ctrl+Z between two agent commands, then `hf_undo` conflicts.
  Capture the scenario under `tools/vibe/mcp/` and file what it finds.
- [ ] **Checkpoint.**

## After the build

Issues to file, from the spec's out-of-scope list: floor paint in cell space on
the bridge; cordons on the bridge with a full-state capture; placing a prefab
from the library; structure Update and Detach; one toast label per command.
