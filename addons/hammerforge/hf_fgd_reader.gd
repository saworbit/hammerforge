@tool
extends RefCounted
## Entity classes from an FGD file (#1721), as the entries an `entities.json`
## holds, so `HFEntityDef` reads them the way it reads its own.
##
## A game's entity set is often written down as an FGD: each class with its base
## classes, size, colour, typed properties with defaults, choices and flags, and
## its inputs and outputs. Point and solid classes become point and brush entity
## classes; a base class lends what it has to the classes that name it and is not
## one itself. `size()` becomes the gizmo box, `color()` the class colour. What
## this reader has no use for, a model, a sprite, an editor helper, a directive
## for another editor, is skipped, and each file says once how much it skipped and
## where the first was. A file never fails to load for it.

## Map units in a metre, as `.map` files measure, for `size()`.
const UNITS_PER_METRE := 32.0
## The class kinds that are a point entity. `@SolidClass` is a brush entity, and
## `@BaseClass` is no class of its own.
const POINT_KINDS := [
	"pointclass", "npcclass", "keyframeclass", "moveclass", "filterclass", "extendclass"
]
const SOLID_KIND := "solidclass"
const BASE_KIND := "baseclass"
## Directives other editors read and this one has nothing to do with. They are
## skipped without a word, since every FGD for those editors has them.
const QUIET_DIRECTIVES := [
	"mapsize", "materialexclusion", "autovisgroup", "version", "gridnav", "exclude"
]
## How deep `@include` may nest, so a file that includes itself ends.
const MAX_INCLUDE_DEPTH := 8
## FGD property types and the type a definition gives them. Anything else reads
## as text, which is what it is in a `.map`.
const TYPES := {
	"string": "string",
	"integer": "int",
	"float": "float",
	"boolean": "bool",
	"choices": "enum",
	"flags": "flags",
	"color255": "color",
	"color1": "color",
}

## Each file read: `{"file": String, "skipped": int, "first_line": int,
## "first": String}`, for the one warning a file gives.
var _skips: Dictionary = {}
var _warnings: Array = []


## Read the FGD at `path`: `{"entries": Array, "warnings": Array, "failure":
## String}`, the shape `HFEntityDef._read_entries()` gives. `failure` is
## "missing" or "unreadable" when there is nothing to read, and "" otherwise.
static func read_file(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {"entries": [], "warnings": [], "failure": "missing"}
	var text := FileAccess.get_file_as_string(path)
	if text == "" and FileAccess.get_open_error() != OK:
		return {"entries": [], "warnings": [], "failure": "unreadable"}
	var reader = _new_reader()
	var classes: Dictionary = {}
	var order: Array = []
	reader._read_into(text, path, classes, order, 0)
	return {
		"entries": reader._flattened(classes, order),
		"warnings": reader._all_warnings(),
		"failure": ""
	}


## The same for FGD text, `label` naming it in warnings.
static func read_text(text: String, label: String = "FGD") -> Dictionary:
	var reader = _new_reader()
	var classes: Dictionary = {}
	var order: Array = []
	reader._read_into(text, label, classes, order, 0)
	return {
		"entries": reader._flattened(classes, order),
		"warnings": reader._all_warnings(),
		"failure": ""
	}


## A reader of its own for one read, which keeps the warnings and skips. The
## script is loaded by path, since a script cannot preload itself.
static func _new_reader() -> RefCounted:
	return load("res://addons/hammerforge/hf_fgd_reader.gd").new()


## `entries` as an `entities.json` file, for Convert to JSON.
static func to_json_text(entries: Array) -> String:
	var out: Array = []
	for entry in entries:
		var record: Dictionary = (entry as Dictionary).duplicate(true)
		record.erase("fgd_bases")
		out.append(record)
	return JSON.stringify({"entities": out}, "\t") + "\n"


func _all_warnings() -> Array:
	var out: Array = _warnings.duplicate()
	for file in _skips:
		var skip: Dictionary = _skips[file]
		(
			out
			. append(
				(
					"HammerForge: %s skipped %d thing%s it has no use for, the first at line %d: %s"
					% [
						file,
						int(skip["count"]),
						"" if int(skip["count"]) == 1 else "s",
						int(skip["line"]),
						str(skip["what"]),
					]
				)
			)
		)
	return out


func _skip(file: String, line: int, what: String) -> void:
	if not _skips.has(file):
		_skips[file] = {"count": 0, "line": line, "what": what}
	_skips[file]["count"] = int(_skips[file]["count"]) + 1


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------


func _read_into(text: String, file: String, classes: Dictionary, order: Array, depth: int) -> void:
	var tokens := _tokens(text, file)
	var at := 0
	while at < tokens.size():
		var token: Dictionary = tokens[at]
		if token["kind"] != "@":
			_skip(file, token["line"], str(token["text"]))
			at = _next_directive(tokens, at + 1)
			continue
		var name_at := at + 1
		if name_at >= tokens.size() or tokens[name_at]["kind"] != "name":
			at = _next_directive(tokens, name_at)
			continue
		var directive := str(tokens[name_at]["text"]).to_lower()
		if directive == "include":
			at = _include(tokens, name_at + 1, file, classes, order, depth)
		elif directive in POINT_KINDS or directive == SOLID_KIND or directive == BASE_KIND:
			at = _read_class(tokens, name_at + 1, directive, file, classes, order)
		else:
			if not directive in QUIET_DIRECTIVES:
				_skip(file, tokens[name_at]["line"], "@" + str(tokens[name_at]["text"]))
			at = _next_directive(tokens, name_at + 1)


## Where the next top level `@` is, past any brackets.
static func _next_directive(tokens: Array, at: int) -> int:
	var depth := 0
	while at < tokens.size():
		var kind: String = tokens[at]["kind"]
		if kind == "[" or kind == "(":
			depth += 1
		elif kind == "]" or kind == ")":
			depth = maxi(depth - 1, 0)
		elif kind == "@" and depth == 0:
			return at
		at += 1
	return at


func _include(
	tokens: Array, at: int, file: String, classes: Dictionary, order: Array, depth: int
) -> int:
	if at >= tokens.size() or tokens[at]["kind"] != "string":
		return _next_directive(tokens, at)
	var name := str(tokens[at]["text"])
	var path := name if name.begins_with("res://") else file.get_base_dir().path_join(name)
	if depth >= MAX_INCLUDE_DEPTH:
		_warnings.append(
			(
				'HammerForge: %s, line %d: @include "%s" nests too deep'
				% [file, tokens[at]["line"], name]
			)
		)
	elif not FileAccess.file_exists(path):
		_warnings.append(
			(
				'HammerForge: %s, line %d: @include "%s" is not there'
				% [file, tokens[at]["line"], name]
			)
		)
	else:
		_read_into(FileAccess.get_file_as_string(path), path, classes, order, depth + 1)
	return at + 1


func _read_class(
	tokens: Array, at: int, kind: String, file: String, classes: Dictionary, order: Array
) -> int:
	var line: int = tokens[at - 1]["line"] if at > 0 else 0
	var record := {
		"kind": kind,
		"bases": [],
		"properties": [],
		"inputs": [],
		"outputs": [],
		"file": file,
		"line": line,
	}
	# Helpers up to the `=`.
	while at < tokens.size() and tokens[at]["kind"] != "=":
		if tokens[at]["kind"] == "@":
			return at
		if (
			tokens[at]["kind"] == "name"
			and at + 1 < tokens.size()
			and tokens[at + 1]["kind"] == "("
		):
			var close := _closing(tokens, at + 1)
			_helper(
				record,
				str(tokens[at]["text"]).to_lower(),
				tokens.slice(at + 2, close),
				file,
				tokens[at]["line"]
			)
			at = close + 1
		else:
			at += 1
	at += 1
	if at >= tokens.size() or tokens[at]["kind"] != "name":
		_skip(file, line, "a class with no name")
		return _next_directive(tokens, at)
	var classname := str(tokens[at]["text"])
	at += 1
	if at < tokens.size() and tokens[at]["kind"] == ":":
		var described := _strings(tokens, at + 1)
		record["description"] = described["text"]
		at = described["at"]
	if at < tokens.size() and tokens[at]["kind"] == "[":
		at = _read_members(tokens, at + 1, record, file)
	if not classes.has(classname):
		order.append(classname)
	classes[classname] = record
	return at


func _helper(record: Dictionary, helper: String, args: Array, file: String, line: int) -> void:
	match helper:
		"base":
			for arg in args:
				if arg["kind"] == "name":
					record["bases"].append(str(arg["text"]))
		"size":
			var numbers := _numbers(args)
			if numbers.size() == 3:
				record["size"] = Vector3(numbers[0], numbers[1], numbers[2]).abs()
			elif numbers.size() == 6:
				record["size"] = (
					(
						Vector3(numbers[3], numbers[4], numbers[5])
						- Vector3(numbers[0], numbers[1], numbers[2])
					)
					. abs()
				)
			else:
				_skip(file, line, "size() with %d numbers" % numbers.size())
		"color":
			var numbers := _numbers(args)
			if numbers.size() >= 3:
				record["color"] = Color8(int(numbers[0]), int(numbers[1]), int(numbers[2]))
			else:
				_skip(file, line, "color() with %d numbers" % numbers.size())
		_:
			_skip(file, line, "%s()" % helper)


## The members of a class, up to its `]`. Returns the token after it.
func _read_members(tokens: Array, at: int, record: Dictionary, file: String) -> int:
	while at < tokens.size():
		var token: Dictionary = tokens[at]
		match token["kind"]:
			"]":
				return at + 1
			"@":
				_skip(file, token["line"], "a class with no closing ]")
				return at
			"name":
				var word := str(token["text"])
				var lower := word.to_lower()
				if (lower == "input" or lower == "output") and _is_io(tokens, at):
					at = _read_io(
						tokens, at + 1, record["inputs" if lower == "input" else "outputs"]
					)
				elif at + 1 < tokens.size() and tokens[at + 1]["kind"] == "(":
					at = _read_property(tokens, at, record, file)
				else:
					_skip(file, token["line"], word)
					at += 1
			_:
				_skip(file, token["line"], str(token["text"]))
				at += 1
	return at


static func _is_io(tokens: Array, at: int) -> bool:
	return (
		at + 2 < tokens.size()
		and tokens[at + 1]["kind"] == "name"
		and tokens[at + 2]["kind"] == "("
	)


func _read_io(tokens: Array, at: int, into: Array) -> int:
	var name := str(tokens[at]["text"])
	if not name in into:
		into.append(name)
	at = _closing(tokens, at + 1) + 1
	if at < tokens.size() and tokens[at]["kind"] == ":":
		at = _strings(tokens, at + 1)["at"]
	return at


func _read_property(tokens: Array, at: int, record: Dictionary, file: String) -> int:
	var line: int = tokens[at]["line"]
	var name := str(tokens[at]["text"])
	var close := _closing(tokens, at + 1)
	var fgd_type := ""
	for token in tokens.slice(at + 2, close):
		if token["kind"] == "name":
			fgd_type = str(token["text"]).to_lower()
	at = close + 1
	# `readonly` and `report` are notes for another editor.
	while (
		at < tokens.size()
		and tokens[at]["kind"] == "name"
		and str(tokens[at]["text"]).to_lower() in ["readonly", "report"]
	):
		at += 1
	var fields: Array = []
	while at < tokens.size() and tokens[at]["kind"] == ":" and fields.size() < 3:
		at += 1
		if at < tokens.size() and tokens[at]["kind"] in ["string", "number"]:
			var value := (
				_strings(tokens, at)
				if tokens[at]["kind"] == "string"
				else {"text": tokens[at]["value"], "at": at + 1}
			)
			fields.append(value["text"])
			at = value["at"]
		else:
			fields.append(null)
	var entries: Array = []
	if at + 1 < tokens.size() and tokens[at]["kind"] == "=" and tokens[at + 1]["kind"] == "[":
		var closing := _closing(tokens, at + 1)
		entries = _list_entries(tokens.slice(at + 2, closing))
		at = closing + 1
	var prop := _property(name, fgd_type, fields, entries)
	if prop.is_empty():
		_skip(file, line, "%s(%s)" % [name, fgd_type])
	else:
		record["properties"].append(prop)
	return at


## A property as a definition holds it.
static func _property(name: String, fgd_type: String, fields: Array, entries: Array) -> Dictionary:
	var type: String = TYPES.get(fgd_type, "string")
	var label: Variant = fields[0] if fields.size() > 0 else null
	var default: Variant = fields[1] if fields.size() > 1 else null
	var tooltip: Variant = fields[2] if fields.size() > 2 else null
	var prop := {"name": name, "type": type}
	if label is String and label != "":
		prop["label"] = label
	if tooltip is String and tooltip != "":
		prop["tooltip"] = tooltip
	match type:
		"enum":
			var values: Array = []
			var labels: Array = []
			for entry in entries:
				values.append(_text_of(entry[0]))
				labels.append(_text_of(entry[1]) if entry.size() > 1 else _text_of(entry[0]))
			prop["enum_values"] = values
			prop["enum_labels"] = labels
			var picked := _text_of(default) if default != null else ""
			prop["default"] = (
				picked if values.has(picked) else (values[0] if not values.is_empty() else "")
			)
		"flags":
			var bits: Array = []
			var labels: Array = []
			var on := 0
			for entry in entries:
				var bit := int(entry[0])
				bits.append(bit)
				labels.append(_text_of(entry[1]) if entry.size() > 1 else str(bit))
				if entry.size() > 2 and int(entry[2]) != 0:
					on |= bit
			prop["flag_values"] = bits
			prop["flag_labels"] = labels
			prop["default"] = int(default) if default is float else on
		"int":
			prop["default"] = (
				int(default)
				if default is float
				else int(str(default)) if default is String and str(default).is_valid_int() else 0
			)
		"float":
			prop["default"] = (
				float(default)
				if default is float
				else (
					float(str(default))
					if default is String and str(default).is_valid_float()
					else 0.0
				)
			)
		"bool":
			prop["default"] = (
				default is float and int(default) != 0
				or default is String and str(default) in ["1", "true", "yes"]
			)
		"color":
			prop["default"] = _colour_text(default, fgd_type == "color1")
		_:
			prop["default"] = _text_of(default) if default != null else ""
	return prop


static func _colour_text(value: Variant, unit: bool) -> String:
	var numbers: Array = []
	for part in _text_of(value).split(" ", false):
		if part.is_valid_float():
			numbers.append(float(part))
	if numbers.size() < 3:
		return "#ffffff"
	if unit:
		return Color(numbers[0], numbers[1], numbers[2]).to_html(false)
	return Color8(int(numbers[0]), int(numbers[1]), int(numbers[2])).to_html(false)


## The entries of a `= [ ... ]` list: each `value : label`, or `value : label :
## default` for a flag. A colon carries an entry on; anything else starts one.
static func _list_entries(tokens: Array) -> Array:
	var out: Array = []
	var current: Array = []
	var carried := false
	for token in tokens:
		if token["kind"] == ":":
			carried = true
			continue
		if not token["kind"] in ["string", "number"]:
			continue
		var value: Variant = token["value"] if token["kind"] == "number" else str(token["text"])
		if not current.is_empty() and not carried:
			out.append(current)
			current = []
		current.append(value)
		carried = false
	if not current.is_empty():
		out.append(current)
	return out


static func _text_of(value: Variant) -> String:
	if value is float and is_equal_approx(value, roundf(value)):
		return str(int(value))
	return str(value)


static func _numbers(tokens: Array) -> Array:
	var out: Array = []
	for token in tokens:
		if token["kind"] == "number":
			out.append(float(token["value"]))
	return out


## The string at `at`, and any joined to it with `+`.
static func _strings(tokens: Array, at: int) -> Dictionary:
	var text := ""
	while at < tokens.size() and tokens[at]["kind"] == "string":
		text += str(tokens[at]["text"])
		at += 1
		if (
			at + 1 < tokens.size()
			and tokens[at]["kind"] == "+"
			and tokens[at + 1]["kind"] == "string"
		):
			at += 1
		else:
			break
	return {"text": text, "at": at}


## The index of the bracket that closes the one at `open`, or the last token.
static func _closing(tokens: Array, open: int) -> int:
	var depth := 0
	var at := open
	while at < tokens.size():
		var kind: String = tokens[at]["kind"]
		if kind == "(" or kind == "[":
			depth += 1
		elif kind == ")" or kind == "]":
			depth -= 1
			if depth == 0:
				return at
		at += 1
	return tokens.size() - 1


# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------


## The tokens of `text`, each `{"kind", "text", "value", "line"}`. Kinds: `@`,
## `(`, `)`, `[`, `]`, `=`, `:`, `,`, `+`, "string", "number" and "name". A
## string left open ends at its line's end, and the file says so.
func _tokens(text: String, file: String) -> Array:
	var out: Array = []
	var line := 1
	var i := 0
	var count := text.length()
	while i < count:
		var c := text[i]
		if c == "\n":
			line += 1
			i += 1
		elif c == " " or c == "\t" or c == "\r":
			i += 1
		elif c == "/" and i + 1 < count and text[i + 1] == "/":
			while i < count and text[i] != "\n":
				i += 1
		elif c == '"':
			var end := text.find('"', i + 1)
			var newline := text.find("\n", i + 1)
			if end < 0 or (newline >= 0 and newline < end):
				_warnings.append("HammerForge: %s, line %d: a string is not closed" % [file, line])
				end = newline if newline >= 0 else count
				out.append(
					{"kind": "string", "text": text.substr(i + 1, end - i - 1), "line": line}
				)
				i = end
			else:
				out.append(
					{"kind": "string", "text": text.substr(i + 1, end - i - 1), "line": line}
				)
				i = end + 1
		elif c in "@()[]=:,+":
			out.append({"kind": c, "text": c, "line": line})
			i += 1
		else:
			var start := i
			while i < count and not text[i] in ' \t\r\n"@()[]=:,+':
				if text[i] == "/" and i + 1 < count and text[i + 1] == "/":
					break
				i += 1
			var word := text.substr(start, i - start)
			if word.is_valid_float():
				out.append({"kind": "number", "text": word, "value": float(word), "line": line})
			else:
				out.append({"kind": "name", "text": word, "line": line})
	return out


# ---------------------------------------------------------------------------
# Base classes
# ---------------------------------------------------------------------------


## Every class that is not a base class, with what its bases lend it, as
## definition entries in file order. A class whose bases loop back to it is left
## out, and said.
func _flattened(classes: Dictionary, order: Array) -> Array:
	var done: Dictionary = {}
	var out: Array = []
	for classname in order:
		var record: Dictionary = classes[classname]
		if record["kind"] == BASE_KIND:
			continue
		var flat: Variant = _flatten(classname, classes, done, [])
		if flat == null:
			continue
		out.append(_entry(classname, flat))
	return out


## `classname` with its bases' members folded in, theirs first and its own over
## them, or null when its bases loop.
func _flatten(classname: String, classes: Dictionary, done: Dictionary, stack: Array) -> Variant:
	if done.has(classname):
		return done[classname]
	if classname in stack:
		var loop: Array = stack.slice(stack.find(classname)) + [classname]
		_warnings.append(
			(
				"HammerForge: the base classes of '%s' loop back to it (%s), so it is left out"
				% [stack[0], " -> ".join(loop)]
			)
		)
		return null
	if not classes.has(classname):
		return {}
	var record: Dictionary = classes[classname]
	var merged := {"properties": [], "inputs": [], "outputs": []}
	stack.append(classname)
	for base in record["bases"]:
		if not classes.has(base):
			_warnings.append(
				(
					"HammerForge: %s, line %d: '%s' names a base class '%s' no file defines"
					% [record["file"], record["line"], classname, base]
				)
			)
			continue
		var lent: Variant = _flatten(base, classes, done, stack)
		if lent == null:
			stack.pop_back()
			return null
		_fold(merged, lent)
	stack.pop_back()
	_fold(merged, record)
	done[classname] = merged
	return merged


## Lay `source`'s members over `into`'s: a property of the same name is replaced
## where it stands, inputs and outputs are added.
static func _fold(into: Dictionary, source: Dictionary) -> void:
	for prop in source.get("properties", []):
		var replaced := false
		for i in into["properties"].size():
			if into["properties"][i]["name"] == prop["name"]:
				into["properties"][i] = prop
				replaced = true
				break
		if not replaced:
			into["properties"].append(prop)
	for key in ["inputs", "outputs"]:
		for name in source.get(key, []):
			if not name in into[key]:
				into[key].append(name)
	for key in ["size", "color", "description"]:
		if source.has(key):
			into[key] = source[key]
	if source.has("kind"):
		into["kind"] = source["kind"]


static func _entry(classname: String, flat: Dictionary) -> Dictionary:
	var brush: bool = flat.get("kind", "") == SOLID_KIND
	var entry := {
		"id": classname,
		"description": str(flat.get("description", "")),
		"is_brush_entity": brush,
		"properties": (flat["properties"] as Array).duplicate(true),
		"inputs": (flat["inputs"] as Array).duplicate(),
		"outputs": (flat["outputs"] as Array).duplicate(),
	}
	var colour: Variant = flat.get("color")
	if colour is Color:
		entry["color"] = "#" + (colour as Color).to_html(false)
	if not brush and flat.get("size") is Vector3:
		# The file measures in map units with Z up, the level in metres with Y up.
		var size: Vector3 = flat["size"] / UNITS_PER_METRE
		entry["preview"] = {
			"type": "box",
			"size": [size.x, size.z, size.y],
			"color": entry.get("color", "#ffffff"),
			"alpha": 0.6,
		}
	return entry
