@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The two JSON config files the editor reads: `entities.json` and the I/O
## preset file.
##
## Both are hand-editable, both live outside the level, and both feed dropdowns
## that a mapper picks from. So the questions are the same for each: what does a
## malformed file do on the way in, what is left usable afterwards, and does the
## editor say anything.

const HFEntityDefType = preload("res://addons/hammerforge/hf_entity_def.gd")


func id() -> String:
	return "definitions"


func summary() -> String:
	return "entities.json and the I/O preset file, malformed and at their edges"


func run() -> void:
	await _malformed_entity_definitions()
	await _entity_definitions_that_parse_but_say_little()
	await _io_preset_names_and_slots()


func _tmp(suffix: String) -> String:
	return "user://vibe_defs_%s.json" % suffix


## Every shape of wrong a JSON file can be. The loader is supposed to fall back
## to the built-ins and say so.
func _malformed_entity_definitions() -> void:
	var root: Node3D = await fresh_root()
	var cases: Dictionary = {
		"not-json": "this is not json",
		"bare-number": "42",
		"entities-is-a-string": '{"entities": "nope"}',
		"entities-is-a-number": '{"entities": 7}',
		"entities-holds-nulls": '{"entities": [null, null]}',
		"entities-holds-strings": '{"entities": ["func_wall", "trigger_once"]}',
		"entry-without-a-classname": '{"entities": [{"description": "no id here"}]}',
		"colour-of-strings": '{"entities": [{"id": "x", "color": ["a", "b", "c"]}]}',
		"colour-too-short": '{"entities": [{"id": "y", "color": [1.0]}]}',
		"properties-is-a-string": '{"entities": [{"id": "z", "properties": "nope"}]}',
	}
	for label in cases:
		var path := _tmp(str(label).replace("-", "_"))
		HFVibe.write_text(path, cases[label])
		var defs: Array = HFEntityDefType.load_definitions(path)
		var names: Array = []
		for d in defs:
			if d != null:
				names.append(d.classname)
		note(
			str(label),
			(
				"%d definition(s) loaded%s"
				% [defs.size(), "" if names.is_empty() else ": %s" % [names]]
			)
		)
		if defs.is_empty():
			known(
				380,
				"a malformed entities.json leaves the editor with no entity definitions at all",
				(
					"case '%s': load_definitions() returned nothing, where every other malformed case falls back to the built-ins. An empty definition list means the entity dropdown is empty and no entity can be placed."
					% label
				)
			)

	# And through the level, which is how the editor actually reaches it.
	root.entity_definitions_path = _tmp("entities_is_a_string")
	root.entity_system.load_entity_definitions()
	await frame()
	note(
		"level_root after pointing entity_definitions_path at a malformed file",
		"%d definition(s)" % root.entity_definitions.size()
	)
	if root.entity_definitions.is_empty():
		known(
			380,
			"a malformed entities.json leaves LevelRoot with an empty definition table",
			"no entity class can be chosen or placed until the file is fixed and the editor reloaded"
		)


## Files that parse fine and are still not what the loader wants.
func _entity_definitions_that_parse_but_say_little() -> void:
	var cases: Dictionary = {
		"empty-object": "{}",
		"empty-entities": '{"entities": []}',
		"empty-array": "[]",
		"duplicate-classnames":
		'{"entities": [{"id": "dup", "description": "first"}, {"id": "dup", "description": "second"}]}',
		"whitespace-classname": '{"entities": [{"id": "   ", "description": "blank"}]}',
	}
	for label in cases:
		var path := _tmp(str(label).replace("-", "_"))
		HFVibe.write_text(path, cases[label])
		var defs: Array = HFEntityDefType.load_definitions(path)
		var names: Array = []
		for d in defs:
			if d != null:
				names.append(d.classname)
		note(str(label), "%d definition(s): %s" % [defs.size(), names])
		var blank := 0
		for n in names:
			if str(n).strip_edges() == "":
				blank += 1
		if blank > 0:
			known(
				381,
				"an entity class can be named with nothing but whitespace",
				(
					"case '%s' loaded %d definition(s) whose classname is blank. The classname is the key in LevelRoot.entity_definitions and the string written into the exported `.map`, so a blank one is a dropdown row nobody can tell apart and a `classname` field with nothing in it."
					% [label, blank]
				)
			)


## The I/O preset list: names, and how a caller addresses a preset to remove it.
func _io_preset_names_and_slots() -> void:
	var root: Node3D = await fresh_root()
	var presets = root.io_presets
	if presets == null:
		note("io_presets", "not present on this root")
		return

	var builtin_count: int = presets.get_all_presets().size()
	note("presets before anything is added", "%d, all built in" % builtin_count)

	note("adding a preset with no name", presets.add_user_preset("", "", []))
	note("adding a preset named only whitespace", presets.add_user_preset("   ", "", []))
	note("adding a normal preset", presets.add_user_preset("Door", "opens a door", []))
	note(
		"adding a second preset with the same name",
		presets.add_user_preset("Door", "a different one", [])
	)

	var user: Array = presets.get_user_presets()
	var names: Array = []
	for p in user:
		names.append(str(p.get("name", "")))
	note("user presets", names)

	var blank := 0
	for n in names:
		if str(n).strip_edges() == "":
			blank += 1
	if blank > 0:
		flag(
			"an I/O preset can be named with nothing but whitespace",
			'add_user_preset() refuses "" and accepts "   " -- the same guard #349 replaced for visgroups and #374 reports for groups. The preset list is a dropdown, so a blank row cannot be told from another blank row, and remove_user_preset() addresses presets by index.'
		)
	if names.count("Door") > 1:
		note(
			"two user presets can share a name",
			"the dropdown shows two identical rows; remove_user_preset() takes an index, so this is ambiguous to a reader rather than to the code"
		)

	# `get_all_presets()` concatenates built-ins and user presets; user presets are
	# deep-copied and built-ins are appended by reference. That asymmetry looks
	# like a defect and is not one: a `const` Array of Dictionaries is read-only
	# in Godot 4, so a caller cannot write to what it was handed. Recorded here so
	# the next reader does not chase it, and so this goes red if the built-ins
	# ever stop being a const.
	var all_a: Array = presets.get_all_presets()
	var all_b: Array = presets.get_all_presets()
	if all_a.is_empty() or all_b.is_empty():
		return
	note("the first built-in preset is the same object across two calls", all_a[0] == all_b[0])
	note("the built-in preset dictionaries are read-only", all_a[0].is_read_only())
	if not all_a[0].is_read_only():
		flag(
			"get_all_presets() hands out the built-in presets by reference and they are writable",
			"user presets are returned as `p.duplicate(true)` and built-ins as `result.append(p)`, so a caller that edits a returned preset edits BUILTIN_PRESETS for the rest of the session"
		)
