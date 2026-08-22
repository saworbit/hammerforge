@tool
class_name HFDockPaintHandler
extends RefCounted
## Paint-tab handlers extracted from dock.gd (layers, heightmap, scatter, sculpt).

const HFBrushToHeightmap = preload("paint/hf_brush_to_heightmap.gd")
const HFScatterBrush = preload("paint/hf_scatter_brush.gd")
const HFPaintLayer = preload("paint/hf_paint_layer.gd")
const HFPaintLayerManager = preload("paint/hf_paint_layer_manager.gd")
const HFPaintGrid = preload("paint/hf_paint_grid.gd")
const HFStroke = preload("paint/hf_stroke.gd")
const DraftBrush = preload("brush_instance.gd")


static func on_paint_layer_selected(dock: Object, index: int) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.set_active_paint_layer(index)
	dock._refresh_paint_layers()


static func on_paint_layer_add(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.add_paint_layer()
	dock._refresh_paint_layers()


static func on_paint_layer_rename(dock: Object) -> void:
	if dock == null or not dock.level_root or not dock.paint_layer_select:
		return
	var idx = dock.paint_layer_select.selected
	if idx < 0:
		return
	var current_name = dock.paint_layer_select.get_item_text(idx)
	var dialog = AcceptDialog.new()
	dialog.title = "Rename Layer"
	var line_edit = LineEdit.new()
	line_edit.text = current_name
	line_edit.select_all()
	dialog.add_child(line_edit)
	dialog.confirmed.connect(
		func():
			if not is_instance_valid(dock):
				return
			var new_name = line_edit.text.strip_edges()
			if new_name != "" and new_name != current_name:
				dock.level_root.rename_paint_layer(idx, new_name)
				dock._refresh_paint_layers()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free(), CONNECT_DEFERRED)
	dock.add_child(dialog)
	dialog.popup_centered(Vector2i(300, 80))
	line_edit.grab_focus()


static func on_paint_layer_remove(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.remove_active_paint_layer()
	dock._refresh_paint_layers()


static func on_heightmap_import(dock: Object) -> void:
	if dock and dock.heightmap_import_dialog:
		dock.heightmap_import_dialog.popup_centered(Vector2i(600, 400))


static func on_heightmap_import_selected(dock: Object, path: String) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.import_heightmap(path)


static func on_heightmap_generate(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.generate_heightmap_noise()


static func on_heightmap_convert(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Convert to Heightmap", dock.DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	var brushes: Array = []
	for node in dock._selection_nodes:
		if is_instance_valid(node) and dock.level_root.is_brush_node(node):
			brushes.append(node)
	if brushes.is_empty():
		dock.level_root.emit_signal("user_message", "Select brushes first to convert to heightmap", 1)
		return
	var converter := HFBrushToHeightmap.new()
	var settings := HFBrushToHeightmap.ConvertSettings.new()
	if dock.level_root.get("grid_snap") and dock.level_root.grid_snap > 0:
		settings.cell_size = dock.level_root.grid_snap
	if dock.height_scale_spin:
		settings.height_scale = dock.height_scale_spin.value
	var result := converter.convert(brushes, settings)
	if result.error != "":
		dock.level_root.emit_signal("user_message", "Convert failed: " + result.error, 2)
		return
	if not dock.level_root.get("paint_layers") or not dock.level_root.paint_layers:
		dock.level_root.emit_signal("user_message", "Convert failed: no paint layer manager", 2)
		return
	var mgr: HFPaintLayerManager = dock.level_root.paint_layers
	if mgr.base_grid:
		var grid := mgr.base_grid.duplicate() as HFPaintGrid
		if grid:
			grid.layer_y = result.layer.grid.layer_y if result.layer.grid else 0.0
			grid.cell_size = result.layer.grid.cell_size if result.layer.grid else grid.cell_size
			result.layer.grid = grid
	result.layer.chunk_size = mgr.chunk_size
	result.layer.name = "Layer_%s" % str(result.layer.layer_id)
	mgr.add_child(result.layer)
	mgr.layers.append(result.layer)
	mgr.active_layer_index = mgr.layers.size() - 1
	if dock.level_root.has_signal("paint_layer_changed"):
		dock.level_root.paint_layer_changed.emit(mgr.active_layer_index)
	if (
		dock.level_root.get("paint_system")
		and dock.level_root.paint_system.has_method("regenerate_paint_layers")
	):
		dock.level_root.paint_system.regenerate_paint_layers()
	dock.level_root.emit_signal(
		"user_message",
		(
			"Converted %d brushes to heightmap layer '%s'"
			% [result.brush_count, result.layer.display_name]
		),
		0
	)
	dock._refresh_paint_layers()


static func on_scatter_mesh_pick(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tres,*.res,*.obj,*.glb,*.gltf", "Mesh Resources")
	dialog.file_selected.connect(
		func(path: String) -> void:
			if is_instance_valid(dock):
				dock._scatter_mesh_path = path
				if dock.scatter_mesh_btn:
					var fname := path.get_file()
					dock.scatter_mesh_btn.text = fname if fname != "" else "Pick Mesh..."
			dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dock.add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


static func build_scatter_settings(dock: Object) -> HFScatterBrush.ScatterSettings:
	var s := HFScatterBrush.ScatterSettings.new()
	if dock == null:
		return s
	if dock._scatter_mesh_path != "" and ResourceLoader.exists(dock._scatter_mesh_path):
		var res = load(dock._scatter_mesh_path)
		if res is Mesh:
			s.mesh = res
	if dock.scatter_density_spin:
		s.density = dock.scatter_density_spin.value
	if dock.scatter_radius_spin:
		s.radius = dock.scatter_radius_spin.value
	if dock.scatter_min_height_spin:
		s.min_height = dock.scatter_min_height_spin.value
	if dock.scatter_max_height_spin:
		s.max_height = dock.scatter_max_height_spin.value
	if dock.scatter_max_slope_spin:
		s.max_slope = dock.scatter_max_slope_spin.value
	if dock.scatter_scale_min_spin and dock.scatter_scale_max_spin:
		s.scale_range = Vector2(dock.scatter_scale_min_spin.value, dock.scatter_scale_max_spin.value)
	if dock.scatter_align_normal:
		s.align_to_normal = dock.scatter_align_normal.button_pressed
	if dock.scatter_random_rotation:
		s.random_rotation = dock.scatter_random_rotation.button_pressed
	if dock.scatter_shape_select:
		s.shape = dock.scatter_shape_select.get_selected_id()
	if dock.scatter_spline_width_spin:
		s.spline_width = dock.scatter_spline_width_spin.value
	if dock.scatter_preview_select:
		s.preview_mode = dock.scatter_preview_select.get_selected_id()
	if s.shape == HFScatterBrush.BrushShape.SPLINE:
		var pts := PackedVector3Array()
		for node in dock._selection_nodes:
			if is_instance_valid(node) and node is Node3D:
				pts.append(node.global_position)
		s.spline_points = pts
	return s


static func get_active_paint_layer(dock: Object) -> HFPaintLayer:
	if dock == null or not dock.level_root:
		return null
	if dock.level_root.get("paint_layers") and dock.level_root.paint_layers:
		return dock.level_root.paint_layers.get_active_layer()
	return null


static func on_scatter_preview(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Scatter Preview", dock.DockSelectionRequirement.NATIVE_ALLOWED
	):
		return
	var layer = get_active_paint_layer(dock)
	if not layer:
		dock.level_root.emit_signal("user_message", "No active paint layer — add one first", 1)
		return
	var settings = build_scatter_settings(dock)
	var brush := HFScatterBrush.new()
	var result: HFScatterBrush.ScatterResult
	if settings.shape == HFScatterBrush.BrushShape.CIRCLE:
		var center := Vector3.ZERO
		if dock._selection_nodes.size() > 0 and is_instance_valid(dock._selection_nodes[0]):
			center = dock._selection_nodes[0].global_position
		result = brush.scatter_circle(center, layer, settings)
	else:
		if settings.spline_points.size() < 2:
			scatter_clear_preview(dock)
			_set_scatter_result(dock, [])
			dock.level_root.emit_signal(
				"user_message", "Spline scatter requires 2+ selected nodes to define the path", 1
			)
			return
		result = brush.scatter_spline(layer, settings)

	_set_scatter_result(dock, result.transforms)
	scatter_clear_preview(dock)
	var mm := brush.build_preview(result.transforms, settings)
	if mm:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "_ScatterPreview"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mmi.material_override = mat
		dock.level_root.add_child(mmi)
		dock._scatter_preview_node = mmi
	var msg := "%d instances (%d filtered)" % [result.transforms.size(), result.rejected_count]
	dock.level_root.emit_signal("user_message", "Scatter preview: " + msg, 0)


static func on_scatter_commit(dock: Object) -> void:
	if dock == null or not dock.level_root:
		return
	if not dock._guard_selection_action(
		"Scatter Commit", dock.DockSelectionRequirement.NATIVE_ALLOWED
	):
		return
	if dock._scatter_last_result.is_empty():
		on_scatter_preview(dock)
		if dock._scatter_last_result.is_empty():
			dock.level_root.emit_signal("user_message", "No scatter instances to commit", 1)
			return
	var settings = build_scatter_settings(dock)
	if not settings.mesh:
		dock.level_root.emit_signal("user_message", "Pick a mesh first", 1)
		return
	var brush := HFScatterBrush.new()
	scatter_clear_preview(dock)
	var parent: Node3D = dock.level_root
	if dock.level_root.get("generated_floors") and dock.level_root.generated_floors:
		parent = dock.level_root.generated_floors.get_parent()
	brush.commit(dock._scatter_last_result, settings, parent)
	dock.level_root.emit_signal(
		"user_message", "Scattered %d instances" % dock._scatter_last_result.size(), 0
	)
	_set_scatter_result(dock, [])


static func on_scatter_clear(dock: Object) -> void:
	if dock == null:
		return
	scatter_clear_preview(dock)
	_set_scatter_result(dock, [])


static func _set_scatter_result(dock: Object, transforms) -> void:
	var typed: Array[Transform3D] = []
	for t in transforms:
		typed.append(t)
	dock._scatter_last_result = typed


static func scatter_clear_preview(dock: Object) -> void:
	if dock == null:
		return
	if dock._scatter_preview_node and is_instance_valid(dock._scatter_preview_node):
		if dock._scatter_preview_node.get_parent():
			dock._scatter_preview_node.get_parent().remove_child(dock._scatter_preview_node)
		dock._scatter_preview_node.queue_free()
		dock._scatter_preview_node = null


static func on_sculpt_tool_toggled(dock: Object, pressed: bool, tool_id: int) -> void:
	if dock == null or not dock.level_root or not dock.level_root.paint_tool:
		return
	var btns = [
		dock._sculpt_raise_btn,
		dock._sculpt_lower_btn,
		dock._sculpt_smooth_btn,
		dock._sculpt_flatten_btn
	]
	var ids = [
		HFStroke.Tool.SCULPT_RAISE,
		HFStroke.Tool.SCULPT_LOWER,
		HFStroke.Tool.SCULPT_SMOOTH,
		HFStroke.Tool.SCULPT_FLATTEN
	]
	if pressed:
		for i in range(btns.size()):
			if ids[i] != tool_id and btns[i]:
				btns[i].set_pressed_no_signal(false)
		dock.level_root.paint_tool.tool = tool_id
	else:
		dock.level_root.paint_tool.tool = HFStroke.Tool.PAINT


static func on_sculpt_strength_changed(dock: Object, value: float) -> void:
	if dock and dock.level_root and dock.level_root.paint_tool:
		dock.level_root.paint_tool.sculpt_strength = value


static func on_sculpt_radius_changed(dock: Object, value: float) -> void:
	if dock and dock.level_root and dock.level_root.paint_tool:
		dock.level_root.paint_tool.sculpt_radius = value


static func on_sculpt_falloff_changed(dock: Object, value: float) -> void:
	if dock and dock.level_root and dock.level_root.paint_tool:
		dock.level_root.paint_tool.sculpt_falloff = value


static func on_height_scale_changed(dock: Object, value: float) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.set_heightmap_scale(value)


static func on_layer_y_changed(dock: Object, value: float) -> void:
	if dock == null or not dock.level_root:
		return
	dock.level_root.set_layer_y(value)


static func on_blend_strength_changed(dock: Object, value: float) -> void:
	if dock == null or not dock.level_root or not dock.level_root.paint_tool:
		return
	dock.level_root.paint_tool.blend_strength = value


static func on_region_enable_toggled(dock: Object, enabled: bool) -> void:
	if dock == null or dock._region_settings_refreshing:
		return
	if not dock.level_root:
		return
	dock.level_root.set_region_streaming_enabled(enabled)


static func on_region_size_changed(dock: Object, value: float) -> void:
	if dock == null or dock._region_settings_refreshing:
		return
	if not dock.level_root:
		return
	dock.level_root.set_region_size_cells(int(value))


static func on_region_radius_changed(dock: Object, value: float) -> void:
	if dock == null or dock._region_settings_refreshing:
		return
	if not dock.level_root:
		return
	dock.level_root.set_region_streaming_radius(int(value))


static func on_region_memory_changed(dock: Object, value: float) -> void:
	if dock == null or dock._region_settings_refreshing:
		return
	if not dock.level_root:
		return
	dock.level_root.set_region_memory_budget_mb(int(value))


static func on_region_grid_toggled(dock: Object, enabled: bool) -> void:
	if dock == null or dock._region_settings_refreshing:
		return
	if not dock.level_root:
		return
	dock.level_root.set_region_show_grid(enabled)


static func on_blend_slot_selected(dock: Object, index: int) -> void:
	if dock == null or not dock.level_root or not dock.level_root.paint_tool or not dock.blend_slot_select:
		return
	var slot_id = dock.blend_slot_select.get_item_id(index)
	dock.level_root.paint_tool.blend_slot = int(slot_id)


static func on_terrain_slot_pressed(dock: Object, slot: int) -> void:
	if dock == null or not dock.terrain_slot_texture_dialog:
		return
	dock._terrain_slot_pick_index = slot
	dock.terrain_slot_texture_dialog.popup_centered(Vector2i(600, 400))


static func on_terrain_slot_texture_selected(dock: Object, path: String) -> void:
	if dock == null or dock._terrain_slot_pick_index < 0:
		return
	if not dock.level_root or not dock.level_root.paint_layers:
		return
	var layer = dock.level_root.paint_layers.get_active_layer()
	if not layer:
		return
	layer._ensure_terrain_slots()
	layer.terrain_slot_paths[dock._terrain_slot_pick_index] = path
	refresh_terrain_slots(dock)
	dock.level_root._regenerate_paint_layers()


static func on_terrain_slot_scale_changed(dock: Object, value: float, slot: int) -> void:
	if dock == null or dock._terrain_slot_refreshing:
		return
	if not dock.level_root or not dock.level_root.paint_layers:
		return
	var layer = dock.level_root.paint_layers.get_active_layer()
	if not layer:
		return
	layer._ensure_terrain_slots()
	var current = float(layer.terrain_slot_uv_scales[slot])
	if is_equal_approx(current, value):
		return
	layer.terrain_slot_uv_scales[slot] = float(value)
	dock.level_root._regenerate_paint_layers()


static func refresh_terrain_slots(dock: Object) -> void:
	if dock == null:
		return
	dock._terrain_slot_refreshing = true
	if not dock.level_root or not dock.level_root.paint_layers:
		set_terrain_slot_controls_enabled(dock, false)
		dock._terrain_slot_refreshing = false
		return
	var layer = dock.level_root.paint_layers.get_active_layer()
	if not layer:
		set_terrain_slot_controls_enabled(dock, false)
		dock._terrain_slot_refreshing = false
		return
	layer._ensure_terrain_slots()
	set_terrain_slot_controls_enabled(dock, true)
	for i in range(dock.terrain_slot_buttons.size()):
		var button = dock.terrain_slot_buttons[i]
		var scale = dock.terrain_slot_scales[i]
		if button:
			var path = layer.terrain_slot_paths[i]
			button.text = terrain_slot_label(path)
		if scale:
			scale.value = float(layer.terrain_slot_uv_scales[i])
	if dock.blend_slot_select and dock.level_root.paint_tool:
		var slot = clamp(dock.level_root.paint_tool.blend_slot, 1, 3)
		dock._select_option_by_id(dock.blend_slot_select, slot)
	dock._terrain_slot_refreshing = false


static func terrain_slot_label(path: String) -> String:
	if path == "":
		return "Texture..."
	return path.get_file()


static func set_terrain_slot_controls_enabled(dock: Object, enabled: bool) -> void:
	if dock == null:
		return
	for button in dock.terrain_slot_buttons:
		if button:
			button.disabled = not enabled
	for spin in dock.terrain_slot_scales:
		if spin:
			spin.editable = enabled
