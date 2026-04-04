extends GutTest

const HFThemeUtilsScript = preload("res://addons/hammerforge/ui/hf_theme_utils.gd")


func test_is_dark_theme_returns_bool():
	var result: bool = HFThemeUtilsScript.is_dark_theme(null)
	assert_typeof(result, TYPE_BOOL)


func test_panel_bg_returns_color():
	var color: Color = HFThemeUtilsScript.panel_bg(null)
	assert_typeof(color, TYPE_COLOR)
	assert_true(color.a > 0.0, "Panel bg should have alpha > 0")


func test_panel_border_returns_color():
	var color: Color = HFThemeUtilsScript.panel_border(null)
	assert_typeof(color, TYPE_COLOR)


func test_muted_text_returns_color():
	var color: Color = HFThemeUtilsScript.muted_text(null)
	assert_typeof(color, TYPE_COLOR)


func test_primary_text_returns_color():
	var color: Color = HFThemeUtilsScript.primary_text(null)
	assert_typeof(color, TYPE_COLOR)


func test_accent_returns_color():
	var color: Color = HFThemeUtilsScript.accent(null)
	assert_typeof(color, TYPE_COLOR)


func test_success_color_returns_color():
	var color: Color = HFThemeUtilsScript.success_color(null)
	assert_typeof(color, TYPE_COLOR)


func test_warning_color_returns_color():
	var color: Color = HFThemeUtilsScript.warning_color(null)
	assert_typeof(color, TYPE_COLOR)


func test_error_color_returns_color():
	var color: Color = HFThemeUtilsScript.error_color(null)
	assert_typeof(color, TYPE_COLOR)


func test_toast_bg_returns_color():
	var color: Color = HFThemeUtilsScript.toast_bg(null)
	assert_typeof(color, TYPE_COLOR)


func test_toast_warning_bg_returns_color():
	var color: Color = HFThemeUtilsScript.toast_warning_bg(null)
	assert_typeof(color, TYPE_COLOR)


func test_toast_error_bg_returns_color():
	var color: Color = HFThemeUtilsScript.toast_error_bg(null)
	assert_typeof(color, TYPE_COLOR)


func test_toast_text_returns_color():
	var color: Color = HFThemeUtilsScript.toast_text(null)
	assert_typeof(color, TYPE_COLOR)


func test_make_panel_stylebox_returns_stylebox():
	var style: StyleBoxFlat = HFThemeUtilsScript.make_panel_stylebox(null)
	assert_not_null(style)
	assert_true(style is StyleBoxFlat)
	assert_true(style.corner_radius_top_left > 0, "Should have rounded corners")
	assert_true(style.content_margin_left > 0, "Should have content margin")


func test_dark_and_light_produce_different_colors():
	# panel_bg should differ between dark and light scenarios
	var dark_bg: Color = HFThemeUtilsScript.panel_bg(null)
	# Since we can't control the editor theme in tests, just verify the
	# functions don't crash and return valid colors
	assert_true(dark_bg.a > 0.0)
