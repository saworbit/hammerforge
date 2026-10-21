extends GutTest

## Apply Rotation and Scale (#1435): a brush's basis folded into its shape and
## faces, leaving every corner, and every face's look, where it was in the world.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const EditorPluginStandIn = preload("res://tests/support/editor_plugin_stand_in.gd")

const EPS := 0.001

var root: LevelRoot
var _messages: Array = []


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	_messages.clear()
	root.user_message.connect(_heard)


func after_each():
	root = null


func _heard(text: String, level: int) -> void:
	_messages.append([text, level])


func _brush(
	brush_id: String, shape: int, size: Vector3, basis: Basis, origin := Vector3(10, 2, -6)
) -> DraftBrush:
	var brush: DraftBrush = root.create_brush_from_info(
		{"shape": shape, "size": size, "brush_id": brush_id, "sides": 16}
	)
	brush.global_transform = Transform3D(basis, origin)
	return brush


## A different look on every face, so a look that lands on the wrong face shows.
func _dress(brush: DraftBrush) -> void:
	var i := 0
	for face in brush.faces:
		face.material_idx = i
		face.uv_scale = Vector2(1.0 + 0.25 * i, 0.5 + 0.125 * i)
		face.uv_offset = Vector2(0.1 * i, -0.2 * i)
		face.uv_rotation = 0.05 * i
		i += 1
	brush.rebuild_preview()


## Each face as its world corners, a copy of its look, and the UV it shows at
## each corner.
func _faces_in_world(brush: DraftBrush) -> Array:
	var out: Array = []
	var xform := brush.global_transform
	for face in brush.faces:
		var corners := PackedVector3Array()
		for v in face.local_verts:
			corners.append(xform * v)
		var look := FaceDataScript.new()
		look.copy_appearance_from(face)
		out.append({"corners": corners, "uvs": face.shown_uvs(), "look": look})
	return out


## Where each of `corners` sits in `others`, or an empty array when one has no
## corner within `EPS` of it.
static func _corner_map(
	corners: PackedVector3Array, others: PackedVector3Array
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if corners.size() != others.size():
		return out
	for corner in corners:
		var found := -1
		for j in others.size():
			if others[j].distance_to(corner) < EPS:
				found = j
				break
		if found < 0:
			return PackedInt32Array()
		out.append(found)
	return out


func _assert_same_faces_in_world(before: Array, brush: DraftBrush, label: String) -> void:
	var after := _faces_in_world(brush)
	assert_eq(after.size(), before.size(), "%s: as many faces" % label)
	for was in before:
		var now: Dictionary = {}
		var map := PackedInt32Array()
		for candidate in after:
			map = _corner_map(was["corners"], candidate["corners"])
			if not map.is_empty():
				now = candidate
				break
		var corners: PackedVector3Array = was["corners"]
		assert_false(now.is_empty(), "%s: a face still has the corners %s" % [label, corners])
		if now.is_empty():
			continue
		assert_true(
			(now["look"] as FaceData).appearance_matches(was["look"]),
			"%s: the face at %s keeps its look" % [label, corners[0]]
		)
		for i in map.size():
			var uv_was: Vector2 = was["uvs"][i]
			var uv_now: Vector2 = now["uvs"][map[i]]
			assert_true(
				uv_now.distance_to(uv_was) < EPS,
				"%s: the texture at %s stays put (%s, was %s)" % [label, corners[i], uv_now, uv_was]
			)


## Every face wound clockwise seen from outside: its normal points away from the
## brush's middle.
func _assert_wound_outward(brush: DraftBrush, label: String) -> void:
	var centre := Vector3.ZERO
	var count := 0
	for face in brush.faces:
		for v in face.local_verts:
			centre += v
			count += 1
	centre /= float(count)
	for face in brush.faces:
		var middle := Vector3.ZERO
		for v in face.local_verts:
			middle += v
		middle /= float(face.local_verts.size())
		assert_gt(face.normal.dot(middle - centre), 0.0, "%s: a face points outward" % label)


func _apply(brushes: Array) -> void:
	var ids: Array = []
	for brush in brushes:
		ids.append(str(brush.brush_id))
	root.apply_managed_rotation_scale(ids)


func _toast() -> String:
	return str(_messages[-1][0]) if not _messages.is_empty() else ""


# ===========================================================================
# What stays a primitive
# ===========================================================================


func test_a_box_scaled_two_one_one_becomes_a_box_twice_as_long():
	var box := _brush(
		"a", LevelRoot.BrushShape.BOX, Vector3(4, 4, 4), Basis.from_scale(Vector3(2, 1, 1))
	)
	_dress(box)
	var before := _faces_in_world(box)
	_apply([box])
	assert_eq(box.shape, LevelRoot.BrushShape.BOX, "it is still a box")
	assert_almost_eq(box.size, Vector3(8, 4, 4), Vector3.ONE * EPS, "twice as long in size")
	assert_true(box.global_basis.is_equal_approx(Basis.IDENTITY), "with no basis of its own")
	assert_almost_eq(box.global_position, Vector3(10, 2, -6), Vector3.ONE * EPS, "where it was")
	_assert_same_faces_in_world(before, box, "scaled box")
	assert_eq(_messages.size(), 1, "one toast")
	assert_eq(_toast(), "Applied rotation and scale to 1 brush")
	assert_eq(int(_messages[-1][1]), 0, "and nothing lost, so not a warning")


func test_a_quarter_turned_box_stays_a_box_with_its_size_turned():
	var turn := Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(1, 1, 3))
	var box := _brush("a", LevelRoot.BrushShape.BOX, Vector3(2, 4, 6), turn)
	_dress(box)
	var before := _faces_in_world(box)
	_apply([box])
	assert_eq(box.shape, LevelRoot.BrushShape.BOX, "a quarter turn keeps a box a box")
	assert_almost_eq(box.size, Vector3(18, 4, 2), Vector3.ONE * EPS, "its long side along X now")
	assert_true(box.global_basis.is_equal_approx(Basis.IDENTITY))
	_assert_same_faces_in_world(before, box, "quarter turned box")


func test_a_box_turned_30_degrees_becomes_custom_with_the_same_corners_and_looks():
	var box := _brush(
		"a", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), Basis(Vector3.UP, deg_to_rad(30.0))
	)
	_dress(box)
	var before := _faces_in_world(box)
	_apply([box])
	assert_eq(box.shape, LevelRoot.BrushShape.CUSTOM, "a box at 30 degrees is no box")
	assert_true(box.global_basis.is_equal_approx(Basis.IDENTITY))
	_assert_same_faces_in_world(before, box, "turned box")
	_assert_wound_outward(box, "turned box")
	assert_string_contains(_toast(), "%s became custom" % box.name)
	assert_eq(int(_messages[-1][1]), 1, "a lossy fold is a warning")


func test_a_sphere_scaled_unevenly_becomes_an_ellipsoid():
	var sphere := _brush(
		"s", LevelRoot.BrushShape.SPHERE, Vector3(32, 32, 32), Basis.from_scale(Vector3(2, 1, 1))
	)
	var faces_before := sphere.faces.size()
	var before := _faces_in_world(sphere)
	_apply([sphere])
	assert_eq(sphere.shape, LevelRoot.BrushShape.ELLIPSOID, "a stretched sphere is an ellipsoid")
	assert_almost_eq(sphere.size, Vector3(64, 32, 32), Vector3.ONE * EPS)
	assert_eq(sphere.faces.size(), faces_before, "built from the same faces")
	_assert_same_faces_in_world(before, sphere, "stretched sphere")


func test_a_mirrored_box_stays_a_box_and_a_mirrored_wedge_keeps_its_winding():
	var mirror := Basis.from_scale(Vector3(-1, 1, 1)) * Basis(Vector3.UP, deg_to_rad(30.0))
	var box := _brush(
		"a", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), Basis.from_scale(Vector3(-2, 1, 1))
	)
	var wedge := _brush(
		"w", LevelRoot.BrushShape.WEDGE, Vector3(4, 2, 6), mirror, Vector3(-20, 0, 0)
	)
	assert_lt(box.global_basis.determinant(), 0.0, "the box is mirrored")
	assert_lt(wedge.global_basis.determinant(), 0.0, "and so is the wedge")
	_dress(box)
	_dress(wedge)
	var box_before := _faces_in_world(box)
	var wedge_before := _faces_in_world(wedge)
	_apply([box, wedge])
	assert_eq(box.shape, LevelRoot.BrushShape.BOX)
	assert_almost_eq(box.size, Vector3(8, 2, 6), Vector3.ONE * EPS)
	_assert_same_faces_in_world(box_before, box, "mirrored box")
	_assert_wound_outward(box, "mirrored box")
	assert_eq(wedge.shape, LevelRoot.BrushShape.CUSTOM)
	assert_true(wedge.global_basis.is_equal_approx(Basis.IDENTITY))
	_assert_same_faces_in_world(wedge_before, wedge, "mirrored wedge")
	_assert_wound_outward(wedge, "mirrored wedge")


func test_an_unrotated_unscaled_brush_is_left_alone():
	var box := _brush("a", LevelRoot.BrushShape.BOX, Vector3(4, 4, 4), Basis.IDENTITY)
	var faces_before: Array = box.faces.duplicate()
	_apply([box])
	assert_eq(box.faces, faces_before, "the faces are the ones it had")
	assert_eq(_toast(), "No rotation or scale to apply")


# ===========================================================================
# What cannot fold losslessly, each named
# ===========================================================================


func test_a_rotated_cylinder_and_an_unevenly_scaled_one_become_custom_and_say_so():
	var tipped := _brush(
		"c1",
		LevelRoot.BrushShape.CYLINDER,
		Vector3(8, 16, 8),
		Basis(Vector3.RIGHT, deg_to_rad(30.0))
	)
	var squashed := _brush(
		"c2",
		LevelRoot.BrushShape.CYLINDER,
		Vector3(8, 16, 8),
		Basis.from_scale(Vector3(2, 1, 1)),
		Vector3(30, 0, 0)
	)
	var even := _brush(
		"c3",
		LevelRoot.BrushShape.CYLINDER,
		Vector3(8, 16, 8),
		Basis.from_scale(Vector3(2, 3, 2)),
		Vector3(-30, 0, 0)
	)
	var tipped_before := _faces_in_world(tipped)
	var squashed_before := _faces_in_world(squashed)
	_apply([tipped, squashed, even])
	assert_eq(tipped.shape, LevelRoot.BrushShape.CUSTOM, "a tipped cylinder is custom")
	assert_eq(squashed.shape, LevelRoot.BrushShape.CUSTOM, "an oval one too")
	assert_eq(even.shape, LevelRoot.BrushShape.CYLINDER, "one scaled evenly round stays one")
	assert_almost_eq(even.size, Vector3(16, 48, 16), Vector3.ONE * EPS)
	_assert_same_faces_in_world(tipped_before, tipped, "tipped cylinder")
	_assert_same_faces_in_world(squashed_before, squashed, "oval cylinder")
	assert_string_contains(_toast(), "%s, %s became custom" % [tipped.name, squashed.name])
	assert_false(_toast().contains(str(even.name)), "the round one is not named")


func test_a_cylindrical_face_keeps_its_look_in_custom_uvs_and_says_so():
	var box := _brush(
		"a", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), Basis(Vector3.UP, deg_to_rad(30.0))
	)
	box.faces[0].uv_projection = FaceDataScript.UVProjection.CYLINDRICAL
	box.rebuild_preview()
	var before := _faces_in_world(box)
	_apply([box])
	var written := 0
	for face in box.faces:
		if face.uv_projection == FaceDataScript.UVProjection.CYLINDRICAL:
			assert_true(face.has_uv_layout(), "the Cylindrical face carries the UVs it showed")
			written += 1
	assert_eq(written, 1)
	_assert_same_faces_in_world(before, box, "cylindrical face")
	assert_string_contains(_toast(), "Cylindrical faces of %s" % box.name)


func _sculpt(face: FaceData) -> void:
	var sculpt := HFDisplacementDataScript.new()
	sculpt.init_flat(2)
	sculpt.set_distance(1, 1, 0.75)
	sculpt.set_distance(2, 3, -0.5)
	sculpt.set_offset(3, 2, Vector3(0.3, 1.0, 0.2))
	sculpt.set_distance(3, 2, 0.6)
	face.displacement = sculpt


## The sculpted surface's triangle corners, in the world.
func _displaced_points(brush: DraftBrush) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xform := brush.global_transform
	for face in brush.faces:
		if face.displacement == null:
			continue
		for v in face.triangulate()["verts"]:
			out.append(xform * v)
	return out


func test_a_sculpt_keeps_its_heights_under_a_turn_and_an_even_scale():
	var box := _brush(
		"a",
		LevelRoot.BrushShape.BOX,
		Vector3(4, 2, 6),
		Basis(Vector3.UP, deg_to_rad(30.0)) * Basis.from_scale(Vector3(2, 2, 2))
	)
	_sculpt(box.faces[2])
	box.rebuild_preview()
	var before := _displaced_points(box)
	_apply([box])
	assert_true(box.global_basis.is_equal_approx(Basis.IDENTITY))
	var after := _displaced_points(box)
	assert_eq(after.size(), before.size())
	assert_false(_corner_map(before, after).is_empty(), "the sculpted surface is where it was")


func test_a_sculpted_brush_under_an_uneven_scale_is_refused_by_name():
	var basis := Basis.from_scale(Vector3(2, 1, 1))
	var sculpted := _brush("a", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), basis)
	_sculpt(sculpted.faces[2])
	var plain := _brush("b", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), basis, Vector3(30, 0, 0))
	var faces_before: Array = sculpted.faces.duplicate()
	_apply([sculpted, plain])
	assert_true(sculpted.global_basis.is_equal_approx(basis), "the sculpted brush keeps its scale")
	assert_eq(sculpted.faces, faces_before, "and its faces")
	assert_almost_eq(sculpted.size, Vector3(4, 2, 6), Vector3.ONE * EPS)
	assert_true(plain.global_basis.is_equal_approx(Basis.IDENTITY), "the other one is applied")
	assert_string_contains(_toast(), "Left alone: %s" % sculpted.name)
	assert_string_contains(_toast(), "Applied rotation and scale to 1 brush")


func test_when_every_brush_is_refused_the_toast_says_nothing_was_applied():
	var sculpted := _brush(
		"a", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), Basis.from_scale(Vector3(1, 1, 3))
	)
	_sculpt(sculpted.faces[0])
	_apply([sculpted])
	assert_eq(
		_toast(),
		(
			"Nothing applied. Left alone: %s (an uneven scale would stretch its sculpted faces)"
			% sculpted.name
		)
	)


func test_a_structure_piece_is_named_as_now_edited():
	var piece := _brush(
		"a", LevelRoot.BrushShape.BOX, Vector3(4, 2, 6), Basis.from_scale(Vector3(1, 2, 1))
	)
	piece.set_meta(HFGeneratorSystemScript.GENERATOR_META, "gen_1")
	_apply([piece])
	assert_string_contains(_toast(), "%s now read as edited structure pieces" % piece.name)


# ===========================================================================
# The dock
# ===========================================================================


func test_the_dock_button_makes_one_step_and_none_for_a_square_brush():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	var undo = EditorPluginStandIn.FakeUndoRedoManager.new()
	dock.undo_redo = undo
	var box := _brush("a", LevelRoot.BrushShape.BOX, Vector3(4, 4, 4), Basis.IDENTITY)
	dock._selection_nodes = [box]
	dock._on_apply_rotation_scale()
	assert_eq(undo.step_count(), 0, "a square brush leaves no step")
	assert_eq(dock.status_label.text, "Nothing applied")
	box.global_basis = Basis.from_scale(Vector3(3, 1, 1))
	dock._on_apply_rotation_scale()
	assert_eq(undo.step_count(), 1, "a scaled one is a step")
	assert_almost_eq(root.find_brush_by_id("a").size, Vector3(12, 4, 4), Vector3.ONE * EPS)
	undo.press_undo()
	var back: DraftBrush = root.find_brush_by_id("a")
	assert_almost_eq(back.size, Vector3(4, 4, 4), Vector3.ONE * EPS, "undo gives the size back")
	assert_true(
		back.global_basis.is_equal_approx(Basis.from_scale(Vector3(3, 1, 1))), "and the scale"
	)
	undo.free_histories()
