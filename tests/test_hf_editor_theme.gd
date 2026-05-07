extends GutTest

const HFEditorTheme = preload("res://addons/hammerforge/ui/hf_editor_theme.gd")


func test_find_editor_icon_returns_null_with_null_controls():
	var icon = HFEditorTheme.find_editor_icon(null, null, ["NoSuchIcon"])
	assert_null(icon)


func test_has_editor_icon_returns_false_with_null_controls():
	assert_false(HFEditorTheme.has_editor_icon(null, null, "NoSuchIcon"))


func test_get_editor_color_returns_default_when_missing():
	var c = HFEditorTheme.get_editor_color(null, null, "NoSuchColor", Color.RED)
	assert_eq(c, Color.RED)


func test_resolve_stylebox_returns_null_with_null_base():
	var sb = HFEditorTheme.resolve_stylebox(null, "panel", "PanelContainer")
	assert_null(sb)


func test_style_toolbar_button_sets_text_and_focus():
	var btn = Button.new()
	add_child_autoqfree(btn)
	HFEditorTheme.style_toolbar_button(null, null, btn, ["NoneIcon"], "Fallback")
	assert_eq(btn.text, "Fallback")
	assert_true(btn.flat)
	assert_eq(btn.focus_mode, Control.FOCUS_NONE)


func test_style_toolbar_button_safe_with_null_button():
	HFEditorTheme.style_toolbar_button(null, null, null, [], "")  # must not error


func test_find_editor_icon_iterates_priority_list():
	# With null controls, all candidates miss and we get null
	var icon = HFEditorTheme.find_editor_icon(null, null, ["A", "B", "C"])
	assert_null(icon)
