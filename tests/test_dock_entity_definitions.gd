extends GutTest
## The point entity palette and the brush entity dropdown have to agree about
## which definitions exist, including a project overlay. See #175.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFEntityDef = preload("res://addons/hammerforge/hf_entity_def.gd")

var dock: HammerForgeDock
var _defs_path := "user://hf_dock_defs_test.json"


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)


func after_each() -> void:
	dock = null
	if FileAccess.file_exists(_defs_path):
		DirAccess.remove_absolute(_defs_path)


func _write_defs(text: String) -> void:
	var f := FileAccess.open(_defs_path, FileAccess.WRITE)
	f.store_string(text)
	f = null


func _palette_ids() -> Array:
	var ids: Array = []
	for button in dock.entity_palette_buttons:
		ids.append(str(button.entity_id))
	return ids


func _brush_class_names() -> Array:
	var names: Array = []
	for i in range(dock.brush_entity_class_opt.item_count):
		names.append(dock.brush_entity_class_opt.get_item_text(i))
	return names


func test_custom_point_entity_reaches_the_palette():
	_write_defs('{"info_custom": {"class": "Node3D", "is_brush_entity": false}}')
	dock.entity_defs_path = _defs_path
	dock._load_entity_definitions()
	assert_true(_palette_ids().has("info_custom"), "A project point entity must be placeable")


func test_custom_brush_entity_reaches_the_dropdown_and_not_the_palette():
	_write_defs('{"func_secret": {"is_brush_entity": true}}')
	dock.entity_defs_path = _defs_path
	dock._load_entity_definitions()
	assert_true(_brush_class_names().has("func_secret"), "Brush classes come from the dropdown")
	assert_false(
		_palette_ids().has("func_secret"), "A brush entity is not placed from the point palette"
	)


func test_both_pickers_read_the_same_definitions():
	_write_defs(
		'{"info_custom": {"is_brush_entity": false},' + ' "func_secret": {"is_brush_entity": true}}'
	)
	dock.entity_defs_path = _defs_path
	dock._load_entity_definitions()
	assert_eq(_palette_ids(), ["info_custom"])
	assert_eq(_brush_class_names(), ["func_secret"])


func test_palette_is_built_even_when_the_file_uses_an_entities_array():
	_write_defs('{"entities": [{"id": "info_listed", "is_brush_entity": false}]}')
	dock.entity_defs_path = _defs_path
	dock._load_entity_definitions()
	assert_true(
		_palette_ids().has("info_listed"),
		"The entities-array form used to return before the palette was built"
	)


func test_plugin_definitions_still_populate_the_palette():
	dock._load_entity_definitions()
	assert_gt(_palette_ids().size(), 0, "The shipped entities.json must still show up")
	assert_true(_palette_ids().has("player_start"))


func test_palette_is_built_from_the_merged_definitions():
	# This is what the split was: the palette read one file directly while the
	# brush dropdown read the merged set, so a project overlay reached only one.
	dock._load_entity_definitions()
	var expected: Array = []
	for entry in HFEntityDef.load_merged_raw_entries(dock._effective_entity_defs_path()):
		expected.append(str(entry.get("id", "")))
	var loaded: Array = []
	for entry in dock.entity_defs:
		loaded.append(str(entry.get("id", "")))
	assert_eq(loaded, expected, "The dock must read the merged definitions, overlay included")


func test_effective_path_follows_the_active_root():
	assert_eq(dock._effective_entity_defs_path(), dock.entity_defs_path)
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.entity_definitions_path = _defs_path
	add_child_autoqfree(root)
	dock.level_root = root
	assert_eq(
		dock._effective_entity_defs_path(),
		_defs_path,
		"A root pointing somewhere custom owns the path"
	)


func test_empty_root_path_falls_back_to_the_dock_default():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.entity_definitions_path = ""
	add_child_autoqfree(root)
	dock.level_root = root
	assert_eq(dock._effective_entity_defs_path(), dock.entity_defs_path)
