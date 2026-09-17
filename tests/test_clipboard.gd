extends GutTest

## Copy and paste (#703).
##
## `hf_keymap.gd` bound `duplicate` to Ctrl+D and nothing to Ctrl+C or Ctrl+V,
## and the only operations in the codebase made a copy in place, in the same
## level, immediately. That covers one of the two things duplication is for. The
## one it did not cover is taking a room out of one level and putting it in
## another, which is how people move work between maps and which every editor in
## this lineage has.
##
## A clipboard is a prefab without a name: the same capture, the same file, the
## same placement. What is asserted here is the part that is not a prefab -- that
## it lands where it came from, that it mints its own ids, and that it crosses
## between two levels.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")


func after_each():
	if FileAccess.file_exists(HFPrefabSystemType.CLIPBOARD_PATH):
		DirAccess.remove_absolute(HFPrefabSystemType.CLIPBOARD_PATH)


func _level() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _brush(root: LevelRoot, brush_id: String, at: Vector3, size := Vector3(2, 2, 2)) -> Node3D:
	return root.create_brush_from_info(
		{"shape": 0, "size": size, "center": at, "brush_id": brush_id}
	)


func _brushes(root: LevelRoot) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			out.append(child)
	return out


func _ids(root: LevelRoot) -> Array:
	var out: Array = []
	for brush in _brushes(root):
		out.append(str(brush.brush_id))
	out.sort()
	return out


## A corridor: three brushes in a row, the kind of piece somebody would move.
func _corridor(root: LevelRoot) -> Array:
	var made: Array = []
	for i in 3:
		made.append(_brush(root, "c%d" % i, Vector3(i * 4, 1, 0)))
	return made


# ===========================================================================
# Copy
# ===========================================================================


func test_copying_nothing_puts_nothing_on_the_clipboard():
	var root := _level()
	assert_false(root.prefab_system.copy_to_clipboard([], []))
	assert_true(root.prefab_system.clipboard_is_empty())


func test_copying_a_selection_fills_the_clipboard():
	var root := _level()
	assert_true(root.prefab_system.copy_to_clipboard(_corridor(root), []))
	assert_false(root.prefab_system.clipboard_is_empty())
	var held = root.prefab_system.clipboard_contents()
	assert_not_null(held)
	assert_eq(held.brush_infos.size(), 3, "all three went on it")


func test_copying_changes_nothing_in_the_level():
	var root := _level()
	var before := _ids(root)
	_corridor(root)
	var after_build := _ids(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	assert_eq(_ids(root), after_build, "the level is as it was")
	assert_ne(before, after_build, "and the fixture really did build something")


func test_a_second_copy_replaces_the_first():
	var root := _level()
	_corridor(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	root.prefab_system.copy_to_clipboard([_brushes(root)[0]], [])
	assert_eq(root.prefab_system.clipboard_contents().brush_infos.size(), 1, "the newer one")


# ===========================================================================
# Paste
# ===========================================================================


func test_pasting_an_empty_clipboard_does_nothing():
	var root := _level()
	_corridor(root)
	var before := _ids(root)
	var result: Dictionary = root.prefab_system.paste_from_clipboard()
	assert_eq(result.get("brush_ids", []).size(), 0, "nothing was placed")
	assert_eq(_ids(root), before, "and the level is untouched")


func test_a_paste_lands_where_it_was_copied_from():
	# What Ctrl+C then Ctrl+V means in every editor in this lineage: the copy sits
	# on top of the original, ready to be moved off it.
	var root := _level()
	_corridor(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	root.prefab_system.paste_from_clipboard()
	var positions: Array = []
	for brush in _brushes(root):
		positions.append(brush.position)
	assert_eq(_brushes(root).size(), 6, "three pasted beside the three that were there")
	for original in [Vector3(0, 1, 0), Vector3(4, 1, 0), Vector3(8, 1, 0)]:
		var matches := 0
		for p in positions:
			if (p as Vector3).distance_to(original) < 0.01:
				matches += 1
		assert_eq(matches, 2, "the pasted brush is on top of the one it came from")


func test_a_paste_mints_its_own_brush_ids():
	# `brush_id` is the address for visgroup membership, group membership, the
	# hollow and array records and every Console lookup. Two brushes sharing one
	# is two brushes the level cannot tell apart.
	var root := _level()
	_corridor(root)
	var before := _ids(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	root.prefab_system.paste_from_clipboard()
	var after := _ids(root)
	assert_eq(after.size(), 6)
	assert_eq(after.size(), _unique(after).size(), "no two brushes share an id")
	for brush_id in before:
		assert_true(brush_id in after, "the originals kept theirs")


func _unique(values: Array) -> Array:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.keys()


func test_pasting_twice_gives_two_pieces_rather_than_one():
	var root := _level()
	_corridor(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	root.prefab_system.paste_from_clipboard()
	root.prefab_system.paste_from_clipboard()
	var ids := _ids(root)
	assert_eq(ids.size(), 9, "three, and three, and three")
	assert_eq(ids.size(), _unique(ids).size(), "all of them distinct")


func test_a_paste_can_be_placed_somewhere_else():
	var root := _level()
	_corridor(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	root.prefab_system.paste_from_clipboard(Vector3(0, 20, 0))
	var high := 0
	for brush in _brushes(root):
		if brush.position.y > 15.0:
			high += 1
	assert_eq(high, 3, "the whole piece moved together")


# ===========================================================================
# The thing it exists for
# ===========================================================================


func test_a_piece_crosses_from_one_level_to_another():
	var source := _level()
	_corridor(source)
	assert_true(source.prefab_system.copy_to_clipboard(_brushes(source), []))

	var destination := _level()
	assert_eq(_brushes(destination).size(), 0, "it starts empty")
	var result: Dictionary = destination.prefab_system.paste_from_clipboard()
	assert_eq(result.get("brush_ids", []).size(), 3, "the corridor arrived")
	assert_eq(_brushes(destination).size(), 3)
	assert_eq(_brushes(source).size(), 3, "and the one it came from still has it")


func test_the_clipboard_outlives_the_level_it_was_copied_from():
	# The buffer is a file in `user://`, not something held by a level, so it
	# survives a level being closed and an editor being restarted.
	var source := _level()
	_corridor(source)
	source.prefab_system.copy_to_clipboard(_brushes(source), [])
	source.free()
	var destination := _level()
	assert_eq(destination.prefab_system.paste_from_clipboard().get("brush_ids", []).size(), 3)


func test_a_pasted_piece_is_not_a_linked_prefab_instance():
	# A pasted corridor is geometry. If it registered as an instance of a library
	# asset it would follow that asset when the asset changed, which is not what
	# anybody means by paste.
	var root := _level()
	_corridor(root)
	root.prefab_system.copy_to_clipboard(_brushes(root), [])
	root.prefab_system.paste_from_clipboard()
	assert_eq(root.prefab_system.get_all_instances().size(), 0, "nothing was linked")


# ===========================================================================
# source_centroid, which is what makes "in place" possible
# ===========================================================================


func test_a_capture_records_where_it_came_from():
	var root := _level()
	_corridor(root)
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, _brushes(root), []
	)
	assert_almost_eq(prefab.source_centroid.x, 4.0, 0.01, "the middle of the three")
	assert_almost_eq(prefab.source_centroid.y, 1.0, 0.01)


func test_where_it_came_from_survives_the_file():
	var root := _level()
	_corridor(root)
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, _brushes(root), []
	)
	var back = HFPrefabType.from_dict(prefab.to_dict())
	assert_almost_eq(back.source_centroid.x, prefab.source_centroid.x, 0.001)
	assert_almost_eq(back.source_centroid.y, prefab.source_centroid.y, 0.001)


func test_a_prefab_written_before_this_key_existed_places_at_the_origin():
	var data := {"prefab_name": "old", "brush_infos": [], "entity_infos": []}
	assert_eq(HFPrefabType.from_dict(data).source_centroid, Vector3.ZERO)


func test_a_centroid_that_is_not_a_vector_is_ignored_rather_than_believed():
	var data := {"prefab_name": "odd", "brush_infos": [], "entity_infos": []}
	data["source_centroid"] = "somewhere"
	assert_eq(HFPrefabType.from_dict(data).source_centroid, Vector3.ZERO)
