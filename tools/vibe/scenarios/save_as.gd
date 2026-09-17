@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Saving the same level to a second file, which is how a mapper keeps a copy.
##
## `persistence` and `chaos-io` both save and load, and both save to one path.
## The thing nobody has done in the sweep is save twice to two different files
## without editing in between -- Save As before a risky change, a copy of the
## level to hand to someone, a numbered backup at the end of a session. The file
## system skips a write whose payload hashes the same as the last one, and the
## hash it compares against does not record which file it came from.


func id() -> String:
	return "save-as"


func summary() -> String:
	return "whether saving an unchanged level to a second path writes a second file"


func run() -> void:
	await _two_paths_one_level()
	await _what_the_level_reports()
	await _an_edit_in_between()


func _paths() -> Array[String]:
	return [
		"user://vibe_saveas_a.hflevel",
		"user://vibe_saveas_b.hflevel",
		"user://vibe_saveas_c.hflevel",
	]


func _clean() -> void:
	for p in _paths():
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _level(root: Node3D) -> void:
	root.auto_spawn_player = false
	box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0))
	box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, -5))
	box(root, Vector3(0.3, 3, 10), Vector3(-5, 1.5, 0))


func _two_paths_one_level() -> void:
	_clean()
	var root: Node3D = await fresh_root()
	_level(root)
	await frame()
	var sizes: Array = []
	for p in _paths():
		root.save_hflevel(p)
		var settled: bool = await HFVibe.settle_save(_tree, root, 2000)
		(
			sizes
			. append(
				{
					"path": p.get_file(),
					"settled": settled,
					"exists": FileAccess.file_exists(p),
					"bytes": HFVibe.file_size(p),
				}
			)
		)
	note("the same level saved to three paths, unchanged in between", sizes)
	var written := sizes.filter(func(s: Dictionary) -> bool: return int(s["bytes"]) > 0)
	if written.size() < sizes.size():
		flag(
			"saving an unchanged level to a second path writes no file",
			(
				(
					"Three saves of one level to three names; %d of 3 exist afterwards. "
					+ "`_hflevel_thread_encode_and_write()` skips the write when the payload "
					+ "hash equals `_hflevel_last_hash`, and that field records only the hash, "
					+ "never the path it was written to. So the first save works and every "
					+ "later save to a *different* file is dropped as a duplicate. This is "
					+ "Save As, and a numbered backup, and handing a copy to a teammate: the "
					+ "thread settles, the save reports no error, and the file is not there."
				)
				% written.size()
			)
		)


## The other half: whether anything the dock can see distinguishes a skip from
## a write.
func _what_the_level_reports() -> void:
	_clean()
	var root: Node3D = await fresh_root()
	_level(root)
	await frame()
	var failures: Array = []
	var saved: Array = []
	if root.has_signal("hflevel_save_failed"):
		root.hflevel_save_failed.connect(
			func(p: String, m: String) -> void: failures.append("%s: %s" % [p, m])
		)
	if root.has_signal("hflevel_saved"):
		root.hflevel_saved.connect(func(p: String) -> void: saved.append(p))
	for p in _paths():
		root.save_hflevel(p)
		await HFVibe.settle_save(_tree, root, 2000)
	note("hflevel_saved signals", saved)
	note("hflevel_save_failed signals", failures)
	note(
		"last_encode_skipped after the third save",
		root.file_system.last_encode_skipped if root.file_system else "no file system"
	)
	var on_disk := _paths().filter(func(p: String) -> bool: return FileAccess.file_exists(p))
	note("files actually on disk", on_disk.map(func(p: String) -> String: return p.get_file()))
	if saved.size() > on_disk.size():
		flag(
			"the level announces a save for a file that was never written",
			(
				(
					"%d hflevel_saved signal(s) against %d file(s) on disk. Whatever the dock "
					+ "shows after a save -- a status line, a cleared modified marker -- is "
					+ "showing it for a write that did not happen."
				)
				% [saved.size(), on_disk.size()]
			)
		)


## And the control: with a real edit between the saves, every file should exist.
func _an_edit_in_between() -> void:
	_clean()
	var root: Node3D = await fresh_root()
	_level(root)
	await frame()
	var rows: Array = []
	var i := 0
	for p in _paths():
		box(root, Vector3(0.5, 0.5, 0.5), Vector3(i * 1.5, 0.25, 3))
		i += 1
		await frame()
		root.save_hflevel(p)
		await HFVibe.settle_save(_tree, root, 2000)
		rows.append({"path": p.get_file(), "bytes": HFVibe.file_size(p)})
	note("three saves with one brush added before each", rows)
	var missing := rows.filter(func(r: Dictionary) -> bool: return int(r["bytes"]) <= 0)
	if missing.is_empty():
		note("with an edit in between, all three files are written", true)
	else:
		flag("a save was dropped even after the level changed", missing)
	_clean()
