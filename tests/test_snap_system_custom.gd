extends GutTest

const HFSnapSystemScript = preload("res://addons/hammerforge/hf_snap_system.gd")

var snap: HFSnapSystem
var root: Node3D


func before_each():
	root = Node3D.new()
	add_child(root)
	snap = HFSnapSystemScript.new(root)


func after_each():
	root.free()
	root = null
	snap = null


func test_initial_no_custom_snap():
	assert_false(snap._has_custom_snap)


func test_set_custom_snap_line():
	snap.set_custom_snap_line(Vector3(0, 0, 0), Vector3(1, 0, 0))
	assert_true(snap._has_custom_snap)
	assert_eq(snap._custom_snap_origin, Vector3(0, 0, 0))
	assert_eq(snap._custom_snap_dir, Vector3(1, 0, 0))


func test_clear_custom_snap_line():
	snap.set_custom_snap_line(Vector3(0, 0, 0), Vector3(1, 0, 0))
	snap.clear_custom_snap_line()
	assert_false(snap._has_custom_snap)


func test_project_onto_line_on_x_axis():
	var result: Vector3 = snap._project_onto_line(
		Vector3(5, 3, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)
	)
	assert_almost_eq(result.x, 5.0, 0.001)
	assert_almost_eq(result.y, 0.0, 0.001)
	assert_almost_eq(result.z, 0.0, 0.001)


func test_project_onto_line_diagonal():
	var dir := Vector3(1, 1, 0).normalized()
	var result: Vector3 = snap._project_onto_line(
		Vector3(2, 0, 0), Vector3(0, 0, 0), dir
	)
	# Projection of (2,0,0) onto (1,1,0) normalized
	assert_almost_eq(result.x, 1.0, 0.01)
	assert_almost_eq(result.y, 1.0, 0.01)


func test_snap_point_uses_custom_line():
	snap.set_custom_snap_line(Vector3(0, 0, 0), Vector3(1, 0, 0))
	snap.snap_threshold = 5.0
	# Point near the X axis should snap onto it
	var result: Vector3 = snap.snap_point(Vector3(3, 0.5, 0), 0.0, [])
	# Custom line projects to (3, 0, 0)
	assert_almost_eq(result.y, 0.0, 0.01, "Should snap Y to the line")
	assert_almost_eq(result.x, 3.0, 0.01, "X should stay projected")
