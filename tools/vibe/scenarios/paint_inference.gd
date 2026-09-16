@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The opt-in Floor Paint cleanup pass, against the strokes a mapper actually
## draws.
##
## `HFInferenceEngine` classifies a finished stroke and then edits cells: it
## fills one-cell holes and gaps, removes isolated one-cell noise, and widens a
## one-cell corridor. Every one of those edits is applied to painted work the
## mapper just made, so "conservative" is a claim worth measuring — what matters
## is whether any of them removes or moves something that was deliberate.

const EngineType = preload("res://addons/hammerforge/paint/hf_inference_engine.gd")
const StrokeType = preload("res://addons/hammerforge/paint/hf_stroke.gd")
const ManagerType = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")


func id() -> String:
	return "paint-inference"


func summary() -> String:
	return "what the opt-in paint cleanup does to the cells a stroke just painted"


func run() -> void:
	_intent_classification()
	await _single_cell_dab()
	await _corridor_widening()
	await _gap_filling()


func _intent_classification() -> void:
	var engine = EngineType.new()
	var single = StrokeType.new()
	single.add_cell(Vector2i(0, 0), 0.0)
	single.analyse()
	note(
		"one-cell dab: closed=%s aspect=%.2f" % [single.is_closed, single.aspect_ratio],
		engine.infer_intent(single)
	)
	if engine.infer_intent(single) == &"room":
		known(
			547,
			"a single-cell dab is classified as a closed room",
			(
				"`is_closed` is the distance from the first cell to the last, so a stroke"
				+ " of one cell is a closed loop, and the cleanup pass treats one dab as a"
				+ " room the mapper drew the outline of"
			)
		)
	var line = StrokeType.new()
	for x in range(20):
		line.add_cell(Vector2i(x, 0), float(x) * 0.01)
	line.analyse()
	note(
		"straight run of 20: aspect=%.2f speed=%.1f" % [line.aspect_ratio, line.avg_speed],
		engine.infer_intent(line)
	)
	var slow = StrokeType.new()
	for x in range(20):
		slow.add_cell(Vector2i(x, 0), float(x) * 1.0)
	slow.analyse()
	note("the same run drawn slowly: speed=%.1f" % slow.avg_speed, engine.infer_intent(slow))
	if engine.infer_intent(line) != engine.infer_intent(slow):
		note(
			"the same shape classifies differently by drawing speed",
			"%s when quick, %s when slow" % [engine.infer_intent(line), engine.infer_intent(slow)]
		)


func _layer() -> Node:
	var manager = ManagerType.new()
	_tree.get_root().add_child(manager)
	await frame()
	manager.clear_layers()
	var layer = manager.create_layer(&"infer", 0.0)
	return layer


func _cleanup(layer, cells: Array, intent: StringName) -> void:
	var engine = EngineType.new()
	var settings = EngineType.InferenceSettings.new()
	var affected: Dictionary = {}
	var chunks: Dictionary = {}
	for cell in cells:
		affected[cell] = true
		chunks[layer._cell_to_chunk(cell)] = true
	var dirty: Array[Vector2i] = []
	for cid in chunks:
		dirty.append(cid)
	engine.apply_cleanup(layer, dirty, intent, settings, affected)


func _single_cell_dab() -> void:
	var layer = await _layer()
	layer.set_cell(Vector2i(5, 5), true)
	note("one cell painted", layer.get_cell(Vector2i(5, 5)))
	_cleanup(layer, [Vector2i(5, 5)], &"blob")
	var survived: bool = layer.get_cell(Vector2i(5, 5))
	note("after the cleanup pass, the cell is", survived)
	if not survived:
		known(
			546,
			"the cleanup pass erases a single-cell paint dab",
			(
				"denoise removes any filled cell with no cardinal neighbour, and a dab is"
				+ " exactly that, so with Inference cleanup on a single click paints nothing"
				+ " and nothing says why"
			)
		)
	layer.get_parent().queue_free()
	await frame()


func _corridor_widening() -> void:
	var layer = await _layer()
	var cells: Array = []
	for x in range(10):
		cells.append(Vector2i(x, 0))
		layer.set_cell(Vector2i(x, 0), true)
	var before := 0
	for y in range(-2, 3):
		for x in range(-2, 13):
			if layer.get_cell(Vector2i(x, y)):
				before += 1
	_cleanup(layer, cells, &"corridor")
	var after := 0
	var added: Array = []
	for y in range(-2, 3):
		for x in range(-2, 13):
			if layer.get_cell(Vector2i(x, y)):
				after += 1
				if y != 0:
					added.append(Vector2i(x, y))
	note("a ten-cell corridor", "%d cells before, %d after" % [before, after])
	note("cells the widening added off the drawn line", added)
	if after > before * 2:
		flag(
			"corridor widening more than doubles a drawn corridor",
			"%d cells drawn became %d" % [before, after]
		)
	layer.get_parent().queue_free()
	await frame()


func _gap_filling() -> void:
	var layer = await _layer()
	# A doorway: a wall of floor with one deliberate one-cell gap in it.
	var cells: Array = []
	for x in range(7):
		if x == 3:
			continue
		cells.append(Vector2i(x, 0))
		layer.set_cell(Vector2i(x, 0), true)
	cells.append(Vector2i(3, 0))
	note("a run with one deliberate gap at x=3", layer.get_cell(Vector2i(3, 0)))
	_cleanup(layer, cells, &"blob")
	var filled: bool = layer.get_cell(Vector2i(3, 0))
	note("after the cleanup pass, the gap is", "filled" if filled else "still there")
	if filled:
		note(
			"gap filling closes a one-cell gap the mapper left",
			"documented behaviour -- recorded so the cost of the option is on the record"
		)
	layer.get_parent().queue_free()
	await frame()
