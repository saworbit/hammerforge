extends GutTest

const HFPluginHud = preload("res://addons/hammerforge/plugin_hud.gd")


func test_hud_update_is_noop_without_plugin():
	HFPluginHud.update_hud_context(null)
	HFPluginHud.update_context_toolbar_state(null, null, 0)
	assert_true(true, "Null plugin must not crash")


func test_plugin_wrappers_delegate_to_hud_module():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var hud_start := source.find("func _update_hud_context")
	var hud_end := source.find("func _update_context_toolbar_state", hud_start)
	var hud_block := source.substr(hud_start, hud_end - hud_start)
	assert_true(hud_block.contains("HFPluginHud.update_hud_context"))
	assert_false(hud_block.contains("set_mode_indicator"), "Mode banner lives in plugin_hud.gd")

	var toolbar_start := source.find("func _update_context_toolbar_state")
	var toolbar_end := source.find("func should_suppress_empty_selection", toolbar_start)
	var toolbar_block := source.substr(toolbar_start, toolbar_end - toolbar_start)
	assert_true(toolbar_block.contains("HFPluginHud.update_context_toolbar_state"))
	assert_false(
		toolbar_block.contains("pending_cut_count"), "Toolbar counts live in plugin_hud.gd"
	)


func test_hud_module_tracks_mixed_selection_and_pending_cuts():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_hud.gd")
	assert_true(source.contains("mixed_selection"))
	assert_true(source.contains("pending_cut_count"))
	assert_true(source.contains("highlight_connected"))
