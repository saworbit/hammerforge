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


## The vertex indices on the face the box presents toward `local_dir`, selected
## together. Moving one corner of a quad bows it, so the only plane-preserving
## move on a box is a whole face along its own normal.
func _select_face_toward(brush: DraftBrush, id: String, local_dir: Vector3) -> PackedInt32Array:
	var dir := local_dir.normalized()
	var verts := vs.get_brush_vertices(brush)
	var furthest := -INF
	for v in verts:
		furthest = maxf(furthest, dir.dot(v))
	var indices := PackedInt32Array()
	for i in verts.size():
		if absf(dir.dot(verts[i]) - furthest) < 0.001:
			indices.append(i)
	for i in indices:
		vs.select_vertex(id, i, i != indices[0])
	return indices


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
	# A whole face slid along its own normal. Every face of the brush stays a
	# plane, so this is the move the validator has to keep letting through.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "ok")
	vs.set_selection([brush])
	var moved := _select_face_toward(brush, "ok", Vector3.RIGHT)
	var before: Vector3 = vs.get_brush_vertices(brush)[moved[0]]
	assert_true(vs.move_vertices(Vector3(4, 0, 0)))
	var found := false
	for vertex in vs.get_brush_vertices(brush):
		if vertex.is_equal_approx(before + Vector3(4, 0, 0)):
			found = true
	assert_true(found, "the vertex moved")


# ===========================================================================
# A move that bows a face out of plane is refused (#364)
# ===========================================================================


## The largest distance any of a face's own vertices sits off the plane through
## its first corner.
func _worst_bow(brush: DraftBrush) -> float:
	var worst := 0.0
	for face in brush.faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 4:
			continue
		var normal: Vector3 = face.normal
		for v in verts:
			worst = maxf(worst, absf(normal.dot(v - verts[0])))
	return worst


func test_the_move_that_filed_this_splits_the_faces_it_bends():
	# One corner of a quad, pulled 256 units. The other three corners stay
	# behind the plane through the first three, so the convexity test alone saw
	# nothing wrong and the move committed with the face 62 units off its own
	# plane.
	#
	# The corner goes away from the solid, so the result is a convex spike. The
	# move is along one axis, so only the face perpendicular to it is bent; the
	# other two keep the corner inside their own plane. That one quad is cut
	# into triangles and the move stands.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "bow")
	vs.set_selection([brush])
	var before := vs.get_brush_vertices(brush)[0]
	vs.select_vertex("bow", 0, false)

	assert_true(vs.move_vertices(Vector3(0, -256, 0)), "a spike is still a convex solid")
	assert_almost_eq(_worst_bow(brush), 0.0, 0.001, "every face is a plane again")
	assert_eq(brush.faces.size(), 7, "the one bent quad became two triangles")
	var found := false
	for vertex in vs.get_brush_vertices(brush):
		if vertex.is_equal_approx(before + Vector3(0, -256, 0)):
			found = true
	assert_true(found, "the corner is where it was dragged to")


func test_a_corner_pulled_outward_splits_the_faces_it_bends():
	# The same thing at a size that looks harmless in the viewport. Vertex 0 of
	# the fixture is the (+x, -y, +z) corner, so this is the outward direction.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "pull")
	vs.set_selection([brush])
	var before := vs.get_brush_vertices(brush)[0]
	vs.select_vertex("pull", 0, false)

	assert_true(vs.move_vertices(Vector3(8, -8, 8)), "an outward pull stays a solid")
	assert_almost_eq(_worst_bow(brush), 0.0, 0.001, "every face is a plane again")
	assert_eq(brush.faces.size(), 9, "the three bent quads became six triangles")
	var found := false
	for vertex in vs.get_brush_vertices(brush):
		if vertex.is_equal_approx(before + Vector3(8, -8, 8)):
			found = true
	assert_true(found, "the corner is where it was dragged to")


func test_a_split_face_keeps_the_material_of_the_face_it_came_from():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "mat")
	for face in brush.faces:
		face.material_idx = 3
	vs.set_selection([brush])
	vs.select_vertex("mat", 0, false)
	assert_true(vs.move_vertices(Vector3(8, -8, 8)))
	assert_eq(brush.faces.size(), 9, "the fixture really did split")
	for face in brush.faces:
		assert_eq(face.material_idx, 3, "a triangle carries its quad's material")


func test_a_corner_pushed_inward_is_still_refused():
	# The other direction. A dent is only visible once the bent quad is two
	# triangles, and then it is a non-convex brush, which is refused.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "dent")
	vs.set_selection([brush])
	var before := vs.get_brush_vertices(brush).duplicate()
	vs.select_vertex("dent", 0, false)

	assert_false(vs.move_vertices(Vector3(-8, 8, -8)), "a dent is not a convex solid")
	assert_eq(brush.faces.size(), 6, "the refusal put the quads back")
	var after := vs.get_brush_vertices(brush)
	assert_eq(after.size(), before.size(), "and every vertex")
	for i in before.size():
		assert_true(after[i].is_equal_approx(before[i]), "vertex %d is where it started" % i)


func test_a_bent_displacement_face_is_refused_rather_than_split():
	# A displacement is defined over four corners. Splitting the quad would
	# throw it away, so this is the one bent face that has to be a refusal.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "disp")
	var face := _side_face(brush, Vector3.RIGHT)
	face.displacement = HFDisplacementData.new()
	vs.set_selection([brush])
	var verts := vs.get_brush_vertices(brush)
	var corner := -1
	for i in verts.size():
		if verts[i].is_equal_approx(face.local_verts[0]):
			corner = i
	assert_gt(corner, -1, "the fixture found the corner to move")

	vs.select_vertex("disp", corner, false)
	assert_false(vs.move_vertices(Vector3(8, 0, 0)), "a displacement cannot be split")
	assert_eq(brush.faces.size(), 6, "and nothing was split")
	assert_almost_eq(_worst_bow(brush), 0.0, 0.001, "the face is back on its plane")


func test_a_bent_displacement_face_is_a_failure_even_where_a_split_is_allowed():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "disp2")
	var face := _side_face(brush, Vector3.RIGHT)
	face.displacement = HFDisplacementData.new()
	var verts := face.local_verts
	verts[0] = verts[0] + Vector3(8, 0, 0)
	face.local_verts = verts
	face.ensure_geometry()

	assert_string_contains(vs.check_solid(brush, true), "displacement")
	assert_eq(vs.planarize_faces(brush), 0, "a displacement quad is never split")


func test_a_drag_bends_while_it_runs_and_is_split_when_it_ends():
	# The split happens on commit, not per update: `_write_drag_geometry()`
	# pairs faces with their starting vertices by position in the array, so the
	# array has to keep its shape until the drag is over.
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "dragsplit")
	vs.set_selection([brush])
	var corner: Vector3 = vs.get_brush_vertices(brush)[0]
	vs.select_vertex("dragsplit", 0, false)
	vs.begin_drag(brush.to_global(corner))

	assert_true(vs.update_drag_absolute(Vector3(8, -8, 8)), "the drag runs")
	assert_eq(brush.faces.size(), 6, "nothing is split mid-drag")
	assert_gt(_worst_bow(brush), 1.0, "the preview really is bent")

	assert_false(vs.end_drag().is_empty(), "a committed drag keeps its undo data")
	assert_eq(brush.faces.size(), 9, "the commit split the three bent quads")
	assert_almost_eq(_worst_bow(brush), 0.0, 0.001, "every face is a plane again")


func test_a_drag_that_ends_in_a_dent_is_put_back():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "dragdent")
	vs.set_selection([brush])
	var before := vs.get_brush_vertices(brush).duplicate()
	vs.select_vertex("dragdent", 0, false)
	vs.begin_drag(brush.to_global(before[0]))

	vs.update_drag_absolute(Vector3(-8, 8, -8))
	assert_true(vs.end_drag().is_empty(), "a refused drag leaves no undo data")
	assert_eq(brush.faces.size(), 6, "the quads went back")
	var after := vs.get_brush_vertices(brush)
	assert_eq(after.size(), before.size(), "and every vertex")
	for i in before.size():
		assert_true(after[i].is_equal_approx(before[i]), "vertex %d is where it started" % i)


func test_the_validator_sees_a_bent_face_on_its_own():
	var brush := _make_box_brush(Vector3.ZERO, Vector3(64, 64, 64), "bent")
	assert_true(vs.validate_convexity(brush), "the fixture starts as a solid")
	var face := _side_face(brush, Vector3.RIGHT)
	var verts := face.local_verts
	verts[0] = verts[0] + Vector3(8, 0, 0)
	face.local_verts = verts
	face.ensure_geometry()
	assert_false(vs.validate_convexity(brush), "a face with four corners and no plane")
	assert_string_contains(vs.check_solid(brush), "out of plane")


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
