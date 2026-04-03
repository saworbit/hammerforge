extends GutTest

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


# ===========================================================================
# check_bake_issues: degenerate brushes
# ===========================================================================


func test_degenerate_brush_near_zero_thickness():
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(10, 0.001, 10))
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "degenerate":
			found = true
			break
	assert_true(found, "Should detect near-zero thickness brush")


func test_normal_brush_no_degenerate_issue():
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(4, 4, 4))
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "degenerate":
			found = true
			break
	assert_false(found, "Normal brush should not be flagged degenerate")


func test_oversized_brush():
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(3000, 10, 10))
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "oversized":
			found = true
			break
	assert_true(found, "Should detect oversized brush")


# ===========================================================================
# check_bake_issues: floating subtracts
# ===========================================================================


func test_floating_subtract_detected():
	# Subtraction brush with no additive brush nearby
	_make_brush(
		root.draft_brushes_node,
		Vector3(1000, 0, 0),
		Vector3(4, 4, 4),
		CSGShape3D.OPERATION_SUBTRACTION
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "floating_subtract":
			found = true
			break
	assert_true(found, "Should detect subtraction not intersecting any additive")


func test_subtract_intersecting_additive_ok():
	# Additive brush at origin
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(10, 10, 10))
	# Subtraction overlapping the additive
	_make_brush(
		root.draft_brushes_node,
		Vector3(2, 2, 2),
		Vector3(4, 4, 4),
		CSGShape3D.OPERATION_SUBTRACTION
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "floating_subtract":
			found = true
			break
	assert_false(found, "Subtraction intersecting additive should not be flagged")


# ===========================================================================
# check_bake_issues: overlapping subtracts
# ===========================================================================


func test_overlapping_subtracts_detected():
	_make_brush(
		root.draft_brushes_node, Vector3.ZERO, Vector3(4, 4, 4), CSGShape3D.OPERATION_SUBTRACTION
	)
	_make_brush(
		root.draft_brushes_node,
		Vector3(1, 0, 0),
		Vector3(4, 4, 4),
		CSGShape3D.OPERATION_SUBTRACTION
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "overlapping_subtract":
			found = true
			break
	assert_true(found, "Should detect overlapping subtractions")


func test_non_overlapping_subtracts_ok():
	_make_brush(
		root.draft_brushes_node, Vector3.ZERO, Vector3(4, 4, 4), CSGShape3D.OPERATION_SUBTRACTION
	)
	_make_brush(
		root.draft_brushes_node,
		Vector3(100, 0, 0),
		Vector3(4, 4, 4),
		CSGShape3D.OPERATION_SUBTRACTION
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "overlapping_subtract":
			found = true
			break
	assert_false(found, "Non-overlapping subtractions should not be flagged")


# ===========================================================================
# check_bake_issues: clean level
# ===========================================================================


func test_clean_level_no_issues():
	_make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(10, 10, 10))
	_make_brush(
		root.draft_brushes_node,
		Vector3(2, 2, 2),
		Vector3(4, 4, 4),
		CSGShape3D.OPERATION_SUBTRACTION
	)
	var issues = val_sys.check_bake_issues()
	assert_eq(issues.size(), 0, "Well-formed level should have no bake issues")


func test_empty_level_no_issues():
	var issues = val_sys.check_bake_issues()
	assert_eq(issues.size(), 0, "Empty level should have no bake issues")


func test_entity_brushes_skipped():
	var b = _make_brush(root.draft_brushes_node, Vector3.ZERO, Vector3(10, 0.001, 10))
	b.set_meta("entity_type", "point")
	var issues = val_sys.check_bake_issues()
	assert_eq(issues.size(), 0, "Entity brushes should be skipped")
