extends GutTest
## Apply Picked Look (#1427): T reads the whole look off a face, its material and
## how it is laid on, and Alt+T gives that look to every selected face as one undo
## step. Shift+T is still the material alone.
##
## The results are checked with `appearance_matches()`, the comparison that reads
## the same fields `copy_appearance_from()` copies, so a field added to the look
## later is checked here without this file being told.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func before_each() -> void:
	# The dock outlives each test's level, and so would the last test's pick.
	if rig.plugin and rig.plugin.dock:
		rig.plugin.dock._picked_look = null
		rig.plugin.dock._picked_look_had_hand_layout = false


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


## A level with three materials, so a look's slot can differ from a target's.
func _level() -> Node:
	var level = await rig.make_level()
	level.set_materials(
		[StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	)
	return level


func _face_idx(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


func _face(brush: Node, normal: Vector3) -> FaceData:
	return brush.faces[_face_idx(brush, normal)]


## Lay a look on a face by hand, as the UV Editor would have.
func _dress(
	face: FaceData, slot: int, offset: Vector2, scale := Vector2.ONE, rotation := 0.0
) -> void:
	face.material_idx = slot
	face.uv_offset = offset
	face.uv_scale = scale
	face.uv_rotation = rotation
	face.custom_uvs = PackedVector2Array()


## The UVs dragged off the projection, as a drag in the UV editor leaves them.
func _lay_by_hand(face: FaceData) -> void:
	face.ensure_custom_uvs()
	var moved := PackedVector2Array()
	for uv in face.custom_uvs:
		moved.append(uv + Vector2(0.37, -0.21))
	face.custom_uvs = moved


func _select_face(level: Node, brush: Node, normal: Vector3) -> void:
	level.toggle_face_selection(brush, _face_idx(brush, normal), true, false)


## T, then a click on the face at `world_point`, as the mapper picks one.
func _pick_at(world_point: Vector3) -> void:
	var aim := rig.camera.unproject_position(world_point)
	rig.forward(PluginRig.motion(aim))
	assert_eq(rig.forward(PluginRig.key_for("texture_picker")), STOP, "T arms the picker")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, aim)), STOP, "a click picks")


func _alt_t() -> int:
	return rig.forward(PluginRig.key_for("apply_picked_look"))


## The UV `face` of `brush` shows at a point in the level that lies on it.
func _uv_at(brush: Node, face: FaceData, world: Vector3) -> Vector2:
	var local: Vector3 = brush.global_transform.affine_inverse() * world
	return face.shown_uvs_at(PackedVector3Array([local]))[0]


func _toasts_containing(text: String) -> int:
	var count := 0
	for toast in rig.toasts():
		if str(toast).contains(text):
			count += 1
	return count


# ---------------------------------------------------------------------------
# The key
# ---------------------------------------------------------------------------


func test_t_then_alt_t_gives_three_faces_the_whole_picked_look() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	var b = rig.box(level, "b", Vector3(8, 0, 0))
	var c = rig.box(level, "c", Vector3(0, 0, -8))
	var look := _face(src, Vector3.UP)
	_dress(look, 2, Vector2(0.25, 0.1), Vector2(0.5, 2.0), 0.3)
	look.uv_projection = FaceDataScript.UVProjection.PLANAR_Y
	look.legacy_wall_axes = true
	src.rebuild_preview()
	_pick_at(Vector3(0, 2, 0))
	assert_has(rig.toasts(), "Picked material #2", "T read the top of the source")
	_select_face(level, a, Vector3.UP)
	_select_face(level, b, Vector3.UP)
	_select_face(level, c, Vector3(0, 0, 1))
	var steps: int = rig.undo().step_count()

	assert_eq(_alt_t(), STOP, "Alt+T is HammerForge's")

	for target in [_face(a, Vector3.UP), _face(b, Vector3.UP), _face(c, Vector3(0, 0, 1))]:
		assert_true(target.appearance_matches(look), "each face has the whole look")
		assert_eq(target.material_idx, 2, "the material")
		assert_eq(target.uv_projection, FaceDataScript.UVProjection.PLANAR_Y, "the projection")
		assert_eq(target.uv_scale, Vector2(0.5, 2.0), "the scale")
		assert_eq(target.uv_offset, Vector2(0.25, 0.1), "the offset")
		assert_almost_eq(target.uv_rotation, 0.3, 0.0001, "the rotation")
	assert_eq(rig.undo().step_count(), steps + 1, "as one undo step")
	assert_has(rig.toasts(), "Applied the picked look to 3 faces")
	await rig.leave_level(level)


func test_two_coplanar_faces_on_different_brushes_line_up_afterwards() -> void:
	var level = await _level()
	# Side by side, so their fronts lie in one plane and meet along x = 0.
	var left = rig.box(level, "left", Vector3(-2, 0, 0))
	var right = rig.box(level, "right", Vector3(2, 0, 0))
	var front := Vector3(0, 0, 1)
	_dress(_face(left, front), 1, Vector2(0.3, 0.1), Vector2(0.5, 0.5), 0.4)
	_dress(_face(right, front), 0, Vector2(0.75, -0.2), Vector2(2.0, 1.0))
	_lay_by_hand(_face(right, front))
	left.rebuild_preview()
	right.rebuild_preview()
	var seam := [Vector3(0, -2, 2), Vector3(0, 0, 2), Vector3(0, 2, 2)]
	var apart := false
	for point in seam:
		var l := _uv_at(left, _face(left, front), point)
		var r := _uv_at(right, _face(right, front), point)
		apart = apart or not l.is_equal_approx(r)
	assert_true(apart, "the two faces start out of line")

	_pick_at(Vector3(-2, 0, 2))
	_select_face(level, right, front)
	_alt_t()

	for point in seam:
		var l := _uv_at(left, _face(left, front), point)
		var r := _uv_at(right, _face(right, front), point)
		assert_true(l.is_equal_approx(r), "one texture runs across the seam at %s" % point)
	await rig.leave_level(level)


func test_one_undo_restores_every_target_custom_uvs_included() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	var b = rig.box(level, "b", Vector3(8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5), Vector2(0.25, 0.25), 1.0)
	_dress(_face(a, Vector3.UP), 1, Vector2(0.1, 0.0), Vector2(3.0, 3.0))
	_lay_by_hand(_face(a, Vector3.UP))
	_dress(_face(b, Vector3.UP), 0, Vector2.ZERO)
	_face(b, Vector3.UP).uv_projection = FaceDataScript.UVProjection.PLANAR_X
	for brush in [src, a, b]:
		brush.rebuild_preview()
	var before := {
		"a": _face(a, Vector3.UP).to_dict(),
		"b": _face(b, Vector3.UP).to_dict(),
	}
	_pick_at(Vector3(0, 2, 0))
	_select_face(level, a, Vector3.UP)
	_select_face(level, b, Vector3.UP)
	_alt_t()
	assert_false(_face(a, Vector3.UP).has_hand_layout(), "the hand layout gave way")

	assert_true(rig.undo().press_undo(), "Ctrl+Z")

	for id in before:
		var brush = level.find_brush_by_id(id)
		assert_eq(
			_face(brush, Vector3.UP).to_dict(), before[id], "%s is as it was, layout and all" % id
		)
	assert_true(rig.undo().press_redo(), "Ctrl+Shift+Z")
	var look := _face(level.find_brush_by_id("src"), Vector3.UP)
	for id in before:
		var redone: FaceData = _face(level.find_brush_by_id(id), Vector3.UP)
		assert_true(redone.appearance_matches(look), "%s has the look again" % id)
	await rig.leave_level(level)


func test_shift_t_still_copies_the_material_only() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5), Vector2(0.25, 0.25), 1.0)
	_dress(_face(a, Vector3.UP), 0, Vector2(0.1, 0.2), Vector2(3.0, 3.0), 0.2)
	_pick_at(Vector3(0, 2, 0))
	_select_face(level, a, Vector3.UP)

	rig.forward(PluginRig.key_for("apply_last_texture"))

	var target := _face(a, Vector3.UP)
	assert_eq(target.material_idx, 2, "Shift+T gives the material")
	assert_eq(target.uv_offset, Vector2(0.1, 0.2), "and leaves the offset")
	assert_eq(target.uv_scale, Vector2(3.0, 3.0), "the scale")
	assert_almost_eq(target.uv_rotation, 0.2, 0.0001, "and the rotation")
	assert_false(target.appearance_matches(_face(src, Vector3.UP)), "so not the whole look")
	await rig.leave_level(level)


## Shift+T on brushes with no face selected paints every one as one undo step
## (#1565). Each brush used to commit its own, so three took three Ctrl+Z.
func test_shift_t_on_three_brushes_is_one_undo_step() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	_dress(_face(src, Vector3.UP), 2, Vector2.ZERO)
	_pick_at(Vector3(0, 2, 0))
	var brushes := [
		rig.box(level, "a", Vector3(-8, 0, 0)),
		rig.box(level, "b", Vector3(8, 0, 0)),
		rig.box(level, "c", Vector3(0, 0, -8)),
	]
	rig.select(brushes)
	await rig.frame()
	var picked: Material = level.get_materials()[2]
	var steps: int = rig.undo().step_count()

	assert_eq(rig.forward(PluginRig.key_for("apply_last_texture")), STOP, "Shift+T")

	for id in ["a", "b", "c"]:
		assert_eq(level.find_brush_by_id(id).material_override, picked, "%s is painted" % id)
	assert_eq(rig.undo().step_count(), steps + 1, "the three are one step")
	assert_true(rig.undo().press_undo(), "Ctrl+Z")
	for id in ["a", "b", "c"]:
		assert_null(level.find_brush_by_id(id).material_override, "one Ctrl+Z takes %s back" % id)
	assert_true(rig.undo().press_redo(), "Ctrl+Shift+Z")
	for id in ["a", "b", "c"]:
		assert_eq(level.find_brush_by_id(id).material_override, picked, "%s is painted again" % id)
	await rig.leave_level(level)


func test_alt_t_with_nothing_picked_says_so_and_changes_nothing() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_select_face(level, a, Vector3.UP)
	var before := _face(a, Vector3.UP).to_dict()
	var steps: int = rig.undo().step_count()

	assert_eq(_alt_t(), STOP, "the key is still HammerForge's")

	assert_eq(_toasts_containing("No look picked yet"), 1, "it says what is missing")
	assert_eq(_face(a, Vector3.UP).to_dict(), before)
	assert_eq(rig.undo().step_count(), steps, "and records nothing")
	await rig.leave_level(level)


func test_alt_t_with_no_face_selected_says_so_and_changes_nothing() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5))
	_pick_at(Vector3(0, 2, 0))
	rig.select([a])
	await rig.frame()
	var before := _face(a, Vector3.UP).to_dict()
	var steps: int = rig.undo().step_count()

	_alt_t()

	assert_eq(_toasts_containing("Select the faces"), 1, "a brush is not a face")
	assert_eq(_face(a, Vector3.UP).to_dict(), before)
	assert_eq(rig.undo().step_count(), steps)
	await rig.leave_level(level)


func test_faces_that_already_have_the_look_leave_no_step() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5))
	_pick_at(Vector3(0, 2, 0))
	_select_face(level, a, Vector3.UP)
	_alt_t()
	var steps: int = rig.undo().step_count()

	_alt_t()

	assert_eq(rig.undo().step_count(), steps, "Ctrl+Z would have nothing to take back")
	assert_eq(_toasts_containing("already have the picked look"), 1)
	await rig.leave_level(level)


# ---------------------------------------------------------------------------
# What travels and what stays
# ---------------------------------------------------------------------------


func test_the_pick_is_a_copy_of_the_look_not_the_face() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5), Vector2(0.25, 0.25))
	_pick_at(Vector3(0, 2, 0))
	var picked: FaceData = FaceDataScript.new()
	picked.copy_appearance_from(_face(src, Vector3.UP))
	# Edited and then deleted after the pick: neither reaches what T read.
	_dress(_face(src, Vector3.UP), 0, Vector2(0.9, 0.9), Vector2(4.0, 4.0))
	level.delete_brush(src)
	_select_face(level, a, Vector3.UP)

	_alt_t()

	assert_true(_face(a, Vector3.UP).appearance_matches(picked), "the look as it was picked")
	await rig.leave_level(level)


func test_a_hand_laid_pick_copies_its_settings_and_says_only_those() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	var look := _face(src, Vector3.UP)
	_dress(look, 2, Vector2(0.5, 0.5), Vector2(0.25, 0.25))
	_lay_by_hand(look)
	src.rebuild_preview()
	_pick_at(Vector3(0, 2, 0))
	_select_face(level, a, Vector3.UP)

	_alt_t()

	var target := _face(a, Vector3.UP)
	assert_true(target.appearance_matches(look), "the settings travel")
	assert_false(target.has_hand_layout(), "the layout does not")
	assert_eq(_toasts_containing("Copied only the picked face's settings to 1 face"), 1)
	assert_eq(_toasts_containing("Applied the picked look"), 0, "rather than claim the look")
	await rig.leave_level(level)


func test_paint_layers_and_a_sculpt_are_left_alone() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0), Vector3(8, 4, 8))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5))
	var top := _face_idx(a, Vector3.UP)
	assert_true(level.create_displacement("a", top, 2), "the target is sculpted")
	assert_true(level.add_surface_paint_layer("a", top), "and painted")
	var sculpt: Dictionary = a.faces[top].displacement.to_dict()
	var layer = a.faces[top].paint_layers[0]
	_pick_at(Vector3(0, 2, 0))
	_select_face(level, a, Vector3.UP)

	_alt_t()

	var target: FaceData = a.faces[top]
	assert_true(target.appearance_matches(_face(src, Vector3.UP)), "the look went on")
	assert_not_null(target.displacement, "the sculpt stayed")
	if target.displacement:
		assert_eq(target.displacement.to_dict(), sculpt, "as it was")
	assert_eq(target.paint_layers.size(), 1, "and the paint layer")
	if target.paint_layers.size() == 1:
		assert_same(target.paint_layers[0], layer)
	await rig.leave_level(level)


# ---------------------------------------------------------------------------
# The other ways in
# ---------------------------------------------------------------------------


func test_the_uv_editor_button_and_the_palette_apply_it_too() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	var b = rig.box(level, "b", Vector3(8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5), Vector2(0.25, 0.25))
	_pick_at(Vector3(0, 2, 0))
	var look := _face(src, Vector3.UP)
	var dock = rig.plugin.dock
	assert_not_null(dock.uv_apply_look_btn, "Paint > UV Editor has the button")
	if dock.uv_apply_look_btn:
		assert_eq(dock.uv_apply_look_btn.text, "Apply Picked Look")

	_select_face(level, a, Vector3.UP)
	if dock.uv_apply_look_btn:
		dock.uv_apply_look_btn.pressed.emit()
	assert_true(_face(a, Vector3.UP).appearance_matches(look), "from the button")

	level.clear_face_selection()
	_select_face(level, b, Vector3.UP)
	rig.plugin._hotkey_palette.action_invoked.emit("apply_picked_look")
	assert_true(_face(b, Vector3.UP).appearance_matches(look), "and from the palette")
	await rig.leave_level(level)


func test_a_slot_gone_from_the_palette_is_refused_with_a_reason() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5))
	_pick_at(Vector3(0, 2, 0))
	level.set_materials([StandardMaterial3D.new()])
	_select_face(level, a, Vector3.UP)
	var before := _face(a, Vector3.UP).to_dict()
	var steps: int = rig.undo().step_count()

	_alt_t()

	assert_eq(_toasts_containing("no longer in the palette"), 1)
	assert_eq(_face(a, Vector3.UP).to_dict(), before)
	assert_eq(rig.undo().step_count(), steps)
	await rig.leave_level(level)


## A face that holds a scale no UV box would accept, from a damaged file say.
## The refusal names it, rather than claiming the faces already have the look.
func test_an_alignment_that_cannot_be_laid_is_refused_with_a_reason() -> void:
	var level = await _level()
	var src = rig.box(level, "src", Vector3.ZERO)
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	_dress(_face(src, Vector3.UP), 2, Vector2(0.5, 0.5))
	_face(src, Vector3.UP).uv_scale = Vector2(0.0, 1.0)
	_pick_at(Vector3(0, 2, 0))
	_select_face(level, a, Vector3.UP)
	var before := _face(a, Vector3.UP).to_dict()
	var steps: int = rig.undo().step_count()

	_alt_t()

	assert_eq(_toasts_containing("cannot be laid on another face"), 1)
	assert_eq(_toasts_containing("already have"), 0)
	assert_eq(_face(a, Vector3.UP).to_dict(), before)
	assert_eq(rig.undo().step_count(), steps)
	await rig.leave_level(level)


# ---------------------------------------------------------------------------
# The level command
# ---------------------------------------------------------------------------


func test_the_level_command_tags_each_brush_it_changes() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3(-8, 0, 0))
	var b = rig.box(level, "b", Vector3(8, 0, 0))
	rig.box(level, "untouched", Vector3(0, 0, -8))
	_select_face(level, a, Vector3.UP)
	_select_face(level, b, Vector3.UP)
	var look: FaceData = FaceDataScript.new()
	look.material_idx = 1
	look.uv_offset = Vector2(0.5, 0.0)
	level.consume_dirty_tags()

	assert_eq(level.apply_look_to_selected_faces(look), 2)

	var tags: Dictionary = level.consume_dirty_tags()
	assert_has(tags["brush_ids"], "a")
	assert_has(tags["brush_ids"], "b")
	assert_does_not_have(tags["brush_ids"], "untouched")
	await rig.leave_level(level)


func test_the_level_command_refuses_a_look_it_cannot_lay() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	_select_face(level, a, Vector3.UP)
	var before := _face(a, Vector3.UP).to_dict()
	var no_slot: FaceData = FaceDataScript.new()
	no_slot.material_idx = 7
	var no_projection: FaceData = FaceDataScript.new()
	no_projection.uv_projection = 99
	var no_scale: FaceData = FaceDataScript.new()
	no_scale.uv_scale = Vector2(0.0, 1.0)

	for look in [null, no_slot, no_projection, no_scale]:
		assert_eq(level.apply_look_to_selected_faces(look), 0)
	assert_eq(_face(a, Vector3.UP).to_dict(), before, "nothing was half laid")
	await rig.leave_level(level)


# ---------------------------------------------------------------------------
# A hand layout
# ---------------------------------------------------------------------------


func test_projected_uvs_stored_on_a_face_are_not_a_hand_layout() -> void:
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var face := _face(a, Vector3.UP)
	assert_false(face.has_hand_layout(), "no stored UVs")
	# What the UV boxes and Reset leave behind.
	face.ensure_custom_uvs()
	assert_false(face.custom_uvs.is_empty())
	assert_false(face.has_hand_layout(), "the projection stored is still the projection")
	_lay_by_hand(face)
	assert_true(face.has_hand_layout(), "a dragged layout is one")
	await rig.leave_level(level)
