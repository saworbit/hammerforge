extends GutTest
## Drives the real HFDockManageHandler playtest entry points through a dock
## stand-in and a real level, so the severity blocking, the temporary spawn and
## cordon moves, and the undo stack are all observed on the production code.

const HFDockManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const HFPlaytestRequest = preload("res://addons/hammerforge/hf_playtest_request.gd")
const UndoCoverageTests = preload("res://tests/test_dock_undo_coverage.gd")


## The real level, with the bake and the cordon calls counted instead of run.
class QuickPlayLevel:
	extends LevelRoot

	var bake_result := true
	var bake_calls := 0
	var reconcile_calls := 0
	var cordon_visual_calls := 0
	var cordon_from_selection_calls := 0
	## How many cordons the bake was handed, or -1 before one ran.
	var cordons_at_bake := -1
	## Run while the bake runs, for what changes the level meanwhile.
	var on_bake := Callable()

	func bake(
		_apply_cuts: bool = true,
		_hide_live: bool = false,
		_collision_layer_mask: int = 0,
		_preview_mode: int = 0,
		_force_csg: bool = false
	) -> bool:
		bake_calls += 1
		cordons_at_bake = get_cordon_regions().size()
		if on_bake.is_valid():
			on_bake.call()
		return bake_result

	func set_cordon_from_selection(_nodes: Array, _index: int = 0) -> bool:
		cordon_from_selection_calls += 1
		cordon_enabled = true
		cordon_aabb = AABB(Vector3.ZERO, Vector3(64, 64, 64))
		return true

	func tag_full_reconcile() -> void:
		reconcile_calls += 1

	func update_cordon_visual() -> void:
		cordon_visual_calls += 1

	## Each export, with where the spawn stood when it was written. Counted
	## rather than written: the real one writes into user://, which the mapper's
	## own editor shares.
	var exports: Array = []

	func export_playtest_scene(
		path: String, _include_debug_rig: bool = true, _metadata: Dictionary = {}
	) -> bool:
		var at: Variant = null
		var start: Node3D = spawn_system.get_active_spawn()
		if start:
			at = start.global_position
		exports.append({"path": path, "spawn_position": at})
		return true


## Answers validation with whatever the test sets.
class SpawnSystemStub:
	extends RefCounted

	var level: QuickPlayLevel
	var active_spawn: Node3D
	## What `create_default_spawn()` makes; null for a level that cannot have one.
	var made_spawn: Node3D
	var validation: Dictionary = {"valid": true, "severity": 0, "issues": PackedStringArray()}
	## What the check says before any bake, when that differs from after it.
	var validation_unbaked: Dictionary = {}
	## How many bakes had run each time the spawn was judged.
	var bakes_when_judged: Array = []
	var created_spawns: int = 0
	var debug_calls: int = 0

	func get_active_spawn() -> Node3D:
		return active_spawn

	func create_default_spawn() -> Node3D:
		created_spawns += 1
		if made_spawn:
			active_spawn = made_spawn
		return made_spawn

	func validate_spawn(_spawn, _mask) -> Dictionary:
		bakes_when_judged.append(level.bake_calls)
		if level.bake_calls == 0 and not validation_unbaked.is_empty():
			return validation_unbaked
		return validation

	func show_validation_debug(_spawn, _validation, _seconds) -> void:
		debug_calls += 1

	func cleanup_debug() -> void:
		pass

	func auto_fix_spawn(spawn: Node3D, result: Dictionary) -> void:
		spawn.global_position = result.get("suggested_position", spawn.global_position)


class StateSystemStub:
	extends RefCounted

	func capture_state(_include_all: bool = false) -> Dictionary:
		return {"snapshot": true}

	func restore_state(_state: Dictionary) -> void:
		pass


var dock: Node
var root: QuickPlayLevel
var spawn: DraftEntity


func before_each():
	root = QuickPlayLevel.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.spawn_system = SpawnSystemStub.new()
	root.spawn_system.level = root
	root.state_system = StateSystemStub.new()
	spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 30.0}
	root.add_child(spawn)
	spawn.global_position = Vector3(10, 0, 5)
	root.spawn_system.active_spawn = spawn
	dock = Node.new()
	dock.set_script(_dock_shim_script())
	# The editor's manager, as a spawn fix calls it: an object, a method and its
	# arguments. Godot's own UndoRedo takes a Callable instead.
	dock.undo_redo = UndoCoverageTests.SteppingUndoRedo.new()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock._plugin = _make_camera_holder()


func after_each():
	# Every launch leaves a playtest request, and a live one makes the next real
	# LevelRoot in the run build a player.
	HFPlaytestRequest.consume()
	dock = null
	root = null
	spawn = null


func _make_camera_holder() -> Node:
	var holder := Node.new()
	holder.set_script(_camera_holder_shim_script())
	add_child_autoqfree(holder)
	var camera := Camera3D.new()
	holder.add_child(camera)
	camera.global_position = Vector3(100, 50, 200)
	camera.global_rotation = Vector3(0, deg_to_rad(90.0), 0)
	holder.last_3d_camera = camera
	return holder


func _camera_holder_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node

var last_3d_camera: Camera3D
"""
	s.reload()
	return s


func _dock_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node

enum DockSelectionRequirement { MANAGED, BRUSHES_ONLY, ENTITIES_ONLY, NATIVE_ALLOWED }

var level_root
var _plugin
var undo_redo = null
var editor_interface = null
var _selection_nodes: Array = []
var selection_guard_passes: bool = true
var toasts: Array = []
var logs: Array = []
var guarded_actions: Array = []

func _log(msg: String, _is_error: bool = false) -> void:
	logs.append(msg)

func show_toast(message: String, level: int = 0) -> void:
	toasts.append({"message": message, "level": level})

func get_collision_layer_mask() -> int:
	return 1

func _warn_missing_dependencies() -> void:
	pass

func _set_status_warning(_text: String, _seconds: float) -> void:
	pass

func _guard_selection_action(action_name: String, _requirement: int = 0) -> bool:
	guarded_actions.append(action_name)
	return selection_guard_passes

func toast_messages() -> Array:
	var out: Array = []
	for t in toasts:
		out.append(t["message"])
	return out

func worst_toast_level() -> int:
	var worst := -1
	for t in toasts:
		worst = max(worst, int(t["level"]))
	return worst
"""
	s.reload()
	return s


func _spawn_angle() -> float:
	return float(spawn.entity_data.get("angle", 0.0))


func _assert_spawn_untouched(context: String) -> void:
	assert_eq(spawn.global_position, Vector3(10, 0, 5), "%s: spawn position restored" % context)
	assert_almost_eq(_spawn_angle(), 30.0, 0.001, "%s: spawn angle restored" % context)


# ===========================================================================
# Play from Camera: the temporary spawn move
# ===========================================================================


func test_play_from_camera_moves_the_spawn_and_puts_it_back():
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	assert_eq(root.bake_calls, 1, "The handler bakes once before launching")
	_assert_spawn_untouched("After a clean launch")


func test_play_from_camera_leaves_no_undo_step_behind():
	# The spawn is always put back, so an undo action recording the move would
	# describe a position the scene does not have. Redo used to move the spawn
	# to the camera for good.
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	assert_false(dock.undo_redo.has_undo(), "A temporary spawn move must not enter undo")
	assert_false(dock.undo_redo.has_redo(), "and must not leave a redo step either")


func test_play_from_camera_restores_the_spawn_when_the_bake_fails():
	root.bake_result = false
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	_assert_spawn_untouched("After a failed bake")
	assert_true(
		"Test cancelled because the level could not be baked" in dock.toast_messages(),
		"A failed bake must say so"
	)


func test_play_from_camera_blocks_and_restores_on_severity_2():
	root.spawn_system.validation = {
		"valid": false,
		"severity": 2,
		"issues": PackedStringArray(["No floor beneath spawn"]),
	}
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	_assert_spawn_untouched("After a blocking validation")
	assert_eq(dock.worst_toast_level(), 2, "Severity 2 reports at error level")
	assert_false(dock.undo_redo.has_undo(), "The blocked path leaves no undo step either")


func test_play_from_camera_warns_but_launches_on_severity_1():
	root.spawn_system.validation = {
		"valid": true,
		"severity": 1,
		"issues": PackedStringArray(["Low clearance"]),
	}
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	assert_eq(root.bake_calls, 1, "Severity 1 still bakes")
	assert_eq(dock.worst_toast_level(), 1, "Severity 1 warns rather than blocking")
	_assert_spawn_untouched("After a warning launch")


func test_play_from_camera_reports_a_missing_camera():
	dock._plugin.last_3d_camera = null
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	assert_true("No editor camera available" in dock.toast_messages())
	assert_eq(root.bake_calls, 0, "No camera means no bake")
	_assert_spawn_untouched("Without a camera")


# ===========================================================================
# Play Selected Area: the temporary cordon
# ===========================================================================


func test_play_selected_area_restores_the_cordon():
	dock._selection_nodes = [autofree(Node3D.new())]
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3(10, 10, 10), Vector3(50, 50, 50))
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(root.cordon_from_selection_calls, 1, "The selection defines the play area")
	assert_true(root.cordon_enabled, "Cordon enabled flag restored")
	assert_eq(root.cordon_aabb, AABB(Vector3(10, 10, 10), Vector3(50, 50, 50)), "Cordon restored")


func test_play_selected_area_restores_the_cordon_when_the_bake_fails():
	dock._selection_nodes = [autofree(Node3D.new())]
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	root.bake_result = false
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_false(root.cordon_enabled, "Cordon disabled flag restored on the error path")
	assert_eq(root.cordon_aabb, AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10)), "Bounds restored")


func test_play_selected_area_restores_the_cordon_when_validation_blocks():
	dock._selection_nodes = [autofree(Node3D.new())]
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3(1, 2, 3), Vector3(8, 8, 8))
	root.spawn_system.validation = {
		"valid": false,
		"severity": 2,
		"issues": PackedStringArray(["No floor beneath spawn"]),
	}
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(root.cordon_aabb, AABB(Vector3(1, 2, 3), Vector3(8, 8, 8)), "Bounds restored")
	assert_eq(dock.worst_toast_level(), 2, "Severity 2 reports at error level")


func _other_cordons() -> Array[AABB]:
	var extra: Array[AABB] = [
		AABB(Vector3(500, 0, 0), Vector3(16, 16, 16)),
		AABB(Vector3(-500, 0, 0), Vector3(16, 16, 16)),
	]
	root.cordon_extra_aabbs = extra
	return extra


func test_play_selected_area_bakes_the_selection_alone():
	dock._selection_nodes = [autofree(Node3D.new())]
	root.cordon_enabled = true
	var extra := _other_cordons()
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(
		root.cordons_at_bake, 1, "the level's other cordons would add their rooms to the area"
	)
	assert_eq(root.cordon_extra_aabbs, extra, "and they are back after it")


func test_play_selected_area_bakes_the_selection_with_the_first_cordon_switched_off():
	dock._selection_nodes = [autofree(Node3D.new())]
	root.cordon_enabled = true
	var active: Array[bool] = [false]
	root.cordon_active = active
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(root.cordons_at_bake, 1, "the area is the first cordon, so it has to bake")
	assert_eq(root.cordon_active, active, "and the first cordon is off again after it")


func test_play_selected_area_puts_the_other_cordons_back_when_the_bake_fails():
	dock._selection_nodes = [autofree(Node3D.new())]
	var extra := _other_cordons()
	root.bake_result = false
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(root.cordon_extra_aabbs, extra)


func test_play_selected_area_puts_the_other_cordons_back_when_validation_blocks():
	dock._selection_nodes = [autofree(Node3D.new())]
	var extra := _other_cordons()
	root.spawn_system.validation = {
		"valid": false,
		"severity": 2,
		"issues": PackedStringArray(["No floor beneath spawn"]),
	}
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(root.cordon_extra_aabbs, extra)


func test_play_selected_area_needs_a_selection():
	dock._selection_nodes = []
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_true("Select brushes to define play area" in dock.toast_messages())
	assert_eq(root.cordon_from_selection_calls, 0, "Nothing selected means no cordon change")
	assert_eq(root.bake_calls, 0, "and no bake")


func test_play_selected_area_respects_the_selection_guard():
	dock._selection_nodes = [autofree(Node3D.new())]
	dock.selection_guard_passes = false
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_true("Play Selected Area" in dock.guarded_actions, "The guard is asked first")
	assert_eq(root.cordon_from_selection_calls, 0, "A refused guard stops before the cordon moves")


# ===========================================================================
# What the scene holds when the run starts (#822)
# ===========================================================================


## Godot saves the edited scene on the way into a run, so whatever the scene
## holds when `play_current_scene()` is called is what lands in the file.
func _watch_launch() -> Node:
	var s := GDScript.new()
	s.source_code = """
extends Node

var root
var spawn
var seen: Array = []
var custom: Array = []

func play_custom_scene(path: String) -> void:
	custom.append(path)

func play_current_scene() -> void:
	seen.append({
		"spawn_position": spawn.global_position,
		"spawn_angle": float(spawn.entity_data.get("angle", 0.0)),
		"cordon_enabled": root.cordon_enabled,
		"cordon_aabb": root.cordon_aabb,
		"cordon_extra_aabbs": root.cordon_extra_aabbs.duplicate(),
	})
"""
	s.reload()
	var editor := Node.new()
	editor.set_script(s)
	add_child_autoqfree(editor)
	editor.root = root
	editor.spawn = spawn
	dock.editor_interface = editor
	return editor


func test_play_from_camera_launches_with_the_authored_spawn_in_the_scene():
	var editor := _watch_launch()
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	assert_eq(editor.seen.size(), 1, "fixture: the run was launched")
	assert_eq(
		editor.seen[0]["spawn_position"],
		Vector3(10, 0, 5),
		"the save before the run writes the spawn the mapper placed, not the camera"
	)
	assert_almost_eq(float(editor.seen[0]["spawn_angle"]), 30.0, 0.001)


func test_play_from_camera_hands_the_camera_pose_to_the_run():
	_watch_launch()
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_false(request.is_empty(), "the launch left a request")
	assert_eq(request.get("spawn_position"), Vector3(100, 50, 200), "the run starts at the camera")
	assert_almost_eq(float(request.get("spawn_yaw_degrees", 0.0)), 90.0, 0.01)


func test_play_selected_area_launches_with_the_authored_cordon_in_the_scene():
	var editor := _watch_launch()
	dock._selection_nodes = [autofree(Node3D.new())]
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(editor.seen.size(), 1, "fixture: the run was launched")
	assert_false(editor.seen[0]["cordon_enabled"], "the scene file keeps the cordon off")
	assert_eq(editor.seen[0]["cordon_aabb"], AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10)))


func test_play_selected_area_launches_with_the_other_cordons_in_the_scene():
	var editor := _watch_launch()
	dock._selection_nodes = [autofree(Node3D.new())]
	var extra := _other_cordons()
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	assert_eq(editor.seen.size(), 1, "fixture: the run was launched")
	assert_eq(editor.seen[0]["cordon_extra_aabbs"], extra, "the scene file keeps every cordon")


func test_play_selected_area_hands_the_play_area_to_the_run():
	_watch_launch()
	dock._selection_nodes = [autofree(Node3D.new())]
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_eq(
		request.get("cordon"),
		AABB(Vector3.ZERO, Vector3(64, 64, 64)),
		"the run bakes the selection"
	)


func test_a_plain_test_level_hands_nothing_over():
	_watch_launch()
	await HFDockManageHandler.on_quick_play(dock)
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_false(request.is_empty(), "the launch left a request")
	assert_false(request.has("spawn_position"), "the run uses the level's own spawn")
	assert_false(request.has("cordon"), "and bakes the whole level")


## Switching scene tabs takes the level out of the tree. Its bake stopped on a
## script error; now it stops plainly, Quick Play launches nothing, and Quick Play
## once the mapper is back bakes again (#1290). The level here bakes for real.
func test_quick_play_stops_plainly_when_the_level_leaves_the_tree_mid_bake():
	var real := LevelRoot.new()
	real.auto_spawn_player = false
	real.hflevel_autosave_enabled = false
	add_child_autoqfree(real)
	real.create_brush_from_info({"size": Vector3(32, 2, 32), "brush_id": "floor"})
	dock.level_root = real
	HFPlaytestRequest.consume()
	var errors_before := get_errors().size()
	HFDockManageHandler.on_quick_play(dock)
	assert_true(real.is_bake_in_flight(), "Quick Play is baking")
	remove_child(real)
	for _i in 6:
		await get_tree().process_frame
	assert_eq(get_errors().size(), errors_before, "it raised no error")
	assert_false(real.is_bake_in_flight(), "the bake stopped")
	assert_true(
		dock.toast_messages().any(func(text): return str(text).contains("cancelled")),
		"Quick Play said it was cancelled"
	)
	assert_false(FileAccess.file_exists(HFPlaytestRequest.PATH), "and launched nothing")
	add_child(real)
	await HFDockManageHandler.on_quick_play(dock)
	assert_eq(
		real.get_last_bake_status(), LevelRoot.BakeStatus.SUCCESS, "back on the tab, it bakes"
	)


# ===========================================================================
# The spawn fix dialog (#1002)
# ===========================================================================


func _blocked_with_suggestion(suggested: Vector3) -> void:
	root.spawn_system.validation = {
		"valid": false,
		"severity": 2,
		"issues": PackedStringArray(["Spawn inside a brush"]),
		"suggested_position": suggested,
	}


func _fix_dialog() -> ConfirmationDialog:
	for child in dock.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			return child
	return null


func test_fix_and_play_moves_the_spawn_where_the_check_says():
	_blocked_with_suggestion(Vector3(12, 0, 5))
	await HFDockManageHandler.on_quick_play(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	assert_eq(dialog.ok_button_text, "Fix & Play")
	dialog.confirmed.emit()
	assert_eq(spawn.global_position, Vector3(12, 0, 5), "moved where the check said")
	assert_true(dock.undo_redo.has_undo(), "as an undo step")


func test_the_dialog_offers_no_fix_when_there_is_nowhere_to_move_to():
	# It said Fix & Play, toasted that the spawn was fixed, and started the player
	# where they were, inside the brush.
	_blocked_with_suggestion(Vector3(10, 0, 5))
	await HFDockManageHandler.on_quick_play(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	assert_eq(dialog.ok_button_text, "Play Anyway")
	dialog.confirmed.emit()
	assert_eq(spawn.global_position, Vector3(10, 0, 5), "the spawn stays")
	assert_false(dock.undo_redo.has_undo(), "with nothing to undo")
	for message in dock.toast_messages():
		assert_false(str(message).contains("fixed"), "and nothing claims a fix: %s" % message)


## Anything can free the spawn while the dialog is up, an agent's edit or a
## reload, and OK was then an engine error for a freed capture. With the level
## still open it plays, from wherever the level now starts.
func test_ok_after_the_spawn_went_plays_without_an_error():
	_blocked_with_suggestion(Vector3(12, 0, 5))
	await HFDockManageHandler.on_quick_play(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	root.remove_child(spawn)
	spawn.free()
	var errors_before := get_errors().size()
	dialog.confirmed.emit()
	assert_eq(get_errors().size(), errors_before, "OK raised nothing")
	assert_true(FileAccess.file_exists(HFPlaytestRequest.PATH), "and played")


## With the level gone there is nothing to play, so OK closes the dialog and
## launches nothing.
func test_ok_after_the_level_went_launches_nothing():
	_blocked_with_suggestion(Vector3(12, 0, 5))
	await HFDockManageHandler.on_quick_play(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	remove_child(root)
	root.free()
	var errors_before := get_errors().size()
	dialog.confirmed.emit()
	assert_eq(get_errors().size(), errors_before, "OK raised nothing")
	assert_false(FileAccess.file_exists(HFPlaytestRequest.PATH), "and launched nothing")


## It moved the level's spawn to the camera, as an undo step, and then played
## from the spawn (#1010).
func test_fix_and_play_from_the_camera_moves_the_start_and_not_the_spawn():
	_blocked_with_suggestion(Vector3(101, 50, 200))
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked camera spot asks first")
	if dialog == null:
		return
	assert_eq(dialog.ok_button_text, "Fix & Play")
	dialog.confirmed.emit()
	_assert_spawn_untouched("After Fix & Play from the camera")
	assert_false(dock.undo_redo.has_undo(), "with nothing to undo")
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_eq(
		request.get("spawn_position"), Vector3(101, 50, 200), "the run starts where the check said"
	)
	assert_almost_eq(
		float(request.get("spawn_yaw_degrees", 0.0)), 90.0, 0.01, "facing the camera's way"
	)


func test_play_anyway_from_the_camera_starts_at_the_camera():
	_blocked_with_suggestion(Vector3(100, 50, 200))
	await HFDockManageHandler.on_quick_play_from_camera(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked camera spot asks first")
	if dialog == null:
		return
	assert_eq(dialog.ok_button_text, "Play Anyway")
	dialog.confirmed.emit()
	_assert_spawn_untouched("After Play Anyway from the camera")
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_eq(request.get("spawn_position"), Vector3(100, 50, 200), "the run starts at the camera")


## It played the whole level (#1010).
func test_fix_and_play_after_a_selected_area_plays_the_area():
	dock._selection_nodes = [autofree(Node3D.new())]
	_blocked_with_suggestion(Vector3(12, 0, 5))
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	dialog.confirmed.emit()
	assert_eq(spawn.global_position, Vector3(12, 0, 5), "the level's spawn is the one fixed")
	assert_true(dock.undo_redo.has_undo(), "as an undo step")
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_eq(
		request.get("cordon"), AABB(Vector3.ZERO, Vector3(64, 64, 64)), "the run bakes the area"
	)


func test_play_anyway_after_a_selected_area_plays_the_area():
	dock._selection_nodes = [autofree(Node3D.new())]
	_blocked_with_suggestion(Vector3(10, 0, 5))
	await HFDockManageHandler.on_quick_play_selected_area(dock)
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	assert_eq(dialog.ok_button_text, "Play Anyway")
	dialog.confirmed.emit()
	var request: Dictionary = HFPlaytestRequest.consume()
	assert_eq(
		request.get("cordon"), AABB(Vector3.ZERO, Vector3(64, 64, 64)), "the run bakes the area"
	)


# ===========================================================================
# The spawn every playtest starts from (#1460)
# ===========================================================================

## The four ways the dock starts a playtest.
const ENTRY_POINTS := ["test_level", "from_camera", "selected_area", "export"]


## Start a playtest one of those ways, with the launch watched, and give back
## the watcher.
func _play(entry: String) -> Node:
	var editor := _watch_launch()
	match entry:
		"test_level":
			await HFDockManageHandler.on_quick_play(dock)
		"from_camera":
			await HFDockManageHandler.on_quick_play_from_camera(dock)
		"selected_area":
			dock._selection_nodes = [autofree(Node3D.new())]
			await HFDockManageHandler.on_quick_play_selected_area(dock)
		"export":
			await HFDockManageHandler.on_export_playtest(dock)
	return editor


func _launches(editor: Node) -> int:
	return editor.seen.size() + editor.custom.size()


func _undo_step_names() -> Array:
	var names: Array = []
	for step in dock.undo_redo._steps:
		names.append(step["name"])
	return names


func test_every_entry_point_judges_the_spawn_once_after_its_bake(
	entry = use_parameters(ENTRY_POINTS)
):
	await _play(entry)
	assert_eq(
		root.spawn_system.bakes_when_judged,
		[1],
		"%s judged its spawn once, on the level it baked" % entry
	)


func test_a_level_with_no_spawn_gets_one_as_one_undo_step(entry = use_parameters(ENTRY_POINTS)):
	root.spawn_system.active_spawn = null
	root.spawn_system.made_spawn = spawn
	var editor: Node = await _play(entry)
	assert_eq(root.spawn_system.created_spawns, 1, "%s made a spawn" % entry)
	assert_eq(_undo_step_names(), ["Auto-create player_start"], "as one undo step")
	assert_true(
		"No player_start found — auto-creating default spawn" in dock.toast_messages(),
		"and said so"
	)
	assert_eq(root.spawn_system.bakes_when_judged, [1], "judged it after the bake")
	assert_eq(_launches(editor), 1, "and launched")


## Test from Camera stopped when no spawn could be made, and the other three
## baked and launched a run whose start nobody had judged. Every one now stops,
## before its bake, and says so.
func test_a_level_that_cannot_have_a_spawn_starts_nothing(entry = use_parameters(ENTRY_POINTS)):
	root.spawn_system.active_spawn = null
	root.spawn_system.made_spawn = null
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var editor: Node = await _play(entry)
	assert_eq(root.bake_calls, 0, "%s baked nothing for a run with no start" % entry)
	assert_eq(_launches(editor), 0, "launched nothing")
	assert_eq(root.exports.size(), 0, "exported nothing")
	assert_eq(dock.worst_toast_level(), 2, "and said so as an error")
	assert_false(dock.undo_redo.has_undo(), "It leaves no undo step")
	assert_false(root.cordon_enabled, "and the cordon as it was")
	assert_eq(root.cordon_aabb, AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10)))


## Anything can take the spawn away while the level bakes, an agent's edit or
## an undo. The run would start wherever the level then falls back to, which
## nobody judged, so it stops and says so.
func test_a_spawn_gone_during_the_bake_stops_the_run(entry = use_parameters(ENTRY_POINTS)):
	root.cordon_enabled = false
	root.on_bake = func():
		root.spawn_system.active_spawn = null
		root.remove_child(spawn)
		spawn.free()
	var editor: Node = await _play(entry)
	assert_eq(root.bake_calls, 1, "fixture: %s baked" % entry)
	assert_eq(_launches(editor), 0, "launched nothing")
	assert_eq(root.exports.size(), 0, "exported nothing")
	assert_true("Spawn was removed during bake" in dock.toast_messages(), "and said why")
	assert_false(root.cordon_enabled, "with the cordon as it was")


## Export Playtest judged the spawn before its bake, by whatever collision the
## last bake left. A spawn the new bake leaves over nothing was exported and
## launched.
func test_export_judges_a_spawn_the_bake_breaks_on_the_baked_level():
	root.spawn_system.validation_unbaked = {
		"valid": true, "severity": 0, "issues": PackedStringArray()
	}
	_blocked_with_suggestion(Vector3(12, 0, 5))
	var editor: Node = await _play("export")
	assert_eq(root.bake_calls, 1, "Export baked")
	assert_eq(root.exports.size(), 0, "and wrote nothing for a spawn the baked level fails")
	assert_eq(editor.custom.size(), 0, "nor launched it")
	assert_eq(dock.worst_toast_level(), 2, "It says so as an error")
	assert_not_null(_fix_dialog(), "and asks, as Test Level does")


## And a spawn the bake puts right was refused by the stale check, with no bake.
func test_export_plays_a_spawn_its_bake_puts_right():
	root.spawn_system.validation_unbaked = {
		"valid": false,
		"severity": 2,
		"issues": PackedStringArray(["Floating in space — no floor below"]),
	}
	var editor: Node = await _play("export")
	assert_eq(root.bake_calls, 1, "Export baked")
	assert_eq(root.exports.size(), 1, "exported the baked level")
	assert_eq(editor.custom, ["user://hammerforge_playtest.tscn"], "and launched it")
	assert_eq(dock.worst_toast_level(), 0, "with nothing to warn about")


## Export said nothing about a spawn warning that Test Level shows.
func test_export_warns_on_a_spawn_warning_and_plays():
	root.spawn_system.validation = {
		"valid": true,
		"severity": 1,
		"issues": PackedStringArray(["Insufficient headroom (0.50 units)"]),
	}
	var editor: Node = await _play("export")
	assert_eq(editor.custom.size(), 1, "a warning still exports and launches")
	assert_eq(dock.worst_toast_level(), 1, "and says so")
	assert_true(
		"Spawn warning: Insufficient headroom (0.50 units)" in dock.toast_messages(),
		"in the words Test Level uses"
	)


## The dialog's OK carries on with the export rather than Test Level's launch,
## with the spawn where the check put it.
func test_fix_and_play_after_export_exports_the_fixed_spawn():
	_blocked_with_suggestion(Vector3(12, 0, 5))
	var editor: Node = await _play("export")
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	dialog.confirmed.emit()
	assert_eq(root.exports.size(), 1, "OK exports")
	assert_eq(
		root.exports[0]["spawn_position"],
		Vector3(12, 0, 5),
		"with the spawn where the check put it"
	)
	assert_eq(_undo_step_names(), ["Fix player_start position"], "the move an undo step")
	assert_eq(editor.custom.size(), 1, "and plays the exported scene")
	assert_eq(editor.seen.size(), 0, "not the level's own")


func test_play_anyway_after_export_exports_the_spawn_where_it_is():
	_blocked_with_suggestion(Vector3(10, 0, 5))
	var editor: Node = await _play("export")
	var dialog := _fix_dialog()
	assert_not_null(dialog, "a blocked spawn asks first")
	if dialog == null:
		return
	assert_eq(dialog.ok_button_text, "Play Anyway")
	dialog.confirmed.emit()
	assert_eq(root.exports.size(), 1, "OK exports")
	assert_eq(root.exports[0]["spawn_position"], Vector3(10, 0, 5), "with the spawn left alone")
	assert_eq(editor.custom.size(), 1, "and plays the exported scene")


## A real level whose export is counted rather than written into user://.
class ExportCountingLevel:
	extends LevelRoot

	var exports: Array = []

	func export_playtest_scene(
		path: String, _include_debug_rig: bool = true, _metadata: Dictionary = {}
	) -> bool:
		exports.append(path)
		return true


## The mapper's case, with a real bake: the floor under the spawn is deleted
## after a bake. Judged before the new bake, the old bake's floor was still
## there to stand on, and the export launched a player over nothing.
func test_export_refuses_a_spawn_whose_floor_went_since_the_last_bake():
	var real := ExportCountingLevel.new()
	real.auto_spawn_player = false
	real.hflevel_autosave_enabled = false
	add_child_autoqfree(real)
	var ground: Node = real.create_brush_from_info(
		{"size": Vector3(8, 1, 8), "center": Vector3(0, -0.5, 0), "brush_id": "floor"}
	)
	real.create_brush_from_info(
		{"size": Vector3(8, 1, 8), "center": Vector3(40, -0.5, 0), "brush_id": "far"}
	)
	var start: Node3D = real.spawn_system.create_default_spawn()
	var height: float = real.spawn_system._get_entity_float(start, "height_offset", 1.0)
	start.global_position = Vector3(0, HFSpawnSystem.FEET_OFFSET + height, 0)
	assert_true(await real.bake(true, false, 1), "fixture: the first bake")
	await get_tree().physics_frame
	assert_eq(
		int(real.spawn_system.validate_spawn(start, 1).get("severity", -1)),
		0,
		"fixture: the spawn stands on the baked floor"
	)
	real.delete_brush(ground)
	assert_eq(
		int(real.spawn_system.validate_spawn(start, 1).get("severity", -1)),
		0,
		"fixture: before a new bake, the old bake's floor still holds the spawn up"
	)
	dock.level_root = real
	var editor := _watch_launch()
	await HFDockManageHandler.on_export_playtest(dock)
	assert_eq(real.exports.size(), 0, "the baked level has no floor there, so nothing is exported")
	assert_eq(editor.custom.size(), 0, "or launched")
	assert_not_null(_fix_dialog(), "and it asks what to do")


# ===========================================================================
# Shared restore helpers
# ===========================================================================


func test_restore_spawn_puts_back_position_and_angle():
	spawn.global_position = Vector3(999, 999, 999)
	spawn.entity_data["angle"] = 180.0
	HFDockManageHandler.restore_spawn(spawn, Vector3(10, 0, 5), 30.0)
	_assert_spawn_untouched("restore_spawn")


func test_restore_cordon_state_refreshes_the_level():
	var extra: Array[AABB] = [AABB(Vector3(90, 0, 0), Vector3(8, 8, 8))]
	var active: Array[bool] = [false]
	var snapshot := {
		"enabled": true,
		"aabb": AABB(Vector3(2, 2, 2), Vector3(4, 4, 4)),
		"extra": extra,
		"names": PackedStringArray(["Arena", "Spawn"]),
		"active": active,
	}
	HFDockManageHandler.restore_cordon_state(dock, snapshot)
	assert_true(root.cordon_enabled)
	assert_eq(root.cordon_aabb, AABB(Vector3(2, 2, 2), Vector3(4, 4, 4)))
	assert_eq(root.cordon_extra_aabbs, extra, "and the other cordons")
	assert_eq(root.cordon_names, PackedStringArray(["Arena", "Spawn"]), "their names")
	assert_eq(root.cordon_active, active, "and which of them bake")
	assert_eq(root.reconcile_calls, 1, "Restoring the cordon must retag a full reconcile")
	assert_eq(root.cordon_visual_calls, 1, "and redraw the cordon volume")


class BakingLevel:
	extends LevelRoot

	func is_bake_in_flight() -> bool:
		return true


## While a bake runs, each of these says to wait for it and nothing else. They
## used to add a red "No LevelRoot" toast with the level right there.
func test_a_bake_in_flight_gets_one_plain_wait_toast():
	var baking := BakingLevel.new()
	baking.auto_spawn_player = false
	baking.hflevel_autosave_enabled = false
	add_child_autoqfree(baking)
	dock.level_root = baking
	var handlers := {
		"Export Playtest": HFDockManageHandler.on_export_playtest,
		"Export Game Scene": HFDockManageHandler.on_export_game_scene,
		"Validate Spawn": HFDockManageHandler.on_spawn_validate,
	}
	for label in handlers:
		dock.toasts.clear()
		handlers[label].call(dock)
		assert_eq(
			dock.toast_messages(),
			["%s will be available when the current bake finishes" % label],
			"%s waits for the bake and says only that" % label
		)
