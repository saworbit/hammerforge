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

signal activity(method: String, running: bool)

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFMcpProtocol = preload("hf_mcp_protocol.gd")
const HFMcpHost = preload("hf_mcp_host.gd")
const HFUndoHelper = preload("../undo_helper.gd")
const DraftBrush = preload("../brush_instance.gd")
const LevelRoot = preload("../level_root.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Tools that only read. Their `operation_id` is ignored and they never touch
## the undo history.
const READ_ONLY := ["hf_get_status"]

## Tools that change the level. Each is one undo step.
const MUTATING := {
	"hf_place_brush": {"verb": "place brush", "check": "_check_place_brush"},
}

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

## operation_id -> {"fingerprint": String, "response": Dictionary}. Dictionaries
## keep insertion order, so the first key is the oldest.
var _operation_cache: Dictionary = {}

## Lower-case shape name -> BrushShape value, and back.
var _shape_by_name: Dictionary = {}
var _name_by_shape: Dictionary = {}


func _init(editor_host: HFMcpHost) -> void:
	host = editor_host
	for key in LevelRoot.BrushShape.keys():
		var value: int = LevelRoot.BrushShape[key]
		_shape_by_name[str(key).to_lower()] = value
		_name_by_shape[value] = str(key).to_lower()


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
	return method in READ_ONLY or MUTATING.has(method)


## Status is answered at once even while another command is running, so an
## agent can see the editor is busy rather than wait to find out.
func runs_while_busy(method: String) -> bool:
	return method == "hf_get_status"


## The method running now, or "".
func busy_method() -> String:
	return _busy_method


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
	if expect != "" and expect != _target_id:
		return _error(
			id,
			HFMcpProtocol.E_TARGET_CHANGED,
			"The editor is on another scene or level now. Call hf_get_status to attach to it.",
			{"current": _target.duplicate()}
		)

	var operation_id = request.get("operation_id", null)
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
			return replay

	_busy_method = method
	activity.emit(method, true)
	var response: Dictionary = await _run_tool(id, method, params)
	_busy_method = ""
	activity.emit(method, false)
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
	var target_id := (
		"%d:%d:%d"
		% [
			host.editor_pid(),
			scene.get_instance_id() if scene else 0,
			root.get_instance_id() if root else 0,
		]
	)
	if target_id != _target_id:
		_target_id = target_id
		_revision += 1
		_scene = scene
		_root = root
		_watch_histories()
	var root_path: Variant = null
	if root:
		root_path = str(scene.get_path_to(root))
	_target = {
		"target_id": _target_id,
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
	if _root == null or not is_instance_valid(_root):
		return _error(
			id,
			HFMcpProtocol.E_NO_LEVEL,
			"The open scene has no LevelRoot. hf_create_starter makes one."
		)
	var spec: Dictionary = MUTATING[method]
	var checked: Dictionary = call(spec["check"], _root, params)
	if not checked.get("ok", false):
		return _error_from(id, checked)
	return await _run_mutation(id, spec["verb"], checked["scope_ids"], checked["apply"])


## Capture, apply, then commit one undo step or put the level back.
##
## `apply` changes the level through the facade and returns `{"ok": true,
## "result": {...}}` or `{"ok": false, "error": {...}}`. It records no undo of its
## own: this is the one place that does.
func _run_mutation(id: String, verb: String, scope_ids: Array, apply: Callable) -> Dictionary:
	var root := _root
	var before := HFUndoHelper.capture_scope_or_state(root, scope_ids)
	var outcome = apply.call()
	if not (outcome is Dictionary):
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
	_last_agent_revision = _revision
	return _respond(id, outcome["result"])


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


static func _fail(code: String, message: String, details := {}) -> Dictionary:
	return {"ok": false, "error": HFMcpProtocol.error_body(code, message, details)}


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
	}


# ---------------------------------------------------------------------------
# hf_place_brush
# ---------------------------------------------------------------------------


func _check_place_brush(root: Node, params: Dictionary) -> Dictionary:
	var shape_read := HFMcpProtocol.read_string(params, "shape", false, "box")
	if not shape_read["ok"]:
		return shape_read
	var shape_name := str(shape_read["value"]).to_lower()
	if not _shape_by_name.has(shape_name) or shape_name == "custom":
		var names: Array = _shape_by_name.keys()
		names.erase("custom")
		return HFMcpProtocol.invalid("shape", "shape must be one of: %s" % ", ".join(names))
	var size_read := HFMcpProtocol.read_positive_vec3(params, "size", true)
	if not size_read["ok"]:
		return size_read
	var position_read := HFMcpProtocol.read_vec3(params, "position", true)
	if not position_read["ok"]:
		return position_read
	var operation_read := HFMcpProtocol.read_string(params, "operation", false, "union")
	if not operation_read["ok"]:
		return operation_read
	var operation_name := str(operation_read["value"])
	if operation_name != "union" and operation_name != "subtract":
		return HFMcpProtocol.invalid("operation", "operation must be union or subtract")
	var snap_read := HFMcpProtocol.read_bool(params, "snap", true)
	if not snap_read["ok"]:
		return snap_read

	var size: Vector3 = size_read["value"]
	var center: Vector3 = position_read["value"]
	var grid: float = root.grid_snap
	var snapping: bool = snap_read["value"] and grid > 0.0
	if snapping:
		size = Vector3(
			maxf(grid, snappedf(size.x, grid)),
			maxf(grid, snappedf(size.y, grid)),
			maxf(grid, snappedf(size.z, grid))
		)
		# The lowest corner goes on the grid, as a drawn brush's does, so its
		# faces sit on grid lines whatever its size.
		var low := center - size * 0.5
		low = Vector3(snappedf(low.x, grid), snappedf(low.y, grid), snappedf(low.z, grid))
		center = low + size * 0.5
	var operation := (
		CSGShape3D.OPERATION_SUBTRACTION
		if operation_name == "subtract"
		else CSGShape3D.OPERATION_UNION
	)
	var plan := {
		"shape": _shape_by_name[shape_name],
		"size": size,
		"center": center,
		"operation": operation,
		"snapped": snapping,
	}
	return {"ok": true, "scope_ids": [], "apply": _apply_place_brush.bind(root, plan)}


func _apply_place_brush(root: Node, plan: Dictionary) -> Dictionary:
	var operation: int = plan["operation"]
	var info := {
		"shape": plan["shape"],
		"size": plan["size"],
		"transform": Transform3D(Basis(), plan["center"]),
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		# Minted here, not left to create_brush_from_info, so the id in the
		# answer is the one undo and redo bring back.
		"brush_id": root._next_brush_id(),
	}
	var node = root.create_brush_from_info(info)
	if node == null or not (node is DraftBrush):
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not create the brush")
	return {"ok": true, "result": {"brush": brush_dict(root, node), "snapped": plan["snapped"]}}


# ---------------------------------------------------------------------------
# Brushes as plain data
# ---------------------------------------------------------------------------


## A brush the way every tool reports one. World space throughout.
func brush_dict(root: Node, brush: DraftBrush) -> Dictionary:
	var xform := brush.global_transform
	var euler := xform.basis.orthonormalized().get_euler(EULER_ORDER_XYZ)
	var degrees := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))
	var bounds: AABB = root.brush_system.world_bounds_of(brush)
	var palette := _palette(root)
	var faces: Array = []
	for i in brush.faces.size():
		var face = brush.faces[i]
		if face == null:
			continue
		var centre := Vector3.ZERO
		var verts: PackedVector3Array = face.local_verts
		for vert in verts:
			centre += vert
		if not verts.is_empty():
			centre /= float(verts.size())
		var slot := int(face.material_idx)
		var material: Dictionary = palette[slot] if slot >= 0 and slot < palette.size() else {}
		var entry := {
			"index": i,
			"normal": HFMcpProtocol.vec3_to_array(face.normal_through(xform.basis)),
			"center": HFMcpProtocol.vec3_to_array(xform * centre),
			"material_id": material.get("id", null),
			"material_name": material.get("name", null),
		}
		faces.append(entry)
	var node_name := str(brush.name)
	var brush_id: Variant = null
	if brush.brush_id != "":
		brush_id = brush.brush_id
	return {
		"brush_id": brush_id,
		"name": "" if node_name.begins_with("@") else node_name,
		"shape": _name_by_shape.get(brush.shape, "custom"),
		"operation": "subtract" if brush.operation == CSGShape3D.OPERATION_SUBTRACTION else "union",
		"pending": brush.get_parent() == root.pending_node,
		"committed": brush.get_parent() == root.committed_node,
		"position": HFMcpProtocol.vec3_to_array(xform.origin),
		"rotation_degrees": HFMcpProtocol.vec3_to_array(degrees),
		"size": HFMcpProtocol.vec3_to_array(brush.size),
		"bounds":
		{
			"min": HFMcpProtocol.vec3_to_array(bounds.position),
			"max": HFMcpProtocol.vec3_to_array(bounds.end),
		},
		"material_id": material_id_of(brush.material_override, -1),
		"faces": faces,
	}


## The palette as `[{id, name}]`, one entry per slot.
func _palette(root: Node) -> Array:
	var entries: Array = []
	var materials: Array = root.get_materials()
	var names: Array = root.get_material_names()
	for slot in materials.size():
		var material: Material = materials[slot]
		var entry := {
			"id": material_id_of(material, slot),
			"name": str(names[slot]) if slot < names.size() else "",
		}
		entries.append(entry)
	return entries


## A material's id: its file path when it has its own file, else its palette
## slot. A material saved inside a scene has a path like `scene.tscn::1`, which
## names nothing an agent could pass back.
static func material_id_of(material: Material, slot: int) -> Variant:
	if material == null:
		return null
	var path := material.resource_path
	if path != "" and not path.contains("::"):
		return path
	if slot < 0:
		return null
	return "palette:%d" % slot
