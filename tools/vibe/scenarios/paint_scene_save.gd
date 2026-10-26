@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Floor paint through Ctrl+S: the level packed into its `.tscn` and opened again.
##
## Since #1854 the scene carries the floor paint in `live_registries` beside the
## layer nodes it always wrote. `scene-reopen` packs a level with no paint and
## `heightmap-io` goes through `capture_state()` only. So: paint everything a
## layer holds -- cells, materials, blend weights, wall heights, a heightmap,
## terrain slots, a confirmed connector, display names, the active layer -- pack
## it the way `scene-reopen` does, open it again, and compare it cell by cell
## with the level before and with the same level through its `.hflevel`. Then
## the same for a level with region streaming on, whose scene carries the region
## index and not the cells, and whose paint is partly in `.hfr` files.
##
## `_get_editor_owner()` reads `tree.edited_scene_root`, null headless, so the
## owners the editor gives are given here before packing.

const DIR := "user://paint_scene_save"
const LEVEL := DIR + "/level.hflevel"
const SCENE := DIR + "/level.tscn"
const STREAMED := DIR + "/streamed.hflevel"
const STREAMED_SCENE := DIR + "/streamed.tscn"
const TEXTURE := "res://addons/hammerforge/icon.png"


func id() -> String:
	return "paint-scene-save"


func summary() -> String:
	return "what a painted level's .tscn keeps of its floor paint, streamed and not, against its .hflevel"


func expected_issues() -> Array[int]:
	return [2006]


func run() -> void:
	_cleanup()
	await _a_painted_level_through_its_scene()
	await _a_streamed_level_through_its_scene()
	await _far_cells_through_both_formats()
	await _what_one_cell_costs()
	_cleanup()


func _cleanup() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(dir):
		return
	var stack: Array[String] = [dir]
	var dirs: Array[String] = []
	while not stack.is_empty():
		var d: String = stack.pop_back()
		dirs.append(d)
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		for sub in DirAccess.get_directories_at(d):
			stack.append(d.path_join(sub))
	dirs.reverse()
	for d in dirs:
		DirAccess.remove_absolute(d)


func _own(root: Node3D) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


## Pack `root` to `path`, free it, and open the scene again in its place.
func _reopen(root: Node3D, path: String) -> Node3D:
	_own(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		flag("PackedScene.pack() failed", err)
		return null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	ResourceSaver.save(packed, path)
	note("packed scene", "%d bytes" % HFVibe.file_size(path))
	root.get_parent().remove_child(root)
	root.queue_free()
	await frame()
	await frame()
	var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var reopened: Node3D = scene.instantiate()
	_tree.get_root().add_child(reopened)
	await frame()
	await frame()
	return reopened


## The floor paint as one comparable dictionary: each layer with its chunks in
## a fixed order, the connectors, the active layer, and what was generated.
func _snapshot(root: Node3D) -> Dictionary:
	var layers: Array = root.state_system.capture_paint_layers(true)
	for entry in layers:
		var chunks: Array = entry.get("chunks", [])
		chunks.sort_custom(func(a, b): return [a["cx"], a["cy"]] < [b["cx"], b["cy"]])
		var heights: Array = entry.get("wall_heights", [])
		heights.sort_custom(func(a, b): return [a["x"], a["y"]] < [b["x"], b["y"]])
	var cells: Array = []
	for layer in root.paint_layers.layers:
		cells.append(layer.filled_cell_count())
	var rec = root.paint_tool.reconciler
	return {
		"layers": layers,
		"cells": cells,
		"connectors": root.paint_tool.capture_connector_defs(),
		"active": root.paint_layers.active_layer_index,
		"generated":
		[
			rec.floors_root.get_child_count(),
			rec.walls_root.get_child_count(),
			rec.heightmap_floors_root.get_child_count(),
		],
	}


func _compare(before: Dictionary, after: Dictionary, context: String) -> Array:
	var moved: Array = []
	for key in before:
		if HFVibe.canonical(before[key]) != HFVibe.canonical(after.get(key)):
			moved.append(key)
			note(
				"%s changed '%s'" % [context, key],
				(
					"%s -> %s"
					% [
						HFVibe.canonical(before[key]).substr(0, 300),
						HFVibe.canonical(after.get(key)).substr(0, 300)
					]
				)
			)
	return moved


func _a_painted_level_through_its_scene() -> void:
	note("-- three painted layers, packed and opened again --")
	var root: Node3D = await fresh_root("PaintScene")
	root.grid_snap = 1.0
	root.hflevel_autosave_path = LEVEL
	await frame()
	var paint = root.paint_system
	paint.paint_cells(0, Vector2i(0, 0), Vector2i(9, 9), true)
	paint.paint_cells(0, Vector2i(0, 0), Vector2i(4, 4), true, 2)
	var ground = root.paint_layers.layers[0]
	ground.set_cell_blend_slot(Vector2i(1, 1), 1, 0.5)
	ground.set_cell_blend_slot(Vector2i(2, 2), 3, 0.75)
	paint.raise_cells(0, Vector2i(0, 0), Vector2i(9, 0), 2.0)
	root.rename_paint_layer(0, "Ground")
	root.add_paint_layer()
	paint.set_layer_y(1.0)
	paint.paint_cells(1, Vector2i(10, 0), Vector2i(13, 3), true)
	root.rename_paint_layer(1, "Step")
	var confirmed: Dictionary = paint.confirm_connectors(1, Vector2i(10, 0), Vector2i(10, 3), 0)
	note("connector confirmed", confirmed.get("added", confirmed.get("error")))
	root.add_paint_layer()
	root.generate_heightmap_noise({"seed": 7})
	root.set_heightmap_scale(3.0)
	root.set_terrain_slot_texture(1, TEXTURE)
	paint.paint_cells(2, Vector2i(20, 0), Vector2i(27, 7), true)
	root.set_active_paint_layer(1)
	await frame()
	var before := _snapshot(root)
	note("cells per layer", before["cells"])
	note("generated floors / walls / terrain chunks", before["generated"])
	root.save_hflevel(LEVEL, true)
	await HFVibe.settle_save(_tree, root)

	var reopened: Node3D = await _reopen(root, SCENE)
	if reopened == null or reopened.get("paint_system") == null:
		flag("the reopened level has no paint system")
		return
	var after := _snapshot(reopened)
	note("cells per layer after reopening", after["cells"])
	note("generated after reopening", after["generated"])
	var moved := _compare(before, after, "the .tscn")
	if not moved.is_empty():
		flag("a painted level's scene does not bring its floor paint back as it was", moved)

	# The same level through its .hflevel, into a fresh root.
	var loaded: Node3D = await fresh_root("PaintLoaded")
	loaded.load_hflevel(LEVEL)
	await frame()
	var from_file := _snapshot(loaded)
	var file_moved := _compare(before, from_file, "the .hflevel")
	if not file_moved.is_empty():
		flag("a painted level's .hflevel does not bring its floor paint back as it was", file_moved)
	await drop_root(loaded)
	await drop_root(reopened)


## With streaming on, the scene keeps the region index and no cells, and the
## cells of a region streamed out are in its `.hfr` file alone.
func _a_streamed_level_through_its_scene() -> void:
	note("-- a streamed level, packed and opened again --")
	var root: Node3D = await fresh_root("PaintStream")
	root.grid_snap = 1.0
	root.hflevel_autosave_path = STREAMED
	await frame()
	var paint = root.paint_system
	paint.set_region_size_cells(64)
	paint.set_region_streaming_radius(0)
	paint.set_region_streaming_enabled(true)
	# Three regions with a room each: (0,0), (2,0) and (0,2).
	paint.paint_cells(0, Vector2i(0, 0), Vector2i(3, 3), true)
	paint.paint_cells(0, Vector2i(130, 0), Vector2i(133, 3), true)
	paint.paint_cells(0, Vector2i(0, 130), Vector2i(3, 133), true)
	root.save_hflevel(STREAMED, true)
	await HFVibe.settle_save(_tree, root)
	# The cursor goes back to the origin, and the other two stream out.
	paint._ensure_regions_for_cell(Vector2i.ZERO)
	await frame()
	note("regions loaded with the cursor at the origin", paint.get_loaded_regions())
	# A room painted after the Save Level, as a mapper keeps working.
	paint.paint_cells(0, Vector2i(10, 10), Vector2i(11, 11), true)
	var region_dir := ProjectSettings.globalize_path(DIR.path_join("streamed.hfregions"))
	var files_before: Array = Array(DirAccess.get_files_at(region_dir))
	files_before.sort()
	note("region files on disk", files_before)
	note("cells in memory, the origin's two rooms", root.paint_layers.layers[0].filled_cell_count())
	var carried: Dictionary = root.live_registries.get("floor_paint", {})
	note("what the scene carries of the paint", carried.get("terrain_regions"))

	var reopened: Node3D = await _reopen(root, STREAMED_SCENE)
	if reopened == null or reopened.get("paint_system") == null:
		flag("the reopened streamed level has no paint system")
		return
	var rp = reopened.paint_system
	var folder: String = rp.region_manager.region_base_path
	var index: Array = rp.region_manager.region_index.keys()
	var in_memory: int = reopened.paint_layers.layers[0].filled_cell_count()
	note("streaming on after reopening", rp.region_streaming_enabled)
	note("region folder after reopening", "'%s'" % folder)
	note("region index after reopening", index)
	note("cells in memory after reopening", in_memory)
	note(
		"generated floors after reopening",
		reopened.paint_tool.reconciler.floors_root.get_child_count()
	)
	# The cursor goes to each region in turn, as the mapper looks round.
	var found: Dictionary = {}
	for cell in [Vector2i(130, 0), Vector2i(0, 130), Vector2i.ZERO]:
		rp._ensure_regions_for_cell(cell)
		await frame()
		for probe in [Vector2i(0, 0), Vector2i(130, 0), Vector2i(0, 130), Vector2i(10, 10)]:
			if reopened.paint_layers.layers[0].get_cell(probe):
				found[probe] = true
	note("of the four rooms, found after visiting each region", found.keys())
	if found.size() < 3:
		known(
			2006,
			"a streamed level opened from its scene has no floor paint and cannot stream any in",
			(
				(
					"Four rooms painted with streaming on: three in regions (0,0), (2,0) and"
					+ " (0,2), then Save Level wrote %s, the far two streamed out, and a fourth"
					+ " room went down at the origin. The scene carries no cells for a streamed"
					+ " level, only the region index. Opened again, restore_floor_paint() turns"
					+ " streaming on but nothing gives the paint system its region folder"
					+ " (only save_hflevel() and load_hflevel() call set_region_base_path), so it"
					+ " is '%s'; restore_paint_layers() then clears the region index it was just"
					+ " handed (hf_paint_system.gd:962), leaving %s. %d cells are in memory, and"
					+ " moving the cursor over each region streams in %d of the four rooms. The"
					+ " room painted after the Save Level is in no file at all"
				)
				% [files_before, folder, index, in_memory, found.size()]
			)
		)

	# The control: the same level through its .hflevel, as Load Level reads it.
	var control: Node3D = await fresh_root("StreamControl")
	control.load_hflevel(STREAMED)
	await frame()
	var through_file: Dictionary = {}
	for cell in [Vector2i(130, 0), Vector2i(0, 130), Vector2i.ZERO]:
		control.paint_system._ensure_regions_for_cell(cell)
		await frame()
		for probe in [Vector2i(0, 0), Vector2i(130, 0), Vector2i(0, 130), Vector2i(10, 10)]:
			if control.paint_layers.layers[0].get_cell(probe):
				through_file[probe] = true
	note("the same level through Load Level finds", through_file.keys())
	await drop_root(control)

	# Nothing more is done. The autosave timer comes round, as it does five
	# minutes after the scene opens whether or not anything changed.
	reopened.autosave_scheduler.on_timer()
	await HFVibe.settle_save(_tree, reopened)
	var files_after: Array = Array(DirAccess.get_files_at(region_dir))
	files_after.sort()
	note("region files after the first autosave", files_after)
	var check: Node3D = await fresh_root("StreamCheck")
	check.load_hflevel(STREAMED)
	await frame()
	var cp = check.paint_system
	var read_back: Dictionary = {}
	for cell in [Vector2i.ZERO, Vector2i(130, 0), Vector2i(0, 130)]:
		cp._ensure_regions_for_cell(cell)
		await frame()
		for probe in [Vector2i(0, 0), Vector2i(130, 0), Vector2i(0, 130), Vector2i(10, 10)]:
			if check.paint_layers.layers[0].get_cell(probe):
				read_back[probe] = true
	note("of the four rooms, found loading the level file afterwards", read_back.keys())
	if files_after.size() < files_before.size():
		known(
			2006,
			"the first autosave after opening a streamed level's scene deletes its region files",
			(
				(
					"Region files before %s; after the autosave timer fires once on the"
					+ " reopened level, with nothing edited, %s. The scheduler's first run saves"
					+ " unconditionally (_saved_marker starts null) to resolved_hflevel_path(),"
					+ " the level's own file. _write_hflevel() calls carry_region_files_to(),"
					+ " which reads the empty region folder as 'a level never saved has no"
					+ " region files anywhere' and runs _clear_region_files() on the target's"
					+ " folder: this level's own. Loading the file afterwards finds %d of the"
					+ " four rooms"
				)
				% [files_before, files_after, read_back.size()]
			)
		)
	await drop_root(check)
	await drop_root(reopened)


## Cells at the corners of the cell-space limit, through the scene and the file.
func _far_cells_through_both_formats() -> void:
	note("-- cells at the edge of the cell limit, through the .tscn and the .hflevel --")
	var root: Node3D = await fresh_root("PaintFar")
	root.hflevel_autosave_path = LEVEL
	await frame()
	var paint = root.paint_system
	var limit: int = paint.CELL_LIMIT
	for corner in [
		Vector2i(-limit, -limit), Vector2i(limit - 1, limit - 1), Vector2i(limit - 1, -limit)
	]:
		var done: Dictionary = paint.paint_cells(0, corner, corner + Vector2i(1, 1), true)
		if not done["ok"]:
			note("refused at %s" % corner, done["error"])
	var outside: Dictionary = paint.paint_cells(
		0, Vector2i(limit + 1, 0), Vector2i(limit + 1, 0), true
	)
	note("one cell past the limit", outside.get("error", "accepted"))
	await frame()
	var before := _snapshot(root)
	note("cells", before["cells"])
	var floors: Array = []
	for child in root.paint_tool.reconciler.floors_root.get_children():
		floors.append(child.global_position.snapped(Vector3.ONE * 0.01))
	floors.sort()
	note("generated floor centres", floors)
	root.save_hflevel(LEVEL, true)
	await HFVibe.settle_save(_tree, root)
	var reopened: Node3D = await _reopen(root, SCENE)
	var moved := _compare(before, _snapshot(reopened), "the .tscn")
	var loaded: Node3D = await fresh_root("PaintFarLoaded")
	loaded.load_hflevel(LEVEL)
	await frame()
	var file_moved := _compare(before, _snapshot(loaded), "the .hflevel")
	if not moved.is_empty() or not file_moved.is_empty():
		flag("far cells do not come back through the scene or the file", [moved, file_moved])
	await drop_root(loaded)
	await drop_root(reopened)


## What one painted cell adds to the scene, and to the level file.
func _what_one_cell_costs() -> void:
	note("-- what painted cells cost the .tscn and the .hflevel --")
	var sizes: Array = []
	for cells in [0, 1, 4]:
		var root: Node3D = await fresh_root("PaintCost%d" % cells)
		root.hflevel_autosave_path = LEVEL
		root.grid_snap = 1.0
		await frame()
		# One cell in each of `cells` chunks, 32 cells apart.
		for i in cells:
			root.paint_system.paint_cells(0, Vector2i(i * 32, 0), Vector2i(i * 32, 0), true)
		root.save_hflevel(LEVEL, true)
		await HFVibe.settle_save(_tree, root)
		var level_bytes := HFVibe.file_size(LEVEL)
		_own(root)
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, SCENE)
		var scene_bytes := HFVibe.file_size(SCENE)
		var paint_text: int = var_to_str(root.live_registries.get("floor_paint", {})).length()
		var generated: int = (
			root.paint_tool.reconciler.floors_root.get_child_count()
			+ root.paint_tool.reconciler.walls_root.get_child_count()
		)
		sizes.append([cells, scene_bytes, level_bytes])
		note(
			"%d painted cell(s), one per chunk" % cells,
			(
				"scene %d bytes (floor paint record %d chars, %d generated brushes), .hflevel %d bytes"
				% [scene_bytes, paint_text, generated, level_bytes]
			)
		)
		await drop_root(root)
	var per_cell_scene: float = float(sizes[2][1] - sizes[0][1]) / 4.0
	var per_cell_level: float = float(sizes[2][2] - sizes[0][2]) / 4.0
	note("scene bytes per painted chunk", per_cell_scene)
	note(".hflevel bytes per painted chunk", per_cell_level)
