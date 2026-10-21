extends GutTest

## HFDoorFrameBuilder: two posts and a head round a clear opening, and the cut that
## makes the opening, as one structure (#1411).
##
## The claims are measured rather than read off the code: the posts' inner faces
## and the head's underside bound exactly the opening, an arched head sits on the
## posts with no gap, every piece is a closed convex solid, and the cut is one
## piece the generator system makes a Cutout. On a level, the cut goes through
## Pending Cuts like a drawn one, follows an Update before and after Apply, and
## Validate reads it as a doorway.

const HFDoorFrameBuilderScript = preload("res://addons/hammerforge/hf_door_frame_builder.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

const EPS := 0.001


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFDoorFrameBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


## The bounds of a piece's corners.
func _bounds(faces: Array) -> AABB:
	var box := AABB(faces[0].local_verts[0], Vector3.ZERO)
	for face in faces:
		for v in face.local_verts:
			box = box.expand(v)
	return box


func _assert_convex_solids(pieces: Array, what: String) -> void:
	for piece in pieces:
		var interior: Vector3 = HFConvexClipScript.interior_point(piece)
		assert_true(HFConvexClipScript.is_convex_solid(piece, interior), "%s: not convex" % what)
		assert_eq(SolidChecks.describe_problem(piece), "", "%s: would not bake" % what)


# ===========================================================================
# The pieces
# ===========================================================================


func test_a_flat_frame_is_two_posts_a_lintel_and_the_cut_last():
	var settings := _settings()
	var pieces: Array = HFDoorFrameBuilderScript.build(settings)
	assert_eq(pieces.size(), 4, "two posts, a lintel and the cut")
	assert_eq(Array(HFDoorFrameBuilderScript.cutter_pieces(settings)), [3], "the cut is last")
	assert_eq(
		Array(HFGeneratorSystemScript.cutter_pieces("door_frame", settings)),
		[3],
		"and the generator system asks the builder"
	)


func test_with_cut_opening_off_there_is_no_cut():
	var settings := _settings({"cut_opening": false})
	assert_eq(HFDoorFrameBuilderScript.build(settings).size(), 3)
	assert_eq(Array(HFDoorFrameBuilderScript.cutter_pieces(settings)), [])


func test_an_arched_frame_is_two_posts_a_piece_per_segment_and_the_cut():
	for segments in [2, 8, 64]:
		var settings := _settings(
			{"head": HFDoorFrameBuilderScript.HEAD_ARCHED, "segments": segments}
		)
		var pieces: Array = HFDoorFrameBuilderScript.build(settings)
		assert_eq(pieces.size(), 2 + segments + 1, "%d segments" % segments)
		assert_eq(Array(HFDoorFrameBuilderScript.cutter_pieces(settings)), [2 + segments])
		var cut: Array = pieces[pieces.size() - 1]
		assert_eq(cut.size(), segments + 5, "one cut: box sides, a face per segment, two ends")
		assert_lte(cut.size(), HFConvexClipScript.MAX_BOOLEAN_PLANES)


func test_other_builders_make_no_cuts():
	for type in HFGeneratorSystemScript.known_types():
		if type == "door_frame":
			continue
		var settings := HFGeneratorSystemScript.default_settings(type)
		assert_eq(Array(HFGeneratorSystemScript.cutter_pieces(type, settings)), [], type)


func test_every_piece_is_a_convex_solid():
	_assert_convex_solids(HFDoorFrameBuilderScript.build(_settings()), "flat")
	_assert_convex_solids(
		HFDoorFrameBuilderScript.build(_settings({"head": 1, "segments": 2})), "two segments"
	)
	_assert_convex_solids(
		HFDoorFrameBuilderScript.build(_settings({"head": 1, "segments": 64, "proud": 0.0})),
		"sixty-four segments, flush"
	)


func test_a_1_by_2_1_opening_in_a_0_2_wall_is_bounded_exactly_by_the_posts_and_lintel():
	var settings := _settings({"width": 1.0, "height": 2.1, "wall": 0.2, "frame": 0.1})
	var pieces: Array = HFDoorFrameBuilderScript.build(settings)
	var left := _bounds(pieces[0])
	var right := _bounds(pieces[1])
	var lintel := _bounds(pieces[2])
	var cut := _bounds(pieces[3])
	var foot := left.position.y
	assert_almost_eq(left.end.x, -0.5, EPS, "the left post's inner face")
	assert_almost_eq(right.position.x, 0.5, EPS, "the right post's inner face")
	assert_almost_eq(lintel.position.y - foot, 2.1, EPS, "the lintel's underside")
	assert_almost_eq(right.position.y, foot, EPS, "both posts stand on the foot")
	assert_almost_eq(left.end.y - foot, 2.1, EPS, "and reach the lintel")
	assert_almost_eq(lintel.position.x, -0.6, EPS, "the lintel spans both posts")
	assert_almost_eq(lintel.end.x, 0.6, EPS)
	var proud: float = settings["proud"]
	for box in [left, right, lintel]:
		assert_almost_eq(box.size.z, 0.2 + 2.0 * proud, EPS, "the frame stands proud of each face")
	assert_almost_eq(cut.position, Vector3(-0.5, foot, -0.1 - proud), Vector3.ONE * EPS)
	assert_almost_eq(cut.size, Vector3(1.0, 2.1, 0.2 + 2.0 * proud), Vector3.ONE * EPS)


func test_the_frame_is_built_about_its_own_middle():
	var box := AABB()
	var first := true
	for piece in HFDoorFrameBuilderScript.build(_settings({"head": 1})):
		box = _bounds(piece) if first else box.merge(_bounds(piece))
		first = false
	assert_almost_eq(box.get_center(), Vector3.ZERO, Vector3.ONE * EPS)


func test_an_arched_head_rests_on_the_posts_with_no_gap():
	var settings := _settings({"head": 1, "segments": 6, "width": 1.2, "frame": 0.15})
	var pieces: Array = HFDoorFrameBuilderScript.build(settings)
	var left := _bounds(pieces[0])
	var right := _bounds(pieces[1])
	var arch: Array = pieces.slice(2, 8)
	# The segment over each post has a face lying exactly on that post's top.
	for post in [left, right]:
		var resting := false
		for piece in arch:
			for face in piece:
				var on_top := true
				for v in face.local_verts:
					var level: bool = absf(v.y - post.end.y) <= EPS
					var over: bool = v.x >= post.position.x - EPS and v.x <= post.end.x + EPS
					on_top = on_top and level and over
				if on_top and _bounds([face]).size.x >= post.size.x - EPS:
					resting = true
		assert_true(resting, "a segment's foot covers the post at %s" % str(post.position))
	# And nothing of the arch hangs below the posts' tops.
	for piece in arch:
		assert_gte(_bounds(piece).position.y, left.end.y - EPS)


func test_an_arched_opening_reaches_its_height_at_the_crown():
	var settings := _settings({"head": 1, "width": 1.0, "height": 2.1, "segments": 8})
	var pieces: Array = HFDoorFrameBuilderScript.build(settings)
	var cut := _bounds(pieces[pieces.size() - 1])
	var foot := _bounds(pieces[0]).position.y
	assert_almost_eq(cut.size.y, 2.1, EPS, "the cut is the opening's full height")
	assert_almost_eq(cut.position.y, foot, EPS, "from its foot")
	assert_almost_eq(_bounds(pieces[0]).end.y - foot, 1.6, EPS, "the posts stop where it springs")


func test_the_arched_cut_meets_every_segment_s_inside():
	var settings := _settings({"head": 1, "segments": 5})
	var pieces: Array = HFDoorFrameBuilderScript.build(settings)
	var cut_corners := {}
	for face in pieces[pieces.size() - 1]:
		for v in face.local_verts:
			cut_corners[SolidChecks.key(v)] = true
	var spring: float = _bounds(pieces[0]).end.y
	var half_width := 0.5
	for k in 6:
		var angle := PI * float(k) / 5.0
		var corner := Vector3(half_width * cos(angle), spring + half_width * sin(angle), 0.0)
		for z in [-1.0, 1.0]:
			corner.z = z * _bounds(pieces[0]).end.z
			assert_true(cut_corners.has(SolidChecks.key(corner)), "the cut meets %s" % corner)


# ===========================================================================
# Refusals
# ===========================================================================


func test_an_arched_head_too_tall_for_the_opening_is_refused():
	var result = HFDoorFrameBuilderScript.validate(
		_settings({"head": 1, "width": 2.0, "height": 1.0})
	)
	assert_false(result.ok, "the posts would have no height")
	assert_eq(
		HFDoorFrameBuilderScript.build(_settings({"head": 1, "width": 2.0, "height": 1.0})), []
	)
	assert_eq(
		Array(HFDoorFrameBuilderScript.cutter_pieces({"head": 1, "width": 2.0, "height": 1.0})), []
	)


func test_a_flat_head_has_no_such_limit():
	assert_true(HFDoorFrameBuilderScript.validate(_settings({"width": 2.0, "height": 1.0})).ok)


func test_out_of_range_settings_are_refused_through_the_system():
	for bad in [{"segments": 1}, {"segments": 65}, {"proud": -0.1}, {"width": 0.0}]:
		assert_false(HFGeneratorSystemScript.validate("door_frame", _settings(bad)).ok, str(bad))


func test_the_defaults_build_a_framed_doorway_with_its_cut():
	assert_true(HFDoorFrameBuilderScript.validate({}).ok)
	var defaults := HFDoorFrameBuilderScript.default_settings()
	assert_almost_eq(float(defaults["width"]), 1.0, EPS)
	assert_almost_eq(float(defaults["height"]), 2.1, EPS)
	assert_true(bool(defaults["cut_opening"]))


# ===========================================================================
# On a level: the cut through Pending Cuts, Update, Detach and the carry
# ===========================================================================


func _level() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _only_generator(root: LevelRoot) -> String:
	assert_eq(root.generator_count(), 1, "one door frame was built")
	return str(root.generator_system.generators.keys()[0])


func _pieces(root: LevelRoot, generator_id: String) -> Array:
	var out: Array = []
	for brush_id in root.generator_system.generator_for_id(generator_id).brush_ids:
		out.append(root.brush_system.find_brush_by_id(str(brush_id)))
	return out


func _cut(root: LevelRoot, generator_id: String) -> DraftBrush:
	var pieces := _pieces(root, generator_id)
	return pieces[pieces.size() - 1]


## A piece's world bounds, from its corners.
func _world_bounds(brush: DraftBrush) -> AABB:
	var box := AABB()
	var first := true
	for face in brush.faces:
		for v in face.local_verts:
			var world: Vector3 = brush.global_transform * v
			box = AABB(world, Vector3.ZERO) if first else box.expand(world)
			first = false
	return box


func test_the_cut_is_a_pending_cut_and_keeps_the_cut_look():
	var root := _level()
	var paint := StandardMaterial3D.new()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY, paint).ok)
	var generator_id := _only_generator(root)
	var pieces := _pieces(root, generator_id)
	var cut: DraftBrush = pieces[3]
	assert_eq(cut.get_parent(), root.pending_node, "it waits in Pending Cuts like a drawn one")
	assert_true(cut.is_pending_cut())
	assert_eq(cut.operation, CSGShape3D.OPERATION_SUBTRACTION)
	assert_null(cut.material_override, "a cut is not given the Active Material")
	for i in 3:
		assert_eq(pieces[i].get_parent(), root.draft_brushes_node, "the frame is solid")
		assert_eq(pieces[i].operation, CSGShape3D.OPERATION_UNION)
		assert_eq(pieces[i].material_override, paint, "and takes the material")
	assert_eq(root.edited_generator_pieces(generator_id), 0, "nothing reads as edited")


func test_an_update_of_the_width_resizes_the_cut_before_apply():
	var root := _level()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)

	assert_true(root.regenerate_generator(generator_id, _settings({"width": 1.5})).ok)

	var cut := _cut(root, generator_id)
	assert_true(cut.is_pending_cut(), "still pending")
	assert_eq(cut.get_parent(), root.pending_node)
	assert_almost_eq(_world_bounds(cut).size.x, 1.5, EPS, "the cut is the new width")
	var pieces := _pieces(root, generator_id)
	assert_almost_eq(_world_bounds(pieces[0]).end.x, -0.75, EPS, "and so is the frame")
	assert_almost_eq(_world_bounds(pieces[1]).position.x, 0.75, EPS)
	assert_eq(root.pending_node.get_child_count(), 1, "the old cut is gone")


func test_an_update_of_the_width_resizes_the_cut_after_apply():
	var root := _level()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)
	root.apply_pending_cuts()
	var applied := _cut(root, generator_id)
	assert_false(applied.is_pending_cut(), "fixture: the cut was applied")
	assert_eq(root.edited_generator_pieces(generator_id), 0, "applying it is not an edit")

	assert_true(root.regenerate_generator(generator_id, _settings({"width": 1.4})).ok)

	var cut := _cut(root, generator_id)
	assert_eq(cut.get_parent(), root.draft_brushes_node, "a doorway already cut stays cut")
	assert_false(cut.is_pending_cut())
	assert_eq(cut.operation, CSGShape3D.OPERATION_SUBTRACTION)
	assert_almost_eq(_world_bounds(cut).size.x, 1.4, EPS, "at its new size")
	assert_eq(root.pending_node.get_child_count(), 0, "and nothing waits in Pending Cuts")
	var cuts := 0
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush and child.operation == CSGShape3D.OPERATION_SUBTRACTION:
			cuts += 1
	assert_eq(cuts, 1, "the old cut is gone")


func test_turning_cut_opening_off_and_on_takes_the_cut_away_and_back():
	var root := _level()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)

	assert_true(root.regenerate_generator(generator_id, _settings({"cut_opening": false})).ok)
	assert_eq(_pieces(root, generator_id).size(), 3)
	assert_eq(root.pending_node.get_child_count(), 0, "no cut")

	assert_true(root.regenerate_generator(generator_id, _settings()).ok)
	assert_eq(root.pending_node.get_child_count(), 1, "the cut is back, pending")


func test_a_cut_an_update_adds_does_not_take_the_frame_s_material():
	var root := _level()
	assert_true(
		(
			root
			. create_generator(
				"door_frame", _settings({"cut_opening": false}), Transform3D.IDENTITY
			)
			. ok
		)
	)
	var generator_id := _only_generator(root)
	var oak := StandardMaterial3D.new()
	for piece in _pieces(root, generator_id):
		piece.material_override = oak

	assert_true(root.regenerate_generator(generator_id, _settings({"head": 1})).ok)

	var pieces := _pieces(root, generator_id)
	for i in pieces.size() - 1:
		assert_eq(pieces[i].material_override, oak, "every frame piece is oak")
	assert_null(_cut(root, generator_id).material_override, "the cut keeps the cut look")


func test_a_new_head_never_hands_the_cut_s_name_to_a_frame_piece():
	var root := _level()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)
	var pieces := _pieces(root, generator_id)
	var cut_name := str(pieces[3].name)
	var post_name := str(pieces[0].name)
	var oak := StandardMaterial3D.new()
	pieces[0].material_override = oak

	assert_true(root.regenerate_generator(generator_id, _settings({"head": 1, "segments": 4})).ok)

	var rebuilt := _pieces(root, generator_id)
	assert_eq(rebuilt.size(), 7)
	assert_eq(str(rebuilt[6].name), cut_name, "the cut keeps its own name")
	assert_eq(str(rebuilt[0].name), post_name, "and the post its own")
	assert_eq(rebuilt[0].material_override, oak, "with its look")
	assert_ne(str(rebuilt[3].name), cut_name, "an arch segment is not named as the cut")


func test_a_new_head_puts_a_painted_cut_at_risk_and_not_a_painted_post():
	# The cut's look goes to the new cut, which an arched head makes of more faces
	# than the box it was. Matched by place in the list, it was weighed against an
	# arch segment of six faces and read as safe.
	var root := _level()
	root.add_material_to_palette(StandardMaterial3D.new())
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)
	var pieces := _pieces(root, generator_id)
	root.assign_material_to_faces_by_id(str(pieces[1].brush_id), [0], 0)
	root.assign_material_to_faces_by_id(str(pieces[3].brush_id), [0], 0)

	var at_risk: PackedStringArray = root.generator_appearance_at_risk(
		generator_id, _settings({"head": 1})
	)

	assert_eq(Array(at_risk), [str(pieces[3].brush_id)], "only the cut, whose faces change")


func test_detach_leaves_the_cut_a_pending_cut_of_its_own():
	var root := _level()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)
	var cut := _cut(root, generator_id)
	assert_true(root.detach_generator(generator_id))
	assert_true(is_instance_valid(cut))
	assert_true(cut.is_pending_cut(), "an ordinary pending cut now")
	assert_false(cut.has_meta(HFGeneratorSystemScript.GENERATOR_META))
	root.apply_pending_cuts()
	assert_eq(cut.get_parent(), root.draft_brushes_node, "which Apply takes like any other")


func test_a_refused_update_leaves_the_frame_and_its_cut_alone():
	var root := _level()
	assert_true(root.create_generator("door_frame", _settings(), Transform3D.IDENTITY).ok)
	var generator_id := _only_generator(root)
	var ids_before := Array(root.generator_system.generator_for_id(generator_id).brush_ids)
	var bad := _settings({"head": 1, "width": 3.0, "height": 1.0})
	var result: HFOpResult = root.regenerate_generator(generator_id, bad)
	assert_false(result.ok)
	assert_eq(Array(root.generator_system.generator_for_id(generator_id).brush_ids), ids_before)
	assert_eq(root.pending_node.get_child_count(), 1, "the cut is still there")


# ===========================================================================
# Validate
# ===========================================================================


func _findings(root: LevelRoot, kind: String) -> Array:
	var found: Array = []
	for finding in root.validate_level(false).get("findings", []):
		if str(finding.get("type", "")) == kind:
			found.append(finding)
	return found


## A wall 6 m along x, 3 m high and `thickness` thick on y 0, and a door frame
## standing on its foot in the middle of it.
func _door_in_a_wall(root: LevelRoot, overrides: Dictionary, thickness := 0.2) -> void:
	root.create_brush_from_info(
		{
			"shape": LevelRoot.BrushShape.BOX,
			"size": Vector3(6, 3, thickness),
			"center": Vector3(0, 1.5, 0)
		}
	)
	var settings := _settings(overrides)
	var lift := (float(settings["height"]) + float(settings["frame"])) * 0.5
	var placement := Transform3D(Basis.IDENTITY, Vector3(0, lift, 0))
	assert_true(root.create_generator("door_frame", settings, placement).ok)


func test_validate_reads_a_full_height_door_as_a_doorway_the_player_fits():
	var root := _level()
	_door_in_a_wall(root, {})
	assert_eq(_findings(root, "small_doorway"), [])


func test_validate_still_reports_a_door_lower_than_the_player():
	var root := _level()
	_door_in_a_wall(root, {"height": 1.2})
	var found := _findings(root, "small_doorway")
	assert_eq(found.size(), 1, "the cut is read as a doorway")
	if found.size() == 1:
		assert_string_contains(found[0]["message"], "crouch")
		assert_true(str(found[0]["message"]).contains("1.20"), found[0]["message"])


func test_validate_measures_an_arched_door_to_its_crown():
	# 2.0 wide and 2.4 high springs at 1.4, under the player's 1.6. Read only to
	# the springing line, it would say the player has to crouch.
	var root := _level()
	_door_in_a_wall(root, {"head": 1, "width": 2.0, "height": 2.4})
	assert_eq(_findings(root, "small_doorway"), [])
