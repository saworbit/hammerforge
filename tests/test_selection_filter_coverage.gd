extends GutTest

## #434, #435, #436. The Selection Filters popover is a bulk selection a mapper
## then acts on. What matters is that the three normal buttons between them name
## every face, that a hidden brush is not in the answer, and that a filter with
## nothing to select says so.

const HFSelectionFilter = preload("res://addons/hammerforge/ui/hf_selection_filter.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var root: LevelRoot


class Capture:
	extends RefCounted

	var nodes: Array = []
	var faces: Dictionary = {}
	var emitted := false
	var message := ""

	func take(p_nodes: Array, p_faces: Dictionary) -> void:
		nodes = p_nodes
		faces = p_faces
		emitted = true

	func hear(p_message: String) -> void:
		message = p_message


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _box(size: Vector3, centre: Vector3 = Vector3.ZERO) -> Node:
	return root.create_brush_from_info({"shape": 0, "size": size, "center": centre})


func _run(method: String, selection: Array = []) -> Capture:
	var sf = HFSelectionFilter.new()
	sf._root = root
	sf._hf_selection = selection
	var cap := Capture.new()
	sf.filter_applied.connect(cap.take)
	sf.filter_reported.connect(cap.hear)
	sf.call(method)
	sf.free()
	return cap


func _face_total(cap: Capture) -> int:
	var total := 0
	for key in cap.faces.keys():
		total += (cap.faces[key] as Array).size()
	return total


# ===========================================================================
# The three normal buttons cover the sphere (#434)
# ===========================================================================


func test_no_face_of_a_ramp_is_left_to_no_filter():
	var brush := _box(Vector3(64, 16, 64)) as Node3D
	# 50 degrees off level: steeper than a floor was, shallower than a wall.
	brush.rotation = Vector3(deg_to_rad(50.0), 0.0, 0.0)
	var faces: Array = brush.get_faces()
	var reached := {}
	for method in ["_filter_walls", "_filter_floors", "_filter_ceilings"]:
		var cap := _run(method)
		for key in cap.faces.keys():
			for i in cap.faces[key]:
				reached[int(i)] = true
	assert_eq(reached.size(), faces.size(), "Every face of a ramp belongs to one of the three")


func test_the_three_normal_filters_do_not_overlap():
	var brush := _box(Vector3(64, 16, 64)) as Node3D
	brush.rotation = Vector3(deg_to_rad(50.0), 0.0, 0.0)
	var counted := 0
	var seen := {}
	for method in ["_filter_walls", "_filter_floors", "_filter_ceilings"]:
		var cap := _run(method)
		counted += _face_total(cap)
		for key in cap.faces.keys():
			for i in cap.faces[key]:
				seen[int(i)] = true
	assert_eq(counted, seen.size(), "No face is selected by two of the three")


func test_a_level_face_is_still_a_floor():
	_box(Vector3(64, 16, 64))
	var cap := _run("_filter_floors")
	assert_eq(_face_total(cap), 1, "A flat box has one upward face")


# ===========================================================================
# Hidden brushes are left alone (#435)
# ===========================================================================


func test_a_filter_skips_a_hidden_brush():
	var shown := _box(Vector3(64, 64, 64)) as Node3D
	var hidden := _box(Vector3(64, 64, 64), Vector3(256, 0, 0)) as Node3D
	hidden.visible = false
	var cap := _run("_filter_floors")
	assert_eq(cap.faces.size(), 1, "Only the visible brush contributes faces")
	assert_true(cap.faces.has(HFBrushSystem.face_key(shown)), "And it is the visible one")


func test_a_node_filter_skips_a_hidden_brush():
	_box(Vector3(64, 64, 64))
	var hidden := _box(Vector3(64, 64, 64), Vector3(256, 0, 0)) as Node3D
	hidden.visible = false
	var cap := _run("_filter_structural")
	assert_eq(cap.nodes.size(), 1, "The hidden brush is not picked")
	assert_false(cap.nodes.has(hidden))


# ===========================================================================
# A filter with nothing to select says so (#436)
# ===========================================================================


func test_a_filter_that_matches_nothing_reports_instead_of_emitting():
	_box(Vector3(64, 64, 64))
	var cap := _run("_filter_detail")
	assert_false(cap.emitted, "The previous selection is left alone")
	assert_string_contains(cap.message, "No detail brushes")


func test_a_filter_with_nothing_to_match_against_asks_for_a_selection():
	_box(Vector3(64, 64, 64))
	var cap := _run("_filter_same_material")
	assert_false(cap.emitted)
	assert_string_contains(cap.message, "Select a face first")


func test_similar_brushes_with_no_brush_selected_asks_for_one():
	_box(Vector3(64, 64, 64))
	var cap := _run("_filter_similar_brushes")
	assert_false(cap.emitted)
	assert_string_contains(cap.message, "Select a brush first")


func test_a_filter_that_matches_something_still_emits():
	_box(Vector3(64, 64, 64))
	var cap := _run("_filter_structural")
	assert_true(cap.emitted, "A structural brush is there to select")
	assert_eq(cap.message, "", "And nothing is reported")


func test_a_filter_closes_the_popover_either_way():
	var sf = HFSelectionFilter.new()
	sf._root = root
	_box(Vector3(64, 64, 64))
	sf.visible = true
	sf._filter_same_material()
	assert_false(sf.visible, "The popover closes even when it has nothing to do")
	sf.free()
