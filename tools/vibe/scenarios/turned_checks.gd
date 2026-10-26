@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Check Bake Issues says about a cut in a turned wall.
##
## The two cut checks, "does not overlap any solid brush" and "cuts overlap",
## read each brush as its unturned size placed at its origin
## (`_build_brush_records()`, which says so). A wall drawn along X and turned a
## quarter turn runs along Z, and its box in those checks still runs along X.
## This cuts a doorway into such a wall, bakes it to show the hole is real, and
## reads what the checks say about the cut.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")


func id() -> String:
	return "turned-checks"


func summary() -> String:
	return "what Check Bake Issues says about a cut in a turned wall"


func expected_issues() -> Array[int]:
	return [1967]


func run() -> void:
	var root: Node3D = await fresh_root("TurnedLevel")
	box(root, Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	var wall = box(root, Vector3(8, 3, 0.3), Vector3(0, 1.5, 0))
	var wall_id := str(wall.get_meta("brush_id", ""))
	root.rotate_managed_nodes([wall_id], [], 1, 90.0, wall.global_position)
	await frame()
	# The doorway is drawn as the mapper would draw it against a wall that runs
	# along Z: thin in X, wide in Z, 3 along the wall from its middle.
	var door = (
		root
		. create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(0.6, 2.2, 1.2),
				"center": Vector3(0, 1.1, 3),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
			}
		)
	)
	door.operation = CSGShape3D.OPERATION_SUBTRACTION
	await frame()
	var issues: Array = root.validation_system.check_bake_issues()
	var said: Array = []
	for issue in issues:
		if (
			issue is Dictionary
			and str(issue.get("type", "")) in ["floating_subtract", "overlapping_subtract"]
		):
			said.append("%s: %s" % [issue["type"], issue["message"]])
	note(
		"what Check Bake Issues says about the doorway", said if not said.is_empty() else "nothing"
	)
	await root.bake(true, false)
	await frame()
	for child in root.draft_brushes_node.get_children():
		root.draft_brushes_node.remove_child(child)
		child.queue_free()
	await frame()
	await _tree.physics_frame
	await _tree.physics_frame
	var through := _ray(root, Vector3(-2, 1.0, 3), Vector3(2, 1.0, 3))
	var solid := _ray(root, Vector3(-2, 1.0, -2), Vector3(2, 1.0, -2))
	note("a ray across the doorway after the bake hits", through)
	note("a ray across the wall beside it hits", solid)
	var cut_is_real := through == "nothing" and solid != "nothing"
	for line in said:
		if str(line).begins_with("floating_subtract") and cut_is_real:
			known(
				1967,
				"Check Bake Issues says a doorway in a turned wall cuts nothing",
				(
					"a wall 8 x 3 x 0.3 turned a quarter turn about Y, and a cut 0.6 x 2.2 x 1.2 through it 3 along it. The bake makes the doorway (a ray through it hits %s, one through the wall beside it hits %s), and Check Bake Issues says: %s."
					% [through, solid, line]
				)
			)
	await drop_root(root)


func _ray(root: Node3D, from: Vector3, to: Vector3) -> String:
	var space := root.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return "nothing"
	return "a hit at %s" % (hit["position"] as Vector3).snapped(Vector3.ONE * 0.01)
