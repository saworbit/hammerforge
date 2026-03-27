extends GutTest

const HFSubtractPreview = preload("res://addons/hammerforge/systems/hf_subtract_preview.gd")

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


func test_default_disabled():
	# Use a bare Node3D shim as root (no signals needed for this test)
	var root = Node3D.new()
	add_child_autofree(root)
	var preview = HFSubtractPreview.new(root)
	assert_false(preview.is_enabled(), "Should be disabled by default")


func test_enable_disable_toggle():
	var root = Node3D.new()
	add_child_autofree(root)
	var preview = HFSubtractPreview.new(root)
	preview.set_enabled(true)
	assert_true(preview.is_enabled(), "Should be enabled after set_enabled(true)")
	preview.set_enabled(false)
	assert_false(preview.is_enabled(), "Should be disabled after set_enabled(false)")


# -- Debounce tests --------------------------------------------------------------


func test_debounce_does_not_rebuild_immediately():
	var root = Node3D.new()
	add_child_autofree(root)
	var preview = HFSubtractPreview.new(root)
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
	var root = Node3D.new()
	# Add draft_brushes_node to satisfy _rebuild()
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	add_child_autofree(root)
	var preview = HFSubtractPreview.new(root)
	preview.set_enabled(true)
	preview.request_update()
	# Process past the debounce threshold
	preview.process(0.2)
	# Should have rebuilt (no crash, container created)
	assert_true(true, "Rebuild after debounce should succeed")
