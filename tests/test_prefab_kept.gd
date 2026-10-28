extends GutTest

## What a linked prefab copy keeps of its own through a Pull, what Push leaves
## out, and what a copy changed (#1734). A kept value stays on the piece it was
## chosen on (#1976), and a copy with a locked piece is not rebuilt (#1977).

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystem = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

const BUTTON := "user://hf_test_prefab_kept_button.hfprefab"
const PANEL := "user://hf_test_prefab_kept_panel.hfprefab"

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_all() -> void:
	for path in [BUTTON, PANEL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A button brush aimed at `door_1`, saved as a prefab, and two linked copies of
## it. Returns the two copies' ids.
func _two_copies() -> Array:
	return _two_copies_of(BUTTON, ["door_1"])


## A button brush for each of `targets`, side by side and aimed at it, saved as
## the prefab `path`, and two linked copies of it. Returns the two copies' ids.
func _two_copies_of(path: String, targets: Array) -> Array:
	var sources: Array = []
	for i in targets.size():
		var brush_id := "src_%d" % i
		var source = root.create_brush_from_info(
			{"brush_id": brush_id, "size": Vector3(1, 1, 0.2), "center": Vector3(-20 + 2 * i, 1, 0)}
		)
		root.brush_system.tie_brushes_to_entity([brush_id], "func_button")
		HFEntityPropUtils.set_entity_property(source, "target", targets[i])
		HFEntityPropUtils.set_entity_property(source, "wait", 1.0)
		sources.append(source)
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, sources, []
	)
	prefab.save_to_file(path)
	for source in sources:
		root.delete_brush(source)
	var iids: Array = []
	for x in [0.0, 6.0]:
		var placed: Dictionary = prefab.instantiate(
			root.brush_system, root.entity_system, root, Vector3(x, 1, 0)
		)
		iids.append(
			root.prefab_system.register_instance(
				path, placed["brush_ids"], placed["entity_nodes"], true
			)
		)
	return iids


func _pieces(iid: String) -> Array:
	return root.prefab_system.pieces_of(root.prefab_system.get_instance(iid))


func _targets(iid: String) -> Array:
	return _pieces(iid).map(
		func(piece): return str(HFEntityPropUtils.get_entity_data(piece).get("target", ""))
	)


## The last thing the level said to the mapper, or "".
func _said() -> String:
	if get_signal_emit_count(root, "user_message") == 0:
		return ""
	return str(get_signal_parameters(root, "user_message")[0])


## Lock a visgroup holding `node`.
func _lock(node: Node) -> void:
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [node])
	root.visgroup_system.set_visgroup_locked("Done", true)


func _button(iid: String) -> Node:
	return _pieces(iid)[0]


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


## Copy X keeps its first button's target. Copy Y loses its first button and
## pushes, so the prefab is one button, door_b's. The Pull gives X that button,
## where X's own door_b button was, and lets the kept value go with the first.
func test_a_pull_that_drops_the_first_piece_drops_what_that_piece_kept():
	var iids := _two_copies_of(PANEL, ["door_a", "door_b"])
	var x := _pieces(iids[0])
	var x_second_at: Vector3 = x[1].global_position
	root.set_entity_property(x[0], "target", "door_7")
	assert_true(root.set_prefab_kept(x[0], "target", true))
	root.delete_brush(_pieces(iids[1])[0])
	assert_true(root.prefab_system.push_instance_to_source(iids[1]))
	watch_signals(root)
	assert_eq(root.prefab_system.propagate_from_source(PANEL), 2)
	assert_eq(_targets(iids[0]), ["door_b"], "X's one button takes the prefab's target")
	assert_eq(root.prefab_system.get_instance(iids[0]).kept, {}, "the kept value is gone")
	assert_eq(_said(), "1 kept value no longer had a piece in the prefab, and was dropped")
	assert_almost_eq(_pieces(iids[0])[0].global_position, x_second_at, Vector3.ONE * 0.001)
	assert_eq(_targets(iids[1]), ["door_b"])


## A copy placed after such a Push is made of the pieces the prefab's records
## name, so what it keeps stays on them through the next Pull.
func test_a_copy_placed_after_a_piece_was_pushed_out_keeps_its_own():
	var iids := _two_copies_of(PANEL, ["door_a", "door_b"])
	root.delete_brush(_pieces(iids[1])[0])
	root.prefab_system.push_instance_to_source(iids[1])
	var placed: Dictionary = root.prefab_system.place(
		HFPrefabType.load_from_file(PANEL),
		PANEL,
		Transform3D(Basis.IDENTITY, Vector3(0, 1, 9)),
		"",
		true
	)
	var z := _pieces(placed["instance_id"])
	root.set_entity_property(z[0], "target", "door_5")
	root.set_prefab_kept(z[0], "target", true)
	root.prefab_system.propagate_from_source(PANEL)
	assert_eq(_targets(placed["instance_id"]), ["door_5"])


## A kept value on a later piece stays on it through a Pull that drops an earlier
## one, and a Push from a copy missing that earlier piece still leaves it out.
func test_a_kept_value_on_a_later_piece_stays_on_it():
	var iids := _two_copies_of(PANEL, ["door_a", "door_b"])
	var y := _pieces(iids[1])
	root.set_entity_property(y[1], "target", "door_9")
	assert_true(root.set_prefab_kept(y[1], "target", true))
	root.delete_brush(y[0])
	assert_true(root.prefab_system.push_instance_to_source(iids[1]))
	var saved = HFPrefabType.load_from_file(PANEL)
	var infos: Array = saved.get_variant_data("base")["brush_infos"]
	assert_eq(infos.size(), 1)
	assert_eq(infos[0]["brush_entity_data"].get("target"), "door_b", "the prefab's own target")
	root.prefab_system.propagate_from_source(PANEL)
	assert_eq(_targets(iids[1]), ["door_9"], "Y's kept target stays on its button")
	assert_eq(_targets(iids[0]), ["door_b"])
	# And through a save of the level and a second Pull.
	root.prefab_system.restore_state(root.prefab_system.capture_state())
	root.prefab_system.propagate_from_source(PANEL)
	assert_eq(_targets(iids[1]), ["door_9"])


## Discard Changes rebuilds nothing of a copy with a locked piece, as a Pull does
## (#1977), and says why.
func test_discard_leaves_a_locked_copy_as_it_is():
	var iids := _two_copies()
	var button := _button(iids[0])
	root.set_entity_property(button, "target", "door_x")
	_lock(button)
	assert_eq(root.prefab_system.propagate_from_source(BUTTON), 1, "a Pull passes it by")
	watch_signals(root)
	assert_false(root.prefab_system.discard_changes(iids[0]))
	assert_same(_button(iids[0]), button, "the same node")
	assert_eq(_value(iids[0], "target"), "door_x")
	assert_eq(_said(), HFPrefabSystem.LOCKED_COPY)
	assert_true(root.prefab_system.discard_changes(iids[1]), "an unlocked copy is rebuilt")


func test_clear_kept_and_a_variant_switch_leave_a_locked_copy_as_it_is():
	var iids := _two_copies()
	var prefab = HFPrefabType.load_from_file(BUTTON)
	var base: Dictionary = prefab.get_variant_data("base")
	prefab.set_variant_data("open", base["brush_infos"].duplicate(true), [])
	prefab.save_to_file(BUTTON)
	var button := _button(iids[0])
	root.set_entity_property(button, "target", "door_7")
	root.set_prefab_kept(button, "target", true)
	_lock(button)
	watch_signals(root)
	assert_false(root.clear_prefab_kept(button))
	assert_eq(root.prefab_system.kept_of(button)["properties"], ["target"], "still kept")
	assert_eq(root.prefab_system.cycle_variant(iids[0]), "")
	assert_false(root.prefab_system.set_variant(iids[0], "open"))
	assert_eq(get_signal_emit_count(root, "user_message"), 3, "each says why")
	assert_eq(_said(), HFPrefabSystem.LOCKED_COPY)
	assert_same(_button(iids[0]), button)
	assert_eq(root.prefab_system.get_instance(iids[0]).variant_name, "base")
	assert_eq(_value(iids[0], "target"), "door_7")
	assert_eq(root.prefab_system.cycle_variant(iids[1]), "open", "an unlocked copy switches")


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
