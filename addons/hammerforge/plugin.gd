@tool
extends EditorPlugin

const DockType = preload("dock.gd")
const HFPluginCommands = preload("plugin_commands.gd")
const HFPluginDropHandler = preload("plugin_drop_handler.gd")
const HFPluginEditActions = preload("plugin_edit_actions.gd")
const HFPluginInputRouter = preload("plugin_input_router.gd")
const HFPluginNumericInput = preload("plugin_numeric_input.gd")
const HFPluginVertexInput = preload("plugin_vertex_input.gd")
const HFPluginVertexOps = preload("plugin_vertex_ops.gd")
const HFPluginHud = preload("plugin_hud.gd")
const HFPluginViewportInput = preload("plugin_viewport_input.gd")
const HFPluginOverlays = preload("plugin_overlays.gd")
const HFPluginPaintInput = preload("plugin_paint_input.gd")
const HFPluginPointerTools = preload("plugin_pointer_tools.gd")
const HFPluginPrefabCommands = preload("plugin_prefab_commands.gd")
const HFPluginSelectionInput = preload("plugin_selection_input.gd")
const HFPluginSelectionCommands = preload("plugin_selection_commands.gd")
const HFPluginSelectionState = preload("plugin_selection_state.gd")
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
var _rmb_camera_navigation := HFPluginViewportInput.RmbCameraNavigationSession.new()
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
const HFViewportContextMenu = preload("ui/hf_viewport_context_menu.gd")
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
	HFPluginHud.update_hud_context(self)


func _update_context_toolbar_state(root: Node, tool_id: int) -> void:
	HFPluginHud.update_context_toolbar_state(self, root, tool_id)


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
	HFPluginOverlays.install_power_user_overlays(self)


func _teardown_power_user_overlays() -> void:
	HFPluginOverlays.teardown_power_user_overlays(self)


func _on_editor_selection_changed() -> void:
	HFPluginSelectionState.on_editor_selection_changed(self)


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
	return HFPluginViewportInput.should_create_root(event, tool_id, paint_mode)


## Clicking outside a quick-property editor protects against accidental LMB
## edits. RMB continues to the active gesture owner; other navigation passes.
static func classify_quick_property_dismiss(event: InputEventMouseButton) -> int:
	return HFPluginViewportInput.classify_quick_property_dismiss(event)


## A live LMB paint stroke keeps pointer ownership until LMB release. Starting
## native camera look midway through the stroke would paint while the view moves.
static func should_block_rmb_during_paint_stroke(
	surface_painting: bool,
	floor_painting: bool,
	displacement_painting: bool,
	left_button_held: bool
) -> bool:
	return HFPluginViewportInput.should_block_rmb_during_paint_stroke(
		surface_painting, floor_painting, displacement_painting, left_button_held
	)


static func is_lmb_release_recovery_motion(event: InputEvent) -> bool:
	return HFPluginViewportInput.is_lmb_release_recovery_motion(event)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return HFPluginViewportInput.handle(self, camera, event)


func _should_start_disp_paint(event: InputEvent, root: Node) -> bool:
	return HFPluginPaintInput.should_start_displacement(self, event, root)


func _handle_disp_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	return HFPluginPaintInput.handle_displacement(self, event, root, cam, pos)


func _commit_disp_paint_undo(root: Node) -> void:
	HFPluginPaintInput.commit_displacement_undo(self, root)


func _do_disp_paint_stroke(root: Node, cam: Camera3D, pos: Vector2) -> void:
	HFPluginPaintInput.do_displacement_stroke(self, root, cam, pos)


func _point_near_polygon_3d(
	point: Vector3, verts: PackedVector3Array, normal: Vector3, margin: float
) -> bool:
	return HFPluginPaintInput.point_near_polygon_3d(point, verts, normal, margin)


func _handle_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	return HFPluginPaintInput.handle_paint(self, event, root, cam, pos)


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
	return HFPluginNumericInput.handle(self, event, root)


func _update_numeric_preview(root: Node) -> void:
	HFPluginNumericInput.update_preview(self, root)


func _apply_numeric_value(root: Node) -> void:
	HFPluginNumericInput.apply_value(self, root)


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
	return HFPluginInputRouter.handle_keyboard(self, event, root, tool_id, paint_mode)


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
	return HFPluginSelectionInput.handle_press(self, event, root, cam, pos, paint_mode)


static func custom_selection_release_result(face_selection: bool) -> int:
	return HFPluginSelectionInput.custom_release_result(face_selection)


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
	return HFPluginSelectionInput.handle_active(self, event, root, cam, pos)


func _handle_extrude_mouse(
	event: InputEventMouseButton, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	return HFPluginPointerTools.handle_extrude(self, event, root, cam, pos)


func _handle_draw_mouse(
	event: InputEventMouseButton, root: Node, cam: Camera3D, pos: Vector2
) -> int:
	return HFPluginPointerTools.handle_draw(self, event, root, cam, pos)


func _handle_mouse_motion(
	event: InputEventMouseMotion,
	root: Node,
	cam: Camera3D,
	pos: Vector2,
	tool_id: int,
) -> int:
	return HFPluginPointerTools.handle_motion(self, event, root, cam, pos, tool_id)


func _update_prefab_hover_overlay(root, cam: Camera3D, pos: Vector2) -> void:
	HFPluginPointerTools.update_prefab_hover(root, cam, pos)


# ---------------------------------------------------------------------------
# Vertex editing mode
# ---------------------------------------------------------------------------


func _toggle_vertex_mode(root: Node) -> void:
	HFPluginVertexOps.toggle_mode(self, root)


func _vertex_merge_selected(root: Node) -> void:
	HFPluginVertexOps.merge_selected(root)


func _vertex_split_selected_edge(root: Node) -> void:
	HFPluginVertexOps.split_selected_edge(root)


func _vertex_clip_to_convex(root: Node) -> void:
	HFPluginVertexOps.clip_to_convex(root)


func _handle_vertex_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	return HFPluginVertexInput.handle(self, event, root, cam, pos)


func _commit_vertex_op(root: Node, pre_op_snapshots: Dictionary, action_name: String) -> void:
	HFPluginVertexOps.commit_op(self, root, pre_op_snapshots, action_name)


func _commit_vertex_move(root: Node, pre_drag_snapshots: Dictionary) -> void:
	HFPluginVertexOps.commit_move(self, root, pre_drag_snapshots)


func _update_vertex_overlay(root: Node, _cam: Camera3D) -> void:
	HFPluginOverlays.update_vertex_overlay(self, root)


func _ensure_vertex_overlay(root: Node) -> void:
	HFPluginOverlays.ensure_vertex_overlay(self, root)


func _clear_vertex_overlay() -> void:
	HFPluginOverlays.clear_vertex_overlay(self)


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
	HFPluginSelectionState.finalize_native_selection(self, selection_before, additive, toggle)


func _normalize_editor_selection(nodes: Array, root: Node) -> Array:
	return HFPluginSelectionState.normalize_editor_selection(self, nodes, root)


func _hammerforge_selection_owner(node: Node, root: Node) -> Node:
	return HFPluginSelectionState.normalize_managed_selection_owner(node, root)


static func normalize_managed_selection_owner(node: Node, root: Node) -> Node:
	return HFPluginSelectionState.normalize_managed_selection_owner(node, root)


func _expand_native_group_selection(
	root: Node, selection_before: Array, current_selection: Array, toggle: bool
) -> Array:
	return HFPluginSelectionState.expand_native_group_selection(
		root, selection_before, current_selection, toggle
	)


static func expand_native_group_members(
	selection_before: Array, current_selection: Array, toggle: bool, groups: Dictionary
) -> Array:
	return HFPluginSelectionState.expand_native_group_members(
		selection_before, current_selection, toggle, groups
	)


static func _same_node_selection(first: Array, second: Array) -> bool:
	return HFPluginSelectionState.same_node_selection(first, second)


func _apply_selection_list(nodes: Array, additive: bool, toggle: bool = false) -> void:
	HFPluginSelectionState.apply_selection_list(self, nodes, additive, toggle)


func _apply_hf_selection(selection: EditorSelection) -> void:
	HFPluginSelectionState.apply_hf_selection(self, selection)


func _sync_hf_selection_if_empty() -> void:
	HFPluginSelectionState.sync_hf_selection_if_empty(self)


func _selection_has_brush(nodes: Array, root: Node) -> bool:
	return HFPluginSelectionState.selection_has_brush(nodes, root)


func _selection_has_entity(nodes: Array, root: Node) -> bool:
	return HFPluginSelectionState.selection_has_entity(nodes, root)


static func classify_selection_scope(nodes: Array, root: Node) -> int:
	return HFPluginSelectionState.classify_selection_scope(nodes, root)


func _guard_hammerforge_shortcut(
	root: Node, brushes_only: bool, minimum_count: int, action_label: String
) -> int:
	return HFPluginSelectionState.guard_hammerforge_shortcut(
		self, root, brushes_only, minimum_count, action_label
	)


static func managed_surface_action_requirement(action: String) -> Dictionary:
	return HFPluginSelectionState.managed_surface_action_requirement(action)


func _managed_action_surface_allowed(root: Node, action: String) -> bool:
	return HFPluginSelectionState.managed_action_surface_allowed(self, root, action)


func _hammerforge_selection_nodes(root: Node, brushes_only: bool = false) -> Array:
	return HFPluginSelectionState.hammerforge_selection_nodes(self, root, brushes_only)


func _managed_entity_owner(root: Node, node: Node) -> Node:
	return HFPluginSelectionState.managed_entity_owner(root, node)


func _current_selection_nodes() -> Array:
	return HFPluginSelectionState.current_selection_nodes(self)


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
	HFPluginSelectionInput.select_faces_in_rect(self, root, camera, from, to, additive, toggle)


func _face_screen_center(camera: Camera3D, brush: DraftBrush, face) -> Vector2:
	return HFPluginSelectionInput.face_screen_center(camera, brush, face)


func _face_key_for(brush: DraftBrush) -> String:
	return HFPluginSelectionCommands.face_key_for(brush)


func _apply_face_selection(root: Node, face_sel: Dictionary) -> void:
	HFPluginSelectionCommands.apply_face_selection(self, root, face_sel)


# ---------------------------------------------------------------------------
# Apply Last Texture
# ---------------------------------------------------------------------------


func _apply_last_texture(root: Node) -> void:
	HFPluginSelectionCommands.apply_last_texture(self, root)


# ---------------------------------------------------------------------------
# Select All / Deselect All
# ---------------------------------------------------------------------------


func _select_all_nodes(root: Node) -> void:
	HFPluginSelectionCommands.select_all(self, root)


func _deselect_all_nodes(root: Node) -> void:
	HFPluginSelectionCommands.deselect_all(self, root)


# ---------------------------------------------------------------------------
# Select Similar
# ---------------------------------------------------------------------------


func _select_similar(root: Node) -> void:
	HFPluginSelectionCommands.select_similar(self, root)


func _size_similar(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return HFPluginSelectionCommands.size_similar(a, b, tolerance)


# ---------------------------------------------------------------------------
# Selection Filter popup
# ---------------------------------------------------------------------------


func _show_selection_filter() -> void:
	HFPluginSelectionCommands.show_selection_filter(self)


func _on_selection_filter_applied(nodes: Array, faces: Dictionary) -> void:
	HFPluginSelectionCommands.on_filter_applied(self, nodes, faces)


# ---------------------------------------------------------------------------
# Marquee overlay
# ---------------------------------------------------------------------------


func _update_marquee_overlay(from: Vector2, to: Vector2, active: bool) -> void:
	HFPluginOverlays.update_marquee_overlay(self, from, to, active)


## Draw through Godot's real 3D overlay so viewport-local event coordinates
## remain correct under split views, editor scaling, and dock rearrangement.
func _forward_3d_force_draw_over_viewport(viewport_control: Control) -> void:
	HFPluginOverlays.draw_marquee_overlay(self, viewport_control)


func _add_confirmable_dialog(dlg: ConfirmationDialog) -> void:
	if _dialog_manager:
		_dialog_manager.add(dlg, get_editor_interface().get_base_control())


func _cleanup_pending_dialogs() -> void:
	if _dialog_manager:
		_dialog_manager.cleanup()


func _delete_selected(root: Node) -> bool:
	return HFPluginEditActions.delete_selected(self, root)


func _duplicate_selected(root: Node) -> bool:
	return HFPluginEditActions.duplicate_selected(self, root)


func _nudge_selected(root: Node, dir: Vector3) -> bool:
	return HFPluginEditActions.nudge_selected(self, root, dir)


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
	return HFPluginEditActions.group_selected(self, root)


func _ungroup_selected(root: Node) -> bool:
	return HFPluginEditActions.ungroup_selected(self, root)


func _hollow_selected(root: Node) -> bool:
	return HFPluginEditActions.hollow_selected(self, root)


func _merge_selected(root: Node) -> bool:
	return HFPluginEditActions.merge_selected(self, root)


func _move_selected_to_floor(root: Node) -> bool:
	return HFPluginEditActions.move_selected_to_floor(self, root)


func _move_selected_to_ceiling(root: Node) -> bool:
	return HFPluginEditActions.move_selected_to_ceiling(self, root)


func _move_selected_vertical(root: Node, action_name: String, method_name: String) -> bool:
	return HFPluginEditActions.move_selected_vertical(self, root, action_name, method_name)


func _clip_selected(root: Node) -> bool:
	return HFPluginEditActions.clip_selected(self, root)


func _carve_selected(root: Node) -> bool:
	return HFPluginEditActions.carve_selected(self, root)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return HFPluginDropHandler.can_drop_data(data)


func _drop_data(position: Vector2, data: Variant) -> void:
	HFPluginDropHandler.drop_data(self, position, data)


func _is_entity_drag_data(data: Variant) -> bool:
	return HFPluginDropHandler.is_entity_drag_data(data)


func _handle_entity_drop(position: Vector2, data: Variant) -> void:
	HFPluginDropHandler.handle_entity_drop(self, position, data)


func _is_brush_preset_drag_data(data: Variant) -> bool:
	return HFPluginDropHandler.is_brush_preset_drag_data(data)


func _handle_brush_preset_drop(position: Vector2, data: Variant) -> void:
	HFPluginDropHandler.handle_brush_preset_drop(self, position, data)


func _is_prefab_drag_data(data: Variant) -> bool:
	return HFPluginDropHandler.is_prefab_drag_data(data)


func _handle_prefab_drop(position: Vector2, data: Variant) -> void:
	HFPluginDropHandler.handle_prefab_drop(self, position, data)


# ---------------------------------------------------------------------------
# Prefab enhancement helpers
# ---------------------------------------------------------------------------


func _quick_save_prefab(root, linked: bool) -> void:
	HFPluginPrefabCommands.quick_save(self, root, linked)


func _cycle_prefab_variant(root) -> void:
	HFPluginPrefabCommands.cycle_variant(self, root)


func _push_prefab_to_source(root) -> void:
	HFPluginPrefabCommands.push_to_source(self, root)


func _propagate_prefab(root) -> void:
	HFPluginPrefabCommands.propagate(self, root)


func _is_material_drag_data(data: Variant) -> bool:
	return HFPluginDropHandler.is_material_drag_data(data)


func _handle_material_drop(position: Vector2, data: Variant) -> void:
	HFPluginDropHandler.handle_material_drop(self, position, data)


# ---------------------------------------------------------------------------
# Context Toolbar + Hotkey Palette handlers
# ---------------------------------------------------------------------------


func _on_context_toolbar_action(action: String, args: Array) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	if not _managed_action_surface_allowed(root, action):
		return
	HFPluginCommands.execute(self, action, args)


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
	HFPluginCommands.execute(self, action)


## Unified action dispatch for viewport context menu and radial menu.
## Routes actions to the same handlers used by context toolbar and hotkey palette.
func _dispatch_viewport_action(action: String, args: Array = []) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	if not _managed_action_surface_allowed(root, action):
		return
	HFPluginCommands.execute(self, action, args)


func _on_viewport_action(action: String, args: Array) -> void:
	_dispatch_viewport_action(action, args)


func _on_radial_action(action: String) -> void:
	_dispatch_viewport_action(action)


## Double-tap handler for quick property popups.
func _handle_double_tap(keycode: int, root: Node, paint_mode: bool) -> bool:
	return HFPluginOverlays.handle_double_tap(self, keycode, root, paint_mode)


func _show_quick_property_at_cursor(prop_type: int, values: Array) -> void:
	HFPluginOverlays.show_quick_property(self, prop_type, values)


func _on_quick_property_committed(property_type: int, values: Array) -> void:
	HFPluginOverlays.on_quick_property_committed(self, property_type, values)


func _show_coach_mark_for_action(action: String) -> void:
	HFPluginOverlays.show_coach_mark_for_action(self, action)


func _show_coach_mark_for_tool_id(tool_id: int) -> void:
	HFPluginOverlays.show_coach_mark_for_tool_id(self, tool_id)


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
