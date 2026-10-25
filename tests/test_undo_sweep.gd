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
## key by key so a failure names what moved. Three things are left out. The face
## selection is a view of the level, not part of it. The id counter is the next
## number to hand out, not anything in the level: Duplicate mints its ids before
## its step records the level, so its undo leaves the counter ahead, which only
## skips numbers. A counter wound back below where it was could hand out an id
## twice, so that is still a failure. The baked container is the bake's product:
## Bake and Quick Play record history, not an undo step, and an undo past a bake
## restores a level that had no bake yet, which takes the output down with it,
## as the editor does. The cuts a bake applies are a step of their own (#1353).

const PaletteSweep = preload("res://tests/test_palette_action_sweep.gd")

## Actions that set a tool setting the level keeps, not its content, so rightly
## leave no step: the grid size is saved with the level and with the mapper's
## own preferences, and is no more undoable than the editor's snap settings. The
## paint grid follows it. They must still raise nothing.
const SETTING_ACTIONS := ["grid_decrease", "grid_increase"]

## Actions that change what is shown: which visgroups, which of them locked, and
## what Hide Selection hides. A view change is kept apart from the undo history
## on purpose, with Previous Visibility to step back through it (#1697), so these
## rightly leave no step either.
const VIEW_ACTIONS := [
	"hide_selection",
	"show_hidden",
	"isolate_selection",
	"isolate_visgroups",
	"end_isolate",
	"previous_visibility",
]

## Failures this sweep found that are filed and not fixed yet, as
## "action|state": issue. Their errors are let through and the case is marked
## pending; once one stops failing, the sweep says to take it off.
const KNOWN := {}
const KnownFailures = preload("res://tests/support/known_failures.gd")


func test_the_sweep_reads_its_actions():
	var actions: Array = PaletteSweep.dispatch_actions()
	assert_gt(actions.size(), 80, "the command registry was read")
	for key in KNOWN:
		var parts: PackedStringArray = str(key).split("|")
		assert_has(actions, parts[0], "KNOWN names a real action: %s" % key)
		assert_has(STATES, parts[1], "KNOWN names a real state: %s" % key)
	KnownFailures.check_shape(self, KNOWN)


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
	assert_eq(await _accept_dialogs(), 1, "Group asked for a name (#1723)")
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


func test_a_step_after_hollow_still_reaches_its_wall_after_undo_and_redo():
	# Redo ran Hollow again, and the walls it made the second time had new ids,
	# so the nudge after it, redone, found no wall to move (#1275).
	await _bring_up(true)
	var root = await _enter_state("box_selected")
	var undo = plugin.stand_in_undo
	undo.clear()
	plugin._on_hotkey_palette_action("hollow")
	await get_tree().process_frame
	assert_eq(await _accept_dialogs(), 1, "Hollow asked first")
	var hollows: Array = root.capture_state()["hollows"]
	assert_eq(hollows.size(), 1, "the box was hollowed")
	var wall_id := str(hollows[0]["wall_ids"][0]) if hollows.size() == 1 else ""
	_select([root.find_brush_by_id(wall_id)])
	plugin._nudge_selected(root, Vector3.RIGHT)
	var moved_to: Vector3 = root.find_brush_by_id(wall_id).global_position
	var nudged := _level(root)
	assert_eq(undo.step_count(), 2, "Hollow and the nudge are a step each")
	undo.press_undo()
	undo.press_undo()
	await get_tree().process_frame
	undo.press_redo()
	undo.press_redo()
	await get_tree().process_frame
	var wall = root.find_brush_by_id(wall_id)
	assert_not_null(wall, "the wall came back under its id")
	if wall:
		assert_eq(wall.global_position, moved_to, "and the redone nudge moved it")
	# The nudge's own redo puts back the wall it names whatever Hollow did, so only
	# the whole level shows a Hollow redone under new ids.
	assert_eq(_differences("redo", nudged, _level(root)), [], "the level is as it was")
	undo.clear()
	await _leave_level(root)


func test_undoing_a_linked_save_unlinks_the_copy_and_keeps_the_file():
	# The link was made with no step, so undo took back the step before it and the
	# box stayed a linked copy (#1276).
	await _bring_up(true)
	var root = await _enter_state("box_selected")
	var undo = plugin.stand_in_undo
	undo.clear()
	plugin._dispatch_viewport_action("quick_save_linked_prefab")
	var source := str(root.find_brush_by_id("a").get_meta("hf_prefab_source", ""))
	assert_ne(source, "", "the box is a linked copy")
	assert_eq(undo.step_count(), 1, "the link is a step")
	undo.press_undo()
	await get_tree().process_frame
	assert_eq(root.prefab_system.get_all_instances().size(), 0, "undo took the link back")
	var box = root.find_brush_by_id("a")
	assert_eq(str(box.get_meta("hf_prefab_instance", "")), "", "and the box is no copy")
	assert_true(FileAccess.file_exists(source), "the prefab stays written")
	undo.press_redo()
	await get_tree().process_frame
	assert_eq(root.prefab_system.get_all_instances().size(), 1, "redo linked it again")
	box = root.find_brush_by_id("a")
	assert_ne(str(box.get_meta("hf_prefab_instance", "")), "", "and tagged the box")
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
	await _settle(root)
	var after := _level(root)
	var steps: int = undo.step_count()
	var problems: Array = []
	if steps == 0:
		if not SETTING_ACTIONS.has(action) and not VIEW_ACTIONS.has(action):
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
	KnownFailures.settle(self, KNOWN, known, "%s undid and redid cleanly" % label, problems)
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
	state.erase("baked_present")
	state.erase("bake_preview_mode")
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
