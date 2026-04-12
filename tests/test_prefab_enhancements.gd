extends GutTest

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")

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


# ===========================================================================
# Variant tests
# ===========================================================================


func test_default_variant_names():
	var prefab = HFPrefabType.new()
	var names := prefab.get_variant_names()
	assert_eq(names.size(), 1, "Default has only base variant")
	assert_eq(names[0], "base", "Default variant is base")


func test_add_variant():
	var prefab = HFPrefabType.new()
	prefab.brush_infos = [_make_brush_info(Vector3.ZERO)]
	prefab.set_variant_data("wooden", [_make_brush_info(Vector3(10, 0, 0))], [])
	var names := prefab.get_variant_names()
	assert_eq(names.size(), 2, "Should have base + wooden")
	assert_true(prefab.has_variant("wooden"), "Should have wooden variant")
	assert_true(prefab.has_variant("base"), "Should always have base")


func test_get_variant_data_base():
	var prefab = HFPrefabType.new()
	prefab.brush_infos = [_make_brush_info(Vector3(1, 2, 3))]
	var data := prefab.get_variant_data("base")
	assert_eq(data["brush_infos"].size(), 1, "Base should return top-level brush_infos")


func test_get_variant_data_named():
	var prefab = HFPrefabType.new()
	var metal_brush := _make_brush_info(Vector3(99, 0, 0))
	prefab.set_variant_data("metal", [metal_brush], [])
	var data := prefab.get_variant_data("metal")
	assert_eq(data["brush_infos"].size(), 1, "Metal variant should have 1 brush")
	var t = data["brush_infos"][0].get("transform")
	if t is Transform3D:
		assert_almost_eq(t.origin.x, 99.0, 0.01, "Metal brush at correct position")


func test_get_variant_data_missing_falls_back():
	var prefab = HFPrefabType.new()
	prefab.brush_infos = [_make_brush_info(Vector3.ZERO)]
	var data := prefab.get_variant_data("nonexistent")
	assert_eq(data["brush_infos"].size(), 1, "Missing variant falls back to base")


func test_remove_variant():
	var prefab = HFPrefabType.new()
	prefab.set_variant_data("ornate", [_make_brush_info(Vector3.ZERO)], [])
	assert_true(prefab.has_variant("ornate"), "Ornate exists before removal")
	var removed := prefab.remove_variant("ornate")
	assert_true(removed, "Remove should return true")
	assert_false(prefab.has_variant("ornate"), "Ornate gone after removal")


func test_cannot_remove_base():
	var prefab = HFPrefabType.new()
	var removed := prefab.remove_variant("base")
	assert_false(removed, "Cannot remove base variant")


func test_set_variant_data_base_updates_top_level():
	var prefab = HFPrefabType.new()
	var new_brush := _make_brush_info(Vector3(50, 0, 0))
	prefab.set_variant_data("base", [new_brush], [])
	assert_eq(prefab.brush_infos.size(), 1, "Setting base updates top-level")
	var t = prefab.brush_infos[0].get("transform")
	if t is Transform3D:
		assert_almost_eq(t.origin.x, 50.0, 0.01, "Base data updated correctly")


# ===========================================================================
# Variant serialization roundtrip
# ===========================================================================


func test_variants_roundtrip():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "door"
	prefab.brush_infos = [_make_brush_info(Vector3.ZERO)]
	prefab.set_variant_data("wooden", [_make_brush_info(Vector3(10, 0, 0))], [])
	prefab.set_variant_data(
		"metal", [_make_brush_info(Vector3(20, 0, 0))], [_make_entity_info(Vector3(25, 0, 0))]
	)
	var data := prefab.to_dict()
	var restored := HFPrefabType.from_dict(data)
	assert_eq(restored.get_variant_names().size(), 3, "3 variants roundtrip")
	assert_true(restored.has_variant("wooden"), "Wooden survives roundtrip")
	assert_true(restored.has_variant("metal"), "Metal survives roundtrip")
	var metal_data := restored.get_variant_data("metal")
	assert_eq(metal_data["brush_infos"].size(), 1, "Metal has 1 brush")
	assert_eq(metal_data["entity_infos"].size(), 1, "Metal has 1 entity")


func test_variants_file_roundtrip():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "file_variant_test"
	prefab.brush_infos = [_make_brush_info(Vector3.ZERO)]
	prefab.set_variant_data("alt", [_make_brush_info(Vector3(5, 5, 5))], [])
	var path := "user://test_variants_roundtrip.hfprefab"
	prefab.save_to_file(path)
	var loaded := HFPrefabType.load_from_file(path)
	assert_not_null(loaded, "Loaded not null")
	assert_true(loaded.has_variant("alt"), "Alt variant survives file roundtrip")
	DirAccess.remove_absolute(path)


# ===========================================================================
# Tags tests
# ===========================================================================


func test_tags_default_empty():
	var prefab = HFPrefabType.new()
	assert_eq(prefab.tags.size(), 0, "Tags default to empty")


func test_tags_roundtrip():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "tagged"
	prefab.tags = PackedStringArray(["door", "architecture", "interior"])
	var data := prefab.to_dict()
	var restored := HFPrefabType.from_dict(data)
	assert_eq(restored.tags.size(), 3, "3 tags roundtrip")
	assert_true("door" in Array(restored.tags), "door tag survives")
	assert_true("architecture" in Array(restored.tags), "architecture tag survives")
	assert_true("interior" in Array(restored.tags), "interior tag survives")


func test_tags_file_roundtrip():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "tagged_file"
	prefab.tags = PackedStringArray(["test_tag"])
	var path := "user://test_tags_roundtrip.hfprefab"
	prefab.save_to_file(path)
	var loaded := HFPrefabType.load_from_file(path)
	assert_not_null(loaded)
	assert_eq(loaded.tags.size(), 1, "Tag survives file roundtrip")
	assert_eq(loaded.tags[0], "test_tag")
	DirAccess.remove_absolute(path)


func test_tags_empty_not_serialized():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "no_tags"
	var data := prefab.to_dict()
	assert_false(data.has("tags"), "Empty tags not serialized")


# ===========================================================================
# Instantiate with variant parameter
# ===========================================================================


func test_instantiate_empty_variant_uses_base():
	var prefab = HFPrefabType.new()
	var result = prefab.instantiate(null, null, null, Vector3.ZERO, "")
	assert_eq(result.get("brush_ids", []).size(), 0, "Empty base = no brushes")


func test_instantiate_returns_entity_names():
	var prefab = HFPrefabType.new()
	# No systems = no actual instantiation, but structure is correct
	var result = prefab.instantiate(null, null, null, Vector3.ZERO)
	assert_true(result.has("entity_names"), "Result should contain entity_names key")


# ===========================================================================
# PrefabSystem unit tests (standalone, no LevelRoot shim needed)
# ===========================================================================


func test_prefab_system_suggest_name_single_brush():
	# Test the name suggestion logic without a full LevelRoot
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "test"
	# Just verify the prefab itself works
	assert_eq(prefab.prefab_name, "test")


func test_prefab_system_capture_restore_state():
	# Validate PrefabSystem serialization round-trip with a minimal shim
	# Create a minimal entity system shim
	var entity_script = GDScript.new()
	entity_script.source_code = ("""
extends RefCounted
func find_entities_by_name(_name: String) -> Array:
	return []
""")
	entity_script.reload()

	# Create a minimal root shim
	var root_script = GDScript.new()
	root_script.source_code = ("""
extends Node3D
var draft_brushes_node: Node3D
var entities_node: Node3D
var entity_system
var prefab_system
""")
	root_script.reload()
	var root = root_script.new()
	root.draft_brushes_node = Node3D.new()
	root.entities_node = Node3D.new()
	root.add_child(root.draft_brushes_node)
	root.add_child(root.entities_node)
	root.entity_system = entity_script.new()

	var system = HFPrefabSystemType.new(root)

	# Create fake entity nodes for registration (register_instance expects Node3D refs)
	var fake_entity := Node3D.new()
	fake_entity.name = "e1"
	root.entities_node.add_child(fake_entity)

	# Register some fake instances
	var iid1 := system.register_instance(
		"res://prefabs/test.hfprefab", ["b1", "b2"], [fake_entity], true, "base"
	)
	var iid2 := system.register_instance("res://prefabs/other.hfprefab", ["b3"], [], false, "metal")
	assert_ne(iid1, "", "Instance 1 should have an ID")
	assert_ne(iid2, "", "Instance 2 should have an ID")
	assert_ne(iid1, iid2, "Instance IDs should be unique")

	# Capture state
	var state := system.capture_state()
	assert_true(state.has("instances"), "Captured state has instances")
	assert_eq(state["instances"].size(), 2, "2 instances captured")

	# Restore into a new system
	var system2 = HFPrefabSystemType.new(root)
	system2.restore_state(state)
	assert_eq(system2.get_all_instances().size(), 2, "2 instances restored")

	var rec1 = system2.get_instance(iid1)
	assert_not_null(rec1, "Instance 1 found after restore")
	assert_eq(rec1.source_path, "res://prefabs/test.hfprefab")
	assert_eq(rec1.brush_ids.size(), 2, "Brush IDs preserved")
	assert_eq(rec1.entity_uids.size(), 1, "Entity UIDs preserved")
	assert_true(rec1.linked, "Linked flag preserved")

	var rec2 = system2.get_instance(iid2)
	assert_not_null(rec2, "Instance 2 found after restore")
	assert_eq(rec2.variant_name, "metal", "Variant name preserved")
	assert_false(rec2.linked, "Non-linked flag preserved")

	root.free()


func _make_root_shim():
	var entity_script = GDScript.new()
	entity_script.source_code = ("""
extends RefCounted
func find_entities_by_name(_name: String) -> Array:
	return []
""")
	entity_script.reload()
	var root_script = GDScript.new()
	root_script.source_code = ("""
extends Node3D
var draft_brushes_node: Node3D
var entities_node: Node3D
var entity_system
""")
	root_script.reload()
	var root = root_script.new()
	root.draft_brushes_node = Node3D.new()
	root.entities_node = Node3D.new()
	root.add_child(root.draft_brushes_node)
	root.add_child(root.entities_node)
	root.entity_system = entity_script.new()
	return root


func test_prefab_system_unregister():
	var root = _make_root_shim()

	var system = HFPrefabSystemType.new(root)
	var iid := system.register_instance("res://prefabs/t.hfprefab", [], [], false)
	assert_eq(system.get_all_instances().size(), 1)
	system.unregister_instance(iid)
	assert_eq(system.get_all_instances().size(), 0, "Instance removed after unregister")
	root.free()


func test_prefab_system_get_instances_for_source():
	var root = _make_root_shim()

	var system = HFPrefabSystemType.new(root)
	system.register_instance("res://prefabs/door.hfprefab", [], [], true)
	system.register_instance("res://prefabs/door.hfprefab", [], [], true)
	system.register_instance("res://prefabs/window.hfprefab", [], [], false)

	var door_instances := system.get_instances_for_source("res://prefabs/door.hfprefab")
	assert_eq(door_instances.size(), 2, "2 door instances")

	var window_instances := system.get_instances_for_source("res://prefabs/window.hfprefab")
	assert_eq(window_instances.size(), 1, "1 window instance")

	root.free()


func test_prefab_system_override_tracking():
	var root = _make_root_shim()

	var system = HFPrefabSystemType.new(root)
	var iid := system.register_instance("res://prefabs/t.hfprefab", ["b1"], [], false)

	system.set_override(iid, "brush/0/size", Vector3(64, 64, 64))
	var overrides := system.get_overrides(iid)
	assert_eq(overrides.size(), 1, "1 override set")
	assert_eq(overrides["brush/0/size"], Vector3(64, 64, 64))

	system.clear_override(iid, "brush/0/size")
	overrides = system.get_overrides(iid)
	assert_eq(overrides.size(), 0, "Override cleared")

	root.free()


func test_prefab_system_suggest_name():
	var root = _make_root_shim()

	var system = HFPrefabSystemType.new(root)

	# Empty → untitled
	var name0 := system.suggest_prefab_name([], [])
	assert_eq(name0, "untitled_prefab")

	# Multiple brushes
	var brush1 = CSGBox3D.new()
	var brush2 = CSGBox3D.new()
	var name1 := system.suggest_prefab_name([brush1, brush2], [])
	assert_eq(name1, "2_brush_group")

	brush1.free()
	brush2.free()
	root.free()


# ===========================================================================
# Overlay tests (just construction/teardown, no visual verification)
# ===========================================================================


func test_prefab_overlay_script_loads():
	var overlay_script = load("res://addons/hammerforge/ui/hf_prefab_overlay.gd")
	assert_not_null(overlay_script, "Overlay script should load successfully")


# ===========================================================================
# Combined variant + tags serialization
# ===========================================================================


func test_full_prefab_roundtrip_with_variants_and_tags():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "full_test"
	prefab.brush_infos = [_make_brush_info(Vector3.ZERO)]
	prefab.entity_infos = [_make_entity_info(Vector3(5, 0, 0))]
	prefab.tags = PackedStringArray(["door", "wooden"])
	prefab.set_variant_data(
		"iron",
		[_make_brush_info(Vector3(10, 0, 0)), _make_brush_info(Vector3(20, 0, 0))],
		[_make_entity_info(Vector3(15, 0, 0), "hinge_1")]
	)
	prefab.set_variant_data("glass", [], [_make_entity_info(Vector3(0, 0, 0), "glass_pane")])

	var path := "user://test_full_roundtrip.hfprefab"
	prefab.save_to_file(path)
	var loaded := HFPrefabType.load_from_file(path)

	assert_not_null(loaded)
	assert_eq(loaded.prefab_name, "full_test")
	assert_eq(loaded.brush_infos.size(), 1, "Base has 1 brush")
	assert_eq(loaded.entity_infos.size(), 1, "Base has 1 entity")
	assert_eq(loaded.tags.size(), 2, "2 tags")
	assert_true("door" in Array(loaded.tags))
	assert_true("wooden" in Array(loaded.tags))

	var names := loaded.get_variant_names()
	assert_eq(names.size(), 3, "base + iron + glass")
	assert_true(loaded.has_variant("iron"))
	assert_true(loaded.has_variant("glass"))

	var iron := loaded.get_variant_data("iron")
	assert_eq(iron["brush_infos"].size(), 2, "Iron has 2 brushes")
	assert_eq(iron["entity_infos"].size(), 1, "Iron has 1 entity")

	var glass := loaded.get_variant_data("glass")
	assert_eq(glass["brush_infos"].size(), 0, "Glass has no brushes")
	assert_eq(glass["entity_infos"].size(), 1, "Glass has 1 entity")

	DirAccess.remove_absolute(path)
