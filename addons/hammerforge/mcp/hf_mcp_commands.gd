@tool
class_name HFMcpCommands
extends RefCounted
## The palette commands an agent runs with `hf_run_command`, and the listing
## `hf_list_commands` answers.
##
## `HFCommandRegistry` says which commands the bridge runs and how: the brushes
## and entities each takes, its parameters, and which parameter form here does
## the work. A form is `check_<form>(root, targets, args)` and returns `{ok,
## scope_ids, apply}`, the contract every `HFMcpTools` check has, so the
## dispatcher runs it through the same capture, apply, commit-or-restore wrapper
## and `hf_batch` as every other change.
##
## A form takes the level and nothing else. It never sees the plugin, so it cannot
## read the selection, the dock, Face Select's memory, the axis lock or the pivot
## mode, and an id it cannot resolve is refused rather than made up from what
## happens to be selected. It asks the same facade check the palette asks before
## its dialog (`can_hollow_brush` and the rest), so both refuse in the same words,
## and it opens no dialog: every one of them guards a change undo takes back, so
## the agent's call is the confirmation and `hf_undo` the way back.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFMcpProtocol = preload("hf_mcp_protocol.gd")
const HFMcpTools = preload("hf_mcp_tools.gd")
const HFCommandRegistry = preload("../hf_command_registry.gd")
const HFGeneratorSystem = preload("../systems/hf_generator_system.gd")
const HFGeneratorSchema = preload("../hf_generator_schema.gd")
const HFPrefab = preload("../hf_prefab.gd")
const HFPrefabSystem = preload("../systems/hf_prefab_system.gd")
const HFPaintSystem = preload("../systems/hf_paint_system.gd")
const HFOpResult = preload("../hf_op_result.gd")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## What `hf_run_command` takes besides `operation_id`, which the dispatcher reads.
const ARGUMENTS := ["command", "brush_ids", "entities", "params"]
const AXES := ["x", "y", "z"]
## The paint forms that write cells, whose streamed regions are loaded before a
## capture.
const CELL_FORMS := ["paint_rect", "raise_rect", "stamp_room"]
## What an Update says when the pieces had moved apart, as the dock says before it.
const LOST_PLACE := "The pieces no longer agreed where the structure was, so it was rebuilt where it was made."

## The dispatcher's tools, for the brush and entity readers, face selectors and
## brushes as plain data.
var tools: HFMcpTools

## The prefab library `place_prefab` places from and the listing lists: the
## folder the library panel reads. Tests and the vibe scenario point it at a
## scratch folder, so neither reads or writes the project's own.
var prefab_dir: String = HFPrefabSystem.prefab_dir


func _init(mcp_tools: HFMcpTools) -> void:
	tools = mcp_tools


# ---------------------------------------------------------------------------
# Reading a request
# ---------------------------------------------------------------------------


## `{ok, scope_ids, apply, verb}` for the command `params` names, or a refusal.
## Nothing in the level changes here.
func check(root: Node, params: Dictionary) -> Dictionary:
	var command_read := HFMcpProtocol.read_string(params, "command", true)
	if not command_read["ok"]:
		return command_read
	var command: String = command_read["value"]
	var spec := HFCommandRegistry.bridge(command)
	if spec.is_empty():
		return _unknown_command(command)
	for key in params:
		if not (str(key) in ARGUMENTS):
			return HFMcpProtocol.invalid(
				str(key), "hf_run_command takes %s, not %s" % [", ".join(ARGUMENTS), key]
			)
	var targets := read_targets(root, command, spec, params)
	if not targets["ok"]:
		return targets
	var args := read_params(spec, params.get("params"))
	if not args["ok"]:
		return args
	var checked = call("check_" + str(spec["form"]), root, targets, args["value"])
	if not (checked is Dictionary and (checked as Dictionary).has("ok")):
		return checked
	if not checked["ok"]:
		return checked
	return {
		"ok": true,
		"scope_ids": checked.get("scope_ids", []),
		"apply": _run_form.bind(root, command, targets["brush_ids"], checked["apply"]),
		"verb": HFCommandRegistry.label(command).to_lower(),
	}


func _unknown_command(command: String) -> Dictionary:
	var message := "There is no command '%s'. hf_list_commands lists them." % command
	if HFCommandRegistry.dispatches(command):
		message = (
			"'%s' is a palette command the bridge does not run. hf_list_commands lists the ones it does."
			% command
		)
	return {
		"ok": false,
		"error":
		HFMcpProtocol.error_body(
			HFMcpProtocol.E_UNKNOWN_COMMAND,
			message,
			{"command": command, "commands": Array(HFCommandRegistry.bridge_ids())}
		),
	}


## The brushes and entities a command names, each resolved the way every brush
## and entity tool resolves one, or a refusal. One that does not resolve refuses
## the whole command.
func read_targets(root: Node, command: String, spec: Dictionary, params: Dictionary) -> Dictionary:
	var rule: Dictionary = spec.get("targets", {})
	var low := int(rule.get("min", 0))
	var high := int(rule.get("max", -1))
	var entities_ok := bool(rule.get("entities", false))
	var ids_read := HFMcpProtocol.read_string_array(params, "brush_ids", false, [])
	if not ids_read["ok"]:
		return ids_read
	var paths_read := HFMcpProtocol.read_string_array(params, "entities", false, [])
	if not paths_read["ok"]:
		return paths_read
	var ids: Array = (ids_read["value"] as Array).duplicate()
	var paths: Array = (paths_read["value"] as Array).duplicate()
	if not paths.is_empty() and not entities_ok:
		return HFMcpProtocol.invalid("entities", "%s takes brushes only" % command)
	var count := ids.size() + paths.size()
	if count < low or (high >= 0 and count > high):
		return HFMcpProtocol.invalid("brush_ids", _count_text(command, low, high, entities_ok))
	var brushes: Array = []
	var seen := {}
	for brush_id in ids:
		if brush_id == "":
			return HFMcpProtocol.invalid("brush_ids", "brush_ids must not hold an empty id")
		if seen.has(brush_id):
			return HFMcpProtocol.invalid("brush_ids", "Brush '%s' is listed twice" % brush_id)
		seen[brush_id] = true
		var found := tools._read_brush(root, {"brush_id": brush_id})
		if not found["ok"]:
			return found
		brushes.append(found["brush"])
	var entities: Array = []
	for path in paths:
		if seen.has(path):
			return HFMcpProtocol.invalid("entities", "Entity '%s' is listed twice" % path)
		seen[path] = true
		var found := tools._read_entity(root, {"entity": path})
		if not found["ok"]:
			return found
		entities.append(found["entity"])
	return {
		"ok": true,
		"brush_ids": ids,
		"brushes": brushes,
		"entity_paths": paths,
		"entities": entities
	}


static func _count_text(command: String, low: int, high: int, entities_ok: bool) -> String:
	var what := "brush_ids and entities together" if entities_ok else "brush_ids"
	if high == 0:
		return "%s takes no brush_ids or entities" % command
	if low == high:
		return "%s takes exactly %d in %s" % [command, low, what]
	if high < 0:
		return "%s takes at least %d in %s" % [command, low, what]
	return "%s takes %d to %d in %s" % [command, low, high, what]


## The command's parameters, checked against its fields and with defaults filled
## in, or `invalid_argument` naming `params.<key>`. A key the command does not
## take is refused rather than dropped.
func read_params(spec: Dictionary, given) -> Dictionary:
	if given == null:
		given = {}
	if not (given is Dictionary):
		return HFMcpProtocol.invalid("params", "params must be an object")
	var fields: Array = spec.get("params", [])
	var keys := PackedStringArray()
	for field_def in fields:
		keys.append(str(field_def["key"]))
	for key in given:
		if not keys.has(str(key)):
			var takes := "no params" if keys.is_empty() else ", ".join(keys)
			return HFMcpProtocol.invalid("params.%s" % key, "This command takes %s" % takes)
	var out := {}
	for field_def in fields:
		var read := _read_field(field_def, given)
		if not read["ok"]:
			return _under(read, "params." + str(field_def["key"]))
		out[str(field_def["key"])] = read["value"]
	return {"ok": true, "value": out}


func _read_field(field_def: Dictionary, given: Dictionary) -> Dictionary:
	var key := str(field_def["key"])
	var type_name := str(field_def.get("type", "float"))
	if not given.has(key) or given[key] == null:
		if bool(field_def.get("required", false)):
			return HFMcpProtocol.invalid(key, "%s is required" % key)
		var fallback = field_def.get("default", null)
		if type_name == "vec3" and fallback == null:
			fallback = Vector3.ZERO
		if type_name == "object" and fallback == null:
			fallback = {}
		return {"ok": true, "value": fallback}
	match type_name:
		"float", "int":
			# The frame's rule on any JSON number first, then the field's own.
			var read := HFMcpProtocol.read_number(given, key, true)
			if not read["ok"]:
				return read
			return _schema_field(field_def, given[key], key)
		"bool":
			return _schema_field(field_def, given[key], key)
		"enum", "axis":
			# By label in any case or by index, as a structure's settings are
			# taken; what goes on to the form is the option itself.
			var options: Array = AXES if type_name == "axis" else _options(field_def)
			var read := _schema_field({"type": "enum", "options": options}, given[key], key)
			if not read["ok"]:
				return read
			return {"ok": true, "value": options[read["value"]]}
		"vec3":
			return HFMcpProtocol.read_vec3(given, key, true)
		"string":
			var read := HFMcpProtocol.read_string(given, key, true)
			if read["ok"] and str(read["value"]) == "":
				return HFMcpProtocol.invalid(key, "%s must not be empty" % key)
			return read
		"object":
			if not (given[key] is Dictionary):
				return HFMcpProtocol.invalid(key, "%s must be an object" % key)
			return {"ok": true, "value": given[key]}
		"cell":
			return HFMcpProtocol.read_cell(given, key, true, HFPaintSystem.CELL_LIMIT)
		"layer":
			# An index from 0 or a name; the form resolves it against the level.
			var raw = given[key]
			var shape := "%s is a paint layer's index from 0, or its name" % key
			if raw is float or raw is int:
				var number := float(raw)
				if not is_finite(number) or number != floorf(number) or number < 0.0:
					return HFMcpProtocol.invalid(key, shape)
				return {"ok": true, "value": int(number)}
			if raw is String:
				if raw == "":
					return HFMcpProtocol.invalid(key, "%s must not be empty" % key)
				return {"ok": true, "value": raw}
			return HFMcpProtocol.invalid(key, shape)
	# A face selector is checked by the form, against the brush it names.
	return {"ok": true, "value": given[key]}


## The schema's rule for one field, `HFGeneratorSchema.read_field()`, with its
## refusal as `invalid_argument` naming the param the way every reader here
## does. A command's params and a structure's settings are both in the schema's
## shape, so one rule reads them both.
static func _schema_field(field_def: Dictionary, value, key: String) -> Dictionary:
	var read := HFGeneratorSchema.read_field(field_def, value, key)
	if not read["ok"]:
		return HFMcpProtocol.invalid(key, read["message"])
	return read


## An enum field's choices. The structure types come from the generator system,
## so a new generator is offered without an edit here.
static func _options(field_def: Dictionary) -> Array:
	if str(field_def.get("options_from", "")) == "generator_types":
		return Array(HFGeneratorSystem.known_types())
	return Array(field_def.get("options", []))


## A refusal from a reader, with its `details.param` given the place it has in
## the request.
static func _under(refusal: Dictionary, param: String) -> Dictionary:
	var error: Dictionary = refusal.get("error", {})
	var details: Dictionary = (error.get("details", {}) as Dictionary).duplicate()
	if details.has("param"):
		details["param"] = param
	return {
		"ok": false,
		"error":
		HFMcpProtocol.error_body(
			str(error.get("code", HFMcpProtocol.E_INVALID_ARGUMENT)),
			str(error.get("message", "")),
			details
		),
	}


static func _failed(message: String, details := {}) -> Dictionary:
	return {
		"ok": false,
		"error": HFMcpProtocol.error_body(HFMcpProtocol.E_OPERATION_FAILED, message, details),
	}


# ---------------------------------------------------------------------------
# Running a form
# ---------------------------------------------------------------------------


## Run a form's apply and say what it did. `HFOpResult` carries no ids, so what
## was made and removed is read off the level either side of the change, the same
## way for every command. The facade's warnings come back too: they are what the
## palette's dialog or toast would have said, such as a sculpt a cut drops.
func _run_form(root: Node, command: String, target_ids: Array, form_apply: Callable) -> Dictionary:
	var brushes_before := _brush_nodes(root)
	var target_before := {}
	for brush_id in target_ids:
		if brushes_before.has(brush_id):
			target_before[brush_id] = (
				tools.brush_dict(root, brushes_before[brush_id], false).duplicate(true)
			)
	var entities_before := _entity_paths(root)
	var warnings: Array = []
	var listen := _keep_warning.bind(warnings)
	root.user_message.connect(listen)
	var outcome = form_apply.call()
	if root.user_message.is_connected(listen):
		root.user_message.disconnect(listen)
	if not (outcome is Dictionary and (outcome as Dictionary).has("ok")) or not outcome["ok"]:
		return outcome
	var result: Dictionary = (outcome.get("result", {}) as Dictionary).duplicate()
	var brushes_after := _brush_nodes(root)
	var made: Array = []
	for brush_id in brushes_after:
		if not brushes_before.has(brush_id):
			made.append(tools.brush_dict(root, brushes_after[brush_id], false))
	var removed: Array = []
	for brush_id in brushes_before:
		if not brushes_after.has(brush_id):
			removed.append(brush_id)
	var changed: Array = []
	for brush_id in target_ids:
		if brushes_after.has(brush_id) and brushes_before.has(brush_id):
			var after: Dictionary = tools.brush_dict(root, brushes_after[brush_id], false)
			if after != target_before[brush_id]:
				changed.append(after)
	var entities_after := _entity_paths(root)
	var entities_made: Array = []
	for path in entities_after:
		if not entities_before.has(path):
			entities_made.append(path)
	var entities_removed: Array = []
	for path in entities_before:
		if not entities_after.has(path):
			entities_removed.append(path)
	result["command"] = command
	result["label"] = HFCommandRegistry.label(command)
	result["made"] = made
	result["removed"] = removed
	result["changed"] = changed
	result["entities_made"] = entities_made
	result["entities_removed"] = entities_removed
	result["warnings"] = (result.get("warnings", []) as Array) + warnings
	# One brush made is what `$N.brush_id` in a batch names, as for a placed brush.
	if made.size() == 1:
		result["brush"] = made[0]
	return {"ok": true, "result": result}


## brush_id -> node for every brush with an id, in container order. Read off the
## nodes: `get_brush_info_from_node()` writes an id onto a brush without one.
static func _brush_nodes(root: Node) -> Dictionary:
	var out := {}
	for node in root._iter_managed_brush_nodes():
		var brush := node as DraftBrush
		if brush and brush.brush_id != "":
			out[brush.brush_id] = brush
	return out


static func _entity_paths(root: Node) -> Dictionary:
	var out := {}
	if root.entities_node == null:
		return out
	for child in root.entities_node.get_children():
		if child is DraftEntity:
			out[str(root.get_path_to(child))] = true
	return out


static func _keep_warning(text: String, level: int, into: Array) -> void:
	if level >= 1:
		into.append(text)


# ---------------------------------------------------------------------------
# The forms
# ---------------------------------------------------------------------------

# Each `check_<form>(root, targets, args)` is named by a registry entry's
# `bridge.form`. It runs the same check the palette runs before its dialog and
# answers `{ok, scope_ids, apply}`, as every `HFMcpTools` check does. It gets the
# level and nothing else, so it cannot reach the selection or the dock.


func check_move_to_floor(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var ids: Array = targets["brush_ids"]
	return {"ok": true, "scope_ids": ids, "apply": _apply_vertical.bind(root, ids, true)}


func check_move_to_ceiling(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var ids: Array = targets["brush_ids"]
	return {"ok": true, "scope_ids": ids, "apply": _apply_vertical.bind(root, ids, false)}


func _apply_vertical(root: Node, ids: Array, down: bool) -> Dictionary:
	if down:
		root.move_brushes_to_floor(ids)
	else:
		root.move_brushes_to_ceiling(ids)
	return {"ok": true, "result": {}}


func check_snap_to_grid(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var verdict: HFOpResult = root.can_snap_to_grid()
	if not verdict.ok:
		return _failed(verdict.user_text())
	var ids: Array = targets["brush_ids"]
	return {"ok": true, "scope_ids": ids, "apply": _apply_snap_to_grid.bind(root, ids)}


func _apply_snap_to_grid(root: Node, ids: Array) -> Dictionary:
	root.snap_managed_nodes_to_grid(ids, [])
	return {"ok": true, "result": {}}


func check_reset_rotation(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var ids: Array = targets["brush_ids"]
	return {"ok": true, "scope_ids": ids, "apply": _apply_reset_rotation.bind(root, ids)}


func _apply_reset_rotation(root: Node, ids: Array) -> Dictionary:
	root.reset_managed_rotation(ids)
	return {"ok": true, "result": {}}


func check_hollow(root: Node, targets: Dictionary, args: Dictionary) -> Dictionary:
	var brush_id: String = targets["brush_ids"][0]
	var thickness := float(args["thickness"])
	var verdict: HFOpResult = root.can_hollow_brush(brush_id, thickness)
	if not verdict.ok:
		return _failed(verdict.user_text())
	return {"ok": true, "scope_ids": [], "apply": _apply_hollow.bind(root, brush_id, thickness)}


func _apply_hollow(root: Node, brush_id: String, thickness: float) -> Dictionary:
	var done: HFOpResult = root.hollow_brush_by_id(brush_id, thickness)
	if not done.ok:
		return _failed(done.user_text())
	return {"ok": true, "result": {"thickness": thickness}}


func check_clip(root: Node, targets: Dictionary, args: Dictionary) -> Dictionary:
	var brush_id: String = targets["brush_ids"][0]
	var axis := AXES.find(str(args["axis"]))
	var position = args.get("position")
	var split: float = (
		root.default_clip_position(brush_id, axis) if position == null else float(position)
	)
	var verdict: HFOpResult = root.can_clip_brush(brush_id, axis, split)
	if not verdict.ok:
		return _failed(verdict.user_text())
	return {"ok": true, "scope_ids": [], "apply": _apply_clip.bind(root, brush_id, axis, split)}


func _apply_clip(root: Node, brush_id: String, axis: int, split: float) -> Dictionary:
	var done: HFOpResult = root.clip_brush_by_id(brush_id, axis, split)
	if not done.ok:
		return _failed(done.user_text())
	# Where the cut went: the clip snaps the position to the grid, as the check did.
	var applied := snappedf(split, root.grid_snap) if root.grid_snap > 0.0 else split
	return {"ok": true, "result": {"axis": AXES[axis], "split_position": applied}}


func check_clip_to_face(root: Node, targets: Dictionary, args: Dictionary) -> Dictionary:
	var source := tools._read_brush(root, {"brush_id": args["plane_brush_id"]})
	if not source["ok"]:
		return _under(source, "params.plane_brush_id")
	var face := tools._resolve_face(source["brush"], args["plane_face"])
	if not face["ok"]:
		return _under(face, "params.plane_face")
	var source_id := str(args["plane_brush_id"])
	var plane: Plane = root.face_world_plane(source_id, int(face["index"]))
	if plane.normal.length_squared() < 0.5:
		return _failed("Clip to Face: that face has no usable plane")
	var cuttable: Array = []
	var skipped: Array = []
	for brush_id in targets["brush_ids"]:
		if root.plane_splits_brush(str(brush_id), plane):
			cuttable.append(str(brush_id))
		else:
			skipped.append(str(brush_id))
	if cuttable.is_empty():
		return _failed("Clip to Face: that plane does not pass through any brush in brush_ids")
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_clip_to_face.bind(root, cuttable, plane, skipped, int(face["index"])),
	}


func _apply_clip_to_face(
	root: Node, cuttable: Array, plane: Plane, skipped: Array, face_index: int
) -> Dictionary:
	if root.clip_brushes_by_plane(cuttable, plane) <= 0:
		return _failed("Clip to Face: the plane cut nothing")
	return {"ok": true, "result": {"skipped": skipped, "plane_face": face_index}}


func check_carve(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var cutting: Array = []
	var skipped: Array = []
	var refusal: HFOpResult = null
	for brush_id in targets["brush_ids"]:
		var verdict: HFOpResult = root.can_carve_brush(str(brush_id))
		if verdict.ok:
			cutting.append(str(brush_id))
		else:
			skipped.append(str(brush_id))
			if refusal == null:
				refusal = verdict
	if cutting.is_empty():
		return _failed(refusal.user_text() if refusal else "Carve: nothing to carve with")
	return {"ok": true, "scope_ids": [], "apply": _apply_carve.bind(root, cutting, skipped)}


func _apply_carve(root: Node, cutting: Array, skipped: Array) -> Dictionary:
	var missed: Array = skipped.duplicate()
	for i in cutting.size():
		var brush_id: String = cutting[i]
		# The first was checked against this level. A carver after it can have been
		# cut up by an earlier one, or lost what it overlapped, as the palette knows.
		if i > 0 and not root.can_carve_brush(brush_id).ok:
			missed.append(brush_id)
			continue
		var done: HFOpResult = root.carve_with_brush(brush_id)
		if not done.ok:
			return _failed(done.user_text())
	return {"ok": true, "result": {"skipped": missed}}


func check_merge(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var ids: Array = targets["brush_ids"]
	# Held for the merge below, so a call plans once, as a palette press does (#1257).
	var verdict: HFOpResult = root.can_merge_brushes(ids, true)
	if not verdict.ok:
		return _failed(verdict.user_text())
	return {"ok": true, "scope_ids": [], "apply": _apply_merge.bind(root, ids)}


func _apply_merge(root: Node, ids: Array) -> Dictionary:
	var done: HFOpResult = root.merge_brushes_by_ids(ids)
	root.release_merge_plan()
	if not done.ok:
		return _failed(done.user_text())
	return {"ok": true, "result": {}}


func check_create_structure(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var type_name := str(args["type"])
	var read := read_settings(type_name, args.get("settings", {}))
	if not read["ok"]:
		return read
	var settings: Dictionary = read["value"]
	var verdict: HFOpResult = root.can_build_generator(type_name, settings)
	if not verdict.ok:
		return _failed(verdict.user_text())
	var degrees: Vector3 = args["rotation_degrees"]
	var radians := Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
	var placement := Transform3D(Basis.from_euler(radians, EULER_ORDER_XYZ), args["position"])
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_create_structure.bind(root, type_name, settings, placement),
	}


## A structure's settings: each key one its type has, each value as
## `HFGeneratorSchema.read_field()` takes it, of the field's type and inside
## its range, an enum by index or by its label. The rest come from `base`, an
## existing structure's settings, or else take their defaults.
## `HFGeneratorSchema.merge()` would turn a stray string into the default and
## drop an unknown key, both quietly; the dock cannot send either, an agent
## can, and is told.
func read_settings(type_name: String, given, base := {}) -> Dictionary:
	if not (given is Dictionary):
		return HFMcpProtocol.invalid("params.settings", "settings must be an object")
	var schema := HFGeneratorSystem.settings_schema(type_name)
	var keys := HFGeneratorSchema.keys(schema)
	var provided := {}
	for key in given:
		var param := "params.settings.%s" % key
		if not keys.has(str(key)):
			return HFMcpProtocol.invalid(
				param, "A %s has no setting %s; it has %s" % [type_name, key, ", ".join(keys)]
			)
		var field_def := HFGeneratorSchema.field(schema, str(key))
		var read := HFGeneratorSchema.read_field(field_def, given[key], str(key))
		if not read["ok"]:
			return HFMcpProtocol.invalid(param, read["message"])
		provided[str(key)] = read["value"]
	var start: Dictionary = base.duplicate(true)
	start.merge(provided, true)
	return {"ok": true, "value": HFGeneratorSchema.merge(schema, start)}


func _apply_create_structure(
	root: Node, type_name: String, settings: Dictionary, placement: Transform3D
) -> Dictionary:
	var before := _generator_ids(root)
	var done: HFOpResult = root.create_generator(type_name, settings, placement)
	if not done.ok:
		return _failed(done.user_text())
	var made_id: Variant = null
	for generator_id in _generator_ids(root):
		if not before.has(generator_id):
			made_id = generator_id
	return {
		"ok": true,
		"result":
		{"generator_id": made_id, "type": type_name, "settings": HFMcpTools._plain(settings)},
	}


static func _generator_ids(root: Node) -> Array:
	return root.generator_system.generators.keys() if root.generator_system else []


func check_update_structure(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var found := _structure(root, str(args["generator_id"]))
	if not found["ok"]:
		return found
	var record = found["value"]
	var read := read_settings(record.type, args.get("settings", {}), record.settings)
	if not read["ok"]:
		return read
	var settings: Dictionary = read["value"]
	var verdict: HFOpResult = root.can_build_generator(record.type, settings)
	if not verdict.ok:
		return _failed(HFGeneratorSystem.not_changed_text(record.type, verdict))
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_update_structure.bind(root, str(record.generator_id), settings),
	}


## What the dock says before an Update over painted faces, hand edits or pieces
## that no longer agree where the structure is, said after it instead: the
## agent's call was the confirmation, and `hf_undo` takes it back.
func _apply_update_structure(root: Node, generator_id: String, settings: Dictionary) -> Dictionary:
	var record = root.generator_for_id(generator_id)
	# The settings it already has, on pieces nobody touched: as from the dock,
	# nothing is rebuilt, so every piece keeps its id (#1368).
	if root.generator_update_changes_nothing(generator_id, settings):
		return {
			"ok": true,
			"result":
			{
				"generator_id": generator_id,
				"type": record.type,
				"settings": HFMcpTools._plain(settings),
				"no_change": true,
				"appearance_dropped": [],
				"edits_replaced": [],
				"warnings": [],
			},
		}
	var dropped := Array(root.generator_appearance_at_risk(generator_id, settings))
	var replaced := Array(root.generator_system.edited_brush_ids(generator_id))
	var lost_place: bool = root.generator_pieces_disagree(generator_id)
	var done: HFOpResult = root.regenerate_generator(generator_id, settings)
	if not done.ok:
		return _failed(HFGeneratorSystem.not_changed_text(record.type, done))
	var warnings: Array = []
	if lost_place:
		warnings.append(LOST_PLACE)
	if not dropped.is_empty():
		warnings.append(
			(
				"%d piece%s had painted faces these settings could not keep."
				% [dropped.size(), "" if dropped.size() == 1 else "s"]
			)
		)
	if not replaced.is_empty():
		warnings.append(
			(
				"%d piece%s edited or deleted by hand went back to the settings' shape."
				% [replaced.size(), "" if replaced.size() == 1 else "s"]
			)
		)
	return {
		"ok": true,
		"result":
		{
			"generator_id": generator_id,
			"type": record.type,
			"settings": HFMcpTools._plain(settings),
			"no_change": false,
			"appearance_dropped": dropped,
			"edits_replaced": replaced,
			"warnings": warnings,
		},
	}


func check_detach_structure(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var found := _structure(root, str(args["generator_id"]))
	if not found["ok"]:
		return found
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_detach_structure.bind(root, str(found["value"].generator_id)),
	}


func _apply_detach_structure(root: Node, generator_id: String) -> Dictionary:
	var record = root.generator_for_id(generator_id)
	# The record is a hint: only a brush that still carries the structure's tag is
	# one of its pieces.
	var nodes := _brush_nodes(root)
	var pieces: Array = []
	for brush_id in record.brush_ids:
		var node: Node = nodes.get(str(brush_id))
		if node and str(node.get_meta(HFGeneratorSystem.GENERATOR_META, "")) == generator_id:
			pieces.append(str(brush_id))
	var type_name := str(record.type)
	var settings: Dictionary = record.settings.duplicate(true)
	if not root.detach_generator(generator_id):
		return _failed("The structure could not be detached")
	return {
		"ok": true,
		"result":
		{
			"generator_id": generator_id,
			"type": type_name,
			"settings": settings,
			"detached": pieces,
		},
	}


## The structure `generator_id` names, or `invalid_argument` naming it. A record
## of a type this build has no builder for cannot be rebuilt, so it is refused
## here rather than by the builder.
func _structure(root: Node, generator_id: String) -> Dictionary:
	var record = root.generator_for_id(generator_id)
	if record == null:
		var message := (
			"No structure '%s' is in the level. hf_get_brushes lists each piece's structure."
			% generator_id
		)
		return HFMcpProtocol.invalid("params.generator_id", message)
	if HFGeneratorSystem.builder_for(record.type) == null:
		return _failed(
			(
				"'%s' is a %s, which this version of HammerForge cannot build"
				% [generator_id, record.type]
			)
		)
	return {"ok": true, "value": record}


func check_cycle_variant(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var piece := _prefab_piece(targets, HFPrefabSystem.INSTANCE_META)
	if not piece["ok"]:
		return piece
	var instance_id: String = piece["value"]
	var record = root.prefab_system.get_instance(instance_id)
	if record == null:
		return _failed("That prefab copy is no longer in the level's prefab records")
	var prefab = HFPrefab.load_from_file(record.source_path)
	if prefab == null:
		return _failed("The prefab file %s could not be read" % record.source_path)
	if prefab.get_variant_names().size() <= 1:
		return _failed("%s has one variant, so there is none to switch to" % record.source_path)
	return {"ok": true, "scope_ids": [], "apply": _apply_cycle_variant.bind(root, instance_id)}


func _apply_cycle_variant(root: Node, instance_id: String) -> Dictionary:
	var variant: String = root.prefab_system.cycle_variant(instance_id)
	if variant == "":
		return _failed("The prefab copy could not switch variant")
	return {"ok": true, "result": {"instance_id": instance_id, "variant": variant}}


func check_propagate_prefab(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var piece := _prefab_piece(targets, HFPrefabSystem.SOURCE_META)
	if not piece["ok"]:
		return piece
	var source: String = piece["value"]
	var linked := 0
	for record in root.prefab_system.get_instances_for_source(source):
		if record.linked and not root.prefab_system._instance_is_gone(record):
			linked += 1
	if linked == 0:
		return _failed("No linked instances to propagate")
	return {"ok": true, "scope_ids": [], "apply": _apply_propagate.bind(root, source)}


func _apply_propagate(root: Node, source: String) -> Dictionary:
	var count: int = root.prefab_system.propagate_from_source(source)
	if count <= 0:
		return _failed("No linked instances to propagate")
	return {"ok": true, "result": {"source": source, "instances": count}}


func check_place_prefab(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	if root.prefab_system == null:
		return _failed("This level has no prefab records, so nothing can be placed in it")
	var library := _library()
	var prefab_name := str(args["prefab"])
	if not library.has(prefab_name):
		return HFMcpProtocol.invalid("params.prefab", _not_in_library(prefab_name, library))
	var path: String = library[prefab_name]["path"]
	var prefab = library[prefab_name]["prefab"]
	if prefab == null:
		return _failed("%s is not a prefab this build can read" % path)
	var variant := "base"
	if args.get("variant") != null:
		variant = str(args["variant"])
		if not prefab.has_variant(variant):
			var message := (
				"%s has no variant '%s'; it has %s"
				% [prefab_name, variant, ", ".join(prefab.get_variant_names())]
			)
			return HFMcpProtocol.invalid("params.variant", message)
	var data: Dictionary = prefab.get_variant_data(variant)
	var brush_infos: Array = data.get("brush_infos", [])
	var entity_infos: Array = data.get("entity_infos", [])
	if brush_infos.is_empty() and entity_infos.is_empty():
		return _failed("%s holds nothing to place in its %s variant" % [prefab_name, variant])
	var degrees: Vector3 = args["rotation_degrees"]
	var radians := Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
	var frame := Transform3D(Basis.from_euler(radians, EULER_ORDER_XYZ), args["position"])
	var placing := {
		"prefab": prefab_name,
		"path": path,
		"variant": variant,
		"linked": bool(args["linked"]),
		"degrees": degrees,
	}
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_place_prefab.bind(root, prefab, frame, placing),
	}


func _apply_place_prefab(
	root: Node, prefab: HFPrefab, frame: Transform3D, placing: Dictionary
) -> Dictionary:
	var placed: Dictionary = root.prefab_system.place(
		prefab, placing["path"], frame, placing["variant"], placing["linked"]
	)
	if placed.is_empty():
		return _failed("%s placed nothing" % placing["prefab"])
	var result := {
		"instance_id": placed["instance_id"],
		"prefab": placing["prefab"],
		"source": placing["path"],
		"variant": placing["variant"],
		"linked": placing["linked"],
		"position": HFMcpProtocol.vec3_to_array(frame.origin),
		"rotation_degrees": HFMcpProtocol.vec3_to_array(placing["degrees"]),
	}
	return {"ok": true, "result": result}


## The library's prefabs by name: `{name: {path, prefab}}`, the prefab null where
## the file will not read. Read off the folder each time, as the library panel
## reads it, and only off it: a name is looked up here and never made into a
## path, so one with `../` in it names nothing.
func _library() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(prefab_dir):
		return out
	for file_name in DirAccess.get_files_at(prefab_dir):
		if file_name.ends_with(".hfprefab"):
			var path := prefab_dir.path_join(file_name)
			out[file_name.get_basename()] = {"path": path, "prefab": HFPrefab.load_from_file(path)}
	return out


func _not_in_library(prefab_name: String, library: Dictionary) -> String:
	if library.is_empty():
		return (
			"The prefab library (%s) holds no prefabs. Save one from the editor first." % prefab_dir
		)
	var names: Array = library.keys()
	names.sort()
	return (
		"There is no prefab '%s' in the library (%s). It holds %s."
		% [prefab_name, prefab_dir, ", ".join(PackedStringArray(names))]
	)


## The library as `hf_list_commands` gives it under `place_prefab`: each prefab's
## name, variants, tags and counts, by name.
func library_listing() -> Array:
	var out: Array = []
	var library := _library()
	var names: Array = library.keys()
	names.sort()
	for prefab_name in names:
		var prefab = library[prefab_name]["prefab"]
		var entry := {"name": prefab_name, "readable": prefab != null}
		if prefab != null:
			entry["variants"] = prefab.get_variant_names()
			entry["tags"] = Array(prefab.tags)
			entry["brushes"] = prefab.brush_infos.size()
			entry["entities"] = prefab.entity_infos.size()
		out.append(entry)
	return out


## The prefab metadata `key` on the one brush or entity a prefab command names.
func _prefab_piece(targets: Dictionary, key: String) -> Dictionary:
	var node: Node = null
	var param := "brush_ids"
	var label := ""
	if not (targets["brushes"] as Array).is_empty():
		node = targets["brushes"][0]
		label = "Brush '%s'" % targets["brush_ids"][0]
	else:
		node = targets["entities"][0]
		param = "entities"
		label = "Entity '%s'" % targets["entity_paths"][0]
	var value := str(node.get_meta(key, ""))
	if value == "":
		return HFMcpProtocol.invalid(param, "%s is not a piece of a placed prefab" % label)
	return {"ok": true, "value": value}


# ---------------------------------------------------------------------------
# Floor paint
# ---------------------------------------------------------------------------

# The paint forms call the paint system's cell-space calls (#1299). Each check
# resolves the layer, reads the rectangle and asks what the call would refuse,
# so a refusal comes before the capture; the apply makes the one call, which
# writes the cells and rebuilds their chunks. A check that writes cells loads
# and pins the rectangle's streamed regions as it passes, so the capture holds
# the paint they had on disk (#1502); the call lets the pins go.


func check_paint_rect(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var rect := _written_rect("paint_rect", args)
	var target := _paint_target(root, args, rect["from"], rect["to"], "params.to")
	if not target["ok"]:
		return target
	var filled := bool(args["filled"])
	var material = args.get("material")
	if material != null and not filled:
		return HFMcpProtocol.invalid(
			"params.material", "material goes on the cells painted; an erase takes none"
		)
	var material_id := -1 if material == null else int(material)
	root.paint_system.load_rect_regions(target["from"], target["to"])
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_paint_rect.bind(root, target, filled, material_id),
	}


func _apply_paint_rect(
	root: Node, target: Dictionary, filled: bool, material_id: int
) -> Dictionary:
	var done: Dictionary = root.paint_system.paint_cells(
		target["index"], target["from"], target["to"], filled, material_id
	)
	if not done["ok"]:
		return _paint_refused(root, done)
	var result := _paint_answer(root, target)
	result["filled"] = filled
	result["cells"] = done["cells"]
	result["cells_changed"] = done["changed"]
	result["materials_changed"] = done["materials_changed"]
	# No ternary: null and a number are not one type to the parser.
	var material: Variant = null
	if material_id >= 0:
		material = material_id
	result["material"] = material
	return {"ok": true, "result": result}


func check_raise_rect(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var rect := _written_rect("raise_rect", args)
	var target := _paint_target(root, args, rect["from"], rect["to"], "params.to")
	if not target["ok"]:
		return target
	var height := float(args["height"])
	var ready: Dictionary = root.paint_system.check_raise_cells(
		target["index"], target["from"], target["to"], height
	)
	if not ready["ok"]:
		return _failed(ready["error"])
	return {"ok": true, "scope_ids": [], "apply": _apply_raise_rect.bind(root, target, height)}


func _apply_raise_rect(root: Node, target: Dictionary, height: float) -> Dictionary:
	var done: Dictionary = root.paint_system.raise_cells(
		target["index"], target["from"], target["to"], height
	)
	if not done["ok"]:
		return _paint_refused(root, done)
	var result := _paint_answer(root, target)
	result["height"] = height
	result["raised"] = done["raised"]
	result["heights_changed"] = done["changed"]
	return {"ok": true, "result": result}


func check_stamp_room(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var rect := _written_rect("stamp_room", args)
	var target := _paint_target(root, args, rect["from"], rect["to"], "params.at")
	if not target["ok"]:
		return target
	var height: float = -1.0 if args.get("height") == null else float(args["height"])
	root.paint_system.load_rect_regions(target["from"], target["to"])
	var width := int(args["width"])
	var depth := int(args["depth"])
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_stamp_room.bind(root, target, width, depth, height),
	}


func _apply_stamp_room(
	root: Node, target: Dictionary, width: int, depth: int, height: float
) -> Dictionary:
	var done: Dictionary = root.paint_system.stamp_room(
		target["index"], target["from"], width, depth, height
	)
	if not done["ok"]:
		return _paint_refused(root, done)
	var result := _paint_answer(root, target)
	result["at"] = result["from"]
	result["width"] = width
	result["depth"] = depth
	var raised_to: Variant = null
	if height > 0.0:
		raised_to = height
	result["height"] = raised_to
	result["cells"] = done["cells"]
	result["cells_changed"] = done["changed"]
	result["raised"] = done["raised"]
	return {"ok": true, "result": result}


func check_confirm_connector(root: Node, _targets: Dictionary, args: Dictionary) -> Dictionary:
	var from: Vector2i = args["from"]
	var to: Vector2i = args["to"] if args.get("to") != null else from
	var target := _paint_target(root, args, from, to, "params.to")
	if not target["ok"]:
		return target
	var other := -1
	if args.get("to_layer") != null:
		var found := _paint_layer(root, args["to_layer"], "params.to_layer")
		if not found["ok"]:
			return found
		other = int(found["index"])
	var candidates: Dictionary = root.paint_system.check_confirm_connectors(
		target["index"], from, to, other
	)
	if not candidates["ok"]:
		if candidates.get("argument", "") == "to_layer":
			return HFMcpProtocol.invalid("params.to_layer", candidates["error"])
		return _failed(candidates["error"])
	return {
		"ok": true,
		"scope_ids": [],
		"apply": _apply_confirm_connector.bind(root, target, other),
	}


func _apply_confirm_connector(root: Node, target: Dictionary, other: int) -> Dictionary:
	var done: Dictionary = root.paint_system.confirm_connectors(
		target["index"], target["from"], target["to"], other
	)
	if not done["ok"]:
		return _failed(done["error"])
	var result := _paint_answer(root, target)
	result.erase("bounds")
	var to_layer: Variant = null
	if other >= 0:
		to_layer = other
	result["to_layer"] = to_layer
	result["connectors"] = done["connectors"]
	result["added"] = done["added"]
	result["already"] = done["already"]
	return {"ok": true, "result": result}


## The corners a cell-writing paint form writes, both included: `from` and
## `to`, `to` alone being `from`, or a room's `at`, `width` and `depth`. Each
## form's check reads them here, and so does hf_batch's region load ahead of its
## capture, so both load the same regions.
static func _written_rect(form: String, args: Dictionary) -> Dictionary:
	if form == "stamp_room":
		var at: Vector2i = args["at"]
		return {"from": at, "to": at + Vector2i(int(args["width"]) - 1, int(args["depth"]) - 1)}
	var from: Vector2i = args["from"]
	return {"from": from, "to": args["to"] if args.get("to") != null else from}


## Load and pin the streamed regions the paint ops among an hf_batch's `ops`
## write, before the batch takes its one capture (#1502). Each op's own check
## loads them only after that capture, which would then miss the paint they had
## on disk, and an undo of the batch would drop it. An op that does not read,
## or whose rectangle the paint system would refuse, is left to its check. True
## when anything was pinned; the batch lets the pins go once it has captured.
func load_batch_paint_regions(root: Node, ops: Array) -> bool:
	if root.paint_system == null or not root.paint_system.region_streaming_enabled:
		return false
	var pinned := false
	for op in ops:
		var params = op.get("params")
		if op.get("tool") != "hf_run_command" or not (params is Dictionary):
			continue
		var spec := HFCommandRegistry.bridge(str(params.get("command", "")))
		var form := str(spec.get("form", ""))
		if not (form in CELL_FORMS):
			continue
		var args := read_params(spec, params.get("params"))
		if not args["ok"]:
			continue
		var rect := _written_rect(form, args["value"])
		var target := _paint_target(root, args["value"], rect["from"], rect["to"], "params.to")
		if not target["ok"]:
			continue
		root.paint_system.load_rect_regions(target["from"], target["to"])
		pinned = true
	return pinned


## A cell-space call's refusal as an answer. The call lets region pins go only
## once it has taken its own, so the ones its check took are let go here.
func _paint_refused(root: Node, done: Dictionary) -> Dictionary:
	root.paint_system.release_paint_region_pins()
	return _failed(done["error"])


## What every paint form reads first: the layer `args.layer` names, the
## rectangle, and the paint system ready to take a call. `{ok, index, layer,
## from, to}` or a refusal: `invalid_argument` naming `params.layer` or
## `to_param` for a rectangle the system would not take, `operation_failed`
## while the Paint tool is mid-stroke.
func _paint_target(
	root: Node, args: Dictionary, from: Vector2i, to: Vector2i, to_param: String
) -> Dictionary:
	if root.paint_system == null or root.paint_layers == null or root.paint_tool == null:
		return _failed("The level has no paint system")
	var found := _paint_layer(root, args.get("layer"), "params.layer")
	if not found["ok"]:
		return found
	var ready: Dictionary = root.paint_system.check_rect(found["index"], from, to)
	if not ready["ok"]:
		var argument := str(ready.get("argument", ""))
		if argument != "":
			return HFMcpProtocol.invalid(
				"params.layer" if argument == "layer" else to_param, ready["error"]
			)
		return _failed(ready["error"])
	return {"ok": true, "index": found["index"], "layer": found["layer"], "from": from, "to": to}


## The paint layer `value` names: an index from 0, a name, or null for the
## active layer. `{ok, index, layer}` or `invalid_argument` naming `param`, with
## the layers the level has.
func _paint_layer(root: Node, value, param: String) -> Dictionary:
	var index := -1
	if value == null:
		index = int(root.paint_layers.active_layer_index)
	elif value is int:
		index = int(value)
	else:
		index = int(root.paint_system.find_paint_layer(str(value)))
	var layer = root.paint_system.paint_layer_at(index)
	if layer == null:
		var names: Array = []
		for entry in root.paint_system.describe_paint_layers():
			names.append("%s (%d)" % [entry["name"], entry["index"]])
		var what := "the active layer" if value == null else "'%s'" % str(value)
		return HFMcpProtocol.invalid(
			param,
			"No paint layer %s. The level has %s." % [what, ", ".join(PackedStringArray(names))]
		)
	return {"ok": true, "index": index, "layer": layer}


## What every paint answer carries: the layer as `{index, id, name}`, the
## corners as `[x, z]`, and `bounds`, the rectangle in world metres on the
## floor's top, so an agent can stand something on what it painted.
func _paint_answer(root: Node, target: Dictionary) -> Dictionary:
	var layer = target["layer"]
	var from: Vector2i = target["from"]
	var to: Vector2i = target["to"]
	var low := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var high := Vector2i(maxi(from.x, to.x) + 1, maxi(from.y, to.y) + 1)
	var top: float = layer.grid.layer_y + root.paint_tool.synth_settings.floor_thickness
	var a: Vector3 = layer.grid.uv_to_world(layer.grid.cell_to_uv(low), top)
	var b: Vector3 = layer.grid.uv_to_world(layer.grid.cell_to_uv(high), top)
	var lowest := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var highest := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	return {
		"layer":
		{
			"index": target["index"],
			"id": str(layer.layer_id),
			"name": HFPaintSystem.paint_layer_name(layer),
		},
		"from": [from.x, from.y],
		"to": [to.x, to.y],
		"bounds":
		{
			"min": HFMcpProtocol.vec3_to_array(lowest),
			"max": HFMcpProtocol.vec3_to_array(highest),
		},
	}


# ---------------------------------------------------------------------------
# hf_list_commands
# ---------------------------------------------------------------------------


## Every command the bridge runs, as the agent reads it: what it does, what it
## takes, and its parameters as JSON Schema. With `root`, the level the bridge
## is on, a paint command also lists its `paint_layers`.
func listing(root: Node = null) -> Array:
	var out: Array = []
	for command in HFCommandRegistry.bridge_ids():
		var spec := HFCommandRegistry.bridge(command)
		var rule: Dictionary = spec.get("targets", {})
		var high := int(rule.get("max", -1))
		# No cap is null to the agent, not -1.
		var cap: Variant = null
		if high >= 0:
			cap = high
		var entry := {
			"command": command,
			"label": HFCommandRegistry.label(command),
			"category": HFCommandRegistry.category(command),
			"description": str(spec.get("description", "")),
			"targets":
			{
				"min": int(rule.get("min", 0)),
				"max": cap,
				"entities": bool(rule.get("entities", false)),
			},
			"params": params_schema(spec),
			"undo": str(spec.get("undo", "level")),
		}
		# Each structure type's settings, for every command that takes them: the
		# type enum of create_arch, and the settings object of create_arch and
		# update_structure.
		for field_def in spec.get("params", []):
			if (
				str(field_def.get("options_from", "")) == "generator_types"
				or str(field_def.get("key", "")) == "settings"
			):
				entry["settings_by_type"] = settings_by_type()
			if str(field_def.get("key", "")) == "prefab":
				entry["prefabs"] = library_listing()
			# The layers an agent can name, read off the level; none with no level.
			if str(field_def.get("type", "")) == "layer" and not entry.has("paint_layers"):
				entry["paint_layers"] = paint_layer_listing(root)
		out.append(entry)
	return out


## The paint layers as `hf_list_commands` gives them under a paint command, or
## `[]` with no level open.
static func paint_layer_listing(root: Node) -> Array:
	if root == null or not is_instance_valid(root) or root.get("paint_system") == null:
		return []
	return root.paint_system.describe_paint_layers()


## The JSON Schema `hf_list_commands` gives for a bridge entry's `params`.
static func params_schema(spec: Dictionary) -> Dictionary:
	var properties := {}
	var required: Array = []
	for field_def in spec.get("params", []):
		var key := str(field_def["key"])
		properties[key] = _field_schema(field_def)
		if bool(field_def.get("required", false)):
			required.append(key)
	return {
		"type": "object",
		"properties": properties,
		"required": required,
		"additionalProperties": false,
	}


static func _field_schema(field_def: Dictionary) -> Dictionary:
	var out := {}
	match str(field_def.get("type", "float")):
		"float":
			out = {"type": "number"}
		"int":
			out = {"type": "integer"}
		"bool":
			out = {"type": "boolean"}
		"enum":
			out = {"type": "string", "enum": _options(field_def)}
		"axis":
			out = {"type": "string", "enum": AXES}
		"vec3":
			out = _vec3_schema()
		"string":
			out = {"type": "string", "minLength": 1}
		"object":
			out = {"type": "object"}
		"cell":
			out = {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2}
		"layer":
			out = {"anyOf": [{"type": "integer", "minimum": 0}, {"type": "string", "minLength": 1}]}
		"face":
			out = {
				"anyOf":
				[
					{"type": "integer", "minimum": 0},
					{"type": "string", "enum": HFMcpTools.SIDES.keys()},
					{
						"type": "object",
						"properties": {"normal": _vec3_schema()},
						"required": ["normal"],
					},
				]
			}
	if field_def.has("min"):
		out["minimum"] = field_def["min"]
	if field_def.has("max"):
		out["maximum"] = field_def["max"]
	if field_def.has("default"):
		out["default"] = field_def["default"]
	if field_def.has("description"):
		out["description"] = field_def["description"]
	return out


static func _vec3_schema() -> Dictionary:
	return {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}


## Each structure type's settings as JSON Schema, from the schema the dock builds
## its fields from, so a new generator is described without an edit here.
static func settings_by_type() -> Dictionary:
	var out := {}
	for type_name in HFGeneratorSystem.known_types():
		var properties := {}
		for field_def in HFGeneratorSystem.settings_schema(type_name):
			var key := str(field_def["key"])
			var schema := {}
			var field_type := str(field_def.get("type", HFGeneratorSchema.TYPE_FLOAT))
			if field_type == HFGeneratorSchema.TYPE_BOOL:
				schema = {"type": "boolean"}
			elif field_type == HFGeneratorSchema.TYPE_ENUM:
				var options: Array = Array(field_def.get("options", []))
				schema = {
					"anyOf":
					[
						{"type": "string", "enum": options},
						{"type": "integer", "minimum": 0, "maximum": options.size() - 1},
					]
				}
			else:
				schema = {
					"type": "integer" if field_type == HFGeneratorSchema.TYPE_INT else "number"
				}
				if field_def.has("min"):
					schema["minimum"] = field_def["min"]
				if field_def.has("max"):
					schema["maximum"] = field_def["max"]
			if field_def.has("default"):
				schema["default"] = field_def["default"]
			var words := str(field_def.get("label", key))
			if str(field_def.get("tooltip", "")) != "":
				words += ": " + str(field_def["tooltip"])
			schema["description"] = words
			properties[key] = schema
		out[type_name] = {"type": "object", "properties": properties, "additionalProperties": false}
	return out
