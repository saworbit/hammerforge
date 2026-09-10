@tool
class_name HFPaintTool
extends Node

signal stroke_committed(changed_cell_count: int)
signal material_picked(material_id: int)

const HFStroke = preload("hf_stroke.gd")
const HFHeightmapSynth = preload("hf_heightmap_synth.gd")
const HFGeneratedModel = preload("hf_generated_model.gd")
const HFAutoConnector = preload("hf_auto_connector.gd")
const HFConnectorTool = preload("hf_connector_tool.gd")
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
var sculpt_strength: float = 5.0
var sculpt_radius: float = 3.0
var sculpt_falloff: float = 0.5  # 0 = hard edge, 1 = soft
var _sculpt_flatten_height: float = 0.0
var _sculpt_flatten_captured := false

var synth_settings := HFGeometrySynth.SynthSettings.new()
var inference_settings := HFInferenceEngine.InferenceSettings.new()
var auto_connector := HFAutoConnector.new()
var connector_settings := HFAutoConnector.Settings.new()
var mirror_x_enabled := false
var mirror_z_enabled := false
var connector_defs: Array = []
var _pending_connector_defs: Array = []

var _active_stroke: HFStroke = null
var _painting := false
var _last_cell := Vector2i.ZERO
var _start_cell := Vector2i.ZERO
var _preview_cells: Dictionary = {}  # Dictionary[Vector2i, bool]
var _preview_original: Dictionary = {}  # Dictionary[Vector2i, bool]
var _stroke_dirty: Dictionary = {}  # Dictionary[Vector2i, bool]
var _preview_dirty: Dictionary = {}  # Dictionary[Vector2i, bool]
var _stroke_erasing := false
## 0 = undecided/free, 1 = X, 2 = Z (the paint grid's Vector2i.y axis).
var _stroke_axis := 0
var _stroke_axis_requested := false
var _stroke_cells: Dictionary = {}  # Dictionary[Vector2i, bool]
var _hover_cell: Variant = null
var _last_committed_cell_count := 0
var _last_committed_cells: Dictionary = {}  # Dictionary[Vector2i, bool]
var _last_committed_layer_index := -1
var _last_rect_size := Vector2i(4, 4)
var _raising_height := false
var _raise_start_screen_y := 0.0
var _raise_start_height := 0.0
var _raise_current_height := 0.0
var _raise_originals: Dictionary = {}


func is_stroke_active() -> bool:
	return _painting


func is_height_gesture_active() -> bool:
	return _raising_height


func finish_stroke_if_active() -> void:
	if _painting:
		_end_stroke()


func cancel_stroke() -> bool:
	if not _painting:
		return false
	_clear_preview_restore()
	_painting = false
	_active_stroke = null
	_stroke_dirty.clear()
	_preview_dirty.clear()
	_stroke_cells.clear()
	_stroke_axis = 0
	_stroke_axis_requested = false
	_stroke_erasing = false
	_last_committed_cell_count = 0
	return true


func cancel_pending_action() -> bool:
	if _raising_height:
		_cancel_height_gesture()
		return true
	if not _pending_connector_defs.is_empty():
		_pending_connector_defs.clear()
		return true
	return false


func handle_input(camera: Camera3D, event: InputEvent, screen_pos: Vector2) -> bool:
	if not camera or not layer_manager:
		if not layer_manager:
			push_warning("HammerForge: paint input ignored — no layer manager")
		return false
	if _raising_height:
		if event is InputEventMouseMotion:
			update_height_gesture(screen_pos.y)
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				confirm_height_gesture()
			return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.is_command_or_control_pressed():
				var pick_cell = _screen_to_cell(camera, screen_pos)
				if pick_cell == null:
					return false
				material_picked.emit(pick_cell_material(pick_cell))
				return true
			return _begin_stroke(camera, screen_pos, event.alt_pressed, event.shift_pressed)
		if _painting:
			_end_stroke()
			return true
	if event is InputEventMouseMotion:
		_hover_cell = _screen_to_cell(camera, screen_pos)
		if _painting and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			_continue_stroke(camera, screen_pos, event.shift_pressed)
			return true
	return false


func _is_sculpt_tool() -> bool:
	return tool >= HFStroke.Tool.SCULPT_RAISE and tool <= HFStroke.Tool.SCULPT_FLATTEN


func _begin_stroke(
	camera: Camera3D, screen_pos: Vector2, temporary_erase: bool = false, axis_lock: bool = false
) -> bool:
	if _is_sculpt_tool():
		return _begin_sculpt_stroke(camera, screen_pos)
	var cell = _screen_to_cell(camera, screen_pos)
	if cell == null:
		return false
	_active_stroke = HFStroke.new()
	_active_stroke.tool = tool
	_active_stroke.radius_cells = brush_radius_cells
	_painting = true
	_stroke_erasing = tool == HFStroke.Tool.ERASE or temporary_erase
	_stroke_axis = 0
	_stroke_axis_requested = axis_lock
	_stroke_cells.clear()
	_last_committed_cell_count = 0
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


func _continue_stroke(camera: Camera3D, screen_pos: Vector2, axis_lock: bool = false) -> void:
	if _is_sculpt_tool():
		var layer = layer_manager.get_active_layer() if layer_manager else null
		if layer:
			_apply_sculpt_at_screen(camera, screen_pos, layer)
		return
	var cell = _screen_to_cell(camera, screen_pos)
	if cell == null:
		return
	_stroke_axis_requested = _stroke_axis_requested or axis_lock
	if tool in [HFStroke.Tool.PAINT, HFStroke.Tool.ERASE, HFStroke.Tool.LINE, HFStroke.Tool.BLEND]:
		cell = _apply_axis_lock(cell, _stroke_axis_requested)
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
	if _is_sculpt_tool():
		var sculpt_changed := _stroke_dirty.size()
		_last_committed_cell_count = sculpt_changed
		_stroke_dirty.clear()
		_stroke_cells.clear()
		_stroke_axis = 0
		_stroke_axis_requested = false
		_stroke_erasing = false
		if sculpt_changed > 0:
			stroke_committed.emit(sculpt_changed)
		return
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
		push_warning("HammerForge: paint stroke ended with no active layer — changes lost")
		_active_stroke = null
		return
	var changed_cell_count := _stroke_cells.size()
	var dirty: Array[Vector2i] = []
	for cid in _stroke_dirty.keys():
		dirty.append(cid)
	_stroke_dirty.clear()
	_preview_dirty.clear()
	if dirty.is_empty():
		_active_stroke = null
		_stroke_cells.clear()
		_stroke_axis = 0
		_stroke_axis_requested = false
		_stroke_erasing = false
		return
	# Inference is deliberately opt-in. The Paint-tab toggle assigns the bounded
	# one-cell cleanup engine; leaving it null preserves authored cells exactly.
	if inference:
		var intent = inference.infer_intent(_active_stroke)
		inference.apply_cleanup(layer, dirty, intent, inference_settings, _stroke_cells)
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
	var generative_footprint := (
		tool in [HFStroke.Tool.PAINT, HFStroke.Tool.RECT] and not _stroke_erasing
	)
	if tool == HFStroke.Tool.RECT and not _stroke_erasing:
		_last_rect_size = Vector2i(
			absi(_last_cell.x - _start_cell.x) + 1, absi(_last_cell.y - _start_cell.y) + 1
		)
	if generative_footprint:
		_last_committed_cells = _stroke_cells.duplicate()
	var active_layer_index := layer_manager.active_layer_index
	if generative_footprint:
		_last_committed_layer_index = active_layer_index
	_active_stroke = null
	_last_committed_cell_count = changed_cell_count
	_stroke_cells.clear()
	_stroke_axis = 0
	_stroke_axis_requested = false
	_stroke_erasing = false
	if generative_footprint:
		_refresh_connector_candidates(active_layer_index)
	stroke_committed.emit(changed_cell_count)


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
	var is_blend := tool == HFStroke.Tool.BLEND and not _stroke_erasing
	var filled = not _stroke_erasing
	var r = max(0, brush_radius_cells - 1)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if brush_shape == HFStroke.BrushShape.CIRCLE and dx * dx + dy * dy > r * r:
				continue
			var base_target = cell + Vector2i(dx, dy)
			for target in _mirrored_cells(base_target):
				if is_blend:
					if not layer.get_cell(target):
						# Blend only works on filled cells — skip unfilled silently during strokes
						continue
					layer.set_cell_material(target, blend_material_id)
					layer.set_cell_blend_slot(target, blend_slot, blend_strength)
				else:
					layer.set_cell(target, filled)
				_record_stroke_cell(target)
				if _active_stroke:
					_active_stroke.add_cell(target, _now_seconds())


func _mirrored_cells(cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	if mirror_x_enabled:
		cells.append(Vector2i(-cell.x - 1, cell.y))
	if mirror_z_enabled:
		var count := cells.size()
		for index in range(count):
			var source := cells[index]
			cells.append(Vector2i(source.x, -source.y - 1))
	var unique: Dictionary = {}
	var out: Array[Vector2i] = []
	for candidate in cells:
		if not unique.has(candidate):
			unique[candidate] = true
			out.append(candidate)
	return out


func _record_stroke_cell(cell: Vector2i) -> void:
	_stroke_cells[cell] = true


func _apply_axis_lock(cell: Vector2i, requested: bool) -> Vector2i:
	if not requested:
		return cell
	if _stroke_axis == 0:
		var delta := cell - _start_cell
		if delta == Vector2i.ZERO:
			return cell
		_stroke_axis = 1 if abs(delta.x) >= abs(delta.y) else 2
	if _stroke_axis == 1:
		return Vector2i(cell.x, _start_cell.y)
	return Vector2i(_start_cell.x, cell.y)


func pick_cell_material(cell: Vector2i) -> int:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return 0
	blend_material_id = layer.get_cell_material(cell)
	return blend_material_id


func get_last_committed_cell_count() -> int:
	return _last_committed_cell_count


func get_preview_cells() -> Array[Vector2i]:
	var source := _last_committed_cells if _raising_height else _stroke_cells
	if not _preview_cells.is_empty() and not _raising_height:
		source = _preview_cells
	var out: Array[Vector2i] = []
	for cell: Vector2i in source:
		out.append(cell)
	return out


func get_raise_preview_height() -> float:
	return _raise_current_height if _raising_height else 0.0


func begin_height_gesture(screen_y: float) -> bool:
	if _painting or _raising_height or _last_committed_cells.is_empty():
		return false
	if (
		_last_committed_layer_index >= 0
		and layer_manager.active_layer_index != _last_committed_layer_index
	):
		return false
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return false
	_raise_originals.clear()
	var first := true
	for cell: Vector2i in _last_committed_cells:
		if not layer.get_cell(cell):
			continue
		var had_override: bool = layer._wall_heights.has(cell)
		var height := layer.get_wall_height(cell, synth_settings.wall_height)
		_raise_originals[cell] = {"had": had_override, "height": height}
		if first:
			_raise_start_height = height
			first = false
	if _raise_originals.is_empty():
		return false
	_raise_start_screen_y = screen_y
	_raise_current_height = _raise_start_height
	_raising_height = true
	_last_committed_cell_count = 0
	return true


func update_height_gesture(screen_y: float) -> void:
	if not _raising_height:
		return
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer:
		return
	var delta_metres := (_raise_start_screen_y - screen_y) / 24.0
	_raise_current_height = maxf(0.25, snappedf(_raise_start_height + delta_metres, 0.25))
	for cell: Vector2i in _raise_originals:
		layer.set_wall_height(cell, _raise_current_height)
	_collect_dirty_chunks()
	_preview_reconcile()


func confirm_height_gesture() -> int:
	if not _raising_height:
		return 0
	var changed := 0
	for cell: Vector2i in _raise_originals:
		if not is_equal_approx(float(_raise_originals[cell]["height"]), _raise_current_height):
			changed += 1
	_raising_height = false
	_raise_originals.clear()
	_last_committed_cell_count = changed
	if changed > 0:
		stroke_committed.emit(changed)
	return changed


func _cancel_height_gesture() -> void:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if layer:
		for cell: Vector2i in _raise_originals:
			var original: Dictionary = _raise_originals[cell]
			if bool(original.get("had", false)):
				layer.set_wall_height(
					cell, float(original.get("height", synth_settings.wall_height))
				)
			else:
				layer.clear_wall_height(cell)
		_collect_dirty_chunks()
		_preview_reconcile()
	_raising_height = false
	_raise_originals.clear()
	_raise_current_height = 0.0
	_last_committed_cell_count = 0


func stamp_room_from_last_rect(anchor: Variant = null) -> int:
	if _painting or _raising_height:
		return 0
	var start: Variant = anchor
	if start == null:
		start = _hover_cell
	if start == null:
		return 0
	var previous_tool := tool
	tool = HFStroke.Tool.RECT
	_active_stroke = HFStroke.new()
	_active_stroke.tool = HFStroke.Tool.RECT
	_painting = true
	_stroke_erasing = false
	_stroke_cells.clear()
	_stroke_dirty.clear()
	_preview_dirty.clear()
	_start_cell = start
	_last_cell = start + _last_rect_size - Vector2i.ONE
	_stamp_rect(_start_cell, _last_cell)
	_collect_dirty_chunks()
	_end_stroke()
	tool = previous_tool
	return _last_committed_cell_count


func confirm_connector_ghosts() -> int:
	var added := 0
	var known: Dictionary = {}
	for definition in connector_defs:
		known[definition.boundary_key()] = true
	for definition in _pending_connector_defs:
		var key: String = definition.boundary_key()
		if known.has(key):
			continue
		known[key] = true
		connector_defs.append(definition)
		added += 1
	_pending_connector_defs.clear()
	_last_committed_cell_count = added
	return added


func get_pending_connector_meshes() -> Array:
	if _pending_connector_defs.is_empty() or not layer_manager:
		return []
	return auto_connector.generate_definitions(_pending_connector_defs, layer_manager)


func capture_connector_defs() -> Array:
	var out: Array = []
	for definition in connector_defs:
		out.append(definition.to_dict())
	return out


func restore_connector_defs(data: Array) -> void:
	connector_defs.clear()
	_pending_connector_defs.clear()
	for entry in data:
		if entry is Dictionary:
			connector_defs.append(HFConnectorTool.ConnectorDef.from_dict(entry))


func _refresh_connector_candidates(active_layer_index: int) -> void:
	_pending_connector_defs.clear()
	if auto_connector and layer_manager and not _last_committed_cells.is_empty():
		_pending_connector_defs = auto_connector.defs_for_touched_cells(
			layer_manager, active_layer_index, _last_committed_cells, connector_settings
		)


func get_stroke_hud_text() -> String:
	if _raising_height:
		return (
			"Raise walls — %s m — Click confirm, Esc cancel" % _format_metres(_raise_current_height)
		)
	if not _painting:
		if not _pending_connector_defs.is_empty():
			return (
				"%d connector ghost%s — Enter confirm, Esc cancel"
				% [
					_pending_connector_defs.size(),
					"" if _pending_connector_defs.size() == 1 else "s"
				]
			)
		return ""
	var cells: Array = _stroke_cells.keys()
	if cells.is_empty():
		cells = [_start_cell]
	var min_cell: Vector2i = cells[0]
	var max_cell: Vector2i = cells[0]
	for cell: Vector2i in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var cell_size := 1.0
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if layer and layer.grid:
		cell_size = layer.grid.cell_size
	var width := float(max_cell.x - min_cell.x + 1) * cell_size
	var depth := float(max_cell.y - min_cell.y + 1) * cell_size
	return (
		"%d cells — %s m × %s m%s"
		% [cells.size(), _format_metres(width), _format_metres(depth), _mirror_hud_suffix()]
	)


func get_hover_hud_text() -> String:
	if _painting or _hover_cell == null:
		return ""
	var footprint := max(1, brush_radius_cells * 2 - 1)
	return (
		"Cell %d, %d — %d×%d footprint%s — Y raise, H room"
		% [_hover_cell.x, _hover_cell.y, footprint, footprint, _mirror_hud_suffix()]
	)


func _mirror_hud_suffix() -> String:
	var axes := PackedStringArray()
	if mirror_x_enabled:
		axes.append("X")
	if mirror_z_enabled:
		axes.append("Z")
	return " — Mirror %s" % "+".join(axes) if not axes.is_empty() else ""


func _format_metres(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")


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
	var filled = not _stroke_erasing
	var next_set: Dictionary = {}
	for base_cell in cells:
		for cell in _mirrored_cells(base_cell):
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
		_record_stroke_cell(cell)
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
	var fill_value = false if _stroke_erasing else not target_filled
	if target_filled == fill_value:
		return
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
		_record_stroke_cell(cell)
		if _active_stroke:
			_active_stroke.add_cell(cell, _now_seconds())
		stack.append(cell + Vector2i(1, 0))
		stack.append(cell + Vector2i(-1, 0))
		stack.append(cell + Vector2i(0, 1))
		stack.append(cell + Vector2i(0, -1))
		guard += 1
		if guard > MAX_BUCKET_FILL_CELLS:
			push_warning(
				(
					"HammerForge: bucket fill hit cell limit (%d) — area may be unbounded"
					% MAX_BUCKET_FILL_CELLS
				)
			)
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


# ---------------------------------------------------------------------------
# Terrain Sculpting
# ---------------------------------------------------------------------------


func _begin_sculpt_stroke(camera: Camera3D, screen_pos: Vector2) -> bool:
	var layer = layer_manager.get_active_layer() if layer_manager else null
	if not layer or not layer.has_heightmap():
		push_warning("HammerForge: sculpt requires an active layer with a heightmap")
		return false
	_painting = true
	_sculpt_flatten_captured = false
	_stroke_dirty.clear()
	_apply_sculpt_at_screen(camera, screen_pos, layer)
	return true


func _apply_sculpt_at_screen(camera: Camera3D, screen_pos: Vector2, layer: HFPaintLayer) -> void:
	if not camera or not layer or not layer.heightmap:
		return
	var cell = _screen_to_cell(camera, screen_pos)
	if cell == null:
		return
	_apply_terrain_brush(layer, cell)
	# Reconcile affected chunks
	var dirty = layer.consume_dirty_chunks()
	var dirty_typed: Array[Vector2i] = []
	for cid in dirty:
		dirty_typed.append(cid)
		_stroke_dirty[cid] = true
	if not dirty_typed.is_empty() and geometry and reconciler and heightmap_synth:
		_reconcile_heightmap(layer, dirty_typed)


func _apply_terrain_brush(layer: HFPaintLayer, center_cell: Vector2i) -> void:
	var img = layer.heightmap
	if not img:
		return
	var w = img.get_width()
	var h = img.get_height()
	var r = int(ceil(sculpt_radius))
	# For FLATTEN, capture height at center on first application
	if tool == HFStroke.Tool.SCULPT_FLATTEN and not _sculpt_flatten_captured:
		var cx = posmod(center_cell.x, w)
		var cy = posmod(center_cell.y, h)
		_sculpt_flatten_height = img.get_pixel(cx, cy).r
		_sculpt_flatten_captured = true
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist = sqrt(float(dx * dx + dy * dy))
			if dist > sculpt_radius:
				continue
			var px = posmod(center_cell.x + dx, w)
			var py = posmod(center_cell.y + dy, h)
			# Falloff: 1.0 at center, 0.0 at edge (when falloff=1)
			var t = dist / max(0.01, sculpt_radius)
			var weight = 1.0 - t * sculpt_falloff
			weight = clamp(weight, 0.0, 1.0)
			var current = img.get_pixel(px, py).r
			var new_val = current
			match tool:
				HFStroke.Tool.SCULPT_RAISE:
					new_val = current + sculpt_strength * weight * 0.01
				HFStroke.Tool.SCULPT_LOWER:
					new_val = current - sculpt_strength * weight * 0.01
				HFStroke.Tool.SCULPT_SMOOTH:
					# Average with neighbors (3x3 kernel)
					var avg := 0.0
					var count := 0
					for sy in range(-1, 2):
						for sx in range(-1, 2):
							avg += img.get_pixel(posmod(px + sx, w), posmod(py + sy, h)).r
							count += 1
					avg /= float(count)
					new_val = lerp(current, avg, weight * 0.5)
				HFStroke.Tool.SCULPT_FLATTEN:
					new_val = lerp(current, _sculpt_flatten_height, weight * 0.5)
			new_val = clamp(new_val, 0.0, 1.0)
			if new_val != current:
				img.set_pixel(px, py, Color(new_val, new_val, new_val))
	# Mark chunks dirty for the affected area
	if layer.grid:
		var chunk_size = layer.chunk_size
		var min_cx = int(floor(float(center_cell.x - r) / float(chunk_size)))
		var max_cx = int(floor(float(center_cell.x + r) / float(chunk_size)))
		var min_cy = int(floor(float(center_cell.y - r) / float(chunk_size)))
		var max_cy = int(floor(float(center_cell.y + r) / float(chunk_size)))
		for cy in range(min_cy, max_cy + 1):
			for cx in range(min_cx, max_cx + 1):
				layer._dirty_chunks[Vector2i(cx, cy)] = true
