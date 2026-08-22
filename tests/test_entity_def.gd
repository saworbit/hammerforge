extends GutTest

const HFEntityDef = preload("res://addons/hammerforge/hf_entity_def.gd")


func test_merge_overlay_replaces_matching_classname():
	var base: Array[HFEntityDef] = [
		HFEntityDef.from_dict({"classname": "light", "description": "plugin"}),
		HFEntityDef.from_dict({"classname": "player_start", "description": "plugin"}),
	]
	var overlay: Array[HFEntityDef] = [
		HFEntityDef.from_dict({"classname": "light", "description": "project"}),
		HFEntityDef.from_dict({"classname": "ammo", "description": "project-only"}),
	]
	var merged := HFEntityDef.merge_definitions(base, overlay)
	var by_name := {}
	for def in merged:
		by_name[def.classname] = def
	assert_eq(by_name.size(), 3)
	assert_eq(by_name["light"].description, "project")
	assert_eq(by_name["player_start"].description, "plugin")
	assert_eq(by_name["ammo"].description, "project-only")


func test_load_definitions_from_file_missing_is_empty():
	var defs := HFEntityDef.load_definitions_from_file("res://does_not_exist_entities.json")
	assert_eq(defs.size(), 0)


func test_project_path_constant():
	assert_eq(HFEntityDef.PROJECT_DEFINITIONS_PATH, "res://hammerforge_entities.json")
