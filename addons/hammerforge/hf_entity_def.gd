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
## The output names this entity class fires, and the input names it answers to.
## The wiring form offers these, so the preset vocabulary and the definitions can
## agree instead of a mapper having to know the strings (#613).
var outputs: Array = []
var inputs: Array = []
## Optional Godot node class to build for this entity in a playtest export, when
## the definition names one other than a plain marker.
var node_class := ""

## Optional per-project overlay. Entries with the same classname replace plugin defs.
const PROJECT_DEFINITIONS_PATH := "res://hammerforge_entities.json"

## The keys this model has a field for. Everything else in a definition file is
## carried through `to_dict()` untouched, because a definition file is data and a
## whitelist in the middle of it drops features in silence. Two had already gone
## that way: `preview`, which is how an entity draws itself in the viewport, and
## `input_methods`, which is how a class says an input names an engine method.
## Both were written, both were read, and neither survived the trip to the level
## root that reads them.
const MODELLED_KEYS := [
	"id",
	"classname",
	"class",
	"description",
	"color",
	"is_brush_entity",
	"properties",
	"scene",
	"outputs",
	"inputs",
]

## The entry this definition was read from, so `to_dict()` can put back what this
## model does not model.
var source_entry: Dictionary = {}


## The class name a definition entry goes by: `id`, then `classname`, then
## `class`, stripped. Every reader asks here, so the class dropdown, the palette
## and the duplicate check cannot key one entry on two names (#1452).
##
## `classname` before `class`. `to_dict()` writes both, and reading `class` first
## meant a definition that named a node class could not survive its own round
## trip - "light_point" came back as "OmniLight3D".
##
## Stripped, because the classname is the identity of the entity class in three
## places at once: the key in LevelRoot.entity_definitions, the row in the class
## dropdown, and the "classname" field written into the exported `.map`, which is
## what the target engine reads to decide what the entity is. A blank one is a
## malformed entity in the `.map` and a blank row in the dropdown that cannot be
## told from another blank row. Stripped also means "door" and "door " are one
## class rather than two, so the overlay and the base agree.
static func classname_of(entry: Dictionary) -> String:
	return str(entry.get("id", entry.get("classname", entry.get("class", "")))).strip_edges()


static func from_dict(data: Dictionary) -> HFEntityDef:
	var def := HFEntityDef.new()
	def.classname = classname_of(data)
	# The Godot node class this entity stands for, read only when the entry
	# identifies itself some other way. In an array-form file `class` *is* the
	# classname, and instantiating that would be nonsense.
	if data.has("id") or data.has("classname"):
		def.node_class = str(data.get("class", "")).strip_edges()
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
	def.outputs = _string_list(data.get("outputs", []))
	def.inputs = _string_list(data.get("inputs", []))
	def.source_entry = data.duplicate(true)
	return def


## Names only, stripped, in order, without blanks or repeats.
static func _string_list(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for item in value:
		var name := str(item).strip_edges()
		if name != "" and not (name in out):
			out.append(name)
	return out


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	# What the file carried and this model has no field for. The modelled keys are
	# written below and win, because `from_dict()` normalises several of them and
	# the raw ones would undo that -- `classname` is resolved from three possible
	# spellings, and a definition that named a node class in `class` came back as
	# that class the last time the raw value was read first.
	for key in source_entry:
		if key in MODELLED_KEYS:
			continue
		d[key] = source_entry[key]
	d["classname"] = classname
	d["description"] = description
	d["is_brush_entity"] = is_brush_entity
	if color != Color.WHITE:
		d["color"] = [color.r, color.g, color.b, color.a]
	if not properties.is_empty():
		d["properties"] = properties
	if scene_path != "":
		d["scene"] = scene_path
	if not outputs.is_empty():
		d["outputs"] = outputs
	if not inputs.is_empty():
		d["inputs"] = inputs
	if node_class != "":
		d["class"] = node_class
	return d


## Turn a definitions file into its entries. The one reader behind all three
## loaders, so the shapes of file they accept and the class name an entry goes by
## cannot drift apart again (#1452). Each loader decides what to do with the
## warnings and whether to fall back.
##
## `entries`: every dictionary entry with a class name, in file order, as the file
## wrote it. An entry in the `{"name": {...}}` form gets its key as `id`.
## `warnings`: what the author of the file should hear about.
## `failure`: "" when the file was read; otherwise "missing", "unreadable" or
## "not_json", and nothing else is filled in.
static func _read_entries(path: String) -> Dictionary:
	var result := {"entries": [], "warnings": [], "failure": ""}
	if path == "" or not FileAccess.file_exists(path):
		result["failure"] = "missing"
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		result["failure"] = "unreadable"
		return result
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		result["failure"] = "not_json"
		return result
	var warnings: Array = result["warnings"]
	var listed: Array = []
	if data is Dictionary:
		# Read before assigning. `listed` is a typed local, so a file that parses
		# with an "entities" key of the wrong type used to be a runtime error
		# here — and GDScript has no exception handling, so the function unwound
		# past every fallback below it and the caller got nothing. A valid JSON
		# file with one key of the wrong type is the most likely hand-edit
		# mistake, not the least.
		var raw_entries = data.get("entities", [])
		if raw_entries is Array:
			listed = raw_entries
		elif raw_entries != null:
			warnings.append(
				(
					"HammerForge: 'entities' in '%s' is a %s, not a list"
					% [path, type_string(typeof(raw_entries))]
				)
			)
		if listed.is_empty():
			for key in data.keys():
				var entry = data[key]
				if entry is Dictionary:
					var record: Dictionary = entry.duplicate(true)
					record["id"] = str(key)
					listed.append(record)
	elif data is Array:
		listed = data
	var entries: Array = result["entries"]
	var skipped := 0
	var seen_classnames: Dictionary = {}
	for entry in listed:
		if not (entry is Dictionary):
			skipped += 1
			continue
		var entry_classname := classname_of(entry)
		if entry_classname == "":
			skipped += 1
			warnings.append(
				"HammerForge: skipping entity definition with no classname in '%s'" % path
			)
			continue
		if seen_classnames.has(entry_classname):
			# load_entity_definitions() writes these into one dictionary key,
			# so the second silently wins. Naming it turns a mistake that
			# vanishes into one the author can fix. This is the file's own
			# duplicates, not the project overlay replacing a plugin
			# definition of the same name, which is the intended behaviour.
			warnings.append(
				"HammerForge: '%s' is defined more than once in '%s'" % [entry_classname, path]
			)
		seen_classnames[entry_classname] = true
		entries.append(entry)
	if skipped > 0:
		warnings.append("HammerForge: skipped %d malformed entries in '%s'" % [skipped, path])
	return result


## Load all definitions from a JSON file (or return built-in defaults).
static func load_definitions(path: String) -> Array[HFEntityDef]:
	var read := _read_entries(path)
	match str(read["failure"]):
		"missing":
			return _built_in_defaults()
		"unreadable":
			push_warning(
				(
					"HammerForge: cannot open entity definitions at '%s' — using built-in defaults"
					% path
				)
			)
			return _built_in_defaults()
		"not_json":
			push_error(
				(
					"HammerForge: failed to parse entities JSON at '%s' — check for syntax errors. Using built-in defaults"
					% path
				)
			)
			return _built_in_defaults()
	for warning in read["warnings"]:
		push_warning(warning)
	var defs: Array[HFEntityDef] = []
	for entry in read["entries"]:
		defs.append(HFEntityDef.from_dict(entry))
	if defs.is_empty():
		push_warning(
			(
				"HammerForge: no valid entity definitions found in '%s' — using built-in defaults"
				% path
			)
		)
		return _built_in_defaults()
	return defs


## Load definitions from a file without falling back to built-ins.
## Missing or invalid files return an empty array. What the file says wrong about
## itself is still said, as `load_definitions()` says it about the plugin file.
static func load_definitions_from_file(path: String) -> Array[HFEntityDef]:
	var defs: Array[HFEntityDef] = []
	var read := _read_entries(path)
	for warning in read["warnings"]:
		push_warning(warning)
	for entry in read["entries"]:
		defs.append(from_dict(entry))
	return defs


## Read the raw JSON entries from a definitions file, normalising the classname
## onto an "id" key. Unlike load_definitions() this keeps every key the file
## carries, so the dock palette still gets its labels, previews and categories.
## Silent, because the typed loader reads the same file and says what is wrong.
static func load_raw_entries(path: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in _read_entries(path)["entries"]:
		var record: Dictionary = (entry as Dictionary).duplicate(true)
		record["id"] = classname_of(record)
		entries.append(record)
	return entries


## The raw entries a project actually sees: plugin file overlaid with the
## project file, same classname replacing the plugin entry.
static func load_merged_raw_entries(
	plugin_path: String, project_path: String = PROJECT_DEFINITIONS_PATH
) -> Array[Dictionary]:
	var by_name: Dictionary = {}
	var order: Array[String] = []
	for entry in load_raw_entries(plugin_path):
		var key := str(entry.get("id", ""))
		if not by_name.has(key):
			order.append(key)
		by_name[key] = entry
	for entry in load_raw_entries(project_path):
		var key := str(entry.get("id", ""))
		if not by_name.has(key):
			order.append(key)
		by_name[key] = entry
	var out: Array[Dictionary] = []
	for key in order:
		out.append(by_name[key])
	return out


## Overlay project defs onto plugin defs. Same classname replaces the plugin entry.
static func merge_definitions(
	base: Array[HFEntityDef], overlay: Array[HFEntityDef]
) -> Array[HFEntityDef]:
	var by_name: Dictionary = {}
	for def in base:
		if def and def.classname != "":
			by_name[def.classname] = def
	for def in overlay:
		if def and def.classname != "":
			by_name[def.classname] = def
	var out: Array[HFEntityDef] = []
	for key in by_name.keys():
		out.append(by_name[key])
	return out


static func load_merged_definitions(
	plugin_path: String, project_path: String = PROJECT_DEFINITIONS_PATH
) -> Array[HFEntityDef]:
	var base := load_definitions(plugin_path)
	var overlay := load_definitions_from_file(project_path)
	if overlay.is_empty():
		return base
	return merge_definitions(base, overlay)


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
