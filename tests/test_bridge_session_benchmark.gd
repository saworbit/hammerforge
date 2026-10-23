extends GutTest

## The bridge session benchmark's town, built at its smallest, so the generator
## cannot rot between the runs that are timed (#1652).

const Bench = preload("res://tools/benchmark_bridge_session.gd")


func test_one_room_builds_through_the_bridge_with_every_call_answered():
	var bench: Dictionary = await Bench.set_up(self)
	var lines: Array = []
	var summary: Dictionary = await Bench.run_session(
		bench, 1, func(line: Dictionary): lines.append(line)
	)
	assert_eq(summary["failed"], [], "every call answered")
	assert_eq(summary["calls"], 15, "one room's calls")
	assert_gt(summary["brushes"], 8, "a floor, walls, a cut, stairs, a trigger and a door")
	assert_false(lines.is_empty(), "a line at the end")
	for key in ["mean_ms", "slowest_ms", "undo_record_ms", "apply_ms", "change_check_ms"]:
		assert_true(summary.has(key), key)
	# From the dispatcher's `last_timings`, which each change sets.
	assert_gt(float(summary["undo_record_ms"]), 0.0, "the undo record is timed")
	var level: Node = bench["level"]
	assert_eq(
		level.get_entity_outputs(level.find_brush_by_id(_trigger_id(level))).size(), 1, "wired"
	)
	var floor_brush: Node = level.find_brush_by_id(_id_named(level, "r0_floor"))
	var painted := 0
	for face in floor_brush.faces:
		if face.material_idx == 1 and face.normal.y > 0.5:
			painted += 1
	assert_eq(painted, 1, "the floor's top painted")
	bench["dispatcher"].shutdown()
	bench["undo"].free_histories()
	(bench["scene"] as Node).free()


static func _trigger_id(level: Node) -> String:
	return _id_named(level, "r0_trig")


static func _id_named(level: Node, brush_name: String) -> String:
	for brush in level._iter_managed_brush_nodes():
		if str(brush.name) == brush_name:
			return str(brush.brush_id)
	return ""
