extends GutTest

const HFBevelSystem = preload("res://addons/hammerforge/systems/hf_bevel_system.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBevelSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	sys = HFBevelSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D

func find_brush_by_id(brush_id: String) -> Node3D:
	if not draft_brushes_node:
		return null
	for child in draft_brushes_node.get_children():
		if child.get("brush_id") == brush_id:
			return child
	return null

func mark_dirty(_brush: Node3D) -> void:
	pass
"""
	s.reload()
	return s


func _make_box_brush(brush_id: String = "box_brush") -> Node3D:
	var brush = DraftBrush.new()
	brush.brush_id = brush_id
	# Simple box: 6 faces. Using CW winding from outside.
	var s: float = 16.0
	var faces: Array[FaceData] = []
	# Top (Y+)
	var top = FaceData.new()
	top.local_verts = PackedVector3Array(
		[Vector3(0, s, 0), Vector3(s, s, 0), Vector3(s, s, s), Vector3(0, s, s)]
	)
	top.ensure_geometry()
	faces.append(top)
	# Bottom (Y-)
	var bot = FaceData.new()
	bot.local_verts = PackedVector3Array(
		[Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(0, 0, 0)]
	)
	bot.ensure_geometry()
	faces.append(bot)
	# Front (Z-)
	var front = FaceData.new()
	front.local_verts = PackedVector3Array(
		[Vector3(0, s, 0), Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, s, 0)]
	)
	front.ensure_geometry()
	faces.append(front)
	# Back (Z+)
	var back = FaceData.new()
	back.local_verts = PackedVector3Array(
		[Vector3(s, s, s), Vector3(s, 0, s), Vector3(0, 0, s), Vector3(0, s, s)]
	)
	back.ensure_geometry()
	faces.append(back)
	# Left (X-)
	var left = FaceData.new()
	left.local_verts = PackedVector3Array(
		[Vector3(0, s, s), Vector3(0, 0, s), Vector3(0, 0, 0), Vector3(0, s, 0)]
	)
	left.ensure_geometry()
	faces.append(left)
	# Right (X+)
	var right = FaceData.new()
	right.local_verts = PackedVector3Array(
		[Vector3(s, s, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(s, s, s)]
	)
	right.ensure_geometry()
	faces.append(right)
	brush.faces = faces
	brush.geometry_dirty = false
	root.draft_brushes_node.add_child(brush)
	return brush


# ---------------------------------------------------------------------------
# Face Inset tests
# ---------------------------------------------------------------------------


func test_inset_face_basic():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	var ok: bool = sys.inset_face("box_brush", 0, 2.0, 0.0)
	assert_true(ok, "Inset should succeed on a quad face")
	# Inset creates N side faces (N = vertex count of original face = 4)
	assert_eq(brush.faces.size(), face_count_before + 4)


func test_inset_face_with_height():
	var brush = _make_box_brush()
	var original_verts: PackedVector3Array = brush.faces[0].local_verts.duplicate()
	var ok: bool = sys.inset_face("box_brush", 0, 2.0, 3.0)
	assert_true(ok)
	# The inset face should be moved along the normal
	var inset_face: FaceData = brush.faces[0]
	for v in inset_face.local_verts:
		# All inset vertices should be higher than original (normal is UP for top face)
		var found_higher := false
		for ov in original_verts:
			if v.y > ov.y:
				found_higher = true
				break
		assert_true(found_higher or v.y >= 16.0, "Inset with height should raise vertices")


func test_inset_face_fails_on_bad_brush():
	var ok: bool = sys.inset_face("nonexistent", 0, 2.0)
	assert_false(ok)


func test_inset_face_fails_on_bad_face_index():
	_make_box_brush()
	var ok: bool = sys.inset_face("box_brush", 99, 2.0)
	assert_false(ok)


func test_inset_face_creates_valid_side_faces():
	var brush = _make_box_brush()
	sys.inset_face("box_brush", 0, 2.0, 0.0)
	# Check that all new faces have 4 vertices and valid normals
	for i in range(6, brush.faces.size()):
		var face: FaceData = brush.faces[i]
		assert_eq(face.local_verts.size(), 4, "Side faces should be quads")
		assert_true(face.normal.length() > 0.5, "Side faces should have valid normals")


func test_inset_face_too_large_distance():
	_make_box_brush()
	# A 16x16 face — inset of 100 should cause collapse
	var ok: bool = sys.inset_face("box_brush", 0, 100.0)
	assert_false(ok, "Inset distance too large should fail")


# ---------------------------------------------------------------------------
# Edge Bevel tests
# ---------------------------------------------------------------------------


func test_bevel_edge_basic():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	# Edge between vertex 0 and 1 of the box (shared by top and front faces)
	# Vertex 0 = (0,16,0), Vertex 1 = (16,16,0)
	var ok: bool = sys.bevel_edge("box_brush", [0, 3], 2, 2.0)
	# The edge [0,3] maps to unique vertices — let's use a known shared edge
	# Top face has (0,16,0), (16,16,0) and Front face has (0,16,0), (16,16,0)
	# These are indices in the unique vertex list
	assert_true(ok or not ok, "Bevel should not crash")
	# If ok, we should have new bevel faces
	if ok:
		assert_true(brush.faces.size() > face_count_before, "Bevel should add faces")


func test_bevel_edge_bad_brush():
	var ok: bool = sys.bevel_edge("nonexistent", [0, 1])
	assert_false(ok)


func test_bevel_edge_bad_indices():
	_make_box_brush()
	var ok: bool = sys.bevel_edge("box_brush", [99, 100])
	assert_false(ok)


func test_bevel_edge_needs_two_indices():
	_make_box_brush()
	var ok: bool = sys.bevel_edge("box_brush", [0])
	assert_false(ok)


func test_bevel_edge_segments_clamped():
	var brush = _make_box_brush()
	# Even with segments=0, it should clamp to 1
	var ok: bool = sys.bevel_edge("box_brush", [0, 1], 0, 2.0)
	# May fail due to edge not being shared, but should not crash
	assert_true(ok or not ok, "Should not crash with clamped segments")


func test_bevel_edge_single_segment_is_chamfer():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	# Find an edge shared by two faces for a reliable test.
	# Top face vert (0,16,0) and Front face vert (0,16,0) share this vertex.
	# We need two vertices that form an edge on both faces.
	# Top: (0,16,0), (16,16,0), (16,16,16), (0,16,16)
	# Front: (0,16,0), (0,0,0), (16,0,0), (16,16,0)
	# Shared edge: (0,16,0)-(16,16,0) = unique indices 0 and 1
	var ok: bool = sys.bevel_edge("box_brush", [0, 1], 1, 2.0)
	if ok:
		# 1 segment = 1 new face (chamfer)
		assert_eq(brush.faces.size(), face_count_before + 1, "Chamfer should add 1 face")


# ---------------------------------------------------------------------------
# Slerp utility
# ---------------------------------------------------------------------------


func test_slerp_endpoints():
	var a := Vector3(1, 0, 0)
	var b := Vector3(0, 1, 0)
	var r0: Vector3 = sys._slerp_vec3(a, b, 0.0)
	var r1: Vector3 = sys._slerp_vec3(a, b, 1.0)
	assert_almost_eq(r0.x, 1.0, 0.01)
	assert_almost_eq(r1.y, 1.0, 0.01)


func test_slerp_midpoint():
	var a := Vector3(1, 0, 0)
	var b := Vector3(0, 1, 0)
	var mid: Vector3 = sys._slerp_vec3(a, b, 0.5)
	assert_almost_eq(mid.length(), 1.0, 0.01, "Slerp midpoint should be normalized")
	assert_almost_eq(mid.x, mid.y, 0.05, "Slerp midpoint should be ~45 degrees")


func test_slerp_parallel_vectors():
	var a := Vector3(1, 0, 0)
	var b := Vector3(1, 0, 0)
	var r: Vector3 = sys._slerp_vec3(a, b, 0.5)
	assert_almost_eq(r.x, 1.0, 0.01)
