extends GutTest

## Four loaders that took a payload on trust. Each one sits behind a file a user
## can hand edit, sync, or truncate, and in each case a bad value did not fail
## where it was read: it became a cascade of engine errors somewhere else, or a
## silent half restore with nothing to trace it back to.

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFIOPresetsType = preload("res://addons/hammerforge/systems/hf_io_presets.gd")
const HFDisplacementDataType = preload("res://addons/hammerforge/displacement_data.gd")
const HFGeneratorSchemaType = preload("res://addons/hammerforge/hf_generator_schema.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const KEYMAP_PATH := "user://hf_test_keymap.json"
const PRESETS_PATH := "user://hf_test_io_presets.json"


func after_each():
	for path in [KEYMAP_PATH, PRESETS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## HFIOPresets keeps a level root reference it does not need for load or save.
func _preset_host() -> Node3D:
	var host := Node3D.new()
	add_child_autoqfree(host)
	return host


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# -- Keymap -------------------------------------------------------------------


func test_a_keymap_entry_that_is_not_a_binding_falls_back_to_the_default():
	_write(KEYMAP_PATH, '{"tool_draw": 68}')

	var km = HFKeymapType.load_or_default(KEYMAP_PATH)

	var binding = km.get_all_bindings().get("tool_draw", {})
	assert_true(binding is Dictionary, "The entry should be a binding, not the raw number")
	assert_eq(int(binding.get("keycode", 0)), KEY_D, "and it should be the default binding")


func test_a_keymap_entry_with_no_keycode_falls_back_to_the_default():
	_write(KEYMAP_PATH, '{"tool_draw": {"ctrl": true}}')

	var km = HFKeymapType.load_or_default(KEYMAP_PATH)

	var binding = km.get_all_bindings().get("tool_draw", {})
	assert_eq(int(binding.get("keycode", 0)), KEY_D, "A binding with no keycode is not a binding")
	assert_false(bool(binding.get("ctrl", false)), "and the default carries no ctrl")


func test_a_keymap_key_that_is_not_an_action_is_dropped():
	var default_count: int = HFKeymapType.load_or_default("").get_actions().size()
	_write(KEYMAP_PATH, '{"junk_action": {"keycode": 90}}')

	var km = HFKeymapType.load_or_default(KEYMAP_PATH)

	assert_eq(km.get_actions().size(), default_count, "An unknown action should not be added")
	assert_false(km.get_actions().has("junk_action"), "and it should not be in the list")


func test_a_good_keymap_entry_still_wins():
	_write(KEYMAP_PATH, '{"tool_draw": {"keycode": 87, "shift": true}}')

	var km = HFKeymapType.load_or_default(KEYMAP_PATH)

	var binding = km.get_all_bindings().get("tool_draw", {})
	assert_eq(int(binding.get("keycode", 0)), KEY_W, "A usable override should be kept")
	assert_true(bool(binding.get("shift", false)), "with its modifiers")


func test_get_display_string_does_not_error_on_a_bad_file():
	_write(KEYMAP_PATH, '{"tool_draw": 68, "junk_action": {"keycode": 90}}')
	var km = HFKeymapType.load_or_default(KEYMAP_PATH)

	assert_ne(km.get_display_string("tool_draw"), "", "The display string should still resolve")


# -- I/O presets --------------------------------------------------------------


func test_a_junk_preset_entry_does_not_take_the_list_with_it():
	_write(
		PRESETS_PATH,
		'[1, {"name": "good_a", "connections": []}, ' + '{"name": "good_b", "connections": []}]'
	)
	var presets = HFIOPresetsType.new(_preset_host())

	presets.load_presets(PRESETS_PATH)

	assert_eq(presets.get_user_presets().size(), 2, "The two real presets should survive")
	var all_presets: Array = presets.get_all_presets()
	assert_gt(all_presets.size(), 2, "and get_all_presets should return them plus the builtins")


func test_a_preset_with_no_name_is_dropped_on_load():
	_write(PRESETS_PATH, '[{"name": "", "connections": []}]')
	var presets = HFIOPresetsType.new(_preset_host())

	presets.load_presets(PRESETS_PATH)

	assert_eq(presets.get_user_presets().size(), 0, "A preset with no label is not a preset")


func test_a_preset_with_no_connections_list_is_dropped_on_load():
	_write(PRESETS_PATH, '[{"name": "no_conns"}]')
	var presets = HFIOPresetsType.new(_preset_host())

	presets.load_presets(PRESETS_PATH)

	assert_eq(presets.get_user_presets().size(), 0, "The rest of the class reads connections")


func test_add_user_preset_refuses_an_empty_name():
	var presets = HFIOPresetsType.new(_preset_host())
	presets._presets_path = PRESETS_PATH

	assert_false(presets.add_user_preset("", "no label", []), "An empty name is refused")
	assert_eq(presets.get_user_presets().size(), 0, "and nothing is added")
	assert_true(presets.add_user_preset("real", "", []), "A named preset is still accepted")


# -- Displacement -------------------------------------------------------------


func test_from_dict_clamps_the_power():
	var disp = HFDisplacementDataType.from_dict({"power": 9})

	assert_eq(disp.power, 4, "Power 9 is a 513 by 513 grid on one face")
	assert_eq(disp.distances.size(), disp.get_vertex_count(), "and the arrays match it")


func test_from_dict_refuses_a_distance_array_that_does_not_match_the_power():
	var disp = HFDisplacementDataType.from_dict({"power": 3, "distances": [1.0, 2.0, 3.0]})

	assert_eq(disp.distances.size(), disp.get_vertex_count(), "The array should be the right size")
	for d in disp.distances:
		assert_eq(d, 0.0, "A face that cannot be trusted comes back flat")


func test_a_matching_payload_still_round_trips():
	var original = HFDisplacementDataType.new()
	original.init_flat(3)
	original.set_distance(2, 2, 12.5)
	original.elevation = 3.0

	var restored = HFDisplacementDataType.from_dict(original.to_dict())

	assert_eq(restored.power, 3, "Power should survive")
	assert_eq(restored.elevation, 3.0, "and so should elevation")
	assert_eq(restored.get_distance(2, 2), 12.5, "and the distance that was set")


# -- Generator settings -------------------------------------------------------


func test_a_wrong_typed_setting_returns_a_result_rather_than_null():
	var root: LevelRoot = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)

	var result = root.create_generator("stairs", {"steps": {}, "step_height": []}, Transform3D())

	assert_not_null(result, "create_generator is declared to hand back a result")
	assert_true(result.ok or not result.ok, "and the caller can read .ok off it")


func test_coerce_falls_back_to_the_field_default():
	var schema: Array = [{"key": "steps", "type": "int", "default": 8}]

	var merged: Dictionary = HFGeneratorSchemaType.merge(schema, {"steps": {}})

	assert_eq(merged["steps"], 8, "A value that cannot be an int becomes the field's default")


func test_coerce_still_takes_a_numeric_string():
	var schema: Array = [{"key": "steps", "type": "int", "default": 8}]

	var merged: Dictionary = HFGeneratorSchemaType.merge(schema, {"steps": "12"})

	assert_eq(merged["steps"], 12, "A number written as text is still a number")


func test_coerce_leaves_a_good_value_alone():
	var schema: Array = [
		{"key": "steps", "type": "int", "default": 8},
		{"key": "height", "type": "float", "default": 1.0},
		{"key": "railing", "type": "bool", "default": false}
	]

	var merged: Dictionary = HFGeneratorSchemaType.merge(
		schema, {"steps": 20, "height": 2.5, "railing": true}
	)

	assert_eq(merged["steps"], 20, "int survives")
	assert_eq(merged["height"], 2.5, "float survives")
	assert_eq(merged["railing"], true, "bool survives")
