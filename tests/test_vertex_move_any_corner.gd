extends GutTest

## A vertex move is judged by the solid it leaves, whichever corner it moves
## (#1561). A bent face used to be cut, and judged, from the first corner in its
## list, so which way it folded depended on where the moved corner fell in that
## list: one corner of a box moved straight up was refused on half the box and
## taken on the rest. Each path that moves a vertex is run here on every corner:
## a typed move, a drag and Snap to Grid.

const HFVertexSystem = preload("res://addons/hammerforge/systems/hf_vertex_system.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const BrushShape = LevelRootScript.BrushShape

## The eight corners of a 4 x 4 x 4 box at the origin.
const CORNERS := [
	Vector3(2, 2, 2),
	Vector3(2, 2, -2),
	Vector3(2, -2, 2),
	Vector3(2, -2, -2),
	Vector3(-2, 2, 2),
	Vector3(-2, 2, -2),
	Vector3(-2, -2, 2),
	Vector3(-2, -2, -2),
]

var root: LevelRoot
var vs: HFVertexSystem
var said: Array[String] = []


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	vs = root.vertex_system
	said = []
	root.user_message.connect(func(text: String, _level: int): said.append(text))


func after_each():
	root = null
	vs = null


func _box(id: String, size := Vector3(4, 4, 4)) -> DraftBrush:
	var brush := root.create_brush_from_info({"size": size, "brush_id": id}) as DraftBrush
	vs.set_selection([brush])
	return brush


## An eight-sided cylinder 4 across and 4 tall at the origin.
func _cylinder(id: String) -> DraftBrush:
	var info := {"shape": BrushShape.CYLINDER, "size": Vector3(4, 4, 4), "sides": 8, "brush_id": id}
	var brush := root.create_brush_from_info(info) as DraftBrush
	vs.set_selection([brush])
	return brush


## Select the vertex of `brush` at `point`, alone. Returns its index.
func _select_at(brush: DraftBrush, id: String, point: Vector3) -> int:
	var verts := vs.get_brush_vertices(brush)
	for i in verts.size():
		if verts[i].is_equal_approx(point):
			vs.select_vertex(id, i, false)
			return i
	return -1


func _has_vertex(brush: DraftBrush, point: Vector3) -> bool:
	for v in vs.get_brush_vertices(brush):
		if v.is_equal_approx(point):
			return true
	return false


## What is wrong with `brush` as a solid, measured without the vertex system:
## a face off its own plane, a corner in front of a plane, or a face wound into
## the solid. "" for a convex solid of planar faces wound clockwise from outside.
func _solid_problem(brush: DraftBrush) -> String:
	var interior := HFConvexClip.interior_point(brush.faces)
	for face in brush.faces:
		var centre := Vector3.ZERO
		for v in face.local_verts:
			centre += v
			if absf(face.normal.dot(v - face.local_verts[0])) > 0.001:
				return "a face is off its own plane: %s" % face.local_verts
		centre /= float(face.local_verts.size())
		if face.normal.dot(centre - interior) <= 0.0:
			return "a face is wound into the solid: %s" % face.local_verts
	if not HFConvexClip.is_convex_solid(brush.faces, interior):
		return "a corner is in front of a face"
	return ""


## The faces as sets of corners, in an order that does not depend on the array.
func _face_sets(brush: DraftBrush) -> Array:
	var sets: Array = []
	for face in brush.faces:
		var keys: Array = []
		for v in face.local_verts:
			keys.append("%.3f,%.3f,%.3f" % [v.x, v.y, v.z])
		keys.sort()
		sets.append(",".join(keys))
	sets.sort()
	return sets


func _said(text: String) -> bool:
	for line in said:
		if line.contains(text):
			return true
	return false


# ===========================================================================
# Moves that keep the box convex are taken, whichever corner
# ===========================================================================


func test_a_corner_moved_up_is_taken(corner = use_parameters(CORNERS)):
	var brush := _box("up")
	assert_gt(_select_at(brush, "up", corner), -1, "%s: the fixture found the corner" % corner)

	assert_true(vs.move_vertices(Vector3.UP), "%s: moving it up keeps the box convex" % corner)
	assert_true(_has_vertex(brush, corner + Vector3.UP), "%s: the corner moved" % corner)
	assert_eq(_solid_problem(brush), "", "%s: the result is a convex solid" % corner)
	assert_eq(vs.check_solid(brush), "", "%s: and the vertex system agrees" % corner)
	assert_eq(said, [] as Array[String], "%s: nothing was refused" % corner)


func test_a_corner_pushed_in_short_of_its_neighbours_is_taken(corner = use_parameters(CORNERS)):
	# A quarter of the way to the middle. The corner stays outside the plane
	# through its three neighbours, so the three faces it bends each fold
	# outward along the diagonal that does not touch it.
	var brush := _box("in")
	_select_at(brush, "in", corner)

	assert_true(vs.move_vertices(-corner * 0.25), "%s: still a convex solid" % corner)
	assert_true(_has_vertex(brush, corner * 0.75), "%s: the corner moved" % corner)
	assert_eq(_solid_problem(brush), "", "%s: the result is a convex solid" % corner)


func test_a_cylinder_cap_corner_raised_is_taken(n = use_parameters([0, 1, 2, 3, 4, 5, 6, 7])):
	# The same thing on a face with eight corners: raising one bends the cap
	# into a cone around it, which a fan from any other corner turns inside out.
	var brush := _cylinder("cyl")
	var cap: Array = []
	for v in vs.get_brush_vertices(brush):
		if v.y > 1.0:
			cap.append(v)
	assert_eq(cap.size(), 8, "the fixture has an eight-sided cap")
	var corner: Vector3 = cap[n]
	_select_at(brush, "cyl", corner)

	assert_true(vs.move_vertices(Vector3.UP), "cap corner %d: raising it keeps the solid" % n)
	assert_true(_has_vertex(brush, corner + Vector3.UP), "cap corner %d moved" % n)
	assert_eq(_solid_problem(brush), "", "cap corner %d: a convex solid" % n)


func test_corners_still_in_one_plane_stay_one_face():
	# One corner of an eight-sided cap pressed down. Seven corners keep their
	# plane, so the cap becomes that seven-cornered face and one triangle, not a
	# fan of six slivers.
	var brush := _cylinder("cap")
	var corner := Vector3.ZERO
	for v in vs.get_brush_vertices(brush):
		if v.y > 1.0:
			corner = v
			break
	var faces_before := brush.faces.size()
	_select_at(brush, "cap", corner)

	assert_true(vs.move_vertices(Vector3.DOWN), "pressing a cap corner in keeps the solid")
	assert_eq(_solid_problem(brush), "", "a convex solid")
	assert_eq(brush.faces.size(), faces_before + 1, "the cap became two faces")
	var flat: Array = []
	for face in brush.faces:
		if face.normal.y > 0.999:
			flat.append(face.local_verts.size())
	assert_eq(flat, [7], "one of them has the seven corners still in the cap's plane")


# ===========================================================================
# Moves that would leave it non-convex are refused, whichever corner
# ===========================================================================


func test_a_corner_pushed_in_past_its_neighbours_is_refused(corner = use_parameters(CORNERS)):
	# Three quarters of the way to the middle, past the plane through the
	# corner's three neighbours: a dent, however the faces are cut.
	var brush := _box("dent")
	var faces_before := _face_sets(brush)
	_select_at(brush, "dent", corner)

	assert_false(vs.move_vertices(-corner * 0.75), "%s: a dent is refused" % corner)
	assert_true(_said("non-convex"), "%s: and the mapper is told why: %s" % [corner, said])
	assert_eq(_face_sets(brush), faces_before, "%s: the box is as it was" % corner)


func test_a_corner_swung_over_the_far_corner_is_refused(corner = use_parameters(CORNERS)):
	# Across its own face to just beyond the corner opposite it there. The two
	# side faces it leaves are twisted so far that, whichever way either is
	# cut, part of the box is in front of it.
	var brush := _box("twist")
	var faces_before := _face_sets(brush)
	_select_at(brush, "twist", corner)
	var delta := Vector3(-2.0 * corner.x, signf(corner.y), -2.0 * corner.z)

	assert_false(vs.move_vertices(delta), "%s: a twisted brush is refused" % corner)
	assert_true(_said("non-convex"), "%s: and the mapper is told why: %s" % [corner, said])
	assert_eq(_face_sets(brush), faces_before, "%s: the box is as it was" % corner)


# ===========================================================================
# Every path that moves a vertex comes to the same answer
# ===========================================================================


func test_a_drag_and_a_typed_move_agree(corner = use_parameters(CORNERS)):
	var typed := _box("typed")
	_select_at(typed, "typed", corner)
	assert_true(vs.move_vertices(Vector3.UP), "%s: the typed move is taken" % corner)

	var dragged := _box("dragged")
	_select_at(dragged, "dragged", corner)
	vs.begin_drag(dragged.to_global(corner))
	assert_true(vs.update_drag_absolute(Vector3.UP), "%s: each step of the drag is taken" % corner)
	assert_false(vs.end_drag().is_empty(), "%s: and so is its release" % corner)

	assert_eq(_solid_problem(dragged), "", "%s: the drag left a convex solid" % corner)
	assert_eq(_face_sets(dragged), _face_sets(typed), "%s: cut the same way" % corner)


func test_a_dent_dragged_in_is_refused_on_every_corner(corner = use_parameters(CORNERS)):
	var brush := _box("dragdent")
	var faces_before := _face_sets(brush)
	_select_at(brush, "dragdent", corner)
	vs.begin_drag(brush.to_global(corner))
	vs.update_drag_absolute(-corner * 0.75)

	assert_true(vs.end_drag().is_empty(), "%s: a dent leaves no undo data" % corner)
	assert_eq(_face_sets(brush), faces_before, "%s: the box is as it was" % corner)


func test_snap_to_grid_takes_a_corner_wherever_it_is(corner = use_parameters(CORNERS)):
	# A box 3.2 tall has its corners 0.4 inside the whole-unit grid line above
	# or below them, so snapping one corner moves it straight out by 0.4.
	var brush := _box("snap", Vector3(4, 3.2, 4))
	var start := Vector3(corner.x, corner.y * 0.8, corner.z)
	assert_gt(_select_at(brush, "snap", start), -1, "%s: the fixture found the corner" % corner)

	assert_false(vs.snap_selected_to_grid(1.0).is_empty(), "%s: the snap is taken" % corner)
	assert_true(_has_vertex(brush, corner), "%s: the corner is on the grid" % corner)
	assert_eq(_solid_problem(brush), "", "%s: the result is a convex solid" % corner)


# ===========================================================================
# What a split keeps
# ===========================================================================


func test_the_split_does_not_depend_on_where_the_face_starts():
	# The top of the box with one corner raised, and with it lowered, wound
	# clockwise from above, started at each of its four corners in turn.
	for raised in [Vector3(2, 3, 2), Vector3(2, 1, 2)]:
		var ring: Array = [Vector3(2, 2, -2), raised, Vector3(-2, 2, 2), Vector3(-2, 2, -2)]
		var answers: Array = []
		for start in 4:
			var verts := PackedVector3Array()
			for i in 4:
				verts.append(ring[(start + i) % 4])
			var pieces: Array = []
			for piece in HFVertexSystem.outward_pieces(verts):
				var keys: Array = []
				for i in piece:
					keys.append(str(verts[i]))
				keys.sort()
				pieces.append(",".join(keys))
			pieces.sort()
			answers.append(pieces)
		for start in range(1, 4):
			assert_eq(answers[start], answers[0], "%s: started at corner %d" % [raised, start])
		assert_eq(answers[0].size(), 2, "%s: two triangles" % raised)
		var through_moved := 0
		for piece in answers[0]:
			if piece.contains(str(raised)):
				through_moved += 1
		# Raised, the fold is a ridge along the diagonal through the moved
		# corner; lowered, it is the other diagonal, with the corner on one side.
		var expected := 2 if raised.y > 2.0 else 1
		assert_eq(through_moved, expected, "%s: folded outward" % raised)


func test_a_split_face_keeps_its_uvs_at_their_corners():
	var brush := _box("uv")
	var top: FaceData = null
	for face in brush.faces:
		if face.normal.y > 0.9:
			top = face
	var laid: Dictionary = {}
	var uvs := PackedVector2Array()
	for i in top.local_verts.size():
		uvs.append(Vector2(i, i * 2 + 1))
		laid[str(top.local_verts[i])] = uvs[i]
	top.custom_uvs = uvs
	_select_at(brush, "uv", Vector3(2, 2, 2))
	laid[str(Vector3(2, 3, 2))] = laid[str(Vector3(2, 2, 2))]

	assert_true(vs.move_vertices(Vector3.UP))
	var pieces := 0
	for face in brush.faces:
		if face.normal.y < 0.5:
			continue
		pieces += 1
		assert_eq(face.custom_uvs.size(), face.local_verts.size(), "the piece has its UVs")
		for i in face.local_verts.size():
			assert_eq(
				face.custom_uvs[i], laid[str(face.local_verts[i])], "each corner keeps its UV"
			)
	assert_eq(pieces, 2, "the top was cut in two")
