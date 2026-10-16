@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Validate's movement check agrees with what the playtest player can do.
##
## `HFTraversalCheck` (#1046) reads stairs, doorways and ramps out of the brushes
## and measures them against `HFPlayerMetrics.standing()`, the numbers the
## playtest player reads its own size and step from. `walkability` puts a body in
## a level; this puts the same body in levels Validate has just ruled on, and
## compares the two answers. A disagreement either way costs a mapper. A clean
## Validate on a flight the player cannot climb is the defect #1046 was filed
## for, and a warning on something the player walks through is a check crying
## wolf, which the check's own header calls worse than none.
##
## The body is the one `walkability` drives: a capsule the playtest player's size,
## gravity as `playtest_fps.gd` applies it, and the shipped
## `PlaytestFPS.step_body_up` routine each frame. It walks at the player's own
## walk speed. It does not jump or crouch unless a case says so; Validate's check
## is about walking, and the player jumps over two metres.
##
## Every case is built at its own place along X, since a freed root's collision
## lingers in the physics space, and dropped at the end of its loop body.


func id() -> String:
	return "traversal-truth"


func summary() -> String:
	return "whether Validate's stair, ramp and doorway verdicts match what the playtest body can walk"


const PlaytestFPS = preload("res://addons/hammerforge/playtest_fps.gd")
const HFPlayerMetrics = preload("res://addons/hammerforge/hf_player_metrics.gd")
const FIXED_STEP := 1.0 / 60.0
const TRAVERSAL := ["steep_stairs", "small_doorway", "steep_ramp"]
## `LevelRoot.BrushShape.WEDGE`, checked against the brush it makes.
const WEDGE := 4
## `LevelRoot.BrushShape.CUSTOM`, what a generated spiral tread is.
const CUSTOM := 15

var _metrics: Dictionary = {}
var _walk_speed := 6.5
var _slot := 0


func run() -> void:
	_metrics = HFPlayerMetrics.standing()
	var script: Script = PlaytestFPS
	_walk_speed = float(script.get_property_default_value("walk_speed"))
	note("the player Validate measures against", _metrics)
	note("the walk speed the body moves at", _walk_speed)
	await _flat_floor_control()
	await _box_stairs()
	await _generated_stairs()
	await _spiral_stairs()
	await _ramps()
	await _cut_doorways()
	await _piece_doorways()
	await _ledges()


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------


func _next_origin() -> Vector3:
	_slot += 1
	return Vector3(_slot * 60.0, 0.0, 0.0)


func _floor(root: Node3D, at: Vector3, extent: Vector2 = Vector2(16, 16)) -> void:
	box(root, Vector3(extent.x, 0.3, extent.y), at + Vector3(0, -0.15, 0))


## Validate's movement findings for the level as it stands.
func _verdict(root: Node3D) -> Array:
	var report: Dictionary = root.validate_level()
	var out: Array = []
	for finding in report.get("findings", []):
		if finding is Dictionary and str(finding.get("type", "")) in TRAVERSAL:
			out.append(finding)
	return out


func _says(findings: Array) -> String:
	if findings.is_empty():
		return "nothing"
	var parts := PackedStringArray()
	for f in findings:
		parts.append("%s (severity %d): %s" % [f["type"], int(f["severity"]), f["message"]])
	return " | ".join(parts)


func _has(findings: Array, kind: String, severity: int = -1) -> bool:
	for f in findings:
		if str(f["type"]) == kind and (severity < 0 or int(f["severity"]) == severity):
			return true
	return false


func _bake_and_clear(root: Node3D) -> void:
	await frame()
	await root.bake(false, false)
	await frame()
	_hide_drafts(root)
	await frame()
	await frame()


## Drop the live draft brushes, the way a bake with `hide_live` does. Their
## picking collision is on layer 1 and a game never sees it.
func _hide_drafts(root: Node3D) -> void:
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			root.draft_brushes_node.remove_child(child)
			child.queue_free()


## A capsule the size of the playtest player, its feet at `feet`. `height` below
## zero is the standing capsule; the crouched one is `crouch_height`, which is
## what `_set_crouched()` shrinks the real one to.
func _player(root: Node3D, feet: Vector3, height: float = -1.0) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(_metrics["radius"])
	capsule.height = height if height > 0.0 else float(_metrics["height"])
	shape.shape = capsule
	body.add_child(shape)
	root.add_child(body)
	body.global_position = feet + Vector3(0, capsule.height * 0.5 + 0.05, 0)
	# What `playtest_fps.gd` sets in `_ready()`, so the drop onto a step is caught.
	body.floor_snap_length = maxf(body.floor_snap_length, float(_metrics["step_height"]) + 0.05)
	return body


func _feet(body: CharacterBody3D) -> float:
	var capsule := (body.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	return body.global_position.y - capsule.height * 0.5


func _settle(body: CharacterBody3D) -> void:
	var fall := 0.0
	for _i in 24:
		fall = 0.0 if body.is_on_floor() else fall - 9.8 * FIXED_STEP
		body.velocity = Vector3(0, fall, 0)
		body.move_and_slide()
		fall = body.velocity.y
		await frame()


## Walk `body` toward `target` until it arrives or stops making progress, the way
## `walkability` does, at `speed`. Reports the highest its feet stood as well as
## where it ended, since a body that climbs and walks off the far side ends low.
## Stood, not reached: the step-up lifts the body a whole step height for a frame
## before the snap brings it down, so the highest it was ever at overstates every
## climb by up to 0.4 and reads a failed hop at a 0.6 riser as a 0.4 climb.
func _walk_to(
	body: CharacterBody3D, target: Vector3, speed: float, budget: int = 1500
) -> Dictionary:
	var highest := _feet(body)
	var stalled := 0
	var last: Vector3 = body.global_position
	var fall := 0.0
	var arrived := false
	var used := 0
	for _i in budget:
		var to_target: Vector3 = target - body.global_position
		to_target.y = 0.0
		if to_target.length() < 0.25:
			arrived = true
			break
		used += 1
		if body.is_on_floor():
			fall = 0.0
		else:
			fall -= 9.8 * FIXED_STEP
		body.velocity = to_target.normalized() * speed
		body.velocity.y = fall
		PlaytestFPS.step_body_up(
			body,
			Vector3(body.velocity.x, 0.0, body.velocity.z) * FIXED_STEP,
			float(_metrics["step_height"])
		)
		body.move_and_slide()
		fall = body.velocity.y
		if body.is_on_floor():
			highest = maxf(highest, _feet(body))
		if body.global_position.distance_to(last) < 0.002:
			stalled += 1
			if stalled > 40:
				break
		else:
			stalled = 0
		last = body.global_position
		await frame()
	# A step-up can leave the body in the air over the step it is climbing onto,
	# riding down under gravity for a dozen frames, and the walk can arrive before
	# it lands. Let it land before saying where it stood.
	if arrived:
		for _i in 40:
			fall = 0.0 if body.is_on_floor() else fall - 9.8 * FIXED_STEP
			body.velocity = Vector3(0, fall, 0)
			body.move_and_slide()
			fall = body.velocity.y
			if body.is_on_floor():
				highest = maxf(highest, _feet(body))
				break
			await frame()
	return {
		"arrived": arrived,
		"stalled": stalled > 40,
		"highest": highest,
		"reached": body.global_position,
		"steps_used": used,
	}


## Walk a path of points in turn, stopping at the first one it cannot reach.
func _walk_path(body: CharacterBody3D, points: Array, speed: float) -> Dictionary:
	var highest := _feet(body)
	var reached := 0
	for p in points:
		var leg: Dictionary = await _walk_to(body, p, speed, 400)
		highest = maxf(highest, float(leg["highest"]))
		if not bool(leg["arrived"]):
			break
		reached += 1
	return {"highest": highest, "reached": reached, "of": points.size()}


func _free_body(body: CharacterBody3D) -> void:
	var parent := body.get_parent()
	if parent:
		parent.remove_child(body)
	body.queue_free()
	await frame()


# ---------------------------------------------------------------------------
# Control
# ---------------------------------------------------------------------------


## A flat floor first: if the body cannot cross open ground, every other answer
## below is about the harness.
func _flat_floor_control() -> void:
	var o := _next_origin()
	var root: Node3D = await fresh_root()
	_floor(root, o)
	await _bake_and_clear(root)
	var body := _player(root, o + Vector3(0, 0, -5))
	await _settle(body)
	var walk: Dictionary = await _walk_to(body, o + Vector3(0, 0, 5), _walk_speed)
	note(
		"control: a flat floor, 10 m across",
		"arrived %s, feet settled at %.3f" % [walk["arrived"], _feet(body)]
	)
	if not bool(walk["arrived"]):
		flag("the harness cannot cross a flat floor, so nothing below means anything")
	await _free_body(body)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Stairs
# ---------------------------------------------------------------------------


## Solid box steps, each from the floor to its own top, four treads and a 2 m
## landing to a flight, 8 m wide so a walk at an angle stays on it. Walked head
## on, then 30 and 60 degrees off head on, since #1046 found a 0.5 m flight
## climbable only straight on and the finding says so.
func _box_stairs() -> void:
	var step_height := float(_metrics["step_height"])
	var climbed_anyway := PackedStringArray()
	for tread in [0.3, 0.5]:
		for rise in [0.2, 0.35, 0.42, 0.45, 0.5, 0.6]:
			var o := _next_origin()
			var root: Node3D = await fresh_root()
			_floor(root, o, Vector2(20, 16))
			var steps := 5
			for i in steps:
				var h: float = rise * (i + 1)
				var deep: float = 2.0 if i == steps - 1 else tread
				box(root, Vector3(8, h, deep), o + Vector3(0, h * 0.5, tread * i + deep * 0.5))
			var findings := _verdict(root)
			await _bake_and_clear(root)
			var top: float = rise * steps
			var far: float = tread * (steps - 1) + 1.0
			var stood: Array = []
			for degrees in [0.0, 30.0, 60.0]:
				var a := deg_to_rad(degrees)
				var start := o + Vector3(-0.5 * (1.8 + far) * tan(a), 0, -1.8)
				var body := _player(root, start)
				await _settle(body)
				var target := start + Vector3(sin(a), 0, cos(a)) * 20.0
				if degrees == 0.0:
					target = o + Vector3(0, 0, far)
				var walk: Dictionary = await _walk_to(body, target, _walk_speed, 400)
				stood.append(float(walk["highest"]))
				await _free_body(body)
			var up_head: bool = float(stood[0]) >= top - 0.05
			var up_aside: bool = float(stood[1]) >= top - 0.05 and float(stood[2]) >= top - 0.05
			var label := (
				"box stairs, %.2f risers on %.2f treads, %.2f m in all" % [rise, tread, top]
			)
			note(
				label,
				(
					"Validate says %s; the feet stood at %.2f head on, %.2f 30 degrees off, %.2f 60 off"
					% [_says(findings), float(stood[0]), float(stood[1]), float(stood[2])]
				)
			)
			if _has(findings, "steep_stairs") and up_head and up_aside:
				climbed_anyway.append(
					(
						"%.2f on %.2f treads (stood %.2f/%.2f/%.2f of %.2f)"
						% [rise, tread, float(stood[0]), float(stood[1]), float(stood[2]), top]
					)
				)
			else:
				_judge_stairs(label, findings, up_head, rise, step_height, "")
			await drop_root(root)
	if not climbed_anyway.is_empty():
		known(
			1216,
			(
				"Validate warns that risers just over 0.4 m are too steep, and the player "
				+ "climbs them from any angle"
			),
			(
				(
					"Five solid box steps each. steep_stairs says the riser is over the %.2f m "
					+ "the player steps up and that it climbs them only head on, or not at all. "
					+ "The playtest body, driving the shipped `PlaytestFPS.step_body_up`, stood "
					+ "on the top head on, 30 and 60 degrees off for: %s. "
					+ "`step_body_up` lifts the body by exactly `max_step_height`, and "
					+ "`move_and_slide()` then carries the capsule's rounded base over a further "
					+ "lip of up to radius * (1 - cos floor_max_angle), about 0.10 m, because the "
					+ "contact with the nose is floor. So the player climbs about 0.50 m (0.5 "
					+ "risers: head on and 30 degrees off on 0.5 treads, not 60; one step on 0.3 "
					+ "treads; 0.6 never), while `hf_traversal_check.gd` `_steep_flight()` holds "
					+ "every flight to the nominal %.2f. A mapper with 0.42-0.45 risers gets a "
					+ "warning whose own text the playtest contradicts."
				)
				% [step_height, "; ".join(climbed_anyway), step_height]
			)
		)


## A flight Validate says nothing about and the body cannot climb. `cause` is
## what the reader needs to find why Validate did not see it.
func _judge_stairs(
	label: String, findings: Array, up: bool, rise: float, step_height: float, cause: String
) -> void:
	if _has(findings, "steep_stairs") or up:
		return
	var what := "Validate passes %s, and the player cannot climb it" % label
	var detail := (
		(
			"No steep_stairs finding, and the playtest body walking it at %.1f m/s "
			+ "never stood on the top. The riser is %.2f against a %.2f step. %s"
		)
		% [_walk_speed, rise, step_height, cause]
	)
	# Both generators' stairs are #1212; a box flight Validate passed would be new.
	if label.contains("generator"):
		known(1212, what, detail)
	else:
		flag(what, detail)


## The Stairs generator, at its defaults and with a riser over the step, solid
## and open.
func _generated_stairs() -> void:
	var step_height := float(_metrics["step_height"])
	var cases := [
		{"label": "Stairs generator at its defaults", "set": {}},
		{"label": "Stairs generator with 0.6 risers", "set": {"rise": 0.6}},
		{"label": "Stairs generator, Open fill, at its defaults", "set": {"fill": 1}},
		{"label": "Stairs generator, Open fill, 0.6 risers", "set": {"rise": 0.6, "fill": 1}},
		# The same open flight with each slab as thick as a riser, so every tread
		# touches the next: whether it is the gap under a tread that hides it.
		{
			"label": "Stairs generator, Open fill, 0.6 risers on 0.6 slabs",
			"set": {"rise": 0.6, "fill": 1, "tread_thickness": 0.6},
		},
	]
	for entry in cases:
		var settings: Dictionary = HFGeneratorSystem.default_settings("stairs")
		settings.merge(entry["set"], true)
		var rise := float(settings["rise"])
		var steps := int(settings["steps"])
		var tread := float(settings["tread"])
		var open := int(settings["fill"]) == 1
		var thickness := float(settings["tread_thickness"])
		var o := _next_origin()
		var root: Node3D = await fresh_root()
		_floor(root, o)
		# The flight is built about its own middle, climbing +Y as it runs +Z.
		# Lift it so the first step's top is one riser over the floor.
		var lowest: float = (rise - thickness) if open else 0.0
		var highest: float = rise * steps
		var placed := Transform3D(Basis.IDENTITY, o + Vector3(0, (lowest + highest) * 0.5, 0))
		var made = root.create_generator("stairs", settings, placed)
		if made == null or not made.ok:
			flag("%s will not build" % entry["label"], made.message if made else "null")
			await drop_root(root)
			continue
		var shapes := PackedStringArray()
		for b in root.draft_brushes_node.get_children():
			if str(b.get_meta("hf_generator_id", "")) != "":
				shapes.append(str(int(b.shape)))
		var length: float = tread * steps
		# A landing level with the top step, so the walk has somewhere to stand. Its
		# riser from the top step is nothing, so it is not a step to Validate.
		box(
			root,
			Vector3(3, rise * steps, 2),
			o + Vector3(0, rise * steps * 0.5, length * 0.5 + 1.0)
		)
		var findings := _verdict(root)
		await _bake_and_clear(root)
		var body := _player(root, o + Vector3(0, 0, -length * 0.5 - 2.0))
		await _settle(body)
		var walk: Dictionary = await _walk_to(
			body, o + Vector3(0, 0, length * 0.5 + 1.0), _walk_speed
		)
		await _free_body(body)
		var top: float = rise * steps
		var up: bool = float(walk["highest"]) >= top - 0.05
		note(
			entry["label"],
			(
				"%d pieces of shape %s; Validate says %s; head on the feet stood at %.2f of %.2f"
				% [shapes.size(), ",".join(shapes), _says(findings), float(walk["highest"]), top]
			)
		)
		var cause := ""
		if open and thickness < rise - 0.05:
			cause = (
				(
					"Every piece is a BOX, so the check reads them, but each %.2f slab's "
					+ "underside is %.2f over the top of the one before, and "
					+ "`hf_traversal_check.gd` `_step()` (and `_turned_step()`) refuse a "
					+ "step whose box starts more than TOUCH (0.05) over the last one's top: "
					+ "`b.position.y > a.end.y + TOUCH`. The same flight with 0.6 slabs, so "
					+ "each tread touches the next, does report steep_stairs. Open fill is "
					+ "the generator's own option; the player meets the slab's front face "
					+ "as a riser whatever is under it, since it cannot walk under a gap "
					+ "of %.2f."
				)
				% [thickness, rise - thickness, rise - thickness]
			)
		_judge_stairs(entry["label"].to_lower(), findings, up, rise, step_height, cause)
		await drop_root(root)


## The Spiral Stairs generator, at its defaults and with a riser over the step.
## Walked tread by tread round the middle of the treads.
func _spiral_stairs() -> void:
	var step_height := float(_metrics["step_height"])
	# Defaults; a riser over the step; and that riser on treads as thick as it, so
	# each touches the next and only the treads' shape stands between the flight
	# and the check.
	for change in [{}, {"rise": 0.6}, {"rise": 0.6, "tread_thickness": 0.6}]:
		var settings: Dictionary = HFGeneratorSystem.default_settings("spiral_stairs")
		settings.merge(change, true)
		var rise := float(settings["rise"])
		var steps := int(settings["steps"])
		var turn := deg_to_rad(float(settings["degrees_per_step"]))
		var radius: float = (
			(float(settings["outer_radius"]) + float(settings["inner_radius"])) * 0.5
		)
		var o := _next_origin()
		var root: Node3D = await fresh_root()
		_floor(root, o)
		# With its post, the flight is centred between the floor and its top.
		var placed := Transform3D(Basis.IDENTITY, o + Vector3(0, rise * steps * 0.5, 0))
		var made = root.create_generator("spiral_stairs", settings, placed)
		var label := (
			"Spiral Stairs generator, %.2f risers on %.2f treads"
			% [rise, float(settings["tread_thickness"])]
		)
		if made == null or not made.ok:
			flag("%s will not build" % label, made.message if made else "null")
			await drop_root(root)
			continue
		var shapes := PackedStringArray()
		for b in root.draft_brushes_node.get_children():
			if str(b.get_meta("hf_generator_id", "")) != "":
				shapes.append(str(int(b.shape)))
		var findings := _verdict(root)
		await _bake_and_clear(root)
		var points: Array = []
		for i in steps:
			var a: float = turn * (i + 0.5)
			points.append(o + Vector3(radius * cos(a), 0, radius * sin(a)))
		var before: float = -turn * 1.5
		var body := _player(root, o + Vector3(radius * cos(before), 0, radius * sin(before)))
		await _settle(body)
		var walk: Dictionary = await _walk_path(body, points, _walk_speed)
		await _free_body(body)
		var top: float = rise * steps
		var up: bool = float(walk["highest"]) >= top - 0.05
		note(
			label,
			(
				"%d pieces of shape %s; Validate says %s; the feet stood at %.2f of %.2f, %d of %d treads"
				% [
					shapes.size(),
					",".join(shapes),
					_says(findings),
					float(walk["highest"]),
					top,
					int(walk["reached"]),
					int(walk["of"]),
				]
			)
		)
		var cause := (
			(
				"Every tread is a CUSTOM brush (shape %s), and `HFTraversalCheck.findings()` "
				% str(CUSTOM)
			)
			+ "reads only BOX and WEDGE brushes into the stairs and ramps it measures, so "
			+ "the Spiral Stairs generator's output is never seen at any riser. "
		)
		if float(settings["tread_thickness"]) < rise - 0.05:
			cause += (
				(
					"Its treads also float, %.2f thick on %.2f risers, which `_step()` refuses "
					% [float(settings["tread_thickness"]), rise]
				)
				+ "for the reason the Open stairs case gives."
			)
		else:
			cause += (
				"Here each tread is as thick as a riser and touches the next, so the shape "
				+ "is all that hides it."
			)
		_judge_stairs(label.to_lower(), findings, up, rise, step_height, cause)
		await drop_root(root)


# ---------------------------------------------------------------------------
# Ramps
# ---------------------------------------------------------------------------


## Wedges 1.5 m high at four slopes, with a landing box at the top and without.
## The header says a wedge without a landing is a roof or a buttress, so only
## the landed ones are held to the walk.
func _ramps() -> void:
	var steepest := float(_metrics["max_slope_degrees"])
	for degrees in [30.0, 40.0, 50.0, 60.0]:
		for landed in [true, false]:
			var o := _next_origin()
			var root: Node3D = await fresh_root()
			_floor(root, o, Vector2(24, 12))
			var h := 1.5
			var run: float = h / tan(deg_to_rad(degrees))
			var wedge = root.create_brush_from_info(
				{"shape": WEDGE, "size": Vector3(run, h, 3.0), "center": o + Vector3(0, h * 0.5, 0)}
			)
			if int(wedge.shape) != WEDGE:
				flag("the harness asked for a wedge and got shape %d" % int(wedge.shape))
			# A wedge's high side is its -X side.
			var high_x: float = o.x - run * 0.5
			if landed:
				box(root, Vector3(3, h, 3), Vector3(high_x - 1.5, h * 0.5, o.z))
			var findings := _verdict(root)
			await _bake_and_clear(root)
			var body := _player(root, Vector3(o.x + run * 0.5 + 2.0, 0, o.z))
			await _settle(body)
			var goal: float = (high_x - 1.5) if landed else (high_x + 0.3)
			var walk: Dictionary = await _walk_to(body, Vector3(goal, 0, o.z), _walk_speed, 600)
			await _free_body(body)
			var up: bool = float(walk["highest"]) >= h - 0.05
			var label := (
				"a %.0f degree wedge ramp %s"
				% [degrees, "onto a landing" if landed else "with nothing at its top"]
			)
			note(
				label,
				(
					"Validate says %s; the feet stood at %.2f of %.2f"
					% [_says(findings), float(walk["highest"]), h]
				)
			)
			var warned := _has(findings, "steep_ramp")
			if landed and not warned and not up:
				flag(
					"Validate passes %s, and the player cannot walk up it" % label,
					(
						(
							"no steep_ramp finding; the floor angle is %.0f and the body's feet "
							+ "stopped at %.2f of %.2f"
						)
						% [steepest, float(walk["highest"]), h]
					)
				)
			elif landed and warned and up:
				flag(
					"Validate warns about %s, and the player walks up it" % label,
					"the body's feet reached %.2f of %.2f" % [float(walk["highest"]), h]
				)
			await drop_root(root)


# ---------------------------------------------------------------------------
# Doorways
# ---------------------------------------------------------------------------


## A subtract brush through an 8 m wall, from the floor, at widths and heights
## round the player's. The last two cut a gap through a wall lower than the
## player, the cutter running out of the wall's top: an opening with nothing over
## it, the way a gateway in a garden wall or a gap in a parapet is made.
func _cut_doorways() -> void:
	var standing := float(_metrics["height"])
	var cases := [
		[0.6, 2.2, 3.0],
		[0.7, 2.2, 3.0],
		[0.72, 2.2, 3.0],
		[0.8, 2.2, 3.0],
		[1.2, 2.2, 3.0],
		[1.2, 1.7, 3.0],
		[1.2, 1.62, 3.0],
		[1.2, 1.4, 3.0],
		[1.0, 2.2, 1.2],
		[1.0, 2.2, 0.8],
	]
	for c in cases:
		var width: float = c[0]
		var height: float = c[1]
		var wall: float = c[2]
		var o := _next_origin()
		var root: Node3D = await fresh_root()
		_floor(root, o)
		box(root, Vector3(8, wall, 0.3), o + Vector3(0, wall * 0.5, 0))
		var cutter = (
			root
			. create_brush_from_info(
				{
					"shape": 0,
					"size": Vector3(width, height, 0.7),
					"center": o + Vector3(0, height * 0.5, 0),
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
				}
			)
		)
		if int(cutter.operation) != CSGShape3D.OPERATION_SUBTRACTION:
			flag("the harness asked for a cutter and got operation %d" % int(cutter.operation))
		var findings := _verdict(root)
		await _bake_and_clear(root)
		var body := _player(root, o + Vector3(0, 0, -3))
		await _settle(body)
		await _walk_to(body, o + Vector3(0, 0, 3), _walk_speed, 600)
		var through: bool = body.global_position.z > o.z + 0.6
		await _free_body(body)
		var crouched := through
		if not through:
			body = _player(root, o + Vector3(0, 0, -3), float(_metrics["crouch_height"]))
			await _settle(body)
			await _walk_to(body, o + Vector3(0, 0, 3), _walk_speed, 600)
			crouched = body.global_position.z > o.z + 0.6
			await _free_body(body)
		var label := (
			"a %.2f by %.2f cut through a %.1f m wall%s"
			% [
				width,
				height,
				wall,
				" (the cutter runs out of the wall's top)" if height > wall else ""
			]
		)
		note(
			label,
			(
				"Validate says %s; standing got through %s, crouched %s"
				% [_says(findings), through, crouched]
			)
		)
		var warning := _has(findings, "small_doorway", 1)
		var crouch_info := _has(findings, "small_doorway", 0)
		# Nothing over the opening: the cutter runs out of the wall's top.
		var open_above: bool = height > wall
		if findings.is_empty() and not through:
			flag(
				"Validate passes %s, and the player cannot get through it standing" % label,
				"no small_doorway finding; standing %s, crouched %s" % [through, crouched]
			)
		elif open_above and (warning or crouch_info) and through:
			known(
				1215,
				(
					(
						"Validate calls a gap through a %.1f m wall a doorway %s, and the player "
						+ "walks through it standing"
					)
					% [wall, "too low even to crouch through" if warning else "to crouch through"]
				),
				(
					(
						"An 8 m wall %.1f m high, and a %.2f by %.2f cutter through it from the "
						+ "floor, running %.2f m out of the wall's top, so nothing at all is over "
						+ "the opening. Validate says: %s. The %.2f m body walked through "
						+ "standing. `hf_traversal_check.gd` `_doorways()` takes the opening's "
						+ "height as `minf(c.end.y, w.end.y) - bottom`, so when the cut runs "
						+ "out of the top the wall's own height is read as the headroom. A gap "
						+ "cut through a garden wall, a parapet or a balcony rail lower than the "
						+ "player is reported as a doorway it has to crouch through, and under "
						+ "0.9 m as a warning that it cannot get through at all."
					)
					% [wall, width, height, height - wall, _says(findings), standing]
				)
			)
		elif warning and crouched:
			flag(
				"Validate warns that %s is too small, and the player gets through it" % label,
				(
					"the finding is %s; the body got through standing %s, crouched %s"
					% [_says(findings), through, crouched]
				)
			)
		elif crouch_info and through:
			flag(
				(
					"Validate says the player must crouch through %s, and it walks through standing"
					% label
				),
				(
					"the finding is %s; the %.2f m body walked through standing"
					% [_says(findings), standing]
				)
			)
		elif crouch_info and not crouched:
			flag(
				"Validate says the player can crouch through %s, and it cannot" % label,
				"the finding is %s" % _says(findings)
			)
		await drop_root(root)


## A doorway made of two jambs and a lintel, too narrow and too low. The header
## says a doorway is a cutter, so Validate is not expected to see these; recorded
## so the next reader knows what the player meets.
func _piece_doorways() -> void:
	for c in [[0.6, 2.2], [1.2, 1.4]]:
		var gap: float = c[0]
		var opening: float = c[1]
		var o := _next_origin()
		var root: Node3D = await fresh_root()
		_floor(root, o)
		for side in [-1.0, 1.0]:
			box(root, Vector3(2, 3, 0.3), o + Vector3(side * (gap * 0.5 + 1.0), 1.5, 0))
		box(
			root,
			Vector3(gap, 3.0 - opening, 0.3),
			o + Vector3(0, opening + (3.0 - opening) * 0.5, 0)
		)
		var findings := _verdict(root)
		await _bake_and_clear(root)
		var body := _player(root, o + Vector3(0, 0, -3))
		await _settle(body)
		await _walk_to(body, o + Vector3(0, 0, 3), _walk_speed, 600)
		var through: bool = body.global_position.z > o.z + 0.6
		await _free_body(body)
		note(
			"a %.2f by %.2f doorway of two jambs and a lintel" % [gap, opening],
			"Validate says %s; standing got through %s" % [_says(findings), through]
		)
		await drop_root(root)


# ---------------------------------------------------------------------------
# Ledges
# ---------------------------------------------------------------------------


## One box, and two, each 0.6 higher than what is before it. The header says one
## box beside another is a ledge on purpose; recorded, not held to the walk.
func _ledges() -> void:
	for count in [1, 2]:
		var o := _next_origin()
		var root: Node3D = await fresh_root()
		_floor(root, o)
		for i in count:
			var h: float = 0.6 * (i + 1)
			box(root, Vector3(4, h, 1.0), o + Vector3(0, h * 0.5, 0.5 + i))
		var findings := _verdict(root)
		await _bake_and_clear(root)
		var body := _player(root, o + Vector3(0, 0, -2))
		await _settle(body)
		var walk: Dictionary = await _walk_to(
			body, o + Vector3(0, 0, count - 0.2), _walk_speed, 600
		)
		await _free_body(body)
		note(
			"%d box%s 0.6 m a step" % [count, "" if count == 1 else "es"],
			(
				"Validate says %s; the feet stood at %.2f of %.2f"
				% [_says(findings), float(walk["highest"]), 0.6 * count]
			)
		)
		await drop_root(root)
