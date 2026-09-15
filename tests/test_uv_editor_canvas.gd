extends GutTest

## The UV editor panel maps a face onto its canvas.
##
## A HammerForge UV is a world coordinate, not a 0..1 fraction, so a 64 unit box
## face spans 64. The panel treated a UV as a fraction of the control: every
## point landed far outside it, nothing was drawn and nothing was selectable, and
## the one interaction it had clamped a dragged point into 0..1 and left the
## face's UV quad no longer a quad.

const UVEditorScript = preload("res://addons/hammerforge/uv_editor.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")

const CANVAS := Vector2(240, 240)

var editor: Control


func before_each():
	editor = UVEditorScript.new()
	add_child_autoqfree(editor)
	editor.size = CANVAS


## One face of a 64 unit box, UVs projected the way FaceData projects them.
func _box_face(span: float = 64.0) -> FaceData:
	var face := FaceDataScript.new()
	face.normal = Vector3.BACK
	face.local_verts = PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(span, 0, 0),
			Vector3(span, span, 0),
			Vector3(0, span, 0),
		]
	)
	face.ensure_custom_uvs()
	return face


func _inside_control(point: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= CANVAS.x and point.y <= CANVAS.y


func test_every_point_of_a_box_face_lands_inside_the_control():
	var face := _box_face()
	editor.set_face(face)

	for uv in face.custom_uvs:
		var point: Vector2 = editor._uv_to_screen(uv)
		assert_true(_inside_control(point), "UV %s drew at %s, outside the panel" % [uv, point])


func test_a_face_at_any_size_fills_the_same_canvas():
	for span in [8.0, 64.0, 512.0]:
		var face := _box_face(span)
		editor.set_face(face)
		for uv in face.custom_uvs:
			assert_true(
				_inside_control(editor._uv_to_screen(uv)),
				"a %s unit face has to fit the canvas too" % span
			)


func test_every_point_of_a_box_face_can_be_reached():
	var face := _box_face()
	editor.set_face(face)

	for i in face.custom_uvs.size():
		var point: Vector2 = editor._uv_to_screen(face.custom_uvs[i])
		assert_eq(
			editor._find_nearest_uv_index(point),
			i,
			"point %d was not selectable at %s" % [i, point]
		)


func test_screen_and_uv_are_inverses():
	var face := _box_face()
	editor.set_face(face)

	for uv in face.custom_uvs:
		var round_tripped: Vector2 = editor._screen_to_uv(editor._uv_to_screen(uv))
		assert_almost_eq(round_tripped.x, uv.x, 0.01, "u did not survive the round trip")
		assert_almost_eq(round_tripped.y, uv.y, 0.01, "v did not survive the round trip")


func test_a_drag_produces_the_uv_the_cursor_is_over():
	var face := _box_face()
	editor.set_face(face)
	var target := Vector2(120, 120)
	var expected: Vector2 = editor._screen_to_uv(target)
	editor._drag_index = 0

	var motion := InputEventMouseMotion.new()
	motion.position = target
	editor._gui_input(motion)

	assert_almost_eq(face.custom_uvs[0].x, expected.x, 0.01)
	assert_almost_eq(face.custom_uvs[0].y, expected.y, 0.01)


## The old clamp collapsed a 32 unit UV into 0..1, which moved one corner 45 UV
## units away from the other three and left the quad bent.
func test_a_drag_keeps_the_point_in_the_face_s_own_range():
	var face := _box_face()
	editor.set_face(face)
	editor._drag_index = 0

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 120)
	editor._gui_input(motion)

	assert_gt(face.custom_uvs[0].x, 1.0, "a world scale UV does not belong in 0..1")
	assert_lt(face.custom_uvs[0].x, 64.0)


func test_a_drag_outside_the_control_is_held_to_the_canvas():
	var face := _box_face()
	editor.set_face(face)
	editor._drag_index = 0

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-4000, 9000)
	editor._gui_input(motion)

	assert_true(
		_inside_control(editor._uv_to_screen(face.custom_uvs[0])),
		"a point dragged off the panel still has to be on it"
	)


## A CYLINDRICAL projection, or any face with a zero UV span, would otherwise be
## a division by zero.
func test_a_face_with_no_span_in_one_axis_still_maps():
	var face := FaceDataScript.new()
	face.normal = Vector3.UP
	face.custom_uvs = PackedVector2Array(
		[Vector2(4, 8), Vector2(4, 8), Vector2(4, 8), Vector2(4, 8)]
	)
	face.local_verts = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])

	editor.set_face(face)

	for uv in face.custom_uvs:
		var point: Vector2 = editor._uv_to_screen(uv)
		assert_true(is_finite(point.x) and is_finite(point.y), "degenerate bounds divided by zero")
		assert_true(_inside_control(point))


func test_no_face_is_not_a_crash():
	editor.set_face(null)
	assert_true(is_finite(editor._uv_to_screen(Vector2.ZERO).x))
