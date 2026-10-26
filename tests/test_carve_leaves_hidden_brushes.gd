extends GutTest

## A mapper hides the outer walls to work inside a room. Carving a doorway
## through an inner wall cut the hidden outer wall as well, and its pieces came
## back shown until something refreshed the visgroups (#1710).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, brush_id: String, size: Vector3, at: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
			}
		)
	)


## Two walls the cutter overlaps, the outer one in a hidden visgroup.
func _room(root: LevelRoot) -> void:
	_box(root, "near_wall", Vector3(8, 4, 1), Vector3(0, 2, -3))
	var outer := _box(root, "hidden_wall", Vector3(8, 4, 1), Vector3(0, 2, -4))
	_box(root, "door_cutter", Vector3(2, 3, 4), Vector3(0, 2, -3.5))
	root.add_selection_to_visgroup("outer", [outer])
	root.set_visgroup_visible("outer", false)


func _in_visgroup(root: LevelRoot, vg_name: String) -> Array:
	return root._iter_managed_brush_nodes().filter(
		func(b): return Array(b.get_meta("visgroups", PackedStringArray())).has(vg_name)
	)


func test_carve_leaves_a_hidden_wall_whole_and_says_so():
	var root := _fresh_root()
	_room(root)
	assert_eq(root.carve_system.hidden_overlaps("door_cutter"), 1, "one hidden wall overlaps")
	var result: HFOpResult = root.carve_with_brush("door_cutter")
	assert_true(result.ok, result.message)
	assert_string_contains(result.message, "carved 1 brush(es)")
	assert_string_contains(result.message, "left 1 hidden brush(es) alone")
	var outer := _in_visgroup(root, "outer")
	assert_eq(outer.size(), 1, "the hidden wall is still one brush")
	assert_not_null(root.brush_system.find_brush_by_id("hidden_wall"), "by its own id")
	assert_null(root.brush_system.find_brush_by_id("near_wall"), "the shown wall was cut")


func test_a_carver_over_only_hidden_brushes_says_why_it_cuts_nothing():
	var root := _fresh_root()
	var outer := _box(root, "hidden_wall", Vector3(8, 4, 1), Vector3(0, 2, -4))
	_box(root, "door_cutter", Vector3(2, 3, 2), Vector3(0, 2, -4))
	root.add_selection_to_visgroup("outer", [outer])
	root.set_visgroup_visible("outer", false)
	var check: HFOpResult = root.can_carve_brush("door_cutter")
	assert_false(check.ok, "nothing shown to cut")
	assert_string_contains(check.fix_hint, "1 hidden brush(es)")


## A locked brush is left alone the same way. The carver reaches past the
## selection to what it overlaps, and nothing changes a locked brush (#1973).
func _locked_room(root: LevelRoot) -> Node:
	_box(root, "near_wall", Vector3(8, 4, 1), Vector3(0, 2, -3))
	var done := _box(root, "done_wall", Vector3(8, 4, 1), Vector3(0, 2, -4))
	_box(root, "door_cutter", Vector3(2, 3, 4), Vector3(0, 2, -3.5))
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [done])
	root.visgroup_system.set_visgroup_locked("Done", true)
	return done


func test_carve_leaves_a_locked_wall_whole_and_says_so():
	var root := _fresh_root()
	var done := _locked_room(root)
	var before: Dictionary = root.get_brush_info_from_node(done)
	assert_eq(root.carve_system.locked_overlaps("door_cutter"), 1, "one locked wall overlaps")
	var result: HFOpResult = root.carve_with_brush("door_cutter")
	assert_true(result.ok, result.message)
	assert_string_contains(result.message, "carved 1 brush(es)")
	assert_string_contains(result.message, "left 1 locked brush(es) alone")
	var still = root.brush_system.find_brush_by_id("done_wall")
	assert_not_null(still, "the locked wall is still there by its own id")
	if still:
		assert_eq(root.get_brush_info_from_node(still), before, "and is as it was")
	assert_eq(_in_visgroup(root, "Done").size(), 1, "with no pieces beside it")
	assert_null(root.brush_system.find_brush_by_id("near_wall"), "the unlocked wall was cut")


func test_a_carver_over_only_locked_brushes_says_why_it_cuts_nothing():
	var root := _fresh_root()
	var done := _box(root, "done_wall", Vector3(8, 4, 1), Vector3(0, 2, -4))
	_box(root, "door_cutter", Vector3(2, 3, 2), Vector3(0, 2, -4))
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [done])
	root.visgroup_system.set_visgroup_locked("Done", true)
	var check: HFOpResult = root.can_carve_brush("door_cutter")
	assert_false(check.ok, "nothing unlocked to cut")
	assert_string_contains(check.fix_hint, "1 locked brush(es). Unlock them")
	assert_not_null(root.brush_system.find_brush_by_id("door_cutter"), "the carver is kept")


func test_a_piece_of_a_hidden_visgroup_is_hidden_as_it_is_made():
	var root := _fresh_root()
	var wall := _box(root, "wall", Vector3(4, 2, 1), Vector3(0, 1, 0))
	root.add_selection_to_visgroup("outer", [wall])
	root.set_visgroup_visible("outer", false)
	var info: Dictionary = root.get_brush_info_from_node(wall)
	info.erase("brush_id")
	info["transform"] = Transform3D(Basis.IDENTITY, Vector3(10, 1, 0))
	var piece: Node3D = root.create_brush_from_info(info)
	assert_false(piece.visible, "made hidden, with no refresh in between")


func test_a_brush_of_a_shown_visgroup_is_made_shown():
	var root := _fresh_root()
	var wall := _box(root, "wall", Vector3(4, 2, 1), Vector3(0, 1, 0))
	root.add_selection_to_visgroup("inner", [wall])
	var info: Dictionary = root.get_brush_info_from_node(wall)
	info.erase("brush_id")
	var piece: Node3D = root.create_brush_from_info(info)
	assert_true(piece.visible)


## A brush dragged between DraftBrushes and PendingCuts in the Scene dock keeps
## the look its visgroup gives it, both ways (#1759).
func test_a_hidden_brush_moved_into_and_out_of_the_pending_cuts_stays_hidden():
	var root := _fresh_root()
	var cutter := _box(root, "cutter", Vector3(2, 2, 2), Vector3.ZERO)
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_selection_to_visgroup("outer", [cutter])
	root.set_visgroup_visible("outer", false)
	assert_false(cutter.visible, "fixture: hidden by its visgroup")
	cutter.reparent(root.pending_node)
	root.brush_system.reconcile_external_structure()
	assert_true(cutter.is_pending_cut(), "fixture: now a pending cut")
	assert_false(cutter.visible, "still hidden among the pending cuts")
	cutter.reparent(root.draft_brushes_node)
	root.brush_system.reconcile_external_structure()
	assert_false(cutter.is_pending_cut(), "fixture: back among the brushes")
	assert_false(cutter.visible, "still hidden among the brushes")


func test_a_brush_of_a_shown_visgroup_moved_into_the_pending_cuts_shows():
	var root := _fresh_root()
	var cutter := _box(root, "cutter", Vector3(2, 2, 2), Vector3.ZERO)
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_selection_to_visgroup("inner", [cutter])
	cutter.reparent(root.pending_node)
	root.brush_system.reconcile_external_structure()
	assert_true(cutter.visible, "a shown visgroup shows it")
	cutter.reparent(root.draft_brushes_node)
	root.brush_system.reconcile_external_structure()
	assert_true(cutter.visible, "and shows it back among the brushes")
