extends GutTest

## The whole level undo step keeps each brush's faces record between steps
## (#1866), and the check after an undo looks at the brushes the step names.
##
## A record kept is a record that can go stale, so the comparer that captured
## every brush in full is kept here as the test: random edits, undos and redos,
## and after each one every brush's kept record is the record a full capture
## would take, and the brushes a restore keeps are the ones a full comparison
## would keep. The cache drops a whole brush, never a field, so a field added
## to the record later needs nothing here.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const UndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const ChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")

const STEPS := 120
const SEEDS := [1866, 7, 42]
const DEPTH := 32


## An undo history with a pointer, as the editor's is: an undo walks back one
## step and a redo forward one, and a new step drops the redos.
class History:
	extends RefCounted

	var steps: Array = []
	var at := -1
	var _open: Dictionary = {}

	func create_action(
		name: String, _merge_mode: int = 0, _context = null, _backward: bool = false
	) -> void:
		_open = {"name": name, "do": [], "undo": []}

	func add_do_method(
		target, method: StringName, a = null, b = null, c = null, d = null, e = null
	):
		_open["do"].append([target, str(method), _args([a, b, c, d, e])])

	func add_undo_method(
		target, method: StringName, a = null, b = null, c = null, d = null, e = null
	):
		_open["undo"].append([target, str(method), _args([a, b, c, d, e])])

	func commit_action(execute: bool = true) -> void:
		if execute:
			for call in _open["do"]:
				call[0].callv(call[1], call[2])
		steps.resize(at + 1)
		steps.append(_open)
		at = steps.size() - 1
		_open = {}

	func undo() -> bool:
		if at < 0:
			return false
		for call in steps[at]["undo"]:
			call[0].callv(call[1], call[2])
		at -= 1
		return true

	func redo() -> bool:
		if at + 1 >= steps.size():
			return false
		at += 1
		for call in steps[at]["do"]:
			call[0].callv(call[1], call[2])
		return true

	func _args(values: Array) -> Array:
		var out: Array = []
		for value in values:
			if value == null:
				break
			out.append(value)
		return out


var level: LevelRoot


func before_each() -> void:
	level = LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)


func after_each() -> void:
	level = null


func _place(at: Vector3, shape := 0) -> Node:
	return level.create_brush_from_info(
		{"shape": shape, "size": Vector3(2, 2, 2), "center": at, "sides": 8}
	)


## Every brush whose kept record is not the record a full capture takes now.
func _stale() -> Array:
	var out: Array = []
	for brush in level._iter_managed_brush_nodes():
		var kept: Dictionary = level.brush_system.get_brush_info_from_node(brush, true)
		var full: Dictionary = level.brush_system.get_brush_info_from_node(brush)
		if not kept.recursive_equal(full, DEPTH):
			out.append(str(brush.brush_id))
	return out


## The brushes a restore of `records` keeps, and the ones a full comparison of
## each brush with its record would keep.
func _kept_both_ways(records: Array) -> Array:
	var cached: Array = level.brush_system.reusable_draft_brushes(records).keys()
	var full: Array = []
	var wanted := {}
	for record in records:
		wanted[str(record["brush_id"])] = record
	for brush in level.draft_brushes_node.get_children():
		var brush_id := str(brush.get("brush_id"))
		if not wanted.has(brush_id) or full.has(brush_id):
			continue
		var live: Dictionary = level.brush_system.get_brush_info_from_node(brush)
		if live.recursive_equal(wanted[brush_id], DEPTH):
			full.append(brush_id)
	cached.sort()
	full.sort()
	return [cached, full]


func _some_brush(rng: RandomNumberGenerator) -> DraftBrush:
	var brushes: Array = level.draft_brushes_node.get_children().filter(
		func(node): return node is DraftBrush
	)
	if brushes.is_empty():
		return null
	return brushes[rng.randi_range(0, brushes.size() - 1)]


func test_kept_records_match_a_full_capture_through_random_edits(seed = use_parameters(SEEDS)):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var history := History.new()
	var tracker := ChangeTracker.new()
	for i in 6:
		_place(Vector3(i * 4.0, 1.0, 0.0), i % 3)
	await get_tree().process_frame
	tracker.prime(level)
	var old_records: Array = level.capture_undo_state()["brushes"]
	var problems: Array = []
	for step in STEPS:
		var op := rng.randi_range(0, 9)
		var brush := _some_brush(rng)
		var said := "op %d" % op
		match op:
			0:
				said = "place"
				var info := {
					"shape": rng.randi_range(0, 2),
					"size": Vector3.ONE * rng.randf_range(1.0, 3.0),
					"center": Vector3(rng.randf_range(-20, 20), 1.0, rng.randf_range(-20, 20)),
				}
				UndoHelper.commit(history, level, "Place Brush", "create_brush_from_info", [info])
			1:
				if brush:
					said = "delete %s" % brush.brush_id
					UndoHelper.commit(
						history, level, "Delete", "delete_brush_by_id", [str(brush.brush_id)]
					)
			2:
				if brush:
					said = "nudge %s" % brush.brush_id
					var id := str(brush.brush_id)
					UndoHelper.commit(
						history,
						level,
						"Nudge",
						"nudge_managed_nodes",
						[[id], [], Vector3(rng.randf_range(-1, 1), 0, 0)],
						false,
						Callable(),
						"",
						true,
						[id],
						[]
					)
			3:
				if brush:
					said = "resize %s" % brush.brush_id
					UndoHelper.commit(
						history,
						level,
						"Resize",
						"set_brush_transform_by_id",
						[
							str(brush.brush_id),
							Vector3.ONE * rng.randf_range(1.0, 4.0),
							brush.global_position
						]
					)
			4:
				if brush and not brush.faces.is_empty():
					said = "uv %s" % brush.brush_id
					UndoHelper.commit(
						history,
						level,
						"Face UV",
						"set_face_uv_params",
						[
							str(brush.brush_id),
							rng.randi_range(0, brush.faces.size() - 1),
							Vector2.ONE * rng.randf_range(0.5, 2.0),
							Vector2(rng.randf(), rng.randf()),
							rng.randf_range(0.0, 90.0)
						]
					)
			5:
				# As Godot's Inspector does it: a face changed with no command and
				# no tag, then the check the plugin runs after the step.
				if brush and not brush.faces.is_empty():
					said = "inspector %s" % brush.brush_id
					var face: FaceData = brush.faces[rng.randi_range(0, brush.faces.size() - 1)]
					face.uv_rotation = rng.randf_range(0.0, 180.0)
					tracker.reconcile_step(level, [brush])
			6:
				said = "undo"
				history.undo()
			7:
				said = "redo"
				history.redo()
			8:
				# As Godot's gizmo does it: the brush moved, then the check.
				if brush:
					said = "gizmo %s" % brush.brush_id
					brush.global_position += Vector3(0, rng.randf_range(-1, 1), 0)
					tracker.reconcile_step(level, [brush])
			9:
				said = "whole level restore"
				level.restore_state(level.capture_undo_state())
		await get_tree().process_frame
		tracker.reconcile_step(level, [])
		var stale := _stale()
		if not stale.is_empty():
			problems.append("step %d, %s: stale %s" % [step, said, stale])
		var kept := _kept_both_ways(old_records)
		if kept[0] != kept[1]:
			problems.append("step %d, %s: kept %s, full %s" % [step, said, kept[0], kept[1]])
		if step % 10 == 0:
			old_records = level.capture_undo_state()["brushes"]
	for problem in problems.slice(0, 10):
		gut.p(problem)
	assert_eq(problems.size(), 0, "seed %d: %s" % [seed, problems.slice(0, 3)])


## A change Godot's own Inspector makes reaches the next step's record, through
## the check the plugin runs after each step.
func test_an_inspector_change_is_in_the_next_record():
	var brush: DraftBrush = _place(Vector3.ZERO)
	await get_tree().process_frame
	var tracker := ChangeTracker.new()
	tracker.prime(level)
	var before: Array = level.capture_undo_state()["brushes"]
	assert_eq(level.capture_undo_state()["brushes"][0]["faces"], before[0]["faces"])
	brush.faces[0].material_idx = 3
	tracker.reconcile_step(level, [brush])
	var after: Dictionary = level.capture_undo_state()["brushes"][0]
	assert_eq(int(after["faces"][0]["material_idx"]), 3, "the next record has it")


## Records taken while nothing changed share one faces record, read-only, so a
## restore keeps each brush without comparing it face by face.
func test_records_share_a_read_only_faces_record():
	_place(Vector3.ZERO)
	await get_tree().process_frame
	var one: Dictionary = level.capture_undo_state()["brushes"][0]
	var two: Dictionary = level.capture_undo_state()["brushes"][0]
	assert_true(is_same(one["faces"], two["faces"]), "one faces record, shared")
	assert_true((one["faces"] as Array).is_read_only(), "and read-only")
	assert_true((one["faces"][0] as Dictionary).is_read_only(), "face by face")
	var mine: Dictionary = level.get_brush_info_from_node(level.draft_brushes_node.get_child(0))
	assert_false((mine["faces"] as Array).is_read_only(), "a record asked for alone is its own")
	var saved: Dictionary = level.capture_state(false)["brushes"][0]
	assert_false((saved["faces"] as Array).is_read_only(), "and so is the record a save takes")


## A save, a compare and every reader but an undo step take the faces as they
## are, so a face a script changed with no tag is never written from a kept
## record.
func test_a_face_changed_with_no_tag_still_reaches_a_save():
	var brush: DraftBrush = _place(Vector3.ZERO)
	await get_tree().process_frame
	level.capture_undo_state()
	brush.faces[0].uv_rotation = 30.0
	var saved: Dictionary = level.state_system.capture_hflevel_payload()
	var face: Dictionary = saved["state"]["brushes"][0]["faces"][0]
	assert_almost_eq(float(face["uv_rotation"]), 30.0, 0.001, "the save has it")


## The check after the undo of a placement looks at the brush the step named,
## not at every brush (#1866).
func test_the_check_after_undoing_a_placement_is_not_a_full_walk():
	for i in 20:
		_place(Vector3(i * 4.0, 1.0, 0.0))
	await get_tree().process_frame
	var history := History.new()
	var tracker := ChangeTracker.new()
	tracker.prime(level)
	var version := 0
	tracker.note_step(version, false)
	tracker.reconcile_step(level, [])
	var info := {"shape": 0, "size": Vector3.ONE, "center": Vector3(0, 10, 0)}
	UndoHelper.commit(history, level, "Place Brush", "create_brush_from_info", [info])
	version += 1
	tracker.note_step(version, false, "Place Brush")
	tracker.reconcile_step(level, [])
	history.undo()
	version -= 1
	tracker.note_step(version, true)
	tracker.reconcile_step(level, [])
	assert_eq(level.get_live_brush_count(), 20, "the placement is undone")
	assert_true(tracker.owes_full_walk(), "the check looked at some brushes, not every one")
