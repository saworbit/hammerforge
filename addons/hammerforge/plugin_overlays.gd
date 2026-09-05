@tool
class_name HFPluginOverlays
extends RefCounted
## Overlay lifecycle, viewport drawing, quick-property, and coach-mark behavior.

const HFQuickProperty = preload("ui/hf_quick_property.gd")
const HFCoachMarks = preload("ui/hf_coach_marks.gd")
const HFOperationReplay = preload("ui/hf_operation_replay.gd")
const HFRadialMenu = preload("ui/hf_radial_menu.gd")
const DraftBrush = preload("brush_instance.gd")


static func install_power_user_overlays(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._coach_marks == null:
		plugin._coach_marks = HFCoachMarks.new()
		if plugin.base_control:
			plugin._coach_marks.theme = plugin.base_control.theme
		plugin._coach_marks.set_user_prefs(plugin._user_prefs)
		plugin._coach_marks.guide_dismissed.connect(plugin._on_coach_mark_dismissed)
		plugin.add_control_to_container(
			EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin._coach_marks
		)
	if plugin._operation_replay == null:
		plugin._operation_replay = HFOperationReplay.new()
		if plugin.base_control:
			plugin._operation_replay.theme = plugin.base_control.theme
		plugin._operation_replay.replay_requested.connect(plugin._on_replay_requested)
		plugin.add_control_to_container(
			EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin._operation_replay
		)
		if plugin.dock:
			plugin.dock.set_operation_replay(plugin._operation_replay)
	if plugin._radial_menu == null:
		plugin._radial_menu = HFRadialMenu.new()
		if plugin.base_control:
			plugin._radial_menu.theme = plugin.base_control.theme
		plugin._radial_menu.action_selected.connect(plugin._on_radial_action)
		plugin.add_control_to_container(
			EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin._radial_menu
		)


static func teardown_power_user_overlays(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._coach_marks:
		if is_instance_valid(plugin._coach_marks):
			plugin._coach_marks.guide_dismissed.disconnect(plugin._on_coach_mark_dismissed)
		plugin.remove_control_from_container(
			EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin._coach_marks
		)
		if is_instance_valid(plugin._coach_marks):
			plugin._coach_marks.queue_free()
		plugin._coach_marks = null
	if plugin._operation_replay:
		if is_instance_valid(plugin._operation_replay):
			plugin._operation_replay.replay_requested.disconnect(plugin._on_replay_requested)
		plugin.remove_control_from_container(
			EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin._operation_replay
		)
		if is_instance_valid(plugin._operation_replay):
			plugin._operation_replay.queue_free()
		plugin._operation_replay = null
		if plugin.dock:
			plugin.dock.set_operation_replay(null)
	if plugin._radial_menu:
		if is_instance_valid(plugin._radial_menu):
			plugin._radial_menu.action_selected.disconnect(plugin._on_radial_action)
		plugin.remove_control_from_container(
			EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin._radial_menu
		)
		if is_instance_valid(plugin._radial_menu):
			plugin._radial_menu.queue_free()
		plugin._radial_menu = null


static func update_vertex_overlay(plugin: Object, root: Node) -> void:
	if plugin == null:
		return
	if not plugin._vertex_mode or not root or not root.vertex_system:
		clear_vertex_overlay(plugin)
		return
	var vertex_system = root.vertex_system
	var vertex_data = vertex_system.get_all_vertex_world_positions()
	if vertex_data.is_empty():
		clear_vertex_overlay(plugin)
		return
	ensure_vertex_overlay(plugin, root)
	plugin._vertex_overlay_imesh.clear_surfaces()
	var edge_data = vertex_system.get_all_edge_world_positions()
	if not edge_data.is_empty():
		plugin._vertex_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for edge in edge_data:
			var edge_color := Color(0.5, 0.5, 0.5, 0.5)
			if edge.selected:
				edge_color = Color.ORANGE
			elif edge.hovered:
				edge_color = Color.YELLOW
			plugin._vertex_overlay_imesh.surface_set_color(edge_color)
			plugin._vertex_overlay_imesh.surface_add_vertex(edge.a)
			plugin._vertex_overlay_imesh.surface_set_color(edge_color)
			plugin._vertex_overlay_imesh.surface_add_vertex(edge.b)
		plugin._vertex_overlay_imesh.surface_end()
	plugin._vertex_overlay_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for entry in vertex_data:
		var position: Vector3 = entry.pos
		var color := Color.WHITE
		if entry.selected:
			color = Color.ORANGE
		elif entry.hovered:
			color = Color.YELLOW
		var size := 0.4
		for offset in [
			Vector3(-size, 0, 0),
			Vector3(size, 0, 0),
			Vector3(0, -size, 0),
			Vector3(0, size, 0),
			Vector3(0, 0, -size),
			Vector3(0, 0, size),
		]:
			plugin._vertex_overlay_imesh.surface_set_color(color)
			plugin._vertex_overlay_imesh.surface_add_vertex(position + offset)
	plugin._vertex_overlay_imesh.surface_end()


static func ensure_vertex_overlay(plugin: Object, root: Node) -> void:
	if plugin == null or root == null:
		return
	if plugin._vertex_overlay_mesh and is_instance_valid(plugin._vertex_overlay_mesh):
		return
	plugin._vertex_overlay_mesh = MeshInstance3D.new()
	plugin._vertex_overlay_mesh.name = "_VertexEditOverlay"
	plugin._vertex_overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plugin._vertex_overlay_mesh.material_override = material
	plugin._vertex_overlay_imesh = ImmediateMesh.new()
	plugin._vertex_overlay_mesh.mesh = plugin._vertex_overlay_imesh
	root.add_child(plugin._vertex_overlay_mesh)


static func clear_vertex_overlay(plugin: Object) -> void:
	if plugin == null:
		return
	if plugin._vertex_overlay_mesh and is_instance_valid(plugin._vertex_overlay_mesh):
		if plugin._vertex_overlay_mesh.get_parent():
			plugin._vertex_overlay_mesh.get_parent().remove_child(plugin._vertex_overlay_mesh)
		plugin._vertex_overlay_mesh.queue_free()
		plugin._vertex_overlay_mesh = null
	plugin._vertex_overlay_imesh = null


static func update_marquee_overlay(
	plugin: Object, from: Vector2, to: Vector2, active: bool
) -> void:
	if plugin == null:
		return
	plugin._marquee_overlay_origin = from
	plugin._marquee_overlay_current = to
	plugin._marquee_overlay_active = active
	if plugin.is_inside_tree():
		plugin.update_overlays()


static func draw_marquee_overlay(plugin: Object, viewport_control: Control) -> void:
	if plugin == null or not plugin._marquee_overlay_active or not viewport_control:
		return
	var local_mouse := viewport_control.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, viewport_control.size).has_point(local_mouse):
		return
	var rect := (
		Rect2(
			plugin._marquee_overlay_origin,
			plugin._marquee_overlay_current - plugin._marquee_overlay_origin
		)
		. abs()
	)
	viewport_control.draw_rect(rect, Color(0.3, 0.6, 1.0, 0.12))
	viewport_control.draw_rect(rect, Color(0.3, 0.6, 1.0, 0.7), false, 1.5)


static func handle_double_tap(plugin: Object, keycode: int, root: Node, paint_mode: bool) -> bool:
	match keycode:
		KEY_G:
			var snap_value: float = root.grid_snap if root else 16.0
			show_quick_property(plugin, HFQuickProperty.PropertyType.GRID_SNAP, [snap_value])
			return true
		KEY_B:
			if paint_mode:
				return false
			var size: Vector3 = (
				root.input_state.drag_size_default
				if root and root.input_state
				else Vector3(4, 4, 4)
			)
			show_quick_property(
				plugin, HFQuickProperty.PropertyType.BRUSH_SIZE, [size.x, size.y, size.z]
			)
			return true
		KEY_R:
			if paint_mode:
				var radius: float = plugin.dock.get_surface_paint_radius() if plugin.dock else 5.0
				show_quick_property(plugin, HFQuickProperty.PropertyType.PAINT_RADIUS, [radius])
				return true
	return false


static func show_quick_property(plugin: Object, property_type: int, values: Array) -> void:
	if (
		plugin == null
		or not plugin._quick_property
		or not is_instance_valid(plugin._quick_property)
	):
		return
	plugin._quick_property.show_property(
		property_type, plugin._get_current_overlay_mouse_pos(), values
	)


static func on_quick_property_committed(plugin: Object, property_type: int, values: Array) -> void:
	if plugin == null:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	match property_type:
		HFQuickProperty.PropertyType.GRID_SNAP:
			if plugin.dock and not values.is_empty():
				plugin.dock._apply_grid_snap(float(values[0]))
		HFQuickProperty.PropertyType.BRUSH_SIZE:
			if root and root.input_state and values.size() >= 3:
				root.input_state.drag_size_default = Vector3(values[0], values[1], values[2])
				if plugin.dock:
					plugin.dock.size_x.value = values[0]
					plugin.dock.size_y.value = values[1]
					plugin.dock.size_z.value = values[2]
		HFQuickProperty.PropertyType.PAINT_RADIUS:
			if plugin.dock and not values.is_empty() and plugin.dock.surface_paint_radius:
				plugin.dock.surface_paint_radius.value = float(values[0])


static func show_coach_mark_for_action(plugin: Object, action: String) -> void:
	if plugin == null or not plugin._coach_marks or not is_instance_valid(plugin._coach_marks):
		return
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
		plugin._coach_marks.show_guide(coach_key)


static func show_coach_mark_for_tool_id(plugin: Object, tool_id: int) -> void:
	if (
		plugin == null
		or not plugin._coach_marks
		or not is_instance_valid(plugin._coach_marks)
		or not plugin._tool_registry
	):
		return
	var tool = plugin._tool_registry.get_tool_by_id(tool_id)
	if not tool:
		return
	var tool_name: String = tool.tool_name().to_lower()
	if "polygon" in tool_name:
		plugin._coach_marks.show_guide("polygon")
	elif "path" in tool_name:
		plugin._coach_marks.show_guide("path")
	elif "measure" in tool_name:
		plugin._coach_marks.show_guide("measure")
	elif "decal" in tool_name:
		plugin._coach_marks.show_guide("decal")


# ---------------------------------------------------------------------------
# Viewport context menu
# ---------------------------------------------------------------------------


## Show the viewport context menu at the current mouse position.
## Triggered by Space key (no modifiers). Converts screen coords to window-local
## for PopupMenu.popup() — the only reliable coordinate source since the 3D
## SubViewport's event.position space doesn't match window space.
static func show_viewport_context_menu(plugin: Object, root: Node, tool_id: int) -> void:
	var menu = plugin._viewport_context_menu
	if not menu or not is_instance_valid(menu):
		return
	var state := {}
	build_viewport_state(plugin, state, root, tool_id)
	var screen_pos := DisplayServer.mouse_get_position()
	var win: Window = plugin.get_window()
	var window_pos := Vector2(screen_pos)
	if win:
		window_pos = Vector2(screen_pos - win.position)
	menu.show_at(window_pos, state)


## Summarise what the pointer is over and what is selected, so the menu can show
## only the entries that would actually do something.
static func build_viewport_state(
	plugin: Object, state: Dictionary, root: Node, tool_id: int
) -> void:
	var dock = plugin.dock
	state["has_root"] = root != null
	state["tool"] = tool_id
	state["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	state["vertex_mode"] = plugin._vertex_mode
	state["is_subtract"] = dock.get_operation() != 0 if dock else false
	var input_mode := 0
	if root and root.input_state:
		input_mode = root.input_state.mode
	state["input_mode"] = input_mode
	var selection_nodes: Array = plugin._current_selection_nodes()
	state["mixed_selection"] = (
		plugin.classify_selection_scope(selection_nodes, root) == plugin.SelectionScope.MIXED
		if root
		else false
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
