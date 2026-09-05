extends GutTest
## Drives the real HFDockManageHandler quick-play entry points through a dock
## and level-root stand-in, so the severity blocking, the temporary spawn and
## cordon moves, and the undo stack are all observed on the production code.

const HFDockManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")

var dock: Node
var root: Node3D
var spawn: DraftEntity


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
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


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var spawn_system = SpawnSystemStub.new()
var state_system = StateSystemStub.new()
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-128, -128, -128), Vector3(256, 256, 256))
var bake_result: bool = true
var bake_calls: int = 0
var reconcile_calls: int = 0
var cordon_visual_calls: int = 0
var cordon_from_selection_calls: int = 0

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

class StateSystemStub:
	extends RefCounted
	func capture_state(_include_all: bool = false) -> Dictionary:
		return {"snapshot": true}

	func restore_state(_state: Dictionary) -> void:
		pass

func bake(_visual: bool, _selection_only: bool, _mask: int, _preview: int = 0) -> bool:
	bake_calls += 1
	return bake_result

func is_bake_in_flight() -> bool:
	return false

func check_missing_dependencies() -> Array:
	return []

func set_cordon_from_selection(_nodes: Array) -> void:
	cordon_from_selection_calls += 1
	cordon_enabled = true
	cordon_aabb = AABB(Vector3.ZERO, Vector3(64, 64, 64))

func tag_full_reconcile() -> void:
	reconcile_calls += 1

func update_cordon_visual() -> void:
	cordon_visual_calls += 1
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
# Shared restore helpers
# ===========================================================================


func test_restore_spawn_puts_back_position_and_angle():
	spawn.global_position = Vector3(999, 999, 999)
	spawn.entity_data["angle"] = 180.0
	HFDockManageHandler.restore_spawn(spawn, Vector3(10, 0, 5), 30.0)
	_assert_spawn_untouched("restore_spawn")


func test_restore_cordon_state_refreshes_the_level():
	HFDockManageHandler.restore_cordon_state(dock, true, AABB(Vector3(2, 2, 2), Vector3(4, 4, 4)))
	assert_true(root.cordon_enabled)
	assert_eq(root.cordon_aabb, AABB(Vector3(2, 2, 2), Vector3(4, 4, 4)))
	assert_eq(root.reconcile_calls, 1, "Restoring the cordon must retag a full reconcile")
	assert_eq(root.cordon_visual_calls, 1, "and redraw the cordon volume")
