extends "res://tests/mcp/mcp_dispatcher_case.gd"

## A streamed region erased to empty (#1550): its file goes with its paint, so
## the region streams back in empty, through an undo, a redo, a rebuild of the
## paint and a save and reload alike. What a file holds for a paint layer the
## level no longer has stays on disk, for the undo of that removal to read back.

## Where these tests write their level and region files, a name of their own so
## no other suite's files are in the way.
const STREAM_LEVEL := "user://hf_streamed_region_erase_test.hflevel"
## Cells (40, 40) and (50, 50) lie in region (1, 1) at 32 cells a region.
const CELL := Vector2i(40, 40)
const OTHER_CELL := Vector2i(50, 50)
const REGION := Vector2i(1, 1)


## A paint system that can be told to fail removing a region file, as a file
## another program holds open on Windows cannot be removed.
class FilesThatStay:
	extends "res://addons/hammerforge/systems/hf_paint_system.gd"

	var refuse := true

	func _remove_region_file(region_id: Vector2i, path: String) -> int:
		if refuse:
			return ERR_FILE_CANT_WRITE
		return super(region_id, path)


var _heard: Array = []


func after_each() -> void:
	_clean_stream_files()
	_heard.clear()
	super()


func _clean_stream_files() -> void:
	var dir := ProjectSettings.globalize_path(STREAM_LEVEL.get_basename() + ".hfregions")
	if DirAccess.dir_exists_absolute(dir):
		for sub in DirAccess.get_directories_at(dir):
			DirAccess.remove_absolute(dir.path_join(sub))
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))
		DirAccess.remove_absolute(dir)
	var level_file := ProjectSettings.globalize_path(STREAM_LEVEL)
	for path in [level_file, level_file + ".previous"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Paint that streams in regions of 32 cells, one resident at a time, written
## next to a level of this suite's own. Nothing is painted or loaded yet.
func stream(level: Node, sys = null) -> void:
	if sys == null:
		sys = level.paint_system
	level.hflevel_compress = false
	_clean_stream_files()
	sys.region_streaming_enabled = true
	sys.region_manager.region_size_cells = 32
	sys.region_manager.streaming_radius = 0
	sys._sync_region_manager()
	sys.set_region_base_path(STREAM_LEVEL)
	if not level.user_message.is_connected(_hear):
		level.user_message.connect(_hear)


func _hear(text: String, _level: int) -> void:
	_heard.append(text)


func streamed_level() -> LevelRoot:
	var level := make_level()
	stream(level)
	return level


## Read again each time: a restore builds the layers anew.
func painted(level: Node, at: Vector2i, index := 0) -> bool:
	return level.paint_layers.layers[index].get_cell(at)


func region_file(level: Node, region: Vector2i) -> String:
	return level.paint_system._region_file_path(region)


## The layer ids the region's file holds paint for, in file order.
func layers_in_file(path: String) -> Array:
	var ids: Array = []
	var data := HFLevelIO.load_from_path(path)
	for entry in data.get("layers", []):
		ids.append(str(entry.get("id", "")))
	return ids


func run(command: String, args) -> Dictionary:
	return await call_tool("hf_run_command", {"command": command, "params": args})


## Stream the region out, which writes its paint to its file, then back in, as
## moving the brush away and back does.
func stream_out_and_in(level: Node, at: Vector2i, sys = null) -> void:
	if sys == null:
		sys = level.paint_system
	var region: Vector2i = sys.region_manager.region_id_from_cell(at)
	if sys.region_manager.is_loaded(region):
		assert_true(sys._unload_region(region), "region %s streamed out" % str(region))
	sys._ensure_regions_for_cell(at)


## The cell painted on the first layer, its region written out and streamed back
## in, so its file holds the paint.
func painted_and_streamed(level: Node, at: Vector2i, sys = null) -> void:
	if sys == null:
		sys = level.paint_system
	level.paint_layers.layers[0].set_cell(at, true)
	sys.region_manager.mark_loaded(sys.region_manager.region_id_from_cell(at))
	stream_out_and_in(level, at, sys)
	assert_true(painted(level, at), "the region streamed back in with its paint")


## A second layer, `layer_1`, with OTHER_CELL painted on it and CELL on the
## first, both written to REGION's file, and then the second layer removed with
## REGION streamed out. `{level, before}`, `before` the level as it was before
## the removal, which is what undoing the removal puts back.
func level_with_a_removed_layer() -> Dictionary:
	var level := streamed_level()
	var sys := level.paint_system
	sys.add_paint_layer()
	assert_eq(str(level.paint_layers.layers[1].layer_id), "layer_1")
	level.paint_layers.layers[0].set_cell(CELL, true)
	level.paint_layers.layers[1].set_cell(OTHER_CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys._unload_region(REGION), "both layers written out")
	assert_eq(layers_in_file(region_file(level, REGION)), ["layer_0", "layer_1"])
	var before := level.capture_state()
	sys.remove_active_paint_layer()
	assert_eq(level.paint_layers.layers.size(), 1, "the second layer is gone")
	return {"level": level, "before": before}


# ===========================================================================
# Streaming out and back in
# ===========================================================================


func test_a_region_erased_to_empty_stays_empty_after_it_streams_out_and_back_in():
	var level := streamed_level()
	var sys := level.paint_system
	painted_and_streamed(level, CELL)
	level.paint_layers.layers[0].set_cell(CELL, false)
	assert_true(sys._unload_region(REGION), "the empty region streams out")
	assert_false(FileAccess.file_exists(region_file(level, REGION)), "and takes its file along")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the region streams back in empty")
	assert_eq(_heard, [], "nothing to report")


func test_the_copy_a_write_leaves_beside_the_file_does_not_bring_the_paint_back():
	var level := streamed_level()
	var sys := level.paint_system
	painted_and_streamed(level, CELL)
	var path := region_file(level, REGION)
	assert_eq(DirAccess.copy_absolute(path, path + ".previous"), OK, "a copy a write left")
	level.paint_layers.layers[0].set_cell(CELL, false)
	assert_true(sys._unload_region(REGION))
	assert_false(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".previous"), "the copy goes too")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL))


## The other half of the copy: a file that is only the copy a write cut short
## left is the region's paint, so it streams in with it, rather than streaming
## in empty and losing the copy on its way out.
func test_a_region_whose_file_is_only_the_copy_a_write_left_streams_in_with_its_paint():
	var level := streamed_level()
	var sys := level.paint_system
	level.paint_layers.layers[0].set_cell(CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys._unload_region(REGION))
	var path := region_file(level, REGION)
	assert_eq(DirAccess.rename_absolute(path, path + ".previous"), OK)
	sys._ensure_regions_for_cell(CELL)
	assert_true(painted(level, CELL), "the copy's paint streams in")
	stream_out_and_in(level, CELL)
	assert_true(painted(level, CELL), "and back in again")


## A layer height, a terrain slot or a removed layer rebuilds the paint, which
## dropped every loaded region with no paint left, unwritten.
func test_a_rebuild_of_the_paint_keeps_an_erased_region_loaded_until_it_streams_out():
	var level := streamed_level()
	var sys := level.paint_system
	painted_and_streamed(level, CELL)
	level.paint_layers.layers[0].set_cell(CELL, false)
	sys.regenerate_paint_layers()
	assert_true(sys.region_manager.is_loaded(REGION), "still loaded")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "not read back from its file")
	stream_out_and_in(level, CELL)
	assert_false(painted(level, CELL), "and empty once it has streamed out and in")


# ===========================================================================
# Undo and redo
# ===========================================================================


func test_an_erase_through_the_bridge_undoes_and_redoes_across_streaming():
	var level := streamed_level()
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	stream_out_and_in(level, CELL)
	r = await run("paint_ramp", {"from": [CELL.x, CELL.y], "filled": false})
	assert_true(r.get("ok", false), str(r))
	stream_out_and_in(level, CELL)
	assert_false(painted(level, CELL), "the erase holds once the region has streamed out")
	await call_tool("hf_undo")
	assert_true(painted(level, CELL), "undo puts the paint back")
	stream_out_and_in(level, CELL)
	assert_true(painted(level, CELL), "and the region streams back in with it")
	await call_tool("hf_redo")
	assert_false(painted(level, CELL), "redo erases it again")
	stream_out_and_in(level, CELL)
	assert_false(painted(level, CELL), "and the region streams back in empty")
	assert_eq(_heard, [], "nothing to report")


## Undo and redo with the region loaded all the while: no file was written in
## between, so the redo has no file to put right, and the region it empties has
## to stay loaded or its file streams back in.
func test_redoing_an_erase_keeps_the_region_empty_when_its_file_was_not_written_since():
	var level := streamed_level()
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	stream_out_and_in(level, CELL)
	r = await run("paint_ramp", {"from": [CELL.x, CELL.y], "filled": false})
	assert_true(r.get("ok", false), str(r))
	await call_tool("hf_undo")
	assert_true(painted(level, CELL))
	await call_tool("hf_redo")
	assert_false(painted(level, CELL))
	level.paint_system._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the redo's empty region is not read back from its file")
	stream_out_and_in(level, CELL)
	assert_false(painted(level, CELL))


## An undo of a later step takes the level back to after the erase, which is
## the same region loaded and empty.
func test_undoing_a_later_step_keeps_an_erased_region_empty():
	var level := streamed_level()
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	stream_out_and_in(level, CELL)
	r = await run("paint_ramp", {"from": [CELL.x, CELL.y], "filled": false})
	assert_true(r.get("ok", false), str(r))
	r = await run("paint_ramp", {"from": [OTHER_CELL.x, OTHER_CELL.y]})
	assert_true(r.get("ok", false), str(r))
	await call_tool("hf_undo")
	assert_false(painted(level, OTHER_CELL), "the later paint is undone")
	level.paint_system._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the erase still holds")


# ===========================================================================
# A paint layer the level no longer has
# ===========================================================================


func test_a_region_emptied_after_a_layer_was_removed_keeps_that_layers_paint_on_disk():
	var made := level_with_a_removed_layer()
	var level: LevelRoot = made["level"]
	var sys := level.paint_system
	sys._ensure_regions_for_cell(CELL)
	assert_true(painted(level, CELL))
	level.paint_layers.layers[0].set_cell(CELL, false)
	var path := region_file(level, REGION)
	assert_eq(DirAccess.copy_absolute(path, path + ".previous"), OK, "a copy a write left")
	assert_true(sys._unload_region(REGION))
	assert_eq(layers_in_file(path), ["layer_1"], "the file keeps only the removed layer's paint")
	assert_false(FileAccess.file_exists(path + ".previous"), "and no copy of the old file")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the erased paint stays erased")
	level.restore_state(made["before"])
	sys._ensure_regions_for_cell(OTHER_CELL)
	assert_true(painted(level, OTHER_CELL, 1), "undoing the removal brings that layer's paint back")


func test_a_region_written_again_after_a_layer_was_removed_keeps_that_layers_paint():
	var made := level_with_a_removed_layer()
	var level: LevelRoot = made["level"]
	var sys := level.paint_system
	sys._ensure_regions_for_cell(CELL)
	level.paint_layers.layers[0].set_cell(CELL + Vector2i.RIGHT, true)
	assert_true(sys._unload_region(REGION))
	assert_eq(layers_in_file(region_file(level, REGION)), ["layer_0", "layer_1"])
	sys._ensure_regions_for_cell(CELL)
	assert_true(painted(level, CELL + Vector2i.RIGHT), "the new paint is written")
	level.restore_state(made["before"])
	sys._ensure_regions_for_cell(OTHER_CELL)
	assert_true(painted(level, OTHER_CELL, 1), "undoing the removal brings that layer's paint back")


func test_a_save_keeps_the_paint_of_a_removed_layer_in_a_loaded_region_with_none_of_its_own():
	var level := streamed_level()
	var sys := level.paint_system
	sys.add_paint_layer()
	level.paint_layers.layers[1].set_cell(OTHER_CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys._unload_region(REGION))
	sys.remove_active_paint_layer()
	sys._ensure_regions_for_cell(CELL)
	assert_true(sys.region_manager.is_loaded(REGION))
	assert_true(sys.save_loaded_regions()["ok"])
	assert_eq(layers_in_file(region_file(level, REGION)), ["layer_1"], "the file stays")


# ===========================================================================
# Save and reload
# ===========================================================================


## The save path clamps a region to 64 cells at least, so this level uses 64,
## and cell (1, 1) in region (0, 0), the region a reload streams in first.
func test_an_erased_region_stays_empty_after_the_level_is_saved_and_loaded_again():
	var level := streamed_level()
	var sys := level.paint_system
	sys.set_region_size_cells(64)
	var at := Vector2i(1, 1)
	painted_and_streamed(level, at)
	level.paint_layers.layers[0].set_cell(at, false)
	assert_true(sys._unload_region(Vector2i.ZERO))
	assert_eq(level.save_hflevel(STREAM_LEVEL), OK)
	await _drain_save(level)
	var again := make_level()
	assert_true(again.load_hflevel(STREAM_LEVEL), "the level loads")
	assert_true(again.paint_system.region_streaming_enabled, "streaming")
	assert_true(again.paint_system.region_manager.is_loaded(Vector2i.ZERO), "region (0, 0) is in")
	assert_false(painted(again, at), "and empty")
	stream_out_and_in(again, at)
	assert_false(painted(again, at))


## The save runs on a write thread. Wait for it, the way the file system's own
## tests do.
func _drain_save(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


# ===========================================================================
# A file that cannot be brought up to date
# ===========================================================================


func test_an_erased_region_whose_file_cannot_be_removed_stays_loaded_and_tries_again():
	var level := make_level()
	var sys := FilesThatStay.new(level)
	stream(level, sys)
	painted_and_streamed(level, CELL, sys)
	level.paint_layers.layers[0].set_cell(CELL, false)
	assert_false(sys._unload_region(REGION), "refused: the file still holds the paint")
	assert_eq(_heard.size(), 1, "said once: %s" % str(_heard))
	if _heard.size() == 1:
		assert_string_contains(_heard[0], str(REGION))
	assert_true(sys.region_manager.is_loaded(REGION), "kept loaded")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "so the file is not read back")
	assert_false(sys._unload_region(REGION), "streaming out tries the file again")
	assert_eq(_heard.size(), 1, "without saying it again")
	sys.refuse = false
	stream_out_and_in(level, CELL, sys)
	assert_false(FileAccess.file_exists(region_file(level, REGION)), "once it can, the file goes")
	assert_false(painted(level, CELL))


func test_a_removed_layers_paint_that_cannot_be_written_back_keeps_the_region_loaded():
	var made := level_with_a_removed_layer()
	var level: LevelRoot = made["level"]
	var sys := level.paint_system
	sys._ensure_regions_for_cell(CELL)
	level.paint_layers.layers[0].set_cell(CELL, false)
	# A folder where the write's temporary file goes, so the write cannot start.
	var path := region_file(level, REGION)
	assert_eq(DirAccess.make_dir_absolute(path + ".writing"), OK)
	assert_false(sys._unload_region(REGION), "refused")
	assert_push_error("could not write region")
	assert_true(sys.region_manager.is_loaded(REGION), "kept loaded")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "and the erase holds")
	DirAccess.remove_absolute(path + ".writing")
	stream_out_and_in(level, CELL)
	assert_false(painted(level, CELL))
	assert_eq(layers_in_file(path), ["layer_1"])
