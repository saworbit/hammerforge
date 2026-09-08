extends GutTest

## Collated edit commands: what merges into one undo entry, and what that entry
## redoes.
##
## An `EditorUndoRedoManager` cannot be constructed outside the editor, so this
## runs in two halves. Whether two presses merge is read from the history
## callback, which `HFUndoHelper` only fires on the first action of a run. What a
## merged entry redoes is driven through `register_action()` against a stand-in
## that implements the one rule that matters: Godot 4.7 documents MERGE_ENDS as
## keeping the first action's undo operations and the last action's do
## operations. The recorded calls are then replayed against a real LevelRoot, so
## a wrong do operation shows up as wrong geometry.

const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

const MERGE_DISABLE := 0
const MERGE_ENDS := 1


class FakeUndoRedo:
	extends RefCounted

	## One entry: the undo calls that take it back, the do calls that put it
	## forward again.
	var entries: Array = []
	var _open: Dictionary = {}
	var _merging := false

	func create_action(
		name: String, merge_mode: int = 0, _context = null, _backward: bool = false
	) -> void:
		_merging = merge_mode == MERGE_ENDS and not entries.is_empty()
		_open = {"name": name, "do": [], "undo": []}

	func add_do_method(
		target, method: StringName, a = null, b = null, c = null, d = null, e = null
	):
		_open["do"].append(_call_info(target, method, [a, b, c, d, e]))

	func add_undo_method(
		target, method: StringName, a = null, b = null, c = null, d = null, e = null
	):
		_open["undo"].append(_call_info(target, method, [a, b, c, d, e]))

	func commit_action(execute: bool = true) -> void:
		if execute:
			for call_info in _open["do"]:
				_invoke(call_info)
		if _merging:
			# MERGE_ENDS: the first action's undo, the last action's do.
			entries[-1]["do"] = _open["do"]
			entries[-1]["name"] = _open["name"]
		else:
			entries.append(_open)
		_open = {}

	func undo() -> void:
		for call_info in entries[-1]["undo"]:
			_invoke(call_info)

	func redo() -> void:
		for call_info in entries[-1]["do"]:
			_invoke(call_info)

	func _call_info(target, method: StringName, args: Array) -> Dictionary:
		var supplied: Array = []
		for arg in args:
			if arg == null:
				break
			supplied.append(arg)
		return {"target": target, "method": str(method), "args": supplied}

	func _invoke(call_info: Dictionary) -> void:
		call_info["target"].callv(call_info["method"], call_info["args"])


class FakePlugin:
	extends RefCounted

	var hf_selection: Array = []
	var history: Array = []

	## Null on purpose. HFUndoHelper still runs the command and still tracks
	## collation without a manager, and the history callback is the signal for
	## whether a press merged into the run before it.
	func _get_undo_redo():
		return null

	func _current_selection_nodes() -> Array:
		return hf_selection.duplicate()

	func _managed_entity_owner(_root: Node, _node: Node) -> Node:
		return null

	func _record_history(action_name: String) -> void:
		history.append(action_name)


var root: LevelRoot
var plugin: FakePlugin


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	plugin = FakePlugin.new()
	HFUndoHelper._reset_collation()


func after_each():
	root = null
	plugin = null


func _make_brush(position: Vector3, size: Vector3 = Vector3(32, 32, 32)) -> DraftBrush:
	var brush = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, position),
			}
		)
	)
	return brush as DraftBrush


func _brush_id(brush: DraftBrush) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))


## The one brush in the level, whichever node now carries it. Restoring a state
## rebuilds the brushes, so a reference does not survive an undo.
func _only_brush() -> DraftBrush:
	for node in root._iter_pick_nodes():
		if node is DraftBrush:
			return node
	return null


func _yaw_degrees() -> float:
	return rad_to_deg(_only_brush().global_transform.basis.get_euler().y)


# ===========================================================================
# A merged entry redoes the whole run, not the last step
# ===========================================================================


## Three presses inside the collation window, the way HFUndoHelper commits them:
## the first on its own, the rest merged onto it, all against the one pre-press
## state so undo jumps back to the start.
func _collate_three(undo_redo: FakeUndoRedo, method_name: String, args: Array) -> void:
	var before := root.capture_state()
	for press in 3:
		HFUndoHelper.register_action(
			undo_redo,
			root,
			"Step",
			MERGE_DISABLE if press == 0 else MERGE_ENDS,
			method_name,
			args,
			before,
			false,
			true
		)


func test_three_collated_rotations_redo_all_forty_five_degrees():
	var brush := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()

	_collate_three(
		undo_redo, "rotate_managed_nodes", [[_brush_id(brush)], [], 1, 15.0, Vector3.ZERO]
	)

	assert_eq(undo_redo.entries.size(), 1, "three presses in the window are one entry")
	assert_almost_eq(_yaw_degrees(), 45.0, 0.001, "the brush reached 45 degrees")

	undo_redo.undo()
	assert_almost_eq(_yaw_degrees(), 0.0, 0.001, "undo takes back all three presses")

	undo_redo.redo()
	assert_almost_eq(
		_yaw_degrees(), 45.0, 0.001, "redo has to put back what undo took, not one step of it"
	)


func test_three_collated_nudges_redo_the_whole_distance():
	var brush := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()

	_collate_three(undo_redo, "nudge_managed_nodes", [[_brush_id(brush)], [], Vector3(16, 0, 0)])

	assert_eq(undo_redo.entries.size(), 1)
	assert_almost_eq(_only_brush().global_position.x, 48.0, 0.001)

	undo_redo.undo()
	assert_almost_eq(_only_brush().global_position.x, 0.0, 0.001)

	undo_redo.redo()
	assert_almost_eq(_only_brush().global_position.x, 48.0, 0.001, "48 units, not the last 16")


func test_a_single_step_still_undoes_and_redoes():
	var brush := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()
	var before := root.capture_state()

	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Step",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[[_brush_id(brush)], [], Vector3(16, 0, 0)],
		before,
		false,
		true
	)

	assert_almost_eq(_only_brush().global_position.x, 16.0, 0.001, "one press moves one step")
	undo_redo.undo()
	assert_almost_eq(_only_brush().global_position.x, 0.0, 0.001)
	undo_redo.redo()
	assert_almost_eq(_only_brush().global_position.x, 16.0, 0.001)


func test_the_work_is_done_once_per_step():
	# The absolute path runs the method itself and then commits without executing,
	# so a step that also executed on commit would move the brush twice.
	var brush := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()

	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Step",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[[_brush_id(brush)], [], Vector3(16, 0, 0)],
		root.capture_state(),
		false,
		true
	)

	assert_almost_eq(_only_brush().global_position.x, 16.0, 0.001)


func test_a_stepping_action_registers_a_snapshot_rather_than_another_step():
	var brush := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()

	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Step",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[[_brush_id(brush)], [], Vector3(16, 0, 0)],
		root.capture_state(),
		false,
		true
	)

	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(str(entry["do"][0]["method"]), "restore_state", "the do operation names the result")
	assert_eq(str(entry["undo"][0]["method"]), "restore_state")


func test_a_setting_action_still_registers_the_method_itself():
	var brush := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()

	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Set",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[[_brush_id(brush)], [], Vector3(16, 0, 0)],
		root.capture_state()
	)

	assert_eq(str(undo_redo.entries[0]["do"][0]["method"]), "nudge_managed_nodes")


# ===========================================================================
# What merges, and what does not
# ===========================================================================


func test_repeating_the_same_press_merges():
	var brush := _make_brush(Vector3.ZERO)
	plugin.hf_selection = [brush]
	root.grid_snap = 16.0

	for _press in 3:
		HFPluginEditActions.nudge_selected(plugin, root, Vector3.RIGHT)

	assert_eq(plugin.history.size(), 1, "a run of the same press is one history entry")
	assert_almost_eq(_only_brush().global_position.x, 48.0, 0.001)


func test_reversing_direction_starts_a_new_entry():
	var brush := _make_brush(Vector3.ZERO)
	plugin.hf_selection = [brush]
	root.grid_snap = 16.0

	HFPluginEditActions.nudge_selected(plugin, root, Vector3.RIGHT)
	HFPluginEditActions.nudge_selected(plugin, root, Vector3.LEFT)

	assert_eq(
		plugin.history.size(),
		2,
		"a nudge back the other way is a different intention, not more of the same"
	)


func test_reversing_rotation_starts_a_new_entry():
	var brush := _make_brush(Vector3.ZERO)
	plugin.hf_selection = [brush]
	root.rotate_snap_degrees = 15.0

	HFPluginEditActions.rotate_selected(plugin, root, 1)
	HFPluginEditActions.rotate_selected(plugin, root, -1)

	assert_eq(plugin.history.size(), 2)


func test_changing_the_selection_starts_a_new_entry():
	var first := _make_brush(Vector3.ZERO)
	var second := _make_brush(Vector3(200, 0, 0))
	root.grid_snap = 16.0

	plugin.hf_selection = [first]
	HFPluginEditActions.nudge_selected(plugin, root, Vector3.RIGHT)
	plugin.hf_selection = [second]
	HFPluginEditActions.nudge_selected(plugin, root, Vector3.RIGHT)

	assert_eq(plugin.history.size(), 2, "two brushes moved a moment apart are two edits, not one")


func test_changing_the_axis_starts_a_new_entry():
	var brush := _make_brush(Vector3.ZERO)
	plugin.hf_selection = [brush]
	root.rotate_snap_degrees = 15.0

	# axis_lock: 0 is none, 1 to 3 lock X, Y and Z.
	root.axis_lock = 2
	HFPluginEditActions.rotate_selected(plugin, root, 1)
	root.axis_lock = 1
	HFPluginEditActions.rotate_selected(plugin, root, 1)

	assert_eq(plugin.history.size(), 2, "a different axis is a different edit")


func test_painting_two_brushes_quickly_keeps_them_apart():
	var first := _make_brush(Vector3.ZERO)
	var second := _make_brush(Vector3(200, 0, 0))
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()

	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, first, red)
	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, second, blue)

	assert_eq(plugin.history.size(), 2, "one entry for each brush, so a redo cannot lose the first")
	assert_same(first.material_override, red)
	assert_same(second.material_override, blue)


func test_repainting_one_brush_quickly_still_merges():
	var brush := _make_brush(Vector3.ZERO)
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()

	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, brush, red)
	HFPluginMaterialCommands.paint_brush_with_undo(plugin, root, brush, blue)

	assert_eq(
		plugin.history.size(),
		1,
		"the same brush repainted names an absolute material, so merging is safe"
	)


func test_the_tag_changes_with_the_target_and_the_inputs():
	var base := HFPluginEditActions.collation_tag("nudge", ["a"], [], [1])
	assert_ne(base, HFPluginEditActions.collation_tag("nudge", ["b"], [], [1]), "target")
	assert_ne(base, HFPluginEditActions.collation_tag("nudge", ["a"], [], [-1]), "direction")
	assert_ne(base, HFPluginEditActions.collation_tag("rotate", ["a"], [], [1]), "command")
	assert_ne(base, HFPluginEditActions.collation_tag("nudge", ["a"], ["e"], [1]), "entities")
	assert_eq(base, HFPluginEditActions.collation_tag("nudge", ["a"], [], [1]), "same press")
