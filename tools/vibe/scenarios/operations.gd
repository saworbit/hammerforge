@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Operations that come in pairs: a `can_*()` that answers whether the thing is
## allowed, and the operation that does it.
##
## The pair exists so the dock can refuse before it opens an undo action and
## tells the user it worked. That makes the `can_*()` the place the *rules* are
## written -- and it makes the operation the place they have to be enforced,
## because the operation is what an undo redo, a script, or a later call site
## reaches directly. A rule that lives only in the `can_*()` is a rule that
## holds for exactly one caller.


func id() -> String:
	return "operations"


func summary() -> String:
	return "whether each can_*() rule is also enforced by the operation it guards"


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func run() -> void:
	await _merging_brushes_of_different_operations()
	await _merging_with_an_id_that_is_not_there()
	await _hollow_and_clip_refusals()


func _add_box(root: Node3D, centre: Vector3, operation: int) -> Node:
	return root.create_brush_from_info(
		{"shape": 0, "size": Vector3(64, 64, 64), "center": centre, "operation": operation}
	)


## `can_merge_brushes()` refuses a mixed selection with "Cannot merge additive
## and subtractive brushes together". Whether `merge_brushes_by_ids()` agrees is
## a different question.
func _merging_brushes_of_different_operations() -> void:
	var root: Node3D = await fresh_root()
	var additive := _add_box(root, Vector3.ZERO, CSGShape3D.OPERATION_UNION)
	var subtractive := _add_box(root, Vector3(32, 0, 0), CSGShape3D.OPERATION_SUBTRACTION)
	await frame()
	var ids: Array = [_bid(additive), _bid(subtractive)]
	note("operations of the two brushes", [additive.operation, subtractive.operation])

	var check: HFOpResult = root.can_merge_brushes(ids)
	note("can_merge_brushes says", "ok %s -- %s" % [check.ok, check.user_text()])

	var before: int = root.brush_system.get_live_brush_count()
	var result: HFOpResult = root.merge_brushes_by_ids(ids)
	await frame()
	var after: int = root.brush_system.get_live_brush_count()
	var survivors: Array = root.draft_brushes_node.get_children()
	var ops: Array = []
	for s in survivors:
		ops.append(s.operation)
	note(
		"merge_brushes_by_ids says",
		(
			"ok %s -- %s; brushes %d -> %d, operations %s"
			% [result.ok, result.user_text(), before, after, ops]
		)
	)

	if not check.ok and result.ok:
		known(
			383,
			"merge_brushes_by_ids does not enforce the rule can_merge_brushes refuses on",
			(
				'can_merge_brushes() refuses this pair with "%s" and merge_brushes_by_ids() does it anyway, reporting "%s". The merged brush takes brushes[0].operation, so the subtractive brush\'s geometry is now additive -- the level builds a solid where the mapper had a hole. Only plugin_edit_actions.gd consults the check, and it does so before opening the undo action, so the redo of that action calls the operation with no check at all.'
				% [check.user_text(), result.user_text()]
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after merging brushes of different operations: %s" % problem)


## `can_merge_brushes()` fails outright when any id in the list is not in the
## level. The operation collects what it can find and carries on.
func _merging_with_an_id_that_is_not_there() -> void:
	var root: Node3D = await fresh_root()
	var a := _add_box(root, Vector3.ZERO, CSGShape3D.OPERATION_UNION)
	var b := _add_box(root, Vector3(128, 0, 0), CSGShape3D.OPERATION_UNION)
	await frame()
	var ids: Array = [_bid(a), _bid(b), "no_such_brush"]

	var check: HFOpResult = root.can_merge_brushes(ids)
	note("can_merge_brushes with a stale id", "ok %s -- %s" % [check.ok, check.user_text()])

	var result: HFOpResult = root.merge_brushes_by_ids(ids)
	await frame()
	note(
		"merge_brushes_by_ids with a stale id",
		(
			"ok %s -- %s; the level holds %d"
			% [result.ok, result.user_text(), root.brush_system.get_live_brush_count()]
		)
	)
	if not check.ok and result.ok:
		known(
			383,
			"merge_brushes_by_ids merges a subset when the check refuses the selection",
			(
				'can_merge_brushes() fails with "%s" because one id is not in the level; merge_brushes_by_ids() drops that id and merges the rest, reporting "%s". A mapper who selected three brushes gets two merged and is told it worked.'
				% [check.user_text(), result.user_text()]
			)
		)
	for problem in HFVibe.check_invariants(root):
		flag("after merging with a stale id: %s" % problem)


## The other two pairs, for the comparison.
func _hollow_and_clip_refusals() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var bid := _bid(b)

	for thickness in [0.0, -8.0, NAN, 1000.0]:
		var check: HFOpResult = root.can_hollow_brush(bid, thickness)
		var before: int = root.brush_system.get_live_brush_count()
		var result: HFOpResult = root.hollow_brush_by_id(bid, thickness)
		await frame()
		var after: int = root.brush_system.get_live_brush_count()
		note(
			"hollow with thickness %s" % thickness,
			"can_hollow %s / hollow %s; brushes %d -> %d" % [check.ok, result.ok, before, after]
		)
		if not check.ok and result.ok:
			flag(
				"hollow_brush_by_id does what can_hollow_brush refuses",
				(
					'thickness %s: the check says "%s" and the operation reports "%s"'
					% [thickness, check.user_text(), result.user_text()]
				)
			)
		if not result.ok and after != before:
			flag(
				"a refused hollow changed the level",
				"thickness %s: %d brushes before, %d after a refusal" % [thickness, before, after]
			)

	var root2: Node3D = await fresh_root()
	var c := box(root2, Vector3(64, 64, 64))
	await frame()
	var cid := _bid(c)
	for split in [1000.0, NAN, -1000.0]:
		var check: HFOpResult = root2.can_clip_brush(cid, 0, split)
		var before: int = root2.brush_system.get_live_brush_count()
		var result: HFOpResult = root2.clip_brush_by_id(cid, 0, split)
		await frame()
		var after: int = root2.brush_system.get_live_brush_count()
		note(
			"clip at %s" % split,
			"can_clip %s / clip %s; brushes %d -> %d" % [check.ok, result.ok, before, after]
		)
		if not check.ok and result.ok:
			flag(
				"clip_brush_by_id does what can_clip_brush refuses",
				(
					'split %s: the check says "%s" and the operation reports "%s"'
					% [split, check.user_text(), result.user_text()]
				)
			)
		if not result.ok and after != before:
			flag(
				"a refused clip changed the level",
				"split %s: %d brushes before, %d after a refusal" % [split, before, after]
			)
