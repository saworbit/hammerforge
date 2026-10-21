extends GutTest

## A Trim Run: a skirting or a cornice run along a room's walls (#1414).
##
## The claims are measured on the pieces, in world space: the faces' edges chain
## into one closed run round a room, every corner is cut on the plane that bisects
## its two walls, inside and outside, a Cutout brush through a wall leaves a gap
## exactly its own width, Edge Top hangs the profile flush from the walls' tops,
## a sloped face is refused by name, and the run is kept on the record, so an
## Update and a level saved and reopened lay new trim along the same run.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFTrimRunBuilderScript = preload("res://addons/hammerforge/hf_trim_run_builder.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")
const TrimProfile = preload("res://addons/hammerforge/hf_trim_profile.gd")

const TYPE := "trim_run"
const LEVEL_PATH := "user://test_trim_run_builder.hflevel"
const EPS := 0.001

## The room a 10 m box hollowed with 1 m walls leaves: a floor at 1, a ceiling at
## 9, and walls on the inside at x and z of 4 either way.
const FLOOR := 1.0
const CEILING := 9.0
const INSIDE := 4.0


func after_each():
	if FileAccess.file_exists(LEVEL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL_PATH))


# ===========================================================================
# Fixtures
# ===========================================================================


func _root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _box(
	root: LevelRoot,
	at: Vector3,
	size: Vector3,
	operation := CSGShape3D.OPERATION_UNION,
	basis := Basis.IDENTITY
) -> DraftBrush:
	var info := {
		"shape": root.BrushShape.BOX,
		"size": size,
		"transform": Transform3D(basis, at),
		"operation": operation,
	}
	return root.create_brush_from_info(info) as DraftBrush


## A 10 m box hollowed into a room, as Hollow makes one: two walls run the box's
## whole length and depth, past the room's corners and down past its floor.
func _hollow_room(root: LevelRoot) -> void:
	var solid := _box(root, Vector3(0, 5, 0), Vector3(10, 10, 10))
	assert_true(root.hollow_brush_by_id(solid.brush_id, 1.0).ok, "the box hollows")


func _world_ring(brush: DraftBrush, index: int) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for corner in brush.get_faces()[index].local_verts:
		ring.append(brush.global_transform * corner)
	return ring


func _ring_middle(ring: PackedVector3Array) -> Vector3:
	var total := Vector3.ZERO
	for corner in ring:
		total += corner
	return total / float(ring.size())


func _world_normal(brush: DraftBrush, index: int) -> Vector3:
	return brush.get_faces()[index].normal_through(brush.global_transform.basis)


## The faces facing into the room round `centre`, upright, within `reach` of it
## in X and Z, as Face Select keeps them: `{brush key: [face index]}`.
func _faces_facing(root: LevelRoot, centre: Vector3, reach: float) -> Dictionary:
	var picked := {}
	for brush in root.draft_brushes_node.get_children():
		if not (brush is DraftBrush) or brush.operation != CSGShape3D.OPERATION_UNION:
			continue
		if brush.has_meta(HFGeneratorSystemScript.GENERATOR_META):
			continue
		for i in brush.get_faces().size():
			var middle := _ring_middle(_world_ring(brush, i))
			var normal := _world_normal(brush, i)
			var toward := Vector3(centre.x - middle.x, 0.0, centre.z - middle.z)
			if absf(normal.y) > 0.01 or normal.dot(toward) <= 0.0:
				continue
			if absf(middle.x - centre.x) > reach + EPS or absf(middle.z - centre.z) > reach + EPS:
				continue
			var key := HFBrushSystem.face_key(brush)
			var indices: Array = picked.get(key, [])
			indices.append(i)
			picked[key] = indices
	return picked


func _inner_walls(root: LevelRoot) -> Dictionary:
	return _faces_facing(root, Vector3.ZERO, INSIDE)


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFTrimRunBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


## Read the run along the picked faces and build a Trim Run along it.
func _create(root: LevelRoot, picked: Dictionary, settings: Dictionary) -> String:
	var read: Dictionary = root.trim_run_from_faces(picked)
	assert_false(read.has("refused"), "the faces are read: %s" % read.get("refused", ""))
	if read.has("refused"):
		return ""
	var before: Array = root.generator_system.generators.keys()
	var result: HFOpResult = root.create_generator(
		TYPE, settings, read["placement"], null, read["run"]
	)
	assert_true(result.ok, "the trim run is built: %s" % result.message)
	for generator_id in root.generator_system.generators:
		if not before.has(generator_id):
			return str(generator_id)
	return ""


func _pieces(root: LevelRoot, generator_id: String) -> Array:
	var out: Array = []
	for brush in root.draft_brushes_node.get_children():
		if str(brush.get_meta(HFGeneratorSystemScript.GENERATOR_META, "")) == generator_id:
			out.append(brush)
	return out


## Every corner of every piece, once a piece, in world space.
func _corners(pieces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for piece: DraftBrush in pieces:
		var seen := {}
		for face in piece.get_faces():
			for corner in face.local_verts:
				var world: Vector3 = piece.global_transform * corner
				var key := SolidChecks.key(world)
				if not seen.has(key):
					seen[key] = true
					out.append(world)
	return out


func _run_points(run: Dictionary, placement: Transform3D) -> Array:
	var out: Array = []
	for corner in run["points"]:
		out.append(placement * Vector3(corner[0], corner[1], corner[2]))
	return out


func _has_point(points: Array, wanted: Vector3) -> bool:
	for corner: Vector3 in points:
		if corner.distance_to(wanted) < EPS:
			return true
	return false


func _assert_solid_pieces(pieces: Array, what: String) -> void:
	for piece: DraftBrush in pieces:
		var faces: Array = piece.get_faces()
		var interior: Vector3 = HFConvexClipScript.interior_point(faces)
		assert_true(HFConvexClipScript.is_convex_solid(faces, interior), "%s: not convex" % what)
		assert_eq(SolidChecks.describe_problem(faces), "", "%s: would not bake" % what)


## Every piece corner within `near` of a room corner in X and Z lies on the plane
## through that corner that bisects its two walls. Returns how many were checked.
func _assert_mitred(corners: PackedVector3Array, room_corners: Array, near: float) -> int:
	var checked := 0
	for room_corner: Dictionary in room_corners:
		var at: Vector3 = room_corner["at"]
		var bisector: Vector3 = room_corner["bisector"]
		for corner in corners:
			if Vector2(corner.x - at.x, corner.z - at.z).length() > near:
				continue
			checked += 1
			var off := absf(bisector.dot(Vector3(corner.x - at.x, 0.0, corner.z - at.z)))
			assert_lt(off, EPS, "%s is on the mitre at %s" % [corner, at])
	return checked


# ===========================================================================
# Reading the run
# ===========================================================================


func test_the_four_inner_faces_of_a_hollowed_box_are_one_closed_run_of_four_corners():
	var root := _root()
	_hollow_room(root)
	var picked := _inner_walls(root)
	assert_eq(picked.size(), 4, "four walls picked")
	var read: Dictionary = root.trim_run_from_faces(picked)
	assert_false(read.has("refused"), str(read.get("refused", "")))
	assert_eq(int(read["used"]), 4, "every face gave an edge")
	for edge in ["bottom", "top"]:
		var runs: Array = read["run"][edge]
		assert_eq(runs.size(), 1, "one %s run" % edge)
		assert_true(runs[0]["closed"], "and it closes")
		var points := _run_points(runs[0], read["placement"])
		assert_eq(points.size(), 4, "four corners")
		# On the floor and under the ceiling, not where the walls that run past
		# the room's corners and under its floor end.
		var height := FLOOR if edge == "bottom" else CEILING
		for x in [-INSIDE, INSIDE]:
			for z in [-INSIDE, INSIDE]:
				var wanted := Vector3(x, height, z)
				assert_true(_has_point(points, wanted), "%s run has the corner %s" % [edge, wanted])


func test_edges_chain_end_to_start_whatever_order_they_are_picked_in():
	# Three faces of a U, given out of order: one open run, corner to corner.
	var faces := [
		_flat_face("east", Vector3(4, 0, 4), Vector3(4, 0, -4), Vector3(-1, 0, 0)),
		_flat_face("south", Vector3(-4, 0, 4), Vector3(4, 0, 4), Vector3(0, 0, -1)),
		_flat_face("north", Vector3(4, 0, -4), Vector3(-4, 0, -4), Vector3(0, 0, 1)),
	]
	var read: Dictionary = HFTrimRunBuilderScript.read(faces, [], [])
	var runs: Array = read["run"]["bottom"]
	assert_eq(runs.size(), 1, "one run")
	assert_false(runs[0]["closed"], "open: the west wall is not picked")
	assert_eq(runs[0]["faces"], ["north", "east", "south"], "read from the end nothing leads into")
	assert_eq(
		runs[0]["points"],
		[[-4.0, 0.0, -4.0], [4.0, 0.0, -4.0], [4.0, 0.0, 4.0], [-4.0, 0.0, 4.0]],
		"each corner once, the room on the right of travel"
	)


func test_faces_that_do_not_meet_are_separate_runs():
	var faces := [
		_flat_face("a", Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, -1)),
		_flat_face("b", Vector3(5, 0, 0), Vector3(9, 0, 0), Vector3(0, 0, -1)),
	]
	var runs: Array = HFTrimRunBuilderScript.read(faces, [], [])["run"]["bottom"]
	assert_eq(runs.size(), 2, "a gap between two faces breaks the run")


func test_a_sloped_face_is_refused_by_name_and_nothing_is_built():
	var root := _root()
	_hollow_room(root)
	# A ramp turned 30 degrees about X, its top face sloped.
	var ramp := _box(
		root,
		Vector3(0, 2, 0),
		Vector3(2, 0.5, 3),
		CSGShape3D.OPERATION_UNION,
		Basis(Vector3.RIGHT, 0.5)
	)
	var picked := _inner_walls(root)
	var sloped := -1
	for i in ramp.get_faces().size():
		var normal := _world_normal(ramp, i)
		if normal.y > 0.5:
			sloped = i
	assert_gt(sloped, -1, "the ramp has a sloped top")
	picked[HFBrushSystem.face_key(ramp)] = [sloped]
	var count := root.generator_count()
	var read: Dictionary = root.trim_run_from_faces(picked)
	assert_true(read.has("refused"), "refused")
	assert_string_contains(str(read.get("refused", "")), "face %d of %s" % [sloped, ramp.name])
	assert_string_contains(str(read.get("refused", "")), "not upright")
	assert_eq(root.generator_count(), count, "and nothing was built")


func test_no_picked_faces_is_refused():
	var root := _root()
	var read: Dictionary = root.trim_run_from_faces({})
	assert_true(read.has("refused"))
	assert_string_contains(str(read["hint"]), "Face Select")


# ===========================================================================
# The pieces
# ===========================================================================


func test_a_closed_run_round_a_room_is_mitred_on_the_bisector_at_every_inside_corner():
	var root := _root()
	_hollow_room(root)
	var generator_id := _create(root, _inner_walls(root), _settings())
	var pieces := _pieces(root, generator_id)
	assert_eq(pieces.size(), 4, "one piece per wall for a flat profile")
	_assert_solid_pieces(pieces, "skirting")
	var corners := _corners(pieces)
	var room_corners: Array = []
	for x in [-INSIDE, INSIDE]:
		for z in [-INSIDE, INSIDE]:
			# Inside corners: the bisector of two walls meeting square is the
			# diagonal through the corner, square to the room's middle.
			room_corners.append(
				{"at": Vector3(x, 0, z), "bisector": Vector3(signf(x), 0, -signf(z)).normalized()}
			)
	assert_eq(_assert_mitred(corners, room_corners, 0.3), 32, "eight corners of each mitre")
	for corner in corners:
		assert_between(corner.y, FLOOR - EPS, FLOOR + 0.2 + EPS, "stands on the floor")
		assert_between(absf(corner.x), 0.0, INSIDE + EPS, "inside the room")
		assert_between(absf(corner.z), 0.0, INSIDE + EPS, "inside the room")


func test_a_run_round_the_outside_of_a_block_is_mitred_at_every_outside_corner():
	var root := _root()
	var block := _box(root, Vector3(0, 1, 0), Vector3(4, 2, 4))
	var sides: Array = []
	for i in block.get_faces().size():
		if absf(_world_normal(block, i).y) < 0.01:
			sides.append(i)
	var picked := {HFBrushSystem.face_key(block): sides}
	var generator_id := _create(root, picked, _settings({"width": 0.25}))
	var pieces := _pieces(root, generator_id)
	assert_eq(pieces.size(), 4)
	_assert_solid_pieces(pieces, "plinth")
	var room_corners: Array = []
	for x in [-2.0, 2.0]:
		for z in [-2.0, 2.0]:
			room_corners.append(
				{"at": Vector3(x, 0, z), "bisector": Vector3(signf(x), 0, -signf(z)).normalized()}
			)
	# An outside corner's mitre runs out from the block to the trim's outer tip.
	var checked := _assert_mitred(_corners(pieces), room_corners, 0.4)
	assert_eq(checked, 32, "eight corners of each mitre")
	assert_true(
		_has_point(Array(_corners(pieces)), Vector3(2.25, 0, 2.25)),
		"the two pieces meet at the tip"
	)


func test_a_cutout_through_a_wall_leaves_a_gap_exactly_its_width():
	var root := _root()
	_hollow_room(root)
	# A doorway a metre wide through the wall at z = 4..5, from the floor up.
	_box(root, Vector3(0.5, 2.0, 4.5), Vector3(1.0, 2.2, 2.0), CSGShape3D.OPERATION_SUBTRACTION)
	var generator_id := _create(root, _inner_walls(root), _settings())
	var pieces := _pieces(root, generator_id)
	assert_eq(pieces.size(), 5, "the wall with the doorway is two pieces")
	var record = root.generator_for_id(generator_id)
	assert_true(record.run["bottom"][0]["closed"], "the run itself still goes all the way round")
	var left := -INF
	var right := INF
	for corner in _corners(pieces):
		if corner.z < INSIDE - 0.2 - EPS:
			continue
		assert_false(corner.x > 0.0 + EPS and corner.x < 1.0 - EPS, "nothing in the doorway")
		if corner.x <= 0.0 + EPS:
			left = maxf(left, corner.x)
		if corner.x >= 1.0 - EPS:
			right = minf(right, corner.x)
	assert_almost_eq(right - left, 1.0, EPS, "the gap is the cutter's width")
	assert_almost_eq(left, 0.0, EPS, "and lies where the cutter does")


func test_a_door_frames_cut_pending_or_applied_is_a_doorway():
	for applied in [false, true]:
		var root := _root()
		_hollow_room(root)
		# A door frame in the wall at z = 4..5, its foot on the floor.
		var placement := Transform3D(Basis.IDENTITY, Vector3(0, FLOOR + 1.1, 4.5))
		var frame := HFGeneratorSystemScript.default_settings("door_frame")
		frame["wall"] = 1.0
		assert_true(root.create_generator("door_frame", frame, placement).ok)
		if applied:
			root.apply_pending_cuts()
		var generator_id := _create(root, _inner_walls(root), _settings())
		var pieces := _pieces(root, generator_id)
		assert_eq(pieces.size(), 5, "applied %s: the doorway's wall is two pieces" % applied)
		for corner in _corners(pieces):
			if corner.z > INSIDE - 0.2 - EPS:
				assert_false(absf(corner.x) < 0.5 - EPS, "nothing across the opening")


func test_a_cutout_above_the_trim_leaves_it_whole():
	var root := _root()
	_hollow_room(root)
	# A window, its sill a metre above the floor.
	_box(root, Vector3(0, 3.0, 4.5), Vector3(1.0, 1.0, 2.0), CSGShape3D.OPERATION_SUBTRACTION)
	var generator_id := _create(root, _inner_walls(root), _settings())
	assert_eq(_pieces(root, generator_id).size(), 4, "a skirting runs under a window")
	var record = root.generator_for_id(generator_id)
	var dado := _settings({"offset": 1.5})
	assert_true(root.regenerate_generator(generator_id, dado).ok)
	assert_eq(_pieces(root, generator_id).size(), 5, "a rail at the window's height breaks at it")
	assert_true(
		HFTrimRunBuilderScript.same_run(record.run, root.generator_for_id(generator_id).run)
	)


func test_edge_top_with_offset_zero_puts_the_profile_flush_with_the_wall_tops():
	var root := _root()
	_hollow_room(root)
	var settings := _settings(
		{"edge": HFTrimRunBuilderScript.EDGE_TOP, "profile": 3, "width": 0.3, "height": 0.25}
	)
	var generator_id := _create(root, _inner_walls(root), settings)
	var high := -INF
	var low := INF
	for corner in _corners(_pieces(root, generator_id)):
		high = maxf(high, corner.y)
		low = minf(low, corner.y)
	assert_almost_eq(high, CEILING, EPS, "flush with the tops")
	assert_almost_eq(low, CEILING - 0.25, EPS, "and hanging its own height")


func test_offset_lifts_a_bottom_run_off_the_floor():
	var root := _root()
	_hollow_room(root)
	var generator_id := _create(root, _inner_walls(root), _settings({"offset": 0.9}))
	var low := INF
	for corner in _corners(_pieces(root, generator_id)):
		low = minf(low, corner.y)
	assert_almost_eq(low, FLOOR + 0.9, EPS)


func test_a_curved_profile_is_one_convex_piece_per_band():
	var root := _root()
	_hollow_room(root)
	var settings := _settings({"profile": 4, "segments": 4, "width": 0.3, "height": 0.4})
	var generator_id := _create(root, _inner_walls(root), settings)
	var bands: int = TrimProfile.bands(4, 0.3, 0.4, 4).size()
	assert_gt(bands, 1, "an ogee is more than one band")
	var pieces := _pieces(root, generator_id)
	assert_eq(pieces.size(), 4 * bands)
	_assert_solid_pieces(pieces, "ogee")


func test_walls_turned_about_y_read_as_well():
	var root := _root()
	var turn := Basis(Vector3.UP, deg_to_rad(30.0))
	# Four walls round a 6 m room, turned 30 degrees together, butted at the corners.
	for side in 4:
		var facing := Basis(Vector3.UP, PI * 0.5 * side)
		var at: Vector3 = turn * facing * Vector3(0, 1.5, 3.25)
		_box(root, at, Vector3(7.0, 3.0, 0.5), CSGShape3D.OPERATION_UNION, turn * facing)
	var picked := _faces_facing(root, Vector3.ZERO, 4.0)
	var read: Dictionary = root.trim_run_from_faces(picked)
	assert_false(read.has("refused"), str(read.get("refused", "")))
	var runs: Array = read["run"]["bottom"]
	assert_eq(runs.size(), 1, "one run")
	assert_true(runs[0]["closed"], "closed round the room")
	assert_eq(_run_points(runs[0], read["placement"]).size(), 4)


# ===========================================================================
# The record
# ===========================================================================


func test_update_with_a_new_profile_keeps_the_run():
	var root := _root()
	_hollow_room(root)
	var generator_id := _create(root, _inner_walls(root), _settings())
	var run: Dictionary = root.generator_for_id(generator_id).run.duplicate(true)
	var cove := _settings({"profile": 3, "width": 0.3, "height": 0.3})
	assert_true(root.can_build_generator(TYPE, cove, generator_id).ok, "the Update is allowed")
	assert_true(root.regenerate_generator(generator_id, cove).ok, "and it rebuilds")
	var record = root.generator_for_id(generator_id)
	assert_true(HFTrimRunBuilderScript.same_run(record.run, run), "along the same run")
	assert_gt(_pieces(root, generator_id).size(), 4, "with the cove's bands")
	assert_true(
		root.generator_update_changes_nothing(generator_id, cove), "and once built, it is settled"
	)


func test_a_level_saved_and_reopened_still_updates():
	var root := _root()
	_hollow_room(root)
	var generator_id := _create(root, _inner_walls(root), _settings())
	var run: Dictionary = root.generator_for_id(generator_id).run.duplicate(true)
	assert_eq(HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state()), OK)

	var copy := _root()
	assert_true(copy.load_hflevel(LEVEL_PATH), "the level opens")
	var record = copy.generator_for_id(generator_id)
	assert_not_null(record, "with its trim run")
	assert_true(HFTrimRunBuilderScript.same_run(record.run, run), "and its run")
	var cornice := _settings({"edge": HFTrimRunBuilderScript.EDGE_TOP})
	assert_true(copy.regenerate_generator(generator_id, cornice).ok, "an Update rebuilds it")
	var high := -INF
	for corner in _corners(_pieces(copy, generator_id)):
		high = maxf(high, corner.y)
	assert_almost_eq(high, CEILING, EPS, "along the run the file kept")


func test_a_run_with_a_face_too_short_for_the_trim_is_refused_and_says_which():
	var root := _root()
	_hollow_room(root)
	var generator_id := _create(root, _inner_walls(root), _settings())
	var wide := _settings({"width": 5.0})
	var check: HFOpResult = root.can_build_generator(TYPE, wide, generator_id)
	assert_false(check.ok, "a trim wider than half the room cannot turn its corners")
	assert_string_contains(check.message, "too short")
	var pieces := _pieces(root, generator_id).size()
	assert_false(root.regenerate_generator(generator_id, wide).ok)
	assert_eq(_pieces(root, generator_id).size(), pieces, "and the run it has is left alone")


func test_a_trim_run_without_a_run_builds_nothing():
	assert_eq(HFGeneratorSystemScript.build_faces(TYPE, _settings()), [])
	assert_false(HFGeneratorSystemScript.can_build(TYPE, _settings()).ok)
	assert_false(Array(HFGeneratorSystemScript.known_types()).has(TYPE), "not built from defaults")
	assert_true(Array(HFGeneratorSystemScript.structure_types()).has(TYPE), "but the dock edits it")


func test_repick_lays_the_trim_along_the_faces_picked_now():
	var root := _root()
	_hollow_room(root)
	var three := _inner_walls(root)
	var keys := three.keys()
	three.erase(keys[0])
	var generator_id := _create(root, three, _settings())
	assert_eq(_pieces(root, generator_id).size(), 3, "three walls")
	assert_false(root.generator_for_id(generator_id).run["bottom"][0]["closed"])

	# The run's own pieces stand in front of the walls, and hide nothing.
	var read: Dictionary = root.trim_run_from_faces(_inner_walls(root))
	assert_false(
		root.generator_repick_changes_nothing(generator_id, read["run"], read["placement"]),
		"four walls are not the three it has"
	)
	assert_true(root.repick_generator(generator_id, read["run"], read["placement"]).ok)
	assert_eq(_pieces(root, generator_id).size(), 4, "all four walls now")
	var record = root.generator_for_id(generator_id)
	assert_true(record.run["bottom"][0]["closed"], "closed round the room")
	var low := INF
	for corner in _corners(_pieces(root, generator_id)):
		low = minf(low, corner.y)
	assert_almost_eq(low, FLOOR, EPS, "on the floor, not on top of the old trim")

	var again: Dictionary = root.trim_run_from_faces(_inner_walls(root))
	assert_true(
		root.generator_repick_changes_nothing(generator_id, again["run"], again["placement"]),
		"the same faces again would change nothing"
	)


# ===========================================================================
# Helpers for the plain-data tests
# ===========================================================================


## An upright face 3 m tall from `a` to `b` on the ground, facing `normal`.
func _flat_face(face_name: String, a: Vector3, b: Vector3, normal: Vector3) -> Dictionary:
	var up := Vector3(0, 3, 0)
	return {
		"id": face_name,
		"name": face_name,
		"verts": PackedVector3Array([a, b, b + up, a + up]),
		"normal": normal,
	}
