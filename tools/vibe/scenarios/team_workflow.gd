@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Two people on one map, which is the second week of any real project.
##
## Everything else in the sweep runs one mapper on one machine. A game is built
## by a team with the level in version control, and the questions that matter
## then are different ones: what does a commit look like, what does a diff show,
## what happens when two branches both touched the level, and can a conflict be
## resolved by anything other than picking a side.
##
## The `.hflevel` is the level. Its shape decides all four answers.


func id() -> String:
	return "team-workflow"


func summary() -> String:
	return "what a level looks like to version control: diff size, readability, merge"


func run() -> void:
	await _what_one_small_edit_costs_a_commit()
	await _what_the_file_looks_like()
	await _what_the_scene_carries_instead()


func _level(root: Node3D, extra: int = 0) -> void:
	box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0))
	box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, -5))
	box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, 5))
	box(root, Vector3(0.3, 3, 10), Vector3(-5, 1.5, 0))
	box(root, Vector3(0.3, 3, 10), Vector3(5, 1.5, 0))
	for i in 40:
		box(root, Vector3(0.6, 0.6, 0.6), Vector3(-4.0 + (i % 8) * 1.0, 0.3, -4.0 + (i / 8) * 1.0))
	for i in extra:
		box(root, Vector3(0.5, 0.5, 0.5), Vector3(i * 1.0, 2.0, 0))


func _bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b


## How many bytes of a level file change when one brush moves. A format a team
## can live with changes a little; one that changes everywhere makes every
## commit a whole-file replacement and every merge a choice between two sides.
func _what_one_small_edit_costs_a_commit() -> void:
	for compress in [true, false]:
		var root: Node3D = await fresh_root()
		root.hflevel_compress = compress
		_level(root)
		await frame()
		var a := "user://vibe_team_a.hflevel"
		var b := "user://vibe_team_b.hflevel"
		root.save_hflevel(a)
		await HFVibe.settle_save(_tree, root, 3000)
		# One brush nudged half a unit: the smallest edit a session produces.
		var brushes: Array = root.draft_brushes_node.get_children()
		if not brushes.is_empty():
			root.nudge_brushes_by_id([str(brushes[0].brush_id)], Vector3(0.5, 0, 0))
		await frame()
		root.save_hflevel(b)
		await HFVibe.settle_save(_tree, root, 3000)

		var ba := _bytes(a)
		var bb := _bytes(b)
		var same := 0
		var limit: int = mini(ba.size(), bb.size())
		for i in limit:
			if ba[i] == bb[i]:
				same += 1
		var pct := 0.0 if limit == 0 else 100.0 * float(same) / float(limit)
		note(
			"hflevel_compress = %s" % compress,
			(
				"%d bytes -> %d bytes after nudging one brush of 45; %.1f%% of the "
				+ "overlapping bytes are unchanged"
			) % [ba.size(), bb.size(), pct]
		)
		if compress and pct < 50.0:
			note(
				"a compressed level file is a new file after any edit",
				(
					"expected: DEFLATE output diverges from the first changed byte, so a "
					+ "version control system sees a whole-file replacement. Recorded so the "
					+ "uncompressed number below is read against it"
				)
			)
		if not compress:
			note(
				"why the uncompressed percentage is not the finding",
				(
					"the nudge changes the length of one number, so every byte after it shifts "
					+ "and a positional comparison reports most of the file as different. A "
					+ "real diff tool would not be fooled by that. What decides whether the "
					+ "file is diffable is the line structure, which is measured below"
				)
			)
		for p in [a, b]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _what_the_file_looks_like() -> void:
	var root: Node3D = await fresh_root()
	root.hflevel_compress = false
	_level(root)
	await frame()
	var path := "user://vibe_team_plain.hflevel"
	root.save_hflevel(path)
	await HFVibe.settle_save(_tree, root, 3000)
	var raw := _bytes(path)
	note("uncompressed size for a 45-brush level", raw.size())
	var head := raw.slice(0, mini(64, raw.size())).get_string_from_utf8()
	note("the first 64 bytes", head.replace("\n", "\\n"))
	var text := raw.get_string_from_utf8()
	var lines := text.split("\n").size() if text != "" else 0
	note("lines in the file", lines)
	note(
		"what that means for a diff",
		(
			"a text format with one line per brush diffs and merges; a single-line JSON "
			+ "document or a binary blob does not, whatever the compression setting says"
		)
	)
	if lines <= 2 and raw.size() > 1000:
		flag(
			"an uncompressed level file is a single line",
			(
				(
					"%d bytes on %d line(s). `hflevel_compress = false` is the setting a team "
					+ "reaches for so the level can live in version control, and it produces a "
					+ "file git can store but not diff, not review and not merge. Pretty-printing "
					+ "the JSON when compression is off -- one object per line for brushes, "
					+ "entities and registries, keys in a stable order -- would make a level "
					+ "reviewable in a pull request and make most two-branch edits merge cleanly."
				)
				% [raw.size(), lines]
			)
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The other file a team commits. `scene-reopen` covers what survives a pack;
## this is only about how big the commit is and whether the two files disagree.
func _what_the_scene_carries_instead() -> void:
	var root: Node3D = await fresh_root()
	_level(root)
	await frame()
	var holder := root
	var stack: Array = [holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != holder:
			n.owner = holder
		for c in n.get_children():
			stack.append(c)
	var packed := PackedScene.new()
	var err := packed.pack(holder)
	note("pack()", err)
	if err != OK:
		return
	var scene_path := "user://vibe_team_level.tscn"
	ResourceSaver.save(packed, scene_path)
	var raw := _bytes(scene_path)
	note("the .tscn a team commits, for the same 45-brush level", "%d bytes" % raw.size())
	var lines := raw.get_string_from_utf8().split("\n").size()
	note("lines in the .tscn", lines)
	note(
		"what a team therefore commits per level",
		"a text .tscn plus a .hflevel beside it, which have to be committed together"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))
