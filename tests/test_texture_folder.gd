extends GutTest

## Add Texture Folder (#1884): every image in a folder ends up in the palette as
## a material, files that share a base name and end in a map's name made one
## material with each map set, as one undo step. A pack of 40 textures used to
## be 40 materials made by hand in the Inspector.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFTextureFolder = preload("res://addons/hammerforge/hf_texture_folder.gd")

## brick_albedo, brick_normal, brick_roughness and tile, 8 x 8 each.
const FOLDER := "res://tests/fixtures/texture_folder"

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func before_each():
	_empty_output()


## The materials a run wrote go into this run's own folder, emptied before each
## test so a test that expects them made does not find them there.
func _empty_output() -> void:
	var dir: String = HFTextureFolder.write_dir
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


func _named(materials: Array, wanted: String) -> StandardMaterial3D:
	for material in materials:
		if material is StandardMaterial3D and material.resource_name == wanted:
			return material
	return null


# ---------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------


func test_a_suffix_names_the_map_whatever_the_case_and_separator():
	assert_eq(HFTextureFolder.split_name("brick_albedo.png"), ["brick", "albedo", false])
	assert_eq(HFTextureFolder.split_name("Brick-Normal.PNG"), ["Brick", "normal", false])
	assert_eq(HFTextureFolder.split_name("old brick ROUGH.jpg"), ["old brick", "roughness", false])
	assert_eq(
		HFTextureFolder.split_name("metal_plate-Metallic.png"), ["metal_plate", "metallic", false]
	)
	assert_eq(HFTextureFolder.split_name("rock_AO.tga"), ["rock", "ao", false])
	assert_eq(HFTextureFolder.split_name("rock_occlusion.png"), ["rock", "ao", false])
	assert_eq(HFTextureFolder.split_name("rock_nrm.png"), ["rock", "normal", false])


func test_two_word_suffixes_are_read_as_one():
	assert_eq(HFTextureFolder.split_name("brick_base_color.png"), ["brick", "albedo", false])
	assert_eq(HFTextureFolder.split_name("brick_Normal_GL.png"), ["brick", "normal", false])
	assert_eq(HFTextureFolder.split_name("brick_normal-dx.png"), ["brick", "normal", true])
	assert_eq(HFTextureFolder.split_name("brick_NormalDX.png"), ["brick", "normal", true])


func test_a_file_with_no_known_suffix_is_an_albedo_named_for_the_whole_file():
	assert_eq(HFTextureFolder.split_name("tile.png"), ["tile", "albedo", false])
	assert_eq(HFTextureFolder.split_name("tile_02.png"), ["tile_02", "albedo", false])
	assert_eq(HFTextureFolder.split_name("normal.png"), ["normal", "albedo", false])


func test_files_are_sorted_into_sets_and_the_rest_are_named():
	var found := (
		HFTextureFolder
		. sets_of(
			[
				"Brick_Albedo.png",
				"brick-normal.png",
				"brick roughness.png",
				"brick.png",
				"tile.png",
				"moss_normal_dx.png",
				"moss.jpg",
				"lonely_normal.png",
				"notes.txt",
				"brick_albedo.png.import",
			]
		)
	)
	var sets: Array = found["sets"]
	assert_eq(sets.size(), 3, "brick, moss and tile")
	var brick: Dictionary = sets[0]
	assert_eq(
		brick["name"], "Brick_Albedo".trim_suffix("_Albedo"), "named as its first file has it"
	)
	assert_eq(brick["albedo"], "Brick_Albedo.png")
	assert_eq(brick["normal"], "brick-normal.png")
	assert_eq(brick["roughness"], "brick roughness.png")
	assert_eq(
		found["unplaced"], ["brick.png", "lonely_normal.png"], "a second albedo, and no albedo"
	)
	assert_eq(found["directx"], ["moss_normal_dx.png"], "a DirectX normal map is named")


# ---------------------------------------------------------------------------
# A folder
# ---------------------------------------------------------------------------


func test_a_folder_adds_one_material_a_set_with_its_maps():
	var built := HFTextureFolder.build(FOLDER)
	assert_eq(built["error"], "")
	assert_eq(built["made"], 2, "brick and tile")
	var brick := _named(built["materials"], "brick")
	assert_not_null(brick, "a brick")
	assert_not_null(brick.albedo_texture, "with its albedo")
	assert_true(brick.normal_enabled, "its normal map on")
	assert_eq(brick.normal_texture.resource_path, FOLDER.path_join("brick_normal.png"))
	assert_eq(brick.roughness_texture.resource_path, FOLDER.path_join("brick_roughness.png"))
	var tile := _named(built["materials"], "tile")
	assert_not_null(tile, "and a tile")
	assert_eq(tile.albedo_texture.resource_path, FOLDER.path_join("tile.png"))
	assert_false(tile.normal_enabled, "with only its albedo")
	assert_null(tile.roughness_texture)
	# Written as files, so each keeps a path through a save and the library.
	assert_eq(brick.resource_path, HFTextureFolder.write_dir.path_join("brick.tres"))
	var loaded = ResourceLoader.load(brick.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(loaded is StandardMaterial3D, "read back from its file")
	assert_eq(loaded.normal_texture.resource_path, FOLDER.path_join("brick_normal.png"))


func test_the_dock_adds_a_folder_as_one_undo_step_and_a_second_run_adds_nothing():
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new()])
	var undo = rig.undo()
	undo.clear()
	var dock = rig.plugin.dock
	var first: Dictionary = dock.add_texture_folder(FOLDER)
	assert_eq(level.get_materials().size(), 3, "two materials join the palette")
	assert_eq(undo.step_count(), 1, "in one step")
	assert_has(rig.toasts(), "Add Texture Folder: 2 materials made, 0 reused")
	var second: Dictionary = dock.add_texture_folder(FOLDER)
	assert_eq(second["reused"], 2, "the files written the first time are used again")
	assert_eq(level.get_materials().size(), 3, "and the palette gains nothing")
	assert_eq(undo.step_count(), 1, "nor the history")
	assert_has(rig.toasts(), "Add Texture Folder: 0 materials made, 2 reused")
	undo.press_undo()
	assert_eq(level.get_materials().size(), 1, "one undo takes out all the folder added")
	assert_eq(first["materials"].size(), 2)
	await rig.leave_level(level)


func test_a_folder_that_is_not_there_says_so():
	var built := HFTextureFolder.build("res://tests/fixtures/no_such_folder")
	assert_eq(built["materials"], [])
	assert_eq(
		HFTextureFolder.report(built),
		"Add Texture Folder: no folder at res://tests/fixtures/no_such_folder"
	)
