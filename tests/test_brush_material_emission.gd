extends GutTest

## The Draw preview's cut look set `emission_energy`, Godot 4's deprecated alias
## for `emission_energy_multiplier`, which goes when Godot drops the alias (#1637).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func test_the_cut_preview_glows_through_the_current_property():
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	var mat: StandardMaterial3D = root.brush_system._make_brush_material(
		CSGShape3D.OPERATION_SUBTRACTION
	)
	assert_almost_eq(mat.emission_energy_multiplier, 0.2, 0.0001)


## No script of the addon names the old property.
func test_no_addon_script_names_the_deprecated_property():
	var pattern := RegEx.create_from_string("\\.emission_energy\\b(?!_multiplier)")
	var named: Array = []
	for path in _scripts_under("res://addons/hammerforge"):
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			named.append(path)
	assert_eq(named, [])
	assert_gt(_scripts_under("res://addons/hammerforge").size(), 100, "the scripts were read")


func _scripts_under(dir_path: String) -> Array:
	var found: Array = []
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".gd"):
			found.append(dir_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(dir_path):
		found.append_array(_scripts_under(dir_path.path_join(sub)))
	return found
