extends "res://tests/support/plugin_sweep_case.gd"
## Every action the shared dispatcher knows, run against a real plugin in awkward
## states.
##
## The actions are every command `HFPluginCommands.execute` runs, as
## `HFCommandRegistry` lists them, so a new one is swept without anyone listing it
## here. A listed command with no arm reaches the dispatcher's default arm, which
## raises an error, so it fails in every state. Each runs from the surface a
## user reaches it by: the command palette for an action with a key, the toolbar
## and menus for the rest. The plugin is the real `plugin.gd`, set up by its own
## `_enter_tree` (`tests/support/plugin_stand_in.gd`), a fresh one per action.
##
## Each action then runs once in every state below, on a level built for it, with
## the Escape ladder in between, so a toggle is exercised both on and off. Any
## dialog it opens gets OK, so what a confirmation commits runs as well. It must
## not raise a script error or a push_error in any of them; with no level it must
## not make one; and with nothing selected it must leave the level as it was
## unless it is one of the few that work on the level as a whole.
##
## Copy, paste and Quick Save Prefab write the run's own clipboard and prefab
## folder, and Quick Play's files under `res://.hammerforge/` are set aside and
## put back; `plugin_sweep_case.gd` says how.
##
## What this does not cover: undo and redo, which `test_undo_sweep.gd` sweeps in
## the same states, keyboard shortcuts, which `test_keymap_sweep.gd` presses, and
## anything the editor draws.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")

## Actions that work on the level as a whole, so may change it with nothing
## selected. A bake is of the whole level, and Quick Play bakes after making a
## default spawn when the level has none; Create Structure builds at the origin;
## the grid size is the level's own setting, and the paint grid follows it.
const WHOLE_LEVEL_ACTIONS := [
	"paste",
	"quick_bake",
	"bake_preview_toggle",
	"quick_play",
	"create_arch",
	"grid_decrease",
	"grid_increase",
]

## Failures this sweep found that are filed and not fixed yet, as
## "action|state": issue. Their errors are let through and the case is marked
## pending; once one stops failing, the sweep says to take it off.
const KNOWN := {}
const KnownFailures = preload("res://tests/support/known_failures.gd")


## A grep on purpose: the dispatcher's own arms are the list of actions, so a
## new one is swept without anyone adding it here, and nothing the plugin does
## can enumerate the names a match knows.
static func dispatch_actions() -> Array:
	return Array(HFCommandRegistry.dispatched_ids())


func test_the_sweep_reads_every_dispatched_action():
	assert_false(_clipboard_seed.is_empty(), "a real copy made the clipboard paste puts down")
	var actions := dispatch_actions()
	assert_gt(actions.size(), 80, "the command table was read")
	for action in _keymap.get_actions():
		assert_has(actions, action, "every palette action reaches the dispatcher")
	for key in KNOWN:
		var parts: PackedStringArray = str(key).split("|")
		assert_has(actions, parts[0], "KNOWN names a real action: %s" % key)
		assert_has(STATES, parts[1], "KNOWN names a real state: %s" % key)
	KnownFailures.check_shape(self, KNOWN)


func test_every_action_in_every_state(action = use_parameters(dispatch_actions())):
	await _bring_up()
	if plugin == null:
		fail_test(PluginStandIn.error())
		return
	for state in STATES:
		await _check(action, state)
	await _take_down()
	assert_no_new_orphans("%s left nodes behind" % action)


func test_paste_from_the_palette_needs_nothing_selected():
	# The keyboard hands Ctrl+V to Godot when nothing of HammerForge's is
	# selected; the palette has nothing to hand it to, and refused instead.
	await _bring_up()
	for state in ["nothing_selected", "level_selected"]:
		var root = await _enter_state("nothing_selected")
		if state == "level_selected":
			_select([root])
		var brushes: int = root.draft_brushes_node.get_child_count()
		plugin._on_hotkey_palette_action("paste")
		await get_tree().process_frame
		assert_eq(root.draft_brushes_node.get_child_count(), brushes + 1, "pasted with %s" % state)
		await _leave_level(root)


func _check(action: String, state: String) -> void:
	var label := "%s in %s" % [action, state]
	var root = await _enter_state(state)
	var before := _snapshot(root)
	var locked_before := _locked_records(root) if state == "locked" else ""
	var errors_before := get_errors().size()
	if _keymap.has_action(action):
		plugin._on_hotkey_palette_action(action)
	else:
		plugin._dispatch_viewport_action(action, [])
	await get_tree().process_frame
	if await _accept_dialogs() > 0:
		label += ", then OK"
	await _settle(root)
	var errors: Array = get_errors().slice(errors_before)
	var known := "%s|%s" % [action, state]
	if KNOWN.has(known):
		for e in errors:
			e.handled = true
	KnownFailures.settle(self, KNOWN, known, "%s raised no error" % label, _describe(errors))
	if state == "no_level":
		assert_eq(_level_roots(), 0, "%s made no level" % label)
	elif state == "nothing_selected" and not WHOLE_LEVEL_ACTIONS.has(action):
		assert_eq(_snapshot(root), before, "%s left the level as it was" % label)
	elif state == "locked":
		assert_eq(_locked_records(root), locked_before, "%s left the locked brushes alone" % label)
	_escape_to_idle(root)
	await _leave_level(root)
