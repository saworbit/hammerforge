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


# ---------------------------------------------------------------------------
# The pointer handlers, through the real plugin
# ---------------------------------------------------------------------------

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


## A level with the grid at 1, so a short drag shows.
func _pointer_level() -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	return level


func _leave_pointer_level(level: Node) -> void:
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _left(pressed: bool, at: Vector2) -> int:
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at))


func _top_face(brush: Node) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.99:
			return i
	return -1


## Draw: a press on the ground starts the base, dragging with the button down
## stretches it, the release sets it, moving sets the height, and a click places
## the brush. Every step is the plugin's to consume.
func test_plugin_pointer_callbacks_are_thin_delegates() -> void:
	assert_not_null(rig.plugin, rig.error())
	var level = await _pointer_level()
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	assert_eq(_left(true, AIM), STOP, "the press starts the base")
	var corner := AIM + Vector2(80, 30)
	assert_eq(rig.forward(PluginRig.motion(corner, MOUSE_BUTTON_MASK_LEFT)), STOP, "the drag")
	assert_eq(_left(false, corner), STOP, "the release")
	assert_true(level.input_state.is_drag_height(), "sets the base")
	assert_eq(rig.forward(PluginRig.motion(corner + Vector2(0, -40))), STOP, "moving sets height")
	_left(true, corner + Vector2(0, -40))
	_left(false, corner + Vector2(0, -40))
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "and a click places the brush")
	await _leave_pointer_level(level)


## Extrude Up: a press on a face starts, a drag pulls, a release places.
func test_extrude_runs_through_the_plugin() -> void:
	var level = await _pointer_level()
	rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	rig.plugin._hotkey_palette.action_invoked.emit("tool_extrude_up")
	var on_top := rig.camera.unproject_position(Vector3(0, 4, 0))
	assert_eq(_left(true, on_top), STOP, "a press on the top face starts the extrude")
	var pulled := on_top + Vector2(0, -60)
	assert_eq(rig.forward(PluginRig.motion(pulled, MOUSE_BUTTON_MASK_LEFT)), STOP, "the drag")
	assert_eq(_left(false, pulled), STOP)
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 2, "and the release places the block")
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await _leave_pointer_level(level)


## In paint mode a press on the ground goes to the floor paint rather than
## starting a Draw drag, though Draw is the tool in hand. The paint system itself
## only runs in the editor, so here it says it could not reach the layer, which
## is how the press is seen to have reached it.
func test_paint_mode_paints_before_draw_can_draw() -> void:
	var level = await _pointer_level()
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	rig.plugin._toggle_paint_mode()
	rig.plugin.dock.set_paint_tool(0)
	watch_signals(level)
	assert_eq(_left(true, AIM), STOP, "the press is taken")
	var said = get_signal_parameters(level, "user_message")
	assert_eq(said[0] if said else "", "Floor Paint could not reach the active layer plane")
	_left(false, AIM)
	assert_true(level.input_state.is_idle(), "and no Draw drag began")
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 0)
	rig.plugin._toggle_paint_mode()
	await _leave_pointer_level(level)


## With a sculpted face selected and the Displacement section open, a press on
## the face sculpts it rather than painting the floor.
func test_displacement_sculpts_before_floor_paint_can_paint() -> void:
	var level = await _pointer_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := _top_face(box)
	assert_true(level.create_displacement("d", top, 2), "the top face is sculptable")
	level.face_selection = {"d": [top]}
	rig.plugin._toggle_paint_mode()
	rig.plugin.dock._disp_section.set_expanded(true)
	var before := var_to_str(box.faces[top].displacement.to_dict())
	watch_signals(level)
	var on_top := rig.camera.unproject_position(Vector3(0, 8, 0))
	assert_eq(_left(true, on_top), STOP, "the press is taken")
	assert_eq(_left(false, on_top), STOP)
	assert_ne(var_to_str(box.faces[top].displacement.to_dict()), before, "and sculpts the face")
	assert_signal_not_emitted(level, "user_message", "instead of going to the floor paint")
	rig.plugin.dock._disp_section.set_expanded(false)
	rig.plugin._toggle_paint_mode()
	await _leave_pointer_level(level)


func test_a_finished_sculpt_stroke_goes_to_the_paint_module_for_its_undo() -> void:
	# A grep, because the commit opens an undo step, which shows only to an undo
	# manager, and the plugin stand-in has none.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(source.contains("HFPluginPaintInput.commit_displacement_undo"))


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
