extends GutTest

## A `.hflevel` the loader refuses must leave everything as it was, and say so.
##
## The loader already refused unreadable, malformed and newer files before it
## touched the level. It did not refuse them before pointing the paint system's
## region path at them, so the next region to unload wrote the open level's paint
## into the refused file's sidecar (#823). And the dock read the refusal as a
## load: it said "Loaded .hflevel", kept the file in recent files and put a load
## that changed nothing on the undo stack (#824).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const HFDockFileHandlerType = preload("res://addons/hammerforge/dock_file_handler.gd")

var root: LevelRoot
var _paths: Array = []


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	_paths = []


func after_each():
	for path in _paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _path(tag: String) -> String:
	var path := "user://hf_refusal_%s_%d.hflevel" % [tag, Time.get_ticks_usec()]
	_paths.append(path)
	return path


func _write_level(path: String, version: int) -> void:
	var bundle := {
		"version": version,
		"saved_at": "now",
		"settings": root._capture_hflevel_settings(),
		"state": root.capture_state(),
	}
	HFLevelIO.save_to_path(path, HFLevelIO.encode_variant(bundle), false)


func _write_malformed(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("this is not a level\n{}")
	file.close()


## The open level's sidecar, as a region unload would resolve it.
func _region_file() -> String:
	return root.paint_system._region_file_path(Vector2i(0, 0))


func _sidecar_of(path: String) -> String:
	var abs_path := ProjectSettings.globalize_path(path)
	return abs_path.get_base_dir().path_join("%s.hfregions" % abs_path.get_file().get_basename())


func _open_level_a() -> String:
	var a := _path("a")
	_write_level(a, HFLevelIO.FORMAT_VERSION)
	assert_true(root.load_hflevel(a), "level A is a good file and opens")
	assert_true(_region_file().begins_with(_sidecar_of(a)), "fixture: paint goes to A's sidecar")
	return a


# ===========================================================================
# The region path (#823)
# ===========================================================================


func test_a_newer_file_leaves_paint_going_to_the_open_level():
	assert_not_null(root.paint_system, "fixture: a level root with a paint system")
	var a := _open_level_a()
	var b := _path("b_newer")
	_write_level(b, HFLevelIO.FORMAT_VERSION + 1)

	assert_false(root.load_hflevel(b), "fixture: B is refused")

	assert_true(
		_region_file().begins_with(_sidecar_of(a)),
		"the next region unload still writes beside A, not beside the file that was refused"
	)


func test_a_malformed_file_leaves_paint_going_to_the_open_level():
	var a := _open_level_a()
	var b := _path("b_malformed")
	_write_malformed(b)

	assert_false(root.load_hflevel(b), "fixture: B is refused")

	assert_true(_region_file().begins_with(_sidecar_of(a)))


func test_a_file_that_loads_takes_its_paint_with_it():
	# The other half: moving the path after the checks must still move it.
	_open_level_a()
	var c := _path("c")
	_write_level(c, HFLevelIO.FORMAT_VERSION)

	assert_true(root.load_hflevel(c))

	assert_true(_region_file().begins_with(_sidecar_of(c)))


# ===========================================================================
# What the dock says (#824)
# ===========================================================================


func _dock() -> LoadDock:
	var dock := LoadDock.new()
	dock.level_root = root
	dock._user_prefs = Prefs.new()
	return dock


func test_the_dock_does_not_call_a_newer_file_loaded():
	var path := _path("dock_newer")
	_write_level(path, HFLevelIO.FORMAT_VERSION + 1)
	var dock := _dock()

	HFDockFileHandlerType.on_hflevel_load_selected(dock, path)

	assert_eq(dock.commits.size(), 0, "nothing loaded, so nothing to undo")
	assert_eq(dock._user_prefs.recent.size(), 0, "a file that did not open is not a recent file")
	assert_eq(dock.statuses.size(), 1)
	assert_true(dock.statuses[0][1], "reported as an error")
	assert_string_contains(str(dock.statuses[0][0]), "newer build")


func test_the_dock_does_not_call_a_malformed_file_loaded():
	var path := _path("dock_malformed")
	_write_malformed(path)
	var dock := _dock()

	HFDockFileHandlerType.on_hflevel_load_selected(dock, path)

	assert_eq(dock.commits.size(), 0)
	assert_eq(dock._user_prefs.recent.size(), 0)
	assert_eq(dock.statuses.size(), 1)
	assert_true(dock.statuses[0][1], "reported as an error")


func test_the_dock_still_loads_a_good_file():
	var path := _path("dock_good")
	_write_level(path, HFLevelIO.FORMAT_VERSION)
	var dock := _dock()

	HFDockFileHandlerType.on_hflevel_load_selected(dock, path)

	assert_eq(dock.commits.size(), 1, "one undo step for the load")
	assert_eq(dock._user_prefs.recent, [path])
	assert_eq(str(dock.statuses[-1][0]), "Loaded .hflevel")
	assert_false(dock.statuses[-1][1])


class LoadDock:
	extends RefCounted

	var level_root: Node = null
	var _user_prefs = null
	var statuses: Array = []
	var commits: Array = []

	func _set_status(message: String, is_error: bool = false, _timeout: float = 0.0) -> void:
		statuses.append([message, is_error])

	func show_toast(_message: String, _level: int = 0) -> void:
		pass

	func _commit_full_state_action(action_name: String, method_name: String, args: Array = []):
		commits.append([action_name, method_name])
		level_root.callv(method_name, args)


class Prefs:
	extends RefCounted

	var recent: Array = []

	func add_recent_file(path: String) -> void:
		recent.append(path)

	func save() -> void:
		pass
