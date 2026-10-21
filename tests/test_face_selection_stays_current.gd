extends GutTest
## `LevelRoot.face_selection` is what Face Select has picked, and what shows it
## (the dock's Surface Paint panel and selection count, the face mark) reads it
## again when `face_selection_changed` fires. Two ways it drifted from the screen
## (#1515): an undo or redo that put back another selection said nothing, so the
## dock kept showing the one it replaced; and a brush Godot's own Delete took out
## of the level left its faces picked, which the HUD went on counting.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func _face_with_normal(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


func _top_face(brush: Node) -> int:
	return _face_with_normal(brush, Vector3.UP)


func _pick(level: Node, brush: Node, face_idx: int) -> void:
	level.toggle_face_selection(brush, face_idx, true, false)


## One entry per `face_selection_changed` from now on.
func _watch(level: Node) -> Array:
	var emits: Array = []
	level.face_selection_changed.connect(func(): emits.append(true))
	return emits


func _faces_picked(level: Node) -> int:
	var count := 0
	for key in level.face_selection:
		count += (level.face_selection[key] as Array).size()
	return count


func _dock_text() -> String:
	return rig.plugin.dock.selection_label.text


func _hud_face_count(level: Node) -> int:
	return int(HFPluginCommands.build_command_state(rig.plugin, level, 0).get("face_count", -1))


## Godot's own Delete in the Scene dock, as its step does it: the node out of its
## parent, and back at its index on undo, held alive by the step meanwhile.
func _godot_delete(node: Node) -> void:
	var parent := node.get_parent()
	var ur = rig.undo()
	ur.create_action("Remove Node(s)")
	ur.add_do_method(parent, "remove_child", node)
	ur.add_undo_method(parent, "add_child", node, true)
	ur.add_undo_method(parent, "move_child", node, node.get_index())
	ur.add_undo_method(node, "set_owner", node.owner)
	ur.add_undo_reference(node)
	ur.commit_action()


# -- Undo and redo ------------------------------------------------------------


func test_an_undo_that_puts_back_another_selection_says_so() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	_pick(level, a, _top_face(a))
	_pick(level, b, _top_face(b))
	HFUndoHelper.commit(
		rig.plugin.undo_redo_manager,
		level,
		"Nudge",
		"nudge_brushes_by_id",
		[["b"], Vector3(0, 0, 2)]
	)
	_pick(level, a, _face_with_normal(a, Vector3.RIGHT))
	assert_eq(_dock_text(), "Sel: 3 faces", "three faces picked")
	var emits := _watch(level)

	rig.undo().press_undo()
	assert_eq(_faces_picked(level), 2, "the undo puts back the two picked before the step")
	assert_eq(emits.size(), 1, "and says so")
	assert_eq(_dock_text(), "Sel: 2 faces", "so the dock counts two")
	await rig.frame()
	assert_eq(emits.size(), 1, "once")
	await rig.leave_level(level)


func test_a_redo_that_puts_back_another_selection_says_so() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	var top := _top_face(a)
	var side := _face_with_normal(a, Vector3.RIGHT)
	_pick(level, a, top)
	var before: Dictionary = level.capture_state()
	level.nudge_brushes_by_id(["b"], Vector3(0, 0, 2))
	_pick(level, a, side)
	HFUndoHelper.commit_completed(rig.plugin.undo_redo_manager, level, "Nudge", before)
	rig.undo().press_undo()
	assert_eq(level.face_selection, {"a": [top]}, "the undo puts back the one face")
	_pick(level, b, _top_face(b))
	var emits := _watch(level)

	rig.undo().press_redo()
	assert_eq(level.face_selection, {"a": [top, side]}, "the redo puts back the two on a")
	assert_eq(emits.size(), 1, "and says so")
	assert_eq(_dock_text(), "Sel: 2 faces", "so the dock counts them")
	await rig.leave_level(level)


## Every undo of a nudge puts back the selection it found, and every one of them
## announcing a change would redraw the dock and the mark for nothing.
func test_a_restore_that_leaves_the_selection_alone_says_nothing() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var top := _top_face(a)
	_pick(level, a, top)
	HFUndoHelper.commit(
		rig.plugin.undo_redo_manager,
		level,
		"Nudge",
		"nudge_brushes_by_id",
		[["a"], Vector3(0, 0, 6)]
	)
	var emits := _watch(level)

	rig.undo().press_undo()
	rig.undo().press_redo()
	level.restore_state(level.capture_state())
	await rig.frame()
	assert_eq(level.face_selection, {"a": [top]}, "the face is still picked")
	assert_eq(emits.size(), 0, "and nothing said it changed")
	await rig.leave_level(level)


## A `.hflevel` holds no selection, so loading one clears it.
func test_a_state_with_no_selection_clears_the_picks_and_says_so() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_pick(level, a, _top_face(a))
	var emits := _watch(level)

	level.restore_state(level.capture_state(false))
	assert_true(level.face_selection.is_empty(), "nothing is picked after the load")
	assert_eq(emits.size(), 1, "and the dock is told")
	assert_eq(_dock_text(), "", "so it stops counting the face")
	await rig.leave_level(level)


# -- A brush that goes ----------------------------------------------------------


func test_a_brush_godot_deletes_takes_its_picked_faces_with_it() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	_pick(level, a, _top_face(a))
	_pick(level, b, _top_face(b))
	await rig.frame()
	var emits := _watch(level)

	_godot_delete(a)
	await rig.frame()
	assert_false(level.face_selection.has("a"), "the deleted brush's face is no longer picked")
	assert_eq(level.face_selection.get("b", []), [_top_face(b)], "the other brush's still is")
	assert_eq(emits.size(), 1, "and the change is announced once")
	assert_eq(_hud_face_count(level), 1, "the HUD counts the one face left")
	assert_eq(_dock_text(), "Sel: 1 face", "and so does the dock")
	await rig.leave_level(level)


## The pick went with the delete. Godot's undo puts the node back and knows
## nothing of faces, so the brush comes back unpicked; HammerForge's own Delete
## records the selection in its step, and its undo puts the picks back (below).
func test_undoing_godot_delete_brings_the_brush_back_unpicked() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	_pick(level, a, _top_face(a))
	_pick(level, b, _top_face(b))
	_godot_delete(a)
	await rig.frame()
	var emits := _watch(level)

	rig.undo().press_undo()
	await rig.frame()
	assert_eq(a.get_parent(), level.draft_brushes_node, "the undo puts the brush back")
	assert_false(level.face_selection.has("a"), "with no face picked")
	assert_eq(level.face_selection.get("b", []), [_top_face(b)], "the other pick is untouched")
	assert_eq(emits.size(), 0, "the selection did not change, so nothing is announced")
	await rig.leave_level(level)


func test_undoing_hammerforge_delete_brings_the_picked_faces_back() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	var top := _top_face(a)
	_pick(level, a, top)
	_pick(level, b, _top_face(b))
	HFUndoHelper.commit(
		rig.plugin.undo_redo_manager, level, "Delete Brushes", "delete_managed_nodes", [["a"], []]
	)
	await rig.frame()
	assert_false(level.face_selection.has("a"), "the delete drops the face")
	var emits := _watch(level)

	rig.undo().press_undo()
	await rig.frame()
	assert_eq(level.face_selection.get("a", []), [top], "the undo puts it back")
	assert_eq(emits.size(), 1, "and says so")
	assert_eq(_dock_text(), "Sel: 2 faces", "so the dock counts both")
	await rig.leave_level(level)


## A brush can pass out of the tree and back without leaving the level: moved to
## another of the level's containers, carried across by Apply Cuts, dragged out
## of its container and put back by the change tracker, or with its whole scene
## while another scene tab is in front. None of that unpicks a face.
func test_a_brush_that_leaves_the_tree_for_a_moment_keeps_its_picked_faces() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var cut = level.create_brush_from_info(
		{"size": Vector3(2, 2, 2), "center": Vector3(10, 0, 0), "brush_id": "cut", "pending": true}
	)
	_pick(level, a, _top_face(a))
	_pick(level, cut, _top_face(cut))
	await rig.frame()
	var picked: Dictionary = level.face_selection.duplicate(true)
	var emits := _watch(level)

	var ur = rig.undo()
	ur.create_action("Reparent Node")
	ur.add_do_method(level.draft_brushes_node, "remove_child", a)
	ur.add_do_method(level.pending_node, "add_child", a, true)
	ur.add_undo_method(level.pending_node, "remove_child", a)
	ur.add_undo_method(level.draft_brushes_node, "add_child", a, true)
	ur.commit_action()
	await rig.frame()
	assert_eq(a.get_parent(), level.pending_node, "Godot moved the brush to another container")
	assert_eq(level.face_selection, picked, "and its face is still picked")

	HFUndoHelper.commit(rig.plugin.undo_redo_manager, level, "Apply Cuts", "apply_pending_cuts", [])
	await rig.frame()
	assert_eq(cut.get_parent(), level.draft_brushes_node, "Apply Cuts carried the cutter over")
	assert_eq(level.face_selection, picked, "with its face still picked")

	ur.create_action("Reparent Node")
	ur.add_do_method(level.draft_brushes_node, "remove_child", a)
	ur.add_do_method(level, "add_child", a, true)
	ur.add_undo_method(level, "remove_child", a)
	ur.add_undo_method(level.draft_brushes_node, "add_child", a, true)
	ur.commit_action()
	await rig.frame()
	assert_eq(
		a.get_parent(), level.draft_brushes_node, "a brush dragged out of its container is put back"
	)
	assert_eq(level.face_selection, picked, "with its face still picked")

	var scene := rig.scene_root
	var host := scene.get_parent()
	var index := scene.get_index()
	host.remove_child(scene)
	await rig.frame()
	host.add_child(scene)
	host.move_child(scene, index)
	await rig.frame()
	assert_eq(level.face_selection, picked, "a scene tab switched away and back keeps them too")
	assert_eq(emits.size(), 0, "and none of it is announced as a change")
	await rig.leave_level(level)


## Closing a scene frees the level and every brush in it. Its picks go with it,
## and nothing is told about it on the way out, even with a reconcile queued by a
## Delete just before the close.
func test_closing_a_level_with_picked_faces_announces_nothing() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	_pick(level, a, _top_face(a))
	_pick(level, b, _top_face(b))
	await rig.frame()
	var emits := _watch(level)

	_godot_delete(a)
	level.get_parent().remove_child(level)
	level.free()
	await rig.frame()
	await rig.frame()
	assert_eq(emits.size(), 0, "nothing is announced while the level goes")
	await rig.leave_level(null)
