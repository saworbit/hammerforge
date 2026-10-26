@tool
extends RefCounted
## A command typed on the Console's line (#1696): `hollow 0.125`, `hollow
## thickness=0.125`, `move to floor`.
##
## The first words name the command by its id, its label or an alias. The rest
## are its values, by position in the order its bridge entry lists its params, or
## by name as `key=value`. A command the bridge runs is read into the request
## `hf_run_command` takes, and checked and run by the bridge's own code, so the
## line, a script and an agent read a command one way. One the bridge does not run
## takes no values and runs as the palette runs it.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFNameMatch = preload("hf_name_match.gd")
const HFCommandAliases = preload("hf_command_aliases.gd")

## Suggestions shown under the line, at most.
const MOST_SUGGESTIONS := 8

## Words for true and false, as a person types them.
const TRUE_WORDS := ["true", "yes", "on", "1"]
const FALSE_WORDS := ["false", "no", "off", "0"]

## The project's own aliases, read as the palette reads them, so the line knows
## the words the palette does (#1991). Tests point it elsewhere.
static var aliases_path := HFCommandAliases.USER_FILE


## The words of `line`: spaces or tabs part them, double quotes keep a value with
## spaces in it together, and braces or brackets keep JSON whole, quotes and all.
## A script pasted from elsewhere often parts them with tabs (#2015).
static func words(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var word := ""
	var quoted := false
	var started := false
	var depth := 0
	for letter in line:
		if depth > 0 or letter == "{" or letter == "[":
			word += letter
			started = true
			if letter == "{" or letter == "[":
				depth += 1
			elif letter == "}" or letter == "]":
				depth -= 1
		elif letter == '"':
			quoted = not quoted
			started = true
		elif (letter == " " or letter == "\t") and not quoted:
			if started:
				out.append(word)
			word = ""
			started = false
		else:
			word += letter
			started = true
	if started:
		out.append(word)
	return out


## The command `typed` starts with, as `{id, used}` where `used` is how many of
## its words name it, or {} for none. The longest name wins, so `move to floor`
## is Move to Floor and not a command called `move`.
static func command_of(typed: PackedStringArray) -> Dictionary:
	var names := _names()
	# As many words as the longest name has: six missed a seven word label (#2015).
	var longest := 1
	for name in names:
		longest = maxi(longest, str(name).split(" ", false).size())
	for used in range(mini(typed.size(), longest), 0, -1):
		var said := " ".join(typed.slice(0, used)).to_lower()
		if names.has(said):
			return {"id": names[said], "used": used}
		var joined := "_".join(typed.slice(0, used)).to_lower()
		if names.has(joined):
			return {"id": names[joined], "used": used}
	return {}


## Each command's names in lower case, to its id: id, label and aliases. A name
## two commands share goes to the first, as the registry lists them.
static func _names() -> Dictionary:
	var out := {}
	var lists := _name_lists()
	for id in HFCommandRegistry.dispatched_ids():
		for name in lists[id]:
			var key := str(name).to_lower()
			if not out.has(key):
				out[key] = id
	return out


## Read `line` into `{ok: true, id, params, bridge}`, with `params` as
## `hf_run_command` takes them, or a refusal `{ok: false, message, field}` naming
## the value it could not read. A required value the line leaves out is not a
## refusal here; `missing()` lists them, so the Console can ask.
static func read(line: String) -> Dictionary:
	var typed := words(line.strip_edges())
	if typed.is_empty():
		return _refused("Type a command.")
	var found := command_of(typed)
	if found.is_empty():
		var near := HFNameMatch.nearest(typed[0], _name_lists())
		var guess := " Did you mean %s?" % " or ".join(near) if not near.is_empty() else ""
		return _refused("There is no command '%s'.%s" % [typed[0], guess])
	var id: String = found["id"]
	var values := typed.slice(int(found["used"]))
	var spec := HFCommandRegistry.bridge(id)
	if spec.is_empty():
		if not values.is_empty():
			return _refused("%s takes no values." % HFCommandRegistry.label(id))
		return {"ok": true, "id": id, "params": {}, "bridge": false}
	var fields: Array = spec.get("params", [])
	var params := {}
	var next := 0
	for value in values:
		var field_def := {}
		var text := value
		var split := value.find("=")
		if split > 0 and _field(fields, value.substr(0, split)) != {}:
			field_def = _field(fields, value.substr(0, split))
			text = value.substr(split + 1)
		else:
			while next < fields.size() and params.has(str(fields[next]["key"])):
				next += 1
			if next >= fields.size():
				return _refused(_takes(id, fields))
			field_def = fields[next]
		var key := str(field_def["key"])
		if params.has(key):
			return _refused("%s is given twice." % key, key)
		var got := value_of(field_def, text)
		if not got["ok"]:
			return got
		params[key] = got["value"]
	return {"ok": true, "id": id, "params": params, "bridge": true}


## The field of `fields` called `key`, or {}.
static func _field(fields: Array, key: String) -> Dictionary:
	for field_def in fields:
		if str(field_def["key"]) == key:
			return field_def
	return {}


## "Hollow takes 1 value: thickness", for a line with one value too many.
static func _takes(id: String, fields: Array) -> String:
	var keys: PackedStringArray = []
	for field_def in fields:
		keys.append(str(field_def["key"]))
	if keys.is_empty():
		return "%s takes no values." % HFCommandRegistry.label(id)
	return (
		"%s takes %d value%s: %s."
		% [
			HFCommandRegistry.label(id),
			keys.size(),
			"" if keys.size() == 1 else "s",
			", ".join(keys)
		]
	)


## `text` as the value a bridge request carries for `field_def`: a number for a
## number, `[x, y, z]` for a vector typed `1,2,3`, an object for JSON. The bridge
## checks the value itself, its range and its options, so a refusal reads the same
## from the line as from an agent.
static func value_of(field_def: Dictionary, text: String) -> Dictionary:
	var key := str(field_def["key"])
	var type_name := str(field_def.get("type", "float"))
	match type_name:
		"float", "int":
			if not text.is_valid_float():
				return _refused("%s is a number, not '%s'." % [key, text], key)
			return {"ok": true, "value": float(text)}
		"bool":
			if text.to_lower() in TRUE_WORDS:
				return {"ok": true, "value": true}
			if text.to_lower() in FALSE_WORDS:
				return {"ok": true, "value": false}
			return _refused("%s is yes or no, not '%s'." % [key, text], key)
		"vec3", "cell":
			var size := 3 if type_name == "vec3" else 2
			var bare := text.trim_prefix("(").trim_suffix(")").trim_prefix("[").trim_suffix("]")
			var parts := bare.replace(" ", "").split(",")
			var numbers: Array = []
			for part in parts:
				if not part.is_valid_float():
					numbers.clear()
					break
				numbers.append(float(part))
			if numbers.size() != size:
				var shape := "x,y,z" if size == 3 else "x,z"
				return _refused("%s is %d numbers as %s, not '%s'." % [key, size, shape, text], key)
			return {"ok": true, "value": numbers}
		"enum", "axis", "layer":
			# By name, or by index from 0, as the bridge takes them.
			var picked: Variant = text
			if text.is_valid_int():
				picked = float(text)
			return {"ok": true, "value": picked}
		"object", "face":
			var json := JSON.new()
			if json.parse(text) == OK:
				return {"ok": true, "value": json.data}
			if type_name == "face" and text.is_valid_int():
				return {"ok": true, "value": float(text)}
			return _refused("%s is JSON, such as {\"steps\": 8}, not '%s'." % [key, text], key)
	return {"ok": true, "value": text}


## The required fields of `id` that `params` has no value for, in order.
static func missing(id: String, params: Dictionary) -> Array:
	var out: Array = []
	for field_def in HFCommandRegistry.bridge(id).get("params", []):
		if bool(field_def.get("required", false)) and not params.has(str(field_def["key"])):
			out.append(field_def)
	return out


## What the line asks for after reading `params` for `id`: every value when the
## line gave none, so `hollow` asks "Thickness <0.25>:", and otherwise only the
## required ones it left out. A script asks for nothing; it has `missing()`.
static func to_ask(id: String, params: Dictionary) -> Array:
	if params.is_empty():
		return Array(HFCommandRegistry.bridge(id).get("params", [])).duplicate()
	return missing(id, params)


## What the line asks for a missing value: "Position:", or "Thickness <0.25>:"
## with the value Enter takes.
static func prompt(field_def: Dictionary) -> String:
	var name := str(field_def["key"]).capitalize()
	if field_def.has("default"):
		return "%s <%s>:" % [name, str(field_def["default"])]
	return "%s:" % name


## The ids to offer for what has been typed so far: names that are the typed
## text first, then names that start with it, then the nearest, up to
## `MOST_SUGGESTIONS`.
static func suggestions(text: String) -> PackedStringArray:
	var typed := text.strip_edges().to_lower()
	var out: PackedStringArray = []
	if typed == "":
		return out
	var names := _names()
	if names.has(typed):
		out.append(names[typed])
	for name in names:
		if out.size() >= MOST_SUGGESTIONS:
			return out
		if str(name).begins_with(typed) and not out.has(names[name]):
			out.append(names[name])
	for id in HFNameMatch.nearest(typed, _name_lists(), MOST_SUGGESTIONS):
		if out.size() >= MOST_SUGGESTIONS:
			break
		if not out.has(id):
			out.append(id)
	return out


## Each command's names, by id, as `HFNameMatch.nearest()` takes them: its id, its
## label, and its aliases as the palette has them, the project's file's among them
## and a word the file gives another command taken away (#1991).
static func _name_lists() -> Dictionary:
	var aliases := HFCommandAliases.by_command(HFCommandAliases.read_user(aliases_path))
	var out := {}
	for id in HFCommandRegistry.dispatched_ids():
		out[id] = [id, HFCommandRegistry.label(id)] + Array(aliases.get(id, []))
	return out


## What a command takes, under the line as it is typed: "Hollow: thickness,
## 0.05 to 128, 0.25 if left out".
static func hint(id: String) -> String:
	var fields: Array = HFCommandRegistry.bridge(id).get("params", [])
	if fields.is_empty():
		return "%s: no values" % HFCommandRegistry.label(id)
	var parts: PackedStringArray = []
	for field_def in fields:
		var part := str(field_def["key"])
		if field_def.has("min") and field_def.has("max"):
			part += ", %s to %s" % [field_def["min"], field_def["max"]]
		elif field_def.has("options"):
			part += ", one of %s" % " ".join(PackedStringArray(field_def["options"]))
		else:
			part += ", " + _shape(str(field_def.get("type", "float")))
		if bool(field_def.get("required", false)):
			part += ", needed"
		elif field_def.has("default"):
			part += ", %s if left out" % str(field_def["default"])
		parts.append(part)
	return "%s: %s" % [HFCommandRegistry.label(id), "; ".join(parts)]


static func _shape(type_name: String) -> String:
	match type_name:
		"vec3":
			return "x,y,z"
		"cell":
			return "x,z in cells"
		"bool":
			return "yes or no"
		"axis":
			return "x, y or z"
		"layer":
			return "a paint layer's index or name"
		"object", "face":
			return "JSON"
		"string":
			return "text"
	return "a number"


## The line that reads back as `id` with `params`: the id, then each value by
## name. What the history keeps, and what a script holds.
static func line_for(id: String, params: Dictionary) -> String:
	var out: PackedStringArray = [id]
	for field_def in HFCommandRegistry.bridge(id).get("params", []):
		var key := str(field_def["key"])
		if params.has(key):
			out.append("%s=%s" % [key, _text_of(params[key])])
	return " ".join(out)


static func _text_of(value: Variant) -> String:
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(_text_of(item))
		return ",".join(parts)
	if value is Dictionary:
		return JSON.stringify(value)
	if value is float and is_equal_approx(value, roundf(value)) and absf(value) < 1e15:
		return str(int(value))
	if value is bool:
		return "yes" if value else "no"
	return _quoted(str(value))


static func _quoted(text: String) -> String:
	return '"%s"' % text if text.contains(" ") else text


static func _refused(message: String, field := "") -> Dictionary:
	return {"ok": false, "message": message, "field": field}
