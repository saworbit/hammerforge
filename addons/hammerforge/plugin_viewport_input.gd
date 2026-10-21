@tool
class_name HFPluginViewportInput
extends RefCounted
## Viewport input arbitration and native RMB camera-session ownership.

const HFTextureGizmoType = preload("hf_texture_gizmo.gd")
const QUICK_PROPERTY_DISMISS_CONTINUE := -1
const SELECT_INPUT_CONTINUE := -2
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFPluginUVWrap = preload("plugin_uv_wrap.gd")
const HFPluginHud = preload("plugin_hud.gd")
const HFPluginTransformTools = preload("plugin_transform_tools.gd")
@warning_ignore_restore("shadowed_global_identifier")


class RmbCameraNavigationSession:
	extends RefCounted

	var active := false

	func begin() -> void:
		active = true

	func handle_followup(event: InputEvent) -> bool:
		if not active:
			return false
		if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_RIGHT != 0:
				return true
			active = false
			return false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				active = false
				return false
			active = false
			return true
		return true


static func should_create_root(event: InputEvent, tool_id: int, paint_mode: bool) -> bool:
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and tool_id == 0
		and not paint_mode
	)


## A scene a first Draw click may make a level of: a plain Node3D root with no
## script and nothing under it, which is what a new 3D scene is. A scene with
## anything in it belongs to something else already, and a Draw click there is a
## select click, so it is Godot's (#932).
static func scene_awaits_a_level(scene: Node) -> bool:
	return (
		scene != null
		and scene.get_class() == "Node3D"
		and scene.get_script() == null
		and scene.get_child_count() == 0
	)


static func classify_quick_property_dismiss(event: InputEventMouseButton) -> int:
	if event.button_index == MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.button_index == MOUSE_BUTTON_RIGHT:
		return QUICK_PROPERTY_DISMISS_CONTINUE
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func should_block_rmb_during_paint_stroke(
	surface_painting: bool,
	floor_painting: bool,
	displacement_painting: bool,
	left_button_held: bool
) -> bool:
	return left_button_held and (surface_painting or floor_painting or displacement_painting)


static func is_lmb_release_recovery_motion(event: InputEvent) -> bool:
	return (
		event is InputEventMouseMotion
		and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT == 0
	)


## Read the keys a drag holds off every event, before anything here can return,
## so a key pressed or let go mid-drag counts from the next motion (#1431,
## #1399). A resize handle is moved by Godot after this hook returns, so it reads
## what this left behind. The HUD's snap line follows them.
static func hold_drag_keys(plugin: Object, root: Node, event: InputEvent) -> void:
	var keymap = plugin.get("_keymap")
	var snap = root.get("snap_system")
	if keymap == null or snap == null:
		return
	snap.hold_drag_keys(
		keymap.held("snap_invert_hold", event), keymap.held("snap_vertex_hold", event)
	)
	HFPluginHud.refresh_drag_snap(plugin, root)


static func handle(plugin: Object, camera: Camera3D, event: InputEvent) -> int:
	var result := _route(plugin, camera, event)
	# STOP only stops Godot's 3D viewport handler. A key goes on to the shortcut
	# stage, where Godot's own 3D shortcuts and our _shortcut_input would act on
	# it again: one Ctrl+D made two duplicates. Consuming it here covers every
	# key this file stops (#927).
	if result == EditorPlugin.AFTER_GUI_INPUT_STOP and event is InputEventKey:
		var viewport: Viewport = plugin.get_viewport()
		if viewport:
			viewport.set_input_as_handled()
	return result


static func _route(plugin: Object, camera: Camera3D, event: InputEvent) -> int:
	if not plugin.dock:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	plugin._ensure_selection_runtime_state()
	var face_select_mode: bool = plugin.dock.is_face_select_mode_enabled()
	if camera:
		plugin.last_3d_camera = camera
	if event is InputEventMouse:
		plugin.last_3d_mouse_pos = event.position

	if plugin._rmb_camera_navigation.handle_followup(event):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		var intentional_draw_click := should_create_root(
			event,
			1 if face_select_mode else plugin.dock.get_tool(),
			plugin.dock.is_paint_mode_enabled() and not face_select_mode
		)
		if intentional_draw_click and not plugin._edited_scene_awaits_a_level():
			plugin._hint_create_level_from_banner()
			intentional_draw_click = false
		if not intentional_draw_click:
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT
				and event.pressed
			):
				plugin._rmb_camera_navigation.begin()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		root = plugin._create_level_root()
		if not root:
			return EditorPlugin.AFTER_GUI_INPUT_PASS

	var target_camera = camera
	var target_pos = event.position if event is InputEventMouse else plugin.last_3d_mouse_pos
	var tool_id = 1 if face_select_mode else plugin.dock.get_tool()
	var paint_mode = plugin.dock.is_paint_mode_enabled() and not face_select_mode
	root.grid_snap = plugin.dock.get_grid_snap()
	hold_drag_keys(plugin, root, event)

	if plugin._radial_menu and plugin._radial_menu.is_active():
		plugin._radial_menu._gui_input(event)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if plugin._quick_property and plugin._quick_property.is_active():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			plugin._quick_property.hide_popup()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseButton and event.pressed:
			var popup_rect: Rect2 = plugin._quick_property.get_rect()
			if not popup_rect.has_point(event.position):
				plugin._quick_property.hide_popup()
				var dismiss_result := classify_quick_property_dismiss(event)
				if dismiss_result != QUICK_PROPERTY_DISMISS_CONTINUE:
					return dismiss_result

	if plugin._brush_gizmo_action_active():
		if is_lmb_release_recovery_motion(event):
			plugin.brush_gizmo_plugin.call("cancel_active_handle_action")
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var gizmo_result := route_texture_gizmo(plugin, event, root, target_camera, target_pos)
	if gizmo_result != SELECT_INPUT_CONTINUE:
		return gizmo_result

	if is_lmb_release_recovery_motion(event):
		plugin._recover_stale_lmb_gestures(root)

	# An armed Pick Pivot takes the next click whatever the tool or mode, ahead of
	# all of them, and a right click or Escape puts it away.
	var pick_result := HFPluginTransformTools.handle_pivot_pick_input(
		plugin, event, root, target_camera, target_pos
	)
	if pick_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
		return pick_result

	if plugin._selection_gesture and plugin._selection_gesture.is_active():
		if tool_id != 1:
			plugin._cancel_selection_gesture()
		else:
			var select_result: int = plugin._handle_active_selection_input(
				event, root, target_camera, target_pos
			)
			if select_result != SELECT_INPUT_CONTINUE:
				return select_result

	if event is InputEventMouseMotion or event is InputEventMouseButton:
		root.update_editor_grid(target_camera, target_pos)

	# Repeat's stamp has the pointer while it is armed (#1407).
	var stamp = plugin.get("_brush_stamp")
	if stamp != null and stamp.armed:
		var stamp_result: int = stamp.handle_input(plugin, event, root, target_camera, target_pos)
		if stamp_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return stamp_result

	if (
		not face_select_mode
		and (
			plugin._disp_paint_active or plugin._should_start_disp_paint(event, root, target_camera)
		)
	):
		var displacement_result = plugin._handle_disp_paint_input(
			event, root, target_camera, target_pos
		)
		if displacement_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return displacement_result

	if paint_mode:
		var paint_result = plugin._handle_paint_input(event, root, target_camera, target_pos)
		if paint_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return paint_result

	if plugin._tool_registry and not face_select_mode:
		var external_result = plugin._tool_registry.dispatch_input(event, target_camera, target_pos)
		if external_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if (
			plugin._tool_registry.has_active_external_tool()
			and (event is InputEventMouseButton or event is InputEventMouseMotion)
		):
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT
				and event.pressed
			):
				root.clear_hover()
				if root.has_method("clear_face_hover_highlight"):
					root.clear_face_hover_highlight()
				plugin._rmb_camera_navigation.begin()
			return EditorPlugin.AFTER_GUI_INPUT_PASS

	if plugin._vertex_mode and root.vertex_system and not face_select_mode:
		var vertex_result = plugin._handle_vertex_input(event, root, target_camera, target_pos)
		if vertex_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return vertex_result

	if plugin._texture_picker_active:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				plugin._texture_picker_active = false
				plugin._pick_face_material(root)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.button_index == MOUSE_BUTTON_RIGHT:
				plugin._texture_picker_active = false
				if plugin.dock:
					plugin.dock.show_toast("Texture Picker cancelled", 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				plugin._texture_picker_active = false
				if plugin.dock:
					plugin.dock.show_toast("Texture Picker cancelled", 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if HFPluginUVWrap.is_active(plugin):
		var wrap_result := HFPluginUVWrap.handle_input(plugin, root, event)
		if wrap_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return wrap_result

	if event is InputEventKey and event.pressed and not event.echo:
		var keyboard_result = plugin._handle_keyboard_input(event, root, tool_id, paint_mode)
		if keyboard_result != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return keyboard_result

	if tool_id == 1 and event is InputEventMouseMotion and event.button_mask == 0:
		root.update_hover(target_camera, target_pos, plugin.hf_selection)
	elif tool_id == 1 and event is InputEventMouseMotion:
		root.clear_hover()
	elif tool_id != 1:
		root.clear_hover()

	if event is InputEventMouseButton:
		if tool_id != 1:
			root.set_shift_pressed(event.shift_pressed)
			root.set_alt_pressed(event.alt_pressed)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			return plugin._handle_rmb_cancel(root, tool_id, event)
		if event.button_index == MOUSE_BUTTON_LEFT:
			match tool_id:
				0:
					return plugin._handle_draw_mouse(event, root, target_camera, target_pos)
				1:
					return plugin._handle_select_mouse(
						event, root, target_camera, target_pos, paint_mode
					)
				2, 3:
					return plugin._handle_extrude_mouse(event, root, target_camera, target_pos)

	if event is InputEventMouseMotion:
		return plugin._handle_mouse_motion(event, root, target_camera, target_pos, tool_id)

	plugin._update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## The Texture Gizmo's share of the input (#1420): all of it while a drag is under
## way, a press on one of its handles, and each pointer move, which sizes it and
## lights the handle under the pointer. SELECT_INPUT_CONTINUE for the rest.
static func route_texture_gizmo(
	plugin: Object, event: InputEvent, root: Node, camera: Camera3D, position: Vector2
) -> int:
	var gizmo = plugin.get("_texture_gizmo")
	if gizmo == null:
		return SELECT_INPUT_CONTINUE
	if gizmo.is_dragging():
		return _drive_texture_gizmo(plugin, gizmo, event, root, camera, position)
	if not gizmo.is_visible():
		return SELECT_INPUT_CONTINUE
	if event is InputEventMouseMotion:
		gizmo.hover(camera, position)
		return SELECT_INPUT_CONTINUE
	if not (event is InputEventMouseButton):
		return SELECT_INPUT_CONTINUE
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed or button.alt_pressed:
		return SELECT_INPUT_CONTINUE
	var grabbed: int = gizmo.handle_at(camera, position)
	if grabbed == HFTextureGizmoType.Handle.NONE:
		return SELECT_INPUT_CONTINUE
	if not gizmo.begin_drag(camera, position, grabbed):
		return SELECT_INPUT_CONTINUE
	root.clear_hover()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## A drag owns the pointer and the keys until it ends. The snap-invert hold, Ctrl
## by default, flips the grid snap for a slide and a stretch as it does for any
## drag (#1431), and frees a turn from Selection Tools > Step.
static func _drive_texture_gizmo(
	plugin: Object, gizmo, event: InputEvent, root: Node, camera: Camera3D, position: Vector2
) -> int:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			# The release went somewhere else. Called off, as a vertex drag is.
			gizmo.cancel()
			_after_texture_gizmo(plugin)
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var step: float = root.drag_grid_step()
		var inverted: bool = root.snap_system != null and root.snap_system.invert_held
		gizmo.drag_to(
			camera,
			position,
			motion.shift_pressed,
			step,
			HFTextureGizmoType.STRETCH_STEP if step > 0.0 else 0.0,
			0.0 if inverted else deg_to_rad(float(root.rotate_snap_degrees))
		)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			if button.canceled:
				gizmo.cancel()
			else:
				gizmo.finish(plugin._get_undo_redo(), Callable(plugin, "_record_history"))
			_after_texture_gizmo(plugin)
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			gizmo.cancel()
			_after_texture_gizmo(plugin)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			gizmo.cancel()
			_after_texture_gizmo(plugin)
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## The UV Editor's boxes show the face on show again, after a drag moved it or
## put it back.
static func _after_texture_gizmo(plugin: Object) -> void:
	if plugin.dock:
		plugin.dock._refresh_uv_face()
	plugin._update_hud_context()
