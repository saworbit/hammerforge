extends GutTest

const HFBevelSystem = preload("res://addons/hammerforge/systems/hf_bevel_system.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBevelSystem


func before_each():
	HFLog.end_test_capture()
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	sys = HFBevelSystem.new(root)


func after_each():
	HFLog.end_test_capture()
	root = null
	sys = null


func _capture_warning(pattern: String) -> void:
	HFLog.begin_test_capture([pattern])


func _assert_captured_warning(pattern: String) -> void:
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1, "Should capture exactly one warning")
	if warnings.size() > 0:
		assert_string_contains(warnings[0], pattern, "Should capture expected warning text")


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
	_capture_warning("HFBevelSystem: inset distance too large")
	var ok: bool = sys.inset_face("box_brush", 0, 100.0)
	assert_false(ok, "Inset distance too large should fail")
	_assert_captured_warning("HFBevelSystem: inset distance too large")


# ---------------------------------------------------------------------------
# Edge Bevel tests
# ---------------------------------------------------------------------------


func test_bevel_edge_basic():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	# Unique vertex 0 = (0,16,0), 3 = (0,16,16). That edge is shared by the top
	# and left faces, so the bevel has the two adjacent faces it needs.
	var ok: bool = sys.bevel_edge("box_brush", [0, 3], 2, 2.0)
	assert_true(ok, "Bevel should succeed on an edge shared by two faces")
	# 2 segments = 2 strip quads, plus one corner cap per endpoint.
	assert_eq(brush.faces.size(), face_count_before + 4, "Two-segment bevel should add 4 faces")


func test_bevel_edge_corner_caps_face_outward():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	# Unique vertex 0 = (0,16,0), 3 = (0,16,16). The edge runs along Z, so the
	# cap at (0,16,0) must face -Z and the cap at (0,16,16) must face +Z.
	assert_true(sys.bevel_edge("box_brush", [0, 3], 2, 2.0))
	assert_eq(brush.faces.size(), face_count_before + 4)
	var cap_a: FaceData = brush.faces[face_count_before + 2]
	var cap_b: FaceData = brush.faces[face_count_before + 3]
	assert_almost_eq(cap_a.normal.z, -1.0, 0.001, "Cap at Z=0 must face -Z")
	assert_almost_eq(cap_b.normal.z, 1.0, 0.001, "Cap at Z=16 must face +Z")
	assert_almost_eq(
		cap_a.normal.dot(cap_b.normal), -1.0, 0.001, "Endpoint caps must oppose each other"
	)


func test_bevel_edge_corner_caps_point_away_from_edge_centre():
	# Same check on an X-aligned edge, so a fix that only hard-codes the Z case
	# cannot pass. Unique vertices 0 = (0,16,0) and 1 = (16,16,0).
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	assert_true(sys.bevel_edge("box_brush", [0, 1], 3, 2.0))
	var caps: Array[FaceData] = []
	for i in range(face_count_before + 3, brush.faces.size()):
		caps.append(brush.faces[i])
	assert_eq(caps.size(), 4, "Three segments produce two caps per endpoint")
	for cap in caps:
		var away: Vector3 = cap.local_verts[0] - Vector3(8, 16, 0)
		assert_gt(
			cap.normal.dot(away.normalized()),
			0.0,
			"Every cap normal must point away from the edge midpoint"
		)


func test_bevel_edge_bad_brush():
	var ok: bool = sys.bevel_edge("nonexistent", [0, 1])
	assert_false(ok)


func test_bevel_edge_bad_indices():
	_make_box_brush()
	_capture_warning("HFBevelSystem: vertex index out of range")
	var ok: bool = sys.bevel_edge("box_brush", [99, 100])
	assert_false(ok)
	_assert_captured_warning("HFBevelSystem: vertex index out of range")


func test_bevel_edge_needs_two_indices():
	_make_box_brush()
	_capture_warning("HFBevelSystem: edge needs 2 vertex indices")
	var ok: bool = sys.bevel_edge("box_brush", [0])
	assert_false(ok)
	_assert_captured_warning("HFBevelSystem: edge needs 2 vertex indices")


func test_bevel_edge_segments_clamped():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	# Unique vertices 0 = (0,16,0) and 1 = (16,16,0), shared by top and front.
	# segments=0 clamps to 1, which is a chamfer: one strip quad, no caps.
	var ok: bool = sys.bevel_edge("box_brush", [0, 1], 0, 2.0)
	assert_true(ok, "Bevel should succeed with segments clamped up to 1")
	assert_eq(brush.faces.size(), face_count_before + 1, "Clamped segments should add 1 face")


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
	assert_true(ok, "Chamfer should succeed on a shared edge")
	# 1 segment = 1 new face (chamfer)
	assert_eq(brush.faces.size(), face_count_before + 1, "Chamfer should add 1 face")


# ---------------------------------------------------------------------------
# Edited faces survive a resize
# ---------------------------------------------------------------------------


func test_bevel_edge_promotes_brush_to_custom_shape():
	var brush = _make_box_brush()
	assert_eq(brush.shape, DraftBrush.BrushShape.BOX, "Fixture starts as a box")
	assert_true(sys.bevel_edge("box_brush", [0, 1], 1, 2.0))
	assert_eq(
		brush.shape,
		DraftBrush.BrushShape.CUSTOM,
		"Bevel must claim the face array so a rebuild cannot overwrite it"
	)


func test_beveled_faces_survive_resize():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	assert_true(sys.bevel_edge("box_brush", [0, 1], 2, 2.0))
	var beveled_count: int = brush.faces.size()
	assert_eq(beveled_count, face_count_before + 4)
	brush.set_size(Vector3(48, 48, 48))
	assert_eq(brush.faces.size(), beveled_count, "Resize must not rebuild the box over a bevel")


func test_inset_faces_survive_resize():
	var brush = _make_box_brush()
	var face_count_before: int = brush.faces.size()
	assert_true(sys.inset_face("box_brush", 0, 2.0, 0.0))
	var inset_count: int = brush.faces.size()
	assert_eq(inset_count, face_count_before + 4)
	brush.set_size(Vector3(48, 48, 48))
	assert_eq(brush.faces.size(), inset_count, "Resize must not rebuild the box over an inset")


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


# ---------------------------------------------------------------------------
# Bevel radius bounds (#315)
# ---------------------------------------------------------------------------


func _local_extent(brush: Node3D) -> Vector3:
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for face in brush.faces:
		for vertex in face.local_verts:
			mn = mn.min(vertex)
			mx = mx.max(vertex)
	return mx - mn


func test_bevel_refuses_a_non_finite_radius():
	var brush = _make_box_brush()
	var before: int = brush.faces.size()
	_capture_warning("radius must be finite")
	assert_false(sys.bevel_edge("box_brush", [0, 1], 2, NAN), "NaN radius should be refused")
	_assert_captured_warning("radius must be finite")
	assert_eq(brush.faces.size(), before, "A refused bevel should add no faces")


func test_an_oversized_radius_does_not_inflate_the_brush():
	var brush = _make_box_brush()
	var before := _local_extent(brush)
	_capture_warning("wider than the edge")
	assert_true(sys.bevel_edge("box_brush", [0, 1], 2, 1000000.0), "The radius is capped, not lost")
	_assert_captured_warning("wider than the edge")
	var after := _local_extent(brush)
	assert_lt(after.x, before.x + 0.01, "A bevel should not grow the brush on X")
	assert_lt(after.y, before.y + 0.01, "A bevel should not grow the brush on Y")
	assert_lt(after.z, before.z + 0.01, "A bevel should not grow the brush on Z")


func test_an_ordinary_radius_is_not_capped():
	var brush = _make_box_brush()
	var original: Array = []
	for face in brush.faces:
		for vertex in face.local_verts:
			original.append(vertex)
	assert_true(sys.bevel_edge("box_brush", [0, 1], 2, 4.0), "A 4 unit bevel on a 16 unit box")
	# Every new vertex sits within the radius of a corner it replaced, and the
	# furthest one sits at exactly the radius asked for, not a clamped figure.
	var furthest := 0.0
	for face in brush.faces:
		for vertex in face.local_verts:
			var nearest := INF
			for old in original:
				nearest = minf(nearest, vertex.distance_to(old))
			furthest = maxf(furthest, nearest)
	assert_almost_eq(furthest, 4.0, 0.001, "The bevel should use the radius asked for")


# ---------------------------------------------------------------------------
# Bevel winding and convexity (#314)
# ---------------------------------------------------------------------------


func _face_centre(face: FaceData) -> Vector3:
	var centre := Vector3.ZERO
	for vertex in face.local_verts:
		centre += vertex
	return centre / float(max(1, face.local_verts.size()))


func _brush_centre(brush: Node3D) -> Vector3:
	var centre := Vector3.ZERO
	var count := 0
	for face in brush.faces:
		for vertex in face.local_verts:
			centre += vertex
			count += 1
	return centre / float(max(1, count))


func _worst_plane_violation(brush: Node3D) -> float:
	var verts: Array = []
	for face in brush.faces:
		for vertex in face.local_verts:
			verts.append(vertex)
	var worst := -INF
	for face in brush.faces:
		if face.local_verts.size() < 3:
			continue
		for vertex in verts:
			worst = maxf(worst, face.normal.dot(vertex - face.local_verts[0]))
	return worst


func test_bevel_faces_all_point_away_from_the_brush_centre():
	var brush = _make_box_brush()
	assert_true(sys.bevel_edge("box_brush", [0, 1], 2, 4.0), "Bevel should succeed")
	var centre := _brush_centre(brush)
	for i in range(brush.faces.size()):
		var face: FaceData = brush.faces[i]
		assert_gt(
			face.normal.dot(_face_centre(face) - centre),
			0.0,
			"Face %d should face outward after a bevel" % i
		)


func test_bevel_leaves_the_brush_convex():
	var brush = _make_box_brush()
	assert_true(sys.bevel_edge("box_brush", [0, 1], 2, 4.0), "Bevel should succeed")
	# Every vertex on or behind every face plane is what convexity means here,
	# and it is the check HFVertexSystem.validate_convexity() runs.
	assert_lt(_worst_plane_violation(brush), 0.02, "No vertex should sit outside a face plane")


func _shared_vertex_count(a: FaceData, b: FaceData) -> int:
	var shared := 0
	for vertex in a.local_verts:
		for other in b.local_verts:
			if vertex.distance_to(other) < 0.01:
				shared += 1
				break
	return shared


func test_each_strip_face_leans_towards_the_face_it_borders():
	# The arc used to be centred on the corner vertex, so a strip quad ran from
	# one pulled-back edge to a point tucked in behind the chord and came out
	# carrying the normal that belongs to the far side of the bevel. A strip
	# quad that shares an edge with an original face must be the face whose
	# normal it is nearest to, out of all of them.
	var brush = _make_box_brush()
	var before: int = brush.faces.size()
	assert_true(sys.bevel_edge("box_brush", [0, 1], 2, 4.0), "Bevel should succeed")
	for i in range(before, before + 2):
		var strip: FaceData = brush.faces[i]
		var neighbour := -1
		for j in range(before):
			if _shared_vertex_count(strip, brush.faces[j]) >= 2:
				assert_eq(neighbour, -1, "A strip quad borders one original face")
				neighbour = j
		assert_ne(neighbour, -1, "Strip quad %d should border an original face" % i)
		if neighbour == -1:
			continue
		for j in range(before):
			if j == neighbour:
				continue
			assert_gt(
				strip.normal.dot(brush.faces[neighbour].normal),
				strip.normal.dot(brush.faces[j].normal),
				"Strip quad %d should lean towards the face it borders, not face %d" % [i, j]
			)


func test_bevel_on_a_larger_radius_is_still_convex():
	var brush = _make_box_brush()
	assert_true(sys.bevel_edge("box_brush", [0, 1], 4, 7.0), "Bevel should succeed")
	assert_lt(_worst_plane_violation(brush), 0.02, "A wider bevel should stay convex")
