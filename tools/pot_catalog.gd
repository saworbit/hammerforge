extends RefCounted
## `addons/hammerforge/translations/hammerforge.pot`: the words HammerForge shows,
## for a translator to start a catalog from (#1702). `tools/gen_pot.gd` writes it,
## and `tests/test_translation.gd` fails when the committed file is not what this
## builds, so a new label reaches translators with the change that adds it.
##
## Where the words are found, much as Godot finds a game's:
##   * each command's label, category and help, from `HFCommandRegistry`;
##   * in the addon's scripts, a literal given to `HFTranslation.t()` or `tn()`,
##     `tr()`, `tr_n()` or `atr()`; one assigned whole to a property in
##     `PROPERTIES`; one given to a call in `CALLS` that sets a control's words
##     or shows a toast or a status line; one sent with a signal in `SIGNALS`.
##     Literals joined with `+` count as one, and so does each branch of
##     `"a" if x else "b"`. A literal with `%` after it is put together in code
##     and is not found: it goes through `HFTranslation.t()` first;
##   * in the addon's scripts too, a literal a table holds under a key in
##     `TABLE_KEYS`, for the control that shows it;
##   * in the addon's scenes, the properties in `PROPERTIES`.
## The bridge (`mcp/`) is left out: its replies stay English.

const HFCommandRegistryType = preload("res://addons/hammerforge/hf_command_registry.gd")

const PATH := "res://addons/hammerforge/translations/hammerforge.pot"
const REGENERATE := "godot --headless -s res://tools/gen_pot.gd --path ."
const ADDON := "res://addons/hammerforge"
const SKIP := ["res://addons/hammerforge/mcp"]
const REGISTRY := "addons/hammerforge/hf_command_registry.gd"
## Properties whose literal a control shows.
const PROPERTIES := ["text", "tooltip_text", "placeholder_text", "title", "dialog_text"]
## Calls that set a control's words, a toast's or the status line's: the index of
## each argument that is one.
const CALLS := {
	"tr": [0],
	"atr": [0],
	"add_item": [0],
	"add_check_item": [0],
	"add_radio_check_item": [0],
	"add_submenu_item": [0],
	"add_submenu_node_item": [0],
	"add_icon_item": [1],
	"add_icon_check_item": [1],
	"add_icon_radio_check_item": [1],
	"add_separator": [0],
	"set_item_text": [1],
	"set_item_tooltip": [1],
	"set_tab_title": [1],
	"set_tab_tooltip": [1],
	"set_text": [0, 1],
	"set_tooltip_text": [0, 1],
	"make_button": [0, 1],
	"make_check": [0],
	"make_label_row": [0],
	"show_toast": [0],
	"_toast": [1],
	"_say": [0, 1],
	"_set_status": [0],
	"_set_status_success": [0],
	"_set_status_warning": [0],
}
## Signals whose first argument a toast shows, sent with `emit_signal()` or
## `.emit()`. The Console's log and the bridge get the same text in English.
const SIGNALS := ["user_message"]
## Calls with a plural: the singular's index and the plural's.
const PLURAL_CALLS := {"tr_n": [0, 1], "atr_n": [0, 1]}
## `HFTranslation`'s own, found only after a name that ends in one of `OWNERS`.
const OWN_CALLS := {"t": [0]}
const OWN_PLURAL_CALLS := {"tn": [0, 1]}
const OWNERS := ["HFTranslation", "HFTranslationType"]
## Keys whose literal a table holds for a control to show, as in
## `{"label": "Width", "tooltip": "How wide the flight is"}`.
const TABLE_KEYS := ["label", "tooltip", "help", "title", "blurb"]

const TOKENS := (
	"(?<c>#[^\\n]*)"
	+ "|(?<s>[&^]?r?(?:\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''"
	+ "|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'))"
	+ "|(?<n>[A-Za-z_][A-Za-z_0-9]*)"
	+ "|(?<x>[0-9][A-Za-z_0-9.]*)"
	+ "|(?<l>\\n)"
	+ "|(?<o>==|!=|<=|>=|\\+=|-=|\\*=|/=|%=|:=|->|\\*\\*)"
	+ "|(?<p>[()\\[\\]{},=+%.:;\\-*/<>!&|^~@$?])"
)
const SCENE_PROPERTY := '(?m)^(?<key>[a-z_]+) = "(?<value>(?:[^"\\\\]|\\\\.)*)"\\s*$'

static var _tokens_re: RegEx = null
static var _letter_re: RegEx = null


## The whole file, from the registry, the scripts and the scenes.
static func build() -> String:
	var found := collect()
	var keys: Array = found.keys()
	keys.sort_custom(func(a, b): return _order(a) < _order(b))
	var lines := PackedStringArray(
		[
			"# HammerForge's interface, for translators (#1702).",
			"# Written by tools/gen_pot.gd from the addon's scripts, scenes and command",
			"# registry. Do not edit it by hand: run %s" % REGENERATE,
			"# docs/translating.md says how to start a language from it.",
			'msgid ""',
			'msgstr ""',
			'"Project-Id-Version: HammerForge\\n"',
			'"MIME-Version: 1.0\\n"',
			'"Content-Type: text/plain; charset=UTF-8\\n"',
			'"Content-Transfer-Encoding: 8-bit\\n"',
		]
	)
	for key in keys:
		var entry: Dictionary = found[key]
		var files: Array = entry["files"].keys()
		files.sort()
		lines.append("")
		lines.append("#: " + " ".join(files))
		if entry["context"] != "":
			lines.append("msgctxt " + _quoted(entry["context"]))
		lines.append("msgid " + _quoted(entry["id"]))
		if entry["plural"] != "":
			lines.append("msgid_plural " + _quoted(entry["plural"]))
			lines.append('msgstr[0] ""')
			lines.append('msgstr[1] ""')
		else:
			lines.append('msgstr ""')
	return "\n".join(lines) + "\n"


## Every word found: a key of context and id to
## `{context, id, plural, files: {path: true}}`.
static func collect() -> Dictionary:
	var found := {}
	for entry in HFCommandRegistryType.COMMANDS:
		for field in ["label", "category", "help"]:
			_add(found, str(entry.get(field, "")), "", "", REGISTRY)
	for path in _files(ADDON):
		var text := FileAccess.get_file_as_string(path)
		var shown := path.trim_prefix("res://")
		if path.ends_with(".gd"):
			for word in script_words(text):
				_add(found, word[0], word[1], word[2], shown)
		elif path.ends_with(".tscn"):
			for word in scene_words(text):
				_add(found, word, "", "", shown)
	return found


## The words a script shows, as [id, plural, context].
static func script_words(source: String) -> Array:
	var tokens := tokens_of(source)
	var out: Array = []
	for i in tokens.size():
		var token: Array = tokens[i]
		if token[0] == "s" and TABLE_KEYS.has(token[1]) and _at(tokens, i + 1) == ["p", ":"]:
			var held := _entry_word(tokens, i + 2)
			if held != "":
				out.append([held, "", ""])
			continue
		if token[0] != "n":
			continue
		var name: String = token[1]
		var next := _at(tokens, i + 1)
		if PROPERTIES.has(name) and next == ["p", "="] and _assigns(tokens, i):
			for word in _branches(tokens, i + 2):
				out.append([word, "", ""])
			continue
		if next != ["p", "("]:
			continue
		var dot := _back(tokens, i - 1)
		var holder: String = (
			_at(tokens, _back(tokens, dot - 1))[1] if _at(tokens, dot) == ["p", "."] else ""
		)
		if name == "emit_signal" or (name == "emit" and SIGNALS.has(holder)):
			var sent := _arguments(tokens, i + 1)
			if name == "emit_signal":
				sent = sent.slice(1) if not sent.is_empty() and SIGNALS.has(sent[0]) else []
			if not sent.is_empty() and sent[0] is String:
				out.append([sent[0], "", ""])
			continue
		var own := OWNERS.has(holder)
		if own and not (OWN_CALLS.has(name) or OWN_PLURAL_CALLS.has(name)):
			continue
		if not own and not (CALLS.has(name) or PLURAL_CALLS.has(name)):
			continue
		var args := _arguments(tokens, i + 1)
		if PLURAL_CALLS.has(name) or (own and OWN_PLURAL_CALLS.has(name)):
			var at: Array = PLURAL_CALLS.get(name, OWN_PLURAL_CALLS.get(name, []))
			var one = args[at[0]] if args.size() > at[0] else null
			var many = args[at[1]] if args.size() > at[1] else null
			if one is String and many is String:
				out.append([one, many, _context(args, at[1] + 2)])
			continue
		var indices: Array = OWN_CALLS[name] if own else CALLS[name]
		for index in indices:
			if args.size() > index and args[index] is String:
				var context := _context(args, index + 1) if own or name == "tr" else ""
				out.append([args[index], "", context])
	return out


## The words a scene shows.
static func scene_words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string(SCENE_PROPERTY)
	for found in re.search_all(text):
		if PROPERTIES.has(found.get_string("key")):
			out.append(found.get_string("value").replace('\\"', '"').replace("\\\\", "\\"))
	return out


## `source` as [kind, text] pairs: "s" a string's value, "sname" a StringName or
## NodePath, "n" a name, "x" a number, "l" a line's end, "o" and "p" the rest.
## Comments are dropped.
static func tokens_of(source: String) -> Array:
	if _tokens_re == null:
		_tokens_re = RegEx.create_from_string(TOKENS)
	var out: Array = []
	for found in _tokens_re.search_all(source.replace("\r\n", "\n").replace("\\\n", " ")):
		if found.get_start("c") >= 0:
			continue
		if found.get_start("s") >= 0:
			var raw := found.get_string("s")
			if raw.begins_with("&") or raw.begins_with("^"):
				out.append(["sname", raw])
			else:
				out.append(["s", _decoded(raw)])
			continue
		for kind in ["n", "x", "l", "o", "p"]:
			if found.get_start(kind) >= 0:
				out.append([kind, found.get_string(kind)])
				break
	return out


static func _add(
	found: Dictionary, id: String, plural: String, context: String, file: String
) -> void:
	if not _is_word(id):
		return
	var key := context + "\u0004" + id
	if not found.has(key):
		found[key] = {"context": context, "id": id, "plural": "", "files": {}}
	if plural != "":
		found[key]["plural"] = plural
	found[key]["files"][file] = true


## Text a translator has something to do with: it holds a letter.
static func _is_word(text: String) -> bool:
	if _letter_re == null:
		_letter_re = RegEx.create_from_string("\\p{L}")
	return _letter_re.search(text) != null


static func _order(key: String) -> String:
	var parts := key.split("\u0004")
	return parts[1] + "\u0004" + parts[0]


static func _at(tokens: Array, i: int) -> Array:
	return tokens[i] if i >= 0 and i < tokens.size() else ["", ""]


## The nearest token at or before `i` that is not a line's end.
static func _back(tokens: Array, i: int) -> int:
	while i >= 0 and tokens[i][0] == "l":
		i -= 1
	return i


## A property assigned as a statement of its own: `x.text = ...` or `text = ...`,
## not a variable, a parameter's default or a comparison.
static func _assigns(tokens: Array, i: int) -> bool:
	var before := _at(tokens, _back(tokens, i - 1))
	if before[0] == "n":
		return false
	return not (before == ["p", "("] or before == ["p", ","])


## The literals the expression at `i` can be, read through `"a" if x else "b"`;
## empty when it is not one whole literal or such a choice of them.
static func _branches(tokens: Array, i: int) -> PackedStringArray:
	var out := PackedStringArray()
	var read := _literal(tokens, i)
	if read.is_empty():
		return out
	out.append(read[0])
	var at: int = read[1]
	var next := _at(tokens, at)
	if next == ["n", "if"]:
		var depth := 0
		at += 1
		while at < tokens.size():
			var token: Array = tokens[at]
			if token[0] == "p" and "([{".contains(token[1]):
				depth += 1
			elif token[0] == "p" and ")]}".contains(token[1]):
				depth -= 1
				if depth < 0:
					return out
			elif depth == 0 and token[0] == "l":
				return out
			elif depth == 0 and token == ["n", "else"]:
				out.append_array(_branches(tokens, at + 1))
				return out
			at += 1
		return out
	if next[0] in ["", "l"] or next == ["p", ";"]:
		return out
	return PackedStringArray()


## [text, index after it] for a literal at `i`, `"a" + "b"` read as one and
## parentheses around it allowed; empty when it is anything else.
static func _literal(tokens: Array, i: int) -> Array:
	var open := 0
	while _at(tokens, i) == ["p", "("]:
		open += 1
		i = _skip_lines(tokens, i + 1, open)
	if _at(tokens, i)[0] != "s":
		return []
	var text: String = tokens[i][1]
	i = _skip_lines(tokens, i + 1, open)
	while _at(tokens, i) == ["p", "+"]:
		i = _skip_lines(tokens, i + 1, open)
		if _at(tokens, i)[0] != "s":
			return []
		text += tokens[i][1]
		i = _skip_lines(tokens, i + 1, open)
	while open > 0:
		if _at(tokens, i) != ["p", ")"]:
			return []
		open -= 1
		i = _skip_lines(tokens, i + 1, open)
	return [text, i]


## A table entry's value at `i`, on its own line or the next, when it is one
## whole literal; empty when it is put together in code.
static func _entry_word(tokens: Array, i: int) -> String:
	while _at(tokens, i)[0] == "l":
		i += 1
	var read := _literal(tokens, i)
	if read.is_empty():
		return ""
	var after: int = read[1]
	while _at(tokens, after)[0] == "l":
		after += 1
	return read[0] if _at(tokens, after) in [["p", ","], ["p", "}"]] else ""


static func _skip_lines(tokens: Array, i: int, open: int) -> int:
	while open > 0 and _at(tokens, i)[0] == "l":
		i += 1
	return i


## The arguments of the call whose `(` is at `i`: each a String when it is one
## whole literal, else null.
static func _arguments(tokens: Array, i: int) -> Array:
	var out: Array = []
	var at := i + 1
	while at < tokens.size():
		while _at(tokens, at)[0] == "l":
			at += 1
		if _at(tokens, at) == ["p", ")"]:
			return out
		var read := _literal(tokens, at)
		var value = null
		if not read.is_empty():
			var after: int = read[1]
			while _at(tokens, after)[0] == "l":
				after += 1
			if _at(tokens, after) in [["p", ","], ["p", ")"]]:
				value = read[0]
		out.append(value)
		var depth := 0
		while at < tokens.size():
			var token: Array = tokens[at]
			if token[0] == "p" and "([{".contains(token[1]):
				depth += 1
			elif token[0] == "p" and ")]}".contains(token[1]):
				if depth == 0:
					return out
				depth -= 1
			elif depth == 0 and token == ["p", ","]:
				at += 1
				break
			at += 1
	return out


static func _context(args: Array, index: int) -> String:
	return args[index] if args.size() > index and args[index] is String else ""


## A string literal's value.
static func _decoded(raw: String) -> String:
	var is_raw := raw.begins_with("r")
	if is_raw:
		raw = raw.substr(1)
	var quote := 3 if raw.begins_with('"""') or raw.begins_with("'''") else 1
	var body := raw.substr(quote, raw.length() - quote * 2)
	if is_raw:
		return body
	var out := ""
	var i := 0
	while i < body.length():
		var c := body[i]
		if c != "\\" or i + 1 >= body.length():
			out += c
			i += 1
			continue
		var e := body[i + 1]
		i += 2
		match e:
			"n":
				out += "\n"
			"t":
				out += "\t"
			"r":
				out += "\r"
			"u":
				out += char(body.substr(i, 4).hex_to_int())
				i += 4
			"U":
				out += char(body.substr(i, 6).hex_to_int())
				i += 6
			_:
				out += e
	return out


static func _quoted(text: String) -> String:
	return (
		'"'
		+ text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
		+ '"'
	)


static func _files(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if SKIP.has(folder):
		return out
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		out.append_array(_files(folder.path_join(sub)))
	out.sort()
	return out


## A catalog's entries, as `{context, id, plural, strings: PackedStringArray}`.
## Enough of the format for the checks: comments, `msgctxt`, `msgid`,
## `msgid_plural`, `msgstr` and `msgstr[n]`, each continued on quoted lines.
static func read_po(text: String) -> Array:
	var out: Array = []
	var entry := {}
	var field := ""
	for raw_line in text.replace("\r\n", "\n").split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with('"'):
			if field != "":
				_po_field(entry, field, _decoded(line), false)
			continue
		if line == "" or line.begins_with("#"):
			continue
		var space := line.find(" ")
		if space < 0:
			continue
		var key := line.substr(0, space)
		# An entry starts at its msgctxt, or at its msgid when it has none.
		if key == "msgctxt" or (key == "msgid" and field != "msgctxt"):
			if not entry.is_empty():
				out.append(entry)
			entry = {"context": "", "id": "", "plural": "", "strings": PackedStringArray()}
		field = key
		_po_field(entry, field, _decoded(line.substr(space + 1).strip_edges()), true)
	if not entry.is_empty():
		out.append(entry)
	# The header is the entry with no id.
	return out.filter(func(e): return e["id"] != "")


static func _po_field(entry: Dictionary, field: String, value: String, start: bool) -> void:
	if entry.is_empty():
		return
	if field == "msgctxt":
		entry["context"] += value
	elif field == "msgid":
		entry["id"] += value
	elif field == "msgid_plural":
		entry["plural"] += value
	elif field.begins_with("msgstr"):
		var strings: PackedStringArray = entry["strings"]
		if start or strings.is_empty():
			strings.append(value)
		else:
			strings[strings.size() - 1] += value
		entry["strings"] = strings
