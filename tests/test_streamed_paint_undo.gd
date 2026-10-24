extends "res://tests/mcp/mcp_dispatcher_case.gd"

## Undo of paint in a streamed region whose file changed after the step was
## captured (#1514): the region streams back in as the undo left it, not as its
## file had it, through the bridge and through the plugin's floor paint steps
## alike, while a region the capture never held keeps the paint in its file.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginPaintInput = preload("res://addons/hammerforge/plugin_paint_input.gd")
## Where these tests write their region files, a name of their own so no other
## suite's files are in the way.
const STREAM_LEVEL := "user://hf_streamed_paint_undo_test.hflevel"
## The same level saved under another name.
const OTHER_LEVEL := "user://hf_streamed_paint_undo_other.hflevel"
## Cell (40, 40) lies in region (1, 1) at 32 cells a region, which holds nothing
## until a test paints it.
const CELL := Vector2i(40, 40)
const REGION := Vector2i(1, 1)


## A paint system whose region files cannot be removed, as a file another
## program holds open on Windows cannot be.
class FilesThatStay:
	extends "res://addons/hammerforge/systems/hf_paint_system.gd"

	func _remove_region_file(_region_id: Vector2i, _path: String) -> int:
		return ERR_FILE_CANT_WRITE


var rig := PluginRig.new()
var _rig_level: Node = null
var _heard: Array = []


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func after_each() -> void:
	if _rig_level != null:
		await rig.leave_level(_rig_level)
		_rig_level = null
	_clean_stream_dir()
	_heard.clear()
	super()


func _clean_stream_dir() -> void:
	for level_path in [STREAM_LEVEL, OTHER_LEVEL]:
		var dir := ProjectSettings.globalize_path(level_path.get_basename() + ".hfregions")
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for sub in DirAccess.get_directories_at(dir):
			DirAccess.remove_absolute(dir.path_join(sub))
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))
		DirAccess.remove_absolute(dir)


## Paint that streams in regions of 32 cells, one resident at a time, written
## next to a level of this suite's own. Nothing is painted or loaded yet.
func stream(level: Node, sys = null) -> void:
	if sys == null:
		sys = level.paint_system
	level.hflevel_compress = false
	_clean_stream_dir()
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
func painted(level: Node, at: Vector2i) -> bool:
	return level.paint_layers.layers[0].get_cell(at)


func region_file(level: Node, region: Vector2i) -> String:
	return level.paint_system._region_file_path(region)


func run(command: String, args) -> Dictionary:
	return await call_tool("hf_run_command", {"command": command, "params": args})


## Stream the region out, which writes its paint to its file, then back in, as
## moving the brush away and back does.
func stream_out_and_in(level: Node, at: Vector2i) -> void:
	var sys = level.paint_system
	var region: Vector2i = sys.region_manager.region_id_from_cell(at)
	if sys.region_manager.is_loaded(region):
		assert_true(sys._unload_region(region), "region %s streamed out" % str(region))
	sys._ensure_regions_for_cell(at)


# ===========================================================================
# Through the bridge
# ===========================================================================


func test_undoing_paint_into_an_empty_region_keeps_it_empty_after_it_streams_back_in():
	var level := streamed_level()
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	assert_true(level.paint_system._unload_region(REGION), "the region was written out")
	assert_true(FileAccess.file_exists(region_file(level, REGION)))
	await call_tool("hf_undo")
	assert_false(painted(level, CELL), "undo takes the paint")
	assert_false(
		FileAccess.file_exists(region_file(level, REGION)), "and the file it was written to"
	)
	level.paint_system._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the region streams back in empty")
	assert_eq(_heard, [], "nothing to report")


func test_redo_after_that_undo_writes_the_paint_back_for_the_region_to_stream_in_with():
	var level := streamed_level()
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	assert_true(level.paint_system._unload_region(REGION))
	await call_tool("hf_undo")
	await call_tool("hf_redo")
	assert_true(painted(level, CELL), "redo puts the paint back")
	assert_true(FileAccess.file_exists(region_file(level, REGION)), "and its file")
	stream_out_and_in(level, CELL)
	assert_true(painted(level, CELL), "the region streams back in painted")


## The control: a region the step never held keeps its file, even one written
## again after the step, since the undo never had that region's paint.
func test_an_undo_leaves_the_file_of_a_region_its_capture_never_held_alone():
	var level := streamed_level()
	var sys := level.paint_system
	level.paint_layers.layers[0].set_cell(Vector2i(5, 5), true)
	sys.region_manager.mark_loaded(Vector2i.ZERO)
	assert_true(sys._unload_region(Vector2i.ZERO), "region (0, 0) is on disk alone")
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	# More paint in region (0, 0) after the step, outside any step, written out.
	sys._ensure_regions_for_cell(Vector2i(5, 5))
	level.paint_layers.layers[0].set_cell(Vector2i(6, 6), true)
	assert_true(sys._unload_region(Vector2i.ZERO))
	await call_tool("hf_undo")
	assert_true(FileAccess.file_exists(region_file(level, Vector2i.ZERO)), "its file stays")
	sys._ensure_regions_for_cell(Vector2i(5, 5))
	assert_true(painted(level, Vector2i(5, 5)), "with the paint it had")
	assert_true(painted(level, Vector2i(6, 6)), "and the paint written after the step")


func test_an_undo_that_cannot_write_a_region_file_says_so_and_keeps_the_region_loaded():
	var level := streamed_level()
	var sys := level.paint_system
	var r := await run("paint_ramp", {"from": [CELL.x, CELL.y]})
	assert_true(r.get("ok", false), str(r))
	var next := CELL + Vector2i.ONE
	r = await run("paint_ramp", {"from": [next.x, next.y]})
	assert_true(r.get("ok", false), str(r))
	assert_true(sys._unload_region(REGION), "both cells written out")
	# A folder where the write's temporary file goes, so the write cannot start.
	var path := region_file(level, REGION)
	assert_eq(DirAccess.make_dir_absolute(path + ".writing"), OK)
	await call_tool("hf_undo")
	assert_push_error("could not write region")
	assert_eq(_heard.size(), 1, "said once: %s" % str(_heard))
	if _heard.size() == 1:
		assert_string_contains(_heard[0], str(REGION))
	assert_true(sys.region_manager.is_loaded(REGION), "kept loaded")
	sys._ensure_regions_for_cell(CELL)
	assert_true(painted(level, CELL), "with the paint the undo kept")
	assert_false(painted(level, next), "not the paint on disk")
	DirAccess.remove_absolute(path + ".writing")
	stream_out_and_in(level, CELL)
	assert_true(
		painted(level, CELL), "once it can be written, it streams out and in as the undo left it"
	)
	assert_false(painted(level, next))


# ===========================================================================
# Through the plugin's floor paint steps
# ===========================================================================


## A level in the rig's edited scene, streaming as above, and the camera over
## cell (40, 40).
func rig_level() -> Node:
	var level = await rig.make_level()
	_rig_level = level
	stream(level)
	rig.camera.look_at_from_position(Vector3(40.5, 20, 56), Vector3(40.5, 0, 40.5))
	return level


func screen_at(level: Node, at: Vector2i) -> Vector2:
	var grid = level.paint_layers.layers[0].grid
	return rig.camera.unproject_position(grid.uv_to_world(grid.cell_center_uv(at)))


func test_a_floor_stroke_into_an_empty_region_undoes_to_empty_after_it_streams_back_in():
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig_level()
	var at := screen_at(level, CELL)
	# What handle_paint() does with a press: load the region under the cursor,
	# then capture. handle_paint_input() runs only in the editor, so the stroke
	# goes to the paint tool itself, between the plugin's own two calls.
	level.prepare_paint_stroke(rig.camera, at)
	assert_true(level.paint_system.region_manager.is_loaded(REGION), "loaded before the capture")
	HFPluginPaintInput.begin_floor_paint_undo(rig.plugin, level)
	assert_true(
		level.paint_tool.handle_input(rig.camera, PluginRig.click(MOUSE_BUTTON_LEFT, true, at), at)
	)
	assert_true(
		level.paint_tool.handle_input(rig.camera, PluginRig.click(MOUSE_BUTTON_LEFT, false, at), at)
	)
	HFPluginPaintInput.commit_floor_paint_undo(rig.plugin, level)
	assert_eq(rig.undo().step_count(), 1, "one Paint Floor step")
	assert_true(painted(level, CELL))
	assert_true(level.paint_system._unload_region(REGION), "the region was written out")
	assert_true(rig.undo().press_undo())
	assert_false(painted(level, CELL), "undo takes the stroke")
	level.paint_system._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the region streams back in empty")


func test_a_stamped_room_undoes_to_empty_after_its_region_streams_back_in():
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig_level()
	level.paint_tool._hover_cell = CELL
	rig.plugin.dock.paint_room_btn.pressed.emit()
	assert_eq(rig.undo().step_count(), 1, "one Stamp Paint Room step")
	var corner := CELL + Vector2i(3, 3)
	assert_true(painted(level, CELL))
	assert_true(painted(level, corner), "a 4 by 4 room")
	assert_true(level.paint_system._unload_region(REGION), "the region was written out")
	assert_true(rig.undo().press_undo())
	level.paint_system._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "the region streams back in without the room")
	assert_false(painted(level, corner))


# ===========================================================================
# A file that cannot be removed
# ===========================================================================


func test_a_restore_that_cannot_remove_a_region_file_says_so_and_tries_again_on_the_way_out():
	var level := make_level()
	var sys := FilesThatStay.new(level)
	stream(level, sys)
	var layers: Array = level.state_system.capture_paint_layers(true)
	var files: Dictionary = sys.capture_region_files()
	level.paint_layers.layers[0].set_cell(CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys._unload_region(REGION), "written out")
	sys.restore_paint_layers(layers, 0)
	sys.restore_region_files(files)
	assert_eq(_heard.size(), 1, "said once: %s" % str(_heard))
	assert_true(FileAccess.file_exists(sys._region_file_path(REGION)), "the file stayed")
	assert_true(sys.region_manager.is_loaded(REGION), "so the region stays loaded")
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL), "and the file is not read back")
	assert_false(sys._unload_region(REGION), "streaming out tries the file again")
	assert_true(sys.region_manager.is_loaded(REGION))
	assert_false(painted(level, CELL))


# ===========================================================================
# A save that writes the same paint again
# ===========================================================================


## Every save writes each loaded region, so an undo past one would otherwise
## rewrite them all. One that writes back what was already there leaves it
## nothing to do.
func test_a_save_that_writes_the_same_paint_again_leaves_an_undo_nothing_to_rewrite():
	var level := streamed_level()
	var sys := level.paint_system
	level.paint_layers.layers[0].set_cell(CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys.save_loaded_regions()["ok"], "written once")
	var before := level.capture_state()
	assert_true(sys.save_loaded_regions()["ok"], "and again, unchanged, as an autosave would")
	# Any write from here on fails, and says so.
	var path := region_file(level, REGION)
	assert_eq(DirAccess.make_dir_absolute(path + ".writing"), OK)
	level.restore_state(before)
	assert_eq(_heard, [], "the restore wrote nothing")
	assert_true(painted(level, CELL))
	DirAccess.remove_absolute(path + ".writing")


# ===========================================================================
# The level's region folder
# ===========================================================================


## Saved under another name, or another level loaded over it: the files in the
## folder now are not the ones the capture knew, so a restore leaves them be.
func test_an_undo_from_before_a_save_as_leaves_the_new_folders_files_alone():
	var level := streamed_level()
	var sys := level.paint_system
	var before := level.capture_state()
	sys.set_region_base_path(OTHER_LEVEL)
	level.paint_layers.layers[0].set_cell(CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys._unload_region(REGION))
	var path := region_file(level, REGION)
	assert_string_contains(path, "hf_streamed_paint_undo_other")
	level.restore_state(before)
	assert_true(FileAccess.file_exists(path), "the file in the other folder stays")


## A level that had never been saved had no files at all, so the ones its first
## save and streaming wrote since are put in line with the undo.
func test_an_undo_from_before_the_first_save_puts_the_files_written_since_in_line():
	var level := streamed_level()
	var sys := level.paint_system
	sys.region_manager.region_base_path = ""
	var before := level.capture_state()
	sys.set_region_base_path(STREAM_LEVEL)
	level.paint_layers.layers[0].set_cell(CELL, true)
	sys.region_manager.mark_loaded(REGION)
	assert_true(sys._unload_region(REGION))
	level.restore_state(before)
	assert_false(FileAccess.file_exists(region_file(level, REGION)))
	sys._ensure_regions_for_cell(CELL)
	assert_false(painted(level, CELL))
