extends GutTest

## The viewport menu's level rows: place an entity, make or unmake a brush
## entity, group, add to a visgroup, show a face's material, draw as Add or Cut
## (#1724).

const HFViewportContextMenu = preload("res://addons/hammerforge/ui/hf_viewport_context_menu.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")

var menu: HFViewportContextMenu
var rig: PluginRig = null
var _emitted: Array = []


func before_each() -> void:
	menu = HFViewportContextMenu.new()
	add_child_autofree(menu)
	_emitted = []
	menu.action_requested.connect(func(action, args): _emitted.append([action, args]))


func after_each() -> void:
	if is_instance_valid(menu):
		menu.hide()
	if rig:
		await rig.take_down()
		rig = null


func _state(extra: Dictionary) -> Dictionary:
	var state := {
		"has_root": true,
		"cursor_screen": Vector2(10, 10),
		"entity_classes": {"Lights": ["light_point"], "Player": ["player_start"]},
		"brush_entity_classes": ["func_wall", "trigger_once"],
		"visgroups": ["Walls"],
	}
	state.merge(extra, true)
	return state


func _rows(state: Dictionary) -> PackedStringArray:
	menu.show_at(Vector2.ZERO, state)
	var rows := PackedStringArray()
	for i in menu.item_count:
		rows.append(menu.get_item_text(i))
	return rows


func test_rows_shown_with_nothing_selected():
	var rows := _rows(_state({}))
	for row in ["Place Entity Here", "Draw as Add", "Draw as Cut"]:
		assert_has(rows, row)
	for row in ["Make Brush Entity", "Add to Visgroup", "Show Material in Browser", "Group"]:
		assert_does_not_have(rows, row)
	assert_true(menu.is_item_checked(menu.get_item_index(HFViewportContextMenu._ID_DRAW_ADD)))
	assert_false(menu.is_item_checked(menu.get_item_index(HFViewportContextMenu._ID_DRAW_CUT)))


func test_rows_shown_with_brushes_selected():
	var rows := _rows(_state({"brush_count": 2}))
	for row in ["Place Entity Here", "Make Brush Entity", "Group", "Add to Visgroup"]:
		assert_has(rows, row)
	assert_does_not_have(rows, "Back to World", "only for a tied brush")
	assert_does_not_have(rows, "Ungroup", "only for a grouped brush")
	rows = _rows(_state({"brush_count": 1, "tied": true, "grouped": true}))
	assert_has(rows, "Back to World")
	assert_has(rows, "Ungroup")


func test_rows_shown_with_faces_picked():
	var rows := _rows(_state({"face_count": 1, "face_material": 2}))
	assert_has(rows, "Show Material in Browser")
	for row in ["Make Brush Entity", "Place Entity Here", "Draw as Add"]:
		assert_does_not_have(rows, row)
	assert_does_not_have(
		_rows(_state({"face_count": 1, "face_material": -1})), "Show Material in Browser"
	)


func test_rows_shown_with_entities_selected():
	var rows := _rows(_state({"entity_count": 1}))
	assert_has(rows, "Place Entity Here")
	assert_has(rows, "Add to Visgroup")
	assert_does_not_have(rows, "Make Brush Entity")


func test_the_submenus_send_their_choice():
	_rows(_state({"brush_count": 1}))
	menu._on_place_pressed(HFViewportContextMenu._ID_PLACE_BASE + 1)
	menu._on_brush_entity_pressed(HFViewportContextMenu._ID_BRUSH_ENTITY_BASE + 1)
	menu._on_visgroup_pressed(HFViewportContextMenu._ID_VISGROUP_BASE)
	menu._on_visgroup_pressed(HFViewportContextMenu._ID_NEW_VISGROUP)
	assert_eq(
		_emitted,
		[
			["place_entity_here", ["player_start", Vector2(10, 10)]],
			["make_brush_entity", ["trigger_once"]],
			["add_to_visgroup", ["Walls"]],
			["new_visgroup", []],
		]
	)
	var labels := []
	for i in menu._place_submenu.item_count:
		labels.append(menu._place_submenu.get_item_text(i))
	assert_eq(labels, ["Lights", "light_point", "Player", "player_start"], "by category")


func test_draw_as_switches_only_to_the_other_operation():
	_rows(_state({}))
	menu._on_id_pressed(HFViewportContextMenu._ID_DRAW_ADD)
	assert_eq(_emitted, [], "already adding")
	menu._on_id_pressed(HFViewportContextMenu._ID_DRAW_CUT)
	assert_eq(_emitted, [["toggle_operation", []]])


## A rig with undo, a level and one box selected.
func _bring_up() -> Array:
	rig = PluginRig.new()
	await rig.bring_up(self, true)
	if rig.plugin == null:
		return []
	var level = await rig.make_level()
	var box = rig.box(level, "b1", Vector3(0, 2, 0))
	rig.select([box])
	rig.plugin.last_3d_camera = rig.camera
	rig.undo().clear()
	return [level, box]


func test_make_brush_entity_and_back_to_world_are_one_step_each():
	var made := await _bring_up()
	if made.is_empty():
		return
	var box = made[1]
	rig.plugin._dispatch_viewport_action("make_brush_entity", ["func_wall"])
	assert_eq(str(box.get_meta("brush_entity_class", "")), "func_wall")
	assert_eq(rig.undo().step_count(), 1)
	rig.plugin._dispatch_viewport_action("back_to_world", [])
	assert_eq(str(box.get_meta("brush_entity_class", "")), "")
	rig.undo().press_undo()
	assert_eq(str(made[0].find_brush_by_id("b1").get_meta("brush_entity_class", "")), "func_wall")


func test_add_to_a_visgroup_and_a_new_one():
	var made := await _bring_up()
	if made.is_empty():
		return
	var level = made[0]
	level.create_visgroup("Walls")
	rig.plugin._dispatch_viewport_action("add_to_visgroup", ["Walls"])
	assert_has(Array(made[1].get_meta("visgroups", PackedStringArray())), "Walls")
	rig.plugin._dispatch_viewport_action("new_visgroup", [])
	assert_has(Array(level.get_visgroup_names()), "Visgroup 1")
	assert_has(
		Array(level.find_brush_by_id("b1").get_meta("visgroups", PackedStringArray())), "Visgroup 1"
	)
	rig.undo().press_undo()
	assert_does_not_have(Array(level.get_visgroup_names()), "Visgroup 1", "undo takes it away")


func test_place_entity_here_stands_it_on_the_surface_as_one_step():
	var made := await _bring_up()
	if made.is_empty():
		return
	var level = made[0]
	rig.camera.look_at_from_position(Vector3(0, 12, 0.01), Vector3.ZERO)
	await get_tree().process_frame
	var screen := rig.camera.unproject_position(Vector3(0, 4, 0))
	rig.plugin._dispatch_viewport_action("place_entity_here", ["light_point", screen])
	assert_eq(level.get_entity_count(), 1, "an entity")
	assert_eq(rig.undo().step_count(), 1, "one step")
	if level.get_entity_count() == 1:
		var entity: Node3D = level.entities_node.get_child(0)
		assert_almost_eq(entity.global_position.y, 4.0, 0.6, "on top of the box")
	rig.undo().press_undo()
	await get_tree().process_frame
	assert_eq(level.get_entity_count(), 0, "undo takes it away")


func test_show_material_in_browser_selects_the_face_s_material():
	var made := await _bring_up()
	if made.is_empty():
		return
	var level = made[0]
	var box = made[1]
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	level.material_manager.add_material(red)
	level.material_manager.add_material(blue)
	box.faces[0].material_idx = 1
	level.face_selection = {"b1": [0]}
	rig.plugin._dispatch_viewport_action("show_material_in_browser", [])
	assert_eq(rig.plugin.dock._selected_material_index, 1)
	if rig.plugin.dock.material_browser:
		assert_eq(rig.plugin.dock.material_browser.get_selected_index(), 1)


func test_the_menu_state_reads_the_level():
	var made := await _bring_up()
	if made.is_empty():
		return
	var state := HFPluginOverlays.menu_level_state(rig.plugin, made[0])
	assert_true((state["brush_entity_classes"] as Array).has("func_wall"))
	var all_points := []
	for category in state["entity_classes"]:
		all_points.append_array(state["entity_classes"][category])
	assert_true(all_points.has("light_point"))
	assert_false(all_points.has("func_wall"), "a brush entity is not placed as a point")
	assert_true(
		(state["entity_classes"].get("Editor", []) as Array).has("note"),
		"a note is placed from the menu (#1700)"
	)
	assert_false(state["tied"])
