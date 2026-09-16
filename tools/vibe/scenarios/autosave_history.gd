@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The autosave history: what "keep N backups" keeps.
##
## The safety net is the last thing anyone tests and the first thing anyone
## needs. Two questions: does the rotation keep the number it says, and does it
## keep *this level's* backups, or the last N files it happened to find.


func id() -> String:
	return "autosave-history"


func summary() -> String:
	return "whether the autosave rotation keeps the number of backups it says, and whose"


const DIR := "user://vibe_autosave"


func run() -> void:
	await _rotation_depth()
	await _two_levels_one_directory()
	await _same_second()


func _clean() -> void:
	var abs := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(abs):
		var hist := abs.path_join("autosave_history")
		if DirAccess.dir_exists_absolute(hist):
			for f in DirAccess.get_files_at(hist):
				DirAccess.remove_absolute(hist.path_join(f))
		for f in DirAccess.get_files_at(abs):
			DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.make_dir_recursive_absolute(abs.path_join("autosave_history"))


func _history() -> Array:
	var hist := ProjectSettings.globalize_path(DIR).path_join("autosave_history")
	var out: Array = []
	if DirAccess.dir_exists_absolute(hist):
		for f in DirAccess.get_files_at(hist):
			out.append(f)
	out.sort()
	return out


func _autosave(root: Node3D, times: int) -> void:
	for i in times:
		box(root, Vector3(32, 32, 32), Vector3(i * 64.0, 0, 0))
		root.save_hflevel(root.hflevel_autosave_path, true, true)
		await HFVibe.settle_save(_tree, root)
		# The history file name is timestamped to the second. Let the clock move.
		var until := Time.get_ticks_msec() + 1100
		while Time.get_ticks_msec() < until:
			await frame()


## Keep 3, autosave 6 times.
func _rotation_depth() -> void:
	_clean()
	var root: Node3D = await fresh_root()
	root.hflevel_autosave_path = DIR.path_join("levelA.hflevel")
	root.hflevel_autosave_keep = 3
	await _autosave(root, 6)
	var files := _history()
	note("keep = 3, autosaved 6 times: history files", files.size())
	note("  ", files)
	if files.size() != 3:
		flag("the autosave history kept %d backups with keep set to 3" % files.size(), files)


## Two levels whose autosave paths sit in the same folder.
func _two_levels_one_directory() -> void:
	_clean()
	var a: Node3D = await fresh_root("LevelA")
	a.hflevel_autosave_path = DIR.path_join("levelA.hflevel")
	a.hflevel_autosave_keep = 3
	await _autosave(a, 3)
	var after_a := _history()
	note("level A autosaved 3 times: history", after_a)

	var b: Node3D = await fresh_root("LevelB")
	b.hflevel_autosave_path = DIR.path_join("levelB.hflevel")
	b.hflevel_autosave_keep = 3
	await _autosave(b, 3)
	var after_b := _history()
	note("then level B autosaved 3 times: history", after_b)

	var a_left := 0
	var b_left := 0
	for f in after_b:
		if str(f).begins_with("levelA"):
			a_left += 1
		elif str(f).begins_with("levelB"):
			b_left += 1
	note("level A backups left", a_left)
	note("level B backups left", b_left)
	if a_left < 3:
		known(
			618,
			"autosaving one level deletes another level's backups",
			(
				("level A had 3 backups and has %d after level B autosaved 3 times. " % a_left)
				+ "_prune_autosave_history() takes the directory and the keep count and "
				+ "nothing else -- it sorts every *.hflevel in autosave_history by mtime "
				+ "and deletes past `keep`, with no filter on which level wrote them, while "
				+ "_write_autosave_rotation() names each file after its own level. Two "
				+ "levels saved side by side share one folder and one budget"
			)
		)


## Two saves inside one second.
func _same_second() -> void:
	_clean()
	var root: Node3D = await fresh_root()
	root.hflevel_autosave_path = DIR.path_join("levelC.hflevel")
	root.hflevel_autosave_keep = 10
	for i in 3:
		box(root, Vector3(32, 32, 32), Vector3(i * 64.0, 0, 0))
		root.save_hflevel(root.hflevel_autosave_path, true, true)
		await HFVibe.settle_save(_tree, root)
	var files := _history()
	note("three autosaves inside one second, keep = 10: history files", files.size())
	note("  ", files)
	if files.size() < 3:
		note(
			"the history file name is timestamped to the second",
			(
				(
					"'%s' -- three writes produced %d file(s), so a second save in the same "
					+ "second overwrites the first rather than joining it"
				)
				% [files[0] if not files.is_empty() else "none", files.size()]
			)
		)
