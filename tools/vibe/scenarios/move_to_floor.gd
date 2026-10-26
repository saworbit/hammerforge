@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Where Move to Floor puts a brush, measured off the brush and the surface below.
##
## The command's help says "Drop the selection onto the nearest surface below
## it". `_move_brushes_vertical()` casts a ray down from the middle of each
## brush's bottom, at `size.y / 2` below its origin, puts the origin that far
## above the hit, and snaps the origin's height to the grid. This asks where the
## bottom of the brush ends up against the top of what is under it: for brushes
## whose half height is off the grid, a brush turned on its side, a selection of
## several brushes that stand on each other, and a floor that is hidden.

const GRID := 0.5


func id() -> String:
	return "move-to-floor"


func summary() -> String:
	return "where Move to Floor puts a brush's bottom against the surface under it"


func expected_issues() -> Array[int]:
	return [1964, 1965, 1966]


func run() -> void:
	await _heights()
	await _turned()
	await _table()
	await _hidden_floor()
	await _moved_since_bake()


## A floor whose top is at 0, and one box of each height dropped from above.
func _heights() -> void:
	var root: Node3D = await fresh_root("FloorLevel")
	root.grid_snap = GRID
	box(root, Vector3(40, 1, 4), Vector3(0, -0.5, 0))
	var rows: Array = []
	var bad: Array = []
	var x := -15.0
	for height in [2.0, 1.0, 0.75, 1.5, 3.0, 0.25]:
		var b = box(root, Vector3(1, height, 1), Vector3(x, 6.0, 0))
		x += 4.0
		await frame()
		root.move_brushes_to_floor([str(b.get_meta("brush_id", ""))])
		await frame()
		var bottom: float = _world_bottom(b)
		rows.append("%.2f tall: bottom at %.3f" % [height, bottom])
		if absf(bottom) > 0.001:
			bad.append("%.2f tall ends with its bottom at %.3f" % [height, bottom])
	note("boxes dropped onto a floor whose top is at 0, grid %.2f" % GRID, rows)
	if not bad.is_empty():
		known(
			1966,
			"Move to Floor leaves a brush floating or sunk when its half height is off the grid",
			(
				"%s. The command snaps the brush's middle to the grid rather than its bottom: a 0.75 tall box has its middle at 0.375 when it rests on the floor, and the grid moves that to 0.5."
				% "; ".join(bad)
			)
		)
	await drop_root(root)


## A 1 x 4 x 1 box turned 90 degrees about X lies on its side, 1 tall.
func _turned() -> void:
	var root: Node3D = await fresh_root("FloorLevel")
	root.grid_snap = GRID
	box(root, Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var b = box(root, Vector3(1, 4, 1), Vector3(0, 6.0, 0))
	var bid := str(b.get_meta("brush_id", ""))
	root.rotate_managed_nodes([bid], [], 0, 90.0, b.global_position)
	await frame()
	var before: float = _world_bottom(b)
	root.move_brushes_to_floor([bid])
	await frame()
	var bottom: float = _world_bottom(b)
	note(
		"a 1 x 4 x 1 box lying on its side", "bottom at %.3f before, %.3f after" % [before, bottom]
	)
	if absf(bottom) > 0.001:
		known(
			1966,
			"Move to Floor puts a turned brush off the floor",
			(
				"a 1 x 4 x 1 box turned 90 degrees about X lies 1 tall; Move to Floor leaves its bottom at %.3f over a floor whose top is at 0. The drop is measured with size.y / 2 = 2, the height it has unturned."
				% bottom
			)
		)
	await drop_root(root)


## A table: a top resting on four legs, the lot 1 above the floor. Select all
## five and drop.
func _table() -> void:
	var root: Node3D = await fresh_root("FloorLevel")
	root.grid_snap = GRID
	box(root, Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var ids: Array = []
	var legs: Array = []
	for corner in [
		Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)
	]:
		var leg = box(root, Vector3(0.5, 2, 0.5), corner + Vector3(0, 2, 0))
		legs.append(leg)
		ids.append(str(leg.get_meta("brush_id", "")))
	var top = box(root, Vector3(4, 0.5, 4), Vector3(0, 3.25, 0))
	ids.append(str(top.get_meta("brush_id", "")))
	await frame()
	root.move_brushes_to_floor(ids)
	await frame()
	var leg_bottom: float = _world_bottom(legs[0])
	var top_bottom: float = _world_bottom(top)
	var gap := top_bottom - (leg_bottom + 2.0)
	note(
		"a table 1 above the floor, all five brushes selected",
		(
			"legs' bottom at %.3f, top's bottom at %.3f (the legs' tops are at %.3f)"
			% [leg_bottom, top_bottom, leg_bottom + 2.0]
		)
	)
	if absf(gap) > 0.001:
		known(
			1964,
			"Move to Floor takes a selection apart",
			(
				"a table, four legs 2 tall under a top, standing 1 above the floor, all five selected: the legs land on the floor and the top lands at %.3f, %.3f %s the legs' tops. Each brush is dropped on its own, so the top falls between the legs. The command's help says it drops the selection."
				% [top_bottom, absf(gap), "into" if gap < 0.0 else "above"]
			)
		)
	await drop_root(root)


## A floor at 0 in a hidden visgroup, and a second floor at -4 under it.
func _hidden_floor() -> void:
	var root: Node3D = await fresh_root("FloorLevel")
	root.grid_snap = GRID
	box(root, Vector3(20, 1, 20), Vector3(0, -4.5, 0))
	var upper = box(root, Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	root.create_visgroup("upper")
	root.add_selection_to_visgroup("upper", [upper])
	root.set_visgroup_visible("upper", false)
	var b = box(root, Vector3(1, 1, 1), Vector3(0, 6.0, 0))
	await frame()
	root.move_brushes_to_floor([str(b.get_meta("brush_id", ""))])
	await frame()
	var bottom: float = _world_bottom(b)
	note("a box over a hidden floor at 0, with a shown floor at -4", "bottom at %.3f" % bottom)
	if absf(bottom) < 0.001:
		known(
			1965,
			"Move to Floor lands on a hidden brush",
			(
				"with the floor at 0 in a hidden visgroup, a box dropped from above lands on it, at %.3f, not on the shown floor at -4."
				% bottom
			)
		)
	await drop_root(root)


func _world_bottom(brush: Node3D) -> float:
	var lowest := INF
	for face in brush.faces:
		for v in face.local_verts:
			lowest = minf(lowest, (brush.global_transform * v).y)
	return lowest


## A floor baked at 0, then moved down to -4 without a second bake.
func _moved_since_bake() -> void:
	var root: Node3D = await fresh_root("FloorLevel")
	root.grid_snap = GRID
	var ground = box(root, Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	await root.bake(true, false)
	await frame()
	root.nudge_brushes_by_id([str(ground.get_meta("brush_id", ""))], Vector3(0, -4, 0))
	var b = box(root, Vector3(1, 1, 1), Vector3(0, 6.0, 0))
	await frame()
	await _tree.physics_frame
	root.move_brushes_to_floor([str(b.get_meta("brush_id", ""))])
	await frame()
	var bottom: float = _world_bottom(b)
	note("a box over a floor moved from 0 to -4 since the last bake", "bottom at %.3f" % bottom)
	if absf(bottom) < 0.001:
		known(
			1965,
			"Move to Floor lands on baked collision the level no longer has",
			(
				"the floor was baked at 0 and moved to -4; a box dropped from above lands at %.3f, on the old bake, in the air over the floor."
				% bottom
			)
		)
	await drop_root(root)
