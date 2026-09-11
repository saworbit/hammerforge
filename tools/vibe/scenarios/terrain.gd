@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The heightmap layer and the region streaming settings around it, plus the two
## exports that take a finished level out of the editor.
##
## Terrain settings are numbers a mapper types into a dock: a scale, a layer
## height, a region size in cells, a memory budget in megabytes. Each one is
## arithmetic on the grid, so a zero or a negative is not a preference -- it is a
## division or an allocation that has to mean something.


func id() -> String:
	return "terrain"


func summary() -> String:
	return "heightmap scale and region settings at their edges, and the playtest/glTF exports"


func run() -> void:
	await _heightmap_settings()
	await _region_settings()
	await _missing_heightmap_file()
	await _exports()


func _heightmap_settings() -> void:
	var root: Node3D = await fresh_root()
	root.generate_heightmap_noise({})
	await frame()
	note("noise heightmap generated", "%d paint bytes" % root.get_paint_memory_bytes())
	for value in [0.0, -8.0, NAN, INF]:
		root.set_heightmap_scale(value)
		await frame()
		var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
		var stored = layer.height_scale if layer else null
		note("heightmap scale %s" % value, "stored as %s" % stored)
		if typeof(stored) == TYPE_FLOAT and not is_finite(stored):
			known(
				350,
				"the heightmap scale accepts %s" % value,
				"every height on the layer is multiplied by it, so the whole layer becomes non-finite"
			)
		if typeof(stored) == TYPE_FLOAT and stored == 0.0 and value == 0.0:
			known(
				350,
				"the heightmap scale accepts zero",
				"the layer flattens to nothing and the sculpt on it cannot be recovered by putting the scale back"
			)
	for value in [NAN, INF, -INF]:
		root.set_layer_y(value)
		await frame()
		var layer = root.paint_layers.get_active_layer() if root.paint_layers else null
		var stored = layer.grid.layer_y if layer and layer.grid else null
		note("layer Y %s" % value, "stored as %s" % stored)
		if typeof(stored) == TYPE_FLOAT and not is_finite(stored):
			known(
				350,
				"the paint layer height accepts %s" % value,
				"the layer's geometry is built at that Y, so it lands nowhere"
			)


func _region_settings() -> void:
	var root: Node3D = await fresh_root()
	root.set_region_streaming_enabled(true)
	await frame()
	for value in [0, -16, 1000000]:
		root.set_region_size_cells(value)
		await frame()
		var settings: Dictionary = root.get_region_settings()
		note("region size %d cells" % value, settings)
		var stored := int(settings.get("region_size_cells", -1))
		if stored <= 0 or stored > 65536:
			known(
				352,
				"the region size can be set to %d cells" % stored,
				"one region is that many cells square, so the streaming budget covers a single region"
			)
	for value in [0, -4, 100000]:
		root.set_region_streaming_radius(value)
		root.set_region_memory_budget_mb(value)
		await frame()
		var settings: Dictionary = root.get_region_settings()
		note("radius and budget %d" % value, settings)
		if int(settings.get("memory_budget_mb", 1)) <= 0:
			flag(
				(
					"the region memory budget can be set to %d MB"
					% int(settings.get("memory_budget_mb", 0))
				),
				"nothing can be held inside that budget, so streaming evicts whatever it loads"
			)


## Pointing the importer at files that are not a heightmap.
func _missing_heightmap_file() -> void:
	var root: Node3D = await fresh_root()
	HFVibe.write_text("user://vibe_not_an_image.png", "this is not a png")
	for path in ["user://vibe_missing.png", "user://vibe_not_an_image.png", ""]:
		root.import_heightmap(path)
		await frame()
		note("import_heightmap('%s')" % path, "%d paint bytes" % root.get_paint_memory_bytes())
	for problem in HFVibe.check_invariants(root):
		flag("a failed heightmap import broke an invariant", problem)


## The two ways a level leaves the editor.
func _exports() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(128, 32, 128))
	b.faces[0].material_idx = 7
	await frame()
	note("level health", root.get_level_health())
	note("missing dependencies", root.check_missing_dependencies())

	var gltf := "user://vibe_export.gltf"
	var gltf_err: int = root.export_baked_gltf(gltf)
	note(
		"export_baked_gltf with nothing baked",
		"returned error %d, wrote %d bytes" % [gltf_err, HFVibe.file_size(gltf)]
	)
	if gltf_err == OK and HFVibe.file_size(gltf) == 0:
		flag(
			"export_baked_gltf reports OK and writes no file",
			"nothing is baked, so there is nothing to export, but the caller is told it worked"
		)

	var scene := "user://vibe_playtest.tscn"
	var play_ok: bool = root.export_playtest_scene(scene)
	note(
		"export_playtest_scene", "returned %s, wrote %d bytes" % [play_ok, HFVibe.file_size(scene)]
	)
	if play_ok and HFVibe.file_size(scene) == 0:
		flag("export_playtest_scene reports success and writes no file", scene)
	for problem in HFVibe.check_invariants(root):
		flag("exporting broke an invariant", problem)
