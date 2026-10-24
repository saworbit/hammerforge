extends GutTest

## The command line on the real plugin (#1696): its key opens it over the
## viewport, and both lines, that one and the Console's, run what is typed and
## share one history.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _painting() -> bool:
	return rig.plugin.dock.paint_mode.button_pressed


func test_its_key_opens_the_line_over_the_viewport():
	var level = await rig.make_level()
	rig.forward(PluginRig.motion(Vector2(400, 300)))
	assert_eq(
		rig.forward(PluginRig.key_for("command_line")),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"the plugin takes the key over the viewport"
	)
	var overlay: Control = rig.plugin._command_line_overlay
	assert_not_null(overlay, "the line is built")
	if overlay != null:
		assert_true(overlay.visible, "and shown")
		assert_true(overlay.is_inside_tree(), "over the viewport")
		overlay.get_child(0).cancel()
		assert_false(overlay.visible, "Escape on an empty line closes it")
	await rig.leave_level(level)


func test_both_lines_run_what_is_typed_and_share_one_history():
	var level = await rig.make_level()
	rig.plugin._on_hotkey_palette_action("command_line")
	var over: Node = rig.plugin._command_line_overlay.get_child(0)
	var console: Node = rig.plugin.console_panel.command_line()
	assert_not_null(console, "the Console has a line")
	var painting := _painting()
	over.submit("toggle paint mode")
	await get_tree().process_frame
	assert_ne(_painting(), painting, "the line over the viewport ran it")
	console.submit("")
	await get_tree().process_frame
	assert_eq(_painting(), painting, "Enter on the Console's empty line ran it again")
	assert_eq(rig.plugin.command_line_history, ["toggle paint mode"], "one history")
	await rig.leave_level(level)
