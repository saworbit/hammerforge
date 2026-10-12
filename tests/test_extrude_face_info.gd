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
	var info: Dictionary = root.extrude_tool.build_extrude_info(wedge, slope, 0.5, -1, 1.0, "")
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
