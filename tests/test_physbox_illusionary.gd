extends GutTest

## Brush entities for a physics prop and for geometry with no collision (#1892).
## Every brush entity baked a StaticBody3D whatever its class, so a crate to push
## was rebuilt by hand as a RigidBody3D after each bake, and a curtain snagged
## the player.

const PlaytestFPS = preload("res://addons/hammerforge/playtest_fps.gd")

const PHYSBOX := "func_physbox"
const ILLUSIONARY := "func_illusionary"

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _box(center: Vector3, size := Vector3(1, 1, 1)) -> DraftBrush:
	var info := {"shape": LevelRoot.BrushShape.BOX, "size": size, "center": center}
	return root.create_brush_from_info(info) as DraftBrush


func _tied(entity_class: String, centers: Array, entity_name := "") -> Array:
	var brushes: Array = []
	var ids: Array = []
	for center in centers:
		var brush := _box(center)
		brushes.append(brush)
		ids.append(str(brush.brush_id))
	root.tie_brushes_to_entity(ids, entity_class, entity_name)
	return brushes


func _bake() -> void:
	assert_true(await root.bake(true, false, 0), "the level bakes")
	assert_not_null(root.baked_container)


func _baked(type_name: String) -> Array:
	return root.baked_container.find_children("*", type_name, true, false)


func _of_class(nodes: Array, entity_class: String) -> Array:
	return nodes.filter(
		func(node): return str(node.get_meta(HFBrushEntity.CLASS_META, "")) == entity_class
	)


func test_a_physbox_bakes_to_one_rigid_body_with_its_mesh_and_one_convex_shape():
	_box(Vector3(0, -0.2, 0), Vector3(8, 0.4, 8))
	var crate: Array = _tied(PHYSBOX, [Vector3(0, 0.5, 0)])
	crate[0].set_meta(HFBrushEntity.DATA_META, {"mass": 25.0, "start_asleep": true})
	await _bake()
	var bodies := _of_class(_baked("RigidBody3D"), PHYSBOX)
	assert_eq(bodies.size(), 1, "one rigid body")
	var body: RigidBody3D = bodies[0]
	assert_almost_eq(body.mass, 25.0, 0.0001, "with the Mass set")
	assert_true(body.sleeping, "asleep, as Start Asleep says")
	var meshes := body.find_children("*", "MeshInstance3D", false, false)
	var shapes := body.find_children("*", "CollisionShape3D", false, false)
	assert_eq(meshes.size(), 1, "its mesh under it")
	assert_eq(shapes.size(), 1, "and one shape")
	assert_true(shapes[0].shape is ConvexPolygonShape3D, "convex")
	assert_eq(
		(meshes[0] as MeshInstance3D).gi_mode, GeometryInstance3D.GI_MODE_DYNAMIC, "dynamic for GI"
	)
	assert_almost_eq(
		(meshes[0] as MeshInstance3D).global_position, Vector3(0, 0.5, 0), Vector3.ONE * 0.001
	)
	assert_eq(_of_class(_baked("StaticBody3D"), PHYSBOX), [], "and no static body for it anywhere")


func test_two_brushes_tied_under_one_name_bake_to_one_body():
	_tied(PHYSBOX, [Vector3(0, 0.5, 0), Vector3(0, 1.5, 0)], "stack")
	await _bake()
	var bodies := _of_class(_baked("RigidBody3D"), PHYSBOX)
	assert_eq(bodies.size(), 1, "one body")
	assert_eq(bodies[0].find_children("*", "CollisionShape3D", false, false).size(), 2)
	assert_eq(str(bodies[0].name), "stack", "named as the entity")


func test_an_illusionary_brush_bakes_a_mesh_and_no_collision_and_a_ray_passes():
	_box(Vector3(0, -0.2, 0), Vector3(8, 0.4, 8))
	_tied(ILLUSIONARY, [Vector3(0, 1, 0)])
	await _bake()
	var meshes := _of_class(_baked("MeshInstance3D"), ILLUSIONARY)
	assert_eq(meshes.size(), 1, "a mesh")
	for type_name in ["StaticBody3D", "RigidBody3D", "Area3D"]:
		for body in _baked(type_name):
			for shape in body.find_children("*", "CollisionShape3D", false, false):
				var at: Vector3 = (shape as Node3D).global_position
				assert_false(
					at.distance_to(Vector3(0, 1, 0)) < 0.01, "no collision where the curtain is"
				)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 5), Vector3(0, 1, -5))
	assert_true(space.intersect_ray(query).is_empty(), "a ray through it hits nothing")
	query = PhysicsRayQueryParameters3D.create(Vector3(0, 3, 0), Vector3(0, -3, 0))
	var hit := space.intersect_ray(query)
	assert_false(hit.is_empty(), "and one down through it hits the floor")
	if not hit.is_empty():
		assert_almost_eq(float(hit["position"].y), 0.0, 0.01)


func test_neither_class_is_in_the_navmesh_source_geometry():
	_box(Vector3(0, -0.2, 0), Vector3(8, 0.4, 8))
	_tied(PHYSBOX, [Vector3(20, 0.5, 0)])
	_tied(ILLUSIONARY, [Vector3(-20, 0.5, 0)])
	await _bake()
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, root.baked_container)
	var vertices := source.get_vertices()
	assert_gt(vertices.size(), 0, "the floor is parsed")
	for i in range(0, vertices.size(), 3):
		assert_lt(absf(vertices[i]), 4.01, "nothing out at the crate or the curtain")


func test_walking_into_a_physbox_moves_it():
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 0.4, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	parent.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.2, 0)
	var crate := RigidBody3D.new()
	var crate_shape := CollisionShape3D.new()
	var crate_box := BoxShape3D.new()
	crate_box.size = Vector3.ONE
	crate_shape.shape = crate_box
	crate.add_child(crate_shape)
	crate.mass = 10.0
	parent.add_child(crate)
	crate.global_position = Vector3(0, 0.5, 2)
	var player := CharacterBody3D.new()
	var capsule := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.height = 1.6
	capsule_shape.radius = 0.35
	capsule.shape = capsule_shape
	player.add_child(capsule)
	parent.add_child(player)
	player.global_position = Vector3(0, 0.81, 0)
	var start := crate.global_position
	for _i in 90:
		var walking := Vector3(0, -0.5, 3.0)
		player.velocity = walking
		player.move_and_slide()
		PlaytestFPS.push_bodies(player, walking, 1.0 / 60.0)
		await get_tree().physics_frame
	assert_gt(crate.global_position.z - start.z, 0.25, "the crate moved the way the player walked")


func test_a_map_round_trip_keeps_both_classes_and_their_properties():
	var crate: Array = _tied(PHYSBOX, [Vector3(0, 0.5, 0)], "crate")
	crate[0].set_meta(HFBrushEntity.DATA_META, {"mass": 25.0})
	_tied(ILLUSIONARY, [Vector3(4, 0.5, 0)], "curtain")
	var parsed: Dictionary = MapIO.parse_map_text(MapIO.export_map_from_level(root))
	var classes := {}
	var mass := ""
	for info in parsed["brushes"]:
		var entity_class := str(info.get("brush_entity_class", ""))
		classes[entity_class] = true
		if entity_class == PHYSBOX:
			var data: Dictionary = info.get(HFBrushEntity.DATA_META, {})
			mass = str(data.get("mass", ""))
	assert_true(classes.has(PHYSBOX), "func_physbox comes back")
	assert_true(classes.has(ILLUSIONARY), "and func_illusionary")
	assert_eq(float(mass), 25.0, "with its Mass")
