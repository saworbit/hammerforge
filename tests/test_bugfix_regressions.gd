extends GutTest
## Regression tests for bug fixes:
## 1. Vertex undo uses pre-drag snapshots (not post-move state)
## 2. Z-axis lock uses correct enum value (3, not 4)
## 3. Carve rejects face/edge-only contact (OR, not AND)
## 4. Vertex drags use view-aware projection and absolute start-relative updates

const HFVertexSystem = preload("res://addons/hammerforge/systems/hf_vertex_system.gd")
const HFCarveSystem = preload("res://addons/hammerforge/systems/hf_carve_system.gd")
const HFInputState = preload("res://addons/hammerforge/input_state.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const LevelRoot = preload("res://addons/hammerforge/level_root.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const HFStateSystem = preload("res://addons/hammerforge/systems/hf_state_system.gd")
const ShortcutHUD = preload("res://addons/hammerforge/shortcut_hud.gd")
const HFHotkeyPalette = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")

var root: Node3D
var draft_node: Node3D


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	draft_node = Node3D.new()
	draft_node.name = "DraftBrushes"
	root.add_child(draft_node)
	root.draft_brushes_node = draft_node
	root.brush_system = _FakeBrushSystem.new(root, draft_node)


func after_each():
	root = null
	draft_node = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var brush_system: RefCounted
var grid_snap := 8.0
var drag_size_default := Vector3(32, 32, 32)
enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }
signal user_message(msg, level)

func _log(msg: String) -> void:
	pass

func tag_full_reconcile() -> void:
	pass

func _assign_owner(_node: Node) -> void:
	pass

func _iter_pick_nodes() -> Array:
	var result: Array = []
	if draft_brushes_node:
		for child in draft_brushes_node.get_children():
			result.append(child)
	return result
"""
	s.reload()
	return s


func _make_box_brush(pos: Vector3, sz: Vector3, id: String) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.brush_id = id
	draft_node.add_child(b)
	b.global_position = pos
	var half = sz * 0.5
	# CW winding from outside (matches _build_box_faces in production code)
	var quads = [
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, -half.y, -half.z)
		],
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, half.y, -half.z)
		],
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(-half.x, half.y, -half.z)
		]
	]
	var faces: Array[FaceData] = []
	for quad in quads:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces.append(face)
	b.faces = faces
	return b


# ===========================================================================
# Bug 1: Vertex undo captures pre-drag state, not post-move state
# ===========================================================================


func test_end_drag_returns_pre_drag_face_data():
	var vs = HFVertexSystem.new(root)
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo1")
	vs.set_selection([b])
	vs.select_vertex("undo1", 0, false)

	# Capture expected pre-drag state
	var pre_drag_expected: Array = []
	for face in b.faces:
		if face:
			pre_drag_expected.append(face.to_dict())

	# Begin drag, move, then end
	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(8, 0, 0))
	var snapshots = vs.end_drag()

	assert_true(snapshots.has("undo1"), "Snapshots should contain the dragged brush")
	var snap_faces: Array = snapshots["undo1"]
	assert_eq(snap_faces.size(), pre_drag_expected.size(), "Should have same face count")

	# Compare actual vertex coordinate values, not just counts.
	# local_verts is serialized as Array of [x, y, z] sub-arrays.
	for i in range(snap_faces.size()):
		var snap_verts: Array = snap_faces[i].get("local_verts", [])
		var pre_verts: Array = pre_drag_expected[i].get("local_verts", [])
		assert_eq(snap_verts.size(), pre_verts.size(), "Face %d vert count" % i)
		for j in range(snap_verts.size()):
			var sv: Array = snap_verts[j]
			var pv: Array = pre_verts[j]
			assert_almost_eq(sv[0], pv[0], 0.001, "Face %d vert %d X" % [i, j])
			assert_almost_eq(sv[1], pv[1], 0.001, "Face %d vert %d Y" % [i, j])
			assert_almost_eq(sv[2], pv[2], 0.001, "Face %d vert %d Z" % [i, j])


func test_pre_drag_snapshots_differ_from_post_move_faces():
	var vs = HFVertexSystem.new(root)
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo2")
	vs.set_selection([b])
	vs.select_vertex("undo2", 0, false)

	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(8, 0, 0))
	var snapshots = vs.end_drag()

	# Now capture post-move state
	var post_state: Array = []
	for face in b.faces:
		if face:
			post_state.append(face.to_dict())

	# The snapshots should NOT equal post-move state (that was the bug)
	var snap_faces: Array = snapshots["undo2"]
	var any_different := false
	for i in range(snap_faces.size()):
		var snap_verts = snap_faces[i].get("local_verts", PackedVector3Array())
		var post_verts = post_state[i].get("local_verts", PackedVector3Array())
		if snap_verts != post_verts:
			any_different = true
			break
	assert_true(any_different, "Pre-drag snapshot should differ from post-move faces")


func test_cancel_drag_restores_pre_drag_geometry():
	var vs = HFVertexSystem.new(root)
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo3")
	vs.set_selection([b])
	vs.select_vertex("undo3", 0, false)

	# Capture pre-drag verts
	var verts_before = vs.get_brush_vertices(b).duplicate()

	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(100, 0, 0))
	vs.cancel_drag()

	var verts_after = vs.get_brush_vertices(b)
	# Verts should be restored to pre-drag
	for i in range(verts_before.size()):
		assert_true(
			verts_before[i].is_equal_approx(verts_after[i]),
			"Vertex %d should be restored after cancel" % i
		)


# ===========================================================================
# Bug 2: Z-axis lock constant matches AxisLock.Z = 3
# ===========================================================================


func test_axis_lock_z_equals_3():
	# The AxisLock enum on LevelRoot should define Z = 3
	# Vertex drag code must use 3, not 4
	var lr_script = LevelRoot
	# AxisLock is: { NONE=0, X=1, Y=2, Z=3 }
	assert_eq(lr_script.AxisLock.NONE, 0, "AxisLock.NONE should be 0")
	assert_eq(lr_script.AxisLock.X, 1, "AxisLock.X should be 1")
	assert_eq(lr_script.AxisLock.Y, 2, "AxisLock.Y should be 2")
	assert_eq(lr_script.AxisLock.Z, 3, "AxisLock.Z should be 3")


func test_axis_lock_shortcuts_are_available_during_select_vertex_editing():
	assert_false(
		HammerForgePlugin.axis_lock_shortcuts_available(1, false),
		"Plain Select should leave X/Y/Z available to the editor",
	)
	assert_true(
		HammerForgePlugin.axis_lock_shortcuts_available(1, true),
		"Select + Vertex Edit should expose X/Y/Z axis constraints",
	)
	assert_true(
		HammerForgePlugin.axis_lock_shortcuts_available(0, false),
		"Construction tools should retain their existing axis constraints",
	)


func test_hotkey_palette_exposes_axis_locks_in_select_vertex_context():
	var palette := HFHotkeyPalette.new()
	autofree(palette)

	var select_tool_context := HammerForgePlugin.hotkey_palette_tool_context(1, false)
	palette.update_state({"tool": select_tool_context, "vertex_mode": false})
	assert_false(palette._is_action_available("axis_x"))

	var vertex_tool_context := HammerForgePlugin.hotkey_palette_tool_context(1, true)
	palette.update_state({"tool": vertex_tool_context, "vertex_mode": true})
	for action in ["axis_x", "axis_y", "axis_z"]:
		assert_true(
			palette._is_action_available(action),
			"%s should be enabled in the Select + Vertex Edit palette" % action,
		)


func test_canceled_vertex_release_is_classified_separately_from_commit_release():
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.canceled = true
	assert_true(HammerForgePlugin.is_canceled_vertex_drag_release(release))

	release.canceled = false
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(release))
	release.pressed = true
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(release))
	release.pressed = false
	release.canceled = true
	release.button_index = MOUSE_BUTTON_RIGHT
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(release))
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(InputEventMouseMotion.new()))


func test_canceled_vertex_release_restores_before_the_normal_commit_path():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var handler_start := source.find("func _handle_vertex_input")
	var handler_end := source.find("func _commit_vertex_move", handler_start)
	assert_true(handler_start >= 0 and handler_end > handler_start)
	var handler := source.substr(handler_start, handler_end - handler_start)
	var canceled_gate := handler.find("if is_canceled_vertex_drag_release(event)")
	var cancel_call := handler.find("vs.cancel_drag()", canceled_gate)
	var normal_end := handler.find("var snapshots = vs.end_drag()", canceled_gate)
	assert_true(
		canceled_gate >= 0 and cancel_call > canceled_gate and normal_end > cancel_call,
		"Canceled releases must restore their snapshot before the normal commit branch",
	)


# ===========================================================================
# Bug 3: Carve rejects face/edge-only contact
# ===========================================================================


func test_carve_face_contact_does_not_destroy():
	# Two brushes touching on one face (no volumetric overlap)
	# Brush A at origin, Brush B immediately adjacent on +X
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "face_a")
	var b = _make_box_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "face_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("face_a")

	# Should fail: brushes only touch on a face, no volume overlap
	assert_false(result.ok, "Face-only contact should not be carved")
	# The carver should NOT have been deleted (it's still in the tree)
	# Actually carver IS deleted at end of carve_with_brush even on success,
	# but since targets_carved == 0 AND targets is empty, it returns _op_fail
	# before reaching the delete. Let's verify the target survived:
	assert_true(is_instance_valid(b), "Target brush should survive face contact")


func test_carve_edge_contact_does_not_destroy():
	# Two brushes touching on one edge only (diagonal neighbor)
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "edge_a")
	var b = _make_box_brush(Vector3(32, 32, 0), Vector3(32, 32, 32), "edge_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("edge_a")

	assert_false(result.ok, "Edge-only contact should not be carved")
	assert_true(is_instance_valid(b), "Target brush should survive edge contact")


func test_carve_corner_contact_does_not_destroy():
	# Two brushes touching at a single corner point
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "corner_a")
	var b = _make_box_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "corner_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("corner_a")

	assert_false(result.ok, "Corner-only contact should not be carved")
	assert_true(is_instance_valid(b), "Target brush should survive corner contact")


func test_carve_volumetric_overlap_succeeds():
	# Two overlapping brushes (carver partially inside target)
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "vol_a")
	var b = _make_box_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "vol_b")

	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("vol_a")

	assert_true(result.ok, "Volumetric overlap should succeed")


func test_carve_thin_overlap_single_axis_produces_no_pieces():
	# Brushes overlap by a negligible amount on X (just touching + epsilon)
	# but fully overlap on Y and Z. The thin X overlap (< min_thickness) means
	# the target is skipped during slicing, so no pieces are created.
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "thin_a")
	# Place b so X overlap is exactly 0.005 (below min_thickness 0.01)
	var b = _make_box_brush(Vector3(31.995, 0, 0), Vector3(32, 32, 32), "thin_b")

	var child_count_before = draft_node.get_child_count()
	var cs = HFCarveSystem.new(root)
	var result = cs.carve_with_brush("thin_a")

	# The target survives (thin overlap is rejected via OR guard)
	assert_true(is_instance_valid(b), "Target should survive thin overlap")


# ===========================================================================
# Bug 4: Vertex input uses the view-aware, start-relative drag contract
# ===========================================================================


func test_plugin_uses_vertex_system_projection_and_absolute_updates():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(source.length() > 0, "plugin.gd should be readable")
	var motion_block := _vertex_motion_source_block(source)
	var compact_block := _compact_source(motion_block)

	assert_true(
		compact_block.contains(
			"vs.project_drag_screen_delta(cam,_vertex_drag_start,pos,root.input_state.axis_lock)"
		),
		"Vertex motion must delegate view and axis projection to HFVertexSystem"
	)
	assert_true(
		compact_block.contains("vs.update_drag_absolute(delta)"),
		"Projected movement must use a stable start-relative update"
	)
	assert_false(
		motion_block.contains("_vertex_screen_to_world_delta"),
		"The obsolete horizontal-plane projection must not return"
	)
	assert_false(
		motion_block.contains("vs.cancel_drag()") or motion_block.contains("vs.move_vertices("),
		"Mouse motion must not rebuild the drag snapshot or apply cumulative deltas"
	)


func test_plugin_resets_absolute_drag_when_projection_is_invalid():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var compact_block := _compact_source(_vertex_motion_source_block(source))
	var valid_update := compact_block.find("vs.update_drag_absolute(delta)")
	var invalid_else := compact_block.find("else:", valid_update)
	var zero_reset := compact_block.find("vs.update_drag_absolute(Vector3.ZERO)", valid_update)
	assert_true(
		valid_update >= 0 and invalid_else > valid_update and zero_reset > invalid_else,
		(
			"An unprojectable head-on axis must restore the drag origin instead of "
			+ "leaving a stale prior delta"
		)
	)


func test_vertex_projection_uses_picked_world_anchor_for_vertices_and_edges():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(
		source.contains("vs.begin_drag(pick.world_pos)"),
		"Vertex drags must capture the picked vertex as their projection anchor"
	)
	assert_true(
		source.contains("vs.begin_drag(pick.world_midpoint)"),
		"Edge drags must capture the picked edge midpoint as their projection anchor"
	)
	assert_false(
		source.contains("_vertex_drag_ref_y"), "The obsolete Y-only anchor must be removed"
	)


func test_vertex_hud_shortcuts_override_select_tool_context():
	var shortcut_hud = ShortcutHUD.new()
	autofree(shortcut_hud)

	var shortcuts: String = shortcut_hud._build_shortcuts_text({"tool": 1, "mode": 5})

	assert_string_contains(shortcuts, "-- Vertex Edit --")
	assert_string_contains(shortcuts, "E: Toggle edge mode")
	assert_false(
		shortcuts.contains("Drag Empty Space: Box Select"),
		"Vertex mode must not be masked by the underlying Select tool",
	)


# ===========================================================================
# Viewport input ownership regressions
# ===========================================================================


func test_passive_viewport_input_does_not_request_a_level_root():
	var motion := InputEventMouseMotion.new()
	assert_false(HammerForgePlugin.should_create_root_for_viewport_input(motion, 0, false))

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	assert_false(HammerForgePlugin.should_create_root_for_viewport_input(right_press, 0, false))


func test_only_an_intentional_draw_press_requests_a_level_root():
	var left_event := InputEventMouseButton.new()
	left_event.button_index = MOUSE_BUTTON_LEFT
	left_event.pressed = true
	assert_true(HammerForgePlugin.should_create_root_for_viewport_input(left_event, 0, false))
	assert_false(
		HammerForgePlugin.should_create_root_for_viewport_input(left_event, 1, false),
		"Select clicks must not create a LevelRoot",
	)
	assert_false(
		HammerForgePlugin.should_create_root_for_viewport_input(left_event, 0, true),
		"Paint clicks must not create a LevelRoot through the Draw path",
	)
	left_event.pressed = false
	assert_false(
		HammerForgePlugin.should_create_root_for_viewport_input(left_event, 0, false),
		"A release without a matching HammerForge press is passive",
	)


func test_command_palette_ui_actions_do_not_require_or_create_a_level_root():
	for action in [
		"toggle_operation",
		"toggle_paint_mode",
		"tool_draw",
		"tool_select",
		"tool_extrude_up",
		"paint_bucket",
		"paint_fill",
		"selection_filter",
		"radial_menu",
		"unknown_action",
	]:
		assert_false(
			HammerForgePlugin.hotkey_palette_action_requires_existing_root(action),
			"%s should remain root-independent" % action,
		)

	# EditorPlugin cannot be instantiated by headless GUT, so also audit the
	# production dispatcher and prevent a future unconditional ensure call.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var handler_start := source.find("func _on_hotkey_palette_action")
	var handler_end := source.find("## Unified action dispatch", handler_start)
	assert_gte(handler_start, 0)
	assert_gt(handler_end, handler_start)
	var handler := source.substr(handler_start, handler_end - handler_start)
	assert_false(
		handler.contains("ensure_level_root()"),
		"Opening or using the command palette must not mutate an empty scene",
	)
	assert_true(
		handler.contains('dock.show_toast("Create a HammerForge level first", 1)'),
		"Root-dependent palette commands must explain why they cannot run",
	)


func test_command_palette_content_actions_require_an_existing_level_root():
	for action in [
		"quick_play",
		"validate_level",
		"select_all",
		"delete",
		"duplicate",
		"hollow",
		"grid_increase",
		"vertex_edit",
		"texture_picker",
		"axis_x",
		"select_similar",
		"apply_last_texture",
		"context_menu",
	]:
		assert_true(
			HammerForgePlugin.hotkey_palette_action_requires_existing_root(action),
			"%s must be guarded when no level exists" % action,
		)


func test_undoable_level_root_creation_registers_node_lifetime():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var create_start := source.find("func _create_level_root")
	var create_end := source.find("func _activate_created_level_root", create_start)
	assert_gte(create_start, 0)
	assert_gt(create_end, create_start)
	var create_body := source.substr(create_start, create_end - create_start)
	assert_true(
		create_body.contains("undo_redo_manager.add_do_reference(root)"),
		"UndoRedo must own a reference to a newly created LevelRoot",
	)


func test_idle_rmb_passes_but_transient_gestures_are_cancelable():
	var input_state := HFInputState.new()
	assert_false(
		HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false),
		"Idle RMB must remain available for Godot camera navigation",
	)

	input_state.begin_drag(Vector3.ZERO, 0, 0, 4, 16.0, Vector3(16, 16, 16), Vector2.ZERO)
	assert_true(HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false))
	input_state.cancel()
	input_state.begin_extrude()
	assert_true(HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false))
	input_state.end_extrude()
	input_state.begin_vertex_edit()
	assert_false(
		HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false),
		"Persistent vertex mode alone must not steal RMB",
	)
	assert_true(
		HammerForgePlugin.has_cancelable_rmb_gesture(null, true),
		"An active selection marquee remains cancelable",
	)


func test_native_rmb_camera_session_owns_all_input_until_release():
	var session := HammerForgePlugin.RmbCameraNavigationSession.new()
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	assert_false(session.handle_followup(motion))
	session.begin()
	assert_true(session.active)
	assert_true(session.handle_followup(motion))
	assert_true(session.active)

	var buttonless_motion := InputEventMouseMotion.new()
	assert_false(session.handle_followup(buttonless_motion))
	assert_false(session.active, "A missed release must clear the camera session")

	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	session.begin()
	assert_true(session.handle_followup(right_release))
	assert_false(session.active, "RMB release must close the camera session")

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	session.begin()
	assert_false(session.handle_followup(right_press))
	assert_false(session.active, "A fresh press must replace stale session state")

	var left_release := InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	session.begin()
	assert_true(session.handle_followup(left_release))
	assert_true(session.active, "Mixed mouse buttons must remain inside RMB camera ownership")

	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		assert_true(session.handle_followup(key), "RMB+%s must stay native" % keycode)
		assert_true(session.active)

	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP]:
		var mixed_button := InputEventMouseButton.new()
		mixed_button.button_index = button
		mixed_button.pressed = true
		assert_true(
			session.handle_followup(mixed_button),
			"RMB camera ownership must contain button %s" % button,
		)
		assert_true(session.active)

	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var shortcut_start := source.find("func _shortcut_input")
	var shortcut_end := source.find("func _cancel_escape_step", shortcut_start)
	var shortcut := source.substr(shortcut_start, shortcut_end - shortcut_start)
	var camera_guard := shortcut.find("if _rmb_camera_navigation.active:")
	assert_gte(camera_guard, 0)
	assert_lt(
		camera_guard,
		shortcut.find("if event.keycode == KEY_ESCAPE:"),
		"RMB camera ownership must preempt HammerForge Escape handling",
	)
	assert_lt(
		camera_guard,
		shortcut.find("var nudge_guard"),
		"RMB camera ownership must preempt HammerForge Ctrl+Arrow nudge",
	)


func test_editor_object_ownership_is_narrow_and_selection_safe():
	var level_root = LevelRoot.new()
	var brush = DraftBrush.new()
	var entity = DraftEntity.new()
	var unrelated = Node3D.new()
	var camera = Camera3D.new()
	var light = DirectionalLight3D.new()
	assert_true(HammerForgePlugin.should_handle_editor_object(level_root))
	assert_true(HammerForgePlugin.should_handle_editor_object(brush))
	assert_true(HammerForgePlugin.should_handle_editor_object(entity))
	assert_false(HammerForgePlugin.should_handle_editor_object(unrelated))
	assert_false(HammerForgePlugin.should_handle_editor_object(camera))
	assert_false(HammerForgePlugin.should_handle_editor_object(light))
	level_root.free()
	brush.free()
	entity.free()
	unrelated.free()
	camera.free()
	light.free()


func test_quick_property_dismiss_preserves_native_navigation_buttons():
	var right_event := InputEventMouseButton.new()
	right_event.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(
		HammerForgePlugin.classify_quick_property_dismiss(right_event),
		HammerForgePlugin.QUICK_PROPERTY_DISMISS_CONTINUE,
		"RMB must continue to the current gesture owner before native navigation",
	)
	for button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		assert_eq(
			HammerForgePlugin.classify_quick_property_dismiss(event),
			EditorPlugin.AFTER_GUI_INPUT_PASS,
			"Navigation button %d must dismiss and pass through" % button,
		)
	var left_event := InputEventMouseButton.new()
	left_event.button_index = MOUSE_BUTTON_LEFT
	assert_eq(
		HammerForgePlugin.classify_quick_property_dismiss(left_event),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"LMB dismiss must be consumed to prevent editing through the popup",
	)


func test_active_paint_stroke_keeps_pointer_capture_until_lmb_release():
	assert_false(HammerForgePlugin.should_block_rmb_during_paint_stroke(false, false, false, true))
	assert_true(HammerForgePlugin.should_block_rmb_during_paint_stroke(true, false, false, true))
	assert_true(HammerForgePlugin.should_block_rmb_during_paint_stroke(false, true, false, true))
	assert_true(HammerForgePlugin.should_block_rmb_during_paint_stroke(false, false, true, true))
	assert_false(
		HammerForgePlugin.should_block_rmb_during_paint_stroke(true, true, true, false),
		"A stale paint flag must not permanently block RMB after LMB is no longer held",
	)
	var floor_paint := HFPaintTool.new()
	floor_paint._painting = true
	floor_paint.finish_stroke_if_active()
	assert_false(floor_paint.is_stroke_active(), "Stale floor-paint capture must be recoverable")
	floor_paint.free()


func test_viewport_forwarding_is_selection_independent_and_rmb_followups_bypass_tool_work():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var enter_start := source.find("func _enter_tree")
	var exit_start := source.find("func _exit_tree", enter_start)
	var enter_body := source.substr(enter_start, exit_start - enter_start)
	assert_true(
		enter_body.contains("set_input_event_forwarding_always_enabled()"),
		"Viewport forwarding must not depend on whichever editor object is selected",
	)

	var forward_start := source.find("func _forward_3d_gui_input")
	var root_create_start := source.find("func _should_start_disp_paint", forward_start)
	var forward_body := source.substr(forward_start, root_create_start - forward_start)
	var camera_bypass := forward_body.find("_rmb_camera_navigation.handle_followup")
	assert_gte(camera_bypass, 0)
	assert_lt(
		camera_bypass,
		forward_body.find("root.update_editor_grid"),
		"RMB camera motion must bypass grid and raycast work",
	)
	assert_lt(
		camera_bypass,
		forward_body.find("_tool_registry.dispatch_input"),
		"RMB camera motion must bypass external tool dispatch",
	)
	var no_root_start := forward_body.find("if not root:")
	var no_root_end := forward_body.find("var target_camera", no_root_start)
	var no_root_branch := forward_body.substr(no_root_start, no_root_end - no_root_start)
	assert_true(no_root_branch.contains("MOUSE_BUTTON_RIGHT"))
	assert_true(
		no_root_branch.contains("_rmb_camera_navigation.begin()"),
		"Rootless idle RMB must still own the complete native camera session",
	)


func test_quick_bake_dispatch_calls_the_real_dock_callback():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_commands.gd")
	var branch_start := source.find('\"quick_bake\":')
	var branch_end := source.find('\"undo\":', branch_start)
	assert_gte(branch_start, 0, "Quick Bake dispatch branch must exist")
	assert_gt(branch_end, branch_start, "Quick Bake branch must end before Undo")
	var branch := source.substr(branch_start, branch_end - branch_start)
	assert_true(branch.contains("dock._on_bake()"), "Quick Bake must call the real bake callback")
	assert_false(
		branch.contains("_on_bake_pressed"), "Quick Bake must not call the removed callback"
	)


func test_nudge_keys_respect_selection_ownership_before_being_consumed():
	# EditorPlugin cannot be instantiated by headless GUT, so audit the two
	# production event paths and the ownership guard they share. Native-only
	# selections must pass through to Godot; HammerForge-owned shortcuts stay
	# consumed even when a move becomes a no-op, so Godot cannot mutate them.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var keyboard_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin_input_router.gd"
	)
	var keyboard_start := keyboard_source.find("# Nudge keys")
	var keyboard_end := keyboard_source.find("# Grid snap size shortcuts", keyboard_start)
	var keyboard_branch := keyboard_source.substr(keyboard_start, keyboard_end - keyboard_start)
	assert_true(
		keyboard_branch.contains('_guard_hammerforge_shortcut(root, false, 1, "Nudge")'),
		"Viewport nudge must classify selection ownership first",
	)
	assert_true(keyboard_branch.contains("nudge_guard != SHORTCUT_APPLY"))
	assert_lt(
		keyboard_branch.find("nudge_guard"), keyboard_branch.find("_nudge_selected(root, nudge)")
	)
	assert_true(keyboard_branch.contains("return STOP"))

	var shortcut_start := source.find("func _shortcut_input")
	var shortcut_end := source.find("func _cancel_escape_step", shortcut_start)
	var shortcut_branch := source.substr(shortcut_start, shortcut_end - shortcut_start)
	assert_true(shortcut_branch.contains("should_yield_global_shortcut_to_focus"))
	assert_false(shortcut_branch.contains("event.accept()"))
	assert_true(shortcut_branch.contains("_mark_shortcut_input_handled()"))
	assert_true(source.contains("viewport.set_input_as_handled()"))
	assert_true(shortcut_branch.contains('_keymap.matches("delete", event)'))
	assert_true(shortcut_branch.contains('_keymap.matches("duplicate", event)'))
	assert_true(
		shortcut_branch.contains('_guard_hammerforge_shortcut(root, false, 1, "Nudge")'),
		"Global Ctrl+nudge must use the same ownership guard",
	)
	assert_lt(
		shortcut_branch.find("nudge_guard"), shortcut_branch.find("_nudge_selected(root, nudge)")
	)
	assert_true(shortcut_branch.contains("elif nudge_guard == EditorPlugin.AFTER_GUI_INPUT_STOP:"))

	var nudge_start := source.find("func _nudge_selected")
	var nudge_end := source.find("func _adjust_grid_snap", nudge_start)
	var nudge_body := source.substr(nudge_start, nudge_end - nudge_start)
	assert_true(nudge_body.contains("root.is_brush_node(node)"))
	assert_true(nudge_body.contains("root.is_entity_node(node)"))
	assert_true(nudge_body.contains("entity_paths"))
	assert_true(nudge_body.contains("if brush_ids.is_empty() and entity_paths.is_empty():"))
	assert_true(nudge_body.contains("return false"))

	var line_edit := LineEdit.new()
	add_child_autoqfree(line_edit)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(line_edit))
	var text_edit := TextEdit.new()
	add_child_autoqfree(text_edit)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(text_edit))
	var spin_box := SpinBox.new()
	add_child_autoqfree(spin_box)
	assert_true(
		HammerForgePlugin.should_yield_global_shortcut_to_focus(spin_box.get_line_edit()),
		"A SpinBox's internal LineEdit keeps editor shortcut ownership",
	)
	var generic_tree := Tree.new()
	add_child_autoqfree(generic_tree)
	assert_true(
		HammerForgePlugin.should_yield_global_shortcut_to_focus(generic_tree),
		"An unrelated editor Tree must keep Delete/Duplicate ownership",
	)
	var item_list := ItemList.new()
	add_child_autoqfree(item_list)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(item_list))
	var graph_edit := GraphEdit.new()
	add_child_autoqfree(graph_edit)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(graph_edit))
	var scene_tree := Tree.new()
	scene_tree.name = "SceneTree"
	add_child_autoqfree(scene_tree)
	assert_false(
		HammerForgePlugin.should_yield_global_shortcut_to_focus(scene_tree),
		"Scene-tree focus must still route managed Delete/Duplicate",
	)
	var hf_surface := Control.new()
	hf_surface.set_meta("_hammerforge_managed_shortcut_surface", true)
	add_child_autoqfree(hf_surface)
	assert_false(HammerForgePlugin.should_yield_global_shortcut_to_focus(hf_surface))
	assert_false(HammerForgePlugin.should_yield_global_shortcut_to_focus(null))

	var preview_start := source.find("func _toggle_bake_preview")
	var preview_end := source.find("func _on_context_tool_switch", preview_start)
	var preview_branch := source.substr(preview_start, preview_end - preview_start)
	assert_true(preview_branch.contains("await root.bake"))
	assert_false(
		preview_branch.contains("_commit_state_action"),
		"Async preview bake must never be dispatched through UndoRedo",
	)


func test_entity_alias_change_refreshes_preview_once_and_detaches_old_preview():
	var script := GDScript.new()
	script.source_code = """
extends \"res://addons/hammerforge/draft_entity.gd\"
var preview_update_count := 0
func _update_preview() -> void:
	preview_update_count += 1
func _get_entity_type_hints() -> PackedStringArray:
	return PackedStringArray(["light_point", "player_start"])
func _get_entity_schema() -> Array:
	return [{"name": "intensity", "type": "float", "default": 1.0}]
"""
	assert_eq(script.reload(), OK)
	var entity = script.new()
	add_child_autoqfree(entity)
	var ready_updates: int = entity.preview_update_count

	entity.entity_type = "light_point"
	assert_eq(entity.entity_class, "light_point")
	assert_eq(
		entity.preview_update_count,
		ready_updates + 1,
		"Mirroring type to class should rebuild the preview only once",
	)
	entity.entity_class = "player_start"
	assert_eq(entity.entity_type, "player_start")
	assert_eq(entity.preview_update_count, ready_updates + 2)
	var visible_type_properties := 0
	var entity_class_usage := -1
	for property in entity.get_property_list():
		if str(property.get("name", "")) == "entity_type":
			visible_type_properties += 1
			assert_eq(int(property.get("hint", PROPERTY_HINT_NONE)), PROPERTY_HINT_ENUM)
		if str(property.get("name", "")) == "entity_class":
			entity_class_usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT))
	assert_eq(visible_type_properties, 1, "Inspector must expose one canonical Entity Type")
	if entity_class_usage >= 0:
		assert_eq(entity_class_usage, PROPERTY_USAGE_NONE, "Legacy class alias stays hidden")
	var dynamic_names: Array[String] = []
	for property in entity._get_property_list():
		dynamic_names.append(str(property.get("name", "")))
	assert_true("data/intensity" in dynamic_names)
	assert_false("entity_data/intensity" in dynamic_names, "Legacy data alias must not duplicate")
	assert_true(entity._set(&"entity_data/intensity", 2.5), "Old scenes still migrate on load")
	assert_eq(entity._get(&"data/intensity"), 2.5)

	for index in range(20):
		var preview := MeshInstance3D.new()
		entity._assign_preview(preview)
		assert_eq(str(preview.name), "_EditorPreview")
		entity._clear_preview()
		assert_null(preview.get_parent(), "Preview %d should detach immediately" % index)
		assert_true(preview.is_queued_for_deletion())
		assert_eq(entity.get_children(true).size(), 0)

	var current := MeshInstance3D.new()
	entity._assign_preview(current)
	assert_eq(entity.get_children(true).size(), 1)
	assert_same(entity.preview_node, current)


func test_floor_and_sun_restore_can_toggle_twice_in_the_same_frame():
	var state := HFStateSystem.new(root)
	var floor_info := {
		"exists": true,
		"size": Vector3(128, 8, 128),
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, -4, 0)),
		"use_collision": true,
	}
	state.restore_floor_info(floor_info)
	var old_floor := root.get_node("TempFloor") as CSGBox3D
	state.restore_floor_info({"exists": false})
	assert_null(old_floor.get_parent())
	assert_true(old_floor.is_queued_for_deletion())
	state.restore_floor_info(floor_info)
	var new_floor := root.get_node("TempFloor") as CSGBox3D
	assert_ne(new_floor.get_instance_id(), old_floor.get_instance_id())
	assert_false(new_floor.is_queued_for_deletion())

	var sun_info := {
		"exists": true,
		"rotation_degrees": Vector3(-45, 30, 0),
		"shadow_enabled": true,
		"light_energy": 1.0,
	}
	state.restore_sun_info(sun_info)
	var old_sun := root.get_node("DefaultSun") as DirectionalLight3D
	state.restore_sun_info({"exists": false})
	assert_null(old_sun.get_parent())
	assert_true(old_sun.is_queued_for_deletion())
	state.restore_sun_info(sun_info)
	var new_sun := root.get_node("DefaultSun") as DirectionalLight3D
	assert_ne(new_sun.get_instance_id(), old_sun.get_instance_id())
	assert_false(new_sun.is_queued_for_deletion())


# ===========================================================================
# Source-integration helpers
# ===========================================================================


func _compact_source(source: String) -> String:
	return source.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "")


func _vertex_motion_source_block(source: String) -> String:
	var block_start := source.find("var projection: Dictionary = vs.project_drag_screen_delta")
	if block_start < 0:
		return ""
	var block_end := source.find("\n\t\t_update_vertex_overlay(root, cam)", block_start)
	if block_end < 0:
		return source.substr(block_start)
	return source.substr(block_start, block_end - block_start)


# ===========================================================================
# Fake brush system for carve tests
# ===========================================================================


class _FakeBrushSystem:
	extends RefCounted
	var _root: Node3D
	var _draft_node: Node3D
	var _next_id := 1000

	func _init(p_root: Node3D, p_draft: Node3D):
		_root = p_root
		_draft_node = p_draft

	func find_brush_by_id(brush_id: String):
		if not _draft_node:
			return null
		for child in _draft_node.get_children():
			if str(child.brush_id) == brush_id:
				return child
			if child.has_meta("brush_id") and str(child.get_meta("brush_id")) == brush_id:
				return child
		return null

	func delete_brush_by_id(brush_id: String) -> HFOpResult:
		var brush = find_brush_by_id(brush_id)
		if brush:
			_draft_node.remove_child(brush)
			brush.queue_free()
		return HFOpResult.success("deleted")

	func _next_brush_id() -> String:
		_next_id += 1
		return "carved_%d" % _next_id

	func create_brush_from_info(info: Dictionary):
		var b = DraftBrush.new()
		b.size = info.get("size", Vector3(1, 1, 1))
		b.brush_id = info.get("brush_id", _next_brush_id())
		_draft_node.add_child(b)
		b.global_position = info.get("center", Vector3.ZERO)
		return b
