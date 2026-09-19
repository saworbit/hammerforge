extends GutTest

## The undo step that records the brushes an action touches instead of the level.
##
## `capture_state()` walks every brush and every registry, so at 900 brushes one
## undo step was 39 ms to take and 2.2 MB to hold, on an action that moved three
## of them (#737). `capture_brush_scope()` records the three.
##
## Two things have to be true for that to be an undo rather than a speedup.
##
## A scoped step has to leave the level exactly where the whole-level step would.
## That is `_assert_scoped_undo_round_trips()` below: capture the whole level, run
## the command, put only the scope back, capture the whole level, and compare the
## two dictionaries.
##
## And the commands that claim a scope have to deserve it. A scope is a claim that
## the command changed those brushes and nothing else, and nothing in a record can
## check it, so the last sections here run each command and assert that nothing
## outside its scope moved.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

## Matches HFBrushSystem._RECORD_COMPARE_DEPTH. A state is a handful of values and
## arrays of face dictionaries, so this is far past anything real.
const COMPARE_DEPTH := 32


## Enough of an `EditorUndoRedoManager` to see what an action registered. One
## cannot be constructed outside the editor, and Godot 4.7 documents MERGE_ENDS
## as keeping the first action's undo operations and the last action's do
## operations, which is the one rule a collated run turns on.
class FakeUndoRedo:
	extends RefCounted

	var entries: Array = []
	var _open: Dictionary = {}
	var _merging := false

	func create_action(
		name: String, merge_mode: int = 0, _context = null, _backward: bool = false
	) -> void:
		_merging = merge_mode == MERGE_ENDS and not entries.is_empty()
		_open = {"name": name, "do": [], "undo": []}

	func add_do_method(target, method: StringName, a = null) -> void:
		_open["do"].append({"target": target, "method": str(method), "arg": a})

	func add_undo_method(target, method: StringName, a = null) -> void:
		_open["undo"].append({"target": target, "method": str(method), "arg": a})

	func commit_action(execute: bool = true) -> void:
		if execute:
			for call_info in _open["do"]:
				_invoke(call_info)
		if _merging:
			entries[-1]["do"] = _open["do"]
		else:
			entries.append(_open)
		_open = {}

	func undo() -> void:
		for call_info in entries[-1]["undo"]:
			_invoke(call_info)

	func redo() -> void:
		for call_info in entries[-1]["do"]:
			_invoke(call_info)

	func _invoke(call_info: Dictionary) -> void:
		call_info["target"].call(call_info["method"], call_info["arg"])


const MERGE_DISABLE := 0
const MERGE_ENDS := 1

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _make_brush(position: Vector3, size: Vector3 = Vector3(32, 32, 32)) -> DraftBrush:
	var brush = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, position),
			}
		)
	)
	return brush as DraftBrush


func _brush_id(brush: DraftBrush) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))


## An entity in the level, and the path the transform commands name it by.
##
## `light_point` is a real class out of `entities.json`, so the record carries
## the properties its schema fills in rather than an empty dictionary. `angle` is
## put there by hand because rotate and flip write it, no light declares one, and
## it is the one field of an entity record that is not the transform.
func _make_entity(position: Vector3, entity_name: String = "TestLight") -> DraftEntity:
	var entity := DraftEntity.new()
	entity.name = entity_name
	entity.entity_type = "light_point"
	root.entity_system.add_entity(entity)
	entity.global_position = position
	entity.entity_data["angle"] = 0.0
	return entity


func _entity_path(entity: DraftEntity) -> NodePath:
	return root.get_path_to(entity)


func _brush_at_index(index: int) -> DraftBrush:
	return root.draft_brushes_node.get_child(index) as DraftBrush


## `==` on an Array of face dictionaries does not go down into them, and only
## Dictionary has `recursive_equal`, so anything else is boxed into one.
func _same_value(a, b) -> bool:
	return {"v": a}.recursive_equal({"v": b}, COMPARE_DEPTH)


## Which top-level keys of two level states disagree, sorted. Named rather than
## counted, so a failure says what came back wrong instead of that something did.
func _differing_keys(before: Dictionary, after: Dictionary) -> Array:
	var changed: Array = []
	for key in before:
		if not after.has(key):
			changed.append(key)
		elif not _same_value(before[key], after[key]):
			changed.append(key)
	for key in after:
		if not before.has(key):
			changed.append(key)
	changed.sort()
	return changed


# ===========================================================================
# What a scope records
# ===========================================================================


func test_a_scope_records_only_the_brushes_it_names():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	_make_brush(Vector3(128, 0, 0))
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	assert_eq(scope.get("brushes", []).size(), 1, "one id must record one brush")
	assert_eq(
		str(scope["brushes"][0].get("brush_id", "")), _brush_id(a), "and it must be that brush"
	)


func test_a_scope_is_smaller_than_the_level_it_came_from():
	var a := _make_brush(Vector3.ZERO)
	for i in 20:
		_make_brush(Vector3(64 * (i + 1), 0, 0))
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	var whole: Dictionary = root.capture_state()
	assert_eq(whole.get("brushes", []).size(), 21, "the whole level records every brush")
	assert_eq(scope.get("brushes", []).size(), 1, "the scope records the one that moved")


func test_a_scope_records_where_each_brush_sits():
	_make_brush(Vector3.ZERO)
	var b := _make_brush(Vector3(64, 0, 0))
	_make_brush(Vector3(128, 0, 0))
	var scope: Dictionary = root.capture_brush_scope([_brush_id(b)])
	assert_eq(int(scope["order"][_brush_id(b)]), 1, "the middle brush is at index 1")


func test_an_id_that_does_not_resolve_is_not_a_scope():
	_make_brush(Vector3.ZERO)
	assert_true(
		root.capture_brush_scope(["no_such_brush"]).is_empty(),
		"an unknown id has to fall back to the whole snapshot, not record nothing"
	)


func test_a_pending_cut_is_not_a_scope():
	var cut = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(32, 32, 32),
				"transform": Transform3D(Basis.IDENTITY, Vector3.ZERO),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"pending": true,
			}
		)
	)
	var cut_id := str(root.get_brush_info_from_node(cut).get("brush_id", ""))
	assert_true(
		root.capture_brush_scope([cut_id]).is_empty(),
		"a brush outside the draft container has no index to be put back at"
	)


func test_no_ids_is_not_a_scope():
	_make_brush(Vector3.ZERO)
	assert_true(root.capture_brush_scope([]).is_empty(), "nothing named is not a scope")


# ===========================================================================
# What a scoped restore does
# ===========================================================================


func test_a_scoped_restore_puts_a_moved_brush_back():
	var a := _make_brush(Vector3.ZERO)
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	root.nudge_brushes_by_id([_brush_id(a)], Vector3(64, 0, 0))
	assert_eq(a.global_position, Vector3(64, 0, 0), "the nudge has to have happened")
	root.restore_brush_scope(scope)
	assert_eq(_brush_at_index(0).global_position, Vector3.ZERO, "and the restore has to undo it")


func test_a_scoped_restore_leaves_the_brush_it_only_moves_alive():
	var a := _make_brush(Vector3.ZERO)
	var instance_id := a.get_instance_id()
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	root.nudge_brushes_by_id([_brush_id(a)], Vector3(64, 0, 0))
	root.restore_brush_scope(scope)
	assert_eq(
		_brush_at_index(0).get_instance_id(),
		instance_id,
		"a transform is written onto the node, so nothing holding it loses it"
	)


func test_a_record_that_changes_more_than_a_transform_rebuilds():
	var a := _make_brush(Vector3.ZERO, Vector3(32, 32, 32))
	var brush_id := _brush_id(a)
	var scope: Dictionary = root.capture_brush_scope([brush_id])
	var instance_id := a.get_instance_id()
	root.set_brush_transform_by_id(brush_id, Vector3(96, 32, 32), Vector3.ZERO)
	assert_eq(_brush_at_index(0).size, Vector3(96, 32, 32), "the resize has to have happened")
	root.restore_brush_scope(scope)
	assert_eq(_brush_at_index(0).size, Vector3(32, 32, 32), "the size has to come back")
	assert_ne(
		_brush_at_index(0).get_instance_id(),
		instance_id,
		"a size is decided when the primitive is built, so that record rebuilds"
	)


func test_a_rebuilt_brush_goes_back_at_its_own_index():
	_make_brush(Vector3.ZERO)
	var b := _make_brush(Vector3(64, 0, 0))
	_make_brush(Vector3(128, 0, 0))
	var brush_id := _brush_id(b)
	var scope: Dictionary = root.capture_brush_scope([brush_id])
	root.set_brush_transform_by_id(brush_id, Vector3(96, 32, 32), Vector3(64, 0, 0))
	root.restore_brush_scope(scope)
	assert_eq(root.draft_brushes_node.get_child_count(), 3, "still three brushes")
	assert_eq(
		_brush_id(_brush_at_index(1)),
		brush_id,
		"a rebuilt brush is added at the end, so the order has to be put back (#660)"
	)


func test_a_scoped_restore_that_rebuilds_keeps_the_connections_aimed_at_it():
	var target := _make_brush(Vector3.ZERO)
	target.name = "TargetDoor"
	var source := _make_brush(Vector3(64, 0, 0))
	source.set_meta("entity_io_outputs", [{"output": "OnTrigger", "target_name": "TargetDoor"}])
	var brush_id := _brush_id(target)
	var scope: Dictionary = root.capture_brush_scope([brush_id])
	root.set_brush_transform_by_id(brush_id, Vector3(96, 32, 32), Vector3.ZERO)
	root.restore_brush_scope(scope)
	assert_eq(
		(source.get_meta("entity_io_outputs", []) as Array).size(),
		1,
		"a restore is not a delete, so it must not strip what pointed at the brush"
	)


func test_a_scoped_restore_of_a_brush_that_matches_changes_nothing():
	var a := _make_brush(Vector3.ZERO)
	var instance_id := a.get_instance_id()
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	root.restore_brush_scope(scope)
	assert_eq(_brush_at_index(0).get_instance_id(), instance_id, "no work for no change")


func test_an_unreadable_record_costs_that_record_and_not_the_step():
	var a := _make_brush(Vector3.ZERO)
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	(scope["brushes"] as Array).push_front("not a record")
	root.nudge_brushes_by_id([_brush_id(a)], Vector3(64, 0, 0))
	root.restore_brush_scope(scope)
	assert_eq(_brush_at_index(0).global_position, Vector3.ZERO, "the good record still applies")


# ===========================================================================
# A scoped undo has to land where the whole-level undo would
# ===========================================================================


## The claim the whole change rests on, made against a real level: take the whole
## state, run the command, put only the scope back, and the whole state has to be
## the dictionary it was. A scoped step restores nothing outside its scope, so
## anything the command moved out there shows up here as a difference.
func _assert_scoped_undo_round_trips(
	brush_ids: Array, method_name: String, args: Array, entity_paths: Array = []
) -> void:
	var before: Dictionary = root.capture_state()
	var scope: Dictionary = root.capture_brush_scope(brush_ids, entity_paths)
	assert_false(scope.is_empty(), "%s must be scopeable in this fixture" % method_name)
	root.callv(method_name, args)
	var moved: Dictionary = root.capture_state()
	assert_false(
		moved.recursive_equal(before, COMPARE_DEPTH), "%s must change something" % method_name
	)
	root.restore_brush_scope(scope)
	var after: Dictionary = root.capture_state()
	assert_eq(
		_differing_keys(before, after),
		[],
		"undoing %s through its scope must leave the level as it was" % method_name
	)


func test_nudge_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	_make_brush(Vector3(128, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "nudge_managed_nodes", [ids, [], Vector3(16, 0, 0)])


func test_rotate_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "rotate_managed_nodes", [ids, [], 1, 45.0, Vector3.ZERO])


func test_flip_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3(32, 0, 0))
	_make_brush(Vector3(64, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "flip_managed_nodes", [ids, [], 0, Vector3.ZERO])


func test_reset_rotation_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	root.rotate_managed_nodes([_brush_id(a)], [], 1, 30.0, Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "reset_managed_rotation", [ids])


## The other half of the restore. Every round trip above takes the in-place path,
## because a transform is one of the fields a live brush can be handed. A resize
## is not, so this one goes through `create_brush_from_info()` -- which frees a
## node and adds a new one, and so is where the brush order and the id counter
## can come back wrong (#660).
func test_a_scoped_undo_that_rebuilds_matches_the_level_before_it():
	_make_brush(Vector3.ZERO)
	var b := _make_brush(Vector3(64, 0, 0))
	_make_brush(Vector3(128, 0, 0))
	var brush_id := _brush_id(b)
	_assert_scoped_undo_round_trips(
		[brush_id], "set_brush_transform_by_id", [brush_id, Vector3(96, 32, 32), Vector3(64, 0, 0)]
	)


func test_a_scoped_undo_of_several_brushes_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	var b := _make_brush(Vector3(64, 0, 0))
	_make_brush(Vector3(128, 0, 0))
	var d := _make_brush(Vector3(192, 0, 0))
	var ids := [_brush_id(a), _brush_id(b), _brush_id(d)]
	_assert_scoped_undo_round_trips(ids, "nudge_managed_nodes", [ids, [], Vector3(0, 16, 0)])


## Every displacement command, through the same round trip the transform commands
## take. `create_displacement` is the interesting one: it adds face data, so the
## restore goes through the rebuild path rather than writing a transform onto a
## live node.
func test_the_displacement_commands_scoped_undo_matches_the_level_before_it():
	for case in [
		["create_displacement", 3],
		["set_displacement_power", 5],
		["set_displacement_elevation", 8.0],
		["smooth_displacement", 0.5],
		["noise_displacement", 1.0],
		["set_displacement_sew_group", 2],
		["destroy_displacement", null],
	]:
		var a := _make_brush(Vector3.ZERO)
		_make_brush(Vector3(96, 0, 0))
		var brush_id := _brush_id(a)
		var method_name := str(case[0])
		if method_name != "create_displacement":
			root.create_displacement(brush_id, 0, 3)
			# Sculpted, so smooth has something to flatten and the round trip is
			# the restore being tested rather than a command that did nothing.
			root.displacement_system.paint(brush_id, 0, _face_centre(a, 0), 24.0, 6.0, 0)
		var args: Array = [brush_id, 0]
		if case[1] != null:
			args.append(case[1])
		_assert_scoped_undo_round_trips([brush_id], method_name, args)
		root.clear_brushes()


## Painting a brush that had no material. The record a scope takes only carries
## a `material` key when there is one, so undoing this paint rests on the key
## being absent rather than on it holding null.
func test_painting_a_material_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var brush_id := _brush_id(a)
	_assert_scoped_undo_round_trips(
		[brush_id], "apply_material_to_brush_by_id", [brush_id, StandardMaterial3D.new()]
	)


## The sculpt drag, which is the one a mapper holds down. Not through
## `_assert_scoped_undo_round_trips()` because the stroke is a call on the
## displacement system rather than a method on the root.
func test_a_displacement_sculpt_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var brush_id := _brush_id(a)
	root.create_displacement(brush_id, 0, 3)
	var before: Dictionary = root.capture_state()
	var scope: Dictionary = root.capture_brush_scope([brush_id])
	assert_false(scope.is_empty(), "a sculpted brush has to be scopeable")
	root.displacement_system.paint(brush_id, 0, _face_centre(a, 0), 16.0, 4.0, 0)
	root.restore_brush_scope(scope)
	assert_eq(
		_differing_keys(before, root.capture_state()),
		[],
		"undoing a stroke through its scope must leave the level as it was"
	)


# ===========================================================================
# An action registered after the work was already done
# ===========================================================================


## `commit_completed()` is the half of the helper for work the caller has run
## itself, and it is what `dock._try_undoable_action()` and the sculpt drag reach
## for: both need the command's return value, which `commit()` throws away.
func test_commit_completed_registers_the_scoped_restore_at_both_ends():
	var a := _make_brush(Vector3.ZERO)
	var ids := [_brush_id(a)]
	var undo_redo := FakeUndoRedo.new()
	var before: Dictionary = root.capture_brush_scope(ids)
	root.create_displacement(ids[0], 0, 3)
	HFUndoHelper.commit_completed(undo_redo, root, "Create Displacement", before, Callable(), ids)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["do"][0]["method"], "restore_brush_scope", "redo restores the scope")
	assert_eq(entry["undo"][0]["method"], "restore_brush_scope", "and so does undo")
	undo_redo.undo()
	assert_eq(_brush_at_index(0).faces[0].displacement, null, "and undo takes the sculpt off")
	undo_redo.redo()
	assert_ne(_brush_at_index(0).faces[0].displacement, null, "and redo puts it back")


## A scope is a claim, and nothing in a record can check it. When the command
## turns out to have changed which brushes exist, the after-scope comes back
## empty and the do operation falls back to the whole level rather than shipping
## a half redo. Same degradation `register_action()` already makes.
func test_commit_completed_falls_back_when_the_scope_did_not_survive():
	var a := _make_brush(Vector3.ZERO)
	var ids := [_brush_id(a)]
	var undo_redo := FakeUndoRedo.new()
	var before: Dictionary = root.capture_brush_scope(ids)
	root.clear_brushes()
	HFUndoHelper.commit_completed(undo_redo, root, "Something Bigger", before, Callable(), ids)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["do"][0]["method"], "restore_state", "redo has to take the whole level")


func test_commit_completed_without_a_scope_is_unchanged():
	var a := _make_brush(Vector3.ZERO)
	var undo_redo := FakeUndoRedo.new()
	var before: Dictionary = root.capture_state()
	root.create_displacement(_brush_id(a), 0, 3)
	HFUndoHelper.commit_completed(undo_redo, root, "Create Displacement", before)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["do"][0]["method"], "restore_state", "redo restores the level")
	assert_eq(entry["undo"][0]["method"], "restore_state", "and so does undo")


# ===========================================================================
# The commands that claim a scope have to deserve it
# ===========================================================================


## Run the command and report every top-level key of the level state it changed.
func _keys_changed_by(method_name: String, args: Array) -> Array:
	var before: Dictionary = root.capture_state()
	root.callv(method_name, args)
	return _differing_keys(before, root.capture_state())


## `plugin_edit_actions` hands these four commands' selections to
## `HFUndoHelper.commit()` as a claim that the command touches those objects and
## nothing else. This is what holds them to it. A command that grows a registry
## write or a palette write fails here, and the answer is to stop scoping it
## rather than to widen the scope.
func test_the_scoped_commands_change_the_brushes_and_nothing_else():
	for method_name in [
		"nudge_managed_nodes",
		"rotate_managed_nodes",
		"flip_managed_nodes",
		"reset_managed_rotation",
	]:
		var a := _make_brush(Vector3(32, 0, 0))
		_make_brush(Vector3(96, 0, 0))
		var ids := [_brush_id(a)]
		var args: Array = []
		match method_name:
			"nudge_managed_nodes":
				args = [ids, [], Vector3(16, 0, 0)]
			"rotate_managed_nodes":
				args = [ids, [], 1, 45.0, Vector3.ZERO]
			"flip_managed_nodes":
				args = [ids, [], 0, Vector3.ZERO]
			"reset_managed_rotation":
				root.rotate_managed_nodes(ids, [], 1, 30.0, Vector3.ZERO)
				args = [ids]
		assert_eq(
			_keys_changed_by(method_name, args),
			["brushes"],
			"%s claims a brush scope, so brushes is the only key it may change" % method_name
		)
		root.clear_brushes()


## The displacement commands. Every one of them edits one face of one brush: the
## dock buttons through `dock._try_undoable_action()`, the elevation spin through
## `HFUndoHelper.commit()`, and the sculpt drag through `commit_completed()`
## (#761). They were the biggest group still recording the whole level, and the
## sculpt drag is held down, so it was taking a 2.2 MB snapshot per stroke.
##
## Same rule as the transform commands above: a command that grows a registry
## write or a palette write fails here, and the answer is to stop scoping it.
func test_the_displacement_commands_change_the_brushes_and_nothing_else():
	for method_name in [
		"create_displacement",
		"set_displacement_power",
		"set_displacement_elevation",
		"smooth_displacement",
		"noise_displacement",
		"set_displacement_sew_group",
		"destroy_displacement",
	]:
		var a := _make_brush(Vector3.ZERO)
		_make_brush(Vector3(96, 0, 0))
		var brush_id := _brush_id(a)
		var args: Array = [brush_id, 0]
		if method_name != "create_displacement":
			assert_true(
				root.create_displacement(brush_id, 0, 3),
				"%s needs a displacement to act on" % method_name
			)
			# Smooth and noise are no-ops on a grid that is still flat, and a
			# command that changes nothing proves nothing here.
			root.displacement_system.paint(brush_id, 0, _face_centre(a, 0), 24.0, 6.0, 0)
		match method_name:
			"create_displacement":
				args.append(3)
			"set_displacement_power":
				args.append(5)
			"set_displacement_elevation":
				args.append(8.0)
			"smooth_displacement":
				args.append(0.5)
			"noise_displacement":
				args.append(1.0)
			"set_displacement_sew_group":
				args.append(2)
		assert_eq(
			_keys_changed_by(method_name, args),
			["brushes"],
			"%s claims a brush scope, so brushes is the only key it may change" % method_name
		)
		root.clear_brushes()


## Where a stroke lands: the middle of the named face, in world space, which is
## what `do_displacement_stroke()` raycasts for.
func _face_centre(brush: DraftBrush, face_index: int) -> Vector3:
	var face = brush.faces[face_index]
	var centre := Vector3.ZERO
	for local_vertex in face.local_verts:
		centre += local_vertex
	centre /= float(face.local_verts.size())
	return brush.global_transform * centre


## The sculpt drag itself, which is the stroke rather than a button. It writes
## through `HFDisplacementSystem.paint()`, and the brush it is sculpting is the
## one the plugin already holds in `_disp_paint_brush_id`.
func test_a_displacement_sculpt_changes_the_brushes_and_nothing_else():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var brush_id := _brush_id(a)
	assert_true(root.create_displacement(brush_id, 0, 3), "the face has to be displaced first")
	var before: Dictionary = root.capture_state()
	assert_true(
		root.displacement_system.paint(brush_id, 0, _face_centre(a, 0), 16.0, 4.0, 0),
		"the stroke has to land on the face"
	)
	assert_eq(
		_differing_keys(before, root.capture_state()),
		["brushes"],
		"a sculpt stroke moves one brush's face and nothing else"
	)


## Why the two states cannot be swapped for each other.
##
## A stroke's pre-state is a scope now, and Escape during a sculpt throws the
## stroke away by restoring it. `restore_state()` would take that scope for a
## whole level -- one with no entities, no materials and no visgroups in it,
## because a scope holds two keys and a level state holds twenty-five -- and
## clear all of them. Nothing in the dictionary says which kind it is, so the
## stroke carries the ids beside it and the cancel picks the matching restore.
func test_a_scope_is_not_a_level_state_and_restore_state_cannot_read_one():
	var a := _make_brush(Vector3.ZERO)
	root.entity_system.create_entity_from_map({"classname": "info_player_start"})
	var entities_before: int = (root.capture_state()["entities"] as Array).size()
	assert_gt(entities_before, 0, "the fixture needs something outside the brushes to lose")
	root.restore_state(root.capture_brush_scope([_brush_id(a)]))
	assert_eq(
		(root.capture_state()["entities"] as Array).size(),
		0,
		"a scope read as a level clears what it never recorded, which is why it must not be"
	)


## And the other half of that, for an entity scope.
##
## An entity scope keys its records by node path, so `entities` in one is a set
## where `entities` in a level state is a list, and that is a shape
## `HFValidation.level_state_problem()` refuses outright. So an entity scope read
## as a level clears nothing, where the brush scope above clears everything.
##
## Pinned because it is the only thing standing between a hand-rolled restore of
## an entity scope and a wiped level, and a record shape that made the two look
## alike would take it away with nothing said.
func test_an_entity_scope_is_refused_by_restore_state_rather_than_read_as_a_level():
	_make_brush(Vector3.ZERO)
	var light := _make_entity(Vector3(32, 0, 0))
	var scope: Dictionary = root.capture_brush_scope([], [_entity_path(light)])
	var before: Dictionary = root.capture_state()
	root.restore_state(scope)
	assert_eq(
		_differing_keys(before, root.capture_state()),
		[],
		"an entity scope is not a level state and restore_state has to refuse it"
	)


## The boundary of the claim. Sewing walks every displacement in the level to
## match its boundary vertices to its neighbours', so it changes brushes the
## caller never named and must keep the whole snapshot it has always taken.
func test_sewing_is_not_a_single_brush_claim():
	# Coincident, so the two faces have the same boundary vertices and the sew
	# has something to match. `sew_all()` pairs faces by sew group and not by
	# where they are, which is the whole reason it cannot be scoped to a brush.
	var a := _make_brush(Vector3.ZERO, Vector3(32, 32, 32))
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32))
	assert_true(root.create_displacement(_brush_id(a), 0, 3), "first face displaced")
	assert_true(root.create_displacement(_brush_id(b), 0, 3), "second face displaced")
	root.set_displacement_sew_group(_brush_id(a), 0, 0)
	root.set_displacement_sew_group(_brush_id(b), 0, 0)
	# A boundary vertex of one pulled under the half unit `sew_all()` matches
	# within, so the pair is near enough to find and far enough apart to move.
	# Both need an elevation: a sewn distance is divided by it, and a face with
	# none takes a zero it already had.
	root.set_displacement_elevation(_brush_id(a), 0, 1.0)
	root.set_displacement_elevation(_brush_id(b), 0, 1.0)
	a.faces[0].displacement.set_distance(0, 0, 0.2)
	var before: Dictionary = root.capture_state()
	assert_gt(root.sew_all_displacements(), 0, "the fixture has to actually sew something")
	var after: Dictionary = root.capture_state()
	var moved: Array = []
	for i in (before["brushes"] as Array).size():
		var was: Dictionary = before["brushes"][i]
		if not was.recursive_equal(after["brushes"][i], COMPARE_DEPTH):
			moved.append(str(was.get("brush_id", "")))
	assert_true(
		moved.has(_brush_id(b)),
		"sew moved a brush the caller never named, so no call site may scope it to one"
	)


## Painting a material. `plugin_material_commands.paint_brush_with_undo()` already
## went through the helper and passed no scope, and the open question was the
## palette: if painting with a material the palette does not hold wrote a slot,
## the claim would be false. It does not. The paint sets `material_override` on
## the node, and `materials` is untouched by a material the palette has never
## seen.
func test_painting_a_material_changes_the_brushes_and_nothing_else():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var unseen := StandardMaterial3D.new()
	assert_eq(
		_keys_changed_by("apply_material_to_brush_by_id", [_brush_id(a), unseen]),
		["brushes"],
		"a material the palette does not hold must not write the palette"
	)


func test_a_scoped_command_leaves_the_brushes_outside_its_scope_alone():
	var a := _make_brush(Vector3.ZERO)
	var b := _make_brush(Vector3(64, 0, 0))
	var before: Dictionary = root.capture_state()
	root.nudge_managed_nodes([_brush_id(a)], [], Vector3(16, 0, 0))
	var after: Dictionary = root.capture_state()
	var moved: Array = []
	for i in (before["brushes"] as Array).size():
		var was: Dictionary = before["brushes"][i]
		if not was.recursive_equal(after["brushes"][i], COMPARE_DEPTH):
			moved.append(str(was.get("brush_id", "")))
	assert_eq(moved, [_brush_id(a)], "only the scoped brush's record may differ")
	assert_eq(b.global_position, Vector3(64, 0, 0), "the other brush has not moved")


# ===========================================================================
# A collated run of scoped steps
# ===========================================================================


## The question the issue asked about collation: a run of nudges keeps the first
## pre-action state so undo jumps all the way back, and MERGE_ENDS keeps the last
## do so redo replays the whole run. A scope has to compose the same way. It can,
## because the collation tag names the brushes, so every press in a run scopes the
## same ids as the first.
func test_a_collated_run_of_scoped_steps_undoes_to_the_start_and_redoes_the_whole_run():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(256, 0, 0))
	var ids := [_brush_id(a)]
	var undo_redo := FakeUndoRedo.new()
	var first_scope: Dictionary = root.capture_brush_scope(ids)
	for press in 3:
		HFUndoHelper.register_action(
			undo_redo,
			root,
			"Nudge",
			MERGE_DISABLE if press == 0 else MERGE_ENDS,
			"nudge_managed_nodes",
			[ids, [], Vector3(16, 0, 0)],
			first_scope,
			false,
			true,
			ids
		)
	assert_eq(undo_redo.entries.size(), 1, "three presses in a run are one undo entry")
	assert_eq(_brush_at_index(0).global_position, Vector3(48, 0, 0), "and all three happened")
	undo_redo.undo()
	assert_eq(
		_brush_at_index(0).global_position,
		Vector3.ZERO,
		"undo has to jump back past the whole run, not one press of it"
	)
	assert_eq(
		root.draft_brushes_node.get_child_count(),
		2,
		"and it must not take the brush outside the scope with it"
	)
	undo_redo.redo()
	assert_eq(
		_brush_at_index(0).global_position,
		Vector3(48, 0, 0),
		"and redo has to replay all of it, not the last press"
	)
	assert_eq(root.draft_brushes_node.get_child_count(), 2, "still both brushes")


func test_a_scoped_run_registers_the_scoped_restore_at_both_ends():
	var a := _make_brush(Vector3.ZERO)
	var ids := [_brush_id(a)]
	var undo_redo := FakeUndoRedo.new()
	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Nudge",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[ids, [], Vector3(16, 0, 0)],
		root.capture_brush_scope(ids),
		false,
		true,
		ids
	)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["do"][0]["method"], "restore_brush_scope", "redo restores the scope")
	assert_eq(entry["undo"][0]["method"], "restore_brush_scope", "and so does undo")


func test_without_a_scope_the_whole_level_restore_is_still_what_registers():
	var a := _make_brush(Vector3.ZERO)
	var ids := [_brush_id(a)]
	var undo_redo := FakeUndoRedo.new()
	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Nudge",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[ids, [], Vector3(16, 0, 0)],
		root.capture_state(),
		false,
		true
	)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["undo"][0]["method"], "restore_state", "a command with no scope is unchanged")


## A resize, which is the gizmo drag rather than a dock button. It is held down,
## the way the sculpt drag is, and `apply_resize_transaction()` registers it
## through `HFUndoHelper.commit()` on the one brush whose handle was pulled.
##
## Texture lock makes this worth asking rather than assuming: a resize defers its
## UV work to the commit, and a UV that lived anywhere but on the brush's own
## faces would be a write outside the scope.
func test_a_resize_changes_the_brushes_and_nothing_else():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var brush_id := _brush_id(a)
	assert_eq(
		_keys_changed_by(
			"set_brush_transform_by_id", [brush_id, Vector3(48, 32, 32), Vector3.ZERO]
		),
		["brushes"],
		"a resize claims a brush scope, so brushes is the only key it may change"
	)


# ===========================================================================
# Bevel and inset
# ===========================================================================


## The two shaping commands on the Build tab (#761). Both reshape the brush they
## name: a bevel replaces one edge with a chamfer, an inset shrinks one face and
## walls the gap. Neither writes a registry, a palette or an entity.
##
## Same rule as everywhere else here. A command that grows a write outside the
## brush fails this, and the answer is to take its scope away rather than widen
## it.
func test_the_bevel_commands_change_the_brushes_and_nothing_else():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var brush_id := _brush_id(a)
	assert_eq(
		_keys_changed_by("inset_face", [brush_id, 0, 4.0, 0.0]),
		["brushes"],
		"inset_face claims a brush scope, so brushes is the only key it may change"
	)
	root.clear_brushes()

	var c := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var bevel_id := _brush_id(c)
	assert_eq(
		_keys_changed_by("bevel_edge", [bevel_id, _a_bevellable_edge(bevel_id), 2, 2.0]),
		["brushes"],
		"bevel_edge claims a brush scope, so brushes is the only key it may change"
	)


func test_inset_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "inset_face", [ids[0], 0, 4.0, 0.0])


## A bevel adds faces, so the restore goes through the rebuild path rather than
## writing a transform onto a live node, which is where brush order and the id
## counter can come back wrong (#660).
func test_bevel_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "bevel_edge", [ids[0], _a_bevellable_edge(ids[0]), 2, 2.0])


## An edge `bevel_edge()` will accept, found on a throwaway brush so the one
## under test is still untouched when its state is captured.
##
## The indices are into the brush's unique vertex list and only a pair shared by
## exactly two faces bevels, so this asks rather than assumes: hard-coding a pair
## that stopped being adjacent would leave the tests above passing on a command
## that returned false and changed nothing.
func _a_bevellable_edge(_subject_id: String) -> Array:
	var probe := _make_brush(Vector3(0, 0, 192))
	var probe_id := _brush_id(probe)
	for i in range(8):
		for j in range(i + 1, 8):
			if root.bevel_edge(probe_id, [i, j], 2, 2.0):
				root.delete_brush_by_id(probe_id)
				return [i, j]
	root.delete_brush_by_id(probe_id)
	assert_true(false, "the fixture box has to have one bevellable edge")
	return []


# ===========================================================================
# Texturing one face
# ===========================================================================


## The two commands that texture a single face (#761). The UV spinboxes in the
## dock, which are dragged, and a material dropped from the browser onto a face
## in the viewport.
##
## Both were the last call sites still taking a whole-level snapshot that could
## name the brush they change. Both write fields on one `FaceData` and rebuild
## that brush's preview.
##
## The palette is the question worth asking here rather than assuming, the same
## one #762 asked of a brush paint. A face material is a slot index rather than a
## material, so a slot the palette does not hold could plausibly have grown one.
## It does not: `is_usable_material_slot()` reads the palette to refuse an index
## it has no slot for, and nothing on this path writes it.
func test_the_face_texturing_commands_change_the_brushes_and_nothing_else():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var brush_id := _brush_id(a)
	root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	assert_eq(
		_keys_changed_by(
			"set_face_uv_params", [brush_id, 0, Vector2(2.0, 2.0), Vector2(8.0, 0.0), 0.5]
		),
		["brushes"],
		"a UV spinbox drag claims a brush scope, so brushes is the only key it may change"
	)
	assert_eq(
		_keys_changed_by("assign_material_to_faces_by_id", [brush_id, [1], 1]),
		["brushes"],
		"a face material claims a brush scope, so brushes is the only key it may change"
	)


## The slot the palette has no room for. `assign_material_to_faces_by_id()`
## refuses it rather than growing the palette to fit, which is what keeps the
## claim above true for an index the browser could not have offered.
func test_a_face_material_slot_the_palette_does_not_hold_changes_nothing():
	var a := _make_brush(Vector3.ZERO)
	root.set_materials([StandardMaterial3D.new()])
	assert_eq(
		_keys_changed_by("assign_material_to_faces_by_id", [_brush_id(a), [0], 7]),
		[],
		"an index past the palette is refused, not added to it"
	)


func test_set_face_uv_params_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(
		ids, "set_face_uv_params", [ids[0], 0, Vector2(2.0, 2.0), Vector2(8.0, 0.0), 0.5]
	)


func test_a_face_material_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var ids := [_brush_id(a)]
	_assert_scoped_undo_round_trips(ids, "assign_material_to_faces_by_id", [ids[0], [1], 1])


# ===========================================================================
# Taking the scope and the level state as one decision
# ===========================================================================


## `capture_scope_or_state()` returns the "before" state and the ids that go with
## it, because the two have to agree. `commit_completed()` picks
## `restore_brush_scope` from the ids alone, so a caller that asked for a scope,
## got the whole level back, and still passed its ids would register a whole
## level state to be restored as though it were a scope.
func test_a_usable_scope_comes_back_with_its_ids():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(96, 0, 0))
	var ids := [_brush_id(a)]
	var before: Dictionary = HFUndoHelper.capture_scope_or_state(root, ids)
	assert_eq(before["scope_ids"], ids, "a scope that worked keeps the ids that restore it")
	assert_eq(
		(before["state"] as Dictionary).keys(),
		root.capture_brush_scope(ids).keys(),
		"the state is the scope, not the level"
	)


func test_a_scope_that_did_not_work_comes_back_with_no_ids():
	_make_brush(Vector3.ZERO)
	var before: Dictionary = HFUndoHelper.capture_scope_or_state(root, ["not-a-brush"])
	assert_eq(
		before["scope_ids"],
		[],
		"ids that could not be a scope must not travel with the level state they fell back to"
	)
	assert_true(
		(before["state"] as Dictionary).has("id_counter"),
		"the fallback is the whole level, and a scope never holds the id counter"
	)


func test_asking_for_no_scope_takes_the_level():
	_make_brush(Vector3.ZERO)
	var before: Dictionary = HFUndoHelper.capture_scope_or_state(root, [])
	assert_eq(before["scope_ids"], [], "no ids is no claim")
	assert_true((before["state"] as Dictionary).has("id_counter"), "so the record is the level")


func test_no_root_is_no_state_and_no_claim():
	var before: Dictionary = HFUndoHelper.capture_scope_or_state(null, ["b1"])
	assert_eq(before["state"], {}, "nothing to capture")
	assert_eq(before["scope_ids"], [], "and nothing to claim")


# ===========================================================================
# The entity half of a scope
# ===========================================================================


## What #761 parked, and why it did not need parking.
##
## The issue held the entity scope back on identity: a restore that rebuilds an
## entity changes its node path, and the commands name entities by path. That is
## true of `restore_state()`, which clears every entity and builds new ones. It
## is not true of a scope. Nudge, rotate and flip write onto entities that are
## already there, so a scoped restore frees nothing, and the node a record came
## from is the node it goes back onto.
func test_an_entity_on_its_own_is_a_scope():
	_make_brush(Vector3.ZERO)
	var light := _make_entity(Vector3(32, 0, 0))
	var scope: Dictionary = root.capture_brush_scope([], [_entity_path(light)])
	assert_false(scope.is_empty(), "a selection of one entity records that entity")
	assert_eq((scope.get("entities", {}) as Dictionary).size(), 1, "one record")
	assert_eq(scope.get("brushes", []), [], "and no brush, though the level has one")


func test_a_mixed_selection_is_a_scope():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	var light := _make_entity(Vector3(32, 0, 0))
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)], [_entity_path(light)])
	assert_eq((scope.get("brushes", []) as Array).size(), 1, "the brush it named")
	assert_eq((scope.get("entities", {}) as Dictionary).size(), 1, "and the entity beside it")


func test_a_path_that_is_not_an_entity_is_not_a_scope():
	var a := _make_brush(Vector3.ZERO)
	assert_true(
		root.capture_brush_scope([_brush_id(a)], [NodePath("Entities/NoSuchLight")]).is_empty(),
		"a path that resolves to nothing falls back to the whole snapshot"
	)


func test_nothing_named_is_still_not_a_scope():
	_make_entity(Vector3.ZERO)
	assert_true(root.capture_brush_scope([], []).is_empty(), "an empty selection records nothing")


## A brush-only scope is the record it was before entities could be in one. An
## editor session holds steps taken before this change, and the restore tells the
## two apart by shape rather than by a flag.
func test_a_brush_only_scope_is_the_record_it_always_was():
	var a := _make_brush(Vector3.ZERO)
	_make_entity(Vector3(32, 0, 0))
	var scope: Dictionary = root.capture_brush_scope([_brush_id(a)])
	assert_eq(scope.keys(), ["brushes", "order"], "no entity key when no entity was named")


func test_a_scoped_restore_puts_an_entity_back_onto_the_node_it_came_from():
	var light := _make_entity(Vector3(32, 0, 0))
	var node_id := light.get_instance_id()
	var path_before := str(_entity_path(light))
	var scope: Dictionary = root.capture_brush_scope([], [_entity_path(light)])
	light.global_position = Vector3(96, 0, 0)
	light.entity_data["angle"] = 90.0
	root.restore_brush_scope(scope)
	assert_eq(light.global_position, Vector3(32, 0, 0), "the transform goes back")
	assert_eq(light.entity_data.get("angle"), 0.0, "and so do the properties")
	assert_eq(light.get_instance_id(), node_id, "onto the same node, which is the whole point")
	assert_eq(str(_entity_path(light)), path_before, "so the path the record is keyed by held")


func test_a_scoped_restore_leaves_the_entities_outside_it_alone():
	var moved := _make_entity(Vector3.ZERO, "Moved")
	var other := _make_entity(Vector3(64, 0, 0), "Other")
	var scope: Dictionary = root.capture_brush_scope([], [_entity_path(moved)])
	moved.global_position = Vector3(16, 0, 0)
	other.global_position = Vector3(80, 0, 0)
	root.restore_brush_scope(scope)
	assert_eq(moved.global_position, Vector3.ZERO, "the one it recorded comes back")
	assert_eq(other.global_position, Vector3(80, 0, 0), "and the one it did not is not touched")


## A record the restore cannot use costs that record and not the step, the same
## way an unreadable brush entry does.
func test_an_entity_the_restore_cannot_find_costs_that_record_only():
	var light := _make_entity(Vector3.ZERO, "Present")
	var scope: Dictionary = root.capture_brush_scope([], [_entity_path(light)])
	var records: Dictionary = scope["entities"]
	records[NodePath("Entities/Gone")] = {"entity_type": "light_point"}
	light.global_position = Vector3(48, 0, 0)
	root.restore_brush_scope(scope)
	assert_eq(light.global_position, Vector3.ZERO, "the entity that is there still comes back")


# ===========================================================================
# Writing a record back onto a live entity
# ===========================================================================


func test_a_record_puts_a_free_name_back():
	var light := _make_entity(Vector3.ZERO, "Alpha")
	var record: Dictionary = root.entity_system.capture_entity_info(light)
	light.name = "Renamed"
	root.entity_system.apply_entity_record(light, record)
	assert_eq(str(light.name), "Alpha", "a name nothing else holds goes back")


## The one write in a record that could move the path the record is keyed by.
## Godot renames a node that is given a name a sibling already holds, so putting
## the name back unconditionally would leave every later lookup in the step
## pointing at nothing.
func test_a_record_keeps_a_name_a_sibling_already_holds():
	var first := _make_entity(Vector3.ZERO, "Alpha")
	var second := _make_entity(Vector3(64, 0, 0), "Beta")
	var record: Dictionary = root.entity_system.capture_entity_info(second)
	second.name = "Gamma"
	first.name = "Beta"
	root.entity_system.apply_entity_record(second, record)
	assert_eq(str(second.name), "Gamma", "the name is refused rather than uniquified")
	assert_eq(str(first.name), "Beta", "and the sibling that holds it keeps it")


## The record is what the entity was, so a field it does not carry is cleared
## rather than left as it is. A command that added an output and was undone would
## otherwise keep it.
func test_a_record_clears_the_metadata_it_does_not_carry():
	var light := _make_entity(Vector3.ZERO)
	var record: Dictionary = root.entity_system.capture_entity_info(light)
	light.set_meta("entity_io_outputs", [{"output_name": "OnFire"}])
	light.set_meta("entity_name", "light_1")
	root.entity_system.apply_entity_record(light, record)
	assert_eq(light.get_meta("entity_io_outputs", []), [], "the wiring goes back to none")
	assert_eq(str(light.get_meta("entity_name", "")), "", "and so does the authored name")


## Every field a record carries, through a write and back.
##
## `capture_entity_info()` is what a whole-level state records per entity, so two
## of those either side of a record write is the same comparison
## `_assert_scoped_undo_round_trips()` makes for the level. A field
## `apply_entity_record()` forgets shows up here rather than going quietly
## missing on an undo of a command that changed it.
func test_a_record_round_trips_every_field_it_carries():
	var light := _make_entity(Vector3(32, 8, 0), "Alpha")
	light.set_meta("entity_io_outputs", [{"output_name": "OnFire", "target_name": "door_1"}])
	light.set_meta("entity_name", "light_1")
	light.set_meta("visgroups", PackedStringArray(["wing_a"]))
	light.set_meta("group_id", "group_3")
	light.entity_data["range"] = 24.0
	var record: Dictionary = root.entity_system.capture_entity_info(light)
	light.name = "Beta"
	light.entity_type = "door_basic"
	light.global_transform = Transform3D(Basis(Vector3.UP, 1.2), Vector3(-9.0, 0.0, 5.0))
	light.entity_data = {"speed": 3.0}
	light.remove_meta("entity_io_outputs")
	light.set_meta("entity_name", "other")
	light.set_meta("visgroups", PackedStringArray(["wing_b"]))
	light.remove_meta("group_id")
	root.entity_system.apply_entity_record(light, record)
	assert_true(
		root.entity_system.capture_entity_info(light).recursive_equal(record, COMPARE_DEPTH),
		"what the entity records now has to be the record that was put back onto it"
	)


## The type is written before the properties. The type setter fills `entity_data`
## in from the class schema, so the other order would put the record's properties
## back and then grow schema keys onto them.
func test_a_record_puts_the_properties_back_without_the_schema_growing_them():
	var light := _make_entity(Vector3.ZERO)
	var record: Dictionary = root.entity_system.capture_entity_info(light)
	light.entity_data["range"] = 99.0
	light.entity_data["invented"] = true
	root.entity_system.apply_entity_record(light, record)
	assert_eq(light.entity_data, record["properties"], "the record's properties, exactly")


# ===========================================================================
# The transform commands, on a selection they could not scope before
# ===========================================================================


func test_an_entity_nudge_scoped_undo_matches_the_level_before_it():
	_make_brush(Vector3.ZERO)
	var light := _make_entity(Vector3(32, 0, 0))
	var paths := [_entity_path(light)]
	_assert_scoped_undo_round_trips(
		[], "nudge_managed_nodes", [[], paths, Vector3(16, 0, 0)], paths
	)


func test_a_mixed_nudge_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	var light := _make_entity(Vector3(32, 0, 0))
	var ids := [_brush_id(a)]
	var paths := [_entity_path(light)]
	_assert_scoped_undo_round_trips(
		ids, "nudge_managed_nodes", [ids, paths, Vector3(16, 0, 0)], paths
	)


func test_a_mixed_rotate_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	var light := _make_entity(Vector3(32, 0, 0))
	var ids := [_brush_id(a)]
	var paths := [_entity_path(light)]
	_assert_scoped_undo_round_trips(
		ids, "rotate_managed_nodes", [ids, paths, 1, 45.0, Vector3.ZERO], paths
	)


func test_a_mixed_flip_scoped_undo_matches_the_level_before_it():
	var a := _make_brush(Vector3.ZERO)
	_make_brush(Vector3(64, 0, 0))
	var light := _make_entity(Vector3(32, 0, 0))
	var ids := [_brush_id(a)]
	var paths := [_entity_path(light)]
	_assert_scoped_undo_round_trips(ids, "flip_managed_nodes", [ids, paths, 0, Vector3.ZERO], paths)


## The claim, for the selections the four transform commands could not make it
## for until now. Same rule as everywhere else here: these are the only keys they
## may change, and a command that grows a registry or palette write fails here
## and loses its scope rather than widening it.
func test_the_transform_commands_with_an_entity_change_nothing_else():
	var a := _make_brush(Vector3.ZERO)
	var light := _make_entity(Vector3(32, 0, 0))
	var ids := [_brush_id(a)]
	var paths := [_entity_path(light)]
	var cases := [
		["nudge_managed_nodes", [ids, paths, Vector3(16, 0, 0)]],
		["rotate_managed_nodes", [ids, paths, 1, 45.0, Vector3.ZERO]],
		["flip_managed_nodes", [ids, paths, 0, Vector3.ZERO]],
	]
	for case in cases:
		assert_eq(
			_keys_changed_by(str(case[0]), case[1] as Array),
			["brushes", "entities"],
			"%s may change the objects it named and nothing else" % str(case[0])
		)


## The more common selection than the mixed one the issue named, and it was
## unscoped for the same reason: an empty `brush_ids` used to end the claim too.
func test_nudging_an_entity_alone_changes_the_entities_and_nothing_else():
	_make_brush(Vector3.ZERO)
	var light := _make_entity(Vector3(32, 0, 0))
	assert_eq(
		_keys_changed_by("nudge_managed_nodes", [[], [_entity_path(light)], Vector3(16, 0, 0)]),
		["entities"],
		"a light on its own records the light"
	)


## The wiring, end to end. The transform commands hand their whole selection to
## the helper now, and an entity in it has to reach the scope rather than send
## the step back to the whole level.
func test_a_mixed_selection_registers_the_scoped_restore_at_both_ends():
	var a := _make_brush(Vector3.ZERO)
	var light := _make_entity(Vector3(32, 0, 0))
	var ids := [_brush_id(a)]
	var paths := [_entity_path(light)]
	var undo_redo := FakeUndoRedo.new()
	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Nudge",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[ids, paths, Vector3(16, 0, 0)],
		root.capture_brush_scope(ids, paths),
		false,
		true,
		ids,
		paths
	)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["do"][0]["method"], "restore_brush_scope", "redo restores the scope")
	assert_eq(entry["undo"][0]["method"], "restore_brush_scope", "and so does undo")
	assert_eq(light.global_position, Vector3(48, 0, 0), "the nudge happened")
	undo_redo.undo()
	assert_eq(light.global_position, Vector3(32, 0, 0), "and undo puts the entity back")
	undo_redo.redo()
	assert_eq(light.global_position, Vector3(48, 0, 0), "and redo moves it again")


## The other half of that: an entity the scope could not record sends the step
## back to the whole level, so the claim degrades to what every command did
## before rather than to a half restore.
func test_an_unrecordable_entity_sends_the_step_back_to_the_whole_level():
	var a := _make_brush(Vector3.ZERO)
	var ids := [_brush_id(a)]
	var paths := [NodePath("Entities/NoSuchLight")]
	var undo_redo := FakeUndoRedo.new()
	HFUndoHelper.register_action(
		undo_redo,
		root,
		"Nudge",
		MERGE_DISABLE,
		"nudge_managed_nodes",
		[ids, paths, Vector3(16, 0, 0)],
		root.capture_state(),
		false,
		true
	)
	var entry: Dictionary = undo_redo.entries[0]
	assert_eq(entry["undo"][0]["method"], "restore_state", "the fallback is the whole snapshot")
