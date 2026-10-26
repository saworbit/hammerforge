@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The floor grid turned to an angle (#1919, #1950). Everything that snaps to it
## is meant to use the turn: Snap to Grid, the nudges along its sides, vertex
## snapping, a Draw, and Repeat. The suite checks each through a turn at the
## world origin. This asks them through a turn whose lines run through an odd
## point, through long runs of nudges (the world grid has a fix that keeps a
## nudged brush on its lines, #1203, that the turned one does not reach), through
## a Draw made headless, through Repeat at odd and even sizes, and through the
## state round trips the turn is meant to sit outside of.

const HFDuplicator = preload("res://addons/hammerforge/hf_duplicator.gd")

var _x := 0.0


func id() -> String:
	return "turned-grid"


func summary() -> String:
	return "snapping, nudges, a draw, Repeat and round trips on a grid turned through an odd point"


func expected_issues() -> Array[int]:
	return [2005]


func run() -> void:
	await _snapping_through_an_odd_origin()
	await _a_long_run_of_nudges()
	await _a_draw_on_the_turned_grid()
	await _repeat_on_the_turned_grid()
	await _the_turn_through_state_and_files()


func _box(root: Node3D, brush_id: String, size: Vector3, centre: Vector3, degrees := 0.0) -> Node:
	var info := {"shape": 0, "size": size, "center": centre, "brush_id": brush_id}
	if degrees != 0.0:
		info["transform"] = Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), centre)
	return root.create_brush_from_info(info)


static func _corners(brush: Node) -> Array:
	var out: Array = []
	for face in brush.faces:
		for corner in face.local_verts:
			out.append(brush.global_transform * corner)
	return out


## How far `point` is from the nearest point of the grid `frame` lays, `step` apart.
static func _off_grid(frame: Transform3D, point: Vector3, step: float) -> float:
	var local := frame.affine_inverse() * point
	return local.distance_to(local.snapped(Vector3.ONE * step))


static func _worst_off(frame: Transform3D, points: Array, step: float) -> float:
	var worst := 0.0
	for p in points:
		worst = maxf(worst, _off_grid(frame, p, step))
	return worst


func _snapping_through_an_odd_origin() -> void:
	var root: Node3D = await fresh_root("TurnedSnap")
	root.grid_snap = 0.5
	var grid = root.grid_system
	grid.set_turn(30.0, Vector3(0.3, 0.0, 0.7))
	var frame: Transform3D = grid.grid_frame()
	note("turn 30 through (0.3, 0, 0.7)", "frame %s, turned %s" % [frame, grid.is_turned()])
	# A point snapped.
	var p := Vector3(2.17, 0.0, -1.33)
	var snapped_p: Vector3 = root._snap_point(p)
	note(
		"a point snapped",
		"%s -> %s, off the turned grid by %.6f" % [p, snapped_p, _off_grid(frame, snapped_p, 0.5)]
	)
	if _off_grid(frame, snapped_p, 0.5) > 0.0005:
		flag(
			"a snapped point is not on the turned grid",
			"%s, %.5f off" % [snapped_p, _off_grid(frame, snapped_p, 0.5)]
		)
	# Snap to Grid: a box turned with the grid, placed off it.
	var turned := _box(root, "sq", Vector3(2, 1, 1.5), frame * Vector3(1.13, 0.5, 0.91), 30.0)
	root.brush_system.snap_brushes_to_grid(["sq"], 0.5)
	turned = root.find_brush_by_id("sq")
	var worst := _worst_off(frame, _corners(turned), 0.5)
	note(
		"Snap to Grid of a 2 x 1 x 1.5 box turned with the grid",
		"worst corner off the grid %.6f" % worst
	)
	if worst > 0.0005:
		flag(
			"Snap to Grid leaves a box square to the turned grid off its points",
			"worst corner %.5f off" % worst
		)
	# An entity.
	var light: Node = root._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(3.37, 1.0, 2.21)}
	)
	root.entity_system.snap_entities_to_grid([str(root.get_path_to(light))], 0.5)
	note(
		"Snap to Grid of an entity",
		"%s, off %.6f" % [light.global_position, _off_grid(frame, light.global_position, 0.5)]
	)
	if _off_grid(frame, light.global_position, 0.5) > 0.0005:
		flag("Snap to Grid leaves an entity off the turned grid", light.global_position)
	# Vertex snap of a turned box's corners.
	var v := _box(root, "verts", Vector3(1, 1, 1), frame * Vector3(5.2, 0.5, 2.3), 30.0)
	var vs = root.vertex_system
	vs.clear_selection()
	var count: int = vs.get_brush_vertices(v).size()
	for i in count:
		vs.select_vertex("verts", i, i > 0)
	var result: Dictionary = vs.snap_selected_to_grid(0.5)
	v = root.find_brush_by_id("verts")
	var worst_v := _worst_off(frame, _corners(v), 0.5)
	note(
		"vertex Snap to Grid of a turned box's %d corners" % count,
		"%d brush(es) moved, worst corner off %.6f" % [result.size(), worst_v]
	)
	if worst_v > 0.0005:
		flag("vertex Snap to Grid leaves corners off the turned grid", "worst %.5f" % worst_v)
	await drop_root(root)


## Two boxes square to the grid turned 30, touching face to face. One is nudged
## along the grid's X forty times away and forty back, as the arrow keys move it.
## Then Check Issues looks for a micro-gap between them. The same on the world's
## grid, for comparison.
func _a_long_run_of_nudges() -> void:
	for degrees in [0.0, 30.0]:
		_x += 100.0
		var root: Node3D = await fresh_root("Nudges_%d" % int(degrees))
		root.grid_snap = 0.25
		var grid = root.grid_system
		var origin := Vector3(_x, 0, 0)
		if degrees != 0.0:
			grid.set_turn(degrees, origin)
		var frame: Transform3D = (
			grid.grid_frame() if degrees != 0.0 else Transform3D(Basis.IDENTITY, origin)
		)
		_box(root, "a", Vector3(2, 2, 2), frame * Vector3(1, 1, 1), degrees)
		_box(root, "b", Vector3(2, 2, 2), frame * Vector3(3, 1, 1), degrees)
		var step: Vector3 = frame.basis * Vector3(0.25, 0, 0)
		for i in 40:
			root.nudge_brushes_by_id(["a"], -step)
		for i in 40:
			root.nudge_brushes_by_id(["a"], step)
		var a: Node = root.find_brush_by_id("a")
		var worst := _worst_off(frame, _corners(a), 0.25)
		var gaps := 0
		for finding in root.validation_system.check_bake_issues():
			if str(finding.get("message", "")).begins_with("Micro-gap"):
				gaps += 1
		note(
			"grid %d degrees: box nudged 40 steps away and 40 back" % int(degrees),
			"worst corner off the grid %.7f, micro-gaps %d" % [worst, gaps]
		)
		if gaps > 0:
			flag(
				(
					"forty nudges out and back on a %d degree grid leave a micro-gap where the box touched"
					% int(degrees)
				),
				"worst corner %.7f off the grid" % worst
			)
		await drop_root(root)


func _camera(at: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	_tree.get_root().add_child(cam)
	cam.global_position = at + Vector3(0, 40, 0)
	cam.look_at(at, Vector3.BACK)
	await frame()
	return cam


## A Draw from one grid point to another, made through the drag system with a
## camera the way the Draw tool makes it.
func _a_draw_on_the_turned_grid() -> void:
	_x += 100.0
	var origin := Vector3(_x, 0, 0)
	var root: Node3D = await fresh_root("TurnedDraw")
	root.grid_snap = 0.5
	var grid = root.grid_system
	grid.set_turn(30.0, origin + Vector3(0.3, 0, 0.7))
	var frame: Transform3D = grid.grid_frame()
	var cam: Camera3D = await _camera(origin)
	var a: Vector3 = frame * Vector3(1, 0, 1)
	var b: Vector3 = frame * Vector3(4, 0, 3)
	var began: bool = root.drag_system.begin_drag(
		cam,
		cam.unproject_position(a + Vector3(0.05, 0, 0.04)),
		CSGShape3D.OPERATION_UNION,
		Vector3(1, 1, 1),
		0
	)
	root.drag_system.update_drag(cam, cam.unproject_position(b + Vector3(-0.04, 0, 0.06)))
	root.drag_system.end_drag_info(cam, cam.unproject_position(b), Vector3(1, 1, 1))
	root.drag_system.update_drag(cam, cam.unproject_position(b) + Vector2(0, -30))
	var placed: Dictionary = root.drag_system.end_drag_info(
		cam, cam.unproject_position(b) + Vector2(0, -30), Vector3(1, 1, 1)
	)
	var info: Dictionary = placed.get("info", {})
	note("a Draw on the turned grid", "began %s, info %s" % [began, info])
	if not info.is_empty():
		var brush: Node = root.create_brush_from_info(info)
		await frame()
		var worst := _worst_off(frame, _corners(brush), 0.5)
		var turn_deg := rad_to_deg(brush.global_transform.basis.get_euler().y)
		note(
			"the brush the Draw made",
			(
				"size %s, turned %.3f degrees, worst corner off the grid %.6f"
				% [brush.size, turn_deg, worst]
			)
		)
		if worst > 0.0005:
			flag("a Draw on the turned grid puts corners off its points", "worst %.5f" % worst)
		if absf(turn_deg - 30.0) > 0.01:
			flag("a Draw on the turned grid is not square to it", "turned %.3f" % turn_deg)
	cam.queue_free()
	await drop_root(root)


## Repeat's copies stand centred on the grid point under the cursor. The guide
## says a copy whose sides are whole steps has its corners on the grid's points.
func _repeat_on_the_turned_grid() -> void:
	_x += 100.0
	var origin := Vector3(_x, 0, 0)
	for degrees in [0.0, 30.0]:
		var root: Node3D = await fresh_root("Repeat_%d" % int(degrees))
		root.grid_snap = 1.0
		var grid = root.grid_system
		if degrees != 0.0:
			grid.set_turn(degrees, origin)
		var frame: Transform3D = grid.grid_frame() if degrees != 0.0 else Transform3D.IDENTITY
		var results := {}
		for size in [Vector3(2, 2, 2), Vector3(3, 2, 3), Vector3(1, 1, 1), Vector3(2, 1, 3)]:
			var base: Vector3 = frame * Vector3(4, 0, 2)
			var info: Dictionary = root.drag_system.repeat_info(
				{"shape": 0, "size": size, "operation": CSGShape3D.OPERATION_UNION}, base
			)
			var brush: Node = root.create_brush_from_info(info)
			results[str(size)] = snappedf(_worst_off(frame, _corners(brush), 1.0), 0.0001)
			root.delete_brush_by_id(str(brush.brush_id))
		note(
			(
				"Repeat on the %s grid, worst corner off it by size"
				% ("world's" if degrees == 0.0 else "%d degree" % int(degrees))
			),
			results
		)
		var odd_off := false
		for key in results:
			if results[key] > 0.0005:
				odd_off = true
		if odd_off and degrees != 0.0:
			known(
				2005,
				"the guide says a Repeat copy whose sides are whole steps has its corners on the turned grid's points; an odd number of steps does not",
				(
					"worst corner off the grid by size %s: repeat_frame() centres the copy on the grid point, so a 1 or 3 step side puts its corners half a step off, on the world's grid too. #1923 and the code comment say even numbers of steps; docs/HammerForge_UserGuide.md (Repeat Last Brush) says whole steps"
					% [results]
				)
			)
		await drop_root(root)


## The turn is editor state: not saved, and an undo leaves it alone.
func _the_turn_through_state_and_files() -> void:
	var root: Node3D = await fresh_root("TurnState")
	root.hflevel_autosave_enabled = false
	root.grid_snap = 0.5
	_box(root, "x", Vector3(1, 1, 1), Vector3(0, 0.5, 0))
	var state: Dictionary = root.capture_state()
	root.grid_system.set_turn(30.0, Vector3(0.3, 0, 0.7))
	root.restore_state(state)
	await frame()
	note("turn after an undo (restore_state)", root.grid_system.turn_degrees)
	if not root.grid_system.is_turned():
		flag(
			"an undo puts the turned grid back to the world's",
			"the guide calls the turn editor state"
		)
	var settings: Dictionary = (
		root.state_system.capture_hflevel_settings() if root.state_system else {}
	)
	var says_turn := false
	for key in settings:
		if str(key).contains("turn"):
			says_turn = true
	note("the .hflevel settings name a turn", says_turn)
	root.state_system.apply_hflevel_settings(settings)
	note(
		"turn after the level's settings are applied again (as a load or a settings undo does)",
		root.grid_system.turn_degrees
	)
	if not root.grid_system.is_turned():
		flag("re-applying the level's settings puts the turned grid back to the world's")
	await drop_root(root)
