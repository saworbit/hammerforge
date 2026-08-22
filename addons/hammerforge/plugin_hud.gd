@tool
class_name HFPluginHud
extends RefCounted
## HUD, mode banner, and context-toolbar state extracted from plugin.gd.

const HFInputStateType = preload("input_state.gd")
const DraftBrush = preload("brush_instance.gd")
## plugin.SelectionScope.MIXED
const SCOPE_MIXED := 3


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
		hud.update_grid_snap(root.grid_snap)
	# Update context toolbar and hotkey palette state
	update_context_toolbar_state(plugin, root, tool_id_ctx)


static func update_context_toolbar_state(plugin: Object, root: Node, tool_id: int) -> void:
	if plugin == null:
		return
	if not plugin._context_toolbar and not plugin._hotkey_palette:
		return
	var dock = plugin.get("dock")
	var registry = plugin.get("_tool_registry")
	var state := {}
	state["has_root"] = root != null
	state["tool"] = tool_id
	state["paint_mode"] = dock.is_paint_mode_enabled() if dock else false
	state["vertex_mode"] = plugin._vertex_mode
	state["is_subtract"] = dock.get_operation() != 0 if dock else false  # 0 = UNION
	state["has_active_external_tool"] = (
		registry.has_active_external_tool() if registry else false
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
	var selection_nodes = plugin._current_selection_nodes()
	state["mixed_selection"] = (
		plugin.classify_selection_scope(selection_nodes, root) == SCOPE_MIXED if root else false
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
	state["bake_preview_active"] = plugin._bake_preview_active
	state["bake_disabled"] = dock._bake_disabled if dock else false

	# Prefab instance info for context toolbar badge
	if root and root.prefab_system and not plugin.hf_selection.is_empty():
		var first_node = plugin.hf_selection[0]
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

	if plugin._context_toolbar:
		plugin._context_toolbar.update_state(state)
		# Feed favorite materials to the face-context thumbnail strip
		if face_count > 0 and dock and dock.material_browser:
			plugin._context_toolbar.set_favorite_materials(dock.material_browser.get_favorite_infos(5))
	if plugin._hotkey_palette and plugin._hotkey_palette.visible:
		var palette_state := state.duplicate()
		palette_state["tool"] = plugin.hotkey_palette_tool_context(tool_id, plugin._vertex_mode)
		plugin._hotkey_palette.update_state(palette_state)
