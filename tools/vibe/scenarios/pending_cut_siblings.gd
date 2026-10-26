@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether the operations beside Clip, Hollow and Merge keep a pending cut pending.
##
## A pending cut is a subtract brush waiting for **Apply Pending Cuts**. #1943
## found that Clip, Hollow and Merge built their results in the draft brushes,
## which applied the cut without the mapper asking, and #1948 taught those three
## to keep it pending. This puts a pending cut through the operations beside
## them that make or rebuild brushes: Duplicate, Mirror Copy, the three arrays,
## Shear, Flip, Hull and Inset. Each result is read off the container it lands
## in.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")


func id() -> String:
	return "pending-cut-siblings"


func summary() -> String:
	return "whether Duplicate, Mirror Copy, arrays, Shear, Flip, Hull and Inset keep a pending cut pending"


func run() -> void:
	var applied: Array = []
	for op in [
		"duplicate",
		"mirror copy",
		"duplicate array",
		"radial array",
		"grid array",
		"shear",
		"flip",
		"hull",
		"inset"
	]:
		var root: Node3D = await fresh_root("PendingLevel")
		box(root, Vector3(8, 2, 8), Vector3(0, 1, 0))
		var cut = (
			root
			. create_brush_from_info(
				{
					"shape": 0,
					"size": Vector3(1, 3, 1),
					"center": Vector3(0, 1.5, 0),
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
					"pending": true,
				}
			)
		)
		await frame()
		var cut_id := str(cut.get_meta("brush_id", ""))
		if cut.get_parent() != root.pending_node:
			note(op, "the cut was not pending to start with, so nothing is asked")
			await drop_root(root)
			continue
		var before := _counts(root)
		var said: Variant = await _apply(root, op, cut, cut_id)
		await frame()
		var after := _counts(root)
		note(op, "%s -> %s; %s" % [before, after, said])
		# A cut that left the pending cuts for the drafts is applied.
		if after["draft_cuts"] > before["draft_cuts"]:
			applied.append(
				(
					"%s: %d subtract brush(es) now in the drafts, pending %d -> %d"
					% [
						op,
						after["draft_cuts"] - before["draft_cuts"],
						before["pending"],
						after["pending"]
					]
				)
			)
		await drop_root(root)
	if not applied.is_empty():
		flag(
			"an operation on a pending cut applies the cut without Apply Pending Cuts",
			"; ".join(applied)
		)


func _apply(root: Node3D, op: String, cut: Node3D, cut_id: String) -> Variant:
	match op:
		"duplicate":
			return root.duplicate_brush(cut)
		"mirror copy":
			return root.mirror_copy_managed_nodes([cut_id], [], 1, Vector3(2, 0, 0))
		"duplicate array":
			return root.create_duplicate_array(PackedStringArray([cut_id]), 2, Vector3(2, 0, 0))
		"radial array":
			return root.create_radial_array(
				PackedStringArray([cut_id]), 3, 1, 90.0, Vector3(2, 0, 0)
			)
		"grid array":
			return root.create_grid_array(
				PackedStringArray([cut_id]), Vector3i(2, 1, 2), Vector3(2, 0, 2)
			)
		"shear":
			return root.shear_managed_nodes([cut_id], [], 0, 1, 0.5, 0.0)
		"flip":
			root.flip_managed_nodes([cut_id], [], 0, cut.global_position)
			return "flipped"
		"hull":
			var other = (
				root
				. create_brush_from_info(
					{
						"shape": 0,
						"size": Vector3(1, 3, 1),
						"center": Vector3(2, 1.5, 0),
						"operation": CSGShape3D.OPERATION_SUBTRACTION,
						"pending": true,
					}
				)
			)
			await frame()
			var r = root.hull_brushes_by_ids([cut_id, str(other.get_meta("brush_id", ""))])
			return r.user_text() if r != null and r.has_method("user_text") else r
		"inset":
			var top := 0
			for i in cut.faces.size():
				if cut.faces[i].normal.y > 0.9:
					top = i
			return root.inset_face(cut_id, top, 0.2, 0.1)
	return null


func _counts(root: Node3D) -> Dictionary:
	var draft_cuts := 0
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush and child.operation == CSGShape3D.OPERATION_SUBTRACTION:
			draft_cuts += 1
	var pending := 0
	for child in root.pending_node.get_children():
		if child is DraftBrush:
			pending += 1
	return {"draft_cuts": draft_cuts, "pending": pending}
