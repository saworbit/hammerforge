extends GutTest

const HFVertexSystem = preload("res://addons/hammerforge/systems/hf_vertex_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

var root: Node3D
var vs: HFVertexSystem
var draft_node: Node3D


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	draft_node = Node3D.new()
	draft_node.name = "DraftBrushes"
	root.add_child(draft_node)
	root.draft_brushes_node = draft_node
	vs = HFVertexSystem.new(root)


func after_each():
	root = null
	vs = null
	draft_node = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var brush_system: RefCounted
var grid_snap := 8.0
var drag_size_default := Vector3(32, 32, 32)
var dirty_brush_ids: Array[String] = []
signal user_message(msg, level)

func tag_brush_dirty(brush_id: String) -> void:
	dirty_brush_ids.append(brush_id)
"""
	s.reload()
	return s


func _make_box_brush(pos: Vector3, sz: Vector3, id: String) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.brush_id = id
	draft_node.add_child(b)
	b.global_position = pos
	# Build box faces
	var half = sz * 0.5
	# CW winding from outside (matches _build_box_faces in production code)
	var quads = [
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, -half.y, -half.z)
		],
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, half.y, -half.z)
		],
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(-half.x, half.y, -half.z)
		]
	]
	var faces: Array[FaceData] = []
	for quad in quads:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces.append(face)
	b.faces = faces
	return b


func _dent_box_corner(brush: DraftBrush, corner: Vector3, replacement: Vector3) -> void:
	for face in brush.faces:
		var updated := PackedVector3Array()
		for vertex in face.local_verts:
			updated.append(replacement if vertex.is_equal_approx(corner) else vertex)
		face.local_verts = updated
		face.ensure_geometry()


func _make_test_camera(position: Vector3, orthogonal := false) -> Camera3D:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.global_position = position
	camera.look_at(Vector3.ZERO, Vector3.UP)
	if orthogonal:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 20.0
	camera.force_update_transform()
	return camera


func _assert_vector_near(actual: Vector3, expected: Vector3, message: String) -> void:
	assert_lt(actual.distance_to(expected), 0.01, message)


# ===========================================================================
# Vertex extraction
# ===========================================================================


func test_box_brush_has_8_unique_vertices():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var verts = vs.get_brush_vertices(b)
	assert_eq(verts.size(), 8, "Box brush should have 8 unique vertices")


func test_small_brush_vertices_count():
	var b = _make_box_brush(Vector3.ZERO, Vector3(2, 4, 6), "b2")
	var verts = vs.get_brush_vertices(b)
	assert_eq(verts.size(), 8)


func test_no_faces_returns_empty():
	# Test with a brush that has no faces (not added to tree to avoid auto-generation)
	var b = DraftBrush.new()
	b.brush_id = "empty"
	var empty_faces: Array[FaceData] = []
	b.faces = empty_faces
	# Don't add to tree — DraftBrush._ready() auto-builds faces
	var verts = vs.get_brush_vertices(b)
	assert_eq(verts.size(), 0)
	b.free()


func test_null_brush_returns_empty():
	var verts = vs.get_brush_vertices(null)
	assert_eq(verts.size(), 0)


# ===========================================================================
# Selection
# ===========================================================================


func test_select_vertex_adds_to_selection():
	vs.select_vertex("b1", 0, false)
	assert_true(vs.has_selection())
	assert_eq(vs.get_selection_count(), 1)


func test_select_vertex_additive():
	vs.select_vertex("b1", 0, false)
	vs.select_vertex("b1", 1, true)
	assert_eq(vs.get_selection_count(), 2)


func test_select_vertex_non_additive_replaces():
	vs.select_vertex("b1", 0, false)
	vs.select_vertex("b1", 1, false)
	assert_eq(vs.get_selection_count(), 1)
	assert_true(vs.selected_vertices.has("b1"))
	var indices: PackedInt32Array = vs.selected_vertices["b1"]
	assert_eq(indices[0], 1)


func test_toggle_deselect():
	vs.select_vertex("b1", 0, false)
	vs.select_vertex("b1", 0, true)
	assert_false(vs.has_selection())


func test_clear_selection():
	vs.select_vertex("b1", 0, false)
	vs.select_vertex("b2", 1, true)
	vs.clear_selection()
	assert_false(vs.has_selection())
	assert_eq(vs.get_selection_count(), 0)


func test_multi_brush_selection():
	vs.select_vertex("b1", 0, false)
	vs.select_vertex("b2", 3, true)
	assert_eq(vs.get_selection_count(), 2)
	assert_true(vs.selected_vertices.has("b1"))
	assert_true(vs.selected_vertices.has("b2"))


# ===========================================================================
# Convexity validation
# ===========================================================================


func test_valid_box_is_convex():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "cv1")
	assert_true(vs.validate_convexity(b))


func test_degenerate_brush_passes_validation():
	# A brush with fewer than 4 faces is allowed (degenerate)
	var b = DraftBrush.new()
	b.brush_id = "degen"
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	face.ensure_geometry()
	var face_arr: Array[FaceData] = [face]
	b.faces = face_arr
	draft_node.add_child(b)
	assert_true(vs.validate_convexity(b))


func test_null_brush_passes_validation():
	assert_true(vs.validate_convexity(null))


func test_clip_to_convex_tags_only_the_mutated_brush():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "concave")
	var untouched := _make_box_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "untouched")
	vs.set_selection([brush, untouched])
	_dent_box_corner(brush, Vector3(16, 16, 16), Vector3.ZERO)
	assert_false(vs.validate_convexity(brush), "The fixture must start non-convex")
	var vertices_before := vs.get_brush_vertices(brush).size()

	assert_true(vs.clip_to_convex("concave"), "A concave brush should be replaced by its hull")
	assert_lt(
		vs.get_brush_vertices(brush).size(),
		vertices_before,
		"The interior dent vertex should be removed by the hull mutation"
	)
	assert_eq(root.dirty_brush_ids, ["concave"], "Only the changed brush should be tagged once")


func test_clip_to_convex_no_op_and_failure_do_not_tag_dirty():
	var convex := _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "convex")
	vs.set_selection([convex])

	assert_false(vs.clip_to_convex("convex"), "An already-convex brush is a no-op")
	assert_false(vs.clip_to_convex("missing"), "A missing brush cannot be clipped")
	assert_true(root.dirty_brush_ids.is_empty(), "No-op and failure paths must not tag a brush")


# ===========================================================================
# Vertex movement
# ===========================================================================


func test_move_vertices_updates_face_data():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "mv1")
	vs.set_selection([b])
	var verts_before = vs.get_brush_vertices(b)
	var target_vert = verts_before[0]
	vs.select_vertex("mv1", 0, false)
	var delta = Vector3(4, 0, 0)
	var result = vs.move_vertices(delta)
	assert_true(result, "Move should succeed for valid convex result")
	var verts_after = vs.get_brush_vertices(b)
	# The moved vertex should differ from the original
	var found_moved := false
	for v in verts_after:
		if v.is_equal_approx(target_vert + delta):
			found_moved = true
			break
	assert_true(found_moved, "Should find the moved vertex at new position")


func test_move_with_no_selection_returns_false():
	vs.clear_selection()
	assert_false(vs.move_vertices(Vector3(1, 0, 0)))


# ===========================================================================
# Edited geometry survives a rebuild
# ===========================================================================


func test_move_vertices_promotes_brush_to_custom_shape():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "promote1")
	assert_eq(b.shape, DraftBrush.BrushShape.BOX, "Fixture starts as a box")
	vs.set_selection([b])
	vs.select_vertex("promote1", 0, false)
	assert_true(vs.move_vertices(Vector3(4, 0, 0)))
	assert_eq(
		b.shape,
		DraftBrush.BrushShape.CUSTOM,
		"A moved vertex must claim the face array so a rebuild cannot overwrite it"
	)


func test_moved_vertices_survive_resize():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "survive1")
	vs.set_selection([b])
	var original_vertex: Vector3 = vs.get_brush_vertices(b)[0]
	vs.select_vertex("survive1", 0, false)
	assert_true(vs.move_vertices(Vector3(4, 0, 0)))
	var moved_vertex := original_vertex + Vector3(4, 0, 0)

	b.set_size(Vector3(48, 48, 48))

	var found := false
	for v in vs.get_brush_vertices(b):
		if v.is_equal_approx(moved_vertex):
			found = true
			break
	assert_true(found, "Resize must not rebuild the box over a moved vertex")


func test_clip_to_convex_promotes_brush_to_custom_shape():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "clipped")
	vs.set_selection([b])
	_dent_box_corner(b, Vector3(16, 16, 16), Vector3.ZERO)
	assert_false(vs.validate_convexity(b), "The fixture must start non-convex")
	assert_true(vs.clip_to_convex("clipped"))
	assert_eq(b.shape, DraftBrush.BrushShape.CUSTOM, "A hull rebuild is not a box any more")


func test_committed_vertex_drag_promotes_brush_to_custom_shape():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "dragged")
	vs.set_selection([b])
	var original_vertex: Vector3 = vs.get_brush_vertices(b)[0]
	vs.select_vertex("dragged", 0, false)
	vs.begin_drag(b.to_global(original_vertex))
	assert_true(vs.update_drag_absolute(Vector3(2, 0, 0)))
	assert_false(vs.end_drag().is_empty(), "A real geometry change should retain undo data")
	assert_eq(b.shape, DraftBrush.BrushShape.CUSTOM, "A committed drag claims the face array")


func test_canceled_vertex_drag_leaves_brush_as_box():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "canceled")
	vs.set_selection([b])
	var original_vertex: Vector3 = vs.get_brush_vertices(b)[0]
	vs.select_vertex("canceled", 0, false)
	vs.begin_drag(b.to_global(original_vertex))
	assert_true(vs.update_drag_absolute(Vector3(2, 0, 0)))
	vs.cancel_drag()
	assert_eq(
		b.shape,
		DraftBrush.BrushShape.BOX,
		"A canceled drag changed nothing, so it must not cost the brush its resize handles"
	)


# ===========================================================================
# Drag lifecycle
# ===========================================================================


func test_begin_end_drag():
	vs.begin_drag(Vector3.ZERO)
	assert_true(vs.is_dragging())
	var snapshots = vs.end_drag()
	assert_false(vs.is_dragging())
	assert_true(snapshots.is_empty(), "A click without movement should not create undo data")


func test_absolute_drag_updates_do_not_accumulate():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "abs1")
	vs.set_selection([b])
	var original_vertex: Vector3 = vs.get_brush_vertices(b)[0]
	vs.select_vertex("abs1", 0, false)
	vs.begin_drag(b.to_global(original_vertex))

	assert_true(vs.update_drag_absolute(Vector3(2, 0, 0)))
	assert_true(vs.update_drag_absolute(Vector3(4, 0, 0)))
	var selected_world: Vector3 = vs.get_selected_world_positions()[0]
	_assert_vector_near(
		selected_world,
		b.to_global(original_vertex) + Vector3(4, 0, 0),
		"The latest start-relative delta should replace, not accumulate with, the prior delta"
	)


func test_zero_absolute_drag_restores_origin_and_suppresses_undo():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "zero1")
	vs.set_selection([b])
	var vertices_before := vs.get_brush_vertices(b).duplicate()
	vs.select_vertex("zero1", 0, false)
	vs.begin_drag(b.to_global(vertices_before[0]))

	assert_true(vs.update_drag_absolute(Vector3(4, 0, 0)))
	assert_true(vs.update_drag_absolute(Vector3.ZERO))
	var vertices_after := vs.get_brush_vertices(b)
	assert_eq(vertices_after.size(), vertices_before.size())
	for vertex_index in range(vertices_before.size()):
		_assert_vector_near(
			vertices_after[vertex_index],
			vertices_before[vertex_index],
			"Returning the cursor to its start should restore every vertex"
		)
	assert_true(vs.end_drag().is_empty(), "A returned-to-origin drag should not create undo data")


func test_changed_absolute_drag_returns_undo_snapshots():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo1")
	vs.set_selection([b])
	var original_vertex: Vector3 = vs.get_brush_vertices(b)[0]
	vs.select_vertex("undo1", 0, false)
	vs.begin_drag(b.to_global(original_vertex))
	assert_true(vs.update_drag_absolute(Vector3(2, 0, 0)))
	assert_false(vs.end_drag().is_empty(), "A real geometry change should retain undo data")


func test_rejected_absolute_drag_restores_origin_and_suppresses_undo():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "reject1")
	vs.set_selection([b])
	var vertices_before := vs.get_brush_vertices(b).duplicate()
	vs.select_vertex("reject1", 0, false)
	vs.begin_drag(b.to_global(vertices_before[0]))

	assert_false(vs.update_drag_absolute(Vector3(-40, 0, 0)))
	var vertices_after := vs.get_brush_vertices(b)
	for vertex_index in range(vertices_before.size()):
		_assert_vector_near(
			vertices_after[vertex_index],
			vertices_before[vertex_index],
			"A rejected non-convex update should restore the drag origin"
		)
	assert_true(vs.end_drag().is_empty(), "A rejected update should not create undo data")


func test_absolute_drag_world_delta_handles_rotated_brushes():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "rot1")
	b.rotation = Vector3(0, deg_to_rad(90.0), 0)
	b.force_update_transform()
	vs.set_selection([b])
	var original_vertex: Vector3 = vs.get_brush_vertices(b)[0]
	var original_world := b.to_global(original_vertex)
	vs.select_vertex("rot1", 0, false)
	vs.begin_drag(original_world)

	assert_true(vs.update_drag_absolute(Vector3(2, 0, 0)))
	var selected_world: Vector3 = vs.get_selected_world_positions()[0]
	_assert_vector_near(
		selected_world,
		original_world + Vector3(2, 0, 0),
		"World-space input should remain world-aligned for a rotated brush"
	)


func test_cancel_drag():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "cd1")
	vs.set_selection([b])
	vs.select_vertex("cd1", 0, false)
	var verts_before = vs.get_brush_vertices(b).duplicate()
	vs.begin_drag(Vector3.ZERO)
	assert_true(vs.update_drag_absolute(Vector3(4, 0, 0)))
	assert_false(
		vs.get_selected_world_positions()[0].is_equal_approx(verts_before[0]),
		"The fixture must contain a real change before cancellation"
	)
	vs.cancel_drag()
	var verts_after = vs.get_brush_vertices(b)
	# After cancel, vertices should be restored
	assert_eq(verts_after.size(), verts_before.size())
	for vertex_index in range(verts_before.size()):
		_assert_vector_near(
			verts_after[vertex_index],
			verts_before[vertex_index],
			"Cancel should restore the original vertex positions"
		)


# ===========================================================================
# Screen-to-world drag projection
# ===========================================================================


func test_screen_drag_projects_on_perspective_view_plane():
	var camera := _make_test_camera(Vector3(0, 0, 10))
	var anchor := Vector3.ZERO
	var expected := Vector3(2, 1, 0)
	var result := HFVertexSystem.screen_to_world_drag_delta(
		camera,
		camera.unproject_position(anchor),
		camera.unproject_position(anchor + expected),
		anchor
	)
	assert_true(result.valid)
	_assert_vector_near(result.delta, expected, "Perspective movement should follow the view plane")


func test_screen_drag_projects_on_front_orthographic_view_plane():
	var camera := _make_test_camera(Vector3(0, 0, 10), true)
	var anchor := Vector3.ZERO
	var expected := Vector3(-3, 2, 0)
	var result := HFVertexSystem.screen_to_world_drag_delta(
		camera,
		camera.unproject_position(anchor),
		camera.unproject_position(anchor + expected),
		anchor
	)
	assert_true(result.valid)
	_assert_vector_near(result.delta, expected, "Front orthographic movement should preserve X/Y")


func test_screen_drag_projects_on_side_orthographic_view_plane():
	var camera := _make_test_camera(Vector3(10, 0, 0), true)
	var anchor := Vector3.ZERO
	var expected := Vector3(0, 2, -3)
	var result := HFVertexSystem.screen_to_world_drag_delta(
		camera,
		camera.unproject_position(anchor),
		camera.unproject_position(anchor + expected),
		anchor
	)
	assert_true(result.valid)
	_assert_vector_near(result.delta, expected, "Side orthographic movement should preserve Y/Z")


func test_screen_drag_axis_locks_follow_visible_world_axes():
	var front_camera := _make_test_camera(Vector3(0, 0, 10))
	var side_camera := _make_test_camera(Vector3(10, 0, 0), true)
	var anchor := Vector3.ZERO
	var cases := [
		[front_camera, Vector3(3, 2, 0), HFVertexSystem.DragAxisLock.X, Vector3(3, 0, 0)],
		[front_camera, Vector3(3, -2, 0), HFVertexSystem.DragAxisLock.Y, Vector3(0, -2, 0)],
		[side_camera, Vector3(0, 2, -3), HFVertexSystem.DragAxisLock.Z, Vector3(0, 0, -3)],
	]
	for test_case in cases:
		var camera: Camera3D = test_case[0]
		var cursor_target: Vector3 = test_case[1]
		var result := HFVertexSystem.screen_to_world_drag_delta(
			camera,
			camera.unproject_position(anchor),
			camera.unproject_position(anchor + cursor_target),
			anchor,
			test_case[2]
		)
		assert_true(result.valid)
		_assert_vector_near(result.delta, test_case[3], "Axis lock should remove off-axis motion")


func test_perspective_axis_projection_uses_off_center_anchor_direction():
	var camera := _make_test_camera(Vector3(0, 0, 10))
	var anchor := Vector3(3, 0, 0)
	var expected := Vector3(0, 0, -2)
	var result := HFVertexSystem.screen_to_world_drag_delta(
		camera,
		camera.unproject_position(anchor),
		camera.unproject_position(anchor + expected),
		anchor,
		HFVertexSystem.DragAxisLock.Z
	)
	assert_true(result.valid)
	_assert_vector_near(
		result.delta,
		expected,
		"Perspective axis projection should remain usable away from the view center"
	)


func test_screen_drag_rejects_axis_that_is_head_on_to_view():
	var camera := _make_test_camera(Vector3(0, 0, 10), true)
	var anchor_screen := camera.unproject_position(Vector3.ZERO)
	var result := HFVertexSystem.screen_to_world_drag_delta(
		camera,
		anchor_screen,
		anchor_screen + Vector2(20, 0),
		Vector3.ZERO,
		HFVertexSystem.DragAxisLock.Z
	)
	assert_false(result.valid)
	assert_eq(result.reason, "axis_parallel_to_view")
	assert_eq(result.delta, Vector3.ZERO)


# ===========================================================================
# World positions
# ===========================================================================


func test_get_all_vertex_world_positions():
	var b = _make_box_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "wp1")
	vs.set_selection([b])
	var positions = vs.get_all_vertex_world_positions()
	assert_eq(positions.size(), 8, "Should return 8 vertex entries for a box")
	# All should be unselected
	for entry in positions:
		assert_false(entry.selected)


func test_selected_vertex_world_positions():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "sp1")
	vs.set_selection([b])
	vs.select_vertex("sp1", 0, false)
	var positions = vs.get_selected_world_positions()
	assert_eq(positions.size(), 1)


func test_get_selected_world_positions_marked():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "sm1")
	vs.set_selection([b])
	vs.select_vertex("sm1", 2, false)
	var all_positions = vs.get_all_vertex_world_positions()
	var selected_count := 0
	for entry in all_positions:
		if entry.selected:
			selected_count += 1
	assert_eq(selected_count, 1)


# ===========================================================================
# Vertex key uniqueness
# ===========================================================================


func test_vertex_key_different_for_distinct_points():
	var k1 = vs._vertex_key(Vector3(1.0, 2.0, 3.0))
	var k2 = vs._vertex_key(Vector3(4.0, 5.0, 6.0))
	assert_ne(k1, k2)


func test_vertex_key_same_for_near_identical_points():
	var k1 = vs._vertex_key(Vector3(1.0, 2.0, 3.0))
	var k2 = vs._vertex_key(Vector3(1.0001, 2.0001, 3.0001))
	assert_eq(k1, k2, "Very close points should hash to same key")
