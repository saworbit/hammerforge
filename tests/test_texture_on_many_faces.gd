extends GutTest
## Texture settings on several selected faces at once, and the keys that slide
## and turn the texture (#1728), on the real plugin and dock. A typed value went
## to the face on show only, so twenty faces took twenty typings, and lining a
## texture up by eye meant typing offsets in steps of 0.01.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFUVMulti = preload("res://addons/hammerforge/hf_uv_multi.gd")
const HFPluginTextureKeys = preload("res://addons/hammerforge/plugin_texture_keys.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _enter() -> Node:
	var level = await rig.make_level()
	rig.undo().clear()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(0.5)
	return level


func _leave(level: Node) -> void:
	var dock = rig.plugin.dock
	if dock.face_select_mode.button_pressed:
		dock.face_select_mode.button_pressed = false
	level.face_selection = {}
	rig.undo().clear()
	dock._apply_grid_snap(_grid_before)
	await rig.leave_level(level)


## Pick `picked`, `{brush_id: [face indices]}`, in Face Select.
func _pick(level: Node, picked: Dictionary) -> void:
	var dock = rig.plugin.dock
	if not dock.face_select_mode.button_pressed:
		dock.face_select_mode.button_pressed = true
	level.face_selection = picked
	level.face_selection_changed.emit()


## The face of `brush` facing along `normal`.
func _facing(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(normal) > 0.99:
			return i
	return -1


## What `face` of `brush` shows at the world point `at`, which lies on it.
func _uv_at(brush: Node, face_idx: int, at: Vector3) -> Vector2:
	var face = brush.faces[face_idx]
	var local: Vector3 = face.world_transform.affine_inverse() * at
	return face._project_uvs_for_vertices(PackedVector3Array([local]))[0]


func test_a_typed_scale_goes_to_all_twenty_faces_and_leaves_their_offsets():
	var level = await _enter()
	var picked := {}
	var offsets := {}
	for b in 4:
		var brush = rig.box(level, "b%d" % b, Vector3(b * 3, 1, 0), Vector3(2, 2, 2))
		var indices: Array = []
		for i in brush.faces.size():
			brush.faces[i].uv_offset = Vector2(b * 0.1, i * 0.1)
			offsets["b%d:%d" % [b, i]] = brush.faces[i].uv_offset
			if picked.size() * 6 + indices.size() < 20:
				indices.append(i)
		picked["b%d" % b] = indices
	_pick(level, picked)
	var count := 0
	for key in picked:
		count += (picked[key] as Array).size()
	assert_eq(count, 20, "twenty faces selected")
	var dock = rig.plugin.dock
	dock.uv_scale_x.value = 0.5
	var set_count := 0
	for b in 4:
		var brush = level.find_brush_by_id("b%d" % b)
		for i in brush.faces.size():
			var face = brush.faces[i]
			var chosen: bool = (picked["b%d" % b] as Array).has(i)
			if chosen:
				set_count += 1
				assert_almost_eq(face.uv_scale.x, 0.5, 0.0001)
			else:
				assert_almost_eq(face.uv_scale.x, 1.0, 0.0001, "an unselected face keeps it")
			assert_eq(face.uv_offset, offsets["b%d:%d" % [b, i]], "every offset kept")
	assert_eq(set_count, 20)
	assert_eq(rig.undo().step_count(), 1, "one step")
	await _leave(level)


func test_a_box_the_faces_disagree_on_shows_mixed():
	var level = await _enter()
	var brush = rig.box(level, "m", Vector3(0, 1, 0), Vector3(2, 2, 2))
	brush.faces[0].uv_offset = Vector2(0.25, 0)
	brush.faces[1].uv_offset = Vector2(0.5, 0)
	_pick(level, {"m": [0, 1]})
	var dock = rig.plugin.dock
	assert_eq(dock.mixed_uv_fields(), ["offset_x"], "the faces differ on U offset only")
	assert_eq(dock.uv_offset_x.get_line_edit().text, "", "with no number shown")
	dock.uv_offset_x.value = 0.75
	assert_eq(dock.mixed_uv_fields(), [], "typing sets both")
	assert_almost_eq(brush.faces[0].uv_offset.x, 0.75, 0.0001)
	assert_almost_eq(brush.faces[1].uv_offset.x, 0.75, 0.0001)
	await _leave(level)


func test_the_arrows_slide_the_texture_the_way_they_point_on_screen():
	var level = await _enter()
	var brush = rig.box(level, "s", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var front := _facing(brush, Vector3.BACK)
	_pick(level, {"s": [front]})
	var middle := Vector3(0, 1, 1)
	var before := _uv_at(brush, front, middle)
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT)), STOP, "the arrow is the texture's")
	var right: Vector3 = rig.camera.global_basis.x
	var along := (right - Vector3.BACK * right.dot(Vector3.BACK)).normalized()
	assert_true(
		_uv_at(brush, front, middle + along * 0.5).is_equal_approx(before),
		"what showed at the middle shows a grid step to the right"
	)
	var after_right := _uv_at(brush, front, middle)
	rig.forward(PluginRig.key(KEY_UP, false, false, true))
	var up: Vector3 = rig.camera.global_basis.y
	var climb := (up - Vector3.BACK * up.dot(Vector3.BACK)).normalized()
	assert_true(
		_uv_at(brush, front, middle + climb * 0.05).is_equal_approx(after_right),
		"Alt slides a tenth of the step, up the screen"
	)
	assert_eq(rig.undo().step_count(), 1, "a quick run of presses is one step")
	assert_true(rig.undo().press_undo())
	await rig.frame()
	var back = level.find_brush_by_id("s")
	assert_true(_uv_at(back, front, middle).is_equal_approx(before), "and one undo takes it back")
	await _leave(level)


func test_shift_turns_the_texture_about_the_face_middle():
	var level = await _enter()
	var brush = rig.box(level, "t", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var front := _facing(brush, Vector3.BACK)
	_pick(level, {"t": [front]})
	var middle := Vector3(0, 1, 1)
	var before := _uv_at(brush, front, middle)
	for case in [
		[KEY_LEFT, false, 15.0],
		[KEY_LEFT, true, 16.0],
		[KEY_RIGHT, false, 1.0],
		[KEY_UP, false, 91.0]
	]:
		rig.forward(PluginRig.key(case[0], false, true, case[1]))
		assert_almost_eq(rad_to_deg(brush.faces[front].uv_rotation), case[2], 0.001, str(case))
		assert_true(_uv_at(brush, front, middle).is_equal_approx(before), "the middle stays put")
	await _leave(level)


func test_the_hud_shows_the_steps_and_the_arrows_still_nudge_objects_outside_face_select():
	var level = await _enter()
	var brush = rig.box(level, "h", Vector3(0, 1, 0), Vector3(2, 2, 2))
	_pick(level, {"h": [0]})
	var lines := HFPluginTextureKeys.hud_lines(level)
	assert_eq(lines[0], "Arrows: Slide texture 0.5 m | Alt: 0.05 m")
	assert_eq(lines[1], "Shift+Left/Right: Turn texture 15° | Alt: 1° | Shift+Up/Down: 90°")
	rig.plugin.dock.face_select_mode.button_pressed = false
	level.face_selection = {}
	rig.select([brush])
	var x: float = brush.global_position.x
	rig.forward(PluginRig.key(KEY_RIGHT))
	assert_ne(level.find_brush_by_id("h").global_position.x, x, "out of Face Select it nudges")
	await _leave(level)
