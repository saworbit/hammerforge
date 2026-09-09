extends GutTest

## The two subtraction checks used to compare every subtraction against the whole
## brush list and then every subtraction against every other one. These tests pin
## what they report and put a ceiling on how many pairs they look at.

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


func _make_brush(
	parent: Node3D, pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(4, 4, 4), op: int = 0
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.operation = op
	parent.add_child(b)
	b.global_position = pos
	return b


func _cut(parent: Node3D, pos: Vector3, sz: Vector3 = Vector3(4, 4, 4)) -> DraftBrush:
	return _make_brush(parent, pos, sz, CSGShape3D.OPERATION_SUBTRACTION)


func _types(issues: Array, wanted: String) -> Array:
	var found: Array = []
	for issue in issues:
		if issue["type"] == wanted:
			found.append(issue)
	return found


# ===========================================================================
# What the checks report has not moved
# ===========================================================================


func test_a_cut_inside_a_solid_is_not_floating():
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(20, 20, 20))
	_cut(root.draft_brushes_node, Vector3(2, 2, 2))
	assert_eq(_types(val_sys.check_bake_issues(), "floating_subtract").size(), 0)


func test_a_cut_that_only_touches_a_solid_is_still_floating():
	# Boxes that share a face do not intersect, and that was the answer before.
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(4, 4, 4))
	_cut(root.draft_brushes_node, Vector3(4, 0, 0))
	assert_eq(
		_types(val_sys.check_bake_issues(), "floating_subtract").size(),
		1,
		"Touching is not intersecting"
	)


func test_a_cut_reaches_a_solid_in_the_committed_node():
	_make_brush(root.committed_node, Vector3.ZERO, Vector3(20, 20, 20))
	_cut(root.draft_brushes_node, Vector3(2, 2, 2))
	assert_eq(
		_types(val_sys.check_bake_issues(), "floating_subtract").size(),
		0,
		"Committed brushes are solids too"
	)


func test_an_entity_solid_does_not_ground_a_cut():
	var entity = _make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(20, 20, 20))
	entity.set_meta("entity_type", "func_door")
	_cut(root.draft_brushes_node, Vector3(2, 2, 2))
	assert_eq(
		_types(val_sys.check_bake_issues(), "floating_subtract").size(),
		1,
		"An entity brush is not part of the world solid"
	)


func test_an_entity_cut_is_not_checked_at_all():
	var cut = _cut(root.draft_brushes_node, Vector3(500, 0, 0))
	cut.set_meta("entity_type", "func_door")
	assert_eq(_types(val_sys.check_bake_issues(), "floating_subtract").size(), 0)


func test_a_turned_cut_is_measured_by_its_own_size():
	# The box is the brush's size at its origin, rotation and all. Widening it to
	# the turned extent would change which levels report an issue.
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(4, 4, 4))
	var cut = _cut(root.draft_brushes_node, Vector3(3.5, 0, 0))
	cut.rotation = Vector3(0, deg_to_rad(45), 0)
	assert_eq(
		_types(val_sys.check_bake_issues(), "floating_subtract").size(),
		0,
		"The unrotated box still overlaps, which is the answer it always gave"
	)


func test_overlapping_cuts_are_reported_once_per_pair():
	_cut(root.draft_brushes_node, Vector3.ZERO)
	_cut(root.draft_brushes_node, Vector3(1, 0, 0))
	_cut(root.draft_brushes_node, Vector3(2, 0, 0))
	var overlaps = _types(val_sys.check_bake_issues(), "overlapping_subtract")
	assert_eq(overlaps.size(), 3, "Three mutually overlapping cuts make three pairs")


func test_overlapping_cuts_name_both_brushes_in_level_order():
	var first = _cut(root.draft_brushes_node, Vector3.ZERO)
	var second = _cut(root.draft_brushes_node, Vector3(1, 0, 0))
	var overlaps = _types(val_sys.check_bake_issues(), "overlapping_subtract")
	assert_eq(overlaps.size(), 1)
	assert_eq(
		overlaps[0]["message"],
		"Overlapping subtractions: '%s' and '%s'" % [first.name, second.name]
	)
	assert_eq(overlaps[0]["node"], first, "The earlier brush carries the issue")


func test_cuts_that_only_touch_do_not_overlap():
	_cut(root.draft_brushes_node, Vector3.ZERO)
	_cut(root.draft_brushes_node, Vector3(4, 0, 0))
	assert_eq(_types(val_sys.check_bake_issues(), "overlapping_subtract").size(), 0)


func test_far_apart_cuts_do_not_overlap():
	_cut(root.draft_brushes_node, Vector3.ZERO)
	_cut(root.draft_brushes_node, Vector3(500, 0, 0))
	assert_eq(_types(val_sys.check_bake_issues(), "overlapping_subtract").size(), 0)


func test_entity_cuts_are_left_out_of_the_overlap_check():
	_cut(root.draft_brushes_node, Vector3.ZERO)
	var entity_cut = _cut(root.draft_brushes_node, Vector3(1, 0, 0))
	entity_cut.set_meta("entity_type", "func_door")
	assert_eq(_types(val_sys.check_bake_issues(), "overlapping_subtract").size(), 0)


# ===========================================================================
# Scale
# ===========================================================================


## A floor plan of paired solids and cuts, well apart from each other.
func _spread_out_level(pairs: int, spacing: float) -> void:
	var per_row := int(ceil(sqrt(float(pairs))))
	for i in range(pairs):
		var origin := Vector3(float(i % per_row) * spacing, 0.0, float(i / per_row) * spacing)
		_make_brush(root.draft_brushes_node, origin, Vector3(8, 8, 8))
		_cut(root.draft_brushes_node, origin + Vector3(1, 1, 1))


func test_a_spread_out_level_reports_nothing_and_stays_under_budget():
	_spread_out_level(500, 100.0)
	var issues = val_sys.check_bake_issues()
	assert_eq(_types(issues, "floating_subtract").size(), 0, "Every cut sits in its own solid")
	assert_eq(_types(issues, "overlapping_subtract").size(), 0, "No two cuts are near each other")
	# 1,000 brushes is 499,500 pairs. The old checks reached an AABB test for
	# roughly 500 x 1,000 of them on the floating pass plus 124,750 on the
	# overlap pass, rebuilding both boxes each time.
	assert_lt(
		val_sys.pair_tests, 50000, "Most of a spread out level should never reach an AABB test"
	)


## Solid and cut pairs strung out along one line, each pair far from the next.
func _strung_out_level(pairs: int, spacing: float) -> void:
	for i in range(pairs):
		var origin := Vector3(float(i) * spacing, 0.0, 0.0)
		_make_brush(root.draft_brushes_node, origin, Vector3(8, 8, 8))
		_cut(root.draft_brushes_node, origin + Vector3(1, 1, 1))


func test_brushes_further_down_the_level_cost_the_ones_at_the_start_nothing():
	# This is the shape of the complaint: adding brushes that cannot affect the
	# answer used to add work anyway.
	_strung_out_level(500, 200.0)
	var issues = val_sys.check_bake_issues()
	assert_eq(_types(issues, "floating_subtract").size(), 0)
	assert_eq(_types(issues, "overlapping_subtract").size(), 0)
	assert_lt(
		val_sys.pair_tests,
		3000,
		"Each pair should only ever meet itself, so the count tracks the pairs"
	)


func test_the_count_tracks_the_brushes_rather_than_their_square():
	_strung_out_level(150, 200.0)
	val_sys.check_bake_issues()
	var small := val_sys.pair_tests
	after_each()
	before_each()
	_strung_out_level(600, 200.0)
	val_sys.check_bake_issues()
	var large := val_sys.pair_tests
	assert_lt(
		float(large) / float(maxi(small, 1)),
		6.0,
		"Four times the brushes, not sixteen times the pairs"
	)


func test_a_dense_pile_still_finds_every_overlap():
	# The broad phase may only skip pairs that cannot touch. Stacked cuts all
	# overlap, so none of them may be skipped.
	for i in range(12):
		_cut(root.draft_brushes_node, Vector3(float(i) * 0.25, 0, 0))
	var overlaps = _types(val_sys.check_bake_issues(), "overlapping_subtract")
	assert_eq(overlaps.size(), 66, "Twelve mutually overlapping cuts make 66 pairs")


func test_a_long_thin_solid_grounds_a_cut_at_its_far_end():
	# A corridor whose origin is nowhere near the cut. Culling on origins alone
	# would call this floating.
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(400, 8, 8))
	_cut(root.draft_brushes_node, Vector3(190, 0, 0))
	assert_eq(
		_types(val_sys.check_bake_issues(), "floating_subtract").size(),
		0,
		"The solid reaches the cut even though its origin does not"
	)


func test_a_solid_that_sorts_after_its_cut_still_grounds_it():
	# The sweep meets brushes in axis order, so the cut is sometimes the one
	# already open when its solid arrives. Both directions have to count.
	_cut(root.draft_brushes_node, Vector3.ZERO)
	_make_brush(root.draft_brushes_node, Vector3(2, 0, 0), Vector3(4, 4, 4))
	assert_eq(
		_types(val_sys.check_bake_issues(), "floating_subtract").size(),
		0,
		"The solid starts further along the axis than the cut does"
	)


func test_a_solid_that_sorts_after_its_cut_grounds_it_on_any_axis():
	# Same again with the level widest on Z, so the sweep picks a different axis.
	_cut(root.draft_brushes_node, Vector3(0, 0, 0))
	_make_brush(root.draft_brushes_node, Vector3(0, 0, 2), Vector3(4, 4, 4))
	_make_brush(root.draft_brushes_node, Vector3(0, 0, 900), Vector3(4, 4, 4))
	assert_eq(_types(val_sys.check_bake_issues(), "floating_subtract").size(), 0)
