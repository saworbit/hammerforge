extends "res://tests/support/plugin_sweep_case.gd"
## Every action the shared dispatcher knows, run against a real plugin in awkward
## states.
##
## The actions are the arms of `HFPluginCommands.execute`, read from its source,
## so a new one is swept without anyone listing it. Each runs from the surface a
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
## Copy, paste and Quick Save Prefab write files the developer's own editor uses.
## The clipboard is set aside and put back, and every prefab an action saves is
## taken away again.
##
## What this does not cover: undo and redo, which `test_undo_sweep.gd` sweeps in
## the same states, keyboard shortcuts, which `test_keymap_sweep.gd` presses, and
## anything the editor draws.

const COMMANDS_PATH := "res://addons/hammerforge/plugin_commands.gd"

## Actions that work on the level as a whole, so may change it with nothing
## selected.
const WHOLE_LEVEL_ACTIONS := ["paste"]

## Failures this sweep found that are filed and not fixed yet, as
## "action|state": issue. Their errors are let through and the case is marked
## pending; once one stops failing, the sweep says to take it off.
const KNOWN := {}


## A grep on purpose: the dispatcher's own arms are the list of actions, so a
## new one is swept without anyone adding it here, and nothing the plugin does
## can enumerate the names a match knows.
static func dispatch_actions() -> Array:
	var source := FileAccess.get_file_as_string(COMMANDS_PATH)
	var body := source.substr(source.find("static func execute"))
	var arm := RegEx.create_from_string('^\\t\\t("[a-z_0-9]+"(?:, "[a-z_0-9]+")*):\\s*$')
	var quoted := RegEx.create_from_string('"([a-z_0-9]+)"')
	var out: Array = []
	for line in body.split("\n"):
		var m := arm.search(line)
		if m == null:
			continue
		for n in quoted.search_all(m.get_string(1)):
			out.append(n.get_string(1))
	return out


func test_the_sweep_reads_every_dispatched_action():
	assert_false(_clipboard_seed.is_empty(), "a real copy made the clipboard paste puts down")
	var actions := dispatch_actions()
	assert_gt(actions.size(), 80, "plugin_commands.gd arms were read")
	for action in _keymap.get_actions():
		assert_has(actions, action, "every palette action reaches the dispatcher")
	for key in KNOWN:
		var parts: PackedStringArray = str(key).split("|")
		assert_has(actions, parts[0], "KNOWN names a real action: %s" % key)
		assert_has(STATES, parts[1], "KNOWN names a real state: %s" % key)


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
	var errors_before := get_errors().size()
	if _keymap.has_action(action):
		plugin._on_hotkey_palette_action(action)
	else:
		plugin._dispatch_viewport_action(action, [])
	await get_tree().process_frame
	if await _accept_dialogs() > 0:
		label += ", then OK"
	var errors: Array = get_errors().slice(errors_before)
	var known := "%s|%s" % [action, state]
	if KNOWN.has(known):
		for e in errors:
			e.handled = true
		if errors.is_empty():
			fail_test("%s no longer fails; take it off KNOWN (%s)" % [label, KNOWN[known]])
		else:
			pending("%s: %s" % [label, KNOWN[known]])
	else:
		assert_eq(_describe(errors), [], "%s raised no error" % label)
	if state == "no_level":
		assert_eq(_level_roots(), 0, "%s made no level" % label)
	elif state == "nothing_selected" and not WHOLE_LEVEL_ACTIONS.has(action):
		assert_eq(_snapshot(root), before, "%s left the level as it was" % label)
	_escape_to_idle(root)
	await _leave_level(root)
