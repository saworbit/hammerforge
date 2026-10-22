extends "res://tests/mcp/mcp_dispatcher_case.gd"
## Every input of every bridge tool and palette command, sent the wrong kind of
## value straight to the editor, past the checks the server makes (#1647).
##
## An agent types every value from a description, and off by one, the wrong type
## and a stale id are its everyday mistakes. Godot's JSON parser reads `1e999` as
## an infinite number with only a warning, so anything that writes to the socket
## itself can deliver one. A script error reaches the agent as `internal_error`,
## which it cannot act on; a refusal that names the field it can fix.
##
## The cases are generated: the tools' inputs from `hammerforge_mcp/
## tool_schemas.json`, which a pytest holds to the server, and the commands'
## params from `HFCommandRegistry`. A new input is swept with no edit here.
##
## Every case must raise no script error and either succeed or be refused. A
## refusal must name the field, or name what it could not find, and leave the
## level and the undo history as they were.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const SCHEMAS := "res://hammerforge_mcp/tool_schemas.json"

## Tools the sweep leaves out, and why.
const SKIPPED_TOOLS := {
	"hf_bake": "writes a scene to disk and takes seconds; its one input is a bool",
	"hf_viewport_screenshot": "needs a drawn viewport, which a headless run has not",
	"hf_create_starter": "makes a new level; its only input is operation_id",
}

## Arguments each tool needs before a bad value can reach the input under test,
## over the level `_build()` makes. A tool missing here that has required inputs
## fails the sweep, so a new one cannot slip past it.
const BASE := {
	"hf_place_brush": {"size": [1, 1, 1], "position": [0, 1, 6]},
	"hf_transform_brush": {"brush_id": "b", "position": [0, 1, 9]},
	"hf_resize_brush": {"brush_id": "b", "size": [2, 2, 2]},
	"hf_delete_brush": {"brush_id": "b"},
	"hf_extrude_face": {"brush_id": "b", "face": "+y", "distance": 1},
	"hf_assign_material": {"brush_id": "b", "material": "palette:1"},
	"hf_set_spawn": {"position": [0, 0, 0]},
	"hf_place_entity": {"entity_class": "light_point", "position": [0, 2, 0]},
	"hf_transform_entity": {"entity": "Entities/lamp", "position": [1, 2, 0]},
	"hf_set_entity_properties": {"entity": "Entities/lamp", "properties": {}},
	"hf_delete_entity": {"entity": "Entities/lamp"},
	"hf_add_entity_output":
	{
		"entity": "Entities/lamp",
		"output_name": "OnTimer",
		"target_name": "lamp",
		"input_name": "Toggle",
	},
	"hf_remove_entity_output": {"entity": "Entities/lamp", "index": 0},
	"hf_set_brush_entity": {"brush_ids": ["b"], "entity_class": "trigger_once"},
	"hf_set_cordon": {"enabled": true},
	"hf_remove_cordon": {"index": 0},
	"hf_measure": {"items": ["a", "b"]},
	"hf_batch": {"ops": [{"tool": "hf_delete_brush", "params": {"brush_id": "b"}}]},
	"hf_run_command": {"command": "move_to_floor", "brush_ids": ["b"]},
}

## Parameters a command needs before a bad value can reach the one under test.
const COMMAND_BASE := {
	"clip_to_face": {"plane_brush_id": "a", "plane_face": "+x"},
	"create_arch": {"type": "stairs", "position": [20, 0, 0]},
	"update_structure": {"generator_id": "gen_made_up"},
	"detach_structure": {"generator_id": "gen_made_up"},
	"place_prefab": {"prefab": "no_such_prefab", "position": [30, 0, 0]},
	"paint_ramp": {"from": [0, 0], "to": [3, 2]},
	"paint_raise": {"from": [0, 0], "to": [3, 2], "height": 2.0},
	"paint_room": {"at": [10, 10]},
	"paint_confirm_connector": {"from": [0, 0]},
	"replace_material": {"from": "palette:1", "to": "palette:2"},
}

## Failures waiting on a fix, as "case": issue.
const KNOWN := {}

## The longest string a case sends.
const LONG := 10000

## The level the last case left as it found it, reused by the next case, since
## most cases are refused and building a level for each took a minute.
var _kept: LevelRoot = null


## Every tool the schema file lists, less the skipped ones.
static func _tools() -> Array:
	var schemas := _schemas()
	var names: Array = []
	for name in schemas:
		if not SKIPPED_TOOLS.has(name):
			names.append(name)
	names.sort()
	return names


static func _schemas() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SCHEMAS))
	return parsed if parsed is Dictionary else {}


func test_the_schema_file_lists_every_tool_and_the_registry_every_command():
	var schemas := _schemas()
	assert_gt(schemas.size(), 30, "the tools are read from %s" % SCHEMAS)
	for name in schemas:
		var schema: Dictionary = schemas[name]
		var required: Array = schema.get("required", [])
		if not required.is_empty() and not SKIPPED_TOOLS.has(name):
			assert_true(BASE.has(name), "%s needs a BASE entry for %s" % [name, required])
	assert_gt(HFCommandRegistry.bridge_ids().size(), 19, "the commands come from the registry")


func test_every_tool_input_takes_bad_values(tool = use_parameters(_tools())):
	var schema: Dictionary = _schemas()[tool]
	var properties: Dictionary = schema.get("properties", {})
	for key in properties:
		if key == "operation_id":
			continue
		for bad in _bad_values(properties[key]):
			var args: Dictionary = (BASE.get(tool, {}) as Dictionary).duplicate(true)
			args[key] = bad
			await _try(tool, args, "%s.%s = %s" % [tool, key, _short(bad)])


func test_every_command_param_takes_bad_values(command = use_parameters(_commands())):
	var spec := HFCommandRegistry.bridge(command)
	for field_def in spec.get("params", []):
		var key := str(field_def["key"])
		for bad in _bad_values(_field_schema(field_def)):
			var params: Dictionary = (COMMAND_BASE.get(command, {}) as Dictionary).duplicate(true)
			params[key] = bad
			var args := {"command": command, "brush_ids": _targets_for(spec), "params": params}
			await _try("hf_run_command", args, "%s params.%s = %s" % [command, key, _short(bad)])


func test_every_command_takes_bad_targets_and_params(command = use_parameters(_commands())):
	var spec := HFCommandRegistry.bridge(command)
	var params: Dictionary = COMMAND_BASE.get(command, {})
	var many: Array = []
	for i in LONG:
		many.append("id_%d" % i)
	var targets := {
		"none": [],
		"made_up": ["made_up"],
		"twice": ["a", "a"],
		"deleted": ["gone"],
		"ten thousand": many,
		"not a list": "a",
		"numbers": [1, 2],
	}
	for label in targets:
		var args := {"command": command, "brush_ids": targets[label], "params": params}
		await _try("hf_run_command", args, "%s brush_ids %s" % [command, label])
	for whole in ["params", [], 7]:
		var args := {"command": command, "brush_ids": _targets_for(spec), "params": whole}
		await _try("hf_run_command", args, "%s params = %s" % [command, _short(whole)])


func test_an_operation_id_of_the_wrong_kind_is_refused():
	for bad in ["", "has spaces", "x".repeat(200), 7, true, [], {}]:
		var args: Dictionary = (BASE["hf_place_brush"] as Dictionary).duplicate()
		args["operation_id"] = bad
		await _try("hf_place_brush", args, "operation_id = %s" % _short(bad))


static func _commands() -> Array:
	return Array(HFCommandRegistry.bridge_ids())


## The ids a command's targets rule asks for, from the level's two brushes.
static func _targets_for(spec: Dictionary) -> Array:
	var rule: Dictionary = spec.get("targets", {})
	var low := int(rule.get("min", 0))
	var high := int(rule.get("max", -1))
	var ids: Array = ["a"] if low > 0 or high != 0 else []
	if low > 1:
		ids.append("b")
	return ids


## A registry param in the shape of a JSON schema property, for `_bad_values()`.
static func _field_schema(field_def: Dictionary) -> Dictionary:
	match str(field_def.get("type", "float")):
		"float":
			return _with_bounds({"type": "number"}, field_def)
		"int":
			return _with_bounds({"type": "integer"}, field_def)
		"bool":
			return {"type": "boolean"}
		"enum":
			return {"enum": field_def.get("options", ["?"])}
		"vec3":
			return {"type": "array", "minItems": 3, "maxItems": 3, "items": {"type": "number"}}
		"cell":
			return {"type": "array", "minItems": 2, "maxItems": 2, "items": {"type": "integer"}}
		"axis":
			return {"enum": ["x", "y", "z"]}
		"face":
			return {"face": true}
		"layer":
			return {"layer": true}
		"object":
			return {"type": "object"}
	return {"type": "string"}


static func _with_bounds(schema: Dictionary, field_def: Dictionary) -> Dictionary:
	if field_def.has("min"):
		schema["minimum"] = field_def["min"]
	if field_def.has("max"):
		schema["maximum"] = field_def["max"]
	return schema


## Wrong values for a property: past its bounds, of another type, and the
## extremes. A value that happens to be right is fine; the rule is what happens.
static func _bad_values(prop: Dictionary) -> Array:
	var schema := prop
	for option in prop.get("anyOf", []):
		if option is Dictionary and option.get("type") != "null":
			schema = option
			break
	if prop.get("face", false):
		return [999999, "+w", {"normal": [0, 0, 0]}, -1, true, null]
	if prop.get("layer", false):
		return ["no_such_layer", -1, 999, true, []]
	if schema.has("enum") or prop.has("enum"):
		return ["no_such_option", 99, -1, true, null, []]
	var values: Array = []
	match str(schema.get("type", "")):
		"number", "integer":
			values = [0, -1, 1e308, -1e308, "1", true, null, [], {}]
			if schema.has("minimum"):
				values.append(float(schema["minimum"]) - 1.0)
			if schema.has("maximum"):
				values.append(float(schema["maximum"]) + 1.0)
			if schema.has("exclusiveMinimum"):
				values.append(schema["exclusiveMinimum"])
		"string":
			values = ["", "x".repeat(LONG), 7, true, null, [], {}]
		"boolean":
			values = ["yes", 1, null, [], {}]
		"array":
			values = ["x", 7, {}, [], [1e308, 1e308, 1e308], ["a", "b", "c"], [null]]
			if schema.has("minItems"):
				values.append(_list_of(int(schema["minItems"]) - 1))
			if schema.has("maxItems"):
				values.append(_list_of(int(schema["maxItems"]) + 1))
		"object":
			values = ["x", 7, [], {"no_such_key": 1}]
		_:
			values = [null, "x", 7, [], {}]
	return values


static func _list_of(count: int) -> Array:
	var out: Array = []
	for i in maxi(count, 0):
		out.append(1)
	return out


static func _short(value) -> String:
	var text := JSON.stringify(value)
	return text if text.length() <= 40 else text.left(37) + "..."


## A level with brushes a and b, the prototype palette, a lamp and a cordon, and
## the brush the "deleted" case names gone.
func _build() -> LevelRoot:
	var level := make_level_with_palette()
	level.create_brush_from_info(
		{"brush_id": "a", "size": Vector3(4, 4, 4), "center": Vector3(0, 2, 0)}
	)
	level.create_brush_from_info(
		{"brush_id": "b", "size": Vector3(4, 4, 4), "center": Vector3(8, 2, 0)}
	)
	level.create_brush_from_info(
		{"brush_id": "gone", "size": Vector3(1, 1, 1), "center": Vector3(0, 2, 8)}
	)
	level.delete_brush_by_id("gone")
	var lamp := await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 3, 0], "name": "lamp"}
	)
	assert_true(lamp.get("ok", false), "fixture: the lamp: %s" % str(lamp))
	return level


## Send one case and hold it to the rule, on the level the last case left as it
## found it, or a new one.
func _try(method: String, args: Dictionary, label: String) -> void:
	var level := _kept
	_kept = null
	if level == null or not is_instance_valid(level):
		_leave()
		await get_tree().process_frame
		level = await _build()
	var before := snapshot(level)
	var errors_before := get_errors().size()
	var r := await call_tool(method, args)
	var errors: Array = get_errors().slice(errors_before)
	if KNOWN.has(label):
		for e in errors:
			e.handled = true
		pending("%s: %s" % [label, KNOWN[label]])
		return
	var described: Array = []
	for e in errors:
		described.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	assert_eq(described, [], "%s raised no script error" % label)
	if not r.get("ok", false):
		var error: Dictionary = r.get("error", {})
		var code := str(error.get("code", ""))
		var details: Dictionary = error.get("details", {})
		assert_ne(code, HFMcpProtocol.E_INTERNAL, "%s: not internal" % label)
		assert_ne(str(error.get("message", "")), "", "%s: the refusal says why" % label)
		# A bad value names its field. Something the level has not got names what
		# was looked for. A refusal of the level's own state, such as no painted
		# cells to raise, has its message alone.
		if code == HFMcpProtocol.E_INVALID_ARGUMENT:
			assert_true(details.has("param"), "%s: names the field: %s" % [label, str(error)])
		elif code.ends_with("_not_found") or code.begins_with("unknown_"):
			assert_false(details.is_empty(), "%s: names what is missing: %s" % [label, str(error)])
		assert_eq(snapshot(level), before, "%s: refused, and nothing changed" % label)
	if not r.get("ok", false) and snapshot(level) == before:
		_kept = level


func after_each() -> void:
	_kept = null
	_leave()
	super.after_each()


func _leave() -> void:
	if host.scene and is_instance_valid(host.scene):
		var scene: Node = host.scene
		host.scene = null
		scene.get_parent().remove_child(scene)
		scene.free()
