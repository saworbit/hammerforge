extends GutTest

const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")


func test_coerce_default_float():
	assert_eq(HFEntityPropUtils.coerce_default("float", 3), 3.0)
	assert_eq(HFEntityPropUtils.coerce_default("float", null), 0.0)
	assert_eq(HFEntityPropUtils.coerce_default("float", "2.5"), 2.5)


func test_coerce_default_int():
	assert_eq(HFEntityPropUtils.coerce_default("int", 4.7), 4)
	assert_eq(HFEntityPropUtils.coerce_default("int", null), 0)


func test_coerce_default_bool():
	assert_eq(HFEntityPropUtils.coerce_default("bool", true), true)
	assert_eq(HFEntityPropUtils.coerce_default("bool", null), false)
	assert_eq(HFEntityPropUtils.coerce_default("bool", 1), true)


func test_coerce_default_color_from_string():
	var c = HFEntityPropUtils.coerce_default("color", "#ff0000")
	assert_true(c is Color)
	assert_almost_eq(c.r, 1.0, 0.01)


func test_coerce_default_color_default_white():
	var c = HFEntityPropUtils.coerce_default("color", null)
	assert_eq(c, Color.WHITE)


func test_coerce_default_vector3_from_array():
	var v = HFEntityPropUtils.coerce_default("vector3", [1, 2, 3])
	assert_eq(v, Vector3(1, 2, 3))


func test_coerce_default_vector3_default_zero():
	var v = HFEntityPropUtils.coerce_default("vector3", null)
	assert_eq(v, Vector3.ZERO)


func test_coerce_default_string():
	assert_eq(HFEntityPropUtils.coerce_default("string", "hello"), "hello")
	assert_eq(HFEntityPropUtils.coerce_default("string", 42), "42")
	assert_eq(HFEntityPropUtils.coerce_default("string", null), "")


func test_coerce_default_unknown_type_passthrough():
	# Unknown type names pass the value through unchanged
	var v = HFEntityPropUtils.coerce_default("custom_type", 42)
	assert_eq(v, 42)


func test_find_definition_returns_match_by_id():
	var defs = [
		{"id": "light_point", "properties": [{"name": "color"}]},
		{"id": "light_spot", "properties": []},
	]
	var def = HFEntityPropUtils.find_definition(defs, "light_point")
	assert_eq(def.get("id"), "light_point")


func test_find_definition_returns_match_by_class():
	# Definitions can use either "id" or "class" as the key field
	var defs = [{"class": "trigger_once"}]
	var def = HFEntityPropUtils.find_definition(defs, "trigger_once")
	assert_eq(def.get("class"), "trigger_once")


func test_find_definition_returns_empty_when_not_found():
	var defs = [{"id": "alpha"}]
	var def = HFEntityPropUtils.find_definition(defs, "missing")
	assert_true(def.is_empty())


func test_find_definition_skips_non_dict_entries():
	var defs = [null, "garbage", 42, {"id": "real"}]
	var def = HFEntityPropUtils.find_definition(defs, "real")
	assert_eq(def.get("id"), "real")


func test_get_entity_data_from_meta_node():
	var node = Node3D.new()
	add_child_autoqfree(node)
	node.set_meta("entity_data", {"foo": "bar"})
	var d = HFEntityPropUtils.get_entity_data(node)
	assert_eq(d.get("foo"), "bar")


func test_get_entity_data_returns_empty_for_plain_node():
	var node = Node3D.new()
	add_child_autoqfree(node)
	var d = HFEntityPropUtils.get_entity_data(node)
	assert_true(d.is_empty())


func test_get_entity_type_from_meta():
	var node = Node3D.new()
	add_child_autoqfree(node)
	node.set_meta("entity_type", "trigger_once")
	assert_eq(HFEntityPropUtils.get_entity_type(node), "trigger_once")


func test_get_entity_type_empty_for_plain_node():
	var node = Node3D.new()
	add_child_autoqfree(node)
	assert_eq(HFEntityPropUtils.get_entity_type(node), "")


func test_set_entity_property_writes_to_meta():
	var node = Node3D.new()
	add_child_autoqfree(node)
	node.set_meta("entity_data", {"x": 1})
	HFEntityPropUtils.set_entity_property(node, "x", 99)
	var d = node.get_meta("entity_data") as Dictionary
	assert_eq(d.get("x"), 99)


func test_set_entity_vec3_axis_updates_one_component():
	var node = Node3D.new()
	add_child_autoqfree(node)
	node.set_meta("entity_data", {"pos": Vector3(1, 2, 3)})
	HFEntityPropUtils.set_entity_vec3_axis(node, "pos", 1, 99.0)
	var d = node.get_meta("entity_data") as Dictionary
	var v = d.get("pos") as Vector3
	assert_eq(v, Vector3(1, 99, 3))


func test_set_entity_vec3_axis_initializes_zero_when_missing():
	var node = Node3D.new()
	add_child_autoqfree(node)
	node.set_meta("entity_data", {})
	HFEntityPropUtils.set_entity_vec3_axis(node, "pos", 0, 5.0)
	var d = node.get_meta("entity_data") as Dictionary
	var v = d.get("pos") as Vector3
	assert_eq(v, Vector3(5, 0, 0))


func test_set_entity_property_safe_with_invalid_node():
	# Must not error on freed/null entities
	HFEntityPropUtils.set_entity_property(null, "x", 1)
