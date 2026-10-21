extends GutTest

## Intersect: keep only the volume two or more brushes share, as one brush (#1426).
##
## What is kept is checked against the volume itself rather than against a list of
## corners: every corner of it lies inside every source, and it holds as much as
## the sources share, so it is all of that volume and nothing else. The volume is
## measured off the kept brush's own faces, and what the sources share is worked
## out independently, from the fixture's symmetry.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _brush(
	brush_id: String,
	centre: Vector3,
	size: Vector3,
	shape: int = LevelRoot.BrushShape.BOX,
	turn: Basis = Basis.IDENTITY
) -> DraftBrush:
	var made = (
		root
		. create_brush_from_info(
			{
				"shape": shape,
				"size": size,
				"sides": 16,
				"transform": Transform3D(turn, centre),
				"brush_id": brush_id,
			}
		)
	)
	assert_not_null(made, "the fixture needs brush %s" % brush_id)
	(made as DraftBrush).rebuild_preview()
	return made


func _brushes() -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			out.append(child)
	return out


func _world_corners(brush: DraftBrush, face) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in face.local_verts:
		out.append(brush.global_transform * v)
	return out


## The plane a face lies in, in the level, facing the way its winding says.
func _world_plane(brush: DraftBrush, face) -> Plane:
	var corners := _world_corners(brush, face)
	for i in range(1, corners.size() - 1):
		var normal: Vector3 = (corners[i + 1] - corners[0]).cross(corners[i] - corners[0])
		if normal.length() > 0.000001:
			return Plane(normal.normalized(), corners[0])
	return Plane()


## The brush's own planes in the level, facing out.
func _outward_planes(brush: DraftBrush) -> Array:
	var faces: Array = brush.get_faces()
	var planes: Array = []
	for plane in HFConvexClip.outward_planes(faces, HFConvexClip.interior_point(faces)):
		planes.append(brush.global_transform * plane)
	return planes


## How much a closed brush holds, in the level's units, by the divergence theorem.
func _volume(brush: DraftBrush) -> float:
	var total := 0.0
	for face in brush.get_faces():
		var corners := _world_corners(brush, face)
		for i in range(1, corners.size() - 1):
			total += corners[0].dot(corners[i].cross(corners[i + 1]))
	return absf(total) / 6.0


func _world_bounds(brush: DraftBrush) -> AABB:
	return root.brush_system.world_bounds_of(brush)


## Every corner of `kept` on or behind every plane of every one of `sources`.
func _assert_inside_all(kept: DraftBrush, sources: Array, note: String) -> void:
	var outside := 0
	for planes in sources:
		for face in kept.get_faces():
			for corner in _world_corners(kept, face):
				for plane: Plane in planes:
					if plane.distance_to(corner) > 0.01:
						outside += 1
	assert_eq(outside, 0, "%s: no corner of what is kept lies outside a source" % note)


func _assert_convex(kept: DraftBrush, note: String) -> void:
	var faces: Array = kept.get_faces()
	assert_gte(faces.size(), 4, "%s: a closed solid" % note)
	assert_true(
		HFConvexClip.is_convex_solid(faces, HFConvexClip.interior_point(faces)),
		"%s: one convex brush" % note
	)


## The kept brush, when the intersect left exactly one brush where the sources were.
func _the_one_kept(note: String) -> DraftBrush:
	var left := _brushes()
	assert_eq(left.size(), 1, "%s: one brush is left" % note)
	return left[0] if left.size() == 1 else null


# ===========================================================================
# What is kept
# ===========================================================================


func test_two_boxes_keep_the_box_they_share():
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	_brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	var result: HFOpResult = root.intersect_brushes_by_ids(["a", "b"])
	assert_true(result.ok, result.message)
	var kept := _the_one_kept("two boxes")
	if kept == null:
		return
	assert_null(root.find_brush_by_id("a"), "the first source is replaced")
	assert_null(root.find_brush_by_id("b"), "and so is the second")
	assert_eq(kept.shape, LevelRoot.BrushShape.BOX, "a box is still a box, with its handles")
	var bounds := _world_bounds(kept)
	assert_almost_eq(bounds.position, Vector3.ZERO, Vector3(0.001, 0.001, 0.001))
	assert_almost_eq(bounds.size, Vector3(32, 32, 32), Vector3(0.001, 0.001, 0.001))


## A cylinder stood on the box's corner edge, reaching above the box: a quarter of
## it lies over the box in plan, and half its height inside it. A sixteen-sided
## cylinder turns into itself a quarter turn about its axis, so the two planes of
## the box through that axis cut it into four equal parts whichever way its sides
## face, and what the two share is an eighth of it.
func test_a_box_and_a_cylinder_at_a_corner_keep_exactly_what_they_share():
	for order in [["box", "cylinder"], ["cylinder", "box"]]:
		var box := _brush("box", Vector3.ZERO, Vector3(64, 64, 64))
		var cylinder := _brush(
			"cylinder", Vector3(32, 32, 32), Vector3(32, 64, 32), LevelRoot.BrushShape.CYLINDER
		)
		var shared := _volume(cylinder) / 8.0
		var sources := [_outward_planes(box), _outward_planes(cylinder)]
		var note := "%s first" % order[0]

		var result: HFOpResult = root.intersect_brushes_by_ids(order)

		assert_true(result.ok, "%s: %s" % [note, result.message])
		var kept := _the_one_kept(note)
		if kept == null:
			return
		_assert_convex(kept, note)
		_assert_inside_all(kept, sources, note)
		assert_almost_eq(_volume(kept), shared, shared * 0.001, "%s: all of it" % note)
		var bounds := _world_bounds(kept)
		assert_almost_eq(bounds.end, Vector3(32, 32, 32), Vector3(0.01, 0.01, 0.01), note)
		assert_almost_eq(bounds.position.y, 0.0, 0.01, "%s: from the cylinder's foot" % note)
		root.brush_system.delete_brush(kept)


## Three boxes, each overlapping the others, and one of them small: what is kept
## is the box all three share and not the larger one any two of them do.
func test_three_brushes_keep_the_volume_all_three_share():
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	_brush("b", Vector3(16, 16, 16), Vector3(64, 64, 64))
	_brush("c", Vector3(24, -8, 0), Vector3(32, 32, 32))
	var result: HFOpResult = root.intersect_brushes_by_ids(["a", "b", "c"])
	assert_true(result.ok, result.message)
	var kept := _the_one_kept("three boxes")
	if kept == null:
		return
	for brush_id in ["a", "b", "c"]:
		assert_null(root.find_brush_by_id(brush_id), "%s is replaced" % brush_id)
	var bounds := _world_bounds(kept)
	assert_almost_eq(bounds.position, Vector3(8, -16, -16), Vector3(0.001, 0.001, 0.001))
	assert_almost_eq(bounds.size, Vector3(24, 24, 32), Vector3(0.001, 0.001, 0.001))
	assert_almost_eq(_volume(kept), 24.0 * 24.0 * 32.0, 0.01)


## A turned brush cuts on its real faces, not its unturned box.
func test_a_turned_brush_cuts_on_its_own_planes():
	var box := _brush("box", Vector3.ZERO, Vector3(64, 64, 64))
	var turned := _brush(
		"turned", Vector3(32, 0, 32), Vector3(32, 128, 32), 0, Basis(Vector3.UP, PI / 4.0)
	)
	var sources := [_outward_planes(box), _outward_planes(turned)]
	assert_true(root.intersect_brushes_by_ids(["box", "turned"]).ok)
	var kept := _the_one_kept("a turned brush")
	if kept == null:
		return
	_assert_convex(kept, "a turned brush")
	_assert_inside_all(kept, sources, "a turned brush")
	# The diamond's corner quarter over the box: a right triangle with legs of
	# 16 * sqrt(2), the full height of the box.
	var leg := 16.0 * sqrt(2.0)
	assert_almost_eq(_volume(kept), leg * leg * 0.5 * 64.0, 0.1)


# ===========================================================================
# What it looks like
# ===========================================================================


## Each face of `brush` its own look, numbered from `first`.
func _label_faces(brush: DraftBrush, prefix: String, first: int) -> Array:
	var records: Array = []
	var faces: Array = brush.get_faces()
	for i in faces.size():
		var face = faces[i]
		face.material_idx = first + i
		face.map_texture = "%s_%d" % [prefix, i]
		face.uv_scale = Vector2(1.0 + i, 2.0 + i)
		records.append({"plane": _world_plane(brush, face), "face": face})
	return records


## The record of the first source face lying on `plane` and facing the same way,
## or an empty one.
func _source_on(plane: Plane, records: Array) -> Dictionary:
	for record: Dictionary in records:
		var other: Plane = record["plane"]
		if other.normal.dot(plane.normal) > 0.999 and absf(other.d - plane.d) < 0.01:
			return record
	return {}


## Each face of `kept` has the look of the first source, in `sources` order, with a
## face on its plane. Returns how many faces each source gave, by name.
func _assert_each_face_looks_like_its_source(kept: DraftBrush, sources: Array) -> Dictionary:
	var counted := {}
	for face in kept.get_faces():
		var plane := _world_plane(kept, face)
		var record := {}
		var brush_name := ""
		for source: Array in sources:
			record = _source_on(plane, source[1])
			brush_name = source[0]
			if not record.is_empty():
				break
		assert_false(record.is_empty(), "the face on %s lies on a source's plane" % plane)
		if record.is_empty():
			continue
		counted[brush_name] = int(counted.get(brush_name, 0)) + 1
		var source = record["face"]
		assert_eq(face.material_idx, source.material_idx, "%s: its material slot" % plane)
		assert_eq(face.map_texture, source.map_texture, "%s: its texture name" % plane)
		assert_eq(face.uv_scale, source.uv_scale, "%s: how it is laid on" % plane)
	return counted


func test_every_face_keeps_the_look_of_the_brush_whose_plane_it_lies_on():
	var a := _brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	var b := _brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	var sources := [["A", _label_faces(a, "A", 10)], ["B", _label_faces(b, "B", 20)]]
	assert_true(root.intersect_brushes_by_ids(["a", "b"]).ok)
	var kept := _the_one_kept("faces")
	if kept == null:
		return
	var counted := _assert_each_face_looks_like_its_source(kept, sources)
	assert_eq(counted, {"A": 3, "B": 3}, "three faces of each box")


## Three brushes: each face is the first brush's with a face on its plane, in the
## order they were named, and the target's sculpt still lies on the piece of its
## face that is kept, however many brushes cut it.
func test_with_three_brushes_each_face_is_the_first_on_its_plane_and_keeps_its_sculpt():
	var a := _brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	var b := _brush("b", Vector3(16, 16, 16), Vector3(64, 64, 64))
	var c := _brush("c", Vector3(24, -8, 0), Vector3(32, 32, 32))
	var sources := [
		["A", _label_faces(a, "A", 10)],
		["B", _label_faces(b, "B", 20)],
		["C", _label_faces(c, "C", 30)],
	]
	var sculpt := HFDisplacementData.new()
	sculpt.init_flat(2)
	sculpt.set_distance(1, 1, 3.0)
	for face in a.get_faces():
		if face.normal.x > 0.9:
			face.displacement = sculpt
	assert_true(root.intersect_brushes_by_ids(["a", "b", "c"]).ok)
	var kept := _the_one_kept("three brushes")
	if kept == null:
		return
	var counted := _assert_each_face_looks_like_its_source(kept, sources)
	# +X is a's. -Y is b's, and so is -Z, where c has a face too: b was named
	# first. c has the other three.
	assert_eq(counted, {"A": 1, "B": 2, "C": 3}, "each from the first on its plane")
	var carried := false
	for face in kept.get_faces():
		if _world_plane(kept, face).normal.x > 0.9:
			carried = face.displacement != null
	assert_true(carried, "the sculpt on a's +X face is on the piece of it that is kept")


func test_a_cylinder_face_takes_the_cylinder_look():
	var box := _brush("box", Vector3.ZERO, Vector3(64, 64, 64))
	var cylinder := _brush(
		"cylinder", Vector3(32, 32, 32), Vector3(32, 64, 32), LevelRoot.BrushShape.CYLINDER
	)
	var from_box := _label_faces(box, "BOX", 1)
	for face in cylinder.get_faces():
		face.material_idx = 7
		face.map_texture = "ROUND"
	assert_true(root.intersect_brushes_by_ids(["box", "cylinder"]).ok)
	var kept := _the_one_kept("cylinder look")
	if kept == null:
		return
	var round_faces := 0
	for face in kept.get_faces():
		if not _source_on(_world_plane(kept, face), from_box).is_empty():
			assert_ne(face.map_texture, "ROUND", "a face on the box's plane is the box's")
			continue
		round_faces += 1
		assert_eq(
			[face.material_idx, face.map_texture], [7, "ROUND"], "the curve is the cylinder's"
		)
	assert_gt(round_faces, 0, "part of the curve is kept")


## A face's material is its palette slot, or its brush's override. The kept brush
## has one override at most, so a face from a brush with another one keeps it as a
## slot, and a face from a brush with none stays with none.
func test_each_face_keeps_the_material_it_showed():
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	for pair in [[red, blue], [red, null], [null, blue], [red, red]]:
		var a := _brush("a", Vector3.ZERO, Vector3(64, 64, 64))
		var b := _brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
		a.material_override = pair[0]
		b.material_override = pair[1]
		var records: Array = _label_faces(a, "A", 0) + _label_faces(b, "B", 0)
		# No palette slot anywhere: every face shows its brush's override.
		var showed := {}
		for record in records:
			record["face"].material_idx = -1
		for face in a.get_faces():
			showed[face] = pair[0]
		for face in b.get_faces():
			showed[face] = pair[1]
		var note := "%s over %s" % [pair[0] != null, pair[1] != null]
		assert_true(root.intersect_brushes_by_ids(["a", "b"]).ok, note)
		var kept := _the_one_kept(note)
		if kept == null:
			return
		for face in kept.get_faces():
			var record := _source_on(_world_plane(kept, face), records)
			if record.is_empty():
				continue
			var shows: Material = face.resolved_material(
				root.material_manager, kept.material_override, null, false
			)
			assert_eq(shows, showed[record["face"]], "%s: the face shows what it showed" % note)
		root.brush_system.delete_brush(kept)


## A face whose texture was laid on by hand keeps it where it was, across the
## corners the cut gave it.
func test_custom_uvs_on_another_brush_face_carry_across_its_new_corners():
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	var b := _brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	var low_x = null
	for face in b.get_faces():
		if face.normal.x < -0.9:
			low_x = face
	assert_not_null(low_x, "the fixture has a -X face")
	var uvs := PackedVector2Array()
	for v in low_x.local_verts:
		uvs.append(Vector2(v.z * 0.25 + 3.0, v.y * 0.5 - 1.0))
	low_x.custom_uvs = uvs
	assert_true(root.intersect_brushes_by_ids(["a", "b"]).ok)
	var kept := _the_one_kept("custom uvs")
	if kept == null:
		return
	var checked := false
	for face in kept.get_faces():
		var plane := _world_plane(kept, face)
		if plane.normal.x > -0.9:
			continue
		checked = true
		assert_eq(face.custom_uvs.size(), face.local_verts.size(), "one UV for each corner")
		var corners := _world_corners(kept, face)
		for i in mini(corners.size(), face.custom_uvs.size()):
			# Where the corner was on b, which stood at (32, 32, 32).
			var on_b: Vector3 = corners[i] - Vector3(32, 32, 32)
			assert_almost_eq(
				face.custom_uvs[i],
				Vector2(on_b.z * 0.25 + 3.0, on_b.y * 0.5 - 1.0),
				Vector2(0.001, 0.001),
				"corner %d" % i
			)
	assert_true(checked, "the kept brush has a face on b's -X plane")


# ===========================================================================
# What it carries
# ===========================================================================


func test_the_kept_brush_is_the_first_brush_group_visgroups_and_entity():
	var a := _brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	var b := _brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	root.tie_brushes_to_entity(["a", "b"], "func_detail")
	a.set_meta("visgroups", PackedStringArray(["walls"]))
	a.set_meta("group_id", "group_7")
	b.set_meta("visgroups", PackedStringArray(["props"]))
	b.set_meta("group_id", "group_9")
	var tie := str(a.get_meta("brush_entity_group", ""))
	assert_ne(tie, "", "the fixture tied the two")
	assert_true(root.intersect_brushes_by_ids(["a", "b"]).ok)
	var kept := _the_one_kept("carried")
	if kept == null:
		return
	assert_eq(Array(kept.get_meta("visgroups", PackedStringArray())), ["walls"])
	assert_eq(str(kept.get_meta("group_id", "")), "group_7")
	assert_eq(str(kept.get_meta("brush_entity_class", "")), "func_detail")
	assert_eq(str(kept.get_meta("brush_entity_group", "")), tie, "still the one entity")


func test_two_cuts_keep_the_cut_they_share():
	var cut := CSGShape3D.OPERATION_SUBTRACTION
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64)).operation = cut
	_brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64)).operation = cut
	assert_true(root.intersect_brushes_by_ids(["a", "b"]).ok)
	var kept := _the_one_kept("two cuts")
	if kept:
		assert_eq(kept.operation, cut, "what two cuts share is a cut")


# ===========================================================================
# Refusals, and the check the confirmation asks first
# ===========================================================================


## Each refusal the intersect makes, from the check, in the intersect's words, and
## nothing in the level changed by asking or by the refused intersect.
func test_each_refusal_leaves_the_level_as_it_was():
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	_brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	_brush("far", Vector3(500, 0, 0), Vector3(32, 32, 32))
	# Against a's +X face: contact, not a volume.
	_brush("touching", Vector3(64, 0, 0), Vector3(64, 64, 64))
	# Each overlaps the next, and the first and the last share nothing.
	_brush("p", Vector3(1000, 0, 0), Vector3(10, 10, 10))
	_brush("q", Vector3(1008, 0, 0), Vector3(10, 10, 10))
	_brush("r", Vector3(1016, 0, 0), Vector3(10, 10, 10))
	var cut := _brush("cut", Vector3(16, 16, 16), Vector3(16, 16, 16))
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	var door := _brush("door", Vector3(-16, 0, 0), Vector3(32, 32, 32))
	root.tie_brushes_to_entity(["door"], "func_door", "door_1")
	_brush("ring", Vector3(0, 0, 0), Vector3(48, 16, 48), LevelRoot.BrushShape.TORUS)
	# Turned clear of a's corner: the two boxes round them overlap, the brushes do not.
	_brush("diamond", Vector3(50, 0, 50), Vector3(32, 32, 32), 0, Basis(Vector3.UP, PI / 4.0))
	var cases := {
		"nothing named": [[], "select at least 2"],
		"one brush": [["a"], "select at least 2"],
		"one brush named twice": [["a", "a"], "select at least 2"],
		"a brush not there": [["a", "nope"], "not found"],
		"far apart": [["a", "far"], "share no volume"],
		"touching": [["a", "touching"], "share no volume"],
		"bounds that overlap": [["a", "diamond"], "share no volume"],
		"a chain": [["p", "q", "r"], "share no volume"],
		"a solid and a cut": [["a", "cut"], "operation"],
		"a door and a wall": [["a", "door"], "not all one entity"],
		"a torus": [["ring", "a"], "not convex"],
	}
	var before := var_to_str(root.capture_state())
	for note in cases:
		var ids: Array = cases[note][0]
		var check: HFOpResult = root.can_intersect_brushes(ids)
		var result: HFOpResult = root.intersect_brushes_by_ids(ids)
		assert_false(check.ok, "%s: the check refuses" % note)
		assert_false(result.ok, "%s: as the intersect does" % note)
		assert_string_contains(result.message, cases[note][1], note)
		assert_eq(check.message, result.message, "%s: for the same reason" % note)
		assert_eq(check.fix_hint, result.fix_hint, "%s: with the same advice" % note)
		assert_eq(var_to_str(root.capture_state()), before, "%s: the level is unchanged" % note)


func test_the_check_passes_an_intersect_and_changes_nothing_itself():
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	_brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	var before := var_to_str(root.capture_state())
	assert_true(root.can_intersect_brushes(["a", "b"]).ok)
	assert_eq(var_to_str(root.capture_state()), before, "asking changed nothing")
	assert_true(root.intersect_brushes_by_ids(["a", "b"]).ok, "and the intersect it passed goes")


# ===========================================================================
# Undo
# ===========================================================================


func test_restoring_the_state_before_puts_every_source_back_with_its_id():
	_brush("a", Vector3.ZERO, Vector3(64, 64, 64))
	_brush("b", Vector3(32, 32, 32), Vector3(64, 64, 64))
	_brush("c", Vector3(24, -8, 0), Vector3(32, 32, 32))
	var before: Dictionary = root.state_system.capture_state()
	assert_true(root.intersect_brushes_by_ids(["a", "b", "c"]).ok)
	root.state_system.restore_state(before)
	assert_eq(_brushes().size(), 3, "three brushes again")
	for pair in [
		["a", Vector3.ZERO, Vector3(64, 64, 64)],
		["b", Vector3(32, 32, 32), Vector3(64, 64, 64)],
		["c", Vector3(24, -8, 0), Vector3(32, 32, 32)],
	]:
		var brush = root.find_brush_by_id(pair[0])
		assert_not_null(brush, "%s is back under its id" % pair[0])
		if brush:
			assert_almost_eq(brush.global_position, pair[1], Vector3(0.001, 0.001, 0.001))
			assert_almost_eq(brush.size, pair[2], Vector3(0.001, 0.001, 0.001))
