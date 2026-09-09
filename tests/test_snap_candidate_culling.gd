extends GutTest

## Precision snap used to transform every vertex of every brush in the level on
## every mouse motion, then measure the whole lot against the pointer. A brush
## that cannot reach the pointer now costs nothing beyond one distance check.
## These tests pin what still has to be reached.

const HFSnapSystem = preload("res://addons/hammerforge/hf_snap_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var snap: HFSnapSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	snap = HFSnapSystem.new(root)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)


func after_each():
	root = null
	snap = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal brush_changed(brush_id: String)
signal brush_removed(brush_id: String)

var draft_brushes_node: Node3D
var preview_brush: Node3D

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out
"""
	s.reload()
	return s


func _make_brush(pos: Vector3, sz: Vector3, brush_id: String) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.brush_id = brush_id
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	return b


func _add_distant_brushes(count: int) -> void:
	for i in range(count):
		_make_brush(Vector3(1000.0 + float(i) * 50.0, 0, 0), Vector3(8, 8, 8), "far_%d" % i)


func _near_query(point: Vector3) -> PackedVector3Array:
	return snap._collect_candidates([], point, snap.snap_threshold)


# ===========================================================================
# Distant brushes cost nothing
# ===========================================================================


func test_a_distant_brush_contributes_no_candidates():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	var alone := _near_query(Vector3(2, 2, 2)).size()
	_add_distant_brushes(1)
	assert_eq(_near_query(Vector3(2, 2, 2)).size(), alone, "A brush 1,000 units away cannot win")


func test_the_candidate_count_does_not_grow_with_the_level():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.EDGE, true)
	snap.set_mode(HFSnapSystem.SnapMode.PERPENDICULAR, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	var query := Vector3(2, 2, 2)
	var small := _near_query(query).size()
	_add_distant_brushes(300)
	var large := _near_query(query).size()
	assert_eq(large, small, "Three hundred brushes elsewhere should change nothing")
	assert_gt(small, 0, "and the brush under the pointer is still collected")


func test_a_distant_brush_centre_is_not_offered():
	snap.set_mode(HFSnapSystem.SnapMode.CENTER, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	_add_distant_brushes(5)
	var candidates := _near_query(Vector3(1, 0, 0))
	assert_eq(candidates.size(), 1, "Only the centre within reach")
	assert_eq(candidates[0], Vector3.ZERO)


func test_no_limit_still_collects_the_whole_level():
	# The geometry tests query without a point, and they expect everything.
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	_add_distant_brushes(3)
	assert_eq(snap._collect_candidates([]).size(), 32, "Four boxes, eight corners each")


# ===========================================================================
# What must still be reached
# ===========================================================================


func test_a_long_wall_is_kept_when_its_far_end_is_under_the_pointer():
	# The origin is 100 units away. Culling on origins alone would drop it.
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(200, 8, 8), "wall")
	var candidates := _near_query(Vector3(100, 4, 4))
	assert_gt(candidates.size(), 0, "The wall's far corner is right under the pointer")
	assert_true(
		Vector3(100, 4, 4) in candidates, "and that corner is one of the candidates offered"
	)


func test_perpendicular_snap_reaches_the_middle_of_a_long_edge():
	# Nothing about this brush is near the pointer except a point along one edge,
	# which is exactly the case a bounding test has to keep.
	snap.set_mode(HFSnapSystem.SnapMode.PERPENDICULAR, true)
	_make_brush(Vector3.ZERO, Vector3(200, 8, 8), "wall")
	var point := Vector3(30, 4, 4)
	var candidates := _near_query(point)
	var best := INF
	for c in candidates:
		best = minf(best, point.distance_to(c))
	assert_almost_eq(best, 0.0, 0.001, "The nearest point on the top edge is the pointer itself")


func test_a_turned_brush_is_kept_by_the_corner_that_swings_towards_the_pointer():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	var b := _make_brush(Vector3.ZERO, Vector3(20, 4, 20), "turned")
	b.rotation = Vector3(0, deg_to_rad(45), 0)
	# A corner of the turned brush lands near here, further out than the
	# unrotated brush would reach along X.
	var corner := Vector3(sqrt(200.0), 2, 0)
	var candidates := _near_query(corner + Vector3(0.5, 0, 0))
	assert_gt(candidates.size(), 0, "The swung corner is in range")


func test_a_scaled_brush_is_measured_after_its_scale():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	var b := _make_brush(Vector3.ZERO, Vector3(4, 4, 4), "big")
	b.scale = Vector3(10, 1, 1)
	# Scaled up, the brush reaches x = 20. Unscaled it would stop at 2.
	assert_gt(_near_query(Vector3(20, 2, 2)).size(), 0, "Scale widens the reach")


func test_a_custom_brush_keeps_its_own_corners():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "cube")
	b.shape = DraftBrush.BrushShape.CUSTOM
	_add_distant_brushes(50)
	var candidates := _near_query(Vector3(16, 16, 16))
	assert_eq(candidates.size(), 8, "The cube's own eight corners, and nothing from far away")


# ===========================================================================
# The rest of the contract
# ===========================================================================


func test_excluded_brushes_are_still_excluded():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	assert_eq(
		snap._collect_candidates(["near"], Vector3(2, 2, 2), snap.snap_threshold).size(),
		0,
		"An excluded brush stays excluded whatever the distance check says"
	)


func test_the_preview_brush_is_still_skipped():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	var preview := _make_brush(Vector3.ZERO, Vector3(4, 4, 4), "preview")
	root.preview_brush = preview
	assert_eq(_near_query(Vector3(2, 2, 2)).size(), 0)


func test_snap_point_still_picks_the_closest_candidate():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "a")
	_make_brush(Vector3(5, 0, 0), Vector3(4, 4, 4), "b")
	# Corners at x = 2 and x = 3 are both within the threshold of x = 2.4.
	assert_eq(snap.snap_point(Vector3(2.4, 2, 2), 0.0), Vector3(2, 2, 2), "The nearer corner wins")
	assert_eq(snap.snap_point(Vector3(2.7, 2, 2), 0.0), Vector3(3, 2, 2))


func test_snap_point_answers_the_same_with_a_level_full_of_distant_brushes():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	var alone := snap.snap_point(Vector3(1.6, 1.6, 1.6), 0.0)
	_add_distant_brushes(200)
	assert_eq(snap.snap_point(Vector3(1.6, 1.6, 1.6), 0.0), alone)


func test_a_point_out_of_reach_of_everything_is_left_alone():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	var point := Vector3(500, 0, 0)
	assert_eq(snap.snap_point(point, 0.0), point, "Nothing in range, so nothing moves")


func test_a_pointer_query_only_measures_the_brushes_it_could_snap_to():
	# Through snap_point, which is the path the viewport actually uses.
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.EDGE, true)
	snap.set_mode(HFSnapSystem.SnapMode.PERPENDICULAR, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "near")
	_add_distant_brushes(300)
	snap.snap_point(Vector3(1.6, 1.6, 1.6), 0.0)
	assert_eq(
		snap.brushes_measured, 1, "Only the brush under the pointer should have been transformed"
	)


func test_the_measured_count_tracks_what_is_in_reach_rather_than_the_level():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	_make_brush(Vector3.ZERO, Vector3(4, 4, 4), "a")
	_make_brush(Vector3(3, 0, 0), Vector3(4, 4, 4), "b")
	_add_distant_brushes(300)
	snap.snap_point(Vector3(1.6, 0, 0), 0.0)
	assert_eq(
		snap.brushes_measured, 2, "Both neighbours are in reach, the other three hundred are not"
	)


# ===========================================================================
# The two ways of asking how far a brush reaches must agree
# ===========================================================================


func _assert_half_extents_agree(brush: DraftBrush, why: String) -> void:
	assert_eq(
		snap._snap_half_extent(brush),
		snap._snap_geometry_local(brush)["half"],
		"The cheap extent and the geometry's own extent disagree for %s" % why
	)


func test_half_extent_agrees_with_the_geometry_for_a_box():
	_assert_half_extents_agree(_make_brush(Vector3.ZERO, Vector3(6, 10, 2), "box"), "a box")


func test_half_extent_agrees_with_the_geometry_for_a_custom_brush():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "cube")
	b.shape = DraftBrush.BrushShape.CUSTOM
	_assert_half_extents_agree(b, "a custom brush")


func test_half_extent_agrees_with_the_geometry_for_a_wedge():
	var b := _make_brush(Vector3.ZERO, Vector3(12, 8, 20), "wedge")
	b.shape = DraftBrush.BrushShape.WEDGE
	_assert_half_extents_agree(b, "a wedge")


func test_half_extent_agrees_with_the_geometry_for_a_faceless_brush():
	# Falls back to the size box in both, which is the case that would drift.
	var b := _make_brush(Vector3.ZERO, Vector3(9, 3, 5), "faceless")
	b.shape = DraftBrush.BrushShape.CUSTOM
	b.faces = []
	_assert_half_extents_agree(b, "a brush with no faces")
