extends GutTest

const HFTooltipText = preload("res://addons/hammerforge/ui/hf_tooltip_text.gd")


func test_set_tooltip_assigns_text():
	var btn = Button.new()
	add_child_autoqfree(btn)
	HFTooltipText.set_tooltip(btn, "Hello")
	assert_eq(btn.tooltip_text, "Hello")


func test_set_tooltip_caches_default_in_meta_first_call_only():
	var btn = Button.new()
	add_child_autoqfree(btn)
	HFTooltipText.set_tooltip(btn, "First")
	assert_eq(btn.get_meta("default_tooltip"), "First")
	HFTooltipText.set_tooltip(btn, "Override")
	# Default meta is preserved from FIRST call so toolbar hint system can restore
	assert_eq(btn.get_meta("default_tooltip"), "First")
	assert_eq(btn.tooltip_text, "Override")


func test_set_tooltip_safe_with_null():
	HFTooltipText.set_tooltip(null, "anything")  # must not error


func test_apply_all_skips_missing_controls():
	# Build a stub object that has only one of the catalog properties
	var stub = Node.new()
	add_child_autoqfree(stub)
	var script = GDScript.new()
	script.source_code = ("extends Node\n" + "var grid_snap = null\n" + "var show_grid = null\n")
	script.reload()
	stub.set_script(script)

	var btn = Button.new()
	add_child_autoqfree(btn)
	stub.show_grid = btn

	HFTooltipText.apply_all(stub)
	# Tooltip applied to the one present control
	assert_eq(btn.tooltip_text, HFTooltipText.TEXTS["show_grid"])


func test_apply_all_safe_with_invalid_dock():
	HFTooltipText.apply_all(null)  # must not error


func test_apply_snap_buttons_uses_meta_value():
	var btn = Button.new()
	add_child_autoqfree(btn)
	btn.set_meta("snap_value", 8)
	HFTooltipText.apply_snap_buttons([btn])
	assert_eq(btn.tooltip_text, "Quick snap: 8 units")


func test_apply_snap_buttons_skips_buttons_without_meta():
	var btn = Button.new()
	add_child_autoqfree(btn)
	HFTooltipText.apply_snap_buttons([btn])
	assert_eq(btn.tooltip_text, "")


func test_catalog_is_non_empty():
	assert_gt(HFTooltipText.TEXTS.size(), 50, "catalog should cover the dock controls")
