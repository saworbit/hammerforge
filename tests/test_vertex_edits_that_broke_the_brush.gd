extends GutTest

## Three things a vertex edit could do that nothing refused or measured (#365,
## #366, #367). The convexity check is written as a lower bound, so it cannot see
## a NaN; it allows a brush with fewer than four faces, so it cannot see a brush
## the merge emptied; and a split leaves three collinear vertices at the front of
## a face, which the old first-three-vertices normal read as no normal at all.

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


func _side_face(brush: DraftBrush, axis_normal: Vector3) -> FaceData:
	for face in brush.faces:
		if face.normal.dot(axis_normal) > 0.9:
			return face
	return null


# ===========================================================================
# A non-finite move is refused (#365)
# ===========================================================================


func test_a_non_finite_vertex_move_is_refused():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "nan")
	vs.set_selection([brush])
	vs.select_vertex("nan", 0, false)
	for delta in [Vector3(NAN, 0, 0), Vector3(0, INF, 0), Vector3(-INF, NAN, INF)]:
		assert_false(vs.move_vertices(delta), "%s is not a delta" % delta)
	for vertex in vs.get_brush_vertices(brush):
		assert_true(vertex.is_finite(), "no vertex was poisoned")
	for face in brush.faces:
		assert_true(face.normal.is_finite(), "no face normal was poisoned")


func test_an_ordinary_vertex_move_still_lands():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "ok")
	vs.set_selection([brush])
	var before := vs.get_brush_vertices(brush)[0]
	vs.select_vertex("ok", 0, false)
	assert_true(vs.move_vertices(Vector3(4, 0, 0)))
	var found := false
	for vertex in vs.get_brush_vertices(brush):
		if vertex.is_equal_approx(before + Vector3(4, 0, 0)):
			found = true
	assert_true(found, "the vertex moved")


func test_a_non_finite_drag_update_is_refused():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "drag")
	vs.set_selection([brush])
	vs.select_vertex("drag", 0, false)
	vs.begin_drag(Vector3.ZERO)
	assert_false(vs.update_drag_absolute(Vector3(NAN, 0, 0)))
	for vertex in vs.get_brush_vertices(brush):
		assert_true(vertex.is_finite(), "the drag wrote nothing")
	vs.cancel_drag()


# ===========================================================================
# A merge that empties the brush is refused (#366)
# ===========================================================================


func test_merging_every_vertex_of_a_box_is_refused():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "all")
	vs.set_selection([brush])
	var all_indices := PackedInt32Array()
	for i in vs.get_brush_vertices(brush).size():
		all_indices.append(i)
	assert_eq(all_indices.size(), 8, "a box has eight vertices")

	assert_false(vs.merge_vertices("all", all_indices), "that is not a solid")
	assert_eq(brush.faces.size(), 6, "the brush still has its faces")
	assert_eq(vs.get_brush_vertices(brush).size(), 8, "and its vertices")


func test_merging_one_face_worth_of_vertices_is_refused():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "face")
	vs.set_selection([brush])
	var verts := vs.get_brush_vertices(brush)
	var top := PackedInt32Array()
	for i in verts.size():
		if verts[i].y > 0.0:
			top.append(i)
	assert_eq(top.size(), 4, "four vertices on the top face")
	# Five faces survive, which the `faces.size() < 4` guard in
	# validate_convexity() lets through, so this is refused for being non-convex
	# rather than for being empty. Either way the brush is not left broken.
	vs.merge_vertices("face", top)
	for face in brush.faces:
		assert_gt(face.local_verts.size(), 2, "no face was left with an edge")


func test_the_convexity_check_cannot_be_what_refuses_an_empty_merge():
	# Why the guard is in merge_vertices() and not in the validator: a brush with
	# no faces passes validate_convexity(), because the `faces.size() < 4`
	# early-out is there to let a genuinely degenerate intermediate through. That
	# is exactly the case an all-vertex merge produces.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "empty")
	brush.faces = [] as Array[FaceData]
	assert_true(vs.validate_convexity(brush), "the validator says nothing about an empty brush")


# ===========================================================================
# A split edge leaves a face that still knows which way it points (#367)
# ===========================================================================


func test_splitting_an_edge_does_not_turn_a_wall_into_a_floor():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "split")
	vs.set_selection([brush])
	var normals_before: Array = []
	for face in brush.faces:
		normals_before.append(face.normal)

	var edges := vs.get_brush_edges(brush)
	assert_gt(edges.size(), 0, "the box has edges")
	assert_true(vs.split_edge("split", edges[0]), "the split was accepted")

	assert_eq(vs.get_brush_vertices(brush).size(), 9, "one vertex was added")
	assert_eq(brush.faces.size(), 6, "no face was added or lost")
	for i in brush.faces.size():
		assert_true(
			brush.faces[i].normal.is_equal_approx(normals_before[i]),
			"face %d still points where it did: %s" % [i, brush.faces[i].normal]
		)


func test_a_split_brush_is_still_convex():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "convex")
	vs.set_selection([brush])
	var edges := vs.get_brush_edges(brush)
	assert_true(vs.split_edge("convex", edges[0]))
	assert_true(
		vs.validate_convexity(brush), "a midpoint on the hull does not make the brush non-convex"
	)


func test_a_collinear_run_does_not_stop_a_face_reporting_its_normal():
	# The shape `split_edge()` produces: a square with a midpoint on the first
	# edge, so local_verts[0..2] are collinear by construction.
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[
			Vector3(-16, 0, -16),
			Vector3(0, 0, -16),
			Vector3(16, 0, -16),
			Vector3(16, 0, 16),
			Vector3(-16, 0, 16)
		]
	)
	face.ensure_geometry()
	assert_almost_eq(absf(face.normal.y), 1.0, 0.001, "this face is flat in Y: %s" % face.normal)


func test_a_tiny_face_still_reports_its_normal():
	# The bug the previous comment in _compute_normal() was about: an absolute
	# floor on the raw cross product called every small face degenerate.
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(0.01, 0, 0), Vector3(0.01, 0, 0.01), Vector3(0, 0, 0.01)]
	)
	face.ensure_geometry()
	assert_almost_eq(absf(face.normal.y), 1.0, 0.001, "a 0.01-unit face has a normal too")
