extends GutTest

## #450. The schema's min/max used to be read in exactly two places: the default
## in `get_setting()`, and the SpinBox `dock._build_tool_settings()` generates.
## So the constraint lived in one control and the tool itself had no opinion - a
## preset, a restore or a script could hand it anything, and three values
## outside one schema failed three different ways.

const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const HFEditorTool = preload("res://addons/hammerforge/hf_editor_tool.gd")


func _tool():
	return HFPathTool.new()


func test_a_value_below_the_schema_minimum_is_clamped():
	var tool_instance = _tool()
	tool_instance.set_setting("path_width", -16.0)
	assert_eq(tool_instance.get_setting("path_width"), 0.5, "Held to the schema's min")


func test_a_value_above_the_schema_maximum_is_clamped():
	var tool_instance = _tool()
	tool_instance.set_setting("path_width", 1.0e9)
	assert_eq(tool_instance.get_setting("path_width"), 64.0, "Held to the schema's max")


func test_zero_is_clamped_to_the_schema_minimum_not_the_brush_minimum():
	var tool_instance = _tool()
	tool_instance.set_setting("path_height", 0.0)
	assert_eq(
		tool_instance.get_setting("path_height"), 0.5, "The schema's 0.5, not MIN_BRUSH_EXTENT"
	)


func test_a_value_inside_the_range_is_kept_as_given():
	var tool_instance = _tool()
	tool_instance.set_setting("path_width", 12.5)
	assert_eq(tool_instance.get_setting("path_width"), 12.5)


func test_a_value_that_is_not_a_number_is_refused():
	var tool_instance = _tool()
	tool_instance.set_setting("path_width", 8.0)
	tool_instance.set_setting("path_width", NAN)
	assert_eq(tool_instance.get_setting("path_width"), 8.0, "The last real value is kept")
	assert_push_warning("is not a number")


func test_an_infinite_value_is_refused():
	var tool_instance = _tool()
	tool_instance.set_setting("path_width", 8.0)
	tool_instance.set_setting("path_width", INF)
	assert_eq(tool_instance.get_setting("path_width"), 8.0)
	assert_push_warning("is not a number")


func test_a_setting_with_no_schema_entry_is_stored_as_given():
	var tool_instance = _tool()
	tool_instance.set_setting("not_in_the_schema", -99.0)
	assert_eq(tool_instance.get_setting("not_in_the_schema"), -99.0)


func test_a_non_numeric_setting_is_untouched():
	var tool_instance = _tool()
	tool_instance.set_setting("miter_joints", false)
	assert_eq(tool_instance.get_setting("miter_joints"), false)


func test_a_bare_tool_with_no_schema_still_stores_settings():
	var bare = HFEditorTool.new()
	bare.set_setting("anything", 3.5)
	assert_eq(bare.get_setting("anything"), 3.5)


# ===========================================================================
# The geometry refuses a degenerate segment on its own too
# ===========================================================================


func test_a_segment_of_no_width_builds_nothing():
	var tool_instance = _tool()
	var info: Dictionary = tool_instance._build_segment_brush(
		Vector3.ZERO, Vector3(256, 0, 0), -16.0, 4.0, "grp"
	)
	assert_true(info.is_empty(), "A negative width reverses the winding, so it builds nothing")


func test_a_segment_of_no_height_builds_nothing():
	var tool_instance = _tool()
	var info: Dictionary = tool_instance._build_segment_brush(
		Vector3.ZERO, Vector3(256, 0, 0), 4.0, 0.0, "grp"
	)
	assert_true(info.is_empty())


func test_a_normal_segment_still_builds():
	var tool_instance = _tool()
	var info: Dictionary = tool_instance._build_segment_brush(
		Vector3.ZERO, Vector3(256, 0, 0), 4.0, 4.0, "grp"
	)
	assert_false(info.is_empty())
	assert_eq(info.get("size"), Vector3(256, 4, 4))
