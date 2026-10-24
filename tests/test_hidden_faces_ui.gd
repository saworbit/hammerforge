extends GutTest
## Hidden faces on the real plugin and dock (#1719): the Hidden swatch, Apply
## Picked Look, the palette commands and Hide Faces Against Solids, each one undo
## step.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _enter() -> Node:
	var level = await rig.make_level()
	rig.undo().clear()
	return level


func _leave(level: Node) -> void:
	rig.undo().clear()
	await rig.leave_level(level)


static func _face_facing(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(normal) > 0.99:
			return i
	return -1


func _swatch() -> Button:
	return rig.plugin.dock.material_browser.hidden_swatch


func test_the_hidden_swatch_hides_the_selected_faces_as_one_step():
	var level = await _enter()
	var box = rig.box(level, "box", Vector3.ZERO, Vector3(2, 2, 2))
	var bottom := _face_facing(box, Vector3.DOWN)
	level.face_selection = {"box": [bottom]}
	var swatch := _swatch()
	assert_not_null(swatch, "the browser shows the Hidden swatch")
	if swatch:
		swatch.pressed.emit()
	assert_true(box.faces[bottom].is_hidden(), "a click hides the selected face")
	var undo = rig.undo()
	assert_eq(undo.step_count(), 1, "one step")
	assert_eq(undo.scene_history.get_current_action_name(), "Make Faces Hidden")
	assert_true(undo.press_undo())
	await rig.frame()
	var restored = level.brush_system.find_brush_by_id("box")
	assert_false(restored.faces[bottom].is_hidden(), "undo shows it again")
	var data: Variant = rig.plugin.dock.material_browser._hidden_drag_data(Vector2.ZERO)
	assert_true(data is Dictionary and data.get("hidden", false), "it drags as Hidden")
	await _leave(level)


func test_a_picked_hidden_look_makes_faces_hidden_and_keeps_their_slots():
	var level = await _enter()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var box = rig.box(level, "box", Vector3.ZERO, Vector3(2, 2, 2))
	box.faces[0].face_type = FaceData.FaceType.HIDDEN
	box.faces[1].material_idx = 1
	var dock = rig.plugin.dock
	dock.remember_picked_look(box.faces[0])
	level.face_selection = {"box": [1]}
	rig.plugin._hotkey_palette.action_invoked.emit("apply_picked_look")
	var face: FaceData = level.brush_system.find_brush_by_id("box").faces[1]
	assert_true(face.is_hidden(), "Alt+T lays the Hidden look on")
	assert_eq(face.material_idx, 1, "and the face keeps its own slot under it")
	assert_eq(rig.undo().step_count(), 1)
	rig.plugin._hotkey_palette.action_invoked.emit("make_faces_normal")
	face = level.brush_system.find_brush_by_id("box").faces[1]
	assert_false(face.is_hidden(), "Make Faces Normal shows it again")
	assert_eq(face.material_idx, 1, "in the material it had")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Make Faces Normal")
	await _leave(level)


func test_hide_faces_against_solids_shows_them_asks_and_is_one_step():
	var level = await _enter()
	rig.box(level, "slab", Vector3(0, 0.5, 0), Vector3(4, 1, 4))
	var block = rig.box(level, "block", Vector3(0, 1.5, 0), Vector3.ONE)
	var bottom := _face_facing(block, Vector3.DOWN)
	level.face_selection = {}
	rig.select([block])
	rig.plugin._hotkey_palette.action_invoked.emit("hide_faces_against_solids")
	assert_eq(rig.open_dialogs().size(), 1, "it asks first")
	assert_eq(level.face_selection, {"block": [bottom]}, "with the face it found picked")
	assert_eq(rig.undo().step_count(), 0, "and nothing changed yet")
	assert_eq(await rig.accept_dialogs(), 1)
	block = level.brush_system.find_brush_by_id("block")
	assert_true(block.faces[bottom].is_hidden())
	var hidden := 0
	for brush in level.draft_brushes_node.get_children():
		for face in brush.faces:
			hidden += 1 if face.is_hidden() else 0
	assert_eq(hidden, 1, "that face alone")
	var undo = rig.undo()
	assert_eq(undo.step_count(), 1, "one step")
	assert_eq(undo.scene_history.get_current_action_name(), "Hide Faces Against Solids")
	assert_true(undo.press_undo())
	await rig.frame()
	assert_false(level.brush_system.find_brush_by_id("block").faces[bottom].is_hidden())
	await _leave(level)


func test_cancel_leaves_the_faces_and_puts_back_the_picked_faces():
	var level = await _enter()
	rig.box(level, "slab", Vector3(0, 0.5, 0), Vector3(4, 1, 4))
	var block = rig.box(level, "block", Vector3(0, 1.5, 0), Vector3.ONE)
	level.face_selection = {}
	rig.select([block])
	rig.plugin._hotkey_palette.action_invoked.emit("hide_faces_against_solids")
	var dialogs := rig.open_dialogs()
	assert_eq(dialogs.size(), 1)
	if dialogs.size() == 1:
		dialogs[0].canceled.emit()
	await rig.frame()
	assert_eq(level.face_selection, {}, "the picked faces are what they were")
	for face in level.brush_system.find_brush_by_id("block").faces:
		assert_false(face.is_hidden())
	assert_eq(rig.undo().step_count(), 0)
	await _leave(level)
