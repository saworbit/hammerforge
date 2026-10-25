extends GutTest

## Sweep the picked faces into a run of brushes along a bend (#1714).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFFaceSweep = preload("res://addons/hammerforge/hf_face_sweep.gd")
const HFPluginFaceSweep = preload("res://addons/hammerforge/plugin_face_sweep.gd")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


## A level with a 1 by 1 by 1 box, its +X face picked.
func _picked_face() -> Array:
	var level = await rig.make_level()
	rig.undo().clear()
	var box = rig.box(level, "source", Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var index := -1
	for i in box.faces.size():
		if (box.global_basis * box.faces[i].normal).normalized().is_equal_approx(Vector3.RIGHT):
			index = i
	level.face_selection = {"source": [index]}
	return [level, box, index]


func _values(changes: Dictionary) -> Dictionary:
	var values: Dictionary = HFPluginFaceSweep.DEFAULTS.duplicate()
	values.merge(changes, true)
	return values


static func _corner_set(face) -> Array:
	var out: Array = []
	for corner in face.local_verts:
		out.append((corner as Vector3).snapped(Vector3.ONE * 0.001))
	out.sort()
	return out


## Whether `a` and `b` have a face with the same corners.
static func _share_a_face(a: Array, b: Array) -> bool:
	for face_a in a:
		var corners := _corner_set(face_a)
		for face_b in b:
			if _corner_set(face_b) == corners:
				return true
	return false


func test_a_face_through_a_quarter_arc_in_eight_is_eight_convex_pieces_face_to_face():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var cut := HFPluginFaceSweep.section(level)
	assert_true(cut["ok"], "fixture: the face is the section")
	var plan := HFPluginFaceSweep.plan(
		cut, _values({"path": HFFaceSweep.Path.ARC, "angle": 90.0, "radius": 4.0, "segments": 8})
	)
	var pieces: Array = plan["pieces"]
	assert_eq(pieces.size(), 8)
	assert_eq(plan["folded"], 0)
	for i in pieces.size():
		assert_true(HFSolidMeasure.is_convex(pieces[i]["faces"]), "piece %d is convex" % i)
		if i > 0:
			assert_true(
				_share_a_face(pieces[i - 1]["faces"], pieces[i]["faces"]),
				"pieces %d and %d meet face to face" % [i - 1, i]
			)
	await rig.leave_level(level)


func test_an_s_bend_between_parallel_offset_caps_is_a_smooth_run():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var cut := HFPluginFaceSweep.section(level)
	var plan := HFPluginFaceSweep.plan(
		cut,
		_values({"path": HFFaceSweep.Path.S_BEND, "length": 8.0, "offset": 3.0, "segments": 10})
	)
	var pieces: Array = plan["pieces"]
	assert_eq(plan["folded"], 0)
	for i in range(1, pieces.size()):
		assert_true(_share_a_face(pieces[i - 1]["faces"], pieces[i]["faces"]), "joined at %d" % i)
	var frames: Array = plan["frames"]
	var first: Transform3D = frames[0]
	var last: Transform3D = frames[frames.size() - 1]
	assert_true(last.basis.is_equal_approx(first.basis), "it ends facing the way it began")
	var moved := last.origin - first.origin
	assert_almost_eq(moved.dot(first.basis.z), 8.0, 0.001, "8 m along")
	assert_almost_eq(moved.length(), sqrt(64.0 + 9.0), 0.001, "and 3 m aside")
	# Smooth: no joint turns much more than its neighbours.
	for k in range(1, frames.size() - 1):
		var turn := (frames[k - 1] as Transform3D).basis.z.angle_to(
			(frames[k] as Transform3D).basis.z
		)
		assert_lt(turn, deg_to_rad(20.0), "a gentle turn at %d" % k)
	await rig.leave_level(level)


func test_four_turns_of_a_quarter_arc_close_a_loop():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var cut := HFPluginFaceSweep.section(level)
	var plan := HFPluginFaceSweep.plan(
		cut,
		_values(
			{
				"path": HFFaceSweep.Path.ARC,
				"angle": 90.0,
				"radius": 4.0,
				"segments": 6,
				"iterations": 4
			}
		)
	)
	var frames: Array = plan["frames"]
	assert_eq(frames.size(), 4 * 6 + 1)
	var first: Transform3D = frames[0]
	var last: Transform3D = frames[frames.size() - 1]
	assert_almost_eq(last.origin, first.origin, Vector3.ONE * 0.001, "back where it began")
	assert_true(last.basis.is_equal_approx(first.basis), "facing the same way")
	assert_eq((plan["pieces"] as Array).size(), 24)
	assert_true(
		_share_a_face(plan["pieces"][23]["faces"], plan["pieces"][0]["faces"]),
		"the last piece meets the first"
	)
	await rig.leave_level(level)


func test_a_bend_too_tight_for_the_face_folds_and_makes_nothing():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var brushes: int = level._iter_managed_brush_nodes().size()
	var steps: int = rig.undo().step_count()
	var tight := _values({"path": HFFaceSweep.Path.ARC, "angle": 90.0, "radius": 0.2})
	assert_gt(HFPluginFaceSweep.plan(HFPluginFaceSweep.section(level), tight)["folded"], 0)
	rig.clear_toasts()
	assert_false(HFPluginFaceSweep.run(rig.plugin, level, tight))
	assert_eq(level._iter_managed_brush_nodes().size(), brushes, "nothing made")
	assert_eq(rig.undo().step_count(), steps, "and no step")
	assert_true(rig.toasts().any(func(t): return t.contains("fold back")), "it says why")
	await rig.leave_level(level)


func test_the_pieces_carry_the_face_s_material_in_one_group_and_one_step():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var box = made[1]
	box.faces[made[2]].material_idx = 2
	var before: Array = level._iter_managed_brush_nodes()
	var steps: int = rig.undo().step_count()
	assert_true(HFPluginFaceSweep.run(rig.plugin, level, _values({"segments": 4})))
	var pieces: Array = level._iter_managed_brush_nodes().filter(func(b): return not before.has(b))
	assert_eq(pieces.size(), 4)
	var groups := {}
	for piece in pieces:
		groups[str(piece.get_meta("group_id", ""))] = true
		for face in piece.faces:
			assert_eq(face.material_idx, 2, "the face's material")
	assert_eq(groups.size(), 1, "one group")
	assert_false(groups.has(""), "and it is a group")
	assert_eq(rig.undo().step_count(), steps + 1, "one step")
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), before.size(), "one Ctrl+Z takes it back")
	await rig.leave_level(level)


func test_faces_not_in_one_plane_are_refused():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var other := 0 if made[2] != 0 else 1
	level.face_selection = {"source": [made[2], other]}
	var cut := HFPluginFaceSweep.section(level)
	assert_false(cut["ok"])
	assert_string_contains(str(cut["reason"]), "one plane")
	await rig.leave_level(level)


func test_the_dialog_outlines_the_pieces_and_ok_makes_them():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var before: int = level._iter_managed_brush_nodes().size()
	assert_true(HFPluginFaceSweep.open(rig.plugin, level))
	var dialogs: Array = rig.open_dialogs()
	assert_eq(dialogs.size(), 1, "it asks")
	if dialogs.size() == 1:
		assert_false(dialogs[0].get_ok_button().disabled, "the default arc can be made")
		var preview: Node = level.find_child("SweepPreview", true, false)
		assert_not_null(preview, "with the pieces outlined")
	assert_eq(await rig.accept_dialogs(), 1)
	assert_eq(level._iter_managed_brush_nodes().size(), before + 8, "OK makes the eight")
	assert_null(level.find_child("SweepPreview", true, false), "and the outline goes")
	await rig.leave_level(level)
