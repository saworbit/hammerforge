extends GutTest
## Show selection size labels the width, depth and height of the selection's
## world bounds in the viewport, and follows every change to them (#1403). The
## viewport never showed how big the selection was: checking a corridor's width
## meant two Measure clicks per dimension, again after every resize.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFSelectionReadout = preload("res://addons/hammerforge/hf_selection_readout.gd")
const HFSizeLabels = preload("res://addons/hammerforge/hf_size_labels.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _readout():
	return rig.plugin._selection_readout


## A level with the grid at 0.5 and the switch on.
func _level() -> Node:
	var level = await rig.make_level()
	rig.plugin.dock._apply_grid_snap(0.5)
	rig.undo().clear()
	rig.plugin.dock.show_selection_size.button_pressed = true
	return level


func _leave(level: Node) -> void:
	rig.plugin.dock.show_selection_size.button_pressed = false
	if rig.plugin._vertex_mode:
		rig.plugin._toggle_vertex_mode(level)
	await rig.leave_level(level)


## The labels shown, as `[text, position]`, width, depth and height in that order.
func _shown() -> Array:
	var out: Array = []
	for label in _readout().get_labels():
		out.append([label.text, label.global_position])
	return out


func _texts() -> Array:
	var out: Array = []
	for entry in _shown():
		out.append(entry[0])
	return out


func _top_face(brush: Node) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


## A 2 x 3 x 4 box with one corner on the origin.
func _box(level: Node, id := "a", corner := Vector3.ZERO) -> Node:
	return rig.box(level, id, corner + Vector3(1, 1.5, 2), Vector3(2, 3, 4))


func test_a_selected_box_shows_its_three_sizes_on_the_matching_edges():
	assert_not_null(rig.plugin, rig.error())
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	assert_eq(
		_shown(),
		[
			["2", Vector3(1, 0, 4)],
			["4", Vector3(2, 0, 2)],
			["3", Vector3(2, 1.5, 4)],
		],
		"width along the bottom front edge, depth along the bottom side, height up the corner"
	)
	var labels: Array = _readout().get_labels()
	if labels.size() == 3:
		assert_true(labels[0].no_depth_test, "drawn over the geometry, as Measure's are")
		assert_eq(labels[0].billboard, BaseMaterial3D.BILLBOARD_ENABLED, "facing the camera")
		assert_eq(labels[0].outline_modulate, HFSizeLabels.OUTLINE_COLOR)
		assert_eq(labels[0].outline_size, HFSizeLabels.OUTLINE_SIZE)
	await _leave(level)


func test_two_brushes_show_their_combined_bounds():
	var level = await _level()
	var a = _box(level)
	var b = rig.box(level, "b", Vector3(5, 0.5, -1), Vector3(1, 1, 1))
	rig.select([a, b])
	await rig.frame()
	# x 0 to 5.5, y 0 to 3, z -1.5 to 4.
	assert_eq(_texts(), ["5.5", "5.5", "3"])
	assert_eq(_shown()[0][1], Vector3(2.75, 0, 4), "on the bounds of both")
	await _leave(level)


func test_a_face_selection_shows_the_bounds_of_its_faces():
	var level = await _level()
	var box = _box(level)
	rig.select([])
	level.toggle_face_selection(box, _top_face(box), true, false)
	await rig.frame()
	assert_eq(_texts(), ["2", "4"], "the top face is 2 by 4 and has no height to label")
	assert_eq(_shown()[0][1], Vector3(1, 3, 4), "and is labelled where it is")
	level.clear_face_selection()
	await rig.frame()
	assert_eq(_shown(), [], "picking no face labels nothing")
	await _leave(level)


func test_a_turned_brush_shows_its_world_bounds():
	var level = await _level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(2, 2, 2))
	box.rotation = Vector3(0, PI / 4.0, 0)
	rig.select([box])
	await rig.frame()
	assert_eq(_texts(), ["2.83", "2.83", "2"], "a 2 unit box turned 45 degrees is 2.83 across")
	await _leave(level)


func test_the_labels_follow_set_brush_transform_by_id():
	var level = await _level()
	_box(level)
	rig.select([level.find_brush_by_id("a")])
	await rig.frame()
	level.set_brush_transform_by_id("a", Vector3(6, 1, 2), Vector3(10, 0.5, 0))
	await rig.frame()
	assert_eq(_shown()[0], ["6", Vector3(10, 0, 1)], "the new width, where the brush now is")
	assert_eq(_texts(), ["6", "2", "1"])
	await _leave(level)


func test_the_labels_follow_a_resize_handle_drag_as_it_goes():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	# What a handle drag does each step: a new size and place, with no signal and
	# no undo step until the handle is let go.
	box.size = Vector3(5, 3, 4)
	box.global_position = Vector3(2.5, 1.5, 2)
	await rig.frame()
	assert_eq(_texts(), ["5", "4", "3"], "the width follows the handle within a frame")
	await _leave(level)


func test_the_labels_follow_a_nudge_and_its_undo():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	assert_true(rig.plugin._nudge_selected(level, Vector3.RIGHT))
	await rig.frame()
	assert_eq(_shown()[0][1], Vector3(1.5, 0, 4), "half a unit along, a grid step")
	assert_true(rig.undo().press_undo())
	await rig.frame()
	await rig.frame()
	assert_eq(_shown()[0][1], Vector3(1, 0, 4), "and back with the undo")
	await _leave(level)


func test_the_labels_follow_a_vertex_drag():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	rig.forward(PluginRig.key_for("vertex_edit"))
	assert_true(rig.plugin._vertex_mode)
	var vs = level.vertex_system
	var verts: PackedVector3Array = vs.get_brush_vertices(box)
	for i in verts.size():
		if verts[i].y > 1.0:
			vs.select_vertex("a", i, true)
	vs.begin_drag(box.global_transform * Vector3(0, 1.5, 0))
	assert_true(vs.update_drag_absolute(Vector3(0, 1, 0)), "the top is dragged up")
	rig.plugin._update_vertex_overlay(level, null)
	await rig.frame()
	assert_eq(_texts()[2], "4", "the height follows the vertices up while they are dragged")
	vs.cancel_drag()
	rig.plugin._update_vertex_overlay(level, null)
	await rig.frame()
	assert_eq(_texts()[2], "3", "and back when the drag is let go of")
	await _leave(level)


func test_a_tagged_brush_is_measured_again_though_it_has_not_moved():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	# Taller faces on the same node, size and place: what a vertex edit's undo or
	# an agent's face edit does. The tag is the only thing that says so.
	var tall = rig.box(level, "tall", Vector3(1, 2.5, 2), Vector3(2, 5, 4))
	var state: Dictionary = tall.geometry_state()
	state["shape"] = box.shape
	state["size"] = box.size
	level._apply_vertex_faces({"a": state})
	await rig.frame()
	assert_eq(_texts()[2], "5", "the height its faces now have")
	await _leave(level)


func test_deselecting_or_switching_off_takes_every_label_down():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	assert_eq(_shown().size(), 3)
	rig.select([])
	await rig.frame()
	assert_eq(_shown(), [], "deselecting takes the labels down")
	assert_null(_readout().get_label_container(), "and their node")
	rig.select([box])
	await rig.frame()
	assert_eq(_shown().size(), 3)
	rig.plugin.dock.show_selection_size.button_pressed = false
	assert_eq(_shown(), [], "and so does the switch, at once")
	assert_null(_readout().get_label_container())
	assert_false(bool(rig.plugin._user_prefs.get_pref("show_selection_size", true)), "kept")
	await _leave(level)


func test_the_labels_are_never_saved_with_the_scene():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	var holder: Node3D = _readout().get_label_container()
	assert_not_null(holder)
	if holder == null:
		await _leave(level)
		return
	assert_null(holder.owner, "the labels have no owner")
	assert_false(level.get_children().has(holder), "they hang off the level as an internal child")
	var packed := PackedScene.new()
	assert_eq(packed.pack(rig.scene_root), OK)
	var state := packed.get_state()
	for i in state.get_node_count():
		assert_ne(state.get_node_name(i), HFSizeLabels.NODE_NAME, "and are not saved")
		assert_ne(str(state.get_node_type(i)), "Label3D")
	await _leave(level)


func test_a_scene_switch_takes_the_labels_off_and_back_on():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	assert_eq(_shown().size(), 3)
	var other := Node3D.new()
	other.name = "OtherScene"
	rig.plugin.stand_in_editor.scene_root = other
	rig.plugin.scene_changed.emit(other)
	assert_null(_readout().get_label_container(), "another scene in front takes them off")
	rig.plugin.stand_in_editor.scene_root = rig.scene_root
	rig.plugin.scene_changed.emit(rig.scene_root)
	assert_eq(_shown().size(), 3, "coming back labels what is still selected")
	other.free()
	await _leave(level)


func test_the_command_palette_and_its_key_flip_the_switch():
	var level = await _level()
	var box = _box(level)
	rig.select([box])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("toggle_selection_size")
	assert_false(rig.plugin.dock.show_selection_size.button_pressed, "the palette turns it off")
	assert_eq(_shown(), [])
	assert_eq(
		rig.forward(PluginRig.key_for("toggle_selection_size")),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"its key is taken"
	)
	assert_true(rig.plugin.dock.show_selection_size.button_pressed, "and turns it back on")
	await rig.frame()
	assert_eq(_shown().size(), 3)
	await _leave(level)


func test_the_switch_is_off_by_default_and_in_the_console_viewport_group():
	var prefs := HFUserPrefs.new()
	assert_false(bool(prefs.get_pref("show_selection_size", true)), "off until asked for")
	var found := ""
	for group in HFConsoleControls.GROUPS:
		for spec in group["rows"]:
			if str(spec.get("pref", "")) == "show_selection_size":
				found = str(group["title"])
				assert_eq(str(spec.get("dock", "")), "show_selection_size")
	assert_eq(found, "Viewport")


func test_label_entries_skip_a_flat_side():
	var entries := HFSelectionReadout.label_entries(AABB(Vector3.ZERO, Vector3(1, 0, 0.25)), 0.25)
	var texts: Array = []
	for entry in entries:
		texts.append(entry["text"])
	assert_eq(texts, ["1", "0.25"], "no height to label on a flat face")
