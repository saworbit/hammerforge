@tool
extends EditorPlugin


## Tracks the native camera's RMB press/motion/release ownership without
## depending on editor selection or HammerForge's persistent tool mode.
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
			# Recover after a focus change that hid the release event.
			active = false
			return false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# A fresh press supersedes stale state and must be classified by
				# the current gesture owner.
				active = false
				return false
			active = false
			return true
		# While Godot owns RMB camera navigation, all other viewport input
		# belongs to that native session too (notably WASD flight and mixed
		# mouse buttons). HammerForge resumes only after RMB release/recovery.
		return true


const DockType = preload("dock.gd")
const HFPathToolType = preload("hf_path_tool.gd")
const HFSelectionGestureType = preload("hf_selection_gesture.gd")
const HFBrushChangeTrackerType = preload("hf_brush_change_tracker.gd")
var dock: DockType
var hud: Control
var base_control: Control
var active_root: LevelRoot = null
var undo_redo_manager: EditorUndoRedoManager = null
var brush_gizmo_plugin: EditorNode3DGizmoPlugin = null
var hf_selection: Array = []
var _selection_gesture := HFSelectionGestureType.new()
var _brush_change_tracker := HFBrushChangeTrackerType.new()
var _brush_reconcile_queued := false
var _marquee_overlay_origin := Vector2.ZERO
var _marquee_overlay_current := Vector2.ZERO
var _marquee_overlay_active := false
var _native_selection_active := false
var _native_selection_before: Array = []
var _native_selection_additive := false
var _native_selection_toggle := false
var _focus_recovery_queued := false
var _applying_hf_selection := false
var _face_mode_saved_object_selection: Array = []
const SELECT_DRAG_THRESHOLD := 6.0
const POWER_USER_OVERLAYS_HINT := "Enable Power-user overlays in Test → Settings"
var last_3d_camera: Camera3D = null
var last_3d_mouse_pos := Vector2.ZERO
var _rmb_camera_navigation := RmbCameraNavigationSession.new()
var numeric_buffer := ""
var _tool_registry: HFToolRegistry = null
var _keymap: HFKeymap = null
var _user_prefs: HFUserPrefs = null
var _vertex_mode := false
var _vertex_drag_active := false
var _vertex_drag_start := Vector2.ZERO
var _vertex_overlay_mesh: MeshInstance3D = null
var _vertex_overlay_imesh: ImmediateMesh = null
var _texture_picker_active := false
var _last_picked_material_index := -1
var _disp_paint_active := false
var _disp_paint_brush_id := ""
var _disp_paint_face_idx := -1
var _disp_paint_pre_state: Dictionary = {}
var _context_toolbar: Control = null
var _hotkey_palette: Control = null
var _selection_filter: Window = null
var _coach_marks: Control = null
var _operation_replay: Control = null
var _viewport_context_menu: PopupMenu = null
var _radial_menu: Control = null
var _quick_property: Control = null
var _dialog_manager  # HFDialogManager — tracks confirmation dialogs for cleanup
# Double-tap detection for quick property popups
var _last_tap_keycode := 0
var _last_tap_time := 0
const _DOUBLE_TAP_MS := 350
const LevelRootType = preload("level_root.gd")
const HFDialogManagerType = preload("plugin_dialogs.gd")
const HFContextToolbar = preload("ui/hf_context_toolbar.gd")
const HFHotkeyPalette = preload("ui/hf_hotkey_palette.gd")
const HFSelectionFilter = preload("ui/hf_selection_filter.gd")
const HFCoachMarks = preload("ui/hf_coach_marks.gd")
const HFOperationReplay = preload("ui/hf_operation_replay.gd")
const HFViewportContextMenu = preload("ui/hf_viewport_context_menu.gd")
const HFRadialMenu = preload("ui/hf_radial_menu.gd")
const HFQuickProperty = preload("ui/hf_quick_property.gd")
const DraftEntityType = preload("draft_entity.gd")
const IconRes = preload("icon.png")
const HFUndoHelper = preload("undo_helper.gd")
const HFInputStateType = preload("input_state.gd")
const QUICK_PROPERTY_DISMISS_CONTINUE := -1
const SELECT_INPUT_CONTINUE := -2
const HF_SHORTCUT_APPLY := -3

enum SelectionScope { EMPTY, NATIVE_ONLY, HAMMERFORGE_ONLY, MIXED }


func _notification(what: int) -> void:
	if (
		what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]
		and is_inside_tree()
		and not _focus_recovery_queued
	):
		_focus_recovery_queued = true
		call_deferred("_recover_after_application_focus_loss")


func _recover_after_application_focus_loss() -> void:
	_focus_recovery_queued = false
	_rmb_camera_navigation.active = false
	# Godot's 3D viewport owns native/custom gizmo focus-loss commit and clears
	# its private edit reference itself. Cancelling the local lifecycle here can
	# race that callback and restore a preview Godot has just committed.
	_cancel_selection_gesture()
	if _tool_registry:
		_tool_registry.cancel_active_pointer_capture()
	_queue_managed_brush_reconcile()
	var root := active_root if active_root else _get_level_root()
	if not root:
		return
	_prepare_tool_transition(root, false, false)
	root.clear_hover()
	if root.has_method("clear_face_hover_highlight"):
		root.clear_face_hover_highlight()


func _enter_tree():
	# HammerForge raycasts in the 3D viewport regardless of which editor object
	# is selected. Keep that input forwarding independent from _handles(), which
	# should describe only the object types this plugin actually edits.
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	call_deferred("_prime_managed_brush_tracker")
	add_custom_type("LevelRoot", "Node3D", LevelRootType, IconRes)
	add_custom_type("DraftEntity", "Node3D", DraftEntityType, IconRes)
	_dialog_manager = HFDialogManagerType.new()
	dock = preload("dock.tscn").instantiate()
	undo_redo_manager = get_undo_redo()
	brush_gizmo_plugin = preload("brush_gizmo_plugin.gd").new()
	if brush_gizmo_plugin:
		brush_gizmo_plugin.set_undo_redo(undo_redo_manager)
		if brush_gizmo_plugin.has_signal("handle_action_started"):
			brush_gizmo_plugin.connect(
				"handle_action_started", Callable(self, "_on_brush_gizmo_action_started")
			)
		if brush_gizmo_plugin.has_signal("handle_action_finished"):
			brush_gizmo_plugin.connect(
				"handle_action_finished", Callable(self, "_on_brush_gizmo_action_finished")
			)
		add_node_3d_gizmo_plugin(brush_gizmo_plugin)
	base_control = get_editor_interface().get_base_control()
	if base_control:
		dock.theme = base_control.theme
		if dock:
			dock.apply_editor_styles(base_control)
		if not base_control.is_connected(
			"theme_changed", Callable(self, "_on_editor_theme_changed")
		):
			base_control.connect("theme_changed", Callable(self, "_on_editor_theme_changed"))
	_tool_registry = HFToolRegistry.new()
	_tool_registry.register_tool(HFMeasureTool.new())
	_tool_registry.register_tool(HFDecalTool.new())
	_tool_registry.register_tool(HFPolygonTool.new())
	_tool_registry.register_tool(HFPathToolType.new())
	_tool_registry.load_external_tools("res://addons/hammerforge/tools/")
	_keymap = HFKeymap.load_or_default("user://hammerforge_keymap.json")
	_user_prefs = HFUserPrefs.load_prefs()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	if dock:
		dock.set_editor_interface(get_editor_interface())
		dock.set_undo_redo(undo_redo_manager)
		dock.set_plugin(self)
		dock.set_keymap(_keymap)
		dock.set_user_prefs(_user_prefs)
		if dock.has_signal("hud_visibility_changed"):
			dock.connect("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed"))
		if dock.has_signal("builtin_tool_changed"):
			dock.connect("builtin_tool_changed", Callable(self, "_on_builtin_tool_changed"))
		if dock.has_signal("vertex_mode_toggled"):
			dock.connect("vertex_mode_toggled", Callable(self, "_on_vertex_mode_toggled"))
		if dock.has_signal("face_select_mode_toggled"):
			dock.connect("face_select_mode_toggled", Callable(self, "_on_face_select_mode_toggled"))
		if dock.has_signal("selection_clear_requested"):
			dock.connect("selection_clear_requested", Callable(self, "_on_dock_selection_clear"))
		if dock.has_signal("grid_snap_applied"):
			dock.connect("grid_snap_applied", Callable(self, "_on_dock_grid_snap_applied"))
		if dock.has_signal("bake_state_changed"):
			dock.connect("bake_state_changed", Callable(self, "_on_dock_bake_state_changed"))
		if dock.has_signal("command_palette_requested"):
			dock.connect("command_palette_requested", Callable(self, "_on_toggle_hotkey_palette"))
		if dock.has_signal("power_user_overlays_changed"):
			dock.connect(
				"power_user_overlays_changed",
				Callable(self, "_on_dock_power_user_overlays_changed")
			)

	hud = preload("shortcut_hud.tscn").instantiate()
	if base_control:
		hud.theme = base_control.theme
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
	if hud.has_method("set_user_prefs"):
		hud.set_user_prefs(_user_prefs)
	if dock:
		hud.visible = dock.get_show_hud()
	# Context toolbar (floating above 3D viewport)
	_context_toolbar = HFContextToolbar.new()
	if base_control:
		_context_toolbar.theme = base_control.theme
	_context_toolbar.set_keymap(_keymap)
	_context_toolbar.action_requested.connect(_on_context_toolbar_action)
	_context_toolbar.operation_toggle_requested.connect(_on_context_toggle_operation)
	_context_toolbar.tool_switch_requested.connect(_on_context_tool_switch)
	_context_toolbar.material_quick_apply.connect(_on_context_material_apply)
	_context_toolbar.hotkey_palette_requested.connect(_on_toggle_hotkey_palette)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _context_toolbar)
	# Hotkey palette (command palette overlay)
	_hotkey_palette = HFHotkeyPalette.new()
	if base_control:
		_hotkey_palette.theme = base_control.theme
	_hotkey_palette.populate(_keymap)
	_hotkey_palette.action_invoked.connect(_on_hotkey_palette_action)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _hotkey_palette)
	# Selection filter popover (Window-based — not a Control, so managed manually)
	_selection_filter = HFSelectionFilter.new()
	_selection_filter.filter_applied.connect(_on_selection_filter_applied)
	get_editor_interface().get_base_control().add_child(_selection_filter)
	if should_install_power_user_overlays(_user_prefs):
		_install_power_user_overlays()
	# Space-key context menu (PopupMenu — added as child of base_control, not container)
	_viewport_context_menu = HFViewportContextMenu.new()
	if base_control:
		_viewport_context_menu.theme = base_control.theme
	_viewport_context_menu.action_requested.connect(_on_viewport_action)
	if base_control:
		base_control.add_child(_viewport_context_menu)
	# Quick property popup (double-tap G/B/R)
	_quick_property = HFQuickProperty.new()
	if base_control:
		_quick_property.theme = base_control.theme
	_quick_property.value_committed.connect(_on_quick_property_committed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _quick_property)
	var selection = get_editor_interface().get_selection()
	if selection:
		if not selection.is_connected(
			"selection_changed", Callable(self, "_on_editor_selection_changed")
		):
			selection.connect("selection_changed", Callable(self, "_on_editor_selection_changed"))
		hf_selection = selection.get_selected_nodes()
		if dock and hf_selection.size() > 0:
			dock.set_selection_count(hf_selection.size())
			dock.set_selection_nodes(hf_selection)
	# Listen for undo/redo to cancel in-flight tool previews and avoid orphaned nodes
	if undo_redo_manager and undo_redo_manager.has_signal("version_changed"):
		if not undo_redo_manager.is_connected(
			"version_changed", Callable(self, "_on_undo_redo_version_changed")
		):
			undo_redo_manager.connect(
				"version_changed", Callable(self, "_on_undo_redo_version_changed")
			)
	set_process(false)


func _exit_tree():
	_cancel_selection_gesture()
	_brush_reconcile_queued = false
	_ensure_brush_change_tracker().reset()
	if _tool_registry and _tool_registry.has_active_external_tool():
		_tool_registry.deactivate_current()
	_cleanup_pending_dialogs()
	remove_custom_type("LevelRoot")
	remove_custom_type("DraftEntity")
	if (
		undo_redo_manager
		and undo_redo_manager.is_connected(
			"version_changed", Callable(self, "_on_undo_redo_version_changed")
		)
	):
		undo_redo_manager.disconnect(
			"version_changed", Callable(self, "_on_undo_redo_version_changed")
		)
	undo_redo_manager = null
	if brush_gizmo_plugin:
		if (
			_brush_gizmo_action_active()
			and brush_gizmo_plugin.has_method("cancel_active_handle_action")
		):
			brush_gizmo_plugin.call("cancel_active_handle_action")
		if brush_gizmo_plugin.is_connected(
			"handle_action_started", Callable(self, "_on_brush_gizmo_action_started")
		):
			brush_gizmo_plugin.disconnect(
				"handle_action_started", Callable(self, "_on_brush_gizmo_action_started")
			)
		if brush_gizmo_plugin.is_connected(
			"handle_action_finished", Callable(self, "_on_brush_gizmo_action_finished")
		):
			brush_gizmo_plugin.disconnect(
				"handle_action_finished", Callable(self, "_on_brush_gizmo_action_finished")
			)
		remove_node_3d_gizmo_plugin(brush_gizmo_plugin)
		brush_gizmo_plugin = null
	if (
		base_control
		and base_control.is_connected("theme_changed", Callable(self, "_on_editor_theme_changed"))
	):
		base_control.disconnect("theme_changed", Callable(self, "_on_editor_theme_changed"))
	if dock:
		if dock.is_connected(
			"hud_visibility_changed", Callable(self, "_on_hud_visibility_changed")
		):
			dock.disconnect("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed"))
		if dock.is_connected("builtin_tool_changed", Callable(self, "_on_builtin_tool_changed")):
			dock.disconnect("builtin_tool_changed", Callable(self, "_on_builtin_tool_changed"))
		if dock.is_connected("vertex_mode_toggled", Callable(self, "_on_vertex_mode_toggled")):
			dock.disconnect("vertex_mode_toggled", Callable(self, "_on_vertex_mode_toggled"))
		if dock.is_connected(
			"selection_clear_requested", Callable(self, "_on_dock_selection_clear")
		):
			dock.disconnect("selection_clear_requested", Callable(self, "_on_dock_selection_clear"))
		if dock.is_connected("grid_snap_applied", Callable(self, "_on_dock_grid_snap_applied")):
			dock.disconnect("grid_snap_applied", Callable(self, "_on_dock_grid_snap_applied"))
		if dock.is_connected("bake_state_changed", Callable(self, "_on_dock_bake_state_changed")):
			dock.disconnect("bake_state_changed", Callable(self, "_on_dock_bake_state_changed"))
		if dock.is_connected(
			"command_palette_requested", Callable(self, "_on_toggle_hotkey_palette")
		):
			dock.disconnect(
				"command_palette_requested", Callable(self, "_on_toggle_hotkey_palette")
			)
		if dock.is_connected(
			"power_user_overlays_changed", Callable(self, "_on_dock_power_user_overlays_changed")
		):
			dock.disconnect(
				"power_user_overlays_changed",
				Callable(self, "_on_dock_power_user_overlays_changed")
			)
		remove_control_from_docks(dock)
		if is_instance_valid(dock):
			dock.queue_free()
		dock = null
	if hud:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
		if is_instance_valid(hud):
			hud.queue_free()
		hud = null
	if _context_toolbar:
		if is_instance_valid(_context_toolbar):
			_context_toolbar.action_requested.disconnect(_on_context_toolbar_action)
			_context_toolbar.operation_toggle_requested.disconnect(_on_context_toggle_operation)
			_context_toolbar.tool_switch_requested.disconnect(_on_context_tool_switch)
			_context_toolbar.material_quick_apply.disconnect(_on_context_material_apply)
			_context_toolbar.hotkey_palette_requested.disconnect(_on_toggle_hotkey_palette)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _context_toolbar)
		if is_instance_valid(_context_toolbar):
			_context_toolbar.queue_free()
		_context_toolbar = null
	if _hotkey_palette:
		if is_instance_valid(_hotkey_palette):
			_hotkey_palette.action_invoked.disconnect(_on_hotkey_palette_action)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _hotkey_palette)
		if is_instance_valid(_hotkey_palette):
			_hotkey_palette.queue_free()
		_hotkey_palette = null
	if _selection_filter:
		if is_instance_valid(_selection_filter):
			_selection_filter.filter_applied.disconnect(_on_selection_filter_applied)
			if _selection_filter.get_parent():
				_selection_filter.get_parent().remove_child(_selection_filter)
			_selection_filter.queue_free()
		_selection_filter = null
	if _coach_marks:
		if is_instance_valid(_coach_marks):
			_coach_marks.guide_dismissed.disconnect(_on_coach_mark_dismissed)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _coach_marks)
		if is_instance_valid(_coach_marks):
			_coach_marks.queue_free()
		_coach_marks = null
	if _operation_replay:
		if is_instance_valid(_operation_replay):
			_operation_replay.replay_requested.disconnect(_on_replay_requested)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _operation_replay)
		if is_instance_valid(_operation_replay):
			_operation_replay.queue_free()
		_operation_replay = null
	if _viewport_context_menu:
		if is_instance_valid(_viewport_context_menu):
			_viewport_context_menu.action_requested.disconnect(_on_viewport_action)
			if _viewport_context_menu.get_parent():
				_viewport_context_menu.get_parent().remove_child(_viewport_context_menu)
			_viewport_context_menu.queue_free()
		_viewport_context_menu = null
	if _radial_menu:
		if is_instance_valid(_radial_menu):
			_radial_menu.action_selected.disconnect(_on_radial_action)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _radial_menu)
		if is_instance_valid(_radial_menu):
			_radial_menu.queue_free()
		_radial_menu = null
	if _quick_property:
		if is_instance_valid(_quick_property):
			_quick_property.value_committed.disconnect(_on_quick_property_committed)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _quick_property)
		if is_instance_valid(_quick_property):
			_quick_property.queue_free()
		_quick_property = null
	var selection = get_editor_interface().get_selection()
	if (
		selection
		and selection.is_connected(
			"selection_changed", Callable(self, "_on_editor_selection_changed")
		)
	):
		selection.disconnect("selection_changed", Callable(self, "_on_editor_selection_changed"))
	_tool_registry = null
	set_process(false)


func _on_editor_theme_changed() -> void:
	if not base_control:
		return
	if dock:
		dock.theme = base_control.theme
		dock.apply_editor_styles(base_control)
	if hud:
		hud.theme = base_control.theme
	if _context_toolbar:
		_context_toolbar.theme = base_control.theme
		if _context_toolbar.has_method("refresh_theme_colors"):
			_context_toolbar.refresh_theme_colors()
	if _hotkey_palette:
		_hotkey_palette.theme = base_control.theme
		if _hotkey_palette.has_method("refresh_theme_colors"):
			_hotkey_palette.refresh_theme_colors()
	if _coach_marks:
		_coach_marks.theme = base_control.theme
		if _coach_marks.has_method("refresh_theme_colors"):
			_coach_marks.refresh_theme_colors()
	if _operation_replay:
		_operation_replay.theme = base_control.theme
		if _operation_replay.has_method("refresh_theme_colors"):
			_operation_replay.refresh_theme_colors()
	if _viewport_context_menu:
		_viewport_context_menu.theme = base_control.theme
	if _radial_menu:
		_radial_menu.theme = base_control.theme
	if _quick_property:
		_quick_property.theme = base_control.theme
		if _quick_property.has_method("refresh_theme_colors"):
			_quick_property.refresh_theme_colors()


func _on_hud_visibility_changed(visible: bool) -> void:
	if hud:
		hud.visible = visible


func _update_hud_context() -> void:
	if not hud or not hud.has_method("update_context"):
		return
	var ctx := {}
	var tool_id_ctx = dock.get_tool() if dock else 0
	ctx["tool"] = tool_id_ctx
	ctx["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	ctx["paint_target"] = dock.get_paint_target() if dock else 0
	ctx["mode"] = 0
	ctx["axis_lock"] = 0
	ctx["external_tool_name"] = ""
	ctx["external_shortcuts"] = PackedStringArray()
	var root = active_root if active_root else _get_level_root()
	if root and root.input_state:
		ctx["mode"] = root.input_state.mode
		ctx["axis_lock"] = root.input_state.axis_lock
	# Update dock mode indicator banner
	if dock:
		var mode_name := "Draw"
		var active_external = _tool_registry.get_active_tool() if _tool_registry else null
		if active_external and _tool_registry.has_active_external_tool():
			mode_name = active_external.tool_name()
			ctx["external_tool_name"] = mode_name
			ctx["external_shortcuts"] = active_external.get_shortcut_hud_lines()
		elif _vertex_mode:
			mode_name = "Vertex"
		elif ctx.get("paint_mode", false):
			mode_name = "Paint"
		else:
			match tool_id_ctx:
				1:
					mode_name = "Select"
				2:
					mode_name = "Extrude ▲"
				3:
					mode_name = "Extrude ▼"
		var stage_hint := ""
		if root and root.input_state:
			if root.input_state.is_drag_base():
				var dims = root.input_state.get_drag_dimensions()
				var dim_str = HFInputStateType.format_dimensions(dims)
				stage_hint = "Step 1/2: Draw base"
				if dim_str != "":
					stage_hint += " — " + dim_str
			elif root.input_state.is_drag_height():
				var dims = root.input_state.get_drag_dimensions()
				var dim_str = HFInputStateType.format_dimensions(dims)
				stage_hint = "Step 2/2: Set height"
				if dim_str != "":
					stage_hint += " — " + dim_str
			elif root.input_state.is_extruding():
				stage_hint = "Extruding..."
			elif root.input_state.is_surface_painting():
				stage_hint = "Painting..."
		var num_display := ""
		if numeric_buffer.length() > 0:
			num_display = numeric_buffer
		dock.set_mode_indicator(mode_name, stage_hint, num_display)
	# Clear stale face hover highlight when not in extrude mode
	if root and tool_id_ctx != 2 and tool_id_ctx != 3:
		if root.has_method("clear_face_hover_highlight"):
			root.clear_face_hover_highlight()
	if numeric_buffer.length() > 0:
		ctx["numeric"] = numeric_buffer
	hud.update_context(ctx)
	# Feed grid snap to HUD indicator
	if root and hud.has_method("update_grid_snap"):
		hud.update_grid_snap(root.grid_snap)
	# Update context toolbar and hotkey palette state
	_update_context_toolbar_state(root, tool_id_ctx)


func _update_context_toolbar_state(root: Node, tool_id: int) -> void:
	if not _context_toolbar and not _hotkey_palette:
		return
	var state := {}
	state["has_root"] = root != null
	state["tool"] = tool_id
	state["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	state["vertex_mode"] = _vertex_mode
	state["is_subtract"] = dock.get_operation() != 0 if dock else false  # 0 = UNION
	state["has_active_external_tool"] = (
		_tool_registry.has_active_external_tool() if _tool_registry else false
	)

	# Input mode
	var input_mode := 0
	if root and root.input_state:
		input_mode = root.input_state.mode
		var dims = root.input_state.get_drag_dimensions()
		state["dimensions"] = HFInputStateType.format_dimensions(dims)
	state["input_mode"] = input_mode

	# Count from the authoritative editor selection. Mixed native/HammerForge
	# selections must remain visible to every action surface so none of them can
	# silently mutate only the managed subset.
	var selection_nodes := _current_selection_nodes()
	state["mixed_selection"] = (
		classify_selection_scope(selection_nodes, root) == SelectionScope.MIXED if root else false
	)
	var brush_count := 0
	var entity_count := 0
	for node in selection_nodes:
		if node is DraftBrush:
			brush_count += 1
		elif root and root.has_method("is_entity_node") and root.is_entity_node(node):
			entity_count += 1
	state["brush_count"] = brush_count
	state["entity_count"] = entity_count

	# I/O connection summary for entity context toolbar
	if entity_count > 0 and root and root.has_method("get_connection_summary"):
		var first_entity: Node = null
		for node in selection_nodes:
			if root.has_method("is_entity_node") and root.is_entity_node(node):
				first_entity = node
				break
		if first_entity:
			var summary = root.get_connection_summary(first_entity.name)
			var triggers: int = summary.get("triggers", 0)
			var triggered_by: int = summary.get("triggered_by", 0)
			var parts: Array = []
			if triggers > 0:
				var targets: Array = summary.get("target_names", [])
				parts.append("%d out" % triggers)
			if triggered_by > 0:
				parts.append("%d in" % triggered_by)
			if not parts.is_empty():
				state["io_summary"] = " | ".join(parts)

	# Push highlight_connected state so both toolbar and wiring panel stay in sync
	if root and root.get("io_visualizer") and root.io_visualizer:
		state["highlight_connected"] = root.io_visualizer.highlight_connected

	# Face selection count
	var face_count := 0
	if root and root.get("face_selection") is Dictionary:
		for key in root.face_selection.keys():
			var indices = root.face_selection.get(key, [])
			face_count += indices.size()
	state["face_count"] = face_count

	# Pending cut count for "Apply Cuts" button visibility
	var pending_cut_count := 0
	if root and root.pending_node:
		for child in root.pending_node.get_children():
			if child is DraftBrush:
				pending_cut_count += 1
	state["pending_cut_count"] = pending_cut_count
	state["bake_preview_active"] = _bake_preview_active
	state["bake_disabled"] = dock._bake_disabled if dock else false

	# Prefab instance info for context toolbar badge
	if root and root.prefab_system and not hf_selection.is_empty():
		var first_node = hf_selection[0]
		var pfb_iid := (
			str(first_node.get_meta("hf_prefab_instance", ""))
			if is_instance_valid(first_node) and first_node is Node
			else ""
		)
		if not pfb_iid.is_empty():
			var pfb_rec = root.prefab_system.get_instance(pfb_iid)
			if pfb_rec:
				state["prefab_source"] = pfb_rec.source_path
				state["prefab_variant"] = pfb_rec.variant_name
				state["prefab_linked"] = pfb_rec.linked

	if _context_toolbar:
		_context_toolbar.update_state(state)
		# Feed favorite materials to the face-context thumbnail strip
		if face_count > 0 and dock and dock.material_browser:
			_context_toolbar.set_favorite_materials(dock.material_browser.get_favorite_infos(5))
	if _hotkey_palette and _hotkey_palette.visible:
		var palette_state := state.duplicate()
		palette_state["tool"] = hotkey_palette_tool_context(tool_id, _vertex_mode)
		_hotkey_palette.update_state(palette_state)


## Deprecated compatibility seam retained for older source-contract tests and
## downstream integrations. Visible EditorSelection state is authoritative;
## an empty native selection must never leave a hidden HammerForge selection.
static func should_suppress_empty_selection(
	_incoming_nodes: Array, _current_hf_selection: Array
) -> bool:
	# Deprecated compatibility helper. EditorSelection is now authoritative;
	# retaining a hidden cache after a visible deselect is unsafe and surprising.
	return false


static func power_user_overlay_unavailable_message() -> String:
	return POWER_USER_OVERLAYS_HINT


static func should_install_power_user_overlays(prefs) -> bool:
	if prefs == null:
		return false
	if prefs.has_method("is_power_user_overlays_enabled"):
		return bool(prefs.is_power_user_overlays_enabled())
	return bool(prefs.get_pref("power_user_overlays", false))


func _toast_power_user_overlay_hint() -> void:
	if dock and dock.has_method("show_toast"):
		dock.show_toast(power_user_overlay_unavailable_message(), 0)


func _on_dock_power_user_overlays_changed(enabled: bool) -> void:
	if enabled:
		_install_power_user_overlays()
	else:
		_teardown_power_user_overlays()


func _install_power_user_overlays() -> void:
	if _coach_marks == null:
		_coach_marks = HFCoachMarks.new()
		if base_control:
			_coach_marks.theme = base_control.theme
		_coach_marks.set_user_prefs(_user_prefs)
		_coach_marks.guide_dismissed.connect(_on_coach_mark_dismissed)
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _coach_marks)
	if _operation_replay == null:
		_operation_replay = HFOperationReplay.new()
		if base_control:
			_operation_replay.theme = base_control.theme
		_operation_replay.replay_requested.connect(_on_replay_requested)
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _operation_replay)
		if dock:
			dock.set_operation_replay(_operation_replay)
	if _radial_menu == null:
		_radial_menu = HFRadialMenu.new()
		if base_control:
			_radial_menu.theme = base_control.theme
		_radial_menu.action_selected.connect(_on_radial_action)
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _radial_menu)


func _teardown_power_user_overlays() -> void:
	if _coach_marks:
		if is_instance_valid(_coach_marks):
			_coach_marks.guide_dismissed.disconnect(_on_coach_mark_dismissed)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _coach_marks)
		if is_instance_valid(_coach_marks):
			_coach_marks.queue_free()
		_coach_marks = null
	if _operation_replay:
		if is_instance_valid(_operation_replay):
			_operation_replay.replay_requested.disconnect(_on_replay_requested)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _operation_replay)
		if is_instance_valid(_operation_replay):
			_operation_replay.queue_free()
		_operation_replay = null
		if dock:
			dock.set_operation_replay(null)
	if _radial_menu:
		if is_instance_valid(_radial_menu):
			_radial_menu.action_selected.disconnect(_on_radial_action)
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _radial_menu)
		if is_instance_valid(_radial_menu):
			_radial_menu.queue_free()
		_radial_menu = null


func _on_editor_selection_changed() -> void:
	if _applying_hf_selection:
		return
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	var nodes = selection.get_selected_nodes()
	var root := active_root if active_root else _get_level_root()
	var selection_before := _normalize_editor_selection(hf_selection, root)
	if dock and dock.is_face_select_mode_enabled() and not nodes.is_empty():
		# Scene-tree/native object selection is an explicit request to leave the
		# face-edit modal state. Settle any in-flight face marquee/widget ownership
		# before closing so a lost release cannot apply stale faces afterwards.
		# Keep the newly selected object; do not restore the snapshot captured when
		# Face Select was entered.
		_prepare_tool_transition(root, false)
		if dock.face_select_mode:
			dock.face_select_mode.set_pressed_no_signal(false)
		_face_mode_saved_object_selection.clear()
		if root and root.has_method("clear_face_selection"):
			root.clear_face_selection()
		if dock:
			dock.show_toast("Face Select closed for object editing", 0)
	# Scene-tree selection must honor the same managed-owner and visgroup
	# normalization as viewport selection. Treat removal of any group member as
	# removal of the complete group, and selection of one as selection of all.
	var normalized_nodes := _normalize_editor_selection(nodes, root)
	var remove_group := group_removal_requested(
		_native_selection_active,
		_native_selection_additive,
		_native_selection_toggle,
		Input.is_key_pressed(KEY_SHIFT),
		Input.is_key_pressed(KEY_CTRL),
		Input.is_key_pressed(KEY_META)
	)
	var expanded_nodes := _expand_native_group_selection(
		root, selection_before, normalized_nodes, remove_group
	)
	if not _same_node_selection(nodes, expanded_nodes):
		hf_selection = expanded_nodes
		_apply_hf_selection(selection)
		return
	hf_selection = expanded_nodes
	if root:
		# Selection has its own gizmo outline. Clear any hover left under the
		# click immediately; subsequent motion suppresses hover on selected nodes.
		root.clear_hover()
		if root.has_method("set_io_visualizer_selection"):
			root.call("set_io_visualizer_selection", hf_selection)
	if dock:
		dock.set_selection_count(hf_selection.size())
		dock.set_selection_nodes(hf_selection)
	# Update vertex system with current brush selection
	if _vertex_mode:
		if root and root.vertex_system:
			var brushes: Array = []
			for node in hf_selection:
				if node is DraftBrush:
					brushes.append(node)
			root.vertex_system.set_selection(brushes)


static func should_handle_editor_object(object: Object) -> bool:
	if not object or not (object is Node):
		return false
	if object is LevelRootType or object is DraftBrush or object is DraftEntityType:
		return true
	var current := (object as Node).get_parent()
	while current:
		if current is LevelRootType:
			return current.has_method("is_entity_node") and current.is_entity_node(object)
		current = current.get_parent()
	return false


## Viewport Select captures its modifier contract at LMB-down. Scene-tree
## selection has no equivalent callback payload, so sample its standard
## multi-selection modifiers while the synchronous selection_changed signal is
## being delivered. An ambient Ctrl key must never reinterpret a native
## viewport press that HammerForge already recorded as unmodified.
static func group_removal_requested(
	native_session_active: bool,
	native_additive: bool,
	native_toggle: bool,
	shift_pressed: bool,
	ctrl_pressed: bool,
	meta_pressed: bool,
) -> bool:
	if native_session_active:
		return native_additive or native_toggle
	return shift_pressed or ctrl_pressed or meta_pressed


func _handles(object: Object) -> bool:
	return should_handle_editor_object(object)


func _edit(object: Object) -> void:
	if object and object is Node:
		var root = _get_level_root_from_node(object as Node)
		if root:
			active_root = root
			_ensure_brush_change_tracker().ensure_root(root)
			return
	# Don't null active_root — keep the previous root alive as long as it still
	# exists in the scene. This prevents losing the dock/3D connection when the
	# user clicks a Camera, Light, or other non-LevelRoot node.
	if active_root and is_instance_valid(active_root) and active_root.is_inside_tree():
		return
	active_root = null
	_ensure_brush_change_tracker().reset()


## Passive viewport input must not create scene content.  Keep this predicate
## side-effect free so its input-ownership contract can be regression tested.
static func should_create_root_for_viewport_input(
	event: InputEvent, tool_id: int, paint_mode: bool
) -> bool:
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and tool_id == 0
		and not paint_mode
	)


## Clicking outside a quick-property editor protects against accidental LMB
## edits. RMB continues to the active gesture owner; other navigation passes.
static func classify_quick_property_dismiss(event: InputEventMouseButton) -> int:
	if event.button_index == MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.button_index == MOUSE_BUTTON_RIGHT:
		return QUICK_PROPERTY_DISMISS_CONTINUE
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## A live LMB paint stroke keeps pointer ownership until LMB release. Starting
## native camera look midway through the stroke would paint while the view moves.
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


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not dock:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_ensure_selection_runtime_state()
	var face_select_mode := dock.is_face_select_mode_enabled()
	if camera:
		last_3d_camera = camera
	if event is InputEventMouse:
		last_3d_mouse_pos = event.position

	# Once an idle RMB press has been passed to Godot, its motion and release
	# belong to the same native camera-navigation session. Bypass all HammerForge
	# raycasts and hover work until the button is released.
	if _rmb_camera_navigation.handle_followup(event):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var root = active_root if active_root else _get_level_root()
	if not root:
		# Native viewport motion/navigation must never dirty the edited scene.
		# Preserve draw-first convenience only for an intentional primary click.
		var intentional_draw_click := should_create_root_for_viewport_input(
			event,
			1 if face_select_mode else dock.get_tool(),
			dock.is_paint_mode_enabled() and not face_select_mode
		)
		if not intentional_draw_click:
			# Empty levels still use Godot's native RMB camera navigation. Record
			# ownership before passing the press through so global shortcuts stay
			# native until the matching release.
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT
				and event.pressed
			):
				_rmb_camera_navigation.begin()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		root = _create_level_root()
		if not root:
			return EditorPlugin.AFTER_GUI_INPUT_PASS

	var target_camera = camera
	var target_pos = event.position if event is InputEventMouse else last_3d_mouse_pos
	# Face Select is a true modal editing state. Its checkbox lives beside the
	# paint controls for discoverability, but while active it must route exactly
	# like Select and must never share a click with paint, vertex, or plug-in tools.
	var tool_id = 1 if face_select_mode else dock.get_tool()
	var paint_mode = dock.is_paint_mode_enabled() and not face_select_mode
	root.grid_snap = dock.get_grid_snap()

	# Radial menu intercept — must be FIRST. While radial is active, it owns
	# all input. No other intercept (paint, vertex, external tool) should run.
	if _radial_menu and _radial_menu.is_active():
		_radial_menu._gui_input(event)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Quick property popup intercept. LMB click-away is consumed to avoid editing
	# through the popup; native navigation buttons dismiss and continue through.
	if _quick_property and _quick_property.is_active():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_quick_property.hide_popup()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseButton and event.pressed:
			var popup_rect := _quick_property.get_rect()
			if not popup_rect.has_point(event.position):
				_quick_property.hide_popup()
				var dismiss_result := classify_quick_property_dismiss(event)
				if dismiss_result != QUICK_PROPERTY_DISMISS_CONTINUE:
					return dismiss_result
				# RMB continues through the normal ownership path so an active
				# gesture can still cancel instead of being abandoned mid-drag.

	# A Godot gizmo action has exclusive pointer ownership. Its press was passed
	# through deliberately; do no raycasts, hover, or tool dispatch until Godot
	# finishes or cancels it.
	if _brush_gizmo_action_active():
		if is_lmb_release_recovery_motion(event):
			brush_gizmo_plugin.call("cancel_active_handle_action")
		# The custom gizmo remains the exclusive owner until Godot receives a
		# release/RMB/Escape and calls _commit_handle(). A recovered action is
		# frozen locally, so forwarding motion cannot resurrect its preview.
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Buttonless motion is the only reliable recovery signal when the editor or
	# application swallowed LMB-up. Close every stale LMB owner before any tool
	# can mutate from that motion as if the button were still held.
	if is_lmb_release_recovery_motion(event):
		_recover_stale_lmb_gestures(root)

	# Once Select has seen LMB-down, route all follow-ups before other tools. This
	# prevents one physical drag from becoming both a marquee and a widget edit.
	if _selection_gesture and _selection_gesture.is_active():
		if tool_id != 1:
			_cancel_selection_gesture()
		else:
			var select_result := _handle_active_selection_input(
				event, root, target_camera, target_pos
			)
			if select_result != SELECT_INPUT_CONTINUE:
				return select_result

	if event is InputEventMouseMotion or event is InputEventMouseButton:
		root.update_editor_grid(target_camera, target_pos)

	# Displacement paint intercept — must come before regular paint so that
	# displacement surfaces get the stroke when paint mode is active.
	# Only activates when: paint mode ON + Displacement section expanded +
	# a displaced face is selected.
	if not face_select_mode and (_disp_paint_active or _should_start_disp_paint(event, root)):
		var dr = _handle_disp_paint_input(event, root, target_camera, target_pos)
		if dr != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return dr

	# Paint mode intercept
	if paint_mode:
		var r = _handle_paint_input(event, root, target_camera, target_pos)
		if r != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return r

	# External tool dispatch
	if _tool_registry and not face_select_mode:
		var ext_result = _tool_registry.dispatch_input(event, target_camera, target_pos)
		if ext_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if (
			_tool_registry.has_active_external_tool()
			and (event is InputEventMouseButton or event is InputEventMouseMotion)
		):
			# An active external tool stays the sole HammerForge mouse owner even
			# when this particular ray misses. If its idle RMB press was not
			# consumed, record the same native camera session as the common RMB path
			# so follow-up mouse and keyboard events cannot trigger HammerForge tools.
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT
				and event.pressed
			):
				root.clear_hover()
				if root.has_method("clear_face_hover_highlight"):
					root.clear_face_hover_highlight()
				_rmb_camera_navigation.begin()
			# PASS still preserves Godot camera UI.
			return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Vertex editing mode intercept
	if _vertex_mode and root.vertex_system and not face_select_mode:
		var vr = _handle_vertex_input(event, root, target_camera, target_pos)
		if vr != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return vr

	# Texture picker modal intercept — must be ABOVE keyboard shortcuts so that
	# tool-switch keys cannot sneak through while picker is armed.
	if _texture_picker_active:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_texture_picker_active = false
				_pick_face_material(root)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_texture_picker_active = false
				if dock:
					dock.show_toast("Texture Picker cancelled", 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				_texture_picker_active = false
				if dock:
					dock.show_toast("Texture Picker cancelled", 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			# Block all other key events while picker is active.
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# Pass through mouse motion so last_3d_mouse_pos stays current.
		if event is InputEventMouseMotion:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		var r = _handle_keyboard_input(event, root, tool_id, paint_mode)
		if r != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return r

	# Hover is an idle affordance, never a second pointer owner during a drag.
	if tool_id == 1 and event is InputEventMouseMotion and event.button_mask == 0:
		root.update_hover(target_camera, target_pos, hf_selection)
	elif tool_id == 1 and event is InputEventMouseMotion:
		root.clear_hover()
	elif tool_id != 1:
		root.clear_hover()

	# Mouse button handling
	if event is InputEventMouseButton:
		if tool_id != 1:
			root.set_shift_pressed(event.shift_pressed)
			root.set_alt_pressed(event.alt_pressed)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			return _handle_rmb_cancel(root, tool_id, event)
		if event.button_index == MOUSE_BUTTON_LEFT:
			match tool_id:
				0:
					return _handle_draw_mouse(event, root, target_camera, target_pos)
				1:
					return _handle_select_mouse(event, root, target_camera, target_pos, paint_mode)
				2, 3:
					return _handle_extrude_mouse(event, root, target_camera, target_pos)

	# Mouse motion handling
	if event is InputEventMouseMotion:
		return _handle_mouse_motion(event, root, target_camera, target_pos, tool_id)

	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _should_start_disp_paint(event: InputEvent, root: Node) -> bool:
	if not event is InputEventMouseButton or not event.pressed:
		return false
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not root or not root.displacement_system:
		return false
	if not dock or not dock._disp_section:
		return false
	# Require paint mode to be active — displacement paint reuses the paint toggle.
	if not dock.is_paint_mode_enabled():
		return false
	if not dock._disp_section.is_expanded():
		return false
	# Check if a displaced face is selected.
	var info: Dictionary = dock._get_selected_face_info()
	if info.is_empty():
		return false
	var brush: Node3D = (
		root.find_brush_by_id(info["brush_id"]) if root.has_method("find_brush_by_id") else null
	)
	if not brush:
		return false
	if root.has_method("_is_pick_visible") and not root._is_pick_visible(brush):
		return false
	if (
		brush.get("mesh_instance") is Node3D
		and root.has_method("_is_pick_visible")
		and not root._is_pick_visible(brush.get("mesh_instance"))
	):
		return false
	var fi: int = info["face_index"]
	if fi < 0 or fi >= brush.faces.size():
		return false
	return brush.faces[fi].displacement != null


func _handle_disp_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var info: Dictionary = dock._get_selected_face_info()
				if info.is_empty():
					return EditorPlugin.AFTER_GUI_INPUT_PASS
				# Capture pre-stroke state for undo.
				if root.has_method("capture_state"):
					_disp_paint_pre_state = root.capture_state()
				_disp_paint_active = true
				_disp_paint_brush_id = info["brush_id"]
				_disp_paint_face_idx = info["face_index"]
				_do_disp_paint_stroke(root, cam, pos)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			# Commit the entire stroke as one undo action.
			if _disp_paint_active and not _disp_paint_pre_state.is_empty():
				_commit_disp_paint_undo(root)
			_disp_paint_active = false
			_disp_paint_brush_id = ""
			_disp_paint_face_idx = -1
			_disp_paint_pre_state = {}
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _disp_paint_active:
		_do_disp_paint_stroke(root, cam, pos)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _commit_disp_paint_undo(root: Node) -> void:
	if not undo_redo_manager or _disp_paint_pre_state.is_empty():
		return
	if not root.has_method("restore_state") or not root.has_method("capture_state"):
		return
	var post_state: Dictionary = root.capture_state()
	undo_redo_manager.create_action("Paint Displacement", 0, null, false)
	undo_redo_manager.add_do_method(root, "restore_state", post_state)
	undo_redo_manager.add_undo_method(root, "restore_state", _disp_paint_pre_state)
	undo_redo_manager.commit_action(false)  # false = don't execute do (already applied)
	_record_history("Paint Displacement")


func _do_disp_paint_stroke(root: Node, cam: Camera3D, pos: Vector2) -> void:
	if not root.displacement_system:
		return
	if _disp_paint_brush_id == "" or _disp_paint_face_idx < 0:
		return
	var brush: Node3D = (
		root.find_brush_by_id(_disp_paint_brush_id) if root.has_method("find_brush_by_id") else null
	)
	if not brush:
		return
	if root.has_method("_is_pick_visible") and not root._is_pick_visible(brush):
		return
	if (
		brush.get("mesh_instance") is Node3D
		and root.has_method("_is_pick_visible")
		and not root._is_pick_visible(brush.get("mesh_instance"))
	):
		return
	var faces: Array = brush.faces
	if _disp_paint_face_idx >= faces.size():
		return
	var face = faces[_disp_paint_face_idx]
	if face.local_verts.size() < 3:
		return
	var basis: Basis = brush.global_transform.basis
	var origin: Vector3 = brush.global_transform.origin
	var world_normal: Vector3 = (basis * face.normal).normalized()
	# Build world-space polygon for the face.
	var world_verts := PackedVector3Array()
	for lv in face.local_verts:
		world_verts.append(origin + basis * lv)
	# Raycast: intersect with face plane.
	var from: Vector3 = cam.project_ray_origin(pos)
	var dir: Vector3 = cam.project_ray_normal(pos)
	var denom: float = world_normal.dot(dir)
	if abs(denom) < 0.0001:
		return
	var t: float = world_normal.dot(world_verts[0] - from) / denom
	if t < 0:
		return
	var hit_pos: Vector3 = from + dir * t
	# Reject hits outside the face polygon (with brush-radius margin).
	var radius: float = dock._disp_radius_spin.value if dock and dock._disp_radius_spin else 4.0
	if not _point_near_polygon_3d(hit_pos, world_verts, world_normal, radius):
		return
	var strength: float = (
		dock._disp_strength_spin.value if dock and dock._disp_strength_spin else 0.5
	)
	var mode: int = 0
	if dock and dock._disp_paint_mode_opt:
		mode = dock._disp_paint_mode_opt.get_selected_id()
	root.displacement_system.paint(
		_disp_paint_brush_id, _disp_paint_face_idx, hit_pos, radius, strength, mode
	)


## Check if a point (on the polygon plane) is inside or within margin of a
## convex polygon defined by world_verts with the given outward normal.
func _point_near_polygon_3d(
	point: Vector3, verts: PackedVector3Array, normal: Vector3, margin: float
) -> bool:
	var count: int = verts.size()
	if count < 3:
		return false
	for i in range(count):
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[(i + 1) % count]
		var edge: Vector3 = b - a
		var inward: Vector3 = normal.cross(edge).normalized()
		var dist: float = inward.dot(point - a)
		if dist < -margin:
			return false
	return true


func _handle_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	var paint_target = dock.get_paint_target()
	var op = dock.get_operation()
	var size = dock.get_brush_size()
	if paint_target == 0:
		var paint_tool_id = dock.get_paint_tool_id()
		var paint_radius_cells = dock.get_paint_radius_cells()
		var paint_brush_shape = dock.get_brush_shape()
		var handled = root.handle_paint_input(
			cam, event, pos, op, size, paint_tool_id, paint_radius_cells, paint_brush_shape
		)
		if handled:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	elif paint_target == 1:
		var radius_uv = dock.get_surface_paint_radius()
		var strength = dock.get_surface_paint_strength()
		var layer_idx = dock.get_surface_paint_layer()
		var handled_surface = root.handle_surface_paint_input(
			cam, event, pos, radius_uv, strength, layer_idx
		)
		if handled_surface:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _get_nudge_direction(keycode: int) -> Vector3:
	match keycode:
		KEY_UP:
			return Vector3(0.0, 0.0, -1.0)
		KEY_DOWN:
			return Vector3(0.0, 0.0, 1.0)
		KEY_LEFT:
			return Vector3(-1.0, 0.0, 0.0)
		KEY_RIGHT:
			return Vector3(1.0, 0.0, 0.0)
		KEY_PAGEUP:
			return Vector3(0.0, 1.0, 0.0)
		KEY_PAGEDOWN:
			return Vector3(0.0, -1.0, 0.0)
	return Vector3.ZERO


func _handle_numeric_input(event: InputEventKey, root: Node) -> int:
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var keycode = event.keycode
	# Digit keys (0-9)
	if keycode >= KEY_0 and keycode <= KEY_9:
		numeric_buffer += str(keycode - KEY_0)
		_update_numeric_preview(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Decimal point
	if keycode == KEY_PERIOD and "." not in numeric_buffer:
		numeric_buffer += "."
		_update_numeric_preview(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Backspace: remove last character
	if keycode == KEY_BACKSPACE and numeric_buffer.length() > 0:
		numeric_buffer = numeric_buffer.substr(0, numeric_buffer.length() - 1)
		_update_numeric_preview(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Enter: apply the numeric value
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if numeric_buffer.length() > 0:
			_apply_numeric_value(root)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Tab: apply and move to next dimension (base → height)
	if keycode == KEY_TAB and numeric_buffer.length() > 0:
		_apply_numeric_value(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _update_numeric_preview(root: Node) -> void:
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return
	if numeric_buffer.length() == 0:
		return
	var value = float(numeric_buffer) if numeric_buffer.is_valid_float() else 0.0
	if value <= 0.0:
		return
	if root.input_state.is_drag_height() or root.input_state.is_extruding():
		root.input_state.drag_height = value
		root.update_drag(last_3d_camera, last_3d_mouse_pos)
	elif root.input_state.is_drag_base():
		# Set the base extent from the origin
		var snap = root.grid_snap if root.grid_snap > 0.0 else 1.0
		var extent = Vector3(value, 0.0, value)
		root.input_state.drag_end = root.input_state.drag_origin + extent
		root.update_drag(last_3d_camera, last_3d_mouse_pos)
	_update_hud_context()


func _apply_numeric_value(root: Node) -> void:
	if numeric_buffer.length() == 0:
		return
	var value = float(numeric_buffer) if numeric_buffer.is_valid_float() else 0.0
	numeric_buffer = ""
	if value <= 0.0:
		return
	if root.input_state.is_drag_height():
		root.input_state.drag_height = value
		# Finalize: place the brush
		var size = dock.get_brush_size()
		var info_result = root.end_drag_info(last_3d_camera, last_3d_mouse_pos, size)
		if info_result.get("placed", false):
			_commit_brush_placement(root, info_result.get("info", {}))
		_update_hud_context()
	elif root.input_state.is_drag_base():
		# Apply base size and advance to height
		var extent = Vector3(value, 0.0, value)
		root.input_state.drag_end = root.input_state.drag_origin + extent
		root.input_state.advance_to_height(last_3d_mouse_pos)
		root.update_drag(last_3d_camera, last_3d_mouse_pos)
		_update_hud_context()
	elif root.input_state.is_extruding():
		root.input_state.drag_height = value
		var info = root.end_extrude_info()
		if not info.is_empty():
			_commit_brush_placement(root, info)
		_update_hud_context()


func _cancel_selection_gesture() -> bool:
	var gesture = _ensure_selection_runtime_state()
	var was_active: bool = bool(gesture.is_active())
	gesture.reset()
	_reset_native_selection_session()
	_marquee_overlay_origin = Vector2.ZERO
	_update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	return was_active


## Tool scripts can be hot-reloaded onto the existing EditorPlugin instance.
## Godot does not guarantee that newly-added object initializers have run on
## that instance, so selection ownership repairs itself before every entry
## point rather than failing halfway through a pointer gesture.
func _ensure_selection_runtime_state():
	if _selection_gesture == null:
		_selection_gesture = HFSelectionGestureType.new()
	if _native_selection_before == null:
		_native_selection_before = []
	if _face_mode_saved_object_selection == null:
		_face_mode_saved_object_selection = []
	_ensure_brush_change_tracker()
	return _selection_gesture


func _ensure_brush_change_tracker():
	if _brush_change_tracker == null:
		_brush_change_tracker = HFBrushChangeTrackerType.new()
	return _brush_change_tracker


func _prime_managed_brush_tracker(root: Node = null) -> void:
	var target := root if root else (active_root if active_root else _get_level_root())
	if target:
		_ensure_brush_change_tracker().ensure_root(target)


func _queue_managed_brush_reconcile() -> void:
	if _brush_reconcile_queued:
		return
	_brush_reconcile_queued = true
	call_deferred("_reconcile_managed_brush_changes")


func _reconcile_managed_brush_changes() -> void:
	_brush_reconcile_queued = false
	var root := active_root if active_root else _get_level_root()
	if root:
		_ensure_brush_change_tracker().reconcile(root)
	else:
		_ensure_brush_change_tracker().reset()


func _begin_native_selection_session(selected_nodes: Array, additive: bool, toggle: bool) -> void:
	_ensure_selection_runtime_state()
	_prime_managed_brush_tracker()
	_native_selection_active = true
	_native_selection_before = selected_nodes.duplicate()
	_native_selection_additive = additive
	_native_selection_toggle = toggle


func _reset_native_selection_session() -> void:
	_ensure_selection_runtime_state()
	_native_selection_active = false
	_native_selection_before.clear()
	_native_selection_additive = false
	_native_selection_toggle = false


func _brush_gizmo_action_active() -> bool:
	return (
		brush_gizmo_plugin != null
		and brush_gizmo_plugin.has_method("is_handle_action_active")
		and bool(brush_gizmo_plugin.call("is_handle_action_active"))
	)


func _on_brush_gizmo_action_started(
	_gizmo: Variant = null, _handle_id: int = -1, _secondary: bool = false
) -> void:
	_ensure_selection_runtime_state().claim_native_gizmo()
	_update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	var root := active_root if active_root else _get_level_root()
	if root:
		root.clear_hover()


func _on_brush_gizmo_action_finished(_cancelled: bool = false) -> void:
	_cancel_selection_gesture()


func _prepare_tool_transition(
	root: Node, notify_user: bool = true, settle_custom_gizmo: bool = true
) -> void:
	var cancelled := false
	if (
		settle_custom_gizmo
		and _brush_gizmo_action_active()
		and brush_gizmo_plugin.has_method("cancel_active_handle_action")
	):
		# Restore and freeze locally; keep yielding until Godot delivers the
		# matching commit/cancel callback and releases its private gizmo owner.
		brush_gizmo_plugin.call("cancel_active_handle_action")
		cancelled = true
	if not root or not root.input_state:
		if cancelled and notify_user and dock:
			dock.show_toast("In-progress brush resize closed for tool switch", 1)
		return
	var paint_tool = root.get("paint_tool")
	if _finish_stale_paint_strokes(root, root.input_state, paint_tool):
		cancelled = true
	if _vertex_drag_active and root.vertex_system:
		root.vertex_system.cancel_drag()
		_vertex_drag_active = false
		cancelled = true
	if root.input_state.is_extruding():
		root.cancel_extrude()
		cancelled = true
	elif root.input_state.is_dragging():
		root.cancel_drag()
		cancelled = true
	if _cancel_selection_gesture():
		cancelled = true
	if cancelled:
		numeric_buffer = ""
		if notify_user and dock:
			dock.show_toast("In-progress gesture closed for tool switch", 1)


func _deactivate_external_tool() -> void:
	if _tool_registry and _tool_registry.has_active_external_tool():
		_tool_registry.deactivate_current()


func _activate_external_tool(tool_id: int, root: Node) -> void:
	if not _tool_registry or not root:
		return
	_close_face_select_mode("Face Select closed for tool change")
	_prepare_tool_transition(root)
	if _vertex_mode:
		_toggle_vertex_mode(root)
	if dock and dock.paint_mode and dock.paint_mode.button_pressed:
		dock.paint_mode.set_pressed_no_signal(false)
		dock.highlight_tab("Brush")
	_tool_registry.activate_tool(tool_id, root, last_3d_camera, undo_redo_manager, _record_history)


func _on_builtin_tool_changed() -> void:
	_close_face_select_mode("Face Select closed for tool change")
	var root = active_root if active_root else _get_level_root()
	_prepare_tool_transition(root)
	_deactivate_external_tool()
	if _vertex_mode:
		_toggle_vertex_mode(root)
	# Show coach marks for extrude tools on first use
	if dock:
		var tool_id: int = dock.get_tool()
		if tool_id == 2 or tool_id == 3:
			_show_coach_mark_for_action("tool_extrude_up")
	_update_hud_context()


func _on_vertex_mode_toggled(enabled: bool) -> void:
	var root = active_root if active_root else _get_level_root()
	if enabled and not _vertex_mode:
		_toggle_vertex_mode(root)
	elif not enabled and _vertex_mode:
		_toggle_vertex_mode(root)


func _on_face_select_mode_toggled(enabled: bool) -> void:
	_ensure_selection_runtime_state()
	var root := active_root if active_root else _get_level_root()
	_prepare_tool_transition(root)
	var selection := get_editor_interface().get_selection()
	if enabled:
		# Establish one unambiguous pointer owner before hiding object selection.
		# Keep the Paint tab visible, but turn painting itself off; Face Select is
		# an editing mode, not a paint stroke layered over Select.
		_deactivate_external_tool()
		if _vertex_mode:
			_toggle_vertex_mode(root)
		_texture_picker_active = false
		if _radial_menu and _radial_menu.is_active():
			_radial_menu.hide_menu()
		if dock:
			if dock.tool_select:
				dock.tool_select.set_pressed_no_signal(true)
			if dock.paint_mode:
				dock.paint_mode.set_pressed_no_signal(false)
		_face_mode_saved_object_selection.clear()
		for node in _current_selection_nodes():
			if is_instance_valid(node) and node is Node:
				_face_mode_saved_object_selection.append(node)
		# Face editing is intentionally modal. Hiding object gizmos removes the
		# otherwise-opaque zero-motion overlap between a face and transform handle.
		hf_selection.clear()
		if selection:
			_apply_hf_selection(selection)
		if dock:
			dock.show_toast("Face Select: object transform handles hidden", 0)
		return
	if root and root.has_method("clear_face_selection"):
		root.clear_face_selection()
	if selection:
		hf_selection.clear()
		for node in _face_mode_saved_object_selection:
			if is_instance_valid(node) and node is Node:
				hf_selection.append(node)
		_apply_hf_selection(selection)
	_face_mode_saved_object_selection.clear()


func _close_face_select_mode(message: String = "") -> bool:
	if not dock or not dock.is_face_select_mode_enabled() or not dock.face_select_mode:
		return false
	# Use the real toggle signal so face selection is cleared and the saved
	# object selection is restored through the same path as a manual exit.
	dock.face_select_mode.button_pressed = false
	if message != "":
		dock.show_toast(message, 0)
	return true


func _on_dock_selection_clear() -> void:
	hf_selection.clear()


func _on_dock_grid_snap_applied(value: float) -> void:
	if hud and hud.has_method("update_grid_snap"):
		hud.update_grid_snap(value)


## Vertex editing is entered from Select, but its move operation still needs the
## same X/Y/Z constraints as the construction tools.
static func axis_lock_shortcuts_available(tool_id: int, vertex_mode: bool) -> bool:
	return tool_id != 1 or vertex_mode


## The palette currently derives axis availability from its tool context. Use a
## distinct modal context for vertex editing without misreporting Select to the
## context toolbar or changing the user's selected tool.
static func hotkey_palette_tool_context(tool_id: int, vertex_mode: bool) -> int:
	return -1 if tool_id == 1 and vertex_mode else tool_id


static func is_canceled_vertex_drag_release(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	return (
		mouse_event.button_index == MOUSE_BUTTON_LEFT
		and not mouse_event.pressed
		and mouse_event.canceled
	)


func _handle_keyboard_input(
	event: InputEventKey, root: Node, tool_id: int, paint_mode: bool
) -> int:
	# Numeric input during drag/extrude
	if root.input_state.is_dragging() or root.input_state.is_extruding():
		var nr = _handle_numeric_input(event, root)
		if nr != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return nr

	# Hotkey palette toggle (? = Shift+/ or F1 or Ctrl+K)
	if _hotkey_palette:
		if _hotkey_palette.visible and event.keycode == KEY_ESCAPE:
			_hotkey_palette.visible = false
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if (event.keycode == KEY_SLASH and event.shift_pressed) or event.keycode == KEY_F1:
			_on_toggle_hotkey_palette()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_K and event.ctrl_pressed:
			_on_toggle_hotkey_palette()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event.keycode == KEY_ESCAPE:
		return (
			EditorPlugin.AFTER_GUI_INPUT_STOP
			if _cancel_escape_step(root)
			else EditorPlugin.AFTER_GUI_INPUT_PASS
		)
	# High-level workflow shortcuts stay together so they remain predictable
	# regardless of the currently active draw/select/paint tool.
	if _keymap.matches("toggle_operation", event):
		_on_context_toggle_operation()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("toggle_paint_mode", event):
		_toggle_paint_mode()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("quick_play", event):
		if dock:
			dock._on_quick_play()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("validate_level", event):
		if dock:
			dock._on_validate_level()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Operation replay toggle (Ctrl+Shift+T)
	if event.keycode == KEY_T and event.ctrl_pressed and event.shift_pressed:
		if _operation_replay and is_instance_valid(_operation_replay):
			_operation_replay.toggle_visible()
		else:
			_toast_power_user_overlay_hint()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# External tool keyboard dispatch first — external tools can override keys
	if _tool_registry and _tool_registry.has_active_external_tool():
		var ext_result = _tool_registry.dispatch_keyboard(event)
		if ext_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return ext_result

	# Viewport context menu — only when idle (no active operation, no active external tool)
	if _keymap.matches("context_menu", event):
		var has_active_ext := _tool_registry and _tool_registry.has_active_external_tool()
		if root.input_state.is_idle() and not has_active_ext:
			_show_viewport_context_menu(root, tool_id)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Radial menu toggle — same idle guard
	if _keymap.matches("radial_menu", event):
		if _radial_menu and is_instance_valid(_radial_menu):
			if _radial_menu.is_active():
				_radial_menu.hide_menu()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			var has_active_ext := _tool_registry and _tool_registry.has_active_external_tool()
			if root.input_state.is_idle() and not has_active_ext:
				_radial_menu.show_at(_get_current_overlay_mouse_pos())
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		else:
			_toast_power_user_overlay_hint()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Double-tap detection for quick property popups (G G, B B, R R)
	# Must come before keymap matches so the second tap is intercepted.
	var tap_now := Time.get_ticks_msec()
	if not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
		if event.keycode == _last_tap_keycode and (tap_now - _last_tap_time) < _DOUBLE_TAP_MS:
			var handled := _handle_double_tap(event.keycode, root, paint_mode)
			if handled:
				_last_tap_keycode = 0
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		_last_tap_keycode = event.keycode
		_last_tap_time = tap_now

	if _keymap.matches("delete", event):
		var delete_guard := _guard_hammerforge_shortcut(root, false, 1, "Delete")
		if delete_guard != HF_SHORTCUT_APPLY:
			return delete_guard
		_delete_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("duplicate", event):
		var duplicate_guard := _guard_hammerforge_shortcut(root, false, 1, "Duplicate")
		if duplicate_guard != HF_SHORTCUT_APPLY:
			return duplicate_guard
		_duplicate_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("group", event):
		var group_guard := _guard_hammerforge_shortcut(root, false, 2, "Group")
		if group_guard != HF_SHORTCUT_APPLY:
			return group_guard
		_group_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("ungroup", event):
		var ungroup_guard := _guard_hammerforge_shortcut(root, false, 1, "Ungroup")
		if ungroup_guard != HF_SHORTCUT_APPLY:
			return ungroup_guard
		_ungroup_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("hollow", event):
		var hollow_guard := _guard_hammerforge_shortcut(root, true, 1, "Hollow")
		if hollow_guard != HF_SHORTCUT_APPLY:
			return hollow_guard
		_hollow_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("move_to_floor", event):
		var floor_guard := _guard_hammerforge_shortcut(root, true, 1, "Move to Floor")
		if floor_guard != HF_SHORTCUT_APPLY:
			return floor_guard
		_move_selected_to_floor(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("move_to_ceiling", event):
		var ceiling_guard := _guard_hammerforge_shortcut(root, true, 1, "Move to Ceiling")
		if ceiling_guard != HF_SHORTCUT_APPLY:
			return ceiling_guard
		_move_selected_to_ceiling(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("clip", event):
		var clip_guard := _guard_hammerforge_shortcut(root, true, 1, "Clip")
		if clip_guard != HF_SHORTCUT_APPLY:
			return clip_guard
		_clip_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("carve", event):
		var carve_guard := _guard_hammerforge_shortcut(root, true, 1, "Carve")
		if carve_guard != HF_SHORTCUT_APPLY:
			return carve_guard
		_carve_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("merge", event):
		var merge_guard := _guard_hammerforge_shortcut(root, true, 2, "Merge")
		if merge_guard != HF_SHORTCUT_APPLY:
			return merge_guard
		_merge_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Nudge keys
	var nudge = _get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO and not event.ctrl_pressed and not event.alt_pressed:
		var nudge_guard := _guard_hammerforge_shortcut(root, false, 1, "Nudge")
		if nudge_guard != HF_SHORTCUT_APPLY:
			return nudge_guard
		_nudge_selected(root, nudge)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Grid snap size shortcuts ([ = halve, ] = double)
	if _keymap.matches("grid_decrease", event):
		_adjust_grid_snap(root, 0.5)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("grid_increase", event):
		_adjust_grid_snap(root, 2.0)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Tool switch shortcuts
	if _keymap.matches("tool_draw", event):
		_prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		_deactivate_external_tool()
		if dock.tool_draw:
			dock.tool_draw.button_pressed = true
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("tool_select", event):
		_prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		_deactivate_external_tool()
		if dock.tool_select:
			dock.tool_select.button_pressed = true
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("tool_extrude_up", event):
		_prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		_deactivate_external_tool()
		dock.set_extrude_tool(1)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("tool_extrude_down", event):
		_prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		_deactivate_external_tool()
		dock.set_extrude_tool(-1)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# E / Shift+E for extrude (Blender convention) — skip in paint and vertex modes
	if not paint_mode and not _vertex_mode:
		if _keymap.matches("tool_extrude", event):
			_prepare_tool_transition(root)
			dock.highlight_tab("Brush")
			_deactivate_external_tool()
			dock.set_extrude_tool(1)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _keymap.matches("tool_extrude_down_alt", event):
			_prepare_tool_transition(root)
			dock.highlight_tab("Brush")
			_deactivate_external_tool()
			dock.set_extrude_tool(-1)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Texture picker (eyedropper) — T key activates click-to-sample mode
	if _keymap.matches("texture_picker", event):
		_texture_picker_active = true
		if dock:
			dock.show_toast("Texture Picker: click a face to sample its material", 0)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Apply Last Texture — Shift+T reapplies the last picked material
	if _keymap.matches("apply_last_texture", event):
		var has_selected_faces: bool = (
			root.face_selection is Dictionary and not root.face_selection.is_empty()
		)
		if not has_selected_faces:
			var texture_guard := _guard_hammerforge_shortcut(root, true, 1, "Apply Texture")
			if texture_guard != HF_SHORTCUT_APPLY:
				return texture_guard
		_apply_last_texture(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Select Similar — Shift+S selects matching faces/brushes
	if _keymap.matches("select_similar", event):
		var has_similar_face_source: bool = (
			root.face_selection is Dictionary and not root.face_selection.is_empty()
		)
		if not has_similar_face_source:
			var similar_guard := _guard_hammerforge_shortcut(root, true, 1, "Select Similar")
			if similar_guard != HF_SHORTCUT_APPLY:
				return similar_guard
		_select_similar(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Selection Filter popup — Shift+F opens the filter popover
	if _keymap.matches("selection_filter", event):
		var filter_scope := classify_selection_scope(_current_selection_nodes(), root)
		if filter_scope == SelectionScope.NATIVE_ONLY:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if filter_scope == SelectionScope.MIXED:
			if dock:
				dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_show_selection_filter()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Select All / Deselect All — A / Shift+A (Blender convention)
	if _keymap.matches("select_all", event):
		_select_all_nodes(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("deselect_all", event):
		_deselect_all_nodes(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Quick Save as Prefab — Ctrl+Shift+P
	if event.keycode == KEY_P and event.ctrl_pressed and event.shift_pressed:
		var save_prefab_guard := _guard_hammerforge_shortcut(root, false, 1, "Save Prefab")
		if save_prefab_guard != HF_SHORTCUT_APPLY:
			return save_prefab_guard
		_quick_save_prefab(root, false)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Cycle Prefab Variant — Ctrl+Shift+V
	if event.keycode == KEY_V and event.ctrl_pressed and event.shift_pressed:
		var variant_guard := _guard_hammerforge_shortcut(root, false, 1, "Cycle Variant")
		if variant_guard != HF_SHORTCUT_APPLY:
			return variant_guard
		_cycle_prefab_variant(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Paint tool shortcuts
	if paint_mode:
		var paint_key := -1
		if _keymap.matches("paint_bucket", event):
			paint_key = 0
		elif _keymap.matches("paint_erase", event):
			paint_key = 1
		elif _keymap.matches("paint_ramp", event):
			paint_key = 2
		elif _keymap.matches("paint_line", event):
			paint_key = 3
		elif _keymap.matches("paint_fill", event):
			paint_key = 4
		elif _keymap.matches("paint_blend", event):
			paint_key = 5
		if paint_key >= 0:
			dock.set_paint_tool(paint_key)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Axis lock for construction tools and Select's vertex-edit operation.
	if axis_lock_shortcuts_available(tool_id, _vertex_mode):
		if _keymap.matches("axis_x", event):
			root.set_axis_lock(LevelRootType.AxisLock.X, true)
			_update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _keymap.matches("axis_y", event):
			root.set_axis_lock(LevelRootType.AxisLock.Y, true)
			_update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if _keymap.matches("axis_z", event):
			root.set_axis_lock(LevelRootType.AxisLock.Z, true)
			_update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Vertex edit toggle (V key)
	if _keymap.matches("vertex_edit", event):
		var vertex_guard := _guard_hammerforge_shortcut(root, true, 1, "Vertex Edit")
		if vertex_guard != HF_SHORTCUT_APPLY:
			return vertex_guard
		_toggle_vertex_mode(root)
		_show_coach_mark_for_action("vertex_edit")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# External tool shortcuts
	if _tool_registry:
		var ext_id = _tool_registry.check_shortcut(event.keycode)
		if ext_id >= 0 and active_root:
			_activate_external_tool(ext_id, active_root)
			_show_coach_mark_for_tool_id(ext_id)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## RMB belongs to Godot camera navigation unless HammerForge currently owns a
## transient gesture.  Persistent modes such as vertex editing are not enough.
static func has_cancelable_rmb_gesture(input_state: Variant, marquee_active: bool) -> bool:
	if marquee_active:
		return true
	return input_state != null and (input_state.is_dragging() or input_state.is_extruding())


func _finish_stale_paint_strokes(root: Node, input_state: Variant, paint_tool: Variant) -> bool:
	var finished := false
	if (
		paint_tool != null
		and paint_tool.has_method("is_stroke_active")
		and paint_tool.is_stroke_active()
		and paint_tool.has_method("finish_stroke_if_active")
	):
		paint_tool.finish_stroke_if_active()
		finished = true
	if input_state != null and input_state.is_surface_painting():
		input_state.end_surface_paint()
		finished = true
	if _disp_paint_active:
		if not _disp_paint_pre_state.is_empty():
			_commit_disp_paint_undo(root)
		_disp_paint_active = false
		_disp_paint_brush_id = ""
		_disp_paint_face_idx = -1
		_disp_paint_pre_state = {}
		finished = true
	return finished


func _recover_stale_lmb_gestures(root: Node) -> void:
	if not root:
		return
	var recovered := false
	var input_state = root.input_state if root.get("input_state") != null else null
	var paint_tool = root.get("paint_tool")
	if _tool_registry and _tool_registry.recover_active_pointer_capture():
		recovered = true
	if _finish_stale_paint_strokes(root, input_state, paint_tool):
		recovered = true
	if _vertex_drag_active and root.vertex_system:
		root.vertex_system.cancel_drag()
		_vertex_drag_active = false
		recovered = true
	if input_state:
		if input_state.is_extruding():
			root.cancel_extrude()
			recovered = true
		elif input_state.is_drag_base():
			root.cancel_drag()
			recovered = true
	if recovered:
		numeric_buffer = ""
		root.clear_hover()
		if root.has_method("clear_face_hover_highlight"):
			root.clear_face_hover_highlight()
		_update_hud_context()


func _handle_rmb_cancel(root: Node, _tool_id: int, event: InputEventMouseButton) -> int:
	var input_state = root.input_state if root else null
	var has_marquee := _selection_gesture != null and _selection_gesture.is_active()
	var paint_tool = root.get("paint_tool") if root else null
	var surface_painting: bool = input_state != null and input_state.is_surface_painting()
	var floor_painting: bool = (
		paint_tool != null
		and paint_tool.has_method("is_stroke_active")
		and paint_tool.is_stroke_active()
	)
	var any_painting := surface_painting or floor_painting or _disp_paint_active
	if should_block_rmb_during_paint_stroke(
		surface_painting,
		floor_painting,
		_disp_paint_active,
		event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0,
	):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if any_painting:
		# If Godot lost the LMB release during a focus/viewport transition,
		# finalize that stale stroke instead of blocking every future RMB press.
		_finish_stale_paint_strokes(root, input_state, paint_tool)
	if not has_cancelable_rmb_gesture(input_state, has_marquee):
		# Idle RMB belongs to Godot's native camera controls.
		if root:
			root.clear_hover()
			if root.has_method("clear_face_hover_highlight"):
				root.clear_face_hover_highlight()
		_rmb_camera_navigation.begin()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if input_state and input_state.is_extruding():
		root.cancel_extrude()
	elif input_state and input_state.is_dragging():
		root.cancel_drag()
	numeric_buffer = ""
	_cancel_selection_gesture()
	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## Show the viewport context menu at the current mouse position.
## Triggered by Space key (no modifiers). Converts screen coords to window-local
## for PopupMenu.popup() — the only reliable coordinate source since the 3D
## SubViewport's event.position space doesn't match window space.
func _show_viewport_context_menu(root: Node, tool_id: int) -> void:
	if not _viewport_context_menu or not is_instance_valid(_viewport_context_menu):
		return
	var state := {}
	_build_viewport_state(state, root, tool_id)
	var screen_pos := DisplayServer.mouse_get_position()
	var win := get_window()
	var window_pos := Vector2(screen_pos)
	if win:
		window_pos = Vector2(screen_pos - win.position)
	_viewport_context_menu.show_at(window_pos, state)


func _get_current_overlay_mouse_pos() -> Vector2:
	return last_3d_mouse_pos


func _build_viewport_state(state: Dictionary, root: Node, tool_id: int) -> void:
	state["has_root"] = root != null
	state["tool"] = tool_id
	state["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	state["vertex_mode"] = _vertex_mode
	state["is_subtract"] = dock.get_operation() != 0 if dock else false
	var input_mode := 0
	if root and root.input_state:
		input_mode = root.input_state.mode
	state["input_mode"] = input_mode
	var selection_nodes := _current_selection_nodes()
	state["mixed_selection"] = (
		classify_selection_scope(selection_nodes, root) == SelectionScope.MIXED if root else false
	)
	var brush_count := 0
	var entity_count := 0
	for node in selection_nodes:
		if node is DraftBrush:
			brush_count += 1
		elif root and root.has_method("is_entity_node") and root.is_entity_node(node):
			entity_count += 1
	state["brush_count"] = brush_count
	state["entity_count"] = entity_count
	var face_count := 0
	if root and root.get("face_selection") is Dictionary:
		for key in root.face_selection.keys():
			var indices = root.face_selection.get(key, [])
			face_count += indices.size()
	state["face_count"] = face_count


func _handle_select_mouse(
	event: InputEventMouseButton,
	root: Node,
	cam: Camera3D,
	pos: Vector2,
	paint_mode: bool,
) -> int:
	if not event.pressed:
		# Releases for owned Select gestures are routed before all other tools.
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var face_select := dock.is_face_select_mode_enabled()
	# Alt+LMB belongs to Godot's alternate navigation/transform schemes.
	if event.alt_pressed or Input.is_key_pressed(KEY_ALT):
		_cancel_selection_gesture()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var active_mat = dock.get_active_material()
	if not face_select and paint_mode and active_mat:
		var painted = root.pick_brush(cam, pos, false)
		if painted:
			_paint_brush_with_undo(root, painted, active_mat)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	var shift_selection := event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
	# Object Select is deliberately native: Shift keeps Godot's own additive /
	# active-selection semantics, while Ctrl/Cmd remain available to the editor's
	# configured transform and navigation behavior. Face Select is HammerForge's
	# custom domain, so Ctrl/Cmd can safely mean toggle there.
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
	var selection_at_press := _current_selection_nodes()
	var native_selection_present := _selection_contains_native_node(selection_at_press, root)

	# Godot already owns exact hit-testing for its transform gizmo, every
	# built-in property gizmo, and object-region selection. Filled brush gizmo
	# triangles make every Object Select press native too, eliminating ambiguous
	# overlaps between a brush surface, marquee origin, and opaque editor widget.
	# Face Select remains custom only while the visible selection is HF-owned.
	var pass_to_native := not face_select or native_selection_present
	if pass_to_native:
		_begin_native_selection_session(selection_at_press, additive, toggle)
		_selection_gesture.begin(
			pos, additive, toggle, face_select, false, false, true, selection_at_press, true
		)
		root.clear_hover()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Face Select retains HammerForge's visible-face click/marquee behavior while
	# CUSTOM forwarding keeps transform and custom gizmos in Godot's pipeline.
	var allow_marquee := face_select
	var allow_click := true
	var may_be_native_gizmo := face_select and not selection_at_press.is_empty()
	_marquee_overlay_origin = pos
	_selection_gesture.begin(
		pos,
		additive,
		toggle,
		face_select,
		allow_marquee,
		allow_click,
		false,
		selection_at_press,
		may_be_native_gizmo
	)
	root.clear_hover()
	# CUSTOM suppresses Godot's competing node/region selection but still lets
	# its custom and transform gizmos inspect face-selection presses.
	return EditorPlugin.AFTER_GUI_INPUT_CUSTOM


## CUSTOM lets Godot finish transform/property/custom gizmos while suppressing
## only its competing node selection. Object selection is fully native.
static func custom_selection_release_result(face_selection: bool) -> int:
	return (
		EditorPlugin.AFTER_GUI_INPUT_CUSTOM if face_selection else EditorPlugin.AFTER_GUI_INPUT_PASS
	)


func _selection_contains_native_node(nodes: Array, root: Node) -> bool:
	for candidate in nodes:
		if not is_instance_valid(candidate) or not (candidate is Node):
			continue
		var owner := _hammerforge_selection_owner(candidate as Node, root)
		if owner is DraftBrush or owner is DraftEntityType:
			continue
		if root and root.has_method("is_entity_node") and root.is_entity_node(owner):
			continue
		return true
	return false


func _handle_active_selection_input(
	event: InputEvent, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	if not _selection_gesture or not _selection_gesture.is_active():
		return SELECT_INPUT_CONTINUE
	# A native transform/property gizmo owns the complete interaction, not just
	# mouse motion. Let Godot see every key while that ownership is active or
	# still opaque; otherwise Delete/Nudge/tool shortcuts can mutate the object
	# underneath its unfinished drag. Escape also clears only our bookkeeping so
	# Godot can perform the authoritative cancel.
	if event is InputEventKey and _selection_gesture.should_yield_cancel_to_native():
		if event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_selection_gesture()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var decision := _selection_gesture.update_motion(
			pos, motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0, SELECT_DRAG_THRESHOLD
		)
		match decision:
			HFSelectionGestureType.MotionDecision.RECOVERED:
				_cancel_selection_gesture()
				_queue_managed_brush_reconcile()
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			HFSelectionGestureType.MotionDecision.NATIVE_GIZMO:
				_update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			HFSelectionGestureType.MotionDecision.DRAW_MARQUEE:
				root.clear_hover()
				_update_marquee_overlay(_marquee_overlay_origin, pos, true)
				return EditorPlugin.AFTER_GUI_INPUT_CUSTOM
			_:
				root.clear_hover()
				return (
					EditorPlugin.AFTER_GUI_INPUT_PASS
					if _selection_gesture.native_passthrough
					else EditorPlugin.AFTER_GUI_INPUT_CUSTOM
				)
	if not (event is InputEventMouseButton):
		return SELECT_INPUT_CONTINUE
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		var yield_cancel := _selection_gesture.should_yield_cancel_to_native()
		_cancel_selection_gesture()
		return (
			EditorPlugin.AFTER_GUI_INPUT_PASS if yield_cancel else EditorPlugin.AFTER_GUI_INPUT_STOP
		)
	if button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
		return SELECT_INPUT_CONTINUE
	if button.canceled:
		var yield_cancel := _selection_gesture.should_yield_cancel_to_native()
		_cancel_selection_gesture()
		return (
			EditorPlugin.AFTER_GUI_INPUT_PASS if yield_cancel else EditorPlugin.AFTER_GUI_INPUT_STOP
		)
	var native_session := _native_selection_active
	var native_before := _native_selection_before.duplicate()
	var native_additive := _native_selection_additive
	var native_toggle := _native_selection_toggle
	var result := _selection_gesture.finish(pos, SELECT_DRAG_THRESHOLD)
	_reset_native_selection_session()
	_update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
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
			_queue_managed_brush_reconcile()
			call_deferred(
				"_finalize_native_selection", native_before, native_additive, native_toggle
			)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	match release_decision:
		HFSelectionGestureType.ReleaseDecision.MARQUEE:
			if not bool(result.get("face_select", false)):
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_select_faces_in_rect(
				root,
				cam,
				result.get("origin", pos),
				pos,
				bool(result.get("additive", false)),
				bool(result.get("toggle", false))
			)
			# CUSTOM keeps native gizmo release/commit handling alive while
			# still blocking Godot's competing node-region selection.
			return custom_selection_release_result(true)
		HFSelectionGestureType.ReleaseDecision.CLICK:
			if not bool(result.get("face_select", false)):
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			root.select_face_at_screen(
				cam,
				result.get("origin", pos),
				bool(result.get("additive", false)),
				bool(result.get("toggle", false))
			)
			return custom_selection_release_result(true)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_extrude_mouse(
	event: InputEventMouseButton, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	if event.pressed:
		numeric_buffer = ""
		var extrude_dir = dock.get_extrude_direction()
		var started = root.begin_extrude(cam, pos, extrude_dir)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var info = root.end_extrude_info()
	if not info.is_empty():
		_commit_brush_placement(root, info)
	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _handle_draw_mouse(
	event: InputEventMouseButton, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	var op = dock.get_operation()
	var size = dock.get_brush_size()
	var shape = dock.get_shape()
	var sides = dock.get_sides()
	if event.pressed:
		# DRAG_HEIGHT follows buttonless motion. This next click confirms it;
		# do not restart the base gesture on the confirmation press.
		if root.input_state.is_drag_height():
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		numeric_buffer = ""
		var started = root.begin_drag(cam, pos, op, size, shape, sides)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
	var result = root.end_drag_info(cam, pos, size)
	if result.get("handled", false):
		if result.get("placed", false):
			_commit_brush_placement(root, result.get("info", {}))
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_mouse_motion(
	event: InputEventMouseMotion,
	root: Node,
	cam: Camera3D,
	pos: Vector2,
	tool_id: int,
) -> int:
	if tool_id != 1:
		root.set_shift_pressed(event.shift_pressed)
		root.set_alt_pressed(event.alt_pressed)
	if (tool_id == 2 or tool_id == 3) and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		root.update_extrude(cam, pos)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if (
		tool_id == 0
		and (
			root.input_state.is_drag_height()
			or (root.input_state.is_drag_base() and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0)
		)
	):
		root.update_drag(cam, pos)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Face hover highlight for extrude tools (when idle, not dragging)
	if (tool_id == 2 or tool_id == 3) and event.button_mask == 0:
		var hover_color = Color(0.2, 0.8, 0.3, 0.35) if tool_id == 2 else Color(0.8, 0.2, 0.2, 0.35)
		if root.has_method("highlight_hovered_face"):
			root.highlight_hovered_face(cam, pos, hover_color)
	elif root.has_method("clear_face_hover_highlight"):
		root.clear_face_hover_highlight()

	# Prefab ghost overlay on hover
	if root.prefab_overlay and event.button_mask == 0 and cam:
		_update_prefab_hover_overlay(root, cam, pos)

	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _update_prefab_hover_overlay(root, cam: Camera3D, pos: Vector2) -> void:
	var from: Vector3 = cam.project_ray_origin(pos)
	var dir: Vector3 = cam.project_ray_normal(pos)
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	if not space:
		root.prefab_overlay.hide_overlay()
		return
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * 1000.0
	)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		root.prefab_overlay.hide_overlay()
		return
	var collider = hit.get("collider")
	if not collider or not (collider is Node3D):
		root.prefab_overlay.hide_overlay()
		return
	# Walk up to find a node with prefab instance meta
	var node: Node = collider
	var iid := ""
	while node and node != root:
		iid = str(node.get_meta("hf_prefab_instance", ""))
		if iid != "":
			break
		node = node.get_parent()
	if iid != "":
		root.prefab_overlay.show_instance_overlay(iid)
	else:
		root.prefab_overlay.hide_overlay()


# ---------------------------------------------------------------------------
# Vertex editing mode
# ---------------------------------------------------------------------------


func _toggle_vertex_mode(root: Node) -> void:
	var enabling := not _vertex_mode
	if enabling:
		_close_face_select_mode("Face Select closed for vertex editing")
	_prepare_tool_transition(root)
	if enabling and dock and dock.paint_mode and dock.paint_mode.button_pressed:
		dock.highlight_tab("Brush")
	_vertex_mode = enabling
	if _vertex_mode:
		_deactivate_external_tool()
		if root and root.vertex_system:
			root.vertex_system.clear_selection()
			# Pass current brush selection
			var brushes: Array = []
			for node in hf_selection:
				if node is DraftBrush:
					brushes.append(node)
			root.vertex_system.set_selection(brushes)
			root.input_state.begin_vertex_edit()
	else:
		if root and root.vertex_system:
			if _vertex_drag_active:
				root.vertex_system.cancel_drag()
				_vertex_drag_active = false
			root.vertex_system.clear_selection()
			root.input_state.end_vertex_edit()
		_clear_vertex_overlay()
	if dock:
		dock.set_vertex_mode(_vertex_mode)
	_update_hud_context()


func _vertex_merge_selected(root: Node) -> void:
	var vs = root.vertex_system
	if not vs:
		return
	for brush_id in vs.selected_vertices:
		var indices: PackedInt32Array = vs.selected_vertices[brush_id]
		if indices.size() >= 2:
			vs.merge_vertices(brush_id, indices)


func _vertex_split_selected_edge(root: Node) -> void:
	var vs = root.vertex_system
	if not vs:
		return
	var sel: Array = vs.get_single_selected_edge()
	if sel.size() == 2:
		vs.split_edge(sel[0], sel[1])


func _vertex_clip_to_convex(root: Node) -> void:
	var vs = root.vertex_system
	if not vs:
		return
	var clipped := false
	for brush_id in vs.selected_vertices:
		if vs.clip_to_convex(brush_id):
			clipped = true
	if clipped:
		root.emit_signal("user_message", "Clipped to convex hull", 0)
	else:
		root.emit_signal("user_message", "Brush is already convex", 0)


func _handle_vertex_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	var vs = root.vertex_system
	if not vs:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		# Escape exits vertex mode
		if event.keycode == KEY_ESCAPE:
			if _vertex_drag_active:
				_vertex_drag_active = false
				vs.cancel_drag()
				_update_vertex_overlay(root, cam)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if vs.has_selection():
				vs.clear_selection()
				_update_vertex_overlay(root, cam)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_toggle_vertex_mode(root)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# E toggles edge sub-mode (without modifiers)
		if _keymap and _keymap.matches("vertex_edge_mode", event):
			if vs.sub_mode == vs.VertexSubMode.VERTEX:
				vs.sub_mode = vs.VertexSubMode.EDGE
				vs.clear_selection()
			else:
				vs.sub_mode = vs.VertexSubMode.VERTEX
				vs.clear_selection()
			_update_vertex_overlay(root, cam)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# Ctrl+W: merge vertices
		if _keymap and _keymap.matches("vertex_merge", event):
			if vs.get_selection_count() >= 2:
				# Merge in first brush that has selected verts
				for brush_id in vs.selected_vertices:
					var indices: PackedInt32Array = vs.selected_vertices[brush_id]
					if indices.size() >= 2:
						var ok: bool = vs.merge_vertices(brush_id, indices)
						if ok and undo_redo_manager:
							var snapshots: Dictionary = vs.get_pre_op_snapshots()
							if not snapshots.is_empty():
								_commit_vertex_op(root, snapshots, "Merge Vertices")
						vs.clear_selection()
						break
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# Ctrl+E: split edge
		if _keymap and _keymap.matches("vertex_split_edge", event):
			var single: Array = vs.get_single_selected_edge()
			if single.size() == 2:
				var ok: bool = vs.split_edge(single[0], single[1])
				if ok and undo_redo_manager:
					var snapshots: Dictionary = vs.get_pre_op_snapshots()
					if not snapshots.is_empty():
						_commit_vertex_op(root, snapshots, "Split Edge")
				vs.clear_selection()
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Mouse click — select or begin drag
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if vs.sub_mode == vs.VertexSubMode.EDGE:
				# Edge sub-mode: pick edges
				var pick: Dictionary = vs.pick_edge(cam, pos)
				if pick.is_empty():
					if not event.shift_pressed:
						vs.clear_selection()
					_update_vertex_overlay(root, cam)
					return EditorPlugin.AFTER_GUI_INPUT_PASS
				vs.select_edge(pick.brush_id, pick.edge, event.shift_pressed)
				# Begin drag using edge midpoint
				_vertex_drag_active = true
				_vertex_drag_start = pos
				vs.begin_drag(pick.world_midpoint)
				_update_vertex_overlay(root, cam)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			# Vertex sub-mode: pick vertices
			var pick = vs.pick_vertex(cam, pos)
			if pick.is_empty():
				if not event.shift_pressed:
					vs.clear_selection()
				_update_vertex_overlay(root, cam)
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			vs.select_vertex(pick.brush_id, pick.vertex_index, event.shift_pressed)
			# Begin drag
			_vertex_drag_active = true
			_vertex_drag_start = pos
			vs.begin_drag(pick.world_pos)
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# A canceled release means the OS/editor broke pointer capture. Restore the
		# pre-drag geometry instead of recording a partial move.
		if is_canceled_vertex_drag_release(event) and _vertex_drag_active:
			_vertex_drag_active = false
			vs.cancel_drag()
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		# Mouse release — end drag
		if _vertex_drag_active:
			_vertex_drag_active = false
			var snapshots = vs.end_drag()
			if not snapshots.is_empty() and undo_redo_manager:
				_commit_vertex_move(root, snapshots)
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Right click cancels drag
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and _vertex_drag_active
	):
		_vertex_drag_active = false
		vs.cancel_drag()
		_update_vertex_overlay(root, cam)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Mouse motion — update drag or hover
	if event is InputEventMouseMotion:
		if _vertex_drag_active and vs.is_dragging():
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				_vertex_drag_active = false
				vs.cancel_drag()
				_update_vertex_overlay(root, cam)
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			var projection: Dictionary = vs.project_drag_screen_delta(
				cam, _vertex_drag_start, pos, root.input_state.axis_lock
			)
			if bool(projection.get("valid", false)):
				var delta: Vector3 = projection.get("delta", Vector3.ZERO)
				if root.grid_snap > 0.0:
					delta = delta.snapped(Vector3.ONE * root.grid_snap)
				# Absolute updates include Vector3.ZERO so returning to the origin
				# or the same snap cell cannot leave a stale prior movement applied.
				vs.update_drag_absolute(delta)
			else:
				vs.update_drag_absolute(Vector3.ZERO)
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if vs.sub_mode == vs.VertexSubMode.EDGE:
			vs.update_edge_hover(cam, pos)
		else:
			vs.update_hover(cam, pos)
		_update_vertex_overlay(root, cam)

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _commit_vertex_op(root: Node, pre_op_snapshots: Dictionary, action_name: String) -> void:
	if not undo_redo_manager:
		return
	var post_state: Dictionary = {}
	for brush_id in pre_op_snapshots:
		var brush = root.brush_system.find_brush_by_id(brush_id) if root.brush_system else null
		if brush and brush.get("faces"):
			var current: Array = []
			for face in brush.faces:
				if face:
					current.append(face.to_dict())
			post_state[brush_id] = current
	undo_redo_manager.create_action(action_name, 0, null, false)
	undo_redo_manager.add_do_method(root, "_apply_vertex_faces", post_state)
	undo_redo_manager.add_undo_method(root, "_apply_vertex_faces", pre_op_snapshots)
	undo_redo_manager.commit_action()
	_record_history(action_name)


func _commit_vertex_move(root: Node, pre_drag_snapshots: Dictionary) -> void:
	if not undo_redo_manager:
		return
	# Capture current (post-move) face state as the "do" state
	var post_state: Dictionary = {}
	for brush_id in pre_drag_snapshots:
		var brush = root.brush_system.find_brush_by_id(brush_id) if root.brush_system else null
		if brush and brush.get("faces"):
			var current: Array = []
			for face in brush.faces:
				if face:
					current.append(face.to_dict())
			post_state[brush_id] = current

	# We must NOT use HFUndoHelper.commit() here because it captures undo
	# state at commit time (post-move), which would replay the move on undo
	# instead of reverting it.  Instead, wire undo/redo manually using the
	# pre-drag snapshots we saved before the drag began.
	undo_redo_manager.create_action("Move Vertices", 0, null, false)
	undo_redo_manager.add_do_method(root, "_apply_vertex_faces", post_state)
	undo_redo_manager.add_undo_method(root, "_apply_vertex_faces", pre_drag_snapshots)
	undo_redo_manager.commit_action()
	_record_history("Move Vertices")


func _update_vertex_overlay(root: Node, cam: Camera3D) -> void:
	if not _vertex_mode or not root or not root.vertex_system:
		_clear_vertex_overlay()
		return
	var vs = root.vertex_system
	var vertex_data = vs.get_all_vertex_world_positions()
	if vertex_data.is_empty():
		_clear_vertex_overlay()
		return
	_ensure_vertex_overlay(root)
	_vertex_overlay_imesh.clear_surfaces()
	# Draw edge wireframe
	var edge_data = vs.get_all_edge_world_positions()
	if not edge_data.is_empty():
		_vertex_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for e in edge_data:
			var ecolor := Color(0.5, 0.5, 0.5, 0.5)
			if e.selected:
				ecolor = Color.ORANGE
			elif e.hovered:
				ecolor = Color.YELLOW
			_vertex_overlay_imesh.surface_set_color(ecolor)
			_vertex_overlay_imesh.surface_add_vertex(e.a)
			_vertex_overlay_imesh.surface_set_color(ecolor)
			_vertex_overlay_imesh.surface_add_vertex(e.b)
		_vertex_overlay_imesh.surface_end()
	# Draw vertex crosses
	_vertex_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for entry in vertex_data:
		var pos: Vector3 = entry.pos
		var color := Color.WHITE
		if entry.selected:
			color = Color.ORANGE
		elif entry.hovered:
			color = Color.YELLOW
		# Draw small cross at each vertex
		var s := 0.4
		_vertex_overlay_imesh.surface_set_color(color)
		_vertex_overlay_imesh.surface_add_vertex(pos + Vector3(-s, 0, 0))
		_vertex_overlay_imesh.surface_set_color(color)
		_vertex_overlay_imesh.surface_add_vertex(pos + Vector3(s, 0, 0))
		_vertex_overlay_imesh.surface_set_color(color)
		_vertex_overlay_imesh.surface_add_vertex(pos + Vector3(0, -s, 0))
		_vertex_overlay_imesh.surface_set_color(color)
		_vertex_overlay_imesh.surface_add_vertex(pos + Vector3(0, s, 0))
		_vertex_overlay_imesh.surface_set_color(color)
		_vertex_overlay_imesh.surface_add_vertex(pos + Vector3(0, 0, -s))
		_vertex_overlay_imesh.surface_set_color(color)
		_vertex_overlay_imesh.surface_add_vertex(pos + Vector3(0, 0, s))
	_vertex_overlay_imesh.surface_end()


func _ensure_vertex_overlay(root: Node) -> void:
	if _vertex_overlay_mesh and is_instance_valid(_vertex_overlay_mesh):
		return
	_vertex_overlay_mesh = MeshInstance3D.new()
	_vertex_overlay_mesh.name = "_VertexEditOverlay"
	_vertex_overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_vertex_overlay_mesh.material_override = mat
	_vertex_overlay_imesh = ImmediateMesh.new()
	_vertex_overlay_mesh.mesh = _vertex_overlay_imesh
	root.add_child(_vertex_overlay_mesh)


func _clear_vertex_overlay() -> void:
	if _vertex_overlay_mesh and is_instance_valid(_vertex_overlay_mesh):
		if _vertex_overlay_mesh.get_parent():
			_vertex_overlay_mesh.get_parent().remove_child(_vertex_overlay_mesh)
		_vertex_overlay_mesh.queue_free()
		_vertex_overlay_mesh = null
	_vertex_overlay_imesh = null


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	_ensure_selection_runtime_state()
	# The 3D viewport receives RMB navigation through the forwarded input hook,
	# but editor shortcuts arrive through this separate hook as well. Keep the
	# complete keyboard stream native until RMB release so Ctrl+Arrow/Escape cannot
	# nudge or cancel HammerForge state during camera flight.
	if _rmb_camera_navigation.active:
		return
	# Native transform/property/custom gizmos own their complete keyboard stream.
	# In particular, Ctrl+Arrow must not become a simultaneous HF nudge while a
	# Godot widget is dragging the same brush.
	if _brush_gizmo_action_active() or _selection_gesture.should_yield_cancel_to_native():
		return
	if not event.pressed or event.echo:
		return
	if should_yield_global_shortcut_to_focus(get_viewport().gui_get_focus_owner()):
		return
	var root = active_root if active_root else _get_level_root()
	if event.keycode == KEY_ESCAPE:
		if _cancel_escape_step(root):
			_mark_shortcut_input_handled()
		return
	if not root:
		return
	# Delete and Duplicate are global editor shortcuts: Godot can deliver them
	# here while focus is in the Scene tree, without ever forwarding them through
	# the 3D viewport. Claim managed selections here as well so every entry point
	# uses HammerForge's undo, stable-ID, and reference-cleanup boundaries.
	if _keymap.matches("delete", event):
		var delete_guard := _guard_hammerforge_shortcut(root, false, 1, "Delete")
		if delete_guard == HF_SHORTCUT_APPLY:
			_delete_selected(root)
			_mark_shortcut_input_handled()
		elif delete_guard == EditorPlugin.AFTER_GUI_INPUT_STOP:
			_mark_shortcut_input_handled()
		return
	if _keymap.matches("duplicate", event):
		var duplicate_guard := _guard_hammerforge_shortcut(root, false, 1, "Duplicate")
		if duplicate_guard == HF_SHORTCUT_APPLY:
			_duplicate_selected(root)
			_mark_shortcut_input_handled()
		elif duplicate_guard == EditorPlugin.AFTER_GUI_INPUT_STOP:
			_mark_shortcut_input_handled()
		return
	if not event.ctrl_pressed:
		return
	var nudge = _get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO:
		var nudge_guard := _guard_hammerforge_shortcut(root, false, 1, "Nudge")
		if nudge_guard == HF_SHORTCUT_APPLY:
			_nudge_selected(root, nudge)
			_mark_shortcut_input_handled()
		elif nudge_guard == EditorPlugin.AFTER_GUI_INPUT_STOP:
			_mark_shortcut_input_handled()


func _mark_shortcut_input_handled() -> void:
	# InputEvent has no accept() API. _shortcut_input() consumes through the
	# viewport so Godot cannot execute the same global command afterwards.
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()


## Only the 3D viewport, the real Scene tree, and explicitly marked HammerForge
## command surfaces may route managed global shortcuts. Unknown editor panels
## keep ownership of their own Delete, Duplicate, arrows, and Escape commands.
static func should_yield_global_shortcut_to_focus(focus_owner: Control) -> bool:
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


func _cancel_escape_step(root: Node) -> bool:
	# Escape is a predictable ladder: dismiss the most local interaction first.
	if _hotkey_palette and _hotkey_palette.visible:
		_hotkey_palette.visible = false
		return true
	if _radial_menu and _radial_menu.is_active():
		_radial_menu.hide_menu()
		return true
	if _quick_property and _quick_property.is_active():
		_quick_property.hide_popup()
		return true
	if _texture_picker_active:
		_texture_picker_active = false
		if dock:
			dock.show_toast("Texture Picker cancelled", 1)
		return true
	if _disp_paint_active:
		if root and not _disp_paint_pre_state.is_empty() and root.has_method("restore_state"):
			root.restore_state(_disp_paint_pre_state)
		_disp_paint_active = false
		_disp_paint_brush_id = ""
		_disp_paint_face_idx = -1
		_disp_paint_pre_state = {}
		return true
	# Godot must see Escape while one of its transform/property/custom gizmos
	# owns LMB so it can restore the exact engine-side value and clear its private
	# drag reference. Only discard HammerForge's parallel bookkeeping here.
	if _brush_gizmo_action_active():
		return false
	if _selection_gesture and _selection_gesture.should_yield_cancel_to_native():
		_cancel_selection_gesture()
		return false
	if _cancel_selection_gesture():
		return true
	if root and root.input_state:
		if root.input_state.is_extruding():
			root.cancel_extrude()
			numeric_buffer = ""
			_update_hud_context()
			return true
		if root.input_state.is_dragging():
			root.cancel_drag()
			numeric_buffer = ""
			_update_hud_context()
			return true
	if _tool_registry and _tool_registry.has_active_external_tool():
		_tool_registry.deactivate_current()
		_update_hud_context()
		return true
	if _vertex_mode:
		_toggle_vertex_mode(root)
		return true
	if root and root.get("face_selection") is Dictionary and not root.face_selection.is_empty():
		root.clear_face_selection()
		_update_hud_context()
		return true
	# Face Select remains modal after its local face selection is cleared. A
	# second Escape (or the first when no face is selected) exits the mode and
	# restores the object selection hidden on entry.
	if _close_face_select_mode("Face Select closed"):
		return true
	if not hf_selection.is_empty():
		hf_selection.clear()
		var selection = get_editor_interface().get_selection()
		if selection:
			selection.clear()
		if dock:
			dock.set_selection_nodes([])
		_update_hud_context()
		return true
	return false


## Godot finishes native selection after _forward_3d_gui_input() returns. Do
## group normalization one deferred tick later so its exact gizmo and region
## hit-testing remains authoritative, then map internal visual children back to
## their HammerForge owner and apply grouped brushes as one selection unit.
func _finalize_native_selection(selection_before: Array, additive: bool, toggle: bool) -> void:
	if not is_inside_tree():
		return
	var selection := get_editor_interface().get_selection()
	if not selection:
		return
	var root := active_root if active_root else _get_level_root()
	var before := _normalize_editor_selection(selection_before, root)
	var editor_nodes := selection.get_selected_nodes()
	var current := _normalize_editor_selection(editor_nodes, root)
	# Native Shift is additive for new hits and removes an already-selected hit.
	# In the latter case, remove the full visgroup instead of re-adding the member
	# Godot just removed. Custom Face Select may additionally request toggle.
	var expanded := _expand_native_group_selection(root, before, current, toggle or additive)
	if _same_node_selection(editor_nodes, expanded):
		hf_selection = expanded
		_on_editor_selection_changed()
		return
	hf_selection = expanded
	_apply_hf_selection(selection)


func _normalize_editor_selection(nodes: Array, root: Node) -> Array:
	var normalized: Array = []
	for candidate in nodes:
		if not is_instance_valid(candidate) or not (candidate is Node):
			continue
		var node := _hammerforge_selection_owner(candidate as Node, root)
		if node and not normalized.has(node):
			normalized.append(node)
	return normalized


func _hammerforge_selection_owner(node: Node, root: Node) -> Node:
	return normalize_managed_selection_owner(node, root)


static func normalize_managed_selection_owner(node: Node, root: Node) -> Node:
	var current := node
	var entities_root: Node = root.get("entities_node") as Node if root else null
	while current:
		if current is DraftBrush or current is DraftEntityType:
			return current
		# is_entity_node() deliberately accepts descendants for interaction tests.
		# Selection ownership is narrower: climb to the DraftEntity or the direct
		# managed child used by legacy/custom entity nodes before returning.
		if (
			entities_root
			and current.get_parent() == entities_root
			and root.has_method("is_entity_node")
			and root.is_entity_node(current)
		):
			return current
		if current == root:
			break
		current = current.get_parent()
	return node


func _expand_native_group_selection(
	root: Node, selection_before: Array, current_selection: Array, toggle: bool
) -> Array:
	if not root or not root.visgroup_system:
		return current_selection.duplicate()
	var groups := {}
	for node in selection_before + current_selection:
		if not is_instance_valid(node):
			continue
		var group_id: String = str(root.visgroup_system.get_group_of(node))
		if group_id != "" and not groups.has(group_id):
			groups[group_id] = root.visgroup_system.get_group_members(group_id)
	return expand_native_group_members(selection_before, current_selection, toggle, groups)


static func expand_native_group_members(
	selection_before: Array, current_selection: Array, toggle: bool, groups: Dictionary
) -> Array:
	var result := current_selection.duplicate()
	for group_id in groups:
		var members: Array = groups.get(group_id, [])
		if members.is_empty():
			continue
		var before_members: Array = []
		var current_members: Array = []
		for member in members:
			if selection_before.has(member):
				before_members.append(member)
			if current_selection.has(member):
				current_members.append(member)
		if _same_node_selection(before_members, current_members):
			continue
		var removed_member := false
		for member in before_members:
			if not current_members.has(member):
				removed_member = true
				break
		if toggle and removed_member:
			for member in members:
				result.erase(member)
		elif not current_members.is_empty():
			for member in members:
				if is_instance_valid(member) and not result.has(member):
					result.append(member)
	return result


static func _same_node_selection(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for node in first:
		if not second.has(node):
			return false
	return true


func _apply_selection_list(nodes: Array, additive: bool, toggle: bool = false) -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	if not additive:
		hf_selection.clear()
	else:
		_sync_hf_selection_if_empty()
	for node in nodes:
		if not node:
			continue
		if additive and toggle and hf_selection.has(node):
			hf_selection.erase(node)
		elif not hf_selection.has(node):
			hf_selection.append(node)
	_apply_hf_selection(selection)


func _apply_hf_selection(selection: EditorSelection) -> void:
	_applying_hf_selection = true
	selection.clear()
	for node in hf_selection:
		if is_instance_valid(node):
			selection.add_node(node)
	_applying_hf_selection = false
	_on_editor_selection_changed()


func _sync_hf_selection_if_empty() -> void:
	if not hf_selection.is_empty():
		return
	var selection = get_editor_interface().get_selection()
	if selection:
		hf_selection = selection.get_selected_nodes()


func _selection_has_brush(nodes: Array, root: Node) -> bool:
	if not root:
		return false
	for node in nodes:
		if root.is_brush_node(node):
			return true
	return false


func _selection_has_entity(nodes: Array, root: Node) -> bool:
	if not root:
		return false
	for node in nodes:
		if root.is_entity_node(node):
			return true
	return false


## Input forwarding is global, but HammerForge edit commands are not. Native
## selections pass through to Godot; mixed selections are blocked from both
## command paths because generic duplicate/delete can corrupt managed IDs.
static func classify_selection_scope(nodes: Array, root: Node) -> int:
	if nodes.is_empty() or not root:
		return SelectionScope.EMPTY
	var has_hammerforge := false
	var has_native := false
	for node in nodes:
		if not is_instance_valid(node) or not (node is Node):
			has_native = true
		elif root.is_brush_node(node) or root.is_entity_node(node):
			has_hammerforge = true
		else:
			has_native = true
	if has_hammerforge and has_native:
		return SelectionScope.MIXED
	return SelectionScope.HAMMERFORGE_ONLY if has_hammerforge else SelectionScope.NATIVE_ONLY


func _guard_hammerforge_shortcut(
	root: Node, brushes_only: bool, minimum_count: int, action_label: String
) -> int:
	var nodes := _current_selection_nodes()
	var scope := classify_selection_scope(nodes, root)
	if scope in [SelectionScope.EMPTY, SelectionScope.NATIVE_ONLY]:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if scope == SelectionScope.MIXED:
		if dock:
			dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if brushes_only:
		for node in nodes:
			if not root.is_brush_node(node):
				if dock:
					dock.show_toast("%s works on brushes only" % action_label, 1)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	if nodes.size() < minimum_count:
		if dock:
			dock.show_toast("%s needs at least %d selected" % [action_label, minimum_count], 1)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return HF_SHORTCUT_APPLY


## Selection-dependent commands enter through keyboard shortcuts, the context
## toolbar, the command palette, the viewport menu, and the radial menu. Keep
## one requirement table so every surface either applies the complete managed
## selection or applies nothing; a mixed native/HammerForge selection must
## never be partially edited.
static func managed_surface_action_requirement(action: String) -> Dictionary:
	if action in ["delete", "duplicate"]:
		return {"brushes_only": false, "minimum": 1, "label": action.capitalize()}
	if action == "group":
		return {"brushes_only": false, "minimum": 2, "label": "Group"}
	if action == "ungroup":
		return {"brushes_only": false, "minimum": 1, "label": "Ungroup"}
	if action == "merge":
		return {"brushes_only": true, "minimum": 2, "label": "Merge"}
	if (
		action
		in [
			"hollow",
			"clip",
			"carve",
			"move_to_floor",
			"move_to_ceiling",
			"vertex_edit",
			"vertex_submode",
			"edge_submode",
			"vertex_merge",
			"vertex_split",
			"vertex_split_edge",
			"vertex_clip_convex",
		]
	):
		return {
			"brushes_only": true,
			"minimum": 1,
			"label": action.replace("_", " ").capitalize(),
		}
	if (
		action
		in ["apply_to_brush", "apply_context_material", "apply_last_texture", "select_similar"]
	):
		return {
			"brushes_only": true,
			"minimum": 1,
			"label": action.replace("_", " ").capitalize(),
			"allow_faces": true,
		}
	if (
		action
		in [
			"justify_fit",
			"justify_center",
			"justify_left",
			"justify_right",
			"justify_top",
			"justify_bottom",
		]
	):
		return {
			"brushes_only": true,
			"minimum": 1,
			"label": "UV Justify",
			"allow_faces": true,
		}
	if (
		action
		in [
			"quick_save_prefab",
			"quick_save_linked_prefab",
			"cycle_variant",
			"push_to_source",
			"propagate_prefab",
			"entity_io",
			"entity_props",
			"highlight_connected",
		]
	):
		return {
			"brushes_only": false,
			"minimum": 1,
			"label": action.replace("_", " ").capitalize(),
		}
	if action == "selection_filter":
		# Filters may start from an empty selection, but never from a mixed one.
		return {"mixed_only": true, "label": "Selection Filters"}
	return {}


func _managed_action_surface_allowed(root: Node, action: String) -> bool:
	var requirement := managed_surface_action_requirement(action)
	if requirement.is_empty():
		return true
	var nodes := _current_selection_nodes()
	var scope := classify_selection_scope(nodes, root)
	if scope == SelectionScope.MIXED:
		if dock:
			dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
		return false
	if bool(requirement.get("mixed_only", false)):
		return true
	if bool(requirement.get("allow_faces", false)) and root:
		var faces = root.get("face_selection")
		if faces is Dictionary and not faces.is_empty():
			return true
	var guard := _guard_hammerforge_shortcut(
		root,
		bool(requirement.get("brushes_only", false)),
		int(requirement.get("minimum", 1)),
		str(requirement.get("label", "Action"))
	)
	if guard == HF_SHORTCUT_APPLY:
		return true
	if guard == EditorPlugin.AFTER_GUI_INPUT_PASS and dock:
		dock.show_toast("Select a HammerForge object first", 1)
	return false


func _hammerforge_selection_nodes(root: Node, brushes_only: bool = false) -> Array:
	var eligible: Array = []
	if not root:
		return eligible
	for node in _current_selection_nodes():
		if not is_instance_valid(node) or not (node is Node):
			continue
		if root.is_brush_node(node) or (not brushes_only and root.is_entity_node(node)):
			eligible.append(node)
	return eligible


func _managed_entity_owner(root: Node, node: Node) -> Node:
	if not root or not node or not root.is_entity_node(node):
		return null
	var owner := _hammerforge_selection_owner(node, root)
	return owner if owner is DraftEntityType else null


func _current_selection_nodes() -> Array:
	if not hf_selection.is_empty():
		return hf_selection.duplicate()
	var selection = get_editor_interface().get_selection()
	if selection:
		return selection.get_selected_nodes()
	return []


func _get_undo_redo() -> EditorUndoRedoManager:
	return undo_redo_manager if undo_redo_manager else get_undo_redo()


func _record_history(action_name: String) -> void:
	if dock:
		dock.record_history(action_name)
	if _operation_replay and is_instance_valid(_operation_replay):
		var version := -1
		if undo_redo_manager:
			var history_id := (
				undo_redo_manager.get_object_history_id(active_root) if active_root else 0
			)
			var undo_redo_obj: UndoRedo = undo_redo_manager.get_history_undo_redo(history_id)
			if undo_redo_obj:
				version = undo_redo_obj.get_version()
		_operation_replay.record_operation(action_name, version)


func _paint_brush_with_undo(root: Node, brush: Node, mat: Material) -> void:
	if not root or not brush:
		return
	var prev = (
		brush.get("material_override") if brush.get("material_override") else brush.get("material")
	)
	if prev == mat:
		return
	var brush_id := ""
	if root.has_method("get_brush_info_from_node"):
		var info = root.get_brush_info_from_node(brush)
		brush_id = str(info.get("brush_id", ""))
	var method_name = "apply_material_to_brush"
	var args: Array = [brush, mat]
	if brush_id != "":
		method_name = "apply_material_to_brush_by_id"
		args = [brush_id, mat]
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Paint Brush",
		method_name,
		args,
		false,
		Callable(self, "_record_history"),
		"paint_brush"
	)


func _commit_brush_placement(root: Node, info: Dictionary) -> void:
	if info.is_empty():
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Place Brush",
		"create_brush_from_info",
		[info],
		false,
		Callable(self, "_record_history")
	)


func _pick_face_material(root: Node) -> void:
	if not last_3d_camera or not dock:
		return
	var cam = last_3d_camera
	var pos = last_3d_mouse_pos
	var hit: Dictionary = root.pick_face(cam, pos)
	if hit.is_empty():
		if dock:
			dock.show_toast("No face under cursor", 1)
		return
	var brush: DraftBrush = hit.get("brush") as DraftBrush
	var face_idx: int = int(hit.get("face_idx", -1))
	if brush == null or face_idx < 0:
		return
	if face_idx >= brush.faces.size():
		return
	var face: FaceData = brush.faces[face_idx]
	var mat_idx: int = face.material_idx if face else -1
	if mat_idx < 0:
		if dock:
			dock.show_toast("Face has no material assigned", 1)
		return
	dock._selected_material_index = mat_idx
	_last_picked_material_index = mat_idx
	if dock.material_browser:
		dock.material_browser.set_selected_index(mat_idx)
	dock.show_toast("Picked material #%d" % mat_idx, 0)


# ---------------------------------------------------------------------------
# Marquee & face rect selection
# ---------------------------------------------------------------------------


func _select_faces_in_rect(
	root: Node, camera: Camera3D, from: Vector2, to: Vector2, additive: bool, toggle: bool = false
) -> void:
	if not root or not camera:
		return
	var rect = Rect2(from, to - from).abs()
	var face_sel: Dictionary = {} if not additive else root.face_selection.duplicate(true)
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	for node in nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		# Match the canonical click picker: tied brush-entity geometry and hidden
		# candidates are not editable as standalone faces.
		if not root.is_brush_node(brush) or not brush.is_visible_in_tree():
			continue
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = _face_key_for(brush)
		var indices: Array = face_sel.get(key, []).duplicate() if additive else []
		for i in range(faces.size()):
			var face = faces[i]
			if not face:
				continue
			var center := _face_screen_center(camera, brush, face)
			if center == Vector2(-1, -1) or not rect.has_point(center):
				continue
			# Projected centers alone select backfaces and faces hidden behind other
			# brushes. Reuse the exact depth-aware picker at that screen point and
			# accept only the face that is actually visible to the camera.
			var visible_hit: Dictionary = root.pick_face(camera, center)
			if visible_hit.get("brush") != brush or int(visible_hit.get("face_idx", -1)) != i:
				continue
			if additive and toggle and indices.has(i):
				indices.erase(i)
			elif not indices.has(i):
				indices.append(i)
		if not indices.is_empty():
			face_sel[key] = indices
		else:
			face_sel.erase(key)
	_apply_face_selection(root, face_sel)


func _face_screen_center(camera: Camera3D, brush: DraftBrush, face) -> Vector2:
	if face.local_verts.is_empty():
		return Vector2(-1, -1)
	var center := Vector3.ZERO
	for v in face.local_verts:
		center += v
	center /= float(face.local_verts.size())
	var world_pos: Vector3 = brush.global_transform * center
	if camera.is_position_behind(world_pos):
		return Vector2(-1, -1)
	return camera.unproject_position(world_pos)


func _face_key_for(brush: DraftBrush) -> String:
	if brush.brush_id != "":
		return brush.brush_id
	return str(brush.get_instance_id())


func _apply_face_selection(root: Node, face_sel: Dictionary) -> void:
	root.face_selection = face_sel
	if root.brush_system:
		root.brush_system._apply_face_selection()
	root.face_selection_changed.emit()
	_update_hud_context()


# ---------------------------------------------------------------------------
# Apply Last Texture
# ---------------------------------------------------------------------------


func _apply_last_texture(root: Node) -> void:
	if _last_picked_material_index < 0:
		if dock:
			dock.show_toast("No texture picked yet — use T to pick first", 1)
		return
	if not dock:
		return
	dock._selected_material_index = _last_picked_material_index
	var face_count = dock._count_selected_faces()
	if face_count > 0:
		dock._on_face_assign_material()
		dock.show_toast(
			"Applied last texture to %d face%s" % [face_count, "" if face_count == 1 else "s"], 0
		)
	else:
		var applied_count := 0
		var mat = (
			root.material_manager.get_material(_last_picked_material_index)
			if root.material_manager
			else null
		)
		if mat:
			for node in hf_selection:
				if node is DraftBrush:
					_paint_brush_with_undo(root, node, mat)
					applied_count += 1
		if applied_count > 0:
			dock.show_toast(
				(
					"Applied last texture to %d brush%s"
					% [applied_count, "" if applied_count == 1 else "es"]
				),
				0
			)
		else:
			dock.show_toast("No brushes or faces selected", 1)


# ---------------------------------------------------------------------------
# Select All / Deselect All
# ---------------------------------------------------------------------------


func _select_all_nodes(root: Node) -> void:
	if not root:
		return
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	# Clear face selection first so context toolbar switches to object context
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	var all_nodes: Array = root._iter_pick_nodes()
	hf_selection.clear()
	for node in all_nodes:
		if is_instance_valid(node):
			hf_selection.append(node)
	_apply_hf_selection(selection)
	_update_hud_context()
	if dock:
		dock.set_selection_count(hf_selection.size())
		dock.set_selection_nodes(hf_selection)
		dock.show_toast("Selected %d objects" % hf_selection.size(), 0)


func _deselect_all_nodes(root: Node) -> void:
	if not root:
		return
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	if dock:
		dock.emit_signal("selection_clear_requested")
	hf_selection.clear()
	selection.clear()
	# Also clear face selection
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	elif root.get("face_selection") is Dictionary:
		root.face_selection.clear()
	_update_hud_context()
	if dock:
		dock.set_selection_count(0)
		dock.set_selection_nodes([])


# ---------------------------------------------------------------------------
# Select Similar
# ---------------------------------------------------------------------------


func _select_similar(root: Node) -> void:
	if not root:
		return
	# If faces are selected, find similar faces across all brushes
	var face_count := 0
	for key in root.face_selection.keys():
		face_count += root.face_selection.get(key, []).size()
	if face_count > 0:
		_select_similar_faces(root)
		return
	# Otherwise match similar brushes by size
	if not hf_selection.is_empty():
		_select_similar_brushes(root)
		return
	if dock:
		dock.show_toast("Select a face or brush first", 1)


func _select_similar_faces(root: Node) -> void:
	# Gather reference face properties with world-space normals
	var ref_faces: Array = []
	var ref_world_normals: Array = []
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		if not brush:
			continue
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		for fi in root.face_selection.get(key, []):
			if int(fi) >= 0 and int(fi) < faces.size():
				ref_faces.append(faces[int(fi)])
				ref_world_normals.append((basis * faces[int(fi)].normal).normalized())
	if ref_faces.is_empty():
		return
	# Find all matching faces (same material AND similar world-space normal within ~15 degrees)
	var face_sel: Dictionary = {}
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	var total := 0
	for node in nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var basis: Basis = brush.global_transform.basis
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = _face_key_for(brush)
		var indices: Array = []
		for i in range(faces.size()):
			var face = faces[i]
			if not face:
				continue
			var world_normal: Vector3 = (basis * face.normal).normalized()
			for ri in range(ref_faces.size()):
				var ref = ref_faces[ri]
				var ref_wn: Vector3 = ref_world_normals[ri]
				if face.material_idx == ref.material_idx and world_normal.dot(ref_wn) > 0.966:
					indices.append(i)
					total += 1
					break
		if not indices.is_empty():
			face_sel[key] = indices
	_apply_face_selection(root, face_sel)
	if dock:
		dock.show_toast("Selected %d similar face%s" % [total, "" if total == 1 else "s"], 0)


func _select_similar_brushes(root: Node) -> void:
	var ref_sizes: Array = []
	for node in hf_selection:
		if node is DraftBrush and is_instance_valid(node):
			ref_sizes.append((node as DraftBrush).size)
	if ref_sizes.is_empty():
		return
	var tolerance := 0.2
	var picked: Array = []
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	for node in nodes:
		if not (node is DraftBrush):
			continue
		var sz: Vector3 = (node as DraftBrush).size
		for ref_sz in ref_sizes:
			if _size_similar(sz, ref_sz, tolerance):
				picked.append(node)
				break
	_apply_selection_list(picked, false)
	if dock:
		dock.show_toast(
			"Selected %d similar brush%s" % [picked.size(), "" if picked.size() == 1 else "es"], 0
		)


func _size_similar(a: Vector3, b: Vector3, tolerance: float) -> bool:
	var sa := _sorted_vec(a)
	var sb := _sorted_vec(b)
	for i in range(3):
		var ref_val: float = maxf(sb[i], 0.01)
		if absf(sa[i] - sb[i]) / ref_val > tolerance:
			return false
	return true


func _sorted_vec(v: Vector3) -> Array:
	var arr := [v.x, v.y, v.z]
	arr.sort()
	return arr


# ---------------------------------------------------------------------------
# Selection Filter popup
# ---------------------------------------------------------------------------


func _show_selection_filter() -> void:
	if not _selection_filter:
		return
	var root = active_root if active_root else _get_level_root()
	_selection_filter.show_for(root, hf_selection)
	# Position near the mouse
	var popup_pos := Vector2i(int(last_3d_mouse_pos.x), int(last_3d_mouse_pos.y))
	_selection_filter.popup(Rect2i(popup_pos, Vector2i.ZERO))


func _on_selection_filter_applied(nodes: Array, faces: Dictionary) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	# Apply face selection if provided
	if not faces.is_empty():
		_apply_face_selection(root, faces)
		var total := 0
		for key in faces.keys():
			total += faces[key].size()
		if dock:
			dock.show_toast("Selected %d face%s" % [total, "" if total == 1 else "s"], 0)
	elif not nodes.is_empty():
		# Node-only filter — clear any stale face selection first
		_apply_face_selection(root, {})
		_apply_selection_list(nodes, false)
		if dock:
			dock.show_toast(
				"Selected %d node%s" % [nodes.size(), "" if nodes.size() == 1 else "s"], 0
			)


# ---------------------------------------------------------------------------
# Marquee overlay
# ---------------------------------------------------------------------------


func _update_marquee_overlay(from: Vector2, to: Vector2, active: bool) -> void:
	_marquee_overlay_origin = from
	_marquee_overlay_current = to
	_marquee_overlay_active = active
	if is_inside_tree():
		update_overlays()


## Draw through Godot's real 3D overlay so viewport-local event coordinates
## remain correct under split views, editor scaling, and dock rearrangement.
func _forward_3d_force_draw_over_viewport(viewport_control: Control) -> void:
	if not _marquee_overlay_active or not viewport_control:
		return
	var local_mouse := viewport_control.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, viewport_control.size).has_point(local_mouse):
		return
	var rect := (
		Rect2(_marquee_overlay_origin, _marquee_overlay_current - _marquee_overlay_origin).abs()
	)
	viewport_control.draw_rect(rect, Color(0.3, 0.6, 1.0, 0.12))
	viewport_control.draw_rect(rect, Color(0.3, 0.6, 1.0, 0.7), false, 1.5)


func _add_confirmable_dialog(dlg: ConfirmationDialog) -> void:
	if _dialog_manager:
		_dialog_manager.add(dlg, get_editor_interface().get_base_control())


func _cleanup_pending_dialogs() -> void:
	if _dialog_manager:
		_dialog_manager.cleanup()


func _delete_selected(root: Node) -> bool:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	var entity_paths: Array = []
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			if info.is_empty():
				continue
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
		elif root.is_entity_node(node):
			var entity := _managed_entity_owner(root, node)
			if entity:
				entity_paths.append(root.get_path_to(entity))
	var object_count := brush_ids.size() + entity_paths.size()
	if object_count == 0:
		return false
	var action_name := (
		"Delete Brushes"
		if entity_paths.is_empty()
		else ("Delete Entities" if brush_ids.is_empty() else "Delete HammerForge Objects")
	)
	# Confirm bulk delete (3+ managed objects) to prevent accidental mass deletion.
	if object_count >= 3:
		var dlg = ConfirmationDialog.new()
		dlg.title = action_name
		dlg.dialog_text = (
			"Delete %d HammerForge objects? This can be undone with Ctrl+Z." % object_count
		)
		dlg.min_size = Vector2i(280, 80)
		_add_confirmable_dialog(dlg)
		dlg.confirmed.connect(
			func():
				if not is_instance_valid(self) or not is_instance_valid(root):
					dlg.queue_free()
					return
				hf_selection.clear()
				selection.clear()
				HFUndoHelper.commit(
					_get_undo_redo(),
					root,
					action_name,
					"delete_managed_nodes",
					[brush_ids, entity_paths],
					false,
					Callable(self, "_record_history")
				)
				dlg.queue_free()
		)
		dlg.canceled.connect(
			func():
				if not is_instance_valid(self):
					return
				dlg.queue_free()
		)
		dlg.popup_centered()
		return true
	hf_selection.clear()
	selection.clear()
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		action_name,
		"delete_managed_nodes",
		[brush_ids, entity_paths],
		false,
		Callable(self, "_record_history")
	)
	return true


func _duplicate_selected(root: Node) -> bool:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var brush_infos: Array = []
	var entity_infos: Array = []
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.build_duplicate_info(node, Vector3(step, 0.0, 0.0))
			if not info.is_empty():
				brush_infos.append(info)
		elif root.is_entity_node(node):
			var entity := _managed_entity_owner(root, node)
			if entity:
				var info: Dictionary = root.build_duplicate_entity_info(
					entity, Vector3(step, 0.0, 0.0)
				)
				if not info.is_empty():
					entity_infos.append(info)
	if brush_infos.is_empty() and entity_infos.is_empty():
		return false
	var action_name := (
		"Duplicate Brushes"
		if entity_infos.is_empty()
		else ("Duplicate Entities" if brush_infos.is_empty() else "Duplicate HammerForge Objects")
	)
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		action_name,
		"create_managed_duplicates",
		[brush_infos, entity_infos],
		false,
		Callable(self, "_record_history")
	)
	hf_selection.clear()
	for info in brush_infos:
		var duplicate_brush = root.find_brush_by_id(info.get("brush_id", ""))
		if duplicate_brush:
			hf_selection.append(duplicate_brush)
	for info in entity_infos:
		var duplicate_entity: Node = root.entities_node.get_node_or_null(
			NodePath(str(info.get("name", "")))
		)
		if duplicate_entity:
			hf_selection.append(duplicate_entity)
	_apply_hf_selection(selection)
	return true


func _nudge_selected(root: Node, dir: Vector3) -> bool:
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	var entity_paths: Array = []
	for node in nodes:
		if node and node is Node3D and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
		elif node and node is Node3D and root.is_entity_node(node):
			var entity := _managed_entity_owner(root, node)
			if entity:
				entity_paths.append(root.get_path_to(entity))
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var offset = dir * step
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[brush_ids, entity_paths, offset],
		false,
		Callable(self, "_record_history"),
		"nudge"
	)
	return true


func _adjust_grid_snap(root: Node, factor: float) -> void:
	if not root:
		return
	var current: float = root.grid_snap if root.grid_snap > 0.0 else 16.0
	var new_val: float = clampf(current * factor, 0.125, 512.0)
	if dock:
		dock._apply_grid_snap(new_val)
	else:
		root.grid_snap = new_val
	_update_hud_context()


func _group_selected(root: Node) -> bool:
	var nodes = _hammerforge_selection_nodes(root)
	if nodes.size() < 2 or not root or not root.visgroup_system:
		return false
	var group_name = "group_%d" % Time.get_ticks_usec()
	root.visgroup_system.group_selection(group_name, nodes)
	_record_history("Group Selection")
	if dock:
		dock.refresh_visgroup_ui()
	return true


func _ungroup_selected(root: Node) -> bool:
	var nodes = _hammerforge_selection_nodes(root)
	if nodes.is_empty() or not root or not root.visgroup_system:
		return false
	var grouped: Array = []
	for node in nodes:
		if str(root.visgroup_system.get_group_of(node)) != "":
			grouped.append(node)
	if grouped.is_empty():
		return false
	root.visgroup_system.ungroup_nodes(grouped)
	_record_history("Ungroup Selection")
	if dock:
		dock.refresh_visgroup_ui()
	return true


func _hollow_selected(root: Node) -> bool:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return false
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return false
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return false
	var thickness = dock.get_hollow_thickness() if dock else 4.0
	var check: HFOpResult = root.can_hollow_brush(brush_id, thickness)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	# Show geometry preview and confirm
	if root.hollow_preview:
		root.hollow_preview.show_preview(brush_id, thickness)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Hollow Brush"
	dlg.dialog_text = (
		"Hollow with wall thickness %.1f?\n(Yellow wireframe shows resulting walls)" % thickness
	)
	dlg.min_size = Vector2i(300, 100)
	_add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(self) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.hollow_preview:
				root.hollow_preview.clear()
			HFUndoHelper.commit(
				_get_undo_redo(),
				root,
				"Hollow",
				"hollow_brush_by_id",
				[brush_id, thickness],
				false,
				Callable(self, "_record_history")
			)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(self):
				return
			if root and is_instance_valid(root) and root.hollow_preview:
				root.hollow_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


func _merge_selected(root: Node) -> bool:
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.size() < 2:
		if dock:
			dock.show_toast("Select at least 2 brushes to merge", 1)
		return false
	var check: HFOpResult = root.can_merge_brushes(brush_ids)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Merge Brushes",
		"merge_brushes_by_ids",
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)
	return true


func _move_selected_to_floor(root: Node) -> bool:
	return _move_selected_vertical(root, "Move to Floor", "move_brushes_to_floor")


func _move_selected_to_ceiling(root: Node) -> bool:
	return _move_selected_vertical(root, "Move to Ceiling", "move_brushes_to_ceiling")


func _move_selected_vertical(root: Node, action_name: String, method_name: String) -> bool:
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return false
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		action_name,
		method_name,
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)
	return true


func _clip_selected(root: Node) -> bool:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return false
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return false
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return false
	# Default clip: split along Y axis at center
	var center = info.get("center", Vector3.ZERO)
	var split_pos = center.y if center is Vector3 else 0.0
	var check: HFOpResult = root.can_clip_brush(brush_id, 1, split_pos)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	# Show geometry preview and confirm
	if root.clip_preview:
		root.clip_preview.show_preview(brush_id, 1, split_pos)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Clip Brush"
	dlg.dialog_text = (
		"Split brush along Y axis at %.1f?\n(Cyan wireframe shows resulting pieces)" % split_pos
	)
	dlg.min_size = Vector2i(300, 100)
	_add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(self) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.clip_preview:
				root.clip_preview.clear()
			HFUndoHelper.commit(
				_get_undo_redo(),
				root,
				"Clip Brush",
				"clip_brush_by_id",
				[brush_id, 1, split_pos],
				false,
				Callable(self, "_record_history")
			)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(self):
				return
			if root and is_instance_valid(root) and root.clip_preview:
				root.clip_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


func _carve_selected(root: Node) -> bool:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return false
	# Collect valid carver brush IDs
	var carve_ids: Array = []
	for node in nodes:
		if not root.is_brush_node(node):
			continue
		var info = root.get_brush_info_from_node(node)
		var brush_id = str(info.get("brush_id", ""))
		if brush_id != "":
			carve_ids.append(brush_id)
	if carve_ids.is_empty():
		return false
	# Show preview for the first carver (multi-carve shows first only)
	if root.carve_preview:
		root.carve_preview.show_preview(carve_ids[0])
	# Confirm before committing destructive carve
	var dlg = ConfirmationDialog.new()
	dlg.title = "Carve"
	dlg.dialog_text = (
		"Carve %d brush(es)?\n(Green wireframe shows resulting pieces)" % carve_ids.size()
	)
	dlg.min_size = Vector2i(300, 100)
	_add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(self) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.carve_preview:
				root.carve_preview.clear()
			for bid in carve_ids:
				HFUndoHelper.commit(
					_get_undo_redo(),
					root,
					"Carve",
					"carve_with_brush",
					[bid],
					false,
					Callable(self, "_record_history")
				)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(self):
				return
			if root and is_instance_valid(root) and root.carve_preview:
				root.carve_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return (
		_is_entity_drag_data(data)
		or _is_brush_preset_drag_data(data)
		or _is_prefab_drag_data(data)
		or _is_material_drag_data(data)
	)


func _drop_data(position: Vector2, data: Variant) -> void:
	if _is_material_drag_data(data):
		_handle_material_drop(position, data)
	elif _is_brush_preset_drag_data(data):
		_handle_brush_preset_drop(position, data)
	elif _is_prefab_drag_data(data):
		_handle_prefab_drop(position, data)
	else:
		_handle_entity_drop(position, data)


func _is_entity_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_entity"


func _handle_entity_drop(position: Vector2, data: Variant) -> void:
	if not _is_entity_drag_data(data):
		return
	var entity_id = str(data.get("entity_id", ""))
	if entity_id == "":
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root:
		return
	var camera = last_3d_camera
	var mouse_pos = position if position != null else last_3d_mouse_pos
	if camera and root:
		var entity = root.place_entity_at_screen(camera, mouse_pos, entity_id)
		if entity:
			var selection = get_editor_interface().get_selection()
			if selection:
				selection.clear()
				selection.add_node(entity)
			hf_selection.clear()
			hf_selection.append(entity)


func _is_brush_preset_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_brush_preset"


func _handle_brush_preset_drop(position: Vector2, data: Variant) -> void:
	if not _is_brush_preset_drag_data(data):
		return
	var preset_path = str(data.get("preset_path", ""))
	if preset_path == "":
		return
	var preset = load(preset_path)
	if not preset or not (preset is BrushPreset):
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root:
		return
	var camera = last_3d_camera
	var mouse_pos = position if position != null else last_3d_mouse_pos
	if not camera:
		return
	var hit = root._raycast(camera, mouse_pos)
	if hit.is_empty():
		return
	var point = root._snap_point(hit.get("position", Vector3.ZERO))
	var size = preset.size
	var center = point + Vector3(0, size.y * 0.5, 0)
	var operation = preset.operation
	var info = {
		"shape": preset.shape,
		"size": size,
		"center": center,
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id()
	}
	if root._shape_uses_sides(preset.shape):
		info["sides"] = preset.sides
	var mat = dock.get_active_material() if dock else null
	if mat:
		info["material"] = mat
	_commit_brush_placement(root, info)


func _is_prefab_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_prefab"


func _handle_prefab_drop(position: Vector2, data: Variant) -> void:
	if not _is_prefab_drag_data(data):
		return
	var prefab_path = str(data.get("path", ""))
	if prefab_path == "":
		return
	var HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
	var prefab = HFPrefabType.load_from_file(prefab_path)
	if not prefab:
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root:
		return
	var camera = last_3d_camera
	var mouse_pos = position if position != null else last_3d_mouse_pos
	if not camera:
		return
	var hit = root._raycast(camera, mouse_pos)
	if hit.is_empty():
		return
	var point = root._snap_point(hit.get("position", Vector3.ZERO))
	# Capture state for undo
	var full_state = root.state_system.capture_state(true)
	var result = prefab.instantiate(root.brush_system, root.entity_system, root, point)
	var placed_anything: bool = (
		not result.get("brush_ids", []).is_empty() or result.get("entity_count", 0) > 0
	)
	if placed_anything:
		# Register prefab instance for tracking/propagation
		if root.prefab_system:
			root.prefab_system.register_instance(
				prefab_path, result.get("brush_ids", []), result.get("entity_nodes", []), false  # not linked by default on drag-drop
			)
		var undo_redo = undo_redo_manager
		if undo_redo:
			undo_redo.create_action("Place Prefab: %s" % prefab.prefab_name)
			undo_redo.add_do_method(
				root.state_system, "restore_state", root.state_system.capture_state(true)
			)
			undo_redo.add_undo_method(root.state_system, "restore_state", full_state)
			undo_redo.commit_action(false)


# ---------------------------------------------------------------------------
# Prefab enhancement helpers
# ---------------------------------------------------------------------------


func _quick_save_prefab(root, linked: bool) -> void:
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in hf_selection:
		if root.is_brush_node(node):
			brush_nodes.append(node)
		elif root.is_entity_node(node):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	var suggested: String = root.prefab_system.suggest_prefab_name(brush_nodes, entity_nodes)
	var path: String = root.prefab_system.quick_save_prefab(
		brush_nodes, entity_nodes, suggested, linked
	)
	if path != "":
		if dock and dock._prefab_library:
			dock._prefab_library.on_prefab_saved()
		if dock:
			dock.show_toast("Saved prefab: %s%s" % [suggested, " (linked)" if linked else ""], 0)


func _cycle_prefab_variant(root) -> void:
	if hf_selection.is_empty():
		return
	var node = hf_selection[0]
	if not is_instance_valid(node) or not (node is Node):
		return
	var iid: String = str(node.get_meta("hf_prefab_instance", ""))
	if iid == "":
		if dock:
			dock.show_toast("Not a prefab instance", 1)
		return
	var full_state: Dictionary = root.state_system.capture_state(true)
	var new_variant: String = root.prefab_system.cycle_variant(iid)
	if new_variant != "":
		if dock:
			dock.show_toast("Variant: %s" % new_variant, 0)
		var undo_redo = undo_redo_manager
		if undo_redo:
			undo_redo.create_action("Cycle Prefab Variant")
			undo_redo.add_do_method(
				root.state_system, "restore_state", root.state_system.capture_state(true)
			)
			undo_redo.add_undo_method(root.state_system, "restore_state", full_state)
			undo_redo.commit_action(false)
		_update_hud_context()


func _push_prefab_to_source(root) -> void:
	if hf_selection.is_empty():
		return
	var node = hf_selection[0]
	if not is_instance_valid(node) or not (node is Node):
		return
	var iid: String = str(node.get_meta("hf_prefab_instance", ""))
	if iid == "":
		if dock:
			dock.show_toast("Not a prefab instance", 1)
		return
	var ok: bool = root.prefab_system.push_instance_to_source(iid)
	if ok:
		if dock:
			dock.show_toast("Pushed changes to prefab source", 0)
		if dock and dock._prefab_library:
			dock._prefab_library.on_prefab_saved()
	else:
		if dock:
			dock.show_toast("Failed to push to source", 1)


func _propagate_prefab(root) -> void:
	if hf_selection.is_empty():
		return
	var node = hf_selection[0]
	if not is_instance_valid(node) or not (node is Node):
		return
	var source: String = str(node.get_meta("hf_prefab_source", ""))
	if source == "":
		if dock:
			dock.show_toast("Not a prefab instance", 1)
		return
	var full_state: Dictionary = root.state_system.capture_state(true)
	var count: int = root.prefab_system.propagate_from_source(source)
	if count > 0:
		if dock:
			dock.show_toast(
				"Propagated to %d linked instance%s" % [count, "" if count == 1 else "s"], 0
			)
		var undo_redo = undo_redo_manager
		if undo_redo:
			undo_redo.create_action("Propagate Prefab")
			undo_redo.add_do_method(
				root.state_system, "restore_state", root.state_system.capture_state(true)
			)
			undo_redo.add_undo_method(root.state_system, "restore_state", full_state)
			undo_redo.commit_action(false)
	else:
		if dock:
			dock.show_toast("No linked instances to propagate", 1)


func _is_material_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_material"


func _handle_material_drop(position: Vector2, data: Variant) -> void:
	if not _is_material_drag_data(data):
		return
	var mat_idx: int = int(data.get("index", -1))
	if mat_idx < 0:
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	var camera = last_3d_camera
	var mouse_pos = position if position != null else last_3d_mouse_pos
	if not camera:
		return
	# Use the same visibility-aware face picker as Select, Extrude, and Paint.
	var hit: Dictionary = root.pick_face(camera, mouse_pos)
	if hit.is_empty():
		if dock:
			dock.show_toast("No face under drop position", 1)
		return
	var brush: DraftBrush = hit.get("brush") as DraftBrush
	var face_idx: int = int(hit.get("face_idx", -1))
	if brush == null or face_idx < 0:
		return
	# Apply material to the hit face via undoable action.
	var brush_key: String = brush.brush_id if brush.brush_id != "" else str(brush.get_instance_id())
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Drop Material on Face",
		"assign_material_to_faces_by_id",
		[brush_key, [face_idx], mat_idx],
		false,
		Callable(self, "_record_history")
	)
	if dock:
		dock._selected_material_index = mat_idx
		if dock.material_browser:
			dock.material_browser.set_selected_index(mat_idx)
		dock.show_toast("Applied material #%d to face" % mat_idx, 0)


# ---------------------------------------------------------------------------
# Context Toolbar + Hotkey Palette handlers
# ---------------------------------------------------------------------------


func _on_context_toolbar_action(action: String, args: Array) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	if not _managed_action_surface_allowed(root, action):
		return
	match action:
		"extrude_up":
			_deactivate_external_tool()
			dock.set_extrude_tool(1)
			_update_hud_context()
		"extrude_down":
			_deactivate_external_tool()
			dock.set_extrude_tool(-1)
			_update_hud_context()
		"hollow":
			_hollow_selected(root)
		"clip":
			_clip_selected(root)
		"carve":
			_carve_selected(root)
		"merge":
			_merge_selected(root)
		"duplicate":
			_duplicate_selected(root)
		"delete":
			_delete_selected(root)
		"justify_fit":
			if dock:
				dock._on_justify("fit")
		"justify_center":
			if dock:
				dock._on_justify("center")
		"justify_left":
			if dock:
				dock._on_justify("left")
		"justify_right":
			if dock:
				dock._on_justify("right")
		"justify_top":
			if dock:
				dock._on_justify("top")
		"justify_bottom":
			if dock:
				dock._on_justify("bottom")
		"apply_to_brush":
			if dock:
				dock._apply_material_to_whole_brush()
		"entity_io":
			if dock:
				dock.main_tabs.current_tab = 2  # Entities tab
		"entity_props":
			if dock:
				dock.main_tabs.current_tab = 2  # Entities tab
		"highlight_connected":
			if root and root.has_method("set_highlight_connected"):
				var pressed: bool = args[0] if not args.is_empty() else false
				root.set_highlight_connected(pressed)
			if dock:
				dock.sync_wiring_highlight_state()
		"shape_box":
			if dock and dock.shape_select:
				dock.shape_select.select(0)
				dock._on_shape_selected(0)
		"shape_cylinder":
			if dock and dock.shape_select:
				dock.shape_select.select(1)
				dock._on_shape_selected(1)
		"shape_sphere":
			if dock and dock.shape_select:
				dock.shape_select.select(2)
				dock._on_shape_selected(2)
		"shape_cone":
			if dock and dock.shape_select:
				dock.shape_select.select(3)
				dock._on_shape_selected(3)
		"axis_x":
			root.set_axis_lock(LevelRootType.AxisLock.X, true)
			_update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
		"axis_y":
			root.set_axis_lock(LevelRootType.AxisLock.Y, true)
			_update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
		"axis_z":
			root.set_axis_lock(LevelRootType.AxisLock.Z, true)
			_update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
		"cancel_drag":
			root.cancel_drag()
			numeric_buffer = ""
			_update_hud_context()
		"vertex_submode":
			if root.vertex_system:
				root.vertex_system.sub_mode = 0  # VERTEX
		"edge_submode":
			if root.vertex_system:
				root.vertex_system.sub_mode = 1  # EDGE
		"vertex_merge":
			if root.vertex_system:
				_vertex_merge_selected(root)
		"vertex_split":
			if root.vertex_system:
				_vertex_split_selected_edge(root)
		"vertex_clip_convex":
			if root.vertex_system:
				_vertex_clip_to_convex(root)
		"vertex_exit":
			_toggle_vertex_mode(root)
		"select_all":
			_select_all_nodes(root)
		"deselect_all":
			_deselect_all_nodes(root)
		"select_similar":
			_select_similar(root)
		"apply_last_texture":
			_apply_last_texture(root)
		"selection_filter":
			_show_selection_filter()
		"quick_save_prefab":
			_quick_save_prefab(root, false)
		"quick_save_linked_prefab":
			_quick_save_prefab(root, true)
		"cycle_variant":
			_cycle_prefab_variant(root)
		"push_to_source":
			_push_prefab_to_source(root)
		"propagate_prefab":
			_propagate_prefab(root)
		"apply_pending_cuts":
			if dock:
				dock._on_apply_cuts()
				_update_hud_context()
		"commit_cuts":
			if dock:
				dock._on_commit_cuts()
				_update_hud_context()
		"clear_pending_cuts":
			if dock:
				dock._on_clear_cuts()
				_update_hud_context()
		"bake_preview_toggle":
			var pressed: bool = args[0] if not args.is_empty() else false
			_toggle_bake_preview(root, pressed)


func _on_context_toggle_operation() -> void:
	if dock:
		if dock.mode_add.button_pressed:
			dock.mode_subtract.button_pressed = true
		else:
			dock.mode_add.button_pressed = true
		_update_hud_context()


func _toggle_paint_mode() -> void:
	if not dock or not dock.paint_mode:
		return
	var root = active_root if active_root else _get_level_root()
	_prepare_tool_transition(root)
	dock.paint_mode.button_pressed = not dock.paint_mode.button_pressed
	dock.show_toast(
		"Paint mode enabled" if dock.paint_mode.button_pressed else "Build mode enabled", 0
	)
	_update_hud_context()


var _bake_preview_active := false
var _bake_preview_in_flight := false


func _on_dock_bake_state_changed(baking: bool, success: bool) -> void:
	if not baking:
		if _bake_preview_in_flight:
			_bake_preview_in_flight = false
			if not success:
				# The preview toggle speculatively set _bake_preview_active
				# before dispatching. Bake failed so baked_container is
				# unchanged — flip the flag back to match the actual scene.
				_bake_preview_active = not _bake_preview_active
			# On success the speculative value is correct — keep it.
		elif success:
			# A non-preview bake replaced baked_container.  Derive the toggle
			# from the actual preview mode that was baked — the dock dropdown
			# may have been set to Wireframe for a normal bake.
			var root = active_root if active_root else _get_level_root()
			if root:
				_bake_preview_active = root._last_bake_preview_mode == 1
			else:
				_bake_preview_active = false
		# Non-preview bake failed: baked_container untouched, keep current flag.
	_update_hud_context()


func _toggle_bake_preview(root: Node, pressed: bool) -> void:
	if not root or not root.bake_system:
		return
	# Guard against overlapping bakes.
	if (
		(dock and dock._bake_disabled)
		or (root.has_method("is_bake_in_flight") and root.call("is_bake_in_flight"))
	):
		_update_hud_context()
		return
	if pressed:
		_bake_preview_active = true
		_bake_preview_in_flight = true
		# Wireframe preview bake — route through undo so it's reversible
		if dock:
			dock._set_bake_buttons_disabled(true)
		var succeeded: bool = await root.bake(false, false, 0, 1)
		if dock:
			dock._set_bake_buttons_disabled(false)
		if _bake_preview_in_flight:
			_bake_preview_in_flight = false
			if not succeeded:
				_bake_preview_active = false
		_update_hud_context()
	else:
		_bake_preview_active = false
		_bake_preview_in_flight = true
		# Re-bake full quality to replace the wireframe preview
		if dock:
			dock._set_bake_buttons_disabled(true)
		var succeeded: bool = await root.bake(false, false, 0, 0)
		if dock:
			dock._set_bake_buttons_disabled(false)
		if _bake_preview_in_flight:
			_bake_preview_in_flight = false
			if not succeeded:
				_bake_preview_active = true
		_update_hud_context()


func _on_context_tool_switch(tool_id: int) -> void:
	var root = active_root if active_root else _get_level_root()
	_prepare_tool_transition(root)
	if dock:
		dock.highlight_tab("Brush")
	_deactivate_external_tool()
	if dock:
		match tool_id:
			0:
				dock.tool_draw.button_pressed = true
			1:
				dock.tool_select.button_pressed = true
			2:
				dock.set_extrude_tool(1)
			3:
				dock.set_extrude_tool(-1)
	_update_hud_context()


func _on_context_material_apply(mat_index: int) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root or not dock:
		return
	if not _managed_action_surface_allowed(root, "apply_context_material"):
		return
	dock._selected_material_index = mat_index
	# Apply to selected faces if any
	var face_count = dock._count_selected_faces()
	if face_count > 0:
		dock._on_face_assign_material()
	else:
		# Apply to all selected brushes
		var mat = root.material_manager.get_material(mat_index) if root.material_manager else null
		if mat:
			for node in hf_selection:
				if node is DraftBrush:
					_paint_brush_with_undo(root, node, mat)


func _on_toggle_hotkey_palette() -> void:
	if _hotkey_palette:
		_hotkey_palette.toggle_visible()
		if _hotkey_palette.visible:
			var root = active_root if active_root else _get_level_root()
			var tool_id = dock.get_tool() if dock else 0
			_update_context_toolbar_state(root, tool_id)


## Actions in this list operate on LevelRoot-owned state or scene content. They
## require an existing level, but must not create one as a side effect of using
## the command palette. Level creation is reserved for explicit setup actions
## and the first intentional Draw press in the viewport.
static func hotkey_palette_action_requires_existing_root(action: String) -> bool:
	return (
		action
		in [
			"quick_play",
			"validate_level",
			"select_all",
			"deselect_all",
			"delete",
			"duplicate",
			"group",
			"ungroup",
			"hollow",
			"clip",
			"carve",
			"merge",
			"move_to_floor",
			"move_to_ceiling",
			"vertex_edit",
			"texture_picker",
			"grid_decrease",
			"grid_increase",
			"vertex_edge_mode",
			"vertex_merge",
			"vertex_split_edge",
			"vertex_clip_convex",
			"axis_x",
			"axis_y",
			"axis_z",
			"select_similar",
			"apply_last_texture",
			"context_menu",
		]
	)


func _on_hotkey_palette_action(action: String) -> void:
	var root = active_root if active_root else _get_level_root()
	if hotkey_palette_action_requires_existing_root(action) and not root:
		if dock:
			dock.show_toast("Create a HammerForge level first", 1)
		return
	if root and not _managed_action_surface_allowed(root, action):
		return
	if (
		root
		and (
			action
			in [
				"tool_draw",
				"tool_select",
				"tool_extrude_up",
				"tool_extrude_down",
				"tool_extrude",
				"tool_extrude_down_alt"
			]
		)
	):
		_prepare_tool_transition(root)
		if dock:
			dock.highlight_tab("Brush")
	match action:
		"toggle_operation":
			_on_context_toggle_operation()
		"toggle_paint_mode":
			_toggle_paint_mode()
		"quick_play":
			if dock:
				dock._on_quick_play()
		"validate_level":
			if dock:
				dock._on_validate_level()
		"tool_draw":
			_deactivate_external_tool()
			if dock and dock.tool_draw:
				dock.tool_draw.button_pressed = true
		"tool_select":
			_deactivate_external_tool()
			if dock and dock.tool_select:
				dock.tool_select.button_pressed = true
		"tool_extrude_up", "tool_extrude":
			_deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(1)
		"tool_extrude_down", "tool_extrude_down_alt":
			_deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(-1)
		"select_all":
			_select_all_nodes(root)
		"deselect_all":
			_deselect_all_nodes(root)
		"delete":
			_delete_selected(root)
		"duplicate":
			_duplicate_selected(root)
		"group":
			_group_selected(root)
		"ungroup":
			_ungroup_selected(root)
		"hollow":
			_hollow_selected(root)
		"clip":
			_clip_selected(root)
		"carve":
			_carve_selected(root)
		"merge":
			_merge_selected(root)
		"move_to_floor":
			_move_selected_to_floor(root)
		"move_to_ceiling":
			_move_selected_to_ceiling(root)
		"vertex_edit":
			_toggle_vertex_mode(root)
		"texture_picker":
			_texture_picker_active = true
			if dock:
				dock.show_toast("Texture Picker: click a face to sample its material", 0)
		"paint_bucket":
			if dock:
				dock.set_paint_tool(0)  # B key = Paint Brush tool
		"paint_erase":
			if dock:
				dock.set_paint_tool(1)
		"paint_ramp":
			if dock:
				dock.set_paint_tool(2)
		"paint_line":
			if dock:
				dock.set_paint_tool(3)
		"paint_fill":
			if dock:
				dock.set_paint_tool(4)
		"paint_blend":
			if dock:
				dock.set_paint_tool(5)
		"grid_decrease":
			_adjust_grid_snap(root, 0.5)
		"grid_increase":
			_adjust_grid_snap(root, 2.0)
		"vertex_edge_mode":
			if root.vertex_system:
				var current: int = root.vertex_system.sub_mode
				root.vertex_system.sub_mode = 1 if current == 0 else 0
		"vertex_merge":
			if root.vertex_system:
				_vertex_merge_selected(root)
		"vertex_split_edge":
			if root.vertex_system:
				_vertex_split_selected_edge(root)
		"vertex_clip_convex":
			if root.vertex_system:
				_vertex_clip_to_convex(root)
		"axis_x":
			root.set_axis_lock(LevelRootType.AxisLock.X, true)
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
		"axis_y":
			root.set_axis_lock(LevelRootType.AxisLock.Y, true)
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
		"axis_z":
			root.set_axis_lock(LevelRootType.AxisLock.Z, true)
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
		"select_all":
			_select_all_nodes(root)
		"deselect_all":
			_deselect_all_nodes(root)
		"select_similar":
			_select_similar(root)
		"apply_last_texture":
			_apply_last_texture(root)
		"selection_filter":
			_show_selection_filter()
		"context_menu":
			var tool_id_now: int = dock.get_tool() if dock else 0
			_show_viewport_context_menu(root, tool_id_now)
		"radial_menu":
			if _radial_menu and is_instance_valid(_radial_menu):
				if _radial_menu.is_active():
					_radial_menu.hide_menu()
				else:
					_radial_menu.show_at(_get_current_overlay_mouse_pos())
	_show_coach_mark_for_action(action)
	_update_hud_context()


## Unified action dispatch for viewport context menu and radial menu.
## Routes actions to the same handlers used by context toolbar and hotkey palette.
func _dispatch_viewport_action(action: String, args: Array = []) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	if not _managed_action_surface_allowed(root, action):
		return
	if (
		action
		in [
			"tool_draw",
			"tool_select",
			"extrude_up",
			"extrude_down",
			"tool_extrude_up",
			"tool_extrude_down",
			"tool_extrude",
			"tool_extrude_down_alt"
		]
	):
		_prepare_tool_transition(root)
		if dock:
			dock.highlight_tab("Brush")
	match action:
		# Tool switching
		"tool_draw":
			_deactivate_external_tool()
			if dock and dock.tool_draw:
				dock.tool_draw.button_pressed = true
		"tool_select":
			_deactivate_external_tool()
			if dock and dock.tool_select:
				dock.tool_select.button_pressed = true
		"extrude_up", "tool_extrude_up", "tool_extrude":
			_deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(1)
		"extrude_down", "tool_extrude_down", "tool_extrude_down_alt":
			_deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(-1)
		# Editing operations
		"hollow":
			_hollow_selected(root)
		"clip":
			_clip_selected(root)
		"carve":
			_carve_selected(root)
		"merge":
			_merge_selected(root)
		"duplicate":
			_duplicate_selected(root)
		"delete":
			_delete_selected(root)
		"group":
			_group_selected(root)
		"ungroup":
			_ungroup_selected(root)
		"move_to_floor":
			_move_selected_to_floor(root)
		"move_to_ceiling":
			_move_selected_to_ceiling(root)
		# Shapes
		"shape_box":
			if dock and dock.shape_select:
				dock.shape_select.select(0)
				dock._on_shape_selected(0)
		"shape_cylinder":
			if dock and dock.shape_select:
				dock.shape_select.select(1)
				dock._on_shape_selected(1)
		"shape_sphere":
			if dock and dock.shape_select:
				dock.shape_select.select(2)
				dock._on_shape_selected(2)
		"shape_cone":
			if dock and dock.shape_select:
				dock.shape_select.select(3)
				dock._on_shape_selected(3)
		# UV/Material
		"justify_fit":
			if dock:
				dock._on_justify("fit")
		"justify_center":
			if dock:
				dock._on_justify("center")
		"justify_left":
			if dock:
				dock._on_justify("left")
		"justify_right":
			if dock:
				dock._on_justify("right")
		"justify_top":
			if dock:
				dock._on_justify("top")
		"justify_bottom":
			if dock:
				dock._on_justify("bottom")
		"apply_to_brush":
			if dock:
				dock._apply_material_to_whole_brush()
		"apply_last_texture":
			_apply_last_texture(root)
		# Entity
		"entity_io":
			if dock:
				dock.main_tabs.current_tab = 2
		"entity_props":
			if dock:
				dock.main_tabs.current_tab = 2
		"highlight_connected":
			if root and root.has_method("set_highlight_connected"):
				var pressed: bool = args[0] if not args.is_empty() else false
				root.set_highlight_connected(pressed)
			if dock:
				dock.sync_wiring_highlight_state()
		# Axis lock
		"axis_x":
			root.set_axis_lock(LevelRootType.AxisLock.X, true)
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
		"axis_y":
			root.set_axis_lock(LevelRootType.AxisLock.Y, true)
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
		"axis_z":
			root.set_axis_lock(LevelRootType.AxisLock.Z, true)
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
		# Vertex
		"vertex_edit":
			_toggle_vertex_mode(root)
		"vertex_submode":
			if root.vertex_system:
				root.vertex_system.sub_mode = 0
		"edge_submode":
			if root.vertex_system:
				root.vertex_system.sub_mode = 1
		"vertex_merge":
			if root.vertex_system:
				_vertex_merge_selected(root)
		"vertex_split":
			if root.vertex_system:
				_vertex_split_selected_edge(root)
		"vertex_clip_convex":
			if root.vertex_system:
				_vertex_clip_to_convex(root)
		"vertex_exit":
			_toggle_vertex_mode(root)
		# Selection
		"select_all":
			_select_all_nodes(root)
		"deselect_all":
			_deselect_all_nodes(root)
		"select_similar":
			_select_similar(root)
		"selection_filter":
			_show_selection_filter()
		# Prefab
		"quick_save_prefab":
			_quick_save_prefab(root, false)
		"quick_save_linked_prefab":
			_quick_save_prefab(root, true)
		"cycle_variant":
			_cycle_prefab_variant(root)
		"push_to_source":
			_push_prefab_to_source(root)
		"propagate_prefab":
			_propagate_prefab(root)
		# Texture picker
		"texture_picker":
			_texture_picker_active = true
			if dock:
				dock.show_toast("Texture Picker: click a face to sample its material", 0)
		# Paint
		"surface_paint":
			if dock and dock.paint_mode:
				dock.paint_mode.button_pressed = true
		# Misc
		"toggle_grid":
			if dock and dock.show_grid:
				dock.show_grid.button_pressed = not dock.show_grid.button_pressed
		"quick_bake":
			if dock:
				dock._on_bake()
		"undo":
			if undo_redo_manager:
				undo_redo_manager.undo()
		"redo":
			if undo_redo_manager:
				undo_redo_manager.redo()
		# Grid snap
		"set_grid_snap":
			if dock and not args.is_empty():
				dock._apply_grid_snap(float(args[0]))
		# Measure
		"measure":
			if _tool_registry and active_root:
				_activate_external_tool(100, active_root)
		"cancel_drag":
			root.cancel_drag()
			numeric_buffer = ""
	_show_coach_mark_for_action(action)
	_update_hud_context()


func _on_viewport_action(action: String, args: Array) -> void:
	_dispatch_viewport_action(action, args)


func _on_radial_action(action: String) -> void:
	_dispatch_viewport_action(action)


## Double-tap handler for quick property popups.
func _handle_double_tap(keycode: int, root: Node, paint_mode: bool) -> bool:
	match keycode:
		KEY_G:
			var snap_val: float = root.grid_snap if root else 16.0
			_show_quick_property_at_cursor(HFQuickProperty.PropertyType.GRID_SNAP, [snap_val])
			return true
		KEY_B:
			if paint_mode:
				return false  # Let paint_bucket handle it
			var sz: Vector3 = (
				root.input_state.drag_size_default
				if root and root.input_state
				else Vector3(4, 4, 4)
			)
			_show_quick_property_at_cursor(
				HFQuickProperty.PropertyType.BRUSH_SIZE, [sz.x, sz.y, sz.z]
			)
			return true
		KEY_R:
			if paint_mode:
				var radius: float = dock.get_surface_paint_radius() if dock else 5.0
				_show_quick_property_at_cursor(HFQuickProperty.PropertyType.PAINT_RADIUS, [radius])
				return true
	return false


func _show_quick_property_at_cursor(prop_type: int, values: Array) -> void:
	if not _quick_property or not is_instance_valid(_quick_property):
		return
	_quick_property.show_property(prop_type, _get_current_overlay_mouse_pos(), values)


func _on_quick_property_committed(property_type: int, values: Array) -> void:
	var root = active_root if active_root else _get_level_root()
	match property_type:
		HFQuickProperty.PropertyType.GRID_SNAP:
			if dock and not values.is_empty():
				dock._apply_grid_snap(float(values[0]))
		HFQuickProperty.PropertyType.BRUSH_SIZE:
			if root and root.input_state and values.size() >= 3:
				root.input_state.drag_size_default = Vector3(values[0], values[1], values[2])
				if dock:
					dock.size_x.value = values[0]
					dock.size_y.value = values[1]
					dock.size_z.value = values[2]
		HFQuickProperty.PropertyType.PAINT_RADIUS:
			if dock and not values.is_empty():
				if dock.surface_paint_radius:
					dock.surface_paint_radius.value = float(values[0])


func _show_coach_mark_for_action(action: String) -> void:
	if not _coach_marks or not is_instance_valid(_coach_marks):
		return
	# Map action names to coach mark tool keys
	var coach_key := ""
	match action:
		"vertex_edit":
			coach_key = "vertex_edit"
		"hollow":
			coach_key = "hollow"
		"clip":
			coach_key = "clip"
		"carve":
			coach_key = "carve"
		"tool_extrude_up", "tool_extrude_down", "tool_extrude", "tool_extrude_down_alt":
			coach_key = "extrude"
		"paint_bucket", "paint_erase", "paint_ramp", "paint_line", "paint_fill", "paint_blend":
			coach_key = "surface_paint"
	if not coach_key.is_empty():
		_coach_marks.show_guide(coach_key)


func _show_coach_mark_for_tool_id(tool_id: int) -> void:
	if not _coach_marks or not is_instance_valid(_coach_marks):
		return
	if not _tool_registry:
		return
	var tool_obj = _tool_registry.get_tool_by_id(tool_id)
	if not tool_obj:
		return
	var tool_name: String = tool_obj.tool_name().to_lower()
	# Map tool names to coach mark keys
	if "polygon" in tool_name:
		_coach_marks.show_guide("polygon")
	elif "path" in tool_name:
		_coach_marks.show_guide("path")
	elif "measure" in tool_name:
		_coach_marks.show_guide("measure")
	elif "decal" in tool_name:
		_coach_marks.show_guide("decal")


func _on_coach_mark_dismissed(_tool_key: String, _dont_show: bool) -> void:
	pass  # Persistence is handled internally by HFCoachMarks


func _on_undo_redo_version_changed() -> void:
	## Cancel any in-flight *transient* tool preview (drag, extrude) when the
	## undo/redo version changes.  Without this, preview MeshInstance3D nodes
	## created mid-operation become orphaned because the scene state they
	## reference no longer matches.
	##
	## VERTEX_EDIT is a persistent mode — commit_action() fires
	## version_changed after every merge/split/move, so resetting it here
	## would desynchronize the plugin's _vertex_mode flag from input_state.
	var root: LevelRoot = active_root if active_root else _get_level_root()
	if not root or not is_instance_valid(root):
		return
	# Native Inspector/gizmo commits and their Undo/Redo are owned by Godot, so
	# reconcile their final brush signature after the editor finishes the action.
	_queue_managed_brush_reconcile()
	if root.drag_system and root.drag_system.input_state:
		var ist: HFInputStateType = root.drag_system.input_state
		# Only reset transient preview modes that own temporary scene nodes.
		# VERTEX_EDIT and IDLE are left alone — see HFInputState.is_transient_preview_mode().
		if HFInputStateType.is_transient_preview_mode(ist.mode):
			ist._force_reset()
	# Subtract preview may reference stale brush data — rebuild
	if root.subtract_preview and root.subtract_preview.is_enabled():
		root.subtract_preview.request_update()
	# Sync preview toggle with the restored scene state.  Skip if a preview
	# bake is in flight — that version_changed came from our own commit, not
	# from the user pressing Ctrl+Z.
	if not _bake_preview_in_flight:
		var restored_preview: bool = root._last_bake_preview_mode == 1  # WIREFRAME only
		if _bake_preview_active != restored_preview:
			_bake_preview_active = restored_preview
			_update_hud_context()


func _on_replay_requested(entry_index: int) -> void:
	if not _operation_replay or not is_instance_valid(_operation_replay):
		return
	var target_version: int = _operation_replay.get_entry_version(entry_index)
	if target_version < 0:
		if dock:
			dock.show_toast("Replay: no undo version recorded for this operation", 1)
		return
	if not undo_redo_manager or not active_root:
		if dock:
			dock.show_toast("Replay: no undo history available", 1)
		return
	var history_id: int = undo_redo_manager.get_object_history_id(active_root)
	var ur: UndoRedo = undo_redo_manager.get_history_undo_redo(history_id)
	if not ur:
		if dock:
			dock.show_toast("Replay: no undo history available", 1)
		return
	var current_version: int = ur.get_version()
	if target_version == current_version:
		if dock:
			dock.show_toast("Already at this operation", 0)
		return
	# Undo or redo to reach the target version
	var steps := 0
	if target_version < current_version:
		while ur.get_version() > target_version and ur.has_undo():
			ur.undo()
			steps += 1
		if dock:
			dock.show_toast("Replay: undid %d step%s" % [steps, "" if steps == 1 else "s"], 0)
	else:
		while ur.get_version() < target_version and ur.has_redo():
			ur.redo()
			steps += 1
		if dock:
			dock.show_toast("Replay: redid %d step%s" % [steps, "" if steps == 1 else "s"], 0)


func _get_level_root() -> Node:
	var scene = get_editor_interface().get_edited_scene_root()
	if scene:
		if scene.get_script() == LevelRootType or scene.name == "LevelRoot":
			return scene
		# Check direct child (fast path)
		var node = scene.get_node_or_null("LevelRoot")
		if node:
			return node
		# Deep search — find any LevelRoot anywhere in the scene tree
		var found = _find_level_root_deep(scene)
		if found:
			return found
	var current = get_tree().get_current_scene()
	if current:
		var node = current.get_node_or_null("LevelRoot")
		if node:
			return node
		return _find_level_root_deep(current)
	return null


func _find_level_root_deep(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() == LevelRootType or child is LevelRoot:
			return child
		var found = _find_level_root_deep(child)
		if found:
			return found
	return null


func _get_level_root_from_node(node: Node) -> Node:
	var current: Node = node
	while current:
		if current.get_script() == LevelRootType or current.name == "LevelRoot":
			return current
		current = current.get_parent()
	return null


## Return the current LevelRoot, creating one in the edited scene when needed.
## This is the public, dock-safe path for explicit empty-state actions.
func ensure_level_root() -> Node:
	var root = active_root if active_root else _get_level_root()
	if root:
		return root
	return _create_level_root()


func _create_level_root() -> Node:
	var scene = get_editor_interface().get_edited_scene_root()
	if not scene:
		return null
	var root = LevelRootType.new()
	root.name = "LevelRoot"
	if undo_redo_manager:
		undo_redo_manager.create_action("Create HammerForge Level")
		undo_redo_manager.add_do_method(scene, "add_child", root)
		undo_redo_manager.add_do_method(root, "set_owner", scene)
		undo_redo_manager.add_do_method(self, "_activate_created_level_root", root)
		undo_redo_manager.add_do_reference(root)
		undo_redo_manager.add_undo_method(self, "_deactivate_created_level_root", root)
		undo_redo_manager.add_undo_method(scene, "remove_child", root)
		undo_redo_manager.commit_action()
	else:
		scene.add_child(root)
		root.owner = scene
		_activate_created_level_root(root)
	return root


func _activate_created_level_root(root: Node) -> void:
	active_root = root
	_ensure_brush_change_tracker().prime(root)
	var selection = get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(root)
	hf_selection.clear()
	hf_selection.append(root)


func _deactivate_created_level_root(root: Node) -> void:
	if active_root == root:
		active_root = null
		_ensure_brush_change_tracker().reset()
	hf_selection.erase(root)
	var selection = get_editor_interface().get_selection()
	if selection and root in selection.get_selected_nodes():
		selection.remove_node(root)
