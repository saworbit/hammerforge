extends GutTest

## The command surfaces free transform is reachable from, and the contracts that
## keep them wired: keymap bindings, shared dispatch, the viewport input ladder,
## the context menu, the floating toolbar, and the dock.
##
## Undo dispatches by method name on LevelRoot, so a typo in one of those strings
## would leave the command working and its undo entry silently absent. These
## tests exist mostly to make that impossible.

const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HFTransformSystemScript = preload("res://addons/hammerforge/systems/hf_transform_system.gd")
const HFDockBrushHandlerScript = preload("res://addons/hammerforge/dock_brush_handler.gd")
const HFPluginGestureRecoveryScript = preload("res://addons/hammerforge/plugin_gesture_recovery.gd")
const HFLevelIOScript = preload("res://addons/hammerforge/hflevel_io.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")

const PluginRig = preload("res://tests/support/plugin_rig.gd")

const TRANSFORM_ACTIONS := ["rotate_ccw", "rotate_cw", "flip_selection", "reset_rotation"]
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const TOLERANCE := Vector3(0.01, 0.01, 0.01)
## Close enough to call an offset exact: far finer than any grid step.
const EXACT := Vector3(0.0001, 0.0001, 0.0001)
const CUSTOM := HFTransformSystemScript.PivotMode.CUSTOM
const PIVOT_LEVEL_PATH := "user://test_transform_commands_pivot.hflevel"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _pick(action: String) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit(action)


func _box_a(root: Node) -> Node3D:
	return root.find_brush_by_id("a")


func _level_state(root: Node) -> String:
	return var_to_str(root.capture_state(false))


# ===========================================================================
# Keymap
# ===========================================================================


func test_every_transform_action_has_a_default_binding():
	var keymap := HFKeymap.new()
	keymap._bindings = HFKeymap._default_bindings()
	for action in TRANSFORM_ACTIONS:
		assert_true(keymap.get_all_bindings().has(action), "%s must ship with a binding" % action)
		assert_ne(keymap.get_display_string(action), "?", "%s must render a shortcut" % action)


func test_transform_actions_land_in_their_own_palette_category():
	for action in TRANSFORM_ACTIONS:
		assert_eq(HFKeymap.get_category(action), "Transform", action)


func test_the_palette_renders_the_transform_category():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/hf_hotkey_palette.gd")
	assert_true(
		source.contains('"Transform"'),
		"a category the keymap emits but the palette never orders would never be drawn"
	)


func test_transform_actions_have_readable_labels():
	for action in TRANSFORM_ACTIONS:
		var label := HFKeymap.get_action_label(action)
		assert_ne(label, action, "%s must have a written label, not its raw name" % action)
		assert_false(label.contains("_"), "%s label should read as prose" % action)


func test_no_transform_binding_collides_with_another_action():
	var keymap := HFKeymap.new()
	keymap._bindings = HFKeymap._default_bindings()
	var bindings: Dictionary = keymap.get_all_bindings()
	for action in TRANSFORM_ACTIONS:
		var binding: Dictionary = bindings[action]
		for other in bindings:
			if other == action:
				continue
			# paint_ramp deliberately shares R: the router only dispatches it in
			# paint mode, and gates the whole transform group on paint mode being
			# off. Every other collision would be two live commands on one key.
			if other == "paint_ramp":
				continue
			assert_false(
				_same_chord(binding, bindings[other]),
				"%s and %s are bound to the same chord" % [action, other]
			)


func _same_chord(a: Dictionary, b: Dictionary) -> bool:
	for key in ["keycode", "ctrl", "shift", "alt", "meta"]:
		var default_value: Variant = 0 if key == "keycode" else false
		if a.get(key, default_value) != b.get(key, default_value):
			return false
	return true


# ===========================================================================
# Shared dispatch
# ===========================================================================


func test_transform_actions_require_an_existing_level():
	for action in TRANSFORM_ACTIONS:
		assert_true(
			HFPluginCommands.requires_existing_root(action),
			"%s changes scene content, so it must not create a level as a side effect" % action
		)


## Each transform action, picked from the command palette, reaches its command
## with its own direction: the box turns 15 degrees one way and back, has its
## rotation cleared, and mirrors across X. The pivot is the world origin, so
## every step shows in where the box sits as well as which way it faces.
func test_the_palette_runs_every_transform_action():
	assert_not_null(rig.plugin, rig.error())
	var root = await rig.make_level()
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.WORLD_ORIGIN
	rig.select([rig.box(root, "a", Vector3(6, 0, 0))])
	var start: Vector3 = _box_a(root).global_position
	var turn := Basis(Vector3.UP, deg_to_rad(root.rotate_snap_degrees))

	_pick("rotate_ccw")
	assert_almost_eq(_box_a(root).global_position, turn * start, TOLERANCE, "Rotate CCW")
	_pick("rotate_cw")
	assert_almost_eq(_box_a(root).global_position, start, TOLERANCE, "Rotate CW undoes it")
	_pick("rotate_cw")
	assert_almost_eq(_box_a(root).global_position, turn.inverse() * start, TOLERANCE, "and goes on")
	assert_false(_box_a(root).global_basis.is_equal_approx(Basis()), "the box is turned")

	var turned_at: Vector3 = _box_a(root).global_position
	_pick("reset_rotation")
	assert_true(_box_a(root).global_basis.is_equal_approx(Basis()), "Reset Rotation clears it")
	assert_almost_eq(_box_a(root).global_position, turned_at, TOLERANCE, "where it stands")

	_pick("flip_selection")
	assert_almost_eq(
		_box_a(root).global_position,
		Vector3(-turned_at.x, turned_at.y, turned_at.z),
		TOLERANCE,
		"Flip mirrors it across X"
	)
	await rig.leave_level(root)


# ===========================================================================
# Undo boundary
# ===========================================================================


func test_level_root_exposes_the_methods_undo_dispatches_by_name():
	# HFUndoHelper resolves these with has_method() and silently does nothing when
	# the lookup fails, so a rename here would cost the whole undo entry.
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	for method_name in [
		"rotate_managed_nodes",
		"flip_managed_nodes",
		"mirror_copy_managed_nodes",
		"resolve_mirror_copy_pivot",
		"reset_managed_rotation",
		"create_radial_array",
		"create_grid_array",
		"resolve_transform_pivot",
		"transform_axis_index",
	]:
		assert_true(root.has_method(method_name), "LevelRoot must expose %s" % method_name)


## Rotate, Flip and Reset Rotation each leave one undo step, Ctrl+Z puts the
## level back as it was, and Ctrl+Shift+Z does the command again.
func test_edit_actions_commit_through_the_undo_helper():
	var root = await rig.make_level()
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.WORLD_ORIGIN
	rig.box(root, "a", Vector3(6, 0, 0))
	# Turned already, so Reset Rotation has something to clear.
	_box_a(root).rotation_degrees = Vector3(0, 30, 0)
	var undo = rig.undo()
	for action in TRANSFORM_ACTIONS:
		if action == "rotate_cw":
			continue
		rig.select([_box_a(root)])
		undo.clear()
		var before := _level_state(root)
		_pick(action)
		var after := _level_state(root)
		assert_ne(after, before, "%s changed the level" % action)
		assert_eq(undo.step_count(), 1, "%s is one undo step" % action)
		undo.press_undo()
		assert_eq(_level_state(root), before, "Ctrl+Z puts the level back after %s" % action)
		undo.press_redo()
		assert_eq(_level_state(root), after, "and Ctrl+Shift+Z does %s again" % action)
	await rig.leave_level(root)


# ===========================================================================
# Mirror Copy (#1434)
# ===========================================================================


func _brush_places(root: Node) -> Array:
	var out: Array = []
	for brush in root.draft_brushes_node.get_children():
		if root.is_brush_node(brush):
			var p: Vector3 = brush.global_position
			out.append("%.3f,%.3f,%.3f" % [p.x, p.y, p.z])
	out.sort()
	return out


## Alt+M with X and Z ticked: the box stays, three mirrored copies join it in the
## selection, and the whole of it is one undo step that Ctrl+Z takes back out and
## Ctrl+Shift+Z puts back as it was.
func test_alt_m_mirror_copies_the_selection_in_one_undo_step():
	var root = await rig.make_level()
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.WORLD_ORIGIN
	root.mirror_copy_at_edge = false
	root.mirror_copy_axes = 5
	rig.select([rig.box(root, "a", Vector3(6, 0, 2))])
	var undo = rig.undo()
	undo.clear()
	var before := _level_state(root)

	assert_eq(rig.forward(PluginRig.key_for("mirror_copy")), STOP, "Alt+M is taken")

	assert_eq(
		_brush_places(root),
		["-6.000,0.000,-2.000", "-6.000,0.000,2.000", "6.000,0.000,-2.000", "6.000,0.000,2.000"],
		"the box and a copy across X, across Z and across both"
	)
	assert_eq(undo.step_count(), 1, "one undo step")
	assert_eq(rig.plugin.hf_selection.size(), 4, "the copies join the box in the selection")
	assert_almost_eq(_box_a(root).global_position, Vector3(6, 0, 2), TOLERANCE, "the box stays")
	var after := _level_state(root)
	undo.press_undo()
	assert_eq(_level_state(root), before, "one Ctrl+Z removes every copy")
	undo.press_redo()
	assert_eq(_level_state(root), after, "and Ctrl+Shift+Z brings them back as they were")
	await rig.leave_level(root)


## The Transform row's boxes are the level's settings, and its button runs the
## command the key runs.
func test_the_dock_row_sets_the_axes_and_its_button_makes_the_copies():
	var root = await rig.make_level()
	var dock = rig.plugin.dock
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.WORLD_ORIGIN
	dock.mirror_copy_x_check.button_pressed = true
	dock.mirror_copy_y_check.button_pressed = true
	dock.mirror_copy_z_check.button_pressed = false
	dock.mirror_copy_edge_check.button_pressed = false
	assert_eq(root.mirror_copy_axes, 3, "X and Y")
	assert_false(root.mirror_copy_at_edge, "through the pivot")
	rig.select([rig.box(root, "a", Vector3(6, 4, 0))])

	dock.mirror_copy_btn.pressed.emit()

	assert_eq(
		_brush_places(root),
		["-6.000,-4.000,0.000", "-6.000,4.000,0.000", "6.000,-4.000,0.000", "6.000,4.000,0.000"]
	)
	await rig.leave_level(root)


func test_mirror_copy_with_no_axis_ticked_says_so_and_changes_nothing():
	var root = await rig.make_level()
	root.mirror_copy_axes = 0
	rig.select([rig.box(root, "a", Vector3(6, 0, 0))])
	var undo = rig.undo()
	undo.clear()
	var before := _level_state(root)
	rig.clear_toasts()

	_pick("mirror_copy")

	assert_eq(_level_state(root), before, "no copy")
	assert_eq(undo.step_count(), 0, "and no step")
	assert_has(rig.toasts(), "Mirror Copy: tick X, Y or Z in Selection Tools first")
	await rig.leave_level(root)


# ===========================================================================
# Offset (#1441)
# ===========================================================================


func _popup():
	return rig.plugin._quick_property


func _lamp(root: Node, at: Vector3) -> Node3D:
	var lamp = DraftEntityScript.new()
	lamp.name = "lamp"
	lamp.entity_type = "light_point"
	lamp.entity_class = "light_point"
	root.add_entity(lamp)
	lamp.global_position = at
	return lamp


## Type `offset` into the open Offset popup, choose World or Local, and press
## Enter in the last field, as a mapper does.
func _type_offset(offset: Vector3, local := false) -> void:
	var popup = _popup()
	var choice: Button = popup._local_button.get_parent().get_child(1 if local else 0)
	choice.button_pressed = true
	for i in 3:
		popup._spinboxes[i].get_line_edit().text = str(offset[i])
	_press_enter_in_popup()


func _press_enter_in_popup() -> void:
	var line_edit: LineEdit = _popup()._spinboxes[2].get_line_edit()
	line_edit.gui_input.emit(PluginRig.key(KEY_ENTER))


## The vertices of `brush` on its side facing `direction`, picked in vertex mode.
func _pick_vertices_toward(root: Node, brush: Node, direction: Vector3) -> void:
	var vs = root.vertex_system
	vs.clear_selection()
	var verts: PackedVector3Array = vs.get_brush_vertices(brush)
	var furthest := -INF
	for v in verts:
		furthest = maxf(furthest, direction.dot(v))
	for i in verts.size():
		if absf(direction.dot(verts[i]) - furthest) < 0.001:
			vs.select_vertex(str(brush.brush_id), i, true)


## The tool to put back after a test that changed it, as the rig is shared.
func _restore_tool(was_select: bool) -> void:
	if was_select:
		rig.plugin.dock.tool_select.button_pressed = true
	else:
		rig.plugin.dock.tool_draw.button_pressed = true


## Alt+G opens the popup on two brushes and an entity, and (0, 3.25, 0) moves
## all three by exactly that, off the grid, in one undo step.
func test_offset_moves_brushes_and_an_entity_by_exactly_what_was_typed():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(0, 0, 0))
	var b = rig.box(root, "b", Vector3(8, 0, 0))
	var lamp := _lamp(root, Vector3(-6, 1, 2))
	rig.select([a, b, lamp])
	var undo = rig.undo()
	undo.clear()
	var before := _level_state(root)
	var starts := [a.global_position, b.global_position, lamp.global_position]

	assert_eq(rig.forward(PluginRig.key_for("offset_selection")), STOP, "Alt+G is taken")
	assert_true(_popup().is_active(), "and opens the Offset popup")
	_type_offset(Vector3(0, 3.25, 0))

	assert_false(_popup().is_active(), "Enter closes it")
	var moved := [a.global_position, b.global_position, lamp.global_position]
	for i in 3:
		assert_almost_eq(moved[i], starts[i] + Vector3(0, 3.25, 0), EXACT, "object %d" % i)
	assert_eq(undo.step_count(), 1, "one undo step")
	undo.press_undo()
	assert_eq(_level_state(root), before, "Ctrl+Z puts all three back")
	await rig.leave_level(root)


## Local goes along the brush's own axes: a box turned a quarter about Y goes 2
## along its own X, which is the world's -Z. World on the same box goes along X.
func test_a_local_offset_goes_along_a_turned_brush_s_own_axes():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	root.rotate_managed_nodes(["a"], [], 1, 90.0, a.global_position)
	rig.select([a])
	var start: Vector3 = a.global_position
	var own_x: Vector3 = a.global_basis.x.normalized()
	assert_almost_eq(own_x, Vector3(0, 0, -1), TOLERANCE, "the box's own X is the world's -Z")

	rig.forward(PluginRig.key_for("offset_selection"))
	_popup()._local_button.button_pressed = true
	assert_false(_popup().is_showing_no_shared_axes(), "one brush has axes of its own")
	_type_offset(Vector3(2, 0, 0), true)
	assert_almost_eq(a.global_position, start + own_x * 2.0, EXACT, "2 along its own X")

	rig.forward(PluginRig.key_for("offset_selection"))
	_type_offset(Vector3(2, 0, 0), false)
	assert_almost_eq(
		a.global_position, start + own_x * 2.0 + Vector3(2, 0, 0), EXACT, "World goes along X"
	)
	await rig.leave_level(root)


## Two brushes facing different ways share no axes, so Local says so and goes
## along the world's.
func test_local_on_a_selection_with_no_shared_axes_says_so_and_uses_the_world_s():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	var b = rig.box(root, "b", Vector3(-6, 0, 0))
	root.rotate_managed_nodes(["a"], [], 1, 90.0, a.global_position)
	rig.select([a, b])
	var starts := [a.global_position, b.global_position]

	rig.forward(PluginRig.key_for("offset_selection"))
	_popup()._local_button.button_pressed = true
	assert_true(_popup().is_showing_no_shared_axes(), "the popup says Local has no axes to go by")
	_type_offset(Vector3(2, 0, 0), true)

	assert_almost_eq(a.global_position, starts[0] + Vector3(2, 0, 0), EXACT)
	assert_almost_eq(b.global_position, starts[1] + Vector3(2, 0, 0), EXACT)
	await rig.leave_level(root)


## The fields keep the last offset and its axes, so a repeat is Alt+G, Enter.
func test_the_popup_opens_on_the_last_offset_so_alt_g_enter_repeats_it():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(0, 0, 0))
	rig.select([a])
	var start: Vector3 = a.global_position
	rig.forward(PluginRig.key_for("offset_selection"))
	_type_offset(Vector3(1.5, 0, -0.25))

	rig.forward(PluginRig.key_for("offset_selection"))
	var popup = _popup()
	assert_eq(popup._spinboxes[0].value, 1.5, "X is the last offset's")
	assert_eq(popup._spinboxes[2].value, -0.25, "and Z")
	assert_false(popup.is_local(), "on the axes it went along")
	_press_enter_in_popup()
	assert_almost_eq(a.global_position, start + Vector3(3, 0, -0.5), EXACT, "twice over")
	await rig.leave_level(root)


## The popup stays open while the Scene tree changes the selection. If a Godot
## node joins it, Enter moves nothing rather than the HammerForge half.
func test_enter_on_a_selection_that_became_mixed_moves_nothing():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(0, 0, 0))
	rig.select([a])
	rig.forward(PluginRig.key_for("offset_selection"))
	assert_true(_popup().is_active())
	rig.select([a, rig.native_node()])
	rig.clear_toasts()
	var before: Vector3 = a.global_position

	_type_offset(Vector3(0, 2, 0))

	assert_eq(a.global_position, before, "the brush stays")
	assert_has(rig.toasts(), "Edit HammerForge and Godot nodes separately")
	await rig.leave_level(root)


## Mid-draw the typed numbers are the draw's: Alt+G opens nothing and moves
## nothing, and the draw goes on.
func test_alt_g_during_a_draw_does_nothing():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	var dock = rig.plugin.dock
	var was_select: bool = dock.get_tool() == 1
	dock.tool_draw.button_pressed = true
	rig.select([a])
	var start := rig.camera.unproject_position(Vector3(-4, 0, -4))
	rig.forward(PluginRig.motion(start))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start))
	assert_true(root.input_state.is_dragging(), "the draw is under way")
	var before: Vector3 = a.global_position

	rig.forward(PluginRig.key_for("offset_selection"))

	assert_false(_popup().is_active(), "no popup")
	assert_eq(a.global_position, before, "nothing moved")
	assert_true(root.input_state.is_dragging(), "and the draw goes on")
	rig.escape_to_idle(root)
	_restore_tool(was_select)
	await rig.leave_level(root)


## In vertex mode Offset moves the picked vertices. A move that would dent the
## brush changes nothing, says why and leaves no step; a face's vertices moved
## out together are one step.
func test_vertex_offsets_move_the_picked_vertices_or_say_why_not():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(0, 0, 0))
	rig.select([a])
	rig.plugin._toggle_vertex_mode(root)
	var vs = root.vertex_system
	var corner: int = Array(vs.get_brush_vertices(a)).find(Vector3(2, 2, 2))
	assert_gt(corner, -1, "the box has a corner at (2, 2, 2)")
	vs.select_vertex("a", corner)
	var undo = rig.undo()
	undo.clear()
	var before := _level_state(root)
	rig.clear_toasts()

	rig.forward(PluginRig.key_for("offset_selection"))
	assert_true(_popup().is_active(), "Alt+G opens on the picked vertex")
	_type_offset(Vector3(-3, -3, -3))

	assert_eq(_level_state(root), before, "pushed into the box, the corner is refused")
	assert_eq(undo.step_count(), 0, "with no step")
	assert_has(rig.toasts(), "Offset rejected: would create a non-convex brush", "and a reason")

	_pick_vertices_toward(root, a, Vector3.UP)
	rig.forward(PluginRig.key_for("offset_selection"))
	_type_offset(Vector3(0, 1, 0))
	assert_eq(undo.step_count(), 1, "the top face's four, raised together, are one step")
	assert_true(vs.get_brush_vertices(a).has(Vector3(2, 3, 2)), "and the top went up")
	undo.press_undo()
	assert_eq(_level_state(root), before, "which Ctrl+Z takes back")
	rig.plugin._toggle_vertex_mode(root)
	await rig.leave_level(root)


## A face picked in Face Select moves by its corners, so the box grows to meet
## it, as one step.
func test_an_offset_moves_a_picked_face_by_its_corners():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(0, 0, 0))
	var dock = rig.plugin.dock
	dock.face_select_mode.button_pressed = true
	var top := -1
	for i in a.faces.size():
		if a.faces[i].normal.y > 0.99:
			top = i
	root.toggle_face_selection(a, top, true, false)
	var undo = rig.undo()
	undo.clear()

	assert_eq(rig.forward(PluginRig.key_for("offset_selection")), STOP)
	assert_true(_popup().is_active(), "Alt+G opens on the picked face")
	_type_offset(Vector3(0, 1.5, 0))

	var tallest := -INF
	for v in root.vertex_system.get_brush_vertices(a):
		tallest = maxf(tallest, v.y)
	assert_almost_eq(tallest, 3.5, 0.0001, "the top went up 1.5")
	assert_eq(undo.step_count(), 1, "in one step")
	dock.face_select_mode.button_pressed = false
	await rig.leave_level(root)


# ===========================================================================
# Pick Pivot (#1442)
# ===========================================================================


## Arm Pick Pivot from the palette and click a few pixels off where `at` is on
## screen, so the snap has to find it.
func _pick_pivot_at(at: Vector3) -> int:
	_pick("pick_pivot")
	var screen := rig.camera.unproject_position(at) + Vector2(3, -2)
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, screen))


## Whether a brush of the level stands at `at`.
func _brush_at(root: Node, at: Vector3) -> bool:
	for brush in root.draft_brushes_node.get_children():
		if root.is_brush_node(brush) and brush.global_position.distance_to(at) < 0.01:
			return true
	return false


## The corner of a box picked as the pivot, R turns the box about it, and the
## corner stays where it was.
func test_r_turns_a_box_about_a_picked_corner():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	var corner := Vector3(8, 2, 2)

	assert_eq(_pick_pivot_at(corner), STOP, "the click is the pick's")
	assert_false(rig.plugin._pivot_pick_armed, "one click, then the pick is spent")
	assert_eq(root.transform_pivot_mode, CUSTOM, "Pick is the Pivot now")
	assert_almost_eq(root.transform_pivot_point, corner, EXACT, "on the corner itself")

	rig.select([a])
	rig.forward(PluginRig.key_for("rotate_ccw"))
	assert_false(a.global_basis.is_equal_approx(Basis()), "the box turned")
	assert_almost_eq(a.global_transform * Vector3(2, 2, 2), corner, TOLERANCE, "about the corner")
	await rig.leave_level(root)


## Flip with a face centre picked mirrors across the plane through it, normal to
## the flip axis: the box's +X face centre is at x = 8, so the box goes to 10.
func test_flip_mirrors_across_a_plane_through_a_picked_face_centre():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	_pick_pivot_at(Vector3(8, 0, 0))
	assert_almost_eq(root.transform_pivot_point, Vector3(8, 0, 0), EXACT, "the face centre")

	rig.select([a])
	rig.forward(PluginRig.key_for("flip_selection"))
	assert_almost_eq(a.global_position, Vector3(10, 0, 0), TOLERANCE)
	await rig.leave_level(root)


## A radial array laid out with Pick as the Pivot rings the picked point.
func test_a_radial_array_turns_about_the_picked_pivot():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	var pivot := Vector3(4, -2, 2)
	_pick_pivot_at(pivot)
	assert_almost_eq(root.transform_pivot_point, pivot, EXACT, "a bottom corner")

	var dock = rig.plugin.dock
	rig.select([a])
	dock.set_selection_nodes([a])
	dock.dup_mode_opt.selected = 1
	HFDockBrushHandlerScript.on_duplicate_array_mode_changed(dock, 1)
	dock.dup_axis_opt.selected = 1
	dock.dup_count_spin.set_value_no_signal(3.0)
	dock.dup_step_spin.set_value_no_signal(90.0)
	HFDockBrushHandlerScript.on_create_duplicate_array(dock)

	var record = root.duplicator_for_selection(["a"])
	assert_not_null(record, "the array was made")
	if record == null:
		await rig.leave_level(root)
		return
	assert_almost_eq(record.pivot, pivot, EXACT, "about the picked point")
	for quarter in [1, 2, 3]:
		var turn := Basis(Vector3.UP, deg_to_rad(90.0 * quarter))
		var at: Vector3 = pivot + turn * (Vector3(6, 0, 0) - pivot)
		assert_true(_brush_at(root, at), "a copy %d quarters round, at %s" % [quarter, at])
	await rig.leave_level(root)


## Mirror Copy through the pivot, rather than at the selection's edge, mirrors
## across the picked point.
func test_mirror_copy_through_the_pivot_uses_the_picked_point():
	var root = await rig.make_level()
	var a = rig.box(root, "a", Vector3(6, 0, 0))
	root.mirror_copy_at_edge = false
	root.mirror_copy_axes = 1
	_pick_pivot_at(Vector3(4, 0, 0))
	rig.select([a])
	rig.forward(PluginRig.key_for("mirror_copy"))
	assert_eq(_brush_places(root), ["2.000,0.000,0.000", "6.000,0.000,0.000"])
	await rig.leave_level(root)


## The picked point is saved with the level, and choosing Selection stops it
## being used without forgetting it.
func test_the_picked_pivot_survives_a_save_and_selection_stops_using_it():
	var root = await rig.make_level()
	rig.box(root, "a", Vector3(6, 0, 0))
	root.transform_pivot_point = Vector3(3, 1, -2)
	root.transform_pivot_mode = CUSTOM
	var saved: int = HFLevelIOScript.save_to_path(
		PIVOT_LEVEL_PATH, root._capture_hflevel_state(), false
	)
	assert_eq(saved, OK, "the level saves")
	root.transform_pivot_point = Vector3.ZERO
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.SELECTION_CENTER

	assert_true(root.load_hflevel(PIVOT_LEVEL_PATH), "and loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PIVOT_LEVEL_PATH))
	assert_eq(root.transform_pivot_mode, CUSTOM, "Pick comes back")
	assert_almost_eq(root.transform_pivot_point, Vector3(3, 1, -2), EXACT, "with its point")
	assert_almost_eq(root.resolve_transform_pivot(["a"], []), Vector3(3, 1, -2), EXACT)
	assert_eq(int(rig.plugin.dock.transform_pivot_opt.selected), CUSTOM, "and the dock shows it")

	rig.plugin.dock.transform_pivot_opt.item_selected.emit(0)
	var a = root.find_brush_by_id("a")
	assert_almost_eq(root.resolve_transform_pivot(["a"], []), a.global_position, EXACT)
	assert_almost_eq(root.transform_pivot_point, Vector3(3, 1, -2), EXACT, "kept for later")
	await rig.leave_level(root)


## Choosing Pick in the dock arms the click, the cross shows while Pick is the
## Pivot, and Clear Pivot takes both back to Selection.
func test_the_dock_option_arms_the_pick_and_clear_pivot_goes_back_to_selection():
	var root = await rig.make_level()
	rig.box(root, "a", Vector3(6, 0, 0))
	var dock = rig.plugin.dock
	assert_eq(dock.PIVOT_PICK, CUSTOM, "the option's Pick is the CUSTOM mode")
	dock.transform_pivot_opt.select(CUSTOM)
	dock.transform_pivot_opt.item_selected.emit(CUSTOM)
	assert_true(rig.plugin._pivot_pick_armed, "choosing Pick arms the click")
	var corner := rig.camera.unproject_position(Vector3(8, 2, 2))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, corner))
	var marker: MeshInstance3D = rig.plugin._pivot_marker.get_mesh_instance()
	assert_not_null(marker, "the cross is drawn")
	if marker:
		assert_eq(marker.get_parent(), root, "on the level")
		assert_almost_eq(
			marker.mesh.get_aabb().get_center(), Vector3(8, 2, 2), EXACT, "at the pivot"
		)

	_pick("clear_pivot")
	assert_eq(root.transform_pivot_mode, HFTransformSystemScript.PivotMode.SELECTION_CENTER)
	assert_eq(int(dock.transform_pivot_opt.selected), 0, "the dock follows")
	assert_null(rig.plugin._pivot_marker.get_mesh_instance(), "and the cross goes")
	await rig.leave_level(root)


## A click with nothing in reach says so and leaves the pick armed for another.
func test_a_pick_with_nothing_in_reach_says_so_and_stays_armed():
	var root = await rig.make_level()
	rig.box(root, "a", Vector3(6, 0, 0))
	rig.clear_toasts()
	_pick("pick_pivot")
	var far := rig.camera.unproject_position(Vector3(-12, 0, -8))
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, far)), STOP, "the pick's")
	assert_true(rig.plugin._pivot_pick_armed, "still armed")
	assert_ne(root.transform_pivot_mode, CUSTOM, "with nothing picked")
	assert_has(
		rig.toasts(), "Pick Pivot: no brush vertex, edge or face there. Click nearer one, or Esc"
	)
	await rig.leave_level(root)


## The armed pick is never left behind out of sight: Escape, a right click, a
## tool change, focus leaving the editor and a scene switch all put it away.
func test_the_armed_pick_goes_with_escape_rmb_a_tool_change_focus_loss_and_a_scene_switch():
	var root = await rig.make_level()
	rig.box(root, "a", Vector3(6, 0, 0))
	var plugin = rig.plugin
	var was_select: bool = plugin.dock.get_tool() == 1

	_pick("pick_pivot")
	assert_true(plugin.dock._mode_label.text.contains("Pick Pivot"), "the mode banner says so")
	assert_eq(rig.forward(PluginRig.key(KEY_ESCAPE)), STOP, "Escape is the pick's")
	assert_false(plugin._pivot_pick_armed, "Escape")
	assert_false(plugin.dock._mode_label.text.contains("Pick Pivot"), "and the banner moves on")

	_pick("pick_pivot")
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true))
	assert_false(plugin._pivot_pick_armed, "a right click")

	_pick("pick_pivot")
	rig.forward(PluginRig.key_for("tool_draw"))
	assert_false(plugin._pivot_pick_armed, "a tool change")

	_pick("pick_pivot")
	HFPluginGestureRecoveryScript.after_application_focus_loss(plugin)
	assert_false(plugin._pivot_pick_armed, "focus leaving the editor")

	_pick("pick_pivot")
	plugin._on_scene_changed(rig.scene_root)
	assert_false(plugin._pivot_pick_armed, "a scene switch")

	_pick("pick_pivot")
	assert_true(plugin._cancel_escape_step(root), "the Escape ladder has a rung for it")
	assert_false(plugin._pivot_pick_armed)
	assert_ne(root.transform_pivot_mode, CUSTOM, "and none of them picked anything")
	_restore_tool(was_select)
	await rig.leave_level(root)


# ===========================================================================
# Viewport input ladder
# ===========================================================================


## R is both Rotate CCW and the paint Ramp tool. In paint mode it picks the
## ramp and leaves the selected box alone; out of it, it turns the box.
func test_the_transform_group_is_gated_on_paint_mode():
	var root = await rig.make_level()
	var box = rig.box(root, "a", Vector3(6, 0, 0))
	rig.select([box])
	rig.plugin._toggle_paint_mode()
	assert_true(rig.plugin.dock.is_paint_mode_enabled(), "paint mode is on")
	rig.plugin.dock.set_paint_tool(0)
	var rotate := PluginRig.key_for("rotate_ccw")
	assert_eq(rig.forward(rotate), STOP, "R is taken in paint mode")
	assert_eq(rig.plugin.dock.get_paint_tool_id(), 2, "and picks the ramp tool")
	assert_true(_box_a(root).global_basis.is_equal_approx(Basis()), "without turning the box")
	for action in TRANSFORM_ACTIONS:
		rig.forward(PluginRig.key_for(action))
		assert_true(
			_box_a(root).global_transform.is_equal_approx(Transform3D(Basis(), Vector3(6, 0, 0))),
			"%s does nothing in paint mode" % action
		)

	rig.plugin._toggle_paint_mode()
	assert_eq(rig.forward(rotate), STOP)
	assert_false(_box_a(root).global_basis.is_equal_approx(Basis()), "out of it, R turns the box")
	await rig.leave_level(root)


## With a brush and a Godot node selected together, every transform key is
## refused before its command runs: the key is consumed, the user is told why,
## and the brush stays where it was.
func test_every_transform_shortcut_asks_the_selection_guard_first():
	var root = await rig.make_level()
	var box = rig.box(root, "a", Vector3(6, 0, 0))
	rig.select([box, rig.native_node()])
	var before: Transform3D = _box_a(root).global_transform
	for action in TRANSFORM_ACTIONS:
		rig.clear_toasts()
		assert_eq(rig.forward(PluginRig.key_for(action)), STOP, "%s is consumed" % action)
		assert_has(rig.toasts(), "Edit HammerForge and Godot nodes separately", action)
		assert_true(
			_box_a(root).global_transform.is_equal_approx(before), "%s did not run" % action
		)
	await rig.leave_level(root)


# ===========================================================================
# Menus and toolbars
# ===========================================================================


func test_the_viewport_context_menu_offers_every_transform_action():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd"
	)
	for action in TRANSFORM_ACTIONS:
		assert_true(source.contains('action = "%s"' % action), "%s must be reachable" % action)
	for label in ["Rotate CCW", "Rotate CW", "Flip", "Reset Rotation"]:
		assert_true(source.contains('add_item("%s"' % label), "%s must be listed" % label)


func test_context_menu_transform_ids_are_unique():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd"
	)
	var seen := {}
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const _ID_"):
			continue
		var value := trimmed.get_slice(":=", 1).strip_edges()
		assert_false(seen.has(value), "menu id %s is used twice" % value)
		seen[value] = true


func test_the_context_toolbar_offers_every_transform_action():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/hf_context_toolbar.gd")
	for action in TRANSFORM_ACTIONS:
		assert_true(source.contains('"%s"' % action), "%s must have a toolbar button" % action)
	assert_true(source.contains('_add_group_label(section, "Transform")'))


# ===========================================================================
# Dock
# ===========================================================================


func test_the_dock_reaches_the_same_level_root_methods():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd")
	for method_name in [
		'"rotate_managed_nodes"',
		'"flip_managed_nodes"',
		'"reset_managed_rotation"',
		'"create_radial_array"',
		'"create_grid_array"',
	]:
		assert_true(source.contains(method_name), "the dock must reach %s" % method_name)


func test_the_dock_transform_controls_are_connected():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/selection_tools_builder.gd"
	)
	for connection in [
		"dock._on_rotate_selection.bind(1)",
		"dock._on_rotate_selection.bind(-1)",
		"dock._on_flip_selection",
		"dock._on_reset_rotation",
		"dock._on_duplicate_array_mode_changed",
		"dock._on_rotate_snap_changed",
		"dock._on_transform_pivot_changed",
		"dock._on_mirror_copy_axes_changed",
		"dock._on_mirror_copy_edge_toggled",
		"dock._on_mirror_copy",
	]:
		assert_true(source.contains(connection), "%s must be wired" % connection)


func test_the_dock_reflects_saved_transform_settings():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	for property in [
		"rotate_snap_degrees", "transform_pivot_mode", "mirror_copy_axes", "mirror_copy_at_edge"
	]:
		assert_true(
			source.contains('_root_has_property("%s")' % property),
			"%s must be read back onto the dock when a level connects" % property
		)


# ===========================================================================
# Settings persistence
# ===========================================================================


func test_transform_settings_travel_with_the_level_not_the_undo_snapshot():
	# `rotate_snap_degrees` and `transform_pivot_mode` are editor settings, so they
	# belong in the settings bundle that goes into the .hflevel file — the same
	# place `texture_lock` lives — and not in the per-action undo snapshot.
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.rotate_snap_degrees = 45.0
	root.transform_pivot_mode = 2
	root.mirror_copy_axes = 6
	root.mirror_copy_at_edge = false
	var bundle: Dictionary = root.capture_full_state()
	var settings: Dictionary = bundle.get("settings", {})
	assert_true(settings.has("rotate_snap_degrees"), "the rotate step must be saved with the level")
	assert_true(settings.has("transform_pivot_mode"), "the pivot mode must be saved with the level")
	assert_true(settings.has("mirror_copy_axes"), "so must the Mirror Copy axes")
	assert_true(settings.has("mirror_copy_at_edge"), "and where its planes stand")
	assert_true(settings.has("texture_lock"), "the reference setting must still be there")
	root.rotate_snap_degrees = 15.0
	root.transform_pivot_mode = 0
	root.mirror_copy_axes = 1
	root.mirror_copy_at_edge = true
	root.restore_full_state(bundle)
	assert_almost_eq(root.rotate_snap_degrees, 45.0, 0.001)
	assert_eq(root.transform_pivot_mode, 2)
	assert_eq(root.mirror_copy_axes, 6)
	assert_false(root.mirror_copy_at_edge)


func test_the_transform_subsystem_is_built_with_the_other_editor_systems():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	assert_not_null(root.transform_system, "LevelRoot must construct the transform system")


func test_pivot_modes_are_named_the_same_way_everywhere():
	# The dock stores the OptionButton index straight into transform_pivot_mode,
	# so the option order and the enum have to agree.
	assert_eq(HFTransformSystemScript.PivotMode.SELECTION_CENTER, 0)
	assert_eq(HFTransformSystemScript.PivotMode.WORLD_ORIGIN, 1)
	assert_eq(HFTransformSystemScript.PivotMode.ACTIVE, 2)
	assert_eq(HFTransformSystemScript.PivotMode.CUSTOM, 3)
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/selection_tools_builder.gd"
	)
	var start := source.find("transform_pivot_opt = HFUIFactoryType.make_option")
	assert_gt(start, -1, "the pivot picker must exist")
	var block := source.substr(start, 200)
	assert_lt(block.find('"Selection"'), block.find('"World Origin"'))
	assert_lt(block.find('"World Origin"'), block.find('"Active"'))
	assert_lt(block.find('"Active"'), block.find('"Pick"'))
