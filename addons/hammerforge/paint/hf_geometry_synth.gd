@tool
class_name HFGeometrySynth
extends RefCounted

const HFHash = preload("hf_hash.gd")
const HFGeneratedModel = preload("hf_generated_model.gd")


class SynthSettings:
	var floor_thickness := 0.2
	var wall_height := 3.0
	var wall_thickness := 0.2


func build_for_chunks(
	layer: HFPaintLayer, chunk_ids: Array[Vector2i], settings: SynthSettings
) -> HFGeneratedModel:
	var model := HFGeneratedModel.new()
	for cid in chunk_ids:
		_add_floors_for_chunk(layer, cid, settings, model)
		_add_walls_for_chunk(layer, cid, settings, model)
	return model


func _add_floors_for_chunk(
	layer: HFPaintLayer, cid: Vector2i, s: SynthSettings, model: HFGeneratedModel
) -> void:
	var size := layer.chunk_size
	var origin := Vector2i(cid.x * size, cid.y * size)
	var mask := _build_chunk_mask(layer, origin, size)
	var rects := _greedy_rectangles(mask, size)
	for rect in rects:
		var fr := HFGeneratedModel.FloorRect.new()
		fr.min_cell = origin + rect.position
		fr.size = rect.size
		fr.layer_y = layer.grid.layer_y
		fr.thickness = s.floor_thickness
		fr.id = HFHash.floor_id(layer.layer_id, cid, fr.min_cell, fr.size)
		model.floors.append(fr)


func _add_walls_for_chunk(
	layer: HFPaintLayer, cid: Vector2i, s: SynthSettings, model: HFGeneratedModel
) -> void:
	var size := layer.chunk_size
	var origin := Vector2i(cid.x * size, cid.y * size)
	var edges = _boundary_edges(layer, origin, size)
	var edges_h: Array = edges[0]
	var edges_v: Array = edges[1]
	var segs_h := _merge_horizontal(edges_h)
	var segs_v := _merge_vertical(edges_v)
	for seg in segs_h:
		var ws := HFGeneratedModel.WallSeg.new()
		var x0: int = seg.get("x0", 0)
		var x1: int = seg.get("x1", 0)
		var y: int = seg.get("y", 0)
		ws.a = Vector2i(min(x0, x1), y)
		ws.b = Vector2i(max(x0, x1), y)
		ws.outward = seg.get("outward", Vector2i.ZERO)
		ws.layer_y = layer.grid.layer_y
		ws.height = s.wall_height
		ws.thickness = s.wall_thickness
		ws.id = HFHash.wall_id(layer.layer_id, cid, ws.a, ws.b, ws.outward)
		model.walls.append(ws)
	for seg in segs_v:
		var ws := HFGeneratedModel.WallSeg.new()
		var x: int = seg.get("x", 0)
		var y0: int = seg.get("y0", 0)
		var y1: int = seg.get("y1", 0)
		ws.a = Vector2i(x, min(y0, y1))
		ws.b = Vector2i(x, max(y0, y1))
		ws.outward = seg.get("outward", Vector2i.ZERO)
		ws.layer_y = layer.grid.layer_y
		ws.height = s.wall_height
		ws.thickness = s.wall_thickness
		ws.id = HFHash.wall_id(layer.layer_id, cid, ws.a, ws.b, ws.outward)
		model.walls.append(ws)


func _build_chunk_mask(layer: HFPaintLayer, origin: Vector2i, size: int) -> Array:
	var rows: Array = []
	for y in range(size):
		var row := PackedByteArray()
		row.resize(size)
		for x in range(size):
			var cell := origin + Vector2i(x, y)
			row[x] = 1 if layer.get_cell(cell) else 0
		rows.append(row)
	return rows


func _greedy_rectangles(mask: Array, size: int) -> Array:
	var used: Array = []
	for y in range(size):
		var row := PackedByteArray()
		row.resize(size)
		used.append(row)
	var rects: Array = []
	for y in range(size):
		for x in range(size):
			var used_row: PackedByteArray = used[y]
			var mask_row: PackedByteArray = mask[y]
			if used_row[x] != 0 or mask_row[x] == 0:
				continue
			var w = 1
			while x + w < size and used_row[x + w] == 0 and mask_row[x + w] != 0:
				w += 1
			var h = 1
			var can_grow = true
			while y + h < size and can_grow:
				for k in range(w):
					var used_row_h: PackedByteArray = used[y + h]
					var mask_row_h: PackedByteArray = mask[y + h]
					if used_row_h[x + k] != 0 or mask_row_h[x + k] == 0:
						can_grow = false
						break
				if can_grow:
					h += 1
			for yy in range(y, y + h):
				var used_row_yy: PackedByteArray = used[yy]
				for xx in range(x, x + w):
					used_row_yy[xx] = 1
			rects.append(Rect2i(x, y, w, h))
	return rects


func _boundary_edges(layer: HFPaintLayer, origin: Vector2i, size: int) -> Array:
	var edges_h: Array = []
	var edges_v: Array = []
	for ly in range(size):
		for lx in range(size):
			var cell := origin + Vector2i(lx, ly)
			if not layer.get_cell(cell):
				continue
			if not layer.get_cell(cell + Vector2i(0, -1)):
				edges_h.append(
					{"x0": cell.x, "x1": cell.x + 1, "y": cell.y, "outward": Vector2i(0, -1)}
				)
			if not layer.get_cell(cell + Vector2i(0, 1)):
				edges_h.append(
					{"x0": cell.x, "x1": cell.x + 1, "y": cell.y + 1, "outward": Vector2i(0, 1)}
				)
			if not layer.get_cell(cell + Vector2i(-1, 0)):
				edges_v.append(
					{"x": cell.x, "y0": cell.y, "y1": cell.y + 1, "outward": Vector2i(-1, 0)}
				)
			if not layer.get_cell(cell + Vector2i(1, 0)):
				edges_v.append(
					{"x": cell.x + 1, "y0": cell.y, "y1": cell.y + 1, "outward": Vector2i(1, 0)}
				)
	return [edges_h, edges_v]


func _merge_horizontal(edges_h: Array) -> Array:
	var groups: Dictionary = {}
	for edge in edges_h:
		var y = int(edge.get("y", 0))
		var outward: Vector2i = edge.get("outward", Vector2i.ZERO)
		var key = "%d:%d,%d" % [y, outward.x, outward.y]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(edge)
	var segs: Array = []
	for key in groups.keys():
		var edges: Array = groups[key]
		edges.sort_custom(func(a, b): return int(a.get("x0", 0)) < int(b.get("x0", 0)))
		var first = edges[0]
		var cur_start = int(first.get("x0", 0))
		var cur_end = int(first.get("x1", 0))
		var y = int(first.get("y", 0))
		var outward: Vector2i = first.get("outward", Vector2i.ZERO)
		for i in range(1, edges.size()):
			var e = edges[i]
			var a = int(e.get("x0", 0))
			var b = int(e.get("x1", 0))
			if a == cur_end:
				cur_end = b
			elif a < cur_end:
				cur_end = max(cur_end, b)
			else:
				segs.append({"x0": cur_start, "x1": cur_end, "y": y, "outward": outward})
				cur_start = a
				cur_end = b
		segs.append({"x0": cur_start, "x1": cur_end, "y": y, "outward": outward})
	return segs


func _merge_vertical(edges_v: Array) -> Array:
	var groups: Dictionary = {}
	for edge in edges_v:
		var x = int(edge.get("x", 0))
		var outward: Vector2i = edge.get("outward", Vector2i.ZERO)
		var key = "%d:%d,%d" % [x, outward.x, outward.y]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(edge)
	var segs: Array = []
	for key in groups.keys():
		var edges: Array = groups[key]
		edges.sort_custom(func(a, b): return int(a.get("y0", 0)) < int(b.get("y0", 0)))
		var first = edges[0]
		var cur_start = int(first.get("y0", 0))
		var cur_end = int(first.get("y1", 0))
		var x = int(first.get("x", 0))
		var outward: Vector2i = first.get("outward", Vector2i.ZERO)
		for i in range(1, edges.size()):
			var e = edges[i]
			var a = int(e.get("y0", 0))
			var b = int(e.get("y1", 0))
			if a == cur_end:
				cur_end = b
			elif a < cur_end:
				cur_end = max(cur_end, b)
			else:
				segs.append({"x": x, "y0": cur_start, "y1": cur_end, "outward": outward})
				cur_start = a
				cur_end = b
		segs.append({"x": x, "y0": cur_start, "y1": cur_end, "outward": outward})
	return segs
