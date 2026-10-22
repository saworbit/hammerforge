extends SceneTree
## How HammerForge's own work grows with the number of brushes in a level (#1423).
##
## For each count it builds a level of that many box brushes, 2 m boxes on a 4 m
## grid, and times what a mapper waits for at that size:
##
##   * picking: the Select tool's hover on a mouse move, and a click pick
##   * editing: a handle resize of one brush and placing one brush, each with the
##     undo step the editor records for it, and the undo of that placement
##   * baking: a full bake, the same bake chunked at the size the Status board
##     recommends, Bake Changed after one brush moved, and the CSG bake a level
##     takes once it holds a cut
##   * files: the scene under each Scene Keeps setting as `.tscn` and `.scn`,
##     and the `.hflevel` compressed and plain, with the time to write and open
##     each one
##   * round brushes: the CSG bake of that many 16-sided spheres in the same
##     places, smoothed as a new sphere is and then set flat, up to 300 brushes
##     unless `--round-limit=` says otherwise
##
## It runs headless, so every time is HammerForge's work and none of it is
## drawing. The editor adds its own frames on top: a bake yields a frame every
## few brushes, and the bake tables say how many frames each one spans.
##
## Everything it writes goes into one folder under `user://`, named for the
## process and removed when the run ends. It never touches the editor's
## preferences, and the levels it builds do not autosave.
##
## Usage:
##   godot --headless -s res://tools/benchmark_level_scale.gd --path .
##   godot --headless -s res://tools/benchmark_level_scale.gd --path . -- --counts=100,300,1000,3000
##   godot --headless -s res://tools/benchmark_level_scale.gd --path . -- --repeats=5
##   godot --headless -s res://tools/benchmark_level_scale.gd --path . -- --round-limit=1000

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const UndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const ChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")

## The issue's own sizes stop at 3,000, which takes several minutes, so the
## default run leaves that one to `--counts=`.
const DEFAULT_COUNTS: Array[int] = [100, 300, 1000]
const BOX_SIZE := 2.0
const SPACING := 4.0
## Calls averaged into one figure for the operations that take well under a
## millisecond, so the clock's resolution is not most of the answer.
const PICK_CALLS := 50
const EDIT_CALLS := 10
## Frames to wait for a scene that loads its brushes from the `.hflevel` on open.
const OPEN_FRAMES := 30
## A level of round brushes bakes several times slower than one of boxes, so the
## default run takes the round case only up to this many.
const DEFAULT_ROUND_LIMIT := 300
const ROUND_SIDES := 16

var _counts: Array[int] = DEFAULT_COUNTS.duplicate()
var _repeats := 3
var _round_limit := DEFAULT_ROUND_LIMIT
var _dir := ""
## One row per measurement, in the order they are printed: [table, label, unit].
var _rows: Array = []
## Label to {count: value}.
var _values: Dictionary = {}


## `HFUndoHelper` speaks to the editor's undo manager, whose `create_action()`
## takes a context the core `UndoRedo` has no use for. The history is the core's,
## so a step is recorded and undone exactly as the editor would.
class UndoManager:
	extends RefCounted

	const NO_ARG := &"__benchmark_no_arg__"

	var history := UndoRedo.new()

	func create_action(
		action_name: String, merge_mode: int = 0, _context = null, backward: bool = false
	) -> void:
		history.create_action(action_name, merge_mode, backward)

	func add_do_method(
		target: Object,
		method: StringName,
		a = NO_ARG,
		b = NO_ARG,
		c = NO_ARG,
		d = NO_ARG,
		e = NO_ARG
	) -> void:
		history.add_do_method(_bound(target, method, [a, b, c, d, e]))

	func add_undo_method(
		target: Object,
		method: StringName,
		a = NO_ARG,
		b = NO_ARG,
		c = NO_ARG,
		d = NO_ARG,
		e = NO_ARG
	) -> void:
		history.add_undo_method(_bound(target, method, [a, b, c, d, e]))

	func commit_action(execute: bool = true) -> void:
		history.commit_action(execute)

	func undo() -> bool:
		return history.undo()

	func release() -> void:
		history.clear_history(false)
		history.free()

	static func _bound(target: Object, method: StringName, args: Array) -> Callable:
		var given: Array = []
		for arg in args:
			if typeof(arg) == TYPE_STRING_NAME and arg == NO_ARG:
				break
			given.append(arg)
		return Callable(target, method).bindv(given)


func _init() -> void:
	_run()


func _run() -> void:
	if not _parse_args(OS.get_cmdline_user_args()):
		quit(1)
		return
	# A headless run sleeps this long every frame, because it has no window to
	# draw. Left in, a bake that yields forty frames is a quarter of a second of
	# sleeping, and every edit timed to the end of its frame is mostly the sleep.
	OS.low_processor_usage_mode_sleep_usec = 0
	_dir = "user://hf_benchmark_level_scale_%d" % OS.get_process_id()
	_remove_folder(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	var started := Time.get_ticks_msec()
	await process_frame
	for count in _counts:
		printerr("level of %d brushes..." % count)
		await _measure(count)
	_remove_folder(_dir)
	_print_report(Time.get_ticks_msec() - started)
	quit()


func _parse_args(args: PackedStringArray) -> bool:
	for arg in args:
		if arg.begins_with("--counts="):
			var counts: Array[int] = []
			for part in arg.trim_prefix("--counts=").split(",", false):
				if not part.strip_edges().is_valid_int() or int(part) < 1:
					printerr("--counts= takes whole numbers above zero, not '%s'" % part)
					return false
				counts.append(int(part))
			if counts.is_empty():
				printerr("--counts= needs at least one count")
				return false
			_counts = counts
		elif arg.begins_with("--repeats="):
			_repeats = maxi(1, int(arg.trim_prefix("--repeats=")))
		elif arg.begins_with("--round-limit="):
			_round_limit = maxi(0, int(arg.trim_prefix("--round-limit=")))
		else:
			printerr(
				(
					"Unknown argument '%s'. Takes --counts=100,300, --repeats=3 and --round-limit=300."
					% arg
				)
			)
			return false
	return true


# ===========================================================================
# One level
# ===========================================================================


func _measure(count: int) -> void:
	var level := await _build(count)
	await _measure_picks(level, count)
	await _measure_edits(level, count)
	await _measure_bakes(level, count)
	var files := await _save_files(level, count)
	_close(level)
	await _measure_opens(files, count)
	await _measure_hflevel_loads(files, count)
	for path in files.values():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(path)))
	if count <= _round_limit:
		await _measure_round(count)


## A fresh level standing where the editor would have it: the edited scene's
## root, so everything it makes is owned and written by a save.
func _new_level() -> Node3D:
	var level: Node3D = LevelRootScript.new()
	level.name = "BenchmarkLevel"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	return level


func _build(count: int, shape: int = LevelRootScript.BrushShape.BOX) -> Node3D:
	var level := _new_level()
	# Explicit, so the `.hflevel` a Bake Only scene loads on open is in this run's
	# folder rather than the project's `.hammerforge/`.
	level.hflevel_autosave_path = _dir.path_join("level_%d.hflevel" % count)
	set_edited_scene_root(level)
	get_root().add_child(level)
	await process_frame
	var side := ceili(sqrt(float(count)))
	var offset := Vector3(side - 1, 0.0, side - 1) * SPACING * 0.5
	var infos: Array = []
	for i in range(count):
		var cell := Vector3(i % side, 0.0, floori(float(i) / side)) * SPACING
		var info := {
			"shape": shape,
			"size": Vector3.ONE * BOX_SIZE,
			"center": cell - offset + Vector3(0.0, BOX_SIZE * 0.5, 0.0),
		}
		if shape != LevelRootScript.BrushShape.BOX:
			info["sides"] = ROUND_SIDES
		infos.append(info)
	level.create_brushes_from_infos(infos)
	await process_frame
	if level.get_live_brush_count() != count:
		push_error("Built %d brushes, wanted %d" % [level.get_live_brush_count(), count])
	return level


func _close(level: Node3D) -> void:
	if get_edited_scene_root() == level:
		set_edited_scene_root(null)
	if level.get_parent():
		level.get_parent().remove_child(level)
	level.free()


# ===========================================================================
# Picking
# ===========================================================================


func _measure_picks(level: Node3D, count: int) -> void:
	var camera := Camera3D.new()
	get_root().add_child(camera)
	# Above one corner of the grid and looking across it, so a sweep of the
	# pointer runs over near brushes, far ones and gaps between them.
	var reach := ceilf(sqrt(float(count))) * SPACING * 0.5
	camera.position = Vector3(-reach, reach * 0.6 + 8.0, -reach)
	camera.look_at(Vector3.ZERO)
	await process_frame
	var view := get_root().get_visible_rect().size
	var points: Array[Vector2] = []
	for i in range(PICK_CALLS):
		var t := float(i) / float(PICK_CALLS - 1)
		points.append(Vector2(view.x * t, view.y * (0.35 + 0.3 * t)))
	var hits := 0
	for point in points:
		if level.pick_brush(camera, point, true) != null:
			hits += 1
	_record("picks", "Pointer positions over a brush, of %d" % PICK_CALLS, count, hits)
	_record(
		"picks",
		"Hover pick, one mouse move (ms)",
		count,
		_median_of(_time_hover.bind(level, camera, points))
	)
	_record("picks", "Click pick (ms)", count, _median_of(_time_click.bind(level, camera, points)))
	level.clear_hover()
	camera.get_parent().remove_child(camera)
	camera.free()


## What the Select tool runs on every mouse move with no button held.
func _time_hover(level: Node3D, camera: Camera3D, points: Array[Vector2]) -> float:
	var start := Time.get_ticks_usec()
	for point in points:
		level.update_hover(camera, point)
	return _ms_since(start) / float(points.size())


## What a click runs to find the brush or entity under the pointer.
func _time_click(level: Node3D, camera: Camera3D, points: Array[Vector2]) -> float:
	var start := Time.get_ticks_usec()
	for point in points:
		level.pick_brush(camera, point, true)
	return _ms_since(start) / float(points.size())


# ===========================================================================
# Editing
# ===========================================================================


## Each edit is timed from the call to the end of the next frame, so the work a
## brush defers to that frame is counted with the edit that caused it.
##
## The editor then checks every brush for changes Godot made behind HammerForge's
## back, once after each step lands in the undo history (`HFBrushChangeTracker`,
## queued by the plugin on `version_changed`). That pass is timed on its own.
func _measure_edits(level: Node3D, count: int) -> void:
	var manager := UndoManager.new()
	var tracker: RefCounted = ChangeTracker.new()
	tracker.prime(level)
	var brush: Node = level.draft_brushes_node.get_child(floori(count / 2.0))
	var brush_id := str(brush.brush_id)
	var home: Vector3 = brush.global_position
	var resize_runs: Array = []
	var place_runs: Array = []
	var undo_runs: Array = []
	var check_runs: Array = []
	for _r in range(_repeats):
		var resize_total := 0.0
		var check_total := 0.0
		for i in range(EDIT_CALLS):
			# Grow and shrink by turns, so every call is a change and the level
			# ends the run as it started.
			var grown := Vector3.ONE * (BOX_SIZE * (1.25 if i % 2 == 0 else 1.0))
			var start := Time.get_ticks_usec()
			# As the handle drag commits it: one brush, so the step is that brush.
			UndoHelper.commit(
				manager,
				level,
				"Resize Brush",
				"set_brush_transform_by_id",
				[brush_id, grown, home],
				false,
				Callable(),
				"",
				false,
				[brush_id]
			)
			await process_frame
			resize_total += _ms_since(start)
			start = Time.get_ticks_usec()
			tracker.reconcile(level)
			check_total += _ms_since(start)
		resize_runs.append(resize_total / float(EDIT_CALLS))
		check_runs.append(check_total / float(EDIT_CALLS))

		var place_total := 0.0
		var undo_total := 0.0
		for i in range(EDIT_CALLS):
			var info := {
				"shape": LevelRootScript.BrushShape.BOX,
				"size": Vector3.ONE * BOX_SIZE,
				"center": home + Vector3(0.0, BOX_SIZE * 2.0 + float(i), 0.0),
			}
			var start := Time.get_ticks_usec()
			# As drawing a brush commits it: the step holds the whole level.
			UndoHelper.commit(manager, level, "Place Brush", "create_brush_from_info", [info])
			await process_frame
			place_total += _ms_since(start)
			tracker.reconcile(level)
			start = Time.get_ticks_usec()
			manager.undo()
			await process_frame
			undo_total += _ms_since(start)
			tracker.reconcile(level)
		place_runs.append(place_total / float(EDIT_CALLS))
		undo_runs.append(undo_total / float(EDIT_CALLS))
	manager.release()
	if level.get_live_brush_count() != count:
		push_error("Edits left %d brushes, wanted %d" % [level.get_live_brush_count(), count])
	_record("edits", "Resize one brush, with its undo step (ms)", count, _median(resize_runs))
	_record("edits", "Place one brush, with its undo step (ms)", count, _median(place_runs))
	_record("edits", "Undo that placement (ms)", count, _median(undo_runs))
	_record("edits", "Change check after every step (ms)", count, _median(check_runs))


# ===========================================================================
# Baking
# ===========================================================================


func _measure_bakes(level: Node3D, count: int) -> void:
	await _bake_runs(level, count, "Full bake", level.bake)

	var chunk: float = level.get_recommended_chunk_size()
	if chunk > 0.0:
		level.bake_chunk_size = chunk
		await _bake_runs(level, count, "Full bake, chunked at the recommended size", level.bake)
		_record("bake_shape", "Recommended chunk size (m)", count, chunk)
		_record("bake_shape", "Chunks that bake makes", count, level.get_bake_chunk_count())
		level.bake_chunk_size = 0.0
	# A full bake leaves nothing changed, so each Bake Changed timed here has one
	# brush moved first, the smallest change there is.
	var brush: Node = level.draft_brushes_node.get_child(floori(count / 3.0))
	await level.bake()
	await _bake_runs(
		level,
		count,
		"Bake Changed, one brush moved",
		_move_one_and_bake_changed.bind(level, str(brush.brush_id), brush.global_position, [false])
	)
	# What a level bakes with once it holds one cut. Forced here rather than by
	# adding a cut, so the brushes are the same ones the bakes above took.
	await _bake_runs(
		level,
		count,
		"CSG bake, the path a level with a cut takes",
		level.bake.bind(true, false, 0, 0, true)
	)


## Up half a metre and back down by turns, so every call is a change.
func _move_one_and_bake_changed(
	level: Node3D, brush_id: String, home: Vector3, raised: Array
) -> Variant:
	raised[0] = not raised[0]
	var to := home + (Vector3(0.0, 0.5, 0.0) if raised[0] else Vector3.ZERO)
	level.set_brush_transform_by_id(brush_id, Vector3.ONE * BOX_SIZE, to)
	return level.bake_dirty()


## `start` begins one bake and returns what the level's bake call returns, which
## is awaited here. Timed from the call to the answer, which is longer than the
## last bake time the dock shows: that one leaves out the frames the bake waits
## for and the passes after the mesh is built.
func _bake_runs(
	level: Node3D, count: int, label: String, start: Callable, table: String = "bakes"
) -> void:
	var walls: Array = []
	var frames: Array = []
	for _r in range(_repeats):
		var frame_before := Engine.get_process_frames()
		var began := Time.get_ticks_usec()
		var ok: bool = await start.call()
		walls.append(_ms_since(began))
		frames.append(Engine.get_process_frames() - frame_before)
		if not ok:
			push_error("%s failed at %d brushes" % [label, count])
	_record(table, "%s (ms)" % label, count, _median(walls))
	if table == "bakes":
		_record("bake_shape", "%s, frames it waits through" % label, count, _median(frames))


# ===========================================================================
# Round brushes
# ===========================================================================


## A smoothed brush's shading goes back on what the CSG boolean made (#1429),
## which took time growing with the square of the round brushes in the level
## (#1612). The same spheres set flat, with no shading to put back, are the
## yardstick.
func _measure_round(count: int) -> void:
	var level := await _build(count, LevelRootScript.BrushShape.SPHERE)
	var csg_bake: Callable = level.bake.bind(true, false, 0, 0, true)
	var label := "CSG bake, %d-sided spheres smoothed" % ROUND_SIDES
	await _bake_runs(level, count, label, csg_bake, "round")
	for brush in level.draft_brushes_node.get_children():
		for face in brush.faces:
			face.smoothing_group = 0
	await _bake_runs(level, count, "CSG bake, the same spheres set flat", csg_bake, "round")
	_close(level)


# ===========================================================================
# Files
# ===========================================================================

const KEEPS := {
	"Brushes and bake": 0,
	"Brushes only": 1,
	"Baked geometry only": 2,
}


## Saves every file once untimed, then times each save, and returns the paths by
## a name the open pass reads them back by.
func _save_files(level: Node3D, count: int) -> Dictionary:
	# The scene is saved with a bake in it, as a level that has been baked is.
	await level.bake()
	var files: Dictionary = {}

	level.hflevel_compress = true
	var compressed_path: String = level.hflevel_autosave_path
	await _time_hflevel_save(level, count, compressed_path, ".hflevel, compressed")
	files["hflevel compressed"] = compressed_path
	level.hflevel_compress = false
	var plain_path := _dir.path_join("level_%d_plain.hflevel" % count)
	await _time_hflevel_save(level, count, plain_path, ".hflevel, plain")
	files["hflevel plain"] = plain_path
	level.hflevel_compress = true

	for keep_name in KEEPS:
		level.scene_contents = KEEPS[keep_name]
		for extension in ["tscn", "scn"]:
			var path := _dir.path_join(
				"level_%d_%s.%s" % [count, keep_name.to_lower().replace(" ", "_"), extension]
			)
			# The editor's own save compresses a binary scene unless its
			# `filesystem/on_save/compress_binary_resources` setting is off.
			var flags := ResourceSaver.FLAG_COMPRESS if extension == "scn" else 0
			var saves: Array = []
			for _r in range(_repeats):
				var start := Time.get_ticks_usec()
				var packed := PackedScene.new()
				var pack_err := packed.pack(level)
				var save_err := ResourceSaver.save(packed, path, flags)
				saves.append(_ms_since(start))
				if pack_err != OK or save_err != OK:
					push_error("Saving %s failed: %d %d" % [path, pack_err, save_err])
			var label := ".%s, %s" % [extension, keep_name]
			_record("sizes", "%s (KB)" % label, count, _kb(path))
			_record("saves", "Save %s (ms)" % label, count, _median(saves))
			files["%s|%s" % [keep_name, extension]] = path
	level.scene_contents = KEEPS["Brushes and bake"]
	return files


## Save Level takes the level on the main thread and writes it on another. Both
## halves are timed: the first is how long the editor stops, the second is when
## the file is on disk.
func _time_hflevel_save(level: Node3D, count: int, path: String, label: String) -> void:
	var blocked: Array = []
	var written: Array = []
	for _r in range(_repeats):
		var start := Time.get_ticks_usec()
		var err: int = level.save_hflevel(path, true)
		blocked.append(_ms_since(start))
		if err != OK:
			push_error("save_hflevel(%s) returned %d" % [path, err])
		if not await _settle_save(level):
			push_error("save_hflevel(%s) did not finish" % path)
		written.append(_ms_since(start))
	_record("sizes", "%s (KB)" % label, count, _kb(path))
	_record("saves", "Save %s, editor blocked (ms)" % label, count, _median(blocked))
	_record("saves", "Save %s, until written (ms)" % label, count, _median(written))


## Until the write thread is done, by the clock rather than by frames: with no
## sleep a headless frame is a few microseconds, and a frame budget runs out
## before a big level is written.
func _settle_save(level: Node3D, timeout_msec: int = 120000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		level._process_hflevel_saves()
		if not level.file_system._hflevel_thread:
			return true
		await process_frame
	return false


## Opening a scene is the load, the instancing, and the level's `_ready()`, and
## for a scene that keeps only its bake, the `.hflevel` it loads after that.
func _measure_opens(files: Dictionary, count: int) -> void:
	for keep_name in KEEPS:
		for extension in ["tscn", "scn"]:
			var path: String = files["%s|%s" % [keep_name, extension]]
			var opens: Array = []
			for _r in range(_repeats):
				var start := Time.get_ticks_usec()
				var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
				var opened: Node3D = (packed as PackedScene).instantiate()
				set_edited_scene_root(opened)
				get_root().add_child(opened)
				for _f in range(OPEN_FRAMES):
					await process_frame
					if opened.get_live_brush_count() >= count:
						break
				opens.append(_ms_since(start))
				if opened.get_live_brush_count() != count:
					push_error(
						(
							"%s opened with %d brushes, wanted %d"
							% [path, opened.get_live_brush_count(), count]
						)
					)
				_close(opened)
			_record("opens", "Open .%s, %s (ms)" % [extension, keep_name], count, _median(opens))


func _measure_hflevel_loads(files: Dictionary, count: int) -> void:
	for key in ["hflevel compressed", "hflevel plain"]:
		var loads: Array = []
		for _r in range(_repeats):
			var level := _new_level()
			set_edited_scene_root(level)
			get_root().add_child(level)
			await process_frame
			var start := Time.get_ticks_usec()
			if not level.load_hflevel(str(files[key])):
				push_error("load_hflevel(%s) failed" % files[key])
			await process_frame
			loads.append(_ms_since(start))
			if level.get_live_brush_count() != count:
				push_error("%s loaded %d brushes" % [files[key], level.get_live_brush_count()])
			_close(level)
		var label := "Load .hflevel, %s (ms)" % key.trim_prefix("hflevel ")
		_record("opens", label, count, _median(loads))


# ===========================================================================
# Report
# ===========================================================================

const TABLES := {
	"picks": "Picking",
	"edits": "Editing",
	"bakes": "Baking",
	"bake_shape": "Bake shape",
	"round": "Round brushes",
	"sizes": "File sizes",
	"saves": "Saving",
	"opens": "Opening",
}


func _print_report(elapsed_ms: int) -> void:
	var version: Dictionary = Engine.get_version_info()
	var memory: Dictionary = OS.get_memory_info()
	print("## Level scale benchmark")
	print("")
	print("- Processor: %s, %d threads" % [OS.get_processor_name(), OS.get_processor_count()])
	print("- Memory: %.1f GiB" % (float(memory.get("physical", 0)) / pow(1024.0, 3)))
	print("- OS: %s %s" % [OS.get_name(), OS.get_version()])
	print("- Godot: %s (%s)" % [version.get("string", ""), str(version.get("hash", "")).left(9)])
	print("- Commit: %s" % _commit())
	print("- Date: %s" % Time.get_date_string_from_system())
	print(
		(
			"- Counts: %s, median of %d runs"
			% [", ".join(PackedStringArray(_counts.map(_fmt_count))), _repeats]
		)
	)
	print("- Whole run: %.1f s, headless" % (float(elapsed_ms) / 1000.0))
	for table in TABLES:
		print("")
		print("### %s" % TABLES[table])
		print("")
		var header := "| Brushes |"
		var rule := "|---|"
		for count in _counts:
			header += " %s |" % _fmt_count(count)
			rule += "--:|"
		print(header)
		print(rule)
		for row in _rows:
			if row[0] != table:
				continue
			var line := "| %s |" % row[1]
			for count in _counts:
				var by_count: Dictionary = _values[row[1]]
				line += " %s |" % (_fmt(by_count[count]) if by_count.has(count) else "-")
			print(line)


## The commit measured, and whether the tree had changes on top of it, since
## those are measured too.
func _commit() -> String:
	var out: Array = []
	if OS.execute("git", ["rev-parse", "--short", "HEAD"], out) != 0 or out.is_empty():
		return "unknown"
	var commit := str(out[0]).strip_edges()
	var changes: Array = []
	OS.execute("git", ["status", "--porcelain", "--untracked-files=no"], changes)
	if not changes.is_empty() and str(changes[0]).strip_edges() != "":
		commit += ", with uncommitted changes"
	return commit


# ===========================================================================
# Helpers
# ===========================================================================


func _record(table: String, label: String, count: int, value: float) -> void:
	if not _values.has(label):
		_values[label] = {}
		_rows.append([table, label])
	_values[label][count] = value


func _median_of(fn: Callable) -> float:
	var runs: Array = []
	for _r in range(_repeats):
		runs.append(float(fn.call()))
	return _median(runs)


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := floori(sorted.size() / 2.0)
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) / 2.0


static func _ms_since(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


static func _kb(path: String) -> float:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1.0
	var size := file.get_length()
	file.close()
	return float(size) / 1024.0


static func _fmt(value: float) -> String:
	if value == floorf(value):
		return _fmt_count(int(value))
	if absf(value) >= 100.0:
		return _fmt_count(roundi(value))
	if absf(value) >= 10.0:
		return "%.1f" % value
	return "%.2f" % value


static func _fmt_count(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## Take `path` away with everything in it.
static func _remove_folder(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		_remove_folder(path.path_join(dir_name))
	DirAccess.remove_absolute(path)
