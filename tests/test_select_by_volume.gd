extends GutTest

## Invert Selection, and selecting with a throwaway brush: Select Inside, Partly
## Inside, Touching and Column (#1717).

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _selected() -> Array:
	return rig.plugin.stand_in_editor.selection.get_selected_nodes()


func _light(level, at: Vector3) -> Node:
	return level._create_entity_from_map({"classname": "light_point", "origin": at})


func test_invert_selects_the_other_visible_brushes_and_skips_hidden_ones():
	var level = await rig.make_level()
	var boxes: Array = []
	for i in 10:
		boxes.append(rig.box(level, "b%d" % i, Vector3(i * 5, 1, 0), Vector3(2, 2, 2)))
	var hidden = rig.box(level, "hidden", Vector3(0, 1, 20), Vector3(2, 2, 2))
	level.visgroup_system.add_to_visgroup(hidden, "Off")
	level.visgroup_system.set_visgroup_visible("Off", false)
	rig.select([boxes[0], boxes[1]])
	rig.plugin._on_hotkey_palette_action("invert_selection")
	var picked := _selected()
	assert_eq(picked.size(), 8, "the other eight")
	assert_false(picked.has(boxes[0]) or picked.has(boxes[1]), "not the two")
	assert_false(picked.has(hidden), "not the hidden one")
	rig.select([])
	await rig.leave_level(level)


## A room: a floor, two walls and a lamp, with a crate outside it.
func _room(level) -> Dictionary:
	return {
		"floor": rig.box(level, "floor", Vector3(0, 0.25, 0), Vector3(8, 0.5, 8)),
		"west": rig.box(level, "west", Vector3(-3.75, 2, 0), Vector3(0.5, 3, 8)),
		"east": rig.box(level, "east", Vector3(3.75, 2, 0), Vector3(0.5, 3, 8)),
		"lamp": _light(level, Vector3(0, 3, 0)),
		"crate": rig.box(level, "crate", Vector3(20, 1, 0), Vector3(2, 2, 2)),
	}


func test_select_inside_picks_the_room_deletes_the_box_and_changes_nothing_else():
	var level = await rig.make_level()
	var room := _room(level)
	var volume = rig.box(level, "volume", Vector3(0, 2, 0), Vector3(9, 5, 9))
	var steps: int = rig.undo().step_count()
	rig.select([volume])
	rig.plugin._on_hotkey_palette_action("select_inside")
	var picked := _selected()
	for key in ["floor", "west", "east", "lamp"]:
		assert_true(picked.has(room[key]), "%s is in the room" % key)
	assert_false(picked.has(room["crate"]), "the crate is not")
	assert_null(level.find_brush_by_id("volume"), "the box is gone")
	assert_eq(rig.undo().step_count(), steps + 1, "one step")
	assert_eq(level._iter_managed_brush_nodes().size(), 4, "and nothing else changed")
	rig.undo().press_undo()
	assert_not_null(level.find_brush_by_id("volume"), "undo brings the box back")
	rig.select([])
	await rig.leave_level(level)


func test_select_partly_inside_takes_what_pokes_out():
	var level = await rig.make_level()
	var room := _room(level)
	var volume = rig.box(level, "volume", Vector3(0, 2, 2), Vector3(9, 5, 5))
	rig.select([volume])
	rig.plugin._on_hotkey_palette_action("select_inside")
	assert_false(_selected().has(room["floor"]), "the floor pokes out of a half box")
	rig.undo().press_undo()
	volume = level.find_brush_by_id("volume")
	rig.select([volume])
	rig.plugin._on_hotkey_palette_action("select_partly_inside")
	assert_true(_selected().has(room["floor"]), "so Partly Inside takes it")
	rig.select([])
	await rig.leave_level(level)


func test_select_touching_picks_what_the_box_touches():
	var level = await rig.make_level()
	var room := _room(level)
	# Against the outside of the east wall, from x 4 to 6.
	var volume = rig.box(level, "volume", Vector3(5, 2, 0), Vector3(2, 2, 2))
	var lamp_on_it := _light(level, Vector3(5, 3, 0))
	rig.select([volume])
	rig.plugin._on_hotkey_palette_action("select_touching")
	var picked := _selected()
	assert_true(picked.has(room["east"]), "the wall it touches")
	assert_true(picked.has(lamp_on_it), "the lamp on its top")
	assert_false(picked.has(room["west"]))
	rig.select([])
	await rig.leave_level(level)


func test_select_column_catches_a_light_on_the_floor_above():
	var level = await rig.make_level()
	var ground = rig.box(level, "ground", Vector3(0, 0.25, 0), Vector3(8, 0.5, 8))
	var upper = rig.box(level, "upper", Vector3(0, 4.25, 0), Vector3(8, 0.5, 8))
	var upstairs := _light(level, Vector3(1, 6, 1))
	var elsewhere := _light(level, Vector3(30, 6, 1))
	var volume = rig.box(level, "volume", Vector3(0, 1, 0), Vector3(9, 1, 9))
	rig.select([volume])
	rig.plugin._on_hotkey_palette_action("select_column")
	var picked := _selected()
	assert_true(picked.has(upstairs), "the light on the floor above")
	assert_true(picked.has(ground) and picked.has(upper), "both floors")
	assert_false(picked.has(elsewhere))
	rig.select([])
	await rig.leave_level(level)


func test_a_turned_box_picks_what_is_in_it_not_what_is_in_its_bounds():
	var level = await rig.make_level()
	var near_corner = rig.box(level, "corner", Vector3(4, 1, 4), Vector3(0.5, 0.5, 0.5))
	var middle = rig.box(level, "middle", Vector3(0, 1, 0), Vector3(0.5, 0.5, 0.5))
	var volume = rig.box(level, "volume", Vector3(0, 1, 0), Vector3(6, 4, 6))
	volume.rotation = Vector3(0, deg_to_rad(45), 0)
	rig.select([volume])
	rig.plugin._on_hotkey_palette_action("select_inside")
	var picked := _selected()
	assert_true(picked.has(middle))
	assert_false(picked.has(near_corner), "in the box's bounds, outside the box")
	rig.select([])
	await rig.leave_level(level)


func test_selecting_with_no_single_brush_says_so_and_deletes_nothing():
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var b = rig.box(level, "b", Vector3(5, 1, 0), Vector3(2, 2, 2))
	rig.clear_toasts()
	rig.select([a, b])
	rig.plugin._on_hotkey_palette_action("select_inside")
	assert_not_null(level.find_brush_by_id("a"))
	assert_not_null(level.find_brush_by_id("b"))
	assert_true(rig.toasts().has("Select Inside: select the one brush to select with"))
	rig.select([])
	await rig.leave_level(level)
