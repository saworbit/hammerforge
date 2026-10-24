extends "res://tests/mcp/mcp_dispatcher_case.gd"
## Random runs through the bridge (#1646), for the PR suite and the nightly run.
##
## `tests/test_mcp_command_sweep.gd` checks one command at a time. Agents send
## long runs, and an undo bug often needs two steps to show: the second step's
## record holds state that undoing the first later changes, or the first leaves
## something the second one's redo trips on. A run here makes valid calls picked
## by a seed from the level as it is at that moment, then walks the undo history
## all the way back and the redo history all the way forward, comparing the level
## with the capture taken after each step, then makes the same calls on a fresh
## level and compares where both ended.
##
## A failure writes the run, one JSON line per call, under `user://`, so it can
## be read and made again by hand.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")

## Where a failing run's calls are written.
const FAILED_RUNS := "user://hf_random_runs"
## The palette commands a run may pick, with the params each needs, and how many
## brushes it takes. Commands that need a structure, a prefab or a paint layer
## are left out: a run has none of them to name.
const COMMANDS := {
	"move_to_floor": {"params": {}, "brushes": 1},
	"move_to_ceiling": {"params": {}, "brushes": 1},
	"snap_to_grid": {"params": {}, "brushes": 1},
	"reset_rotation": {"params": {}, "brushes": 1},
	"hollow": {"params": {"thickness": 0.25}, "brushes": 1},
	"clip": {"params": {"axis": "y"}, "brushes": 1},
	"carve": {"params": {}, "brushes": 1},
	"merge": {"params": {}, "brushes": 2},
	"intersect": {"params": {}, "brushes": 2},
	"hull": {"params": {}, "brushes": 2},
	"create_arch": {"params": {"type": "stairs"}, "brushes": 0},
}
const BRUSH_CLASSES := ["trigger_once", "func_door", "func_detail", "func_wall"]

var _rng := RandomNumberGenerator.new()
var _entity_count := 0


## Make `count` calls picked by `seed_value`, undo them all, redo them all, and
## make them again on a fresh level. Returns `{"failures": Array, "calls": Array,
## "steps": int}`, every failure naming the call it is about.
func run_seed(seed_value: int, count: int) -> Dictionary:
	var first := await _make_calls(seed_value, count)
	var level: LevelRoot = first["level"]
	var failures: Array = first["failures"]
	var steps: Array = first["steps"]
	var calls: Array = first["calls"]
	# Undo, walking back through the captures.
	for k in range(steps.size() - 1, -1, -1):
		var undone := await call_tool("hf_undo")
		var call_index: int = steps[k]["call"]
		if not undone.get("ok", false):
			failures.append(
				"undo of call %d (%s) refused: %s" % [call_index, _name(calls[call_index]), undone]
			)
			break
		var expected: String = steps[k - 1]["state"] if k > 0 else first["start"]
		if _state(level) != expected:
			failures.append(
				(
					"undo of call %d (%s) did not give back the level from before it: %s"
					% [
						call_index,
						_name(calls[call_index]),
						_first_difference(expected, _state(level))
					]
				)
			)
			break
	if failures.is_empty():
		var beyond := await call_tool("hf_undo")
		if beyond.get("ok", false) and _state(level) != first["start"]:
			failures.append("an undo past the run's first step changed the starting level")
	# Redo, walking forward again.
	if failures.is_empty():
		for k in steps.size():
			var redone := await call_tool("hf_redo")
			var call_index: int = steps[k]["call"]
			if not redone.get("ok", false):
				failures.append(
					(
						"redo of call %d (%s) refused: %s"
						% [call_index, _name(calls[call_index]), redone]
					)
				)
				break
			if _state(level) != steps[k]["state"]:
				failures.append(
					(
						"redo of call %d (%s) did not give back the level after it: %s"
						% [
							call_index,
							_name(calls[call_index]),
							_first_difference(steps[k]["state"], _state(level))
						]
					)
				)
				break
	var end_content := _content(level)
	# The same calls on a fresh level end in the same level.
	if failures.is_empty():
		var second := await _make_calls(seed_value, count)
		if _content(second["level"]) != end_content:
			failures.append("the same %d calls on a fresh level ended in a different level" % count)
	if not failures.is_empty():
		_write_run(seed_value, calls)
	return {"failures": failures, "calls": calls, "steps": steps.size()}


## One run of calls on a fresh level: the level, the calls, the capture after each
## call that made a step, and anything a refusal changed.
func _make_calls(seed_value: int, count: int) -> Dictionary:
	_rng.seed = seed_value
	_entity_count = 0
	var level := make_level_with_palette()
	await place_box([0, 1, 0], [4, 2, 4])
	await place_box([6, 1, 0], [2, 2, 2])
	await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 4, 0], "name": "lamp"}
	)
	undo.scene_history.clear_history()
	var start := _state(level)
	var calls: Array = []
	var steps: Array = []
	var failures: Array = []
	for i in count:
		var call := _pick_call(level)
		var before := _state(level)
		var steps_before: int = undo.scene_history.get_history_count()
		var answer := await call_tool(call["tool"], call["params"])
		call["ok"] = answer.get("ok", false)
		if not call["ok"]:
			call["error"] = str(answer.get("error", {}).get("code", ""))
		calls.append(call)
		var made: int = undo.scene_history.get_history_count() - steps_before
		if made > 1:
			failures.append("call %d (%s) made %d steps, not one" % [i, _name(call), made])
		elif made == 1:
			steps.append({"call": i, "state": _state(level)})
		elif _state(level) != before:
			failures.append("call %d (%s) changed the level with no step" % [i, _name(call)])
	return {"level": level, "start": start, "calls": calls, "steps": steps, "failures": failures}


## A valid call picked from the level as it is now.
func _pick_call(level: LevelRoot) -> Dictionary:
	var ids := _brush_ids(level)
	var entities := _entity_paths(level)
	var roll := _rng.randi_range(0, 99)
	if ids.is_empty() or roll < 18:
		return _call(
			"hf_place_brush",
			{
				"size": [_rng.randi_range(1, 4), _rng.randi_range(1, 3), _rng.randi_range(1, 4)],
				"position": _spot(),
				"operation": "subtract" if _rng.randf() < 0.2 else "union",
			}
		)
	var brush_id: String = ids[_rng.randi_range(0, ids.size() - 1)]
	if roll < 28:
		var params := {"brush_id": brush_id}
		if _rng.randf() < 0.5:
			params["position"] = _spot()
		else:
			params["rotation_degrees"] = [0, 90 * _rng.randi_range(0, 3), 0]
		return _call("hf_transform_brush", params)
	if roll < 33:
		return _call(
			"hf_resize_brush",
			{"brush_id": brush_id, "size": [_rng.randi_range(1, 4), 2, _rng.randi_range(1, 4)]}
		)
	if roll < 37 and ids.size() > 2:
		return _call("hf_delete_brush", {"brush_id": brush_id})
	if roll < 42:
		var faces := ["+x", "-x", "+y", "-y", "+z", "-z"]
		return _call(
			"hf_extrude_face",
			{
				"brush_id": brush_id,
				"face": faces[_rng.randi_range(0, 5)],
				"distance": _rng.randi_range(1, 2)
			}
		)
	if roll < 48:
		return _call(
			"hf_assign_material",
			{"brush_id": brush_id, "material": "palette:%d" % _rng.randi_range(0, 3)}
		)
	if roll < 52:
		return _call(
			"hf_set_brush_entity",
			{
				"brush_ids": [brush_id],
				"entity_class": BRUSH_CLASSES[_rng.randi_range(0, BRUSH_CLASSES.size() - 1)]
			}
		)
	if roll < 57:
		_entity_count += 1
		return _call(
			"hf_place_entity",
			{"entity_class": "light_point", "position": _spot(3), "name": "lamp_%d" % _entity_count}
		)
	if roll < 62 and not entities.is_empty():
		return _call(
			"hf_transform_entity",
			{"entity": entities[_rng.randi_range(0, entities.size() - 1)], "position": _spot(3)}
		)
	if roll < 66 and not entities.is_empty():
		return _call(
			"hf_set_entity_properties",
			{
				"entity": entities[_rng.randi_range(0, entities.size() - 1)],
				"properties": {"energy": _rng.randi_range(1, 4)}
			}
		)
	if roll < 69 and entities.size() > 1:
		return _call(
			"hf_delete_entity", {"entity": entities[_rng.randi_range(0, entities.size() - 1)]}
		)
	if roll < 74:
		return _call(
			"hf_set_cordon", {"brush_ids": [brush_id], "name": "C%d" % _rng.randi_range(0, 9)}
		)
	if roll < 77:
		return _call("hf_remove_cordon", {"index": 0})
	if roll < 80:
		return _call("hf_set_spawn", {"position": _spot(0)})
	if roll < 85:
		var ops: Array = []
		for _i in _rng.randi_range(2, 3):
			ops.append(
				{"tool": "hf_place_brush", "params": {"size": [1, 1, 1], "position": _spot()}}
			)
		return _call("hf_batch", {"ops": ops})
	var names := COMMANDS.keys()
	var command: String = names[_rng.randi_range(0, names.size() - 1)]
	var spec: Dictionary = COMMANDS[command]
	var targets: Array = []
	for _i in int(spec["brushes"]):
		targets.append(ids[_rng.randi_range(0, ids.size() - 1)])
	var params: Dictionary = (spec["params"] as Dictionary).duplicate(true)
	if command == "create_arch":
		params["position"] = _spot(0)
	return _call("hf_run_command", {"command": command, "brush_ids": targets, "params": params})


func _call(tool: String, params: Dictionary) -> Dictionary:
	return {"tool": tool, "params": params}


## A point on the grid near the middle of the level.
func _spot(height := 1) -> Array:
	return [_rng.randi_range(-8, 8), height, _rng.randi_range(-8, 8)]


## The brushes a call may name, in the level's own order, which two runs of the
## same calls share. Committed cutters are frozen and refused by every tool.
func _brush_ids(level: LevelRoot) -> Array:
	var out: Array = []
	for container in [level.draft_brushes_node, level.pending_node]:
		if container == null:
			continue
		for child in container.get_children():
			if child is DraftBrush and not child.is_queued_for_deletion():
				out.append(str(child.brush_id))
	return out


func _entity_paths(level: LevelRoot) -> Array:
	var out: Array = []
	for child in level.entities_node.get_children():
		if child is DraftEntity and not child.is_queued_for_deletion():
			out.append(str(level.get_path_to(child)))
	return out


static func _name(call: Dictionary) -> String:
	if call["tool"] == "hf_run_command":
		return "hf_run_command %s" % call["params"].get("command", "")
	return str(call["tool"])


## The level and its cordons, which no level state holds (#1300).
func _state(level: LevelRoot) -> String:
	return var_to_str({"level": level.capture_state(false), "cordons": level.capture_cordons()})


## What the level holds, without its ids, which carry the clock and differ from
## one run to the next: each brush's shape, size, place, operation and face
## materials, and each entity's class, place and properties.
static func _content(level: LevelRoot) -> Array:
	var out: Array = []
	for node in level._iter_managed_brush_nodes():
		var brush := node as DraftBrush
		var slots: Array = []
		for face in brush.faces:
			slots.append(face.material_idx if face != null else -1)
		out.append(
			var_to_str(
				[
					brush.shape,
					brush.size.snapped(Vector3.ONE * 0.001),
					brush.global_transform.origin.snapped(Vector3.ONE * 0.001),
					brush.operation,
					slots
				]
			)
		)
	for child in level.entities_node.get_children():
		if child is DraftEntity:
			out.append(
				var_to_str(
					[
						child.entity_class,
						child.global_position.snapped(Vector3.ONE * 0.001),
						child.entity_data
					]
				)
			)
	out.sort()
	return out


## Where two captures first differ, a line of each, for the failure message.
static func _first_difference(expected: String, actual: String) -> String:
	var want := expected.split("\n")
	var got := actual.split("\n")
	for i in mini(want.size(), got.size()):
		if want[i] != got[i]:
			return "line %d was %s, is %s" % [i, want[i].strip_edges(), got[i].strip_edges()]
	return "%d lines, now %d" % [want.size(), got.size()]


func _write_run(seed_value: int, calls: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FAILED_RUNS))
	var file := FileAccess.open("%s/seed_%d.jsonl" % [FAILED_RUNS, seed_value], FileAccess.WRITE)
	if file == null:
		return
	for call in calls:
		file.store_line(JSON.stringify(call))
	file.close()
