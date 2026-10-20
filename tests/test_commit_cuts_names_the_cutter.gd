extends GutTest
## A cut moved between the level's containers keeps a name its record keeps.
##
## Commit Cuts moved its cutter into the committed container, and Apply Cuts
## into the draft, with `add_child()`, which names a node that lands beside a
## sibling of the same name `@Box_0@14`. A brush's record leaves such a name out
## (#660), so the cutter an undo or a redo rebuilt came back as `Box_0` (#1065)
## and the two captures differed by that one field (#1354). The moves now ask
## Godot for a readable name, which numbers the cutter on past its sibling as a
## new brush is numbered, and a name a mapper typed keeps its stem.

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	# A box and a cut through it, both named by their shape as a drawn brush is:
	# the cut's name is its own in PendingCuts and taken in the draft.
	root.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3(0, 2, 0), "brush_id": "a"}
	)
	var cut := {
		"size": Vector3(2, 2, 2),
		"center": Vector3(0, 2, 0),
		"brush_id": "cut",
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
		"pending": true,
	}
	root.create_brush_from_info(cut)


func _brush_in(container: Node, brush_id: String) -> Node:
	for child in container.get_children():
		if str(child.get("brush_id")) == brush_id:
			return child
	return null


## The records under `key`, before and after `restore_state()` of the level's own
## capture, as a redo rebuilds it.
func _before_and_after_a_rebuild(key: String) -> Array:
	var state: Dictionary = root.capture_state(false)
	root.restore_state(state)
	return [state[key], root.capture_state(false)[key]]


func test_the_fixture_gives_the_cut_the_box_name_in_another_container():
	var box_name := str(_brush_in(root.draft_brushes_node, "a").name)
	assert_false(box_name.begins_with("@"), "the box is named by its shape")
	assert_eq(str(_brush_in(root.pending_node, "cut").name), box_name, "and so is the cut")


func test_the_committed_cutter_is_described_the_same_after_a_redo():
	assert_true(await root.commit_cuts(), "Commit Cuts ran")
	var cutter := _brush_in(root.committed_node, "cut")
	assert_not_null(cutter, "the cutter is committed")
	if cutter == null:
		return
	assert_false(str(cutter.name).begins_with("@"), "under a name of its own: %s" % cutter.name)
	var pair := _before_and_after_a_rebuild("committed")
	assert_eq(pair[1], pair[0], "the record is the same once a redo rebuilt the cutter")


func test_an_applied_cut_is_described_the_same_after_a_redo():
	root.apply_pending_cuts()
	var cut := _brush_in(root.draft_brushes_node, "cut")
	assert_not_null(cut, "the cut is in the draft")
	if cut == null:
		return
	assert_false(str(cut.name).begins_with("@"), "under a name of its own: %s" % cut.name)
	var pair := _before_and_after_a_rebuild("brushes")
	assert_eq(pair[1], pair[0], "the record is the same once a redo rebuilt the cut")


func test_a_cutter_put_back_in_the_draft_is_described_the_same_after_a_redo():
	assert_true(await root.commit_cuts(), "Commit Cuts ran")
	root.restore_committed_cuts()
	var cut := _brush_in(root.draft_brushes_node, "cut")
	assert_not_null(cut, "the cutter is back in the draft")
	if cut == null:
		return
	assert_false(str(cut.name).begins_with("@"), "under a name of its own: %s" % cut.name)
	var pair := _before_and_after_a_rebuild("brushes")
	assert_eq(pair[1], pair[0], "the record is the same once a redo rebuilt the cut")


func test_a_cutter_a_mapper_named_keeps_its_stem():
	_brush_in(root.draft_brushes_node, "a").name = "Doorway"
	_brush_in(root.pending_node, "cut").name = "Doorway"
	root.apply_pending_cuts()
	var cut := _brush_in(root.draft_brushes_node, "cut")
	assert_eq(str(cut.name), "Doorway2", "numbered on past the box, not renamed by its shape")
	assert_true(await root.commit_cuts(), "Commit Cuts ran")
	var cutter := _brush_in(root.committed_node, "cut")
	assert_eq(str(cutter.name), "Doorway2", "and the commit keeps it, with nothing beside it")
