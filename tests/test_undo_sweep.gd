extends "res://tests/support/plugin_sweep_case.gd"
## Every action the palette sweep runs, undone and redone in every state it runs
## in.
##
## The plugin here commits through the undo manager stand-in, so an action
## registers its steps the way it does in the editor, over a real `UndoRedo`, and
## the plugin and the dock hear `version_changed` as they do there. Each action
## runs from its surface as in `test_palette_action_sweep.gd`, with OK on any
## dialog. Then Ctrl+Z once for every step it left, then Ctrl+Shift+Z as often,
## each followed by the frame the editor gives deferred work.
##
## Neither may raise a script error. Undo must put the level back as it was
## before the action, and redo must bring back what the action made. An action
## that changes the level and leaves no step cannot be undone at all, so that
## fails too.
##
## "The level" is `capture_state()`, what an undo step itself records, compared
## key by key so a failure names what moved. Two things are left out. The face
## selection is a view of the level, not part of it. The id counter is the next
## number to hand out, not anything in the level: Duplicate mints its ids before
## its step records the level, so its undo leaves the counter ahead, which only
## skips numbers. A counter wound back below where it was could hand out an id
## twice, so that is still a failure.

const PaletteSweep = preload("res://tests/test_palette_action_sweep.gd")

const REDO_REMINTS := "#1275: redo runs the command again and mints new brush ids"
const LINK_NOT_UNDOABLE := "#1276: Save as Live-Linked Prefab links the selection with no undo step"

## Failures this sweep found that are filed and not fixed yet, as
## "action|state": issue. Their errors are let through and the case is marked
## pending; once one stops failing, the sweep says to take it off.
const KNOWN := {
	"hollow|box_selected": REDO_REMINTS,
	"hollow|two_boxes": REDO_REMINTS,
	"hollow|pending_cut": REDO_REMINTS,
	"hollow|brush_entity": REDO_REMINTS,
	"hollow|displaced_brush": REDO_REMINTS,
	"hollow|freed_brush": REDO_REMINTS,
	"clip|box_selected": REDO_REMINTS,
	"clip|two_boxes": REDO_REMINTS,
	"clip|pending_cut": REDO_REMINTS,
	"clip|brush_entity": REDO_REMINTS,
	"clip|displaced_brush": REDO_REMINTS,
	"clip|freed_brush": REDO_REMINTS,
	"merge|two_boxes": REDO_REMINTS,
	"carve|pending_cut": REDO_REMINTS,
	"quick_save_linked_prefab|box_selected": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|two_boxes": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|entity_only": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|pending_cut": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|generator_piece": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|brush_entity": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|displaced_brush": LINK_NOT_UNDOABLE,
	"quick_save_linked_prefab|freed_brush": LINK_NOT_UNDOABLE,
}


func test_the_sweep_reads_its_actions():
	var actions: Array = PaletteSweep.dispatch_actions()
	assert_gt(actions.size(), 80, "plugin_commands.gd arms were read")
	for key in KNOWN:
		var parts: PackedStringArray = str(key).split("|")
		assert_has(actions, parts[0], "KNOWN names a real action: %s" % key)
		assert_has(STATES, parts[1], "KNOWN names a real state: %s" % key)


func test_undo_and_redo_every_action(action = use_parameters(PaletteSweep.dispatch_actions())):
	await _bring_up(true)
	if plugin == null:
		fail_test(PluginStandIn.error())
		return
	for state in STATES:
		await _check_undo(action, state)
	await _take_down()
	assert_no_new_orphans("%s left nodes behind" % action)


func test_undo_and_redo_from_the_viewport_menu_step_the_history():
	# The menu's Undo called an undo() the editor's manager does not have.
	await _bring_up(true)
	var root = await _enter_state("box_selected")
	plugin.stand_in_undo.clear()
	var brushes: int = root.draft_brushes_node.get_child_count()
	plugin._on_hotkey_palette_action("duplicate")
	assert_eq(root.draft_brushes_node.get_child_count(), brushes + 1, "duplicated")
	plugin._dispatch_viewport_action("undo")
	await get_tree().process_frame
	assert_eq(root.draft_brushes_node.get_child_count(), brushes, "undone from the menu")
	plugin._dispatch_viewport_action("redo")
	await get_tree().process_frame
	assert_eq(root.draft_brushes_node.get_child_count(), brushes + 1, "redone from the menu")
	plugin.stand_in_undo.clear()
	await _leave_level(root)


func test_grouping_and_ungrouping_from_the_keyboard_are_undone():
	# The dock's Group and Ungroup put a step on the stack; the keys and the
	# palette changed the level with none.
	await _bring_up(true)
	var root = await _enter_state("two_boxes")
	var undo = plugin.stand_in_undo
	undo.clear()
	plugin._on_hotkey_palette_action("group")
	assert_eq(root.capture_state()["group_order"].size(), 1, "grouped")
	plugin._on_hotkey_palette_action("ungroup")
	assert_eq(root.capture_state()["group_order"].size(), 0, "ungrouped")
	assert_eq(undo.step_count(), 2, "each is a step of its own")
	undo.press_undo()
	assert_eq(root.capture_state()["group_order"].size(), 1, "the ungroup is undone")
	undo.press_undo()
	assert_eq(root.capture_state()["group_order"].size(), 0, "and the group")
	undo.clear()
	await _leave_level(root)


func _check_undo(action: String, state: String) -> void:
	var label := "%s in %s" % [action, state]
	var undo = plugin.stand_in_undo
	var root = await _enter_state(state)
	# A fresh scene's history: nothing from the level before, and nothing from
	# building this one.
	undo.clear()
	var before := _level(root)
	var counter_before := _id_counter(root)
	var errors_before := get_errors().size()
	if _keymap.has_action(action):
		plugin._on_hotkey_palette_action(action)
	else:
		plugin._dispatch_viewport_action(action, [])
	await get_tree().process_frame
	await _accept_dialogs()
	var after := _level(root)
	var steps: int = undo.step_count()
	var problems: Array = []
	if steps == 0:
		problems.append_array(_differences("left no step, and changed", before, after))
	else:
		for _i in steps:
			undo.press_undo()
		await get_tree().process_frame
		problems.append_array(_differences("undo did not restore", before, _level(root)))
		if _id_counter(root) < counter_before:
			problems.append("undo wound the id counter back past %d" % counter_before)
		for _i in steps:
			undo.press_redo()
		await get_tree().process_frame
		problems.append_array(_differences("redo did not restore", after, _level(root)))
	var errors: Array = get_errors().slice(errors_before)
	problems.append_array(_describe(errors))
	var known := "%s|%s" % [action, state]
	if KNOWN.has(known):
		for e in errors:
			e.handled = true
		if problems.is_empty():
			fail_test("%s no longer fails; take it off KNOWN (%s)" % [label, KNOWN[known]])
		else:
			pending("%s: %s" % [label, KNOWN[known]])
	else:
		assert_eq(problems, [], "%s undid and redid cleanly" % label)
	_escape_to_idle(root)
	# No step may hold the level once it is gone.
	undo.clear()
	await _leave_level(root)


## The level as undo has to put it back, one entry per key of `capture_state()`.
func _level(root: Node) -> Dictionary:
	if root == null or not is_instance_valid(root):
		return {}
	var out := {}
	var state: Dictionary = root.capture_state(false)
	state.erase("id_counter")
	for key in state:
		out[key] = var_to_str(state[key])
	return out


func _id_counter(root: Node) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	return root._brush_id_counter


## "<what> <keys>" naming every key that differs, or nothing.
func _differences(what: String, expected: Dictionary, actual: Dictionary) -> Array:
	var keys: Array = []
	for key in expected:
		if not actual.has(key) or actual[key] != expected[key]:
			keys.append(key)
	for key in actual:
		if not expected.has(key):
			keys.append(key)
	if keys.is_empty():
		return []
	keys.sort()
	return ["%s %s" % [what, ", ".join(keys)]]
