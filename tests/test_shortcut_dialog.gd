extends GutTest

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

# -- Category assignment tests --------------------------------------------------


func test_category_tools():
	assert_eq(HFKeymapType.get_category("tool_draw"), "Tools")
	assert_eq(HFKeymapType.get_category("tool_select"), "Tools")
	assert_eq(HFKeymapType.get_category("tool_extrude_up"), "Tools")


func test_category_vertex_is_tools():
	assert_eq(HFKeymapType.get_category("vertex_edit"), "Tools")


func test_category_paint():
	assert_eq(HFKeymapType.get_category("paint_bucket"), "Paint")
	assert_eq(HFKeymapType.get_category("paint_erase"), "Paint")


func test_category_axis():
	assert_eq(HFKeymapType.get_category("axis_x"), "Axis Lock")
	assert_eq(HFKeymapType.get_category("axis_z"), "Axis Lock")


func test_category_editing_default():
	assert_eq(HFKeymapType.get_category("delete"), "Editing")
	assert_eq(HFKeymapType.get_category("hollow"), "Editing")
	assert_eq(HFKeymapType.get_category("clip"), "Editing")


# -- Action label tests ----------------------------------------------------------


func test_action_label_known():
	assert_eq(HFKeymapType.get_action_label("tool_draw"), "Draw")
	assert_eq(HFKeymapType.get_action_label("hollow"), "Hollow")
	assert_eq(HFKeymapType.get_action_label("paint_blend"), "Blend")


func test_action_label_unknown():
	var label: String = HFKeymapType.get_action_label("some_new_action")
	assert_true(label.length() > 0, "Unknown action should produce a non-empty label")


# -- get_all_bindings test -------------------------------------------------------


func test_get_all_bindings():
	var keymap := HFKeymapType.load_or_default("")
	var bindings := keymap.get_all_bindings()
	assert_true(bindings.has("tool_draw"), "Bindings should contain tool_draw")
	assert_true(bindings.has("hollow"), "Bindings should contain hollow")
	# Verify it's a copy, not a reference
	bindings.erase("tool_draw")
	var orig := keymap.get_all_bindings()
	assert_true(orig.has("tool_draw"), "Original bindings should be unmodified")
