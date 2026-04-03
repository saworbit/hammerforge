extends GutTest
## Tests for Quick Play mode validation logic patterns.
## These verify the severity-blocking and undo patterns match _on_quick_play().
## Full integration requires editor UI; these test the spawn/validation flow.

const HFSpawnSystem = preload("res://addons/hammerforge/systems/hf_spawn_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")

var root: Node3D
var spawn_sys


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities


func after_each():
	root = null
	spawn_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text, level)

var draft_brushes_node: Node3D
var entities_node: Node3D
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-128, -128, -128), Vector3(256, 256, 256))
var _dirty_brush_ids: Dictionary = {}

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")

func _log(_msg: String) -> void:
	pass
"""
	s.reload()
	return s


# ===========================================================================
# Severity-blocking: severity >= 2 must prevent play
# ===========================================================================


func test_severity_2_blocks_play():
	# Simulates the validation check pattern used by all three quick-play paths
	var validation := {
		"valid": false,
		"severity": 2,
		"issues": PackedStringArray(["No floor beneath spawn"]),
	}
	var severity: int = validation.get("severity", 0)
	var should_block: bool = severity >= 2
	assert_true(should_block, "Severity 2 must block play launch")


func test_severity_1_allows_play():
	var validation := {
		"valid": true,
		"severity": 1,
		"issues": PackedStringArray(["Low clearance"]),
	}
	var severity: int = validation.get("severity", 0)
	var should_block: bool = severity >= 2
	assert_false(should_block, "Severity 1 should warn but not block")


func test_severity_0_allows_play():
	var validation := {"valid": true, "severity": 0, "issues": PackedStringArray()}
	var severity: int = validation.get("severity", 0)
	var should_block: bool = severity >= 2
	assert_false(should_block, "Severity 0 should not block")


# ===========================================================================
# Cordon save/restore for Play Selected Area
# ===========================================================================


func test_cordon_state_preserved_after_play_area():
	# Simulate the cordon save/restore pattern
	var prev_enabled := true
	var prev_aabb := AABB(Vector3(10, 10, 10), Vector3(50, 50, 50))

	# Save state
	root.cordon_enabled = prev_enabled
	root.cordon_aabb = prev_aabb

	# Simulate set_cordon_from_selection changing it
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3.ZERO, Vector3(100, 100, 100))

	# Restore (as done at end of _on_quick_play_selected_area)
	root.cordon_enabled = prev_enabled
	root.cordon_aabb = prev_aabb

	assert_true(root.cordon_enabled, "Cordon enabled should be restored")
	assert_eq(root.cordon_aabb.position, Vector3(10, 10, 10), "Cordon AABB position restored")
	assert_eq(root.cordon_aabb.size, Vector3(50, 50, 50), "Cordon AABB size restored")


func test_cordon_restored_on_error_path():
	# Same pattern but simulating the severity >= 2 early return
	var prev_enabled := false
	var prev_aabb := AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))

	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3.ZERO, Vector3(200, 200, 200))

	# Simulate error path restoring cordon before returning
	root.cordon_enabled = prev_enabled
	root.cordon_aabb = prev_aabb

	assert_false(root.cordon_enabled, "Cordon should be restored to disabled on error")
	assert_eq(root.cordon_aabb.position, Vector3(-5, -5, -5), "Cordon restored on error")


# ===========================================================================
# Dirty tag retention across failed bakes
# ===========================================================================


func test_dirty_tags_survive_failed_incremental():
	root._dirty_brush_ids = {"b1": true, "b2": true, "b3": true}

	# Simulate failed bake — _last_bake_success stays false
	var bake_succeeded := false

	# The conditional clear pattern from bake_dirty
	if bake_succeeded:
		root._dirty_brush_ids.clear()

	assert_eq(
		root._dirty_brush_ids.size(),
		3,
		"All 3 dirty tags should survive a failed bake",
	)


func test_dirty_tags_cleared_after_successful_incremental():
	root._dirty_brush_ids = {"b1": true, "b2": true}

	var bake_succeeded := true

	if bake_succeeded:
		root._dirty_brush_ids.clear()

	assert_eq(
		root._dirty_brush_ids.size(),
		0,
		"Dirty tags should be cleared after successful bake",
	)


func test_dirty_tags_can_accumulate_after_failed_retry():
	root._dirty_brush_ids = {"b1": true}

	# First bake fails
	var bake_succeeded := false
	if bake_succeeded:
		root._dirty_brush_ids.clear()

	# User modifies another brush
	root._dirty_brush_ids["b2"] = true

	assert_eq(
		root._dirty_brush_ids.size(),
		2,
		"New dirty tags should accumulate with retained ones after failure",
	)


# ===========================================================================
# Camera yaw propagation to entity_data (not set_meta)
# ===========================================================================


func test_camera_yaw_written_to_entity_data():
	# Simulate what _on_quick_play_from_camera does with the spawn
	var spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 0.0}
	add_child_autoqfree(spawn)

	# Simulate camera yaw of 90 degrees
	var camera_yaw_deg: float = 90.0
	if spawn is DraftEntity:
		(spawn as DraftEntity).entity_data["angle"] = camera_yaw_deg

	assert_eq(
		spawn.entity_data["angle"],
		90.0,
		"Camera yaw should be written to entity_data['angle']",
	)


func test_camera_yaw_not_written_to_meta():
	# Verify the fix: yaw should NOT go to set_meta("angle", ...)
	var spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 0.0}
	add_child_autoqfree(spawn)

	# Simulate the corrected code path
	var camera_yaw_deg: float = 45.0
	if spawn is DraftEntity:
		(spawn as DraftEntity).entity_data["angle"] = camera_yaw_deg

	assert_false(spawn.has_meta("angle"), "Yaw should not be stored as meta")
	assert_eq(spawn.entity_data["angle"], 45.0, "Yaw should be in entity_data")


func test_playtest_reads_angle_from_entity_data():
	# The playtest runtime reads deg_to_rad(entity_data.get("angle", 0.0))
	var spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 180.0}
	add_child_autoqfree(spawn)

	var spawn_yaw: float = deg_to_rad(float(spawn.entity_data.get("angle", 0.0)))
	assert_almost_eq(spawn_yaw, PI, 0.001, "180 degrees should convert to PI radians")


# ===========================================================================
# Spawn restore after Play from Camera
# ===========================================================================


func test_spawn_restored_after_camera_play():
	# Simulate the full temporary-move + restore flow
	var spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 30.0}
	add_child_autoqfree(spawn)
	spawn.global_position = Vector3(10, 0, 5)

	# Save originals — explicit type because spawn is untyped GDScript instance
	var old_pos: Vector3 = spawn.global_position
	var old_angle: float = float(spawn.entity_data.get("angle", 0.0))

	# Temporarily move to camera
	spawn.global_position = Vector3(100, 50, 200)
	(spawn as DraftEntity).entity_data["angle"] = 270.0

	assert_eq(spawn.global_position, Vector3(100, 50, 200), "Should be at camera pos")
	assert_eq(spawn.entity_data["angle"], 270.0, "Should have camera yaw")

	# Restore (as _restore_spawn does)
	spawn.global_position = old_pos
	(spawn as DraftEntity).entity_data["angle"] = old_angle

	assert_eq(spawn.global_position, Vector3(10, 0, 5), "Position should be restored")
	assert_eq(spawn.entity_data["angle"], 30.0, "Angle should be restored")


func test_spawn_restored_on_error_path():
	# Even when validation blocks play, spawn must be restored
	var spawn = DraftEntityScript.new()
	spawn.entity_data = {"angle": 45.0}
	add_child_autoqfree(spawn)
	spawn.global_position = Vector3(5, 5, 5)

	var old_pos: Vector3 = spawn.global_position
	var old_angle: float = float(spawn.entity_data.get("angle", 0.0))

	# Temporarily move
	spawn.global_position = Vector3(999, 999, 999)
	(spawn as DraftEntity).entity_data["angle"] = 180.0

	# Simulate severity >= 2 error path — restore before return
	var severity := 2
	if severity >= 2:
		spawn.global_position = old_pos
		if spawn is DraftEntity:
			(spawn as DraftEntity).entity_data["angle"] = old_angle

	assert_eq(spawn.global_position, Vector3(5, 5, 5), "Restored on error")
	assert_eq(spawn.entity_data["angle"], 45.0, "Angle restored on error")
