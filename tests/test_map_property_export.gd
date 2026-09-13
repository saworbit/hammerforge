extends GutTest

## What an entity property looks like in the file a `.map` export produces.
##
## A `.map` exists to be read by something else. The Objects tab stores typed
## values - the colour picker writes a `Color`, the vector row writes a `Vector3`
## - and `str()` on either produces Godot's own notation, which no Quake-family
## compiler or editor parses. The parentheses and the commas make the key
## unusable rather than merely differently scaled.

const MapAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_adapter.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")


func _adapter() -> HFMapAdapter:
	return MapAdapter.new()


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


# ---------------------------------------------------------------------------
# The values themselves
# ---------------------------------------------------------------------------


func test_a_colour_is_three_numbers_with_no_alpha() -> void:
	assert_eq(
		_adapter().format_property_value(Color(0.2, 0.4, 0.8, 1.0)),
		"51 102 204",
		"the notation a light colour is written in, not Godot's"
	)
	assert_eq(_adapter().format_property_value(Color(1, 1, 1, 1)), "255 255 255")


func test_a_hex_colour_string_is_written_the_same_way() -> void:
	# entities.json gives a colour property a hex default, so a colour the mapper
	# never opened is still a String on the way out - and "#ffffff" is no more
	# readable to a compiler than "(1, 1, 1, 1)" is.
	assert_eq(_adapter().format_property_value("#ffffff"), "255 255 255")
	assert_eq(
		_adapter().format_property_value("lamp_1"), "lamp_1", "an ordinary string is left alone"
	)


func test_a_vector_is_space_separated_components() -> void:
	assert_eq(_adapter().format_property_value(Vector3(16, 32, 0)), "16 32 0")
	assert_eq(_adapter().format_property_value(Vector3(1.5, -2.25, 0)), "1.5 -2.25 0")
	assert_eq(_adapter().format_property_value(Vector2(4, 8)), "4 8")


func test_a_flag_is_one_or_zero() -> void:
	assert_eq(_adapter().format_property_value(true), "1", "not the word true")
	assert_eq(_adapter().format_property_value(false), "0")


func test_a_float_keeps_the_snapping_the_rest_of_the_file_uses() -> void:
	assert_eq(_adapter().format_property_value(64.0), "64", "not 64.000")
	assert_eq(_adapter().format_property_value(2.5), "2.5")


# ---------------------------------------------------------------------------
# What reaches the file
# ---------------------------------------------------------------------------


func test_an_exported_entity_carries_its_properties_in_map_notation() -> void:
	var root := _fresh_root()
	var entity := DraftEntityScript.new()
	entity.name = "Lamp"
	entity.entity_type = "light"
	entity.entity_class = "light"
	entity.set_meta("is_entity", true)
	root.add_entity(entity)
	entity.entity_data["color"] = Color(0.2, 0.4, 0.8, 1.0)
	entity.entity_data["mins"] = Vector3(16, 32, 0)
	entity.entity_data["spawnflags_on"] = true
	entity.entity_data["targetname"] = "lamp_1"

	var text := MapIO.export_map_from_level(root)
	assert_true(text.contains('"color" "51 102 204"'), "the colour is numbers in the file")
	assert_true(text.contains('"mins" "16 32 0"'), "and so is the vector")
	assert_true(text.contains('"spawnflags_on" "1"'), "and the flag is 1, not true")
	assert_true(text.contains('"targetname" "lamp_1"'), "a string is untouched")
	assert_false(text.contains("(0.2, 0.4, 0.8, 1)"), "Godot's own notation is gone")
	assert_false(text.contains("(16, 32, 0)"))


func test_the_export_formats_the_same_way_with_no_adapter_given() -> void:
	# The fallback used to `str()` every value, which is the notation this path
	# exists to keep out of the file.
	var root := _fresh_root()
	var entity := DraftEntityScript.new()
	entity.name = "Lamp"
	entity.entity_type = "light"
	entity.entity_class = "light"
	entity.set_meta("is_entity", true)
	root.add_entity(entity)
	entity.entity_data["color"] = Color(1, 0, 0, 1)

	assert_true(
		MapIO.export_map_from_level(root, null).contains('"color" "255 0 0"'),
		"no adapter is not a reason to write Godot notation"
	)


func test_a_format_can_write_colours_its_own_way() -> void:
	# The scale is a per-format convention: some of the family take 0..1. The
	# point of the override is that it is one method, not a rewrite.
	var adapter := _adapter()
	assert_eq(
		adapter.format_color(Color(0.5, 0.5, 0.5, 1.0)),
		"128 128 128",
		"the base adapter writes 0..255, which is what the Quake family uses"
	)
