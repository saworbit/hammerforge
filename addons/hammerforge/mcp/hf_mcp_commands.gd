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
const HFPluginPrefabCommands = preload("../plugin_prefab_commands.gd")
const HFOpResult = preload("../hf_op_result.gd")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## What `hf_run_command` takes besides `operation_id`, which the dispatcher reads.
const ARGUMENTS := ["command", "brush_ids", "entities", "params"]
const AXES := ["x", "y", "z"]

## The dispatcher's tools, for the brush and entity readers, face selectors and
## brushes as plain data.
var tools: HFMcpTools


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
		"float":
			var read := HFMcpProtocol.read_number(given, key, true)
			if not read["ok"]:
				return read
			return _in_range(field_def, key, read["value"])
		"int":
			var read := HFMcpProtocol.read_number(given, key, true)
			if not read["ok"]:
				return read
			var number: float = read["value"]
			if number != floorf(number):
				return HFMcpProtocol.invalid(key, "%s must be a whole number" % key)
			var ranged := _in_range(field_def, key, number)
			if ranged["ok"]:
				ranged["value"] = int(number)
			return ranged
		"bool":
			return HFMcpProtocol.read_bool(given, key, false)
		"enum", "axis":
			var options: Array = AXES if type_name == "axis" else _options(field_def)
			var value = given[key]
			if not (value is String) or not options.has(value):
				return HFMcpProtocol.invalid(key, "%s is one of %s" % [key, ", ".join(options)])
			return {"ok": true, "value": value}
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
	# A face selector is checked by the form, against the brush it names.
	return {"ok": true, "value": given[key]}


static func _in_range(field_def: Dictionary, key: String, number: float) -> Dictionary:
	var too_low := field_def.has("min") and number < float(field_def["min"])
	var too_high := field_def.has("max") and number > float(field_def["max"])
	if too_low or too_high:
		return HFMcpProtocol.invalid(
			key,
			(
				"%s must be from %s to %s"
				% [key, _number_text(field_def.get("min")), _number_text(field_def.get("max"))]
			)
		)
	return {"ok": true, "value": number}


static func _number_text(value) -> String:
	if value == null:
		return "any"
	var number := float(value)
	return str(int(number)) if number == floorf(number) else str(number)


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
			changed.append(tools.brush_dict(root, brushes_after[brush_id], false))
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
	result["warnings"] = warnings
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


## A structure's settings: each key one its type has, each value of the field's
## type and inside its range, an enum by index or by its label. The rest take
## their defaults. `HFGeneratorSchema.merge()` would turn a string into the
## default and drop an unknown key, both quietly; the dock cannot send either, an
## agent can, and is told.
func read_settings(type_name: String, given) -> Dictionary:
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
		var value = given[key]
		var field_type := str(field_def.get("type", HFGeneratorSchema.TYPE_FLOAT))
		if field_type == HFGeneratorSchema.TYPE_BOOL:
			if not (value is bool):
				return HFMcpProtocol.invalid(param, "%s is true or false" % key)
		elif field_type == HFGeneratorSchema.TYPE_ENUM:
			var options: Array = Array(field_def.get("options", []))
			var index := _option_index(options, value)
			if index < 0:
				return HFMcpProtocol.invalid(
					param,
					(
						"%s is one of %s, or its index from 0"
						% [key, ", ".join(PackedStringArray(options))]
					)
				)
			value = index
		else:
			if not (value is float or value is int) or not is_finite(float(value)):
				return HFMcpProtocol.invalid(param, "%s must be a number" % key)
			if field_type == HFGeneratorSchema.TYPE_INT and float(value) != floorf(float(value)):
				return HFMcpProtocol.invalid(param, "%s must be a whole number" % key)
			var ranged := _in_range(field_def, str(key), float(value))
			if not ranged["ok"]:
				return _under(ranged, param)
		provided[str(key)] = value
	return {"ok": true, "value": HFGeneratorSchema.merge(schema, provided)}


static func _option_index(options: Array, value) -> int:
	if (value is float or value is int) and not (value is bool):
		var number := float(value)
		if number == floorf(number) and number >= 0 and number < options.size():
			return int(number)
		return -1
	if value is String:
		for i in options.size():
			if str(options[i]).to_lower() == (value as String).to_lower():
				return i
	return -1


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


func check_cycle_variant(root: Node, targets: Dictionary, _args: Dictionary) -> Dictionary:
	var piece := _prefab_piece(targets, HFPluginPrefabCommands.INSTANCE_META)
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
	var piece := _prefab_piece(targets, HFPluginPrefabCommands.SOURCE_META)
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
# hf_list_commands
# ---------------------------------------------------------------------------


## Every command the bridge runs, as the agent reads it: what it does, what it
## takes, and its parameters as JSON Schema.
func listing() -> Array:
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
		for field_def in spec.get("params", []):
			if str(field_def.get("options_from", "")) == "generator_types":
				entry["settings_by_type"] = settings_by_type()
		out.append(entry)
	return out


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
