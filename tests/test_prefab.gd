extends GutTest

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

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
	var loaded = HFPrefabType.load_from_file("user://no_such_file.hfprefab")
	assert_null(loaded, "Loading nonexistent file should return null")


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
	var result = prefab.instantiate(null, null, Node3D.new(), Vector3.ZERO)
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
