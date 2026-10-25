extends GutTest

## Sweep the picked faces into a run of brushes along a bend (#1714).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFFaceSweep = preload("res://addons/hammerforge/hf_face_sweep.gd")
const HFPluginFaceSweep = preload("res://addons/hammerforge/plugin_face_sweep.gd")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

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


## Each side of a piece takes the look of the box's face that meets the swept face
## along that edge, and the ends the swept face's own (#1899). Every face used to
## take the swept face's material, so a wall's brick sides came out in the end
## face's.
func test_the_pieces_carry_each_side_s_material_in_one_group_and_one_step():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var box = made[1]
	var slot_of := {
		Vector3.RIGHT: 2, Vector3.UP: 3, Vector3.DOWN: 4, Vector3.BACK: 5, Vector3.FORWARD: 6
	}
	for face in box.faces:
		for normal in slot_of:
			if (face.normal as Vector3).is_equal_approx(normal):
				face.material_idx = slot_of[normal]
	var before: Array = level._iter_managed_brush_nodes()
	var steps: int = rig.undo().step_count()
	var straight := {"path": HFFaceSweep.Path.STRAIGHT, "segments": 4}
	assert_true(HFPluginFaceSweep.run(rig.plugin, level, _values(straight)))
	var pieces: Array = level._iter_managed_brush_nodes().filter(func(b): return not before.has(b))
	assert_eq(pieces.size(), 4)
	var groups := {}
	for piece in pieces:
		groups[str(piece.get_meta("group_id", ""))] = true
		for face in piece.faces:
			var facing: Vector3 = (piece.global_basis * face.normal).normalized()
			var wanted := 2
			for normal in [Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
				if facing.is_equal_approx(normal):
					wanted = slot_of[normal]
			assert_eq(face.material_idx, wanted, "the face facing %s" % facing)
	assert_eq(groups.size(), 1, "one group")
	assert_false(groups.has(""), "and it is a group")
	assert_eq(rig.undo().step_count(), steps + 1, "one step")
	rig.undo().press_undo()
	await rig.frame()
	assert_eq(level._iter_managed_brush_nodes().size(), before.size(), "one Ctrl+Z takes it back")
	await rig.leave_level(level)


## An End scale of 0.5 ends the run at half the width and height, each piece
## convex and meeting the next face to face (#1899).
func test_a_straight_run_with_end_scale_half_ends_at_half_size():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _picked_face()
	var level = made[0]
	var cut := HFPluginFaceSweep.section(level)
	var values := _values(
		{
			"path": HFFaceSweep.Path.STRAIGHT,
			"length": 4.0,
			"segments": 4,
			"end_width": 0.5,
			"end_height": 0.5,
		}
	)
	var plan := HFPluginFaceSweep.plan(cut, values)
	assert_eq(int(plan["folded"]), 0)
	var pieces: Array = plan["pieces"]
	assert_eq(pieces.size(), 4)
	for i in pieces.size():
		var faces: Array = pieces[i]["faces"]
		assert_true(HFSolidMeasure.is_convex(faces), "piece %d is convex" % i)
		if i > 0:
			assert_true(
				_share_a_face(pieces[i - 1]["faces"], faces), "piece %d meets the one before" % i
			)
	var far_cap: PackedVector3Array = PackedVector3Array()
	for face in pieces[3]["faces"] as Array:
		if (face.normal as Vector3).is_equal_approx(Vector3.RIGHT):
			far_cap = face.local_verts
	assert_eq(far_cap.size(), 4, "the far end is a square")
	var low := Vector3(INF, INF, INF)
	var high := -low
	for corner in far_cap:
		low = low.min(corner)
		high = high.max(corner)
	assert_almost_eq(high.x, 4.5, 0.0001, "4 m along")
	assert_almost_eq(high.y - low.y, 0.5, 0.0001, "half as tall")
	assert_almost_eq(high.z - low.z, 0.5, 0.0001, "and half as wide")
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


# ===========================================================================
# A sweep kept as a structure (#1885)
# ===========================================================================

const SAVE_PATH := "user://test_face_sweep_live.hflevel"


func _sweeps(level) -> Array:
	return level.generator_system.generators.values().filter(
		func(record): return record.type == HFGeneratorSystemScript.TYPE_SWEEP
	)


func _pieces_of(level, record) -> Array:
	var out: Array = []
	for brush_id in record.brush_ids:
		var brush = level.find_brush_by_id(str(brush_id))
		if brush:
			out.append(brush)
	return out


func _swept(changes: Dictionary) -> Array:
	var made: Array = await _picked_face()
	var level = made[0]
	assert_true(HFPluginFaceSweep.run(rig.plugin, level, _values(changes)), "fixture: swept")
	var records := _sweeps(level)
	assert_eq(records.size(), 1, "fixture: one sweep structure")
	return [level, records[0]]


func test_ok_keeps_the_sweep_and_a_piece_shows_it_in_the_structure_section():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _swept({"segments": 8})
	var level = made[0]
	var record = made[1]
	assert_eq(_pieces_of(level, record).size(), 8, "eight pieces")
	assert_eq(int(record.settings["segments"]), 8, "with the values it was made with")
	rig.select([_pieces_of(level, record)[3]])
	await rig.frame()
	var dock = rig.plugin.dock
	dock.refresh_structure_section()
	assert_eq(str(dock._active_generator_id), str(record.generator_id), "the section edits it")
	assert_eq(HFDockBrushHandler.structure_type(dock), HFGeneratorSystemScript.TYPE_SWEEP)
	assert_eq(int((dock.structure_fields["segments"] as SpinBox).value), 8, "showing its values")
	rig.select([])
	await rig.leave_level(level)


func test_more_segments_rebuild_it_in_place_as_one_step():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _swept({"segments": 8})
	var level = made[0]
	var record = made[1]
	var group := str(_pieces_of(level, record)[0].get_meta("group_id", ""))
	rig.select([_pieces_of(level, record)[0]])
	await rig.frame()
	var dock = rig.plugin.dock
	dock.refresh_structure_section()
	(dock.structure_fields["segments"] as SpinBox).value = 12
	var steps: int = rig.undo().step_count()
	HFDockBrushHandler.on_update_structure(dock)
	assert_eq(_pieces_of(level, record).size(), 12, "twelve pieces")
	assert_eq(rig.undo().step_count(), steps + 1, "in one undo step")
	assert_eq(
		str(_pieces_of(level, record)[0].get_meta("group_id", "")), group, "in the group it was in"
	)
	rig.undo().press_undo()
	await rig.frame()
	# The undo puts the level's records back, this one among them.
	assert_eq(_pieces_of(level, _sweeps(level)[0]).size(), 8, "Ctrl+Z gives the eight back")
	rig.select([])
	await rig.leave_level(level)


func test_a_rebuild_that_folds_a_piece_is_refused_and_changes_nothing():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _swept({"segments": 8})
	var level = made[0]
	var record = made[1]
	var before: Array = Array(record.brush_ids)
	var settings: Dictionary = record.settings.duplicate()
	settings["radius"] = 0.1
	var result: HFOpResult = level.regenerate_generator(str(record.generator_id), settings)
	assert_false(result.ok, "refused")
	assert_string_contains(result.message, "fold back on themselves")
	assert_eq(Array(record.brush_ids), before, "and the pieces are the ones it had")
	await rig.leave_level(level)


func test_detach_leaves_plain_brushes():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _swept({"segments": 4})
	var level = made[0]
	var record = made[1]
	var pieces := _pieces_of(level, record)
	assert_true(level.detach_generator(str(record.generator_id)))
	assert_eq(_sweeps(level).size(), 0, "no sweep is kept")
	for piece in pieces:
		assert_true(is_instance_valid(piece), "every piece stays")
		assert_null(level.generator_for_selection([str(piece.brush_id)]), "as a plain brush")
	await rig.leave_level(level)


func test_a_saved_and_reopened_sweep_is_still_editable():
	if rig.plugin == null:
		fail_test(rig.error())
		return
	var made: Array = await _swept({"segments": 6})
	var level = made[0]
	assert_eq(level.save_hflevel(SAVE_PATH, true), OK)
	await rig.leave_level(level)
	var other = await rig.make_level()
	assert_true(other.load_hflevel(SAVE_PATH))
	var records := _sweeps(other)
	assert_eq(records.size(), 1, "the sweep comes back")
	var settings: Dictionary = records[0].settings.duplicate()
	settings["segments"] = 3
	var result: HFOpResult = other.regenerate_generator(str(records[0].generator_id), settings)
	assert_true(result.ok, "and rebuilds: %s" % result.message)
	assert_eq(_pieces_of(other, records[0]).size(), 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await rig.leave_level(other)
