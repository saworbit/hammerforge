@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Add Texture Folder makes of the names texture packs really use.
##
## `HFTextureFolder.sets_of()` groups a folder's images into one material per
## base name by the map word a file ends in (#1884). The tests feed it
## `brick_albedo.png` and friends. Downloaded packs name their files otherwise:
## a resolution or a format after the map word, longer map words, and plain
## albedo textures whose name happens to end in a map word. This feeds it those
## names and reads what it would make: how many materials, and which file each
## would wear as its albedo.

const HFTextureFolder = preload("res://addons/hammerforge/hf_texture_folder.gd")


func id() -> String:
	return "texture-folder"


func summary() -> String:
	return "what Add Texture Folder makes of the names texture packs really use"


func expected_issues() -> Array[int]:
	return [1960]


func run() -> void:
	_pack(
		"the documented names",
		["brick_albedo.png", "brick_normal.png", "brick_roughness.png", "tile.png"],
		2
	)
	_pack(
		"a resolution after the map word",
		[
			"brick_wall_diff_2k.png",
			"brick_wall_nor_gl_2k.png",
			"brick_wall_rough_2k.png",
			"brick_wall_ao_2k.png",
		],
		1
	)
	_pack(
		"a resolution and format before a long map word",
		[
			"Bricks059_1K-PNG_Color.png",
			"Bricks059_1K-PNG_NormalGL.png",
			"Bricks059_1K-PNG_Roughness.png",
			"Bricks059_1K-PNG_AmbientOcclusion.png",
			"Bricks059_1K-PNG_Metalness.png",
		],
		1
	)
	_pack(
		"plain albedo textures whose names end in a map word",
		["sheet_metal.png", "concrete_rough.png", "stone_col.png"],
		3
	)


## Feed `names` to `sets_of()` and say what it made; flag when the number of
## materials is not `expected`, or a map other than an albedo would be worn as
## one.
func _pack(label: String, names: Array, expected: int) -> void:
	var found: Dictionary = HFTextureFolder.sets_of(names)
	var sets: Array = found["sets"]
	var albedos: Array = []
	for set_of in sets:
		albedos.append(str((set_of as Dictionary).get("albedo", "")))
	note(
		label, "%d material(s), albedos %s, unplaced %s" % [sets.size(), albedos, found["unplaced"]]
	)
	var map_as_albedo: Array = []
	for albedo in albedos:
		var lower := str(albedo).to_lower()
		for word in ["nor", "normal", "rough", "ao", "occlusion", "metal", "disp"]:
			if lower.contains("_" + word):
				map_as_albedo.append(albedo)
				break
	if sets.size() != expected or not map_as_albedo.is_empty():
		known(
			1960,
			"Add Texture Folder: %s" % label,
			(
				"%s makes %d material(s) where %d was meant; %s would be worn as albedo, and %s is left out"
				% [names, sets.size(), expected, map_as_albedo, found["unplaced"]]
			)
		)
