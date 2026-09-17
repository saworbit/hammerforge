extends GutTest

## Justify moves a hand-made UV layout instead of throwing it away (#654).
##
## Every `_justify_face()` branch ended by clearing `custom_uvs`, which drops the
## face back to its projection. The shift was measured from the hand-made
## rectangle and then applied to a different one, so the mapper lost the
## alignment *and* did not get the button's result. For a face nobody had touched
## the two rectangles are the same one, which is why it never showed up.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _wall(root: LevelRoot) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(16, 8, 1),
				"transform": Transform3D(),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _rect_of(uvs: PackedVector2Array) -> Rect2:
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	return Rect2(lo, hi - lo)


func _hand_layout(face: FaceData) -> void:
	# The trapezoid a mapper makes dragging one corner of a decal to line it up.
	face.ensure_custom_uvs()
	var hand := PackedVector2Array()
	for i in face.custom_uvs.size():
		var uv: Vector2 = face.custom_uvs[i]
		hand.append(Vector2(uv.x * 0.5 + 0.25, uv.y * 0.5 + 0.1 * float(i)))
	face.custom_uvs = hand


func test_justify_left_moves_the_layout_rather_than_dropping_it():
	var root := _fresh_root()
	var wall := _wall(root)
	var face: FaceData = wall.get("faces")[0]
	_hand_layout(face)
	var before := _rect_of(face.custom_uvs)
	var width := before.size.x

	root.clear_face_selection()
	root.toggle_face_selection(wall, 0, false)
	root.justify_selected_faces("left", false)

	assert_eq(face.custom_uvs.size(), 4, "the hand layout is still there")
	var after := _rect_of(face.custom_uvs)
	assert_almost_eq(after.position.x, 0.0, 0.0001, "left means the left edge lands at u=0")
	assert_almost_eq(
		after.size.x, width, 0.0001, "and the layout is moved, not rescaled or reprojected"
	)


func test_justify_right_lands_the_right_edge_at_one():
	var root := _fresh_root()
	var wall := _wall(root)
	var face: FaceData = wall.get("faces")[0]
	_hand_layout(face)

	root.clear_face_selection()
	root.toggle_face_selection(wall, 0, false)
	root.justify_selected_faces("right", false)

	assert_almost_eq(_rect_of(face.custom_uvs).end.x, 1.0, 0.0001, "right edge at u=1")


func test_a_face_nobody_laid_out_still_justifies_through_the_offset():
	# Without a hand layout the projection is the truth, and Justify must leave
	# the face free to re-project rather than pinning it to explicit UVs.
	var root := _fresh_root()
	var wall := _wall(root)
	var face: FaceData = wall.get("faces")[0]
	assert_eq(face.custom_uvs.size(), 0, "nobody has touched this face")

	root.clear_face_selection()
	root.toggle_face_selection(wall, 0, false)
	root.justify_selected_faces("left", false)

	assert_eq(face.custom_uvs.size(), 0, "it stays on its projection, with the shift in uv_offset")
	var projected := face._project_uvs_for_vertices(face.local_verts)
	assert_almost_eq(_rect_of(projected).position.x, 0.0, 0.0001, "and Justify Left still works")


func test_the_unreachable_stretch_mode_is_gone():
	# It was character for character the "fit" body and no button or console
	# command could ask for it, so it could not have been wanted.
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_brush_system.gd"
	)
	assert_false(source.contains('"stretch"'), "a mode nothing can reach is not a mode")
