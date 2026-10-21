extends GutTest

## Paint > UV Editor shows the face's texture under its outline, and has Flip U,
## Flip V, Rotate 90, Fit U and Fit V (#1421).
##
## Mirroring, a quarter turn and fitting one axis took typed numbers in boxes
## that reach only the face on show, and Fit stretched both axes to one repeat,
## which is wrong for a long wall. Each of the five now acts on the whole face
## selection as one undo step and is a command. Flip and Rotate 90 turn about the
## middle of the face's UV rectangle so the texture does not jump; Fit U and Fit V
## scale both axes by one factor, from the `tile` branch of `_justify_face()`.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

const EPS := 0.0001


## The stand-in, answering the two calls the dock's history list makes of the
## editor's manager. With no scene history the list counts its own entries.
class DockUndo:
	extends CollationTests.FakeUndoRedo

	func get_object_history_id(_object: Object) -> int:
		return 0

	func get_history_undo_redo(_id: int) -> UndoRedo:
		return null


var root: LevelRoot


func before_each():
	HFUndoHelper._reset_collation()
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	HFUndoHelper._reset_collation()
	root = null


func _make_dock() -> Node:
	var prefs := HFUserPrefsType.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefsType._defaults()
	prefs.data["show_welcome"] = false
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	dock.undo_redo = DockUndo.new()
	return dock


## A box `size` across, standing at `at`.
func _box(brush_id: String, size: Vector3, at: Vector3 = Vector3.ZERO) -> DraftBrush:
	var place := Transform3D(Basis(), at)
	var brush := (
		root.create_brush_from_info({"size": size, "brush_id": brush_id, "transform": place})
		as DraftBrush
	)
	# What the transform notification does a frame later in the editor. Until then
	# a face projects as though its brush stood at the origin.
	brush.sync_face_world_transform()
	return brush


## The index of the face looking down +Z or -Z: on it U runs along X and V down Y.
func _front(brush_id: String) -> int:
	var brush: DraftBrush = root.brush_system.find_brush_by_id(brush_id)
	for i in brush.faces.size():
		if absf((brush.faces[i] as FaceData).normal.z) > 0.9:
			return i
	return -1


func _face(brush_id: String) -> FaceData:
	var brush: DraftBrush = root.brush_system.find_brush_by_id(brush_id)
	return brush.faces[_front(brush_id)]


func _select(brush_ids: Array) -> void:
	root.clear_face_selection()
	for brush_id in brush_ids:
		root.toggle_face_selection(
			root.brush_system.find_brush_by_id(brush_id), _front(brush_id), true
		)


func _rect(uvs: PackedVector2Array) -> Rect2:
	var low := uvs[0]
	var high := uvs[0]
	for uv in uvs:
		low = low.min(uv)
		high = high.max(uv)
	return Rect2(low, high - low)


func _assert_uvs_near(got: PackedVector2Array, want: PackedVector2Array, message: String) -> void:
	assert_eq(got.size(), want.size(), "%s: corner count" % message)
	for i in mini(got.size(), want.size()):
		assert_almost_eq(got[i].x, want[i].x, EPS, "%s: u of corner %d" % [message, i])
		assert_almost_eq(got[i].y, want[i].y, EPS, "%s: v of corner %d" % [message, i])


## What a face holds, to compare a face with itself after a round of presses.
func _uv_state(face: FaceData) -> Dictionary:
	return {
		"scale": face.uv_scale,
		"offset": face.uv_offset,
		"rotation": face.uv_rotation,
		"shown": face.shown_uvs(),
	}


func _assert_state_near(face: FaceData, was: Dictionary, message: String) -> void:
	assert_almost_eq(face.uv_scale.x, was["scale"].x, EPS, "%s: scale u" % message)
	assert_almost_eq(face.uv_scale.y, was["scale"].y, EPS, "%s: scale v" % message)
	assert_almost_eq(face.uv_offset.x, was["offset"].x, EPS, "%s: offset u" % message)
	assert_almost_eq(face.uv_offset.y, was["offset"].y, EPS, "%s: offset v" % message)
	assert_almost_eq(face.uv_rotation, was["rotation"], EPS, "%s: rotation" % message)
	_assert_uvs_near(face.shown_uvs(), was["shown"], message)


## A face with a layout of its own, as a dragged corner gives it, and one drawn
## from its projection. Both have to come out the same. Neither stands at the
## origin, where the middle of a face's UVs is its offset.
func _two_faces() -> void:
	_box("a", Vector3(4, 2, 1), Vector3(5, 3, 0))
	_box("b", Vector3(3, 1, 1), Vector3(-2, 6, 1))
	root.set_face_uv_params("a", _front("a"), Vector2(2, 1), Vector2(0.3, -0.2), 0.4)
	root.set_face_uv_params("b", _front("b"), Vector2(-1, 0.5), Vector2(0.1, 0.0), 0.0)
	_face("a").ensure_custom_uvs()
	_select(["a", "b"])


func _assert_layout_matches_its_params(face: FaceData, message: String) -> void:
	if face.has_uv_layout():
		_assert_uvs_near(face.custom_uvs, face._project_uvs_for_vertices(face.local_verts), message)


func test_flip_mirrors_each_face_about_its_middle():
	_two_faces()
	for edit in ["flip_u", "flip_v"]:
		var axis := 0 if edit == "flip_u" else 1
		var before := {"a": _face("a").shown_uvs(), "b": _face("b").shown_uvs()}
		var scale_before := {"a": _face("a").uv_scale, "b": _face("b").uv_scale}

		root.edit_selected_face_uvs(edit)

		for brush_id in ["a", "b"]:
			var face := _face(brush_id)
			var was: PackedVector2Array = before[brush_id]
			var rect := _rect(was)
			var mirrored := PackedVector2Array()
			for uv in was:
				var flipped := uv
				flipped[axis] = rect.position[axis] * 2.0 + rect.size[axis] - uv[axis]
				mirrored.append(flipped)
			_assert_uvs_near(face.shown_uvs(), mirrored, "%s on %s" % [edit, brush_id])
			assert_almost_eq(
				face.uv_scale[axis], -scale_before[brush_id][axis], EPS, "the sign is the flip"
			)
			_assert_layout_matches_its_params(
				face, "%s keeps %s's layout its own" % [edit, brush_id]
			)


func test_two_flips_return_the_face_to_where_it_was():
	_two_faces()
	for edit in ["flip_u", "flip_v"]:
		var was := {"a": _uv_state(_face("a")), "b": _uv_state(_face("b"))}
		root.edit_selected_face_uvs(edit)
		root.edit_selected_face_uvs(edit)
		for brush_id in ["a", "b"]:
			_assert_state_near(_face(brush_id), was[brush_id], "two %s on %s" % [edit, brush_id])


func test_rotate_90_is_a_quarter_more_about_the_face_middle():
	_two_faces()
	var was := {"a": _face("a").shown_uvs(), "b": _face("b").shown_uvs()}
	var rotation_before := {"a": _face("a").uv_rotation, "b": _face("b").uv_rotation}

	root.edit_selected_face_uvs("rotate_90")

	for brush_id in ["a", "b"]:
		var face := _face(brush_id)
		assert_almost_eq(
			wrapf(face.uv_rotation - rotation_before[brush_id], -PI, PI),
			PI * 0.5,
			EPS,
			"%s is turned a quarter in Rotate" % brush_id
		)
		var centre_before := _rect(was[brush_id]).get_center()
		var centre_after := _rect(face.shown_uvs()).get_center()
		assert_almost_eq(centre_after.x, centre_before.x, EPS, "%s's middle stays put" % brush_id)
		assert_almost_eq(centre_after.y, centre_before.y, EPS)
		_assert_layout_matches_its_params(face, "%s's layout turned with it" % brush_id)


func test_four_quarter_turns_return_the_face_to_where_it_was():
	_two_faces()
	var was := {"a": _uv_state(_face("a")), "b": _uv_state(_face("b"))}
	for _i in 4:
		root.edit_selected_face_uvs("rotate_90")
	for brush_id in ["a", "b"]:
		_assert_state_near(_face(brush_id), was[brush_id], "four turns on %s" % brush_id)
	assert_eq(_face("b").uv_rotation, 0.0, "a face that started square ends exactly square")


## The acceptance case: one repeat top to bottom and four along.
func test_fit_v_on_a_four_by_one_wall_keeps_the_aspect():
	for laid_out in [false, true]:
		var wall := "laid_out" if laid_out else "projected"
		_box(wall, Vector3(4, 1, 0.25))
		var face := _face(wall)
		root.set_face_uv_params(wall, _front(wall), Vector2(0.7, 0.7), Vector2(0.3, 0.1), 0.0)
		if laid_out:
			face.ensure_custom_uvs()
		_select([wall])

		root.justify_selected_faces("fit_v", false)

		var rect := _rect(face.shown_uvs())
		var label := "with a layout" if laid_out else "from the projection"
		assert_almost_eq(rect.position.y, 0.0, EPS, "%s: the top of the texture at the top" % label)
		assert_almost_eq(rect.size.y, 1.0, EPS, "%s: one repeat top to bottom" % label)
		assert_almost_eq(rect.position.x, 0.0, EPS, "%s: starting on a whole repeat" % label)
		assert_almost_eq(rect.size.x, 4.0, EPS, "%s: four along" % label)


func test_fit_u_fits_the_width_and_repeats_down_the_face():
	_box("pillar", Vector3(1, 4, 0.25))
	var face := _face("pillar")
	root.set_face_uv_params("pillar", _front("pillar"), Vector2(-2, 2), Vector2.ZERO, 0.0)
	_select(["pillar"])

	root.justify_selected_faces("fit_u", false)

	var rect := _rect(face.shown_uvs())
	assert_almost_eq(rect.size.x, 1.0, EPS, "one repeat across")
	assert_almost_eq(rect.size.y, 4.0, EPS, "four down")
	assert_almost_eq(rect.position.x, 0.0, EPS)
	assert_lt(face.uv_scale.x, 0.0, "a mirrored face stays mirrored")
	assert_almost_eq(absf(face.uv_scale.x), absf(face.uv_scale.y), EPS, "the aspect is kept")


func test_fit_u_and_v_change_every_selected_face_together_as_one():
	_box("a", Vector3(4, 1, 0.25))
	_box("b", Vector3(2, 1, 0.25))
	_select(["a", "b"])
	root.justify_selected_faces("fit_v", true)
	var a := _rect(_face("a").shown_uvs())
	var b := _rect(_face("b").shown_uvs())
	assert_almost_eq(a.size.y, 1.0, EPS, "treated as one, both faces share the one height")
	assert_almost_eq(b.size.y, 1.0, EPS)
	assert_almost_eq(a.size.x, 4.0, EPS)
	assert_almost_eq(b.size.x, 2.0, EPS)


func test_each_button_changes_every_selected_face_as_one_step():
	_two_faces()
	var dock := _make_dock()
	var undo = dock.undo_redo
	var buttons := {
		"Flip U": dock.uv_flip_u_btn,
		"Flip V": dock.uv_flip_v_btn,
		"Rotate 90": dock.uv_rotate_90_btn,
		"Fit U": dock.justify_fit_u_btn,
		"Fit V": dock.justify_fit_v_btn,
	}
	for label in buttons:
		var was := {"a": _uv_state(_face("a")), "b": _uv_state(_face("b"))}
		var steps: int = undo.entries.size()

		(buttons[label] as Button).pressed.emit()

		assert_eq(undo.entries.size(), steps + 1, "%s is one step" % label)
		for brush_id in ["a", "b"]:
			assert_ne(
				_face(brush_id).shown_uvs(),
				was[brush_id]["shown"],
				"%s changed %s" % [label, brush_id]
			)
		undo.undo()
		for brush_id in ["a", "b"]:
			_assert_state_near(
				_face(brush_id), was[brush_id], "%s undone on %s" % [label, brush_id]
			)
		undo.redo()
	await get_tree().process_frame


func test_a_press_that_changes_nothing_leaves_no_step():
	_box("a", Vector3(4, 1, 0.25))
	_select(["a"])
	var dock := _make_dock()
	var undo = dock.undo_redo
	dock.justify_fit_v_btn.pressed.emit()
	var steps: int = undo.entries.size()
	root.clear_face_selection()
	dock.uv_flip_u_btn.pressed.emit()
	dock.uv_rotate_90_btn.pressed.emit()
	dock.justify_fit_u_btn.pressed.emit()
	assert_eq(undo.entries.size(), steps, "with no face selected nothing changes")
	await get_tree().process_frame


func test_the_five_are_commands():
	for id in ["uv_flip_u", "uv_flip_v", "uv_rotate_90", "justify_fit_u", "justify_fit_v"]:
		assert_true(HFCommandRegistry.has(id), "%s is in the registry" % id)
		assert_true(HFCommandRegistry.dispatches(id), "and runs")


# ---------------------------------------------------------------------------
# The texture under the outline
# ---------------------------------------------------------------------------


func _textured(size: Vector2i) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(
		Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	)
	return material


func test_the_canvas_shows_the_face_texture_once_per_repeat():
	_box("a", Vector3(4, 2, 1))
	var material := _textured(Vector2i(64, 32))
	var slot := root.material_manager.add_material(material)
	var front := _front("a")
	root.assign_material_to_faces_by_id("a", [front], slot)
	var dock := _make_dock()
	_select(["a"])

	var canvas: UVEditor = dock.uv_editor
	assert_eq(canvas._texture, material.albedo_texture, "the face's albedo is on the canvas")
	assert_eq(
		canvas.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED, "and wraps, one tile a repeat"
	)
	var bounds := _rect(_face("a").shown_uvs())
	var source: Rect2 = canvas._texture_source_rect()
	assert_eq(source.position, bounds.position * Vector2(64, 32), "a UV unit is one texture")
	assert_eq(source.size, bounds.size * Vector2(64, 32))

	dock.uv_scale_up_btn.pressed.emit()
	assert_almost_eq(
		canvas._texture_source_rect().size.x, source.size.x * 2.0, EPS, "it follows Scale"
	)
	dock.uv_offset_x.value = 0.5
	assert_almost_eq(
		canvas._texture_source_rect().position.x,
		source.position.x * 2.0 + 0.5 * 64.0,
		EPS,
		"and Offset"
	)
	var turned_from: Rect2 = canvas._texture_source_rect()
	dock.uv_rotate_90_btn.pressed.emit()
	assert_ne(canvas._texture_source_rect(), turned_from, "and Rotate")


func test_a_face_with_no_texture_keeps_the_blank_canvas():
	_box("a", Vector3(4, 2, 1))
	var dock := _make_dock()
	_select(["a"])
	assert_null(dock.uv_editor._texture, "no palette slot, no texture")
	assert_eq(dock.uv_editor._texture_source_rect(), Rect2())

	var shader := ShaderMaterial.new()
	var slot := root.material_manager.add_material(shader)
	root.assign_material_to_faces_by_id("a", [_front("a")], slot)
	root.clear_face_selection()
	_select(["a"])
	assert_null(dock.uv_editor._texture, "a shader has no albedo to show")


# ---------------------------------------------------------------------------
# A value typed after a Justify (#1539)
# ---------------------------------------------------------------------------


func _assert_one_repeat_at(face: FaceData, at: Vector2, message: String) -> void:
	var rect := _rect(face.shown_uvs())
	assert_almost_eq(rect.position.x, at.x, EPS, "%s: u starts at %.3f" % [message, at.x])
	assert_almost_eq(rect.position.y, at.y, EPS, "%s: v starts at %.3f" % [message, at.y])
	assert_almost_eq(rect.size.x, 1.0, EPS, "%s: one repeat across" % message)
	assert_almost_eq(rect.size.y, 1.0, EPS, "%s: one repeat down" % message)


## Fit, then an Offset U typed into its box, on the face on show and on the other
## selected face. Each keeps its Fit and moves by the offset. Being on show gave a
## face a layout of its own, Fit moved that layout and left the boxes as they
## were, and the typed value rebuilt the face from the boxes, so the Fit was gone.
func test_an_offset_typed_after_fit_keeps_the_fit():
	_box("a", Vector3(4, 2, 1), Vector3(5, 3, 0))
	_box("b", Vector3(3, 1, 1), Vector3(-2, 6, 1))
	var dock := _make_dock()
	_select(["a", "b"])
	var on_show: FaceData = dock._uv_active_face
	assert_true(on_show == _face("a") or on_show == _face("b"), "a selected face is on show")
	assert_false(on_show.has_uv_layout(), "being on show gives a face no layout of its own")

	dock.justify_fit_btn.pressed.emit()
	for brush_id in ["a", "b"]:
		_assert_one_repeat_at(_face(brush_id), Vector2.ZERO, "Fit on %s" % brush_id)

	var first := "a" if on_show == _face("a") else "b"
	var second := "b" if first == "a" else "a"
	var settled := {}
	for brush_id in [first, second]:
		var face := _face(brush_id)
		_select([brush_id])
		assert_eq(dock._uv_active_face, face, "%s is on show" % brush_id)
		var offset_was := face.uv_offset.x
		dock.uv_offset_x.value = offset_was + 0.25
		var moved := face.uv_offset.x - offset_was
		assert_almost_eq(moved, 0.25, 0.01, "the box took the offset")
		_assert_one_repeat_at(face, Vector2(moved, 0.0), "Fit and an offset on %s" % brush_id)
		settled[brush_id] = _uv_state(face)
	_assert_state_near(_face(first), settled[first], "the offset on %s left %s" % [second, first])
	await get_tree().process_frame


## A face with a layout dragged out by hand keeps it, Fit and all, when a value is
## typed: the layout moves the way the value moves the projection, as it does for
## x2, Flip and Rotate 90. The typed value used to throw the layout away.
func test_an_offset_typed_on_a_dragged_layout_moves_the_layout():
	_box("a", Vector3(4, 2, 1), Vector3(5, 3, 0))
	var face := _face("a")
	face.ensure_custom_uvs()
	var dragged := face.custom_uvs.duplicate()
	dragged[2] += Vector2(0.4, -0.3)
	face.custom_uvs = dragged
	var dock := _make_dock()
	_select(["a"])

	dock.justify_fit_btn.pressed.emit()
	assert_true(face.has_uv_layout(), "Fit moved the layout")
	var fitted := face.custom_uvs.duplicate()
	var offset_was := face.uv_offset.x
	dock.uv_offset_x.value = offset_was + 0.25
	var moved := face.uv_offset.x - offset_was

	assert_true(face.has_uv_layout(), "the typed value kept the layout")
	var shifted := PackedVector2Array()
	for uv in fitted:
		shifted.append(uv + Vector2(moved, 0.0))
	_assert_uvs_near(face.custom_uvs, shifted, "the fitted layout moved by the offset")
	await get_tree().process_frame


## Scale, offset and rotation typed on a face whose layout is its projection leave
## the two agreeing: the map a typed value makes of the projection is the map the
## layout is moved by.
func test_a_layout_moves_with_every_value_typed():
	_box("a", Vector3(4, 2, 1), Vector3(5, 3, 0))
	var front := _front("a")
	root.set_face_uv_params("a", front, Vector2(2, 1), Vector2(0.3, -0.2), 0.4)
	_face("a").ensure_custom_uvs()
	var values := [
		[Vector2(0.5, 3), Vector2(0.3, -0.2), 0.4],
		[Vector2(0.5, 3), Vector2(-1.5, 2), 0.4],
		[Vector2(0.5, 3), Vector2(-1.5, 2), -1.2],
		[Vector2(-0.75, 3), Vector2(-1.5, 2), -1.2],
	]
	for typed in values:
		root.set_face_uv_params("a", front, typed[0], typed[1], typed[2])
		assert_true(_face("a").has_uv_layout(), "%s kept the layout" % str(typed))
		_assert_layout_matches_its_params(_face("a"), "after %s" % str(typed))


## A scale of zero has no inverse, so a layout under one cannot be carried and is
## dropped, as every typed value used to drop it, rather than inverted into NaN.
func test_a_layout_under_a_zero_scale_is_dropped_by_a_typed_value():
	_box("a", Vector3(4, 2, 1), Vector3(5, 3, 0))
	var face := _face("a")
	face.ensure_custom_uvs()
	face.uv_scale = Vector2(0.0, 1.0)

	root.set_face_uv_params("a", _front("a"), Vector2(2, 2), Vector2.ZERO, 0.0)

	assert_false(face.has_uv_layout(), "the face is back on its projection")
	assert_eq(face.uv_scale, Vector2(2, 2), "with the value typed")
	assert_true(face.shown_uvs()[0].is_finite())


func _lay_on(edit: String, front: int) -> void:
	match edit:
		"a typed value":
			root.set_face_uv_params("a", front, Vector2(2, 1), Vector2(0.3, -0.2), 0.4)
		"Reset Projected UVs":
			root.reset_uv_on_face("a", front)
		"Re-project":
			root.reproject_face_uvs("a", front, FaceData.UVProjection.PLANAR_Z)
		"Apply + Re-project":
			_select(["a"])
			root.assign_material_and_reproject(-1, FaceData.UVProjection.BOX_UV)


## A typed value, Reset Projected UVs, Re-project and Apply + Re-project each leave
## the face drawn from its projection, so it textures from wherever its brush
## stands. Each used to fill in a layout from the projection, which froze the face:
## moved with Texture Lock off, its texture went with it.
func test_typed_values_and_reprojects_leave_the_face_on_its_projection():
	root.texture_lock = false
	_box("a", Vector3(4, 2, 1), Vector3(5, 3, 0))
	var front := _front("a")
	var x := 5.0
	for edit in ["a typed value", "Reset Projected UVs", "Re-project", "Apply + Re-project"]:
		_lay_on(edit, front)
		assert_false(_face("a").has_uv_layout(), "%s gives the face no layout" % edit)
		x += 1.0
		var brush: DraftBrush = root.brush_system.find_brush_by_id("a")
		root.set_brush_transform_by_id("a", brush.size, Vector3(x, 3, 0))
		# Asked again: a move goes through the resize, which can hand the face over.
		var face := _face("a")
		var there := Transform3D(Basis(), Vector3(x, 3, 0))
		_assert_uvs_near(
			face.shown_uvs(),
			face._project_uvs_in_space(face.local_verts, there),
			"after %s, moved, the face textures from where the brush is" % edit
		)
