extends GutTest

const HFDuplicator = preload("res://addons/hammerforge/hf_duplicator.gd")


func test_init_generates_unique_id():
	var dup1 = HFDuplicator.new()
	var dup2 = HFDuplicator.new()
	assert_ne(dup1.duplicator_id, "")
	assert_true(dup1.duplicator_id.begins_with("dup_"))


func test_generate_empty_source_returns_false():
	var dup = HFDuplicator.new()
	dup.source_brush_ids = PackedStringArray()
	assert_false(dup.generate(null, 3, Vector3(8, 0, 0)))


func test_generate_zero_count_returns_false():
	var dup = HFDuplicator.new()
	dup.source_brush_ids = PackedStringArray(["brush_1"])
	assert_false(dup.generate(null, 0, Vector3(8, 0, 0)))


func test_to_dict_roundtrip():
	var dup = HFDuplicator.new()
	dup.duplicator_id = "dup_test_123"
	dup.source_brush_ids = PackedStringArray(["src_a", "src_b"])
	dup.count = 3
	dup.offset = Vector3(4.0, 0.0, 2.0)
	dup.instance_groups = [
		PackedStringArray(["inst_1", "inst_2"]),
		PackedStringArray(["inst_3", "inst_4"]),
		PackedStringArray(["inst_5", "inst_6"]),
	]

	var d = dup.to_dict()
	assert_eq(d["duplicator_id"], "dup_test_123")
	assert_eq(d["count"], 3)
	assert_eq(d["source_brush_ids"].size(), 2)
	assert_eq(d["instance_groups"].size(), 3)

	var restored = HFDuplicator.from_dict(d)
	assert_eq(restored.duplicator_id, "dup_test_123")
	assert_eq(restored.source_brush_ids.size(), 2)
	assert_eq(restored.source_brush_ids[0], "src_a")
	assert_eq(restored.count, 3)
	assert_almost_eq(restored.offset.x, 4.0, 0.001)
	assert_almost_eq(restored.offset.z, 2.0, 0.001)
	assert_eq(restored.instance_groups.size(), 3)
	assert_eq(restored.instance_groups[0].size(), 2)
	assert_eq(restored.instance_groups[0][0], "inst_1")


func test_get_all_instance_ids():
	var dup = HFDuplicator.new()
	dup.instance_groups = [
		PackedStringArray(["a", "b"]),
		PackedStringArray(["c"]),
	]
	var all_ids = dup.get_all_instance_ids()
	assert_eq(all_ids.size(), 3)
	assert_true("a" in Array(all_ids))
	assert_true("b" in Array(all_ids))
	assert_true("c" in Array(all_ids))


func test_from_dict_missing_fields():
	var dup = HFDuplicator.from_dict({})
	assert_eq(dup.count, 0)
	assert_eq(dup.source_brush_ids.size(), 0)
	assert_eq(dup.instance_groups.size(), 0)
	assert_eq(dup.offset, Vector3.ZERO)


func test_from_dict_partial_offset():
	var dup = HFDuplicator.from_dict({"offset": [1.0, 2.0, 3.0]})
	assert_almost_eq(dup.offset.x, 1.0, 0.001)
	assert_almost_eq(dup.offset.y, 2.0, 0.001)
	assert_almost_eq(dup.offset.z, 3.0, 0.001)
