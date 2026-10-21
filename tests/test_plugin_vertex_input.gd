extends GutTest

const HFPluginVertexInput = preload("res://addons/hammerforge/plugin_vertex_input.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")


func test_handler_passes_on_null_inputs():
	assert_eq(
		HFPluginVertexInput.handle(null, null, null, null, Vector2.ZERO),
		EditorPlugin.AFTER_GUI_INPUT_PASS
	)


## In vertex mode a click on a corner of the selected brush picks that vertex,
## through the plugin, and E switches to picking edges.
func test_plugin_wrapper_delegates_to_vertex_input_module():
	var rig := PluginRig.new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	rig.select([rig.box(level, "v", Vector3.ZERO)])
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	var corner := rig.camera.unproject_position(Vector3(2, 2, 2))
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, corner)
	assert_eq(rig.forward(press), EditorPlugin.AFTER_GUI_INPUT_STOP, "the click is taken")
	assert_eq(
		level.vertex_system.get_selected_world_positions(),
		PackedVector3Array([Vector3(2, 2, 2)]),
		"and picks the corner under it"
	)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, corner))
	rig.forward(PluginRig.key_for("vertex_edge_mode"))
	assert_eq(level.vertex_system.sub_mode, level.vertex_system.VertexSubMode.EDGE, "E: edges")
	await rig.leave_level(level)
	await rig.take_down()


func test_drag_cancel_stays_in_the_vertex_module():
	# A grep on purpose: it keeps plugin.gd's vertex callback thin, a boundary the
	# behaviour above cannot see.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_vertex_input")
	var finish := source.find("func _commit_vertex_move", start)
	var block := source.substr(start, finish - start)
	assert_false(block.contains("cancel_drag"), "Drag cancel lives in the vertex module")
