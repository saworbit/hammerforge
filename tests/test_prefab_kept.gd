extends GutTest

## What a linked prefab copy keeps of its own through a Pull, what Push leaves
## out, and what a copy changed (#1734).

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

const BUTTON := "user://hf_test_prefab_kept_button.hfprefab"

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_all() -> void:
	if FileAccess.file_exists(BUTTON):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BUTTON))


## A button brush aimed at `door_1`, saved as a prefab, and two linked copies of
## it. Returns the two copies' ids.
func _two_copies() -> Array:
	var source = root.create_brush_from_info(
		{"brush_id": "src", "size": Vector3(1, 1, 0.2), "center": Vector3(-20, 1, 0)}
	)
	root.brush_system.tie_brushes_to_entity(["src"], "func_button")
	HFEntityPropUtils.set_entity_property(source, "target", "door_1")
	HFEntityPropUtils.set_entity_property(source, "wait", 1.0)
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, [source], []
	)
	prefab.save_to_file(BUTTON)
	root.delete_brush(source)
	var iids: Array = []
	for x in [0.0, 6.0]:
		var placed: Dictionary = prefab.instantiate(
			root.brush_system, root.entity_system, root, Vector3(x, 1, 0)
		)
		iids.append(
			root.prefab_system.register_instance(
				BUTTON, placed["brush_ids"], placed["entity_nodes"], true
			)
		)
	return iids


func _button(iid: String) -> Node:
	return root.prefab_system.pieces_of(root.prefab_system.get_instance(iid))[0]


func _value(iid: String, prop_name: String) -> Variant:
	return HFEntityPropUtils.get_entity_data(_button(iid)).get(prop_name)


func test_a_kept_target_still_aims_at_its_own_door_after_a_pull():
	var iids := _two_copies()
	root.set_entity_property(_button(iids[0]), "target", "door_7")
	assert_true(root.set_prefab_kept(_button(iids[0]), "target", true))
	root.set_entity_property(_button(iids[1]), "target", "door_9")
	assert_eq(root.prefab_system.propagate_from_source(BUTTON), 2)
	assert_eq(_value(iids[0], "target"), "door_7", "the kept target stays")
	assert_eq(_value(iids[1], "target"), "door_1", "the other copy takes the prefab's again")


func test_push_leaves_a_kept_value_out_of_the_prefab():
	var iids := _two_copies()
	root.set_entity_property(_button(iids[0]), "target", "door_7")
	root.set_prefab_kept(_button(iids[0]), "target", true)
	root.set_entity_property(_button(iids[0]), "wait", 5.0)
	assert_true(root.prefab_system.push_instance_to_source(iids[0]))
	var saved = HFPrefabType.load_from_file(BUTTON)
	var data: Dictionary = saved.get_variant_data("base")["brush_infos"][0]["brush_entity_data"]
	assert_eq(data.get("target"), "door_1", "the prefab keeps its own target")
	assert_almost_eq(float(data.get("wait")), 5.0, 0.001, "and takes the change not kept")
	root.prefab_system.propagate_from_source(BUTTON)
	assert_almost_eq(float(_value(iids[1], "wait")), 5.0, 0.001, "which reaches the other copy")
	assert_eq(_value(iids[1], "target"), "door_1")


func test_a_changed_copy_says_so_and_lists_what_changed():
	var iids := _two_copies()
	assert_eq(root.prefab_system.compute_instance_diff(iids[0]), [], "a fresh copy is unchanged")
	root.set_entity_property(_button(iids[0]), "wait", 4.0)
	root.set_entity_property(_button(iids[0]), "target", "door_7")
	root.set_prefab_kept(_button(iids[0]), "target", true)
	var diff: Array = root.prefab_system.compute_instance_diff(iids[0])
	var fields: Array = diff.map(func(change): return str(change["field"]))
	assert_eq(fields.size(), 1, "the wait, and not the kept target: %s" % str(fields))
	if fields.size() == 1:
		assert_true(str(fields[0]).ends_with("wait"))
	assert_eq(root.prefab_system.compute_instance_diff(iids[1]), [], "the other copy is as it was")


func test_discard_puts_the_prefab_back_and_keeps_what_is_kept():
	var iids := _two_copies()
	root.set_entity_property(_button(iids[0]), "wait", 4.0)
	root.set_entity_property(_button(iids[0]), "target", "door_7")
	root.set_prefab_kept(_button(iids[0]), "target", true)
	assert_true(root.prefab_system.discard_changes(iids[0]))
	assert_almost_eq(float(_value(iids[0], "wait")), 1.0, 0.001, "the change is gone")
	assert_eq(_value(iids[0], "target"), "door_7", "the kept target is not")
	assert_eq(root.prefab_system.compute_instance_diff(iids[0]), [])


func test_clear_kept_takes_the_prefab_s_values_again():
	var iids := _two_copies()
	root.set_entity_property(_button(iids[0]), "target", "door_7")
	root.set_prefab_kept(_button(iids[0]), "target", true)
	assert_true(root.clear_prefab_kept(_button(iids[0])))
	assert_eq(_value(iids[0], "target"), "door_1")
	assert_eq(root.prefab_system.kept_of(_button(iids[0]))["properties"], [])


func test_kept_wiring_survives_a_pull():
	var iids := _two_copies()
	root.add_entity_output(_button(iids[0]), "OnPressed", "door_7", "Open")
	assert_true(root.set_prefab_wiring_kept(_button(iids[0]), true))
	root.prefab_system.propagate_from_source(BUTTON)
	var outputs: Array = root.get_entity_outputs(_button(iids[0]))
	assert_eq(outputs.size(), 1, "the copy's own wire")
	if outputs.size() == 1:
		assert_eq(str(outputs[0].get("target_name", "")), "door_7")


func test_what_a_copy_keeps_is_saved_with_the_level():
	var iids := _two_copies()
	root.set_prefab_kept(_button(iids[0]), "target", true)
	var state: Dictionary = root.prefab_system.capture_state()
	root.prefab_system.restore_state(state)
	assert_eq(root.prefab_system.kept_of(_button(iids[0]))["properties"], ["target"])


func test_the_entity_panel_offers_keep_on_a_linked_copy():
	var iids := _two_copies()
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	if dock.entity_defs.is_empty():
		dock._load_entity_definitions()
	var button := _button(iids[0])
	dock.set_selection_nodes([button])
	var keep: CheckBox = null
	for control in dock._entity_props_controls:
		if is_instance_valid(control):
			var found = control.get_node_or_null("Keep_target")
			if found:
				keep = found
	assert_not_null(keep, "a Keep box beside the target")
	if keep:
		keep.button_pressed = true
		assert_true(root.prefab_system.kept_of(button)["properties"].has("target"))
