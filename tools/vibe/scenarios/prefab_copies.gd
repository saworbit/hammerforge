@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Placed prefab copies (#1797, #1799): Unlink, Select Linked Copies, what a copy
## keeps through a Pull, and a duplicate of a linked copy.
##
## A copy keeps a property by its piece's key, "b" or "e" and the piece's index
## in the copy. The question is what that key means after a Pull that changes how
## many pieces there are, and whether every rebuild of a copy (Pull, Discard
## Changes, a variant switch) leaves a locked piece alone the way a Pull does.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")

const PANEL := "user://vibe_prefab_copies_panel.hfprefab"


func id() -> String:
	return "prefab-copies"


func summary() -> String:
	return "kept properties through a Pull that drops a piece, unlink, copies, duplicates and locks"


func expected_issues() -> Array[int]:
	return [1976, 1977]


func run() -> void:
	await _kept_through_a_pull_that_drops_a_piece()
	await _a_copy_with_a_locked_piece()
	await _unlink_and_duplicate_through_undo()
	if FileAccess.file_exists(PANEL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PANEL))


## A panel of two buttons, each aimed at its own door, saved as a prefab, with
## two linked copies. Returns the two copies' ids.
func _two_copies(root: Node3D) -> Array:
	var first = root.create_brush_from_info(
		{"brush_id": "src_a", "size": Vector3(1, 1, 0.2), "center": Vector3(-20, 1, 0)}
	)
	var second = root.create_brush_from_info(
		{"brush_id": "src_b", "size": Vector3(1, 1, 0.2), "center": Vector3(-18, 1, 0)}
	)
	root.brush_system.tie_brushes_to_entity(["src_a"], "func_button")
	root.brush_system.tie_brushes_to_entity(["src_b"], "func_button")
	HFEntityPropUtils.set_entity_property(first, "target", "door_a")
	HFEntityPropUtils.set_entity_property(second, "target", "door_b")
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, [first, second], []
	)
	prefab.save_to_file(PANEL)
	root.delete_brush(first)
	root.delete_brush(second)
	var iids: Array = []
	for x in [0.0, 10.0]:
		var placed: Dictionary = prefab.instantiate(
			root.brush_system, root.entity_system, root, Vector3(x, 1, 0)
		)
		iids.append(
			root.prefab_system.register_instance(
				PANEL, placed["brush_ids"], placed["entity_nodes"], true
			)
		)
	return iids


func _pieces(root: Node3D, iid: String) -> Array:
	return root.prefab_system.pieces_of(root.prefab_system.get_instance(iid))


func _targets(root: Node3D, iid: String) -> Array:
	var out: Array = []
	for piece in _pieces(root, iid):
		out.append(str(HFEntityPropUtils.get_entity_data(piece).get("target", "")))
	return out


## Copy X keeps its first button's target. Copy Y loses its first button and
## pushes, so the prefab is one button, door_b's. A Pull then rebuilds X.
func _kept_through_a_pull_that_drops_a_piece() -> void:
	var root: Node3D = await fresh_root()
	var iids := _two_copies(root)
	var x_pieces := _pieces(root, iids[0])
	root.set_entity_property(x_pieces[0], "target", "door_7")
	root.set_prefab_kept(x_pieces[0], "target", true)
	note("X before: targets", _targets(root, iids[0]))
	# Y drops its first button and pushes.
	var y_pieces := _pieces(root, iids[1])
	root.delete_brush(y_pieces[0])
	await frame()
	note("Y after deleting its first button", _targets(root, iids[1]))
	root.prefab_system.push_instance_to_source(iids[1])
	var count: int = root.prefab_system.propagate_from_source(PANEL)
	await frame()
	note("Pull updated", count)
	var after := _targets(root, iids[0])
	note("X after the Pull: targets", after)
	note("X keeps", root.prefab_system.get_instance(iids[0]).kept)
	if after.has("door_7") and after.size() == 1:
		known(
			1976,
			"a kept property lands on a different piece after a Pull that drops an earlier one",
			"X kept its first button's target door_7; the prefab now holds only the button aimed at door_b, and after the Pull that button aims at door_7 -- kept values are keyed by the piece's index (piece_key() 'b0'), and a Pull renumbers the pieces"
		)
	await drop_root(root)


## A Pull leaves a copy with a locked piece as it is (#1697). Discard Changes,
## Clear Kept and a variant switch rebuild the copy the same way a Pull does.
func _a_copy_with_a_locked_piece() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var iids := _two_copies(root)
	var x_pieces := _pieces(root, iids[0])
	# X's second button was aimed elsewhere, then its visgroup was locked.
	root.set_entity_property(x_pieces[1], "target", "door_x")
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [x_pieces[1]])
	vg.set_visgroup_locked("Done", true)
	var locked_id := str(x_pieces[1].get_meta("brush_id", ""))
	note("X before: targets", _targets(root, iids[0]))
	root.prefab_system.propagate_from_source(PANEL)
	note(
		"after a Pull: X targets, locked brush still there",
		[_targets(root, iids[0]), root.find_brush_by_id(locked_id) != null]
	)
	var discarded: bool = root.prefab_system.discard_changes(iids[0])
	var after := _targets(root, iids[0])
	note(
		"after Discard Changes (%s): X targets, locked brush id still there" % discarded,
		[after, root.find_brush_by_id(locked_id) != null]
	)
	if not after.has("door_x"):
		known(
			1977,
			"Discard Changes rebuilds a copy's locked piece, which a Pull leaves alone",
			(
				"the locked button aimed at door_x before and at %s after; propagate_from_source() asks _instance_is_locked() and set_variant(), which Discard Changes, Clear Kept and a variant switch run, does not"
				% [after]
			)
		)
	await drop_root(root)


## Unlink and a duplicated linked copy through capture_state / restore_state.
func _unlink_and_duplicate_through_undo() -> void:
	var root: Node3D = await fresh_root()
	var ps = root.prefab_system
	var iids := _two_copies(root)
	var piece: Node = _pieces(root, iids[0])[0]
	var piece_id := str(piece.get_meta("brush_id", ""))
	var before: Dictionary = root.capture_state()
	ps.unlink_instance(iids[0])
	var after: Dictionary = root.capture_state()
	note(
		"after Unlink: X's piece is a copy", ps.instance_of(root.find_brush_by_id(piece_id)) != null
	)
	note("copies of Y", ps.copies_like(iids[1]).size())
	root.restore_state(before)
	await frame()
	var back = ps.instance_of(root.find_brush_by_id(piece_id))
	note("after undoing Unlink: X's piece is a copy again", back != null)
	if back == null:
		flag("undoing Unlink leaves the copy unlinked")
	root.restore_state(after)
	await frame()
	var again = ps.instance_of(root.find_brush_by_id(piece_id))
	note("after redoing Unlink: X's piece is a copy", again != null)
	if again != null:
		flag("redoing Unlink leaves the copy linked")
	# Duplicate a linked copy, keeping what it keeps.
	root.restore_state(before)
	await frame()
	var y_first: Node = _pieces(root, iids[1])[0]
	root.set_entity_property(y_first, "target", "door_9")
	ps.set_kept(y_first, "target", true)
	var copy: String = ps.duplicate_linked(iids[1], Vector3(0, 0, 10))
	note(
		"duplicate of Y: id, linked, targets",
		[
			copy,
			ps.get_instance(copy).linked if copy != "" else null,
			_targets(root, copy) if copy != "" else []
		]
	)
	note("copies of Y now", ps.copies_like(iids[1]).size())
	if copy != "" and not _targets(root, copy).has("door_9"):
		flag("a duplicated linked copy does not keep what its original keeps", _targets(root, copy))
	await drop_root(root)
