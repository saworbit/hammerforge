extends GutTest

## The micro-gap and non-manifold scans bucket points into a grid. Those keys
## used to be formatted strings and are now grid indices, which is a large speed
## difference and must be no behaviour difference at all. These pin the bucketing
## itself rather than only the issues it leads to.

const HFValidationSystem = preload("res://addons/hammerforge/systems/hf_validation_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var val_sys: HFValidationSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	var committed = Node3D.new()
	committed.name = "Committed"
	root.add_child(committed)
	root.committed_node = committed
	val_sys = HFValidationSystem.new(root)


func after_each():
	root = null
	val_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var committed_node: Node3D

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")
"""
	s.reload()
	return s


# ===========================================================================
# Bucketing
# ===========================================================================


func test_points_inside_the_tolerance_share_a_cell():
	var a := val_sys._snap_key(Vector3(1.0, 2.0, 3.0), 0.01)
	var b := val_sys._snap_key(Vector3(1.002, 2.001, 2.998), 0.01)
	assert_eq(a, b, "A nudge well under the tolerance is the same cell")


func test_points_beyond_the_tolerance_do_not_share_a_cell():
	var a := val_sys._snap_key(Vector3(1.0, 2.0, 3.0), 0.001)
	var b := val_sys._snap_key(Vector3(1.05, 2.0, 3.0), 0.001)
	assert_ne(a, b, "Fifty tolerances apart is a different cell")


func test_negative_coordinates_bucket_the_same_way():
	# Rounding across zero is where an index scheme most easily disagrees with
	# the snapped positions it replaced.
	var a := val_sys._snap_key(Vector3(-1.0, -2.0, -3.0), 0.01)
	var b := val_sys._snap_key(Vector3(-1.002, -2.001, -2.998), 0.01)
	assert_eq(a, b, "Negative coordinates cell together the same as positive")
	assert_ne(
		val_sys._snap_key(Vector3(-1.0, 0.0, 0.0), 0.01),
		val_sys._snap_key(Vector3(1.0, 0.0, 0.0), 0.01),
		"and either side of zero is not the same cell"
	)


func test_the_cell_matches_the_snapped_position_it_replaced():
	# The index has to be the snapped position divided by the step, or the grid
	# has silently moved.
	var tol := 0.01
	for v in [Vector3(1.234, -5.678, 9.0), Vector3.ZERO, Vector3(-0.004, 0.006, -0.5)]:
		var key: Vector3i = val_sys._snap_key(v, tol)
		var expected := Vector3i(
			roundi(snapped(v.x, tol) / tol),
			roundi(snapped(v.y, tol) / tol),
			roundi(snapped(v.z, tol) / tol)
		)
		assert_eq(key, expected, "Cell for %s" % v)


# ===========================================================================
# The neighbourhood
# ===========================================================================


func test_the_neighbourhood_is_twenty_seven_distinct_cells():
	var keys: Array = val_sys._cell_keys(Vector3(1.0, 2.0, 3.0), 0.01)
	assert_eq(keys.size(), 27, "Own cell plus twenty-six neighbours")
	var seen := {}
	for k in keys:
		seen[k] = true
	assert_eq(seen.size(), 27, "and none of them repeat")


func test_the_neighbourhood_contains_the_point_own_cell():
	var v := Vector3(1.0, 2.0, 3.0)
	assert_true(
		val_sys._snap_key(v, 0.01) in val_sys._cell_keys(v, 0.01),
		"A point must be found in its own cell"
	)


func test_a_neighbour_across_a_boundary_is_reachable():
	# The reason the neighbourhood exists: two points a hair apart can still
	# land in adjacent cells, and the scan has to look next door.
	var tol := 0.01
	var a := Vector3(1.0049, 0.0, 0.0)
	var b := Vector3(1.0051, 0.0, 0.0)
	assert_ne(val_sys._snap_key(a, tol), val_sys._snap_key(b, tol), "They straddle a boundary")
	assert_true(
		val_sys._snap_key(b, tol) in val_sys._cell_keys(a, tol),
		"so each must appear in the other's neighbourhood"
	)


# ===========================================================================
# Edges
# ===========================================================================


func test_an_edge_reads_the_same_both_ways_round():
	var a := Vector3(1.0, 2.0, 3.0)
	var b := Vector3(4.0, 5.0, 6.0)
	assert_eq(val_sys._edge_key(a, b), val_sys._edge_key(b, a), "(A,B) and (B,A) are one edge")


func test_edges_apart_by_more_than_the_precision_differ():
	assert_ne(
		val_sys._edge_key(Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)),
		val_sys._edge_key(Vector3(1.05, 2.0, 3.0), Vector3(4.0, 5.0, 6.0))
	)


func test_edge_precision_is_fixed_and_ignores_weld_tolerance():
	# Raising the weld tolerance must not collapse distinct edges, or a real
	# non-manifold brush stops being reported.
	val_sys.weld_tolerance = 0.5
	assert_ne(
		val_sys._edge_key(Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)),
		val_sys._edge_key(Vector3(1.05, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)),
		"Edge keys use their own fixed precision"
	)


func test_an_edge_key_works_as_a_dictionary_key():
	# The scans count edges in a Dictionary, so equal keys must collide there
	# and not merely compare equal.
	var counts := {}
	counts[val_sys._edge_key(Vector3(1, 2, 3), Vector3(4, 5, 6))] = 1
	var same: Array = val_sys._edge_key(Vector3(4, 5, 6), Vector3(1, 2, 3))
	assert_true(counts.has(same), "The same edge from either end is one entry")
	counts[same] = int(counts[same]) + 1
	assert_eq(counts.size(), 1, "so the dictionary holds one edge")
	assert_eq(counts[same], 2, "counted twice, which is what manifold means")


func test_a_cell_key_works_as_a_dictionary_key():
	var cells := {}
	cells[val_sys._snap_key(Vector3(1.0, 2.0, 3.0), 0.01)] = "first"
	var same: Vector3i = val_sys._snap_key(Vector3(1.001, 2.0, 3.0), 0.01)
	assert_true(cells.has(same), "Points in one cell collide in the dictionary")
