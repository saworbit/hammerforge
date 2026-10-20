extends GutTest

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
const DraftBrushType = preload("res://addons/hammerforge/brush_instance.gd")
const HFPluginPointerTools = preload("res://addons/hammerforge/plugin_pointer_tools.gd")


## The real LevelRoot, in the tree so `_ready()` builds the systems the prefab
## system reaches through.
func _make_level_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func test_prefab_removes_property_identified_brushes_from_all_brush_containers():
	for container_name in [&"pending_node", &"committed_node"]:
		var root := _make_level_root()
		var brush := DraftBrushType.new()
		brush.brush_id = "brush_%s" % container_name
		root.get(container_name).add_child(brush)
		var system: HFPrefabSystemType = root.prefab_system
		var iid := system.register_instance("res://prefabs/test.hfprefab", [brush.brush_id], [])
		assert_eq(brush.get_meta("hf_prefab_instance", ""), iid, "brush was found and tagged")
		system._remove_instance_nodes(system.get_instance(iid))
		assert_null(brush.get_parent(), "%s brush was removed" % container_name)
		if is_instance_valid(brush):
			brush.free()


func test_prefab_finds_brush_entities_in_the_committed_container():
	var root := _make_level_root()
	var brush_entity := DraftBrushType.new()
	root.committed_node.add_child(brush_entity)
	var system: HFPrefabSystemType = root.prefab_system
	var iid := system.register_instance("res://prefabs/test.hfprefab", [], [brush_entity])
	assert_eq(
		brush_entity.get_meta("hf_prefab_instance", ""), iid, "brush entity was found and tagged"
	)
	system._remove_instance_nodes(system.get_instance(iid))
	assert_null(brush_entity.get_parent(), "committed brush entity was removed")
	if is_instance_valid(brush_entity):
		brush_entity.free()


func test_prefab_removal_warns_when_recorded_members_are_missing():
	var root := _make_level_root()
	var system: HFPrefabSystemType = root.prefab_system
	var rec = HFPrefabSystemType.PrefabInstanceRecord.new()
	rec.instance_id = "pfx_missing"
	rec.brush_ids = ["missing_brush"]
	rec.entity_uids = ["missing_entity"]
	system._remove_instance_nodes(rec)
	assert_push_warning("brush 'missing_brush' was not found during removal")
	assert_push_warning("entity 'missing_entity' was not found during removal")


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
# PrefabSystem unit tests
# ===========================================================================


func test_prefab_system_suggest_name_single_brush():
	# Test the name suggestion logic without a full LevelRoot
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "test"
	# Just verify the prefab itself works
	assert_eq(prefab.prefab_name, "test")


func test_prefab_system_capture_restore_state():
	# Validate PrefabSystem serialization round-trip
	var root := _make_level_root()
	var system: HFPrefabSystemType = root.prefab_system

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

	# Restore into a new system, on purpose: one that has never seen these instances
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


## Where an instance is has one definition. A prefab's brush transforms are
## stored relative to the merged visual AABB centre of the selection, and
## `instantiate()` adds the placement back onto that - so a variant swap that
## re-places the instance at the mean of the node origins moves it by the
## difference between the two, every press, and recomputing against the new
## nodes means cycling back does not bring it home.
func test_the_variant_swap_measures_the_instance_the_way_the_capture_did():
	var root := _make_level_root()
	var big := DraftBrushType.new()
	big.brush_id = "big"
	big.size = Vector3(128, 16, 16)
	root.draft_brushes_node.add_child(big)
	big.global_position = Vector3.ZERO
	var small := DraftBrushType.new()
	small.brush_id = "small"
	small.size = Vector3(16, 16, 16)
	root.draft_brushes_node.add_child(small)
	small.global_position = Vector3(96, 0, 0)

	var system: HFPrefabSystemType = root.prefab_system
	var iid := system.register_instance("res://prefabs/t.hfprefab", ["big", "small"], [])
	var rec = system.get_instance(iid)

	var capture_point: Vector3 = HFPrefabType.compute_selection_centroid([big, small], [])
	assert_eq(
		system._instance_centroid(rec),
		capture_point,
		"The swap and the capture measure the same point"
	)


func test_prefab_system_unregister():
	var root := _make_level_root()

	var system: HFPrefabSystemType = root.prefab_system
	var iid := system.register_instance("res://prefabs/t.hfprefab", [], [], false)
	assert_eq(system.get_all_instances().size(), 1)
	system.unregister_instance(iid)
	assert_eq(system.get_all_instances().size(), 0, "Instance removed after unregister")


func test_prefab_system_get_instances_for_source():
	var root := _make_level_root()

	var system: HFPrefabSystemType = root.prefab_system
	system.register_instance("res://prefabs/door.hfprefab", [], [], true)
	system.register_instance("res://prefabs/door.hfprefab", [], [], true)
	system.register_instance("res://prefabs/window.hfprefab", [], [], false)

	var door_instances := system.get_instances_for_source("res://prefabs/door.hfprefab")
	assert_eq(door_instances.size(), 2, "2 door instances")

	var window_instances := system.get_instances_for_source("res://prefabs/window.hfprefab")
	assert_eq(window_instances.size(), 1, "1 window instance")


func test_prefab_system_suggest_name():
	var root := _make_level_root()

	var system: HFPrefabSystemType = root.prefab_system

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


func test_a_lone_entity_names_the_prefab_after_its_type():
	# Object.get() takes one argument, so asking it for a default was a script
	# error and a blank name.
	var system: HFPrefabSystemType = _make_level_root().prefab_system
	var lamp := DraftEntity.new()
	lamp.entity_type = "light_point"
	assert_eq(system.suggest_prefab_name([], [lamp]), "light_point")
	lamp.entity_type = ""
	assert_eq(system.suggest_prefab_name([], [lamp]), "entity")
	lamp.free()


func test_a_lone_brush_names_the_prefab_after_its_shape():
	# The shape was read from a meta nothing sets, so every brush was a box.
	var system: HFPrefabSystemType = _make_level_root().prefab_system
	var brush := DraftBrushType.new()
	brush.shape = LevelRoot.BrushShape.CYLINDER
	assert_eq(system.suggest_prefab_name([brush], []), "cylinder")
	brush.shape = LevelRoot.BrushShape.BOX
	assert_eq(system.suggest_prefab_name([brush], []), "box")
	brush.free()
	var plain := CSGBox3D.new()
	assert_eq(system.suggest_prefab_name([plain], []), "box", "a node with no shape")
	plain.free()


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


# ===========================================================================
# One list of link keys (#1339), one lookup for the copy a node is in (#1340)
# ===========================================================================


func _brush_in(root: LevelRoot, brush_id: String) -> DraftBrush:
	var brush := DraftBrushType.new()
	brush.brush_id = brush_id
	root.draft_brushes_node.add_child(brush)
	return brush


func test_untag_takes_every_link_off_a_node():
	# The four names are what saved scenes hold, so they are pinned here as
	# written.
	var node := Node3D.new()
	autofree(node)
	var keys := [
		"hf_prefab_entity_id", "hf_prefab_instance", "hf_prefab_source", "hf_prefab_variant"
	]
	for key in keys:
		node.set_meta(key, "x")
	HFPrefabSystemType.untag(node)
	for key in keys:
		assert_false(node.has_meta(key), "%s is off" % key)
	assert_eq(Array(HFPrefabSystemType.LINK_META).map(func(k): return str(k)), keys)


func test_a_node_is_a_piece_of_the_copy_its_tag_names():
	var root := _make_level_root()
	var brush := _brush_in(root, "a")
	var system: HFPrefabSystemType = root.prefab_system
	var iid := system.register_instance("res://prefabs/t.hfprefab", ["a"], [])
	var record = system.instance_of(brush)
	assert_not_null(record, "the brush is a piece")
	if record:
		assert_eq(record.instance_id, iid, "of the copy its tag names")
	assert_null(system.instance_of(root.draft_brushes_node), "an untagged node is a piece of none")


func test_a_tag_naming_no_record_makes_no_piece():
	# A saved scene can bring in the tag of a copy the level's records do not
	# hold. The badge and the bridge checked the record for themselves; the
	# hover overlay was handed the tag.
	var root := _make_level_root()
	var brush := _brush_in(root, "a")
	brush.set_meta("hf_prefab_instance", "pfx_9")
	assert_null(root.prefab_system.instance_of(brush))


func test_the_lookup_walks_up_to_a_tagged_ancestor_only_when_asked():
	var root := _make_level_root()
	var brush := _brush_in(root, "a")
	var body := Node3D.new()
	brush.add_child(body)
	var system: HFPrefabSystemType = root.prefab_system
	var iid := system.register_instance("res://prefabs/t.hfprefab", ["a"], [])
	assert_null(system.instance_of(body), "the body carries no tag of its own")
	var record = system.instance_of(body, true)
	assert_not_null(record, "asked to, the lookup finds the brush above it")
	if record:
		assert_eq(record.instance_id, iid)
	root.set_meta("hf_prefab_instance", iid)
	assert_null(system.instance_of(root.draft_brushes_node, true), "and stops below the level")


func test_the_hover_overlay_marks_a_copy_and_not_a_tag_whose_copy_is_gone():
	# The ray the pointer casts hits a physics body, and the brush carrying the
	# link is above it. The pointer walked up to the tag and handed the overlay
	# whatever it named, so a tag a saved scene brought in for a copy that was
	# gone counted as a hovered copy (#1340).
	var root := _make_level_root()
	var brush = root.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3.ZERO, "brush_id": "a"}
	)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 4)
	shape.shape = box
	body.add_child(shape)
	brush.add_child(body)
	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 0, 40)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at: Vector2 = camera.unproject_position(Vector3.ZERO)
	var iid: String = root.prefab_system.register_instance("res://prefabs/t.hfprefab", ["a"], [])

	HFPluginPointerTools.update_prefab_hover(root, camera, at)
	assert_eq(root.prefab_overlay._active_instance_id, iid, "hovering a piece marks its copy")
	assert_not_null(root.prefab_overlay._overlay_mesh_instance, "and draws the ghost")

	root.prefab_system.unregister_instance(iid)
	brush.set_meta("hf_prefab_instance", "pfx_9")
	HFPluginPointerTools.update_prefab_hover(root, camera, at)
	assert_eq(root.prefab_overlay._active_instance_id, "", "a tag naming no copy marks nothing")
	assert_null(root.prefab_overlay._overlay_mesh_instance, "and draws no ghost")
	await get_tree().process_frame
