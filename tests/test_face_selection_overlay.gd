extends GutTest
## A face picked in Face Select is marked in the viewport, the mark follows its
## brush, and it goes when the face does (#1491). Before this nothing drew the
## faces at all: the only reader of `face_selection` outside the commands counted
## them for the HUD.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const PluginStandIn = preload("res://tests/support/plugin_stand_in.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFFaceSelectionOverlay = preload("res://addons/hammerforge/hf_face_selection_overlay.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func _overlay():
	return rig.plugin._face_selection_overlay


func _mark(level: Node) -> MeshInstance3D:
	for child in level.get_children(true):
		if child is MeshInstance3D and child.name == HFFaceSelectionOverlay.NODE_NAME:
			return child
	return null


func _top_face(brush: Node) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


func _face_with_normal(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


func _world_points(brush: Node, face_idx: int) -> PackedVector3Array:
	return brush.global_transform * brush.faces[face_idx].local_verts


func _entry_for(key: String, face_idx: int) -> Dictionary:
	for entry in _overlay().get_entries():
		if entry["key"] == key and entry["face_idx"] == face_idx:
			return entry
	return {}


func _points_match(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


func _pick(level: Node, brush: Node, face_idx: int) -> void:
	level.toggle_face_selection(brush, face_idx, true, false)


func _left(pressed: bool, at: Vector2, shift := false) -> int:
	var event := PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at)
	event.shift_pressed = shift
	return rig.forward(event)


func test_a_face_picked_in_the_viewport_is_drawn_on_the_level() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	var meshes_before: Array = level.get_children(true).filter(
		func(node): return node is MeshInstance3D
	)
	rig.plugin._hotkey_palette.action_invoked.emit("tool_select")
	rig.plugin.dock.face_select_mode.button_pressed = true
	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	_left(true, on_top)
	_left(false, on_top)
	assert_eq(level.face_selection.get("a", []), [_top_face(box)], "the click picks the face")
	# Off the face, so no hover feedback can stand in for the mark.
	rig.forward(PluginRig.motion(Vector2(10, 10)))
	await rig.frame()

	var drawn: Array = level.get_children(true).filter(
		func(node): return node is MeshInstance3D and not meshes_before.has(node)
	)
	assert_eq(drawn.size(), 1, "picking a face puts one mark on the level")
	if drawn.size() == 1:
		var mark: MeshInstance3D = drawn[0]
		assert_true(mark.is_visible_in_tree(), "and it is shown")
		assert_true(mark.mesh is ImmediateMesh, "drawn on an ImmediateMesh")
		assert_eq(mark.mesh.get_surface_count(), 2, "as a fill and an outline")
	rig.plugin.dock.face_select_mode.button_pressed = false
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)


func test_the_mark_holds_one_entry_per_selected_face() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	var a_top := _top_face(a)
	var a_side := _face_with_normal(a, Vector3.RIGHT)
	var b_top := _top_face(b)
	_pick(level, a, a_top)
	_pick(level, a, a_side)
	_pick(level, b, b_top)
	await rig.frame()

	var entries: Array = _overlay().get_entries()
	assert_eq(entries.size(), 3, "one entry for each of the three faces")
	for picked in [["a", a, a_top], ["b", b, b_top], ["a", a, a_side]]:
		var entry := _entry_for(picked[0], picked[2])
		assert_false(entry.is_empty(), "face %d of %s is marked" % [picked[2], picked[0]])
		if not entry.is_empty():
			assert_true(
				_points_match(entry["points"], _world_points(picked[1], picked[2])),
				"on the face itself"
			)
	assert_not_null(_mark(level), "drawn under the level")
	await rig.leave_level(level)


func test_the_mark_follows_a_brush_that_moves_or_is_resized() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var top := _top_face(a)
	_pick(level, a, top)
	await rig.frame()
	var before: PackedVector3Array = _entry_for("a", top)["points"]

	level.nudge_brushes_by_id(["a"], Vector3(4, 0, 0))
	await rig.frame()
	var moved: PackedVector3Array = _entry_for("a", top)["points"]
	var expected := PackedVector3Array()
	for point in before:
		expected.append(point + Vector3(4, 0, 0))
	assert_true(_points_match(moved, expected), "a nudge carries the mark with the face")

	level.set_brush_transform_by_id("a", Vector3(4, 10, 4), a.global_position)
	await rig.frame()
	var resized: PackedVector3Array = _entry_for("a", top)["points"]
	assert_false(_points_match(resized, moved), "a resize moves the top face")
	assert_true(_points_match(resized, _world_points(a, top)), "and the mark goes with it")
	await rig.leave_level(level)


func test_the_mark_follows_an_undo_and_a_redo() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var top := _top_face(a)
	_pick(level, a, top)
	await rig.frame()
	var before: PackedVector3Array = _entry_for("a", top)["points"]

	HFUndoHelper.commit(
		rig.plugin.undo_redo_manager,
		level,
		"Nudge",
		"nudge_brushes_by_id",
		[["a"], Vector3(0, 0, 6)]
	)
	await rig.frame()
	var moved: PackedVector3Array = _entry_for("a", top)["points"]
	assert_false(_points_match(moved, before), "the step moves the mark")

	rig.undo().press_undo()
	await rig.frame()
	assert_eq(_overlay().get_entries().size(), 1, "the undo keeps the face picked")
	assert_true(_points_match(_entry_for("a", top)["points"], before), "and puts the mark back")
	rig.undo().press_redo()
	await rig.frame()
	assert_true(_points_match(_entry_for("a", top)["points"], moved), "a redo moves it again")
	await rig.leave_level(level)


func test_the_mark_goes_on_deselect_and_when_the_mode_turns_off() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	rig.plugin.dock.face_select_mode.button_pressed = true
	_pick(level, a, _top_face(a))
	await rig.frame()
	assert_not_null(_mark(level), "a picked face is marked")

	level.clear_face_selection()
	await rig.frame()
	assert_eq(_overlay().get_entries().size(), 0, "clearing the selection empties the mark")
	assert_null(_mark(level), "and takes its node off the level")

	_pick(level, a, _top_face(a))
	await rig.frame()
	assert_not_null(_mark(level), "picked again, marked again")
	rig.plugin.dock.face_select_mode.button_pressed = false
	await rig.frame()
	assert_eq(_overlay().get_entries().size(), 0, "turning Face Select off clears the mark")
	assert_null(_mark(level), "and its node")
	await rig.leave_level(level)


func test_a_brush_that_goes_leaves_no_mark_behind() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	_pick(level, a, _top_face(a))
	_pick(level, b, _top_face(b))
	await rig.frame()
	assert_eq(_overlay().get_entries().size(), 2)

	level.delete_brush_by_id("a")
	await rig.frame()
	var entries: Array = _overlay().get_entries()
	assert_eq(entries.size(), 1, "a deleted brush takes its face's mark with it")
	assert_eq(entries[0]["key"] if entries.size() == 1 else "", "b", "and leaves the other")

	# Godot's own delete takes the node out of the scene without telling the level,
	# so the key stays behind in face_selection; the mark must still drop it.
	b.get_parent().remove_child(b)
	rig.plugin._on_undo_redo_version_changed()
	await rig.frame()
	assert_true(level.face_selection.has("b"), "the stale key is still there")
	assert_eq(_overlay().get_entries().size(), 0, "but nothing is drawn for it")
	assert_null(_mark(level), "and no node is left on the level")
	b.free()
	await rig.leave_level(level)


func test_the_mark_is_never_saved_with_the_scene() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_pick(level, a, _top_face(a))
	await rig.frame()
	var mark := _mark(level)
	assert_not_null(mark)
	if mark == null:
		await rig.leave_level(level)
		return
	assert_null(mark.owner, "the mark has no owner")
	assert_false(level.get_children().has(mark), "it is an internal child, out of the Scene tree")
	var packed := PackedScene.new()
	assert_eq(packed.pack(rig.scene_root), OK)
	var state := packed.get_state()
	for i in state.get_node_count():
		assert_ne(state.get_node_name(i), HFFaceSelectionOverlay.NODE_NAME, "and is not saved")
	await rig.leave_level(level)


func test_a_scene_switch_takes_the_mark_off_and_back_on() -> void:
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_pick(level, a, _top_face(a))
	await rig.frame()
	assert_not_null(_mark(level))

	var other := Node3D.new()
	other.name = "OtherScene"
	rig.plugin.stand_in_editor.scene_root = other
	rig.plugin.scene_changed.emit(other)
	assert_null(_mark(level), "another scene in front takes the mark off this level")
	assert_eq(_overlay().get_entries().size(), 0, "and that scene has nothing picked")

	rig.plugin.stand_in_editor.scene_root = rig.scene_root
	rig.plugin.scene_changed.emit(rig.scene_root)
	assert_not_null(_mark(level), "coming back marks the faces still picked there")
	assert_eq(_overlay().get_entries().size(), 1)
	other.free()
	await rig.leave_level(level)


## A plugin of its own, so taking it down leaves the shared one alone.
func test_disabling_the_plugin_takes_the_mark_down() -> void:
	var scene := Node3D.new()
	scene.name = "ExitScene"
	add_child(scene)
	var plugin := PluginStandIn.build(self, scene)
	assert_not_null(plugin, PluginStandIn.error())
	if plugin == null:
		remove_child(scene)
		scene.free()
		get_tree().edited_scene_root = rig.scene_root
		return
	var level = LevelRootScript.new()
	level.name = "LevelRoot"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene.add_child(level)
	level.owner = scene
	plugin.stand_in_editor.selection.add_node(level)
	var a = level.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3.ZERO, "brush_id": "a"}
	)
	_pick(level, a, _top_face(a))
	await get_tree().process_frame
	assert_not_null(_mark(level), "the face is marked")

	PluginStandIn.teardown(plugin)
	assert_null(_mark(level), "the plugin takes the mark with it when it goes")
	assert_eq(level.face_selection.size(), 1, "and leaves the level's selection alone")
	remove_child(scene)
	scene.free()
	# The stand-in's teardown cleared the tree's edited scene, which the shared
	# plugin's dock still reads.
	get_tree().edited_scene_root = rig.scene_root
	await get_tree().process_frame
	await get_tree().process_frame
