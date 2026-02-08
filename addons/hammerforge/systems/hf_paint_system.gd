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

var root: Node3D


func _init(level_root: Node3D) -> void:
	root = level_root


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
	return root.paint_tool.handle_input(camera, event, screen_pos)


func get_paint_layer_names() -> Array:
	var names: Array = []
	if not root.paint_layers:
		return names
	for layer in root.paint_layers.layers:
		if layer:
			names.append(str(layer.layer_id))
	return names


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


func restore_paint_layers(data: Array, active_index: int) -> void:
	if not root.paint_layers:
		root._setup_paint_system()
	if not root.paint_layers:
		return
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
	if root.paint_layers.layers.size() > 0:
		root.paint_layers.active_layer_index = clamp(
			active_index, 0, root.paint_layers.layers.size() - 1
		)
	regenerate_paint_layers()


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
