extends GutTest

## Whether a level that comes up outside the editor builds a playtest player.
##
## Two runs look identical from inside the level: Test Level plays the scene the
## mapper is editing, and the mapper pressing F5 on their own game plays that
## same scene. The only difference is who launched it, so the launcher has to say
## so. #719 made the level refuse by default, which stopped a shipped game
## getting a second character controller and stopped Test Level getting its first
## one (#771). These are the two halves, and they have to keep disagreeing.

const HFDockManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")
const HFPlaytestRequest = preload("res://addons/hammerforge/hf_playtest_request.gd")


func before_each() -> void:
	_clear_request()


func after_each() -> void:
	# A request left behind here would make every LevelRoot built by every later
	# test in the run spawn a player. Clear it whatever the test did.
	_clear_request()


func _clear_request() -> void:
	var abs_path := ProjectSettings.globalize_path(HFPlaytestRequest.PATH)
	if FileAccess.file_exists(HFPlaytestRequest.PATH):
		DirAccess.remove_absolute(abs_path)


func _dock() -> Node:
	var s := GDScript.new()
	s.source_code = """
extends Node

var level_root
var editor_interface = null

func _log(_msg: String, _is_error: bool = false) -> void:
	pass
"""
	s.reload()
	var dock := Node.new()
	dock.set_script(s)
	add_child_autoqfree(dock)
	return dock


func _root() -> LevelRoot:
	var root := LevelRoot.new()
	# Off, deliberately. This is the #719 default, and the point of every test
	# here is what happens when the level itself is not asking for a player.
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _player_of(root: LevelRoot) -> Node:
	return root.get_node_or_null("PlaytestPlayer")


func _write_request_aged(seconds_ago: float) -> void:
	var dir := HFPlaytestRequest.PATH.get_base_dir()
	var abs_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var file := FileAccess.open(HFPlaytestRequest.PATH, FileAccess.WRITE)
	file.store_string(str(Time.get_unix_time_from_system() - seconds_ago))
	file.close()


# ---------------------------------------------------------------------------
# The bug: Test Level launched a level with no player and no camera (#771)
# ---------------------------------------------------------------------------


func test_a_launched_playtest_builds_a_player_though_the_property_is_off() -> void:
	var dock := _dock()
	HFDockManageHandler.launch_playtest(dock)

	var root := _root()
	await wait_for_signal(root.bake_finished, 10.0)
	await wait_frames(2)

	assert_not_null(
		_player_of(root),
		"Test Level asked for the playtest, so the level builds the player it did not ask for itself"
	)


func test_the_player_a_launched_playtest_builds_carries_the_camera() -> void:
	# No player means no Camera3D, which is the grey window #771 was reported as.
	var dock := _dock()
	HFDockManageHandler.launch_playtest(dock)

	var root := _root()
	await wait_for_signal(root.bake_finished, 10.0)
	await wait_frames(2)

	var player := _player_of(root)
	assert_not_null(player, "the player is there to hang a camera off")
	if player == null:
		return
	var camera := player.find_child("MainCamera", true, false)
	assert_not_null(camera, "and it brought a camera, so the run renders something")
	if camera != null:
		assert_true((camera as Camera3D).current, "which is the current one")


# ---------------------------------------------------------------------------
# The other half: a run nobody asked for still gets nothing (#719)
# ---------------------------------------------------------------------------


func test_a_run_nobody_requested_builds_no_player() -> void:
	var root := _root()
	await wait_frames(4)

	assert_null(
		_player_of(root),
		"a mapper running their own game gets their own player and not a second one"
	)


func test_a_stale_request_is_not_a_request() -> void:
	# The editor can write a request and then never launch - a refused bake, a
	# crash. That file must not turn the mapper's next F5 into a playtest.
	_write_request_aged(HFPlaytestRequest.WINDOW_SECONDS + 60.0)

	var root := _root()
	await wait_frames(4)

	assert_null(_player_of(root), "an old request has expired rather than waiting around")


func test_the_request_is_consumed_by_the_run_it_launched() -> void:
	var dock := _dock()
	HFDockManageHandler.launch_playtest(dock)
	assert_true(FileAccess.file_exists(HFPlaytestRequest.PATH), "the launch wrote a request")

	var first := _root()
	await wait_for_signal(first.bake_finished, 10.0)
	await wait_frames(2)
	assert_not_null(_player_of(first), "the launched run took it")

	assert_false(
		FileAccess.file_exists(HFPlaytestRequest.PATH),
		"and took it away with it, so it cannot fire twice"
	)

	var second := _root()
	await wait_frames(4)
	assert_null(_player_of(second), "so the next run is an ordinary one")
