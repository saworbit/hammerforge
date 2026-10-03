extends GutTest
## Focused coverage for extracted plugin paint and pointer handlers.

const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFPluginPaintInput = preload("res://addons/hammerforge/plugin_paint_input.gd")


func test_displacement_start_is_null_safe() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	assert_false(HFPluginPaintInput.should_start_displacement(null, press, null))


func test_polygon_margin_accepts_inside_and_rejects_distant_points() -> void:
	var vertices := PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	)
	assert_true(HFPluginPaintInput.point_near_polygon_3d(Vector3.ZERO, vertices, Vector3.UP, 0.0))
	assert_false(
		HFPluginPaintInput.point_near_polygon_3d(Vector3(4, 0, 0), vertices, Vector3.UP, 0.0)
	)


func test_plugin_pointer_callbacks_are_thin_delegates() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	# The entry points plugin.gd owns. `do_displacement_stroke()`,
	# `point_near_polygon_3d()` and `update_prefab_hover()` are called by the
	# handlers below them, inside their own modules; plugin.gd used to carry a
	# wrapper for each that nothing called, and this assertion is why they
	# survived (#609).
	for call in [
		"HFPluginPaintInput.should_start_displacement",
		"HFPluginPaintInput.handle_displacement",
		"HFPluginPaintInput.commit_displacement_undo",
		"HFPluginPaintInput.handle_paint",
		"HFPluginPointerTools.handle_extrude",
		"HFPluginPointerTools.handle_draw",
		"HFPluginPointerTools.handle_motion",
	]:
		assert_true(source.contains(call), "%s must be delegated" % call)


func test_dispatcher_keeps_paint_and_pointer_calls_in_the_same_order() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_viewport_input.gd")
	var displacement := source.find("plugin._handle_disp_paint_input")
	var paint := source.find("plugin._handle_paint_input")
	var draw := source.find("plugin._handle_draw_mouse")
	var motion := source.find("plugin._handle_mouse_motion")
	assert_gte(displacement, 0)
	assert_gt(paint, displacement)
	assert_gt(draw, paint)
	assert_gt(motion, draw)


# ---------------------------------------------------------------------------
# Displacement paint on a stretched brush (#884)
# ---------------------------------------------------------------------------

const DraftBrushScript = preload("res://addons/hammerforge/brush_instance.gd")


class StrokePlugin:
	extends RefCounted

	var _disp_paint_brush_id := ""
	var _disp_paint_face_idx := -1
	var dock = null


class StrokeRecorder:
	extends RefCounted

	var hits: Array = []

	func paint(
		_brush_id: String,
		_face_idx: int,
		position: Vector3,
		_radius: float,
		_strength: float,
		_mode: int
	) -> void:
		hits.append(position)


class StrokeRoot:
	extends Node3D

	var displacement_system = StrokeRecorder.new()
	var brush: Node3D = null

	func find_brush_by_id(_brush_id: String) -> Node3D:
		return brush


## Aim a stroke at the middle of one face of the brush, through a camera that
## looks straight at it, and return where the paint went down.
func _stroke_at_middle_of(root: StrokeRoot, brush: Node3D, face_idx: int) -> Dictionary:
	var corners := PackedVector3Array()
	var middle := Vector3.ZERO
	for v in brush.faces[face_idx].local_verts:
		corners.append(brush.global_transform * v)
		middle += corners[-1]
	middle /= corners.size()
	var facing := (corners[2] - corners[0]).cross(corners[1] - corners[0]).normalized()
	if facing.dot(brush.global_transform.basis * brush.faces[face_idx].normal) < 0.0:
		facing = -facing
	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	camera.look_at_from_position(middle + facing * 120.0 + Vector3(0.0, 0.0, 0.1), middle)
	var plugin := StrokePlugin.new()
	plugin._disp_paint_brush_id = "w"
	plugin._disp_paint_face_idx = face_idx
	HFPluginPaintInput.do_displacement_stroke(
		plugin, root, camera, camera.unproject_position(middle)
	)
	var recorder: StrokeRecorder = root.displacement_system
	return {"middle": middle, "hits": recorder.hits}


func _stroke_root(shape: int, stretch: Vector3) -> StrokeRoot:
	var root := StrokeRoot.new()
	add_child_autoqfree(root)
	var brush = DraftBrushScript.new()
	root.add_child(brush)
	brush.shape = shape
	brush.size = Vector3(32, 32, 32)
	brush.scale = stretch
	root.brush = brush
	return root


## Faces wind clockwise seen from outside. The check that a stroke is on its face
## took the other winding, so it turned away every point of every real face and
## no stroke ever reached a sculpt.
func test_polygon_margin_reads_a_face_wound_the_way_faces_are() -> void:
	var vertices := PackedVector3Array(
		[Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]
	)
	assert_true(HFPluginPaintInput.point_near_polygon_3d(Vector3.ZERO, vertices, Vector3.UP, 0.0))
	assert_true(
		HFPluginPaintInput.point_near_polygon_3d(Vector3(1.5, 0, 0), vertices, Vector3.UP, 1.0),
		"a point within the margin of an edge still counts"
	)
	assert_false(
		HFPluginPaintInput.point_near_polygon_3d(Vector3(4, 0, 0), vertices, Vector3.UP, 0.0)
	)


func test_a_stroke_on_the_top_of_a_box_lands_under_the_cursor() -> void:
	var root := _stroke_root(DraftBrushScript.BrushShape.BOX, Vector3.ONE)
	var top := -1
	for i in root.brush.faces.size():
		if root.brush.faces[i].normal.y > 0.99:
			top = i
	var stroke := _stroke_at_middle_of(root, root.brush, top)
	assert_eq(stroke["hits"].size(), 1, "the stroke reached the face")
	if stroke["hits"].size() == 1:
		assert_almost_eq(stroke["hits"][0], stroke["middle"], Vector3.ONE * 0.05)


## A stroke aimed at the middle of a stretched slope lands there. The ray meets
## the face's plane, and a normal carried by the basis alone tilts that plane
## about the face's first corner, so the paint went down off to one side (#884).
func test_a_stroke_on_a_stretched_slope_lands_under_the_cursor() -> void:
	var root := _stroke_root(DraftBrushScript.BrushShape.WEDGE, Vector3(1, 3, 1))
	var slope := -1
	for i in root.brush.faces.size():
		var n: Vector3 = root.brush.faces[i].normal
		if absf(n.x) < 0.99 and absf(n.y) < 0.99 and absf(n.z) < 0.99:
			slope = i
	assert_gte(slope, 0, "the wedge has a slope")
	var stroke := _stroke_at_middle_of(root, root.brush, slope)
	assert_eq(stroke["hits"].size(), 1, "the stroke reached the face")
	if stroke["hits"].size() == 1:
		assert_almost_eq(stroke["hits"][0], stroke["middle"], Vector3.ONE * 0.05)
