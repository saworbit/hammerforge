extends GutTest

## Terrain settings that take a number and never looked at it. #320 fixed this
## shape for displacement paint and elevation; the terrain layer has the same two
## knobs and did not get the same treatment, and the region streaming settings
## enforce their lower bounds and not their upper ones.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _active_layer():
	root.add_paint_layer()
	return root.paint_layers.get_active_layer()


# ===========================================================================
# The heightmap scale and the layer height (#350)
# ===========================================================================


func test_a_heightmap_scale_that_is_not_a_number_is_refused():
	var layer = _active_layer()
	root.set_heightmap_scale(4.0)
	for value in [NAN, INF, -INF]:
		root.set_heightmap_scale(value)
		assert_almost_eq(layer.height_scale, 4.0, 0.0001, "%s must not stick" % value)


func test_a_heightmap_scale_of_zero_does_not_flatten_the_sculpt():
	var layer = _active_layer()
	root.set_heightmap_scale(0.0)
	assert_gt(layer.height_scale, 0.0, "a multiplier of nothing reads as the terrain gone")


func test_an_ordinary_heightmap_scale_still_goes_through():
	var layer = _active_layer()
	root.set_heightmap_scale(2.5)
	assert_almost_eq(layer.height_scale, 2.5, 0.0001)


func test_a_negative_heightmap_scale_still_turns_the_sculpt_over():
	# The floor is on the magnitude. Inverting a terrain is a thing to want, the
	# same way a negative UV scale mirrors a texture.
	var layer = _active_layer()
	root.set_heightmap_scale(-8.0)
	assert_almost_eq(layer.height_scale, -8.0, 0.0001)
	root.set_heightmap_scale(-0.0000001)
	assert_lt(layer.height_scale, 0.0, "still upside down")
	assert_lt(absf(layer.height_scale), 1.0, "and still floored")


func test_a_layer_height_that_is_not_a_number_is_refused():
	var layer = _active_layer()
	root.set_layer_y(32.0)
	for value in [NAN, INF, -INF]:
		root.set_layer_y(value)
		assert_almost_eq(layer.grid.layer_y, 32.0, 0.0001, "%s must not stick" % value)


func test_a_negative_layer_height_still_goes_through():
	var layer = _active_layer()
	root.set_layer_y(-64.0)
	assert_almost_eq(layer.grid.layer_y, -64.0, 0.0001, "below the origin is a place")


# ===========================================================================
# Region streaming (#352)
# ===========================================================================


func _region_settings() -> Dictionary:
	return root.get_region_settings()


func test_a_region_size_is_clamped_at_both_ends():
	root.set_region_size_cells(0)
	assert_gte(int(_region_settings()["region_size_cells"]), 64, "still a floor")
	root.set_region_size_cells(1000000)
	var size := int(_region_settings()["region_size_cells"])
	assert_lte(size, 4096, "a region has to stay smaller than the world")
	assert_gte(size, 64)


func test_a_region_size_in_range_is_kept():
	root.set_region_size_cells(256)
	assert_eq(int(_region_settings()["region_size_cells"]), 256)


func test_a_memory_budget_is_clamped_at_both_ends():
	root.set_region_memory_budget_mb(1)
	assert_gte(int(_region_settings()["memory_budget_mb"]), 32)
	root.set_region_memory_budget_mb(100000)
	assert_lte(int(_region_settings()["memory_budget_mb"]), 8192, "more than a machine can hold")


func test_the_streaming_radius_is_still_clamped():
	root.set_region_streaming_radius(100000)
	assert_lte(int(_region_settings()["streaming_radius"]), 8)


func test_a_region_sidecar_cannot_smuggle_a_size_past_the_clamp():
	# An index written by an older version or by hand is the caller these are for.
	root.paint_system.load_region_index(
		{"region_size_cells": 1000000, "streaming_radius": 99, "memory_budget_mb": 100000}
	)
	var settings := _region_settings()
	assert_lte(int(settings["region_size_cells"]), 4096)
	assert_lte(int(settings["streaming_radius"]), 8)
	assert_lte(int(settings["memory_budget_mb"]), 8192)
