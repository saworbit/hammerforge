extends GutTest
## Paste at the cursor, and copy and paste brushes as `.map` text (#1722).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const HFPrefabSystem = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFFileSystem = preload("res://addons/hammerforge/systems/hf_file_system.gd")
const PaintLayer = preload("res://addons/hammerforge/paint/hf_face_paint_layer.gd")

## Where the rig's camera sees the floor in front of the origin.
const AIM := Vector2(400, 380)

var rig := PluginRig.new()
var said: Array = []


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func before_each():
	HFPrefabSystem.system_clipboard_stand_in = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HFPrefabSystem.map_text_path()))


func after_each():
	HFPrefabSystem.system_clipboard_stand_in = null


func _enter() -> Node:
	var level = await rig.make_level()
	# The camera and the cursor a mouse move over the viewport tells the plugin.
	rig.forward(PluginRig.motion(AIM))
	said = []
	level.user_message.connect(func(text, _level): said.append(text))
	rig.undo().clear()
	return level


## The bottom centre of the box round `brushes`.
static func _bottom_centre(brushes: Array) -> Vector3:
	var bounds := AABB()
	var first := true
	for brush in brushes:
		for face in brush.faces:
			for corner in face.local_verts:
				var point: Vector3 = brush.global_transform * corner
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
	return Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)


static func _sizes(brushes: Array) -> Array:
	var out: Array = []
	for brush in brushes:
		out.append(str(brush.size.snapped(Vector3.ONE * 0.01)))
	out.sort()
	return out


func _pasted(level: Node, before: Array) -> Array:
	var out: Array = []
	for brush in level.draft_brushes_node.get_children():
		if not before.has(brush):
			out.append(brush)
	return out


func test_a_room_copied_in_one_level_lands_on_the_floor_under_the_cursor_in_another():
	var first = await _enter()
	var wall = rig.box(first, "wall", Vector3(50, 1.5, 50), Vector3(4, 3, 0.5))
	var other = rig.box(first, "other_wall", Vector3(52, 1.5, 48), Vector3(0.5, 3, 4))
	rig.select([wall, other])
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, first))
	await rig.leave_level(first)
	var level = await _enter()
	var floor_brush = rig.box(level, "floor", Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var hit = level._raycast(rig.camera, AIM)
	assert_not_null(hit, "fixture: the camera sees the floor")
	var at: Vector3 = level._snap_point(hit.position)
	assert_true(HFPluginEditActions.paste_at_cursor(rig.plugin, level, AIM))
	var pasted := _pasted(level, [floor_brush])
	assert_eq(pasted.size(), 2)
	var bottom := _bottom_centre(pasted)
	assert_almost_eq(bottom.y, 0.0, 0.001, "standing on the floor")
	assert_almost_eq(Vector2(bottom.x, bottom.z), Vector2(at.x, at.z), Vector2.ONE * 0.001)
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Paste at Cursor")
	assert_eq(rig.plugin.hf_selection.size(), 2, "and selected")
	await rig.leave_level(level)


func test_copy_puts_map_text_on_the_system_clipboard_and_it_pastes_back():
	var level = await _enter()
	var a = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var b = rig.box(level, "b", Vector3(4, 1, 0), Vector3(1, 2, 3))
	rig.select([a, b])
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, level))
	var text := str(HFPrefabSystem.system_clipboard_stand_in)
	var parsed := MapIO.parse_map_text(text, MapIO.QUAKE_UNITS_PER_METRE, true)
	assert_eq(parsed["errors"], [], "valid .map text")
	assert_eq(parsed["brushes"].size(), 2, "two brushes")
	assert_eq(level.prefab_system.newer_map_text(), "", "its own text is not newer than the copy")
	var wanted := _sizes([a, b])
	await rig.leave_level(level)
	# The same text copied again from elsewhere, so it is newer than the buffer.
	var empty = await _enter()
	rig.box(empty, "floor", Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	HFPrefabSystem.system_clipboard_stand_in = text + "\n"
	var before: Array = empty.draft_brushes_node.get_children()
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, empty), "Ctrl+V takes the text")
	var pasted := _pasted(empty, before)
	assert_eq(_sizes(pasted), wanted, "the same two brushes")
	assert_true(said.any(func(t): return str(t).contains("from .map text")), str(said))
	await rig.leave_level(empty)


func test_a_hand_written_snippet_pastes_and_counts_what_it_left_out():
	var level = await _enter()
	rig.box(level, "floor", Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var snippet := """this line is no part of a map
{
"classname" "worldspawn"
{
( -32 -32 0 ) ( -32 32 0 ) ( 32 32 0 ) floor 0 0 0 1 1
( -32 -32 64 ) ( 32 -32 64 ) ( 32 32 64 ) floor 0 0 0 1 1
( -32 -32 0 ) ( 32 -32 0 ) ( 32 -32 64 ) wall 0 0 0 1 1
( -32 32 0 ) ( -32 32 64 ) ( 32 32 64 ) wall 0 0 0 1 1
( -32 -32 0 ) ( -32 -32 64 ) ( -32 32 64 ) wall 0 0 0 1 1
( 32 -32 0 ) ( 32 32 0 ) ( 32 32 64 ) wall 0 0 0 1 1
}
}
"""
	HFPrefabSystem.system_clipboard_stand_in = snippet
	var before: Array = level.draft_brushes_node.get_children()
	assert_true(HFPluginEditActions.paste_at_cursor(rig.plugin, level, AIM))
	var pasted := _pasted(level, before)
	assert_eq(pasted.size(), 1, "the brush it holds")
	if pasted.size() == 1:
		assert_true(pasted[0].size.is_equal_approx(Vector3(2, 2, 2)), str(pasted[0].size))
	assert_true(
		said.any(func(t): return str(t).contains("left out 1 line it could not read")), str(said)
	)
	await rig.leave_level(level)


func test_a_copy_within_hammerforge_keeps_its_paint():
	var level = await _enter()
	var box = rig.box(level, "painted", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var layer := PaintLayer.new()
	layer.ensure_weight_image(Vector2i(8, 8))
	box.faces[0].paint_layers.append(layer)
	rig.select([box])
	assert_true(HFPluginEditActions.copy_selection(rig.plugin, level))
	var before: Array = level.draft_brushes_node.get_children()
	assert_true(HFPluginEditActions.paste_clipboard(rig.plugin, level))
	var pasted := _pasted(level, before)
	assert_eq(pasted.size(), 1)
	if pasted.size() == 1:
		assert_eq(pasted[0].faces[0].paint_layers.size(), 1, "the buffer, which keeps paint")
	await rig.leave_level(level)
