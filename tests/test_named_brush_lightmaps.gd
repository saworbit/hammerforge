extends GutTest

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.bake_lightmap_uv2 = true
	root.bake_generate_lods = true
	add_child_autoqfree(root)


func _brush(id: String, center: Vector3, entity_class: String):
	var brush = root.create_brush_from_info(
		{"brush_id": id, "center": center, "size": Vector3(4, 4, 4)}
	)
	brush.set_meta("brush_entity_class", entity_class)
	brush.set_meta("entity_name", id)
	return brush


func test_real_bake_gives_named_static_brushes_uv2_and_movers_dynamic_gi():
	var wall = _brush("named_wall", Vector3.ZERO, "func_wall")
	_brush("gate", Vector3(8, 0, 0), "func_door")
	var source_mesh: Mesh = wall.mesh_instance.mesh
	assert_true(await root.bake(false, false))
	var baked_wall = root.baked_container.get_node_or_null("Nonstructural/named_wall")
	assert_not_null(baked_wall)
	assert_true(baked_wall.mesh is ArrayMesh)
	var uv2 = baked_wall.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_true(uv2 is PackedVector2Array and uv2.size() > 0)
	assert_eq(baked_wall.gi_mode, GeometryInstance3D.GI_MODE_STATIC)
	assert_eq(wall.mesh_instance.mesh, source_mesh, "The editor mesh stays unchanged")
	assert_null(source_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2])
	var door = root.baked_container.get_node("Nonstructural/gate")
	var meshes := door.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1)
	assert_eq(meshes[0].gi_mode, GeometryInstance3D.GI_MODE_DYNAMIC)


func test_named_dense_mesh_gets_lods_without_changing_the_source():
	var sphere = _brush("round_wall", Vector3.ZERO, "func_wall")
	var mesh := SphereMesh.new()
	mesh.radial_segments = 32
	mesh.rings = 16
	sphere.mesh_instance.mesh = mesh
	assert_true(await root.bake(false, false))
	var baked = root.baked_container.get_node("Nonstructural/round_wall")
	var importer := ImporterMesh.from_mesh(baked.mesh)
	assert_gt(importer.get_surface_lod_count(0), 0)
	assert_eq(sphere.mesh_instance.mesh, mesh)


func test_array_preview_stays_unmodified_and_keeps_its_material():
	var wall = _brush("array_wall", Vector3.ZERO, "func_wall")
	var surface := SurfaceTool.new()
	surface.create_from(wall.mesh_instance.mesh, 0)
	var source := surface.commit()
	var material := StandardMaterial3D.new()
	source.surface_set_material(0, material)
	wall.mesh_instance.mesh = source
	assert_true(await root.bake(false, false))
	var baked = root.baked_container.get_node("Nonstructural/array_wall")
	assert_ne(baked.mesh, source)
	assert_eq(baked.mesh.surface_get_material(0), material)
	assert_null(source.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2])


func test_missing_uv2_warning_names_the_static_mesh_and_skips_movers():
	var container := Node3D.new()
	add_child_autoqfree(container)
	var static_mesh := MeshInstance3D.new()
	static_mesh.name = "missing_uv2"
	static_mesh.mesh = BoxMesh.new()
	container.add_child(static_mesh)
	var mover := MeshInstance3D.new()
	mover.name = "moving_door"
	mover.mesh = BoxMesh.new()
	mover.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	container.add_child(mover)
	HFLog.begin_test_capture(["has no lightmap UV2"])
	root.bake_system._report_missing_lightmap_uv2(container)
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1)
	assert_string_contains(warnings[0], "missing_uv2")
