@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The status board and the material palette it reports on.
##
## The board is the one place that tells a mapper whether the level is in a fit
## state, so a row that disagrees with the level is worse than no row: it is a
## reassurance. Each check here drives the level into a state and then compares
## what the board says against what is actually there.

const StatusBoard = preload("res://addons/hammerforge/hf_status_board.gd")


func id() -> String:
	return "status-board"


func summary() -> String:
	return "what the status board says against what the level is, and what a half-missing palette reports"


func run() -> void:
	await _the_board_through_a_bake()
	await _a_palette_whose_files_have_moved()
	await _a_library_file_that_is_not_shaped_like_one()


func _row(rows: Array, id_wanted: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == id_wanted:
			return row
	return {}


func _board(root: Node3D) -> Array:
	return StatusBoard.evaluate(StatusBoard.collect_context(root, null))


## Empty, drawn on, baked, then edited again.
func _the_board_through_a_bake() -> void:
	var root: Node3D = await fresh_root()
	await frame()

	var empty := _board(root)
	note("empty level, bake row", _row(empty, "bake").get("value", ""))
	note("empty level, geometry row", _row(empty, "geometry").get("value", ""))

	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var drawn := _board(root)
	note("one brush, bake row", _row(drawn, "bake").get("value", ""))

	await root.bake_dirty()
	await frame()
	var baked := _board(root)
	note("after a bake, bake row", _row(baked, "bake").get("value", ""))
	if str(_row(baked, "bake").get("value", "")) != "Up to date":
		flag(
			"the bake row does not say the level is baked straight after a bake",
			_row(baked, "bake")
		)

	# Edit the brush: the board should stop saying the bake matches the drafts.
	root.set_brush_transform_by_id(
		str(b.get_meta("brush_id", "")), Vector3(128, 64, 64), b.global_position
	)
	await frame()
	var edited := _board(root)
	note("after resizing a brush, bake row", _row(edited, "bake").get("value", ""))
	if str(_row(edited, "bake").get("value", "")) == "Up to date":
		flag(
			"the bake row still says the bake is up to date after a brush was resized",
			"the baked meshes are the old shape and play mode runs against them"
		)

	# And deleting everything after a bake.
	root.brush_system.delete_brush(b)
	await frame()
	await root.bake_dirty()
	await frame()
	var emptied := _board(root)
	note(
		"after deleting the only brush and rebaking, bake row",
		_row(emptied, "bake").get("value", "")
	)
	note("  brush count", root.brush_system.get_live_brush_count())


## A `.hfmaterials` library is a list of resource paths. Materials move.
func _a_palette_whose_files_have_moved() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()

	var path := "user://vibe_moved_palette.hfmaterials"
	HFVibe.write_text(
		path,
		(
			'{"version": 1, "materials": ["res://gone/a.tres", "res://gone/b.tres",'
			+ ' "res://gone/c.tres"]}'
		)
	)
	var mm = root.get_material_manager()
	var loaded = mm.load_library(path)
	note("load_library returned", loaded)
	note("palette slots after the load", mm.materials.size())
	var live := 0
	for mat in mm.materials:
		if mat != null:
			live += 1
	note("slots that actually resolved", live)
	if loaded and live == 0:
		known(
			414,
			"loading a palette whose files have all moved reports success and says nothing",
			(
				"load_library() appends a null for every path it cannot resolve -- right, since"
				+ " the indices have to stay stable -- and then returns true with no count of"
				+ (
					" what was dropped and no warning. The palette has %d slots and %d materials."
					% [mm.materials.size(), live]
				)
			)
		)

	var rows := _board(root)
	var materials_row := _row(rows, "materials")
	note(
		"status board materials row",
		"%s / %s" % [materials_row.get("value", ""), materials_row.get("detail", "")]
	)
	if str(materials_row.get("value", "")) == "Empty":
		known(
			415,
			"the status board calls a palette of missing materials empty",
			(
				"material_count only counts non-null slots, so three unresolved materials read"
				+ (
					" as an empty palette: '%s'. Every face that indexes one of those slots bakes"
					% str(materials_row.get("detail", ""))
				)
				+ " grey, and the board's advice is that this is fine for greyboxing."
			)
		)

	# What the level's own validator makes of it.
	var report: Dictionary = root.validation_system.validate(false)
	note("validate() issues with three missing materials", report.get("issues", []).size())
	for issue in report.get("issues", []):
		note("  issue", issue)


## The other way a `.hfmaterials` file goes wrong: the right JSON, the wrong
## shape. `load_library()` reads the list into a typed local.
func _a_library_file_that_is_not_shaped_like_one() -> void:
	var root: Node3D = await fresh_root()
	await frame()
	var mm = root.get_material_manager()
	var good := StandardMaterial3D.new()
	mm.add_material(good)
	note("palette before the load", mm.materials.size())

	var path := "user://vibe_bad_palette.hfmaterials"
	HFVibe.write_text(path, '{"version": 1, "materials": "res://a.tres"}')
	var returned = mm.load_library(path)
	note("load_library returned", returned)
	note("returned value is a bool", typeof(returned) == TYPE_BOOL)
	note("palette after the load", mm.materials.size())
	note("library path the manager now thinks it has", mm.get_library_path())
	if typeof(returned) != TYPE_BOOL:
		flag(
			"a .hfmaterials file whose materials key is not a list aborts load_library mid-call",
			(
				'`var mat_paths: Array = parsed.get("materials", [])` is a runtime error when'
				+ " the value is a String, so the function unwinds and a `-> bool` call returns"
				+ (
					" %s instead of false. Callers that test the result see a falsy value by luck"
					% str(returned)
				)
				+ " rather than by design, and nothing tells the user the file was unusable."
			)
		)

	# And the empty-but-valid case, for the contrast.
	HFVibe.write_text(path, '{"version": 1, "materials": []}')
	note("load_library on an empty list returned", mm.load_library(path))
	note("palette after loading an empty list", mm.materials.size())
