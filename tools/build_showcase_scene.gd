extends SceneTree
## Generate the HammerForge showcase level used for README and docs screenshots.
##
## The scene is authored as data below so the shot can be regenerated whenever
## brush defaults or the prototype texture set change. Brushes are built
## detached and packed directly, so _ready() never runs and no private mesh
## children leak into the saved scene (matching samples/hf_sample_minimal.tscn).
##
## Usage:
##   godot --headless -s res://tools/build_showcase_scene.gd --path .
##   godot --headless -s res://tools/build_showcase_scene.gd --path . -- --out=res://samples/other.tscn

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const BrushScript = preload("res://addons/hammerforge/brush_instance.gd")
const PROTO_DIR := "res://addons/hammerforge/textures/prototypes/"
const DEFAULT_OUT := "res://samples/hf_demo_showcase.tscn"

# name, shape, size, position, texture, uv scale, subtract
const LAYOUT := [
	# --- main hall ---
	["HallFloor", "BOX", Vector3(32, 1, 24), Vector3(0, -0.5, 0), "checker_grey", Vector2(8, 6)],
	[
		"HallWallNorth",
		"BOX",
		Vector3(32, 10, 1),
		Vector3(0, 5, -12.5),
		"brick_grey",
		Vector2(8, 2.5)
	],
	[
		"HallWallSouth",
		"BOX",
		Vector3(32, 10, 1),
		Vector3(0, 5, 12.5),
		"brick_grey",
		Vector2(8, 2.5)
	],
	[
		"HallWallWest",
		"BOX",
		Vector3(1, 10, 24),
		Vector3(-16.5, 5, 0),
		"brick_blue",
		Vector2(6, 2.5)
	],
	# East wall is split around a 5x6 doorway opening rather than carved with a
	# subtract brush. Both render identically; the split keeps the staged
	# sequence scenes readable as plain additive geometry.
	[
		"HallWallEastNorth",
		"BOX",
		Vector3(1, 10, 9.5),
		Vector3(16.5, 5, -7.25),
		"brick_grey",
		Vector2(3, 2.5)
	],
	[
		"HallWallEastSouth",
		"BOX",
		Vector3(1, 10, 9.5),
		Vector3(16.5, 5, 7.25),
		"brick_grey",
		Vector2(3, 2.5)
	],
	[
		"HallWallEastLintel",
		"BOX",
		Vector3(1, 4, 5),
		Vector3(16.5, 8, 0),
		"brick_grey",
		Vector2(2, 1)
	],
	# --- raised platform and ramp (north-west) ---
	["Platform", "BOX", Vector3(10, 3, 8), Vector3(-10, 1.5, -7), "brick_orange", Vector2(3, 1)],
	[
		"Ramp",
		"WEDGE",
		Vector3(6, 3, 8),
		Vector3(-2, 1.5, -7),
		"stripes_diagonal_yellow",
		Vector2(2, 1)
	],
	# --- pillars ---
	["PillarA", "CYLINDER", Vector3(2, 10, 2), Vector3(7, 5, -7), "dots_grey", Vector2(2, 3)],
	["PillarB", "CYLINDER", Vector3(2, 10, 2), Vector3(7, 5, 7), "dots_grey", Vector2(2, 3)],
	["PillarC", "CYLINDER", Vector3(2, 10, 2), Vector3(-7, 5, 7), "dots_grey", Vector2(2, 3)],
	# --- corridor east through the carved doorway ---
	[
		"CorridorFloor",
		"BOX",
		Vector3(14, 1, 6),
		Vector3(23.5, -0.5, 0),
		"checker_brown",
		Vector2(4, 2)
	],
	[
		"CorridorWallNorth",
		"BOX",
		Vector3(14, 10, 1),
		Vector3(23.5, 5, -3.5),
		"brick_brown",
		Vector2(4, 2.5)
	],
	[
		"CorridorWallSouth",
		"BOX",
		Vector3(14, 10, 1),
		Vector3(23.5, 5, 3.5),
		"brick_brown",
		Vector2(4, 2.5)
	],
	[
		"CorridorWallEnd",
		"BOX",
		Vector3(1, 10, 6),
		Vector3(30.5, 5, 0),
		"brick_red",
		Vector2(2, 2.5)
	],
]

# Subtract brushes carve the doorway. Kept separate so the cut reads clearly.
const CUTS := []

# Cumulative build stages for the how-it-works sequence. Each entry names the
# brushes present at that step, so the strip shows one level being built up
# rather than four unrelated screenshots.
const STAGES := [
	["hf_demo_step1", ["HallFloor"]],
	[
		"hf_demo_step2",
		[
			"HallFloor",
			"HallWallNorth",
			"HallWallSouth",
			"HallWallWest",
			"HallWallEastNorth",
			"HallWallEastSouth",
			"HallWallEastLintel",
		]
	],
	[
		"hf_demo_step3",
		[
			"HallFloor",
			"HallWallNorth",
			"HallWallSouth",
			"HallWallWest",
			"HallWallEastNorth",
			"HallWallEastSouth",
			"HallWallEastLintel",
			"Platform",
			"Ramp",
			"PillarA",
			"PillarB",
			"PillarC",
		]
	],
]


func _init() -> void:
	var out_path := DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg == "--help" or arg == "-h":
			_print_usage()
			quit(0)
			return
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")

	var root := Node3D.new()
	root.name = "LevelRoot"
	root.set_script(LevelRootScript)

	var draft := Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	draft.owner = root

	var built := 0
	for entry in LAYOUT:
		var brush := _make_brush(entry[0], entry[1], entry[2], entry[3], CSGShape3D.OPERATION_UNION)
		brush.material_override = _make_material(entry[4], entry[5])
		draft.add_child(brush)
		brush.owner = root
		built += 1

	for cut in CUTS:
		var brush := _make_brush(cut[0], cut[1], cut[2], cut[3], CSGShape3D.OPERATION_SUBTRACTION)
		draft.add_child(brush)
		brush.owner = root
		built += 1

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		printerr("Failed to pack showcase scene: error ", pack_err)
		quit(1)
		return

	var save_err := ResourceSaver.save(packed, out_path)
	if save_err != OK:
		printerr("Failed to save ", out_path, ": error ", save_err)
		quit(1)
		return

	root.free()
	var staged := 0
	for stage in STAGES:
		if _write_scene(str(stage[0]), stage[1]) == OK:
			staged += 1

	print("HammerForge showcase scene written")
	print("out=", out_path)
	print("brushes=", built, " (", LAYOUT.size(), " solid, ", CUTS.size(), " subtract)")
	print("stages=", staged, "/", STAGES.size())
	quit(0)


## Write a subset of LAYOUT as its own scene, used for the sequence strip.
## Returns an Error so the caller can count successes.
func _write_scene(scene_name: String, include: Array) -> Error:
	var root := Node3D.new()
	root.name = "LevelRoot"
	root.set_script(LevelRootScript)

	var draft := Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	draft.owner = root

	for entry in LAYOUT:
		if not include.has(entry[0]):
			continue
		var brush := _make_brush(entry[0], entry[1], entry[2], entry[3], CSGShape3D.OPERATION_UNION)
		brush.material_override = _make_material(entry[4], entry[5])
		draft.add_child(brush)
		brush.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.free()
		printerr("Failed to pack ", scene_name, ": error ", pack_err)
		return pack_err

	var path := "res://samples/" + scene_name + ".tscn"
	var save_err := ResourceSaver.save(packed, path)
	root.free()
	if save_err != OK:
		printerr("Failed to save ", path, ": error ", save_err)
		return save_err
	print("stage=", path)
	return OK


func _make_brush(
	node_name: String, shape_name: String, size: Vector3, pos: Vector3, operation: int
) -> Node3D:
	var brush := Node3D.new()
	brush.name = node_name
	brush.set_script(BrushScript)
	brush.shape = LevelRootScript.BrushShape[shape_name]
	brush.size = size
	brush.operation = operation
	brush.brush_id = node_name.to_snake_case()
	brush.position = pos
	return brush


func _make_material(texture_name: String, uv_scale: Vector2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex_path := PROTO_DIR + texture_name + ".svg"
	var tex := load(tex_path)
	if tex == null:
		printerr("Missing prototype texture: ", tex_path)
	else:
		mat.albedo_texture = tex
	mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 0.9
	return mat


func _print_usage() -> void:
	print("HammerForge showcase scene generator")
	print("  --out=PATH   Destination .tscn (default ", DEFAULT_OUT, ")")
	print("Example:")
	print("  godot --headless -s res://tools/build_showcase_scene.gd --path .")
