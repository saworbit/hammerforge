extends GutTest

## Every preview draws where the geometry it previews actually is.
##
## The overlay containers hang off `LevelRoot`, and most of what the previews are
## handed is world-space: a brush's own `global_transform`, a plane built from
## world bounds, an intersection measured with `world_aabb()`. Assigning that to a
## child's *local* transform is right only while the root sits at the world origin
## with no rotation, which is the only way anybody had ever tested it.
##
## Move the root a thousand units and the hollow preview drew its walls two
## thousand units out — and the whole point of these overlays is that you agree to
## a destructive edit by looking at one. So the property is checked here directly:
## put the root somewhere awkward, and ask each preview where it drew.

const OFFSET := Vector3(1000.0, -250.0, 640.0)
const TOLERANCE := 96.0

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Somewhere awkward: moved and turned, so a fix that only handles translation
## does not pass.
func _displace_root() -> void:
	root.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), OFFSET)


func _a_brush(at: Vector3, size: Vector3 = Vector3(64, 64, 64), op: int = 0) -> Node3D:
	var brush_id: String = root.brush_system._next_brush_id()
	var made = (
		root
		. brush_system
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"operation": op,
				"brush_id": brush_id,
				"transform": Transform3D(Basis.IDENTITY, at),
			}
		)
	)
	assert_not_null(made, "the fixture needs a brush")
	return made


func _id(brush: Node3D) -> String:
	return str(brush.get_meta("brush_id"))


## Where a preview mesh instance is actually drawing, in world space.
func _drawn_centre(mesh_instance: MeshInstance3D) -> Vector3:
	assert_not_null(mesh_instance, "there is a mesh instance to measure")
	assert_not_null(mesh_instance.mesh, "and it has something in it")
	return mesh_instance.global_transform * mesh_instance.mesh.get_aabb().get_center()


func _assert_drawn_at(mesh_instance: MeshInstance3D, expected: Vector3, context: String) -> void:
	var drawn := _drawn_centre(mesh_instance)
	assert_lt(
		drawn.distance_to(expected),
		TOLERANCE,
		"%s: drew at %s, but the geometry is at %s" % [context, drawn, expected]
	)


# ===========================================================================
# With the root where it has always been
# ===========================================================================


func test_hollow_draws_on_the_brush_with_the_root_at_the_origin():
	var brush := _a_brush(Vector3(128, 0, 0))

	root.hollow_preview.show_preview(_id(brush), 4.0)

	_assert_drawn_at(root.hollow_preview._mesh_pool[0], brush.global_position, "hollow")


# ===========================================================================
# With the root moved and turned
# ===========================================================================


func test_hollow_draws_on_the_brush_under_a_displaced_root():
	_displace_root()
	var brush := _a_brush(OFFSET)

	root.hollow_preview.show_preview(_id(brush), 4.0)

	assert_eq(root.hollow_preview._active_count, 6, "a box hollows into six walls")
	for index in root.hollow_preview._active_count:
		_assert_drawn_at(
			root.hollow_preview._mesh_pool[index], brush.global_position, "hollow wall %d" % index
		)


func test_carve_draws_on_the_target_under_a_displaced_root():
	_displace_root()
	var target := _a_brush(OFFSET, Vector3(128, 128, 128))
	var cutter := _a_brush(OFFSET + Vector3(32, 0, 0), Vector3(32, 32, 32))

	root.carve_preview.show_preview(_id(cutter))

	assert_gt(root.carve_preview._active_count, 0, "the carve has pieces to show")
	for index in root.carve_preview._active_count:
		_assert_drawn_at(
			root.carve_preview._mesh_pool[index], target.global_position, "carve piece %d" % index
		)


func test_clip_draws_its_halves_and_its_plane_under_a_displaced_root():
	_displace_root()
	var brush := _a_brush(OFFSET, Vector3(128, 128, 128))

	root.clip_preview.show_preview(_id(brush), 0, brush.global_position.x)

	_assert_drawn_at(root.clip_preview._piece_a_mesh, brush.global_position, "clip front")
	_assert_drawn_at(root.clip_preview._piece_b_mesh, brush.global_position, "clip back")
	# The plane is the thing the user is aiming; drawing it somewhere else is the
	# worst of the three, because it is what the cut is agreed to.
	_assert_drawn_at(root.clip_preview._plane_mesh, brush.global_position, "clip plane")


func test_subtract_draws_the_cut_volume_under_a_displaced_root():
	_displace_root()
	var solid := _a_brush(OFFSET, Vector3(128, 128, 128))
	_a_brush(OFFSET + Vector3(32, 0, 0), Vector3(64, 64, 64), CSGShape3D.OPERATION_SUBTRACTION)

	root.subtract_preview.set_enabled(true)
	root.subtract_preview._rebuild()

	assert_gt(root.subtract_preview._active_count, 0, "the overlap has a volume to show")
	_assert_drawn_at(root.subtract_preview._mesh_pool[0], solid.global_position, "subtract volume")


func test_the_structure_ghost_draws_where_it_is_placed_under_a_displaced_root():
	_displace_root()
	var where := Transform3D(Basis.IDENTITY, OFFSET)

	root.preview_structure("arch", HFGeneratorSystem.default_settings("arch"), where)

	_assert_drawn_at(root.structure_preview._mesh_instance, OFFSET, "structure ghost")


func test_the_array_ghost_draws_on_its_copies_under_a_displaced_root():
	_displace_root()
	var brush := _a_brush(OFFSET)
	var placements := HFDuplicator.linear_placements(1, Vector3(128, 0, 0))

	root.preview_array([_id(brush)], placements)

	_assert_drawn_at(
		root.array_preview._mesh_instance,
		placements[0].applied_to(brush.global_transform).origin,
		"array ghost"
	)
