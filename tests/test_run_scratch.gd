extends GutTest
## Every test in a run writes its clipboard and its prefabs into a folder of the
## run's own, never the developer's (#1304).
##
## `tests/support/gut_pre_run.gd` points `HFPrefabSystem.clipboard_path` and
## `prefab_dir` there before the first test, from `.gutconfig.json` locally and
## from `-gpre_run_script` on CI. Had neither run, every test that copies or
## quick-saves would write to the real paths and two worktrees' runs would meet
## in one `user://` again, so this fails rather than let that pass quietly.

const HFPrefabSystemScript = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFUserPrefsScript = preload("res://addons/hammerforge/hf_user_prefs.gd")
const GutPreRun = preload("res://tests/support/gut_pre_run.gd")
const RealPrefsGuard = preload("res://tests/support/real_prefs_guard.gd")


func test_the_clipboard_is_this_runs_own():
	var path: String = HFPrefabSystemScript.clipboard_path
	assert_ne(
		path,
		HFPrefabSystemScript.CLIPBOARD_PATH,
		"the developer's clipboard; was tests/support/gut_pre_run.gd run?"
	)
	assert_true(path.begins_with(GutPreRun.folder() + "/"), "%s is this run's" % path)
	assert_true(path.ends_with(".hfprefab"), "and a prefab file, as the real one is")


func test_the_prefab_folder_is_this_runs_own():
	var dir: String = HFPrefabSystemScript.prefab_dir
	assert_ne(
		dir,
		HFPrefabSystemScript.PREFAB_DIR,
		"the project's prefab folder; was tests/support/gut_pre_run.gd run?"
	)
	assert_true(dir.begins_with(GutPreRun.folder() + "/"), "%s is this run's" % dir)
	assert_false(dir.begins_with("res://"), "nothing a test saves lands in the project")


func test_the_folder_is_named_for_this_process():
	# Two worktrees' runs are two processes, so their folders never meet.
	assert_true(GutPreRun.folder().ends_with(str(OS.get_process_id())))
	assert_true(DirAccess.dir_exists_absolute(GutPreRun.folder()), "and it is there to write into")


func test_a_copy_and_a_quick_save_land_in_the_runs_folder():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	var box = root.create_brush_from_info(
		{"size": Vector3(2, 2, 2), "center": Vector3.ZERO, "brush_id": "scratch"}
	)
	assert_true(root.prefab_system.copy_to_clipboard([box], []), "copied")
	assert_true(FileAccess.file_exists(HFPrefabSystemScript.clipboard_path), "to this run's file")
	var saved: String = root.prefab_system.quick_save_prefab([box], [], "run_scratch_box")
	assert_eq(saved.get_base_dir(), HFPrefabSystemScript.prefab_dir, "saved into this run's folder")
	assert_true(FileAccess.file_exists(saved))
	# Left as found, for the next script that counts the folder's files.
	DirAccess.remove_absolute(saved)
	DirAccess.remove_absolute(HFPrefabSystemScript.clipboard_path)


## The preferences too (#1581): the developer's own file is the one their editor
## reads, and a test that saved there wrote their recent files and dismissed hints.
func test_the_preferences_are_this_runs_own():
	var path: String = HFUserPrefsScript.prefs_path
	assert_ne(
		path,
		HFUserPrefsScript.PREFS_PATH,
		"the developer's preferences; was tests/support/gut_pre_run.gd run?"
	)
	assert_true(path.begins_with(GutPreRun.folder() + "/"), "%s is this run's" % path)


func test_a_preferences_save_lands_in_the_runs_folder():
	if HFUserPrefsScript.prefs_path == HFUserPrefsScript.PREFS_PATH:
		fail_test("not saved: that is the developer's own file")
		return
	var prefs := HFUserPrefsScript.new()
	prefs.data = HFUserPrefsScript._defaults()
	prefs.set_pref("grid_snap", 16.0)
	prefs.save()
	assert_true(FileAccess.file_exists(HFUserPrefsScript.prefs_path), "saved to this run's file")
	assert_eq(HFUserPrefsScript.load_prefs().get_pref("grid_snap"), 16.0, "and read back from it")
	DirAccess.remove_absolute(HFUserPrefsScript.prefs_path)


## `gut_post_run.gd` fails the run on what this reports, so it has to see each way
## a file can change, and stay quiet when one has not.
func test_the_guard_sees_a_file_written_rewritten_and_removed():
	assert_not_null(GutPreRun.real_prefs_before, "the real file was taken before the first test")
	var path := GutPreRun.folder().path_join("guard_probe.json")
	var none := RealPrefsGuard.fingerprint(path)
	assert_eq(RealPrefsGuard.change_since(none, path), "", "nothing there, and still nothing")

	_write(path, "{}")
	assert_string_contains(RealPrefsGuard.change_since(none, path), "was written")
	var first := RealPrefsGuard.fingerprint(path)
	_write(path, "{}")
	assert_eq(RealPrefsGuard.change_since(first, path), "", "the same bytes again are no change")
	_write(path, '{"grid_snap": 2.0}')
	assert_string_contains(RealPrefsGuard.change_since(first, path), "was rewritten")

	DirAccess.remove_absolute(path)
	assert_string_contains(RealPrefsGuard.change_since(first, path), "is gone")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
