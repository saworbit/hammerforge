@tool
extends HFVibeScenario

## Point entities, brush entities and the I/O wiring between them.
##
## Wiring is held by *name*, so every question here is really the same one: when
## a name changes -- because an entity was renamed, duplicated, deleted or
## restored -- does the wiring that referred to it follow, break loudly, or
## quietly point at nothing.


func id() -> String:
	return "entities"


func summary() -> String:
	return "entity naming, duplication, deletion and what happens to the I/O wired to them"


func run() -> void:
	await _duplicate_keeps_the_wiring_straight()
	await _delete_leaves_no_dangling_output()
	await _rename_by_hand()
	await _output_input_validation()
	await _brush_entity_tie()


## An entity of `type` at `where`, with an authored name.
func _spawn(root: Node3D, type: String, where: Vector3, authored: String) -> Node3D:
	var info := {
		"entity_type": type,
		"entity_class": type,
		"transform": Transform3D(Basis.IDENTITY, where),
		"properties": {},
		"name": authored,
		"entity_name": authored,
	}
	var entity = root._restore_entity_from_info(info)
	return entity


func _paths(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(n.get_path())
	return out


## Duplicating a wired entity: the copy cannot keep the original's authored name,
## or every output aimed at that name now fires at two entities.
func _duplicate_keeps_the_wiring_straight() -> void:
	var root: Node3D = await fresh_root()
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	if button == null or door == null:
		note("entity creation", "could not create func_button/func_door, skipping")
		return
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	note("wired", "%d output(s) on the button" % root.get_entity_outputs(button).size())

	var copy_info: Dictionary = root.build_duplicate_entity_info(door, Vector3(0, 0, 128))
	root.create_entities_from_infos([copy_info])
	await frame()
	var matches: Array = root.find_entities_by_name("door_1")
	note("after duplicating the door", "%d entities answer to 'door_1'" % matches.size())
	if matches.size() > 1:
		known(
			341,
			"duplicating a wired entity leaves two entities with the same authored name",
			(
				"%d entities answer to 'door_1', so every output aimed at it now fires at all of them"
				% matches.size()
			)
		)
	var summary: Dictionary = root.get_connection_summary("door_1")
	note("connection summary for 'door_1'", summary)


## Deleting the target of an output leaves the output pointing at a name nothing
## answers to. `cleanup_dangling_connections` exists for exactly this.
func _delete_leaves_no_dangling_output() -> void:
	var root: Node3D = await fresh_root()
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	if button == null or door == null:
		return
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	root.delete_entities_by_paths(_paths([door]))
	await frame()
	var outputs: Array = root.get_entity_outputs(button)
	var dangling := 0
	for o in outputs:
		if root.find_entities_by_name(str((o as Dictionary).get("target_name", ""))).is_empty():
			dangling += 1
	note(
		"after deleting the door", "%d of %d outputs point at nothing" % [dangling, outputs.size()]
	)
	if dangling > 0:
		flag(
			"deleting an entity leaves the outputs aimed at it dangling",
			(
				"%d of %d outputs on the button still target 'door_1'; the level reports no error"
				% [dangling, outputs.size()]
			)
		)
	var all: Array = root.get_all_entity_connections()
	var health: Dictionary = root.validate_level()
	note("validate_level after the delete", health)
	note("get_all_entity_connections", "%d connection(s)" % all.size())


## Renaming an entity by hand -- which is what the Inspector does -- and whether
## the wiring follows.
func _rename_by_hand() -> void:
	var root: Node3D = await fresh_root()
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	if button == null or door == null:
		return
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	door.set_meta("entity_name", "door_renamed")
	await frame()
	var found: Array = root.find_entities_by_name("door_1")
	var summary: Dictionary = root.get_connection_summary("door_renamed")
	note("after renaming door_1 to door_renamed", "%d answer to the old name" % found.size())
	note("connection summary for the new name", summary)
	if found.is_empty() and int(summary.get("triggers", 0)) == 0:
		note(
			"the wiring did not follow the rename",
			"the button still fires at 'door_1', which nothing answers to"
		)


## What an output accepts. Every field here is written verbatim into the exported
## `.map`, so anything a mapper can type is something the engine reads back.
func _output_input_validation() -> void:
	var root: Node3D = await fresh_root()
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	if button == null:
		return
	var cases := [
		["empty output name", "", "door_1", "Open", "", 0.0],
		["empty target", "OnPressed", "", "Open", "", 0.0],
		["empty input", "OnPressed", "door_1", "", "", 0.0],
		["negative delay", "OnPressed", "door_1", "Open", "", -5.0],
		["non-finite delay", "OnPressed", "door_1", "Open", "", NAN],
		["target with a comma", "OnPressed", "door,1", "Open", "", 0.0],
		["parameter with a quote", "OnPressed", "door_1", "Open", 'say "hi"', 0.0],
	]
	for case in cases:
		var before: int = root.get_entity_outputs(button).size()
		root.add_entity_output(button, case[1], case[2], case[3], case[4], case[5], false)
		await frame()
		var after: int = root.get_entity_outputs(button).size()
		note(case[0], "accepted" if after > before else "refused")
		if after > before and case[0] in ["empty output name", "empty target", "empty input"]:
			known(
				342,
				"an entity output with an %s is accepted" % case[0],
				"it writes a line into the exported .map that names nothing"
			)
		if after > before and case[0] == "non-finite delay":
			known(
				342,
				"an entity output accepts a non-finite delay",
				"NAN is written straight into the exported .map"
			)
	# One final export, to see what the accepted junk does downstream, and then
	# back in through the importer -- a format this exporter writes and its own
	# importer cannot read is not a format.
	var path := "user://vibe_entities.map"
	root.export_map(path, "valve220")
	var text := FileAccess.get_file_as_string(path)
	note("exported .map", "%d bytes, %d output lines" % [text.length(), text.count("OnPressed")])
	if text.find("nan") >= 0 or text.find("NAN") >= 0:
		known(
			342,
			"the exported .map carries a NAN through an entity output",
			"a map compiler reading that line has no defined behaviour"
		)
	for line in text.split("\n"):
		if line.find("door 1") >= 0:
			# Deliberate: `MapIO._no_commas()` strips rather than escapes, because
			# the format defines no escape for a comma and a reader splitting on
			# it would get a field too many. Recorded so the behaviour stays
			# visible, not reported.
			note("a comma in a target name is rewritten on export", line.strip_edges())
		if line.find('\\"') >= 0:
			# Deliberate: `escape_property()` and the reader agree on `\"` and
			# `\`. Classic .map parsers do not define an escape, so this is
			# recorded as a compatibility note rather than reported as a defect.
			note("the exporter escapes a quote inside a value", line.strip_edges())
	var validation: Dictionary = root.validate_map(path)
	note("the exporter's own validator on that file", validation)
	var reader: Node3D = await fresh_root("Reimport")
	var imported: int = reader.import_map(path)
	var back: Array = HFVibe.describe_entities(reader)
	note("re-imported", "%d brushes, %d entities" % [imported, back.size()])
	if back.is_empty():
		flag(
			"the importer reads back no entities from a file this exporter wrote",
			"%d bytes of .map with a func_button in it" % text.length()
		)
	var restored_outputs := 0
	for e in back:
		restored_outputs += (e.get("io", []) as Array).size()
		note("re-imported entity", "%s io %s" % [e.get("type"), e.get("io")])
	if restored_outputs == 0 and text.count("OnPressed") > 0:
		flag(
			"the importer drops every entity output the exporter wrote",
			(
				"%d OnPressed lines went out and %d came back, so a .map round trip unwires the level"
				% [text.count("OnPressed"), restored_outputs]
			)
		)


## Tying brushes to an entity class makes them a brush entity. Untying puts them
## back. The round trip should be exact.
func _brush_entity_tie() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var id := str(b.get_meta("brush_id", ""))
	var before := HFVibe.describe_brushes(root)
	root.tie_brushes_to_entity([id], "func_door")
	await frame()
	note("after tie", "entity class %s" % str(b.get_meta("brush_entity_class", "")))
	root.untie_brushes_from_entity([id])
	await frame()
	var after := HFVibe.describe_brushes(root)
	diff_levels({"b": before}, {"b": after}, "tie to func_door and untie")
	for bad_class in ["", "   ", "worldspawn"]:
		root.tie_brushes_to_entity([id], bad_class)
		await frame()
		var tied := str(b.get_meta("brush_entity_class", ""))
		note("tie to '%s'" % bad_class, "brush entity class is now '%s'" % tied)
		if bad_class.strip_edges() == "" and tied != "":
			flag(
				"a brush can be tied to an entity class that is blank",
				"the class ends up '%s', which exports as an entity with no classname" % tied
			)
		root.untie_brushes_from_entity([id])
		await frame()
	for problem in HFVibe.check_invariants(root):
		flag("tying and untying broke an invariant", problem)
