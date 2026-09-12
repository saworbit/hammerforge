@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The heightmap as it goes into a saved level and comes back out.
##
## A heightmap is a 32-bit float image and the `.hflevel` carries it as a
## base64 PNG, so the interesting question is what survives that. The scenario
## puts known float values in, takes them out again, and measures the difference
## in the world units the mapper actually sees.

const HeightmapIO = preload("res://addons/hammerforge/paint/hf_heightmap_io.gd")


func id() -> String:
	return "heightmap-io"


func summary() -> String:
	return "what a heightmap loses going through the .hflevel's base64 PNG, measured in world units"


func run() -> void:
	await _the_base64_round_trip()
	await _through_a_real_level_save()


func _ramp_image(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	for y in range(size):
		for x in range(size):
			# A gentle ramp: the values a sculpted hillside actually holds.
			img.set_pixel(x, y, Color(float(x) / float(size * 8), 0.0, 0.0, 1.0))
	return img


func _the_base64_round_trip() -> void:
	var size := 64
	var before := _ramp_image(size)
	note("source format", before.get_format())
	note("source value at (1,0)", before.get_pixel(1, 0).r)
	note("source value at (2,0)", before.get_pixel(2, 0).r)

	var encoded := HeightmapIO.encode_to_base64(before)
	note("base64 length", encoded.length())
	var after := HeightmapIO.decode_from_base64(encoded)
	if after == null:
		flag("a heightmap could not be decoded back out of its own encoding")
		return
	note("decoded format", after.get_format())

	var worst := 0.0
	var distinct_before: Dictionary = {}
	var distinct_after: Dictionary = {}
	for x in range(size):
		var a := before.get_pixel(x, 0).r
		var b := after.get_pixel(x, 0).r
		distinct_before[snappedf(a, 0.0000001)] = true
		distinct_after[snappedf(b, 0.0000001)] = true
		worst = maxf(worst, absf(a - b))
	note("distinct values along the ramp, before", distinct_before.size())
	note("distinct values along the ramp, after", distinct_after.size())
	note("worst error in normalised units", worst)

	# What that is on the ground, at the default height scale.
	var height_scale := 10.0
	note("worst error at height_scale %s" % height_scale, worst * height_scale)

	if distinct_after.size() < distinct_before.size():
		known(
			445,
			"saving a level quantises the heightmap to 8 bits per sample",
			(
				"HFHeightmapIO.encode_to_base64() calls save_png_to_buffer() on a FORMAT_RF "
				+ "image. PNG has no 32-bit float channel, so Godot writes it as 8-bit and "
				+ (
					"decode_from_base64() converts the 8-bit result back to RF. A %d-step ramp "
					% distinct_before.size()
				)
				+ (
					"came back with %d distinct values, worst error %s, which is %s world units "
					% [distinct_after.size(), worst, worst * height_scale]
				)
				+ (
					"at height_scale %s. Every sculpted slope reloads as a staircase, and the "
					% height_scale
				)
				+ "damage compounds on each save/load because the quantised values are what "
				+ "gets re-encoded"
			)
		)

	# And what happens above 1.0, which an imported or sculpted map can hold.
	var tall := Image.create(4, 4, false, Image.FORMAT_RF)
	tall.set_pixel(0, 0, Color(4.5, 0, 0, 1))
	tall.set_pixel(1, 0, Color(-2.0, 0, 0, 1))
	var tall_back := HeightmapIO.decode_from_base64(HeightmapIO.encode_to_base64(tall))
	if tall_back:
		note("4.5 came back as", tall_back.get_pixel(0, 0).r)
		note("-2.0 came back as", tall_back.get_pixel(1, 0).r)
		if not is_equal_approx(tall_back.get_pixel(0, 0).r, 4.5):
			known(
				445,
				"a heightmap sample outside 0..1 does not survive a save at all",
				(
					(
						"4.5 came back as %s and -2.0 as %s. The 8-bit PNG round trip clamps as "
						% [tall_back.get_pixel(0, 0).r, tall_back.get_pixel(1, 0).r]
					)
					+ "well as quantises, so anything a sculpt pushed above or below the unit "
					+ "range is flattened to the limit on the next save"
				)
			)


## The same trip through capture_state / restore_state on a real level.
func _through_a_real_level_save() -> void:
	var root: Node3D = await fresh_root()
	var layer = root.paint_layers.get_active_layer()
	layer.heightmap = _ramp_image(64)
	layer.height_scale = 10.0
	for y in range(4):
		for x in range(8):
			layer.set_cell(Vector2i(x, y), true)
	await frame()

	var before: Array = []
	for x in range(8):
		before.append(snappedf(layer.get_height_at(Vector2i(x, 0)), 0.00001))
	note("world heights before the save", before)

	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	await frame()

	var restored = root.paint_layers.get_active_layer()
	var after: Array = []
	for x in range(8):
		after.append(snappedf(restored.get_height_at(Vector2i(x, 0)), 0.00001))
	note("world heights after capture/restore", after)
	if before != after:
		known(
			445,
			"a capture_state / restore_state round trip moves the terrain",
			(
				(
					"the same eight cells read %s before and %s after. The heightmap goes through "
					% [str(before), str(after)]
				)
				+ "HFHeightmapIO.encode_to_base64() in HFStateSystem, which is the same 8-bit "
				+ "PNG trip -- so this is not only the .hflevel on disk, it is every undo that "
				+ "restores level state"
			)
		)
