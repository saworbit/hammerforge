extends GutTest

## What the baked collision says about what you are standing on (#707).
##
## Texturing a level is how a shipped game knows what is underfoot: the footstep
## sound, the impact decal, the bullet spark. All of it is a lookup against the
## surface a ray just hit, and none of it reached the baked collision, which was
## one `StaticBody3D` with no metadata at all. The baked *mesh* kept the
## materials as separate surfaces the whole time; the collision kept nothing.

const BakerType = preload("res://addons/hammerforge/baker.gd")
const HFSurfaceType = preload("res://addons/hammerforge/hf_surface.gd")


func _named(label: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	return mat


## A quad at a known offset, so which surface a triangle came from is readable
## off its coordinates.
func _quad_arrays(offset: Vector3) -> Array:
	var verts := PackedVector3Array(
		[
			offset + Vector3(0, 0, 0),
			offset + Vector3(1, 0, 0),
			offset + Vector3(1, 0, 1),
			offset + Vector3(0, 0, 0),
			offset + Vector3(1, 0, 1),
			offset + Vector3(0, 0, 1),
		]
	)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays


## Three quads, three materials, one surface each.
func _three_surface_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var labels := ["metal", "wood", "stone"]
	for i in 3:
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _quad_arrays(Vector3(i * 100.0, 0, 0))
		)
		mesh.surface_set_material(i, _named(labels[i]))
	return mesh


func _body_for(mesh: ArrayMesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	add_child_autoqfree(body)
	BakerType._add_per_surface_trimesh(body, mesh)
	return body


func _shapes_on(body: StaticBody3D) -> Array:
	var out: Array = []
	for child in body.get_children():
		if child is CollisionShape3D:
			out.append(child)
	return out


# ===========================================================================
# Why it is the shape index and not the face index
# ===========================================================================


func test_a_trimesh_hit_reports_no_face_index_under_this_projects_physics():
	# The documented answer to "which triangle did I hit" is `face_index`, and it
	# is -1 here from both the space state and RayCast3D, because this project
	# runs Jolt. The whole design rests on that, so it is pinned: if a Godot
	# release starts populating it, this fails and the better answer becomes
	# available rather than going unnoticed for a year.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad_arrays(Vector3(-0.5, 0, -0.5)))
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child_autoqfree(body)
	assert_eq(col.shape.get_class(), "ConcavePolygonShape3D", "it really is a concave shape")
	await get_tree().physics_frame
	await get_tree().physics_frame

	var query := PhysicsRayQueryParameters3D.new()
	query.from = Vector3(0, 2, 0)
	query.to = Vector3(0, -2, 0)
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "the ray hit it")
	assert_eq(int(hit.get("face_index", -1)), -1, "no face index, so the shape is what is left")
	assert_eq(int(hit.get("shape", -1)), 0, "and the shape index is reported")


# ===========================================================================
# What the bake builds
# ===========================================================================


func test_there_is_one_collision_shape_for_every_surface():
	# The mapping is 1:1 by construction rather than by an ordering assumption:
	# shape N is built from surface N.
	var body := _body_for(_three_surface_mesh())
	var shapes := _shapes_on(body)
	assert_eq(shapes.size(), 3, "one shape per surface")
	for shape in shapes:
		assert_eq((shape as CollisionShape3D).shape.get_faces().size() / 3, 2, "two per quad")


func test_a_single_surface_level_still_gets_one_shape():
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad_arrays(Vector3.ZERO))
	mesh.surface_set_material(0, _named("metal"))
	var body := _body_for(mesh)
	assert_eq(_shapes_on(body).size(), 1)
	assert_eq(HFSurfaceType.material_at(body, 0), "metal")


func test_the_body_carries_a_name_for_every_shape():
	var body := _body_for(_three_surface_mesh())
	assert_eq(Array(HFSurfaceType.names_on(body)), ["metal", "wood", "stone"], "in shape order")


func test_a_material_with_no_name_is_still_labelled():
	# A material made in the editor session has no resource_name and no path. It
	# still occupies a surface, and a nameless row in a footstep table is easier
	# to act on than a missing one.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad_arrays(Vector3.ZERO))
	mesh.surface_set_material(0, StandardMaterial3D.new())
	assert_eq(Array(HFSurfaceType.names_on(_body_for(mesh))), ["Material"])


func test_a_surface_with_no_material_says_so_rather_than_being_skipped():
	# Skipping it would slide every later name by one, which is the failure that
	# reports the wrong material rather than none.
	var mesh := ArrayMesh.new()
	for i in 2:
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _quad_arrays(Vector3(i * 100.0, 0, 0))
		)
	mesh.surface_set_material(1, _named("wood"))
	var body := _body_for(mesh)
	assert_eq(Array(HFSurfaceType.names_on(body)), ["<none>", "wood"])
	assert_eq(HFSurfaceType.material_at(body, 1), "wood", "the second surface is still the second")


# ===========================================================================
# The lookup a game does
# ===========================================================================


func test_a_hit_resolves_to_the_material_that_was_hit():
	var body := _body_for(_three_surface_mesh())
	assert_eq(HFSurfaceType.material_at(body, 0), "metal")
	assert_eq(HFSurfaceType.material_at(body, 1), "wood")
	assert_eq(HFSurfaceType.material_at(body, 2), "stone")


func test_a_ray_query_result_resolves_in_one_call():
	var body := _body_for(_three_surface_mesh())
	assert_eq(
		HFSurfaceType.material_from_hit({"collider": body, "shape": 1}),
		"wood",
		"the shape of the lookup a game writes"
	)
	assert_eq(HFSurfaceType.material_from_hit({}), HFSurfaceType.UNKNOWN, "a ray that missed")


func test_a_shape_index_past_the_end_answers_unknown_rather_than_the_last_one():
	var body := _body_for(_three_surface_mesh())
	assert_eq(HFSurfaceType.material_at(body, 3), HFSurfaceType.UNKNOWN)
	assert_eq(HFSurfaceType.material_at(body, 999), HFSurfaceType.UNKNOWN)


func test_a_missing_hit_answers_unknown():
	var body := _body_for(_three_surface_mesh())
	assert_eq(HFSurfaceType.material_at(body, -1), HFSurfaceType.UNKNOWN)


func test_a_body_the_bake_never_touched_answers_unknown_rather_than_erroring():
	# A per-brush collision mode leaves no names, because there a shape is a brush
	# and a brush has six faces with six materials. Answering UNKNOWN is the point:
	# naming one of the six would be worse than saying nothing.
	var plain := StaticBody3D.new()
	add_child_autoqfree(plain)
	assert_eq(HFSurfaceType.material_at(plain, 0), HFSurfaceType.UNKNOWN)
	assert_eq(Array(HFSurfaceType.names_on(plain)), [])


func test_a_null_body_answers_unknown():
	assert_eq(HFSurfaceType.material_at(null, 0), HFSurfaceType.UNKNOWN)
	assert_eq(Array(HFSurfaceType.names_on(null)), [])


func test_a_ray_touching_nothing_answers_unknown():
	var ray := RayCast3D.new()
	add_child_autoqfree(ray)
	assert_eq(HFSurfaceType.material_under(ray), HFSurfaceType.UNKNOWN)
	assert_eq(HFSurfaceType.material_under(null), HFSurfaceType.UNKNOWN)


# ===========================================================================
# Whichever bake path ran (#1462)
# ===========================================================================


## Three floor slabs textured metal, wood and stone, with a drain cut through the
## stone one away from where the rays land. The cut is what sends the bake down
## the CSG path; without it the level takes the face-material path.
func _level_with_a_cut(merge_meshes: bool) -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.bake_merge_meshes = merge_meshes
	add_child_autoqfree(root)
	root.set_materials([_named("metal"), _named("wood"), _named("stone")])
	for i in 3:
		var slab = (
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(4, 0.4, 4),
					"center": Vector3(i * 5.0, -0.2, 0),
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": "slab_%d" % i,
				}
			)
		)
		for face in slab.faces:
			face.material_idx = i
		slab.rebuild_preview()
	(
		root
		. create_brush_from_info(
			{
				"shape": LevelRoot.BrushShape.BOX,
				"size": Vector3(0.5, 2, 0.5),
				"center": Vector3(11.0, -0.2, 1.0),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"brush_id": "drain",
			}
		)
	)
	return root


## What a ray dropped onto each slab names, hitting only the baked body.
func _names_under_each_slab(root: LevelRoot, body: StaticBody3D) -> Array:
	# The live brushes keep their own picking collision, which a ray would find
	# first. Only the baked body is the thing a shipped game has.
	var exclude: Array[RID] = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		if node != body:
			exclude.append((node as CollisionObject3D).get_rid())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := body.get_world_3d().direct_space_state
	var answers: Array = []
	for i in 3:
		var query := PhysicsRayQueryParameters3D.new()
		query.from = Vector3(i * 5.0, 2, 0)
		query.to = Vector3(i * 5.0, -2, 0)
		query.exclude = exclude
		answers.append(HFSurfaceType.material_from_hit(space.intersect_ray(query)))
	return answers


func _assert_a_cut_level_names_its_floors(merge_meshes: bool) -> void:
	var root := _level_with_a_cut(merge_meshes)
	await root.bake(true, false, 0)
	assert_not_null(root.baked_container, "the cut has to bake at all")
	if root.baked_container == null:
		return
	var body := root.baked_container.get_node_or_null("FloorCollision") as StaticBody3D
	assert_not_null(body, "the cut took the CSG path, whose body is FloorCollision")
	if body == null:
		return
	var names := Array(HFSurfaceType.names_on(body))
	for label in ["metal", "wood", "stone"]:
		assert_has(names, label, "the CSG mesh keeps a surface per material, so it can say")
	assert_eq(
		names.size(), _shapes_on(body).size(), "a name for every shape, and a shape per surface"
	)
	assert_eq(
		await _names_under_each_slab(root, body),
		["metal", "wood", "stone"],
		"a cut in one floor must not cost every floor its footsteps"
	)


func test_a_level_with_a_cut_still_names_the_surface_a_ray_lands_on():
	await _assert_a_cut_level_names_its_floors(false)


func test_a_cut_level_baked_as_one_merged_mesh_names_it_too():
	await _assert_a_cut_level_names_its_floors(true)


func test_a_level_too_thin_to_hull_falls_back_to_a_shape_per_surface():
	# A convex collision mode with no brush solid enough to hull falls back to the
	# triangles. They used to come back as one shape for the level and no names.
	var baker := BakerType.new()
	add_child_autoqfree(baker)
	var groups := {}
	var labels := ["metal", "wood"]
	for i in 2:
		var mat := _named(labels[i])
		var verts: PackedVector3Array = _quad_arrays(Vector3(i * 100.0, 0, 0))[Mesh.ARRAY_VERTEX]
		groups[mat] = {"material": mat, "verts": verts, "tiling": false}
	var too_thin := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK])
	var options := {"collision_mode": 1, "per_brush_verts": [too_thin]}
	var baked: Node3D = baker.build_mesh_from_groups(groups, 1, 1, options)
	assert_not_null(baked)
	if baked == null:
		return
	add_child_autoqfree(baked)
	var body := baked.get_node("FaceCollision") as StaticBody3D
	assert_eq(_shapes_on(body).size(), 2, "one shape per surface")
	assert_eq(Array(HFSurfaceType.names_on(body)), labels, "and a name for each")


func test_the_surface_shapes_keep_the_place_the_mesh_was_baked_at():
	# A CSG mesh comes with a placement, and its triangles have to land there.
	var body := StaticBody3D.new()
	add_child_autoqfree(body)
	var placed := Transform3D(Basis.IDENTITY, Vector3(0, 7, 0))
	BakerType._add_collision(body, _three_surface_mesh(), placed, [], 0, true, 0.0)
	var shapes := _shapes_on(body)
	assert_eq(shapes.size(), 3)
	for shape in shapes:
		assert_eq((shape as CollisionShape3D).transform, placed, "every surface, not only one")


func test_a_second_mesh_on_one_body_names_its_own_shapes():
	# A body can take collision from more than one mesh. Its names follow the
	# shapes already there, and a shape that is not a surface answers unknown
	# rather than pushing every later name onto the wrong shape.
	var body := StaticBody3D.new()
	add_child_autoqfree(body)
	var hull := CollisionShape3D.new()
	hull.shape = BoxShape3D.new()
	body.add_child(hull)
	BakerType._add_per_surface_trimesh(body, _three_surface_mesh())
	var glass := ArrayMesh.new()
	glass.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad_arrays(Vector3(0, 0, 100)))
	glass.surface_set_material(0, _named("glass"))
	BakerType._add_per_surface_trimesh(body, glass)
	assert_eq(_shapes_on(body).size(), 5)
	assert_eq(Array(HFSurfaceType.names_on(body)), ["", "metal", "wood", "stone", "glass"])
	assert_eq(HFSurfaceType.material_at(body, 0), HFSurfaceType.UNKNOWN, "the hull cannot say")
	assert_eq(HFSurfaceType.material_at(body, 4), "glass")
