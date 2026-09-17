@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Names that are not ASCII, through every surface that stores a name.
##
## A real team is not all anglophone and a real map is not all `corridor_2`.
## Entity names, group names, visgroup names and the level's own filename each
## reach a different encoder: JSON in the `.hflevel`, a quoted key in a `.map`,
## a node name in the `.tscn`, and a path on the filesystem. Each one has its
## own rules about what a name may contain, and the failure is silent in all
## four -- a name comes back mangled, or the thing it named stops being
## findable, and nothing said anything.
##
## Godot's own node names are the sharpest edge: `Node.name` strips `.`, `:`,
## `@`, `/`, `"` and `%` quietly, on assignment.


func id() -> String:
	return "unicode-names"


func summary() -> String:
	return "non-ASCII and punctuation in every kind of name, through every format"


const NAMES: Array[String] = [
	"couloir_é",
	"部屋_1",
	"Кабинет",
	"sala—principal",
	"room with spaces",
	"naive/slash",
	"dots.in.name",
	"percent%sign",
	"at@sign",
	"emoji_🔦",
]


func run() -> void:
	await _entity_names()
	await _visgroup_and_group_names()
	await _through_the_hflevel()
	await _through_the_map_export()


func _spawn(root: Node3D, type: String, where: Vector3, authored: String) -> Node3D:
	return (
		root
		. _restore_entity_from_info(
			{
				"entity_type": type,
				"entity_class": type,
				"transform": Transform3D(Basis.IDENTITY, where),
				"properties": {},
				"name": authored,
				"entity_name": authored,
			}
		)
	)


func _entity_names() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var rows: Array = []
	for i in NAMES.size():
		var n: String = NAMES[i]
		var ent := _spawn(root, "info_target", Vector3(i * 0.5, 0, 0), n)
		if ent == null:
			rows.append({"asked": n, "result": "not created"})
			continue
		(
			rows
			. append(
				{
					"asked": n,
					"meta": str(ent.get_meta("entity_name", "")),
					"node": str(ent.name),
				}
			)
		)
	note("what each name became", rows)
	var lost: Array = []
	for r in rows:
		if r.get("meta", null) != null and str(r["meta"]) != str(r["asked"]):
			lost.append(r)
	if not lost.is_empty():
		flag("an entity's authored name was changed on the way into the level", lost)
	note(
		"why meta and node can differ",
		(
			"entity_name metadata is the identity HFIORuntime dispatches on; Node.name is "
			+ 'what the scene tree and get_node() use. Godot strips . : @ / " % from the '
			+ "second, so a name legal in the panel is not the name in the tree"
		)
	)
	# The thing that matters: can the I/O layer still address it.
	var button := _spawn(root, "func_button", Vector3(0, 0, 2), "bouton")
	if button:
		root.add_entity_output(button, "OnPressed", "dots.in.name", "Open")
		var outs: Array = root.get_entity_outputs(button)
		note("an output aimed at a dotted target name", outs)
		var reachable := false
		for c in root.entities_node.get_children():
			if str(c.get_meta("entity_name", "")) == "dots.in.name":
				reachable = true
		note("a node still carries 'dots.in.name' as its entity_name", reachable)


func _visgroup_and_group_names() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var b1 = box(root, Vector3(1, 1, 1))
	var b2 = box(root, Vector3(1, 1, 1), Vector3(2, 0, 0))
	await frame()
	for n in NAMES:
		root.create_visgroup(n)
	var live: PackedStringArray = root.get_visgroup_names()
	note("visgroup names the level kept", live)
	var missing: Array = []
	for n in NAMES:
		if not live.has(n):
			missing.append(n)
	if not missing.is_empty():
		flag(
			"create_visgroup accepted a name the list does not hold",
			(
				"asked for %d names, %d are in get_visgroup_names(): missing %s"
				% [NAMES.size(), NAMES.size() - missing.size(), missing]
			)
		)
	root.group_selection("Groupe_é", [b1, b2])
	await frame()
	var members: Array = root.get_group_members("Groupe_é")
	note("members of an accented group", members.size())
	if members.size() != 2:
		flag(
			"a group with an accented name did not keep its members",
			"grouped 2 brushes, get_group_members returned %d" % members.size()
		)


func _through_the_hflevel() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(1, 1, 1))
	for n in NAMES:
		root.create_visgroup(n)
	_spawn(root, "info_target", Vector3(1, 0, 0), "部屋_1")
	var before: PackedStringArray = root.get_visgroup_names()

	var path := "user://vibe_unicode.hflevel"
	root.save_hflevel(path)
	var settled: bool = await HFVibe.settle_save(_tree, root, 2000)
	note("save settled", settled)
	root.load_hflevel(path)
	await frame()
	var after: PackedStringArray = root.get_visgroup_names()
	note("visgroups before", before)
	note("visgroups after a .hflevel round trip", after)
	var lost: Array = []
	for n in before:
		if not after.has(n):
			lost.append(n)
	if not lost.is_empty():
		flag("non-ASCII visgroup names did not survive the .hflevel", lost)
	elif Array(before) != Array(after):
		note(
			"the round trip kept every name and reordered them",
			(
				"the list comes back alphabetised rather than in the order the mapper made "
				+ "them, so the Visgroups panel reshuffles itself on every reload"
			)
		)
	var names: Array = []
	for c in root.entities_node.get_children():
		names.append(str(c.get_meta("entity_name", "")))
	note("entity names after the round trip", names)
	if not names.has("部屋_1"):
		flag("a CJK entity name did not survive the .hflevel", "saved '部屋_1', loaded %s" % [names])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# A filename that is not ASCII, which is what a French or Japanese mapper
	# types into the save dialog.
	var nudge := 0
	for utf_path in [
		"user://niveau_e_ascii.hflevel",
		"user://niveau_é.hflevel",
		"user://niveau_部屋.hflevel",
	]:
		# One brush per iteration, so each save has a payload the dedupe in #688
		# has not seen. Without it every save after the first is skipped and the
		# question this asks -- whether a non-ASCII filename can be written at
		# all -- cannot be reached.
		box(root, Vector3(0.5, 0.5, 0.5), Vector3(nudge * 1.5, 0.25, 4))
		nudge += 1
		await frame()
		root.save_hflevel(utf_path)
		settled = await HFVibe.settle_save(_tree, root, 2000)
		var size := HFVibe.file_size(utf_path)
		var exists := FileAccess.file_exists(utf_path)
		note("saved to '%s'" % utf_path, "settled=%s exists=%s size=%d" % [settled, exists, size])
		if settled and size <= 0:
			# Not a filename problem: the ASCII control in this same loop is
			# dropped too, because the level has not changed since the save above
			# and `_hflevel_last_hash` does not record which file it came from.
			known(
				688,
				"save_hflevel wrote nothing for '%s'" % utf_path,
				(
					"the payload is identical to the previous save, so the dedupe skips it "
					+ "whatever path it is given -- every name in this list fails, ASCII "
					+ "included, which is what says the filename is not the cause"
				)
			)
	# What the directory actually holds, so a mangled name is visible rather
	# than reading as a missing file.
	var listed := DirAccess.get_files_at("user://")
	note(
		"files in user:// whose name starts with niveau",
		Array(listed).filter(func(f: String) -> bool: return f.begins_with("niveau"))
	)
	for utf_path in [
		"user://niveau_e_ascii.hflevel",
		"user://niveau_é.hflevel",
		"user://niveau_部屋.hflevel",
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(utf_path))


func _through_the_map_export() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(2, 2, 2))
	_spawn(root, "info_target", Vector3(1, 0, 0), "cible_é")
	var path := "user://vibe_unicode.map"
	var ok = root.export_map(path, "valve220")
	note("export_map returned", ok)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		flag("export_map wrote no file for a level with an accented entity name")
		return
	var text := f.get_as_text()
	f.close()
	note("the .map holds the accented name verbatim", text.contains("cible_é"))
	note(
		"lines mentioning the target",
		Array(text.split("\n")).filter(func(l: String) -> bool: return l.contains("cible"))
	)
	var root2: Node3D = await fresh_root("Level2")
	root2.auto_spawn_player = false
	var imported = root2.import_map(path)
	note("import_map returned", imported)
	var back: Array = []
	for c in root2.entities_node.get_children():
		back.append(str(c.get_meta("entity_name", c.name)))
	note("entity names after the .map round trip", back)
	if not back.is_empty() and not back.has("cible_é"):
		flag(
			"an accented entity name did not survive a .map round trip",
			"exported 'cible_é', imported %s" % [back]
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
