@tool
extends RefCounted
class_name HFIOPresets

## Manages reusable I/O connection presets (macros).
## Presets define a pattern of outputs that can be applied from a source entity
## to one or more target entities in one action.
##
## Built-in presets cover common patterns (door+light+sound).
## User presets are saved to a JSON file alongside the project.

var root: Node3D
var _user_presets: Array = []
var _presets_path: String = ""

# Built-in presets — always available
const BUILTIN_PRESETS: Array = [
	{
		"name": "Door Open → Light + Sound",
		"description": "Trigger opens door, turns on light, plays sound",
		"connections":
		[
			{"output_name": "OnTrigger", "input_name": "Open", "target_tag": "door"},
			{"output_name": "OnTrigger", "input_name": "TurnOn", "target_tag": "light"},
			{"output_name": "OnTrigger", "input_name": "PlaySound", "target_tag": "sound"},
		],
		"builtin": true,
	},
	{
		"name": "Button → Door Toggle",
		"description": "Button press toggles a door open/closed",
		"connections":
		[
			{"output_name": "OnPressed", "input_name": "Toggle", "target_tag": "door"},
		],
		"builtin": true,
	},
	{
		"name": "Trigger → Alarm Sequence",
		"description": "Trigger activates alarm light + siren with staggered timing",
		"connections":
		[
			{
				"output_name": "OnTrigger",
				"input_name": "TurnOn",
				"target_tag": "alarm_light",
				"delay": 0.0
			},
			{
				"output_name": "OnTrigger",
				"input_name": "PlaySound",
				"target_tag": "siren",
				"delay": 0.5
			},
		],
		"builtin": true,
	},
	{
		"name": "Pickup → Effect + Remove",
		"description": "Pickup triggers an effect and removes itself (fire-once)",
		"connections":
		[
			{
				"output_name": "OnUse",
				"input_name": "PlayEffect",
				"target_tag": "effect",
				"fire_once": true
			},
			{"output_name": "OnUse", "input_name": "Kill", "target_tag": "self", "fire_once": true},
		],
		"builtin": true,
	},
	{
		"name": "Damage → Break + Particles",
		"description": "Entity takes damage, breaks and spawns particle effect",
		"connections":
		[
			{"output_name": "OnDamage", "input_name": "Break", "target_tag": "self"},
			{"output_name": "OnBreak", "input_name": "Start", "target_tag": "particles"},
		],
		"builtin": true,
	},
	{
		"name": "Timer → Cycle Lights",
		"description": "Timer periodically toggles a set of lights",
		"connections":
		[
			{"output_name": "OnTimer", "input_name": "Toggle", "target_tag": "light"},
		],
		"builtin": true,
	},
]


func _init(level_root: Node3D) -> void:
	root = level_root


## Load user presets from the editor user config directory.
func load_presets(path: String = "") -> void:
	if path != "":
		_presets_path = path
	if _presets_path == "":
		_presets_path = _default_presets_path()
	_user_presets.clear()
	if not FileAccess.file_exists(_presets_path):
		return
	var file = FileAccess.open(_presets_path, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	var data = JSON.parse_string(text)
	if data is Array:
		_user_presets = data


## Save user presets to file.
func save_presets() -> void:
	if _presets_path == "":
		_presets_path = _default_presets_path()
	# Ensure parent directory exists
	var dir_path = _presets_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file = FileAccess.open(_presets_path, FileAccess.WRITE)
	if not file:
		push_error("HFIOPresets: Cannot write to %s" % _presets_path)
		return
	file.store_string(JSON.stringify(_user_presets, "\t"))


## Get all presets (builtins + user).
func get_all_presets() -> Array:
	var result: Array = []
	for p in BUILTIN_PRESETS:
		result.append(p)
	for p in _user_presets:
		var d = p.duplicate(true)
		d["builtin"] = false
		result.append(d)
	return result


## Get only user-defined presets.
func get_user_presets() -> Array:
	return _user_presets.duplicate(true)


## Add a new user preset.
func add_user_preset(name: String, description: String, connections: Array) -> void:
	(
		_user_presets
		. append(
			{
				"name": name,
				"description": description,
				"connections": connections.duplicate(true),
				"builtin": false,
			}
		)
	)
	save_presets()


## Remove a user preset by index (in the user array, not combined).
func remove_user_preset(index: int) -> void:
	if index < 0 or index >= _user_presets.size():
		return
	_user_presets.remove_at(index)
	save_presets()


## Save current connections from an entity as a new user preset.
func save_entity_as_preset(entity: Node, preset_name: String, description: String = "") -> bool:
	if not entity or not root or not root.entity_system:
		return false
	var outputs = root.entity_system.get_entity_outputs(entity)
	if outputs.is_empty():
		return false
	var connections: Array = []
	for conn in outputs:
		if not (conn is Dictionary):
			continue
		var entry: Dictionary = {
			"output_name": str(conn.get("output_name", "")),
			"input_name": str(conn.get("input_name", "")),
			"target_tag": str(conn.get("target_name", "")),
		}
		var delay = float(conn.get("delay", 0.0))
		if delay > 0.0:
			entry["delay"] = delay
		if bool(conn.get("fire_once", false)):
			entry["fire_once"] = true
		var param = str(conn.get("parameter", ""))
		if param != "":
			entry["parameter"] = param
		connections.append(entry)
	add_user_preset(preset_name, description, connections)
	return true


## Apply a preset from a source entity to named targets.
## target_map: { "tag" -> "actual_entity_name" } — maps preset target_tags to real entity names.
## If target_tag is "self", uses the source entity's name.
func apply_preset(source_entity: Node, preset: Dictionary, target_map: Dictionary) -> int:
	if not source_entity or not root or not root.entity_system:
		return 0
	var connections = preset.get("connections", [])
	if connections.is_empty():
		return 0
	var count := 0
	var source_name: String = source_entity.name
	for conn in connections:
		if not (conn is Dictionary):
			continue
		var output_name = str(conn.get("output_name", ""))
		var input_name = str(conn.get("input_name", ""))
		var tag = str(conn.get("target_tag", ""))
		if output_name == "" or input_name == "":
			continue
		var actual_target: String = ""
		if tag == "self":
			actual_target = source_name
		else:
			actual_target = str(target_map.get(tag, tag))
		if actual_target == "":
			continue
		var delay = float(conn.get("delay", 0.0))
		var fire_once = bool(conn.get("fire_once", false))
		var parameter = str(conn.get("parameter", ""))
		root.entity_system.add_entity_output(
			source_entity, output_name, actual_target, input_name, parameter, delay, fire_once
		)
		count += 1
	return count


## Get the target tags used by a preset (for UI to prompt user for mapping).
func get_preset_target_tags(preset: Dictionary) -> Array:
	var tags: Array = []
	var connections = preset.get("connections", [])
	for conn in connections:
		if not (conn is Dictionary):
			continue
		var tag = str(conn.get("target_tag", ""))
		if tag != "" and tag != "self" and not tags.has(tag):
			tags.append(tag)
	return tags


## Default path in the editor config dir so presets stay out of the project repo.
static func _default_presets_path() -> String:
	if Engine.is_editor_hint():
		var cfg_dir = EditorInterface.get_editor_paths().get_config_dir()
		return cfg_dir.path_join("hammerforge_io_presets.json")
	# Fallback for runtime / tests — use user:// so it never lands in res://
	return "user://hammerforge_io_presets.json"
