extends GutTest

## Merge keeps the relief of the displaced faces it joins into one (#1906). It
## used to drop both sculpts with a warning in the Output panel, since a sculpt is
## laid on its face's four corners and the merged face has four new ones. Now the
## merged face takes one sculpt over all of them, at the coarsest power whose grid
## has every point of theirs as a point of its own. A merge that would still lose
## a sculpt, on a face that grows into one with more than four corners, is
## refused, and so is one that would move a sculpt's points, on faces no grid of
## up to 16 cells a side holds (#1972).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _box(brush_id: String, center: Vector3) -> DraftBrush:
	return root.create_brush_from_info(
		{"size": Vector3(4, 1, 4), "center": center, "brush_id": brush_id}
	)


## The top of `brush` displaced at power 2, raised at each `[row, col, height]`.
func _displace_top(brush: DraftBrush, heights: Array) -> int:
	for index in brush.faces.size():
		if brush.faces[index].normal.y < 0.9:
			continue
		root.create_displacement(str(brush.brush_id), index, 2)
		for height in heights:
			brush.faces[index].displacement.set_distance(
				int(height[0]), int(height[1]), float(height[2])
			)
		root.set_displacement_sew_group(str(brush.brush_id), index, 1)
		return index
	return -1


## The corners of the triangles `brush`'s top draws, in the level.
func _top_points(brush: DraftBrush) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in brush.faces:
		if face.normal.y < 0.9:
			continue
		for vertex in face.triangulate().get("verts", PackedVector3Array()):
			out.append(brush.global_transform * vertex)
	return out


func _has_point(points: PackedVector3Array, wanted: Vector3) -> bool:
	for point in points:
		if point.distance_to(wanted) < 0.0001:
			return true
	return false


func test_merging_two_displaced_boxes_keeps_both_reliefs():
	var left := _box("left", Vector3(0, 0.5, 0))
	var right := _box("right", Vector3(4, 0.5, 0))
	_displace_top(left, [[2, 2, 0.5], [1, 3, 0.25], [3, 1, -0.2]])
	_displace_top(right, [[2, 2, -0.3], [2, 0, 0.4]])
	root.sew_all_displacements()
	var before := _top_points(left)
	before.append_array(_top_points(right))
	var warnings_before := get_errors().size()
	var result: HFOpResult = root.merge_brushes_by_ids(["left", "right"])
	assert_true(result.ok, "merged: %s" % result.message)
	assert_eq(get_errors().size(), warnings_before, "with nothing said about a lost sculpt")
	var merged: DraftBrush = null
	for brush in root._iter_managed_brush_nodes():
		merged = brush
	var top: FaceData = null
	for face in merged.faces:
		if face.normal.y > 0.9:
			top = face
	assert_not_null(top.displacement, "the merged top is sculpted")
	assert_eq(top.displacement.power, 3, "a power finer than the two it joins")
	var after := _top_points(merged)
	var missing := 0
	for point in before:
		if not _has_point(after, point):
			missing += 1
	assert_eq(missing, 0, "every point of both old surfaces is a point of the new one")


func test_a_merge_with_one_sculpted_top_keeps_it_and_leaves_the_other_half_flat():
	var left := _box("left", Vector3(0, 0.5, 0))
	_box("right", Vector3(4, 0.5, 0))
	_displace_top(left, [[2, 2, 0.5]])
	var before := _top_points(left)
	var result: HFOpResult = root.merge_brushes_by_ids(["left", "right"])
	assert_true(result.ok, "merged: %s" % result.message)
	var merged: DraftBrush = root._iter_managed_brush_nodes()[0]
	var after := _top_points(merged)
	for point in before:
		assert_true(_has_point(after, point), "%s kept" % point)
	assert_true(_has_point(after, Vector3(4, 1, 0)), "and the other half is flat at its middle")


func test_merged_onto_reads_each_point_off_the_part_it_lies_in():
	var a := HFDisplacementDataScript.new()
	a.init_flat(2)
	a.set_distance(2, 2, 1.0)
	var b := HFDisplacementDataScript.new()
	b.init_flat(2)
	b.elevation = 2.0
	b.set_distance(2, 2, 1.0)
	var quad_a := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	var quad_b := PackedVector3Array(
		[Vector3(4, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 4), Vector3(4, 0, 4)]
	)
	var whole := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 4), Vector3(0, 0, 4)]
	)
	var merged := HFDisplacementDataScript.merged_onto([[a, quad_a], [b, quad_b]], whole, 3)
	assert_not_null(merged)
	assert_eq(merged.get_dim(), 9)
	# Columns step by 1 and rows by 0.5, so a's middle (2, 2) is row 4, col 2, and
	# b's is row 4, col 6.
	assert_almost_eq(merged.get_distance(4, 2) * merged.elevation, 1.0, 0.0001, "a's bump")
	assert_almost_eq(
		merged.get_distance(4, 6) * merged.elevation, 2.0, 0.0001, "b's, at its elevation"
	)
	assert_almost_eq(merged.get_distance(0, 0), 0.0, 0.0001, "flat where both were")
	assert_null(
		HFDisplacementDataScript.merged_onto([[null, quad_a], [null, quad_b]], whole, 3),
		"nothing to lay when no part is sculpted"
	)


func test_a_union_face_with_more_than_four_corners_counts_its_sculpts_as_lost():
	var source := FaceDataScript.new()
	source.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	source.displacement = HFDisplacementDataScript.new()
	source.displacement.init_flat(2)
	var grown := FaceDataScript.new()
	grown.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(6, 0, 2), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	var origins := {grown: source}
	var parts := {grown: [source]}
	assert_eq(HFConvexClipScript.sculpts_a_union_would_drop([grown], origins, parts), 1)
	assert_eq(HFConvexClipScript.carry_onto_union([grown], origins, parts), 1, "and drops it")
	assert_null(grown.displacement)
	var square := FaceDataScript.new()
	square.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 4), Vector3(0, 0, 4)]
	)
	assert_eq(
		HFConvexClipScript.sculpts_a_union_would_drop(
			[square], {square: source}, {square: [source]}
		),
		0,
		"a four-cornered face holds it"
	)


## A box 1 tall and 4 deep, `width` wide, its left side at `left`, with its top
## sculpted at `power` in a pattern between 0 and 0.5 and put in sew group 1.
func _sculpted(brush_id: String, left: float, width: float, power: int) -> DraftBrush:
	var brush: DraftBrush = (
		root
		. create_brush_from_info(
			{
				"size": Vector3(width, 1, 4),
				"center": Vector3(left + width * 0.5, 0.5, 0),
				"brush_id": brush_id,
			}
		)
	)
	for index in brush.faces.size():
		if brush.faces[index].normal.y < 0.9:
			continue
		root.create_displacement(brush_id, index, power)
		var sculpt: HFDisplacementData = brush.faces[index].displacement
		for row in sculpt.get_dim():
			for col in sculpt.get_dim():
				sculpt.set_distance(row, col, 0.05 * float((row * 7 + col * 3) % 11))
		root.set_displacement_sew_group(brush_id, index, 1)
	return brush


func _top_of(brush: DraftBrush) -> FaceData:
	for face in brush.faces:
		if face.normal.y > 0.9:
			return face
	return null


## Merge laid one sculpt a power finer than the finest it joined. That grid has
## every point of two equal halves, and of no other split, so the relief moved
## and Merge said only how many brushes it merged (#1972). The power now comes
## from the faces' widths: the coarsest grid with every point of theirs.
func test_the_merged_power_is_the_coarsest_grid_with_every_point():
	var whole := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 4), Vector3(0, 0, 4)]
	)
	var at := func(left: float, right: float) -> PackedVector3Array:
		return PackedVector3Array(
			[Vector3(left, 0, 0), Vector3(right, 0, 0), Vector3(right, 0, 4), Vector3(left, 0, 4)]
		)
	var sculpt := func(power: int) -> HFDisplacementData:
		var made := HFDisplacementDataScript.new()
		made.init_flat(power)
		return made
	var holding := func(widths: Array, powers: Array) -> int:
		var parts: Array = []
		var left := 0.0
		for i in widths.size():
			var power: int = powers[i]
			parts.append(
				[sculpt.call(power) if power > 0 else null, at.call(left, left + widths[i])]
			)
			left += float(widths[i])
		return HFDisplacementDataScript.power_holding(parts, whole, 2)
	assert_eq(holding.call([4.0, 4.0], [2, 2]), 3, "two halves at power 2: a power finer")
	assert_eq(holding.call([4.0, 4.0], [2, 3]), 4, "halves at 2 and 3: one finer than 3")
	assert_eq(holding.call([4.0, 4.0], [2, 0]), 3, "a flat half asks nothing")
	assert_eq(holding.call([2.0, 6.0], [2, 2]), 4, "a 2 and a 6 at power 2: two finer")
	assert_eq(holding.call([4.0, 4.0], [4, 4]), -1, "halves at power 4: no finer grid")
	assert_eq(holding.call([6.0, 2.0], [3, 3]), -1, "a 6 at power 3 has points 0.75 apart")
	var thirds := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(12, 0, 0), Vector3(12, 0, 4), Vector3(0, 0, 4)]
	)
	var three: Array = []
	for left in [0.0, 4.0, 8.0]:
		three.append([sculpt.call(2), at.call(left, left + 4.0)])
	assert_eq(
		HFDisplacementDataScript.power_holding(three, thirds, 2),
		-1,
		"three in a row: a grid's cells come in twos, so none has points 1 apart over 12"
	)


func test_a_2_and_a_6_merge_at_the_power_that_keeps_every_point():
	var narrow := _sculpted("narrow", 0.0, 2.0, 2)
	var wide := _sculpted("wide", 2.0, 6.0, 2)
	root.sew_all_displacements()
	var before := _top_points(narrow)
	before.append_array(_top_points(wide))
	assert_true(root.merge_brushes_by_ids(["narrow", "wide"]).ok, "merged")
	var merged: DraftBrush = root._iter_managed_brush_nodes()[0]
	assert_eq(_top_of(merged).displacement.power, 4, "a grid with every point of both")
	var after := _top_points(merged)
	var missing := 0
	for point in before:
		if not _has_point(after, point):
			missing += 1
	assert_eq(missing, 0, "every point of both old surfaces is a point of the new one")


func test_three_sculpted_tops_in_a_row_are_refused_with_the_reason():
	var ids := ["one", "two", "three"]
	for i in ids.size():
		_sculpted(ids[i], 4.0 * i, 4.0, 2)
	root.sew_all_displacements()
	var check: HFOpResult = root.can_merge_brushes(ids)
	assert_false(check.ok, "refused")
	assert_eq(check.message, "Merge: 3 sculpts would move")
	assert_string_contains(check.fix_hint, "4, 8 or 16 cells a side")
	var done: HFOpResult = root.merge_brushes_by_ids(ids)
	assert_false(done.ok, "and refused on a redo as well")
	assert_eq(root._iter_managed_brush_nodes().size(), 3, "nothing was merged")
	for brush in root._iter_managed_brush_nodes():
		assert_eq(_top_of(brush).displacement.power, 2, "each top keeps its own sculpt")


func test_two_halves_at_the_finest_power_are_refused():
	_sculpted("left", 0.0, 4.0, 4)
	_sculpted("right", 4.0, 4.0, 4)
	root.sew_all_displacements()
	var check: HFOpResult = root.can_merge_brushes(["left", "right"])
	assert_false(check.ok, "no grid finer than 16 cells a side")
	assert_eq(check.message, "Merge: 2 sculpts would move")
