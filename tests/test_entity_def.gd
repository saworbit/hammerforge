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


# ===========================================================================
# A definition file is data, not a whitelist (#690)
# ===========================================================================


func test_to_dict_carries_keys_the_model_does_not_model():
	# `root.entity_definitions` is built from `to_dict()`, and it was the only
	# writer, so anything this model had no field for never reached the level root
	# that reads it. `preview` is how an entity draws itself in the viewport and
	# `input_methods` is how a class says an input names an engine method; both
	# were written, both were read, and neither survived the trip.
	var def := (
		HFEntityDef
		. from_dict(
			{
				"classname": "logic_timer",
				"class": "Timer",
				"preview": {"type": "billboard", "path": "res://icon.svg"},
				"input_methods": {"Start": "start"},
				"some_future_key": 7,
			}
		)
	)
	var d := def.to_dict()
	assert_eq(d.get("preview", {}).get("type", ""), "billboard")
	assert_eq(d.get("input_methods", {}).get("Start", ""), "start")
	assert_eq(int(d.get("some_future_key", 0)), 7)


func test_to_dict_still_normalises_the_keys_it_owns():
	# The raw entry carries `class`, and reading it back first is what made
	# "light_point" come back as "OmniLight3D". The modelled keys have to win.
	var def := HFEntityDef.from_dict(
		{"id": "light_point", "class": "OmniLight3D", "description": "a lamp"}
	)
	var d := def.to_dict()
	assert_eq(d.get("classname"), "light_point", "the classname is the identity")
	assert_eq(d.get("class"), "OmniLight3D", "the node class stays beside it")
	assert_false(d.has("id"), "the spelling it came in under is not written back")


func test_the_shipped_library_keeps_its_previews_and_grants():
	var defs := HFEntityDef.load_definitions("res://addons/hammerforge/entities.json")
	var by_name := {}
	for def in defs:
		if def and def.classname != "":
			by_name[def.classname] = def.to_dict()
	assert_true(by_name.has("prop_static"), "the shipped library should load")
	assert_true(by_name["prop_static"].has("preview"), "prop_static draws itself with a preview")
	assert_eq(
		by_name["logic_timer"].get("input_methods", {}).get("Start", ""),
		"start",
		"logic_timer names the engine method behind its Start input"
	)
	assert_eq(by_name["prop_static"].get("scene_property", ""), "scene")
