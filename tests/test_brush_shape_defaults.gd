extends GutTest

## What a brush is actually built from when nobody has said otherwise.
##
## Two defaults that did not describe the shape they were on: a round brush was
## built from Godot's `radial_segments` rather than the `sides` it carries, and
## every new face projected its UVs on Z whatever direction it faced.


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _brush(root: LevelRoot, shape: int, sides: int = -1) -> Node:
	var info := {"shape": shape, "size": Vector3(128, 64, 32)}
	if sides >= 0:
		info["sides"] = sides
	return root.create_brush_from_info(info)


## The area a face's triangles cover in UV space. A face with world area and no
## UV area samples one row of texels, which is what "smeared" means.
func _uv_area(face: FaceData) -> float:
	var tri: Dictionary = face.triangulate()
	var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
	var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
	if verts.size() < 3 or uvs.size() != verts.size():
		return 0.0
	var area := 0.0
	for t in range(verts.size() / 3):
		var i := t * 3
		var a: Vector2 = uvs[i + 1] - uvs[i]
		var b: Vector2 = uvs[i + 2] - uvs[i]
		area += 0.5 * absf(a.x * b.y - a.y * b.x)
	return area


# ---------------------------------------------------------------------------
# Round shapes are built from their sides (#482)
# ---------------------------------------------------------------------------


func test_a_cylinder_is_built_from_the_sides_it_was_given() -> void:
	var root := _fresh_root()
	# Faces after the coplanar merge: one per side, plus the two caps.
	for sides in [6, 8, 12, 16]:
		var brush = _brush(root, LevelRoot.BrushShape.CYLINDER, sides)
		assert_eq(brush.sides, sides, "the brush stores what it was asked for")
		assert_eq(
			brush.get_faces().size(),
			sides + 2,
			"a %d-sided cylinder is %d side faces and two caps" % [sides, sides]
		)


func test_a_cone_is_built_from_the_sides_it_was_given() -> void:
	var root := _fresh_root()
	var eight = _brush(root, LevelRoot.BrushShape.CONE, 8)
	var sixteen = _brush(root, LevelRoot.BrushShape.CONE, 16)
	assert_lt(
		eight.get_faces().size(),
		sixteen.get_faces().size(),
		"a cone with fewer sides is fewer faces, rather than a 64-gon either way"
	)


func test_a_round_shape_below_the_minimum_uses_the_default() -> void:
	var root := _fresh_root()
	# `sides` is 4 on every brush the Build tab makes, and on every cylinder in a
	# level saved before this was honoured, so a low number there is not a request
	# for a square prism - the editor has PRISM_TRI and PRISM_PENT for those.
	var default_built = _brush(root, LevelRoot.BrushShape.CYLINDER, 4)
	assert_eq(
		default_built.get_faces().size(),
		DraftBrush.DEFAULT_ROUND_SIDES + 2,
		"a cylinder carrying the generic default is built round, not square"
	)
	assert_eq(DraftBrush.round_sides(4), DraftBrush.DEFAULT_ROUND_SIDES)
	assert_eq(DraftBrush.round_sides(3), DraftBrush.DEFAULT_ROUND_SIDES)
	assert_eq(DraftBrush.round_sides(8), 8, "a count a round shape could have meant is kept")


func test_the_preview_and_the_bake_build_a_cylinder_the_same_way() -> void:
	var root := _fresh_root()
	var brush = _brush(root, LevelRoot.BrushShape.CYLINDER, 12)
	var csg := PrefabFactory.create_prefab(
		LevelRoot.BrushShape.CYLINDER, brush.size, max(3, brush.sides)
	)
	assert_not_null(csg, "the bake builds its CSG through PrefabFactory")
	assert_eq(
		csg.sides, brush.sides, "the shape the bake produces is the one the mapper was looking at"
	)


# ---------------------------------------------------------------------------
# A new face projects on its own axis (#463)
# ---------------------------------------------------------------------------


func test_a_new_face_projects_on_its_dominant_normal_axis() -> void:
	assert_eq(
		FaceData.new().uv_projection,
		FaceData.UVProjection.BOX_UV,
		"PLANAR_Z leaves one UV axis constant on any face that contains the Z axis"
	)


func test_every_face_of_a_new_brush_can_show_a_texture() -> void:
	var root := _fresh_root()
	var shapes := {
		"box": LevelRoot.BrushShape.BOX,
		"cylinder": LevelRoot.BrushShape.CYLINDER,
		"wedge": LevelRoot.BrushShape.WEDGE,
		"pyramid": LevelRoot.BrushShape.PYRAMID,
	}
	for label in shapes:
		var brush = _brush(root, shapes[label])
		for index in range(brush.get_faces().size()):
			assert_gt(
				_uv_area(brush.get_faces()[index]),
				0.0001,
				"%s face %d has UVs that cannot show a texture" % [label, index]
			)


func test_source_uvs_that_span_no_area_are_refused() -> void:
	var root := _fresh_root()
	# CylinderMesh maps both caps onto a line: every vertex of the top cap sits at
	# v = 0 and every vertex of the bottom at v = 0.5. Carried over, that face
	# samples one row of texels however it is textured.
	var brush = _brush(root, LevelRoot.BrushShape.CYLINDER, 16)
	var faces: Array = brush.get_faces()
	var caps := 0
	for face in faces:
		if absf(face.normal.y) > 0.99:
			caps += 1
			assert_eq(
				face.custom_uvs.size(),
				0,
				"a cap falls back to its projection rather than keeping a flat source UV"
			)
			assert_gt(_uv_area(face), 0.0001, "so the cap can show a texture")
	assert_eq(caps, 2, "a cylinder has two caps to check")


func test_texture_lock_compensates_a_face_of_a_brush_nobody_reprojected() -> void:
	var root := _fresh_root()
	var brush = _brush(root, LevelRoot.BrushShape.BOX)
	var top: FaceData = brush.get_faces()[2]
	assert_true(
		top.adjust_uvs_for_rotation(Basis(Vector3.UP, deg_to_rad(90.0))),
		"a projection that does not contain the face cannot be world locked at all"
	)
