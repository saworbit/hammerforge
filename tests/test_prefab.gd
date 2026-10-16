extends GutTest

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")


func before_each():
	HFLog.end_test_capture()


func after_each():
	HFLog.end_test_capture()


func _capture_warning(pattern: String) -> void:
	HFLog.begin_test_capture([pattern])


func _assert_captured_warning(pattern: String) -> void:
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1, "Should capture exactly one warning")
	if warnings.size() > 0:
		assert_string_contains(warnings[0], pattern, "Should capture expected warning text")


# -- Helper data ----------------------------------------------------------------


func _make_brush_info(pos: Vector3, size: Vector3 = Vector3(32, 32, 32)) -> Dictionary:
	return {
		"shape": 0,
		"size": size,
		"brush_id": "test_%d" % randi(),
		"operation": 0,
		"transform": Transform3D(Basis.IDENTITY, pos),
	}


func _make_entity_info(pos: Vector3, ename: String = "light_1") -> Dictionary:
	return {
		"entity_type": "light",
		"entity_class": "light",
		"transform": Transform3D(Basis.IDENTITY, pos),
		"properties": {},
		"name": ename,
	}


# -- Tests ----------------------------------------------------------------------


func test_empty_prefab():
	var prefab = HFPrefabType.new()
	assert_eq(prefab.brush_infos.size(), 0, "Empty prefab should have no brushes")
	assert_eq(prefab.entity_infos.size(), 0, "Empty prefab should have no entities")


func test_to_dict_from_dict_roundtrip():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "test_room"
	prefab.brush_infos = [_make_brush_info(Vector3(10, 0, 0))]
	prefab.entity_infos = [_make_entity_info(Vector3(5, 0, 0))]
	var data: Dictionary = prefab.to_dict()
	var restored = HFPrefabType.from_dict(data)
	assert_eq(restored.prefab_name, "test_room", "Name should roundtrip")
	assert_eq(restored.brush_infos.size(), 1, "Should have 1 brush")
	assert_eq(restored.entity_infos.size(), 1, "Should have 1 entity")


func test_to_dict_from_dict_preserves_transform():
	var prefab = HFPrefabType.new()
	var info := _make_brush_info(Vector3(42, 7, -3))
	prefab.brush_infos = [info]
	var data: Dictionary = prefab.to_dict()
	var restored = HFPrefabType.from_dict(data)
	var t = restored.brush_infos[0].get("transform")
	assert_not_null(t, "Transform should exist after roundtrip")
	if t is Transform3D:
		assert_almost_eq(t.origin.x, 42.0, 0.01, "X should be preserved")
		assert_almost_eq(t.origin.y, 7.0, 0.01, "Y should be preserved")
		assert_almost_eq(t.origin.z, -3.0, 0.01, "Z should be preserved")


func test_save_and_load_file():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "file_test"
	prefab.brush_infos = [_make_brush_info(Vector3(1, 2, 3))]
	var path := "user://test_prefab_roundtrip.hfprefab"
	var err := prefab.save_to_file(path)
	assert_eq(err, OK, "Save should succeed")
	var loaded = HFPrefabType.load_from_file(path)
	assert_not_null(loaded, "Loaded prefab should not be null")
	assert_eq(loaded.prefab_name, "file_test", "Name should match")
	assert_eq(loaded.brush_infos.size(), 1, "Should have 1 brush")
	# Cleanup
	DirAccess.remove_absolute(path)


func test_load_nonexistent_returns_null():
	_capture_warning("HFPrefab: file not found")
	var loaded = HFPrefabType.load_from_file("user://no_such_file.hfprefab")
	assert_null(loaded, "Loading nonexistent file should return null")
	_assert_captured_warning("HFPrefab: file not found")


func test_from_dict_empty_data():
	var prefab = HFPrefabType.from_dict({})
	assert_eq(prefab.prefab_name, "", "Empty dict gives empty name")
	assert_eq(prefab.brush_infos.size(), 0, "Empty dict gives no brushes")
	assert_eq(prefab.entity_infos.size(), 0, "Empty dict gives no entities")


func test_from_dict_invalid_types():
	# Ensure bad data doesn't crash
	var prefab = (
		HFPrefabType
		. from_dict(
			{
				"prefab_name": 123,
				"brush_infos": "not_an_array",
				"entity_infos": null,
			}
		)
	)
	assert_eq(prefab.brush_infos.size(), 0, "Invalid brush_infos should default to empty")
	assert_eq(prefab.entity_infos.size(), 0, "Invalid entity_infos should default to empty")


func test_instantiate_empty_prefab():
	var prefab = HFPrefabType.new()
	# With no brush_system or entity_system, instantiate should return empty result
	var result = prefab.instantiate(null, null, null, Vector3.ZERO)
	assert_eq(result.get("brush_ids", []).size(), 0, "Empty prefab should produce no brush IDs")
	assert_eq(result.get("entity_count", 0), 0, "Empty prefab should produce no entities")


func test_multiple_brushes_roundtrip():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "multi"
	prefab.brush_infos = [
		_make_brush_info(Vector3(0, 0, 0)),
		_make_brush_info(Vector3(32, 0, 0)),
		_make_brush_info(Vector3(0, 0, 32)),
	]
	var data := prefab.to_dict()
	var restored = HFPrefabType.from_dict(data)
	assert_eq(restored.brush_infos.size(), 3, "All 3 brushes should roundtrip")


func test_entity_io_preserved():
	var prefab = HFPrefabType.new()
	var entity_info := _make_entity_info(Vector3.ZERO, "trigger_1")
	entity_info["io_outputs"] = [
		{"output_name": "on_trigger", "target_name": "door_1", "input_name": "open"}
	]
	prefab.entity_infos = [entity_info]
	var data := prefab.to_dict()
	var restored = HFPrefabType.from_dict(data)
	var outputs = restored.entity_infos[0].get("io_outputs", [])
	assert_eq(outputs.size(), 1, "I/O connection should be preserved")
	assert_eq(str(outputs[0].get("target_name", "")), "door_1", "Target name preserved")


func _make_box_node(pos: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.position = pos
	mi.scale = scale
	add_child_autoqfree(mi)
	return mi


func test_centroid_uses_combined_aabb_center_not_origin_mean():
	# Equal origins would also average to 5; unequal visual size makes AABB
	# center (6) differ from the mean of node origins (5).
	var a := _make_box_node(Vector3(0, 0, 0), Vector3.ONE)
	var b := _make_box_node(Vector3(10, 0, 0), Vector3(5, 1, 1))
	var centroid: Vector3 = HFPrefabType.compute_selection_centroid([a, b], [])
	assert_almost_eq(centroid.x, 6.0, 0.05, "Centroid should be combined AABB center")
	assert_almost_eq(centroid.y, 0.0, 0.05)
	assert_almost_eq(centroid.z, 0.0, 0.05)


# ===========================================================================
# Prefab I/O is remapped through the entities it just made (#257)
# ===========================================================================


func _a_level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _an_entity_in(level: LevelRoot, node_name: String) -> DraftEntity:
	var entity := DraftEntity.new()
	entity.name = node_name
	entity.entity_type = "light"
	entity.entity_class = "light"
	entity.set_meta("is_entity", true)
	level.entities_node.add_child(entity)
	return entity


func test_prefab_io_is_remapped_through_the_entities_it_just_made():
	# The alias-aware name lookup is not unique. Here the first prefab entity is
	# renamed on the way in and carries an authored name matching the second one's
	# node name, so looking the second one up by name returns the first: it gets
	# remapped twice, and the entity it stood in for is never remapped at all.
	var level := _a_level()
	# Occupy the first name only, so the first entity is renamed and the second is not.
	_an_entity_in(level, "Source")

	var source_info := _make_entity_info(Vector3.ZERO, "Source")
	source_info["entity_name"] = "Target"
	var target_info := _make_entity_info(Vector3.ZERO, "Target")
	target_info["io_outputs"] = [
		{"output_name": "OnTrigger", "target_name": "Source", "input_name": "Open"}
	]
	var prefab = HFPrefabType.new()
	prefab.entity_infos = [source_info, target_info]

	var result: Dictionary = prefab.instantiate(
		level.brush_system, level.entity_system, level, Vector3.ZERO
	)

	var made: Array = result.get("entity_nodes", [])
	assert_eq(made.size(), 2, "both prefab entities were placed")
	assert_ne(str(made[0].name), "Source", "the first was renamed, so the remap has work to do")
	var outputs: Array = made[1].get_meta("entity_io_outputs", [])
	assert_eq(outputs.size(), 1, "the output travelled with the prefab")
	assert_eq(
		str(outputs[0].get("target_name", "")),
		str(made[0].name),
		"the output points inside the new instance, not at the entity it was built from"
	)


func test_prefab_io_remap_still_works_without_an_alias_in_the_way():
	var level := _a_level()
	_an_entity_in(level, "Button")

	var source_info := _make_entity_info(Vector3.ZERO, "Button")
	var target_info := _make_entity_info(Vector3.ZERO, "Door")
	target_info["io_outputs"] = [
		{"output_name": "OnTrigger", "target_name": "Button", "input_name": "Open"}
	]
	var prefab = HFPrefabType.new()
	prefab.entity_infos = [source_info, target_info]

	var result: Dictionary = prefab.instantiate(
		level.brush_system, level.entity_system, level, Vector3.ZERO
	)

	var made: Array = result.get("entity_nodes", [])
	assert_eq(made.size(), 2)
	var outputs: Array = made[1].get_meta("entity_io_outputs", [])
	assert_eq(
		str(outputs[0].get("target_name", "")),
		str(made[0].name),
		"the ordinary case still lands on the copy it was made with"
	)


# ===========================================================================
# A placed copy is entities of its own (#1158, #1159)
# ===========================================================================


func _leaf_in(level: LevelRoot, brush_id: String, x: float) -> DraftBrush:
	return (
		level.create_brush_from_info(
			{"size": Vector3(1, 2, 0.25), "center": Vector3(x, 1, 0), "brush_id": brush_id}
		)
		as DraftBrush
	)


func _place(level: LevelRoot, brushes: Array, entities: Array, at: Vector3) -> Dictionary:
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, brushes, entities
	)
	return prefab.instantiate(level.brush_system, level.entity_system, level, at)


func _placed_of_class(level: LevelRoot, result: Dictionary, entity_class: String) -> Array:
	var out: Array = []
	for brush_id in result["brush_ids"]:
		var brush: Node = level.find_brush_by_id(str(brush_id))
		if brush and str(brush.get_meta("brush_entity_class", "")) == entity_class:
			out.append(brush)
	return out


func _targets_of(node: Node) -> Array:
	return (node.get_meta("entity_io_outputs", []) as Array).map(
		func(wire): return str(wire.get("target_name", ""))
	)


func test_a_door_prefab_placed_twice_is_three_doors():
	# Every copy kept the tie it was captured with, and brushes of one tie are one
	# entity, so the export wrote one door of six brushes (#1158).
	var level := _a_level()
	var leaves := [_leaf_in(level, "l0", 0), _leaf_in(level, "l1", 1)]
	level.tie_brushes_to_entity(["l0", "l1"], "func_door")
	var first := _place(level, leaves, [], Vector3(10, 0, 0))
	_place(level, leaves, [], Vector3(20, 0, 0))

	assert_eq(MapIO.export_map_from_level(level).count('"classname" "func_door"'), 3)
	var copy: Array = _placed_of_class(level, first, "func_door")
	assert_eq(copy.size(), 2)
	assert_eq(
		level.brush_system.brushes_of_entity(copy[0]).size(), 2, "a copy is one door of two leaves"
	)


func test_a_placed_door_and_button_are_wired_to_each_other():
	# The copy kept the names it was captured with, so its button opened the
	# source's door as well as its own (#1159).
	var level := _a_level()
	var leaves := [_leaf_in(level, "l0", 0), _leaf_in(level, "l1", 1)]
	level.tie_brushes_to_entity(["l0", "l1"], "func_door", "gate")
	var button := _leaf_in(level, "b0", 3)
	level.tie_brushes_to_entity(["b0"], "func_button", "btn")
	level.add_entity_output(button, "OnPressed", "gate", "Open")

	var result := _place(level, leaves + [button], [], Vector3(10, 0, 0))
	var door: Array = _placed_of_class(level, result, "func_door")
	var placed_button: Array = _placed_of_class(level, result, "func_button")
	var door_name := str(door[0].get_meta("entity_name", ""))
	assert_ne(door_name, "gate", "the copy's door has a name of its own")
	assert_eq(str(door[1].get_meta("entity_name", "")), door_name, "one name for both leaves")
	assert_ne(str(placed_button[0].get_meta("entity_name", "")), "btn")
	assert_eq(_targets_of(placed_button[0]), [door_name], "and its button opens it")
	assert_eq(_targets_of(button), ["gate"], "the source is left alone")


func test_a_placed_buttons_wire_to_a_placed_lamp_reaches_that_lamp_only():
	var level := _a_level()
	var button := _leaf_in(level, "b0", 3)
	level.tie_brushes_to_entity(["b0"], "func_button", "btn")
	var lamp := _an_entity_in(level, "Lamp")
	lamp.set_meta("entity_name", "lamp")
	level.add_entity_output(button, "OnPressed", "lamp", "TurnOn")

	var result := _place(level, [button], [lamp], Vector3(10, 0, 0))
	var placed_lamp: Node = result["entity_nodes"][0]
	var lamp_name := str(placed_lamp.get_meta("entity_name", ""))
	assert_ne(lamp_name, "lamp")
	assert_eq(_targets_of(_placed_of_class(level, result, "func_button")[0]), [lamp_name])


func test_a_wire_to_a_brush_by_its_node_name_follows_the_copy():
	var level := _a_level()
	var leaves := [_leaf_in(level, "l0", 0), _leaf_in(level, "l1", 1)]
	level.tie_brushes_to_entity(["l0", "l1"], "func_door")
	var button := _leaf_in(level, "b0", 3)
	level.tie_brushes_to_entity(["b0"], "func_button", "btn")
	level.add_entity_output(button, "OnPressed", str(leaves[0].name), "Open")

	var result := _place(level, leaves + [button], [], Vector3(10, 0, 0))
	var door: Array = _placed_of_class(level, result, "func_door")
	var targets := _targets_of(_placed_of_class(level, result, "func_button")[0])
	assert_eq(targets.size(), 1)
	assert_true(targets[0] in [str(door[0].name), str(door[1].name)], "a leaf of the copy's door")


func test_a_wire_aimed_outside_the_prefab_still_aims_there():
	var level := _a_level()
	_an_entity_in(level, "alarm").set_meta("entity_name", "alarm")
	var button := _leaf_in(level, "b0", 3)
	level.tie_brushes_to_entity(["b0"], "func_button", "btn")
	level.add_entity_output(button, "OnPressed", "alarm", "Trigger")

	var result := _place(level, [button], [], Vector3(10, 0, 0))
	assert_eq(_targets_of(_placed_of_class(level, result, "func_button")[0]), ["alarm"])


func test_a_variant_applied_to_a_placed_door_keeps_it_a_door_of_its_own():
	# Cycling a variant and pushing a prefab's changes out both rebuild an
	# instance through `_apply_variant()`, which kept the captured tie the same way.
	var level := _a_level()
	var leaves := [_leaf_in(level, "l0", 0), _leaf_in(level, "l1", 1)]
	level.tie_brushes_to_entity(["l0", "l1"], "func_door")
	var path := "user://hf_test_prefab_variant_ties.hfprefab"
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, leaves, []
	)
	assert_eq(prefab.save_to_file(path), OK)
	var placed: Dictionary = prefab.instantiate(
		level.brush_system, level.entity_system, level, Vector3(10, 0, 0)
	)
	var system = level.prefab_system
	var iid: String = system.register_instance(path, placed["brush_ids"], [])

	assert_true(system.set_variant(iid, "base"))
	var rebuilt: Array = system.get_instance(iid).brush_ids.map(
		func(brush_id): return level.find_brush_by_id(str(brush_id))
	)
	assert_eq(rebuilt.size(), 2)
	assert_eq(level.brush_system.brushes_of_entity(rebuilt[0]).size(), 2, "one door of two leaves")
	assert_eq(
		level.brush_system.brushes_of_entity(leaves[0]).size(), 2, "and the source is its own"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# A rebuilt copy keeps the names it has (#1168)
# ===========================================================================


## A door called `gate` and a button wired to it, saved as a prefab at `path`.
func _gate_prefab(level: LevelRoot, path: String) -> HFPrefabType:
	var leaves := [_leaf_in(level, "l0", 0), _leaf_in(level, "l1", 1)]
	level.tie_brushes_to_entity(["l0", "l1"], "func_door", "gate")
	var button := _leaf_in(level, "b0", 3)
	level.tie_brushes_to_entity(["b0"], "func_button", "btn")
	level.add_entity_output(button, "OnPressed", "gate", "Open")
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, leaves + [button], []
	)
	assert_eq(prefab.save_to_file(path), OK)
	return prefab


func _register(level: LevelRoot, prefab: HFPrefabType, path: String, at: Vector3) -> String:
	var placed: Dictionary = prefab.instantiate(level.brush_system, level.entity_system, level, at)
	return level.prefab_system.register_instance(
		path, placed["brush_ids"], placed["entity_nodes"], true
	)


func _names_of(level: LevelRoot, iid: String, entity_class: String) -> Array:
	var out: Array = []
	for brush_id in level.prefab_system.get_instance(iid).brush_ids:
		var brush: Node = level.find_brush_by_id(str(brush_id))
		if brush and str(brush.get_meta("brush_entity_class", "")) == entity_class:
			out.append(str(brush.get_meta("entity_name", "")))
	return out


func _button_of(level: LevelRoot, iid: String) -> Node:
	for brush_id in level.prefab_system.get_instance(iid).brush_ids:
		var brush: Node = level.find_brush_by_id(str(brush_id))
		if brush and str(brush.get_meta("brush_entity_class", "")) == "func_button":
			return brush
	return null


func test_a_rebuilt_copy_keeps_its_name_when_a_lower_one_is_free():
	# A rebuild asked for the lowest free name, so once the second copy was gone the
	# third door became `gate_3`, and a wire aimed at `gate_4` reached nothing.
	var level := _a_level()
	var path := "user://hf_test_prefab_rebuild_names.hfprefab"
	var prefab := _gate_prefab(level, path)
	_register(level, prefab, path, Vector3(10, 0, 0))
	var second := _register(level, prefab, path, Vector3(20, 0, 0))
	var third := _register(level, prefab, path, Vector3(30, 0, 0))
	assert_eq(_names_of(level, third, "func_door"), ["gate_4", "gate_4"])
	level.delete_brushes_by_id(level.prefab_system.get_instance(second).brush_ids)
	level.prefab_system.unregister_instance(second)

	assert_true(level.prefab_system.set_variant(third, "base"))
	assert_eq(_names_of(level, third, "func_door"), ["gate_4", "gate_4"], "the door keeps its name")
	assert_eq(_names_of(level, third, "func_button"), ["btn_4"], "and so does the button")
	assert_eq(_targets_of(_button_of(level, third)), ["gate_4"], "which still opens it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_two_rebuilt_copies_keep_names_of_their_own():
	var level := _a_level()
	var path := "user://hf_test_prefab_rebuild_two.hfprefab"
	var prefab := _gate_prefab(level, path)
	var first := _register(level, prefab, path, Vector3(10, 0, 0))
	var second := _register(level, prefab, path, Vector3(20, 0, 0))

	assert_true(level.prefab_system.set_variant(second, "base"))
	assert_true(level.prefab_system.set_variant(first, "base"))
	assert_eq(_names_of(level, first, "func_door"), ["gate_2", "gate_2"])
	assert_eq(_names_of(level, second, "func_door"), ["gate_3", "gate_3"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_pushed_copy_and_the_copies_it_propagates_to_keep_their_names():
	# Pushing a copy writes its names into the prefab, `gate_4`, and the rebuild
	# that follows numbered every other copy on from there: the first door, rebuilt
	# while the third still held `gate_4`, became `gate_5`.
	var level := _a_level()
	var path := "user://hf_test_prefab_propagate_names.hfprefab"
	var prefab := _gate_prefab(level, path)
	var first := _register(level, prefab, path, Vector3(10, 0, 0))
	var second := _register(level, prefab, path, Vector3(20, 0, 0))
	var third := _register(level, prefab, path, Vector3(30, 0, 0))

	assert_true(level.prefab_system.push_instance_to_source(third))
	assert_eq(level.prefab_system.propagate_from_source(path), 3)
	assert_eq(_names_of(level, first, "func_door"), ["gate_2", "gate_2"])
	assert_eq(_names_of(level, second, "func_door"), ["gate_3", "gate_3"])
	assert_eq(_names_of(level, third, "func_door"), ["gate_4", "gate_4"])
	assert_eq(_targets_of(_button_of(level, first)), ["gate_2"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_name_a_variant_adds_takes_a_free_one():
	var level := _a_level()
	var path := "user://hf_test_prefab_variant_adds_a_name.hfprefab"
	var prefab := _gate_prefab(level, path)
	_an_entity_in(level, "Lamp").set_meta("entity_name", "lamp")
	var lit: Dictionary = prefab.get_variant_data("base").duplicate(true)
	var lamp := _make_entity_info(Vector3(2, 2, 0), "Lamp")
	lamp["entity_name"] = "lamp"
	prefab.set_variant_data("lit", lit["brush_infos"], [lamp])
	assert_eq(prefab.save_to_file(path), OK)
	var iid := _register(level, prefab, path, Vector3(10, 0, 0))

	assert_true(level.prefab_system.set_variant(iid, "lit"))
	assert_eq(_names_of(level, iid, "func_door"), ["gate_2", "gate_2"], "the door keeps its name")
	var lamps: Array = level.prefab_system.get_instance(iid).entity_uids.map(
		func(uid): return level.entity_system.find_entity_by_prefab_uid(str(uid))
	)
	assert_eq(lamps.size(), 1)
	assert_eq(str(lamps[0].get_meta("entity_name", "")), "lamp_2", "the lamp takes a free name")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_point_entity_placed_back_into_its_own_level_has_a_readable_name():
	# Its recorded node name is the one the entity it was captured from has, and
	# the copy came in as `@Node3D@14`, which the Scene dock, Validate and the
	# Objects tab's target list all showed (#1169).
	var level := _a_level()
	var lamp := _an_entity_in(level, "Lamp")
	var result := _place(level, [], [lamp], Vector3(10, 0, 0))
	var placed: Node = result["entity_nodes"][0]
	assert_false(str(placed.name).begins_with("@"), "got %s" % placed.name)
	assert_true(str(placed.name).begins_with("Lamp"), "got %s" % placed.name)
	assert_eq(str(lamp.name), "Lamp", "the source keeps its own")


# ===========================================================================
# A rebuilt copy keeps its node names (#1178)
# ===========================================================================


## An unnamed door and a lamp, saved as a prefab at `path` and placed three times.
func _door_and_lamp_copies(level: LevelRoot, path: String) -> Array:
	var leaves := [_leaf_in(level, "l0", 0), _leaf_in(level, "l1", 1)]
	level.tie_brushes_to_entity(["l0", "l1"], "func_door")
	var lamp := _an_entity_in(level, "Lamp")
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, leaves, [lamp]
	)
	assert_eq(prefab.save_to_file(path), OK)
	var iids: Array = []
	for i in 3:
		iids.append(_register(level, prefab, path, Vector3(10 * (i + 1), 0, 0)))
	return iids


func _node_names(level: LevelRoot, iid: String) -> Array:
	var rec = level.prefab_system.get_instance(iid)
	var out: Array = []
	for brush_id in rec.brush_ids:
		out.append(str(level.find_brush_by_id(str(brush_id)).name))
	for uid in rec.entity_uids:
		out.append(str(level.entity_system.find_entity_by_prefab_uid(str(uid)).name))
	return out


func test_a_rebuilt_copy_keeps_its_node_names():
	# The editor takes a brush's node name, and an unnamed point entity's, as an
	# address. A rebuild numbered them on afresh, so with the second copy gone the
	# third copy's `Box_6` became `Box_4` and a wire aimed at it reached nothing.
	var level := _a_level()
	var path := "user://hf_test_prefab_rebuild_node_names.hfprefab"
	var iids := _door_and_lamp_copies(level, path)
	var before := _node_names(level, iids[2])
	var second = level.prefab_system.get_instance(iids[1])
	level.delete_brushes_by_id(second.brush_ids)
	for uid in second.entity_uids:
		var entity: Node = level.entity_system.find_entity_by_prefab_uid(str(uid))
		entity.get_parent().remove_child(entity)
		entity.free()
	level.prefab_system.unregister_instance(iids[1])

	assert_true(level.prefab_system.set_variant(iids[2], "base"))
	assert_eq(_node_names(level, iids[2]), before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_brush_a_variant_adds_does_not_take_a_name_the_copy_keeps():
	# The added brush is made first, and Godot numbers its taken name on to the
	# first free one, which is the name the third copy's first leaf is about to
	# get back.
	var level := _a_level()
	var path := "user://hf_test_prefab_variant_keeps_node_names.hfprefab"
	var iids := _door_and_lamp_copies(level, path)
	var before := _node_names(level, iids[2])
	var prefab = HFPrefabType.load_from_file(path)
	var base: Dictionary = prefab.get_variant_data("base")
	var extra: Dictionary = base["brush_infos"][0].duplicate(true)
	for key in ["brush_entity_class", "brush_entity_group", "entity_name"]:
		extra.erase(key)
	extra["name"] = "Box_3"
	prefab.set_variant_data(
		"wide", [extra] + base["brush_infos"].duplicate(true), base["entity_infos"].duplicate(true)
	)
	assert_eq(prefab.save_to_file(path), OK)

	assert_true(level.prefab_system.set_variant(iids[2], "wide"))
	var after := _node_names(level, iids[2])
	assert_eq(after.slice(1), before, "the leaves and the lamp keep their names")
	assert_false(str(after[0]) in before, "the added brush has one of its own")
	assert_false(str(after[0]).begins_with("@"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# A Pull passes over a linked copy that was deleted (#1181)
# ===========================================================================


## A one-brush prefab saved at `path` and placed as linked copies at x 10 and 20.
func _two_linked_copies(level: LevelRoot, path: String) -> Array:
	var leaf := _leaf_in(level, "src", -40)
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [leaf], []
	)
	assert_eq(prefab.save_to_file(path), OK)
	return [
		_register(level, prefab, path, Vector3(10, 0, 0)),
		_register(level, prefab, path, Vector3(20, 0, 0)),
	]


func _brush_xs(level: LevelRoot) -> Array:
	var xs: Array = []
	for brush in level._iter_managed_brush_nodes():
		xs.append(roundi(brush.global_position.x))
	xs.sort()
	return xs


func test_a_pull_passes_over_a_linked_copy_that_was_deleted():
	# Nothing unregisters a copy on Delete, so its record stayed, and a Pull rebuilt
	# it at the origin: none of its nodes were left to say where it had been.
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_deleted.hfprefab"
	var iids := _two_linked_copies(level, path)
	level.delete_managed_nodes(level.prefab_system.get_instance(iids[1]).brush_ids, [])

	assert_eq(level.prefab_system.propagate_from_source(path), 1, "only the copy still there")
	assert_false(level.prefab_system.set_variant(iids[1], "base"))
	assert_eq(level.prefab_system.cycle_variant(iids[1]), "")
	assert_false(level.prefab_system.push_instance_to_source(iids[1]), "nothing to push")
	assert_eq(_brush_xs(level), [-40, 10], "and nothing placed at the origin")
	assert_eq(HFPrefabType.load_from_file(path).brush_infos.size(), 1, "the prefab keeps its brush")
	assert_not_null(level.prefab_system.get_instance(iids[1]), "the record stays for an undo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_pull_after_the_delete_is_undone_rebuilds_the_copy_where_it_was():
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_undone.hfprefab"
	var iids := _two_linked_copies(level, path)
	# What the Delete action's undo puts back.
	var before: Dictionary = level.capture_state()
	level.delete_managed_nodes(level.prefab_system.get_instance(iids[1]).brush_ids, [])
	level.restore_state(before)

	assert_eq(level.prefab_system.propagate_from_source(path), 2)
	assert_eq(_brush_xs(level), [-40, 10, 20])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# A partly deleted copy is rebuilt where it was placed (#1186)
# ===========================================================================


## Two leaves a box apart, saved as a prefab at `path` and placed as a linked
## copy at x 10, so they sit at x 9 and 11.
func _a_pair_at_ten(level: LevelRoot, path: String) -> String:
	var leaves := [_leaf_in(level, "p0", -41), _leaf_in(level, "p1", -39)]
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, leaves, []
	)
	assert_eq(prefab.save_to_file(path), OK)
	return _register(level, prefab, path, Vector3(10, 0, 0))


func _xs_of(level: LevelRoot, iid: String) -> Array:
	var xs: Array = []
	for brush_id in level.prefab_system.get_instance(iid).brush_ids:
		var brush: Node3D = level.find_brush_by_id(str(brush_id))
		if brush:
			xs.append(roundi(brush.global_position.x))
	return xs


func test_a_pull_rebuilds_a_partly_deleted_copy_where_it_was_placed():
	# The rebuild centred the copy on what was left of it, so with one of its two
	# leaves deleted it came back a leaf's half width over.
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_partial.hfprefab"
	var iid := _a_pair_at_ten(level, path)
	assert_eq(_xs_of(level, iid), [9, 11])
	level.delete_managed_nodes([level.prefab_system.get_instance(iid).brush_ids[1]], [])

	assert_eq(level.prefab_system.propagate_from_source(path), 1)
	assert_eq(_xs_of(level, iid), [9, 11])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_variant_switch_rebuilds_a_partly_deleted_copy_where_it_was_placed():
	var level := _a_level()
	var path := "user://hf_test_prefab_variant_partial.hfprefab"
	var iid := _a_pair_at_ten(level, path)
	level.delete_managed_nodes([level.prefab_system.get_instance(iid).brush_ids[0]], [])

	assert_true(level.prefab_system.set_variant(iid, "base"))
	assert_eq(_xs_of(level, iid), [9, 11])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# An edit that changes a copy's bounds moves nothing it did not touch (#1188)
# ===========================================================================


## Three leaves at x -41, -39 and -40, saved as a prefab at `path` and placed as
## linked copies at x 10 and 20.
func _three_leaf_copies(level: LevelRoot, path: String) -> Array:
	var leaves := [
		_leaf_in(level, "t0", -41), _leaf_in(level, "t1", -39), _leaf_in(level, "t2", -40)
	]
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, leaves, []
	)
	assert_eq(prefab.save_to_file(path), OK)
	return [
		_register(level, prefab, path, Vector3(10, 0, 0)),
		_register(level, prefab, path, Vector3(20, 0, 0)),
	]


func _nudge_leaf(level: LevelRoot, iid: String, index: int, by: float) -> void:
	var brush_ids: Array = level.prefab_system.get_instance(iid).brush_ids
	level.nudge_brushes_by_id([brush_ids[index]], Vector3(by, 0, 0))


func test_a_push_that_moves_one_leaf_leaves_the_other_copies_untouched_leaves_in_place():
	# The Push re-centred the prefab on the copy's new bounds, and the Pull rebuilt
	# every other copy around its own centre, so their untouched leaves moved too.
	var level := _a_level()
	var path := "user://hf_test_prefab_push_bounds.hfprefab"
	var iids := _three_leaf_copies(level, path)
	_nudge_leaf(level, iids[0], 1, 4)

	assert_true(level.prefab_system.push_instance_to_source(iids[0]))
	assert_eq(level.prefab_system.propagate_from_source(path), 2)
	assert_eq(_xs_of(level, iids[0]), [9, 15, 10], "the edited copy stays as edited")
	assert_eq(_xs_of(level, iids[1]), [19, 25, 20], "and the other takes the edit and nothing else")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_pull_puts_back_a_copy_with_one_leaf_moved_where_it_was_placed():
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_moved.hfprefab"
	var iids := _three_leaf_copies(level, path)
	_nudge_leaf(level, iids[0], 1, 4)

	assert_eq(level.prefab_system.propagate_from_source(path), 2)
	assert_eq(_xs_of(level, iids[0]), [9, 11, 10])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_copy_moved_as_a_whole_rebuilds_where_it_now_is():
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_whole.hfprefab"
	var iids := _three_leaf_copies(level, path)
	level.nudge_brushes_by_id(level.prefab_system.get_instance(iids[0]).brush_ids, Vector3(5, 0, 0))

	assert_eq(level.prefab_system.propagate_from_source(path), 2)
	assert_eq(_xs_of(level, iids[0]), [14, 16, 15])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# A rebuilt copy stays in its visgroups and its group (#1190)
# ===========================================================================


## A leaf and a lamp, saved as a prefab at `path` and placed as a linked copy. The
## leaf goes in visgroup `Walls`, the lamp in `Lighting`, which is hidden, and
## both in group `Room`.
func _sorted_copy(level: LevelRoot, path: String) -> String:
	var leaf := _leaf_in(level, "m0", -40)
	var lamp := _an_entity_in(level, "Lamp")
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [leaf], [lamp]
	)
	assert_eq(prefab.save_to_file(path), OK)
	var iid := _register(level, prefab, path, Vector3(10, 0, 0))
	var copy := _copy_nodes(level, iid)
	level.add_selection_to_visgroup("Walls", [copy[0]])
	level.add_selection_to_visgroup("Lighting", [copy[1]])
	level.group_selection("Room", copy)
	level.set_visgroup_visible("Lighting", false)
	return iid


func _copy_nodes(level: LevelRoot, iid: String) -> Array:
	var rec = level.prefab_system.get_instance(iid)
	var out: Array = []
	for brush_id in rec.brush_ids:
		out.append(level.find_brush_by_id(str(brush_id)))
	for uid in rec.entity_uids:
		out.append(level.entity_system.find_entity_by_prefab_uid(str(uid)))
	return out


func _membership(node: Node) -> Array:
	return [
		Array(node.get_meta("visgroups", PackedStringArray())),
		str(node.get_meta("group_id", "")),
		node.visible,
	]


func test_a_pull_keeps_each_node_of_a_copy_in_its_visgroups_and_group():
	# A rebuild makes new nodes, and a prefab carries no membership (#368), so
	# every copy fell out of its visgroups and group, and a hidden one showed.
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_membership.hfprefab"
	var iid := _sorted_copy(level, path)

	assert_eq(level.prefab_system.propagate_from_source(path), 1)
	var copy := _copy_nodes(level, iid)
	assert_eq(_membership(copy[0]), [["Walls"], "Room", true], "the leaf")
	assert_eq(_membership(copy[1]), [["Lighting"], "Room", false], "the lamp, still hidden")
	assert_eq(level.get_group_members("Room").size(), 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_node_a_variant_adds_joins_only_what_the_whole_copy_was_in():
	var level := _a_level()
	var path := "user://hf_test_prefab_variant_membership.hfprefab"
	var iid := _sorted_copy(level, path)
	var prefab = HFPrefabType.load_from_file(path)
	var base: Dictionary = prefab.get_variant_data("base")
	var extra: Dictionary = base["brush_infos"][0].duplicate(true)
	extra["name"] = "Extra"
	prefab.set_variant_data(
		"wide", base["brush_infos"].duplicate(true) + [extra], base["entity_infos"].duplicate(true)
	)
	assert_eq(prefab.save_to_file(path), OK)

	assert_true(level.prefab_system.set_variant(iid, "wide"))
	var copy := _copy_nodes(level, iid)
	assert_eq(copy.size(), 3)
	assert_eq(_membership(copy[0]), [["Walls"], "Room", true], "the leaf keeps its own")
	assert_eq(_membership(copy[1]), [[], "Room", true], "the new brush is in the copy's group")
	assert_eq(_membership(copy[2]), [["Lighting"], "Room", false], "the lamp keeps its own")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ===========================================================================
# A turned copy stays turned (#1192)
# ===========================================================================


## Where each leaf of a copy is and which way it faces, to a hundredth.
func _poses_of(level: LevelRoot, iid: String) -> Array:
	var out: Array = []
	for brush_id in level.prefab_system.get_instance(iid).brush_ids:
		var brush: Node3D = level.find_brush_by_id(str(brush_id))
		var yaw := rad_to_deg(brush.global_transform.basis.get_euler().y)
		out.append([brush.global_position.snapped(Vector3.ONE * 0.01), snappedf(yaw, 0.01)])
	return out


func _turn_copy(level: LevelRoot, iid: String, degrees: float, about: Vector3) -> void:
	var brush_ids: Array = level.prefab_system.get_instance(iid).brush_ids
	level.rotate_managed_nodes(brush_ids, [], 1, degrees, about)


func test_a_pull_leaves_a_turned_copy_turned():
	# A copy had a position and no turn of its own, so a rebuild faced it the way
	# the prefab faces.
	var level := _a_level()
	var path := "user://hf_test_prefab_pull_turned.hfprefab"
	var iids := _three_leaf_copies(level, path)
	_turn_copy(level, iids[0], 90, Vector3(10, 0, 0))
	var turned := _poses_of(level, iids[0])

	assert_eq(level.prefab_system.propagate_from_source(path), 2)
	assert_eq(_poses_of(level, iids[0]), turned, "after a Pull")
	assert_true(level.prefab_system.set_variant(iids[0], "base"))
	assert_eq(_poses_of(level, iids[0]), turned, "and after a variant switch")
	assert_eq(_xs_of(level, iids[1]), [19, 21, 20], "the copy nobody turned is as placed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_an_edit_pushed_from_a_turned_copy_lands_along_each_copys_own_axes():
	var level := _a_level()
	var path := "user://hf_test_prefab_push_turned.hfprefab"
	var iids := _three_leaf_copies(level, path)
	_turn_copy(level, iids[0], 90, Vector3(10, 0, 0))
	# Turned 90 degrees, the copy's x axis runs along world -z, so 4 along +z is 4
	# back along its x.
	_nudge_leaf_by(level, iids[0], 1, Vector3(0, 0, 4))
	var edited := _poses_of(level, iids[0])

	assert_true(level.prefab_system.push_instance_to_source(iids[0]))
	assert_eq(level.prefab_system.propagate_from_source(path), 2)
	assert_eq(_poses_of(level, iids[0]), edited, "the edited copy stays as edited")
	assert_eq(_xs_of(level, iids[1]), [19, 17, 20], "the other's leaf moves back along its x")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _nudge_leaf_by(level: LevelRoot, iid: String, index: int, by: Vector3) -> void:
	var brush_ids: Array = level.prefab_system.get_instance(iid).brush_ids
	level.nudge_brushes_by_id([brush_ids[index]], by)
