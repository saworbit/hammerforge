@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The two bake toggles a mapper reaches for when the frame rate goes.
##
## `bake-options` asks whether each switch changes the node classes in the
## container. Multimesh and occluders both need a second question, because the
## answer to the first one is misleading in opposite directions: multimesh
## changed nothing at all, and occluders changed a great deal. This scenario
## builds the level each one is *for* -- a room full of identical crates, and a
## room whose walls should occlude what is behind them -- and prices the result.


func id() -> String:
	return "bake-optimisation"


func summary() -> String:
	return "what Use multimesh and Generate occluders do to a level built to need them"


func run() -> void:
	await _a_room_full_of_identical_crates()
	await _how_many_occluders_a_room_gets()
	await _what_an_occluder_costs_per_brush()


func _collect(node: Node, pred: Callable, out: Array) -> Array:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_collect(c, pred, out)
	return out


func _counts(node: Node, out: Dictionary) -> Dictionary:
	out[node.get_class()] = int(out.get(node.get_class(), 0)) + 1
	for c in node.get_children():
		_counts(c, out)
	return out


## Sixty crates, all the same size, laid out in a grid. This is the level the
## Use multimesh toggle exists for, and the only one where it can pay.
func _a_room_full_of_identical_crates() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	for i in 60:
		box(
			root, Vector3(0.8, 0.8, 0.8), Vector3(-9.0 + (i % 10) * 2.0, 0.4, -5.0 + (i / 10) * 2.0)
		)
	await frame()
	note("brushes", root.brush_system.get_live_brush_count())
	note("of which identical 0.8 crates", 60)

	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var baked := _counts(container, {})
	note("what 60 identical crates bake to", baked)

	# There used to be a `Use MultiMesh` toggle here, and the measurement above is
	# why it was removed (#692). The structural pass merges every face into one
	# mesh per material before anything else looks at the container, so what
	# consolidation was handed was a single MeshInstance3D and a group of one.
	# There was no level, at any size, in any arrangement, that could make it
	# fire.
	var meshes: Array = _collect(container, func(n: Node) -> bool: return n is MeshInstance3D, [])
	note("MeshInstance3D nodes the merge leaves to consolidate", meshes.size())
	note(
		"draw calls for this room",
		"one per material, which is the floor; multimesh would have made it two"
	)
	if meshes.size() > 1:
		note(
			"worth revisiting",
			(
				"more than one mesh instance survived the merge here, which is the input "
				+ "consolidation always wanted and never got. See #742."
			)
		)


func _room(root: Node3D, span: float) -> void:
	box(root, Vector3(span, 0.2, span), Vector3(0, -0.1, 0))
	box(root, Vector3(span, 0.2, span), Vector3(0, 3.1, 0))
	box(root, Vector3(span, 3, 0.3), Vector3(0, 1.5, -span * 0.5))
	box(root, Vector3(span, 3, 0.3), Vector3(0, 1.5, span * 0.5))
	box(root, Vector3(0.3, 3, span), Vector3(-span * 0.5, 1.5, 0))
	box(root, Vector3(0.3, 3, span), Vector3(span * 0.5, 1.5, 0))


func _how_many_occluders_a_room_gets() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root, 12.0)
	root.bake_generate_occluders = true
	note("bake_occluder_min_area", root.get("bake_occluder_min_area"))
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	if container == null:
		flag("bake-optimisation: nothing baked")
		return
	var occ: Array = _collect(container, func(n: Node) -> bool: return n is OccluderInstance3D, [])
	note("brushes in the room", 6)
	note("OccluderInstance3D nodes the bake made", occ.size())
	var names: Array = occ.map(func(n: Node) -> String: return n.name)
	note("their names", names.slice(0, 12))
	# Six boxes have 36 faces, of which at most 12 are large walls. One occluder
	# per large face is defensible; several per face is not, and neither is one
	# per face when the six coplanar faces of a wall could be one quad.
	if occ.size() > 12:
		flag(
			"a six-brush room bakes to %d separate occluders" % occ.size(),
			(
				"Godot's occlusion culling walks every OccluderInstance3D in the scene each "
				+ "frame, so the count is the cost. A room this size wants a handful of large "
				+ "quads, not one node per face -- and no pass merges coplanar faces from "
				+ "different brushes into a single occluder, so a wall built from four brushes "
				+ "is four occluders where it should be one."
			)
		)


func _what_an_occluder_costs_per_brush() -> void:
	# `_group_touching_coplanar()` is the merge, and "touching" is the word that
	# matters: a long wall built from abutting segments is one flat surface and
	# should be one occluder, while the same segments with gaps between them are
	# genuinely separate. Measure both, so the number is read against the design
	# rather than on its own.
	for spec in [
		[6, 4.0, "abutting: a long wall built from 6 segments"],
		[6, 5.0, "with a 1-unit gap between each: 6 separate walls"],
		[24, 4.0, "abutting, 24 segments"],
		[60, 4.0, "abutting, 60 segments"],
	]:
		var brushes: int = int(spec[0])
		var pitch: float = float(spec[1])
		var root: Node3D = await fresh_root()
		root.auto_spawn_player = false
		for i in brushes:
			box(root, Vector3(4, 3, 0.3), Vector3(i * pitch, 1.5, 0))
		root.bake_generate_occluders = true
		var t := Time.get_ticks_msec()
		await root.bake(false, false)
		await frame()
		var ms := Time.get_ticks_msec() - t
		var container := root.get_node_or_null("BakedGeometry") as Node3D
		var occ: Array = (
			_collect(container, func(n: Node) -> bool: return n is OccluderInstance3D, [])
			if container
			else []
		)
		note(
			str(spec[2]),
			(
				"%d occluders (%.1f per brush), bake %d ms"
				% [occ.size(), float(occ.size()) / brushes, ms]
			)
		)
		if is_equal_approx(pitch, 4.0) and occ.size() > 4:
			flag(
				(
					"a wall built from %d abutting segments bakes to %d occluders"
					% [brushes, occ.size()]
				),
				(
					"The segments are placed edge to edge, so their front faces are one "
					+ "continuous flat surface and their back faces are another -- two occluders "
					+ "for the whole wall. `_group_touching_coplanar()` is meant to find exactly "
					+ "that, and the result is two per brush regardless, so coplanar triangles "
					+ "from different brushes are never landing in one group. Godot walks every "
					+ "OccluderInstance3D in the scene per frame, so the count is the cost, and it "
					+ "grows with the brush count rather than with the number of real surfaces."
				)
			)
