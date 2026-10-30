extends GutTest

## A paint layer's ground (#2007).
##
## The layer kept its terrain in one image read at `posmod(cell, width)`, so the
## ground repeated every width and a sculpt landed again a width away. A sculpt
## keeps samples per chunk now, and the ground elsewhere is the layer's base: an
## image placed at a cell, a noise field, or flat.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFHeightmapIO = preload("res://addons/hammerforge/paint/hf_heightmap_io.gd")

const PNG := "user://test_paint_heights.png"


func after_each() -> void:
	if FileAccess.file_exists(PNG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PNG))


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _flat(size: int, value: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	img.fill(Color(value, 0, 0))
	return img


func _ramp(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, Color(float(x + y * size) / 100.0, 0, 0))
	return img


func _raise(layer: HFPaintLayer, cell: Vector2i) -> HFPaintTool:
	var t: HFPaintTool = autofree(HFPaintTool.new())
	t.sculpt_radius = 4.0
	t.sculpt_strength = 20.0
	t.sculpt_falloff = 0.5
	t.tool = HFStroke.Tool.SCULPT_RAISE
	t._apply_terrain_brush(layer, cell)
	return t


func _layer(size: int = 32) -> HFPaintLayer:
	var layer: HFPaintLayer = autofree(HFPaintLayer.new())
	layer.chunk_size = size
	return layer


## The issue's own case: one Raise at cell (10, 2) on a 64 pixel map raised cell
## (74, 2) from 0.8 to 1.0 as well.
func test_a_sculpt_changes_only_the_ground_under_the_brush():
	var layer := _layer()
	layer.heightmap = _flat(64, 0.2)
	var flat := layer.get_height_sample(Vector2i(10, 2))
	_raise(layer, Vector2i(10, 2))
	assert_gt(layer.get_height_sample(Vector2i(10, 2)), flat, "the ground under the brush rises")
	for far in [Vector2i(74, 2), Vector2i(-54, 2), Vector2i(10, 66), Vector2i(74, 66)]:
		assert_eq(layer.get_height_sample(far), flat, "a width away it stays: %s" % far)


func test_a_sculpt_on_noise_changes_only_the_ground_under_the_brush():
	var layer := _layer()
	layer.set_height_noise({"seed": 4})
	var far := Vector2i(266, 2)
	var before := layer.get_height_sample(far)
	var under := layer.get_height_sample(Vector2i(10, 2))
	_raise(layer, Vector2i(10, 2))
	assert_gt(layer.get_height_sample(Vector2i(10, 2)), under, "the ground under the brush rises")
	assert_eq(layer.get_height_sample(far), before, "256 cells on it stays")


## The first change to a chunk fills it from the base. A corner of that chunk
## outside the brush keeps the height it had, so no step forms at its edge.
func test_a_sculpt_leaves_the_rest_of_its_chunks_where_they_were():
	var layer := _layer()
	layer.set_height_noise({"seed": 9, "frequency": 0.05})
	var before := {}
	for y in range(-8, 40):
		for x in range(-8, 40):
			before[Vector2i(x, y)] = layer.get_height_sample(Vector2i(x, y))
	# At a chunk's first column, so the brush reaches the chunks before it.
	_raise(layer, Vector2i(32, 30))
	assert_gt(layer.get_height_chunk_ids().size(), 1, "fixture: the brush spans chunks")
	var moved := []
	for corner: Vector2i in before:
		if corner.distance_to(Vector2i(32, 30)) <= 4.0:
			continue
		if layer.get_height_sample(corner) != before[corner]:
			moved.append(corner)
	assert_eq(moved, [], "only corners inside the brush moved")


## Generate Noise across the origin put a cliff along x = 0 and z = 0: cell -1
## read the image's last column. The steepest step over an axis is no steeper
## than one elsewhere.
func test_noise_ground_has_no_step_across_the_axes():
	var root := _fresh_root()
	root.grid_snap = 1
	root.generate_heightmap_noise({})
	root.set_heightmap_scale(4)
	var layer: HFPaintLayer = root.paint_layers.get_active_layer()
	var across := 0.0
	var elsewhere := 0.0
	for z in range(-16, 16):
		for x in range(-16, 15):
			var step := absf(
				layer.get_height_at(Vector2i(x + 1, z)) - layer.get_height_at(Vector2i(x, z))
			)
			if x == -1:
				across = maxf(across, step)
			else:
				elsewhere = maxf(elsewhere, step)
	assert_gt(elsewhere, 0.0, "fixture: the noise has relief")
	assert_lte(across, elsewhere, "the step across x = 0 is one the noise has elsewhere")


func test_noise_ground_does_not_repeat():
	var layer := _layer()
	layer.set_height_noise({})
	var same := 0
	for x in range(64):
		if layer.get_height_sample(Vector2i(x, 3)) == layer.get_height_sample(Vector2i(x + 256, 3)):
			same += 1
	assert_lt(same, 64, "the ground 256 cells on is other ground")
	assert_null(layer.heightmap, "noise is not kept as an image")
	assert_true(layer.has_heightmap(), "a noise layer builds terrain")


func test_a_placed_image_reads_its_nearest_edge_outside_it():
	var layer := _layer()
	var img := _ramp(4)
	layer.set_height_image(img, Vector2i(10, 10))
	assert_eq(layer.get_height_sample(Vector2i(10, 10)), img.get_pixel(0, 0).r, "its first pixel")
	assert_eq(layer.get_height_sample(Vector2i(13, 12)), img.get_pixel(3, 2).r, "inside it")
	assert_eq(layer.get_height_sample(Vector2i(30, 11)), img.get_pixel(3, 1).r, "past its edge")
	assert_eq(layer.get_height_sample(Vector2i(-5, -5)), img.get_pixel(0, 0).r, "before it")
	assert_eq(layer.get_height_sample(Vector2i(14, 10)), img.get_pixel(3, 0).r, "not repeated")


## Kept with each cell's pixel at `posmod(cell, size)`, the way a build from
## before #2007 reads it, so that build shows the ground right inside the image.
func test_a_placed_image_is_kept_where_an_older_build_reads_it():
	var layer := _layer()
	var img := _ramp(4)
	layer.set_height_image(img, Vector2i(5, -6))
	for y in range(4):
		for x in range(4):
			var cell := Vector2i(5 + x, -6 + y)
			assert_eq(
				layer.heightmap.get_pixel(posmod(cell.x, 4), posmod(cell.y, 4)).r,
				img.get_pixel(x, y).r,
				"cell %s" % cell
			)


func test_a_new_image_or_noise_clears_the_sculpts():
	var layer := _layer()
	layer.set_height_image(_flat(8, 0.5), Vector2i.ZERO)
	_raise(layer, Vector2i(3, 3))
	assert_false(layer.get_height_chunk_ids().is_empty(), "fixture: sculpted")
	layer.set_height_noise({})
	assert_true(layer.get_height_chunk_ids().is_empty(), "noise starts the ground again")
	_raise(layer, Vector2i(3, 3))
	layer.set_height_image(_flat(8, 0.5), Vector2i.ZERO)
	assert_true(layer.get_height_chunk_ids().is_empty(), "an image does too")
	assert_true(layer.get_height_noise().is_empty(), "and replaces the noise")


func test_a_sculpted_chunk_of_another_size_is_refused():
	var layer := _layer(16)
	assert_false(layer.set_height_chunk(Vector2i(0, 0), _flat(32, 0.5)), "32 square on 16")
	assert_true(layer.get_height_chunk_ids().is_empty(), "nothing kept")
	assert_true(layer.set_height_chunk(Vector2i(0, 0), _flat(16, 0.5)), "16 square on 16")


## Convert to Heightmap repeated the converted ground past its box. Past the box
## the ground is the margin's zero now.
func test_converted_ground_ends_at_its_box():
	var root := _fresh_root()
	root.grid_snap = 1
	var brush = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 2, 4), "center": Vector3(10, 1, 10)}
	)
	var settings := HFBrushToHeightmap.ConvertSettings.new()
	settings.cell_size = 1.0
	var result := HFBrushToHeightmap.new().convert([brush], settings)
	var layer: HFPaintLayer = autofree(result.layer)
	var size := result.heightmap.get_size()
	var top := result.cell_min + Vector2i(size.x / 2, size.y / 2)
	assert_gt(layer.get_height_at(top), 1.0, "the brush's top is there")
	assert_eq(layer.get_height_at(top + Vector2i(size.x, 0)), 0.0, "a box away it is not")
	assert_eq(layer.get_height_at(top - Vector2i(0, size.y)), 0.0, "on either side")


## An image imported onto painted ground starts at the painted ground's first
## cell, and repeats nowhere.
func test_an_import_lies_on_the_painted_ground():
	var root := _fresh_root()
	var png := Image.create(4, 4, false, Image.FORMAT_L8)
	png.set_pixel(0, 0, Color.WHITE)
	png.save_png(PNG)
	var layer: HFPaintLayer = root.paint_layers.get_active_layer()
	for cell in [Vector2i(40, -8), Vector2i(45, -2)]:
		layer.set_cell(cell, true)
	root.import_heightmap(PNG)
	assert_almost_eq(layer.get_height_sample(Vector2i(40, -8)), 1.0, 0.01, "on its first cell")
	assert_almost_eq(layer.get_height_sample(Vector2i(41, -8)), 0.0, 0.01, "beside it")
	assert_almost_eq(layer.get_height_sample(Vector2i(44, -8)), 0.0, 0.01, "not 4 cells on")
	assert_almost_eq(layer.get_height_sample(Vector2i(0, 0)), 0.0, 0.01, "nor at the origin")


func test_an_import_onto_unpainted_ground_starts_at_the_origin():
	var root := _fresh_root()
	var png := Image.create(4, 4, false, Image.FORMAT_L8)
	png.set_pixel(1, 2, Color.WHITE)
	png.save_png(PNG)
	root.import_heightmap(PNG)
	var layer: HFPaintLayer = root.paint_layers.get_active_layer()
	assert_almost_eq(
		layer.get_height_sample(Vector2i(1, 2)), 1.0, 0.01, "pixel (1, 2) at cell (1, 2)"
	)
	assert_almost_eq(layer.get_height_sample(Vector2i(5, 6)), 0.0, 0.01, "and nowhere else")


## The base and the sculpts go through the capture a save and an undo snapshot
## both take, and come back the same.
func test_the_ground_comes_back_from_a_save():
	var root := _fresh_root()
	var layer: HFPaintLayer = root.paint_layers.get_active_layer()
	layer.set_cell(Vector2i(3, 3), true)
	layer.set_height_image(_ramp(8), Vector2i(-3, 2))
	_raise(layer, Vector2i(0, 4))
	var second: HFPaintLayer = root.paint_layers.create_layer(&"hills", 0.0)
	second.set_height_noise({"seed": 11, "frequency": 0.03})
	_raise(second, Vector2i(100, -40))
	var corners := [Vector2i(0, 4), Vector2i(-3, 2), Vector2i(20, 20), Vector2i(-9, 30)]
	var before := []
	for each in [layer, second]:
		for corner in corners + [Vector2i(100, -40), Vector2i(300, 7)]:
			before.append(each.get_height_sample(corner))
	var saved: Array = root.state_system.capture_paint_layers()
	assert_true(saved[0].has("heightmap_origin"), "the image's place is saved")
	assert_true(saved[0].has("height_chunks"), "and its sculpt")
	assert_true(saved[1].has("heightmap_noise"), "the noise is saved as noise")
	assert_false(saved[1].has("heightmap_b64"), "not as an image")
	root.paint_system.restore_paint_layers(saved, 0)
	var after := []
	for each in root.paint_layers.layers:
		for corner in corners + [Vector2i(100, -40), Vector2i(300, 7)]:
			after.append(each.get_height_sample(corner))
	assert_eq(after, before, "every corner reads what it read")


## An undo puts back the snapshot taken before the stroke, and the sculpt goes
## with it.
func test_restoring_the_snapshot_before_a_sculpt_takes_the_sculpt_away():
	var root := _fresh_root()
	root.generate_heightmap_noise({"seed": 2})
	var layer: HFPaintLayer = root.paint_layers.get_active_layer()
	var flat := layer.get_height_sample(Vector2i(6, 6))
	var snapshot: Array = root.state_system.capture_paint_layers()
	_raise(layer, Vector2i(6, 6))
	assert_gt(layer.get_height_sample(Vector2i(6, 6)), flat, "fixture: sculpted")
	root.paint_system.restore_paint_layers(snapshot, 0)
	layer = root.paint_layers.get_active_layer()
	assert_eq(layer.get_height_sample(Vector2i(6, 6)), flat, "the ground is back")
	assert_true(layer.get_height_chunk_ids().is_empty(), "with no sculpt")


## A level saved before #2007 has an image and no place for it. It reads the way
## it was saved, repeating from cell (0, 0), and a sculpt on it still lands once.
func test_a_level_saved_before_keeps_its_ground():
	var root := _fresh_root()
	var img := _ramp(8)
	var entry := {
		"id": "layer_0",
		"chunk_size": 32,
		"height_scale": 1.0,
		"heightmap_b64": HFHeightmapIO.encode_to_base64(img),
		"chunks": [],
	}
	root.paint_system.restore_paint_layers([entry], 0)
	var layer: HFPaintLayer = root.paint_layers.get_active_layer()
	assert_eq(layer.get_height_sample(Vector2i(2, 3)), img.get_pixel(2, 3).r, "inside the image")
	assert_eq(layer.get_height_sample(Vector2i(10, 3)), img.get_pixel(2, 3).r, "8 on, as it was")
	assert_eq(layer.get_height_sample(Vector2i(-1, 0)), img.get_pixel(7, 0).r, "and before it")
	_raise(layer, Vector2i(2, 3))
	assert_eq(
		layer.get_height_sample(Vector2i(10, 3)), img.get_pixel(2, 3).r, "the sculpt lands once"
	)
	var saved: Array = root.state_system.capture_paint_layers()
	assert_false(saved[0].has("heightmap_origin"), "saved again, it still has no place")
	assert_eq(saved[0]["heightmap_b64"], entry["heightmap_b64"], "and the same image")


## A box of corners is read a chunk at a time. Across four chunks, one of them
## sculpted, it reads what each corner reads alone.
func test_a_box_of_corners_reads_what_each_corner_reads():
	var layer := _layer(8)
	layer.set_height_noise({"seed": 5, "frequency": 0.1})
	_raise(layer, Vector2i(9, 9))
	var from := Vector2i(3, -2)
	var size := Vector2i(11, 13)
	var box := layer.get_height_samples(from, size)
	var differ := []
	for y in range(size.y):
		for x in range(size.x):
			if box[y * size.x + x] != layer.get_height_sample(from + Vector2i(x, y)):
				differ.append(from + Vector2i(x, y))
	assert_eq(box.size(), size.x * size.y, "one sample a corner")
	assert_eq(differ, [], "every corner as it reads alone")
