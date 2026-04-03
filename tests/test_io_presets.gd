extends GutTest

const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFIOPresets = preload("res://addons/hammerforge/systems/hf_io_presets.gd")

var root: Node3D
var sys: HFEntitySystem
var presets: HFIOPresets


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.entity_definitions = {}
	root.entity_definitions_path = ""
	sys = HFEntitySystem.new(root)
	root.entity_system = sys
	presets = HFIOPresets.new(root)
	# Use a temp path so tests never write into the project repo
	presets.load_presets("user://test_io_presets_tmp.json")


func after_each():
	# Clean up temp preset file
	if FileAccess.file_exists("user://test_io_presets_tmp.json"):
		DirAccess.remove_absolute("user://test_io_presets_tmp.json")
	root = null
	sys = null
	presets = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
var entity_system = null

func _assign_owner(node: Node) -> void:
	pass
"""
	s.reload()
	return s


func _make_entity(entity_name: String) -> Node3D:
	var e = Node3D.new()
	e.name = entity_name
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	return e


# ===========================================================================
# Built-in presets
# ===========================================================================


func test_builtin_presets_exist():
	var all = presets.get_all_presets()
	assert_gt(all.size(), 0, "Should have builtin presets")


func test_builtin_presets_are_marked():
	var all = presets.get_all_presets()
	for p in all:
		if p.get("name", "") == "Door Open → Light + Sound":
			assert_true(p["builtin"], "Builtin preset should be marked")
			return
	fail_test("Missing builtin preset 'Door Open → Light + Sound'")


func test_builtin_preset_has_connections():
	var all = presets.get_all_presets()
	for p in all:
		var conns = p.get("connections", [])
		assert_gt(conns.size(), 0, "Preset '%s' should have connections" % p.get("name", ""))


func test_all_builtin_preset_connections_have_required_fields():
	var all = presets.get_all_presets()
	for p in all:
		for conn in p.get("connections", []):
			assert_true(conn.has("output_name"), "Missing output_name in preset %s" % p["name"])
			assert_true(conn.has("input_name"), "Missing input_name in preset %s" % p["name"])
			assert_true(conn.has("target_tag"), "Missing target_tag in preset %s" % p["name"])


# ===========================================================================
# User presets
# ===========================================================================


func test_add_user_preset():
	(
		presets
		. add_user_preset(
			"Test Preset",
			"A test",
			[
				{"output_name": "OnTest", "input_name": "DoThing", "target_tag": "target"},
			]
		)
	)
	var user = presets.get_user_presets()
	assert_eq(user.size(), 1)
	assert_eq(user[0]["name"], "Test Preset")


func test_user_presets_in_combined_list():
	(
		presets
		. add_user_preset(
			"My Preset",
			"desc",
			[
				{"output_name": "A", "input_name": "B", "target_tag": "c"},
			]
		)
	)
	var all = presets.get_all_presets()
	var found := false
	for p in all:
		if p.get("name", "") == "My Preset":
			assert_false(p.get("builtin", true), "User preset should not be builtin")
			found = true
	assert_true(found, "User preset should appear in combined list")


func test_remove_user_preset():
	presets.add_user_preset(
		"A", "desc", [{"output_name": "x", "input_name": "y", "target_tag": "z"}]
	)
	presets.add_user_preset(
		"B", "desc", [{"output_name": "x", "input_name": "y", "target_tag": "z"}]
	)
	presets.remove_user_preset(0)
	var user = presets.get_user_presets()
	assert_eq(user.size(), 1)
	assert_eq(user[0]["name"], "B")


func test_remove_user_preset_invalid_index():
	presets.add_user_preset(
		"A", "desc", [{"output_name": "x", "input_name": "y", "target_tag": "z"}]
	)
	presets.remove_user_preset(5)
	presets.remove_user_preset(-1)
	assert_eq(presets.get_user_presets().size(), 1, "Invalid remove should be no-op")


# ===========================================================================
# Save entity as preset
# ===========================================================================


func test_save_entity_as_preset():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open")
	sys.add_entity_output(e, "OnTrigger", "light_1", "TurnOn", "", 0.5, false)
	var ok = presets.save_entity_as_preset(e, "Trigger Pattern")
	assert_true(ok)
	var user = presets.get_user_presets()
	assert_eq(user.size(), 1)
	assert_eq(user[0]["connections"].size(), 2)


func test_save_entity_no_outputs_fails():
	var e = _make_entity("empty_1")
	var ok = presets.save_entity_as_preset(e, "Empty")
	assert_false(ok, "Should fail with no outputs")


func test_save_entity_null_fails():
	var ok = presets.save_entity_as_preset(null, "Null")
	assert_false(ok, "Should fail with null entity")


func test_save_entity_preserves_delay_and_fire_once():
	var e = _make_entity("trigger_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open", "p", 2.5, true)
	presets.save_entity_as_preset(e, "Delayed")
	var user = presets.get_user_presets()
	var conn = user[0]["connections"][0]
	assert_almost_eq(float(conn.get("delay", 0.0)), 2.5, 0.001)
	assert_true(bool(conn.get("fire_once", false)))
	assert_eq(conn.get("parameter", ""), "p")


# ===========================================================================
# Apply preset
# ===========================================================================


func test_apply_preset_creates_connections():
	var e = _make_entity("trigger_1")
	_make_entity("door_1")
	_make_entity("light_1")
	var preset = {
		"name": "Test",
		"connections":
		[
			{"output_name": "OnTrigger", "input_name": "Open", "target_tag": "door"},
			{"output_name": "OnTrigger", "input_name": "TurnOn", "target_tag": "light"},
		],
	}
	var target_map = {"door": "door_1", "light": "light_1"}
	var count = presets.apply_preset(e, preset, target_map)
	assert_eq(count, 2, "Should create 2 connections")
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs.size(), 2)
	assert_eq(outputs[0]["target_name"], "door_1")
	assert_eq(outputs[1]["target_name"], "light_1")


func test_apply_preset_self_target():
	var e = _make_entity("pickup_1")
	var preset = {
		"name": "Self Kill",
		"connections":
		[
			{"output_name": "OnUse", "input_name": "Kill", "target_tag": "self", "fire_once": true},
		],
	}
	var count = presets.apply_preset(e, preset, {})
	assert_eq(count, 1)
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs[0]["target_name"], "pickup_1", "Self tag should map to entity's name")
	assert_true(outputs[0]["fire_once"])


func test_apply_preset_missing_target_uses_tag_as_name():
	var e = _make_entity("source_1")
	var preset = {
		"name": "Test",
		"connections":
		[
			{"output_name": "OnTrigger", "input_name": "Open", "target_tag": "door"},
		],
	}
	var count = presets.apply_preset(e, preset, {})
	assert_eq(count, 1)
	var outputs = sys.get_entity_outputs(e)
	assert_eq(outputs[0]["target_name"], "door", "Unmapped tag should be used as-is")


func test_apply_preset_with_delay():
	var e = _make_entity("source_1")
	var preset = {
		"name": "Delayed",
		"connections":
		[
			{"output_name": "OnTrigger", "input_name": "Play", "target_tag": "snd", "delay": 1.5},
		],
	}
	var count = presets.apply_preset(e, preset, {"snd": "sound_1"})
	assert_eq(count, 1)
	var outputs = sys.get_entity_outputs(e)
	assert_almost_eq(outputs[0]["delay"], 1.5, 0.001)


func test_apply_preset_null_entity():
	var count = presets.apply_preset(null, {"connections": []}, {})
	assert_eq(count, 0)


func test_apply_preset_empty_connections():
	var e = _make_entity("source_1")
	var count = presets.apply_preset(e, {"connections": []}, {})
	assert_eq(count, 0)


func test_apply_preset_skips_empty_names():
	var e = _make_entity("source_1")
	var preset = {
		"connections":
		[
			{"output_name": "", "input_name": "Open", "target_tag": "door"},
			{"output_name": "OnTrigger", "input_name": "", "target_tag": "door"},
			{"output_name": "OnTrigger", "input_name": "Open", "target_tag": "door"},
		],
	}
	var count = presets.apply_preset(e, preset, {"door": "door_1"})
	assert_eq(count, 1, "Should only create connection with non-empty names")


# ===========================================================================
# Target tags
# ===========================================================================


func test_get_preset_target_tags():
	var preset = {
		"connections":
		[
			{"output_name": "A", "input_name": "B", "target_tag": "door"},
			{"output_name": "A", "input_name": "B", "target_tag": "light"},
			{"output_name": "A", "input_name": "B", "target_tag": "door"},
			{"output_name": "A", "input_name": "B", "target_tag": "self"},
		],
	}
	var tags = presets.get_preset_target_tags(preset)
	assert_eq(tags.size(), 2, "Should have 2 unique tags (excluding self)")
	assert_true(tags.has("door"))
	assert_true(tags.has("light"))
	assert_false(tags.has("self"), "Self should be excluded")


func test_get_preset_target_tags_empty():
	var tags = presets.get_preset_target_tags({"connections": []})
	assert_eq(tags.size(), 0)
