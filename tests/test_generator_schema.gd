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
	var problem = HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": 256.0, "segments": 16})
	assert_eq(problem, [], "nothing wrong with these")


func test_defaults_are_inside_their_own_schema():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {}), [])


func test_a_non_finite_float_is_refused():
	for value in [NAN, INF, -INF]:
		var problem = HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": value})
		assert_false(problem.is_empty(), "radius %s should be refused" % value)
		assert_string_contains(str(problem[0]), "Radius")


func test_a_non_finite_int_field_is_refused_before_it_is_coerced():
	# int(NAN) is some integer, so by the time merge() has run the NaN is gone.
	var problem = HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": NAN})
	assert_false(problem.is_empty())
	assert_string_contains(str(problem[0]), "Segments")


func test_a_value_past_the_schema_maximum_is_refused():
	var problem = HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 129000})
	assert_false(problem.is_empty())
	assert_string_contains(str(problem[0]), "128")
	assert_string_contains(str(problem[1]), "128")


func test_the_maximum_itself_is_allowed():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"segments": 128}), [])
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"radius": 4096.0}), [])


func test_a_bool_or_enum_field_is_not_range_checked():
	assert_eq(HFGeneratorSchemaScript.check_ranges(RANGED, {"post": false, "fill": 1}), [])


func test_a_field_with_no_maximum_has_no_ceiling():
	var open_schema := [{"key": "n", "label": "N", "type": "float", "default": 1.0}]
	assert_eq(HFGeneratorSchemaScript.check_ranges(open_schema, {"n": 1.0e9}), [])
