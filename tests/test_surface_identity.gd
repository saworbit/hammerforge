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
