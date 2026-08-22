extends GutTest

const HFPluginVertexInput = preload("res://addons/hammerforge/plugin_vertex_input.gd")


func test_handler_passes_on_null_inputs():
	assert_eq(
		HFPluginVertexInput.handle(null, null, null, null, Vector2.ZERO),
		EditorPlugin.AFTER_GUI_INPUT_PASS
	)


func test_plugin_wrapper_delegates_to_vertex_input_module():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_vertex_input")
	var finish := source.find("func _commit_vertex_op", start)
	var block := source.substr(start, finish - start)
	assert_true(block.contains("HFPluginVertexInput.handle"))
	assert_false(block.contains("cancel_drag"), "Drag cancel lives in the vertex module")
