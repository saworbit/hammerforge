@tool
extends EditorPlugin

const DockType = preload("dock.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFPluginBakePreview = preload("plugin_bake_preview.gd")
const HFPluginCommands = preload("plugin_commands.gd")
const HFPluginConsoleType = preload("plugin_console.gd")
const HFPluginCommandLineType = preload("plugin_command_line.gd")
const HFPluginMcpType = preload("plugin_mcp.gd")
const HFPluginCompareType = preload("plugin_compare.gd")
const HFPluginAdjustLastType = preload("plugin_adjust_last.gd")
const HFPluginRunType = preload("plugin_run.gd")
const HFPluginCrashJournalType = preload("plugin_crash_journal.gd")
const HFPluginDropHandler = preload("plugin_drop_handler.gd")
const HFPluginEditActions = preload("plugin_edit_actions.gd")
const HFViewAxes = preload("hf_view_axes.gd")
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
const HFPluginShortcuts = preload("plugin_shortcuts.gd")
const HFPluginSnapFeedback = preload("plugin_snap_feedback.gd")
const HFPluginGestureRecovery = preload("plugin_gesture_recovery.gd")
const HFPluginMaterialCommands = preload("plugin_material_commands.gd")
const HFPluginToolModes = preload("plugin_tool_modes.gd")
const HFPluginTransformTools = preload("plugin_transform_tools.gd")
const HFPluginUndoEvents = preload("plugin_undo_events.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFPathToolType = preload("hf_path_tool.gd")
const HFAutosaveSchedulerType = preload("systems/hf_autosave_scheduler.gd")
const HFPluginUpdateCheckType = preload("plugin_update_check.gd")
const HFClipToolType = preload("hf_clip_tool.gd")
const HFHullToolType = preload("hf_hull_tool.gd")
const HFShearToolType = preload("hf_shear_tool.gd")
const HFSelectionGestureType = preload("hf_selection_gesture.gd")
const HFBrushChangeTrackerType = preload("hf_brush_change_tracker.gd")
const HFFaceSelectionOverlayType = preload("hf_face_selection_overlay.gd")
const HFPivotMarkerType = preload("hf_pivot_marker.gd")
const HFSelectionReadoutType = preload("hf_selection_readout.gd")
const HFTextureGizmoType = preload("hf_texture_gizmo.gd")
const HFPluginBrushStampType = preload("plugin_brush_stamp.gd")
var dock: DockType
## The Console main screen and the lamp that opens it from the 3D toolbar.
## Optional surface: if the editor refuses either, the rest of the plugin
## carries on without them.
var console_panel: Control = null
var console_strip: Control = null
## The MCP bridge: the dispatcher for the editor session, and the listener while
## the Test tab's Agent Bridge box is ticked. See plugin_mcp.gd.
var mcp_dispatcher: RefCounted = null
var mcp_listener: Node = null
## What this session did, on disk until a clean close (#1654).
var crash_journal: RefCounted = null
var hud: Control
var base_control: Control
var active_root: LevelRoot = null
var undo_redo_manager: Object = null
var brush_gizmo_plugin: EditorNode3DGizmoPlugin = null
var hf_selection: Array = []
## The scene the "no level here" hint was last shown for, so it shows once each.
var _no_level_hint_scene_id := 0
var _selection_gesture := HFSelectionGestureType.new()
var _brush_change_tracker := HFBrushChangeTrackerType.new()
var _brush_reconcile_queued := false
## The queued check looks at every brush rather than at those the steps since
## the last one can have touched (#1619).
var _brush_reconcile_full := false
## Marks the faces picked in Face Select on the level the plugin is editing.
var _face_selection_overlay := HFFaceSelectionOverlayType.new()
## The cross at that level's picked pivot, while its Pivot is Pick.
var _pivot_marker := HFPivotMarkerType.new()
## Measures the selection for its size labels and the dock's Selection Info.
var _selection_readout := HFSelectionReadoutType.new()
## Slides, stretches and turns the texture on the faces Face Select picked (#1420).
var _texture_gizmo := HFTextureGizmoType.new()
## Repeat's stamp of the brush the last Draw made (#1407).
var _brush_stamp := HFPluginBrushStampType.new()
## The Control Godot draws the 3D viewport overlay through, captured the first
## time _forward_3d_force_draw_over_viewport runs. Viewport overlays are
## parented here rather than into the toolbar row, which is a layout container
## that reserved each of them a slot the width of its whole panel.
var _viewport_overlay_host: Control = null
# The plugin_*.gd modules use many of the private fields below, which Godot's
# unused check cannot see. CI's tools/check_dead_declarations.py checks them
# across files instead.
@warning_ignore_start("unused_private_class_variable")
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
## The size last drawn beside the cursor, so the overlay is redrawn once more
## when it goes.
var _cursor_size_text := ""
const SELECT_DRAG_THRESHOLD := 6.0
## Two places carry this switch, and the toast names both. The dock is the
## shorter trip from the viewport the reader just pressed a key in; the
## Console is where every other HammerForge setting now lives.
## The menu path is joined with non-breaking spaces so the toast never wraps
## between "Test" and "Settings" and leaves the arrow dangling at a line end.
const POWER_USER_OVERLAYS_HINT := (
	"Power-user overlays are off \u2014 turn them on in"
	+ " Test\u00a0\u2192\u00a0Settings, or the Console's Controls tab"
)
var last_3d_camera: Camera3D = null
var last_3d_mouse_pos := Vector2.ZERO
var _rmb_camera_navigation := HFPluginViewportInput.RmbCameraNavigationSession.new()
var numeric_buffer := ""
var _tool_registry: HFToolRegistry = null
var _keymap: HFKeymap = null
var _user_prefs: HFUserPrefs = null
## The overlay palette each level was last drawn under, by the level's instance
## id, so one in another scene tab is redrawn when it comes back to the front.
var _overlay_colors_drawn: Dictionary = {}
var _vertex_mode := false
var _vertex_drag_active := false
var _vertex_drag_start := Vector2.ZERO
## A box over the corners in vertex mode, and how it selects: 0 replaces, 1 adds,
## 2 takes away (#1713). How many brushes the last corner picked is shared by.
var _vertex_marquee_active := false
var _vertex_marquee_start := Vector2.ZERO
var _vertex_marquee_mode := 0
var _vertex_shared_count := 0
var _vertex_overlay_mesh: MeshInstance3D = null
var _vertex_overlay_imesh: ImmediateMesh = null
var _texture_picker_active := false
## Wrap mode's face, `{brush_id, face_idx}`, or empty when Wrap is off (#1428).
var _wrap_source: Dictionary = {}
## Pick Pivot is waiting for its one click (plugin_transform_tools.gd).
var _pivot_pick_armed := false
## What the Offset popup opens with: the last offset and axes Enter applied.
var _offset_last := Vector3.ZERO
var _offset_local := false
var _last_picked_material_index := -1
var _disp_paint_active := false
var _disp_paint_brush_id := ""
var _disp_paint_face_idx := -1
var _disp_paint_pre_state: Dictionary = {}
## The brushes `_disp_paint_pre_state` records, when it is a brush scope rather
## than the whole level. Empty means the whole level, which is what a stroke on a
## brush that cannot be scoped still takes (#761).
var _disp_paint_scope_ids: Array = []
var _floor_paint_pre_state: Dictionary = {}
var _paint_overlay_mesh: MeshInstance3D = null
var _paint_overlay_imesh: ImmediateMesh = null
var _paint_connector_overlay_meshes: Array[MeshInstance3D] = []
var _context_toolbar: Control = null
var _hotkey_palette: Control = null
## A compare's outlines in the viewport while one is shown (#1701). See
## plugin_compare.gd.
var _compare_overlay = null
## The command line over the viewport, and the file dialog its scripts come
## from, built when first asked for (#1696). See plugin_command_line.gd.
var _command_line_overlay: Control = null
## The last command run with settings, for Adjust Last (#1867):
## `{id, settings, version, recipe, targets}`. See `plugin_adjust_last.gd`.
var last_run: Dictionary = {}
var _adjust_last_panel: Control = null
## Set while Adjust Last makes a step again, so its own undo and step do not close
## the panel.
var _adjusting_last := false
var _command_script_dialog: FileDialog = null
## The lines run on either command line this session, oldest first.
var command_line_history: Array = []
var _selection_filter: Window = null
var _coach_marks: Control = null
var _operation_replay: Control = null
var _viewport_context_menu: PopupMenu = null
var _radial_menu: Control = null
var _quick_property: Control = null
## Takes drags over the viewport for `_can_drop_data()` and `_drop_data()`, which
## Godot never calls on a plugin itself (#1417).
var _viewport_drop_target: Control = null
## A drop target for each viewport of a split layout, by its host's id, and each
## viewport's host by its camera's id, so a click can bring the overlays (#1627).
var _viewport_drop_targets: Dictionary = {}
var _viewport_hosts_by_camera: Dictionary = {}
var _dialog_manager  # HFDialogManager — tracks confirmation dialogs for cleanup
# Double-tap detection for quick property popups
var _last_tap_keycode := 0
var _last_tap_time := 0
@warning_ignore_restore("unused_private_class_variable")
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
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
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
	HFPluginGestureRecovery.after_application_focus_loss(self)


func _enter_tree():
	# First, so a crash while the rest starts up still leaves a journal.
	HFPluginCrashJournalType.setup(self)
	# HammerForge raycasts in the 3D viewport regardless of which editor object
	# is selected. Keep that input forwarding independent from _handles(), which
	# should describe only the object types this plugin actually edits.
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	call_deferred("_prime_managed_brush_tracker")
	call_deferred("_watch_face_selection_root")
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
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
	base_control = EditorInterface.get_base_control()
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
	_tool_registry.register_tool(HFClipToolType.new())
	_tool_registry.register_tool(HFHullToolType.new())
	_tool_registry.register_tool(HFShearToolType.new())
	# A project's own tools go outside the addon, the way HFEntityDef already looks
	# for `res://hammerforge_entities.json`. The in-addon path is the folder the
	# upgrade instructions tell you to replace, so every custom tool a project
	# wrote was destroyed by the documented upgrade, silently (#612). It is kept as
	# a secondary scan so an existing install does not lose anything today.
	_tool_registry.load_external_tools(HFToolRegistry.PROJECT_TOOLS_PATH)
	_tool_registry.load_external_tools("res://addons/hammerforge/tools/")
	_keymap = HFKeymap.load_or_default("user://hammerforge_keymap.json")
	_user_prefs = HFUserPrefs.load_prefs()
	# A new note is signed with the last author, across sessions (#1700).
	DraftEntityType.last_note_author = str(_user_prefs.get_pref("note_author", ""))
	# Each tool comes back with the settings it was last used with (#1406).
	_tool_registry.keep_settings_in(_user_prefs)
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	HFPluginCrashJournalType.stage(self, "dock")
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
		if dock.has_signal("texture_gizmo_toggled"):
			dock.connect("texture_gizmo_toggled", Callable(self, "_sync_texture_gizmo"))
		if dock.has_signal("face_xray_toggled"):
			dock.connect("face_xray_toggled", Callable(self, "_on_face_xray_toggled"))
		if dock.has_signal("selection_clear_requested"):
			dock.connect("selection_clear_requested", Callable(self, "_on_dock_selection_clear"))
		if dock.has_signal("grid_snap_applied"):
			dock.connect("grid_snap_applied", Callable(self, "_on_dock_grid_snap_applied"))
		if dock.has_signal("command_requested"):
			dock.connect("command_requested", Callable(self, "_dispatch_viewport_action"))
		if dock.has_signal("bake_state_changed"):
			dock.connect("bake_state_changed", Callable(self, "_on_dock_bake_state_changed"))
		if dock.has_signal("command_palette_requested"):
			dock.connect("command_palette_requested", Callable(self, "_on_toggle_hotkey_palette"))
		if dock.has_signal("compare_requested"):
			dock.connect("compare_requested", Callable(self, "_on_compare_requested"))
		if dock.has_signal("power_user_overlays_changed"):
			dock.connect(
				"power_user_overlays_changed",
				Callable(self, "_on_dock_power_user_overlays_changed")
			)
		if dock.has_signal("paint_options_changed"):
			dock.connect("paint_options_changed", Callable(self, "_on_paint_options_changed"))
		if dock.has_signal("paint_raise_requested"):
			dock.connect("paint_raise_requested", Callable(self, "_on_paint_raise_requested"))
		if dock.has_signal("paint_room_requested"):
			dock.connect("paint_room_requested", Callable(self, "_on_paint_room_requested"))
		if dock.has_signal("paint_connector_confirm_requested"):
			dock.connect(
				"paint_connector_confirm_requested",
				Callable(self, "_on_paint_connector_confirm_requested")
			)
		if dock.has_signal("selection_size_toggled"):
			dock.connect(
				"selection_size_toggled", Callable(self, "_on_dock_selection_size_toggled")
			)
		if dock.has_signal("selection_vertex_typed"):
			dock.connect("selection_vertex_typed", Callable(self, "_on_selection_vertex_typed"))
		if dock.has_signal("command_ran"):
			dock.connect("command_ran", Callable(self, "_note_last_run"))
		if dock.has_signal("selection_narrow_requested"):
			dock.connect(
				"selection_narrow_requested", Callable(self, "_on_selection_narrow_requested")
			)
		if dock.has_signal("overlay_colors_changed"):
			dock.connect("overlay_colors_changed", Callable(self, "_on_overlay_colors_changed"))
		if not _ensure_selection_readout().refreshed.is_connected(dock.set_selection_info):
			_selection_readout.refreshed.connect(dock.set_selection_info)
	_ensure_selection_readout().set_source(_selection_readout_source)
	_selection_readout.set_show_size(bool(_user_prefs.get_pref("show_selection_size", false)))
	HFPluginOverlays.apply_overlay_colors(self)

	HFPluginCrashJournalType.stage(self, "console")
	HFPluginConsoleType.setup(self)
	HFPluginMcpType.setup(self)
	HFPluginCommandLineType.setup(self)
	# Whether a newer HammerForge is out, asked once a day when allowed (#1656).
	HFPluginUpdateCheckType.setup(self)
	# The timed autosave waits for a pause in editing, and asks here (#1736).
	HFAutosaveSchedulerType.editor_state = HFPluginGestureRecovery.editing_state.bind(self)
	HFPluginCrashJournalType.stage(self, "overlays")
	# The dock lands in its TabContainer during this frame, so the tab icon is
	# stamped again once the editor has finished parenting it.
	call_deferred("_reapply_console_icons")

	hud = preload("shortcut_hud.tscn").instantiate()
	if base_control:
		hud.theme = base_control.theme
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
	if hud.has_method("set_user_prefs"):
		hud.set_user_prefs(_user_prefs)
	if hud.has_method("set_keymap"):
		hud.set_keymap(_keymap)
	if dock:
		hud.visible = dock.get_show_hud()
	# Context toolbar (floating above 3D viewport)
	_context_toolbar = HFContextToolbar.new()
	if base_control:
		_context_toolbar.theme = base_control.theme
	_context_toolbar.set_keymap(_keymap)
	_context_toolbar.action_requested.connect(_on_context_toolbar_action)
	_context_toolbar.operation_toggle_requested.connect(_on_context_toggle_operation)
	_context_toolbar.material_quick_apply.connect(_on_context_material_apply)
	HFPluginOverlays.attach_viewport_overlay(self, _context_toolbar)
	# Hotkey palette (command palette overlay)
	_hotkey_palette = HFHotkeyPalette.new()
	if base_control:
		_hotkey_palette.theme = base_control.theme
	_hotkey_palette.populate(_keymap)
	_hotkey_palette.action_invoked.connect(_on_hotkey_palette_action)
	# A key changed in the shortcut dialog shows on every surface at once (#1733).
	_keymap.changed.connect(_on_keymap_changed)
	HFPluginOverlays.attach_viewport_overlay(self, _hotkey_palette)
	# Selection filter popover (Window-based — not a Control, so managed manually)
	_selection_filter = HFSelectionFilter.new()
	_selection_filter.filter_applied.connect(_on_selection_filter_applied)
	_selection_filter.filter_reported.connect(_on_selection_filter_reported)
	EditorInterface.get_base_control().add_child(_selection_filter)
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
	HFPluginOverlays.attach_viewport_overlay(self, _quick_property)
	var selection = EditorInterface.get_selection()
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
	HFPluginCrashJournalType.started(self)


func _exit_tree():
	HFPluginCrashJournalType.stage(self, "exit_tree")
	HFAutosaveSchedulerType.editor_state = Callable()
	if _keymap and _keymap.changed.is_connected(_on_keymap_changed):
		_keymap.changed.disconnect(_on_keymap_changed)
	HFPluginCompareType.end(self)
	HFPluginCommandLineType.teardown(self)
	HFPluginAdjustLastType.teardown(self)
	HFPluginConsoleType.teardown(self)
	# Before the dock goes: the panel lives in it, and the listener has a file to
	# delete and a socket to close.
	HFPluginMcpType.teardown(self)
	_clear_paint_overlay()
	_cancel_selection_gesture()
	_brush_reconcile_queued = false
	_brush_reconcile_full = false
	_ensure_brush_change_tracker().reset()
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	_ensure_face_selection_overlay().reset()
	_ensure_texture_gizmo().reset()
	_ensure_pivot_marker().reset()
	_pivot_pick_armed = false
	if dock and _ensure_selection_readout().refreshed.is_connected(dock.set_selection_info):
		_selection_readout.refreshed.disconnect(dock.set_selection_info)
	_ensure_selection_readout().reset()
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
		if dock.is_connected("face_xray_toggled", Callable(self, "_on_face_xray_toggled")):
			dock.disconnect("face_xray_toggled", Callable(self, "_on_face_xray_toggled"))
		if dock.is_connected(
			"selection_clear_requested", Callable(self, "_on_dock_selection_clear")
		):
			dock.disconnect("selection_clear_requested", Callable(self, "_on_dock_selection_clear"))
		if dock.is_connected("grid_snap_applied", Callable(self, "_on_dock_grid_snap_applied")):
			dock.disconnect("grid_snap_applied", Callable(self, "_on_dock_grid_snap_applied"))
		if dock.is_connected("command_requested", Callable(self, "_dispatch_viewport_action")):
			dock.disconnect("command_requested", Callable(self, "_dispatch_viewport_action"))
		if dock.is_connected("bake_state_changed", Callable(self, "_on_dock_bake_state_changed")):
			dock.disconnect("bake_state_changed", Callable(self, "_on_dock_bake_state_changed"))
		if dock.is_connected(
			"command_palette_requested", Callable(self, "_on_toggle_hotkey_palette")
		):
			dock.disconnect(
				"command_palette_requested", Callable(self, "_on_toggle_hotkey_palette")
			)
		if dock.is_connected("compare_requested", Callable(self, "_on_compare_requested")):
			dock.disconnect("compare_requested", Callable(self, "_on_compare_requested"))
		if dock.is_connected(
			"power_user_overlays_changed", Callable(self, "_on_dock_power_user_overlays_changed")
		):
			dock.disconnect(
				"power_user_overlays_changed",
				Callable(self, "_on_dock_power_user_overlays_changed")
			)
		if dock.is_connected("paint_options_changed", Callable(self, "_on_paint_options_changed")):
			dock.disconnect("paint_options_changed", Callable(self, "_on_paint_options_changed"))
		if dock.is_connected("paint_raise_requested", Callable(self, "_on_paint_raise_requested")):
			dock.disconnect("paint_raise_requested", Callable(self, "_on_paint_raise_requested"))
		if dock.is_connected("paint_room_requested", Callable(self, "_on_paint_room_requested")):
			dock.disconnect("paint_room_requested", Callable(self, "_on_paint_room_requested"))
		if dock.is_connected(
			"paint_connector_confirm_requested",
			Callable(self, "_on_paint_connector_confirm_requested")
		):
			dock.disconnect(
				"paint_connector_confirm_requested",
				Callable(self, "_on_paint_connector_confirm_requested")
			)
		if dock.is_connected(
			"selection_size_toggled", Callable(self, "_on_dock_selection_size_toggled")
		):
			dock.disconnect(
				"selection_size_toggled", Callable(self, "_on_dock_selection_size_toggled")
			)
		if dock.is_connected(
			"selection_vertex_typed", Callable(self, "_on_selection_vertex_typed")
		):
			dock.disconnect("selection_vertex_typed", Callable(self, "_on_selection_vertex_typed"))
		if dock.is_connected(
			"selection_narrow_requested", Callable(self, "_on_selection_narrow_requested")
		):
			dock.disconnect(
				"selection_narrow_requested", Callable(self, "_on_selection_narrow_requested")
			)
		if dock.is_connected(
			"overlay_colors_changed", Callable(self, "_on_overlay_colors_changed")
		):
			dock.disconnect("overlay_colors_changed", Callable(self, "_on_overlay_colors_changed"))
		if dock.is_connected("command_ran", Callable(self, "_note_last_run")):
			dock.disconnect("command_ran", Callable(self, "_note_last_run"))
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
			_context_toolbar.material_quick_apply.disconnect(_on_context_material_apply)
		HFPluginOverlays.detach_viewport_overlay(self, _context_toolbar)
		if is_instance_valid(_context_toolbar):
			_context_toolbar.queue_free()
		_context_toolbar = null
	if _hotkey_palette:
		if is_instance_valid(_hotkey_palette):
			_hotkey_palette.action_invoked.disconnect(_on_hotkey_palette_action)
		HFPluginOverlays.detach_viewport_overlay(self, _hotkey_palette)
		if is_instance_valid(_hotkey_palette):
			_hotkey_palette.queue_free()
		_hotkey_palette = null
	if _selection_filter:
		if is_instance_valid(_selection_filter):
			_selection_filter.filter_applied.disconnect(_on_selection_filter_applied)
			_selection_filter.filter_reported.disconnect(_on_selection_filter_reported)
			if _selection_filter.get_parent():
				_selection_filter.get_parent().remove_child(_selection_filter)
			_selection_filter.queue_free()
		_selection_filter = null
	if _coach_marks:
		if is_instance_valid(_coach_marks):
			_coach_marks.guide_dismissed.disconnect(_on_coach_mark_dismissed)
		HFPluginOverlays.detach_viewport_overlay(self, _coach_marks)
		if is_instance_valid(_coach_marks):
			_coach_marks.queue_free()
		_coach_marks = null
	if _operation_replay:
		if is_instance_valid(_operation_replay):
			_operation_replay.replay_requested.disconnect(_on_replay_requested)
		HFPluginOverlays.detach_viewport_overlay(self, _operation_replay)
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
		HFPluginOverlays.detach_viewport_overlay(self, _radial_menu)
		if is_instance_valid(_radial_menu):
			_radial_menu.queue_free()
		_radial_menu = null
	if _quick_property:
		if is_instance_valid(_quick_property):
			_quick_property.value_committed.disconnect(_on_quick_property_committed)
		HFPluginOverlays.detach_viewport_overlay(self, _quick_property)
		if is_instance_valid(_quick_property):
			_quick_property.queue_free()
		_quick_property = null
	HFPluginOverlays.free_viewport_drop_target(self)
	# Dropped last: detach_viewport_overlay reads it to know which of the two
	# parents each overlay went onto.
	_viewport_overlay_host = null
	var selection = EditorInterface.get_selection()
	if (
		selection
		and selection.is_connected(
			"selection_changed", Callable(self, "_on_editor_selection_changed")
		)
	):
		selection.disconnect("selection_changed", Callable(self, "_on_editor_selection_changed"))
	if _tool_registry:
		_tool_registry.keep_settings_in(null)
	_tool_registry = null
	if _user_prefs and _user_prefs.get_pref("note_author", "") != DraftEntityType.last_note_author:
		_user_prefs.set_pref("note_author", DraftEntityType.last_note_author)
		_user_prefs.save()
	_ensure_brush_stamp().disarm()
	set_process(false)
	# Last: a crash while closing leaves the journal too.
	HFPluginCrashJournalType.teardown(self)


## The Test tab's Agent Bridge box. HFPluginMcp starts or stops the listener.
func _on_mcp_enable_toggled(enabled: bool) -> void:
	HFPluginMcpType.set_enabled(self, enabled)


## The listener's state, shown on the panel.
func _on_mcp_state_changed(state: int, detail: String) -> void:
	HFPluginMcpType.show_state(self, state, detail)


## What the agent's last command did, shown on the panel.
func _on_mcp_command_finished(method: String, ok: bool, code: String, ms: int) -> void:
	HFPluginCrashJournalType.note_bridge(self, method, ok, code)
	HFPluginMcpType.show_last(self, method, ok, code, ms)


## What the agent changed, outlined for a moment, and what the panel's Last line
## selects (#1653).
var _agent_highlight = null
var _mcp_last_changed: Dictionary = {}


func _on_mcp_last_pressed() -> void:
	HFPluginMcpType.select_last_changed(self, _mcp_last_changed)


## Routed from the Console's status rows and header buttons. Every action is
## carried out by a handler that already exists on the dock — see
## HFPluginConsole.handle_action.
func _on_console_action(action_id: String) -> void:
	HFPluginConsoleType.handle_action(self, action_id)


## The dock's Compare With... picked a file.
func _on_compare_requested(path: String) -> void:
	HFPluginCompareType.start(self, path)


## The viewport lamp was clicked.
func _on_console_requested() -> void:
	HFPluginConsoleType.open_console()


# HammerForge takes a place in the main-screen switcher beside 2D, 3D and
# Script. That row is the one part of the editor chrome that draws a plugin's
# own icon, and it is where a Godot user looks for an installed addon.
#
# The price of that row is _handles(). A plugin that has a main screen and also
# handles the selected object is switched to by Godot the moment that object is
# selected, which cost eleven days of the Console jumping in front of the 3D
# view (#592). Keep the two apart: a main screen is a place you go to, not an
# editor for a node type.


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "HammerForge"


func _get_plugin_icon() -> Texture2D:
	return HFPluginConsoleType.plugin_icon()


func _make_visible(visible: bool) -> void:
	HFPluginConsoleType.set_console_visible(self, visible)


func _reapply_console_icons() -> void:
	if is_inside_tree():
		HFPluginConsoleType.apply_icons(self)


func _on_editor_theme_changed() -> void:
	if not base_control:
		return
	if console_panel and is_instance_valid(console_panel):
		console_panel.set_theme_source(base_control)
	# The editor rebuilds its tab bars around a theme change, dropping icons
	# that were set from outside it.
	HFPluginConsoleType.apply_icons(self)
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
	_ensure_selection_readout().queue_refresh()
	HFPluginSelectionState.on_editor_selection_changed(self)
	HFPluginRunType.on_selection_changed(self)


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


## Always false, and it has to stay that way while _has_main_screen() is true.
## Godot resolves the pair in EditorData::get_handling_main_editor(): a plugin
## that has a main screen and handles the selected object becomes the main
## screen. That loop runs the plugin list backwards so an addon beats the
## built-in editors, so claiming a DraftBrush here threw the user off the 3D
## view and onto the Console on every brush click (#592).
##
## Refusing costs nothing. Viewport input comes from the force-forwarding lists
## set up in _enter_tree(), which Node3DEditorViewport dispatches separately
## from the handled-object list, so _forward_3d_gui_input() is unaffected. The
## only other thing a true here bought was _edit(), and that is now
## sync_active_root_from_selection() driven off selection_changed.
func _handles(_object: Object) -> bool:
	return false


## Point active_root at the LevelRoot that owns the current selection. This is
## what _edit() used to do, moved onto EditorSelection so the plugin can keep a
## main screen without claiming the objects it draws for.
func sync_active_root_from_selection(nodes: Array) -> void:
	var root := resolve_active_root_for_selection(nodes)
	if root:
		active_root = root
		_ensure_brush_change_tracker().ensure_root(root)
		_watch_face_selection_root()
		return
	# Don't null active_root — keep the previous root alive as long as it still
	# exists in the scene. This prevents losing the dock/3D connection when the
	# user clicks a Camera, Light, or other non-LevelRoot node.
	if active_root and is_instance_valid(active_root) and active_root.is_inside_tree():
		_watch_face_selection_root()
		return
	active_root = null
	_ensure_brush_change_tracker().reset()
	_watch_face_selection_root()


## The LevelRoot a selection should make active, or null to keep the current
## one. Only nodes this plugin owns may retarget it, which is the same bar
## _handles() used to set before Godot stopped asking.
static func resolve_active_root_for_selection(nodes: Array) -> Node:
	for node in nodes:
		if not is_instance_valid(node) or not should_handle_editor_object(node):
			continue
		var root := level_root_from_node(node as Node)
		if root:
			return root
	return null


## Whether a first Draw click may create a level in the open scene (#932).
func _edited_scene_awaits_a_level() -> bool:
	return HFPluginViewportInput.scene_awaits_a_level(EditorInterface.get_edited_scene_root())


## A Draw click in a scene with no level points at the dock's banner, once per
## scene, rather than doing nothing without a word.
func _hint_create_level_from_banner() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	var scene_id := scene.get_instance_id() if scene else 0
	if scene_id == 0 or scene_id == _no_level_hint_scene_id:
		return
	_no_level_hint_scene_id = scene_id
	if dock:
		dock.show_toast(
			"This scene has no HammerForge level. Use Create Starter or Create Empty in the dock.",
			0
		)


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
	HFPluginSnapFeedback.begin(self, event)
	var answer := HFPluginViewportInput.handle(self, camera, event)
	HFPluginSnapFeedback.end(self, event)
	return answer


func _should_start_disp_paint(event: InputEvent, root: Node, cam: Camera3D) -> bool:
	return HFPluginPaintInput.should_start_displacement(self, event, root, cam)


func _handle_disp_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	return HFPluginPaintInput.handle_displacement(self, event, root, cam, pos)


func _commit_disp_paint_undo(root: Node) -> void:
	HFPluginPaintInput.commit_displacement_undo(self, root)


func _commit_floor_paint_undo(root: Node) -> void:
	HFPluginPaintInput.commit_floor_paint_undo(self, root)


func _begin_floor_paint_raise(root: Node) -> bool:
	return HFPluginPaintInput.begin_floor_paint_raise(self, root, last_3d_mouse_pos.y)


func _stamp_floor_paint_room(root: Node) -> bool:
	return HFPluginPaintInput.stamp_floor_paint_room(self, root)


func _confirm_floor_paint_connector(root: Node) -> bool:
	return HFPluginPaintInput.confirm_floor_paint_connector(self, root)


func _on_paint_options_changed() -> void:
	var root = active_root if active_root else _get_level_root()
	if root and root.get("paint_tool") and dock:
		root.paint_tool.inference = (
			preload("paint/hf_inference_engine.gd").new()
			if dock.get_paint_inference_enabled()
			else null
		)
		root.paint_tool.mirror_x_enabled = dock.get_paint_mirror_x_enabled()
		root.paint_tool.mirror_z_enabled = dock.get_paint_mirror_z_enabled()
	_update_hud_context()
	_update_paint_overlay(root)


func _on_paint_raise_requested() -> void:
	var root = active_root if active_root else _get_level_root()
	if root:
		_begin_floor_paint_raise(root)


func _on_paint_room_requested() -> void:
	var root = active_root if active_root else _get_level_root()
	if root:
		_stamp_floor_paint_room(root)


func _on_paint_connector_confirm_requested() -> void:
	var root = active_root if active_root else _get_level_root()
	if root:
		_confirm_floor_paint_connector(root)


func _handle_paint_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	return HFPluginPaintInput.handle_paint(self, event, root, cam, pos)


## The way an arrow or Page key moves the selection: along the world axis
## nearest its direction in the view it was pressed in, unless the mapper keeps
## the fixed mapping (#1716).
func _get_nudge_direction(keycode: int) -> Vector3:
	var follow := _user_prefs == null or bool(_user_prefs.get_pref("nudge_follows_view", true))
	return HFViewAxes.nudge_direction(keycode, last_3d_camera if follow else null)


## The last move, as the HUD shows it for a moment: [text, when].
var _nudge_readout: Array = []


## Show a move on the HUD for a moment, as "+Y 0.25 m".
func read_out_move(text: String) -> void:
	_nudge_readout = [text, Time.get_ticks_msec()]


func _handle_numeric_input(event: InputEventKey, root: Node) -> int:
	return HFPluginNumericInput.handle(self, event, root)


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


func _ensure_face_selection_overlay():
	if _face_selection_overlay == null:
		_face_selection_overlay = HFFaceSelectionOverlayType.new()
	return _face_selection_overlay


func _ensure_pivot_marker():
	if _pivot_marker == null:
		_pivot_marker = HFPivotMarkerType.new()
	return _pivot_marker


## Mark the picked faces, and the picked pivot, of the level the plugin is editing
## now, and only those, and measure its selection.
func _watch_face_selection_root() -> void:
	var root: Node = active_root if active_root else _get_level_root()
	_ensure_face_selection_overlay().watch(root)
	_ensure_pivot_marker().watch(root)
	_ensure_selection_readout().watch(root)
	_ensure_texture_gizmo().watch(root)
	HFPluginOverlays.refresh_overlay_colors(self, root)


## A tab switch leaves active_root on the level that was in front until something
## else is selected, so the marks go by the scene now open instead. A pick armed
## on the scene that went is put away rather than left to catch a click here.
func _on_scene_changed(_scene_root: Node) -> void:
	HFPluginTransformTools.cancel_pivot_pick(self)
	_ensure_face_selection_overlay().watch(_get_level_root())
	_ensure_pivot_marker().watch(_get_level_root())
	_ensure_selection_readout().watch(_get_level_root())
	_ensure_texture_gizmo().watch(_get_level_root())
	# A stamp belongs to the level it was armed in.
	_ensure_brush_stamp().disarm()
	HFPluginOverlays.refresh_overlay_colors(self, _get_level_root())


func _ensure_texture_gizmo():
	if _texture_gizmo == null:
		_texture_gizmo = HFTextureGizmoType.new()
	return _texture_gizmo


## Show the Texture Gizmo while its toggle is on and Face Select is open (#1420).
func _sync_texture_gizmo(_enabled := false) -> void:
	var gizmo = _ensure_texture_gizmo()
	gizmo.set_camera(last_3d_camera)
	gizmo.set_shown(
		dock != null and dock.is_face_select_mode_enabled() and dock.is_texture_gizmo_enabled()
	)


## A colour picked under Test > Settings > Colours, or a preset or Reset there.
func _on_overlay_colors_changed() -> void:
	HFPluginOverlays.apply_overlay_colors(self)


func _ensure_selection_readout():
	if _selection_readout == null:
		_selection_readout = HFSelectionReadoutType.new()
	return _selection_readout


func _ensure_brush_stamp():
	if _brush_stamp == null:
		_brush_stamp = HFPluginBrushStampType.new()
	return _brush_stamp


## What the readout measures: the selection, and whether it is vertices of it.
func _selection_readout_source() -> Dictionary:
	return {"nodes": hf_selection, "vertex_mode": _vertex_mode}


func _on_dock_selection_size_toggled(enabled: bool) -> void:
	_ensure_selection_readout().set_show_size(enabled)


## A place typed for the one selected vertex in the dock's Selection Info.
func _on_selection_narrow_requested(kind: String) -> void:
	var root := active_root if active_root else _get_level_root()
	if root:
		HFPluginSelectionCommands.narrow_selection(self, root, kind)


func _on_selection_vertex_typed(place: Vector3, local: bool) -> void:
	var root := active_root if active_root else _get_level_root()
	if root:
		HFPluginVertexOps.move_selected_vertex_to(self, root, place, local)
	# Measured now rather than next frame, so a refused place goes back at once.
	_ensure_selection_readout().refresh()


## Check the level's brushes for what Godot changed, once this frame is done.
## `full` looks at every brush, for a change nothing can narrow, such as one made
## while the editor was out of focus.
## Every surface that names a chord reads the keymap again: the dock, the HUD,
## the context toolbar and the command palette.
func _on_keymap_changed() -> void:
	if dock:
		dock.set_keymap(_keymap)
	if hud and hud.has_method("set_keymap"):
		hud.set_keymap(_keymap)
	if _context_toolbar:
		_context_toolbar.set_keymap(_keymap)
	if _hotkey_palette:
		_hotkey_palette.populate(_keymap)


func _queue_managed_brush_reconcile(full := false) -> void:
	_brush_reconcile_full = _brush_reconcile_full or full
	if _brush_reconcile_queued:
		return
	_brush_reconcile_queued = true
	call_deferred("_reconcile_managed_brush_changes")


func _reconcile_managed_brush_changes() -> void:
	_brush_reconcile_queued = false
	var full := _brush_reconcile_full or undo_redo_manager == null
	_brush_reconcile_full = false
	var root := active_root if active_root else _get_level_root()
	if root:
		var selection = EditorInterface.get_selection()
		var selected: Array = selection.get_selected_nodes() if selection else []
		_ensure_brush_change_tracker().reconcile_step(root, selected, full)
	else:
		_ensure_brush_change_tracker().reset()


## Tell the change check where the level's undo history now stands, so the check
## after this step looks at the brushes the step can have touched (#1619).
func _note_history_step(root: Node) -> void:
	if not undo_redo_manager or not root:
		return
	var history_id: int = undo_redo_manager.get_object_history_id(root)
	var history: UndoRedo = undo_redo_manager.get_history_undo_redo(history_id)
	if history:
		_ensure_brush_change_tracker().note_step(
			history.get_version(), history.has_redo(), history.get_current_action_name()
		)
		HFPluginCrashJournalType.note_step(self, root, history)


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
	HFPluginToolModes.prepare_transition(self, root, notify_user, settle_custom_gizmo)


func _deactivate_external_tool() -> void:
	HFPluginToolModes.deactivate_external(self)


func _activate_external_tool(tool_id: int, root: Node) -> void:
	HFPluginToolModes.activate_external(self, tool_id, root)


func _on_builtin_tool_changed() -> void:
	HFPluginToolModes.on_builtin_tool_changed(self)


func _on_vertex_mode_toggled(enabled: bool) -> void:
	HFPluginToolModes.on_vertex_mode_toggled(self, enabled)


func _on_face_select_mode_toggled(enabled: bool) -> void:
	HFPluginToolModes.on_face_select_mode_toggled(self, enabled)
	_sync_texture_gizmo()


## The HUD line and the marquee's colour say whether X-ray is on.
func _on_face_xray_toggled(_enabled: bool) -> void:
	_update_hud_context()
	if is_inside_tree():
		update_overlays()


func _close_face_select_mode(message: String = "") -> bool:
	return HFPluginToolModes.close_face_select(self, message)


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
	return HFPluginGestureRecovery.finish_stale_paint_strokes(self, root, input_state, paint_tool)


func _recover_stale_lmb_gestures(root: Node) -> void:
	HFPluginGestureRecovery.recover_stale_lmb_gestures(self, root)


func _handle_rmb_cancel(root: Node, _tool_id: int, event: InputEventMouseButton) -> int:
	return HFPluginGestureRecovery.handle_rmb_cancel(self, root, event)


func _show_viewport_context_menu(root: Node, tool_id: int) -> void:
	HFPluginOverlays.show_viewport_context_menu(self, root, tool_id)


func _get_current_overlay_mouse_pos() -> Vector2:
	return last_3d_mouse_pos


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
		var hf_owner := _hammerforge_selection_owner(candidate as Node, root)
		if hf_owner is DraftBrush or hf_owner is DraftEntityType:
			continue
		if root and root.has_method("is_entity_node") and root.is_entity_node(hf_owner):
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


# ---------------------------------------------------------------------------
# Vertex editing mode
# ---------------------------------------------------------------------------


func _toggle_vertex_mode(root: Node) -> void:
	HFPluginVertexOps.toggle_mode(self, root)
	_ensure_selection_readout().queue_refresh()


func _vertex_merge_selected(root: Node) -> void:
	HFPluginVertexOps.merge_selected(self, root)


func _vertex_split_selected_edge(root: Node) -> void:
	HFPluginVertexOps.split_selected_edge(self, root)


func _vertex_clip_to_convex(root: Node) -> void:
	HFPluginVertexOps.clip_to_convex(self, root)


func _handle_vertex_input(event: InputEvent, root: Node, cam: Camera3D, pos: Vector2) -> int:
	return HFPluginVertexInput.handle(self, event, root, cam, pos)


func _commit_vertex_move(root: Node, pre_drag_snapshots: Dictionary) -> void:
	HFPluginVertexOps.commit_move(self, root, pre_drag_snapshots)


func _update_vertex_overlay(root: Node, _cam: Camera3D) -> void:
	HFPluginOverlays.update_vertex_overlay(self, root)
	# Every vertex pick, drag step and edit redraws the overlay, and none of the
	# drag steps tags the brush.
	_ensure_selection_readout().queue_refresh()


func _clear_vertex_overlay() -> void:
	HFPluginOverlays.clear_vertex_overlay(self)


func _update_paint_overlay(root: Node) -> void:
	HFPluginOverlays.update_paint_overlay(self, root)


func _clear_paint_overlay() -> void:
	HFPluginOverlays.clear_paint_overlay(self)


func _shortcut_input(event: InputEvent) -> void:
	HFPluginShortcuts.handle(self, event)


## Retained because tests and downstream integrations call this by name.
static func should_yield_global_shortcut_to_focus(focus_owner: Control) -> bool:
	return HFPluginShortcuts.should_yield_to_focus(focus_owner)


func _cancel_escape_step(root: Node) -> bool:
	return HFPluginShortcuts.cancel_escape_step(self, root)


## Godot finishes native selection after _forward_3d_gui_input() returns. Do
## group normalization one deferred tick later so its exact gizmo and region
## hit-testing remains authoritative, then map internal visual children back to
## their HammerForge owner and apply grouped brushes as one selection unit.
func _finalize_native_selection(selection_before: Array, additive: bool, toggle: bool) -> void:
	HFPluginSelectionState.finalize_native_selection(self, selection_before, additive, toggle)


func _hammerforge_selection_owner(node: Node, root: Node) -> Node:
	return HFPluginSelectionState.normalize_managed_selection_owner(node, root)


static func normalize_managed_selection_owner(node: Node, root: Node) -> Node:
	return HFPluginSelectionState.normalize_managed_selection_owner(node, root)


static func expand_native_group_members(
	selection_before: Array, current_selection: Array, toggle: bool, groups: Dictionary
) -> Array:
	return HFPluginSelectionState.expand_native_group_members(
		selection_before, current_selection, toggle, groups
	)


func _apply_selection_list(nodes: Array, additive: bool, toggle: bool = false) -> void:
	HFPluginSelectionState.apply_selection_list(self, nodes, additive, toggle)


func _apply_hf_selection(selection: Object) -> void:
	HFPluginSelectionState.apply_hf_selection(self, selection)


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


func _get_undo_redo() -> Object:
	return undo_redo_manager if undo_redo_manager else get_undo_redo()


func _record_history(action_name: String) -> void:
	if dock:
		dock.record_history(action_name)
	if _operation_replay and is_instance_valid(_operation_replay):
		var version := -1
		if undo_redo_manager:
			var history_id: int = (
				undo_redo_manager.get_object_history_id(active_root) if active_root else 0
			)
			var undo_redo_obj: UndoRedo = undo_redo_manager.get_history_undo_redo(history_id)
			if undo_redo_obj:
				version = undo_redo_obj.get_version()
		_operation_replay.record_operation(action_name, version)


func _paint_brush_with_undo(root: Node, brush: Node, mat: Material) -> void:
	HFPluginMaterialCommands.paint_brush_with_undo(self, root, brush, mat)


func _paint_brushes_with_undo(root: Node, brushes: Array, mat: Material) -> int:
	return HFPluginMaterialCommands.paint_brushes_with_undo(self, root, brushes, mat)


func _commit_brush_placement(root: Node, info: Dictionary) -> void:
	if info.is_empty():
		return
	# New work joins the current visgroup, as part of the step so a redo does too
	# (#1732).
	var current: String = (
		root.visgroup_system.get_current_visgroup() if root.get("visgroup_system") else ""
	)
	if current != "" and not info.has("visgroups"):
		info = info.duplicate()
		info["visgroups"] = [current]
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
	HFPluginMaterialCommands.pick_face_material(self, root)


# ---------------------------------------------------------------------------
# Marquee & face rect selection
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Selection Filter popup
# ---------------------------------------------------------------------------


func _show_selection_filter() -> void:
	HFPluginSelectionCommands.show_selection_filter(self)


func _on_selection_filter_applied(nodes: Array, faces: Dictionary) -> void:
	HFPluginSelectionCommands.on_filter_applied(self, nodes, faces)


## A filter that matched nothing says so, rather than closing in silence.
func _on_selection_filter_reported(message: String) -> void:
	if dock:
		dock.show_toast(message, 1)


# ---------------------------------------------------------------------------
# Marquee overlay
# ---------------------------------------------------------------------------


func _update_marquee_overlay(from: Vector2, to: Vector2, active: bool) -> void:
	HFPluginOverlays.update_marquee_overlay(self, from, to, active)


## Draw through Godot's real 3D overlay so viewport-local event coordinates
## remain correct under split views, editor scaling, and dock rearrangement.
func _forward_3d_force_draw_over_viewport(viewport_control: Control) -> void:
	HFPluginOverlays.adopt_viewport_overlay_host(self, viewport_control)
	HFPluginOverlays.ensure_viewport_drop_target(self, viewport_control)
	HFPluginOverlays.refresh_viewport_overlay_placement(self)
	HFPluginOverlays.draw_marquee_overlay(self, viewport_control)
	HFPluginHud.draw_cursor_size(self, viewport_control)
	HFPluginSnapFeedback.draw(self, viewport_control)
	if _agent_highlight:
		_agent_highlight.draw_edge_arrow(viewport_control, last_3d_camera)


func _add_confirmable_dialog(dlg: ConfirmationDialog) -> void:
	if _dialog_manager:
		_dialog_manager.add(dlg, EditorInterface.get_base_control())


func _cleanup_pending_dialogs() -> void:
	if _dialog_manager:
		_dialog_manager.cleanup()


func _delete_selected(root: Node) -> bool:
	return HFPluginEditActions.delete_selected(self, root)


func _duplicate_selected(root: Node) -> bool:
	return HFPluginEditActions.duplicate_selected(self, root)


func _copy_selection(root: Node) -> bool:
	return HFPluginEditActions.copy_selection(self, root)


func _paste_clipboard(root: Node) -> bool:
	return HFPluginEditActions.paste_clipboard(self, root)


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


## Keep what a command with settings ran with, for Adjust Last (#1867). See
## `HFPluginAdjustLast.note()`.
func _note_last_run(id: String, settings: Dictionary, recipe: Dictionary) -> void:
	HFPluginAdjustLastType.note(self, id, settings, recipe)
	HFPluginRunType.note(self, id, settings)


## Adjust Last made the last step again with `settings`, for the run's step for
## it (#1735).
func _note_run_adjusted(id: String, settings: Dictionary, version: int) -> void:
	HFPluginRunType.adjusted(self, id, settings, version)


## A drag of the gizmo moved `moved`, for Repeat Run (#1735). See
## `HFPluginRun.note_moved()`.
func _note_run_moved(moved: Array) -> void:
	HFPluginRunType.note_moved(self, moved)


func _hollow_selected(root: Node) -> bool:
	return HFPluginEditActions.hollow_selected(self, root)


func _merge_selected(root: Node) -> bool:
	return HFPluginEditActions.merge_selected(self, root)


func _rotate_selected(root: Node, direction: int) -> bool:
	return HFPluginEditActions.rotate_selected(self, root, direction)


func _flip_selected(root: Node) -> bool:
	return HFPluginEditActions.flip_selected(self, root)


func _reset_rotation_selected(root: Node) -> bool:
	return HFPluginEditActions.reset_rotation_selected(self, root)


func _move_selected_to_floor(root: Node) -> bool:
	return HFPluginEditActions.move_selected_to_floor(self, root)


func _move_selected_to_ceiling(root: Node) -> bool:
	return HFPluginEditActions.move_selected_to_ceiling(self, root)


func _clip_selected(root: Node) -> bool:
	return HFPluginEditActions.clip_selected(self, root)


func _clip_to_face_plane_selected(root: Node) -> bool:
	return HFPluginEditActions.clip_to_face_plane_selected(self, root)


func _carve_selected(root: Node) -> bool:
	return HFPluginEditActions.carve_selected(self, root)


func _intersect_selected(root: Node) -> bool:
	return HFPluginEditActions.intersect_selected(self, root)


## Called by `_viewport_drop_target` for a drag over the viewport.
func _can_drop_data(position: Vector2, data: Variant) -> bool:
	return HFPluginDropHandler.can_drop(self, position, data)


func _drop_data(position: Vector2, data: Variant) -> void:
	HFPluginDropHandler.drop_data(self, position, data)


## The same for a drag over the viewport `host` draws over, which is the one whose
## camera says what is under the cursor (#1627).
func _can_drop_data_on(position: Vector2, data: Variant, host: Control) -> bool:
	_look_through(host)
	return _can_drop_data(position, data)


func _drop_data_on(position: Vector2, data: Variant, host: Control) -> void:
	_look_through(host)
	_drop_data(position, data)


func _look_through(host: Control) -> void:
	var camera := HFPluginOverlays.camera_for_host(host)
	if camera:
		last_3d_camera = camera


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
	HFPluginToolModes.toggle_paint_mode(self)


# plugin_bake_preview.gd keeps these.
@warning_ignore_start("unused_private_class_variable")
var _bake_preview_active := false
var _bake_preview_in_flight := false
@warning_ignore_restore("unused_private_class_variable")


func _on_dock_bake_state_changed(baking: bool, success: bool) -> void:
	HFPluginBakePreview.on_bake_state_changed(self, baking, success)


func _toggle_bake_preview(root: Node, pressed: bool) -> void:
	await HFPluginBakePreview.toggle(self, root, pressed)


func _on_context_material_apply(mat_index: int) -> void:
	HFPluginMaterialCommands.apply_context_material(self, mat_index)


func _on_toggle_hotkey_palette() -> void:
	if _hotkey_palette:
		_hotkey_palette.toggle_visible()
		if _hotkey_palette.visible:
			var root = active_root if active_root else _get_level_root()
			var tool_id = dock.get_tool() if dock else 0
			_update_context_toolbar_state(root, tool_id)


## Retained because tests and downstream integrations call this by name.
static func hotkey_palette_action_requires_existing_root(action: String) -> bool:
	return HFPluginCommands.requires_existing_root(action)


## The last command run that changed the level or the selection, which Repeat
## Last Command runs again, and the commands run lately, newest first (#1694).
var last_repeatable_command := ""
var recent_commands: Array = []
## The commands run since the selection last changed by hand, which Repeat Run
## plays again (#1735): each `{id, settings, version}`. See `plugin_run.gd`.
var run_steps: Array = []
## The selection the run's last step left, by instance id, and whether one made
## by hand since has the next command start a new run.
var run_selection: Array = []
var run_restart := false
## The level the run was made in.
var run_root := 0
## Set while Repeat Run plays, so what it does is not taken into the run.
var playing_run := false


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


func _on_quick_property_committed(property_type: int, values: Array) -> void:
	HFPluginOverlays.on_quick_property_committed(self, property_type, values)


func _show_coach_mark_for_action(action: String) -> void:
	HFPluginOverlays.show_coach_mark_for_action(self, action)


func _show_coach_mark_for_tool_id(tool_id: int) -> void:
	HFPluginOverlays.show_coach_mark_for_tool_id(self, tool_id)


func _on_coach_mark_dismissed(_tool_key: String, _dont_show: bool) -> void:
	pass  # Persistence is handled internally by HFCoachMarks


func _on_undo_redo_version_changed() -> void:
	HFPluginUndoEvents.on_version_changed(self)
	HFPluginRunType.on_version_changed(self)
	# A Godot undo moves a brush with no signal until the brush tracker tags it,
	# and the first reconcile of a level the tracker was not watching tags nothing.
	_ensure_face_selection_overlay().queue_refresh()
	_ensure_selection_readout().queue_refresh()
	_ensure_texture_gizmo().queue_refresh()
	# An undo can end a drag, and the size beside the cursor with it.
	update_overlays()


func _on_replay_requested(entry_index: int) -> void:
	HFPluginUndoEvents.on_replay_requested(self, entry_index)


func _get_level_root() -> Node:
	var scene = EditorInterface.get_edited_scene_root()
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


static func level_root_from_node(node: Node) -> Node:
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


## Create a starter level in the edited scene and return its LevelRoot: a
## floor, an angled sun light and a player spawn. One undo entry, named
## `action_name`, whether or not the scene had a LevelRoot already.
##
## This is Create Starter without the dock. For a scene that is not the one open
## in the editor, use `HFLevelFactory.create_starter()` instead.
func create_starter_level(action_name: String = "New HammerForge Level") -> Node:
	var scene = EditorInterface.get_edited_scene_root()
	if not scene:
		return null
	# The edited scene's own level, not active_root, which can still name a level
	# on another tab.
	var root = _get_level_root()
	if root:
		HFUndoHelper.commit(undo_redo_manager, root, action_name, "create_new_level")
		return root
	return HFLevelFactory.create_starter_undoable(undo_redo_manager, scene, action_name, self)


func _create_level_root() -> Node:
	var scene = EditorInterface.get_edited_scene_root()
	if not scene:
		return null
	var root = HFLevelFactory.make_level_root()
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
	var selection = EditorInterface.get_selection()
	selection.clear()
	selection.add_node(root)
	hf_selection.clear()
	hf_selection.append(root)


func _deactivate_created_level_root(root: Node) -> void:
	if active_root == root:
		active_root = null
		_ensure_brush_change_tracker().reset()
	hf_selection.erase(root)
	var selection = EditorInterface.get_selection()
	if selection and root in selection.get_selected_nodes():
		selection.remove_node(root)
