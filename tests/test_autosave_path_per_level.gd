extends GutTest

## Which file a level autosaves to (#655).
##
## `hflevel_autosave_path` ships as one literal, so every level in a project
## pointed at `res://.hammerforge/autosave.hflevel` with autosave already running
## on a five minute timer. Two levels open in two tabs wrote over each other, and
## the loser found out when someone reopened it and got the other level back.
##
## `resolved_hflevel_path()` is what turns the stored value into a file, so these
## assert the resolution rather than the property.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFFileSystemType = preload("res://addons/hammerforge/systems/hf_file_system.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

const _A_SCENE := "res://levels/e1m1.tscn"
const _B_SCENE := "res://levels/e1m2.tscn"


## A level that believes it was loaded from `scene`.
##
## `scene_source_path()` walks up to the topmost node with no owner and reads its
## `scene_file_path`, which is how a level answers the question whichever editor
## tab is in front. Headless there is no such tab, so the chain is built here.
func _level_from_scene(scene: String) -> LevelRoot:
	var holder := Node3D.new()
	holder.scene_file_path = scene
	add_child_autoqfree(holder)
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	holder.add_child(root)
	root.owner = holder
	return root


func _unsaved_level() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


# ===========================================================================
# Two levels are two files
# ===========================================================================


func test_two_levels_do_not_share_one_autosave_file():
	var a := _level_from_scene(_A_SCENE)
	var b := _level_from_scene(_B_SCENE)
	assert_eq(
		a.hflevel_autosave_path,
		b.hflevel_autosave_path,
		"they still ship with the same stored default, which is what made this silent"
	)
	assert_ne(
		a.resolved_hflevel_path(),
		b.resolved_hflevel_path(),
		"and they resolve to different files, so neither can overwrite the other"
	)
	assert_eq(a.resolved_hflevel_path(), "res://.hammerforge/levels/e1m1.hflevel")
	assert_eq(b.resolved_hflevel_path(), "res://.hammerforge/levels/e1m2.hflevel")


func test_two_scenes_with_the_same_name_are_still_two_files():
	# `levels/test.tscn` beside `prototypes/test.tscn` is an ordinary way to end
	# up here, and a basename-only derivation would have put them back on one
	# file, which is the bug this is all about.
	var a := _level_from_scene("res://levels/test.tscn")
	var b := _level_from_scene("res://prototypes/test.tscn")
	assert_ne(
		a.resolved_hflevel_path(),
		b.resolved_hflevel_path(),
		"the scene's whole path under res:// is mirrored, not just its file name"
	)
	assert_eq(a.resolved_hflevel_path(), "res://.hammerforge/levels/test.hflevel")
	assert_eq(b.resolved_hflevel_path(), "res://.hammerforge/prototypes/test.hflevel")


func test_a_scene_at_the_project_root_keeps_a_flat_name():
	var a := _level_from_scene("res://e1m1.tscn")
	assert_eq(a.resolved_hflevel_path(), "res://.hammerforge/e1m1.hflevel")


func test_a_level_given_its_own_path_keeps_it():
	var a := _level_from_scene(_A_SCENE)
	a.hflevel_autosave_path = "res://somewhere/else.hflevel"
	assert_eq(
		a.resolved_hflevel_path(),
		"res://somewhere/else.hflevel",
		"the dialog's answer wins over the derived name"
	)


## An unsaved scene is the case where the autosave is the only copy of the work,
## so two of them sharing a file is the worst version of this rather than an edge.
func test_two_unsaved_levels_are_still_two_files():
	var a := _unsaved_level()
	var b := _unsaved_level()
	assert_ne(a.level_uid, "", "an unsaved level mints its own name")
	assert_ne(
		a.resolved_hflevel_path(),
		b.resolved_hflevel_path(),
		"and two of them do not share a file, which is when it matters most"
	)
	assert_string_starts_with(a.resolved_hflevel_path(), "res://.hammerforge/unsaved_")


func test_a_level_told_not_to_autosave_is_not_given_a_path_anyway():
	# `scene_keeps_brushes()` asks `has_hflevel_path()` before letting a
	# BAKE_ONLY scene drop its brushes, so inventing a path here loses work.
	var a := _unsaved_level()
	a.hflevel_autosave_path = ""
	assert_eq(a.resolved_hflevel_path(), "", "an empty path is a decision, not an absence")
	assert_false(a.has_hflevel_path(), "and the level says so")


# ===========================================================================
# The guard, for levels deliberately pointed at one file
# ===========================================================================

const _SHARED := "user://hf_autosave_collision.hflevel"


func after_each():
	if FileAccess.file_exists(_SHARED):
		DirAccess.remove_absolute(_SHARED)
	_clear_moved_files()


## A `.hflevel` the way Save Level writes one, recording the scene it came from.
func _write_level_file(scene: String) -> void:
	var bundle := {"version": HFLevelIO.FORMAT_VERSION, "settings": {}, "state": {}, "scene": scene}
	HFLevelIO.save_to_path(_SHARED, bundle, false)


func test_an_autosave_refuses_a_file_that_records_another_level():
	var b := _level_from_scene(_B_SCENE)
	_write_level_file(_A_SCENE)
	var files := HFFileSystemType.new(b)
	assert_eq(
		files.autosave_target_belongs_elsewhere(_SHARED),
		_A_SCENE,
		"the file says it holds e1m1 and this level is e1m2"
	)
	assert_eq(
		files.save_hflevel(_SHARED, true, true),
		ERR_FILE_CANT_WRITE,
		"so the autosave does not write over it"
	)
	files.shutdown()


func test_an_autosave_writes_over_its_own_file():
	var a := _level_from_scene(_A_SCENE)
	_write_level_file(_A_SCENE)
	var files := HFFileSystemType.new(a)
	assert_eq(files.autosave_target_belongs_elsewhere(_SHARED), "", "the file is this level's own")
	files.shutdown()


func test_a_file_that_names_no_scene_is_not_refused():
	var b := _level_from_scene(_B_SCENE)
	var bundle := {"version": HFLevelIO.FORMAT_VERSION, "settings": {}, "state": {}}
	HFLevelIO.save_to_path(_SHARED, bundle, false)
	var files := HFFileSystemType.new(b)
	assert_eq(
		files.autosave_target_belongs_elsewhere(_SHARED),
		"",
		(
			"written before a .hflevel said where it came from; refusing on a guess would stop"
			+ " a level autosaving to its own history"
		)
	)
	files.shutdown()


func test_a_manual_save_is_never_refused():
	var b := _level_from_scene(_B_SCENE)
	_write_level_file(_A_SCENE)
	var files := HFFileSystemType.new(b)
	assert_eq(
		files.save_hflevel(_SHARED, true, false),
		OK,
		"Save Level onto another level's file is a deliberate act; only the timer is guarded"
	)
	files.shutdown()


# ===========================================================================
# A level saved under a new name (#1591)
# ===========================================================================

const _MOVED_DIR := "res://hf_autosave_moved_scene_test"
const _MOVED_TSCN := _MOVED_DIR + "/level.tscn"
const _MOVED_SCN := _MOVED_DIR + "/level.scn"
const _MOVED_LEVEL := "res://.hammerforge/hf_autosave_moved_scene_test/level.hflevel"


func _clear_moved_files() -> void:
	var dir := _MOVED_LEVEL.get_base_dir()
	var history := dir.path_join("autosave_history")
	for folder in [history, dir]:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file_name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file_name))
		DirAccess.remove_absolute(folder)


## A level that autosaves, the way a mapper's does, loaded from `scene`.
func _autosaving_level(scene: String) -> LevelRoot:
	var level := _level_from_scene(scene)
	level.hflevel_autosave_enabled = true
	return level


## Let the level's write thread finish and hand its result back, the way
## `_process()` does every frame in the editor.
func _drain_writes(level: LevelRoot) -> void:
	var files: HFFileSystem = level.file_system
	var guard := 0
	while guard < 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			guard += 1
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


## The editor's Save Scene As, in its order: the scene is told it is about to be
## saved, is written and pointed at its new file, then told it was saved. The
## same scene name is an ordinary Ctrl+S.
func _save_scene(level: LevelRoot, scene: String) -> void:
	var scene_root := level.get_owner()
	scene_root.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	scene_root.scene_file_path = scene
	scene_root.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)


## What the autosave timer does.
func _autosave(level: LevelRoot) -> int:
	return level.save_hflevel(level.resolved_hflevel_path(), true, true)


func test_an_autosave_follows_a_scene_saved_as_scn():
	var level := _autosaving_level(_MOVED_TSCN)
	assert_eq(level.resolved_hflevel_path(), _MOVED_LEVEL)
	var refusals: Array = []
	level.autosave_failed.connect(func(message): refusals.append(message))
	assert_eq(level.save_hflevel(), OK, "Save Level")
	await _drain_writes(level)
	assert_eq(HFFileSystemType.read_recorded_scene(_MOVED_LEVEL), _MOVED_TSCN)
	_save_scene(level, _MOVED_SCN)
	assert_eq(
		level.resolved_hflevel_path(),
		_MOVED_LEVEL,
		"the derived name drops the extension, so the .scn resolves to the file the .tscn wrote"
	)
	await _drain_writes(level)
	assert_eq(
		HFFileSystemType.read_recorded_scene(_MOVED_LEVEL),
		_MOVED_SCN,
		"the record follows the scene as soon as it is saved under its new name"
	)
	assert_eq(_autosave(level), OK, "so the next autosave writes")
	await _drain_writes(level)
	assert_eq(refusals, [], "and nothing was refused")


func test_an_ordinary_scene_save_writes_no_level_file():
	var level := _autosaving_level(_MOVED_TSCN)
	assert_eq(level.save_hflevel(), OK)
	await _drain_writes(level)
	_save_scene(level, _MOVED_TSCN)
	assert_null(level.file_system._hflevel_thread, "Ctrl+S under the same name starts no write")
	assert_true(level.file_system._hflevel_pending.is_empty(), "and queues none")


func test_a_level_that_does_not_autosave_is_not_written_by_save_scene_as():
	var level := _autosaving_level(_MOVED_TSCN)
	assert_eq(level.save_hflevel(), OK)
	await _drain_writes(level)
	level.hflevel_autosave_enabled = false
	_save_scene(level, _MOVED_SCN)
	assert_null(level.file_system._hflevel_thread, "the .hflevel is the mapper's to write")
	assert_eq(HFFileSystemType.read_recorded_scene(_MOVED_LEVEL), _MOVED_TSCN)


func test_save_scene_as_does_not_take_over_another_levels_file():
	var b := _autosaving_level(_B_SCENE)
	b.hflevel_autosave_path = _SHARED
	_write_level_file(_A_SCENE)
	var refusals: Array = []
	b.autosave_failed.connect(func(message): refusals.append(message))
	_save_scene(b, "res://levels/e1m2.scn")
	assert_null(b.file_system._hflevel_thread, "the file names e1m1, which this level never was")
	assert_eq(HFFileSystemType.read_recorded_scene(_SHARED), _A_SCENE, "so its record stays")
	assert_eq(_autosave(b), ERR_FILE_CANT_WRITE, "and the autosave is still refused")
	assert_eq(refusals.size(), 1, "with its reason")
	assert_string_contains(str(refusals), "holds e1m1.tscn")


## Save Scene As leaves the old `.tscn` on disk, and that copy resolves to the
## same `.hflevel`. Once the record has followed the scene, the copy is the
## other level, and its autosave is the one refused.
func test_the_copy_left_under_the_old_name_does_not_autosave_over_the_level():
	var level := _autosaving_level(_MOVED_TSCN)
	assert_eq(level.save_hflevel(), OK)
	await _drain_writes(level)
	_save_scene(level, _MOVED_SCN)
	await _drain_writes(level)
	var copy := _autosaving_level(_MOVED_TSCN)
	assert_eq(copy.resolved_hflevel_path(), _MOVED_LEVEL, "the copy resolves to the same file")
	var refusals: Array = []
	copy.autosave_failed.connect(func(message): refusals.append(message))
	assert_eq(_autosave(copy), ERR_FILE_CANT_WRITE, "the copy's autosave is refused")
	assert_eq(refusals.size(), 1, "and says why")
	assert_eq(
		HFFileSystemType.read_recorded_scene(_MOVED_LEVEL),
		_MOVED_SCN,
		"the level's file is untouched"
	)
