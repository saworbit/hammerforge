extends GutTest

## A command that ships with no key, given one in the shortcut dialog, answers
## that key in the viewport at once, through the same dispatch the palette uses
## (#1733).

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func test_a_key_given_to_a_keyless_command_runs_it_in_the_viewport():
	var level = await rig.make_level()
	level.add_prototype_materials()
	rig.box(level, "a", Vector3.ZERO)
	var keymap = rig.plugin._keymap
	assert_true(keymap.chord_of("replace_material", 0).is_empty(), "fixture: no key")
	keymap.set_chord("replace_material", {"keycode": KEY_F12})
	var key := PluginRig.key(KEY_F12)
	assert_eq(rig.forward(key), EditorPlugin.AFTER_GUI_INPUT_STOP, "the key is taken")
	var dialog = rig.plugin.dock._replace_material_dialog
	assert_not_null(dialog, "and Replace Material opened")
	if dialog:
		assert_true(dialog.visible)
		dialog.hide()
	keymap.reset_binding("replace_material")
	await rig.leave_level(level)


func test_a_rebind_redraws_the_surfaces_that_name_it():
	var keymap = rig.plugin._keymap
	var dock = rig.plugin.dock
	keymap.set_chord("tool_draw", {"keycode": KEY_F11})
	assert_string_contains(dock.tool_draw.tooltip_text, "F11", "the dock's Draw button says so")
	keymap.reset_binding("tool_draw")
	assert_false(dock.tool_draw.tooltip_text.contains("F11"), "and the reset too")
