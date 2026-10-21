extends GutTest
## Wrap mode in the plugin (#1428): the UV Editor's Wrap button, or the command
## palette, starts it from the selected face; each click on a face beside it wraps
## the texture over as one undo step and makes the clicked face the next source;
## Escape or a right click ends it. A refusal says why and changes nothing.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginUVWrapScript = preload("res://addons/hammerforge/plugin_uv_wrap.gd")
const HFPluginCommandsScript = preload("res://addons/hammerforge/plugin_commands.gd")
const HFUVWrapScript = preload("res://addons/hammerforge/hf_uv_wrap.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const EPS := 0.0001

var rig := PluginRig.new()
var _level_root: Node = null


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func after_each() -> void:
	if _level_root != null:
		await rig.leave_level(_level_root)
		_level_root = null


func _level() -> Node:
	_level_root = await rig.make_level()
	_level_root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	return _level_root


func _face_idx(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


func _face(brush: Node, normal: Vector3) -> FaceData:
	return brush.faces[_face_idx(brush, normal)]


func _click_at(world_point: Vector3) -> int:
	var aim := rig.camera.unproject_position(world_point)
	rig.forward(PluginRig.motion(aim))
	var answer := rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, aim))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, aim))
	return answer


func _uv_at(brush: Node, face: FaceData, world: Vector3) -> Vector2:
	brush.sync_face_world_transform()
	var local: Vector3 = brush.global_transform.affine_inverse() * world
	return face.shown_uvs_at(PackedVector3Array([local]))[0]


func _toasts_containing(text: String) -> int:
	var count := 0
	for toast in rig.toasts():
		if str(toast).contains(text):
			count += 1
	return count


## A 4 unit box at the origin, its top laid on by hand and selected.
func _box_with_top_selected(level: Node) -> Node:
	var box = rig.box(level, "a", Vector3.ZERO)
	box.sync_face_world_transform()
	var top := _face(box, Vector3.UP)
	top.material_idx = 1
	top.uv_offset = Vector2(0.25, -0.5)
	top.uv_scale = Vector2(0.5, 0.25)
	top.uv_rotation = 0.4
	box.rebuild_preview()
	level.toggle_face_selection(box, _face_idx(box, Vector3.UP), false)
	return box


func test_each_click_wraps_onto_the_face_clicked_as_one_step() -> void:
	var level = await _level()
	var box = _box_with_top_selected(level)
	var steps: int = rig.undo().step_count()

	rig.plugin.dock.uv_wrap_btn.pressed.emit()

	assert_true(HFPluginUVWrapScript.is_active(rig.plugin), "the button starts Wrap")
	assert_eq(_click_at(Vector3(0, 0, 2)), STOP, "a click on the front is Wrap's")
	assert_eq(rig.undo().step_count(), steps + 1, "one step for the click")
	var top := _face(box, Vector3.UP)
	var front := _face(box, Vector3(0, 0, 1))
	for point in [Vector3(-2, 2, 2), Vector3(2, 2, 2), Vector3(0, 2, 2)]:
		assert_almost_eq(
			_uv_at(box, front, point), _uv_at(box, top, point), Vector2(EPS, EPS), "%s" % point
		)
	assert_eq(front.material_idx, 1, "with the top's material")
	assert_eq(
		int(rig.plugin._wrap_source["face_idx"]),
		_face_idx(box, Vector3(0, 0, 1)),
		"the front is where the next click carries from"
	)
	var front_before := front.to_dict()

	rig.undo().press_undo()

	assert_ne(_face(box, Vector3(0, 0, 1)).to_dict(), front_before, "Ctrl+Z takes the click back")


func test_a_face_that_shares_no_edge_is_refused_with_a_toast_and_wrap_stays_on() -> void:
	var level = await _level()
	_box_with_top_selected(level)
	var far = rig.box(level, "b", Vector3(0, 0, 8))
	var before := _face(far, Vector3.UP).to_dict()
	HFPluginCommandsScript.execute(rig.plugin, "uv_wrap")
	var steps: int = rig.undo().step_count()

	_click_at(Vector3(0, 2, 8))

	assert_eq(rig.undo().step_count(), steps, "no step")
	assert_eq(_face(far, Vector3.UP).to_dict(), before, "the face is as it was")
	assert_gt(_toasts_containing(HFUVWrapScript.REFUSALS["no_shared_edge"]), 0, "and it says why")
	assert_true(HFPluginUVWrapScript.is_active(rig.plugin), "Wrap waits for another click")


func test_escape_and_a_right_click_end_wrap() -> void:
	var level = await _level()
	_box_with_top_selected(level)
	HFPluginCommandsScript.execute(rig.plugin, "uv_wrap")
	assert_eq(rig.forward(PluginRig.key(KEY_ESCAPE)), STOP, "Escape is Wrap's")
	assert_false(HFPluginUVWrapScript.is_active(rig.plugin), "and ends it")

	HFPluginCommandsScript.execute(rig.plugin, "uv_wrap")
	var aim := rig.camera.unproject_position(Vector3(0, 0, 2))
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true, aim)), STOP)
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, false, aim))
	assert_false(HFPluginUVWrapScript.is_active(rig.plugin), "a right click ends it")
	var steps: int = rig.undo().step_count()
	_click_at(Vector3(0, 0, 2))
	assert_eq(rig.undo().step_count(), steps, "and the next click is no wrap")


func test_wrap_with_no_face_selected_says_so_and_does_not_start() -> void:
	var level = await _level()
	rig.box(level, "a", Vector3.ZERO)
	level.clear_face_selection()
	HFPluginCommandsScript.execute(rig.plugin, "uv_wrap")
	assert_false(HFPluginUVWrapScript.is_active(rig.plugin), "nothing to carry from")
	assert_gt(_toasts_containing("select the face"), 0, "and it says what to do")


func test_the_palette_lists_wrap_with_no_key() -> void:
	var palette = rig.plugin._hotkey_palette
	assert_not_null(palette, "the plugin has a palette")
	if palette == null:
		return
	var found := false
	for entry in palette._entries:
		if entry["action"] == "uv_wrap":
			found = true
			assert_eq(entry["binding"], "", "with no key")
	assert_true(found, "Wrap Texture is in the palette")
	assert_false(rig.plugin._keymap.has_action("uv_wrap"), "and no key is bound to it")
