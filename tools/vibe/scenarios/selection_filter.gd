@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The Selection Filters popover: walls/floors/ceilings, same material, similar,
## detail/structural.
##
## Every one of these is a bulk selection a mapper then acts on -- paints,
## deletes, moves. What matters is not that a filter selects something but that
## the set it selects is the set the button names, and that a face it should not
## reach is not in it.

const SelectionFilter = preload("res://addons/hammerforge/ui/hf_selection_filter.gd")


func id() -> String:
	return "selection-filter"


func summary() -> String:
	return "which faces each bulk filter reaches, and which faces no filter reaches at all"


func run() -> void:
	await _the_faces_between_the_three_buttons()
	await _what_a_hidden_brush_contributes()
	await _detail_against_structural()
	await _a_filter_that_matches_nothing()


class Capture:
	extends RefCounted
	var nodes: Array = []
	var faces: Dictionary = {}
	var emitted := false

	func take(p_nodes: Array, p_faces: Dictionary) -> void:
		nodes = p_nodes
		faces = p_faces
		emitted = true


func _filter_for(root: Node3D, selection: Array = []):
	var f = SelectionFilter.new()
	f._root = root
	f._hf_selection = selection
	return f


func _run_filter(root: Node3D, method: String, selection: Array = []) -> Capture:
	var f = _filter_for(root, selection)
	var cap := Capture.new()
	f.filter_applied.connect(cap.take)
	f.call(method)
	f.free()
	return cap


func _face_total(cap: Capture) -> int:
	var total := 0
	for key in cap.faces.keys():
		total += (cap.faces[key] as Array).size()
	return total


## A ramp. Walls, floors and ceilings between them should name every face.
func _the_faces_between_the_three_buttons() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 16, 64))
	await frame()
	# 50 degrees off level: steeper than a floor, shallower than a wall.
	b.rotation = Vector3(deg_to_rad(50.0), 0.0, 0.0)
	await frame()

	var faces: Array = b.get_faces()
	note("ramp faces", faces.size())
	var basis: Basis = b.global_transform.basis
	var ys: Array = []
	for f in faces:
		ys.append(snappedf((basis * f.normal).normalized().y, 0.001))
	note("world normal y per face", ys)

	var walls := _run_filter(root, "_filter_walls")
	var floors := _run_filter(root, "_filter_floors")
	var ceilings := _run_filter(root, "_filter_ceilings")
	note(
		"walls / floors / ceilings",
		"%d / %d / %d" % [_face_total(walls), _face_total(floors), _face_total(ceilings)]
	)

	var reached: Dictionary = {}
	for cap in [walls, floors, ceilings]:
		for key in cap.faces.keys():
			for i in cap.faces[key]:
				reached[int(i)] = true
	var missed: Array = []
	for i in range(faces.size()):
		if not reached.has(i):
			missed.append([i, ys[i]])
	note("faces no filter reaches", missed)
	if not missed.is_empty():
		known(
			434,
			"the three normal filters between them do not cover every face",
			(
				(
					"a brush pitched 50 degrees has %d face(s) that Walls, Floors and Ceilings "
					% missed.size()
				)
				+ "all skip: %s (index, world normal y). " % str(missed)
				+ "Walls is |n.y| < 0.3, Floors is n.y > 0.7, Ceilings is n.y < -0.7, so "
				+ "everything between 0.3 and 0.7 off level belongs to no button -- exactly "
				+ "the ramps and chamfers a mapper reaches for the filter to catch"
			)
		)


## A brush hidden by a visgroup, and what a filter does with it.
func _what_a_hidden_brush_contributes() -> void:
	var root: Node3D = await fresh_root()
	var visible_brush := box(root, Vector3(64, 64, 64))
	var hidden_brush := box(root, Vector3(64, 64, 64), Vector3(256, 0, 0))
	await frame()
	hidden_brush.visible = false
	await frame()
	note("brushes", "1 visible, 1 hidden")

	var floors := _run_filter(root, "_filter_floors")
	note("floor faces selected", _face_total(floors))
	var keys: Array = floors.faces.keys()
	note("brushes contributing faces", keys.size())
	if keys.size() > 1:
		known(
			435,
			"a bulk filter selects faces on brushes that are hidden",
			(
				"one of the two brushes has visible = false, and Floors still returned faces "
				+ (
					"from both (%d keys). _get_all_brushes() walks _iter_pick_nodes() and never "
					% keys.size()
				)
				+ "looks at visibility, so a paint or a material assignment made straight "
				+ "after the filter lands on geometry the mapper cannot see"
			)
		)
	note("visible brush still selected", floors.faces.has(HFBrushSystem.face_key(visible_brush)))


## Detail, structural, and the brushes that are neither.
func _detail_against_structural() -> void:
	var root: Node3D = await fresh_root()
	var plain := box(root, Vector3(64, 64, 64))
	var detail := box(root, Vector3(64, 64, 64), Vector3(128, 0, 0))
	var door := box(root, Vector3(64, 64, 64), Vector3(256, 0, 0))
	await frame()
	detail.set_meta("brush_entity_class", "func_detail")
	door.set_meta("brush_entity_class", "func_door")
	await frame()

	var as_detail := _run_filter(root, "_filter_detail")
	var as_structural := _run_filter(root, "_filter_structural")
	note("detail filter picked", as_detail.nodes.size())
	note("structural filter picked", as_structural.nodes.size())

	var picked: Dictionary = {}
	for n in as_detail.nodes:
		picked[n] = true
	for n in as_structural.nodes:
		picked[n] = true
	note("door brush in either set", picked.has(door))
	if not picked.has(door):
		note(
			"a brush entity that is not func_detail belongs to neither filter",
			"Structural is cls == '' or 'worldspawn'; a func_door brush answers to neither button"
		)


## What happens when a filter matches nothing.
func _a_filter_that_matches_nothing() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()

	var empty := _run_filter(root, "_filter_detail")
	note("detail filter on a level with no detail brushes: emitted", empty.emitted)
	note("  nodes", empty.nodes.size())
	note("  faces", empty.faces.size())
	if empty.emitted and empty.nodes.is_empty() and empty.faces.is_empty():
		known(
			436,
			"a filter that matches nothing reports nothing and leaves the old selection standing",
			(
				"_filter_detail() emits filter_applied([], {}) when no brush matches. "
				+ "HFPluginSelectionCommands.on_filter_applied() only acts when one of the two "
				+ "is non-empty -- with both empty it returns without clearing the selection "
				+ "and without a toast, so the popover closes and the button looks broken. "
				+ "The other filters differ again: _filter_same_material() with no face "
				+ "selected returns before emitting and does not even close the popover"
			)
		)

	var f = _filter_for(root, [])
	var cap := Capture.new()
	f.filter_applied.connect(cap.take)
	f.visible = true
	f._filter_same_material()
	note("same-material with no face selected: emitted", cap.emitted)
	note("  popover still open", f.visible)
	f.free()
