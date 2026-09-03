extends SceneTree
## Measures HFMaterialAtlas packing (issue #24).
##
##   * `gutter` compares the current `blit_rect` / `fill_rect` border fill against
##     the per-texel `get_pixel` / `set_pixel` loop it replaced.
##   * `build` reports `build_atlas()` end to end for albedo only against albedo
##     plus every PBR slot, so the cost of the parallel atlases is visible.
##
## Usage:
##   godot --headless -s res://tools/benchmark_bake_atlas.gd --path .
##   godot --headless -s res://tools/benchmark_bake_atlas.gd --path . -- --tiles=32
##   godot --headless -s res://tools/benchmark_bake_atlas.gd --path . -- --size=256

const AtlasScript = preload("res://addons/hammerforge/hf_material_atlas.gd")

var _tile_count := 16
var _tile_size := 128
var _repeats := 3


func _init() -> void:
	_parse_args(OS.get_cmdline_user_args())
	print(
		(
			"HammerForge atlas benchmark (%d tiles of %dpx, best of %d)"
			% [_tile_count, _tile_size, _repeats]
		)
	)
	print("")
	_bench_gutter()
	_bench_build()
	quit()


func _parse_args(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--tiles="):
			_tile_count = maxi(1, int(arg.split("=")[1]))
		elif arg.begins_with("--size="):
			_tile_size = maxi(4, int(arg.split("=")[1]))
		elif arg.begins_with("--repeats="):
			_repeats = maxi(1, int(arg.split("=")[1]))


# ===========================================================================
# Gutter fill
# ===========================================================================


func _bench_gutter() -> void:
	var gutter: int = AtlasScript.GUTTER
	var padded: int = _tile_size + gutter * 2
	var tile := Image.create(_tile_size, _tile_size, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0.4, 0.6, 0.8, 1.0))

	var blit_ms := _time(
		func():
			var atlas := Image.create(padded, padded, false, Image.FORMAT_RGBA8)
			atlas.blit_rect(tile, Rect2i(0, 0, _tile_size, _tile_size), Vector2i(gutter, gutter))
			AtlasScript._fill_gutter(atlas, tile, gutter, gutter, _tile_size, _tile_size)
	)
	var loop_ms := _time(
		func():
			var atlas := Image.create(padded, padded, false, Image.FORMAT_RGBA8)
			atlas.blit_rect(tile, Rect2i(0, 0, _tile_size, _tile_size), Vector2i(gutter, gutter))
			_legacy_fill_gutter(atlas, gutter, gutter, _tile_size, _tile_size)
	)
	print("gutter fill around one %dpx tile" % _tile_size)
	print("  get_pixel/set_pixel loop  : %8.3f ms" % loop_ms)
	print("  blit_rect/fill_rect       : %8.3f ms" % blit_ms)
	print("  speedup                   : %8.2fx" % (loop_ms / maxf(blit_ms, 0.0001)))
	print("")


## The pre-#24 implementation, kept here only as the comparison baseline.
func _legacy_fill_gutter(atlas: Image, cx: int, cy: int, tw: int, th: int) -> void:
	var gutter: int = AtlasScript.GUTTER
	for x in range(tw):
		var top_pixel: Color = atlas.get_pixel(cx + x, cy)
		var bot_pixel: Color = atlas.get_pixel(cx + x, cy + th - 1)
		for g in range(1, gutter + 1):
			atlas.set_pixel(cx + x, cy - g, top_pixel)
			atlas.set_pixel(cx + x, cy + th - 1 + g, bot_pixel)
	for y in range(-gutter, th + gutter):
		var sample_y: int = clampi(cy + y, cy, cy + th - 1)
		var left_pixel: Color = atlas.get_pixel(cx, sample_y)
		var right_pixel: Color = atlas.get_pixel(cx + tw - 1, sample_y)
		for g in range(1, gutter + 1):
			atlas.set_pixel(cx - g, cy + y, left_pixel)
			atlas.set_pixel(cx + tw - 1 + g, cy + y, right_pixel)


# ===========================================================================
# build_atlas
# ===========================================================================


func _bench_build() -> void:
	var albedo_only := _materials(false)
	var full_pbr := _materials(true)
	var albedo_ms := _time(func(): AtlasScript.build_atlas(albedo_only))
	var pbr_ms := _time(func(): AtlasScript.build_atlas(full_pbr))
	var sample = AtlasScript.build_atlas(full_pbr)
	print("build_atlas over %d materials" % _tile_count)
	print("  albedo only               : %8.3f ms" % albedo_ms)
	print("  albedo + 4 PBR slots      : %8.3f ms" % pbr_ms)
	print("  ratio                     : %8.2fx" % (pbr_ms / maxf(albedo_ms, 0.0001)))
	print("  channels packed           : %s" % str(sample.atlased_channels))
	print("  channels skipped          : %s" % str(sample.skipped_channels))
	print("")


func _materials(with_pbr: bool) -> Array:
	var out: Array = []
	for i in range(_tile_count):
		var shade := float(i) / float(maxi(1, _tile_count))
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _texture(Color(shade, 0.5, 1.0 - shade, 1.0))
		if with_pbr:
			mat.normal_enabled = true
			mat.normal_texture = _texture(Color(0.5, 0.5, 1.0, 1.0))
			mat.roughness_texture = _texture(Color(shade, shade, shade, 1.0))
			mat.metallic_texture = _texture(Color(shade, shade, shade, 1.0))
			mat.metallic = 1.0
			mat.emission_enabled = true
			mat.emission_texture = _texture(Color(shade, 0.0, 0.0, 1.0))
		out.append(mat)
	return out


func _texture(color: Color) -> ImageTexture:
	var img := Image.create(_tile_size, _tile_size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


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
