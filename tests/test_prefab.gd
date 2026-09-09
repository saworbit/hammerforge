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
