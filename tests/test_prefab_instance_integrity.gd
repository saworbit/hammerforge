extends GutTest

## Three ways a prefab left the level holding something it should not (#368,
## #369, #370): a visgroup name the level has never registered, an instance id
## already in use, and a signal batch nothing closed.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info({"size": Vector3(32, 32, 32), "brush_id": brush_id})
		as DraftBrush
	)


# ===========================================================================
# Visgroup membership does not ride along (#368)
# ===========================================================================


func test_a_captured_prefab_carries_no_visgroup_names():
	var brush := _box("src")
	root.create_visgroup("Lighting")
	root.add_selection_to_visgroup("Lighting", [brush])
	assert_true(
		Array(brush.get_meta("visgroups", PackedStringArray())).has("Lighting"),
		"the fixture put the brush in the visgroup"
	)

	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, [brush], []
	)
	assert_eq(prefab.brush_infos.size(), 1)
	assert_false(prefab.brush_infos[0].has("visgroups"), "stripped, like brush_id and group_id")
	assert_false(prefab.brush_infos[0].has("brush_id"))
	assert_false(prefab.brush_infos[0].has("group_id"))


func test_a_placed_prefab_brush_is_in_no_visgroup_the_level_lacks():
	var brush := _box("src")
	root.create_visgroup("Lighting")
	root.add_selection_to_visgroup("Lighting", [brush])
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, [brush], []
	)

	var receiver: LevelRoot = LevelRootType.new()
	receiver.auto_spawn_player = false
	receiver.hflevel_autosave_enabled = false
	add_child_autoqfree(receiver)
	prefab.instantiate(receiver.brush_system, receiver.entity_system, receiver, Vector3(128, 0, 0))

	assert_eq(receiver.get_visgroup_names().size(), 0, "the receiving level registered nothing")
	for child in receiver.draft_brushes_node.get_children():
		var names := Array(child.get_meta("visgroups", PackedStringArray()))
		assert_eq(names, [], "a placed brush is in no unregistered visgroup")


# ===========================================================================
# The id counter is derived from what was restored (#369)
# ===========================================================================


func test_a_restore_does_not_reissue_a_live_instance_id():
	var system := HFPrefabSystemType.new(root)
	var first := system.register_instance("res://a.hfprefab", ["b1"], [])
	assert_eq(first, "pfx_1")

	# The shape a `.hflevel` saved before next_instance_id was captured produces.
	var state := system.capture_state()
	state.erase("next_instance_id")
	state.erase("next_entity_uid")
	system.restore_state(state)

	var second := system.register_instance("res://b.hfprefab", ["b2"], [])
	assert_ne(second, first, "the next id is not one already in the registry")
	assert_eq(system.get_all_instances().size(), 2, "both placements are registered")


func test_a_restore_keeps_a_counter_that_is_already_ahead():
	var system := HFPrefabSystemType.new(root)
	system.register_instance("res://a.hfprefab", ["b1"], [])
	var state := system.capture_state()
	system.restore_state(state)
	assert_eq(system.register_instance("res://b.hfprefab", ["b2"], []), "pfx_2")


# ===========================================================================
# A malformed .hfprefab does not take the dock with it (#370)
# ===========================================================================


func test_a_non_dictionary_brush_entry_is_dropped_on_load():
	var prefab = HFPrefabType.from_dict(
		{"prefab_name": "x", "brush_infos": [null, {"shape": 0, "size": Vector3(8, 8, 8)}, 7]}
	)
	assert_eq(prefab.brush_infos.size(), 1, "only the object survived")
	assert_eq(prefab.entity_infos.size(), 0)


func test_a_brush_infos_that_is_not_a_list_loads_as_empty():
	var prefab = HFPrefabType.from_dict({"prefab_name": "x", "brush_infos": "nope"})
	assert_eq(prefab.brush_infos.size(), 0)


func test_placing_a_malformed_prefab_leaves_the_signal_batch_closed():
	var prefab = HFPrefabType.from_dict(
		{"prefab_name": "x", "brush_infos": [null, {"shape": 0, "size": Vector3(8, 8, 8)}]}
	)
	var depth_before: int = root._signal_batch_depth
	prefab.instantiate(root.brush_system, root.entity_system, root, Vector3.ZERO)
	assert_eq(root._signal_batch_depth, depth_before, "the batch was closed")


func test_a_batch_nothing_closes_is_released_rather_than_left_open():
	root.begin_signal_batch()
	assert_eq(root._signal_batch_depth, 1)
	# Pretend the batch opened long ago, which is what an unwound function
	# leaves behind.
	root._signal_batch_opened_msec = 0
	root._release_stuck_signal_batch()
	assert_eq(root._signal_batch_depth, 0, "released, so the dock keeps updating")


func test_a_batch_that_has_just_opened_is_left_alone():
	root.begin_signal_batch()
	root._release_stuck_signal_batch()
	assert_eq(root._signal_batch_depth, 1, "an ordinary batch is not disturbed")
	root.end_signal_batch()
