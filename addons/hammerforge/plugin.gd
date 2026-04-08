@tool
extends EditorPlugin

const DockType = preload("dock.gd")
var dock: DockType
var hud: Control
var base_control: Control
var active_root: LevelRoot = null
var undo_redo_manager: EditorUndoRedoManager = null
var brush_gizmo_plugin: EditorNode3DGizmoPlugin = null
var hf_selection: Array = []
var select_drag_origin := Vector2.ZERO
var select_drag_active := false
var select_dragging := false
var select_additive := false
var select_drag_threshold := 6.0
var last_3d_camera: Camera3D = null
var last_3d_mouse_pos := Vector2.ZERO
var numeric_buffer := ""
var _tool_registry: HFToolRegistry = null
var _keymap: HFKeymap = null
var _user_prefs: HFUserPrefs = null
var _vertex_mode := false
var _vertex_drag_active := false
var _vertex_drag_start := Vector2.ZERO
var _vertex_drag_ref_y := 0.0  # World Y of the picked vertex for projection plane
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
var _marquee_overlay: Control = null
var _coach_marks: Control = null
var _operation_replay: Control = null
const LevelRootType = preload("level_root.gd")
const HFContextToolbar = preload("ui/hf_context_toolbar.gd")
const HFHotkeyPalette = preload("ui/hf_hotkey_palette.gd")
const HFSelectionFilter = preload("ui/hf_selection_filter.gd")
const HFCoachMarks = preload("ui/hf_coach_marks.gd")
const HFOperationReplay = preload("ui/hf_operation_replay.gd")
const DraftEntityType = preload("draft_entity.gd")
const IconRes = preload("icon.png")
const HFUndoHelper = preload("undo_helper.gd")
const HFInputStateType = preload("input_state.gd")


func _enter_tree():
	add_custom_type("LevelRoot", "Node3D", LevelRootType, IconRes)
	add_custom_type("DraftEntity", "Node3D", DraftEntityType, IconRes)
	dock = preload("dock.tscn").instantiate()
	undo_redo_manager = get_undo_redo()
	brush_gizmo_plugin = preload("brush_gizmo_plugin.gd").new()
	if brush_gizmo_plugin:
		brush_gizmo_plugin.set_undo_redo(undo_redo_manager)
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
	_tool_registry.register_tool(HFPathTool.new())
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
		if dock.has_signal("selection_clear_requested"):
			dock.connect("selection_clear_requested", Callable(self, "_on_dock_selection_clear"))

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
	# Marquee overlay (2D rect drawn over 3D viewport during drag-select)
	_marquee_overlay = _MarqueeOverlay.new()
	_marquee_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _marquee_overlay)
	# Coach marks (first-use tool guides)
	_coach_marks = HFCoachMarks.new()
	if base_control:
		_coach_marks.theme = base_control.theme
	_coach_marks.set_user_prefs(_user_prefs)
	_coach_marks.guide_dismissed.connect(_on_coach_mark_dismissed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _coach_marks)
	# Operation replay timeline
	_operation_replay = HFOperationReplay.new()
	if base_control:
		_operation_replay.theme = base_control.theme
	_operation_replay.replay_requested.connect(_on_replay_requested)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _operation_replay)
	if dock:
		dock.set_operation_replay(_operation_replay)
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
	if _marquee_overlay:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _marquee_overlay)
		if is_instance_valid(_marquee_overlay):
			_marquee_overlay.queue_free()
		_marquee_overlay = null
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
	var root = active_root if active_root else _get_level_root()
	if root and root.input_state:
		ctx["mode"] = root.input_state.mode
		ctx["axis_lock"] = root.input_state.axis_lock
	# Update dock mode indicator banner
	if dock:
		var mode_name := "Draw"
		if _vertex_mode:
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

	# Input mode
	var input_mode := 0
	if root and root.input_state:
		input_mode = root.input_state.mode
		var dims = root.input_state.get_drag_dimensions()
		state["dimensions"] = HFInputStateType.format_dimensions(dims)
	state["input_mode"] = input_mode

	# Count brushes, entities, faces in selection
	var brush_count := 0
	var entity_count := 0
	for node in hf_selection:
		if node is DraftBrush:
			brush_count += 1
		elif root and root.has_method("is_entity_node") and root.is_entity_node(node):
			entity_count += 1
	state["brush_count"] = brush_count
	state["entity_count"] = entity_count

	# I/O connection summary for entity context toolbar
	if entity_count > 0 and root and root.has_method("get_connection_summary"):
		var first_entity: Node = null
		for node in hf_selection:
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

	# Prefab instance info for context toolbar badge
	if root and root.prefab_system and not hf_selection.is_empty():
		var first_node: Node3D = hf_selection[0]
		var pfb_iid: String = str(first_node.get_meta("hf_prefab_instance", ""))
		if pfb_iid != "":
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
		_hotkey_palette.update_state(state)


## Returns true when an incoming (empty) editor selection should be ignored
## because hf_selection still holds brushes — i.e. the empty signal is
## likely a spurious side-effect (texture reimport, resource scan) rather
## than an intentional user deselect.  Intentional deselects clear
## hf_selection *before* the editor selection, so the guard lets them
## through.
static func should_suppress_empty_selection(
	incoming_nodes: Array, current_hf_selection: Array
) -> bool:
	return incoming_nodes.is_empty() and not current_hf_selection.is_empty()


func _on_editor_selection_changed() -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	var nodes = selection.get_selected_nodes()
	if should_suppress_empty_selection(nodes, hf_selection):
		return
	hf_selection = nodes
	if dock:
		dock.set_selection_count(hf_selection.size())
		dock.set_selection_nodes(hf_selection)
	# Update vertex system with current brush selection
	if _vertex_mode:
		var root = active_root if active_root else _get_level_root()
		if root and root.vertex_system:
			var brushes: Array = []
			for node in hf_selection:
				if node is DraftBrush:
					brushes.append(node)
			root.vertex_system.set_selection(brushes)


func _handles(object: Object) -> bool:
	if not object or not (object is Node):
		return false
	# Accept if the node is under a LevelRoot, OR if a LevelRoot exists anywhere
	# in the scene. This keeps _forward_3d_gui_input() active so the user can
	# draw/select without having to re-click the LevelRoot node.
	if _get_level_root_from_node(object as Node) != null:
		return true
	if active_root and is_instance_valid(active_root) and active_root.is_inside_tree():
		return true
	return _get_level_root() != null


func _edit(object: Object) -> void:
	if object and object is Node:
		var root = _get_level_root_from_node(object as Node)
		if root:
			active_root = root
			return
	# Don't null active_root — keep the previous root alive as long as it still
	# exists in the scene. This prevents losing the dock/3D connection when the
	# user clicks a Camera, Light, or other non-LevelRoot node.
	if active_root and is_instance_valid(active_root) and active_root.is_inside_tree():
		return
	active_root = null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var root = active_root if active_root else _get_level_root()
	if not root:
		root = _create_level_root()
	if not root or not dock:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if camera:
		last_3d_camera = camera
	if event is InputEventMouse:
		last_3d_mouse_pos = event.position

	var target_camera = camera
	var target_pos = event.position if event is InputEventMouse else last_3d_mouse_pos

	if event is InputEventMouseMotion or event is InputEventMouseButton:
		root.update_editor_grid(target_camera, target_pos)

	var tool_id = dock.get_tool()
	var paint_mode = dock.is_paint_mode_enabled()
	root.grid_snap = dock.get_grid_snap()

	# Displacement paint intercept — must come before regular paint so that
	# displacement surfaces get the stroke when paint mode is active.
	# Only activates when: paint mode ON + Displacement section expanded +
	# a displaced face is selected.
	if _disp_paint_active or _should_start_disp_paint(event, root):
		var dr = _handle_disp_paint_input(event, root, target_camera, target_pos)
		if dr != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return dr

	# Paint mode intercept
	if paint_mode:
		var r = _handle_paint_input(event, root, target_camera, target_pos)
		if r != EditorPlugin.AFTER_GUI_INPUT_PASS:
			return r

	# External tool dispatch
	if _tool_registry:
		var ext_result = _tool_registry.dispatch_input(event, target_camera, target_pos)
		if ext_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Vertex editing mode intercept
	if _vertex_mode and root.vertex_system:
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

	# Hover update
	if tool_id == 1 and event is InputEventMouseMotion:
		root.update_hover(target_camera, target_pos)
	elif tool_id != 1:
		root.clear_hover()

	# Mouse button handling
	if event is InputEventMouseButton:
		if tool_id != 1:
			root.set_shift_pressed(event.shift_pressed)
			root.set_alt_pressed(event.alt_pressed)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			return _handle_rmb_cancel(root, tool_id)
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


func _deactivate_external_tool() -> void:
	if _tool_registry and _tool_registry.has_active_external_tool():
		_tool_registry.deactivate_current()


func _on_builtin_tool_changed() -> void:
	_deactivate_external_tool()
	if _vertex_mode:
		var root = active_root if active_root else _get_level_root()
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


func _on_dock_selection_clear() -> void:
	hf_selection.clear()


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
	# Operation replay toggle (Ctrl+Shift+T)
	if event.keycode == KEY_T and event.ctrl_pressed and event.shift_pressed:
		if _operation_replay and is_instance_valid(_operation_replay):
			_operation_replay.toggle_visible()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# External tool keyboard dispatch first — external tools can override keys
	if _tool_registry and _tool_registry.has_active_external_tool():
		var ext_result = _tool_registry.dispatch_keyboard(event)
		if ext_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return ext_result

	if _keymap.matches("delete", event):
		var deleted = _delete_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if deleted else EditorPlugin.AFTER_GUI_INPUT_PASS
	if _keymap.matches("duplicate", event):
		_duplicate_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("group", event):
		_group_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("ungroup", event):
		_ungroup_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("hollow", event):
		if hf_selection.is_empty():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_hollow_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("move_to_floor", event):
		if hf_selection.is_empty():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_move_selected_to_floor(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("move_to_ceiling", event):
		if hf_selection.is_empty():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_move_selected_to_ceiling(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("clip", event):
		if hf_selection.is_empty():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_clip_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("carve", event):
		if hf_selection.is_empty():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_carve_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("merge", event):
		if hf_selection.size() < 2:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_merge_selected(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Nudge keys
	var nudge = _get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO:
		_nudge_selected(root, nudge)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Tool switch shortcuts
	if _keymap.matches("tool_draw", event):
		_deactivate_external_tool()
		if dock.tool_draw:
			dock.tool_draw.button_pressed = true
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("tool_select", event):
		_deactivate_external_tool()
		if dock.tool_select:
			dock.tool_select.button_pressed = true
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("tool_extrude_up", event):
		_deactivate_external_tool()
		dock.set_extrude_tool(1)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if _keymap.matches("tool_extrude_down", event):
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
		_apply_last_texture(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Select Similar — Shift+S selects matching faces/brushes
	if _keymap.matches("select_similar", event):
		_select_similar(root)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Selection Filter popup — Shift+F opens the filter popover
	if _keymap.matches("selection_filter", event):
		_show_selection_filter()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Quick Save as Prefab — Ctrl+Shift+P
	if event.keycode == KEY_P and event.ctrl_pressed and event.shift_pressed:
		_quick_save_prefab(root, false)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Cycle Prefab Variant — Ctrl+Shift+V
	if event.keycode == KEY_V and event.ctrl_pressed and event.shift_pressed:
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
		elif _keymap.matches("paint_blend", event):
			paint_key = 4
		if paint_key >= 0:
			dock.set_paint_tool(paint_key)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Axis lock (non-select tools only)
	if tool_id != 1:
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
		_toggle_vertex_mode(root)
		_show_coach_mark_for_action("vertex_edit")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# External tool shortcuts
	if _tool_registry:
		var ext_id = _tool_registry.check_shortcut(event.keycode)
		if ext_id >= 0 and active_root:
			_tool_registry.activate_tool(
				ext_id, active_root, last_3d_camera, undo_redo_manager, _record_history
			)
			_show_coach_mark_for_tool_id(ext_id)
			_update_hud_context()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_rmb_cancel(root: Node, tool_id: int) -> int:
	if tool_id == 2 or tool_id == 3:
		root.cancel_extrude()
	else:
		root.cancel_drag()
	numeric_buffer = ""
	select_drag_active = false
	select_dragging = false
	_update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	_update_hud_context()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func _handle_select_mouse(
	event: InputEventMouseButton,
	root: Node,
	cam: Camera3D,
	pos: Vector2,
	paint_mode: bool,
) -> int:
	var face_select = dock.is_face_select_mode_enabled()
	if event.pressed:
		if face_select:
			# Start drag tracking for possible marquee face selection
			select_drag_origin = pos
			select_drag_active = true
			select_dragging = false
			select_additive = (
				event.shift_pressed
				or event.ctrl_pressed
				or event.meta_pressed
				or Input.is_key_pressed(KEY_SHIFT)
				or Input.is_key_pressed(KEY_CTRL)
				or Input.is_key_pressed(KEY_META)
			)
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var active_mat = dock.get_active_material()
		if paint_mode and active_mat:
			var painted = root.pick_brush(cam, pos, false)
			if painted:
				_paint_brush_with_undo(root, painted, active_mat)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		select_drag_origin = pos
		select_drag_active = true
		select_dragging = false
		select_additive = (
			event.shift_pressed
			or event.ctrl_pressed
			or event.meta_pressed
			or Input.is_key_pressed(KEY_SHIFT)
			or Input.is_key_pressed(KEY_CTRL)
			or Input.is_key_pressed(KEY_META)
		)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	# Mouse release
	var selection_action := false
	if select_drag_active:
		if select_dragging:
			# Marquee box selection
			if face_select:
				_select_faces_in_rect(root, cam, select_drag_origin, pos, select_additive)
			else:
				_select_nodes_in_rect(root, cam, select_drag_origin, pos, select_additive)
			selection_action = true
		elif face_select:
			# Single click — select individual face
			var face_handled = root.select_face_at_screen(cam, pos, select_additive)
			if face_handled:
				selection_action = true
		else:
			var picked = root.pick_brush(cam, pos)
			_select_node(picked, select_additive)
			selection_action = true
	select_drag_active = false
	select_dragging = false
	_update_marquee_overlay(Vector2.ZERO, Vector2.ZERO, false)
	return (
		EditorPlugin.AFTER_GUI_INPUT_STOP if selection_action else EditorPlugin.AFTER_GUI_INPUT_PASS
	)


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
	var face_select = dock.is_face_select_mode_enabled()
	if tool_id == 1 and select_drag_active and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		if not select_dragging and select_drag_origin.distance_to(pos) >= select_drag_threshold:
			select_dragging = true
		if select_dragging:
			_update_marquee_overlay(select_drag_origin, pos, true)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if (tool_id == 2 or tool_id == 3) and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		root.update_extrude(cam, pos)
		_update_hud_context()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if tool_id == 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
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
	_vertex_mode = not _vertex_mode
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
				_vertex_drag_ref_y = pick.world_midpoint.y
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
			_vertex_drag_ref_y = pick.world_pos.y
			vs.begin_drag(pick.world_pos)
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
			# Project mouse delta to world-space movement
			var delta = _vertex_screen_to_world_delta(
				cam, _vertex_drag_start, pos, root, _vertex_drag_ref_y
			)
			if delta.length() > 0.001:
				# Snap delta
				if root.grid_snap > 0.0:
					delta = Vector3(
						snappedf(delta.x, root.grid_snap),
						snappedf(delta.y, root.grid_snap),
						snappedf(delta.z, root.grid_snap)
					)
				# Apply axis lock (AxisLock enum: NONE=0, X=1, Y=2, Z=3)
				if root.input_state.axis_lock == 1:  # X
					delta = Vector3(delta.x, 0, 0)
				elif root.input_state.axis_lock == 2:  # Y
					delta = Vector3(0, delta.y, 0)
				elif root.input_state.axis_lock == 3:  # Z
					delta = Vector3(0, 0, delta.z)
				vs.cancel_drag()
				vs.begin_drag(Vector3.ZERO)
				vs.move_vertices(delta)
			_update_vertex_overlay(root, cam)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if vs.sub_mode == vs.VertexSubMode.EDGE:
			vs.update_edge_hover(cam, pos)
		else:
			vs.update_hover(cam, pos)
		_update_vertex_overlay(root, cam)

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _vertex_screen_to_world_delta(
	cam: Camera3D, start_screen: Vector2, end_screen: Vector2, root: Node, ref_y: float = 0.0
) -> Vector3:
	# Project screen movement onto a horizontal plane at the picked vertex's Y
	# height, so dragging works correctly for elevated geometry and all view angles.
	var start_origin = cam.project_ray_origin(start_screen)
	var start_dir = cam.project_ray_normal(start_screen)
	var end_origin = cam.project_ray_origin(end_screen)
	var end_dir = cam.project_ray_normal(end_screen)
	var start_pos = _intersect_y_plane(start_origin, start_dir, ref_y)
	var end_pos = _intersect_y_plane(end_origin, end_dir, ref_y)
	if start_pos == null or end_pos == null:
		return Vector3.ZERO
	return end_pos - start_pos


func _intersect_y_plane(origin: Vector3, dir: Vector3, y: float) -> Variant:
	if abs(dir.y) < 0.0001:
		return null
	var t = (y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


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
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if select_drag_active:
			select_drag_active = false
			select_dragging = false
		hf_selection.clear()
		var selection = get_editor_interface().get_selection()
		if selection:
			selection.clear()
		if dock:
			dock.set_selection_count(0)
			dock.set_selection_nodes([])
		_update_hud_context()
		event.accept()
		return
	if not event.ctrl_pressed:
		return
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	var nudge = _get_nudge_direction(event.keycode)
	if nudge != Vector3.ZERO:
		_nudge_selected(root, nudge)
		event.accept()


func _select_node(node: Node, additive: bool = false) -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	var toggle = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	# Expand grouped nodes
	var expanded: Array = [node] if node else []
	var root = active_root if active_root else _get_level_root()
	if node and root and root.visgroup_system:
		var group_id = root.visgroup_system.get_group_of(node)
		if group_id != "":
			expanded = root.visgroup_system.get_group_members(group_id)
	if not additive:
		hf_selection.clear()
		for n in expanded:
			if n and not hf_selection.has(n):
				hf_selection.append(n)
	else:
		_sync_hf_selection_if_empty()
		for n in expanded:
			if n:
				if toggle and hf_selection.has(n):
					hf_selection.erase(n)
				elif not hf_selection.has(n):
					hf_selection.append(n)
	if not additive and node == null:
		hf_selection.clear()
	_apply_hf_selection(selection)


func _select_nodes_in_rect(
	root: Node, camera: Camera3D, from: Vector2, to: Vector2, additive: bool
) -> void:
	if not root or not camera:
		return
	var rect = Rect2(from, to - from).abs()
	var nodes: Array = []
	if root:
		nodes = root._iter_pick_nodes()
	var picked: Array = []
	for node in nodes:
		if not (node is Node3D):
			continue
		if root and root.is_brush_node(node):
			pass
		elif root and root.is_entity_node(node):
			pass
		else:
			continue
		var bounds = _node_screen_bounds(camera, node as Node3D, root)
		if bounds.size == Vector2.ZERO:
			continue
		if (
			rect.intersects(bounds)
			or bounds.has_point(rect.position)
			or bounds.has_point(rect.position + rect.size)
		):
			picked.append(node)
	if not additive and picked.is_empty():
		hf_selection.clear()
		var selection = get_editor_interface().get_selection()
		if selection:
			selection.clear()
		return
	_apply_selection_list(picked, additive)


func _apply_selection_list(nodes: Array, additive: bool) -> void:
	var selection = get_editor_interface().get_selection()
	if not selection:
		return
	if not additive:
		hf_selection.clear()
	else:
		_sync_hf_selection_if_empty()
	for node in nodes:
		if node and not hf_selection.has(node):
			hf_selection.append(node)
	_apply_hf_selection(selection)


func _apply_hf_selection(selection: EditorSelection) -> void:
	selection.clear()
	for node in hf_selection:
		if is_instance_valid(node):
			selection.add_node(node)


func _sync_hf_selection_if_empty() -> void:
	if not hf_selection.is_empty():
		return
	var selection = get_editor_interface().get_selection()
	if selection:
		hf_selection = selection.get_selected_nodes()


func _project_to_screen(camera: Camera3D, position: Vector3) -> Variant:
	if camera.is_position_behind(position):
		return null
	return camera.unproject_position(position)


func _node_screen_bounds(camera: Camera3D, node: Node3D, root: Node) -> Rect2:
	if not camera or not node:
		return Rect2()
	var visuals: Array = []
	if root:
		root._gather_visual_instances(node, visuals)
	else:
		_gather_visual_instances_local(node, visuals)
	if visuals.is_empty():
		var fallback = _project_to_screen(camera, node.global_transform.origin)
		return Rect2(fallback - Vector2.ONE, Vector2.ONE * 2.0) if fallback != null else Rect2()
	var min_pt = Vector2(INF, INF)
	var max_pt = Vector2(-INF, -INF)
	var had_point = false
	for visual in visuals:
		if not (visual is VisualInstance3D):
			continue
		var vis := visual as VisualInstance3D
		var aabb = vis.get_aabb()
		var corners = [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
			aabb.position + Vector3(0.0, aabb.size.y, 0.0),
			aabb.position + Vector3(0.0, 0.0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
			aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
			aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
			aabb.position + aabb.size
		]
		var center_world = vis.global_transform * aabb.get_center()
		if camera.is_position_behind(center_world):
			var all_behind = true
			for corner in corners:
				if not camera.is_position_behind(vis.global_transform * corner):
					all_behind = false
					break
			if all_behind:
				continue
		for corner in corners:
			var world_pos = vis.global_transform * corner
			var screen = _project_to_screen(camera, world_pos)
			if screen == null:
				continue
			had_point = true
			min_pt.x = min(min_pt.x, screen.x)
			min_pt.y = min(min_pt.y, screen.y)
			max_pt.x = max(max_pt.x, screen.x)
			max_pt.y = max(max_pt.y, screen.y)
	if not had_point:
		return Rect2()
	var size = max_pt - min_pt
	if size == Vector2.ZERO:
		size = Vector2.ONE * 2.0
		min_pt -= Vector2.ONE
	return Rect2(min_pt, size)


func _gather_visual_instances_local(node: Node, out: Array) -> void:
	if not node:
		return
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		_gather_visual_instances_local(child, out)


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


func _collect_brushes(root: Node) -> Array:
	var brushes: Array = []
	var nodes: Array = (
		root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else root.get_children()
	)
	for node in nodes:
		if node is DraftBrush:
			brushes.append(node)
	return brushes


func _pick_face_material(root: Node) -> void:
	if not last_3d_camera or not dock:
		return
	var cam = last_3d_camera
	var pos = last_3d_mouse_pos
	var ray_origin = cam.project_ray_origin(pos)
	var ray_dir = cam.project_ray_normal(pos)
	var brushes: Array = _collect_brushes(root)
	var hit = FaceSelector.intersect_brushes(brushes, ray_origin, ray_dir)
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
	root: Node, camera: Camera3D, from: Vector2, to: Vector2, additive: bool
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
		var faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		var key: String = _face_key_for(brush)
		var indices: Array = face_sel.get(key, []) if additive else []
		for i in range(faces.size()):
			var face = faces[i]
			if not face:
				continue
			var center := _face_screen_center(camera, brush, face)
			if center != Vector2(-1, -1) and rect.has_point(center):
				if not indices.has(i):
					indices.append(i)
		if not indices.is_empty():
			face_sel[key] = indices
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
	if _marquee_overlay and is_instance_valid(_marquee_overlay):
		_marquee_overlay.set_rect(from, to, active)


## Lightweight Control that draws a semi-transparent selection rectangle.
class _MarqueeOverlay:
	extends Control

	var _from := Vector2.ZERO
	var _to := Vector2.ZERO
	var _active := false

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_rect(from: Vector2, to: Vector2, active: bool) -> void:
		_from = from
		_to = to
		_active = active
		queue_redraw()

	func _draw() -> void:
		if not _active:
			return
		var rect = Rect2(_from, _to - _from).abs()
		# Fill
		draw_rect(rect, Color(0.3, 0.6, 1.0, 0.12))
		# Border
		draw_rect(rect, Color(0.3, 0.6, 1.0, 0.7), false, 1.5)


func _delete_selected(root: Node) -> bool:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			if info.is_empty():
				continue
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
	if brush_ids.is_empty():
		return false
	hf_selection.clear()
	selection.clear()
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Delete Brushes",
		"delete_brushes_by_id",
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)
	return true


func _duplicate_selected(root: Node) -> void:
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var infos: Array = []
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.build_duplicate_info(node, Vector3(step, 0.0, 0.0))
			if not info.is_empty():
				infos.append(info)
	if infos.is_empty():
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Duplicate Brushes",
		"create_brushes_from_infos",
		[infos],
		false,
		Callable(self, "_record_history")
	)
	hf_selection.clear()
	selection.clear()
	if root:
		for info in infos:
			var dup = root.find_brush_by_id(info.get("brush_id", ""))
			if dup:
				hf_selection.append(dup)
				selection.add_node(dup)


func _nudge_selected(root: Node, dir: Vector3) -> void:
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	var selection = get_editor_interface().get_selection()
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and node is Node3D and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var brush_id = str(info.get("brush_id", ""))
			if brush_id != "":
				brush_ids.append(brush_id)
	if brush_ids.is_empty():
		return
	var offset = dir * step
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Nudge Brushes",
		"nudge_brushes_by_id",
		[brush_ids, offset],
		false,
		Callable(self, "_record_history"),
		"nudge"
	)


func _group_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.size() < 2 or not root or not root.visgroup_system:
		return
	var group_name = "group_%d" % Time.get_ticks_usec()
	root.visgroup_system.group_selection(group_name, nodes)
	_record_history("Group Selection")
	if dock:
		dock.refresh_visgroup_ui()


func _ungroup_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty() or not root or not root.visgroup_system:
		return
	root.visgroup_system.ungroup_nodes(nodes)
	_record_history("Ungroup Selection")
	if dock:
		dock.refresh_visgroup_ui()


func _hollow_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	var thickness = dock.get_hollow_thickness() if dock else 4.0
	var check: HFOpResult = root.can_hollow_brush(brush_id, thickness)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Hollow",
		"hollow_brush_by_id",
		[brush_id, thickness],
		false,
		Callable(self, "_record_history")
	)


func _merge_selected(root: Node) -> void:
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
		return
	var check: HFOpResult = root.can_merge_brushes(brush_ids)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Merge Brushes",
		"merge_brushes_by_ids",
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)


func _move_selected_to_floor(root: Node) -> void:
	_move_selected_vertical(root, "Move to Floor", "move_brushes_to_floor")


func _move_selected_to_ceiling(root: Node) -> void:
	_move_selected_vertical(root, "Move to Ceiling", "move_brushes_to_ceiling")


func _move_selected_vertical(root: Node, action_name: String, method_name: String) -> void:
	var nodes = _current_selection_nodes()
	var brush_ids: Array = []
	for node in nodes:
		if node and root.is_brush_node(node):
			var info = root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		action_name,
		method_name,
		[brush_ids],
		false,
		Callable(self, "_record_history")
	)


func _clip_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return
	var info = root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	# Default clip: split along Y axis at center
	var center = info.get("center", Vector3.ZERO)
	var split_pos = center.y if center is Vector3 else 0.0
	var check: HFOpResult = root.can_clip_brush(brush_id, 1, split_pos)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return
	HFUndoHelper.commit(
		_get_undo_redo(),
		root,
		"Clip Brush",
		"clip_brush_by_id",
		[brush_id, 1, split_pos],
		false,
		Callable(self, "_record_history")
	)


func _carve_selected(root: Node) -> void:
	var nodes = _current_selection_nodes()
	if nodes.is_empty():
		return
	for node in nodes:
		if not root.is_brush_node(node):
			continue
		var info = root.get_brush_info_from_node(node)
		var brush_id = str(info.get("brush_id", ""))
		if brush_id == "":
			continue
		HFUndoHelper.commit(
			_get_undo_redo(),
			root,
			"Carve",
			"carve_with_brush",
			[brush_id],
			false,
			Callable(self, "_record_history")
		)


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
		if node is CSGShape3D:
			brush_nodes.append(node)
		elif node.has_meta("is_entity"):
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
	var node: Node3D = hf_selection[0]
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
	var node: Node3D = hf_selection[0]
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
	var node: Node3D = hf_selection[0]
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
	# Raycast to find the face under the drop position.
	var brushes: Array = _collect_brushes(root)
	var hit = FaceSelector.intersect_brushes(
		brushes, camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos)
	)
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
		"set_player_start":
			if dock:
				dock._on_spawn_set_primary()
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


func _on_context_toggle_operation() -> void:
	if dock:
		if dock.mode_add.button_pressed:
			dock.mode_subtract.button_pressed = true
		else:
			dock.mode_add.button_pressed = true
		_update_hud_context()


func _on_context_tool_switch(tool_id: int) -> void:
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


func _on_hotkey_palette_action(action: String) -> void:
	var root = active_root if active_root else _get_level_root()
	if not root:
		return
	match action:
		"tool_draw":
			_deactivate_external_tool()
			if dock and dock.tool_draw:
				dock.tool_draw.button_pressed = true
		"tool_select":
			_deactivate_external_tool()
			if dock and dock.tool_select:
				dock.tool_select.button_pressed = true
		"tool_extrude_up":
			_deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(1)
		"tool_extrude_down":
			_deactivate_external_tool()
			if dock:
				dock.set_extrude_tool(-1)
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
		"paint_blend":
			if dock:
				dock.set_paint_tool(4)  # K key = Bucket Fill tool
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
		"select_similar":
			_select_similar(root)
		"apply_last_texture":
			_apply_last_texture(root)
		"selection_filter":
			_show_selection_filter()
	_show_coach_mark_for_action(action)
	_update_hud_context()


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
		"tool_extrude_up", "tool_extrude_down":
			coach_key = "extrude"
		"paint_bucket", "paint_erase", "paint_ramp", "paint_line", "paint_blend":
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
	if root.drag_system and root.drag_system.input_state:
		var ist: HFInputStateType = root.drag_system.input_state
		# Only reset transient preview modes that own temporary scene nodes.
		# VERTEX_EDIT and IDLE are left alone — see HFInputState.is_transient_preview_mode().
		if HFInputStateType.is_transient_preview_mode(ist.mode):
			ist._force_reset()
	# Subtract preview may reference stale brush data — rebuild
	if root.subtract_preview and root.subtract_preview.is_enabled():
		root.subtract_preview.request_update()


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


func _create_level_root() -> Node:
	var scene = get_editor_interface().get_edited_scene_root()
	if not scene:
		return null
	var root = LevelRootType.new()
	root.name = "LevelRoot"
	scene.add_child(root)
	root.owner = scene
	active_root = root
	var selection = get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(root)
	hf_selection.clear()
	hf_selection.append(root)
	return root
