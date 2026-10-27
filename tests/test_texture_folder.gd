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


func test_a_resolution_or_format_after_the_suffix_is_passed_over_and_kept_in_the_name():
	# How texture packs name their files, the resolution after the map word. Kept
	# in the name, so a pack's 2k and 4k sets of one texture are two sets (#1960).
	assert_eq(
		HFTextureFolder.split_name("brick_wall_diff_2k.png"), ["brick_wall_2k", "albedo", false]
	)
	assert_eq(
		HFTextureFolder.split_name("brick_wall_nor_gl_2k.png"), ["brick_wall_2k", "normal", false]
	)
	assert_eq(
		HFTextureFolder.split_name("brick_wall_nor_dx_4K.jpg"), ["brick_wall_4K", "normal", true]
	)
	assert_eq(
		HFTextureFolder.split_name("rock_rough_16k-png.png"), ["rock_16k-png", "roughness", false]
	)
	assert_eq(HFTextureFolder.split_name("tile_2k.png"), ["tile_2k", "albedo", false])
	assert_eq(HFTextureFolder.split_name("normal_2k.png"), ["normal_2k", "albedo", false])


func test_longer_map_words_name_their_maps():
	assert_eq(
		HFTextureFolder.split_name("Bricks059_1K-PNG_Color.png"),
		["Bricks059_1K-PNG", "albedo", false]
	)
	assert_eq(
		HFTextureFolder.split_name("Bricks059_1K-PNG_AmbientOcclusion.png"),
		["Bricks059_1K-PNG", "ao", false]
	)
	assert_eq(
		HFTextureFolder.split_name("Bricks059_1K-PNG_Metalness.png"),
		["Bricks059_1K-PNG", "metallic", false]
	)
	assert_eq(
		HFTextureFolder.split_name("Bricks059_1K-PNG_NormalDX.png"),
		["Bricks059_1K-PNG", "normal", true]
	)
	assert_eq(HFTextureFolder.split_name("rock_Displacement.png"), ["rock", "unused", false])
	assert_eq(HFTextureFolder.split_name("rock_arm_2k.png"), ["rock_2k", "unused", false])


func test_a_pack_with_a_resolution_after_the_map_word_makes_one_material():
	var found := (
		HFTextureFolder
		. sets_of(
			[
				"brick_wall_diff_2k.png",
				"brick_wall_nor_gl_2k.png",
				"brick_wall_rough_2k.png",
				"brick_wall_ao_2k.png",
				"brick_wall_disp_2k.png",
			]
		)
	)
	assert_eq(found["sets"].size(), 1, "one material, not one a file")
	var brick: Dictionary = found["sets"][0]
	assert_eq(brick["name"], "brick_wall_2k")
	assert_eq(brick["albedo"], "brick_wall_diff_2k.png")
	assert_eq(brick["normal"], "brick_wall_nor_gl_2k.png")
	assert_eq(brick["roughness"], "brick_wall_rough_2k.png")
	assert_eq(brick["ao"], "brick_wall_ao_2k.png")
	assert_eq(found["unplaced"], [])
	assert_eq(found["unused"], ["brick_wall_disp_2k.png"], "a height map is seen and not used")


func test_a_pack_with_long_map_words_makes_one_material_with_all_four_maps():
	var found := (
		HFTextureFolder
		. sets_of(
			[
				"Bricks059_1K-PNG_Color.png",
				"Bricks059_1K-PNG_NormalGL.png",
				"Bricks059_1K-PNG_NormalDX.png",
				"Bricks059_1K-PNG_Roughness.png",
				"Bricks059_1K-PNG_AmbientOcclusion.png",
				"Bricks059_1K-PNG_Metalness.png",
				"Bricks059_1K-PNG_Displacement.png",
			]
		)
	)
	assert_eq(found["sets"].size(), 1)
	var brick: Dictionary = found["sets"][0]
	assert_eq(brick["albedo"], "Bricks059_1K-PNG_Color.png")
	assert_eq(brick["normal"], "Bricks059_1K-PNG_NormalGL.png", "the OpenGL normal map")
	assert_eq(brick["roughness"], "Bricks059_1K-PNG_Roughness.png")
	assert_eq(brick["ao"], "Bricks059_1K-PNG_AmbientOcclusion.png")
	assert_eq(brick["metallic"], "Bricks059_1K-PNG_Metalness.png")
	assert_eq(found["unplaced"], [])
	assert_eq(
		found["unused"],
		["Bricks059_1K-PNG_Displacement.png", "Bricks059_1K-PNG_NormalDX.png"],
		"the height map and the DirectX normal map are seen and not used"
	)
	assert_eq(found["directx"], [], "so there is no DirectX map to warn of")
	var other_way := HFTextureFolder.sets_of(["rock.png", "rock_normal.png", "rock_normal_dx.png"])
	assert_eq(other_way["sets"][0]["normal"], "rock_normal.png", "whichever comes first")
	assert_eq(other_way["unused"], ["rock_normal_dx.png"])


func test_a_plain_texture_whose_name_ends_in_a_map_word_is_an_albedo():
	var alone := HFTextureFolder.sets_of(["sheet_metal.png"])
	assert_eq(alone["sets"], [{"name": "sheet_metal", "albedo": "sheet_metal.png"}])
	assert_eq(alone["unplaced"], [])
	var several := HFTextureFolder.sets_of(
		["sheet_metal.png", "concrete_rough.png", "stone_col.png"]
	)
	assert_eq(several["sets"].size(), 3, "one material each")
	var named: Array = []
	for set_of in several["sets"]:
		named.append(set_of["name"])
	assert_eq(named, ["concrete_rough", "sheet_metal", "stone"], "each named for its file")
	var with_its_maps := HFTextureFolder.sets_of(
		["sheet_metal.png", "sheet_metal_normal.png", "sheet_metal_rough.png"]
	)
	assert_eq(with_its_maps["sets"].size(), 1, "a plain texture with maps of its own")
	var sheet: Dictionary = with_its_maps["sets"][0]
	assert_eq(sheet["name"], "sheet_metal")
	assert_eq(sheet["albedo"], "sheet_metal.png")
	assert_eq(sheet["normal"], "sheet_metal_normal.png")
	assert_eq(sheet["roughness"], "sheet_metal_rough.png")


func test_the_report_names_the_maps_not_used():
	assert_eq(
		(
			HFTextureFolder
			. report(
				{
					"made": 1,
					"reused": 0,
					"unplaced": [],
					"unused": ["brick_disp.png", "brick_arm.png"],
					"directx": [],
					"error": "",
				}
			)
		),
		"Add Texture Folder: 1 material made, 0 reused. Maps not used: brick_disp.png, brick_arm.png"
	)


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
