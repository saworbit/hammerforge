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


# ===========================================================================
# A stretched brush is sorted by the way its faces really face (#884)
# ===========================================================================


func _wedge(size: Vector3, centre: Vector3, stretch: Vector3 = Vector3.ONE) -> Node3D:
	var brush := (
		root.create_brush_from_info(
			{"shape": LevelRootType.BrushShape.WEDGE, "size": size, "center": centre}
		)
		as Node3D
	)
	brush.scale = stretch
	return brush


## The way a face faces in the world, square to its own corners there.
func _true_normal(brush: Node3D, face) -> Vector3:
	var xform: Transform3D = brush.global_transform
	var corners: PackedVector3Array = face.local_verts
	var n := Vector3.ZERO
	for i in corners.size():
		var a: Vector3 = xform * corners[i]
		var b: Vector3 = xform * corners[(i + 1) % corners.size()]
		n += Vector3(
			(a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)
		)
	n = n.normalized()
	# Newell's sum follows the winding; the basis keeps the outward side.
	return n if n.dot(xform.basis * face.normal) > 0.0 else -n


## A face that faces along no axis: the wedge's slope.
func _slope_index(brush: Node3D) -> int:
	var faces: Array = brush.get_faces()
	for i in faces.size():
		var n: Vector3 = faces[i].normal
		if absf(n.x) < 0.99 and absf(n.y) < 0.99 and absf(n.z) < 0.99:
			return i
	return -1


func test_a_stretched_ramp_is_sorted_by_the_way_its_slope_really_faces():
	# A 45 degree ramp four times as tall is steeper than the wall limit, and
	# four times as long or wide is shallower than it. Carried by the basis, the
	# slope's normal leans the other way each time.
	var brushes: Array = [
		_wedge(Vector3(32, 32, 32), Vector3.ZERO, Vector3(1, 4, 1)),
		_wedge(Vector3(32, 32, 32), Vector3(200, 0, 0), Vector3(4, 1, 1)),
		_wedge(Vector3(32, 32, 32), Vector3(400, 0, 0), Vector3(1, 1, 4)),
	]
	var limit: float = HFSelectionFilter.WALL_NORMAL_Y
	var predicates := {
		"_filter_walls": func(n: Vector3) -> bool: return absf(n.y) <= limit,
		"_filter_floors": func(n: Vector3) -> bool: return n.y > limit,
		"_filter_ceilings": func(n: Vector3) -> bool: return n.y < -limit,
	}
	for method in predicates:
		var cap := _run(method)
		for brush in brushes:
			var key := HFBrushSystem.face_key(brush)
			var taken: Array = cap.faces.get(key, [])
			var faces: Array = brush.get_faces()
			for i in faces.size():
				var n := _true_normal(brush, faces[i])
				assert_eq(
					taken.has(i),
					bool(predicates[method].call(n)),
					"%s, face %d of the brush at %s facing %s" % [method, i, brush.scale, n]
				)


func test_similar_faces_matches_a_stretched_slope_to_one_built_that_steep():
	# A 32 unit wedge stretched three times as tall is the same solid as a wedge
	# built 96 units tall, so their slopes face the same way.
	var stretched := _wedge(Vector3(32, 32, 32), Vector3.ZERO, Vector3(1, 3, 1))
	var built := _wedge(Vector3(32, 96, 32), Vector3(200, 0, 0))
	var slope := _slope_index(stretched)
	assert_gte(slope, 0, "the wedge has a slope")
	assert_almost_eq(
		_true_normal(stretched, stretched.get_faces()[slope]),
		_true_normal(built, built.get_faces()[_slope_index(built)]),
		Vector3.ONE * 1e-4,
		"the two slopes are the same plane"
	)
	root.face_selection = {HFBrushSystem.face_key(stretched): [slope]}
	var cap := _run("_filter_similar_faces")
	assert_eq(
		cap.faces.get(HFBrushSystem.face_key(built), []),
		[_slope_index(built)],
		"the built slope faces the way the stretched one does"
	)
