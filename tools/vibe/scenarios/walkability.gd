@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether a person can walk through what was built.
##
## Everything else in the sweep measures the level as a data structure. This one
## puts a body in it and moves. A level is not finished when it validates and
## bakes; it is finished when a player can get from one end of it to the other
## without falling through the floor, getting stuck in a doorway or being unable
## to climb a step, and none of those is visible in any count.
##
## `playtest-spawn` checks where the player starts. This checks what happens
## after that.


func id() -> String:
	return "walkability"


func summary() -> String:
	return "whether a body the size of the playtest player can walk the level that was baked"


const PLAYER_HEIGHT := 1.6
const PLAYER_RADIUS := 0.35


func run() -> void:
	await _does_the_floor_hold()
	await _can_it_get_through_a_doorway()
	await _can_it_climb_the_stairs_the_plugin_builds()


## A capsule the size of the playtest player, dropped in and settled.
## The step height and physics tick the walk loop drives the shipped routine with.
## `max_step_height` is what `playtest_fps.gd` exports; the tick is Godot's
## default physics rate, which is what `_physics_process` would hand it.
const STEP_HEIGHT := 0.4
const FIXED_STEP := 1.0 / 60.0
const PlaytestFPS = preload("res://addons/hammerforge/playtest_fps.gd")


func _player(root: Node3D, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = PLAYER_HEIGHT
	capsule.radius = PLAYER_RADIUS
	shape.shape = capsule
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
	# The shipped player widens this so the drop onto a step is caught.
	body.floor_snap_length = maxf(body.floor_snap_length, STEP_HEIGHT + 0.05)
	body.global_position = at
	return body


## Drop the live draft brushes, the way a bake with `hide_live` does. Their
## picking collision is on layer 1 and a game never sees it; leaving it in means
## the walk measures the editor rather than the level.
func _hide_drafts(root: Node3D) -> void:
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			root.draft_brushes_node.remove_child(child)
			child.queue_free()


func _settle(body: CharacterBody3D) -> void:
	var fall := 0.0
	for _i in 24:
		fall = 0.0 if body.is_on_floor() else fall - 9.8 * FIXED_STEP
		body.velocity = Vector3(0, fall, 0)
		body.move_and_slide()
		fall = body.velocity.y
		await frame()


## Walk `body` toward `target` until it arrives or stops making progress.
##
## "Stopped" has to be measured as a stall rather than as distance remaining: a
## fixed iteration budget reads as the player being blocked whenever the budget
## runs out, which is how the first version of this scenario reported a flat
## open floor as impassable.
func _walk_to(body: CharacterBody3D, target: Vector3, budget: int = 2000) -> Dictionary:
	var lowest: float = body.global_position.y
	var start: Vector3 = body.global_position
	var stalled := 0
	var last: Vector3 = body.global_position
	var used := 0
	# Gravity the way `playtest_fps.gd` applies it: zero on the floor, accumulating
	# only while airborne. The constant -9.8 this loop used to set is not gravity,
	# it is a downward velocity nine times a walk speed, and it pins the body to
	# whatever it is standing on - which is a fair model of nothing the plugin
	# ships, and it hides every step the player takes.
	var fall := 0.0
	for _i in budget:
		used += 1
		var to_target: Vector3 = target - body.global_position
		to_target.y = 0.0
		if to_target.length() < 0.25:
			break
		if body.is_on_floor():
			fall = 0.0
		else:
			fall -= 9.8 * FIXED_STEP
		body.velocity = to_target.normalized() * 3.0
		body.velocity.y = fall
		# The step-up the shipped player runs, driven directly, because this loop
		# sets velocity rather than pressing keys. It is the same static routine
		# `playtest_fps.gd` calls each physics frame.
		PlaytestFPS.step_body_up(
			body, Vector3(body.velocity.x, 0.0, body.velocity.z) * FIXED_STEP, STEP_HEIGHT
		)
		body.move_and_slide()
		fall = body.velocity.y
		lowest = minf(lowest, body.global_position.y)
		if body.global_position.distance_to(last) < 0.002:
			stalled += 1
			if stalled > 40:
				break
		else:
			stalled = 0
		last = body.global_position
		await frame()
	return {
		"from": start,
		"reached": body.global_position,
		"remaining": (target - body.global_position).length(),
		"lowest_y": lowest,
		"stalled": stalled > 40,
		"steps_used": used,
		"budget": budget,
	}


func _does_the_floor_hold() -> void:
	# One seam, crossed head on, in each collision mode. A floor of any size is
	# several brushes butted edge to edge, so the join is the most common piece of
	# geometry in a level after the brush itself.
	for mode in [0, 1, 2]:
		var root: Node3D = await fresh_root()
		box(root, Vector3(10, 0.3, 6), Vector3(-5, -0.15, 0))
		box(root, Vector3(10, 0.3, 6), Vector3(5, -0.15, 0))
		root.bake_collision_mode = mode
		await frame()
		await root.bake(false, false)
		await frame()
		_hide_drafts(root)
		await frame()
		await frame()

		var body := _player(root, Vector3(-4, 1.0, 0))
		await _settle(body)
		var feet: float = body.global_position.y - PLAYER_HEIGHT * 0.5
		var walk: Dictionary = await _walk_to(body, Vector3(4, 1.0, 0))
		note(
			"bake_collision_mode = %d: walking from x -4 to x 4 across the seam at x 0" % mode,
			(
				"feet settled at %.4f, reached x %.2f, stalled %s, %d of %d steps, lowest y %.3f"
				% [
					feet,
					body.global_position.x,
					walk["stalled"],
					int(walk["steps_used"]),
					int(walk["budget"]),
					float(walk["lowest_y"]),
				]
			)
		)
		if float(walk["lowest_y"]) < -1.0:
			flag(
				"the player fell through the seam between two floor brushes (mode %d)" % mode,
				"dropped to y %.2f crossing x = 0" % float(walk["lowest_y"])
			)
		elif bool(walk["stalled"]):
			flag(
				(
					"the player is stopped by the seam between two butted floor brushes (mode %d)"
					% mode
				),
				(
					(
						"Two 10x6 slabs, edge to edge at x = 0, baked and walked across head on. "
						+ "The capsule settled with its feet at %.4f and stopped making progress at "
						+ "x %.2f with nothing above the floor there. A floor of any size is "
						+ "several brushes butted together, so the join is the most common piece of "
						+ "geometry in a level."
					)
					% [feet, body.global_position.x]
				)
			)
		body.queue_free()
		await frame()
		await drop_root(root)


func _can_it_get_through_a_doorway() -> void:
	# The doorway sizes a mapper might draw, against the player that has to fit.
	for gap in [0.8, 1.0, 1.2, 2.0]:
		var root: Node3D = await fresh_root()
		box(root, Vector3(12, 0.3, 12), Vector3(0, -0.15, 0))
		# A wall with a gap in it, built as two pieces, which is how a doorway is
		# made without a subtract brush.
		var side: float = (12.0 - gap) * 0.5
		box(root, Vector3(side, 3, 0.3), Vector3(-(gap * 0.5 + side * 0.5), 1.5, 0))
		box(root, Vector3(side, 3, 0.3), Vector3(gap * 0.5 + side * 0.5, 1.5, 0))
		await frame()
		await root.bake(false, false)
		await frame()
		_hide_drafts(root)
		await frame()
		await frame()
		var body := _player(root, Vector3(0, 1.0, -3))
		await _settle(body)
		var walk: Dictionary = await _walk_to(body, Vector3(0, 1.0, 3))
		var through: bool = body.global_position.z > 0.5
		note(
			"a %.1f-unit doorway (the player is %.2f across)" % [gap, PLAYER_RADIUS * 2.0],
			(
				"got through: %s, reached z %.2f, stalled %s"
				% [through, body.global_position.z, walk["stalled"]]
			)
		)
		if gap >= PLAYER_RADIUS * 2.0 + 0.3 and not through:
			flag(
				"the player cannot walk through a %.1f-unit doorway" % gap,
				(
					(
						"the capsule is %.2f across and the gap is %.1f, so it fits with %.2f units "
						+ "to spare, and the walk stopped at z %.2f."
					)
					% [PLAYER_RADIUS * 2.0, gap, gap - PLAYER_RADIUS * 2.0, body.global_position.z]
				)
			)
		body.queue_free()
		await frame()
		await drop_root(root)


func _can_it_climb_the_stairs_the_plugin_builds() -> void:
	# Three step heights: the plugin's own default, half of it, and a low one --
	# so the report says where the wall is rather than only that there is one.
	var default_rise: float = 0.25
	var root_probe: Node3D = await fresh_root()
	default_rise = float(root_probe.get("bake_connector_stair_height"))
	note("bake_connector_stair_height", default_rise)

	for rise in [default_rise, default_rise * 0.5, 0.05]:
		var root: Node3D = await fresh_root()
		box(root, Vector3(12, 0.3, 12), Vector3(0, -0.15, 0))
		var steps := 8
		for i in steps:
			box(root, Vector3(3, rise, 0.5), Vector3(0, rise * (i + 0.5), 1.0 + i * 0.5))
		await frame()
		await root.bake(false, false)
		await frame()
		_hide_drafts(root)
		await frame()
		await frame()

		var body := _player(root, Vector3(0, 1.0, -1))
		await _settle(body)
		var base: float = body.global_position.y
		var top: float = rise * steps
		var walk: Dictionary = await _walk_to(body, Vector3(0, 1.0, 1.0 + steps * 0.5))
		var climbed: float = body.global_position.y - base
		note(
			"steps of %.3f, rising %.2f in total" % [rise, top],
			(
				"the player rose %.3f, reached z %.2f, stalled %s"
				% [climbed, body.global_position.z, walk["stalled"]]
			)
		)
		if climbed < top * 0.5:
			var label := (
				"the playtest character cannot climb a step of any height"
				if rise <= 0.06
				else "a stock body cannot climb a staircase at %.3f per step" % rise
			)
			flag(
				label,
				(
					(
						"Eight steps of %.3f, rising %.2f in total, baked, walked into head on. The "
						+ "capsule rose %.3f and stalled at the first riser. "
						+ "`_make_playtest_player()` constructs a bare CharacterBody3D and "
						+ "`playtest_fps.gd` never sets `floor_snap_length`, `motion_mode` or any "
						+ "step-up routine -- it applies gravity and calls `move_and_slide()`. "
						+ "Godot's character body has no automatic step-up, so a vertical face is a "
						+ "wall to it whatever its height: the 0.05 row in this scenario is blocked "
						+ "exactly as the 0.25 row is. "
						+ "The plugin ships a Stairs generator, a Spiral Stairs generator and an "
						+ "auto-connector that builds stairs between height layers at "
						+ "`bake_connector_stair_height` (%.2f). None of them can be climbed in "
						+ "Quick Play or in the exported playtest scene. A mapper builds a "
						+ "staircase with the plugin's own tool, presses Play, and walks into it. "
						+ "A `test_move` step-up in `_physics_process` is the usual fix, and it is "
						+ "about fifteen lines: when `is_on_wall()` and the body is grounded, try "
						+ "the same motion raised by a step height and drop back onto the floor."
					)
					% [rise, top, climbed, default_rise]
				)
			)
		body.queue_free()
		await frame()
		await drop_root(root)
