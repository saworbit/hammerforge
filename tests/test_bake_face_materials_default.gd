extends GutTest

## Whether the materials a mapper painted reach the baked mesh.
##
## The bake has two paths. The face-material path triangulates each face and
## resolves its own material; the CSG path does not, and every face of the level
## comes out on one surface. Which one runs is decided by
## `bake_use_face_materials`, and the check box that mirrors it sits inside the
## Advanced fold of the Test tab - so the Materials panel, the face selection
## filters, "Apply to Selected Faces" and the UV controls all worked on the
## preview and stopped at the bake, with nothing said about it.


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _palette_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	return mat


func test_a_fresh_level_bakes_the_materials_its_faces_carry() -> void:
	var root := _fresh_root()
	assert_true(
		root.bake_use_face_materials,
		"a mapper who textures a level and presses Bake gets what they textured"
	)


func test_the_dock_check_box_agrees_with_the_level_it_mirrors() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/manage_tab_builder.gd")
	assert_true(
		source.contains('_make_check("Use Face Materials", true)'),
		"an unticked box in front of a level that has it on is the same defect the other way"
	)


func test_a_level_with_structural_subtractors_still_falls_back_to_csg() -> void:
	var root := _fresh_root()
	# Independent face triangulation has no boolean subtraction stage, so the
	# fallback is what keeps a cut. Defaulting the flag on must not cost that.
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_bake_system.gd"
	)
	assert_true(
		source.contains("not _has_effective_structural_subtractors()"),
		"the face-material path is still gated on the level having no effective cutters"
	)
	assert_true(
		source.contains("Face-material bake switched to CSG to preserve active cuts"),
		"and the fallback still says so"
	)


func test_a_bake_that_drops_face_materials_says_so() -> void:
	var root := _fresh_root()
	root.bake_use_face_materials = false
	root.set_materials([_palette_material(Color.RED), _palette_material(Color.BLUE)])
	var brush = (
		root
		. create_brush_from_info(
			{
				"shape": LevelRoot.BrushShape.BOX,
				"size": Vector3(64, 64, 64),
				"center": Vector3.ZERO,
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": "face_material_brush",
			}
		)
	)
	brush.faces[0].material_idx = 1

	var messages: Array = []
	root.user_message.connect(func(text: String, _severity: int) -> void: messages.append(text))
	await root.bake(true, false, 0)

	var said := false
	for text in messages:
		if str(text).contains("Per-face materials"):
			said = true
	assert_true(
		said, "turning the flag off is a choice; losing the materials without being told is not"
	)


func test_a_bake_with_no_face_materials_says_nothing_about_them() -> void:
	var root := _fresh_root()
	root.bake_use_face_materials = false
	(
		root
		. create_brush_from_info(
			{
				"shape": LevelRoot.BrushShape.BOX,
				"size": Vector3(64, 64, 64),
				"center": Vector3.ZERO,
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": "plain_brush",
			}
		)
	)

	var messages: Array = []
	root.user_message.connect(func(text: String, _severity: int) -> void: messages.append(text))
	await root.bake(true, false, 0)

	var said := false
	for text in messages:
		if str(text).contains("Per-face materials"):
			said = true
	assert_false(said, "a level with nothing painted on it has nothing to warn about")
