extends GutTest
## Align to Edge, Fit Repeats and Fit Strip (#1727), on the real plugin and dock.
## A texture along a 23 degree slope was a typed angle worked out by hand, three
## clean repeats were Fit then a scale divided by hand, and a trim sheet's strip
## was a scale and an offset worked out per face.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")

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
	level.face_selection = {}
	rig.undo().clear()
	await rig.leave_level(level)


func _facing(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal_through(brush.global_transform.basis).dot(normal) > 0.99:
			return i
	return -1


func _pick(level: Node, picked: Dictionary) -> void:
	level.face_selection = picked
	level.face_selection_changed.emit()


func _bounds(face: Object) -> Rect2:
	var uvs: PackedVector2Array = face.shown_uvs()
	var rect := Rect2(uvs[0], Vector2.ZERO)
	for uv in uvs:
		rect = rect.expand(uv)
	return rect


## What `face` shows at its own corner `i`.
func _uv_at_corner(face: Object, i: int) -> Vector2:
	return face.shown_uvs()[i]


func test_align_to_edge_runs_the_texture_along_a_23_degree_edge_then_the_next():
	var level = await _enter()
	var brush = rig.box(level, "w", Vector3(0, 2, 0), Vector3(4, 2, 1))
	brush.rotation_degrees = Vector3(0, 0, 23)
	var front := _facing(brush, Vector3.BACK)
	_pick(level, {"w": [front]})
	assert_eq(level.align_selected_faces_to_edge(), 1, "one face turned")
	var face = level.find_brush_by_id("w").faces[front]
	var first: int = level.brush_system._aligned_edges[face.get_instance_id()]
	var count: int = face.local_verts.size()
	var a := _uv_at_corner(face, first)
	var b := _uv_at_corner(face, (first + 1) % count)
	assert_almost_eq(a.y, b.y, 0.001, "along the edge the texture's V stays put")
	assert_gt(absf(b.x - a.x), 0.1, "and its U runs")
	var turned := fposmod(rad_to_deg(face.uv_rotation), 90.0)
	assert_true(
		absf(turned - 23.0) < 0.01 or absf(turned - 67.0) < 0.01,
		"turned by the edge's 23 degrees (%.3f)" % turned
	)
	assert_almost_eq(a.y, roundf(a.y), 0.001, "a repeat starts at the edge")
	var middle := Vector3.ZERO
	for corner in face.local_verts:
		middle += corner
	middle /= float(count)
	var mid_uv: Vector2 = face.shown_uvs_at(PackedVector3Array([middle]))[0]
	assert_lt(mid_uv.y, a.y, "the texture's top faces the middle of the face")
	level.align_selected_faces_to_edge()
	var second: int = level.brush_system._aligned_edges[face.get_instance_id()]
	assert_eq(second, (first + 1) % count, "pressing again steps to the next edge")
	var c := _uv_at_corner(face, second)
	var d := _uv_at_corner(face, (second + 1) % count)
	assert_almost_eq(c.y, d.y, 0.001, "now along that edge")
	await _leave(level)


## A wall and a ramp sheared with Texture Lock on, the default, carry a layout of
## their own. Align to Edge worked from the projection under it, and left V
## running along the sloped edge, not on a whole repeat (#1993).
func test_align_to_edge_lays_the_texture_along_each_edge_of_a_sheared_face():
	var level = await _enter()
	for case in [["wall", 0, 1, 0.4, 0.0], ["ramp", 1, 0, 0.5, -2.0]]:
		var id: String = case[0]
		rig.box(level, id, Vector3(0, 1, 0), Vector3(4, 2, 1))
		level.shear_managed_nodes([id], [], case[1], case[2], case[3], case[4])
		var front := _facing(level.find_brush_by_id(id), Vector3.BACK)
		var face = level.find_brush_by_id(id).faces[front]
		assert_true(face.has_uv_layout(), "%s: Texture Lock laid one on" % id)
		_pick(level, {id: [front]})
		var count: int = face.local_verts.size()
		for step in count:
			assert_eq(level.align_selected_faces_to_edge(), 1)
			face = level.find_brush_by_id(id).faces[front]
			var edge: int = level.brush_system._aligned_edges[face.get_instance_id()]
			var a := _uv_at_corner(face, edge)
			var b := _uv_at_corner(face, (edge + 1) % count)
			var at := "%s edge %d" % [id, edge]
			assert_almost_eq(a.y, b.y, 0.001, "%s: V stays put along it" % at)
			assert_almost_eq(a.y, roundf(a.y), 0.001, "%s: a repeat starts on it" % at)
			var middle := Vector3.ZERO
			for corner in face.local_verts:
				middle += corner
			var mid_uv: Vector2 = face.shown_uvs_at(PackedVector3Array([middle / float(count)]))[0]
			assert_lt(mid_uv.y, a.y, "%s: the texture's top faces the middle" % at)
	await _leave(level)


func test_fit_repeats_shows_exactly_three_across_on_several_faces():
	var level = await _enter()
	var a = rig.box(level, "a", Vector3(0, 2, 0), Vector3(4, 2, 1))
	var b = rig.box(level, "b", Vector3(8, 2, 0), Vector3(6, 3, 1))
	var fa := _facing(a, Vector3.BACK)
	var fb := _facing(b, Vector3.BACK)
	_pick(level, {"a": [fa], "b": [fb]})
	assert_eq(level.fit_selected_faces_repeats(3, 0), 2)
	for pair in [[a, fa], [b, fb]]:
		var shown := _bounds(level.find_brush_by_id(pair[0].brush_id).faces[pair[1]])
		assert_almost_eq(shown.position.x, 0.0, 0.0001, "starts at one edge")
		assert_almost_eq(shown.end.x, 3.0, 0.0001, "and ends at the other after three")
	var wide := _bounds(level.find_brush_by_id("b").faces[fb])
	assert_almost_eq(wide.size.y, 3.0 * 3.0 / 6.0, 0.0001, "V keeps the texture's aspect")
	await _leave(level)


func test_fit_strip_three_of_eight_maps_the_third_eighth():
	var level = await _enter()
	var trim = rig.box(level, "t", Vector3(0, 2, 0), Vector3(8, 0.5, 1))
	var face_idx := _facing(trim, Vector3.BACK)
	_pick(level, {"t": [face_idx]})
	assert_eq(level.fit_selected_faces_strip(3, 8), 1)
	var shown := _bounds(level.find_brush_by_id("t").faces[face_idx])
	assert_almost_eq(shown.position.x, 0.0, 0.0001)
	assert_almost_eq(shown.end.x, 1.0, 0.0001, "stretched once along U")
	assert_almost_eq(shown.position.y, 2.0 / 8.0, 0.0001, "from the end of the second strip")
	assert_almost_eq(shown.end.y, 3.0 / 8.0, 0.0001, "to the end of the third")
	await _leave(level)


func test_the_dock_and_the_face_menu_each_make_one_step():
	var level = await _enter()
	var brush = rig.box(level, "w", Vector3(0, 2, 0), Vector3(4, 2, 1))
	var front := _facing(brush, Vector3.BACK)
	_pick(level, {"w": [front]})
	var dock = rig.plugin.dock
	dock.fit_strip_count.value = 4
	dock.fit_strip_index.value = 2
	dock._on_fit_strip()
	assert_eq(rig.undo().step_count(), 1, "Fit Strip is one step")
	var shown := _bounds(level.find_brush_by_id("w").faces[front])
	assert_almost_eq(shown.position.y, 0.25, 0.0001, "strip two of four")
	# From the face menu, the edge nearest the cursor: the bottom edge here.
	rig.forward(PluginRig.motion(rig.camera.unproject_position(Vector3(0, 1.05, 0.5))))
	HFPluginCommands.execute(rig.plugin, "align_texture_to_edge", ["cursor"])
	assert_eq(rig.undo().step_count(), 2, "Align to Edge is one more")
	var face = level.find_brush_by_id("w").faces[front]
	var edge: int = level.brush_system._aligned_edges[face.get_instance_id()]
	var corner_a: Vector3 = face.local_verts[edge]
	var corner_b: Vector3 = face.local_verts[(edge + 1) % face.local_verts.size()]
	assert_almost_eq(corner_a.y, -1.0, 0.001, "the bottom edge, nearest the cursor")
	assert_almost_eq(corner_b.y, -1.0, 0.001)
	await _leave(level)
