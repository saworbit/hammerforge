extends GutTest

## Undo and redo are whole-level snapshots, and `restore_state()` used to free and
## rebuild every brush in the level to take back an edit to one of them (#600). At
## 400 brushes that was 122 ms of a 141 ms undo step.
##
## A brush whose record is identical to what it would capture right now is the
## brush that record describes, so restoring it would put back the brush that is
## already there. Those are kept across the clear and registered again rather than
## rebuilt.
##
## The assertions below are mostly about what a mapper gets, not about how many
## nodes were spared: a restore has to land the same level whether it rebuilt
## everything or nothing. The ones that would catch a brush being kept when it
## should have been rebuilt are the important half, because that is the only way
## this can be wrong.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(at: Vector3, size := Vector3(2, 2, 2)) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _draft_brushes() -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child.has_method("serialize_faces"):
			out.append(child)
	return out


func _ids() -> Array:
	var out: Array = []
	for brush in _draft_brushes():
		out.append(str(brush.brush_id))
	out.sort()
	return out


# ===========================================================================
# The level a restore lands
# ===========================================================================


func test_restoring_an_unchanged_level_leaves_the_same_brushes():
	_box(Vector3.ZERO)
	_box(Vector3(8, 0, 0))
	_box(Vector3(0, 0, 8))
	var before := _ids()
	var snapshot: Dictionary = root.capture_state()

	root.state_system.restore_state(snapshot)

	assert_eq(_ids(), before, "the same brushes, by id")
	assert_eq(_draft_brushes().size(), 3, "and no more of them")


func test_an_untouched_brush_is_the_same_node_after_a_restore():
	# The point of the change: the node survives rather than being replaced by an
	# identical one. If this ever has to stop being true, every other test here
	# still holds, because they are about the level and not about the nodes.
	# Checked on the parent rather than on `is_instance_valid()`: `clear_brushes()`
	# takes a brush out of the tree and then `queue_free()`s it, and the free is
	# deferred to the end of the frame, so a rebuilt brush is still a valid
	# instance for the whole of this test. Being back under `DraftBrushes` is what
	# actually separates kept from rebuilt.
	var kept := _box(Vector3.ZERO)
	_box(Vector3(8, 0, 0))
	var snapshot: Dictionary = root.capture_state()
	var kept_id := kept.get_instance_id()

	root.state_system.restore_state(snapshot)

	assert_true(is_instance_valid(kept), "the untouched brush was not freed")
	assert_eq(kept.get_parent(), root.draft_brushes_node, "it never left the level")
	assert_eq(kept.get_instance_id(), kept_id, "and it is the same node")
	var ids: Array = []
	for brush in _draft_brushes():
		ids.append(brush.get_instance_id())
	assert_true(ids.has(kept_id), "the brush in the level is that same node, not a copy")


func test_a_moved_brush_is_put_back_where_the_snapshot_says():
	# The case the whole thing is for: nudge one brush on a level of several and
	# take it back. The moved one cannot be reused, the rest can, and the level
	# has to come out the same either way.
	var moved := _box(Vector3.ZERO)
	_box(Vector3(8, 0, 0))
	_box(Vector3(0, 0, 8))
	var snapshot: Dictionary = root.capture_state()

	moved.global_position = Vector3(0, 16, 0)
	root.state_system.restore_state(snapshot)

	assert_eq(_draft_brushes().size(), 3, "the level still has three brushes")
	var heights: Array = []
	for brush in _draft_brushes():
		heights.append(roundi(brush.global_position.y))
	assert_false(heights.has(16), "the nudge was taken back, not left at its new height")


func test_a_resized_brush_is_rebuilt_rather_than_kept():
	# A size change is in the record, so the brush fails the comparison and is
	# rebuilt. Keeping it would silently leave the level at the wrong size, which
	# is the one way this can be wrong.
	var resized := _box(Vector3.ZERO, Vector3(2, 2, 2))
	var snapshot: Dictionary = root.capture_state()

	resized.size = Vector3(6, 6, 6)
	root.state_system.restore_state(snapshot)

	var brushes := _draft_brushes()
	assert_eq(brushes.size(), 1, "still one brush")
	assert_eq(brushes[0].size, Vector3(2, 2, 2), "and it is the size the snapshot recorded")


func test_a_brush_added_after_the_snapshot_is_gone_after_a_restore():
	_box(Vector3.ZERO)
	var snapshot: Dictionary = root.capture_state()
	_box(Vector3(8, 0, 0))
	assert_eq(_draft_brushes().size(), 2, "two before the restore")

	root.state_system.restore_state(snapshot)

	assert_eq(_draft_brushes().size(), 1, "the brush the snapshot never had is gone")


func test_a_brush_deleted_after_the_snapshot_comes_back():
	var doomed := _box(Vector3.ZERO)
	_box(Vector3(8, 0, 0))
	var snapshot: Dictionary = root.capture_state()

	root.delete_brush(doomed)
	assert_eq(_draft_brushes().size(), 1, "one after the delete")

	root.state_system.restore_state(snapshot)

	assert_eq(_draft_brushes().size(), 2, "both are back")


# ===========================================================================
# The registries a cleared level no longer holds
# ===========================================================================


func test_a_kept_brush_is_still_in_the_caches_a_restore_clears():
	# `clear_brushes()` empties the id cache, the count and the BrushManager
	# mirror. A brush kept across it has to go back into all three, or it is a
	# node in the tree that nothing can find.
	_box(Vector3.ZERO)
	_box(Vector3(8, 0, 0))
	var snapshot: Dictionary = root.capture_state()

	root.state_system.restore_state(snapshot)

	assert_eq(root.get_live_brush_count(), 2, "the count knows about both")
	assert_eq(root.brush_system.get_cached_brush_count(), 2, "and so does the id cache")
	if root.brush_manager:
		assert_eq(root.brush_manager.brushes.size(), 2, "and the manager mirror")
	for brush in _draft_brushes():
		assert_eq(
			root.brush_system.find_brush_by_id(str(brush.brush_id)),
			brush,
			"every kept brush is findable by its own id"
		)


func test_two_restores_in_a_row_do_not_double_register():
	_box(Vector3.ZERO)
	_box(Vector3(8, 0, 0))
	var snapshot: Dictionary = root.capture_state()

	root.state_system.restore_state(snapshot)
	root.state_system.restore_state(snapshot)

	assert_eq(_draft_brushes().size(), 2, "still two brushes in the tree")
	assert_eq(root.get_live_brush_count(), 2, "and the count did not climb")


# ===========================================================================
# The comparison itself
# ===========================================================================


func test_reusable_draft_brushes_offers_only_what_matches():
	var kept := _box(Vector3.ZERO)
	var moved := _box(Vector3(8, 0, 0))
	var records: Array = root.capture_state().get("brushes", [])
	moved.global_position = Vector3(0, 16, 0)

	var reusable: Dictionary = root.brush_system.reusable_draft_brushes(records)

	assert_true(reusable.has(str(kept.brush_id)), "the untouched brush is offered")
	assert_false(reusable.has(str(moved.brush_id)), "the moved one is not")


func test_nothing_is_offered_against_a_state_with_no_brushes():
	_box(Vector3.ZERO)
	assert_eq(
		root.brush_system.reusable_draft_brushes([]).size(),
		0,
		"a state with no brushes keeps none of them"
	)


func test_a_face_edit_is_seen_even_though_it_is_nested_in_the_record():
	# A record carries its faces as an array of dictionaries, and plain `==` does
	# not go down into those. This is what `recursive_equal` is for: a brush whose
	# geometry moved but whose transform and size did not must still fail.
	var brush := _box(Vector3.ZERO)
	var records: Array = root.capture_state().get("brushes", [])
	assert_gt(brush.faces.size(), 0, "the brush has faces to edit")
	brush.faces[0].local_verts[0] += Vector3(0, 1, 0)

	assert_false(
		root.brush_system.reusable_draft_brushes(records).has(str(brush.brush_id)),
		"a brush whose faces moved is not the brush the record describes"
	)
