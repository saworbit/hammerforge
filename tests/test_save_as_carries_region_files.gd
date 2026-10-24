extends "res://tests/mcp/mcp_dispatcher_case.gd"

## A level saved under a new name writes its paint regions into the new name's
## region folder. Only the loaded ones were written there, so a region streamed
## out at the time stayed in the old folder alone, and the new level opened with
## no paint in it (#1665). An autosave to a path of its own did the same.

const OLD_LEVEL := "user://hf_save_as_regions_old.hflevel"
const NEW_LEVEL := "user://hf_save_as_regions_new.hflevel"
## Region (0, 0) and region (2, 2) at 64 cells a region: far enough apart that
## only one is loaded at a time.
const NEAR := Vector2i(1, 1)
const FAR := Vector2i(150, 150)


func before_each() -> void:
	super()
	_clean()


func after_each() -> void:
	_clean()
	super()


func _clean() -> void:
	for level_path in [OLD_LEVEL, NEW_LEVEL]:
		var dir := ProjectSettings.globalize_path(level_path.get_basename() + ".hfregions")
		if DirAccess.dir_exists_absolute(dir):
			for file_name in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(file_name))
			DirAccess.remove_absolute(dir)
		var level_file := ProjectSettings.globalize_path(level_path)
		for path in [level_file, level_file + ".previous"]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _streamed_level(path: String) -> LevelRoot:
	var level := make_level()
	level.hflevel_compress = false
	var sys := level.paint_system
	sys.region_streaming_enabled = true
	sys.set_region_size_cells(64)
	sys.region_manager.streaming_radius = 0
	sys._sync_region_manager()
	sys.set_region_base_path(path)
	return level


func _painted(level: Node, at: Vector2i) -> bool:
	return level.paint_layers.layers[0].get_cell(at)


## Paint both cells, then leave only NEAR's region loaded, so FAR's paint is in
## its file in the old folder and nowhere else.
func _paint_and_stream_far_out(level: LevelRoot) -> void:
	var sys := level.paint_system
	for at in [NEAR, FAR]:
		level.paint_layers.layers[0].set_cell(at, true)
		sys.region_manager.mark_loaded(sys.region_manager.region_id_from_cell(at))
	assert_true(sys._unload_region(sys.region_manager.region_id_from_cell(FAR)), "FAR streams out")


func _drain_save(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


func _region_file(level_path: String, at: Vector2i, level: LevelRoot) -> String:
	var region: Vector2i = level.paint_system.region_manager.region_id_from_cell(at)
	var dir := ProjectSettings.globalize_path(level_path.get_basename() + ".hfregions")
	return dir.path_join("region_%d_%d.hfr" % [region.x, region.y])


func test_save_as_takes_a_streamed_out_region_to_the_new_folder():
	var level := _streamed_level(OLD_LEVEL)
	_paint_and_stream_far_out(level)
	assert_true(FileAccess.file_exists(_region_file(OLD_LEVEL, FAR, level)), "FAR's file, old")
	assert_eq(level.save_hflevel(NEW_LEVEL), OK)
	await _drain_save(level)
	assert_true(FileAccess.file_exists(_region_file(NEW_LEVEL, FAR, level)), "FAR's file, new")
	assert_true(FileAccess.file_exists(_region_file(OLD_LEVEL, FAR, level)), "the old one stays")


func test_the_level_saved_as_opens_with_the_streamed_out_paint():
	var level := _streamed_level(OLD_LEVEL)
	_paint_and_stream_far_out(level)
	assert_eq(level.save_hflevel(NEW_LEVEL), OK)
	await _drain_save(level)
	var again := make_level()
	assert_true(again.load_hflevel(NEW_LEVEL), "the new level loads")
	again.paint_system._ensure_regions_for_cell(FAR)
	assert_true(_painted(again, FAR), "FAR's paint came with it")
	again.paint_system._ensure_regions_for_cell(NEAR)
	assert_true(_painted(again, NEAR), "and NEAR's")


func test_streaming_back_in_after_save_as_finds_the_paint():
	var level := _streamed_level(OLD_LEVEL)
	_paint_and_stream_far_out(level)
	assert_eq(level.save_hflevel(NEW_LEVEL), OK)
	await _drain_save(level)
	level.paint_system._ensure_regions_for_cell(FAR)
	assert_true(_painted(level, FAR), "the open level reads FAR back from the new folder")


func test_a_save_to_the_same_name_copies_nothing():
	var level := _streamed_level(OLD_LEVEL)
	_paint_and_stream_far_out(level)
	assert_eq(level.paint_system.carry_region_files_to(OLD_LEVEL), OK)
	assert_false(
		DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(NEW_LEVEL.get_basename() + ".hfregions")
		),
		"no second folder"
	)
