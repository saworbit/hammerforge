extends GutTest
## The Selection Info section of the Build tab: where the selection is and how
## big, in world or local space, with typed coordinates for one vertex (#1404).
## A selection only ever showed as a count, and a vertex could only be dragged.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFNumberFormat = preload("res://addons/hammerforge/hf_number_format.gd")
const HFSelectionReadout = preload("res://addons/hammerforge/hf_selection_readout.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _info() -> HFSelectionInfo:
	return rig.plugin.dock.selection_info


func _level() -> Node:
	var level = await rig.make_level()
	rig.plugin.dock._apply_grid_snap(0.5)
	rig.undo().clear()
	_info().set_local(false)
	return level


func _leave(level: Node) -> void:
	if rig.plugin._vertex_mode:
		rig.plugin._toggle_vertex_mode(level)
	_info().set_local(false)
	await rig.leave_level(level)


func _row(name_text: String) -> String:
	for row in _info().get_rows():
		if row[0] == name_text:
			return row[1]
	return "<no %s row>" % name_text


func _said(text: String) -> bool:
	for toast in rig.toasts():
		if str(toast).contains(text):
			return true
	return false


func _top_face(brush: Node) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


## Vertex mode on [param brush], with the vertex at [param local] selected.
func _select_vertex(level: Node, brush: Node, local: Vector3) -> int:
	rig.select([brush])
	if not rig.plugin._vertex_mode:
		rig.forward(PluginRig.key_for("vertex_edit"))
	var vs = level.vertex_system
	var verts: PackedVector3Array = vs.get_brush_vertices(brush)
	for i in verts.size():
		if verts[i].is_equal_approx(local):
			vs.select_vertex(str(brush.brush_id), i)
			rig.plugin._update_vertex_overlay(level, null)
			return i
	return -1


func _type(axis: int, text: String) -> void:
	var field: LineEdit = _info().get_vertex_fields()[axis]
	field.text = text
	field.text_submitted.emit(text)


func _vertex_at(level: Node, brush: Node, index: int) -> Vector3:
	return brush.global_transform * level.vertex_system.get_brush_vertices(brush)[index]


func test_one_brush_shows_the_centre_and_size_its_record_has():
	assert_not_null(rig.plugin, rig.error())
	var level = await _level()
	var box = rig.box(level, "a", Vector3(1, 2, 3), Vector3(2, 4, 6))
	assert_false(rig.plugin.dock._selection_info_section.visible, "nothing selected, no section")
	rig.select([box])
	await rig.frame()
	assert_true(rig.plugin.dock._selection_info_section.visible, "a brush shows it")
	var info: Dictionary = level.get_brush_info_from_node(box)
	var transform: Transform3D = info["transform"]
	assert_eq(_info().get_title(), "1 brush")
	assert_eq(_row("Centre"), HFNumberFormat.point(transform.origin, 0.5))
	assert_eq(_row("Size"), HFNumberFormat.dimensions(info["size"], 0.5))
	assert_eq(_row("Size"), "2 x 4 x 6")
	await _leave(level)


func test_typing_a_vertex_height_moves_it_in_one_undo_step():
	var level = await _level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(4, 4, 4))
	var index := _select_vertex(level, box, Vector3(2, 2, -2))
	assert_ne(index, -1)
	await rig.frame()
	assert_eq(_info().get_title(), "1 vertex")
	var fields := _info().get_vertex_fields()
	assert_true(fields[1].get_parent().visible, "one vertex gets fields to type in")
	assert_eq([fields[0].text, fields[1].text, fields[2].text], ["2", "2", "-2"])
	var steps: int = rig.undo().step_count()
	_type(1, "3")
	assert_eq(_vertex_at(level, box, index), Vector3(2, 3, -2), "the vertex goes up to 3")
	assert_eq(rig.undo().step_count(), steps + 1, "as one undo step")
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Move Vertices")
	assert_eq(fields[1].text, "3", "the field reads where it went")
	assert_true(rig.undo().press_undo())
	await rig.frame()
	assert_eq(_vertex_at(level, box, index), Vector3(2, 2, -2), "and undo puts it back")
	await rig.frame()
	assert_eq(fields[1].text, "2", "the field follows the undo")
	await _leave(level)


func test_a_place_that_would_dent_the_brush_is_refused_and_the_field_goes_back():
	var level = await _level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(4, 4, 4))
	var index := _select_vertex(level, box, Vector3(2, 2, -2))
	await rig.frame()
	var steps: int = rig.undo().step_count()
	rig.clear_toasts()
	# Through the box and out past its far side: the corner would stand in front
	# of the -X face, whichever way the bent faces were split.
	_type(0, "-3")
	assert_eq(_vertex_at(level, box, index), Vector3(2, 2, -2), "the vertex stays where it was")
	assert_eq(rig.undo().step_count(), steps, "and no step is recorded")
	var fields := _info().get_vertex_fields()
	assert_eq([fields[0].text, fields[1].text, fields[2].text], ["2", "2", "-2"], "fields go back")
	assert_true(_said("Move rejected"), "and a message says why")
	await _leave(level)


func test_a_field_that_is_not_a_number_goes_back_and_says_so():
	var level = await _level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(4, 4, 4))
	_select_vertex(level, box, Vector3(2, 2, 2))
	await rig.frame()
	var steps: int = rig.undo().step_count()
	_type(1, "up")
	assert_eq(_info().get_vertex_fields()[1].text, "2", "the field goes back")
	assert_string_contains(_info().get_note(), "Y must be a number")
	assert_eq(rig.undo().step_count(), steps, "and nothing moved")
	await _leave(level)


func test_one_edge_shows_its_length_and_midpoint():
	var level = await _level()
	var box = rig.box(level, "a", Vector3(10, 0, 0), Vector3(4, 2, 6))
	rig.select([box])
	rig.forward(PluginRig.key_for("vertex_edit"))
	var vs = level.vertex_system
	vs.sub_mode = vs.VertexSubMode.EDGE
	var verts: PackedVector3Array = vs.get_brush_vertices(box)
	var a := -1
	var b := -1
	for i in verts.size():
		if verts[i].is_equal_approx(Vector3(2, 1, -3)):
			a = i
		elif verts[i].is_equal_approx(Vector3(2, 1, 3)):
			b = i
	vs.select_edge("a", [a, b])
	rig.plugin._update_vertex_overlay(level, null)
	await rig.frame()
	assert_eq(_info().get_title(), "1 edge")
	assert_eq(_row("Length"), "6")
	assert_eq(_row("Midpoint"), "12, 1, 0")
	vs.sub_mode = vs.VertexSubMode.VERTEX
	await _leave(level)


func test_one_face_shows_its_centre_normal_and_area():
	var level = await _level()
	var box = rig.box(level, "a", Vector3(0, 1, 0), Vector3(4, 2, 6))
	rig.select([])
	level.toggle_face_selection(box, _top_face(box), true, false)
	await rig.frame()
	assert_true(rig.plugin.dock._selection_info_section.visible, "a face alone shows it")
	assert_eq(_info().get_title(), "1 face")
	assert_eq(_row("Centre"), "0, 2, 0")
	assert_eq(_row("Normal"), "0, 1, 0")
	assert_eq(_row("Area"), "24")
	level.clear_face_selection()
	await _leave(level)


func test_several_brushes_show_their_count_centre_and_bounds():
	var level = await _level()
	var a = rig.box(level, "a", Vector3(1, 1, 1), Vector3(2, 2, 2))
	var b = rig.box(level, "b", Vector3(7, 1, 1), Vector3(2, 2, 2))
	rig.select([a, b])
	await rig.frame()
	assert_eq(_info().get_title(), "2 brushes")
	assert_eq(_row("Count"), "2")
	assert_eq(_row("Centre"), "4, 1, 1")
	assert_eq(_row("Size"), "8 x 2 x 2")
	await _leave(level)


func test_several_vertices_show_their_count_centre_and_bounds():
	var level = await _level()
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(4, 4, 4))
	_select_vertex(level, box, Vector3(2, 2, 2))
	var vs = level.vertex_system
	var verts: PackedVector3Array = vs.get_brush_vertices(box)
	for i in verts.size():
		if verts[i].is_equal_approx(Vector3(-2, -2, 2)):
			vs.select_vertex("a", i, true)
	rig.plugin._update_vertex_overlay(level, null)
	await rig.frame()
	assert_eq(_info().get_title(), "2 vertices")
	assert_eq(_row("Count"), "2")
	assert_eq(_row("Centre"), "0, 0, 2")
	assert_eq(_row("Size"), "4 x 4 x 0")
	assert_false(_info().get_vertex_fields()[0].get_parent().visible, "no fields for several")
	await _leave(level)


func test_world_and_local_differ_under_a_turned_level():
	var level = await _level()
	level.position = Vector3(10, 0, 0)
	level.rotation = Vector3(0, PI / 2.0, 0)
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(2, 2, 2))
	box.position = Vector3(2, 1, 0)
	rig.select([box])
	await rig.frame()
	var world: Vector3 = box.global_position
	assert_false(world.is_equal_approx(box.position), "the level's turn moves the brush")
	assert_eq(_row("Centre"), HFNumberFormat.point(world, 0.5), "World is where it stands")
	_info().set_local(true)
	assert_eq(_row("Centre"), "2, 1, 0", "Local is its place in its parent, as the Inspector has")
	assert_eq(_row("Size"), "2 x 2 x 2", "and a size is a size in either")
	_info().set_local(false)
	var index := _select_vertex(level, box, Vector3(1, 1, -1))
	await rig.frame()
	var fields := _info().get_vertex_fields()
	var corner := _vertex_at(level, box, index)
	assert_eq(fields[0].text, HFNumberFormat.number(corner.x, 0.5), "a vertex in world space")
	# The level is turned about Y, so its brush's own +X runs along the world's -Z.
	_type(2, HFNumberFormat.number(corner.z - 0.5, 0.5))
	assert_eq(
		_vertex_at(level, box, index),
		corner - Vector3(0, 0, 0.5),
		"a world number is a place in the world"
	)
	assert_eq(level.vertex_system.get_brush_vertices(box)[index], Vector3(1.5, 1, -1))
	_info().set_local(true)
	assert_eq(
		[fields[0].text, fields[1].text, fields[2].text], ["1.5", "1", "-1"], "or its brush's"
	)
	_type(1, "1.5")
	assert_eq(
		level.vertex_system.get_brush_vertices(box)[index],
		Vector3(1.5, 1.5, -1),
		"a local number is a place in the brush's own space"
	)
	level.position = Vector3.ZERO
	level.rotation = Vector3.ZERO
	await _leave(level)


func test_the_section_sits_at_the_top_of_selection_tools():
	var dock = rig.plugin.dock
	var info_section: Node = dock._selection_info_section
	var tools_section: Node = dock._selection_tools_section
	assert_eq(info_section.get_parent(), tools_section.get_parent(), "both in the Build tab")
	assert_eq(info_section.get_index() + 1, tools_section.get_index(), "directly above")


func test_summarize_names_nothing_for_nothing():
	var summary := HFSelectionReadout.summarize(null, [], false)
	assert_eq(summary["kind"], "")
	assert_false(summary["has_bounds"])
