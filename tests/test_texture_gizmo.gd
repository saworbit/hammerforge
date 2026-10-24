extends GutTest
## The Texture Gizmo (#1420), driven through the real plugin: press, drag and let
## go in the viewport, and what the faces' UVs and the undo history hold after.
##
## The rig's camera looks at the origin from above and in front, so the front of
## a box there faces it. That face's texture runs U along +X and V down the wall
## (#907), and with scale 1 one repeat is one level unit.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const Gizmo = preload("res://addons/hammerforge/hf_texture_gizmo.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const HELD := MOUSE_BUTTON_MASK_LEFT
## Somewhere on the viewport away from the gizmo.
const ASIDE := Vector2(40, 40)

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func after_each() -> void:
	var dock = rig.plugin.dock
	dock.set_texture_gizmo_enabled(false)
	dock.face_select_mode.button_pressed = false


func _gizmo() -> Gizmo:
	return rig.plugin._texture_gizmo


func _face_idx(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


## A level with an 8 unit box at the origin and another beside it, in Face Select
## with a 1 unit grid and the gizmo on, and `picked` picked: `[brush id, normal]`
## pairs.
func _level(picked: Array) -> Node:
	var level = await rig.make_level()
	rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	rig.box(level, "beside", Vector3(-10, 0, 0), Vector3(8, 8, 8))
	var dock = rig.plugin.dock
	dock.grid_snap.value = 1.0
	# The pointer has been over the viewport, so the plugin knows its camera.
	rig.forward(PluginRig.motion(ASIDE))
	dock.face_select_mode.button_pressed = true
	dock.set_texture_gizmo_enabled(true)
	var selection := {}
	for pair in picked:
		var brush = level._find_brush_by_key(pair[0])
		var faces: Array = selection.get(pair[0], [])
		faces.append(_face_idx(brush, pair[1]))
		selection[pair[0]] = faces
	level.face_selection = selection
	level.face_selection_changed.emit()
	await rig.frame()
	rig.forward(PluginRig.motion(ASIDE))
	return level


func _face(level: Node, id: String, normal: Vector3) -> FaceData:
	var brush = level._find_brush_by_key(id)
	return brush.faces[_face_idx(brush, normal)]


func _screen(world: Vector3) -> Vector2:
	return rig.camera.unproject_position(world)


func _motion(at: Vector2, shift := false, ctrl := false) -> InputEventMouseMotion:
	var motion := PluginRig.motion(at, HELD)
	motion.shift_pressed = shift
	motion.ctrl_pressed = ctrl
	return motion


## Press at `from`, drag to `to` in two moves, and let go.
func _drag(from: Vector2, to: Vector2, shift := false, ctrl := false) -> void:
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, from)), STOP, "taken")
	assert_true(_gizmo().is_dragging(), "the press took a handle")
	rig.forward(_motion(from.lerp(to, 0.5), shift, ctrl))
	assert_eq(rig.forward(_motion(to, shift, ctrl)), STOP, "the drag is the gizmo's")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, to))
	assert_false(_gizmo().is_dragging(), "and letting go ends it")


## The world direction the texture's U runs along on the front of a box, read
## off its corners: on a face square to Z the UVs are an affine map of x and y.
func _u_direction(face: FaceData, xform: Transform3D) -> Vector3:
	var p: PackedVector3Array = xform * face.local_verts
	var uv := face.projected_uvs()
	var across := Transform2D(
		Vector2(p[1].x - p[0].x, p[1].y - p[0].y),
		Vector2(p[2].x - p[0].x, p[2].y - p[0].y),
		Vector2()
	)
	var map := Transform2D(uv[1] - uv[0], uv[2] - uv[0], Vector2()) * across.affine_inverse()
	var d := map.affine_inverse().basis_xform(Vector2(1, 0))
	return Vector3(d.x, d.y, 0.0).normalized()


func test_the_gizmo_shows_only_in_face_select_with_faces_picked_and_the_toggle_on() -> void:
	var level = await _level([])
	var dock = rig.plugin.dock
	assert_false(_gizmo().is_visible(), "no face picked, no gizmo")
	var front := _face_idx(level._find_brush_by_key("target"), Vector3.BACK)
	level.face_selection = {"target": [front]}
	level.face_selection_changed.emit()
	await rig.frame()
	assert_true(_gizmo().is_visible(), "a picked face shows it")
	var mesh := _gizmo().get_mesh_instance()
	assert_not_null(mesh, "drawn")
	if mesh:
		assert_eq(mesh.get_parent(), level, "on the level")
		assert_null(mesh.owner, "and never saved")
		assert_false(level.get_children().has(mesh), "or listed")
	var frame := _gizmo().get_frame()
	assert_true((frame["centre"] as Vector3).is_equal_approx(Vector3(0, 0, 4)), "at its middle")
	assert_true((frame["u"] as Vector3).is_equal_approx(Vector3.RIGHT), "U along the texture's U")
	assert_true((frame["v"] as Vector3).is_equal_approx(Vector3.DOWN), "and V down the wall")
	dock.set_texture_gizmo_enabled(false)
	assert_false(_gizmo().is_visible(), "the toggle off hides it")
	assert_null(_gizmo().get_mesh_instance())
	dock.set_texture_gizmo_enabled(true)
	assert_true(_gizmo().is_visible())
	dock.face_select_mode.button_pressed = false
	assert_false(_gizmo().is_visible(), "and so does leaving Face Select")
	await rig.leave_level(level)


## The toolbar's button and the palette switch the UV Editor's box.
func test_the_toolbar_and_the_palette_switch_the_gizmo() -> void:
	var level = await _level([["target", Vector3.BACK]])
	var dock = rig.plugin.dock
	rig.plugin._on_context_toolbar_action("texture_gizmo", [false])
	assert_false(dock.is_texture_gizmo_enabled(), "the button turns it off")
	assert_false(_gizmo().is_visible())
	rig.plugin._dispatch_viewport_action("texture_gizmo")
	assert_true(dock.is_texture_gizmo_enabled(), "and the palette back on")
	assert_true(_gizmo().is_visible())
	rig.plugin._update_hud_context()
	var button := rig.plugin._context_toolbar.find_child("TextureGizmoBtn", true, false) as Button
	assert_not_null(button)
	if button:
		assert_true(button.button_pressed, "the toolbar's button shows the box")
		dock.set_texture_gizmo_enabled(false)
		rig.plugin._update_hud_context()
		assert_false(button.button_pressed, "both ways")
	await rig.leave_level(level)


## With a 1 unit grid the middle square slides the texture a whole unit along the
## face per step, on every picked face along its own U, whatever its scale.
func test_sliding_moves_the_texture_a_grid_step_along_each_face() -> void:
	var level = await _level([["target", Vector3.BACK], ["beside", Vector3.BACK]])
	var beside := _face(level, "beside", Vector3.BACK)
	level.set_face_uv_params(
		"beside",
		_face_idx(level._find_brush_by_key("beside"), Vector3.BACK),
		Vector2(0.5, 0.5),
		Vector2.ZERO,
		0.0
	)
	await rig.frame()
	var centre: Vector3 = _gizmo().get_frame()["centre"]
	_drag(_screen(centre), _screen(centre + Vector3(1.3, 0, 0)))
	var target := _face(level, "target", Vector3.BACK)
	assert_almost_eq(target.uv_offset.x, -1.0, 0.0001, "one repeat is one unit, so one step")
	assert_almost_eq(target.uv_offset.y, 0.0, 0.0001, "and none down the wall")
	assert_almost_eq(beside.uv_offset.x, -0.5, 0.0001, "half a repeat is one unit there")
	assert_eq(beside.uv_scale, Vector2(0.5, 0.5), "and the scale is left alone")
	# Ctrl lets it go between steps.
	centre = _gizmo().get_frame()["centre"]
	_drag(_screen(centre), _screen(centre + Vector3(0, 0.3, 0)), false, true)
	assert_almost_eq(target.uv_offset.y, 0.3, 0.0001, "V runs down, so up is back along it")
	await rig.leave_level(level)


func test_an_axis_end_stretches_along_that_axis_and_shift_both() -> void:
	var level = await _level([["target", Vector3.BACK]])
	var target := _face(level, "target", Vector3.BACK)
	var centre: Vector3 = _gizmo().get_frame()["centre"]
	var end := _gizmo().world_point(rig.camera, Gizmo.Handle.STRETCH_U)
	_drag(_screen(end), _screen(centre + (end - centre) * 2.0))
	assert_almost_eq(target.uv_scale.x, 0.5, 0.0001, "twice as long is half the repeats")
	assert_almost_eq(target.uv_scale.y, 1.0, 0.0001, "along U only")
	end = _gizmo().world_point(rig.camera, Gizmo.Handle.STRETCH_V)
	_drag(_screen(end), _screen(centre + (end - centre) * 0.5), true)
	assert_almost_eq(target.uv_scale.x, 1.0, 0.0001, "Shift stretches both")
	assert_almost_eq(target.uv_scale.y, 2.0, 0.0001)
	level.set_face_uv_params(
		"target",
		_face_idx(level._find_brush_by_key("target"), Vector3.BACK),
		Vector2.ONE,
		Vector2.ZERO,
		0.0
	)
	await rig.frame()
	end = _gizmo().world_point(rig.camera, Gizmo.Handle.STRETCH_U)
	_drag(_screen(end), _screen(centre + (end - centre) * 2.0), true)
	assert_eq(target.uv_scale.x, target.uv_scale.y, "so U and V stay equal")
	await rig.leave_level(level)


## The ring turns the texture by Selection Tools > Step, the way the pointer went.
func test_the_ring_turns_the_texture_in_steps() -> void:
	var level = await _level([["target", Vector3.BACK]])
	level.rotate_snap_degrees = 15.0
	var target := _face(level, "target", Vector3.BACK)
	var xform: Transform3D = level._find_brush_by_key("target").global_transform
	var before := _u_direction(target, xform)
	var frame := _gizmo().get_frame()
	var centre: Vector3 = frame["centre"]
	var start := _gizmo().world_point(rig.camera, Gizmo.Handle.TURN)
	var radius := (start - centre).length()
	var across := (frame["normal"] as Vector3).cross(frame["u"])
	var angle := deg_to_rad(40.0)
	var to := centre + ((frame["u"] as Vector3) * cos(angle) + across * sin(angle)) * radius
	_drag(_screen(start), _screen(to))
	assert_almost_eq(
		absf(rad_to_deg(target.uv_rotation)), 45.0, 0.001, "40 degrees snaps to 45 at 15 a step"
	)
	var after := _u_direction(target, xform)
	assert_almost_eq(
		rad_to_deg(before.signed_angle_to(after, Vector3.BACK)),
		45.0,
		0.01,
		"anticlockwise seen from in front, as the pointer went"
	)
	await rig.leave_level(level)


## Right click or Escape in a drag puts every face back and records nothing.
func test_right_click_or_escape_puts_the_texture_back() -> void:
	var level = await _level([["target", Vector3.BACK], ["target", Vector3.UP]])
	var target := _face(level, "target", Vector3.BACK)
	var undo = rig.undo()
	undo.clear()
	var centre: Vector3 = _gizmo().get_frame()["centre"]
	for cancel in [PluginRig.click(MOUSE_BUTTON_RIGHT, true), PluginRig.key(KEY_ESCAPE)]:
		assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, _screen(centre))), STOP)
		rig.forward(_motion(_screen(centre + Vector3(2.2, 0, 0))))
		assert_almost_eq(target.uv_offset.x, -2.0, 0.0001, "the texture follows the drag")
		assert_eq(rig.forward(cancel), STOP, "the cancel is the gizmo's")
		assert_false(_gizmo().is_dragging(), "and ends the drag")
		assert_eq(target.uv_offset, Vector2.ZERO, "with the texture where it was")
		rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, _screen(centre)))
	assert_eq(undo.step_count(), 0, "and nothing in the history")
	await rig.leave_level(level)


## A drag over three picked faces is one undo step, and Ctrl+Z puts all three
## back.
func test_a_drag_over_three_faces_is_one_undo_step() -> void:
	var picked := [["target", Vector3.BACK], ["target", Vector3.UP], ["beside", Vector3.BACK]]
	var level = await _level(picked)
	var undo = rig.undo()
	undo.clear()
	var centre: Vector3 = _gizmo().get_frame()["centre"]
	_drag(_screen(centre), _screen(centre + _gizmo().get_frame()["u"] * 2.0))
	for pair in picked:
		assert_ne(_face(level, pair[0], pair[1]).uv_offset, Vector2.ZERO, "each face moved")
	assert_eq(undo.step_count(), 1, "in one step")
	assert_eq(undo.scene_history.get_current_action_name(), "Slide Texture")
	undo.press_undo()
	await rig.frame()
	for pair in picked:
		assert_eq(_face(level, pair[0], pair[1]).uv_offset, Vector2.ZERO, "Ctrl+Z puts each back")
	undo.press_redo()
	await rig.frame()
	for pair in picked:
		assert_ne(
			_face(level, pair[0], pair[1]).uv_offset, Vector2.ZERO, "and redo moves them again"
		)
	await rig.leave_level(level)


## A face laid out by hand moves its layout, as Justify moves one (#654).
func test_a_layout_made_by_hand_moves_with_the_slide() -> void:
	var level = await _level([["target", Vector3.BACK]])
	var target := _face(level, "target", Vector3.BACK)
	var layout := target.projected_uvs()
	layout[0] += Vector2(0.3, 0.1)
	target.custom_uvs = layout
	assert_true(target.has_hand_layout())
	var centre: Vector3 = _gizmo().get_frame()["centre"]
	_drag(_screen(centre), _screen(centre + Vector3(1.2, 0, 0)))
	assert_true(target.has_hand_layout(), "the layout is kept")
	for i in layout.size():
		assert_true(
			target.custom_uvs[i].is_equal_approx(layout[i] - Vector2(1, 0)), "and slid a unit"
		)
	await rig.leave_level(level)


## A press away from the gizmo is Face Select's, as before.
func test_a_press_off_the_gizmo_picks_faces_as_before() -> void:
	var level = await _level([["target", Vector3.BACK]])
	assert_ne(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, ASIDE)), STOP)
	assert_false(_gizmo().is_dragging())
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, ASIDE))
	await rig.leave_level(level)
