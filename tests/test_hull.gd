extends GutTest
## Hull of Selection and the Hull tool (#1715), on the real plugin and level.
## Merge makes the exact union and refuses brushes that do not touch, so a shape
## that is "everything between these" was built by vertex editing a box.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFHull = preload("res://addons/hammerforge/hf_hull.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")

var rig := PluginRig.new()
var said: Array = []
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _enter() -> Node:
	var level = await rig.make_level()
	said = []
	level.user_message.connect(func(text, _level): said.append(text))
	rig.undo().clear()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	return level


func _leave(level: Node) -> void:
	rig.undo().clear()
	rig.plugin.dock._apply_grid_snap(_grid_before)
	await rig.leave_level(level)


func _ids(level: Node) -> Array:
	var out: Array = []
	for child in level.draft_brushes_node.get_children():
		out.append(str(child.brush_id))
	out.sort()
	return out


func _paint(level: Node, brush: Node, slot: int) -> void:
	for face in brush.faces:
		face.material_idx = slot
	level.tag_brush_dirty(str(brush.brush_id))


func _slots(brush: Node) -> Dictionary:
	var out: Dictionary = {}
	for face in brush.faces:
		out[face.material_idx] = int(out.get(face.material_idx, 0)) + 1
	return out


func _showing(preview: Object) -> bool:
	var container: Node3D = preview._preview_container
	return is_instance_valid(container) and container.visible


func _newest(level: Node, but: Array) -> Node:
	for child in level.draft_brushes_node.get_children():
		if not but.has(child):
			return child
	return null


func test_a_block_on_a_slab_becomes_one_convex_brush_with_its_outer_looks():
	var level = await _enter()
	var palette: Array = []
	for material_name in ["stone", "brick", "wood"]:
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		level.add_material_to_palette(material)
		palette.append(material)
	var slab = rig.box(level, "slab", Vector3.ZERO, Vector3(4, 1, 4))
	var block = rig.box(level, "block", Vector3(0, 1, 0), Vector3(1, 1, 1))
	_paint(level, slab, 0)
	_paint(level, block, 1)
	level.active_material = palette[2]
	rig.select([slab, block])
	rig.plugin._hotkey_palette.action_invoked.emit("hull")
	var dialogs: Array = rig.open_dialogs()
	assert_eq(dialogs.size(), 1, "the hull is asked about")
	if dialogs.size() == 1:
		assert_string_contains(dialogs[0].dialog_text, "Replace 2 brushes")
	assert_true(_showing(level.carve_preview), "with the brush on show in green")
	assert_eq(_ids(level), ["block", "slab"], "and nothing changed yet")
	assert_eq(await rig.accept_dialogs(), 1)
	assert_eq(_ids(level).size(), 1, "one brush")
	var hull = level.draft_brushes_node.get_child(0)
	var bounds: AABB = level.brush_system.world_bounds_of(hull)
	assert_true(bounds.position.is_equal_approx(Vector3(-2, -0.5, -2)), str(bounds))
	assert_true(bounds.size.is_equal_approx(Vector3(4, 2, 4)), "covering both")
	assert_eq(hull.faces.size(), 10, "bottom, four sides, four slopes and the top")
	assert_true(
		HFConvexClip.is_convex_solid(hull.faces, HFConvexClip.interior_point(hull.faces)), "convex"
	)
	assert_eq(_slots(hull), {0: 5, 1: 1, 2: 4}, "outer faces keep their looks, slopes take wood")
	var undo = rig.undo()
	assert_eq(undo.step_count(), 1, "one step")
	assert_eq(undo.scene_history.get_current_action_name(), "Hull of Selection")
	assert_true(undo.press_undo())
	await rig.frame()
	assert_eq(_ids(level), ["block", "slab"], "one undo brings both back")
	level.active_material = null
	await _leave(level)


func test_brushes_apart_are_wrapped_where_merge_still_refuses():
	var level = await _enter()
	rig.box(level, "a", Vector3.ZERO, Vector3(1, 1, 1))
	rig.box(level, "b", Vector3(6, 0, 0), Vector3(1, 1, 1))
	var merge: HFOpResult = level.can_merge_brushes(["a", "b"])
	assert_eq(merge.message, "Merge: the selected brushes do not touch", "Merge is as it was")
	var done: HFOpResult = level.hull_brushes_by_ids(["a", "b"])
	assert_true(done.ok, done.message)
	assert_eq(_ids(level).size(), 1)
	var bounds: AABB = level.brush_system.world_bounds_of(level.draft_brushes_node.get_child(0))
	assert_true(bounds.size.is_equal_approx(Vector3(7, 1, 1)), "spanning the gap: %s" % bounds)
	var one: HFOpResult = level.can_hull_brushes([str(_ids(level)[0])])
	assert_eq(one.message, "Hull: select at least 2 brushes")
	await _leave(level)


func test_eight_corners_make_a_cube_and_four_on_a_plane_are_refused():
	var flat := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 2), Vector3(0, 0, 2)]
	)
	assert_eq(HFHull.of(flat)["reason"], HFHull.FLAT)
	var cube := PackedVector3Array()
	for x in [0.0, 2.0]:
		for y in [0.0, 2.0]:
			for z in [0.0, 2.0]:
				cube.append(Vector3(x, y, z))
	cube.append(Vector3(1, 1, 1))
	var hull: Dictionary = HFHull.of(cube)
	assert_true(hull["ok"])
	assert_eq(hull["faces"].size(), 6, "a cube, the point inside left out")
	assert_eq(hull["corners"].size(), 8)
	var level = await _enter()
	rig.plugin._hotkey_palette.action_invoked.emit("tool_hull")
	var tool = rig.plugin._tool_registry.get_active_tool()
	assert_eq(tool.tool_name(), "Hull", "the palette starts the Hull tool")
	tool._points = flat
	assert_false(tool.finish(), "four points on a plane")
	assert_eq(said.back(), HFHull.FLAT, "say why")
	tool._points = cube
	assert_true(tool.finish())
	var made = level.draft_brushes_node.get_child(0)
	assert_true(made.size.is_equal_approx(Vector3(2, 2, 2)))
	assert_eq(made.faces.size(), 6)
	assert_eq(rig.undo().scene_history.get_current_action_name(), "Create Hull Brush")
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await _leave(level)


func _press(at: Vector2, shift := false, double := false) -> void:
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, at)
	press.shift_pressed = shift
	press.double_click = double
	rig.forward(press)


func _release(at: Vector2) -> void:
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, at))


func test_clicks_double_clicks_and_a_pull_place_the_points():
	var level = await _enter()
	var post = rig.box(level, "post", Vector3(0, 1, 0), Vector3(2, 2, 2))
	rig.plugin._hotkey_palette.action_invoked.emit("tool_hull")
	var tool = rig.plugin._tool_registry.get_active_tool()
	var top := rig.camera.unproject_position(Vector3(0, 2, 0))
	_press(top)
	_release(top)
	_press(top, false, true)
	_release(top)
	assert_eq(tool.get_points().size(), 4, "a double click puts the top face's corners in")
	var ground := rig.camera.unproject_position(Vector3(6, 0, 0))
	_press(ground)
	_release(ground)
	assert_eq(tool.get_points().size(), 5, "and a click one point on the grid")
	assert_eq(rig.forward(PluginRig.key(KEY_BACKSPACE)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool.get_points().size(), 4, "Backspace takes the last one back")
	_press(ground)
	_release(ground)
	assert_eq(rig.forward(PluginRig.key(KEY_ENTER)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	var made = _newest(level, [post])
	assert_not_null(made, "Enter makes the brush")
	if made:
		var bounds: AABB = level.brush_system.world_bounds_of(made)
		assert_true(bounds.position.is_equal_approx(Vector3(-1, 0, -1)), str(bounds))
		assert_true(bounds.end.is_equal_approx(Vector3(6, 2, 1)), str(bounds))
	assert_eq(tool.get_points().size(), 0, "and starts again")
	# The face toward the camera, which looks from +Z and above.
	var side := rig.camera.unproject_position(Vector3(0, 1, 1))
	var out := rig.camera.unproject_position(Vector3(0, 1, 3))
	_press(side, true)
	rig.forward(PluginRig.motion(out, MOUSE_BUTTON_MASK_LEFT))
	_release(out)
	assert_eq(tool.get_points().size(), 8, "a pull puts the face's corners in twice")
	rig.forward(PluginRig.key(KEY_ENTER))
	var pulled = _newest(level, [post, made])
	assert_not_null(pulled, "the pull makes a box beside the post")
	if pulled:
		var box: AABB = level.brush_system.world_bounds_of(pulled)
		assert_true(box.position.is_equal_approx(Vector3(-1, 0, 1)), str(box))
		assert_true(box.size.is_equal_approx(Vector3(2, 2, 2)), str(box))
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await _leave(level)
