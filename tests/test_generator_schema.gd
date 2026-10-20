extends GutTest

## HFGeneratorSchema: what a generator's settings are, described well enough for
## the dock to build the controls.
##
## The value of the schema is that it is the *only* description. If defaults and
## schema could disagree, the dock would show one thing and the builder would use
## another, so the builders derive their defaults from here rather than writing
## them twice.

const HFGeneratorSchemaScript = preload("res://addons/hammerforge/hf_generator_schema.gd")

const SCHEMA := [
	{"key": "radius", "type": "float", "default": 128.0},
	{"key": "segments", "type": "int", "default": 8},
	{"key": "post", "type": "bool", "default": true},
	{"key": "fill", "type": "enum", "options": ["Solid", "Open"], "default": 0},
]


func test_defaults_are_every_field_at_its_default():
	var defaults: Dictionary = HFGeneratorSchemaScript.defaults(SCHEMA)
	assert_eq(defaults.size(), 4)
	assert_eq(defaults["radius"], 128.0)
	assert_eq(defaults["segments"], 8)
	assert_eq(defaults["post"], true)
	assert_eq(defaults["fill"], 0)


func test_each_value_comes_back_as_the_type_the_schema_says():
	# A SpinBox hands back a float for everything, and a segment count of 7.999
	# would build seven segments and be very hard to explain.
	var merged: Dictionary = HFGeneratorSchemaScript.merge(
		SCHEMA, {"segments": 7.0, "post": 0, "fill": 1.0, "radius": 64}
	)
	assert_typeof(merged["segments"], TYPE_INT)
	assert_typeof(merged["post"], TYPE_BOOL)
	assert_typeof(merged["fill"], TYPE_INT)
	assert_typeof(merged["radius"], TYPE_FLOAT)
	assert_eq(merged["segments"], 7)
	assert_false(merged["post"])


func test_settings_that_say_nothing_take_the_defaults():
	var merged: Dictionary = HFGeneratorSchemaScript.merge(SCHEMA, {"radius": 200.0})
	assert_eq(merged["radius"], 200.0)
	assert_eq(merged["segments"], 8, "an unmentioned setting keeps its default")


func test_an_empty_dictionary_is_exactly_the_defaults():
	assert_eq(HFGeneratorSchemaScript.merge(SCHEMA, {}), HFGeneratorSchemaScript.defaults(SCHEMA))


func test_keys_the_schema_does_not_describe_are_dropped():
	# A record written by an older version, or by hand, must not smuggle a value
	# into arithmetic that never expected it.
	var merged: Dictionary = HFGeneratorSchemaScript.merge(SCHEMA, {"radius": 10.0, "wat": 99})
	assert_false(merged.has("wat"))
	assert_eq(merged.size(), 4)


func test_fields_are_findable_by_key():
	assert_eq(str(HFGeneratorSchemaScript.field(SCHEMA, "segments")["type"]), "int")
	assert_eq(HFGeneratorSchemaScript.field(SCHEMA, "nothing"), {})


func test_keys_come_back_in_the_order_they_are_described():
	assert_eq(Array(HFGeneratorSchemaScript.keys(SCHEMA)), ["radius", "segments", "post", "fill"])


func test_a_malformed_field_is_skipped_rather_than_crashing():
	var messy := [{"key": "radius", "default": 1.0}, "not a field", {"no_key": true}]
	assert_eq(HFGeneratorSchemaScript.defaults(messy), {"radius": 1.0})
	assert_eq(Array(HFGeneratorSchemaScript.keys(messy)), ["radius"])


func test_an_empty_schema_describes_nothing():
	assert_eq(HFGeneratorSchemaScript.defaults([]), {})
	assert_eq(HFGeneratorSchemaScript.merge([], {"radius": 5.0}), {})


# ===========================================================================
# check_ranges — the schema holds a caller that never saw the dock (#336, #338)
# ===========================================================================

const RANGED := [
	{
		"key": "radius",
		"label": "Radius",
		"type": "float",
		"min": 1.0,
		"max": 4096.0,
		"default": 128.0
	},
	{"key": "segments", "label": "Segments", "type": "int", "min": 1, "max": 128, "default": 8},
	{"key": "post", "label": "Post", "type": "bool", "default": true},
	{"key": "fill", "label": "Fill", "type": "enum", "options": ["Solid", "Open"], "default": 0},
]


func test_settings_inside_the_schema_are_accepted():
	var problem := HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": 256.0, "segments": 16})
	assert_eq(problem, "", "nothing wrong with these")


func test_defaults_are_inside_their_own_schema():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {}), "")


func test_a_non_finite_float_is_refused():
	for value in [NAN, INF, -INF]:
		var problem := HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": value})
		assert_eq(problem, "'Radius' must be finite", "radius %s should be refused" % value)


func test_a_non_finite_int_field_is_refused_before_it_is_coerced():
	# int(NAN) is some integer, so by the time merge() has run the NaN is gone.
	var problem := HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": NAN})
	assert_eq(problem, "'Segments' must be finite")


func test_a_value_past_the_schema_maximum_is_refused():
	var problem := HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 129000})
	assert_eq(problem, "'Segments' must be from 1 to 128")


func test_the_maximum_itself_is_allowed():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 128}), "")
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": 4096.0}), "")


func test_a_bool_is_not_range_checked_and_an_enum_inside_its_options_is_accepted():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"post": false, "fill": 1}), "")
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"fill": 0}), "")


func test_a_value_below_the_schema_minimum_is_refused():
	var problem := HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 0})
	assert_eq(
		problem,
		"'Segments' must be from 1 to 128",
		"the floor is half the range and was never held"
	)


func test_the_minimum_itself_is_allowed():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 1}), "")
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": 1.0}), "")


func test_a_field_with_no_minimum_has_no_floor():
	var open_schema := [{"key": "n", "label": "N", "type": "float", "default": 1.0}]
	assert_eq(HFGeneratorSchemaScript.check_ranges(open_schema, {"n": -1.0e9}), "")


func test_an_enum_index_its_options_do_not_have_is_refused():
	var problem := HFGeneratorSchemaScript.check_ranges(RANGED, {"fill": 7})
	assert_eq(
		problem,
		"'Fill' is one of Solid, Open, or its index from 0",
		"an OptionButton has no item 7 to show"
	)


func test_a_negative_enum_index_is_refused():
	assert_ne(HFGeneratorSchemaScript.check_ranges(RANGED, {"fill": -1}), "")


## An enum with no options is a schema mistake rather than a settings one, and
## the dock builds an empty OptionButton from it either way.
func test_an_enum_declaring_no_options_is_refused():
	var broken := [{"key": "mode", "label": "Mode", "type": "enum", "default": 0}]
	assert_ne(HFGeneratorSchemaScript.check_ranges(broken, {"mode": 0}), "")


func test_a_field_with_no_maximum_has_no_ceiling():
	var open_schema := [{"key": "n", "label": "N", "type": "float", "default": 1.0}]
	assert_eq(HFGeneratorSchemaScript.check_ranges(open_schema, {"n": 1.0e9}), "")


# ===========================================================================
# read_field — the one rule the bridge, the dock and a create apply (#1341)
# ===========================================================================


func test_an_enum_is_taken_by_index_or_by_its_label_in_any_case():
	var fill := HFGeneratorSchemaScript.field(RANGED, "fill")
	for value in [1, 1.0, "Open", "open", "OPEN"]:
		var read: Dictionary = HFGeneratorSchemaScript.read_field(fill, value)
		assert_true(read["ok"], "%s picks Open" % [value])
		assert_eq(read["value"], 1, "%s is index 1" % [value])
	for value in [2, -1, 0.5, "Glass", "1", true, null]:
		var read: Dictionary = HFGeneratorSchemaScript.read_field(fill, value)
		assert_false(read["ok"], "%s is no choice" % [value])
		assert_eq(read["message"], "'Fill' is one of Solid, Open, or its index from 0")


func test_a_label_merges_to_the_index_read_field_gives_it():
	# What the check took is what the build gets. A create handed its settings by
	# label used to pass the check and build with the default instead.
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"fill": "open"}), "")
	var merged: Dictionary = HFGeneratorSchemaScript.merge(RANGED, {"fill": "open"})
	assert_eq(merged["fill"], 1)


func test_an_int_field_refuses_a_fraction_a_string_and_a_bool():
	var segments := HFGeneratorSchemaScript.field(RANGED, "segments")
	for case in [
		[2.5, "'Segments' must be a whole number"],
		["8", "'Segments' must be a number"],
		[true, "'Segments' must be a number"],
		[NAN, "'Segments' must be finite"],
	]:
		var read: Dictionary = HFGeneratorSchemaScript.read_field(segments, case[0])
		assert_false(read["ok"], "%s is no segment count" % [case[0]])
		assert_eq(read["message"], case[1])
	var read: Dictionary = HFGeneratorSchemaScript.read_field(segments, 8.0)
	assert_eq(read["value"], 8)
	assert_typeof(read["value"], TYPE_INT)
	assert_eq(
		HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 2.5}),
		"'Segments' must be a whole number",
		"a create is held to the rule the bridge applies, not rounded down"
	)


func test_a_bool_field_takes_only_a_bool():
	var post := HFGeneratorSchemaScript.field(RANGED, "post")
	assert_true(HFGeneratorSchemaScript.read_field(post, false)["ok"])
	assert_eq(
		HFGeneratorSchemaScript.read_field(post, 0)["message"], "'Post' must be true or false"
	)


func test_a_one_sided_range_is_said_as_one_side():
	var floor_only := {"key": "n", "label": "N", "type": "float", "min": 0.05}
	assert_eq(
		HFGeneratorSchemaScript.read_field(floor_only, 0.01)["message"], "'N' must be 0.05 or more"
	)
	assert_eq(HFGeneratorSchemaScript.read_field(floor_only, 0.05)["value"], 0.05)
	var ceiling_only := {"key": "n", "label": "N", "type": "float", "max": 128}
	assert_eq(
		HFGeneratorSchemaScript.read_field(ceiling_only, 200)["message"], "'N' must be 128 or less"
	)


func test_the_message_names_the_field_as_the_caller_does():
	# The bridge names the key an agent sent; the dock names the label.
	var radius := HFGeneratorSchemaScript.field(RANGED, "radius")
	var by_key: Dictionary = HFGeneratorSchemaScript.read_field(radius, 0.0, "radius")
	assert_eq(by_key["message"], "radius must be from 1 to 4096")
	var by_label: Dictionary = HFGeneratorSchemaScript.read_field(radius, 0.0)
	assert_eq(by_label["message"], "'Radius' must be from 1 to 4096")
