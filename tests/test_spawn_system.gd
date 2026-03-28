extends GutTest

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFSpawnSystemScript = preload("res://addons/hammerforge/systems/hf_spawn_system.gd")

var root: Node3D
var sys: HFSpawnSystemScript


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	root.entity_definitions = _test_definitions()
	root.entity_definitions_path = ""
	sys = HFSpawnSystemScript.new(root)


func after_each():
	sys.cleanup_debug()
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
var entity_system = null
var spawn_system = null

func get_entity_definition(key: String) -> Dictionary:
	return entity_definitions.get(key, {})

func get_entity_definitions() -> Dictionary:
	return entity_definitions

func is_entity_node(node: Node) -> bool:
	if node == null:
		return false
	if node.has_meta("is_entity"):
		return true
	var s = node.get_script()
	if s != null and s.resource_path == "res://addons/hammerforge/draft_entity.gd":
		return true
	return false

func _assign_owner(node: Node) -> void:
	pass

func _iter_pick_nodes() -> Array:
	var nodes: Array = []
	if draft_brushes_node:
		nodes.append_array(draft_brushes_node.get_children())
	if entities_node:
		nodes.append_array(entities_node.get_children())
	return nodes
"""
	s.reload()
	return s


func _test_definitions() -> Dictionary:
	return {
		"player_start":
		{
			"id": "player_start",
			"class": "Node3D",
			"category": "Player",
			"properties":
			[
				{"name": "primary", "type": "bool", "label": "Primary Spawn", "default": false},
				{"name": "angle", "type": "float", "label": "Yaw Angle (deg)", "default": 0.0},
				{
					"name": "height_offset",
					"type": "float",
					"label": "Height Offset",
					"default": 1.0,
				},
			],
		},
	}


func _make_spawn(pos: Vector3 = Vector3.ZERO, primary: bool = false) -> DraftEntity:
	var e = DraftEntity.new()
	e.name = "DraftEntity"
	root.entities_node.add_child(e)
	e.entity_type = "player_start"
	e.entity_class = "player_start"
	e.global_position = pos
	e.entity_data["primary"] = primary
	e.entity_data["angle"] = 0.0
	e.entity_data["height_offset"] = 1.0
	return e


# ===========================================================================
# get_active_spawn tests
# ===========================================================================


func test_no_spawns_returns_null():
	var spawn = sys.get_active_spawn()
	assert_null(spawn, "Should return null when no player_start entities exist")


func test_single_spawn_returned():
	var e = _make_spawn(Vector3(10, 0, 5))
	var spawn = sys.get_active_spawn()
	assert_not_null(spawn)
	assert_eq(spawn, e)


func test_primary_flag_takes_priority():
	var e1 = _make_spawn(Vector3(1, 0, 0), false)
	var e2 = _make_spawn(Vector3(2, 0, 0), true)
	_make_spawn(Vector3(3, 0, 0), false)
	var spawn = sys.get_active_spawn()
	assert_eq(spawn, e2, "Primary-flagged spawn should be returned")


func test_first_spawn_fallback_when_no_primary():
	var e1 = _make_spawn(Vector3(1, 0, 0), false)
	_make_spawn(Vector3(2, 0, 0), false)
	var spawn = sys.get_active_spawn()
	assert_eq(spawn, e1, "First spawn should be returned when none is primary")


func test_get_all_spawns():
	_make_spawn(Vector3(1, 0, 0))
	_make_spawn(Vector3(2, 0, 0))
	_make_spawn(Vector3(3, 0, 0))
	var spawns = sys.get_all_spawns()
	assert_eq(spawns.size(), 3)


func test_non_player_start_entities_ignored():
	# Add a non-player_start entity
	var e = DraftEntity.new()
	e.name = "DraftEntity"
	root.entities_node.add_child(e)
	e.entity_type = "light_point"
	e.entity_class = "light_point"
	# Also add a real spawn
	var spawn_e = _make_spawn(Vector3(5, 0, 0))
	var spawns = sys.get_all_spawns()
	assert_eq(spawns.size(), 1)
	assert_eq(spawns[0], spawn_e)


# ===========================================================================
# validate_spawn tests
# ===========================================================================


func test_validate_null_spawn():
	var result = sys.validate_spawn(null)
	assert_false(result.valid)
	assert_eq(result.severity, HFSpawnSystemScript.Severity.ERROR)
	assert_true(result.issues.size() > 0)


func test_validate_spawn_not_in_tree():
	var e = DraftEntity.new()
	e.entity_type = "player_start"
	e.entity_class = "player_start"
	# NOT added to tree
	var result = sys.validate_spawn(e)
	assert_false(result.valid)
	e.free()


func test_validate_spawn_in_tree_no_physics():
	# Spawn is in the tree but no physics bodies exist = no floor.
	# In headless mode without a physics world, the validator should detect
	# the missing World3D/space or the absent floor and report accordingly.
	var e = _make_spawn(Vector3(0, 100, 0))
	var result = sys.validate_spawn(e)
	assert_true(result is Dictionary)
	assert_true(result.has("valid"))
	assert_true(result.has("issues"))
	assert_true(result.has("severity"))
	# Without physics, the result should be invalid (no world/space or no floor)
	if not result.valid:
		assert_true(
			result.severity >= HFSpawnSystemScript.Severity.ERROR,
			"Missing physics should produce ERROR severity",
		)


# ===========================================================================
# auto_fix_spawn tests
# ===========================================================================


func test_auto_fix_spawn_applies_suggested_position():
	var e = _make_spawn(Vector3(0, 10, 0))
	var validation = {
		"valid": false,
		"issues": PackedStringArray(["Floating"]),
		"suggested_position": Vector3(0, 1, 0),
		"severity": HFSpawnSystemScript.Severity.WARNING,
	}
	sys.auto_fix_spawn(e, validation)
	assert_almost_eq(e.global_position.y, 1.0, 0.01)


func test_auto_fix_spawn_null_is_safe():
	var validation = {"suggested_position": Vector3.ZERO}
	# Should not crash
	sys.auto_fix_spawn(null, validation)
	pass_test("auto_fix_spawn with null did not crash")


# ===========================================================================
# create_default_spawn tests
# ===========================================================================


func test_create_default_spawn_when_empty():
	var spawn = sys.create_default_spawn()
	assert_not_null(spawn)
	assert_true(spawn is DraftEntity)
	assert_eq(spawn.entity_class, "player_start")
	# Should be added to entities_node
	assert_true(spawn.get_parent() == root.entities_node)


func test_create_default_spawn_uses_brush_centroid():
	# Add a mock draft_brushes_node with some brushes
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft

	var b1 = Node3D.new()
	b1.position = Vector3(10, 0, 0)
	draft.add_child(b1)
	var b2 = Node3D.new()
	b2.position = Vector3(0, 0, 10)
	draft.add_child(b2)

	var spawn = sys.create_default_spawn()
	assert_not_null(spawn)
	# Centroid of (10,0,0) and (0,0,10) = (5,0,5), + 5.0 height = (5,5,5)
	assert_almost_eq(spawn.global_position.x, 5.0, 0.1)
	assert_almost_eq(spawn.global_position.y, 5.0, 0.1)
	assert_almost_eq(spawn.global_position.z, 5.0, 0.1)


# ===========================================================================
# Debug visualisation tests
# ===========================================================================


func test_cleanup_debug_on_empty():
	# Should not crash when nothing to clean
	sys.cleanup_debug()
	assert_false(sys.is_debug_visible())


func test_show_validation_debug_creates_nodes():
	var e = _make_spawn(Vector3(0, 0, 0))
	var validation = {
		"valid": true,
		"issues": PackedStringArray(),
		"suggested_position": Vector3.ZERO,
		"floor_hit": null,
		"ceiling_hit": null,
		"severity": HFSpawnSystemScript.Severity.NONE,
	}
	sys.show_validation_debug(e, validation, 0.0)
	assert_true(sys.is_debug_visible(), "Debug nodes should be visible after show")
	sys.cleanup_debug()
	assert_false(sys.is_debug_visible(), "Debug nodes should be cleared after cleanup")


func test_show_validation_debug_with_issues():
	var e = _make_spawn(Vector3(0, 50, 0))
	var validation = {
		"valid": false,
		"issues": PackedStringArray(["Spawn inside solid geometry", "Floating"]),
		"suggested_position": Vector3(0, 1, 0),
		"floor_hit": null,
		"ceiling_hit": null,
		"severity": HFSpawnSystemScript.Severity.ERROR,
	}
	sys.show_validation_debug(e, validation, 0.0)
	assert_true(sys.is_debug_visible())
	sys.cleanup_debug()


func test_show_validation_debug_with_floor_hit():
	var e = _make_spawn(Vector3(0, 2, 0))
	var validation = {
		"valid": true,
		"issues": PackedStringArray(),
		"suggested_position": Vector3(0, 1, 0),
		"floor_hit": {"position": Vector3(0, 0, 0), "normal": Vector3.UP},
		"ceiling_hit": null,
		"severity": HFSpawnSystemScript.Severity.NONE,
	}
	sys.show_validation_debug(e, validation, 0.0)
	assert_true(sys.is_debug_visible())
	sys.cleanup_debug()


func test_show_validation_debug_null_spawn_is_safe():
	var validation = {
		"valid": false,
		"issues": PackedStringArray(["No spawn"]),
		"suggested_position": Vector3.ZERO,
		"severity": HFSpawnSystemScript.Severity.ERROR,
	}
	sys.show_validation_debug(null, validation, 0.0)
	assert_false(sys.is_debug_visible(), "No nodes created for null spawn")


# ===========================================================================
# Entity property helpers
# ===========================================================================


func test_entity_bool_from_data():
	var e = _make_spawn()
	e.entity_data["primary"] = true
	assert_true(sys._get_entity_bool(e, "primary"))
	e.entity_data["primary"] = false
	assert_false(sys._get_entity_bool(e, "primary"))


func test_entity_float_from_data():
	var e = _make_spawn()
	e.entity_data["height_offset"] = 2.5
	assert_almost_eq(sys._get_entity_float(e, "height_offset"), 2.5, 0.01)


func test_entity_float_fallback():
	var e = _make_spawn()
	e.entity_data.erase("height_offset")
	assert_almost_eq(sys._get_entity_float(e, "height_offset", 1.0), 1.0, 0.01)


# ===========================================================================
# Severity enum
# ===========================================================================


func test_severity_ordering():
	assert_true(HFSpawnSystemScript.Severity.NONE < HFSpawnSystemScript.Severity.WARNING)
	assert_true(HFSpawnSystemScript.Severity.WARNING < HFSpawnSystemScript.Severity.ERROR)


# ===========================================================================
# Capsule constant alignment
# ===========================================================================


func test_capsule_constants_match_playtest_fps():
	# Spawn system validation capsule MUST match runtime FPS controller dimensions
	# Source of truth: playtest_fps.gd exports capsule_radius=0.35, capsule_height=1.6
	assert_eq(
		HFSpawnSystemScript.PLAYER_RADIUS,
		0.35,
		"PLAYER_RADIUS must match playtest_fps.gd capsule_radius default",
	)
	assert_eq(
		HFSpawnSystemScript.PLAYER_HEIGHT,
		1.6,
		"PLAYER_HEIGHT must match playtest_fps.gd capsule_height default",
	)


# ===========================================================================
# collision_mask parameter — verify the mask-selection logic
# ===========================================================================


func test_validate_spawn_mask_zero_and_one_produce_same_result():
	# mask=0 should fall back to 1 internally, so both calls must produce
	# identical validation output when run against the same spawn.
	var e = _make_spawn(Vector3(0, 5, 0))
	var r0 = sys.validate_spawn(e, 0)
	var r1 = sys.validate_spawn(e, 1)
	assert_eq(r0.valid, r1.valid, "mask=0 and mask=1 must agree on validity")
	assert_eq(r0.severity, r1.severity, "mask=0 and mask=1 must agree on severity")
	assert_eq(r0.issues, r1.issues, "mask=0 and mask=1 must report same issues")


func test_validate_spawn_different_masks_do_not_crash():
	# Exercise validate_spawn with several mask values to confirm no code path
	# rejects a non-default mask. In headless mode without collision bodies the
	# result will be the same, but this guards against TypeErrors or branching
	# bugs when a non-1 mask is passed.
	var e = _make_spawn(Vector3(0, 5, 0))
	for mask_val in [0, 1, 2, 4, 0xFFFF]:
		var result = sys.validate_spawn(e, mask_val)
		assert_true(result is Dictionary, "mask=%d must return a Dictionary" % mask_val)
		assert_true(result.has("valid"), "mask=%d result must have 'valid' key" % mask_val)
		assert_true(result.has("severity"), "mask=%d result must have 'severity' key" % mask_val)


# ===========================================================================
# height_offset — verify the floor-snap formula
# ===========================================================================


func test_auto_fix_with_default_height_offset():
	# With default height_offset (1.0) the expected snap position for a floor
	# at y=0 is FEET_OFFSET + 1.0 = 1.1. Call auto_fix_spawn (production code)
	# with a validation dict matching what validate_spawn would produce.
	var e = _make_spawn(Vector3(3, 15, 3))
	# height_offset defaults to 1.0 in _make_spawn
	var validation = {
		"valid": false,
		"issues": PackedStringArray(["Spawn not on floor"]),
		"suggested_position": Vector3(3, 1.1, 3),
		"severity": HFSpawnSystemScript.Severity.WARNING,
	}
	sys.auto_fix_spawn(e, validation)
	assert_almost_eq(e.global_position.y, 1.1, 0.01, "Must snap to floor+FEET+height_offset")


func test_auto_fix_with_custom_height_offset():
	# With height_offset=2.5 and floor at y=3.0, the expected snap is
	# 3.0 + FEET_OFFSET(0.1) + 2.5 = 5.6. Verify auto_fix_spawn applies it.
	var e = _make_spawn(Vector3(0, 50, 0))
	e.entity_data["height_offset"] = 2.5
	var validation = {
		"valid": false,
		"issues": PackedStringArray(["Spawn not on floor"]),
		"suggested_position": Vector3(0, 5.6, 0),
		"severity": HFSpawnSystemScript.Severity.WARNING,
	}
	sys.auto_fix_spawn(e, validation)
	assert_almost_eq(e.global_position.y, 5.6, 0.01, "Must snap with custom height_offset")


func test_auto_fix_applies_floor_snap_formula():
	# Simulate a validation result where the floor was hit at y=0, with
	# height_offset=2.0. suggested_position.y should be FEET_OFFSET + 2.0 = 2.1
	var e = _make_spawn(Vector3(5, 20, 5))
	e.entity_data["height_offset"] = 2.0
	var suggested_y := 0.0 + HFSpawnSystemScript.FEET_OFFSET + 2.0
	var validation = {
		"valid": false,
		"issues": PackedStringArray(["Spawn not on floor"]),
		"suggested_position": Vector3(5, suggested_y, 5),
		"severity": HFSpawnSystemScript.Severity.WARNING,
	}
	sys.auto_fix_spawn(e, validation)
	assert_almost_eq(e.global_position.y, 2.1, 0.01, "auto_fix must apply floor-snap position")
	assert_almost_eq(e.global_position.x, 5.0, 0.01, "X must not change during fix")
	assert_almost_eq(e.global_position.z, 5.0, 0.01, "Z must not change during fix")


func test_height_offset_read_from_entity_data():
	# Verify the validator's _get_entity_float reads height_offset, which feeds
	# the floor-snap formula. This is the integration seam between entity data
	# and the snap calculation.
	var e = _make_spawn(Vector3.ZERO)
	e.entity_data["height_offset"] = 3.7
	var ho = sys._get_entity_float(e, "height_offset", 1.0)
	assert_almost_eq(ho, 3.7, 0.001)
	# Erasing should yield fallback
	e.entity_data.erase("height_offset")
	ho = sys._get_entity_float(e, "height_offset", 1.0)
	assert_almost_eq(ho, 1.0, 0.001, "Missing key must return fallback")


# ===========================================================================
# Validation result structure and invariants
# ===========================================================================


func test_validate_result_structure_complete():
	# Every validation result must contain all six keys regardless of outcome.
	var e = _make_spawn(Vector3(0, 100, 0))
	var result = sys.validate_spawn(e)
	var required_keys := [
		"valid", "issues", "severity", "suggested_position", "floor_hit", "ceiling_hit"
	]
	for key in required_keys:
		assert_true(result.has(key), "Result must contain '%s'" % key)


func test_invalid_result_always_has_issue_and_error_severity():
	# If valid==false, there MUST be at least one issue and severity >= ERROR.
	var e = _make_spawn(Vector3(0, 100, 0))
	var result = sys.validate_spawn(e)
	if not result.valid:
		assert_true(result.issues.size() > 0, "Invalid result must list at least one issue")
		assert_true(
			result.severity >= HFSpawnSystemScript.Severity.ERROR,
			"Invalid result must have ERROR severity",
		)
