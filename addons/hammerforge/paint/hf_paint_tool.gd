@tool
class_name HFPaintTool
extends Node

const HFStroke = preload("hf_stroke.gd")
const HFHeightmapSynth = preload("hf_heightmap_synth.gd")
const HFGeneratedModel = preload("hf_generated_model.gd")
const MAX_BUCKET_FILL_CELLS := 500_000

@export var layer_manager: HFPaintLayerManager
var inference: HFInferenceEngine
var geometry: HFGeometrySynth
var reconciler: HFGeneratedReconciler
var heightmap_synth: HFHeightmapSynth
@export var brush_radius_cells: int = 1
@export var brush_shape: int = HFStroke.BrushShape.SQUARE
@export var tool: int = HFStroke.Tool.PAINT
var blend_material_id: int = 1
var blend_strength: float = 0.5
var blend_slot: int = 1  # 1..3 (slot 0 is implicit base)

var synth_settings := HFGeometrySynth.SynthSettings.new()
var inference_settings := HFInferenceEngine.InferenceSettings.new()

var _active_stroke: HFStroke = null
var _painting := false
var _last_cell := Vector2i.ZERO
var _start_cell := Vector2i.ZERO
var _preview_cells: Dictionary = {}  # Dictionary[Vector2i, bool]
var _preview_original: Dictionary = {}  # Dictionary[Vector2i, bool]
var _stroke_dirty: Dictionary = {}  # Dictionary[Vector2i, bool]
var _preview_dirty: Dictionary = {}  # Dictionary[Vector2i, bool]


func handle_input(camera: Camera3D, event: InputEvent, screen_pos: Vector2) -> bool:
	if not camera or not layer_manager:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _begin_stroke(camera, screen_pos)
		if _painting:
			_end_stroke()
			return true
	if event is InputEventMouseMotion:
		if _painting and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			_continue_stroke(camera, screen_pos)
			return true
	return false


func _begin_stroke(camera: Camera3D, screen_pos: Vector2) -> bool:
	var cell = _screen_to_cell(camera, screen_pos)
	if cell == null:
		return false
	_active_stroke = HFStroke.new()
	_active_stroke.tool = tool
	_active_stroke.radius_cells = brush_radius_cells
	_painting = true
	_stroke_dirty.clear()
	_preview_dirty.clear()
	_start_cell = cell
	_last_cell = cell
	if tool == HFStroke.Tool.BUCKET:
		_bucket_fill(cell)
		_painting = false
		_end_stroke()
		return true
	if tool == HFStroke.Tool.PAINT or tool == HFStroke.Tool.ERASE or tool == HFStroke.Tool.BLEND:
		_stamp_cell(cell)
		_collect_dirty_chunks()
		_preview_reconcile()
	else:
		_active_stroke.add_cell(cell, _now_seconds())
		_begin_preview()
	return true


func _continue_stroke(camera: Camera3D, screen_pos: Vector2) -> void:
	var cell = _screen_to_cell(camera, screen_pos)
	if cell == null:
		return
	if cell == _last_cell:
		return
	if tool == HFStroke.Tool.PAINT or tool == HFStroke.Tool.ERASE or tool == HFStroke.Tool.BLEND:
		_stamp_line(_last_cell, cell)
		_collect_dirty_chunks()
		_preview_reconcile()
	else:
		if _active_stroke:
			_active_stroke.add_cell(cell, _now_seconds())
		_update_preview(cell)
	_last_cell = cell


func _end_stroke() -> void:
	_painting = false
	if not _active_stroke:
		return
	if tool == HFStroke.Tool.LINE:
		_commit_preview()
	elif tool == HFStroke.Tool.RECT:
		_commit_preview()
	else:
		_clear_preview_restore()
	_active_stroke.analyse()
	var layer = layer_manager.get_active_layer()
	if not layer:
		_active_stroke = null
		return
	var dirty: Array[Vector2i] = []
	for cid in _stroke_dirty.keys():
		dirty.append(cid)
	_stroke_dirty.clear()
	_preview_dirty.clear()
	if dirty.is_empty():
		_active_stroke = null
		return
	if inference:
		var intent = inference.infer_intent(_active_stroke)
		inference.apply_cleanup(layer, dirty, intent, inference_settings)
		var extra = layer.consume_dirty_chunks()
		if not extra.is_empty():
			for cid in extra:
				if not dirty.has(cid):
					dirty.append(cid)
	if geometry and reconciler:
		if layer.has_heightmap() and heightmap_synth:
			_reconcile_heightmap(layer, dirty)
		else:
			var model = geometry.build_for_chunks(layer, dirty, synth_settings)
			reconciler.reconcile(model, layer.grid, synth_settings, dirty)
	_active_stroke = null


func _screen_to_cell(camera: Camera3D, screen_pos: Vector2) -> Variant:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer or not layer.grid:
		return null
	var grid = layer.grid
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


func _stamp_cell(cell: Vector2i) -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return
	var is_blend := tool == HFStroke.Tool.BLEND
	var filled = tool != HFStroke.Tool.ERASE
	var r = max(0, brush_radius_cells - 1)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if brush_shape == HFStroke.BrushShape.CIRCLE and dx * dx + dy * dy > r * r:
				continue
			var target = cell + Vector2i(dx, dy)
			if is_blend:
				if not layer.get_cell(target):
					continue
				layer.set_cell_material(target, blend_material_id)
				layer.set_cell_blend_slot(target, blend_slot, blend_strength)
			else:
				layer.set_cell(target, filled)
			if _active_stroke:
				_active_stroke.add_cell(target, _now_seconds())


func _stamp_line(a: Vector2i, b: Vector2i) -> void:
	var points = _bresenham(a, b)
	for p in points:
		_stamp_cell(p)


func _stamp_rect(a: Vector2i, b: Vector2i) -> void:
	var min_x = min(a.x, b.x)
	var max_x = max(a.x, b.x)
	var min_y = min(a.y, b.y)
	var max_y = max(a.y, b.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			_stamp_cell(Vector2i(x, y))


func _begin_preview() -> void:
	_preview_cells.clear()
	_preview_original.clear()


func _update_preview(current: Vector2i) -> void:
	if tool == HFStroke.Tool.LINE:
		_apply_preview_cells(_line_cells(_start_cell, current))
	elif tool == HFStroke.Tool.RECT:
		_apply_preview_cells(_rect_cells(_start_cell, current))


func _apply_preview_cells(cells: Array) -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return
	var filled = tool != HFStroke.Tool.ERASE
	var next_set: Dictionary = {}
	for cell in cells:
		next_set[cell] = true
		if not _preview_cells.has(cell):
			if not _preview_original.has(cell):
				_preview_original[cell] = layer.get_cell(cell)
			layer.set_cell(cell, filled)
			_collect_dirty_chunks()
	for cell in _preview_cells.keys():
		if not next_set.has(cell):
			if _preview_original.has(cell):
				layer.set_cell(cell, _preview_original[cell])
				_preview_original.erase(cell)
				_collect_dirty_chunks()
	_preview_cells = next_set
	_preview_reconcile()


func _clear_preview_restore() -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		_preview_cells.clear()
		_preview_original.clear()
		return
	for cell in _preview_original.keys():
		layer.set_cell(cell, _preview_original[cell])
	_collect_dirty_chunks()
	_preview_cells.clear()
	_preview_original.clear()
	_preview_reconcile()


func _commit_preview() -> void:
	if not _active_stroke:
		return
	for cell in _preview_cells.keys():
		_active_stroke.add_cell(cell, _now_seconds())
	_preview_cells.clear()
	_preview_original.clear()


func _line_cells(a: Vector2i, b: Vector2i) -> Array:
	return _bresenham(a, b)


func _rect_cells(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = []
	var min_x = min(a.x, b.x)
	var max_x = max(a.x, b.x)
	var min_y = min(a.y, b.y)
	var max_y = max(a.y, b.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			cells.append(Vector2i(x, y))
	return cells


func _bucket_fill(start: Vector2i) -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return
	var target_filled = layer.get_cell(start)
	var fill_value = not target_filled
	var stack: Array = [start]
	var visited: Dictionary = {}
	var guard = 0
	while not stack.is_empty():
		var cell = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true
		if layer.get_cell(cell) != target_filled:
			continue
		layer.set_cell(cell, fill_value)
		if _active_stroke:
			_active_stroke.add_cell(cell, _now_seconds())
		stack.append(cell + Vector2i(1, 0))
		stack.append(cell + Vector2i(-1, 0))
		stack.append(cell + Vector2i(0, 1))
		stack.append(cell + Vector2i(0, -1))
		guard += 1
		if guard > MAX_BUCKET_FILL_CELLS:
			break
	_collect_dirty_chunks()
	_preview_reconcile()


func _bresenham(a: Vector2i, b: Vector2i) -> Array:
	var points: Array = []
	var x0 = a.x
	var y0 = a.y
	var x1 = b.x
	var y1 = b.y
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return points


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _collect_dirty_chunks() -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return
	var dirty = layer.consume_dirty_chunks()
	for cid in dirty:
		_stroke_dirty[cid] = true
		_preview_dirty[cid] = true


func _preview_reconcile() -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer or not geometry or not reconciler:
		return
	var dirty: Array[Vector2i] = []
	for cid in _preview_dirty.keys():
		dirty.append(cid)
	_preview_dirty.clear()
	if dirty.is_empty():
		return
	if layer.has_heightmap() and heightmap_synth:
		_reconcile_heightmap(layer, dirty)
	else:
		var model = geometry.build_for_chunks(layer, dirty, synth_settings)
		reconciler.reconcile(model, layer.grid, synth_settings, dirty)


func build_heightmap_model(layer: HFPaintLayer, chunk_ids: Array) -> HFGeneratedModel:
	var model := HFGeneratedModel.new()
	var hm_results = heightmap_synth.build_for_chunks(layer, chunk_ids, synth_settings)
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
	var wall_model = geometry.build_for_chunks(layer, chunk_ids, synth_settings)
	model.walls = wall_model.walls
	return model


func _reconcile_heightmap(layer: HFPaintLayer, dirty: Array[Vector2i]) -> void:
	var model = build_heightmap_model(layer, dirty)
	reconciler.reconcile(model, layer.grid, synth_settings, dirty)
