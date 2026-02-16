@tool
extends RefCounted
class_name HFPaintSystem

const DraftBrush = preload("../brush_instance.gd")
const FaceData = preload("../face_data.gd")
const FaceSelector = preload("../face_selector.gd")
const SurfacePaint = preload("../surface_paint.gd")
const HFPaintGrid = preload("../paint/hf_paint_grid.gd")
const HFPaintLayerManager = preload("../paint/hf_paint_layer_manager.gd")
const HFPaintTool = preload("../paint/hf_paint_tool.gd")
const HFInferenceEngine = preload("../paint/hf_inference_engine.gd")
const HFGeometrySynth = preload("../paint/hf_geometry_synth.gd")
const HFGeneratedReconciler = preload("../paint/hf_reconciler.gd")
const HFStroke = preload("../paint/hf_stroke.gd")
const HFHeightmapIO = preload("../paint/hf_heightmap_io.gd")
const HFHeightmapSynth = preload("../paint/hf_heightmap_synth.gd")
const HFGeneratedModel = preload("../paint/hf_generated_model.gd")
const HFTerrainRegionManager = preload("../paint/hf_region_manager.gd")
const HFLevelIO = preload("../hflevel_io.gd")

var root: Node3D
var region_manager: HFTerrainRegionManager
var region_streaming_enabled: bool = false
var region_memory_budget_mb: int = 256
var region_show_grid: bool = false
var region_overlay_material: Material = null


func _init(level_root: Node3D) -> void:
	root = level_root
	region_manager = HFTerrainRegionManager.new()


func handle_paint_input(
	camera: Camera3D,
	event: InputEvent,
	screen_pos: Vector2,
	operation: int,
	size: Vector3,
	paint_tool_id: int = -1,
	paint_radius_cells: int = -1,
	paint_brush_shape: int = 1
) -> bool:
	if not Engine.is_editor_hint():
		return false
	if not root.paint_tool:
		return false
	if not root.paint_tool or not root.paint_layers:
		return false
	_sync_region_manager()
	var layer = root.paint_layers.get_active_layer()
	root.paint_tool.brush_shape = paint_brush_shape
	if paint_radius_cells > 0:
		root.paint_tool.brush_radius_cells = paint_radius_cells
	elif layer and layer.grid:
		var cell_size = max(layer.grid.cell_size, 0.1)
		var radius_cells = max(1, int(round(size.x / cell_size)))
		root.paint_tool.brush_radius_cells = radius_cells
	if paint_tool_id >= 0:
		root.paint_tool.tool = paint_tool_id
	else:
		root.paint_tool.tool = (
			HFStroke.Tool.PAINT if operation == CSGShape3D.OPERATION_UNION else HFStroke.Tool.ERASE
		)
	if region_streaming_enabled:
		var cell = _screen_to_cell(camera, screen_pos)
		if cell != null:
			_ensure_regions_for_cell(cell)
	return root.paint_tool.handle_input(camera, event, screen_pos)


func get_paint_layer_names() -> Array:
	var names: Array = []
	if not root.paint_layers:
		return names
	for layer in root.paint_layers.layers:
		if layer:
			names.append(str(layer.layer_id))
	return names


func set_region_streaming_enabled(value: bool) -> void:
	if region_streaming_enabled == value:
		return
	region_streaming_enabled = value
	if region_streaming_enabled:
		load_initial_regions()
	_update_region_overlay()


func set_region_show_grid(value: bool) -> void:
	region_show_grid = value
	_update_region_overlay()


func set_region_size_cells(value: int) -> void:
	region_manager.region_size_cells = max(64, value)


func set_region_streaming_radius(value: int) -> void:
	region_manager.streaming_radius = clamp(value, 0, 8)


func set_region_memory_budget_mb(value: int) -> void:
	region_memory_budget_mb = max(32, value)


func get_region_settings() -> Dictionary:
	return {
		"enabled": region_streaming_enabled,
		"region_size_cells": region_manager.region_size_cells,
		"streaming_radius": region_manager.streaming_radius,
		"memory_budget_mb": region_memory_budget_mb,
		"show_grid": region_show_grid
	}


func get_loaded_regions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for rid in region_manager.loaded_regions.keys():
		out.append(rid)
	return out


func load_initial_regions() -> void:
	if not region_streaming_enabled:
		return
	_ensure_regions_for_cell(Vector2i.ZERO)


func get_paint_memory_bytes() -> int:
	if not root.paint_layers:
		return 0
	var total := 0
	for layer in root.paint_layers.layers:
		if layer:
			total += layer.get_memory_bytes()
	return total


func get_active_paint_layer_index() -> int:
	return root.paint_layers.active_layer_index if root.paint_layers else 0


func set_active_paint_layer(index: int) -> void:
	if not root.paint_layers:
		return
	root.paint_layers.set_active_layer(index)


func add_paint_layer() -> void:
	if not root.paint_layers:
		return
	var new_id = next_paint_layer_id()
	root.paint_layers.create_layer(StringName(new_id), root.grid_plane_origin.y)
	root.paint_layers.active_layer_index = root.paint_layers.layers.size() - 1


func remove_active_paint_layer() -> void:
	if not root.paint_layers:
		return
	if root.paint_layers.layers.size() <= 1:
		return
	var idx = root.paint_layers.active_layer_index
	root.paint_layers.remove_layer(idx)
	regenerate_paint_layers()


func next_paint_layer_id() -> String:
	var base = "layer_"
	var index = root.paint_layers.layers.size() if root.paint_layers else 0
	var seen: Dictionary = {}
	if root.paint_layers:
		for layer in root.paint_layers.layers:
			if layer:
				seen[str(layer.layer_id)] = true
	while true:
		var candidate = "%s%d" % [base, index]
		if not seen.has(candidate):
			return candidate
		index += 1
	return "%s0" % base


func handle_surface_paint_input(
	camera: Camera3D,
	event: InputEvent,
	mouse_pos: Vector2,
	radius_uv: float,
	strength: float,
	layer_idx: int
) -> bool:
	if not root.surface_paint:
		root._setup_surface_paint()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			root.input_state.begin_surface_paint()
			paint_surface_at(camera, mouse_pos, radius_uv, strength, layer_idx)
			return true
		if root.input_state.is_surface_painting():
			root.input_state.end_surface_paint()
			return true
	if event is InputEventMouseMotion:
		if (
			root.input_state.is_surface_painting()
			and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
		):
			paint_surface_at(camera, mouse_pos, radius_uv, strength, layer_idx)
			return true
	return false


func paint_surface_at(
	camera: Camera3D, mouse_pos: Vector2, radius_uv: float, strength: float, layer_idx: int
) -> void:
	if not camera:
		return
	var hit = pick_face(camera, mouse_pos)
	if hit.is_empty():
		return
	var brush = hit.get("brush", null)
	var face_idx = int(hit.get("face_idx", -1))
	var uv = hit.get("uv", Vector2.ZERO)
	if not brush or face_idx < 0 or face_idx >= brush.faces.size():
		return
	uv.x = clamp(uv.x, 0.0, 1.0)
	uv.y = clamp(uv.y, 0.0, 1.0)
	var face: FaceData = brush.faces[face_idx]
	root.surface_paint.paint_at_uv(face, layer_idx, uv, radius_uv, strength)
	brush.rebuild_preview()


func pick_face(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	if not camera:
		return {}
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos).normalized()
	var brushes: Array = []
	for node in root._iter_pick_nodes():
		if node is DraftBrush and root.is_brush_node(node):
			brushes.append(node)
	return FaceSelector.intersect_brushes(brushes, ray_origin, ray_dir)


func select_face_at_screen(camera: Camera3D, mouse_pos: Vector2, additive: bool) -> bool:
	var hit = pick_face(camera, mouse_pos)
	if hit.is_empty():
		if not additive:
			clear_face_selection()
		return false
	var brush = hit.get("brush", null)
	var face_idx = int(hit.get("face_idx", -1))
	if brush and face_idx >= 0:
		toggle_face_selection(brush, face_idx, additive)
		return true
	return false


func toggle_face_selection(brush: DraftBrush, face_idx: int, additive: bool) -> void:
	if not brush:
		return
	if not additive:
		root.face_selection.clear()
	var key = face_key(brush)
	var indices: Array = root.face_selection.get(key, [])
	var idx = indices.find(face_idx)
	if idx >= 0:
		indices.remove_at(idx)
	else:
		indices.append(face_idx)
	root.face_selection[key] = indices
	apply_face_selection()


func clear_face_selection() -> void:
	root.face_selection.clear()
	apply_face_selection()


func get_face_selection() -> Dictionary:
	return root.face_selection.duplicate(true)


func get_primary_selected_face() -> Dictionary:
	for key in root.face_selection.keys():
		var indices: Array = root.face_selection.get(key, [])
		if indices.is_empty():
			continue
		var brush = root._find_brush_by_key(str(key))
		if brush and indices[0] != null:
			return {"brush": brush, "face_idx": int(indices[0])}
	return {}


func assign_material_to_selected_faces(material_index: int) -> void:
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = root.face_selection.get(key, [])
		var typed: Array[int] = []
		for idx in indices:
			typed.append(int(idx))
		brush.assign_material_to_faces(material_index, typed)


func apply_face_selection() -> void:
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var key = face_key(brush)
		var indices: Array = root.face_selection.get(key, [])
		brush.set_selected_faces(PackedInt32Array(indices))


func face_key(brush: DraftBrush) -> String:
	if brush == null:
		return ""
	if brush.brush_id != "":
		return brush.brush_id
	return str(brush.get_instance_id())


func regenerate_paint_layers() -> void:
	if not root.paint_tool or not root.paint_layers:
		return
	if not root.paint_tool.geometry or not root.paint_tool.reconciler:
		return
	root._clear_generated()
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		var chunk_ids = layer.get_chunk_ids()
		if chunk_ids.is_empty():
			continue
		if layer.has_heightmap() and root.paint_tool.heightmap_synth:
			var model := HFGeneratedModel.new()
			var hm_results = root.paint_tool.heightmap_synth.build_for_chunks(
				layer, chunk_ids, root.paint_tool.synth_settings
			)
			for hr in hm_results:
				var hf := HFGeneratedModel.HeightmapFloor.new()
				hf.id = hr.id
				hf.mesh = hr.mesh
				hf.transform = hr.transform
				hf.blend_image = hr.blend_image
				if hr.blend_image:
					hf.blend_texture = ImageTexture.create_from_image(hr.blend_image)
				hf.slot_textures = hr.slot_textures
				hf.slot_uv_scales = hr.slot_uv_scales
				hf.slot_tints = hr.slot_tints
				model.heightmap_floors.append(hf)
			var wall_model = root.paint_tool.geometry.build_for_chunks(
				layer, chunk_ids, root.paint_tool.synth_settings
			)
			model.walls = wall_model.walls
			root.paint_tool.reconciler.reconcile(
				model, layer.grid, root.paint_tool.synth_settings, chunk_ids
			)
		else:
			var model = root.paint_tool.geometry.build_for_chunks(
				layer, chunk_ids, root.paint_tool.synth_settings
			)
			root.paint_tool.reconciler.reconcile(
				model, layer.grid, root.paint_tool.synth_settings, chunk_ids
			)
	if region_streaming_enabled:
		_rebuild_loaded_regions_from_layers()


func restore_paint_layers(data: Array, active_index: int) -> void:
	if not root.paint_layers:
		root._setup_paint_system()
	if not root.paint_layers:
		return
	if region_streaming_enabled:
		region_manager.loaded_regions.clear()
		region_manager.region_index.clear()
	root.paint_layers.clear_layers()
	root._clear_generated()
	if data.is_empty():
		root.paint_layers.create_layer(&"layer_0", root.grid_plane_origin.y)
		root.paint_layers.active_layer_index = 0
		return
	for entry in data:
		if not (entry is Dictionary):
			continue
		var layer_id = StringName(str(entry.get("id", "layer_0")))
		var chunk_size = int(entry.get("chunk_size", root.paint_layers.chunk_size))
		var grid_data = entry.get("grid", {})
		var layer_y = (
			float(grid_data.get("layer_y", root.grid_plane_origin.y))
			if grid_data is Dictionary
			else root.grid_plane_origin.y
		)
		var layer = root.paint_layers.create_layer(layer_id, layer_y)
		layer.chunk_size = chunk_size
		if grid_data is Dictionary and layer.grid:
			layer.grid.cell_size = float(grid_data.get("cell_size", layer.grid.cell_size))
			layer.grid.origin = grid_data.get("origin", layer.grid.origin)
			layer.grid.basis = grid_data.get("basis", layer.grid.basis)
			layer.grid.layer_y = float(grid_data.get("layer_y", layer.grid.layer_y))
		layer._ensure_terrain_slots()
		var slot_paths = entry.get("terrain_slot_paths", [])
		if slot_paths is Array:
			layer.terrain_slot_paths = slot_paths.duplicate()
		var slot_scales = entry.get("terrain_slot_uv_scales", [])
		if slot_scales is Array:
			layer.terrain_slot_uv_scales = slot_scales.duplicate()
		var slot_tints = entry.get("terrain_slot_tints", [])
		if slot_tints is Array:
			layer.terrain_slot_tints = slot_tints.duplicate()
		layer._ensure_terrain_slots()
		var hm_b64 = str(entry.get("heightmap_b64", ""))
		if hm_b64 != "":
			layer.heightmap = HFHeightmapIO.decode_from_base64(hm_b64)
			layer.height_scale = float(entry.get("height_scale", 10.0))
		var chunks = entry.get("chunks", [])
		if chunks is Array:
			for chunk in chunks:
				if not (chunk is Dictionary):
					continue
				var cx = int(chunk.get("cx", 0))
				var cy = int(chunk.get("cy", 0))
				var bytes = chunk.get("bits", [])
				var bits = PackedByteArray()
				if bytes is Array:
					bits.resize(bytes.size())
					for i in range(bytes.size()):
						bits[i] = int(bytes[i])
				layer.set_chunk_bits(Vector2i(cx, cy), bits)
				var mat_bytes = chunk.get("material_ids", [])
				if mat_bytes is Array and not mat_bytes.is_empty():
					var mat_ids = PackedByteArray()
					mat_ids.resize(mat_bytes.size())
					for i in range(mat_bytes.size()):
						mat_ids[i] = int(mat_bytes[i])
					layer.set_chunk_material_ids(Vector2i(cx, cy), mat_ids)
				var blend_bytes = chunk.get("blend_weights", [])
				if blend_bytes is Array and not blend_bytes.is_empty():
					var blends = PackedByteArray()
					blends.resize(blend_bytes.size())
					for i in range(blend_bytes.size()):
						blends[i] = int(blend_bytes[i])
					layer.set_chunk_blend_weights(Vector2i(cx, cy), blends)
				var blend2_bytes = chunk.get("blend_weights_2", [])
				if blend2_bytes is Array and not blend2_bytes.is_empty():
					var blends2 = PackedByteArray()
					blends2.resize(blend2_bytes.size())
					for i in range(blend2_bytes.size()):
						blends2[i] = int(blend2_bytes[i])
					layer.set_chunk_blend_weights_slot(Vector2i(cx, cy), 2, blends2)
				var blend3_bytes = chunk.get("blend_weights_3", [])
				if blend3_bytes is Array and not blend3_bytes.is_empty():
					var blends3 = PackedByteArray()
					blends3.resize(blend3_bytes.size())
					for i in range(blend3_bytes.size()):
						blends3[i] = int(blend3_bytes[i])
					layer.set_chunk_blend_weights_slot(Vector2i(cx, cy), 3, blends3)
	if root.paint_layers.layers.size() > 0:
		root.paint_layers.active_layer_index = clamp(
			active_index, 0, root.paint_layers.layers.size() - 1
		)
	regenerate_paint_layers()


func _rebuild_loaded_regions_from_layers() -> void:
	if not region_streaming_enabled:
		return
	region_manager.loaded_regions.clear()
	if not root.paint_layers:
		return
	var cs := region_manager.chunk_size
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		for cid in layer.get_chunk_ids():
			var cell := Vector2i(cid.x * cs, cid.y * cs)
			var rid := region_manager.region_id_from_cell(cell)
			region_manager.mark_loaded(rid)
	_update_region_overlay()


func import_heightmap(path: String) -> void:
	var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
	if not layer:
		return
	var img := HFHeightmapIO.load_from_file(path)
	if img:
		layer.heightmap = img
		regenerate_paint_layers()


func generate_heightmap_noise(settings: Dictionary = {}) -> void:
	var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
	if not layer:
		return
	var s := max(layer.chunk_size * 4, 256)
	layer.heightmap = HFHeightmapIO.generate_noise(s, s, settings)
	regenerate_paint_layers()


func set_heightmap_scale(value: float) -> void:
	var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
	if not layer:
		return
	layer.height_scale = value
	regenerate_paint_layers()


func set_layer_y(value: float) -> void:
	var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
	if not layer or not layer.grid:
		return
	layer.grid.layer_y = value
	regenerate_paint_layers()


func set_region_base_path(hflevel_path: String) -> void:
	if hflevel_path == "":
		return
	var abs = hflevel_path
	if hflevel_path.begins_with("res://") or hflevel_path.begins_with("user://"):
		abs = ProjectSettings.globalize_path(hflevel_path)
	region_manager.region_base_path = abs


func _region_dir_for_base_path(base_path: String) -> String:
	var dir = base_path.get_base_dir()
	var name = base_path.get_file().get_basename()
	if name == "":
		name = "level"
	return dir.path_join("%s.hfregions" % name)


func _region_file_path(region_id: Vector2i) -> String:
	if region_manager.region_base_path == "":
		return ""
	var dir = _region_dir_for_base_path(region_manager.region_base_path)
	var file_name = "region_%d_%d.hfr" % [region_id.x, region_id.y]
	return dir.path_join(file_name)


func save_loaded_regions() -> void:
	if not region_streaming_enabled:
		return
	if region_manager.region_base_path == "":
		return
	var dir = _region_dir_for_base_path(region_manager.region_base_path)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	for rid in region_manager.loaded_regions.keys():
		_save_region_file(rid)


func load_region_index(index_data: Dictionary, hflevel_path: String = "") -> void:
	if hflevel_path != "":
		set_region_base_path(hflevel_path)
	if index_data.is_empty():
		return
	region_manager.region_size_cells = int(
		index_data.get("region_size_cells", region_manager.region_size_cells)
	)
	region_manager.streaming_radius = int(
		index_data.get("streaming_radius", region_manager.streaming_radius)
	)
	region_manager.region_index.clear()
	var regions = index_data.get("regions", [])
	if regions is Array:
		for entry in regions:
			if entry is Dictionary:
				var x = int(entry.get("x", 0))
				var y = int(entry.get("y", 0))
				region_manager.region_index[Vector2i(x, y)] = {"has_data": true}


func capture_region_index() -> Dictionary:
	var regions: Array = []
	for rid in region_manager.region_index.keys():
		regions.append({"x": rid.x, "y": rid.y})
	for rid in region_manager.loaded_regions.keys():
		var exists = false
		for entry in regions:
			if int(entry.get("x", 0)) == rid.x and int(entry.get("y", 0)) == rid.y:
				exists = true
				break
		if not exists and _region_has_data(rid):
			regions.append({"x": rid.x, "y": rid.y})
	return {
		"region_size_cells": region_manager.region_size_cells,
		"streaming_radius": region_manager.streaming_radius,
		"regions": regions
	}


func _sync_region_manager() -> void:
	if not region_manager:
		return
	if root.paint_layers:
		region_manager.chunk_size = root.paint_layers.chunk_size
	region_manager.base_grid = root.paint_layers.base_grid if root.paint_layers else null


func _screen_to_cell(camera: Camera3D, screen_pos: Vector2) -> Variant:
	if not camera or not root.paint_layers or not root.paint_layers.base_grid:
		return null
	var grid = root.paint_layers.base_grid
	var plane_point = grid.origin + (grid.basis * Vector3(0.0, grid.layer_y, 0.0))
	var plane_normal = grid.basis.y.normalized()
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var denom = plane_normal.dot(ray_dir)
	if abs(denom) < 0.0001:
		return null
	var t = plane_normal.dot(plane_point - ray_origin) / denom
	if t < 0.0:
		return null
	var hit = ray_origin + ray_dir * t
	return grid.world_to_cell(hit)


func _ensure_regions_for_cell(cell: Vector2i) -> void:
	if not region_streaming_enabled:
		return
	_sync_region_manager()
	var center = region_manager.region_id_from_cell(cell)
	var want = region_manager.region_ids_in_radius(center)
	for rid in want:
		if not region_manager.is_loaded(rid):
			_load_region(rid)
	var loaded = region_manager.loaded_regions.keys()
	for rid in loaded:
		if region_manager.is_pinned(rid):
			continue
		if not want.has(rid):
			_unload_region(rid)
	for rid in want:
		region_manager.last_access[rid] = Time.get_ticks_msec()
	_evict_for_budget(center)
	_update_region_overlay()


func _region_chunk_bounds(region_id: Vector2i) -> Rect2i:
	return region_manager.region_bounds_chunks(region_id)


func _region_has_data(region_id: Vector2i) -> bool:
	if not root.paint_layers:
		return false
	var chunk_bounds = _region_chunk_bounds(region_id)
	var min_chunk = chunk_bounds.position
	var max_chunk = chunk_bounds.position + chunk_bounds.size - Vector2i.ONE
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		for cid in layer.get_chunk_ids():
			if cid.x < min_chunk.x or cid.x > max_chunk.x:
				continue
			if cid.y < min_chunk.y or cid.y > max_chunk.y:
				continue
			return true
	return false


func _estimate_region_bytes(region_id: Vector2i) -> int:
	if not root.paint_layers:
		return 0
	var chunk_bounds = _region_chunk_bounds(region_id)
	var min_chunk = chunk_bounds.position
	var max_chunk = chunk_bounds.position + chunk_bounds.size - Vector2i.ONE
	var total := 0
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		for cid in layer.get_chunk_ids():
			if cid.x < min_chunk.x or cid.x > max_chunk.x:
				continue
			if cid.y < min_chunk.y or cid.y > max_chunk.y:
				continue
			total += layer.get_chunk_bits(cid).size()
			total += layer.get_chunk_material_ids(cid).size()
			total += layer.get_chunk_blend_weights(cid).size()
			total += layer.get_chunk_blend_weights_slot(cid, 2).size()
			total += layer.get_chunk_blend_weights_slot(cid, 3).size()
	return total


func _total_loaded_bytes() -> int:
	var total := 0
	for rid in region_manager.loaded_regions.keys():
		total += _estimate_region_bytes(rid)
	return total


func _evict_for_budget(center_region: Vector2i) -> void:
	var budget_bytes = region_memory_budget_mb * 1024 * 1024
	if budget_bytes <= 0:
		return
	var total = _total_loaded_bytes()
	if total <= budget_bytes:
		return
	var candidates: Array = []
	for rid in region_manager.loaded_regions.keys():
		if region_manager.is_pinned(rid):
			continue
		if rid == center_region:
			continue
		candidates.append(rid)
	candidates.sort_custom(
		func(a, b):
			return (
				int(region_manager.last_access.get(a, 0))
				< int(region_manager.last_access.get(b, 0))
			)
	)
	for rid in candidates:
		var bytes = _estimate_region_bytes(rid)
		_unload_region(rid)
		total -= bytes
		if total <= budget_bytes:
			break


func _load_region(region_id: Vector2i) -> void:
	region_manager.mark_loaded(region_id)
	if not region_streaming_enabled:
		return
	var path = _region_file_path(region_id)
	if path == "" or not FileAccess.file_exists(path):
		return
	var data = HFLevelIO.load_from_path(path)
	if data.is_empty():
		return
	var decoded = HFLevelIO.decode_variant(data)
	if not (decoded is Dictionary):
		return
	region_manager.region_index[region_id] = {"has_data": true}
	var layers = decoded.get("layers", [])
	if not (layers is Array):
		return
	var dirty_chunks: Dictionary = {}
	for entry in layers:
		if not (entry is Dictionary):
			continue
		var layer_id = StringName(str(entry.get("id", "")))
		var layer = _get_layer_by_id(layer_id)
		if not layer:
			continue
		var chunks = entry.get("chunks", [])
		if not (chunks is Array):
			continue
		for chunk in chunks:
			if not (chunk is Dictionary):
				continue
			var cx = int(chunk.get("cx", 0))
			var cy = int(chunk.get("cy", 0))
			var cid = Vector2i(cx, cy)
			var bytes = chunk.get("bits", [])
			var bits = PackedByteArray()
			if bytes is Array:
				bits.resize(bytes.size())
				for i in range(bytes.size()):
					bits[i] = int(bytes[i])
			layer.set_chunk_bits(cid, bits)
			var mat_bytes = chunk.get("material_ids", [])
			if mat_bytes is Array and not mat_bytes.is_empty():
				var mat_ids = PackedByteArray()
				mat_ids.resize(mat_bytes.size())
				for i in range(mat_bytes.size()):
					mat_ids[i] = int(mat_bytes[i])
				layer.set_chunk_material_ids(cid, mat_ids)
			var blend_bytes = chunk.get("blend_weights", [])
			if blend_bytes is Array and not blend_bytes.is_empty():
				var blends = PackedByteArray()
				blends.resize(blend_bytes.size())
				for i in range(blend_bytes.size()):
					blends[i] = int(blend_bytes[i])
				layer.set_chunk_blend_weights(cid, blends)
			var blend2_bytes = chunk.get("blend_weights_2", [])
			if blend2_bytes is Array and not blend2_bytes.is_empty():
				var blends2 = PackedByteArray()
				blends2.resize(blend2_bytes.size())
				for i in range(blend2_bytes.size()):
					blends2[i] = int(blend2_bytes[i])
				layer.set_chunk_blend_weights_slot(cid, 2, blends2)
			var blend3_bytes = chunk.get("blend_weights_3", [])
			if blend3_bytes is Array and not blend3_bytes.is_empty():
				var blends3 = PackedByteArray()
				blends3.resize(blend3_bytes.size())
				for i in range(blend3_bytes.size()):
					blends3[i] = int(blend3_bytes[i])
				layer.set_chunk_blend_weights_slot(cid, 3, blends3)
			dirty_chunks[cid] = true
	var dirty_list: Array[Vector2i] = []
	for cid in dirty_chunks.keys():
		dirty_list.append(cid)
	_reconcile_dirty_chunks(dirty_list)


func _unload_region(region_id: Vector2i) -> void:
	if not root.paint_layers:
		return
	var chunk_bounds = _region_chunk_bounds(region_id)
	var min_chunk = chunk_bounds.position
	var max_chunk = chunk_bounds.position + chunk_bounds.size - Vector2i.ONE
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		var removed = layer.remove_chunks_in_range(min_chunk, max_chunk)
		if not removed.is_empty():
			_reconcile_dirty_chunks(removed, layer)
	region_manager.mark_unloaded(region_id)


func _reconcile_dirty_chunks(dirty: Array[Vector2i], layer_override: HFPaintLayer = null) -> void:
	if dirty.is_empty():
		return
	if not root.paint_tool or not root.paint_tool.geometry or not root.paint_tool.reconciler:
		return
	if layer_override:
		_reconcile_layer(layer_override, dirty)
		return
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		_reconcile_layer(layer, dirty)


func _reconcile_layer(layer: HFPaintLayer, dirty: Array[Vector2i]) -> void:
	if layer.has_heightmap() and root.paint_tool.heightmap_synth:
		var model := HFGeneratedModel.new()
		var hm_results = root.paint_tool.heightmap_synth.build_for_chunks(
			layer, dirty, root.paint_tool.synth_settings
		)
		for hr in hm_results:
			var hf := HFGeneratedModel.HeightmapFloor.new()
			hf.id = hr.id
			hf.mesh = hr.mesh
			hf.transform = hr.transform
			hf.blend_image = hr.blend_image
			if hr.blend_image:
				hf.blend_texture = ImageTexture.create_from_image(hr.blend_image)
			hf.slot_textures = hr.slot_textures
			hf.slot_uv_scales = hr.slot_uv_scales
			hf.slot_tints = hr.slot_tints
			model.heightmap_floors.append(hf)
		var wall_model = root.paint_tool.geometry.build_for_chunks(
			layer, dirty, root.paint_tool.synth_settings
		)
		model.walls = wall_model.walls
		root.paint_tool.reconciler.reconcile(
			model, layer.grid, root.paint_tool.synth_settings, dirty
		)
	else:
		var model = root.paint_tool.geometry.build_for_chunks(
			layer, dirty, root.paint_tool.synth_settings
		)
		root.paint_tool.reconciler.reconcile(
			model, layer.grid, root.paint_tool.synth_settings, dirty
		)


func _get_layer_by_id(layer_id: StringName) -> HFPaintLayer:
	if not root.paint_layers:
		return null
	for layer in root.paint_layers.layers:
		if layer and layer.layer_id == layer_id:
			return layer
	return null


func _save_region_file(region_id: Vector2i) -> void:
	if not root.paint_layers:
		return
	var data: Dictionary = {"version": 1, "region_id": [region_id.x, region_id.y], "layers": []}
	var chunk_bounds = _region_chunk_bounds(region_id)
	var min_chunk = chunk_bounds.position
	var max_chunk = chunk_bounds.position + chunk_bounds.size - Vector2i.ONE
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		var entry: Dictionary = {"id": str(layer.layer_id), "chunks": []}
		for cid in layer.get_chunk_ids():
			if cid.x < min_chunk.x or cid.x > max_chunk.x:
				continue
			if cid.y < min_chunk.y or cid.y > max_chunk.y:
				continue
			var bits = layer.get_chunk_bits(cid)
			var bytes: Array = []
			for b in bits:
				bytes.append(int(b))
			var mat_ids = layer.get_chunk_material_ids(cid)
			var mat_bytes: Array = []
			for b in mat_ids:
				mat_bytes.append(int(b))
			var blends = layer.get_chunk_blend_weights(cid)
			var blend_bytes: Array = []
			for b in blends:
				blend_bytes.append(int(b))
			var blends2 = layer.get_chunk_blend_weights_slot(cid, 2)
			var blend2_bytes: Array = []
			for b in blends2:
				blend2_bytes.append(int(b))
			var blends3 = layer.get_chunk_blend_weights_slot(cid, 3)
			var blend3_bytes: Array = []
			for b in blends3:
				blend3_bytes.append(int(b))
			entry["chunks"].append(
				{
					"cx": cid.x,
					"cy": cid.y,
					"bits": bytes,
					"material_ids": mat_bytes,
					"blend_weights": blend_bytes,
					"blend_weights_2": blend2_bytes,
					"blend_weights_3": blend3_bytes
				}
			)
		if not entry["chunks"].is_empty():
			data["layers"].append(entry)
	if data["layers"].is_empty():
		var path = _region_file_path(region_id)
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var encoded = HFLevelIO.encode_variant(data)
	var path = _region_file_path(region_id)
	if path == "":
		return
	var dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	HFLevelIO.save_to_path(path, encoded, root.hflevel_compress)
	region_manager.region_index[region_id] = {"has_data": true}


func _update_region_overlay() -> void:
	if not root or not root.generated_region_overlay:
		return
	if not region_streaming_enabled or not region_show_grid:
		root.generated_region_overlay.mesh = null
		return
	if not root.paint_layers or not root.paint_layers.base_grid:
		root.generated_region_overlay.mesh = null
		return
	if region_overlay_material == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 0.9, 1.0, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		region_overlay_material = mat
	var grid = root.paint_layers.base_grid
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, region_overlay_material)
	for rid in region_manager.loaded_regions.keys():
		var bounds := region_manager.region_bounds_cells(rid)
		var min_cell := bounds.position
		var max_cell := bounds.position + bounds.size
		var min_uv = grid.cell_to_uv(min_cell)
		var max_uv = grid.cell_to_uv(max_cell)
		var y = grid.layer_y + 0.05
		var p00 = grid.uv_to_world(Vector2(min_uv.x, min_uv.y), y)
		var p10 = grid.uv_to_world(Vector2(max_uv.x, min_uv.y), y)
		var p11 = grid.uv_to_world(Vector2(max_uv.x, max_uv.y), y)
		var p01 = grid.uv_to_world(Vector2(min_uv.x, max_uv.y), y)
		mesh.surface_add_vertex(p00)
		mesh.surface_add_vertex(p10)
		mesh.surface_add_vertex(p10)
		mesh.surface_add_vertex(p11)
		mesh.surface_add_vertex(p11)
		mesh.surface_add_vertex(p01)
		mesh.surface_add_vertex(p01)
		mesh.surface_add_vertex(p00)
	mesh.surface_end()
	root.generated_region_overlay.mesh = mesh
