extends GutTest
## Draw on a wall: the face under the cursor as the drawing plane (#1401).
##
## A draw always built a flat base and pulled straight up, so a door, a window or
## an alcove was drawn on the floor and then moved and resized into the wall.
## With Draw on Face a draw that starts on a face lays its base on the face's
## plane and pulls its height along the face's normal: a Solid out of the face,
## a Cutout into it. The brush is a box turned so its local up is the normal,
## and the turn must be right handed, or every face of it is inside out with no
## sign until the bake.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDragSystemType = preload("res://addons/hammerforge/systems/hf_drag_system.gd")

const SOLID := CSGShape3D.OPERATION_UNION
const CUTOUT := CSGShape3D.OPERATION_SUBTRACTION
const BOX := 0

var root: LevelRoot
var camera: Camera3D


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.grid_snap = 1.0
	camera = Camera3D.new()
	add_child_autoqfree(camera)


func after_each() -> void:
	root = null
	camera = null


func _box(center: Vector3, size: Vector3, basis := Basis.IDENTITY):
	return root.create_brush_from_info(
		{"shape": BOX, "size": size, "transform": Transform3D(basis, center)}
	)


func _look_west_at(point: Vector3) -> void:
	camera.global_position = point + Vector3(30, 0, 0)
	camera.look_at(point, Vector3.UP)


func _look_down_at(point: Vector3) -> void:
	camera.global_position = point + Vector3(0, 30, 0)
	camera.look_at(point, Vector3.BACK)


func _screen(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


## Drag from `from` to `to`, both world points the camera sees, pull to
## `depth`, and let go. Returns the brush the draw made.
func _draw(from: Vector3, to: Vector3, depth: float, operation := SOLID, on_face := true):
	assert_true(
		root.begin_drag(camera, _screen(from), operation, Vector3.ONE, BOX, 4, on_face),
		"the draw starts"
	)
	root.update_drag(camera, _screen(to))
	var preview: Node3D = root.preview_brush
	var base := root.end_drag_info(camera, _screen(to), Vector3.ONE)
	assert_false(base.get("placed", true), "the first release ends the base")
	# Typed, so the mouse standing still does not take the height back.
	root.input_state.drag_height = depth
	root.input_state.numeric_override = depth
	root.update_drag(camera, _screen(to))
	var preview_transform := (
		preview.global_transform if is_instance_valid(preview) else Transform3D()
	)
	var result := root.end_drag_info(camera, _screen(to), Vector3.ONE)
	assert_true(result.get("placed", false), "the second release places it")
	var brush: Node3D = root.create_brush_from_info(result.get("info", {}))
	assert_not_null(brush)
	if brush:
		assert_almost_eq(
			brush.global_transform.origin,
			preview_transform.origin,
			Vector3.ONE * 0.001,
			"the brush lands where its preview stood"
		)
		assert_true(
			brush.global_transform.basis.is_equal_approx(preview_transform.basis),
			"turned as its preview was"
		)
	return brush


func _world_box(brush: Node) -> AABB:
	return root.brush_system.world_bounds_of(brush)


func _issues_about(brush: Node) -> Array:
	var report: Dictionary = root.validate_level()
	var found: Array = []
	for finding in report.get("findings", []):
		if finding.get("node") == brush:
			found.append(finding.get("message"))
	return found


# ---------------------------------------------------------------------------
# A wall facing +X
# ---------------------------------------------------------------------------


func test_a_draw_on_a_wall_facing_x_lies_on_the_wall_and_grows_along_x():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	var brush = _draw(Vector3(1, -1.2, -0.8), Vector3(1, 1.8, 2.2), 1.0)
	assert_almost_eq(
		brush.global_transform.basis.y, Vector3.RIGHT, Vector3.ONE * 0.0001, "local up is +X"
	)
	var bounds := _world_box(brush)
	assert_almost_eq(bounds.position.x, 1.0, 0.001, "its base lies on the wall")
	assert_almost_eq(bounds.end.x, 2.0, 0.001, "and its depth runs out along +X")
	assert_almost_eq(bounds.position.y, -1.0, 0.001, "the base was dragged up the wall")
	assert_almost_eq(bounds.end.y, 2.0, 0.001)
	assert_almost_eq(bounds.position.z, -1.0, 0.001, "and along it, on grid points")
	assert_almost_eq(bounds.end.z, 2.0, 0.001)


func test_a_cutout_on_the_wall_goes_into_it():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	var cut = _draw(Vector3(1, -1.2, -0.8), Vector3(1, 1.8, 2.2), 2.0, CUTOUT)
	assert_eq(cut.operation, CUTOUT)
	var bounds := _world_box(cut)
	assert_almost_eq(bounds.end.x, 1.0, 0.001, "it starts at the wall's face")
	assert_almost_eq(bounds.position.x, -1.0, 0.001, "and goes the wall's depth into it")


func test_the_brush_is_right_handed_and_validates_clean():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	var brush = _draw(Vector3(1, -1.2, -0.8), Vector3(1, 1.8, 2.2), 1.0)
	assert_gt(brush.global_transform.basis.determinant(), 0.0, "a positive determinant")
	assert_almost_eq(brush.global_transform.basis.determinant(), 1.0, 0.0001, "a pure turn")
	assert_eq(_issues_about(brush), [], "Validate says nothing about it")


func test_every_face_frame_is_right_handed():
	var normals := [
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3.UP,
		Vector3.DOWN,
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3(1, 1, 0).normalized(),
		Vector3(-0.3, 0.2, 0.9).normalized(),
		Vector3(0.0001, -1, 0).normalized(),
	]
	for normal in normals:
		var frame := HFDragSystemType.face_frame(normal, Vector3.ZERO)
		assert_almost_eq(frame.basis.determinant(), 1.0, 0.0001, "right handed facing %s" % normal)
		assert_almost_eq(frame.basis.y, normal, Vector3.ONE * 0.0001, "local up is the normal")
		assert_true(frame.basis.is_equal_approx(frame.basis.orthonormalized()), "and no stretch")


func test_an_off_grid_wall_keeps_the_base_on_the_wall():
	# A wall face at x = 1.3: the grid would round the start to 1, inside it.
	_box(Vector3(0.3, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1.3, 0, 0))
	var brush = _draw(Vector3(1.3, -1.2, -0.8), Vector3(1.3, 1.8, 2.2), 1.0)
	var bounds := _world_box(brush)
	assert_almost_eq(bounds.position.x, 1.3, 0.001, "flush with the face, not with the grid")
	assert_almost_eq(bounds.position.y, -1.0, 0.001, "while its corners still snap")


func test_a_typed_base_runs_along_the_face():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	assert_true(
		root.begin_drag(camera, _screen(Vector3(1, 0.2, 0.2)), SOLID, Vector3.ONE, BOX, 4, true)
	)
	assert_eq(root.input_state.get_drag_dimensions(), Vector3(0, 1, 0), "nothing dragged yet")
	root.input_state.drag_end = root.input_state.drag_origin + Vector3(3, 0, 2)
	assert_eq(
		root.input_state.get_drag_dimensions(),
		Vector3(3, 1, 2),
		"the size reads in the face's own axes, as a typed size is given"
	)
	root.cancel_drag()


# ---------------------------------------------------------------------------
# A slanted face
# ---------------------------------------------------------------------------


func test_on_a_slanted_face_the_base_is_flush_with_it():
	var tilt := Basis(Vector3.BACK, deg_to_rad(30.0))
	var ramp = _box(Vector3(0, 0, 0), Vector3(8, 2, 8), tilt)
	var top: Vector3 = tilt * Vector3.UP
	var plane := Plane(top, top * 1.0)
	var start := plane.project(Vector3(0.37, 5, 0.41))
	var finish := plane.project(Vector3(2.6, 5, 2.3))
	_look_down_at(start)
	var described: Dictionary = root.drag_system.draw_start(camera, _screen(start), true)
	assert_same(described.get("brush"), ramp, "the draw starts on the ramp")
	assert_eq(int(described.get("kind")), HFDragSystemType.StartKind.FACE)
	assert_almost_eq(described["point"], start, Vector3.ONE * 0.001, "at the click itself")
	var brush = _draw(start, finish, 1.0)
	assert_almost_eq(brush.global_transform.basis.y, top, Vector3.ONE * 0.0001, "up is the normal")
	var half: Vector3 = brush.size * 0.5
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, -1, 1), Vector3(1, -1, 1)]:
		var world: Vector3 = brush.global_transform * (half * corner)
		assert_almost_eq(
			plane.distance_to(world), 0.0, 0.001, "base corner %s on the face" % corner
		)
	assert_almost_eq(brush.size.x, roundf(brush.size.x), 0.001, "grid steps along the face")
	assert_almost_eq(brush.size.z, roundf(brush.size.z), 0.001, "both ways")
	assert_gt(brush.global_transform.basis.determinant(), 0.0)
	assert_eq(_issues_about(brush), [])


# ---------------------------------------------------------------------------
# Off, or over empty space, a draw is what it was
# ---------------------------------------------------------------------------


func test_with_the_toggle_off_a_wall_draw_builds_flat():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	assert_true(root.begin_drag(camera, _screen(Vector3(1, 0.2, 0.2)), SOLID, Vector3.ONE, BOX))
	assert_false(root.input_state.drag_on_face, "off is an ordinary draw")
	assert_almost_eq(root.input_state.drag_origin, Vector3(1, 0, 0), Vector3.ONE * 0.001)
	root.input_state.drag_end = Vector3(3, 0, 2)
	root.end_drag_info(camera, Vector2.ZERO, Vector3.ONE)
	root.input_state.drag_height = 1.0
	var info: Dictionary = root.end_drag_info(camera, Vector2.ZERO, Vector3.ONE).get("info", {})
	assert_false(info.has("transform"), "no turn")
	assert_almost_eq(info["center"], Vector3(2, 0.5, 1), Vector3.ONE * 0.001, "flat, growing up")
	assert_eq(info.get("draw_origin"), Vector3(1, 0, 0))


func test_on_over_empty_space_is_an_ordinary_draw():
	_look_down_at(Vector3(5.3, 0, 5.3))
	assert_true(
		root.begin_drag(camera, _screen(Vector3(5.3, 0, 5.3)), SOLID, Vector3.ONE, BOX, 4, true)
	)
	assert_false(root.input_state.drag_on_face, "no face, no face plane")
	assert_almost_eq(root.input_state.drag_origin, Vector3(5, 0, 5), Vector3.ONE * 0.001)
	root.cancel_drag()


func test_a_wall_draw_leaves_the_drawing_plane_alone():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	var plane_before: Vector3 = root.grid_plane_origin
	_draw(Vector3(1, 1.2, -0.8), Vector3(1, 3.8, 2.2), 1.0)
	assert_eq(root.grid_plane_origin, plane_before, "the floor grid stays on the floor")


func test_cancelling_a_face_draw_leaves_no_face_state():
	_box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0, 0))
	assert_true(
		root.begin_drag(camera, _screen(Vector3(1, 0.2, 0.2)), SOLID, Vector3.ONE, BOX, 4, true)
	)
	assert_true(root.input_state.drag_on_face)
	root.cancel_drag()
	assert_false(root.input_state.drag_on_face)
	assert_eq(root.input_state.drag_frame, Transform3D.IDENTITY)
	assert_null(root.preview_brush, "and no preview")
