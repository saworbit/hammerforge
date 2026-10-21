extends GutTest
## Where a draw will land, shown before the click (#1400).
##
## A draw starts at the first thing the ray meets: a physics body, a draft face,
## then the grid. Nothing said which before the click, so over a busy area the
## first sign of the wrong one was a brush in the wrong place. The hover preview
## reads `HFDragSystem.draw_start()`, the answer `begin_drag()` starts from, so
## these tests pin the two together for the floor, a raised face, a wall and
## empty space.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDragSystemType = preload("res://addons/hammerforge/systems/hf_drag_system.gd")
const HFDrawHoverType = preload("res://addons/hammerforge/systems/hf_draw_hover.gd")
const GridShader = preload("res://addons/hammerforge/editor_grid.gdshader")
const HFPolygonToolType = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const HFPathToolType = preload("res://addons/hammerforge/hf_path_tool.gd")

const Kind = HFDragSystemType.StartKind

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
	_stand_in_for_the_editor_grid()


func after_each() -> void:
	root = null
	camera = null


## The grid is built only in the editor. Its material is what the preview
## writes the cursor to, so a test stands one in.
func _stand_in_for_the_editor_grid() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "EditorGrid"
	root.add_child(grid)
	root.grid_mesh = grid
	root.grid_material = ShaderMaterial.new()
	root.grid_material.shader = GridShader
	root.grid_plane_origin = root.global_position
	root.grid_axis_preference = root.AxisLock.Y


func _screen() -> Vector2:
	return camera.get_viewport().get_visible_rect().size * 0.5


func _look_down_at(point: Vector3) -> void:
	camera.global_position = point + Vector3(0, 30, 0)
	camera.look_at(point, Vector3.BACK)


func _look_west_at(point: Vector3) -> void:
	camera.global_position = point + Vector3(30, 0, 0)
	camera.look_at(point, Vector3.UP)


func _box(center: Vector3, size: Vector3) -> Node:
	return root.create_brush_from_info({"shape": 0, "size": size, "center": center})


## Show the preview where the camera points, as the plugin does on a move.
func _hover() -> Dictionary:
	var start: Dictionary = root.drag_system.draw_start(camera, _screen())
	root.draw_hover.show_start(start)
	return root.draw_hover.shown


## Where a click there starts the draw. The drag is cancelled, so it leaves
## nothing behind.
func _click_origin() -> Vector3:
	assert_true(root.begin_drag(camera, _screen(), 0, Vector3.ONE, 0), "the click starts a draw")
	var origin: Vector3 = root.input_state.drag_origin
	root.cancel_drag()
	return origin


func _face_normal(start: Dictionary) -> Vector3:
	var brush = start.get("brush")
	var face: FaceData = brush.faces[int(start.get("face_idx"))]
	face.ensure_geometry()
	return face.normal_through(brush.global_basis)


func _cursor_on_grid() -> Variant:
	if not bool(root.grid_material.get_shader_parameter("cursor_visible")):
		return null
	return root.grid_material.get_shader_parameter("cursor_point")


# ---------------------------------------------------------------------------
# One look per surface, and the click starts where the preview says
# ---------------------------------------------------------------------------


func test_the_floor_level_with_the_grid():
	var floor_brush := _box(Vector3(0, -1, 0), Vector3(8, 2, 8))
	_look_down_at(Vector3(0.3, 0, 0.3))
	var shown := _hover()
	assert_eq(int(shown.get("kind")), Kind.LEVEL, "a floor at the grid's height")
	assert_same(shown.get("brush"), floor_brush, "its top face is the one under the cursor")
	assert_almost_eq(_face_normal(shown), Vector3.UP, Vector3.ONE * 0.001)
	assert_true(root.draw_hover.shows_face(), "the face is tinted")
	assert_almost_eq(shown["point"], Vector3.ZERO, Vector3.ONE * 0.001, "snapped")
	assert_eq(_click_origin(), shown["point"], "the click starts where the preview said")


func test_a_raised_top_face():
	var table := _box(Vector3(0, 1, 0), Vector3(8, 2, 8))
	_look_down_at(Vector3(0.3, 2, 0.3))
	var shown := _hover()
	assert_eq(int(shown.get("kind")), Kind.RAISED, "flat, at another height")
	assert_same(shown.get("brush"), table)
	assert_almost_eq(_face_normal(shown), Vector3.UP, Vector3.ONE * 0.001)
	assert_almost_eq(shown["point"], Vector3(0, 2, 0), Vector3.ONE * 0.001)
	assert_eq(_click_origin(), shown["point"], "the click starts on the table")


func test_a_wall():
	var wall := _box(Vector3(0, 0, 0), Vector3(2, 8, 8))
	_look_west_at(Vector3(1, 0.3, 0.3))
	var shown := _hover()
	assert_eq(int(shown.get("kind")), Kind.SLOPED, "not flat")
	assert_same(shown.get("brush"), wall)
	assert_almost_eq(_face_normal(shown), Vector3.RIGHT, Vector3.ONE * 0.001)
	assert_almost_eq(shown["point"], Vector3(1, 0, 0), Vector3.ONE * 0.001)
	assert_eq(_click_origin(), shown["point"], "the click starts halfway up the wall")


func test_empty_space_shows_no_face():
	_look_down_at(Vector3(5.3, 0, 5.3))
	var shown := _hover()
	assert_eq(int(shown.get("kind")), Kind.GRID, "the draw starts on the grid")
	assert_null(shown.get("brush"), "no face under the cursor")
	assert_false(root.draw_hover.shows_face(), "so none is tinted")
	assert_almost_eq(shown["point"], Vector3(5, 0, 5), Vector3.ONE * 0.001)
	assert_eq(_click_origin(), shown["point"])


func test_the_four_looks_differ():
	var colors := {}
	for kind in [Kind.LEVEL, Kind.RAISED, Kind.SLOPED, Kind.FACE]:
		colors[HFDrawHoverType.color_for(kind)] = kind
	assert_eq(
		colors.size(), 4, "a floor, a raised face, a wall and a face drawn on each look different"
	)


func test_a_held_off_grid_plane_is_where_the_preview_and_the_click_start():
	# Grid Up on a 0.5 grid and then a coarser snap leaves the plane at 0.5,
	# which plain snapping would round to 0 (#1501).
	root.grid_snap = 0.5
	root.grid_system.run_command("grid_up")
	root.grid_snap = 2.0
	_look_down_at(Vector3(0.3, 0.5, 0.3))
	var shown := _hover()
	assert_eq(int(shown.get("kind")), Kind.GRID)
	assert_almost_eq(shown["point"], Vector3(0, 0.5, 0), Vector3.ONE * 0.001)
	assert_eq(_click_origin(), shown["point"])


## Polygon and Path take their first point where a Draw starts, so a plane held
## off the grid step keeps its height for them too (#1583).
func test_polygon_and_path_start_on_a_held_off_grid_plane():
	root.grid_snap = 0.5
	root.grid_system.run_command("grid_up")
	root.grid_snap = 2.0
	_look_down_at(Vector3(0.3, 0.5, 0.3))
	for tool in [HFPolygonToolType.new(), HFPathToolType.new()]:
		tool.root = root
		var start: Dictionary = tool.first_point_start(camera, _screen())
		var point: Vector3 = start.get("point", Vector3.INF)
		assert_almost_eq(point, Vector3(0, 0.5, 0), Vector3.ONE * 0.001, tool.tool_name())


func test_a_physics_surface_is_marked_without_a_face():
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 2, 8)
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = Vector3(0, 5, 0)
	_look_down_at(Vector3(0.3, 6, 0.3))
	await wait_physics_frames(2)
	var shown := _hover()
	assert_eq(int(shown.get("kind")), Kind.RAISED, "a physics top is flat at its own height")
	assert_false(root.draw_hover.shows_face(), "it has no draft face to tint")
	assert_almost_eq(shown["point"], Vector3(0, 6, 0), Vector3.ONE * 0.001)
	assert_eq(_click_origin(), shown["point"])


# ---------------------------------------------------------------------------
# The grid lines and the cross sit on the point the click snaps to
# ---------------------------------------------------------------------------


func test_the_grid_lines_and_the_cross_mark_the_snapped_point():
	_box(Vector3(0, 1, 0), Vector3(8, 2, 8))
	_look_down_at(Vector3(1.3, 2, -0.6))
	var shown := _hover()
	var origin := _click_origin()
	assert_eq(_cursor_on_grid(), origin, "the bright grid lines go through the click's start")
	var cross: Node3D = root.draw_hover._cross
	assert_true(cross.visible, "a cross marks it")
	assert_almost_eq(cross.global_position, origin, Vector3.ONE * 0.001, "on the face too")
	assert_eq(shown["point"], origin)


## The headless renderer compiles a shader's code to list its uniforms, so a
## grid shader that no longer compiles lists none.
func test_the_grid_shader_compiles_with_the_cursor_uniforms():
	var names := []
	for uniform in GridShader.get_shader_uniform_list():
		names.append(uniform["name"])
	assert_has(names, "snap_size", "the shader compiles")
	assert_has(names, "cursor_point")
	assert_has(names, "cursor_visible")


func test_clearing_takes_down_the_lines_the_cross_and_the_tint():
	_box(Vector3(0, 1, 0), Vector3(8, 2, 8))
	_look_down_at(Vector3(0.3, 2, 0.3))
	_hover()
	root.draw_hover.clear()
	assert_null(_cursor_on_grid(), "the grid lines go")
	assert_false(root.draw_hover._cross.visible, "the cross goes")
	assert_false(root.draw_hover.shows_face(), "the tint goes")
	assert_false(root.draw_hover.is_showing())


func test_moving_off_a_face_onto_empty_space_drops_the_tint():
	_box(Vector3(0, 1, 0), Vector3(8, 2, 8))
	_look_down_at(Vector3(0.3, 2, 0.3))
	_hover()
	assert_true(root.draw_hover.shows_face())
	_look_down_at(Vector3(20.3, 0, 0.3))
	_hover()
	assert_false(root.draw_hover.shows_face(), "no face, no tint")
	assert_true(root.draw_hover._cross.visible, "the cross stays, on the grid")


func test_the_preview_is_not_saved_with_the_level():
	_box(Vector3(0, 1, 0), Vector3(8, 2, 8))
	_look_down_at(Vector3(0.3, 2, 0.3))
	_hover()
	for node in [root.draw_hover._face, root.draw_hover._cross]:
		assert_null(node.owner, "%s has no owner, so a save leaves it out" % node.name)
		assert_eq(node.get_parent(), root)
		assert_false(root.get_children().has(node), "an internal child")
