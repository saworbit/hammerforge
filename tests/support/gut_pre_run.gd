extends GutHookScript
## Before the first test: the files a test can write go into a folder of this
## run's own, never the developer's (#1304).
##
## Every checkout shares one `user://`, so two suites running at once in two
## worktrees used the same clipboard file, and a palette sweep in one rewrote it
## under a clipboard test in the other. Quick Save Prefab wrote into the
## project's own `res://prefabs/`, beside the developer's prefabs. The folder is
## named for the process, so two runs never meet, and `gut_post_run.gd` takes it
## away at the end. `.gutconfig.json` names both hooks for a local run; CI reads
## no config and passes them on the command line. `tests/test_run_scratch.gd`
## fails when neither did.

const HFPrefabSystemScript = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")


## This run's folder. The same answer from any script in the process, so the
## post-run hook and the guard test find it without sharing state.
static func folder() -> String:
	return "user://hf_test_run_%d" % OS.get_process_id()


func run() -> void:
	var dir := folder()
	# A run under this process id that never finished may have left one.
	remove_folder(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	HFPrefabSystemScript.prefab_dir = dir.path_join("prefabs")
	HFPrefabSystemScript.clipboard_path = dir.path_join("clipboard.hfprefab")


## Take `path` away with everything in it.
static func remove_folder(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		remove_folder(path.path_join(dir_name))
	DirAccess.remove_absolute(path)
