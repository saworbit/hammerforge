@tool
class_name HFPluginHud
extends RefCounted
## HUD and mode banner extracted from plugin.gd, and the command state handed to
## the context toolbar and the palette.

const HFInputStateType = preload("input_state.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFPluginCommands = preload("plugin_commands.gd")
const HFPluginOverlays = preload("plugin_overlays.gd")
@warning_ignore_restore("shadowed_global_identifier")


static func update_hud_context(plugin: Object) -> void:
	if plugin == null:
		return
	var hud = plugin.get("hud")
	if not hud or not hud.has_method("update_context"):
		return
	var dock = plugin.get("dock")
	var ctx := {}
	var tool_id_ctx = dock.get_tool() if dock else 0
	ctx["tool"] = tool_id_ctx
	ctx["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	ctx["paint_target"] = dock.get_paint_target() if dock else 0
	# X-ray only changes the face marquee, so the HUD names it in Face Select.
	ctx["face_xray"] = (
		dock != null and dock.is_face_select_mode_enabled() and dock.is_face_xray_enabled()
	)
	ctx["mode"] = 0
	ctx["axis_lock"] = 0
	ctx["external_tool_name"] = ""
	ctx["external_shortcuts"] = PackedStringArray()
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if root and root.input_state:
		ctx["mode"] = root.input_state.mode
		ctx["axis_lock"] = root.input_state.axis_lock
	# Update dock mode indicator banner
	if dock:
		var mode_name := "Draw"
		var registry = plugin.get("_tool_registry")
		var active_external = registry.get_active_tool() if registry else null
		if active_external and registry.has_active_external_tool():
			mode_name = active_external.tool_name()
			ctx["external_tool_name"] = mode_name
			ctx["external_shortcuts"] = active_external.get_shortcut_hud_lines()
		elif plugin._vertex_mode:
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
				var height_dims = root.input_state.get_drag_dimensions()
				var height_str = HFInputStateType.format_dimensions(height_dims)
				stage_hint = "Step 2/2: Set height"
				if height_str != "":
					stage_hint += " — " + height_str
			elif root.input_state.is_extruding():
				stage_hint = "Extruding..."
			elif root.input_state.is_surface_painting():
				stage_hint = "Painting..."
		if (
			ctx.get("paint_mode", false)
			and int(ctx.get("paint_target", 0)) == 0
			and root
			and root.get("paint_tool")
		):
			var paint_status: String = root.paint_tool.get_stroke_hud_text()
			if paint_status.is_empty():
				paint_status = root.paint_tool.get_hover_hud_text()
			if not paint_status.is_empty():
				stage_hint = paint_status
		var num_display := ""
		if plugin.numeric_buffer.length() > 0:
			num_display = plugin.numeric_buffer
		dock.set_mode_indicator(mode_name, stage_hint, num_display)
	# Clear stale face hover highlight when not in extrude mode
	if root and tool_id_ctx != 2 and tool_id_ctx != 3:
		if root.has_method("clear_face_hover_highlight"):
			root.clear_face_hover_highlight()
	if plugin.numeric_buffer.length() > 0:
		ctx["numeric"] = plugin.numeric_buffer
	hud.update_context(ctx)
	# Feed grid snap to HUD indicator
	if root and hud.has_method("update_grid_snap"):
		var axis: int = root.grid_system.effective_grid_axis()
		hud.update_grid_snap(
			root.grid_snap, ["X", "Y", "Z"][axis - 1], root.grid_plane_origin[axis - 1]
		)
	# Update context toolbar and hotkey palette state
	update_context_toolbar_state(plugin, root, tool_id_ctx)


static func update_context_toolbar_state(plugin: Object, root: Node, tool_id: int) -> void:
	if plugin == null:
		return
	if not plugin._context_toolbar and not plugin._hotkey_palette:
		return
	var dock = plugin.get("dock")
	var state := HFPluginCommands.build_command_state(plugin, root, tool_id)
	if plugin._context_toolbar:
		plugin._context_toolbar.update_state(state)
		# Feed the favourites to the strip a face or a brush selection shows
		var selected := int(state.get("face_count", 0)) + int(state.get("brush_count", 0))
		if selected > 0 and dock and dock.material_browser:
			plugin._context_toolbar.set_favorite_materials(
				dock.material_browser.get_favorite_infos()
			)
		# Placed only on the viewport's draw-over, the toolbar kept the old
		# context's width after a selection made in the Scene dock, which gives
		# the viewport nothing to redraw for, and its new buttons wrapped into a
		# column down the viewport (#1375).
		HFPluginOverlays.refresh_viewport_overlay_placement(plugin)
	if plugin._hotkey_palette and plugin._hotkey_palette.visible:
		var palette_state := state.duplicate()
		palette_state["tool"] = plugin.hotkey_palette_tool_context(tool_id, plugin._vertex_mode)
		plugin._hotkey_palette.update_state(palette_state)
