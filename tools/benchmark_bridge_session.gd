extends SceneTree
## How an agent session's small bridge calls cost as the level grows (#1652).
##
## It drives the bridge's dispatcher directly, with no socket, so every number is
## the editor's own, and builds a town through `hf_*` calls the way an agent
## would: per room a floor, four walls, a doorway cut, a flight of stairs, a lamp,
## a trigger tied to `trigger_once` and a door tied to `func_door`, wired, the
## floor painted, and a count read back. Every 100 calls it prints one JSON line: the call count, the
## brush count, the mean and slowest call, and the time in the parts of a change,
## the undo record (`capture` and `commit`), the change and its answer (`apply`),
## and the change check the plugin runs after every step. At the end it saves the
## level, opens it again, and times both.
##
## Usage:
##   godot --headless -s res://tools/benchmark_bridge_session.gd --path .
##   godot --headless -s res://tools/benchmark_bridge_session.gd --path . -- --scale=0.1
##
## `--scale=1` is 100 rooms, 1,500 calls.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const ChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")

const ROOMS_AT_SCALE_ONE := 100
const ROOM_SPACING := 14.0
const REPORT_EVERY := 100

var _scale := 1.0


func _init() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scale="):
			_scale = maxf(0.01, float(arg.trim_prefix("--scale=")))
	OS.low_processor_usage_mode_sleep_usec = 0
	await process_frame
	var bench := await set_up(get_root())
	var rooms := maxi(1, roundi(ROOMS_AT_SCALE_ONE * _scale))
	var summary: Dictionary = await run_session(
		bench, rooms, func(line: Dictionary): print(JSON.stringify(line))
	)
	var path := "user://hf_benchmark_bridge_session_%d.hflevel" % OS.get_process_id()
	var level: Node = bench["level"]
	# The file is written on a thread; the save is done when the level says so.
	# Outside the editor nothing collects a finished save, so this does.
	var done: Array = []
	level.hflevel_save_completed.connect(func(_p): done.append(true), CONNECT_ONE_SHOT)
	level.hflevel_save_failed.connect(func(_p, _m): done.append(false), CONNECT_ONE_SHOT)
	var began := Time.get_ticks_usec()
	var saved: int = level.save_hflevel(path, true)
	while saved == OK and done.is_empty() and _ms(began) < 120000.0:
		await process_frame
		level._process_hflevel_saves()
	summary["save_ms"] = _ms(began)
	summary["save_ok"] = saved == OK and done == [true]
	var again: Node3D = LevelRootScript.new()
	again.auto_spawn_player = false
	again.hflevel_autosave_enabled = false
	get_root().add_child(again)
	began = Time.get_ticks_usec()
	summary["open_ok"] = again.load_hflevel(path)
	summary["open_ms"] = _ms(began)
	print(JSON.stringify(summary))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	bench["dispatcher"].shutdown()
	bench["undo"].free_histories()
	(bench["scene"] as Node).free()
	again.free()
	quit()


## A level in a scene the dispatcher sees, with the undo stand-in and the change
## tracker the plugin runs: `{dispatcher, undo, level, tracker, requests}`.
static func set_up(parent: Node) -> Dictionary:
	var undo = UndoStandIn.new()
	var host = HostStandIn.new()
	host.undo = undo
	host.tree = parent.get_tree()
	var scene := Node3D.new()
	scene.name = "Scene"
	var level: Node3D = LevelRootScript.new()
	level.name = "LevelRoot"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	scene.add_child(level)
	parent.add_child(scene)
	host.scene = scene
	# The palette the editor gives a new level, for the floors to be painted from.
	level.add_prototype_materials()
	await parent.get_tree().process_frame
	var tracker: RefCounted = ChangeTracker.new()
	tracker.prime(level)
	return {
		"dispatcher": HFMcpDispatcher.new(host),
		"undo": undo,
		"host": host,
		"scene": scene,
		"level": level,
		"tracker": tracker,
		"requests": 0,
	}


## Build `rooms` rooms through the bridge, calling `report` with a line every
## `REPORT_EVERY` calls and once at the end. Gives back the totals, with `failed`
## the calls that were refused.
static func run_session(bench: Dictionary, rooms: int, report: Callable) -> Dictionary:
	var totals := {
		"calls": 0,
		"failed": [],
		"slowest_ms": 0.0,
		"call_ms": 0.0,
		"check_ms": 0.0,
		"capture_ms": 0.0,
		"apply_ms": 0.0,
		"commit_ms": 0.0,
		"place_calls": 0,
		"place_record_ms": 0.0,
	}
	var window := totals.duplicate(true)
	var side := ceili(sqrt(float(rooms)))
	for room in rooms:
		var x := float(room % side) * ROOM_SPACING
		var z := floorf(float(room) / side) * ROOM_SPACING
		for call in _room_calls(room, x, z):
			await _call(bench, call[0], call[1], totals, window)
			if int(totals["calls"]) % REPORT_EVERY == 0:
				report.call(_line(bench, totals, window))
				window = _fresh(window)
	if int(window["calls"]) > 0:
		report.call(_line(bench, totals, window))
	var summary := _line(bench, totals, totals)
	summary["failed"] = totals["failed"]
	return summary


## One room's calls, `[method, params]`. Ids are named, so the wiring can aim at
## what the room made.
static func _room_calls(room: int, x: float, z: float) -> Array:
	var r := "r%d" % room
	return [
		[
			"hf_place_brush",
			{"size": [10, 0.5, 10], "position": [x, -0.25, z], "name": r + "_floor"}
		],
		["hf_place_brush", {"size": [10, 3, 0.5], "position": [x, 1.5, z - 5.25]}],
		["hf_place_brush", {"size": [10, 3, 0.5], "position": [x, 1.5, z + 5.25]}],
		["hf_place_brush", {"size": [0.5, 3, 10], "position": [x - 5.25, 1.5, z]}],
		["hf_place_brush", {"size": [0.5, 3, 10], "position": [x + 5.25, 1.5, z]}],
		[
			"hf_place_brush",
			{"size": [2, 2.5, 1], "position": [x, 1.25, z + 5.25], "operation": "subtract"}
		],
		[
			"hf_run_command",
			{"command": "create_arch", "params": {"type": "stairs", "position": [x + 2, 0, z - 3]}}
		],
		[
			"hf_place_entity",
			{"entity_class": "light_point", "position": [x, 2.5, z], "name": r + "_lamp"}
		],
		["hf_place_brush", {"size": [2, 2, 2], "position": [x - 3, 1, z + 3], "name": r + "_trig"}],
		["$tie", {"name": r + "_trig", "entity_class": "trigger_once", "entity_name": r + "_t"}],
		[
			"hf_place_brush",
			{"size": [2, 2.5, 0.2], "position": [x, 1.25, z + 6.0], "name": r + "_door"}
		],
		["$tie", {"name": r + "_door", "entity_class": "func_door", "entity_name": r + "_d"}],
		["$wire", {"from": r + "_trig", "target": r + "_d"}],
		["$paint", {"name": r + "_floor", "material": "palette:%d" % (1 + room % 4)}],
		["hf_get_brushes", {"count_only": true}],
	]


static func _call(
	bench: Dictionary, method: String, params: Dictionary, totals: Dictionary, window: Dictionary
) -> void:
	var dispatcher = bench["dispatcher"]
	var level: Node = bench["level"]
	# Four of a room's calls name a brush by the name the room gave it.
	if method == "$tie":
		method = "hf_set_brush_entity"
		params = {
			"brush_ids": [_id_named(level, params["name"])],
			"entity_class": params["entity_class"],
			"name": params["entity_name"],
		}
	elif method == "$paint":
		method = "hf_assign_material"
		params = {
			"brush_id": _id_named(level, params["name"]),
			"material": params["material"],
			"faces": ["+y"],
		}
	elif method == "$wire":
		method = "hf_add_entity_output"
		params = {
			"brush_id": _id_named(level, params["from"]),
			"output_name": "OnStartTouch",
			"target_name": params["target"],
			"input_name": "Open",
		}
	bench["requests"] = int(bench["requests"]) + 1
	dispatcher.last_timings = {}
	var began := Time.get_ticks_usec()
	var answer: Dictionary = await dispatcher.handle(
		{"type": "request", "id": "b%d" % bench["requests"], "method": method, "params": params}
	)
	var took := _ms(began)
	var undo = bench["undo"]
	var checked := Time.get_ticks_usec()
	var history: UndoRedo = undo.scene_history
	bench["tracker"].note_step(
		history.get_version(), history.has_redo(), history.get_current_action_name()
	)
	bench["tracker"].reconcile_step(level, [])
	var check := _ms(checked)
	for sums in [totals, window]:
		sums["calls"] = int(sums["calls"]) + 1
		sums["call_ms"] = float(sums["call_ms"]) + took
		sums["check_ms"] = float(sums["check_ms"]) + check
		sums["slowest_ms"] = maxf(float(sums["slowest_ms"]), took)
		for part in ["capture", "apply", "commit"]:
			sums[part + "_ms"] = (
				float(sums[part + "_ms"]) + float(dispatcher.last_timings.get(part, 0)) / 1000.0
			)
		# A solid placement's own undo record, which should not grow (#1786).
		if method == "hf_place_brush" and str(params.get("operation", "union")) == "union":
			sums["place_calls"] = int(sums["place_calls"]) + 1
			sums["place_record_ms"] = (
				float(sums["place_record_ms"])
				+ (
					(
						float(dispatcher.last_timings.get("capture", 0))
						+ float(dispatcher.last_timings.get("commit", 0))
					)
					/ 1000.0
				)
			)
	if not answer.get("ok", false):
		(totals["failed"] as Array).append(
			"%s: %s" % [method, str(answer.get("error", {}).get("message", ""))]
		)


static func _id_named(level: Node, brush_name: String) -> String:
	for brush in level._iter_managed_brush_nodes():
		if str(brush.name) == brush_name:
			return str(brush.brush_id)
	return brush_name


static func _line(bench: Dictionary, totals: Dictionary, window: Dictionary) -> Dictionary:
	var calls := maxi(1, int(window["calls"]))
	return {
		"calls": totals["calls"],
		"brushes": (bench["level"] as Node)._iter_managed_brush_nodes().size(),
		"mean_ms": snappedf(float(window["call_ms"]) / calls, 0.001),
		"slowest_ms": snappedf(float(window["slowest_ms"]), 0.001),
		"undo_record_ms":
		snappedf((float(window["capture_ms"]) + float(window["commit_ms"])) / calls, 0.001),
		"apply_ms": snappedf(float(window["apply_ms"]) / calls, 0.001),
		"change_check_ms": snappedf(float(window["check_ms"]) / calls, 0.001),
		"place_record_ms":
		snappedf(float(window["place_record_ms"]) / maxi(1, int(window["place_calls"])), 0.001),
	}


static func _fresh(window: Dictionary) -> Dictionary:
	var out := window.duplicate(true)
	for key in out:
		if out[key] is float or out[key] is int:
			out[key] = 0 if out[key] is int else 0.0
	out["failed"] = []
	return out


static func _ms(began_usec: int) -> float:
	return float(Time.get_ticks_usec() - began_usec) / 1000.0
