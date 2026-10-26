@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Notes (#1813) promise to stay in the editor: saved with the level, never in a
## bake, a `.map` or a game scene. Validate can list the open To Do ones (#1828).
## And a Validate finding can be accepted for good (#1830): set aside until what
## it names changes, saved with the level and undone like an edit, with the kinds
## of check a project runs chosen in a file.
##
## The acceptance is keyed by the finding's text and the objects it names, and
## held to a fingerprint of those objects. So the questions are the round trips:
## does an accepted finding stay accepted through an unrelated undo, a `.hflevel`
## save and load, a move and the move back, and does it come back when it should.

const HFNotes = preload("res://addons/hammerforge/hf_notes.gd")
const HFAcceptedFindings = preload("res://addons/hammerforge/hf_accepted_findings.gd")
const HFValidationChecks = preload("res://addons/hammerforge/hf_validation_checks.gd")

const LEVEL_PATH := "user://vibe_notes_and_checks.hflevel"
const MAP_PATH := "user://vibe_notes_and_checks.map"
const SCENE_PATH := "user://vibe_notes_and_checks_game.tscn"
const CHECKS_PATH := "user://vibe_notes_and_checks_checks.json"


func id() -> String:
	return "notes-and-checks"


func summary() -> String:
	return "notes kept out of every export, To Do warnings, and accepted findings through undo, save, load and edits"


func run() -> void:
	var project_checks := HFValidationChecks.path
	# Never the project's own file: every write below goes to user://.
	HFValidationChecks.path = CHECKS_PATH
	await _notes_stay_in_the_editor()
	await _accepted_findings_round_trips()
	await _choosing_the_checks()
	HFValidationChecks.path = project_checks
	for path in [LEVEL_PATH, MAP_PATH, SCENE_PATH, CHECKS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _note(root: Node3D, title: String, kind := "Note", done := false, at := Vector3.ZERO) -> Node:
	return (
		root
		. entity_system
		. restore_entity_from_info(
			{
				"name": "Note",
				"entity_type": "note",
				"properties":
				{"title": title, "body": "b", "kind": kind, "author": "", "done": done},
				"transform": Transform3D(Basis(), at),
			}
		)
	)


func _box(root: Node3D, brush_id: String, size: Vector3, centre: Vector3) -> Node:
	return root.create_brush_from_info(
		{"shape": 0, "size": size, "center": centre, "brush_id": brush_id}
	)


func _todo_findings(root: Node3D) -> Array:
	var out: Array = []
	for issue in root.validate_level(false).get("issues", []):
		if str(issue).begins_with("Open To Do note"):
			out.append(str(issue))
	return out


# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------


func _notes_stay_in_the_editor() -> void:
	var root: Node3D = await fresh_root("NotesLevel")
	root.hflevel_autosave_enabled = false
	_box(root, "floor", Vector3(8, 0.5, 8), Vector3(0, -0.25, 0))
	_note(root, "Lift goes here", "Note", false, Vector3(0, 1, 0))
	_note(root, "Fix the ledge", "To Do", false, Vector3(1, 1, 0))
	_note(root, "Done one", "To Do", true, Vector3(2, 1, 0))
	_note(root, "Players stuck", "Playtest", false, Vector3(3, 1, 0))
	_note(root, "Odd kind", "todo", false, Vector3(4, 1, 0))
	await frame()
	note("notes in the level", HFNotes.summary(root))

	root.validate_warns_open_todos = false
	note("To Do findings with the setting off", _todo_findings(root))
	if not _todo_findings(root).is_empty():
		flag("Validate lists To Do notes with the setting off", _todo_findings(root))
	root.validate_warns_open_todos = true
	var listed := _todo_findings(root)
	note("To Do findings with the setting on", listed)
	if listed.size() != 1:
		flag("Validate does not list exactly the one open To Do note", listed)

	# The bake, the .map in both formats and the game scene.
	await root.bake()
	await frame()
	var baked_notes := 0
	if root.baked_container:
		for node in root.baked_container.find_children("*", "", true, false):
			if node is DraftEntity or str(node.get_meta("entity_class", "")) == "note":
				baked_notes += 1
	note("note nodes in the bake", baked_notes)
	if baked_notes > 0:
		flag("a note reaches the bake", baked_notes)
	for format in ["quake", "valve220"]:
		root.export_map(MAP_PATH, format)
		var text := FileAccess.get_file_as_string(MAP_PATH)
		note(
			".map %s carries a note" % format,
			text.contains('"note"') or text.contains("Lift goes here")
		)
		if text.contains('"note"') or text.contains("Lift goes here"):
			flag(".map %s export carries a note" % format)
	var exported: bool = root.export_game_scene(SCENE_PATH)
	var packed := load(SCENE_PATH) as PackedScene if exported else null
	if packed:
		var scene := packed.instantiate()
		var in_scene := 0
		for node in scene.find_children("*", "", true, false):
			if (
				str(node.name).begins_with("Note")
				or (node is DraftEntity and node.entity_type == "note")
			):
				in_scene += 1
			var data = node.get_meta("entity_data", {})
			if (
				data is Dictionary
				and (data as Dictionary).has("kind")
				and (data as Dictionary).has("done")
			):
				in_scene += 1
		note("note nodes in the exported game scene", in_scene)
		if in_scene > 0:
			flag("a note reaches the game scene", in_scene)
		scene.free()

	# The setting and the notes through a .hflevel.
	root.save_hflevel(LEVEL_PATH, true)
	await HFVibe.settle_save(_tree, root)
	var back: Node3D = await fresh_root("NotesBack")
	back.hflevel_autosave_enabled = false
	var loaded: bool = back.load_hflevel(LEVEL_PATH)
	await frame()
	note(
		".hflevel round trip",
		(
			"load %s, notes %s, warns-open-todos %s, To Do findings %s"
			% [loaded, HFNotes.summary(back), back.validate_warns_open_todos, _todo_findings(back)]
		)
	)
	if loaded and not back.validate_warns_open_todos:
		flag("the open To Do setting does not survive a .hflevel save and load")
	await drop_root(back)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Accepted findings
# ---------------------------------------------------------------------------


## The level the acceptance round trips run on: a brush wholly inside another, a
## copy left on its original, a turned pair the same, two lights answering to one
## name, and an open To Do note.
func _accept_level(root: Node3D) -> void:
	root.hflevel_autosave_enabled = false
	root.validate_warns_open_todos = true
	_box(root, "outer", Vector3(4, 4, 4), Vector3(0, 2, 0))
	_box(root, "inner", Vector3(1, 1, 1), Vector3(0, 2, 0))
	_box(root, "orig", Vector3(2, 2, 2), Vector3(10, 1, 0))
	_box(root, "copy", Vector3(2, 2, 2), Vector3(10, 1, 0))
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(33.0)), Vector3(20, 1, 0))
	root.create_brush_from_info(
		{
			"shape": 0,
			"size": Vector3(2, 2, 2),
			"center": Vector3(20, 1, 0),
			"brush_id": "t1",
			"transform": turn
		}
	)
	root.create_brush_from_info(
		{
			"shape": 0,
			"size": Vector3(0.5, 0.5, 0.5),
			"center": Vector3(20, 1, 0),
			"brush_id": "t2",
			"transform": turn
		}
	)
	for i in 2:
		var lamp: Node = root._create_entity_from_map(
			{"classname": "light_point", "origin": Vector3(i * 2.0, 3, 8)}
		)
		lamp.set_meta("entity_name", "lamp")
		root.set_entity_property(lamp, "energy", 1.37)
	_note(root, "Seal the vent", "To Do", false, Vector3(0, 1, 12))


## What validate says: `{open: [messages], accepted: [messages], changed: [messages]}`.
func _verdict(root: Node3D) -> Dictionary:
	var report: Dictionary = root.validate_level(false)
	var open: Array = []
	var changed: Array = []
	for finding in report.get("findings", []):
		if int(finding.get("severity", 1)) == 0:
			continue
		open.append(str(finding.get("message", "")))
		if finding.get("changed_since_accepted", false):
			changed.append(str(finding.get("message", "")))
	var accepted: Array = []
	for finding in report.get("accepted", []):
		accepted.append(str(finding.get("message", "")))
	open.sort()
	accepted.sort()
	changed.sort()
	return {
		"open": open,
		"accepted": accepted,
		"changed": changed,
		"issues": (report.get("issues", []) as Array).size()
	}


func _accepted_findings_round_trips() -> void:
	var root: Node3D = await fresh_root("AcceptLevel")
	_accept_level(root)
	await frame()
	var first: Dictionary = root.validate_level(false)
	var to_accept: Array = []
	for finding in first.get("findings", []):
		if int(finding.get("severity", 1)) > 0:
			to_accept.append(finding)
	note("findings on the level before any are accepted", _verdict(root)["open"])
	var before_accept: Dictionary = root.capture_state()
	for finding in to_accept:
		HFAcceptedFindings.accept(root, finding, "meant")
	var base := _verdict(root)
	note("after accepting every one", base)
	if not base["open"].is_empty():
		flag("an accepted finding is still listed straight after it was accepted", base["open"])
	var expected: int = base["accepted"].size()

	# An unrelated edit undone: a brush added far off, then the state put back.
	var undo_point: Dictionary = root.capture_state()
	_box(root, "elsewhere", Vector3(1, 1, 1), Vector3(-40, 0.5, 0))
	root.restore_state(undo_point)
	await frame()
	var after_undo := _verdict(root)
	note("after an unrelated edit and its undo", after_undo)
	if after_undo["accepted"].size() != expected:
		flag(
			"an undo of an unrelated edit brings accepted findings back",
			(
				"accepted %d -> %d; open now %s"
				% [expected, after_undo["accepted"].size(), after_undo["open"]]
			)
		)

	# Undo of the acceptance itself.
	var redo_point: Dictionary = root.capture_state()
	root.restore_state(before_accept)
	await frame()
	var unaccepted := _verdict(root)
	note(
		"after undoing the acceptance",
		"accepted %d, open %d" % [unaccepted["accepted"].size(), unaccepted["open"].size()]
	)
	if not unaccepted["accepted"].is_empty():
		flag("undoing an acceptance leaves findings accepted", unaccepted["accepted"])
	root.restore_state(redo_point)
	await frame()

	# A move of the inner brush, and the move back.
	root.nudge_brushes_by_id(["inner"], Vector3(0.5, 0, 0))
	var moved := _verdict(root)
	root.nudge_brushes_by_id(["inner"], Vector3(-0.5, 0, 0))
	var moved_back := _verdict(root)
	note("inner brush nudged 0.5", "changed %s" % [moved["changed"]])
	note(
		"and nudged back",
		"accepted %d, open %s" % [moved_back["accepted"].size(), moved_back["open"]]
	)
	if moved["changed"].is_empty():
		flag("a finding whose brush moved does not come back marked changed", moved)
	if moved_back["accepted"].size() != expected:
		flag("a finding whose brush moved back does not go back to accepted", moved_back)

	# The incremental recheck the dock runs after an edit.
	root.nudge_brushes_by_id(["inner"], Vector3(0.25, 0, 0))
	var rechecked: Dictionary = root.validation_system.recheck(["inner"])
	var re_open: Array = []
	for finding in rechecked.get("open", []):
		re_open.append(
			[str(finding.get("message", "")), finding.get("changed_since_accepted", false)]
		)
	note(
		"recheck after a nudge",
		"open %s, accepted %d" % [re_open, (rechecked.get("accepted", []) as Array).size()]
	)
	root.nudge_brushes_by_id(["inner"], Vector3(-0.25, 0, 0))

	# Delete an unrelated brush made before the rest, and see whether the names
	# the findings carry move.
	_box(root, "early", Vector3(1, 1, 1), Vector3(-60, 0.5, 0))
	var with_early := _verdict(root)
	root.delete_brush_by_id("early")
	await frame()
	var after_delete := _verdict(root)
	note(
		"after deleting an unrelated brush",
		"accepted %d, open %s" % [after_delete["accepted"].size(), after_delete["open"]]
	)
	if after_delete["accepted"].size() != with_early["accepted"].size():
		flag("deleting an unrelated brush brings accepted findings back", after_delete)

	# A .hflevel save, then a load into a fresh level.
	root.save_hflevel(LEVEL_PATH, true)
	await HFVibe.settle_save(_tree, root)
	var back: Node3D = await fresh_root("AcceptBack")
	back.hflevel_autosave_enabled = false
	var loaded: bool = back.load_hflevel(LEVEL_PATH)
	await frame()
	var after_load := _verdict(back)
	note(
		".hflevel save and load",
		(
			"load %s, %d records kept, accepted %d of %d, open %s, changed %s"
			% [
				loaded,
				back.validation_system.accepted.size(),
				after_load["accepted"].size(),
				expected,
				after_load["open"],
				after_load["changed"]
			]
		)
	)
	if loaded and after_load["accepted"].size() != expected:
		var lost: Array = []
		for message in base["accepted"]:
			if not after_load["accepted"].has(message):
				lost.append(message)
		flag(
			"accepted findings come back after a .hflevel save and load",
			(
				"%d of %d no longer accepted: %s; marked changed: %s"
				% [lost.size(), expected, lost, after_load["changed"]]
			)
		)
	# And the loaded level through a state round trip of its own.
	var reload_state: Dictionary = back.capture_state()
	back.restore_state(reload_state)
	await frame()
	var again := _verdict(back)
	note(
		"the loaded level through capture/restore",
		"accepted %d, open %s" % [again["accepted"].size(), again["open"]]
	)
	await drop_root(back)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Which checks run
# ---------------------------------------------------------------------------


func _choosing_the_checks() -> void:
	var root: Node3D = await fresh_root("ChecksLevel")
	_accept_level(root)
	await frame()
	var all := _verdict(root)
	var by_kind: Dictionary = {}
	for finding in root.validate_level(false).get("findings", []):
		var kind := str(finding.get("check", "?"))
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	note("findings by check, every check running", by_kind)
	for kind in HFValidationChecks.KINDS:
		var err := HFValidationChecks.set_runs(kind, false)
		var left: Dictionary = {}
		for finding in root.validate_level(false).get("findings", []):
			var k := str(finding.get("check", "?"))
			left[k] = int(left.get(k, 0)) + 1
		note("with %s left out" % kind, "%s -> %s" % [error_string(err), left])
		if left.has(kind):
			flag("Validate still reports '%s' findings with that check left out" % kind, left)
		HFValidationChecks.set_runs(kind, true)
	var back_to_all := _verdict(root)
	if back_to_all["open"] != all["open"]:
		flag(
			"turning every check back on does not give the findings back",
			"%s vs %s" % [back_to_all["open"], all["open"]]
		)
	# A malformed file: every check runs, and the bad file is said.
	HFVibe.write_text(CHECKS_PATH, '{"skip": "notes"}')
	note("a file whose skip is a string", "skipped %s" % [HFValidationChecks.skipped()])
	HFVibe.write_text(CHECKS_PATH, '{"skip": ["notes", "nonsense", 7]}')
	note("a file naming an unknown kind", "skipped %s" % [HFValidationChecks.skipped()])
	note(
		"set_runs on an unknown kind", error_string(HFValidationChecks.set_runs("nonsense", false))
	)
	await drop_root(root)
