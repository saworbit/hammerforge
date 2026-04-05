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
signal user_message(msg, level)
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
		[Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z),
		 Vector3(half.x, half.y, -half.z), Vector3(half.x, -half.y, -half.z)],
		[Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, half.y, -half.z),
		 Vector3(-half.x, half.y, half.z), Vector3(-half.x, -half.y, half.z)],
		[Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z),
		 Vector3(-half.x, half.y, half.z), Vector3(-half.x, half.y, -half.z)],
		[Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z),
		 Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, -half.y, half.z)],
		[Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z),
		 Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z)],
		[Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		 Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z)]
	]
	var faces: Array[FaceData] = []
	for quad in quads:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces.append(face)
	b.faces = faces
	return b


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
# Drag lifecycle
# ===========================================================================

func test_begin_end_drag():
	vs.begin_drag(Vector3.ZERO)
	assert_true(vs.is_dragging())
	var snapshots = vs.end_drag()
	assert_false(vs.is_dragging())


func test_cancel_drag():
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "cd1")
	vs.set_selection([b])
	vs.select_vertex("cd1", 0, false)
	var verts_before = vs.get_brush_vertices(b).duplicate()
	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(100, 0, 0))
	vs.cancel_drag()
	var verts_after = vs.get_brush_vertices(b)
	# After cancel, vertices should be restored
	assert_eq(verts_after.size(), verts_before.size())


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
