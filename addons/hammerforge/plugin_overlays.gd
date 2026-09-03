@tool
class_name HFPluginOverlays
extends RefCounted
## Quick-property and coach-mark behavior extracted from plugin.gd.

const HFQuickProperty = preload("ui/hf_quick_property.gd")


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
