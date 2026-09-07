@tool
class_name HFPluginSelectionInput
extends RefCounted
## Native object and HammerForge face-selection pointer arbitration.

const HFSelectionGestureType = preload("hf_selection_gesture.gd")
const SELECT_DRAG_THRESHOLD := 6.0
const SELECT_INPUT_CONTINUE := -2


static func handle_press(
	plugin: Object,
	event: InputEventMouseButton,
	root: Node,
	camera: Camera3D,
	position: Vector2,
	paint_mode: bool
) -> int:
	if not event.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var face_select: bool = plugin.dock.is_face_select_mode_enabled()
	if event.alt_pressed or Input.is_key_pressed(KEY_ALT):
		plugin._cancel_selection_gesture()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var active_material = plugin.dock.get_active_material()
	if not face_select and paint_mode and active_material:
		var painted = root.pick_brush(camera, position, false)
		if painted:
			plugin._paint_brush_with_undo(root, painted, active_material)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	var shift_selection := event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
	var toggle := (
		face_select
		and (
			event.ctrl_pressed
			or event.meta_pressed
			or Input.is_key_pressed(KEY_CTRL)
			or Input.is_key_pressed(KEY_META)
		)
	)
	var additive := shift_selection or toggle
	var selection_at_press: Array = plugin._current_selection_nodes()
	var native_selection_present: bool = plugin._selection_contains_native_node(
		selection_at_press, root
	)
	var pass_to_native := not face_select or native_selection_present
	if pass_to_native:
		plugin._begin_native_selection_session(selection_at_press, additive, toggle)
		plugin._selection_gesture.begin(
			position, additive, toggle, face_select, false, false, true, selection_at_press, true
		)
		root.clear_hover()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	plugin._marquee_overlay_origin = position
	plugin._selection_gesture.begin(
		position,
		additive,
		toggle,
		face_select,
		face_select,
		true,
		false,
		selection_at_press,
		face_select and not selection_at_press.is_empty()
	)
	root.clear_hover()
	return EditorPlugin.AFTER_GUI_INPUT_CUSTOM


static func custom_release_result(face_selection: bool) -> int:
	return (
		EditorPlugin.AFTER_GUI_INPUT_CUSTOM if face_selection else EditorPlugin.AFTER_GUI_INPUT_PASS
	)


static func handle_active(
	plugin: Object, event: InputEvent, root: Node, camera: Camera3D, position: Vector2
) -> int:
	if not plugin._selection_gesture or not plugin._selection_gesture.is_active():
		return SELECT_INPUT_CONTINUE
	if event is InputEventKey and plugin._selection_gesture.should_yield_cancel_to_native():
		if event.pressed and event.keycode == KEY_ESCAPE:
			plugin._cancel_selection_gesture()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var decision: int = plugin._selection_gesture.update_motion(
			position, motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0, SELECT_DRAG_THRESHOLD
		)
		match decision:
			HFSelectionGestureType.MotionDecision.RECOVERED:
				plugin._cancel_selection_gesture()
				plugin._queue_managed_brush_reconcile()
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			HFSelectionGestureType.MotionDecision.NATIVE_GIZMO:
				plugin._update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			HFSelectionGestureType.MotionDecision.DRAW_MARQUEE:
				root.clear_hover()
				plugin._update_marquee_overlay(plugin._marquee_overlay_origin, position, true)
				return EditorPlugin.AFTER_GUI_INPUT_CUSTOM
			_:
				root.clear_hover()
				return (
					EditorPlugin.AFTER_GUI_INPUT_PASS
					if plugin._selection_gesture.native_passthrough
					else EditorPlugin.AFTER_GUI_INPUT_CUSTOM
				)
	if not (event is InputEventMouseButton):
		return SELECT_INPUT_CONTINUE
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		var yield_cancel: bool = plugin._selection_gesture.should_yield_cancel_to_native()
		plugin._cancel_selection_gesture()
		return (
			EditorPlugin.AFTER_GUI_INPUT_PASS if yield_cancel else EditorPlugin.AFTER_GUI_INPUT_STOP
		)
	if button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
		return SELECT_INPUT_CONTINUE
	if button.canceled:
		var yield_cancel: bool = plugin._selection_gesture.should_yield_cancel_to_native()
		plugin._cancel_selection_gesture()
		return (
			EditorPlugin.AFTER_GUI_INPUT_PASS if yield_cancel else EditorPlugin.AFTER_GUI_INPUT_STOP
		)

	var native_session: bool = plugin._native_selection_active
	var native_before: Array = plugin._native_selection_before.duplicate()
	var native_additive: bool = plugin._native_selection_additive
	var native_toggle: bool = plugin._native_selection_toggle
	var result: Dictionary = plugin._selection_gesture.finish(position, SELECT_DRAG_THRESHOLD)
	plugin._reset_native_selection_session()
	plugin._update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	var release_decision := int(
		result.get("decision", HFSelectionGestureType.ReleaseDecision.PASS_THROUGH)
	)
	if (
		release_decision
		in [
			HFSelectionGestureType.ReleaseDecision.NATIVE_GIZMO,
			HFSelectionGestureType.ReleaseDecision.PASS_THROUGH,
		]
	):
		if native_session:
			plugin._queue_managed_brush_reconcile()
			plugin.call_deferred(
				"_finalize_native_selection", native_before, native_additive, native_toggle
			)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	match release_decision:
		HFSelectionGestureType.ReleaseDecision.MARQUEE:
			if not bool(result.get("face_select", false)):
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			select_faces_in_rect(
				plugin,
				root,
				camera,
				result.get("origin", position),
				position,
				bool(result.get("additive", false)),
				bool(result.get("toggle", false))
			)
			return custom_release_result(true)
		HFSelectionGestureType.ReleaseDecision.CLICK:
			if not bool(result.get("face_select", false)):
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			root.select_face_at_screen(
				camera,
				result.get("origin", position),
				bool(result.get("additive", false)),
				bool(result.get("toggle", false))
			)
			return custom_release_result(true)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func select_faces_in_rect(
	plugin: Object,
	root: Node,
	camera: Camera3D,
	from: Vector2,
	to: Vector2,
	additive: bool,
	toggle: bool = false
) -> void:
	if not root or not camera:
		return
	var rect := Rect2(from, to - from).abs()
	var face_selection: Dictionary = {} if not additive else root.face_selection.duplicate(true)
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	for node in nodes:
		if not node is DraftBrush:
			continue
		var brush := node as DraftBrush
		if not root.is_brush_node(brush) or not brush.is_visible_in_tree():
			continue
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = plugin._face_key_for(brush)
		var indices: Array = face_selection.get(key, []).duplicate() if additive else []
		for index in range(faces.size()):
			var face = faces[index]
			if not face:
				continue
			var center := face_screen_center(camera, brush, face)
			if center == Vector2(-1, -1) or not rect.has_point(center):
				continue
			var visible_hit: Dictionary = root.pick_face(camera, center)
			if visible_hit.get("brush") != brush or int(visible_hit.get("face_idx", -1)) != index:
				continue
			if additive and toggle and indices.has(index):
				indices.erase(index)
			elif not indices.has(index):
				indices.append(index)
		if indices.is_empty():
			face_selection.erase(key)
		else:
			face_selection[key] = indices
	plugin._apply_face_selection(root, face_selection)


static func face_screen_center(camera: Camera3D, brush: DraftBrush, face) -> Vector2:
	if face.local_verts.is_empty():
		return Vector2(-1, -1)
	var center := Vector3.ZERO
	for vertex in face.local_verts:
		center += vertex
	center /= float(face.local_verts.size())
	var world_position: Vector3 = brush.global_transform * center
	if camera.is_position_behind(world_position):
		return Vector2(-1, -1)
	return camera.unproject_position(world_position)
