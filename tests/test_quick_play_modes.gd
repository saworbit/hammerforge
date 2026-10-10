extends GutTest
## Drives the real HFDockManageHandler quick-play entry points through a dock
## stand-in and a real level, so the severity blocking, the temporary spawn and
## cordon moves, and the undo stack are all observed on the production code.

const HFDockManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const HFPlaytestRequest = preload("res://addons/hammerforge/hf_playtest_request.gd")


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

	func bake(
		_apply_cuts: bool = true,
		_hide_live: bool = false,
		_collision_layer_mask: int = 0,
		_preview_mode: int = 0,
		_force_csg: bool = false
	) -> bool:
		bake_calls += 1
		cordons_at_bake = get_cordon_regions().size()
		return bake_result

	func set_cordon_from_selection(_nodes: Array, _index: int = 0) -> void:
		cordon_from_selection_calls += 1
		cordon_enabled = true
		cordon_aabb = AABB(Vector3.ZERO, Vector3(64, 64, 64))

	func tag_full_reconcile() -> void:
		reconcile_calls += 1

	func update_cordon_visual() -> void:
		cordon_visual_calls += 1


## Answers validation with whatever the test sets.
class SpawnSystemStub:
	extends RefCounted

	var active_spawn: Node3D
	var validation: Dictionary = {"valid": true, "severity": 0, "issues": PackedStringArray()}
	var created_spawns: int = 0
	var debug_calls: int = 0

	func get_active_spawn() -> Node3D:
		return active_spawn

	func create_default_spawn() -> Node3D:
		created_spawns += 1
		return active_spawn

	func validate_spawn(_spawn, _mask) -> Dictionary:
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
	root.state_system = StateSystemStub.new()
	spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 30.0}
	root.add_child(spawn)
	spawn.global_position = Vector3(10, 0, 5)
	root.spawn_system.active_spawn = spawn
	dock = Node.new()
	dock.set_script(_dock_shim_script())
	add_child_autoqfree(dock)
	dock.level_root = root
	dock._plugin = _make_camera_holder()


func after_each():
	# UndoRedo is an Object, so the shim's copy has to be freed by hand.
	if is_instance_valid(dock) and dock.undo_redo:
		dock.undo_redo.free()
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
var undo_redo = UndoRedo.new()
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
