extends GutTest
## Where a drag lands. G and a held Ctrl decide the grid for the draw, the resize
## handles and the vertex drags alike, and Alt nudges by a tenth of a grid step
## (#1431). V, or Alt held through the drag, lands a vertex or handle drag on
## another brush's vertex (#1399).
##
## The plugin's part is reading the keys off each event, so the draw, the vertex
## drag and the nudges go through it. A resize handle is moved by Godot's gizmo,
## which a headless run cannot build, so its landing is driven through
## `land_handle_drag()` after the plugin has read the keys, as Godot calls it.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const BrushGizmoPlugin = preload("res://addons/hammerforge/brush_gizmo_plugin.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each():
	# The dock's snap toggles outlive a level. Put them back as a level starts
	# them, without reaching for a level that is gone.
	if rig.plugin and rig.plugin.dock:
		rig.plugin.dock.snap_grid_btn.set_pressed_no_signal(true)
		rig.plugin.dock.snap_vertex_btn.set_pressed_no_signal(false)


## The dock's Grid and Corners toggles, pressed as a mapper presses them.
func _toggles(grid: bool, vertex: bool) -> void:
	rig.plugin.dock.snap_grid_btn.button_pressed = grid
	rig.plugin.dock.snap_vertex_btn.button_pressed = vertex


func _motion(position: Vector2, ctrl := false, alt := false, held := true) -> InputEventMouseMotion:
	var event := PluginRig.motion(position, MOUSE_BUTTON_MASK_LEFT if held else 0)
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	return event


func _click(pressed: bool, position: Vector2, ctrl := false) -> InputEventMouseButton:
	var event := PluginRig.click(MOUSE_BUTTON_LEFT, pressed, position)
	event.ctrl_pressed = ctrl
	return event


func _on_grid(value: float, step: float) -> bool:
	return is_equal_approx(value, snappedf(value, step))


func _hit(level, position: Vector2) -> Vector3:
	return level._raycast(rig.camera, position)["position"]


func _has_near(points: PackedVector3Array, wanted: Vector3) -> bool:
	for p in points:
		if p.is_equal_approx(wanted):
			return true
	return false


func _assert_near(got: Variant, wanted: Vector3, text: String) -> void:
	assert_true(
		got is Vector3 and (got as Vector3).is_equal_approx(wanted), "%s (%s)" % [text, got]
	)


# ===========================================================================
# The draw (#1431)
# ===========================================================================

## Corners off the grid, and a height 41 px up: 10.25 units at 4 px a unit.
const DRAW_A := Vector3(0.37, 0, 0.81)
const DRAW_B := Vector3(3.12, 0, 2.66)
const HEIGHT_PX := 41.0


## Press, drag the base and let go, then raise the height, each event holding
## Ctrl or not as asked. Leaves the draw in its height stage.
func _draw_to_height(level, ctrl: bool) -> void:
	rig.plugin.dock.tool_draw.button_pressed = true
	var a := rig.camera.unproject_position(DRAW_A)
	var b := rig.camera.unproject_position(DRAW_B)
	rig.forward(_motion(a, ctrl, false, false))
	assert_eq(rig.forward(_click(true, a, ctrl)), STOP, "the draw starts")
	rig.forward(_motion(b, ctrl))
	rig.forward(_click(false, b, ctrl))
	assert_true(level.input_state.is_drag_height(), "the base is down")
	rig.forward(_motion(b - Vector2(0, HEIGHT_PX), ctrl, false, false))


func test_ctrl_puts_both_corners_and_the_height_where_the_cursor_is():
	var level = await rig.make_level()
	var a := rig.camera.unproject_position(DRAW_A)
	var b := rig.camera.unproject_position(DRAW_B)
	_draw_to_height(level, true)
	var state = level.input_state
	assert_eq(state.drag_origin, _hit(level, a), "the first corner is the cursor's")
	assert_eq(state.drag_end, _hit(level, b), "and so is the second")
	var raised: float = state.height_stage_start_height + HEIGHT_PX / level.height_pixels_per_unit
	assert_almost_eq(state.drag_height, raised, 0.0001, "the height is the cursor's")
	assert_false(_on_grid(state.drag_origin.x, level.grid_snap), "none of it on the grid")
	assert_eq(rig.plugin.hud.shown_drag_snap(), "Snap off", "the HUD says what Ctrl does")
	rig.forward(_motion(b - Vector2(0, HEIGHT_PX + 2.0), false, false, false))
	assert_true(_on_grid(state.drag_height, level.grid_snap), "letting go snaps the next motion")
	assert_eq(rig.plugin.hud.shown_drag_snap(), "", "and the HUD line goes")
	level.cancel_drag()
	await rig.leave_level(level)


func test_without_ctrl_the_draw_snaps_as_before():
	var level = await rig.make_level()
	_draw_to_height(level, false)
	var state = level.input_state
	for axis in [0, 2]:
		assert_true(_on_grid(state.drag_origin[axis], level.grid_snap), "corner A on the grid")
		assert_true(_on_grid(state.drag_end[axis], level.grid_snap), "corner B on the grid")
	assert_true(_on_grid(state.drag_height, level.grid_snap), "the height on the grid")
	assert_eq(rig.plugin.hud.shown_drag_snap(), "", "no key, no HUD line")
	level.cancel_drag()
	await rig.leave_level(level)


func test_with_g_off_ctrl_snaps_the_draw_and_nothing_else_does():
	var level = await rig.make_level()
	_toggles(false, false)
	_draw_to_height(level, false)
	var state = level.input_state
	var b := rig.camera.unproject_position(DRAW_B)
	assert_eq(state.drag_end, _hit(level, b), "G off: the corner is the cursor's")
	assert_false(_on_grid(state.drag_height, level.grid_snap), "and so is the height")
	rig.forward(_motion(b - Vector2(0, HEIGHT_PX), true, false, false))
	assert_true(_on_grid(state.drag_height, level.grid_snap), "Ctrl snaps it")
	assert_eq(rig.plugin.hud.shown_drag_snap(), "Snap on", "and the HUD says so")
	level.cancel_drag()
	_toggles(true, false)
	await rig.leave_level(level)


# ===========================================================================
# Vertex drags
# ===========================================================================


## A box at the origin with its +X face selected and its (2, 2, 2) corner
## grabbed through the plugin, the way a mapper shift-clicks the last corner.
## Returns the screen position of the press.
func _grab_plus_x_face(level, box) -> Vector2:
	rig.select([box])
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	var vs = level.vertex_system
	var verts: PackedVector3Array = vs.get_brush_vertices(box)
	var grabbed := -1
	for i in verts.size():
		if is_equal_approx(verts[i].x, 2.0):
			if verts[i].is_equal_approx(Vector3(2, 2, 2)):
				grabbed = i
			else:
				vs.select_vertex("v", i, true)
	var corner := rig.camera.unproject_position(Vector3(2, 2, 2))
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, corner)
	press.shift_pressed = true
	assert_eq(rig.forward(press), STOP, "the corner is grabbed")
	assert_eq(vs.get_selection_count(), 4, "with the rest of its face")
	assert_true(grabbed >= 0 and vs.is_dragging())
	return corner


func _face_x(level) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in level.vertex_system.get_selected_world_positions():
		out.append(p.x)
	return out


func test_ctrl_turns_the_vertex_drag_grid_off_and_back_on():
	var level = await rig.make_level()
	var box = rig.box(level, "v", Vector3.ZERO)
	var corner := _grab_plus_x_face(level, box)
	var to := corner + Vector2(37.3, 0)
	rig.forward(_motion(to))
	var snapped_x: float = _face_x(level)[0]
	assert_true(_on_grid(snapped_x - 2.0, level.grid_snap), "G on: whole grid steps")
	rig.forward(_motion(to, true))
	var free_x: float = _face_x(level)[0]
	assert_false(_on_grid(free_x - 2.0, level.grid_snap), "Ctrl: where the cursor is")
	assert_eq(rig.plugin.hud.shown_drag_snap(), "Snap off")
	rig.forward(_motion(to))
	assert_eq(_face_x(level)[0], snapped_x, "let go of Ctrl and the next motion snaps")
	_toggles(false, false)
	rig.forward(_motion(to))
	assert_eq(_face_x(level)[0], free_x, "G off: no snap")
	rig.forward(_motion(to, true))
	assert_eq(_face_x(level)[0], snapped_x, "G off and Ctrl: the grid")
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true, to))
	_toggles(true, false)
	await rig.leave_level(level)


## A second box whose near corner is off the grid: (4.3, 2, 2.2).
func _neighbour(level) -> Node:
	return rig.box(level, "w", Vector3(6.3, 0, 0.2))


const TARGET := Vector3(4.3, 2, 2.2)


func test_with_v_on_a_vertex_drag_lands_on_the_other_brush_corner():
	var level = await rig.make_level()
	var box = rig.box(level, "v", Vector3.ZERO)
	_neighbour(level)
	_toggles(true, true)
	_grab_plus_x_face(level, box)
	var before: PackedVector3Array = level.vertex_system.get_selected_world_positions()
	var near := rig.camera.unproject_position(TARGET) + Vector2(3, -2)
	rig.forward(_motion(near))
	var moved: PackedVector3Array = level.vertex_system.get_selected_world_positions()
	var shift := TARGET - Vector3(2, 2, 2)
	assert_true(_has_near(moved, TARGET), "the grabbed corner is on the other brush's")
	for p in before:
		assert_true(_has_near(moved, p + shift), "the rest of the face moved with it")
	_assert_near(level.snap_system.drag_marker_position(), TARGET, "the marker is on the target")
	var steps: int = rig.undo().step_count()
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, near))
	assert_null(level.snap_system.drag_marker_position(), "and goes with the drag")
	assert_eq(rig.undo().step_count(), steps + 1, "the drag is one step")
	assert_true(rig.undo().press_undo(), "one undo")
	var after: PackedVector3Array = level.vertex_system.get_brush_vertices(box)
	assert_true(_has_near(after, Vector3(2, 2, 2)), "puts the corner back")
	assert_false(_has_near(after, TARGET))
	_toggles(true, false)
	await rig.leave_level(level)


func test_with_v_off_alt_does_the_same_and_without_it_the_grid_does():
	var level = await rig.make_level()
	var box = rig.box(level, "v", Vector3.ZERO)
	_neighbour(level)
	_grab_plus_x_face(level, box)
	var near := rig.camera.unproject_position(TARGET) + Vector2(3, -2)
	rig.forward(_motion(near))
	var positions: PackedVector3Array = level.vertex_system.get_selected_world_positions()
	assert_false(_has_near(positions, TARGET), "no Alt: the grid")
	for p in positions:
		assert_true(_on_grid(p.x, level.grid_snap), "whole steps from a corner on the grid")
	assert_null(level.snap_system.drag_marker_position(), "and no marker")
	rig.forward(_motion(near, false, true))
	positions = level.vertex_system.get_selected_world_positions()
	assert_true(_has_near(positions, TARGET), "Alt: the corner")
	_assert_near(level.snap_system.drag_marker_position(), TARGET, "with the marker on it")
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true, near))
	assert_null(level.snap_system.drag_marker_position(), "a cancel takes the marker down")
	assert_true(
		_has_near(level.vertex_system.get_brush_vertices(box), Vector3(2, 2, 2)),
		"and restores the box"
	)
	await rig.leave_level(level)


func test_a_snapped_vertex_drag_that_would_dent_the_brush_is_refused():
	var level = await rig.make_level()
	var box = rig.box(level, "v", Vector3.ZERO)
	# A small box inside the big one: pulling one corner onto it dents the brush.
	rig.box(level, "w", Vector3(-0.3, 0, 0.2), Vector3(0.6, 1, 0.6))
	var before: PackedVector3Array = level.vertex_system.get_brush_vertices(box)
	rig.select([box])
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	var vs = level.vertex_system
	var corner := rig.camera.unproject_position(Vector3(2, 2, 2))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, corner))
	assert_eq(vs.get_selection_count(), 1, "one corner grabbed")
	var steps: int = rig.undo().step_count()
	var inside := rig.camera.unproject_position(Vector3(0, 0.5, 0.5))
	rig.forward(_motion(inside, false, true))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, inside))
	assert_eq(vs.get_brush_vertices(box), before, "the refusal puts the box back")
	assert_null(level.snap_system.drag_marker_position(), "with no marker left")
	assert_eq(rig.undo().step_count(), steps, "and records nothing")
	await rig.leave_level(level)


# ===========================================================================
# Resize handles
# ===========================================================================


func test_a_handle_honours_g_and_ctrl_as_the_draw_does():
	var level = await rig.make_level()
	var box = rig.box(level, "v", Vector3.ZERO)
	var at := rig.camera.unproject_position(Vector3(3.37, 0, 0))
	rig.forward(_motion(at, false, false, false))
	var snapped := BrushGizmoPlugin.land_handle_drag(box, 0, rig.camera, at)
	assert_true(_on_grid(snapped["size"].x, level.grid_snap), "G on: whole steps")
	rig.forward(_motion(at, true, false, false))
	var free := BrushGizmoPlugin.land_handle_drag(box, 0, rig.camera, at)
	assert_false(_on_grid(free["size"].x, level.grid_snap), "Ctrl: where the cursor is")
	_toggles(false, false)
	rig.forward(_motion(at, false, false, false))
	assert_eq(BrushGizmoPlugin.land_handle_drag(box, 0, rig.camera, at), free, "G off: free")
	rig.forward(_motion(at, true, false, false))
	assert_eq(BrushGizmoPlugin.land_handle_drag(box, 0, rig.camera, at), snapped, "and Ctrl")
	rig.forward(_motion(at, false, false, false))
	_toggles(true, false)
	await rig.leave_level(level)


func test_a_handle_stops_level_with_the_other_brush_vertex():
	var level = await rig.make_level()
	var box = rig.box(level, "v", Vector3.ZERO)
	_neighbour(level)
	var near := rig.camera.unproject_position(TARGET) + Vector2(2, 3)
	rig.forward(_motion(near, false, false, false))
	var grid := BrushGizmoPlugin.land_handle_drag(box, 0, rig.camera, near)
	assert_true(_on_grid(grid["size"].x, level.grid_snap), "without V the handle takes the grid")
	assert_null(level.snap_system.drag_marker_position())
	rig.forward(_motion(near, false, true, false))
	var level_with := BrushGizmoPlugin.land_handle_drag(box, 0, rig.camera, near)
	assert_almost_eq(level_with["size"].x, 6.3, 0.0001, "Alt: the +X face is level with x 4.3")
	assert_almost_eq(level_with["position"].x, 1.15, 0.0001, "and the -X face stays")
	_assert_near(level.snap_system.drag_marker_position(), TARGET, "the marker shows the vertex")
	var restore := {"size": box.size, "position": box.global_position}
	box.size = level_with["size"]
	box.global_position = level_with["position"]
	assert_true(
		BrushGizmoPlugin.apply_resize_transaction(box, restore, false, null, level),
		"the drag commits"
	)
	assert_null(level.snap_system.drag_marker_position(), "and the marker goes with it")
	rig.forward(_motion(near, false, false, false))
	await rig.leave_level(level)


func test_the_handle_resize_lands_level_with_a_point():
	var r := BrushGizmoPlugin.calculate_brush_axis_resize(
		0,
		Basis.IDENTITY,
		Vector3(4, 4, 4),
		Vector3.ZERO,
		Vector3.RIGHT,
		1,
		3.37,
		0.5,
		Vector3(4.3, 9, -7)
	)
	assert_almost_eq(r["size"].x, 6.3, 0.0001, "the face goes to x 4.3, unsnapped")
	assert_almost_eq(r["position"].x, 1.15, 0.0001)
	var behind := BrushGizmoPlugin.calculate_brush_axis_resize(
		0,
		Basis.IDENTITY,
		Vector3(4, 4, 4),
		Vector3.ZERO,
		Vector3.RIGHT,
		1,
		3.37,
		0.5,
		Vector3(-3, 0, 0)
	)
	assert_eq(behind, {}, "a point behind the far face cannot be reached")


# ===========================================================================
# Nudges (#1431)
# ===========================================================================


func test_alt_arrow_nudges_a_tenth_of_the_grid_step_and_stays_off_the_grid():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	rig.select([box])
	var tenth: float = level.grid_snap * 0.1
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT, false, false, true)), STOP)
	assert_almost_eq(box.global_position.x, tenth, 0.00001, "Alt+Right: a tenth")
	assert_eq(rig.forward(PluginRig.key(KEY_PAGEUP, false, true, true)), STOP)
	assert_almost_eq(box.global_position.y, tenth, 0.00001, "Alt+Shift+PgUp: a tenth up")
	var plane: Vector3 = level.grid_plane_origin
	assert_eq(rig.forward(PluginRig.key_for("grid_up")), STOP, "Alt+PgUp is still Grid Up")
	assert_almost_eq(box.global_position.y, tenth, 0.00001, "which moves no brush")
	assert_ne(level.grid_plane_origin, plane, "but the drawing plane")
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT)), STOP)
	assert_almost_eq(box.global_position.x, tenth + level.grid_snap, 0.00001, "Right: a step")
	await rig.leave_level(level)


# ===========================================================================
# The keys are bindings (#1431)
# ===========================================================================


func test_the_held_keys_are_bindings_and_not_commands():
	var keymap := HFKeymapType.load_or_default("")
	assert_eq(keymap.get_display_string("snap_invert_hold"), "Ctrl")
	assert_eq(keymap.get_display_string("snap_vertex_hold"), "Alt")
	assert_false(keymap.get_actions().has("snap_invert_hold"), "a hold runs no command")
	assert_eq(Array(keymap.conflicts_for("snap_invert_hold")), [], "and clashes with nothing")
	var motion := InputEventMouseMotion.new()
	motion.ctrl_pressed = true
	assert_true(keymap.held("snap_invert_hold", motion), "a motion says Ctrl is down")
	assert_false(keymap.held("snap_vertex_hold", motion))
	var release := InputEventKey.new()
	release.keycode = KEY_CTRL
	release.ctrl_pressed = true
	assert_false(keymap.held("snap_invert_hold", release), "its own release says it is up")


func test_the_draw_hints_name_the_bound_key():
	var hud = rig.plugin.hud
	var keymap = rig.plugin._keymap
	assert_string_contains(hud._build_shortcuts_text({"tool": 0, "mode": 1}), "Hold Ctrl:")
	assert_string_contains(hud._build_shortcuts_text({"tool": 0, "mode": 2}), "Hold Ctrl:")
	keymap.set_binding("snap_invert_hold", KEY_SHIFT)
	assert_string_contains(hud._build_shortcuts_text({"tool": 0, "mode": 1}), "Hold Shift:")
	keymap.set_binding("snap_invert_hold", KEY_CTRL)
