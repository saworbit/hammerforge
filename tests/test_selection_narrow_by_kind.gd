extends GutTest
## Selection Info lists each kind in a mixed selection with its count, and a
## click on one keeps only that kind (#1698), on the real plugin and dock. A big
## selection could not be narrowed to "only the cuts" or "only the entities".

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _texts(buttons: Array) -> Array:
	var out: Array = []
	for button in buttons:
		out.append(button.text)
	return out


func test_a_click_on_a_kind_keeps_only_that_kind():
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(4, 0, 0))
	var lamp: Node = level._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(8, 1, 0)}
	)
	rig.select([a, b, lamp])
	var info = rig.plugin.dock.selection_info
	assert_eq(_texts(info.get_kind_buttons()), ["Brushes 2", "Entities 1"])
	info.get_kind_buttons()[1].pressed.emit()
	assert_eq(rig.plugin.hf_selection, [lamp], "only the light is left")
	assert_eq(info.get_kind_buttons(), [], "and one kind needs no row")
	rig.select([a, b])
	assert_eq(info.get_kind_buttons(), [], "brushes alone are one kind")
	await rig.leave_level(level)
