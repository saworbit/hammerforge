extends GutTest

## Extruding a face by its index, without a camera or a drag. The MCP bridge
## calls this, and the Extrude tool's own brush comes from the same code, so a
## drag and a call make the same brush.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

## Box faces are stored +X, -X, +Y, -Y, +Z, -Z.
const TOP := 2

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.grid_snap = 1.0
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(4, 2, 4),
		"transform": Transform3D(),
		"brush_id": brush_id,
	}
	return root.create_brush_from_info(info) as DraftBrush


func test_the_top_face_makes_a_box_on_top():
	_box("e1")
	var info: Dictionary = root.extrude_face_info("e1", TOP, 3.0)
	assert_false(info.is_empty())
	assert_eq(info["shape"], LevelRoot.BrushShape.BOX)
	assert_eq(info["operation"], CSGShape3D.OPERATION_UNION)
	assert_eq(info["size"], Vector3(4, 3, 4))
	var xform: Transform3D = info["transform"]
	assert_eq(xform.origin, Vector3(0, 2.5, 0))
	assert_ne(str(info.get("brush_id", "")), "", "an id minted for redo to keep")


func test_the_source_brush_is_left_alone():
	var brush := _box("e2")
	var before: Array = brush.serialize_faces()
	root.extrude_face_info("e2", TOP, 3.0)
	assert_eq(brush.serialize_faces(), before)
	assert_eq(root._iter_managed_brush_nodes().size(), 1, "the info is not a brush yet")


func test_a_side_face():
	_box("e3")
	var info: Dictionary = root.extrude_face_info("e3", 0, 2.0)
	assert_eq(info["size"], Vector3(2, 2, 4))
	assert_eq((info["transform"] as Transform3D).origin, Vector3(3, 0, 0))


func test_it_matches_a_drag_on_the_face_from_the_pointer():
	# Through begin_extrude() with a camera looking down at the box, the way a
	# click starts it, rather than through the shared builder from both ends.
	var brush := _box("e4")
	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 20, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var centre := camera.unproject_position(Vector3(0, 1, 0))
	var tool = root.extrude_tool
	assert_true(tool.begin_extrude(camera, centre, tool.Direction.UP), "the click lands on the top")
	assert_eq(tool.source_brush, brush)
	assert_eq(tool.source_face_idx, TOP)
	tool._current_height = 3.0
	var from_drag: Dictionary = tool.end_extrude_info()
	var from_call: Dictionary = root.extrude_face_info("e4", TOP, 3.0)
	assert_eq(from_call["size"], from_drag["size"])
	assert_eq(from_call["transform"], from_drag["transform"])
	assert_eq(from_drag["size"], Vector3(4, 3, 4), "and both are the box on top")


func test_refusals():
	_box("e5")
	var counter: int = root._brush_id_counter
	assert_eq(root.extrude_face_info("e5", TOP, 0.0), {})
	assert_eq(root.extrude_face_info("e5", TOP, -1.0), {})
	assert_eq(root.extrude_face_info("e5", TOP, 300.0), {})
	assert_eq(root.extrude_face_info("e5", TOP, NAN), {})
	assert_eq(root.extrude_face_info("e5", 99, 1.0), {})
	assert_eq(root.extrude_face_info("e5", -1, 1.0), {})
	assert_eq(root.extrude_face_info("nope", TOP, 1.0), {})
	assert_eq(root.extrude_face_info("", TOP, 1.0), {})
	assert_eq(root._brush_id_counter, counter, "no id spent on a refusal")


# ---------------------------------------------------------------------------
# A face that is not square to its brush (#1107)
# ---------------------------------------------------------------------------


func _shape(shape: int, brush_id: String, xform := Transform3D(), sides := 4) -> DraftBrush:
	var info := {
		"shape": shape,
		"size": Vector3(2, 2, 2),
		"transform": xform,
		"brush_id": brush_id,
		"sides": sides,
	}
	return root.create_brush_from_info(info) as DraftBrush


## The first face whose normal is not along one of the brush's own axes.
func _slanted_face(brush: DraftBrush) -> int:
	for i in brush.faces.size():
		var n: Vector3 = brush.faces[i].normal.normalized()
		if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) < 0.99:
			return i
	return -1


## The eight corners of the box `info` makes, in the world.
func _corners(info: Dictionary) -> PackedVector3Array:
	var half: Vector3 = info["size"] * 0.5
	var xform: Transform3D = info["transform"]
	var out := PackedVector3Array()
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				out.append(xform * Vector3(half.x * x, half.y * y, half.z * z))
	return out


## The box stands `distance` off the face, `way` 1 out of the brush or -1 into it:
## every corner is between the face's plane and `distance` from it, and every
## corner of the face is on the box's own face against it.
func _assert_lies_on(brush: DraftBrush, index: int, info: Dictionary, distance: float, way := 1.0):
	assert_false(info.is_empty(), "face %d makes a box" % index)
	if info.is_empty():
		return
	var face = brush.faces[index]
	var normal: Vector3 = face.normal_through(brush.global_transform.basis) * way
	var on_face: Vector3 = brush.global_transform * face.local_verts[0]
	for corner in _corners(info):
		var off := normal.dot(corner - on_face)
		assert_between(off, -0.001, distance + 0.001, "a corner %.3f off the face" % off)
	var into_box: Transform3D = (info["transform"] as Transform3D).affine_inverse()
	var half: Vector3 = info["size"] * 0.5
	for v in face.local_verts:
		var local: Vector3 = into_box * (brush.global_transform * v)
		assert_true(
			absf(local.x) <= half.x + 0.001 and absf(local.z) <= half.z + 0.001,
			"the face's corner %s is under the box" % [local]
		)
		assert_almost_eq(absf(local.y), half.y, 0.001, "on the box's face against it")


func test_a_wedge_slope_gets_a_box_lying_on_it():
	var wedge := _shape(LevelRoot.BrushShape.WEDGE, "s1")
	var slope := _slanted_face(wedge)
	assert_gte(slope, 0, "a wedge has a slope")
	var info: Dictionary = root.extrude_face_info("s1", slope, 1.0)
	_assert_lies_on(wedge, slope, info, 1.0)
	if info.is_empty():
		return
	# Two metres along the slope's level edge, 2.83 down it, one deep.
	var sizes := [info["size"].x, info["size"].y, info["size"].z]
	sizes.sort()
	assert_almost_eq(sizes[0], 1.0, 0.001)
	assert_almost_eq(sizes[1], 2.0, 0.001)
	assert_almost_eq(sizes[2], 2.0 * sqrt(2.0), 0.001)


func test_a_cylinder_side_gets_a_box_lying_on_it():
	var cylinder := _shape(LevelRoot.BrushShape.CYLINDER, "s2", Transform3D(), 8)
	var side := _slanted_face(cylinder)
	assert_gte(side, 0, "an eight sided cylinder has a side off the axes")
	_assert_lies_on(cylinder, side, root.extrude_face_info("s2", side, 0.5), 0.5)


func test_a_slope_on_a_turned_brush_gets_a_box_lying_on_it():
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(5, 1, -3))
	var wedge := _shape(LevelRoot.BrushShape.WEDGE, "s3", xform)
	var slope := _slanted_face(wedge)
	_assert_lies_on(wedge, slope, root.extrude_face_info("s3", slope, 1.5), 1.5)


func test_extruding_a_slope_down_goes_into_the_brush():
	var wedge := _shape(LevelRoot.BrushShape.WEDGE, "s4")
	var slope := _slanted_face(wedge)
	var info: Dictionary = root.extrude_tool.build_extrude_info(wedge, slope, 0.5, -1, "")
	_assert_lies_on(wedge, slope, info, 0.5, -1.0)


func test_a_drag_on_a_slope_shows_and_makes_the_same_box_as_a_call():
	var wedge := _shape(LevelRoot.BrushShape.WEDGE, "s5")
	var slope := _slanted_face(wedge)
	var tool = root.extrude_tool
	assert_true(tool.begin_on_face(wedge, slope, tool.Direction.UP))
	tool._current_height = 1.0
	tool._update_preview(1.0)
	var ghost: DraftBrush = tool._preview_brush
	var from_call: Dictionary = root.extrude_face_info("s5", slope, 1.0)
	assert_not_null(ghost)
	if ghost != null:
		assert_eq(ghost.size, from_call["size"], "the ghost is the box")
		assert_true(ghost.global_transform.is_equal_approx(from_call["transform"]), "where it goes")
	var from_drag: Dictionary = tool.end_extrude_info()
	assert_eq(from_drag["size"], from_call["size"])
	assert_true((from_drag["transform"] as Transform3D).is_equal_approx(from_call["transform"]))


## The box takes the brush's basis, scale and all, so its height was stretched
## with the brush: three times the height asked for, half of it inside.
func test_a_box_stretched_tall_gets_a_box_of_the_height_asked_for_on_top():
	var brush := _box("e6")
	brush.scale = Vector3(1, 3, 1)
	var info: Dictionary = root.extrude_face_info("e6", TOP, 1.0)
	var low := INF
	var high := -INF
	for corner in _corners(info):
		low = minf(low, corner.y)
		high = maxf(high, corner.y)
	assert_almost_eq(low, 3.0, 0.001, "on the top, which the stretch puts at 3")
	assert_almost_eq(high, 4.0, 0.001, "and one high")


# ---------------------------------------------------------------------------
# A face narrower than the grid, or with no area (#1122)
# ---------------------------------------------------------------------------


func test_a_face_narrower_than_the_grid_keeps_its_own_width():
	var pillar := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(0.5, 2, 0.5),
		"transform": Transform3D(),
		"brush_id": "n1",
	}
	root.create_brush_from_info(pillar)
	var info: Dictionary = root.extrude_face_info("n1", TOP, 1.0)
	assert_eq(info.get("size"), Vector3(0.5, 1, 0.5), "as wide as the pillar, not a grid step")
	assert_eq((info.get("transform", Transform3D()) as Transform3D).origin, Vector3(0, 1.5, 0))


func test_a_face_with_no_area_makes_nothing():
	var brush := _box("n2")
	brush.faces[TOP].local_verts = PackedVector3Array(
		[Vector3(-2, 1, 0), Vector3(0, 1, 0), Vector3(2, 1, 0), Vector3(0, 1, 0)]
	)
	var counter: int = root._brush_id_counter
	assert_eq(root.extrude_face_info("n2", TOP, 1.0), {})
	assert_eq(root._brush_id_counter, counter, "no id spent on it")


# ---------------------------------------------------------------------------
# A face that is not a rectangle makes a prism of its own outline (#1123)
# ---------------------------------------------------------------------------


## The face whose normal in the world points most nearly along `direction`.
func _face_facing(brush: DraftBrush, direction: Vector3) -> int:
	var best := -1
	var closest := -INF
	for i in brush.faces.size():
		var along: float = brush.faces[i].normal_through(brush.global_transform.basis).dot(
			direction
		)
		if along > closest:
			closest = along
			best = i
	return best


## The first face with `count` corners.
func _face_with_corners(brush: DraftBrush, count: int) -> int:
	for i in brush.faces.size():
		if brush.faces[i].local_verts.size() == count:
			return i
	return -1


## Every corner of `brush` in the world, each once.
func _world_corners(brush: DraftBrush) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in brush.faces:
		for v in face.local_verts:
			var at: Vector3 = brush.global_transform * v
			if not _has_corner(out, at):
				out.append(at)
	return out


func _has_corner(corners: PackedVector3Array, at: Vector3) -> bool:
	for c in corners:
		if c.distance_to(at) < 0.001:
			return true
	return false


## Every face of `brush` faces away from its middle, as a solid's must.
func _assert_faces_point_out(brush: DraftBrush) -> void:
	var middle := Vector3.ZERO
	var count := 0
	for face in brush.faces:
		for v in face.local_verts:
			middle += v
			count += 1
	middle /= float(maxi(count, 1))
	for i in brush.faces.size():
		var face = brush.faces[i]
		var centre := Vector3.ZERO
		for v in face.local_verts:
			centre += v
		centre /= float(face.local_verts.size())
		assert_gt(face.normal.dot(centre - middle), 0.0, "face %d faces out" % i)


## The brush `info` makes is the face's own outline, and that outline `distance`
## along its normal, `way` 1 out of the brush or -1 into it: no corner more, none
## less. Returns the brush, made in the level.
func _assert_prism_on(
	brush: DraftBrush, index: int, info: Dictionary, distance: float, way := 1.0
) -> DraftBrush:
	assert_eq(info.get("shape"), LevelRoot.BrushShape.CUSTOM, "a prism, not a box")
	if info.get("shape") != LevelRoot.BrushShape.CUSTOM:
		return null
	var made := root.create_brush_from_info(info) as DraftBrush
	assert_not_null(made)
	if made == null:
		return null
	var face = brush.faces[index]
	var offset: Vector3 = face.normal_through(brush.global_transform.basis) * way * distance
	var corners := _world_corners(made)
	assert_eq(corners.size(), face.local_verts.size() * 2, "the outline twice")
	for v in face.local_verts:
		var at: Vector3 = brush.global_transform * v
		assert_true(_has_corner(corners, at), "on the face at %s" % [at])
		assert_true(_has_corner(corners, at + offset), "and %.2f off it" % distance)
	assert_eq(made.faces.size(), face.local_verts.size() + 2, "a side per edge and two caps")
	_assert_faces_point_out(made)
	return made


func test_a_cylinder_cap_makes_a_prism_no_wider_than_the_cylinder():
	var cylinder := _shape(LevelRoot.BrushShape.CYLINDER, "p1", Transform3D(), 16)
	var cap := _face_facing(cylinder, Vector3.UP)
	var made := _assert_prism_on(cylinder, cap, root.extrude_face_info("p1", cap, 1.0), 1.0)
	if made == null:
		return
	assert_eq(made.faces.size(), 18, "16 sides and two caps")
	for at in _world_corners(made):
		assert_lte(Vector2(at.x, at.z).length(), 1.001, "inside the rim")
		assert_between(at.y, 0.999, 2.001, "from the cap to one above it")


func test_a_pyramid_side_makes_a_triangular_prism_on_it():
	var pyramid := _shape(LevelRoot.BrushShape.PYRAMID, "p2")
	var side := _slanted_face(pyramid)
	assert_eq(pyramid.faces[side].local_verts.size(), 3, "a pyramid's side is a triangle")
	_assert_prism_on(pyramid, side, root.extrude_face_info("p2", side, 0.5), 0.5)


func test_a_wedge_end_makes_a_triangular_prism():
	var wedge := _shape(LevelRoot.BrushShape.WEDGE, "p3")
	var end := _face_with_corners(wedge, 3)
	assert_gte(end, 0, "a wedge's end is a triangle")
	_assert_prism_on(wedge, end, root.extrude_face_info("p3", end, 1.0), 1.0)


func test_a_cap_on_a_turned_and_stretched_cylinder_makes_a_prism_on_it():
	var turned := Basis(Vector3.RIGHT, deg_to_rad(90.0)).scaled_local(Vector3(1, 3, 1))
	var cylinder := _shape(
		LevelRoot.BrushShape.CYLINDER, "p4", Transform3D(turned, Vector3(4, 2, -1)), 12
	)
	var cap := _face_facing(cylinder, Vector3.BACK)
	_assert_prism_on(cylinder, cap, root.extrude_face_info("p4", cap, 2.0), 2.0)


func test_extruding_a_cap_down_makes_the_prism_inside_the_brush():
	var cylinder := _shape(LevelRoot.BrushShape.CYLINDER, "p5", Transform3D(), 16)
	var cap := _face_facing(cylinder, Vector3.UP)
	var info: Dictionary = root.extrude_tool.build_extrude_info(cylinder, cap, 0.5, -1, "")
	_assert_prism_on(cylinder, cap, info, 0.5, -1.0)


func test_a_box_face_a_wedge_slope_a_round_side_and_a_square_base_still_make_a_box():
	_box("p6")
	assert_eq(root.extrude_face_info("p6", TOP, 1.0).get("shape"), LevelRoot.BrushShape.BOX)
	var wedge := _shape(LevelRoot.BrushShape.WEDGE, "p7")
	var slope := _slanted_face(wedge)
	assert_eq(root.extrude_face_info("p7", slope, 1.0).get("shape"), LevelRoot.BrushShape.BOX)
	var cylinder := _shape(LevelRoot.BrushShape.CYLINDER, "p8", Transform3D(), 8)
	var side := _slanted_face(cylinder)
	assert_eq(root.extrude_face_info("p8", side, 1.0).get("shape"), LevelRoot.BrushShape.BOX)
	var pyramid := _shape(LevelRoot.BrushShape.PYRAMID, "p9")
	var base := _face_facing(pyramid, Vector3.DOWN)
	assert_eq(root.extrude_face_info("p9", base, 1.0).get("shape"), LevelRoot.BrushShape.BOX)


func test_a_drag_on_a_cap_shows_and_makes_the_same_prism_as_a_call():
	var cylinder := _shape(LevelRoot.BrushShape.CYLINDER, "p10", Transform3D(), 16)
	var cap := _face_facing(cylinder, Vector3.UP)
	var tool = root.extrude_tool
	assert_true(tool.begin_on_face(cylinder, cap, tool.Direction.UP))
	tool._current_height = 1.0
	tool._update_preview(1.0)
	var ghost: DraftBrush = tool._preview_brush
	var from_call: Dictionary = root.extrude_face_info("p10", cap, 1.0)
	assert_not_null(ghost)
	if ghost != null:
		assert_eq(ghost.shape, LevelRoot.BrushShape.CUSTOM, "the ghost is the prism")
		assert_eq(ghost.faces.size(), 18)
		assert_true(ghost.global_transform.is_equal_approx(from_call["transform"]), "where it goes")
	var from_drag: Dictionary = tool.end_extrude_info()
	assert_eq(from_drag.get("shape"), LevelRoot.BrushShape.CUSTOM)
	assert_eq(from_drag.get("faces"), from_call.get("faces"))
	assert_true((from_drag["transform"] as Transform3D).is_equal_approx(from_call["transform"]))


## A redo makes the brush again from the same dictionary, so the same dictionary
## has to make the same brush twice.
func test_the_prism_made_again_from_its_info_is_the_same_brush():
	var cylinder := _shape(LevelRoot.BrushShape.CYLINDER, "p11", Transform3D(), 16)
	var cap := _face_facing(cylinder, Vector3.UP)
	var info: Dictionary = root.extrude_face_info("p11", cap, 1.0)
	var first := root.create_brush_from_info(info) as DraftBrush
	assert_not_null(first)
	if first == null:
		return
	var made_id: String = first.brush_id
	var faces: Array = first.serialize_faces()
	var xform := first.global_transform
	root.delete_brush_by_id(made_id)
	var again := root.create_brush_from_info(info) as DraftBrush
	assert_eq(again.brush_id, made_id)
	assert_eq(again.serialize_faces(), faces)
	assert_true(again.global_transform.is_equal_approx(xform))
