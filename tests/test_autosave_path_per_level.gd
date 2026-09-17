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
