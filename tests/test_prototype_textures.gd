extends GutTest

const HFProto = preload("res://addons/hammerforge/hf_prototype_textures.gd")
const MaterialManagerScript = preload("res://addons/hammerforge/material_manager.gd")

# ===========================================================================
# Catalog constants
# ===========================================================================


func test_patterns_count():
	assert_eq(HFProto.PATTERNS.size(), 15, "expected 15 patterns")


func test_colors_count():
	assert_eq(HFProto.COLORS.size(), 10, "expected 10 colors")


func test_patterns_sorted():
	var sorted := HFProto.PATTERNS.duplicate()
	sorted.sort()
	assert_eq(HFProto.PATTERNS, sorted, "PATTERNS should be alphabetically sorted")


func test_colors_sorted():
	var sorted := HFProto.COLORS.duplicate()
	sorted.sort()
	assert_eq(HFProto.COLORS, sorted, "COLORS should be alphabetically sorted")


func test_known_patterns_present():
	var expected := ["solid", "brick", "checker", "hex", "zigzag"]
	for p in expected:
		assert_true(HFProto.PATTERNS.has(p), "PATTERNS should contain '%s'" % p)


func test_known_colors_present():
	var expected := ["red", "blue", "green", "grey", "yellow"]
	for c in expected:
		assert_true(HFProto.COLORS.has(c), "COLORS should contain '%s'" % c)


# ===========================================================================
# Path generation
# ===========================================================================


func test_get_texture_path_format():
	var path := HFProto.get_texture_path("checker", "red")
	assert_eq(
		path,
		"res://addons/hammerforge/textures/prototypes/checker_red.svg",
		"path should follow pattern_color.svg convention",
	)


func test_get_material_path_format():
	var path := HFProto.get_material_path("checker", "red")
	assert_eq(
		path,
		"res://addons/hammerforge/textures/prototypes/materials/proto_checker_red.tres",
		"material path should follow proto_pattern_color.tres convention",
	)


func test_get_texture_path_starts_with_base_dir():
	for pattern in HFProto.PATTERNS:
		for color in HFProto.COLORS:
			var path := HFProto.get_texture_path(pattern, color)
			assert_true(
				path.begins_with(HFProto.BASE_DIR),
				"path should begin with BASE_DIR: %s" % path,
			)


func test_get_texture_path_ends_with_svg():
	for pattern in HFProto.PATTERNS:
		for color in HFProto.COLORS:
			var path := HFProto.get_texture_path(pattern, color)
			assert_true(path.ends_with(".svg"), "path should end with .svg: %s" % path)


func test_get_all_texture_paths_count():
	assert_eq(HFProto.get_all_texture_paths().size(), 150, "should return 150 paths")


func test_get_all_texture_paths_no_duplicates():
	var paths := HFProto.get_all_texture_paths()
	var unique := {}
	for p in paths:
		unique[p] = true
	assert_eq(unique.size(), 150, "all 150 paths should be unique")


func test_get_all_texture_paths_matches_manual_iteration():
	var manual: Array[String] = []
	for pattern in HFProto.PATTERNS:
		for color in HFProto.COLORS:
			manual.append(HFProto.get_texture_path(pattern, color))
	assert_eq(HFProto.get_all_texture_paths(), manual, "get_all should match manual loop")


# ===========================================================================
# Resource loading (requires textures imported by Godot)
# ===========================================================================


func _skip_if_textures_missing() -> bool:
	if not ResourceLoader.exists(HFProto.get_texture_path("solid", "blue")):
		pass_test("Skipped: prototype textures not imported")
		return true
	return false


func test_texture_exists_valid():
	if _skip_if_textures_missing():
		return
	assert_true(HFProto.texture_exists("solid", "blue"), "solid_blue should exist")


func test_texture_exists_all():
	if _skip_if_textures_missing():
		return
	for pattern in HFProto.PATTERNS:
		for color in HFProto.COLORS:
			assert_true(
				HFProto.texture_exists(pattern, color),
				"should exist: %s_%s" % [pattern, color],
			)


func test_texture_exists_invalid_pattern():
	assert_false(
		HFProto.texture_exists("nonexistent", "blue"),
		"nonexistent pattern should return false",
	)


func test_texture_exists_invalid_color():
	assert_false(
		HFProto.texture_exists("solid", "neon"),
		"nonexistent color should return false",
	)


func test_load_texture_valid():
	if _skip_if_textures_missing():
		return
	var tex := HFProto.load_texture("solid", "blue")
	assert_not_null(tex, "load_texture should return a texture")
	assert_true(tex is Texture2D, "loaded resource should be Texture2D")


func test_load_texture_invalid():
	var tex := HFProto.load_texture("nonexistent", "blue")
	assert_null(tex, "invalid pattern should return null")


func test_create_material_valid():
	if _skip_if_textures_missing():
		return
	var mat := HFProto.create_material("checker", "green")
	assert_not_null(mat, "create_material should return a material")
	assert_true(mat is StandardMaterial3D, "should be StandardMaterial3D")
	assert_eq(mat.resource_name, "proto_checker_green", "resource_name format")
	assert_not_null(mat.albedo_texture, "albedo_texture should be set")


func test_create_material_resource_name_format():
	if _skip_if_textures_missing():
		return
	for pattern in ["solid", "brick", "hex"]:
		for color in ["red", "blue"]:
			var mat := HFProto.create_material(pattern, color)
			assert_eq(
				mat.resource_name,
				"proto_%s_%s" % [pattern, color],
				"resource_name for %s_%s" % [pattern, color],
			)


func test_create_material_has_resource_path():
	if _skip_if_textures_missing():
		return
	var mat := HFProto.create_material("solid", "red")
	assert_not_null(mat, "create_material should return a material")
	assert_ne(mat.resource_path, "", "material must have a resource_path for serialization")
	assert_eq(
		mat.resource_path,
		HFProto.get_material_path("solid", "red"),
		"resource_path should match get_material_path",
	)


func test_create_material_idempotent():
	if _skip_if_textures_missing():
		return
	var mat1 := HFProto.create_material("brick", "blue")
	var mat2 := HFProto.create_material("brick", "blue")
	assert_eq(
		mat1.resource_path,
		mat2.resource_path,
		"calling create_material twice should return same resource_path",
	)


func test_create_material_invalid():
	var mat := HFProto.create_material("nonexistent", "blue")
	assert_null(mat, "invalid pattern should return null")


func test_load_all_into_populates_manager():
	if _skip_if_textures_missing():
		return
	var mm: MaterialManager = autofree(MaterialManagerScript.new())
	var count := HFProto.load_all_into(mm)
	assert_eq(count, 150, "should load 150 materials")
	assert_eq(mm.materials.size(), 150, "manager should contain 150 materials")


func test_load_all_into_material_names():
	if _skip_if_textures_missing():
		return
	var mm: MaterialManager = autofree(MaterialManagerScript.new())
	HFProto.load_all_into(mm)
	var names: Array[String] = mm.get_material_names()
	for n in names:
		assert_true(
			n.begins_with("proto_"),
			"all material names should start with 'proto_': %s" % n,
		)


func test_load_all_into_empty_manager_starts_clean():
	if _skip_if_textures_missing():
		return
	var mm: MaterialManager = autofree(MaterialManagerScript.new())
	assert_eq(mm.materials.size(), 0, "fresh manager should be empty")
	HFProto.load_all_into(mm)
	assert_eq(mm.materials.size(), 150, "after load should have 150")
