extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_bake: bake the level, write the scene a runtime test loads, and say which
## bake it is. A bake is not an authoring change: no undo step, no revision move.

const ARTIFACT := "user://mcp_bake_test/level_mcp.tscn"


## A level whose bake can be told to fail, to hold for a few frames, or to say
## another bake is running.
class ScriptedBakeLevel:
	extends LevelRoot

	var fail := false
	var hold_frames := 0
	var busy := false

	func is_bake_in_flight() -> bool:
		return busy or super.is_bake_in_flight()

	func bake(
		apply_cuts: bool = true,
		hide_live: bool = false,
		collision_layer_mask: int = 0,
		preview_mode: int = 0,
		force_csg: bool = false
	) -> bool:
		for i in hold_frames:
			await get_tree().process_frame
		if fail:
			return false
		return await super.bake(
			apply_cuts, hide_live, collision_layer_mask, preview_mode, force_csg
		)


func before_each() -> void:
	super.before_each()
	host.artifact_path_override = ARTIFACT


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(ARTIFACT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ARTIFACT))


func _artifact_meta() -> Dictionary:
	var packed := ResourceLoader.load(ARTIFACT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return {}
	var scene: Node = packed.instantiate()
	var meta: Dictionary = scene.get_meta("hammerforge_bake", {})
	scene.free()
	return meta


func test_a_bake_writes_the_scene_and_says_which_bake_it_is():
	var level := make_level()
	await place_box()
	var status := await call_tool("hf_get_status")
	var steps: int = undo.scene_history.get_history_count()
	var r := await call_tool("hf_bake")
	assert_true(r["ok"], str(r))
	var result: Dictionary = r["result"]
	assert_eq(result["artifact"]["path"], ARTIFACT)
	assert_true(FileAccess.file_exists(ARTIFACT))
	var meta := _artifact_meta()
	assert_eq(meta.get("bake_id"), result["bake_id"])
	assert_eq(int(meta.get("source_revision", -1)), int(result["source_revision"]))
	assert_eq(meta.get("target_id"), status["target_id"])
	assert_eq(result["status"], "success")
	assert_true(result["current"])
	assert_eq(undo.scene_history.get_history_count(), steps, "no undo step")
	assert_eq(r["revision"], status["revision"], "no revision move")
	assert_not_null(level.baked_container, "the level is baked")


## The x of every vertex in the written scene, in the scene's space.
func _artifact_xs() -> Array[float]:
	var xs: Array[float] = []
	var packed := ResourceLoader.load(ARTIFACT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return xs
	var scene: Node = packed.instantiate()
	var stack: Array = [[scene, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		if node is Node3D:
			xform = xform * (node as Node3D).transform
		for child in node.get_children():
			stack.append([child, xform])
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for surface in mesh.get_surface_count():
				for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					xs.append((xform * vertex).x)
	scene.free()
	return xs


func test_a_bake_with_a_cordon_on_writes_the_whole_level():
	# The same as Export Game Scene: a cordon left on from working on one room
	# shipped that room alone (#1205).
	var level := make_level()
	await place_box([0, 1, 0])
	await place_box([40, 1, 0])
	level.cordon_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	level.cordon_enabled = true
	var cordons: Dictionary = level.capture_cordons()
	var r := await call_tool("hf_bake")
	assert_true(r["ok"], str(r))
	var far := false
	for x in _artifact_xs():
		far = far or absf(x - 40.0) <= 1.01
	assert_true(far, "the box outside the cordon is in the scene")
	assert_eq(level.capture_cordons(), cordons, "and the cordon is back on, as it was")


func test_status_says_whether_the_bake_is_still_current():
	make_level()
	await place_box()
	await call_tool("hf_bake")
	var fresh := await call_tool("hf_get_status")
	assert_true(fresh["result"]["bake_current"])
	assert_eq(fresh["result"]["last_bake"]["status"], "success")
	await place_box([6, 1, 0])
	var stale := await call_tool("hf_get_status")
	assert_false(stale["result"]["bake_current"], "a change since makes it stale")
	assert_eq(stale["result"]["last_bake"]["bake_id"], fresh["result"]["last_bake"]["bake_id"])


func test_a_failed_bake_says_so_and_writes_nothing():
	var level := ScriptedBakeLevel.new()
	level.fail = true
	make_scene(level)
	await place_box()
	assert_refused(await call_tool("hf_bake"), "bake_failed")
	assert_false(FileAccess.file_exists(ARTIFACT))
	var status := await call_tool("hf_get_status")
	assert_false(status["result"]["bake_current"])


func test_a_bake_already_running_is_bake_busy():
	var level := ScriptedBakeLevel.new()
	level.busy = true
	make_scene(level)
	assert_refused(await call_tool("hf_bake"), "bake_busy")


var _late: Dictionary = {}


func _bake_in_background() -> void:
	_late = await call_tool("hf_bake")


func test_a_scene_switch_during_the_bake_exports_nothing():
	var level := ScriptedBakeLevel.new()
	level.hold_frames = 5
	make_scene(level)
	await place_box()
	_late = {}
	_bake_in_background()
	make_scene(LevelRoot.new())
	for i in 60:
		if not _late.is_empty():
			break
		await get_tree().process_frame
	assert_refused(_late, "target_changed")
	assert_false(FileAccess.file_exists(ARTIFACT), "nothing exported from the old level")


## A real bake this time, not a scripted one. Switching tabs takes the scene out
## of the tree, and the bake waiting in it stopped on a script error; it now stops
## plainly, the bridge answers, and it takes the next command (#1290).
func test_a_real_bake_switched_away_from_answers_and_frees_the_bridge():
	make_level()
	await place_box()
	_late = {}
	_bake_in_background()
	await get_tree().process_frame
	var away: Node3D = host.scene
	remove_child(away)
	make_level()
	for i in 60:
		if not _late.is_empty():
			break
		await get_tree().process_frame
	assert_refused(_late, "target_changed")
	var next := await call_tool("hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]})
	assert_true(next.get("ok", false), "the bridge takes the next command: %s" % str(next))
	add_child(away)


func test_the_artifact_goes_beside_the_scene():
	assert_eq(
		HostStandIn.artifact_path_for("res://levels/arena.tscn"), "res://levels/arena_mcp.tscn"
	)
	assert_eq(HostStandIn.artifact_path_for("res://arena.tscn"), "res://arena_mcp.tscn")
	assert_eq(HostStandIn.artifact_path_for(""), "res://hammerforge_mcp_bake.tscn")
	assert_eq(HostStandIn.artifact_path_for("user://x.tscn"), "res://hammerforge_mcp_bake.tscn")


func test_closing_the_level_mid_bake_answers_rather_than_hangs():
	var level := ScriptedBakeLevel.new()
	level.hold_frames = 5
	var scene := make_scene(level)
	await place_box()
	_late = {}
	_bake_in_background()
	await get_tree().process_frame
	# A scene tab closed: the level goes, with the bake waiting inside it.
	host.scene = null
	scene.free()
	for i in 30:
		if not _late.is_empty():
			break
		await get_tree().process_frame
	assert_refused(_late, "target_changed")
	assert_false(FileAccess.file_exists(ARTIFACT))
	make_level()
	var next := await call_tool("hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]})
	assert_true(next.get("ok", false), "the bridge takes the next command: %s" % str(next))


func test_a_bake_that_applies_pending_cuts_moves_the_revision():
	var level := make_level()
	await place_box([0, 1, 0], [4, 4, 4])
	var cut := await call_tool(
		"hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0], "operation": "subtract"}
	)
	assert_true(cut["ok"], str(cut))
	assert_eq(level.pending_node.get_child_count(), 1, "the cut waits in PendingCuts")
	var r := await call_tool("hf_bake")
	assert_true(r["ok"], str(r))
	assert_eq(level.pending_node.get_child_count(), 0, "the bake applied it")
	assert_eq(int(r["revision"]), int(cut["revision"]) + 1, "a change no undo step records")
	assert_eq(int(r["result"]["source_revision"]), int(r["revision"]))
	assert_true(r["result"]["current"], "the bake is of the level after the cut")
	assert_refused(await call_tool("hf_undo"), "undo_conflict", "the undo chain ends at the bake")


func test_a_bake_without_pending_cuts_leaves_the_revision():
	make_level()
	var placed := await call_tool("hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]})
	var r := await call_tool("hf_bake")
	assert_eq(int(r["revision"]), int(placed["revision"]))
	assert_true((await call_tool("hf_undo"))["ok"], "undo still reaches the place")


func test_a_replayed_bake_says_whether_it_is_current_now():
	make_level()
	await place_box()
	var first := await call_tool("hf_bake", {}, {"operation_id": "bake-1"})
	assert_true(first["result"]["current"])
	var same := await call_tool("hf_bake", {}, {"operation_id": "bake-1"})
	assert_true(same["replayed"])
	assert_true(same["result"]["current"], "nothing changed yet")
	await place_box([6, 1, 0])
	var later := await call_tool("hf_bake", {}, {"operation_id": "bake-1"})
	assert_true(later["replayed"])
	assert_eq(later["result"]["bake_id"], first["result"]["bake_id"])
	assert_false(later["result"]["current"], "the level changed since that bake")


func test_a_command_while_a_bake_runs_is_busy():
	var level := ScriptedBakeLevel.new()
	level.hold_frames = 5
	make_scene(level)
	await place_box()
	_late = {}
	_bake_in_background()
	var during := await call_tool("hf_place_brush", {"size": [2, 2, 2], "position": [6, 1, 0]})
	assert_refused(during, "busy")
	assert_eq(during["error"]["details"]["busy"], "hf_bake")
	var status := await call_tool("hf_get_status")
	assert_eq(status["result"]["busy"], "hf_bake", "status still answers")
	for i in 30:
		if not _late.is_empty():
			break
		await get_tree().process_frame
	assert_true(_late.get("ok", false), str(_late))
	assert_eq(brushes(level).size(), 1, "the refused place made nothing")


func test_the_bake_answer_carries_warnings_not_progress_notes():
	var kept: Array = []
	HFMcpDispatcher._keep_warning("note", 0, kept)
	HFMcpDispatcher._keep_warning("careful", 1, kept)
	HFMcpDispatcher._keep_warning("broken", 2, kept)
	assert_eq(kept, ["careful", "broken"])
