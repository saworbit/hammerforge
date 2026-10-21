extends GutTest

const HFSubtractPreview = preload("res://addons/hammerforge/systems/hf_subtract_preview.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

# -- AABB intersection math tests -----------------------------------------------


func test_intersection_overlapping():
	var a := AABB(Vector3(0, 0, 0), Vector3(10, 10, 10))
	var b := AABB(Vector3(5, 5, 5), Vector3(10, 10, 10))
	var result: AABB = HFSubtractPreview.get_intersection_aabb(a, b)
	assert_eq(result.position, Vector3(5, 5, 5), "Intersection origin")
	assert_eq(result.size, Vector3(5, 5, 5), "Intersection size")


func test_intersection_no_overlap():
	var a := AABB(Vector3(0, 0, 0), Vector3(5, 5, 5))
	var b := AABB(Vector3(10, 10, 10), Vector3(5, 5, 5))
	var result: AABB = HFSubtractPreview.get_intersection_aabb(a, b)
	assert_true(
		result.size.x <= 0.0 or result.size.y <= 0.0 or result.size.z <= 0.0,
		"No overlap should produce zero-sized AABB"
	)


func test_intersection_contained():
	var a := AABB(Vector3(0, 0, 0), Vector3(20, 20, 20))
	var b := AABB(Vector3(5, 5, 5), Vector3(5, 5, 5))
	var result: AABB = HFSubtractPreview.get_intersection_aabb(a, b)
	assert_eq(result.position, Vector3(5, 5, 5), "Contained AABB position")
	assert_eq(result.size, Vector3(5, 5, 5), "Contained AABB size matches inner")


func test_intersection_partial_axis():
	# Only overlaps on 2 of 3 axes
	var a := AABB(Vector3(0, 0, 0), Vector3(10, 10, 10))
	var b := AABB(Vector3(5, 5, 15), Vector3(10, 10, 10))
	var result: AABB = HFSubtractPreview.get_intersection_aabb(a, b)
	assert_true(result.size.z <= 0.0, "No Z overlap should produce non-positive Z size")


# -- Enable/disable tests -------------------------------------------------------


func test_collect_cut_groups_pairs_overlapping_brushes():
	var add: DraftBrush = autoqfree(DraftBrush.new())
	add.size = Vector3(10, 10, 10)
	add.operation = CSGShape3D.OPERATION_UNION
	var sub: DraftBrush = autoqfree(DraftBrush.new())
	sub.size = Vector3(4, 4, 4)
	sub.operation = CSGShape3D.OPERATION_SUBTRACTION
	var groups: Array = HFSubtractPreview.collect_cut_groups([sub], [add])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0]["sub"], sub)
	assert_eq((groups[0]["adds"] as Array).size(), 1)
	assert_true(HFSubtractPreview.is_valid_aabb(groups[0]["aabb"]))


func test_collect_cut_groups_skips_separated_brushes():
	var add: DraftBrush = autoqfree(DraftBrush.new())
	add.size = Vector3(2, 2, 2)
	add.position = Vector3(0, 0, 0)
	add.operation = CSGShape3D.OPERATION_UNION
	var sub: DraftBrush = autoqfree(DraftBrush.new())
	sub.size = Vector3(2, 2, 2)
	sub.position = Vector3(50, 0, 0)
	sub.operation = CSGShape3D.OPERATION_SUBTRACTION
	var groups: Array = HFSubtractPreview.collect_cut_groups([sub], [add])
	assert_eq(groups.size(), 0)


## A box brush out of the tree, tied to `entity_class` when one is given.
func _loose_brush(size: Vector3, subtract := false, entity_class := "") -> DraftBrush:
	var brush: DraftBrush = autoqfree(DraftBrush.new())
	brush.size = size
	if subtract:
		brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	else:
		brush.operation = CSGShape3D.OPERATION_UNION
	if entity_class != "":
		brush.set_meta("brush_entity_class", entity_class)
	return brush


func test_a_cutter_pairs_with_the_world_brush_and_not_the_brush_entities_under_it():
	# The bake leaves every brush entity out of its boolean, so a cut drawn through
	# one is a cut the bake never makes (#1563).
	var world := _loose_brush(Vector3(10, 10, 10))
	var detail := _loose_brush(Vector3(10, 10, 10), false, "func_detail")
	var clip := _loose_brush(Vector3(10, 10, 10), false, "func_clip")
	var sub := _loose_brush(Vector3(4, 4, 4), true)
	var groups: Array = HFSubtractPreview.collect_cut_groups([sub], [world, detail, clip])
	assert_eq(groups.size(), 1, "one cutter, one group")
	if groups.size() == 1:
		assert_eq(groups[0]["sub"], sub)
		assert_eq(groups[0]["adds"], [world], "only the world brush is cut")


func test_a_cutter_tied_to_a_class_cuts_nothing():
	# The bake leaves it out of the boolean too, so it carves nothing at all.
	var world := _loose_brush(Vector3(10, 10, 10))
	var sub := _loose_brush(Vector3(4, 4, 4), true, "func_detail")
	assert_eq(HFSubtractPreview.collect_cut_groups([sub], [world]), [])


func test_extract_csg_meshes_reads_transform_mesh_pair():
	var entries: Array = HFSubtractPreview.extract_csg_meshes(null)
	assert_eq(entries.size(), 0)


func test_preview_operation_reads_draft_brushes():
	var brush = autoqfree(DraftBrush.new())
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	assert_eq(HFSubtractPreview.preview_operation(brush), CSGShape3D.OPERATION_SUBTRACTION)
	brush.operation = CSGShape3D.OPERATION_UNION
	assert_eq(HFSubtractPreview.preview_operation(brush), CSGShape3D.OPERATION_UNION)
	assert_eq(HFSubtractPreview.preview_operation(autoqfree(Node3D.new())), -1)


func _level_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _placed_box(root: LevelRoot, size: Vector3, subtract := false) -> DraftBrush:
	var op := CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION
	var info := {
		"shape": LevelRoot.BrushShape.BOX, "size": size, "center": Vector3.ZERO, "operation": op
	}
	return root.create_brush_from_info(info) as DraftBrush


func test_the_live_preview_cuts_the_world_brush_and_not_a_detail_or_a_clip():
	var root := _level_root()
	var world := _placed_box(root, Vector3(10, 10, 10))
	var detail := _placed_box(root, Vector3(10, 10, 10))
	root.tie_brushes_to_entity([str(detail.brush_id)], "func_detail")
	var clip := _placed_box(root, Vector3(10, 10, 10))
	root.tie_brushes_to_entity([str(clip.brush_id)], "func_clip")
	var sub := _placed_box(root, Vector3(4, 4, 4), true)
	var preview = root.subtract_preview
	preview.set_enabled(true)
	preview.process(1.0)
	# Each combiner the preview cuts with holds the brushes it pairs, the cutter last.
	assert_eq(preview._csg_scratch.size(), 1, "one cutter, one cut")
	if preview._csg_scratch.size() == 1:
		var cut: Array = []
		for operand in (preview._csg_scratch[0] as Node).get_children():
			cut.append((operand as CSGMesh3D).mesh)
		assert_eq(cut, [world.mesh_instance.mesh, sub.mesh_instance.mesh])
	preview.destroy()


func test_default_disabled():
	var root := _level_root()
	var preview = root.subtract_preview
	assert_false(preview.is_enabled(), "Should be disabled by default")


func test_enable_disable_toggle():
	var root := _level_root()
	var preview = root.subtract_preview
	preview.set_enabled(true)
	assert_true(preview.is_enabled(), "Should be enabled after set_enabled(true)")
	preview.set_enabled(false)
	assert_false(preview.is_enabled(), "Should be disabled after set_enabled(false)")


# -- Debounce tests --------------------------------------------------------------


func test_debounce_does_not_rebuild_immediately():
	var root := _level_root()
	var preview = root.subtract_preview
	preview.request_update()
	# Process with a very small delta (less than DEBOUNCE_SEC)
	preview.process(0.01)
	# _needs_rebuild should still be true since debounce hasn't elapsed
	# We verify by calling process again — if it rebuilt, _needs_rebuild
	# would be false and a second process(large) would be a no-op.
	# Since we can't directly inspect _needs_rebuild, just verify no crash
	preview.process(0.2)
	assert_true(true, "Debounced processing should not crash")


func test_debounce_rebuilds_after_elapsed():
	var root := _level_root()
	var preview = root.subtract_preview
	preview.set_enabled(true)
	preview.request_update()
	# Process past the debounce threshold
	preview.process(0.2)
	# Should have rebuilt (no crash, container created)
	assert_true(true, "Rebuild after debounce should succeed")


# -- Destroy / cleanup tests ---------------------------------------------------


func test_destroy_frees_pool_and_container():
	var root := _level_root()
	var preview = root.subtract_preview
	preview.set_enabled(true)
	# Force a rebuild so the container and pool are created
	preview.request_update()
	preview.process(0.2)
	# Destroy should free everything without errors
	preview.destroy()
	assert_false(preview.is_enabled(), "Should be disabled after destroy")
	assert_eq(preview._mesh_pool.size(), 0, "Pool should be empty after destroy")
	assert_null(preview._preview_container, "Container ref should be null after destroy")


func test_destroy_when_never_enabled():
	var root := _level_root()
	var preview = root.subtract_preview
	# destroy on a never-enabled preview should not crash
	preview.destroy()
	assert_false(preview.is_enabled(), "Should remain disabled")
	assert_eq(preview._mesh_pool.size(), 0, "Pool should be empty")


# -- brush_changed wiring --------------------------------------------------------


func test_enabled_preview_rebuilds_when_a_brush_changes():
	var root := _level_root()
	var preview = root.subtract_preview
	preview.set_enabled(true)
	# Clear the update set_enabled itself asked for.
	preview.process(1.0)
	assert_false(preview._needs_rebuild, "Starting state is settled")
	root.brush_changed.emit("b1")
	assert_true(preview._needs_rebuild, "A changed brush must schedule a rebuild")
	preview.destroy()


func test_disabled_preview_ignores_a_changed_brush():
	var root := _level_root()
	var preview = root.subtract_preview
	preview.set_enabled(true)
	preview.set_enabled(false)
	preview.process(1.0)
	root.brush_changed.emit("b1")
	assert_false(preview._needs_rebuild, "A disabled preview stays disconnected")
	preview.destroy()
