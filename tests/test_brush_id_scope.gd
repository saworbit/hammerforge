extends GutTest

## What a brush id is the address of (#696).
##
## `brush_id` is how everything that refers to a brush without holding a
## reference finds it: visgroup and group membership, the hollow and array
## records, `nudge_brushes_by_id`, `tie_brushes_to_entity`, the Console's
## lookups. Saving a piece of level as its own scene and instancing it twice
## puts the same set of ids in one scene tree, because a saved scene freezes
## the ids it had.
##
## The rule is that **an id is unique within one level, not within a scene**.
## That is the cheaper of the two answers the issue offered and the one that
## keeps the property the prefab system deliberately relies on: re-minting on
## entry would make ids unstable across loads, and a saved level piece would
## stop being the same piece each time it was opened.
##
## Which makes the load-bearing claim "every lookup resolves inside its own
## root", and the thing actually worth catching two brushes in *one* level
## sharing an id. Both are asserted here.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _level() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _brush(root: LevelRoot, brush_id: String, at: Vector3) -> Node3D:
	return root.create_brush_from_info(
		{"shape": 0, "size": Vector3(2, 2, 2), "center": at, "brush_id": brush_id}
	)


## The duplicate-id issues a level reports, as a list rather than as a loop.
##
## A `for issue in ...: assert_false(...)` makes no assertion at all when the
## list is empty, which is the case these tests are mostly about: it would pass
## whatever the validator did.
func _duplicate_id_issues(root: LevelRoot) -> Array:
	var out: Array = []
	for issue in root.validate_level().get("issues", []):
		if str(issue).to_lower().contains("more than one brush"):
			out.append(str(issue))
	return out


# ===========================================================================
# The rule: an id is unique within one level
# ===========================================================================


func test_two_levels_may_hold_the_same_id_and_each_finds_its_own():
	# This is the arrangement instancing a saved piece twice produces, and it is
	# supported. What must not happen is one level answering with the other's
	# brush.
	var first := _level()
	var second := _level()
	var a := _brush(first, "shared_1", Vector3.ZERO)
	var b := _brush(second, "shared_1", Vector3(40, 0, 0))
	assert_ne(a, b, "two different brushes")
	assert_eq(first.find_brush_by_id("shared_1"), a, "the first level finds its own")
	assert_eq(second.find_brush_by_id("shared_1"), b, "and the second finds its own")


func test_a_level_does_not_find_a_brush_that_belongs_to_another_level():
	var first := _level()
	var second := _level()
	_brush(second, "only_in_the_second", Vector3.ZERO)
	assert_null(
		first.find_brush_by_id("only_in_the_second"), "a lookup does not leave its own level"
	)


func test_a_second_level_appearing_does_not_disturb_the_first():
	# Instancing the second copy must not move, renumber or unregister anything
	# in the first.
	var first := _level()
	var kept := _brush(first, "keep_me", Vector3.ZERO)
	var before := first.brush_system.get_live_brush_count()
	var second := _level()
	_brush(second, "keep_me", Vector3(40, 0, 0))
	assert_eq(first.brush_system.get_live_brush_count(), before, "the count is unchanged")
	assert_eq(first.find_brush_by_id("keep_me"), kept, "and it is still the same brush")


func test_ids_minted_live_in_two_levels_do_not_collide():
	# The prefix is `Time.get_ticks_usec()` and the counter is per level, so two
	# levels minting at once are distinguished by the clock rather than by
	# design. Worth an assertion, because if the prefix ever became a per-session
	# constant the counters alone would collide immediately.
	var first := _level()
	var second := _level()
	var minted: Dictionary = {}
	for i in 12:
		for root in [first, second]:
			var brush = root.create_brush_from_info(
				{"shape": 0, "size": Vector3.ONE, "center": Vector3(i * 3, 0, 0)}
			)
			var brush_id := str(brush.brush_id)
			assert_false(minted.has(brush_id), "id %s was minted twice" % brush_id)
			minted[brush_id] = true
	assert_eq(minted.size(), 24)


# ===========================================================================
# What is genuinely broken: two brushes in one level sharing an id
# ===========================================================================


func test_two_brushes_in_one_level_sharing_an_id_is_reported():
	# One of them is unreachable: `_brush_cache` is keyed by id, so the second
	# overwrites the first and every lookup afterwards answers with one of the
	# two. A hand-edited `.hflevel`, a `.tscn` where a DraftBrush was copied with
	# Godot's own node duplication, or a record that names the same id twice all
	# produce it, and nothing said so.
	var root := _level()
	_brush(root, "twice", Vector3.ZERO)
	_brush(root, "twice", Vector3(8, 0, 0))
	var reported := _duplicate_id_issues(root)
	assert_eq(reported.size(), 1, "one issue, for the one id: %s" % str(reported))
	assert_true(reported[0].contains("twice"), "and it names the id: %s" % reported[0])


func test_a_level_whose_ids_are_all_distinct_reports_nothing_about_them():
	var root := _level()
	for i in 4:
		_brush(root, "b%d" % i, Vector3(i * 8, 0, 0))
	assert_eq(_duplicate_id_issues(root).size(), 0, "nothing about duplicate ids")


func test_the_other_level_does_not_make_this_one_look_duplicated():
	# The check has to be per level, or the supported arrangement above would
	# report every brush in both copies.
	var first := _level()
	var second := _level()
	_brush(first, "shared_1", Vector3.ZERO)
	_brush(second, "shared_1", Vector3(40, 0, 0))
	assert_eq(_duplicate_id_issues(first).size(), 0, "one brush each is not a duplicate")
	assert_eq(_duplicate_id_issues(second).size(), 0)


func test_a_brush_with_no_id_is_not_read_as_a_duplicate_of_another():
	# An empty id is the absence of one, not a value two brushes can share.
	var root := _level()
	for i in 3:
		var brush = root.create_brush_from_info(
			{"shape": 0, "size": Vector3.ONE, "center": Vector3(i * 4, 0, 0)}
		)
		brush.set_meta("brush_id", "")
		brush.brush_id = ""
	assert_eq(_duplicate_id_issues(root).size(), 0, "blank ids are not duplicates")
