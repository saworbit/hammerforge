@tool
class_name HFMcpDispatcher
extends RefCounted
## Runs MCP bridge requests against the level in the edited scene.
##
## The listener hands it one parsed request at a time and sends back what
## `handle()` returns. This is the adapter the design calls for: every domain
## operation is a LevelRoot facade call, and the only thing added here is the
## contract around it. See `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`.
##
## Target. A request names the target it expects. If the editor has moved to
## another scene or LevelRoot since, the request is refused rather than run
## against the wrong level.
##
## Revision. A counter that goes up on every `version_changed` from the scene's
## undo history and the global one. `UndoRedo.get_version()` cannot do this job:
## it falls on undo, and undoing one action and committing another gives back the
## version the first had.
##
## One step, all or nothing. A mutating handler checks its arguments before
## anything changes, the level is captured, the facade calls run, and then either
## `HFUndoHelper.commit_completed()` records it as one step named `MCP: ...`, or
## the capture is restored. The facade methods return real results this way,
## which `HFUndoHelper.commit()` would throw away.
##
## operation_id. A retry of a mutating request that already succeeded gets the
## first answer back instead of running again.


## A bake started from an object the dispatcher holds. Awaiting `root.bake()`
## directly would wait inside the LevelRoot, and a coroutine waiting inside a node
## that is freed (a scene tab closed mid-bake) never resumes; the dispatcher would
## never answer. This runs the bake and says when it is done, and the dispatcher
## watches it and the level frame by frame.
class BakeRun:
	extends RefCounted

	var done := false
	var baked := false

	func start(root: Node) -> void:
		baked = await root.bake(true, false, 0)
		done = true


# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFMcpProtocol = preload("hf_mcp_protocol.gd")
const HFMcpHost = preload("hf_mcp_host.gd")
const HFMcpTools = preload("hf_mcp_tools.gd")
const HFUndoHelper = preload("../undo_helper.gd")
const LevelRoot = preload("../level_root.gd")
const HFPlayerMetrics = preload("../hf_player_metrics.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Tools that only read. Their `operation_id` is ignored and they never touch
## the undo history.
## A screenshot only reads too, but it waits for frames to be drawn, so it runs in
## the queue like a change rather than straight away like the other reads.
const READ_ONLY := [
	"hf_get_status", "hf_get_brushes", "hf_get_materials", "hf_validate", "hf_viewport_screenshot"
]

## The reads other than status: method -> the HFMcpTools function that answers it,
## `func(root, params) -> {ok, result}`.
const READS := {
	"hf_get_brushes": "_read_brushes",
	"hf_get_materials": "_read_materials",
	"hf_validate": "_read_validate",
}

## Tools that change the level through the one wrapper. Each is one undo step.
## `check` is the HFMcpTools function that reads the arguments and returns
## `{ok, scope_ids, apply}`.
const MUTATING := {
	"hf_place_brush": {"verb": "place brush", "check": "_check_place_brush"},
	"hf_transform_brush": {"verb": "transform brush", "check": "_check_transform_brush"},
	"hf_resize_brush": {"verb": "resize brush", "check": "_check_resize_brush"},
	"hf_delete_brush": {"verb": "delete brush", "check": "_check_delete_brush"},
	"hf_extrude_face": {"verb": "extrude face", "check": "_check_extrude_face"},
	"hf_assign_material": {"verb": "assign material", "check": "_check_assign_material"},
	"hf_set_spawn": {"verb": "set spawn", "check": "_check_set_spawn"},
}

## Changes that do not go through the wrapper. Create starter is one step of the
## plugin's own; undo and redo move through steps rather than making one. They
## still run one at a time, and a retry of one is answered from the cache.
const CONTROL := ["hf_create_starter", "hf_undo", "hf_redo", "hf_bake", "hf_batch"]

## How many changes one hf_batch may carry.
const BATCH_LIMIT := 100

const OPERATION_CACHE_SIZE := 256

## `EditorUndoRedoManager.GLOBAL_HISTORY`, written out because the stand-in the
## tests use is not that class.
const GLOBAL_HISTORY := 0

var host: HFMcpHost

var _revision := 0
var _last_agent_revision: Variant = null
var _target_id := ""
var _target: Dictionary = {}
var _scene: Node = null
var _root: Node = null
var _watched: Array[UndoRedo] = []
var _busy_method := ""
var _busy_since_ms := 0
## The last bake the bridge made: {bake_id, source_revision, target_id, status,
## path, warnings, duration_ms}, or empty.
var _last_bake: Dictionary = {}
var _bake_count := 0
## hf_validate's counts for one revision, so status does not rescan the level on
## every call: {"revision": int, "target_id": String, "counts": Dictionary}.
var _validation_cache: Dictionary = {}

## operation_id -> {"fingerprint": String, "response": Dictionary}. Dictionaries
## keep insertion order, so the first key is the oldest.
var _operation_cache: Dictionary = {}

## The tools themselves: argument checks, facade calls, and levels as plain data.
## Public so a test can put a broken one in.
var tools: HFMcpTools


func _init(editor_host: HFMcpHost) -> void:
	host = editor_host
	tools = HFMcpTools.new()


## Stop listening to the undo histories. The plugin calls this when it lets the
## dispatcher go, and the tests between cases.
func shutdown() -> void:
	_unwatch_histories()
	_scene = null
	_root = null


func revision() -> int:
	return _revision


func current_target() -> Dictionary:
	_refresh_target()
	return _target.duplicate()


func is_known_method(method: String) -> bool:
	return method in READ_ONLY or MUTATING.has(method) or method in CONTROL


## Status is answered at once even while another command is running, so an
## agent can see the editor is busy rather than wait to find out.
func runs_while_busy(method: String) -> bool:
	return method == "hf_get_status"


## Answer one request. A coroutine: callers `await` it.
func handle(request: Dictionary) -> Dictionary:
	var id := str(request.get("id", ""))
	_refresh_target()
	var method = request.get("method")
	if not (method is String) or (method as String).is_empty():
		return _error(id, HFMcpProtocol.E_BAD_REQUEST, "A request needs a method")
	if not is_known_method(method):
		return _error(id, HFMcpProtocol.E_UNKNOWN_METHOD, "There is no tool called '%s'" % method)
	var params = request.get("params", {})
	if params == null:
		params = {}
	if not (params is Dictionary):
		return _error(id, HFMcpProtocol.E_BAD_REQUEST, "params must be an object")

	if method == "hf_get_status":
		return _respond(id, _status())

	var expect = request.get("expect_target", "")
	if expect == null:
		expect = ""
	if not (expect is String):
		return _error(id, HFMcpProtocol.E_BAD_REQUEST, "expect_target must be a string")

	# The cache first. A change that committed and then lost its answer is
	# replayed even if the editor has moved to another scene since, so the agent
	# learns it happened rather than doing it again somewhere else. The
	# fingerprint carries expect_target, so a replay only answers a request aimed
	# where the first one was.
	var changes: bool = MUTATING.has(method) or method in CONTROL
	var operation_id = request.get("operation_id", null) if changes else null
	var fingerprint := ""
	if operation_id != null:
		if not HFMcpProtocol.valid_operation_id(operation_id):
			return _error(
				id,
				HFMcpProtocol.E_INVALID_ARGUMENT,
				"operation_id must be 1 to 128 of A-Z a-z 0-9 . _ : -",
				{"param": "operation_id"}
			)
		fingerprint = HFMcpProtocol.fingerprint(method, params, expect)
		if _operation_cache.has(operation_id):
			var entry: Dictionary = _operation_cache[operation_id]
			if entry["fingerprint"] != fingerprint:
				return _error(
					id,
					HFMcpProtocol.E_OPERATION_ID_CONFLICT,
					"operation_id '%s' was already used with other arguments" % operation_id,
					{"param": "operation_id"}
				)
			var replay: Dictionary = (entry["response"] as Dictionary).duplicate(true)
			replay["id"] = id
			replay["replayed"] = true
			if method == "hf_bake" and replay.get("result") is Dictionary:
				# Current then is not current now: say so, rather than hand on an
				# old bake as the level's.
				var was: Dictionary = replay["result"]
				was["current"] = (
					was.get("bake_id") == _last_bake.get("bake_id") and _bake_is_current()
				)
			return replay

	if expect != "" and expect != _target_id:
		return _error(
			id,
			HFMcpProtocol.E_TARGET_CHANGED,
			"The editor is on another scene or level now. Call hf_get_status to attach to it.",
			{"current": _target.duplicate()}
		)

	if READS.has(method):
		return _run_read(id, method, params)

	# The listener runs one command at a time, but a stop and a start while a bake
	# awaits gives it a fresh queue while the dispatcher is still in the bake.
	if _busy_method != "":
		return _error(
			id,
			HFMcpProtocol.E_BUSY,
			"The editor is still running %s. hf_get_status says for how long." % _busy_method,
			{"busy": _busy_method, "busy_seconds": _busy_seconds()}
		)

	_busy_method = method
	_busy_since_ms = Time.get_ticks_msec()
	var response = await _run_tool(id, method, params)
	_busy_method = ""
	if not _is_answer(response, "type"):
		return _error(
			id, HFMcpProtocol.E_INTERNAL, "%s stopped with a script error; see Output" % method
		)
	if operation_id != null and bool(response.get("ok", false)):
		_remember(operation_id, fingerprint, response)
	return response


# ---------------------------------------------------------------------------
# Target and revision
# ---------------------------------------------------------------------------


func _refresh_target() -> void:
	var scene := host.edited_scene_root()
	if scene != null and not is_instance_valid(scene):
		scene = null
	var root: Node = host.level_root_in(scene) if scene != null else null
	var target_id := _target_id_for(scene, root)
	if target_id != _target_id:
		_target_id = target_id
		_revision += 1
		# The agent's undo chain belongs to the level it was built in. On another
		# scene or level, hf_undo would be working through a history nobody was
		# watching while the agent worked elsewhere.
		_last_agent_revision = null
		_scene = scene
		_root = root
		_watch_histories()
	_target = _target_info(scene, root)


## What hf_get_status says about a scene and level.
func _target_info(scene: Node, root: Node) -> Dictionary:
	var root_path: Variant = null
	if root:
		root_path = str(scene.get_path_to(root))
	return {
		"target_id": _target_id_for(scene, root),
		"scene_path": str(scene.scene_file_path) if scene else "",
		"scene_name": str(scene.name) if scene else "",
		"level_root_path": root_path,
	}


func _watch_histories() -> void:
	_unwatch_histories()
	var manager := host.undo_manager()
	if manager == null:
		return
	var histories: Array = []
	var anchor: Object = _root if _root else _scene
	if anchor != null:
		histories.append(manager.get_history_undo_redo(manager.get_object_history_id(anchor)))
	histories.append(manager.get_history_undo_redo(GLOBAL_HISTORY))
	for history in histories:
		if history == null or _watched.has(history):
			continue
		history.version_changed.connect(_on_history_changed)
		_watched.append(history)


func _unwatch_histories() -> void:
	for history in _watched:
		if is_instance_valid(history) and history.version_changed.is_connected(_on_history_changed):
			history.version_changed.disconnect(_on_history_changed)
	_watched.clear()


func _on_history_changed() -> void:
	_revision += 1


func _remember(operation_id: String, fingerprint: String, response: Dictionary) -> void:
	_operation_cache.erase(operation_id)
	_operation_cache[operation_id] = {"fingerprint": fingerprint, "response": response}
	while _operation_cache.size() > OPERATION_CACHE_SIZE:
		_operation_cache.erase(_operation_cache.keys()[0])


# ---------------------------------------------------------------------------
# Running a tool
# ---------------------------------------------------------------------------


func _run_tool(id: String, method: String, params: Dictionary) -> Dictionary:
	if _scene == null:
		return _error(id, HFMcpProtocol.E_NO_EDITED_SCENE, "No scene is open in the editor")
	match method:
		"hf_create_starter":
			return await _create_starter(id)
		"hf_undo":
			return await _step(id, true)
		"hf_redo":
			return await _step(id, false)
		"hf_bake":
			return await _bake(id)
		"hf_batch":
			return await _batch(id, params)
		"hf_viewport_screenshot":
			return await _screenshot(id, params)
	if _root == null or not is_instance_valid(_root):
		return _no_level(id)
	var spec: Dictionary = MUTATING[method]
	var checked = tools.call(spec["check"], _root, params)
	if not _is_answer(checked, "ok"):
		return _error(
			id, HFMcpProtocol.E_INTERNAL, "%s stopped with a script error; see Output" % method
		)
	if not checked.get("ok", false):
		return _error_from(id, checked)
	return await _run_mutation(id, spec["verb"], checked["scope_ids"], checked["apply"])


func _no_level(id: String) -> Dictionary:
	return _error(
		id,
		HFMcpProtocol.E_NO_LEVEL,
		"The open scene has no LevelRoot. hf_create_starter makes one."
	)


func _run_read(id: String, method: String, params: Dictionary) -> Dictionary:
	if _scene == null:
		return _error(id, HFMcpProtocol.E_NO_EDITED_SCENE, "No scene is open in the editor")
	if _root == null or not is_instance_valid(_root):
		return _no_level(id)
	var answer = tools.call(READS[method], _root, params)
	if not _is_answer(answer, "ok"):
		return _error(
			id, HFMcpProtocol.E_INTERNAL, "%s stopped with a script error; see Output" % method
		)
	if not answer["ok"]:
		return _error_from(id, answer)
	if method == "hf_validate":
		_validation_cache = {
			"revision": _revision, "target_id": _target_id, "counts": answer["result"]["counts"]
		}
	return _respond(id, answer["result"])


## Capture, apply, then commit one undo step or put the level back.
##
## `apply` changes the level through the facade and returns `{"ok": true,
## "result": {...}}` or `{"ok": false, "error": {...}}`. It records no undo of its
## own: this is the one place that does.
func _run_mutation(id: String, verb: String, scope_ids: Array, apply: Callable) -> Dictionary:
	var root := _root
	# What this command ran against. A status request answered while it awaits
	# can move the dispatcher onto another scene; the answer must still name the
	# level that changed, or the client would follow the move without being told.
	var target_id := _target_id
	var before := HFUndoHelper.capture_scope_or_state(root, scope_ids)
	var outcome = apply.call()
	if not _is_answer(outcome, "ok"):
		_restore(root, before)
		return _error(
			id,
			HFMcpProtocol.E_INTERNAL,
			"The %s handler returned no result" % verb,
			{"rolled_back": true}
		)
	if not outcome.get("ok", false):
		_restore(root, before)
		var failure: Dictionary = outcome.get("error", {})
		var details: Dictionary = (failure.get("details", {}) as Dictionary).duplicate()
		details["rolled_back"] = true
		return _error(
			id,
			str(failure.get("code", HFMcpProtocol.E_OPERATION_FAILED)),
			str(failure.get("message", "The %s failed" % verb)),
			details
		)
	HFUndoHelper.commit_completed(
		host.undo_manager(),
		root,
		HFMcpProtocol.ACTION_PREFIX + verb,
		before["state"],
		Callable(host, "record_history"),
		before["scope_ids"]
	)
	# A commit sets off deferred work (the plugin queues a brush reconcile on
	# version_changed). Let it land before the revision is read, so the number
	# the agent gets back is the one it will see next.
	await host.next_frame()
	_settle(target_id)
	return HFMcpProtocol.response_ok(id, outcome["result"], _revision, target_id)


## After a step's frame: follow the editor, and keep the agent's undo chain only
## if the editor is still on the level the step was meant for. A status request
## answered during the frame can have moved the dispatcher to another scene.
func _settle(expected_target: String) -> void:
	_refresh_target()
	_last_agent_revision = null
	if _target_id == expected_target:
		_last_agent_revision = _revision


func _target_id_for(scene: Node, root: Node) -> String:
	return (
		"%d:%d:%d"
		% [
			host.editor_pid(),
			scene.get_instance_id() if scene else 0,
			root.get_instance_id() if root else 0,
		]
	)


## Whether a handler gave back what it should. A function typed `-> Dictionary`
## that hits a script error returns an empty one, so an empty result means the
## handler broke, not that it refused; without this the agent would be told its
## arguments were wrong, with no message.
static func _is_answer(value, key: String) -> bool:
	return value is Dictionary and (value as Dictionary).has(key)


func _restore(root: Node, before: Dictionary) -> void:
	if not is_instance_valid(root):
		return
	if not (before["scope_ids"] as Array).is_empty():
		root.restore_brush_scope(before["state"])
	else:
		root.restore_state(before["state"])


func _respond(id: String, result: Dictionary) -> Dictionary:
	return HFMcpProtocol.response_ok(id, result, _revision, _target_id)


func _error(id: String, code: String, message: String, details := {}) -> Dictionary:
	return HFMcpProtocol.response_error(id, code, message, details, _revision, _target_id)


## A refusal from a check or reader, `{"ok": false, "error": {...}}`, as a response.
func _error_from(id: String, refusal: Dictionary) -> Dictionary:
	var failure: Dictionary = refusal.get("error", {})
	return _error(
		id,
		str(failure.get("code", HFMcpProtocol.E_INVALID_ARGUMENT)),
		str(failure.get("message", "")),
		failure.get("details", {})
	)


# ---------------------------------------------------------------------------
# hf_get_status
# ---------------------------------------------------------------------------


func _status() -> Dictionary:
	var counts := {"brushes": 0, "pending_cuts": 0, "committed_cuts": 0, "entities": 0}
	var grid: Variant = null
	if _root != null and is_instance_valid(_root):
		for node in _root._iter_managed_brush_nodes():
			var parent: Node = node.get_parent()
			if parent == _root.pending_node:
				counts["pending_cuts"] += 1
			elif parent == _root.committed_node:
				counts["committed_cuts"] += 1
			else:
				counts["brushes"] += 1
		counts["entities"] = _root.get_entity_count()
		grid = _root.grid_snap
	return {
		"bridge_version": HFMcpProtocol.BRIDGE_VERSION,
		"schema_version": HFMcpProtocol.SCHEMA_VERSION,
		"hammerforge_version": host.hammerforge_version(),
		"editor_pid": host.editor_pid(),
		"project_path": host.project_path(),
		"target": _target.duplicate(),
		"revision": _revision,
		"last_agent_revision": _last_agent_revision,
		"counts": counts,
		"grid_snap": grid,
		"camera": host.camera_pose(),
		"busy": _busy_method,
		# How long the running command has run, so a long bake can be told from
		# one that will never answer. Unticking and ticking the bridge clears it.
		"busy_seconds": _busy_seconds(),
		"validation": _validation_counts(),
		"validation_revision": _validation_revision(),
		"last_bake": _last_bake_or_null(),
		"bake_current": _bake_is_current(),
		"player": _player(),
	}


## The playtest player an agent builds for: its capsule, where its eyes are above
## its feet, the step it climbs, the jump and the steepest floor it walks. The
## same numbers Validate measures stairs, doorways and ramps against (#1046). An
## agent guessed these and built 0.5 m stair risers and a parapet over the
## player's eye (#1045).
static func _player() -> Dictionary:
	return HFPlayerMetrics.standing()


# ---------------------------------------------------------------------------
# hf_create_starter, hf_undo, hf_redo
# ---------------------------------------------------------------------------


func _create_starter(id: String) -> Dictionary:
	if _root != null and is_instance_valid(_root):
		return _error(
			id,
			HFMcpProtocol.E_LEVEL_EXISTS,
			"This scene already has a LevelRoot. Build in it, or open a scene without one.",
			{"level_root_path": _target.get("level_root_path")}
		)
	var action := HFMcpProtocol.ACTION_PREFIX + "create starter"
	var made = host.create_starter(action)
	if not (made is LevelRoot):
		return _error(id, HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not make the level")
	host.record_history(action)
	var made_target := _target_id_for(_scene, made)
	var made_info := _target_info(_scene, made)
	await host.next_frame()
	# The level is the new target. The answer carries it, and a client that takes
	# its target from a good answer follows on to it.
	_settle(made_target)
	var spawn_position: Variant = null
	var spawn_feet: Variant = null
	var spawn: Node3D = made.spawn_system.get_active_spawn() if made.spawn_system else null
	if spawn:
		spawn_position = HFMcpProtocol.vec3_to_array(spawn.global_position)
		spawn_feet = HFMcpProtocol.vec3_to_array(made.spawn_system._floor_of(spawn))
	var floor_top: Variant = null
	var floor_box := made.get_node_or_null("TempFloor") as CSGBox3D
	if floor_box:
		floor_top = floor_box.global_position.y + floor_box.size.y * 0.5
	var result := {
		"target": made_info,
		"spawn_position": spawn_position,
		"spawn_feet": spawn_feet,
		"floor_top": floor_top,
	}
	return HFMcpProtocol.response_ok(id, result, _revision, made_target)


# ---------------------------------------------------------------------------
# hf_viewport_screenshot
# ---------------------------------------------------------------------------


## A picture of the level. Without `focus`, what the editor's 3D viewport shows,
## scaled to fit. With `focus` (`{brush_ids}` or `{bounds}`), a temporary viewport
## on the same world, its own camera looking the way the editor's does and backed
## off until the whole of it is in view. The editor's camera is never moved, so
## there is nothing to put back.
func _screenshot(id: String, params: Dictionary) -> Dictionary:
	var width_read := HFMcpProtocol.read_int(params, "width", false, 1280, 64, 1920)
	if not width_read["ok"]:
		return _error_from(id, width_read)
	var height_read := HFMcpProtocol.read_int(params, "height", false, 720, 64, 1080)
	if not height_read["ok"]:
		return _error_from(id, height_read)
	var width: int = width_read["value"]
	var height: int = height_read["value"]
	var framing := {}
	if params.get("focus") != null:
		if _root == null or not is_instance_valid(_root):
			return _no_level(id)
		framing = tools.focus_bounds(_root, params["focus"])
		if not framing["ok"]:
			return _error_from(id, framing)
	var viewport := host.viewport_3d()
	if viewport == null:
		return _no_picture(id)
	var image: Image = null
	var camera: Variant = null
	if framing.is_empty():
		if not await host.frame_drawn():
			return _no_picture(id)
		var texture := viewport.get_texture()
		image = texture.get_image() if texture else null
		camera = host.camera_pose()
		if image != null and not image.is_empty():
			var fitted := fit_size(image.get_size(), width, height)
			if fitted != image.get_size():
				image.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	else:
		var shot := await _framed_shot(viewport, framing["bounds"], width, height)
		image = shot["image"]
		camera = shot["camera"]
	if image == null or image.is_empty():
		return _no_picture(id)
	var png := image.save_png_to_buffer()
	var result := {
		"image": {"mime_type": "image/png", "data": Marshalls.raw_to_base64(png)},
		"width": image.get_width(),
		"height": image.get_height(),
		"camera": camera,
	}
	return _respond(id, result)


## The size a viewport picture of `source` pixels is sent at: inside width by
## height, in its own shape, and never bigger than it is. A bigger copy of a small
## viewport is a bigger file with no more in it.
static func fit_size(source: Vector2i, width: int, height: int) -> Vector2i:
	var scale := minf(1.0, minf(float(width) / source.x, float(height) / source.y))
	return Vector2i(maxi(1, int(source.x * scale)), maxi(1, int(source.y * scale)))


func _no_picture(id: String) -> Dictionary:
	return _error(
		id,
		HFMcpProtocol.E_SCREENSHOT_UNAVAILABLE,
		"There is no picture to take: the editor is running without a display, or has no 3D viewport."
	)


func _framed_shot(viewport: Viewport, bounds: AABB, width: int, height: int) -> Dictionary:
	var editor_camera := viewport.get_camera_3d()
	var direction := Vector3(-1, -1, -1).normalized()
	var fov := 70.0
	if editor_camera:
		direction = -editor_camera.global_basis.z
		fov = editor_camera.fov
	var place := HFMcpTools.frame_bounds(bounds, direction, fov, float(width) / float(height))
	var sub := SubViewport.new()
	sub.size = Vector2i(width, height)
	sub.own_world_3d = false
	sub.world_3d = viewport.find_world_3d()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	camera.fov = fov
	# Far enough to see the far side of a large box from where the framing puts it.
	var reach := (Vector3(place["target"]) - Vector3(place["position"])).length()
	camera.far = maxf(camera.far, reach + bounds.size.length() * 2.0)
	sub.add_child(camera)
	var parent := host.screenshot_parent()
	if parent == null:
		sub.free()
		return {"image": null, "camera": null}
	parent.add_child(sub)
	camera.global_position = place["position"]
	var up := Vector3.UP if absf(direction.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	camera.look_at(place["target"], up)
	camera.current = true
	# Two frames: one for the viewport to exist, one to draw it.
	var drawn: bool = await host.frame_drawn()
	drawn = drawn and await host.frame_drawn()
	if not drawn:
		parent.remove_child(sub)
		sub.queue_free()
		return {"image": null, "camera": null}
	var texture := sub.get_texture()
	var image: Image = texture.get_image() if texture else null
	var euler := camera.global_basis.get_euler(EULER_ORDER_XYZ)
	var pose := {
		"position": HFMcpProtocol.vec3_to_array(camera.global_position),
		"rotation_degrees":
		HFMcpProtocol.vec3_to_array(
			Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))
		),
		"fov": fov,
	}
	parent.remove_child(sub)
	sub.queue_free()
	return {"image": image, "camera": pose}


# ---------------------------------------------------------------------------
# hf_batch
# ---------------------------------------------------------------------------


## Several changes as one undo step, all or nothing: one capture of the whole
## level, each op checked against what the ones before it left and then applied,
## and one commit at the end. Any refusal or failure restores the capture.
func _batch(id: String, params: Dictionary) -> Dictionary:
	if _root == null or not is_instance_valid(_root):
		return _no_level(id)
	var ops = params.get("ops")
	if not (ops is Array) or (ops as Array).is_empty() or (ops as Array).size() > BATCH_LIMIT:
		return _error(
			id,
			HFMcpProtocol.E_INVALID_ARGUMENT,
			"ops is a list of 1 to %d changes" % BATCH_LIMIT,
			{"param": "ops"}
		)
	for i in ops.size():
		var op = ops[i]
		var tool_name = op.get("tool") if op is Dictionary else null
		if not (tool_name is String) or not MUTATING.has(tool_name):
			return _error(
				id,
				HFMcpProtocol.E_INVALID_ARGUMENT,
				"op %d: tool must be one of %s" % [i, ", ".join(MUTATING.keys())],
				{"param": "ops", "index": i}
			)
		if op.get("params") != null and not (op["params"] is Dictionary):
			return _error(
				id,
				HFMcpProtocol.E_INVALID_ARGUMENT,
				"op %d: params must be an object" % i,
				{"param": "ops", "index": i}
			)
	var root := _root
	var target_id := _target_id
	var before := HFUndoHelper.capture_scope_or_state(root, [])
	var results: Array = []
	# Set as soon as an apply runs, not when one succeeds: an apply can change the
	# level and then fail, and that op's own change needs taking back too.
	var touched := false
	for i in ops.size():
		var op: Dictionary = ops[i]
		var refusal := {}
		var resolved := _resolve_refs(
			op.get("params", {}) if op.get("params") != null else {}, results, i
		)
		if not resolved["ok"]:
			refusal = resolved["error"]
		else:
			var checked = tools.call(MUTATING[op["tool"]]["check"], root, resolved["value"])
			if not _is_answer(checked, "ok"):
				refusal = HFMcpProtocol.error_body(HFMcpProtocol.E_INTERNAL, "op %d broke" % i)
			elif not checked["ok"]:
				refusal = checked["error"]
			else:
				touched = true
				var outcome = checked["apply"].call()
				if not _is_answer(outcome, "ok"):
					refusal = HFMcpProtocol.error_body(HFMcpProtocol.E_INTERNAL, "op %d broke" % i)
				elif not outcome["ok"]:
					refusal = outcome["error"]
				else:
					results.append({"tool": op["tool"], "result": outcome["result"]})
		if not refusal.is_empty():
			if touched:
				_restore(root, before)
			return _error(
				id,
				HFMcpProtocol.E_BATCH_FAILED,
				(
					"op %d (%s) failed, so none of the batch was kept: %s"
					% [i, op["tool"], refusal.get("message", "")]
				),
				{"index": i, "tool": op["tool"], "error": refusal, "rolled_back": touched}
			)
	HFUndoHelper.commit_completed(
		host.undo_manager(),
		root,
		HFMcpProtocol.ACTION_PREFIX + "batch (%d ops)" % ops.size(),
		before["state"],
		Callable(host, "record_history"),
		[]
	)
	await host.next_frame()
	_settle(target_id)
	return HFMcpProtocol.response_ok(id, {"results": results}, _revision, target_id)


## A copy of `value` with every "$N.brush_id" swapped for the brush id op N's
## answer carries. N has to be an earlier op, and its answer has to be a brush.
func _resolve_refs(value, results: Array, index: int) -> Dictionary:
	if value is String and (value as String).begins_with("$"):
		var text := value as String
		var number := text.trim_prefix("$").trim_suffix(".brush_id")
		if not text.ends_with(".brush_id") or not number.is_valid_int():
			return {"ok": true, "value": value}
		var n := number.to_int()
		if n < 0 or n >= index:
			return _bad_ref("op %d refers to %s, which is not an earlier op" % [index, text])
		var made = results[n].get("result", {}).get("brush", {}).get("brush_id")
		if not (made is String) or (made as String).is_empty():
			return _bad_ref("op %d refers to %s, but op %d made no brush" % [index, text, n])
		return {"ok": true, "value": made}
	if value is Dictionary:
		var out := {}
		for key in value:
			var inner := _resolve_refs(value[key], results, index)
			if not inner["ok"]:
				return inner
			out[key] = inner["value"]
		return {"ok": true, "value": out}
	if value is Array:
		var list: Array = []
		for item in value:
			var inner := _resolve_refs(item, results, index)
			if not inner["ok"]:
				return inner
			list.append(inner["value"])
		return {"ok": true, "value": list}
	return {"ok": true, "value": value}


static func _bad_ref(message: String) -> Dictionary:
	return {
		"ok": false,
		"error":
		HFMcpProtocol.error_body(HFMcpProtocol.E_INVALID_ARGUMENT, message, {"param": "ops"}),
	}


# ---------------------------------------------------------------------------
# hf_bake
# ---------------------------------------------------------------------------


## Bake the level and write the scene a runtime test loads, beside the level's
## own scene. Not an undo step: it records nothing, and the revision stays where
## it was unless the bake applied pending cuts. The answer's `current` and
## status's `bake_current` say whether the level still matches it.
func _bake(id: String) -> Dictionary:
	if _root == null or not is_instance_valid(_root):
		return _no_level(id)
	var root := _root
	if root.is_bake_in_flight():
		return _error(
			id,
			HFMcpProtocol.E_BAKE_BUSY,
			"A bake is already running, from the dock or a test run. Try again when it ends."
		)
	_bake_count += 1
	var bake_id := "%d-%d" % [int(Time.get_unix_time_from_system() * 1000.0), _bake_count]
	var source_revision := _revision
	var target_id := _target_id
	var messages: Array = []
	var listen := _keep_warning.bind(messages)
	root.user_message.connect(listen)
	var cuts_before := _pending_cut_count(root)
	var started := Time.get_ticks_msec()
	var run := BakeRun.new()
	run.start(root)
	while not run.done and is_instance_valid(root):
		await host.next_frame()
	if is_instance_valid(root) and root.user_message.is_connected(listen):
		root.user_message.disconnect(listen)
	# A bake applies the level's pending cuts, moving them in among the brushes.
	# No undo step records that, so it moves the revision and the agent's undo
	# chain ends there. The bake is of the level after the cuts went in, so its
	# source revision moves with it.
	if is_instance_valid(root) and _pending_cut_count(root) < cuts_before:
		_revision += 1
		source_revision += 1
	_refresh_target()
	if not is_instance_valid(root) or not run.done or _target_id != target_id:
		return _error(
			id,
			HFMcpProtocol.E_TARGET_CHANGED,
			"The editor moved to another scene or level during the bake, so nothing was exported.",
			{"current": _target.duplicate()}
		)
	var duration := Time.get_ticks_msec() - started
	var baked := run.baked
	if not baked:
		var status_name := _bake_status_name(root.get_last_bake_status())
		_last_bake = {
			"bake_id": bake_id,
			"source_revision": source_revision,
			"target_id": target_id,
			"status": status_name,
			"path": null,
			"warnings": messages,
			"duration_ms": duration,
		}
		return _error(
			id,
			HFMcpProtocol.E_BAKE_FAILED,
			"The bake did not finish: %s" % status_name,
			{"status": status_name, "warnings": messages}
		)
	var path := host.artifact_path(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var meta := {
		"bake_id": bake_id,
		"source_revision": source_revision,
		"target_id": target_id,
		"baked_at": Time.get_datetime_string_from_system(true),
	}
	if not root.export_game_scene(path, meta):
		return _error(
			id,
			HFMcpProtocol.E_EXPORT_FAILED,
			"The level baked, but %s could not be written" % path,
			{"path": path}
		)
	host.notify_file_written(path)
	_last_bake = {
		"bake_id": bake_id,
		"source_revision": source_revision,
		"target_id": target_id,
		"status": "success",
		"path": path,
		"warnings": messages,
		"duration_ms": duration,
	}
	var result := {
		"bake_id": bake_id,
		"source_revision": source_revision,
		"revision": _revision,
		"current": _bake_is_current(),
		"status": "success",
		"artifact": {"path": path, "absolute_path": ProjectSettings.globalize_path(path)},
		"warnings": messages,
		"duration_ms": duration,
	}
	return HFMcpProtocol.response_ok(id, result, _revision, target_id)


## A bake's warnings and errors for its answer; its progress notes stay out.
static func _keep_warning(text: String, level: int, into: Array) -> void:
	if level >= 1:
		into.append(text)


static func _pending_cut_count(root: Node) -> int:
	var pending: Node = root.get("pending_node")
	return pending.get_child_count() if pending != null and is_instance_valid(pending) else 0


func _busy_seconds() -> Variant:
	if _busy_method == "":
		return null
	return float(Time.get_ticks_msec() - _busy_since_ms) / 1000.0


func _last_bake_or_null() -> Variant:
	if _last_bake.is_empty():
		return null
	return _last_bake.duplicate()


## The counts by severity of the last hf_validate on this level, and the revision
## it ran at. Status worked them out again after every change, which ran the whole
## Validate pass on the main thread, 650 ms on a 121-brush level (#1048). It says
## how old they are instead, and an agent that wants them current calls
## hf_validate. Null before the first one, and on another level.
func _validation_counts() -> Variant:
	if _validation_cache.get("target_id", null) != _target_id:
		return null
	return _validation_cache["counts"]


func _validation_revision() -> Variant:
	if _validation_cache.get("target_id", null) != _target_id:
		return null
	return _validation_cache["revision"]


## The last bake succeeded, and nothing has changed the level or moved the editor
## since it started. An edit that was undone again still moves the revision, so
## it counts as a change: the answer errs towards baking again.
func _bake_is_current() -> bool:
	return (
		not _last_bake.is_empty()
		and _last_bake.get("status") == "success"
		and int(_last_bake.get("source_revision", -1)) == _revision
		and _last_bake.get("target_id") == _target_id
	)


static func _bake_status_name(status: int) -> String:
	for key in LevelRoot.BakeStatus.keys():
		if LevelRoot.BakeStatus[key] == status:
			return str(key).to_lower()
	return "unknown"


func _scene_history() -> UndoRedo:
	var manager := host.undo_manager()
	if manager == null:
		return null
	var anchor: Object = _root if _root else _scene
	return manager.get_history_undo_redo(manager.get_object_history_id(anchor))


## hf_undo (`back`) or hf_redo. Only the agent's own step, and only while
## nothing else has touched the level since the agent's last answer: a human edit
## moves the revision even if it was undone again, and then this refuses rather
## than take back somebody's work.
func _step(id: String, back: bool) -> Dictionary:
	var history := _scene_history()
	var word := "undo" if back else "redo"
	var empty := (
		history == null
		or (back and not history.has_undo())
		or (not back and not history.has_redo())
	)
	if empty:
		return _error(
			id,
			HFMcpProtocol.E_NOTHING_TO_UNDO if back else HFMcpProtocol.E_NOTHING_TO_REDO,
			"There is nothing to %s in this scene" % word
		)
	var step_name := (
		history.get_current_action_name()
		if back
		else history.get_action_name(history.get_current_action() + 1)
	)
	var conflict := HFMcpProtocol.E_UNDO_CONFLICT if back else HFMcpProtocol.E_REDO_CONFLICT
	var details := {
		"top_action": step_name,
		"revision": _revision,
		"last_agent_revision": _last_agent_revision,
	}
	if not step_name.begins_with(HFMcpProtocol.ACTION_PREFIX):
		return _error(
			id,
			conflict,
			"The step to %s is '%s', which the agent did not make." % [word, step_name],
			details
		)
	if _last_agent_revision == null or _revision != int(_last_agent_revision):
		return _error(
			id,
			conflict,
			(
				(
					"The level changed after the agent's last step (revision %d, the agent's was %s), "
					+ "so %s could take back someone else's work."
				)
				% [_revision, str(_last_agent_revision), word]
			),
			details
		)
	var scene := _scene
	if back:
		history.undo()
	else:
		history.redo()
	# A history stepped directly, as the dock's own Undo button does, tells the
	# editor's undo manager nothing, so the plugin's own reaction to a step is
	# asked for by name.
	host.after_history_step()
	# Undo can take a whole level away (a starter) and redo bring it back, so the
	# level this lands on is worked out afresh, in the scene it ran in.
	var landed := _target_id_for(scene, host.level_root_in(scene))
	await host.next_frame()
	_settle(landed)
	return HFMcpProtocol.response_ok(
		id, {"undone" if back else "redone": step_name}, _revision, landed
	)
