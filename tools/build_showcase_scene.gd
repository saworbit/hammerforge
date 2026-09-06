extends SceneTree
## Generate the HammerForge showcase level used for README and docs screenshots.
##
## Built procedurally rather than as a flat table so the level can carry real
## architecture -- a colonnade, a galleried upper level, window bays -- instead
## of the handful of boxes a literal list encourages.
##
## The palette is deliberately restrained: greys carry the structure and a
## single warm accent marks the surfaces people walk on. A colour per brush
## reads as a texture swatch rather than a designed space.
##
## Openings are modelled as gaps between segments, never as subtract brushes.
## The editor screenshots show draft geometry, and an unbaked subtract renders
## as a solid box sitting in the hole it is meant to cut.
##
## Usage:
##   godot --headless -s res://tools/build_showcase_scene.gd --path .

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const BrushScript = preload("res://addons/hammerforge/brush_instance.gd")
const PROTO_DIR := "res://addons/hammerforge/textures/prototypes/"
const DEFAULT_OUT := "res://samples/hf_demo_showcase.tscn"

# Hall dimensions. Everything else derives from these.
const HALF_W := 24.0
const HALF_D := 32.0
const WALL_H := 26.0
const WALL_T := 2.0
const SILL := 8.0
const HEAD := 20.0
const COL_X := 14.0
const GALLERY_Y := 18.0

const STONE := "brick_grey"
const FLOOR := "checker_grey"
const SHAFT := "solid_grey"
const TRIM := "hex_grey"
const ACCENT := "brick_orange"

var _out: Array = []


func _init() -> void:
	var out_path := DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg == "--help" or arg == "-h":
			_print_usage()
			quit(0)
			return
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")

	# Stages double as the how-it-works strip: floor, walls, columns, detail.
	var stages := [
		["hf_demo_empty", []],
		["hf_demo_step1", ["floor"]],
		["hf_demo_step2", ["floor", "walls"]],
		["hf_demo_step3", ["floor", "walls", "colonnade"]],
	]
	var staged := 0
	for stage in stages:
		if _write_scene(str(stage[0]), _layout(stage[1])) == OK:
			staged += 1

	var full := _layout(["floor", "walls", "colonnade", "gallery", "dais", "towers"])
	if _write_scene_at(out_path, full) != OK:
		quit(1)
		return

	print("HammerForge showcase scene written")
	print("out=", out_path)
	print("brushes=", full.size())
	print("stages=", staged, "/", stages.size())
	quit(0)


## Assemble the brush list for the named parts, in build order.
func _layout(parts: Array) -> Array:
	_out = []
	if parts.has("floor"):
		_add(
			"Floor",
			"BOX",
			Vector3(HALF_W * 2.0, 1.0, HALF_D * 2.0),
			Vector3(0, -0.5, 0),
			FLOOR,
			Vector2(12, 16)
		)
	if parts.has("walls"):
		_build_side_wall(-HALF_W, "West")
		_build_side_wall(HALF_W, "East")
		_add(
			"WallNorth",
			"BOX",
			Vector3(HALF_W * 2.0, WALL_H, WALL_T),
			Vector3(0, WALL_H * 0.5, -HALF_D),
			STONE,
			Vector2(12, 6)
		)
		_build_entrance_wall()
	if parts.has("colonnade"):
		_build_colonnade()
	if parts.has("gallery"):
		_build_gallery(-1.0)
		_build_gallery(1.0)
	if parts.has("dais"):
		_build_dais()
	if parts.has("towers"):
		_build_towers()
	return _out


func _add(
	brush_name: String, shape: String, size: Vector3, pos: Vector3, tex: String, uv: Vector2
) -> void:
	_out.append([brush_name, shape, size, pos, tex, uv])


## A side wall as a solid base, a run of piers and a lintel above. The gaps
## between piers are the window bays.
func _build_side_wall(x: float, side: String) -> void:
	_add(
		"Wall%sBase" % side,
		"BOX",
		Vector3(WALL_T, SILL, HALF_D * 2.0),
		Vector3(x, SILL * 0.5, 0),
		STONE,
		Vector2(16, 2)
	)
	_add(
		"Wall%sLintel" % side,
		"BOX",
		Vector3(WALL_T, WALL_H - HEAD, HALF_D * 2.0),
		Vector3(x, (WALL_H + HEAD) * 0.5, 0),
		STONE,
		Vector2(16, 1.5)
	)
	var bays := 8
	for i in range(bays + 1):
		var z: float = -HALF_D + (HALF_D * 2.0) * float(i) / float(bays)
		_add(
			"Wall%sPier%d" % [side, i],
			"BOX",
			Vector3(WALL_T, HEAD - SILL, 4.0),
			Vector3(x, (SILL + HEAD) * 0.5, z),
			STONE,
			Vector2(1, 3)
		)


## South wall, split around a tall central entrance.
func _build_entrance_wall() -> void:
	var opening := 10.0
	var seg: float = (HALF_W * 2.0 - opening) * 0.5
	for s in [-1.0, 1.0]:
		var label := "West" if s < 0.0 else "East"
		_add(
			"Entrance%s" % label,
			"BOX",
			Vector3(seg, WALL_H, WALL_T),
			Vector3(s * (opening + seg) * 0.5, WALL_H * 0.5, HALF_D),
			STONE,
			Vector2(5, 6)
		)
	_add(
		"EntranceLintel",
		"BOX",
		Vector3(opening, WALL_H - 16.0, WALL_T),
		Vector3(0, (WALL_H + 16.0) * 0.5, HALF_D),
		TRIM,
		Vector2(3, 2)
	)


## Two rows of columns: base, shaft, capital. This is what makes the space read
## as architecture rather than as a room.
func _build_colonnade() -> void:
	for side in [-1.0, 1.0]:
		var label := "W" if side < 0.0 else "E"
		for i in range(7):
			var z: float = -24.0 + 8.0 * float(i)
			var x: float = side * COL_X
			_add(
				"Col%s%dBase" % [label, i],
				"BOX",
				Vector3(3.6, 1.0, 3.6),
				Vector3(x, 0.5, z),
				TRIM,
				Vector2(1, 1)
			)
			_add(
				"Col%s%dShaft" % [label, i],
				"CYLINDER",
				Vector3(2.6, 16.0, 2.6),
				Vector3(x, 9.0, z),
				SHAFT,
				Vector2(2, 4)
			)
			_add(
				"Col%s%dCap" % [label, i],
				"BOX",
				Vector3(3.9, 1.4, 3.9),
				Vector3(x, 17.7, z),
				TRIM,
				Vector2(1, 1)
			)


## Upper walkway over each aisle, with a balustrade on the open edge.
func _build_gallery(side: float) -> void:
	var label := "West" if side < 0.0 else "East"
	var width := 8.0
	var cx: float = side * (HALF_W - WALL_T * 0.5 - width * 0.5)
	_add(
		"Gallery%sFloor" % label,
		"BOX",
		Vector3(width, 1.0, HALF_D * 2.0),
		Vector3(cx, GALLERY_Y, 0),
		ACCENT,
		Vector2(2, 16)
	)
	_add(
		"Gallery%sRail" % label,
		"BOX",
		Vector3(0.8, 3.0, HALF_D * 2.0),
		Vector3(cx - side * (width * 0.5), GALLERY_Y + 2.0, 0),
		STONE,
		Vector2(16, 1)
	)


## Raised circular platform at the north end, approached by broad steps.
func _build_dais() -> void:
	_add("Dais", "CYLINDER", Vector3(18, 2, 18), Vector3(0, 1, -20), ACCENT, Vector2(3, 1))
	for i in range(3):
		_add(
			"DaisStep%d" % i,
			"BOX",
			Vector3(22.0 - 2.0 * float(i), 0.7, 2.0),
			Vector3(0, 0.35 + 0.7 * float(i), -10.0 - 2.0 * float(i)),
			TRIM,
			Vector2(6, 1)
		)


## Corner towers, for silhouette from outside.
func _build_towers() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var nx := "W" if sx < 0.0 else "E"
			var nz := "N" if sz < 0.0 else "S"
			_add(
				"Tower%s%s" % [nz, nx],
				"CYLINDER",
				Vector3(7, WALL_H + 6.0, 7),
				Vector3(sx * HALF_W, (WALL_H + 6.0) * 0.5, sz * HALF_D),
				STONE,
				Vector2(4, 6)
			)


func _write_scene(scene_name: String, entries: Array) -> Error:
	return _write_scene_at("res://samples/" + scene_name + ".tscn", entries)


func _write_scene_at(path: String, entries: Array) -> Error:
	var root := Node3D.new()
	root.name = "LevelRoot"
	root.set_script(LevelRootScript)
	var draft := Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	draft.owner = root

	for entry in entries:
		var brush := _make_brush(entry[0], entry[1], entry[2], entry[3])
		brush.material_override = _make_material(entry[4], entry[5])
		draft.add_child(brush)
		brush.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.free()
		printerr("Failed to pack ", path, ": error ", pack_err)
		return pack_err
	var save_err := ResourceSaver.save(packed, path)
	root.free()
	if save_err != OK:
		printerr("Failed to save ", path, ": error ", save_err)
		return save_err
	print("scene=", path, " brushes=", entries.size())
	return OK


func _make_brush(brush_name: String, shape_name: String, size: Vector3, pos: Vector3) -> Node3D:
	var brush := Node3D.new()
	brush.name = brush_name
	brush.set_script(BrushScript)
	brush.shape = LevelRootScript.BrushShape[shape_name]
	brush.size = size
	brush.operation = CSGShape3D.OPERATION_UNION
	brush.brush_id = brush_name.to_snake_case()
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
