extends GutTest

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")

var root: LevelRoot
var sys: HFEntitySystem


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# The tests assert these fixture definitions: test_all_types is not shipped,
	# and door_basic's speed default here is 200 where entities.json has 2.
	root.entity_definitions = _test_definitions()
	sys = root.entity_system


func after_each():
	root = null
	sys = null


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
		# Values a definition built in code can carry and a JSON file cannot.
		"test_native_defaults":
		{
			"id": "test_native_defaults",
			"class": "Node3D",
			"properties":
			[
				{"name": "count", "type": "int", "default": 0},
				{"name": "active", "type": "bool", "default": false},
				{"name": "tint", "type": "color", "default": Color.BLUE},
				{"name": "offset", "type": "vector3", "default": Vector3(4, 5, 6)},
			],
		},
		"test_no_defaults":
		{
			"id": "test_no_defaults",
			"class": "Node3D",
			"properties":
			[
				{"name": "label", "type": "string"},
				{"name": "count", "type": "int"},
				{"name": "speed", "type": "float"},
				{"name": "active", "type": "bool"},
				{"name": "tint", "type": "color"},
				{"name": "offset", "type": "vector3"},
			],
		},
		# `"default": null` in a JSON file. The level root reads a default only
		# when the key is there, so this is the case that reaches it.
		"test_null_defaults":
		{
			"id": "test_null_defaults",
			"class": "Node3D",
			"properties":
			[
				{"name": "text", "type": "string", "default": null},
				{"name": "count", "type": "int", "default": null},
				{"name": "speed", "type": "float", "default": null},
				{"name": "active", "type": "bool", "default": null},
				{"name": "tint", "type": "color", "default": null},
				{"name": "drift", "type": "vector3", "default": null},
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
# A placed entity's starting values come from its class defaults (#1453)
# ===========================================================================

## The zero each declared type starts at when its definition gives no default.
## The same values the Entity panel and the MCP bridge fill in.
const NO_DEFAULT := {
	"label": "",
	"text": "",
	"count": 0,
	"speed": 0.0,
	"active": false,
	"tint": Color.WHITE,
	"offset": Vector3.ZERO,
	"drift": Vector3.ZERO,
}


func _assert_typed(value: Variant, expected: Variant, what: String) -> void:
	assert_eq(typeof(value), typeof(expected), "%s keeps its declared type" % what)
	assert_eq(value, expected, what)


func test_a_placed_entity_takes_each_default_in_its_declared_type():
	var e = _make_draft_entity("test_all_types")
	_assert_typed(e.entity_data.get("label"), "hello", "string")
	_assert_typed(e.entity_data.get("count"), 5, "int")
	_assert_typed(e.entity_data.get("speed"), 1.5, "float")
	_assert_typed(e.entity_data.get("active"), true, "bool")
	_assert_typed(e.entity_data.get("tint"), Color(1, 0, 0), "color from a string")
	_assert_typed(e.entity_data.get("offset"), Vector3(1, 2, 3), "vector3 from a list")


func test_a_placed_entity_keeps_native_defaults():
	var e = _make_draft_entity("test_native_defaults")
	_assert_typed(e.entity_data.get("count"), 0, "int zero")
	_assert_typed(e.entity_data.get("active"), false, "bool false")
	_assert_typed(e.entity_data.get("tint"), Color.BLUE, "a Color")
	_assert_typed(e.entity_data.get("offset"), Vector3(4, 5, 6), "a Vector3")


func test_a_string_property_with_no_default_starts_empty():
	# It started as "<null>", which the panel showed and the exported `.map` wrote.
	var e = _make_draft_entity("test_no_defaults")
	_assert_typed(e.entity_data.get("label"), "", "a string with no default")


func test_every_type_with_no_default_starts_at_its_zero():
	# The numbers and the bool went through float(null), int(null) and bool(null),
	# each a script error, and the property was left null.
	var e = _make_draft_entity("test_no_defaults")
	for prop_name in ["label", "count", "speed", "active", "tint", "offset"]:
		_assert_typed(e.entity_data.get(prop_name), NO_DEFAULT[prop_name], prop_name)


func test_the_inspector_reads_the_same_zero_for_a_property_the_level_does_not_store():
	var e = _make_draft_entity("test_no_defaults")
	e.entity_data.clear()
	for prop_name in ["label", "count", "speed", "active", "tint", "offset"]:
		_assert_typed(e.get("data/" + prop_name), NO_DEFAULT[prop_name], prop_name)


func test_a_null_default_starts_at_its_zero_on_a_placed_entity():
	var e = _make_draft_entity("test_null_defaults")
	for prop_name in ["text", "count", "speed", "active", "tint", "drift"]:
		_assert_typed(e.entity_data.get(prop_name), NO_DEFAULT[prop_name], prop_name)


func test_a_null_default_ships_at_its_zero_on_a_marker():
	# A level saved before the class gained these stores none of them, and the
	# export fills them from the class defaults.
	var e = _make_draft_entity("test_null_defaults")
	e.entity_data.clear()
	var shipped: Dictionary = root._shipped_entity_data(e)
	for prop_name in ["text", "count", "speed", "active", "tint", "drift"]:
		_assert_typed(shipped.get(prop_name), NO_DEFAULT[prop_name], prop_name)


func test_a_null_default_reaches_a_built_node_at_its_zero():
	var e = _make_draft_entity("test_null_defaults")
	e.entity_data.clear()
	# A Label3D has `text` and none of the class's other names, so the rest are
	# left alone as a node without them would be.
	var label: Label3D = autofree(Label3D.new())
	label.text = "before"
	root._apply_entity_properties_to_node(
		label, e, root.get_entity_definition("test_null_defaults")
	)
	assert_eq(label.text, "", "not the text <null>")


func test_a_bool_default_written_as_text_reads_as_that_bool():
	# bool() has no String form, so "false" was a script error and came back null.
	var coerce := HFEntityPropUtils.coerce_default
	for text in ["true", "True", " 1 ", "yes"]:
		_assert_typed(coerce.call("bool", text), true, "%s reads as true" % text)
	for text in ["false", "FALSE", "0", "no", ""]:
		_assert_typed(coerce.call("bool", text), false, "%s reads as false" % text)


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
	# Don't set speed. Setting the type under a real LevelRoot runs
	# _apply_entity_defaults(), which fills it from the definition.
	assert_true(e.entity_data.has("speed"), "speed should be populated by defaults")
	assert_almost_eq(float(e.entity_data.get("speed", 0.0)), 200.0, 0.01)
	assert_eq(e.entity_data.get("locked"), false)


# ===========================================================================
# World placement with an offset LevelRoot
# ===========================================================================


func test_restore_entity_from_info_keeps_world_transform_when_root_is_offset():
	root.position = Vector3(100, 0, 100)
	var restored = (
		sys
		. restore_entity_from_info(
			{
				"name": "OffsetLight",
				"entity_type": "light_point",
				"transform": Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)),
			}
		)
	)
	assert_not_null(restored)
	assert_almost_eq(
		restored.global_position,
		Vector3(10, 0, 0),
		Vector3(0.001, 0.001, 0.001),
		"A restored entity keeps the world position it was captured at"
	)


func test_create_entity_from_map_keeps_world_origin_when_root_is_offset():
	root.position = Vector3(100, 0, 100)
	var entity = sys.create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(10, 0, 0)}
	)
	assert_not_null(entity)
	assert_almost_eq(
		entity.global_position,
		Vector3(10, 0, 0),
		Vector3(0.001, 0.001, 0.001),
		"Map origins are world coordinates, not offsets from the level root"
	)


# ===========================================================================
# The authored entity name survives capture and restore (#251)
# ===========================================================================


func test_roundtrip_preserves_the_authored_entity_name():
	# The authored name is not the node name. It is what an I/O output targets and
	# what find_entities_by_name() looks up, so an entity that comes back without
	# it is wired to nothing.
	var e = _make_draft_entity("info_target")
	e.set_meta("entity_name", "key_door_target")

	var info = sys.capture_entity_info(e)
	assert_eq(str(info.get("entity_name", "")), "key_door_target", "the name is captured")

	var restored = sys.restore_entity_from_info(info)
	assert_not_null(restored)
	assert_eq(str(restored.get_meta("entity_name", "")), "key_door_target")


func test_duplicate_info_gives_the_copy_an_authored_name_of_its_own():
	# #251 was the copy coming back with no authored name at all, which left it
	# wired to nothing. It carries one, but it has to be its own: the authored
	# name is the address, and two entities cannot answer to one.
	var e = _make_draft_entity("info_target")
	e.set_meta("entity_name", "key_door_target")

	var dup = sys.restore_entity_from_info(sys.build_duplicate_info(e, Vector3(64, 0, 0)))

	assert_not_null(dup)
	var copied := str(dup.get_meta("entity_name", ""))
	assert_ne(copied, "", "a copy still has to be addressable")
	assert_ne(copied, "key_door_target", "and not at the original's address")
	assert_string_starts_with(copied, "key_door_target", "named after what it came from")


func test_roundtrip_without_a_name_sets_no_meta():
	var e = _make_draft_entity("light_point")
	var info = sys.capture_entity_info(e)
	assert_false(info.has("entity_name"))
	var restored = sys.restore_entity_from_info(info)
	assert_false(restored.has_meta("entity_name"), "Unnamed entities stay free of the meta")


func test_a_point_entity_name_survives_a_state_restore():
	# The reported symptom: an undo, a redo, an autosave or a reload all run the
	# level through a snapshot, and the name was dropped every time.
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	var entity := DraftEntity.new()
	entity.entity_type = "info_target"
	entity.entity_class = "info_target"
	level.entities_node.add_child(entity)
	entity.set_meta("entity_name", "key_door_target")

	level.restore_state(level.capture_state())

	var found: Array = level.entity_system.find_entities_by_name("key_door_target")
	assert_eq(found.size(), 1, "the restored entity still answers to the name it was given")
