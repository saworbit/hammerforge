@tool
class_name HFEntityDef
extends RefCounted

## Data-driven entity definition.  Loaded from JSON (entities.json) or
## user-provided files.  Used by the dock palette, brush-entity dropdown,
## and entity I/O system.

var classname := ""
var description := ""
var color := Color.WHITE
var is_brush_entity := false
## Key-value defaults shown in the inspector when placing.
var properties: Array[Dictionary] = []
## Optional scene path to instantiate instead of a plain DraftEntity.
var scene_path := ""


static func from_dict(data: Dictionary) -> HFEntityDef:
	var def := HFEntityDef.new()
	def.classname = str(data.get("id", data.get("class", data.get("classname", ""))))
	def.description = str(data.get("description", ""))
	var c = data.get("color", null)
	if c is Array and c.size() >= 3:
		def.color = Color(
			float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0
		)
	elif c is String:
		def.color = Color.from_string(c, Color.WHITE)
	def.is_brush_entity = bool(data.get("is_brush_entity", false))
	var props = data.get("properties", [])
	if props is Array:
		for p in props:
			if p is Dictionary:
				def.properties.append(p)
	def.scene_path = str(data.get("scene", ""))
	return def


func to_dict() -> Dictionary:
	var d: Dictionary = {
		"classname": classname,
		"description": description,
		"is_brush_entity": is_brush_entity,
	}
	if color != Color.WHITE:
		d["color"] = [color.r, color.g, color.b, color.a]
	if not properties.is_empty():
		d["properties"] = properties
	if scene_path != "":
		d["scene"] = scene_path
	return d


## Load all definitions from a JSON file (or return built-in defaults).
static func load_definitions(path: String) -> Array[HFEntityDef]:
	var defs: Array[HFEntityDef] = []
	if path == "" or not FileAccess.file_exists(path):
		return _built_in_defaults()
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return _built_in_defaults()
	var text = file.get_as_text()
	var data = JSON.parse_string(text)
	if data == null:
		return _built_in_defaults()
	var entries: Array = []
	if data is Dictionary:
		entries = data.get("entities", [])
		if entries.is_empty():
			for key in data.keys():
				var entry = data[key]
				if entry is Dictionary:
					var record = entry.duplicate(true)
					record["id"] = str(key)
					entries.append(record)
	elif data is Array:
		entries = data
	for entry in entries:
		if entry is Dictionary:
			defs.append(HFEntityDef.from_dict(entry))
	if defs.is_empty():
		return _built_in_defaults()
	return defs


## Built-in brush entity classes — always available even without entities.json.
static func _built_in_defaults() -> Array[HFEntityDef]:
	var defs: Array[HFEntityDef] = []
	var defaults: Array[Dictionary] = [
		{
			"classname": "func_detail",
			"description": "Non-structural brush (excluded from BSP/CSG visibility)",
			"is_brush_entity": true,
			"color": [0.0, 0.8, 0.8],
		},
		{
			"classname": "func_wall",
			"description": "Structural wall brush",
			"is_brush_entity": true,
			"color": [0.6, 0.6, 0.6],
		},
		{
			"classname": "trigger_once",
			"description": "Fires outputs once when activated",
			"is_brush_entity": true,
			"color": [1.0, 0.6, 0.0],
			"properties":
			[
				{
					"name": "filter_class",
					"type": "string",
					"label": "Filter Class",
					"default": "",
				},
				{
					"name": "start_disabled",
					"type": "bool",
					"label": "Start Disabled",
					"default": false,
				},
			],
		},
		{
			"classname": "trigger_multiple",
			"description": "Fires outputs every time activated",
			"is_brush_entity": true,
			"color": [1.0, 0.5, 0.0],
			"properties":
			[
				{
					"name": "filter_class",
					"type": "string",
					"label": "Filter Class",
					"default": "",
				},
				{
					"name": "start_disabled",
					"type": "bool",
					"label": "Start Disabled",
					"default": false,
				},
				{
					"name": "wait_time",
					"type": "float",
					"label": "Wait Time",
					"default": 1.0,
				},
			],
		},
	]
	for d in defaults:
		defs.append(HFEntityDef.from_dict(d))
	return defs


## Filter definitions to only brush entities.
static func filter_brush_entities(defs: Array[HFEntityDef]) -> Array[HFEntityDef]:
	var out: Array[HFEntityDef] = []
	for d in defs:
		if d.is_brush_entity:
			out.append(d)
	return out


## Filter definitions to only point entities.
static func filter_point_entities(defs: Array[HFEntityDef]) -> Array[HFEntityDef]:
	var out: Array[HFEntityDef] = []
	for d in defs:
		if not d.is_brush_entity:
			out.append(d)
	return out
