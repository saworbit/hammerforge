@tool
class_name HFPluginInputRouter
extends RefCounted
## Viewport keymap dispatch extracted from plugin.gd.
## Surfaces still call plugin._handle_keyboard_input(); this module owns the order.

const LevelRootType = preload("level_root.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## Same sentinel as plugin.HF_SHORTCUT_APPLY
const SHORTCUT_APPLY := -3


static func handle_keyboard(
	plugin: Object, event: InputEventKey, root: Node, tool_id: int, paint_mode: bool
) -> int:
	if plugin == null or event == null or root == null:
		return PASS
	var dock = plugin.get("dock")
	var keymap = plugin.get("_keymap")

	# Numeric input during drag/extrude
	if root.input_state.is_dragging() or root.input_state.is_extruding():
		var nr = plugin._handle_numeric_input(event, root)
		if nr != PASS:
			return nr

	# Hotkey palette toggle (? = Shift+/ or F1 or Ctrl+K)
	if plugin._hotkey_palette:
		if plugin._hotkey_palette.visible and event.keycode == KEY_ESCAPE:
			plugin._hotkey_palette.visible = false
			return STOP
		if (event.keycode == KEY_SLASH and event.shift_pressed) or event.keycode == KEY_F1:
			plugin._on_toggle_hotkey_palette()
			return STOP
		if event.keycode == KEY_K and event.ctrl_pressed:
			plugin._on_toggle_hotkey_palette()
			return STOP
	if event.keycode == KEY_ESCAPE:
		return STOP if plugin._cancel_escape_step(root) else PASS
	# High-level workflow shortcuts stay together so they remain predictable
	# regardless of the currently active draw/select/paint tool.
	if keymap.matches("toggle_operation", event):
		plugin._on_context_toggle_operation()
		return STOP
	if keymap.matches("toggle_paint_mode", event):
		plugin._toggle_paint_mode()
		return STOP
	if keymap.matches("quick_play", event):
		if dock:
			dock._on_quick_play()
		return STOP
	if keymap.matches("validate_level", event):
		if dock:
			dock._on_validate_level()
		return STOP
	# Operation replay toggle (Ctrl+Shift+T)
	if event.keycode == KEY_T and event.ctrl_pressed and event.shift_pressed:
		if plugin._operation_replay and is_instance_valid(plugin._operation_replay):
			plugin._operation_replay.toggle_visible()
		else:
			plugin._toast_power_user_overlay_hint()
		return STOP

	# External tool keyboard dispatch first — external tools can override keys
	if plugin._tool_registry and plugin._tool_registry.has_active_external_tool():
		var ext_result = plugin._tool_registry.dispatch_keyboard(event)
		if ext_result == STOP:
			return ext_result

	# Viewport context menu — only when idle (no active operation, no active external tool)
	if keymap.matches("context_menu", event):
		var has_active_ext = plugin._tool_registry and plugin._tool_registry.has_active_external_tool()
		if root.input_state.is_idle() and not has_active_ext:
			plugin._show_viewport_context_menu(root, tool_id)
			return STOP
	# Radial menu toggle — same idle guard
	if keymap.matches("radial_menu", event):
		if plugin._radial_menu and is_instance_valid(plugin._radial_menu):
			if plugin._radial_menu.is_active():
				plugin._radial_menu.hide_menu()
				return STOP
			var radial_ext = plugin._tool_registry and plugin._tool_registry.has_active_external_tool()
			if root.input_state.is_idle() and not radial_ext:
				plugin._radial_menu.show_at(plugin._get_current_overlay_mouse_pos())
				return STOP
		else:
			plugin._toast_power_user_overlay_hint()
			return STOP

	# Double-tap detection for quick property popups (G G, B B, R R)
	# Must come before keymap matches so the second tap is intercepted.
	var tap_now := Time.get_ticks_msec()
	if not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
		if event.keycode == plugin._last_tap_keycode and (tap_now - plugin._last_tap_time) < plugin._DOUBLE_TAP_MS:
			var handled = plugin._handle_double_tap(event.keycode, root, paint_mode)
			if handled:
				plugin._last_tap_keycode = 0
				return STOP
		plugin._last_tap_keycode = event.keycode
		plugin._last_tap_time = tap_now

	if keymap.matches("delete", event):
		var delete_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Delete")
		if delete_guard != SHORTCUT_APPLY:
			return delete_guard
		plugin._delete_selected(root)
		return STOP
	if keymap.matches("duplicate", event):
		var duplicate_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Duplicate")
		if duplicate_guard != SHORTCUT_APPLY:
			return duplicate_guard
		plugin._duplicate_selected(root)
		return STOP
	if keymap.matches("group", event):
		var group_guard = plugin._guard_hammerforge_shortcut(root, false, 2, "Group")
		if group_guard != SHORTCUT_APPLY:
			return group_guard
		plugin._group_selected(root)
		return STOP
	if keymap.matches("ungroup", event):
		var ungroup_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Ungroup")
		if ungroup_guard != SHORTCUT_APPLY:
			return ungroup_guard
		plugin._ungroup_selected(root)
		return STOP
	if keymap.matches("hollow", event):
		var hollow_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Hollow")
		if hollow_guard != SHORTCUT_APPLY:
			return hollow_guard
		plugin._hollow_selected(root)
		return STOP
	if keymap.matches("move_to_floor", event):
		var floor_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Move to Floor")
		if floor_guard != SHORTCUT_APPLY:
			return floor_guard
		plugin._move_selected_to_floor(root)
		return STOP
	if keymap.matches("move_to_ceiling", event):
		var ceiling_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Move to Ceiling")
		if ceiling_guard != SHORTCUT_APPLY:
			return ceiling_guard
		plugin._move_selected_to_ceiling(root)
		return STOP
	if keymap.matches("clip", event):
		var clip_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Clip")
		if clip_guard != SHORTCUT_APPLY:
			return clip_guard
		plugin._clip_selected(root)
		return STOP
	if keymap.matches("carve", event):
		var carve_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Carve")
		if carve_guard != SHORTCUT_APPLY:
			return carve_guard
		plugin._carve_selected(root)
		return STOP
	if keymap.matches("merge", event):
		var merge_guard = plugin._guard_hammerforge_shortcut(root, true, 2, "Merge")
		if merge_guard != SHORTCUT_APPLY:
			return merge_guard
		plugin._merge_selected(root)
		return STOP
	# Nudge keys
	var nudge = plugin._get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO and not event.ctrl_pressed and not event.alt_pressed:
		var nudge_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Nudge")
		if nudge_guard != SHORTCUT_APPLY:
			return nudge_guard
		plugin._nudge_selected(root, nudge)
		return STOP
	# Grid snap size shortcuts ([ = halve, ] = double)
	if keymap.matches("grid_decrease", event):
		plugin._adjust_grid_snap(root, 0.5)
		return STOP
	if keymap.matches("grid_increase", event):
		plugin._adjust_grid_snap(root, 2.0)
		return STOP
	# Tool switch shortcuts
	if keymap.matches("tool_draw", event):
		plugin._prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		plugin._deactivate_external_tool()
		if dock.tool_draw:
			dock.tool_draw.button_pressed = true
		plugin._update_hud_context()
		return STOP
	if keymap.matches("tool_select", event):
		plugin._prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		plugin._deactivate_external_tool()
		if dock.tool_select:
			dock.tool_select.button_pressed = true
		plugin._update_hud_context()
		return STOP
	if keymap.matches("tool_extrude_up", event):
		plugin._prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		plugin._deactivate_external_tool()
		dock.set_extrude_tool(1)
		plugin._update_hud_context()
		return STOP
	if keymap.matches("tool_extrude_down", event):
		plugin._prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		plugin._deactivate_external_tool()
		dock.set_extrude_tool(-1)
		plugin._update_hud_context()
		return STOP
	# E / Shift+E for extrude (Blender convention) — skip in paint and vertex modes
	if not paint_mode and not plugin._vertex_mode:
		if keymap.matches("tool_extrude", event):
			plugin._prepare_tool_transition(root)
			dock.highlight_tab("Brush")
			plugin._deactivate_external_tool()
			dock.set_extrude_tool(1)
			plugin._update_hud_context()
			return STOP
		if keymap.matches("tool_extrude_down_alt", event):
			plugin._prepare_tool_transition(root)
			dock.highlight_tab("Brush")
			plugin._deactivate_external_tool()
			dock.set_extrude_tool(-1)
			plugin._update_hud_context()
			return STOP
	# Texture picker (eyedropper) — T key activates click-to-sample mode
	if keymap.matches("texture_picker", event):
		plugin._texture_picker_active = true
		if dock:
			dock.show_toast("Texture Picker: click a face to sample its material", 0)
		return STOP
	# Apply Last Texture — Shift+T reapplies the last picked material
	if keymap.matches("apply_last_texture", event):
		var has_selected_faces: bool = (
			root.face_selection is Dictionary and not root.face_selection.is_empty()
		)
		if not has_selected_faces:
			var texture_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Apply Texture")
			if texture_guard != SHORTCUT_APPLY:
				return texture_guard
		plugin._apply_last_texture(root)
		return STOP
	# Select Similar — Shift+S selects matching faces/brushes
	if keymap.matches("select_similar", event):
		var has_similar_face_source: bool = (
			root.face_selection is Dictionary and not root.face_selection.is_empty()
		)
		if not has_similar_face_source:
			var similar_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Select Similar")
			if similar_guard != SHORTCUT_APPLY:
				return similar_guard
		plugin._select_similar(root)
		return STOP
	# Selection Filter popup — Shift+F opens the filter popover
	if keymap.matches("selection_filter", event):
		var filter_scope = plugin.classify_selection_scope(plugin._current_selection_nodes(), root)
		# plugin.SelectionScope: EMPTY=0, NATIVE_ONLY=1, HAMMERFORGE_ONLY=2, MIXED=3
		if filter_scope == 1:
			return PASS
		if filter_scope == 3:
			if dock:
				dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
			return STOP
		plugin._show_selection_filter()
		return STOP
	# Select All / Deselect All — A / Shift+A (Blender convention)
	if keymap.matches("select_all", event):
		plugin._select_all_nodes(root)
		return STOP
	if keymap.matches("deselect_all", event):
		plugin._deselect_all_nodes(root)
		return STOP
	# Quick Save as Prefab — Ctrl+Shift+P
	if event.keycode == KEY_P and event.ctrl_pressed and event.shift_pressed:
		var save_prefab_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Save Prefab")
		if save_prefab_guard != SHORTCUT_APPLY:
			return save_prefab_guard
		plugin._quick_save_prefab(root, false)
		return STOP
	# Cycle Prefab Variant — Ctrl+Shift+V
	if event.keycode == KEY_V and event.ctrl_pressed and event.shift_pressed:
		var variant_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Cycle Variant")
		if variant_guard != SHORTCUT_APPLY:
			return variant_guard
		plugin._cycle_prefab_variant(root)
		return STOP
	# Paint tool shortcuts
	if paint_mode:
		var paint_key := -1
		if keymap.matches("paint_bucket", event):
			paint_key = 0
		elif keymap.matches("paint_erase", event):
			paint_key = 1
		elif keymap.matches("paint_ramp", event):
			paint_key = 2
		elif keymap.matches("paint_line", event):
			paint_key = 3
		elif keymap.matches("paint_fill", event):
			paint_key = 4
		elif keymap.matches("paint_blend", event):
			paint_key = 5
		if paint_key >= 0:
			dock.set_paint_tool(paint_key)
			return STOP
	# Axis lock for construction tools and Select's vertex-edit operation.
	if plugin.axis_lock_shortcuts_available(tool_id, plugin._vertex_mode):
		if keymap.matches("axis_x", event):
			root.set_axis_lock(LevelRootType.AxisLock.X, true)
			plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
			return STOP
		if keymap.matches("axis_y", event):
			root.set_axis_lock(LevelRootType.AxisLock.Y, true)
			plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
			return STOP
		if keymap.matches("axis_z", event):
			root.set_axis_lock(LevelRootType.AxisLock.Z, true)
			plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
			return STOP
	# Vertex edit toggle (V key)
	if keymap.matches("vertex_edit", event):
		var vertex_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Vertex Edit")
		if vertex_guard != SHORTCUT_APPLY:
			return vertex_guard
		plugin._toggle_vertex_mode(root)
		plugin._show_coach_mark_for_action("vertex_edit")
		return STOP
	# External tool shortcuts
	if plugin._tool_registry:
		var ext_id = plugin._tool_registry.check_shortcut(event.keycode)
		if ext_id >= 0 and plugin.active_root:
			plugin._activate_external_tool(ext_id, plugin.active_root)
			plugin._show_coach_mark_for_tool_id(ext_id)
			plugin._update_hud_context()
			return STOP
	return PASS
