extends GutTest

## The per-face bake path chunks (#656).
##
## `_bake_impl()` picked between two geometry paths and only the CSG one had a
## chunked branch. `bake_use_face_materials` defaults to true, so on every
## default level the bake took the branch that had never heard of
## `bake_chunk_size` -- while the dock offered a Chunk Size spin, the health
## badge said "Consider Chunking", and `bake_dry_run()` reported a chunk count
## the bake did not produce.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _pillars(root: LevelRoot, count: int, spacing: float) -> void:
	for i in count:
		(
			root
			. create_brush_from_info(
				{
					"shape": root.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"transform": Transform3D(Basis.IDENTITY, Vector3(i * spacing, 0, 0)),
					"operation": CSGShape3D.OPERATION_UNION,
				}
			)
		)


func _chunk_nodes(baked: Node) -> int:
	if baked == null:
		return 0
	var found := 0
	for child in baked.get_children():
		if str(child.name).begins_with("BakedChunk_"):
			found += 1
	return found


# ===========================================================================


func test_the_default_path_produces_the_chunks_the_dry_run_promises():
	var root := _fresh_root()
	_pillars(root, 6, 8.0)
	root.bake_chunk_size = 4.0
	assert_true(root.bake_use_face_materials, "the default path is the one under test")
	var promised: int = int(root.bake_dry_run()["chunk_count"])
	assert_gt(promised, 1, "the level is spread out enough to chunk")

	assert_true(await root.bake(), "the bake succeeds")
	assert_eq(
		_chunk_nodes(root.baked_container),
		promised,
		"and makes the number of chunks the dry run said it would"
	)


func test_chunking_off_bakes_one_mesh_with_no_chunk_wrapper():
	# A single chunk must return exactly what the unchunked path returned, with
	# the same node shape, so nothing downstream has to learn about chunking.
	var root := _fresh_root()
	_pillars(root, 4, 8.0)
	root.bake_chunk_size = 0.0

	assert_true(await root.bake(), "the bake succeeds")
	assert_not_null(root.baked_container, "there is geometry")
	assert_eq(_chunk_nodes(root.baked_container), 0, "and no BakedChunk_ wrapper for one mesh")


func test_a_level_that_fits_in_one_chunk_is_not_wrapped_either():
	var root := _fresh_root()
	_pillars(root, 3, 0.5)
	root.bake_chunk_size = 64.0

	assert_true(await root.bake(), "the bake succeeds")
	assert_eq(_chunk_nodes(root.baked_container), 0, "everything landed in one chunk")


func test_chunk_size_starts_off_rather_than_at_a_stale_distance():
	# 32.0 was a pre-#625 world-space number: four rooms wide on a project whose
	# shipped examples are 8 unit rooms, so a greybox level fell in one chunk and
	# the setting did nothing. `get_recommended_chunk_size()` returns 0.0 for
	# anything under 30 brushes, so off agrees with the recommendation.
	var root := _fresh_root()
	assert_eq(root.bake_chunk_size, 0.0, "a fresh level does not chunk")
	_pillars(root, 4, 4.0)
	assert_eq(root.get_recommended_chunk_size(), 0.0, "and is not recommended to")
