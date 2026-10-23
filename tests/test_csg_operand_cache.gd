extends GutTest

## A round brush's CSG operand is reused while the brush is unchanged (#1628).
## Built from its own faces since #1613, it cost about 1.8 ms a 128-face sphere
## every bake. Anything the operand is built from changing builds it again.

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _sphere(center: Vector3) -> DraftBrush:
	return root.create_brush_from_info(
		{
			"shape": LevelRoot.BrushShape.SPHERE,
			"size": Vector3(2, 2, 2),
			"center": center,
			"sides": 16
		}
	)


## The operand the last bake used for `brush`: the face material one when Use
## Face Materials is on, else the bare one.
func _operand(brush: DraftBrush) -> Variant:
	var kinds: Dictionary = root.bake_system._operand_cache.get(brush.get_instance_id(), {})
	var held: Array = kinds.get(not root.bake_use_face_materials, [])
	return held[1] if not held.is_empty() else null


func _bake() -> void:
	assert_true(await root.bake(true, false, 0, 0, true), "the CSG bake")


func _baked_vertices() -> int:
	var count := 0
	for mesh in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		var arrays := (mesh as MeshInstance3D).mesh.surface_get_arrays(0)
		count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return count


func test_an_unchanged_sphere_is_built_once():
	var sphere := _sphere(Vector3(0, 1, 0))
	await _bake()
	var first: Variant = _operand(sphere)
	assert_not_null(first, "the operand is kept")
	var vertices := _baked_vertices()
	await _bake()
	assert_same(_operand(sphere), first, "and reused")
	assert_eq(_baked_vertices(), vertices, "to the same result")


func test_moving_it_keeps_the_operand_and_resizing_it_builds_it_again():
	var sphere := _sphere(Vector3(0, 1, 0))
	await _bake()
	var first: Variant = _operand(sphere)
	sphere.global_position = Vector3(5, 1, 0)
	await _bake()
	assert_same(_operand(sphere), first, "a move does not change the operand")
	root.set_brush_transform_by_id(sphere.brush_id, Vector3(3, 3, 3), sphere.global_position)
	await _bake()
	assert_not_same(_operand(sphere), first, "a new size builds it again")


func test_both_kinds_of_bake_reuse_their_own_operand():
	var sphere := _sphere(Vector3(0, 1, 0))
	for use_face_materials in [false, true]:
		root.bake_use_face_materials = use_face_materials
		await _bake()
		var first: Variant = _operand(sphere)
		assert_not_null(first, "face materials %s: kept" % use_face_materials)
		await _bake()
		assert_same(_operand(sphere), first, "face materials %s: reused" % use_face_materials)


func test_a_changed_material_builds_it_again():
	root.bake_use_face_materials = true
	root.add_prototype_materials()
	var sphere := _sphere(Vector3(0, 1, 0))
	for face in sphere.faces:
		face.material_idx = 1
	await _bake()
	var first: Variant = _operand(sphere)
	assert_not_null(first)
	sphere.faces[0].material_idx = 2
	await _bake()
	var second: Variant = _operand(sphere)
	assert_not_same(second, first, "another slot")
	root.material_manager.materials[2] = StandardMaterial3D.new()
	await _bake()
	assert_not_same(_operand(sphere), second, "the same slot holding another material")


func test_a_gone_brush_lets_its_operand_go():
	var sphere := _sphere(Vector3(0, 1, 0))
	var other := _sphere(Vector3(6, 1, 0))
	await _bake()
	var id := sphere.get_instance_id()
	assert_true(root.bake_system._operand_cache.has(id))
	root.delete_brush_by_id(sphere.brush_id)
	await get_tree().process_frame
	await _bake()
	assert_false(root.bake_system._operand_cache.has(id), "forgotten")
	assert_not_null(_operand(other), "the other kept")
