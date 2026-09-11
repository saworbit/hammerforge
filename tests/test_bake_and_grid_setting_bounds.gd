extends GutTest

## #361 bounded the terrain settings that take a number. The bake and grid
## settings are the same list and were not touched (#373), and the cordon is the
## same shape one type up (#377). The dock SpinBoxes have ranges; the `.hflevel`
## does not, and it is JSON that gets hand-edited and merged.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(64, 64, 64), "brush_id": brush_id})
		as DraftBrush
	)


# ===========================================================================
# The numbers (#373)
# ===========================================================================


func test_no_bake_or_grid_setting_keeps_a_value_that_is_not_a_number():
	var before := {
		"grid_snap": root.grid_snap,
		"grid_plane_size": root.grid_plane_size,
		"rotate_snap_degrees": root.rotate_snap_degrees,
		"bake_chunk_size": root.bake_chunk_size,
		"bake_lightmap_texel_size": root.bake_lightmap_texel_size,
		"bake_navmesh_cell_size": root.bake_navmesh_cell_size,
		"bake_navmesh_cell_height": root.bake_navmesh_cell_height,
		"bake_navmesh_agent_height": root.bake_navmesh_agent_height,
		"bake_navmesh_agent_radius": root.bake_navmesh_agent_radius,
		"bake_connector_stair_height": root.bake_connector_stair_height,
		"bake_convex_simplify": root.bake_convex_simplify,
	}
	for key in before.keys():
		root.set(key, NAN)
		assert_eq(root.get(key), before[key], "%s refused NaN" % key)
		root.set(key, INF)
		assert_true(is_finite(root.get(key)), "%s refused inf" % key)


func test_the_settings_that_must_be_positive_are_floored():
	root.bake_chunk_size = -32.0
	assert_gt(root.bake_chunk_size, 0.0, "a chunk size is a size")
	root.bake_lightmap_texel_size = 0.0
	assert_gt(root.bake_lightmap_texel_size, 0.0, "a texel size is a size")
	root.bake_navmesh_cell_size = 0.0
	assert_gt(root.bake_navmesh_cell_size, 0.0)
	root.bake_navmesh_cell_height = -1.0
	assert_gt(root.bake_navmesh_cell_height, 0.0)
	root.bake_navmesh_agent_radius = -5.0
	assert_gt(root.bake_navmesh_agent_radius, 0.0)
	root.bake_connector_stair_height = 0.0
	assert_gt(root.bake_connector_stair_height, 0.0)
	root.bake_connector_width = -4
	assert_gte(root.bake_connector_width, 1, "a piece count is at least one")
	root.grid_plane_size = 0.0
	assert_gt(root.grid_plane_size, 0.0)


func test_the_settings_with_a_declared_range_are_held_to_it():
	root.bake_convex_simplify = 5.0
	assert_lte(root.bake_convex_simplify, 1.0, "the export_range is enforced on assignment now")
	root.bake_convex_simplify = -1.0
	assert_gte(root.bake_convex_simplify, 0.0)
	root.rotate_snap_degrees = 0.0
	assert_gte(root.rotate_snap_degrees, 1.0, "a zero step makes the rotate buttons a no-op")
	root.rotate_snap_degrees = 100000.0
	assert_lte(root.rotate_snap_degrees, 180.0)


func test_ordinary_values_still_land():
	root.bake_chunk_size = 64.0
	root.bake_convex_simplify = 0.5
	root.rotate_snap_degrees = 45.0
	root.grid_snap = 8.0
	assert_eq(root.bake_chunk_size, 64.0)
	assert_almost_eq(root.bake_convex_simplify, 0.5, 0.001)
	assert_eq(root.rotate_snap_degrees, 45.0)
	assert_eq(root.grid_snap, 8.0)


func test_a_poisoned_settings_block_from_a_file_does_not_land():
	(
		root
		. state_system
		. apply_hflevel_settings(
			{
				"grid_snap": NAN,
				"bake_chunk_size": -1.0,
				"bake_lightmap_texel_size": 0.0,
				"bake_navmesh_cell_size": NAN,
				"bake_convex_simplify": 9.0,
				"bake_connector_width": -4,
			}
		)
	)
	assert_true(is_finite(root.grid_snap), "grid snap is still a snap")
	assert_gt(root.grid_snap, 0.0, "and not silently off")
	assert_gt(root.bake_chunk_size, 0.0)
	assert_gt(root.bake_lightmap_texel_size, 0.0)
	assert_true(is_finite(root.bake_navmesh_cell_size))
	assert_lte(root.bake_convex_simplify, 1.0)
	assert_gte(root.bake_connector_width, 1)


# ===========================================================================
# The cordon (#377)
# ===========================================================================


func test_a_cordon_entered_backwards_is_the_same_region_either_way():
	root.cordon_aabb = AABB(Vector3(128, 128, 128), Vector3(-256, -256, -256))
	assert_eq(root.cordon_aabb.size, Vector3(256, 256, 256), "normalised by abs()")
	assert_eq(root.cordon_aabb.position, Vector3(-128, -128, -128))


func test_a_non_finite_cordon_is_refused():
	var before: AABB = root.cordon_aabb
	root.cordon_aabb = AABB(Vector3.ZERO, Vector3(NAN, NAN, NAN))
	assert_eq(root.cordon_aabb, before, "the cordon that was there is still there")
	root.cordon_aabb = AABB(Vector3(INF, 0, 0), Vector3(256, 256, 256))
	assert_eq(root.cordon_aabb, before)


func test_an_inverted_cordon_no_longer_bakes_an_empty_level():
	_box("b")
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3(128, 128, 128), Vector3(-256, -256, -256))
	assert_true(
		root.cordon_aabb.intersects(AABB(Vector3(-32, -32, -32), Vector3(64, 64, 64))),
		"the box at the origin is inside the cordon"
	)


func test_a_cordon_block_from_a_file_with_the_wrong_contents_is_refused():
	var before: AABB = root.cordon_aabb
	root.state_system.apply_hflevel_settings(
		{"cordon_aabb_pos": [0.0, 0.0, 0.0], "cordon_aabb_size": [NAN, NAN, NAN]}
	)
	assert_eq(root.cordon_aabb, before, "a NaN size did not become the cordon")
