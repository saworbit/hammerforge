extends SceneTree
## Measures the paint hot paths called out in issue #39.
##
## Issue #39 assumed `Image.get_pixel()` / `set_pixel()` were the bottleneck and
## proposed rewriting the loops over `PackedByteArray`. On Godot 4.7 that is not
## true — the packed rewrite measured ~7x *slower* for the composite — so the fix
## that shipped is memoisation instead. This script exists so both halves of that
## claim stay checkable:
##
##   * `primitives` compares the per-texel access costs directly.
##   * `composite` compares a cold `FaceData.get_painted_albedo()` against a
##     cache hit, which is the path `rebuild_preview()` takes.
##   * `sculpt` reports how `HFPaintTool._apply_terrain_brush` scales with radius.
##
## Usage:
##   godot --headless -s res://tools/benchmark_paint_hot_paths.gd --path .
##   godot --headless -s res://tools/benchmark_paint_hot_paths.gd --path . -- --size=512
##   godot --headless -s res://tools/benchmark_paint_hot_paths.gd --path . -- --repeats=5

const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const PaintLayerScript = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const PaintToolScript = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const StrokeScript = preload("res://addons/hammerforge/paint/hf_stroke.gd")

var _size := 256
var _repeats := 3

## Accumulator that keeps measured reads from being trivially discardable.
var _sink := 0


func _init() -> void:
	_parse_args(OS.get_cmdline_user_args())
	print("HammerForge paint hot-path benchmark (%dx%d, best of %d)" % [_size, _size, _repeats])
	print("")
	_bench_primitives()
	_bench_composite()
	_bench_sculpt()
	quit()


func _parse_args(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--size="):
			_size = maxi(8, int(arg.split("=")[1]))
		elif arg.begins_with("--repeats="):
			_repeats = maxi(1, int(arg.split("=")[1]))


# ===========================================================================
# Per-texel access primitives
# ===========================================================================


func _bench_primitives() -> void:
	print("per-texel primitives over %d texels" % (_size * _size))
	var img := Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.25, 0.75, 1.0))
	var data := img.get_data()
	print("  Image.get_pixel (RGBA)    : %8.3f ms" % _time(func(): _read_pixels(img)))
	print("  PackedByteArray (4 bytes) : %8.3f ms" % _time(func(): _read_bytes(data)))
	print("  Image.set_pixel (RGBA)    : %8.3f ms" % _time(func(): _write_pixels(img)))
	print("  PackedByteArray (4 bytes) : %8.3f ms" % _time(func(): _write_bytes(data)))
	print("  hash(Image.get_data())    : %8.3f ms" % _time(func(): _hash_data(img)))
	print("")


func _read_pixels(img: Image) -> void:
	var acc := 0.0
	for y in range(_size):
		for x in range(_size):
			acc += img.get_pixel(x, y).r
	_sink += int(acc)


func _read_bytes(data: PackedByteArray) -> void:
	var acc := 0.0
	for i in range(_size * _size):
		var o := i * 4
		acc += float(data[o]) + float(data[o + 1]) + float(data[o + 2]) + float(data[o + 3])
	_sink += int(acc)


func _write_pixels(img: Image) -> void:
	for y in range(_size):
		for x in range(_size):
			img.set_pixel(x, y, Color(0.1, 0.2, 0.3, 1.0))


func _write_bytes(data: PackedByteArray) -> void:
	for i in range(_size * _size):
		var o := i * 4
		data[o] = 1
		data[o + 1] = 2
		data[o + 2] = 3
		data[o + 3] = 4


func _hash_data(img: Image) -> void:
	_sink += hash(img.get_data())


# ===========================================================================
# FaceData.get_painted_albedo
# ===========================================================================


func _bench_composite() -> void:
	var face = _painted_face()
	var cold := _time(
		func():
			face.invalidate_painted_albedo()
			face.get_painted_albedo()
	)
	face.get_painted_albedo()
	var warm := _time(func(): face.get_painted_albedo())
	print("get_painted_albedo (1 layer)")
	print("  cold composite            : %8.3f ms" % cold)
	print("  cache hit                 : %8.3f ms" % warm)
	print("  speedup                   : %8.2fx" % (cold / maxf(warm, 0.0001)))
	print("")


func _painted_face() -> Resource:
	var face = FaceDataScript.new()
	var layer = FaceDataScript.PaintLayer.new()
	var tex_img := Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	tex_img.fill(Color(0.3, 0.6, 0.2, 1.0))
	layer.texture = ImageTexture.create_from_image(tex_img)
	layer.weight_image = Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	layer.weight_image.fill(Color(0.75, 0, 0, 1))
	face.paint_layers.append(layer)
	return face


# ===========================================================================
# HFPaintTool._apply_terrain_brush
# ===========================================================================


func _bench_sculpt() -> void:
	print("sculpt smooth stamp (heightmap %dx%d)" % [_size, _size])
	var paint_tool = PaintToolScript.new()
	paint_tool.tool = StrokeScript.Tool.SCULPT_SMOOTH
	paint_tool.sculpt_strength = 20.0
	paint_tool.sculpt_falloff = 0.5
	for radius in [8, 16, 32, 64]:
		paint_tool.sculpt_radius = float(radius)
		var layer = PaintLayerScript.new()
		layer.chunk_size = 32
		layer.heightmap = Image.create(_size, _size, false, Image.FORMAT_RF)
		layer.heightmap.fill(Color(0.5, 0, 0))
		var centre := Vector2i(_size / 2, _size / 2)
		var ms := _time(func(): paint_tool._apply_terrain_brush(layer, centre))
		print("  radius %-3d                : %8.3f ms" % [radius, ms])
		layer.free()
	paint_tool.free()
	print("")


# ===========================================================================
# Helpers
# ===========================================================================


func _time(fn: Callable) -> float:
	var best := INF
	for _i in range(_repeats):
		var start := Time.get_ticks_usec()
		fn.call()
		best = minf(best, float(Time.get_ticks_usec() - start) / 1000.0)
	return best
