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
const GutPreRun = preload("res://tests/support/gut_pre_run.gd")


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
