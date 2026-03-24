@tool
extends RefCounted
class_name HFPrototypeTextures
## Built-in prototype texture catalog for greyboxing and level layout testing.
##
## Provides 150 SVG textures (15 patterns x 10 colors) that ship with the
## plugin.  Use [method create_material] to build a [StandardMaterial3D] from
## any pattern/color pair, or [method load_all_into] to batch-populate a
## [MaterialManager] palette.

const BASE_DIR := "res://addons/hammerforge/textures/prototypes/"
const MATERIALS_DIR := "res://addons/hammerforge/textures/prototypes/materials/"

const PATTERNS: Array[String] = [
	"arrow_down",
	"arrow_left",
	"arrow_right",
	"arrow_up",
	"brick",
	"checker",
	"cross",
	"diamond",
	"dots",
	"hex",
	"solid",
	"stripes_diagonal",
	"stripes_horizontal",
	"triangles",
	"zigzag",
]

const COLORS: Array[String] = [
	"blue",
	"brown",
	"cyan",
	"green",
	"grey",
	"orange",
	"pink",
	"purple",
	"red",
	"yellow",
]


## Returns the resource path for a given pattern and color.
static func get_texture_path(pattern: String, color: String) -> String:
	return BASE_DIR + pattern + "_" + color + ".svg"


## Returns the resource path for a saved material .tres file.
static func get_material_path(pattern: String, color: String) -> String:
	return MATERIALS_DIR + "proto_" + pattern + "_" + color + ".tres"


## Returns [code]true[/code] if the texture resource exists on disk.
static func texture_exists(pattern: String, color: String) -> bool:
	return ResourceLoader.exists(get_texture_path(pattern, color))


## Loads and returns the [Texture2D] for a pattern/color pair, or [code]null[/code].
static func load_texture(pattern: String, color: String) -> Texture2D:
	var path := get_texture_path(pattern, color)
	if not ResourceLoader.exists(path):
		return null
	var res = ResourceLoader.load(path)
	if res is Texture2D:
		return res as Texture2D
	return null


## Loads a pre-built [StandardMaterial3D] from the shipped [code].tres[/code]
## files.  Each material has a stable [member Resource.resource_path] so it
## survives [code].hflevel[/code] serialization and material-library export.
## Returns [code]null[/code] if the material file does not exist.
static func create_material(pattern: String, color: String) -> StandardMaterial3D:
	var mat_path := get_material_path(pattern, color)
	if not ResourceLoader.exists(mat_path):
		return null
	var res = ResourceLoader.load(mat_path)
	if res is StandardMaterial3D:
		return res as StandardMaterial3D
	return null


## Batch-loads every prototype texture as a material into [param manager].
## Returns the number of materials added.
static func load_all_into(manager: MaterialManager) -> int:
	var count := 0
	for pattern in PATTERNS:
		for color in COLORS:
			var mat := create_material(pattern, color)
			if mat:
				manager.add_material(mat)
				count += 1
	return count


## Returns all 150 texture resource paths.
static func get_all_texture_paths() -> Array[String]:
	var paths: Array[String] = []
	for pattern in PATTERNS:
		for color in COLORS:
			paths.append(get_texture_path(pattern, color))
	return paths
