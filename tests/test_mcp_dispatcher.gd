extends GutTest

## The MCP dispatcher on a real LevelRoot, with an undo stand-in that wraps a
## real `UndoRedo`, so undo and redo here actually run.

const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const HFMcpProtocol = preload("res://addons/hammerforge/mcp/hf_mcp_protocol.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")


## Builds a brush, then reports that it failed, so the wrapper has real work to
## take back.
class BrushThenFailLevel:
	extends LevelRoot

	func create_brush_from_info(info: Dictionary) -> Node:
		super.create_brush_from_info(info)
		return null


var host: HostStandIn
var undo
var dispatcher
var _request_count := 0


func before_each() -> void:
	_request_count = 0
	undo = UndoStandIn.new()
	host = HostStandIn.new()
	host.undo = undo
	host.tree = get_tree()
	dispatcher = HFMcpDispatcher.new(host)


func after_each() -> void:
	dispatcher.shutdown()
	undo.free_histories()


func _make_scene(level: LevelRoot = null) -> Node3D:
	var scene := Node3D.new()
	scene.name = "Scene"
	if level != null:
		level.name = "LevelRoot"
		level.auto_spawn_player = false
		level.hflevel_autosave_enabled = false
		level.grid_snap = 1.0
		scene.add_child(level)
	add_child_autoqfree(scene)
	host.scene = scene
	return scene


func _make_level() -> LevelRoot:
	var level := LevelRoot.new()
	_make_scene(level)
	return level


func _call(method: String, params := {}, extra := {}) -> Dictionary:
	_request_count += 1
	var request := {
		"type": "request", "id": "r%d" % _request_count, "method": method, "params": params
	}
	request.merge(extra, true)
	return await dispatcher.handle(request)


func _place_params(position := [0, 1.5, 0], size := [4, 3, 4]) -> Dictionary:
	return {"shape": "box", "size": size, "position": position}


func _brushes(level: LevelRoot) -> Array:
	return level._iter_managed_brush_nodes()


# --- Status and target -----------------------------------------------------


func test_status_without_a_scene():
	var r := await _call("hf_get_status")
	assert_true(r["ok"], str(r))
	assert_eq(r["id"], "r1")
	assert_true(str(r["target_id"]).ends_with(":0:0"))
	assert_null(r["result"]["target"]["level_root_path"])
	assert_eq(int(r["result"]["bridge_version"]), HFMcpProtocol.BRIDGE_VERSION)


func test_status_with_a_scene_and_no_level_then_place_is_refused():
	var scene := _make_scene()
	var status := await _call("hf_get_status")
	assert_true(status["ok"])
	assert_null(status["result"]["target"]["level_root_path"])
	assert_eq(status["target_id"], "%d:%d:0" % [OS.get_process_id(), scene.get_instance_id()])
	var placed := await _call("hf_place_brush", _place_params())
	assert_false(placed["ok"])
	assert_eq(placed["error"]["code"], "no_level")
	assert_eq(scene.get_child_count(), 0)


func test_place_without_a_scene_is_refused():
	var placed := await _call("hf_place_brush", _place_params())
	assert_false(placed["ok"])
	assert_eq(placed["error"]["code"], "no_edited_scene")


func test_status_with_a_level():
	var level := _make_level()
	var r := await _call("hf_get_status")
	assert_true(r["ok"])
	var result: Dictionary = r["result"]
	assert_eq(
		r["target_id"],
		"%d:%d:%d" % [OS.get_process_id(), host.scene.get_instance_id(), level.get_instance_id()]
	)
	assert_eq(result["target"]["level_root_path"], "LevelRoot")
	assert_eq(int(result["counts"]["brushes"]), 0)
	assert_almost_eq(float(result["grid_snap"]), 1.0, 0.0001)
	assert_true(r["revision"] is int)
	assert_null(result["last_agent_revision"])
	assert_eq(result["busy"], "")


# --- Place brush -----------------------------------------------------------


func test_place_box_is_one_named_undo_step():
	var level := _make_level()
	# Attach first, so the target bump is behind us and only the commit counts.
	await _call("hf_get_status")
	var before: int = dispatcher.revision()
	var r := await _call("hf_place_brush", _place_params())
	assert_true(r["ok"], str(r))
	assert_eq(_brushes(level).size(), 1)
	var brush: Dictionary = r["result"]["brush"]
	assert_eq(brush["shape"], "box")
	assert_eq(brush["operation"], "union")
	assert_eq(brush["position"], [0.0, 1.5, 0.0])
	assert_eq(brush["size"], [4.0, 3.0, 4.0])
	assert_eq(brush["rotation_degrees"], [0.0, 0.0, 0.0])
	assert_eq(brush["bounds"], {"min": [-2.0, 0.0, -2.0], "max": [2.0, 3.0, 2.0]})
	assert_eq((brush["faces"] as Array).size(), 6)
	assert_eq(undo.scene_history.get_current_action_name(), "MCP: place brush")
	assert_eq(undo.scene_history.get_history_count(), 1)
	assert_eq(host.history, ["MCP: place brush"])
	assert_eq(r["revision"], before + 1, "one version_changed, one revision")
	assert_eq(dispatcher.revision(), r["revision"])


func test_place_reports_the_world_normal_and_centre_of_each_face():
	_make_level()
	var r := await _call("hf_place_brush", _place_params())
	var by_normal := {}
	for face in r["result"]["brush"]["faces"]:
		by_normal[str(face["normal"])] = face["center"]
	assert_eq(by_normal[str([0.0, 1.0, 0.0])], [0.0, 3.0, 0.0])
	assert_eq(by_normal[str([1.0, 0.0, 0.0])], [2.0, 1.5, 0.0])


func test_place_snaps_size_and_lowest_corner_to_the_grid():
	_make_level()
	var r := await _call("hf_place_brush", _place_params([0.3, 1.5, 0], [1.2, 2.9, 3]))
	assert_true(r["ok"], str(r))
	var brush: Dictionary = r["result"]["brush"]
	assert_eq(brush["size"], [1.0, 3.0, 3.0])
	var low: Array = brush["bounds"]["min"]
	for value in low:
		assert_almost_eq(float(value), roundf(float(value)), 0.0001, "corner on the grid")
	assert_true(r["result"]["snapped"])


func test_place_without_snap_keeps_the_values():
	_make_level()
	var params := _place_params([0.3, 1.5, 0], [1.2, 2.9, 3])
	params["snap"] = false
	var r := await _call("hf_place_brush", params)
	var brush: Dictionary = r["result"]["brush"]
	assert_eq(brush["size"], [1.2, 2.9, 3.0])
	assert_eq(brush["position"], [0.3, 1.5, 0.0])
	assert_false(r["result"]["snapped"])


func test_place_subtract_goes_to_the_pending_cuts():
	var level := _make_level()
	var params := _place_params()
	params["operation"] = "subtract"
	var r := await _call("hf_place_brush", params)
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["brush"]["operation"], "subtract")
	assert_true(r["result"]["brush"]["pending"])
	assert_eq(level.pending_node.get_child_count(), 1)


func test_place_another_shape():
	_make_level()
	var params := _place_params()
	params["shape"] = "cylinder"
	var r := await _call("hf_place_brush", params)
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["brush"]["shape"], "cylinder")


func test_undo_then_redo_brings_back_the_same_brush_id():
	var level := _make_level()
	var r := await _call("hf_place_brush", _place_params())
	var brush_id: String = r["result"]["brush"]["brush_id"]
	assert_ne(brush_id, "")
	undo.scene_history.undo()
	assert_eq(_brushes(level).size(), 0)
	undo.scene_history.redo()
	var brushes := _brushes(level)
	assert_eq(brushes.size(), 1)
	assert_eq((brushes[0] as DraftBrush).brush_id, brush_id)


func test_invalid_input_changes_nothing():
	var level := _make_level()
	var cases := [
		[{"shape": "box", "size": [NAN, 1, 1], "position": [0, 0, 0]}, "size"],
		[{"shape": "box", "size": [1, 2], "position": [0, 0, 0]}, "size"],
		[{"shape": "box", "size": [0, 1, 1], "position": [0, 0, 0]}, "size"],
		[{"shape": "box", "position": [0, 0, 0]}, "size"],
		[{"shape": "blob", "size": [1, 1, 1], "position": [0, 0, 0]}, "shape"],
		[{"shape": "custom", "size": [1, 1, 1], "position": [0, 0, 0]}, "shape"],
		[{"shape": "box", "size": [1, 1, 1], "position": "x"}, "position"],
		[{"shape": "box", "size": [1, 1, 1], "position": [0, 0, 0], "operation": "x"}, "operation"],
		[{"shape": "box", "size": [1, 1, 1], "position": [0, 0, 0], "snap": "yes"}, "snap"],
	]
	var state_before: Dictionary = level.capture_state(false)
	for case in cases:
		var r := await _call("hf_place_brush", case[0])
		assert_false(r["ok"], "refused: %s" % str(case[0]))
		if r["ok"]:
			continue
		assert_eq(r["error"]["code"], "invalid_argument", str(case[0]))
		assert_eq(r["error"]["details"]["param"], case[1], str(case[0]))
	assert_eq_deep(level.capture_state(false), state_before)
	assert_eq(undo.scene_history.get_history_count(), 0)
	assert_eq(host.history, [])


func test_params_that_are_not_an_object_are_a_bad_request():
	_make_level()
	_request_count += 1
	var r: Dictionary = await dispatcher.handle(
		{"type": "request", "id": "x", "method": "hf_place_brush", "params": [1]}
	)
	assert_false(r["ok"])
	assert_eq(r["error"]["code"], "bad_request")


func test_unknown_method():
	var r := await _call("hf_explode")
	assert_false(r["ok"])
	assert_eq(r["error"]["code"], "unknown_method")


# --- operation_id ----------------------------------------------------------


func test_same_operation_id_and_params_replays_instead_of_running():
	var level := _make_level()
	var first := await _call("hf_place_brush", _place_params(), {"operation_id": "op-1"})
	var second := await _call("hf_place_brush", _place_params(), {"operation_id": "op-1"})
	assert_true(second["ok"])
	assert_true(second["replayed"])
	assert_false(first["replayed"])
	assert_eq(second["id"], "r2")
	assert_eq(second["revision"], first["revision"])
	assert_eq(second["result"], first["result"])
	assert_eq(_brushes(level).size(), 1)
	assert_eq(undo.scene_history.get_history_count(), 1)


func test_same_operation_id_with_other_params_is_a_conflict():
	var level := _make_level()
	await _call("hf_place_brush", _place_params(), {"operation_id": "op-2"})
	var other := await _call("hf_place_brush", _place_params([8, 1.5, 0]), {"operation_id": "op-2"})
	assert_false(other["ok"])
	assert_eq(other["error"]["code"], "operation_id_conflict")
	assert_eq(_brushes(level).size(), 1)


func test_a_failed_command_is_not_cached():
	var level := _make_level()
	var bad := await _call(
		"hf_place_brush",
		{"shape": "box", "size": [0, 1, 1], "position": [0, 0, 0]},
		{"operation_id": "op-3"}
	)
	assert_false(bad["ok"])
	var good := await _call("hf_place_brush", _place_params(), {"operation_id": "op-3"})
	assert_true(good["ok"], str(good))
	assert_false(good["replayed"])
	assert_eq(_brushes(level).size(), 1)


func test_a_bad_operation_id_is_refused():
	_make_level()
	var r := await _call("hf_place_brush", _place_params(), {"operation_id": "has space"})
	assert_false(r["ok"])
	assert_eq(r["error"]["code"], "invalid_argument")
	assert_eq(r["error"]["details"]["param"], "operation_id")


func test_the_cache_forgets_the_oldest_entry_past_its_size():
	_make_level()
	for i in HFMcpDispatcher.OPERATION_CACHE_SIZE + 1:
		dispatcher._remember("op-%d" % i, "fp", {"ok": true})
	assert_false(dispatcher._operation_cache.has("op-0"))
	assert_true(dispatcher._operation_cache.has("op-1"))
	assert_eq(dispatcher._operation_cache.size(), HFMcpDispatcher.OPERATION_CACHE_SIZE)


# --- expect_target and revision --------------------------------------------


func test_a_stale_expect_target_is_refused_with_the_current_one():
	var level := _make_level()
	var r := await _call("hf_place_brush", _place_params(), {"expect_target": "1:2:3"})
	assert_false(r["ok"])
	assert_eq(r["error"]["code"], "target_changed")
	var expected := (
		"%d:%d:%d" % [OS.get_process_id(), host.scene.get_instance_id(), level.get_instance_id()]
	)
	assert_eq(r["error"]["details"]["current"]["target_id"], expected)
	assert_eq(_brushes(level).size(), 0)


func test_status_ignores_expect_target_so_it_can_reattach():
	_make_level()
	var r := await _call("hf_get_status", {}, {"expect_target": "1:2:3"})
	assert_true(r["ok"])


func test_a_matching_expect_target_runs():
	_make_level()
	var status := await _call("hf_get_status")
	var r := await _call("hf_place_brush", _place_params(), {"expect_target": status["target_id"]})
	assert_true(r["ok"], str(r))


func test_an_action_committed_by_someone_else_moves_the_revision_by_one():
	_make_level()
	await _call("hf_get_status")
	var before: int = dispatcher.revision()
	var marker := Node.new()
	undo.scene_history.create_action("Human edit")
	undo.scene_history.add_do_property(marker, "name", "after")
	undo.scene_history.add_undo_property(marker, "name", "before")
	undo.scene_history.commit_action()
	assert_eq(dispatcher.revision(), before + 1)
	undo.global_history.create_action("Global edit")
	undo.global_history.add_do_property(marker, "name", "again")
	undo.global_history.add_undo_property(marker, "name", "after")
	undo.global_history.commit_action()
	assert_eq(dispatcher.revision(), before + 2)
	marker.free()


func test_switching_scene_moves_the_revision_and_the_target():
	_make_level()
	var first := await _call("hf_get_status")
	_make_scene(LevelRoot.new())
	var second := await _call("hf_get_status")
	assert_ne(second["target_id"], first["target_id"])
	assert_gt(second["revision"], first["revision"])


func test_last_agent_revision_is_the_place_responses():
	_make_level()
	var placed := await _call("hf_place_brush", _place_params())
	var status := await _call("hf_get_status")
	assert_eq(int(status["result"]["last_agent_revision"]), placed["revision"])


# --- Rolling back ----------------------------------------------------------


func test_a_failed_apply_puts_the_level_back():
	var level := BrushThenFailLevel.new()
	_make_scene(level)
	var state_before: Dictionary = level.capture_state(false)
	var r := await _call("hf_place_brush", _place_params())
	assert_false(r["ok"])
	assert_eq(r["error"]["code"], "operation_failed")
	assert_true(r["error"]["details"]["rolled_back"])
	assert_eq(_brushes(level).size(), 0)
	assert_eq_deep(level.capture_state(false), state_before)
	assert_eq(undo.scene_history.get_history_count(), 0)


# --- Review follow-ups -----------------------------------------------------


## A dispatcher whose place check hits a real script error, so the call gives
## back null the way a bug in a handler would.
class BrokenCheckDispatcher:
	extends "res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd"

	func _check_place_brush(_root: Node, _params: Dictionary) -> Dictionary:
		var nothing: Object = null
		nothing.call("explode")
		return {}


func test_a_handler_that_returns_nothing_is_an_internal_error_and_clears_busy():
	_make_level()
	dispatcher.shutdown()
	dispatcher = BrokenCheckDispatcher.new(host)
	var r := await _call("hf_place_brush", _place_params())
	assert_engine_error_count(1, "the script error the check hits")
	assert_false(r["ok"])
	assert_eq(r["error"]["code"], "internal_error")
	var status := await _call("hf_get_status")
	assert_eq(status["result"]["busy"], "", "busy cleared after the failure")


func test_a_committed_change_replays_after_the_editor_moved_on():
	_make_level()
	var status := await _call("hf_get_status")
	var extra := {"operation_id": "op-moved", "expect_target": status["target_id"]}
	var first := await _call("hf_place_brush", _place_params(), extra)
	assert_true(first["ok"], str(first))
	_make_scene(LevelRoot.new())
	var again := await _call("hf_place_brush", _place_params(), extra)
	assert_true(again["ok"], "replayed, not refused: %s" % str(again))
	assert_true(again["replayed"])
	var fresh := await _call(
		"hf_place_brush", _place_params(), {"expect_target": status["target_id"]}
	)
	assert_eq(fresh["error"]["code"], "target_changed", "a new change is still refused")


var _late: Dictionary = {}


func _place_in_background(params: Dictionary) -> void:
	_late = await _call("hf_place_brush", params)


func test_an_answer_names_the_level_that_changed_even_if_status_moved_on():
	var level := _make_level()
	var status := await _call("hf_get_status")
	host.wait_frames = 5
	_late = {}
	_place_in_background(_place_params())
	# While the place waits out its frames, the user opens another scene and a
	# status request attaches the dispatcher to it.
	_make_scene(LevelRoot.new())
	var moved := await _call("hf_get_status")
	assert_ne(moved["target_id"], status["target_id"])
	for i in 20:
		if not _late.is_empty():
			break
		await get_tree().process_frame
	assert_true(_late.get("ok", false), str(_late))
	assert_eq(_late["target_id"], status["target_id"], "the level that changed")
	assert_eq(_brushes(level).size(), 1)
