@tool
class_name HFPluginShortcuts
extends RefCounted
## Editor-wide keyboard shortcuts and the Escape cancel ladder.
##
## Godot delivers Delete, Duplicate, Ctrl+Arrow and Escape through _shortcut_input
## no matter which editor panel has focus, so this is a second way into commands
## the 3D viewport also routes. Both jobs answer the same question and so live
## together: does HammerForge own this key press right now, or does the editor.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
## Same sentinel as plugin.HF_SHORTCUT_APPLY
const SHORTCUT_APPLY := -3


## Route one global key press. Returns nothing: ownership is expressed by
## consuming the event through the viewport rather than by a return code, because
## Godot gives _shortcut_input no way to answer.
static func handle(plugin: Object, event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	plugin._ensure_selection_runtime_state()
	# The 3D viewport receives RMB navigation through the forwarded input hook,
	# but editor shortcuts arrive through this separate hook as well. Keep the
	# complete keyboard stream native until RMB release so Ctrl+Arrow/Escape cannot
	# nudge or cancel HammerForge state during camera flight.
	if plugin._rmb_camera_navigation.active:
		return
	# Native transform/property/custom gizmos own their complete keyboard stream.
	# In particular, Ctrl+Arrow must not become a simultaneous HF nudge while a
	# Godot widget is dragging the same brush.
	if (
		plugin._brush_gizmo_action_active()
		or plugin._selection_gesture.should_yield_cancel_to_native()
	):
		return
	if not event.pressed or event.echo:
		return
	if should_yield_to_focus(plugin.get_viewport().gui_get_focus_owner()):
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if event.keycode == KEY_ESCAPE:
		if cancel_escape_step(plugin, root):
			mark_handled(plugin)
		return
	if not root:
		return
	# Delete and Duplicate are global editor shortcuts: Godot can deliver them
	# here while focus is in the Scene tree, without ever forwarding them through
	# the 3D viewport. Claim managed selections here as well so every entry point
	# uses HammerForge's undo, stable-ID, and reference-cleanup boundaries.
	if plugin._keymap.matches("delete", event):
		if _claim(plugin, root, "Delete"):
			plugin._delete_selected(root)
		return
	if plugin._keymap.matches("duplicate", event):
		if _claim(plugin, root, "Duplicate"):
			plugin._duplicate_selected(root)
		return
	if not event.ctrl_pressed:
		return
	var nudge: Vector3 = plugin._get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO:
		if _claim(plugin, root, "Nudge"):
			plugin._nudge_selected(root, nudge)


## Delete, Duplicate and Nudge each asked the shared selection-scope guard the
## same way, so they ask it here instead of three times over. True means the
## selection is HammerForge's and the command should run. The event is consumed
## either way once the guard has claimed it, so Godot cannot go on to run its own
## version of the same command against the same nodes.
static func _claim(plugin: Object, root: Node, action: String) -> bool:
	var guard: int = plugin._guard_hammerforge_shortcut(root, false, 1, action)
	if guard == SHORTCUT_APPLY or guard == STOP:
		mark_handled(plugin)
	return guard == SHORTCUT_APPLY


static func mark_handled(plugin: Object) -> void:
	# InputEvent has no accept() API. _shortcut_input() consumes through the
	# viewport so Godot cannot execute the same global command afterwards.
	var viewport: Viewport = plugin.get_viewport()
	if viewport:
		viewport.set_input_as_handled()


## Only the 3D viewport, the real Scene tree, and explicitly marked HammerForge
## command surfaces may route managed global shortcuts. Unknown editor panels
## keep ownership of their own Delete, Duplicate, arrows, and Escape commands.
static func should_yield_to_focus(focus_owner: Control) -> bool:
	if focus_owner == null:
		# The 3D viewport normally has no GUI focus owner.
		return false
	var current: Control = focus_owner
	while current:
		if bool(current.get_meta("_hammerforge_managed_shortcut_surface", false)):
			return false
		var control_class := current.get_class()
		var node_name := str(current.name)
		if control_class in ["SceneTreeDock", "SceneTreeEditor"]:
			return false
		if node_name in ["SceneTree", "SceneTreeDock", "SceneTreeEditor"]:
			return false
		if control_class in ["Node3DEditor", "Node3DEditorViewport"]:
			return false
		if node_name in ["Node3DEditor", "Node3DEditorViewport"]:
			return false
		current = current.get_parent() as Control
	return true


## Escape is a predictable ladder: dismiss the most local interaction first.
## Returns true when a rung was taken, which is what tells the caller to consume
## the key instead of letting Godot act on it.
static func cancel_escape_step(plugin: Object, root: Node) -> bool:
	if plugin._hotkey_palette and plugin._hotkey_palette.visible:
		plugin._hotkey_palette.visible = false
		return true
	if plugin._radial_menu and plugin._radial_menu.is_active():
		plugin._radial_menu.hide_menu()
		return true
	if plugin._quick_property and plugin._quick_property.is_active():
		plugin._quick_property.hide_popup()
		return true
	if plugin._texture_picker_active:
		plugin._texture_picker_active = false
		if plugin.dock:
			plugin.dock.show_toast("Texture Picker cancelled", 1)
		return true
	if plugin._disp_paint_active:
		if (
			root
			and not plugin._disp_paint_pre_state.is_empty()
			and root.has_method("restore_state")
		):
			root.restore_state(plugin._disp_paint_pre_state)
		plugin._disp_paint_active = false
		plugin._disp_paint_brush_id = ""
		plugin._disp_paint_face_idx = -1
		plugin._disp_paint_pre_state = {}
		return true
	# Godot must see Escape while one of its transform/property/custom gizmos
	# owns LMB so it can restore the exact engine-side value and clear its private
	# drag reference. Only discard HammerForge's parallel bookkeeping here.
	if plugin._brush_gizmo_action_active():
		return false
	if plugin._selection_gesture and plugin._selection_gesture.should_yield_cancel_to_native():
		plugin._cancel_selection_gesture()
		return false
	if plugin._cancel_selection_gesture():
		return true
	if root and root.input_state:
		if root.input_state.is_extruding():
			root.cancel_extrude()
			plugin.numeric_buffer = ""
			plugin._update_hud_context()
			return true
		if root.input_state.is_dragging():
			root.cancel_drag()
			plugin.numeric_buffer = ""
			plugin._update_hud_context()
			return true
	if plugin._tool_registry and plugin._tool_registry.has_active_external_tool():
		plugin._tool_registry.deactivate_current()
		plugin._update_hud_context()
		return true
	if plugin._vertex_mode:
		plugin._toggle_vertex_mode(root)
		return true
	if root and root.get("face_selection") is Dictionary and not root.face_selection.is_empty():
		root.clear_face_selection()
		plugin._update_hud_context()
		return true
	# Face Select remains modal after its local face selection is cleared. A
	# second Escape (or the first when no face is selected) exits the mode and
	# restores the object selection hidden on entry.
	if plugin._close_face_select_mode("Face Select closed"):
		return true
	if not plugin.hf_selection.is_empty():
		plugin.hf_selection.clear()
		var selection = plugin.get_editor_interface().get_selection()
		if selection:
			selection.clear()
		if plugin.dock:
			plugin.dock.set_selection_nodes([])
		plugin._update_hud_context()
		return true
	return false
