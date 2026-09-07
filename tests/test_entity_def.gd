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


# ===========================================================================
# Raw merged entries: what both dock pickers read (#175)
# ===========================================================================

var _plugin_defs_path := "user://hf_defs_plugin_test.json"
var _project_defs_path := "user://hf_defs_project_test.json"


func after_each():
	for path in [_plugin_defs_path, _project_defs_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write_json(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f = null
	return path


func _entry_by_id(entries: Array, id: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func test_raw_entries_keep_keys_the_typed_loader_drops():
	_write_json(
		_plugin_defs_path,
		'{"player_start": {"class": "Node3D", "label": "Player Start", "preview": {"type": "capsule"}}}'
	)
	var entries := HFEntityDef.load_raw_entries(_plugin_defs_path)
	assert_eq(entries.size(), 1)
	var entry := entries[0]
	assert_eq(str(entry.get("id", "")), "player_start")
	assert_eq(str(entry.get("label", "")), "Player Start", "The palette shows this")
	assert_true(entry.has("preview"), "The palette icon comes from this")


func test_raw_entries_from_a_top_level_array():
	_write_json(_project_defs_path, '[{"classname": "info_custom", "is_brush_entity": false}]')
	var entries := HFEntityDef.load_raw_entries(_project_defs_path)
	assert_eq(entries.size(), 1)
	assert_eq(str(entries[0].get("id", "")), "info_custom")


func test_raw_entries_missing_file_is_empty():
	assert_eq(HFEntityDef.load_raw_entries("user://hf_defs_nope.json").size(), 0)


func test_merged_raw_entries_include_project_only_point_entities():
	_write_json(_plugin_defs_path, '{"light_point": {"class": "OmniLight3D"}}')
	_write_json(
		_project_defs_path,
		'{"info_custom": {"class": "Node3D", "is_brush_entity": false}, "func_secret": {"is_brush_entity": true}}'
	)
	var merged := HFEntityDef.load_merged_raw_entries(_plugin_defs_path, _project_defs_path)
	assert_eq(merged.size(), 3)
	assert_false(_entry_by_id(merged, "info_custom").is_empty(), "Project point entity is present")
	assert_true(bool(_entry_by_id(merged, "func_secret").get("is_brush_entity", false)))


func test_merged_raw_entries_project_overrides_the_plugin_entry():
	_write_json(_plugin_defs_path, '{"light_point": {"label": "plugin"}}')
	_write_json(_project_defs_path, '{"light_point": {"label": "project"}}')
	var merged := HFEntityDef.load_merged_raw_entries(_plugin_defs_path, _project_defs_path)
	assert_eq(merged.size(), 1)
	assert_eq(str(merged[0].get("label", "")), "project")


func test_merged_raw_entries_keep_plugin_order_first():
	_write_json(_plugin_defs_path, '[{"id": "a"}, {"id": "b"}]')
	_write_json(_project_defs_path, '[{"id": "b"}, {"id": "c"}]')
	var merged := HFEntityDef.load_merged_raw_entries(_plugin_defs_path, _project_defs_path)
	var ids: Array = []
	for entry in merged:
		ids.append(str(entry.get("id", "")))
	assert_eq(ids, ["a", "b", "c"], "An override keeps its original slot")


func test_merged_raw_and_typed_loaders_agree_on_classnames():
	_write_json(_plugin_defs_path, '{"light_point": {"class": "OmniLight3D"}}')
	_write_json(
		_project_defs_path,
		'{"info_custom": {"is_brush_entity": false}, "func_secret": {"is_brush_entity": true}}'
	)
	var raw_ids: Array = []
	for entry in HFEntityDef.load_merged_raw_entries(_plugin_defs_path, _project_defs_path):
		raw_ids.append(str(entry.get("id", "")))
	var typed_ids: Array = []
	for def in HFEntityDef.load_merged_definitions(_plugin_defs_path, _project_defs_path):
		typed_ids.append(def.classname)
	raw_ids.sort()
	typed_ids.sort()
	assert_eq(raw_ids, typed_ids, "The two pickers must not disagree about what exists")
