extends GutTest

## Faces that point into their brush, found and shown (#1869).
##
## A face wound the wrong way is culled seen from outside and bakes facing into
## the solid, so it looks like any missing face. Validate names the brush, Auto
## Fix turns the face back on a convex brush, and Face Direction draws the back
## of every face in a colour of its own.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")
const HFFaceDirection = preload("res://addons/hammerforge/hf_face_direction.gd")
const HFOverlayColors = preload("res://addons/hammerforge/hf_overlay_colors.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const ReleaseLevels = preload("res://tests/test_release_levels.gd")

var root: LevelRoot


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _box(brush_id: String, centre := Vector3(0, 1, 0)) -> DraftBrush:
	return root.create_brush_from_info(
		{
			"shape": LevelRootType.BrushShape.BOX,
			"size": Vector3(2, 2, 2),
			"center": centre,
			"brush_id": brush_id
		}
	)


func _reverse(face: FaceData) -> void:
	face.local_verts.reverse()
	face.ensure_geometry()


func _inward_findings(result: Dictionary) -> Array:
	return (result["issues"] as Array).filter(func(text): return "pointing into it" in text)


func test_a_face_turned_by_hand_is_the_one_that_points_in():
	var brush := _box("box")
	assert_eq(HFSolidMeasure.inward_faces(brush.faces), PackedInt32Array(), "a box points out")
	assert_eq(HFSolidMeasure.outward_ratio(brush.faces), 1.0)
	_reverse(brush.faces[2])
	assert_eq(HFSolidMeasure.inward_faces(brush.faces), PackedInt32Array([2]))
	assert_true(HFSolidMeasure.is_convex(brush.faces), "turned the right way it is convex")


func test_validate_names_the_brush_and_auto_fix_turns_the_face_back():
	var brush := _box("box")
	brush.name = "Wall"
	_reverse(brush.faces[2])
	_reverse(brush.faces[4])
	var found: Dictionary = root.validate_level(false)
	assert_eq(
		_inward_findings(found),
		["Brush has 2 faces pointing into it, which draw as holes and bake inside out:" + " Wall"]
	)
	assert_false(
		(found["issues"] as Array).any(func(text): return "not a convex solid" in text),
		"the faces are the finding, not the shape: %s" % [found["issues"]]
	)
	var fixed: Dictionary = root.validate_level(true)
	assert_gte(int(fixed["fixed"]), 2, "two faces turned")
	assert_eq(HFSolidMeasure.inward_faces(brush.faces), PackedInt32Array(), "both point out")
	assert_eq(_inward_findings(root.validate_level(false)), [], "and Validate is clean")


func test_auto_fix_leaves_a_displaced_face_and_still_reports_it():
	var brush := _box("box")
	var top := -1
	for index in brush.faces.size():
		if brush.faces[index].normal.y > 0.9:
			top = index
	root.displacement_system.create_displacement("box", top, 2)
	_reverse(brush.faces[top])
	assert_eq(HFSolidMeasure.inward_faces(brush.faces), PackedInt32Array([top]))
	root.validate_level(true)
	assert_eq(
		HFSolidMeasure.inward_faces(brush.faces),
		PackedInt32Array([top]),
		"its sculpt would turn inside out with it"
	)
	assert_eq(_inward_findings(root.validate_level(false)).size(), 1, "so it is still reported")


## Every shape a brush can be is built pointing out, and a torus, which is not
## convex, is not read as pointing in.
func test_no_brush_shape_is_reported():
	var at := 0.0
	for shape in LevelRootType.BrushShape.values():
		if shape == LevelRootType.BrushShape.CUSTOM:
			continue
		root.create_brush_from_info(
			{"shape": shape, "size": Vector3(2, 2, 2), "center": Vector3(at, 1, 0)}
		)
		at += 4.0
	assert_eq(_inward_findings(root.validate_level(false)), [])


## The reference map and every level a release saved: cylinders, structure
## pieces and all, nothing points in.
func test_no_release_level_has_a_face_pointing_in(
	folder = use_parameters(ReleaseLevels._folders())
):
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	assert_true(level.load_hflevel(ReleaseLevels._level_file(folder)), "%s loads" % folder)
	await get_tree().process_frame
	var pointing_in: Array = []
	for brush in level._iter_managed_brush_nodes():
		if HFSolidMeasure.is_convex(brush.faces):
			if not HFSolidMeasure.inward_faces(brush.faces).is_empty():
				pointing_in.append(str(brush.name))
	assert_eq(pointing_in, [], "%s: brushes with a face pointing in" % folder)


func test_face_direction_draws_the_faces_in_its_look_and_puts_them_back():
	var brush := _box("box")
	var before: Dictionary = root.capture_state(false)
	var drawn_with: Material = brush.mesh_instance.material_override
	root.face_direction_view = true
	var look := brush.mesh_instance.material_override as ShaderMaterial
	assert_not_null(look, "the brush draws in the Face Direction look")
	if look == null:
		return
	assert_eq(look, HFFaceDirection.material())
	assert_string_contains(look.shader.code, "cull_disabled")
	assert_true(bool(look.get_meta(DraftBrush.EDITOR_LOOK_META, false)), "an editor look")
	assert_eq(
		look.get_shader_parameter("back_color"),
		HFOverlayColors.get_color(HFOverlayColors.FACE_BACK),
		"in the overlay colours"
	)
	assert_null(brush.material_override, "the brush's own material is left alone")
	assert_true(
		brush.mesh_instance.mesh is ArrayMesh,
		"drawn from its faces, not from the primitive mesh a plain box draws with"
	)
	assert_eq(root.capture_state(false), before, "nothing a step or a save holds changed")
	root.face_direction_view = false
	var back := brush.mesh_instance.material_override as StandardMaterial3D
	assert_not_null(back, "the look it had")
	if back != null and drawn_with is StandardMaterial3D:
		assert_eq(back.albedo_color, (drawn_with as StandardMaterial3D).albedo_color)


## A brush drawn while Face Direction is on takes the look too: one placed, and
## one whose faces are rebuilt by a resize.
func test_a_brush_made_or_rebuilt_while_it_is_on_takes_the_look():
	root.face_direction_view = true
	var brush := _box("box")
	await get_tree().process_frame
	assert_eq(brush.mesh_instance.material_override, HFFaceDirection.material(), "a new brush")
	brush.size = Vector3(3, 2, 2)
	await get_tree().process_frame
	assert_eq(brush.mesh_instance.material_override, HFFaceDirection.material(), "a resize")
