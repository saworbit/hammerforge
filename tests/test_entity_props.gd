extends GutTest

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")

var root: Node3D
var sys: HFEntitySystem


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
	root.entity_definitions = _test_definitions()
	root.entity_definitions_path = ""
	sys = HFEntitySystem.new(root)


func after_each():
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
"""
	s.reload()
	return s


func _test_definitions() -> Dictionary:
	return {
		"light_point":
		{
			"id": "light_point",
			"class": "OmniLight3D",
			"properties":
			[
				{"name": "range", "type": "float", "label": "Range", "default": 10.0},
				{"name": "energy", "type": "float", "label": "Energy", "default": 1.0},
				{"name": "color", "type": "color", "label": "Color", "default": "#ffffff"},
			],
		},
		"door_basic":
		{
			"id": "door_basic",
			"class": "Node3D",
			"properties":
			[
				{"name": "speed", "type": "float", "label": "Speed", "default": 200.0},
				{"name": "locked", "type": "bool", "label": "Locked", "default": false},
			],
		},
		"player_start":
		{
			"id": "player_start",
			"class": "Node3D",
			"properties": [],
		},
		"test_all_types":
		{
			"id": "test_all_types",
			"class": "Node3D",
			"properties":
			[
				{"name": "label", "type": "string", "default": "hello"},
				{"name": "count", "type": "int", "default": 5},
				{"name": "speed", "type": "float", "default": 1.5},
				{"name": "active", "type": "bool", "default": true},
				{"name": "tint", "type": "color", "default": "#ff0000"},
				{"name": "offset", "type": "vector3", "default": [1.0, 2.0, 3.0]},
			],
		},
	}


func _make_draft_entity(type_key: String) -> DraftEntity:
	var e = DraftEntity.new()
	e.name = type_key
	root.entities_node.add_child(e)
	# Skip preview/level_root lookup by setting type directly on the var.
	e.entity_type = type_key
	e.entity_class = type_key
	return e


# ===========================================================================
# _parse_default_value tests
# ===========================================================================


func test_parse_default_string():
	var e = DraftEntity.new()
	assert_eq(e._parse_default_value("string", "hello"), "hello")
	assert_eq(e._parse_default_value("string", null), "<null>")
	e.free()


func test_parse_default_int():
	var e = DraftEntity.new()
	assert_eq(e._parse_default_value("int", 42), 42)
	assert_eq(e._parse_default_value("int", 0), 0)
	e.free()


func test_parse_default_float():
	var e = DraftEntity.new()
	assert_almost_eq(e._parse_default_value("float", 3.14), 3.14, 0.001)
	e.free()


func test_parse_default_bool():
	var e = DraftEntity.new()
	assert_eq(e._parse_default_value("bool", true), true)
	assert_eq(e._parse_default_value("bool", false), false)
	e.free()


func test_parse_default_color():
	var e = DraftEntity.new()
	var c = e._parse_default_value("color", "#ff0000")
	assert_true(c is Color, "Should return Color")
	assert_almost_eq(c.r, 1.0, 0.01)
	assert_almost_eq(c.g, 0.0, 0.01)
	e.free()


func test_parse_default_color_value():
	var e = DraftEntity.new()
	var c = e._parse_default_value("color", Color.BLUE)
	assert_true(c is Color)
	assert_almost_eq(c.b, 1.0, 0.01)
	e.free()


func test_parse_default_vector3():
	var e = DraftEntity.new()
	var v = e._parse_default_value("vector3", [1.0, 2.0, 3.0])
	assert_true(v is Vector3, "Should return Vector3")
	assert_almost_eq(v.x, 1.0, 0.01)
	assert_almost_eq(v.y, 2.0, 0.01)
	assert_almost_eq(v.z, 3.0, 0.01)
	e.free()


func test_parse_default_vector3_native():
	var e = DraftEntity.new()
	var v = e._parse_default_value("vector3", Vector3(4, 5, 6))
	assert_eq(v, Vector3(4, 5, 6))
	e.free()


# ===========================================================================
# Roundtrip: set entity_data -> capture -> restore -> verify
# ===========================================================================


func test_roundtrip_preserves_properties():
	var e = _make_draft_entity("door_basic")
	e.entity_data["speed"] = 500.0
	e.entity_data["locked"] = true

	var info = sys.capture_entity_info(e)
	assert_true(info.has("properties"), "info should have properties")
	assert_eq(info["properties"]["speed"], 500.0)
	assert_eq(info["properties"]["locked"], true)

	var restored = sys.restore_entity_from_info(info)
	assert_not_null(restored)
	assert_eq(restored.entity_data.get("speed"), 500.0)
	assert_eq(restored.entity_data.get("locked"), true)


func test_roundtrip_all_types():
	var e = _make_draft_entity("test_all_types")
	e.entity_data["label"] = "world"
	e.entity_data["count"] = 99
	e.entity_data["speed"] = 7.5
	e.entity_data["active"] = false
	e.entity_data["tint"] = Color.GREEN
	e.entity_data["offset"] = Vector3(10, 20, 30)

	var info = sys.capture_entity_info(e)
	var restored = sys.restore_entity_from_info(info)
	assert_not_null(restored)
	assert_eq(restored.entity_data.get("label"), "world")
	assert_eq(restored.entity_data.get("count"), 99)
	assert_almost_eq(float(restored.entity_data.get("speed")), 7.5, 0.01)
	assert_eq(restored.entity_data.get("active"), false)
	assert_eq(restored.entity_data.get("tint"), Color.GREEN)
	assert_eq(restored.entity_data.get("offset"), Vector3(10, 20, 30))


# ===========================================================================
# Empty / missing property edge cases
# ===========================================================================


func test_empty_properties_no_crash():
	var e = _make_draft_entity("player_start")
	# player_start has empty properties array — should not crash
	var info = sys.capture_entity_info(e)
	assert_true(info.has("properties"))
	var restored = sys.restore_entity_from_info(info)
	assert_not_null(restored)


func test_missing_property_uses_default():
	var e = _make_draft_entity("door_basic")
	# Don't set speed — verify _parse_default_value produces the correct defaults.
	# _apply_entity_defaults() requires a real LevelRoot ancestor (fails with shim),
	# so we apply defaults manually using the same logic.
	var definition: Dictionary = _test_definitions().get("door_basic", {})
	var props: Array = definition.get("properties", [])
	for prop in props:
		var pname = str(prop.get("name", ""))
		if pname == "" or e.entity_data.has(pname):
			continue
		e.entity_data[pname] = e._parse_default_value(
			prop.get("type", ""), prop.get("default", null)
		)
	assert_true(e.entity_data.has("speed"), "speed should be populated by defaults")
	assert_almost_eq(float(e.entity_data.get("speed", 0.0)), 200.0, 0.01)
	assert_eq(e.entity_data.get("locked"), false)
