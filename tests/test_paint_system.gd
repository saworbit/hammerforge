extends GutTest
## Focused HFPaintSystem coverage for the core greybox loop.

const HFPaintSystem = preload("res://addons/hammerforge/systems/hf_paint_system.gd")
const HFPaintLayerManager = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")

var root: Node3D
var sys: HFPaintSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	root.paint_layers = autoqfree(HFPaintLayerManager.new())
	sys = HFPaintSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D
var paint_layers
var paint_tool
var hflevel_compress: bool = false
var generated_region_overlay = null

signal user_message(text: String, level: int)
"""
	s.reload()
	return s


func test_layer_names_empty_without_manager():
	root.paint_layers = null
	assert_eq(sys.get_paint_layer_names(), [])


func test_layer_names_use_display_then_id():
	var floor_layer = root.paint_layers.create_layer(&"floor", 0.0)
	floor_layer.display_name = "Floor"
	var unnamed = root.paint_layers.create_layer(&"layer_1", 1.0)
	unnamed.display_name = ""
	var names: Array = sys.get_paint_layer_names()
	assert_eq(names.size(), 2)
	assert_eq(names[0], "Floor")
	assert_eq(str(names[1]), "layer_1")


func test_paint_stroke_region_pins_release_as_one_unit():
	sys._pin_paint_region(Vector2i(-1, 2))
	sys._pin_paint_region(Vector2i(3, 4))
	assert_true(sys.region_manager.is_pinned(Vector2i(-1, 2)))
	assert_true(sys.region_manager.is_pinned(Vector2i(3, 4)))

	sys.release_paint_region_pins()

	assert_false(sys.region_manager.is_pinned(Vector2i(-1, 2)))
	assert_false(sys.region_manager.is_pinned(Vector2i(3, 4)))


# ===========================================================================
# Region streaming persistence (#172, #173)
# ===========================================================================

var _region_level_path := "user://hf_region_stream_test.hflevel"


func _region_dir() -> String:
	return ProjectSettings.globalize_path("user://hf_region_stream_test.hfregions")


func _clean_region_dir() -> void:
	var dir := _region_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _streaming_system() -> HFPaintSystem:
	root.hflevel_compress = false
	_clean_region_dir()
	sys.region_streaming_enabled = true
	sys.region_manager.region_size_cells = 32
	sys.region_manager.streaming_radius = 0
	sys.region_manager.chunk_size = 32
	sys._sync_region_manager()
	sys.set_region_base_path(_region_level_path)
	return sys


func _paint_cell(cell: Vector2i) -> void:
	_floor_layer().set_cell(cell, true)


func _floor_layer():
	for layer in root.paint_layers.layers:
		if layer and layer.layer_id == &"floor":
			return layer
	return root.paint_layers.create_layer(&"floor", 0.0)


func test_unloading_a_region_writes_its_paint_first():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	sys.region_manager.mark_loaded(Vector2i(0, 0))
	assert_true(sys._unload_region(Vector2i(0, 0)), "An empty destination must accept the write")
	var path: String = sys._region_file_path(Vector2i(0, 0))
	assert_true(FileAccess.file_exists(path), "Streaming out must persist before it drops chunks")
	_clean_region_dir()


func test_unloaded_region_reloads_with_its_paint():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	sys.region_manager.mark_loaded(Vector2i(0, 0))
	sys._unload_region(Vector2i(0, 0))
	var layer = _floor_layer()
	assert_eq(layer.get_chunk_ids().size(), 0, "The region really was streamed out")
	sys._load_region(Vector2i(0, 0))
	assert_gt(layer.get_chunk_ids().size(), 0, "Coming back must restore the paint")
	_clean_region_dir()


func test_streamed_region_preserves_raised_wall_heights():
	_streaming_system()
	var layer = _floor_layer()
	layer.set_cell(Vector2i(2, 3), true)
	layer.set_wall_height(Vector2i(2, 3), 4.5)
	sys.region_manager.mark_loaded(Vector2i.ZERO)
	assert_true(sys._unload_region(Vector2i.ZERO))
	sys._load_region(Vector2i.ZERO)
	assert_almost_eq(layer.get_wall_height(Vector2i(2, 3), 3.0), 4.5, 0.001)
	_clean_region_dir()


func test_unload_keeps_the_region_when_the_write_fails():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	# A regular file where the sidecar directory belongs blocks every write.
	var blocker := FileAccess.open("user://hf_region_stream_test.hfregions", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker = null
	sys.region_manager.mark_loaded(Vector2i(0, 0))
	var layer = _floor_layer()
	var before: int = layer.get_chunk_ids().size()
	assert_false(sys._unload_region(Vector2i(0, 0)), "A failed write must refuse the unload")
	assert_push_error("could not write region")
	assert_eq(layer.get_chunk_ids().size(), before, "The paint stays in memory")
	assert_true(sys.region_manager.is_loaded(Vector2i(0, 0)))
	DirAccess.remove_absolute("user://hf_region_stream_test.hfregions")


func test_unloading_an_empty_region_still_streams_out():
	_streaming_system()
	root.paint_layers.create_layer(&"floor", 0.0)
	sys.region_manager.mark_loaded(Vector2i(5, 5))
	assert_true(sys._unload_region(Vector2i(5, 5)), "Nothing to lose, nothing to block on")
	_clean_region_dir()


func test_save_loaded_regions_reports_a_failed_write():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	sys.region_manager.mark_loaded(Vector2i(0, 0))
	var blocker := FileAccess.open("user://hf_region_stream_test.hfregions", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker = null
	var result: Dictionary = sys.save_loaded_regions()
	assert_false(bool(result.get("ok", true)), "A failed sidecar is not a successful save")
	assert_eq((result.get("failed", []) as Array).size(), 1)
	assert_push_error("could not write region")
	DirAccess.remove_absolute("user://hf_region_stream_test.hfregions")


func test_save_loaded_regions_reports_success():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	sys.region_manager.mark_loaded(Vector2i(0, 0))
	var result: Dictionary = sys.save_loaded_regions()
	assert_true(bool(result.get("ok", false)))
	assert_eq(result.get("failed", []), [])
	_clean_region_dir()


func test_failed_region_write_is_not_recorded_as_having_data():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	var blocker := FileAccess.open("user://hf_region_stream_test.hfregions", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker = null
	assert_ne(sys._save_region_file(Vector2i(0, 0)), OK)
	assert_push_error("could not write region")
	assert_false(
		sys.region_manager.region_index.has(Vector2i(0, 0)),
		"The index must not claim a sidecar that was never written"
	)
	DirAccess.remove_absolute("user://hf_region_stream_test.hfregions")


# ---------------------------------------------------------------------------
# Paint layer rename collisions (#321)
# ---------------------------------------------------------------------------


func _three_layers() -> void:
	root.paint_layers.create_layer(&"layer_0", 0.0).display_name = "Ground"
	root.paint_layers.create_layer(&"layer_1", 1.0).display_name = "Walkway"
	root.paint_layers.create_layer(&"layer_2", 2.0).display_name = ""


func test_rename_refuses_a_name_another_layer_already_has():
	_three_layers()
	assert_false(sys.rename_paint_layer(0, "Walkway"), "Walkway is taken")
	assert_eq(sys.get_paint_layer_names()[0], "Ground", "The layer should keep its name")
	assert_eq(sys.get_paint_layer_names()[1], "Walkway", "The other layer is untouched")


func test_rename_refuses_a_name_a_layer_shows_because_it_has_no_display_name():
	# A layer with no display name shows its id, and that is the row the user
	# reads, so it is the name that has to stay unique.
	_three_layers()
	assert_false(sys.rename_paint_layer(0, "layer_2"), "layer_2 is what row 3 shows")
	assert_eq(sys.get_paint_layer_names()[0], "Ground")


func test_rename_refuses_an_empty_name():
	_three_layers()
	assert_false(sys.rename_paint_layer(0, "   "), "Whitespace is not a name")
	assert_eq(sys.get_paint_layer_names()[0], "Ground")


func test_rename_refuses_an_index_out_of_range():
	_three_layers()
	assert_false(sys.rename_paint_layer(7, "Anything"))
	assert_false(sys.rename_paint_layer(-1, "Anything"))
	assert_eq(sys.get_paint_layer_names().size(), 3, "No layer should have been added")


func test_a_rename_to_a_free_name_still_works():
	_three_layers()
	assert_true(sys.rename_paint_layer(0, "Basement"))
	assert_eq(sys.get_paint_layer_names()[0], "Basement")


func test_renaming_a_layer_to_its_own_name_is_not_a_collision():
	_three_layers()
	assert_true(sys.rename_paint_layer(1, "Walkway"), "A layer does not collide with itself")
	assert_eq(sys.get_paint_layer_names()[1], "Walkway")


func test_a_rename_is_trimmed_before_it_is_compared():
	_three_layers()
	assert_false(sys.rename_paint_layer(0, "  Walkway  "), "Padding does not make it a new name")
	assert_true(sys.rename_paint_layer(0, "  Basement  "))
	assert_eq(sys.get_paint_layer_names()[0], "Basement", "The stored name is trimmed")


# ===========================================================================
# The memory budget only counts what it actually freed (#446)
# ===========================================================================


func _messages_from(fn: Callable) -> Array:
	var heard: Array = []
	var sink := func(text: String, level: int): heard.append(text)
	root.user_message.connect(sink)
	fn.call()
	root.user_message.disconnect(sink)
	return heard


## Five regions of one big chunk each, which is comfortably over a 1 MB budget.
func _budget_fixture() -> void:
	root.hflevel_compress = false
	_clean_region_dir()
	root.paint_layers.chunk_size = 256
	sys.region_streaming_enabled = true
	sys.region_manager.region_size_cells = 256
	sys.region_manager.streaming_radius = 0
	sys.region_manager.chunk_size = 256
	sys._sync_region_manager()
	sys.set_region_base_path(_region_level_path)
	var layer = root.paint_layers.create_layer(&"floor", 0.0)
	layer.chunk_size = 256
	for i in range(5):
		layer.set_cell(Vector2i(i * 256, 0), true)
		sys.region_manager.mark_loaded(Vector2i(i, 0))
	sys.region_memory_budget_mb = 1


func test_eviction_does_not_count_a_region_it_failed_to_free():
	_budget_fixture()
	# A level that has never been saved has nowhere to write a region to, so
	# every unload refuses and nothing can be reclaimed.
	sys.region_manager.region_base_path = ""
	var loaded_before: int = sys.region_manager.loaded_regions.size()
	var said: Array = _messages_from(func(): sys._evict_for_budget(Vector2i(9, 9)))
	assert_eq(
		sys.region_manager.loaded_regions.size(),
		loaded_before,
		"Nothing could be written, so nothing was freed"
	)
	assert_gt(said.size(), 0, "And the mapper is told the budget could not be met")
	var last := str(said[said.size() - 1])
	assert_string_contains(last, "budget")
	assert_string_contains(last, "Save the level")


func test_eviction_frees_regions_when_the_write_works():
	_budget_fixture()
	var loaded_before: int = sys.region_manager.loaded_regions.size()
	sys._evict_for_budget(Vector2i(9, 9))
	assert_lt(
		sys.region_manager.loaded_regions.size(),
		loaded_before,
		"A writable destination lets the budget reclaim memory"
	)
	assert_lte(sys._total_loaded_bytes(), 1048576, "And it keeps going until the budget is met")
	_clean_region_dir()


func test_eviction_is_silent_while_the_budget_is_met():
	_streaming_system()
	_paint_cell(Vector2i(1, 1))
	sys.region_manager.mark_loaded(Vector2i(0, 0))
	sys.region_memory_budget_mb = 64
	var said: Array = _messages_from(func(): sys._evict_for_budget(Vector2i(0, 0)))
	assert_eq(said, [], "Nothing to say while the budget is fine")
	_clean_region_dir()
