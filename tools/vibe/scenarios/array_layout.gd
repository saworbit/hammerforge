@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The duplicate-array layouts, measured against the count the same parameters
## are refused or accepted by.
##
## `HFDuplicator` has two answers to "how many copies is this": the length of
## `placements_for()` and `grid_copy_count()`. The dock asks the first, the
## brush system asks the second, and both feed the same `can_generate()` gate.
## Where the two differ, one path refuses a layout the other builds.

const DuplicatorType = preload("res://addons/hammerforge/hf_duplicator.gd")


func id() -> String:
	return "array-layout"


func summary() -> String:
	return "whether the two ways of counting an array's copies give the same answer"


func run() -> void:
	_two_counts_of_one_grid()
	_layouts_at_their_edges()
	await _an_array_built_from_each()


func _two_counts_of_one_grid() -> void:
	var disagreements: Array = []
	for counts in [
		Vector3i(2, 2, 2),
		Vector3i(1, 1, 1),
		Vector3i(4, 1, 1),
		Vector3i(0, 2, 2),
		Vector3i(-1, 2, 2),
		Vector3i(2, -3, 2),
		Vector3i(0, 0, 0),
	]:
		var by_count: int = DuplicatorType.grid_copy_count(counts)
		var by_placements: int = (
			DuplicatorType
			. placements_for(
				DuplicatorType.ArrayMode.GRID, {"counts": counts, "spacing": Vector3(8, 0, 8)}
			)
			. size()
		)
		var gate_count = DuplicatorType.can_generate(by_count, 1, {"spacing": Vector3(8, 0, 8)})
		var gate_placements = DuplicatorType.can_generate(
			by_placements, 1, {"spacing": Vector3(8, 0, 8)}
		)
		note(
			"counts %s" % str(counts),
			(
				"grid_copy_count %d (%s), placements %d (%s)"
				% [
					by_count,
					"allowed" if gate_count.ok else "refused",
					by_placements,
					"allowed" if gate_placements.ok else "refused",
				]
			)
		)
		if gate_count.ok != gate_placements.ok:
			(
				disagreements
				. append(
					(
						"%s: grid_copy_count says %d (%s), placements_for says %d (%s)"
						% [
							str(counts),
							by_count,
							"build it" if gate_count.ok else "refuse it",
							by_placements,
							"build it" if gate_placements.ok else "refuse it",
						]
					)
				)
			)
	if not disagreements.is_empty():
		known(
			542,
			"the two ways of counting an array's copies disagree about whether to build it",
			(
				(
					"`grid_copy_count()` answers -1 for a count below one on any axis so the"
					+ " gate refuses it, and `grid_placements()` clamps the same axis up to one"
					+ " and lays out a smaller array instead. The dock measures an array by"
					+ " `placements_for(...).size()` and the brush system by"
					+ " `grid_copy_count()`, so the same numbers are refused down one path and"
					+ " built down the other: %s"
				)
				% str(disagreements)
			)
		)


func _layouts_at_their_edges() -> void:
	note("linear, count 0", DuplicatorType.linear_placements(0, Vector3(8, 0, 0)).size())
	note("linear, count -5", DuplicatorType.linear_placements(-5, Vector3(8, 0, 0)).size())
	note("linear, NaN offset", DuplicatorType.linear_placements(3, Vector3(NAN, 0, 0)).size())
	note("linear, INF offset", DuplicatorType.linear_placements(3, Vector3(INF, 0, 0)).size())
	note(
		"radial, axis index 7",
		DuplicatorType.radial_placements(3, 7, 45.0, Vector3.ZERO, 0.0).size()
	)
	note(
		"radial, axis index -1",
		DuplicatorType.radial_placements(3, -1, 45.0, Vector3.ZERO, 0.0).size()
	)
	note("radial, NaN step", DuplicatorType.radial_placements(3, 1, NAN, Vector3.ZERO, 0.0).size())
	note(
		"grid, spacing NaN",
		DuplicatorType.grid_placements(Vector3i(2, 2, 2), Vector3(NAN, 0, 0)).size()
	)
	# An axis index nothing recognises still produces placements. Where they land
	# is the thing to look at, not how many there are.
	var odd_axis: Array = DuplicatorType.radial_placements(2, 7, 90.0, Vector3.ZERO, 4.0)
	if not odd_axis.is_empty():
		var placed: Transform3D = odd_axis[0].applied_to(Transform3D.IDENTITY)
		note("radial with axis index 7: first copy lands at", placed.origin)
		note("radial with axis index 7: first copy's basis", placed.basis)
		if placed.origin == Vector3.ZERO and placed.basis.is_equal_approx(Basis.IDENTITY):
			known(
				541,
				"a radial array about an axis that does not exist stacks every copy on the source",
				(
					"`radial_placements()` does not check the axis index; an unrecognised one"
					+ " gives a zero rotation and a zero climb, so the layout builds the"
					+ " requested number of brushes all in the same place as the original"
				)
			)
	note("MAX_COPY_BRUSHES", DuplicatorType.MAX_COPY_BRUSHES)
	var over = DuplicatorType.can_generate(DuplicatorType.MAX_COPY_BRUSHES + 1, 1)
	note("one copy past the budget", over.user_text() if not over.ok else "allowed")


func _an_array_built_from_each() -> void:
	var root: Node3D = await fresh_root("ArrayLevel")
	var source = box(root, Vector3(32, 32, 32))
	await frame()
	var ids := PackedStringArray([str(source.brush_id)])
	var before: int = root.brush_system.get_live_brush_count()
	note("brushes before", before)
	root.create_grid_array(ids, Vector3i(2, 1, 2), Vector3(64, 0, 64))
	await frame()
	note("after a 2x1x2 grid array", root.brush_system.get_live_brush_count())
	note("copies the grid made", root.brush_system.get_live_brush_count() - before)
	if (
		root.brush_system.get_live_brush_count() - before
		!= DuplicatorType.grid_copy_count(Vector3i(2, 1, 2))
	):
		flag(
			"a grid array does not make the number of copies its own count function reports",
			(
				"grid_copy_count says %d, the level gained %d"
				% [
					DuplicatorType.grid_copy_count(Vector3i(2, 1, 2)),
					root.brush_system.get_live_brush_count() - before,
				]
			)
		)
	await frame()
