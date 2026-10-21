extends GutTest

## Convex collision on a level the CSG path bakes (#1513).
##
## Collision Mode 1 is one convex hull per brush. A level with a cut bakes through
## CSG, whose output is one mesh for the whole level, and that mesh was what got
## hulled: the gaps between brushes filled in and a player walked on air. The
## hulls have to come from the brushes, and a cut has to stay open in them.

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _box(center: Vector3, size: Vector3, subtract: bool = false) -> DraftBrush:
	var op := CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION
	var info := {"shape": LevelRoot.BrushShape.BOX, "size": size, "center": center, "operation": op}
	return root.create_brush_from_info(info) as DraftBrush


## Three slabs 4 wide at x = 0, 5 and 10, with a metre of air between them, and a
## drain cut through the last one at x = 11.
func _three_slabs_and_a_drain() -> void:
	for i in 3:
		_box(Vector3(i * 5.0, -0.2, 0), Vector3(4, 0.4, 4))
	_box(Vector3(11.0, -0.2, 1.0), Vector3(0.5, 2, 0.5), true)


## A wall 8 wide and 4 tall, with a doorway 2 wide and 2.25 tall cut through it.
func _wall_with_a_doorway() -> void:
	_box(Vector3(0, 2, 0), Vector3(8, 4, 0.5))
	_box(Vector3(0, 1, 0), Vector3(2, 2.5, 2), true)


func _bake(collision_mode: int, merge_meshes: bool) -> void:
	root.bake_collision_mode = collision_mode
	root.bake_merge_meshes = merge_meshes
	assert_true(await root.bake(true, false, 0), "the level has to bake")
	assert_not_null(root.baked_container)


## Everything a ray could hit that is not the bake. The live brushes keep their
## own picking collision, and only the baked bodies are what a shipped game has.
func _not_baked() -> Array[RID]:
	var exclude: Array[RID] = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		if root.baked_container == null or not root.baked_container.is_ancestor_of(node):
			exclude.append((node as CollisionObject3D).get_rid())
	return exclude


func _hits(from: Vector3, to: Vector3) -> bool:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = _not_baked()
	return not root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _drops_onto(x: float, z: float = 0.0) -> bool:
	return await _hits(Vector3(x, 2, z), Vector3(x, -2, z))


func _baked_shapes() -> Array:
	var out: Array = []
	for node in root.baked_container.find_children("*", "CollisionShape3D", true, false):
		out.append((node as CollisionShape3D).shape)
	return out


func _assert_slabs_stand_apart() -> void:
	for x in [0.0, 5.0, 10.0]:
		assert_true(await _drops_onto(x), "a ray onto the slab at x = %s lands" % x)
	for x in [2.5, 7.5]:
		assert_false(await _drops_onto(x), "the gap at x = %s is air" % x)
	assert_true(await _drops_onto(10.5, 1.0), "the floor beside the drain is still floor")
	assert_false(await _drops_onto(11.0, 1.0), "and the drain is still a hole")


# ===========================================================================
# Mode 1: one hull per brush on the CSG path
# ===========================================================================


func test_a_cut_level_keeps_the_gaps_between_its_brushes():
	_three_slabs_and_a_drain()
	await _bake(1, false)
	await _assert_slabs_stand_apart()


func test_a_cut_level_baked_as_one_merged_mesh_keeps_them_too():
	_three_slabs_and_a_drain()
	await _bake(1, true)
	await _assert_slabs_stand_apart()


func test_the_hulls_are_convex_shapes():
	# Mode 1 is chosen for convex shapes. A cut must not quietly turn it into
	# triangles when the cut can be carved out of the hulls.
	_three_slabs_and_a_drain()
	await _bake(1, true)
	var shapes := _baked_shapes()
	assert_gt(shapes.size(), 3, "one hull per uncut slab and several for the one the drain cuts")
	for shape in shapes:
		assert_true(shape is ConvexPolygonShape3D, "every shape is a hull")


func test_a_level_baked_through_csg_without_a_cut_keeps_its_gaps():
	# Use Face Materials off sends every bake through CSG, cut or not.
	root.bake_use_face_materials = false
	for i in 3:
		_box(Vector3(i * 5.0, -0.2, 0), Vector3(4, 0.4, 4))
	await _bake(1, true)
	for x in [0.0, 5.0, 10.0]:
		assert_true(await _drops_onto(x), "a ray onto the slab at x = %s lands" % x)
	for x in [2.5, 7.5]:
		assert_false(await _drops_onto(x), "the gap at x = %s is air" % x)


func test_a_doorway_cut_through_a_wall_stays_open():
	_wall_with_a_doorway()
	await _bake(1, true)
	assert_false(
		await _hits(Vector3(0, 1, -2), Vector3(0, 1, 2)), "a ray through the doorway passes"
	)
	assert_true(await _hits(Vector3(3, 1, -2), Vector3(3, 1, 2)), "the wall beside it stops one")
	assert_true(await _hits(Vector3(0, 3, -2), Vector3(0, 3, 2)), "and so does the lintel")


func test_a_body_fits_through_the_doorway():
	_wall_with_a_doorway()
	await _bake(1, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body := BoxShape3D.new()
	body.size = Vector3(1, 1.5, 1)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.exclude = _not_baked()
	var space := root.get_world_3d().direct_space_state
	query.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	assert_eq(space.intersect_shape(query).size(), 0, "nothing in the doorway")
	query.transform = Transform3D(Basis.IDENTITY, Vector3(3, 1, 0))
	assert_gt(space.intersect_shape(query).size(), 0, "the wall beside it is solid")


func test_a_brush_drawn_after_a_cut_is_not_cut_by_it():
	# CSG applies its operands in order, so a cut only carves what came before it.
	# The collision has to agree with the mesh, or there is a hole under a floor
	# the player can see.
	_box(Vector3(0, -0.2, 0), Vector3(4, 0.4, 4))
	_box(Vector3(5, -0.2, 0), Vector3(1, 2, 1), true)
	_box(Vector3(5, -0.2, 0), Vector3(4, 0.4, 4))
	await _bake(1, true)
	assert_true(await _drops_onto(5.0), "the later floor is whole")
	assert_true(await _drops_onto(0.0), "and the earlier one is there")


# ===========================================================================
# The other bakes that go through CSG
# ===========================================================================


func test_a_selection_bake_keeps_the_gaps_too():
	_three_slabs_and_a_drain()
	root.bake_collision_mode = 1
	var brushes: Array = []
	for child in root.draft_brushes_node.get_children():
		brushes.append(child)
	assert_true(await root.bake_selected(brushes), "the selection has to bake")
	await _assert_slabs_stand_apart()


func test_a_chunked_bake_keeps_the_gaps_too():
	_three_slabs_and_a_drain()
	root.bake_chunk_size = 5.0
	await _bake(1, true)
	assert_gt(
		root.baked_container.find_children("BakedChunk_*", "Node3D", false, false).size(),
		1,
		"the level really did bake in chunks"
	)
	await _assert_slabs_stand_apart()


# ===========================================================================
# Mode 2 hulls the same pieces
# ===========================================================================


func test_mode_2_keeps_a_doorway_open_too():
	_wall_with_a_doorway()
	await _bake(2, true)
	assert_false(
		await _hits(Vector3(0, 1, -2), Vector3(0, 1, 2)), "a ray through the doorway passes"
	)
	assert_true(await _hits(Vector3(3, 1, -2), Vector3(3, 1, 2)), "the wall beside it stops one")


func test_mode_2_keeps_the_gaps_between_slabs():
	_three_slabs_and_a_drain()
	await _bake(2, true)
	await _assert_slabs_stand_apart()


# ===========================================================================
# A cut the hulls cannot follow
# ===========================================================================


## A slab with a ring-shaped channel cut through it by a torus, which is not
## convex, so its planes would carve out its hull rather than the ring.
func _slab_with_a_ring_cut() -> void:
	_box(Vector3(0, 0, 0), Vector3(8, 0.4, 8))
	var ring := _box(Vector3(0, 0, 0), Vector3(6, 2, 6), true)
	ring.shape = LevelRoot.BrushShape.TORUS
	ring._update_visuals()


func _assert_the_triangles_stood_in(collision_mode: int) -> void:
	_slab_with_a_ring_cut()
	watch_signals(root)
	await _bake(collision_mode, true)
	var said := false
	for i in get_signal_emit_count(root, "user_message"):
		var text := str(get_signal_parameters(root, "user_message", i)[0])
		said = said or text.contains("triangles instead of hulls: a cut is not convex")
	assert_true(said, "the mapper is told why there are no hulls")
	var shapes := _baked_shapes()
	assert_gt(shapes.size(), 0)
	var collision_points := 0
	for shape in shapes:
		assert_true(shape is ConcavePolygonShape3D, "the cut mesh's own triangles, which are exact")
		if shape is ConcavePolygonShape3D:
			collision_points += (shape as ConcavePolygonShape3D).get_faces().size()
	var mesh_points := 0
	for node in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		mesh_points += (node as MeshInstance3D).mesh.get_faces().size()
	assert_gt(mesh_points, 36, "the ring cut the slab")
	assert_eq(collision_points, mesh_points, "every triangle the mesh has, and only those")
	assert_true(await _drops_onto(0.0), "the middle of the ring is still floor")
	assert_true(await _drops_onto(3.6), "and so is the slab outside it")


func test_a_cut_that_is_not_convex_keeps_the_exact_triangles():
	await _assert_the_triangles_stood_in(1)


func test_mode_2_keeps_them_too_rather_than_partition_hulls():
	await _assert_the_triangles_stood_in(2)


# ===========================================================================
# Mode 0 is the mesh's own triangles, as before
# ===========================================================================


func test_mode_0_is_still_the_cut_mesh():
	_three_slabs_and_a_drain()
	await _bake(0, true)
	for shape in _baked_shapes():
		assert_true(shape is ConcavePolygonShape3D, "mode 0 is triangles")
	await _assert_slabs_stand_apart()
