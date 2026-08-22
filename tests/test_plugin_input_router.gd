extends GutTest

const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")


func test_router_passes_on_null_inputs():
	assert_eq(
		HFPluginInputRouter.handle_keyboard(null, null, null, 0, false),
		EditorPlugin.AFTER_GUI_INPUT_PASS
	)


func test_plugin_wrapper_delegates_to_router():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_keyboard_input")
	var finish := source.find("func has_cancelable_rmb_gesture", start)
	var block := source.substr(start, finish - start)
	assert_true(block.contains("HFPluginInputRouter.handle_keyboard"))
	assert_false(block.contains("delete_guard"), "Guards live in the router, not the wrapper")


func test_router_keeps_nudge_ownership_guard():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_input_router.gd")
	var start := source.find("# Nudge keys")
	var finish := source.find("# Grid snap size shortcuts", start)
	var block := source.substr(start, finish - start)
	assert_true(block.contains('_guard_hammerforge_shortcut(root, false, 1, "Nudge")'))
	assert_lt(block.find("nudge_guard"), block.find("_nudge_selected"))
