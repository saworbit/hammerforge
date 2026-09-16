@tool
class_name HFInferenceEngine
extends RefCounted

## Conservative, opt-in cleanup for Floor Paint strokes.
##
## Every edit is one-cell topology repair: isolated one-cell noise is removed,
## enclosed holes and cardinal one-cell gaps are filled, and a one-cell-wide
## corridor may gain exactly one neighbouring row/column. Live strokes pass an
## affected-cell scope so cleanup cannot wander into unrelated painted work.

const HFStroke = preload("hf_stroke.gd")


## Which of the four repairs run.
##
## Bools, because that is what they are. They were numbers with magnitudes in
## their names - `fill_max_hole_area`, `gap_tolerance`,
## `denoise_min_island_area`, `min_corridor_width` - and every one of them was
## read as an on/off threshold, so 5 did exactly what 1 did and 50 did exactly
## what 2 did. The one-cell bound is deliberate and the class comment above
## defends it; the names are what was wrong. A settings panel built from the old
## names would have been four spin boxes doing nothing but switching.
##
## `angle_snap_degrees` is gone. Nothing read it, no doc promised it, and stroke
## angle snapping is not something this pass does: `infer_intent()` classifies a
## stroke and `apply_cleanup()` edits cells. If it is wanted later it belongs on
## the stroke.
class InferenceSettings:
	var denoise := true
	var fill_holes := true
	var fill_gaps := true
	var widen_corridors := true


## What the stroke looks like it was meant to be, which decides whether the
## corridor widening runs.
##
## `avg_speed` is part of the corridor test, so the same shape classifies two
## ways: a long thin run drawn at 10 cells a second or more is a corridor and
## gains a row, and the identical run drawn slowly is a blob and gains nothing.
## That is worth knowing before reading a cleanup that did not happen - the
## widening is the only intent-gated pass, so nothing else depends on which
## answer comes back.
func infer_intent(stroke: HFStroke) -> StringName:
	if stroke.tool == HFStroke.Tool.ERASE:
		return &"erase"
	if stroke.is_closed and stroke.aspect_ratio < 3.0:
		return &"room"
	if stroke.aspect_ratio >= 3.0 and stroke.avg_speed >= 10.0:
		return &"corridor"
	return &"blob"


func apply_cleanup(
	layer: HFPaintLayer,
	dirty_chunks: Array[Vector2i],
	intent: StringName,
	settings: InferenceSettings,
	affected_cells: Dictionary = {}
) -> void:
	if layer == null or dirty_chunks.is_empty() or intent == &"erase":
		return
	var writable := _writable_cells(layer, dirty_chunks, affected_cells)
	if writable.is_empty():
		return

	var snapshot := _snapshot(layer, writable)
	var changes: Dictionary = {}
	for cell: Vector2i in writable:
		if bool(snapshot.get(cell, false)):
			continue
		var left := _filled(snapshot, layer, cell + Vector2i(-1, 0))
		var right := _filled(snapshot, layer, cell + Vector2i(1, 0))
		var up := _filled(snapshot, layer, cell + Vector2i(0, -1))
		var down := _filled(snapshot, layer, cell + Vector2i(0, 1))
		var hole := settings.fill_holes and left and right and up and down
		var gap := settings.fill_gaps and ((left and right) or (up and down))
		if hole or gap:
			changes[cell] = true
	_apply(layer, changes)

	snapshot = _snapshot(layer, writable)
	changes.clear()
	# A stroke of exactly one cell is not noise. Denoise removes a filled cell
	# with no cardinal neighbour, which is every single click on empty ground,
	# and the scope this pass runs on is the stroke that was just made - so with
	# cleanup on, one click painted nothing and said nothing about it. There is
	# no isolated cell to remove from a one-cell stroke that the stroke did not
	# deliberately put there.
	var deliberate_dab := affected_cells.size() == 1
	if settings.denoise and not deliberate_dab:
		for cell: Vector2i in writable:
			if bool(snapshot.get(cell, false)) and _cardinal_count(snapshot, layer, cell) == 0:
				changes[cell] = false
	_apply(layer, changes)

	if intent == &"corridor" and settings.widen_corridors:
		_widen_one_cell_corridor(layer, writable)


func _writable_cells(
	layer: HFPaintLayer, dirty_chunks: Array[Vector2i], affected_cells: Dictionary
) -> Dictionary:
	var dirty_set: Dictionary = {}
	for cid in dirty_chunks:
		dirty_set[cid] = true
	var writable: Dictionary = {}
	if affected_cells.is_empty():
		for cid in dirty_chunks:
			var origin := cid * layer.chunk_size
			for y in range(layer.chunk_size):
				for x in range(layer.chunk_size):
					writable[origin + Vector2i(x, y)] = true
		return writable
	for raw_cell in affected_cells:
		var cell := raw_cell as Vector2i
		for offset in [
			Vector2i.ZERO,
			Vector2i(-1, 0),
			Vector2i(1, 0),
			Vector2i(0, -1),
			Vector2i(0, 1),
		]:
			var candidate: Vector2i = cell + offset
			if dirty_set.has(layer._cell_to_chunk(candidate)):
				writable[candidate] = true
	return writable


func _snapshot(layer: HFPaintLayer, writable: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in writable:
		out[cell] = layer.get_cell(cell)
	return out


func _filled(snapshot: Dictionary, layer: HFPaintLayer, cell: Vector2i) -> bool:
	return bool(snapshot.get(cell, layer.get_cell(cell)))


func _cardinal_count(snapshot: Dictionary, layer: HFPaintLayer, cell: Vector2i) -> int:
	var count := 0
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if _filled(snapshot, layer, cell + offset):
			count += 1
	return count


func _apply(layer: HFPaintLayer, changes: Dictionary) -> void:
	for cell: Vector2i in changes:
		layer.set_cell(cell, bool(changes[cell]))


func _widen_one_cell_corridor(layer: HFPaintLayer, writable: Dictionary) -> void:
	var snapshot := _snapshot(layer, writable)
	var changes: Dictionary = {}
	for cell: Vector2i in writable:
		if not bool(snapshot.get(cell, false)):
			continue
		var horizontal := (
			_filled(snapshot, layer, cell + Vector2i(-1, 0))
			or _filled(snapshot, layer, cell + Vector2i(1, 0))
		)
		var vertical := (
			_filled(snapshot, layer, cell + Vector2i(0, -1))
			or _filled(snapshot, layer, cell + Vector2i(0, 1))
		)
		var target := Vector2i.ZERO
		if horizontal and not vertical:
			target = cell + Vector2i(0, 1)
		elif vertical and not horizontal:
			target = cell + Vector2i(1, 0)
		else:
			continue
		if writable.has(target) and not _filled(snapshot, layer, target):
			changes[target] = true
	_apply(layer, changes)
