extends RefCounted
## Stairs, doorways and ramps built from brushes, measured against the playtest
## player (#1046).
##
## Validate's movement checks measured only the connectors the bake builds between
## paint layers, and only against the navmesh agent. A flight of brush stairs with
## 0.5 m risers, over the player's 0.4 m step, passed clean. These read the level
## the way a mapper builds it, and are narrow on purpose, since a check that cries
## wolf is worse than none:
##
## - Stairs are a run of three or more touching boxes, each a similar step higher
##   than the last in one direction. One box beside another is a ledge, and a rise
##   over a metre is a wall.
## - A doorway is a cutter right through a wall that reaches down to its foot. A
##   cut that starts higher up is a window.
## - A ramp is a wedge with a flat landing at its top, so a steep roof or buttress
##   is not one.
##
## Each finding names the two brushes it is about, as a micro-gap does.
##
## Boxes are measured in the turn about the vertical they share, where each is
## square and its box is the brush, so a flight, a wall or a landing turned as a
## group to any angle reads as it would square to the world (#1087). Boxes turned
## different ways have no such frame, so they are compared from above by their
## outlines, and a flight of them is followed step by step as long as it does
## not fold back: a spiral of boxes reads as stairs (#1095). A box tipped off
## upright is left out, since its sides are not walls nor its top a floor.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBakeSystemType = preload("hf_bake_system.gd")
const HFPlayerMetrics = preload("../hf_player_metrics.gd")

## Faces this close count as touching.
const TOUCH := 0.05
## Turns this close, in radians, are one turn: about 2.6 degrees, the lean a box
## square to the world has always been allowed (0.999 along a unit axis).
const SAME_TURN := 0.0447
## A rise over this between neighbouring boxes is a wall or a ledge, not a step.
const MAX_RISER := 1.0
const MIN_RISER := 0.05
## Risers within this ratio of each other are one flight.
const SAME_RISE := 1.3
## Boxes a flight needs before it is stairs.
const MIN_FLIGHT := 3


## The findings for `brush_nodes`: `{type, severity, message, node, other_node}`.
static func findings(root: Node, brush_nodes: Array) -> Array:
	var player := HFPlayerMetrics.standing()
	# Boxes by the turn they stand square in, the world's first. Each keeps its box
	# in that turn, and its box in the world for finding the cutters near it.
	var frames: Array = [{"turn": 0.0, "basis": Basis.IDENTITY, "boxes": []}]
	var wedges: Array = []
	var cutters: Array = []
	for node in brush_nodes:
		if not (node is DraftBrush) or not is_instance_valid(node):
			continue
		var brush := node as DraftBrush
		# Auto-fix can take a brush out of the level before this runs.
		if not brush.is_inside_tree() or root.is_entity_node(brush):
			continue
		if str(brush.get_meta("brush_entity_class", "")).begins_with("trigger_"):
			continue
		var box := HFBakeSystemType.brush_world_aabb(brush, brush.global_transform)
		if not (box.position.is_finite() and box.size.is_finite()):
			continue
		var entry := {"node": brush, "box": box}
		if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			cutters.append(entry)
		elif brush.shape == DraftBrush.BrushShape.WEDGE:
			wedges.append(entry)
		elif brush.shape == DraftBrush.BrushShape.BOX:
			var turn := _turn(brush)
			if turn < 0.0:
				continue
			var frame := _frame_of(frames, turn)
			if frame.is_empty():
				frame = {"turn": turn, "basis": Basis(Vector3.UP, turn), "boxes": []}
				frames.append(frame)
			var basis: Basis = frame["basis"]
			frame["boxes"].append({"node": brush, "box": _box_in(brush, basis), "world": box})
	var out: Array = []
	for frame in frames:
		out.append_array(_stairs(frame["boxes"], player))
	out.append_array(_turned_stairs(frames, player))
	for frame in frames:
		out.append_array(_doorways(frame, cutters, player))
	out.append_array(_ramps(wedges, frames, player))
	return out


## How far `brush` is turned about the vertical, short of a quarter turn, or -1
## when it is tipped off upright.
static func _turn(brush: Node3D) -> float:
	var basis := brush.global_transform.basis.orthonormalized()
	var columns: Array[Vector3] = [basis.x, basis.y, basis.z]
	var up := 0
	for i: int in [1, 2]:
		if absf(columns[i].y) > absf(columns[up].y):
			up = i
	if absf(columns[up].y) < 0.999:
		return -1.0
	var across: Vector3 = columns[(up + 1) % 3]
	return fposmod(atan2(across.x, across.z), PI * 0.5)


## The frame turned within `SAME_TURN` of `turn`, a quarter turn either way, or {}.
static func _frame_of(frames: Array, turn: float) -> Dictionary:
	for frame in frames:
		var apart := fposmod(turn - float(frame["turn"]), PI * 0.5)
		if minf(apart, PI * 0.5 - apart) <= SAME_TURN:
			return frame
	return {}


## The box round `brush` in a frame turned by `basis`. For a brush square in it,
## the brush itself.
static func _box_in(brush: DraftBrush, basis: Basis) -> AABB:
	var to_frame := Transform3D(basis.transposed(), Vector3.ZERO)
	return HFBakeSystemType.brush_world_aabb(brush, to_frame * brush.global_transform)


# ---------------------------------------------------------------------------
# Stairs
# ---------------------------------------------------------------------------


static func _stairs(boxes: Array, player: Dictionary) -> Array:
	# Each step up from one box to a neighbour: {from, to, rise, axis, sign}.
	var ups: Dictionary = {}  # index -> Array of steps from it
	var has_below: Dictionary = {}  # "index|axis|sign" -> true
	var order := range(boxes.size())
	order.sort_custom(func(a, b): return boxes[a]["box"].position.x < boxes[b]["box"].position.x)
	for n in order.size():
		var i: int = order[n]
		var a: AABB = boxes[i]["box"]
		for m in range(n + 1, order.size()):
			var j: int = order[m]
			var b: AABB = boxes[j]["box"]
			if b.position.x > a.end.x + TOUCH:
				break
			for pair in [[i, j], [j, i]]:
				var step := _step(boxes, pair[0], pair[1], player)
				if not step.is_empty():
					if not ups.has(pair[0]):
						ups[pair[0]] = []
					ups[pair[0]].append(step)
					has_below["%d|%d|%d" % [pair[1], step["axis"], step["sign"]]] = true
	var out: Array = []
	for start in ups:
		for first in ups[start]:
			if has_below.has("%d|%d|%d" % [start, first["axis"], first["sign"]]):
				continue  # the middle of a flight, counted from its foot
			var flight := [start]
			var rises: Array = []
			var step: Dictionary = first
			while not step.is_empty():
				flight.append(step["to"])
				rises.append(step["rise"])
				step = _next_step(ups, step, rises[0])
			if flight.size() < MIN_FLIGHT:
				continue
			var finding := _steep_flight(
				boxes[flight[0]]["node"], boxes[flight[-1]]["node"], rises, player
			)
			if not finding.is_empty():
				out.append(finding)
	return out


## The finding for a flight from `low` up to `high` by `rises`, or {} when the
## player walks up every step.
static func _steep_flight(
	low: DraftBrush, high: DraftBrush, rises: Array, player: Dictionary
) -> Dictionary:
	var tallest: float = rises.max()
	if tallest <= float(player["step_height"]) + 0.005:
		return {}
	var message := (
		(
			"Stairs from %s to %s rise %.2f m a step, over the %.2f m the player "
			+ "steps up; it climbs them only head on, or not at all"
		)
		% [low.name, high.name, tallest, float(player["step_height"])]
	)
	return _finding("steep_stairs", 1, message, low, high)


## The step from box `i` up to box `j`, or {}: `j` stands beside `i` with a face
## on one of `i`'s, overlapping it by a player's width, and its top a riser higher.
static func _step(boxes: Array, i: int, j: int, player: Dictionary) -> Dictionary:
	var a: AABB = boxes[i]["box"]
	var b: AABB = boxes[j]["box"]
	var rise := b.end.y - a.end.y
	if rise < MIN_RISER or rise > MAX_RISER or b.position.y > a.end.y + TOUCH:
		return {}
	var width := 2.0 * float(player["radius"])
	for axis: int in [0, 2]:
		var other := 2 - axis
		var overlap := minf(a.end[other], b.end[other]) - maxf(a.position[other], b.position[other])
		if overlap < width:
			continue
		if absf(b.position[axis] - a.end[axis]) <= TOUCH:
			return {"from": i, "to": j, "rise": rise, "axis": axis, "sign": 1}
		if absf(a.position[axis] - b.end[axis]) <= TOUCH:
			return {"from": i, "to": j, "rise": rise, "axis": axis, "sign": -1}
	return {}


## The next step of a flight: up from where `step` landed, the same way, by a
## similar riser.
static func _next_step(ups: Dictionary, step: Dictionary, first_rise: float) -> Dictionary:
	for candidate in ups.get(step["to"], []):
		if candidate["axis"] != step["axis"] or candidate["sign"] != step["sign"]:
			continue
		var ratio := maxf(candidate["rise"], first_rise) / minf(candidate["rise"], first_rise)
		if ratio <= SAME_RISE:
			return candidate
	return {}


# ---------------------------------------------------------------------------
# Stairs of boxes turned each their own way
# ---------------------------------------------------------------------------


## Flights that step from one turn to another, as a spiral of boxes does (#1095).
## Only steps between turns are taken here, and `_stairs` takes only steps within
## one, so no flight is counted by both.
static func _turned_stairs(frames: Array, player: Dictionary) -> Array:
	var turns := 0
	for frame in frames:
		turns += 0 if frame["boxes"].is_empty() else 1
	if turns < 2:
		return []  # every box shares one turn, as in most levels
	# Every upright box with its outline seen from above, the outline grown by a
	# touch, and its middle.
	var boxes: Array = []
	for f in frames.size():
		var basis: Basis = frames[f]["basis"]
		for entry in frames[f]["boxes"]:
			var box: AABB = entry["box"]
			var middle := basis * box.get_center()
			var seen := {
				"node": entry["node"],
				"world": entry["world"],
				"frame": f,
				"outline": _outline(box, basis, 0.0),
				"near": _outline(box, basis, TOUCH),
				"middle": Vector2(middle.x, middle.z),
			}
			boxes.append(seen)
	var width := 2.0 * float(player["radius"])
	var reach: Dictionary = {}  # index -> Array of steps from it
	var pairs: Dictionary = {}  # "from|to" -> true
	var order := range(boxes.size())
	order.sort_custom(
		func(a, b): return boxes[a]["world"].position.x < boxes[b]["world"].position.x
	)
	for n in order.size():
		var i: int = order[n]
		var a: AABB = boxes[i]["world"]
		for m in range(n + 1, order.size()):
			var j: int = order[m]
			var b: AABB = boxes[j]["world"]
			if b.position.x > a.end.x + TOUCH:
				break
			if boxes[i]["frame"] == boxes[j]["frame"]:
				continue
			if b.position.z > a.end.z + TOUCH or a.position.z > b.end.z + TOUCH:
				continue
			for pair in [[i, j], [j, i]]:
				var found := _turned_step(boxes, pair[0], pair[1], width)
				if found.is_empty():
					continue
				if not reach.has(pair[0]):
					reach[pair[0]] = []
				reach[pair[0]].append(found)
				pairs["%d|%d" % pair] = true
	# A box two treads up a tight spiral can reach past the one between. The
	# player meets that one first, so the step past it is not a step.
	var ups: Dictionary = {}  # index -> Array of steps from it
	for low in reach:
		for found in reach[low]:
			var past := false
			for other in reach[low]:
				past = past or pairs.has("%d|%d" % [other["to"], found["to"]])
			if past:
				continue
			if not ups.has(low):
				ups[low] = []
			ups[low].append(found)
	# Each flight from each step, then only those that start at their foot.
	var flights: Array = []
	var inside: Dictionary = {}  # "from|to" of each step past a flight's first
	for start in ups:
		for first in ups[start]:
			var flight := [start]
			var rises: Array = []
			var step: Dictionary = first
			while not step.is_empty():
				flight.append(step["to"])
				rises.append(step["rise"])
				step = _next_turned_step(ups, step, rises[0])
			if flight.size() < MIN_FLIGHT:
				continue
			for k in range(1, flight.size() - 1):
				inside["%d|%d" % [flight[k], flight[k + 1]]] = true
			flights.append({"flight": flight, "rises": rises})
	var out: Array = []
	for each in flights:
		var flight: Array = each["flight"]
		if inside.has("%d|%d" % [flight[0], flight[1]]):
			continue  # the middle of a flight, counted from its foot
		var finding := _steep_flight(
			boxes[flight[0]]["node"], boxes[flight[-1]]["node"], each["rises"], player
		)
		if not finding.is_empty():
			out.append(finding)
	return out


## The corners of `box`, square in the turn `basis`, seen from above, with its
## sides pushed out by `grow`.
static func _outline(box: AABB, basis: Basis, grow: float) -> PackedVector2Array:
	var low := box.position - Vector3(grow, 0.0, grow)
	var high := box.end + Vector3(grow, 0.0, grow)
	var out := PackedVector2Array()
	for corner: Vector2 in [
		Vector2(low.x, low.z),
		Vector2(high.x, low.z),
		Vector2(high.x, high.z),
		Vector2(low.x, high.z)
	]:
		var world := basis * Vector3(corner.x, 0.0, corner.y)
		out.append(Vector2(world.x, world.z))
	return out


## The step from box `i` up to box `j` turned another way, or {}. Seen from above,
## `j` stands beside `i`, not on it as a crate stands on a floor: neither's middle
## is inside the other. They meet across a player's width, and its top is a riser
## higher.
static func _turned_step(boxes: Array, i: int, j: int, width: float) -> Dictionary:
	var a: AABB = boxes[i]["world"]
	var b: AABB = boxes[j]["world"]
	var rise := b.end.y - a.end.y
	if rise < MIN_RISER or rise > MAX_RISER or b.position.y > a.end.y + TOUCH:
		return {}
	var here: Vector2 = boxes[i]["middle"]
	var there: Vector2 = boxes[j]["middle"]
	if (
		Geometry2D.is_point_in_polygon(there, boxes[i]["outline"])
		or Geometry2D.is_point_in_polygon(here, boxes[j]["outline"])
	):
		return {}
	var met := Geometry2D.intersect_polygons(boxes[i]["near"], boxes[j]["outline"])
	if met.is_empty() or _across(met[0]) < width:
		return {}
	return {"from": i, "to": j, "rise": rise, "way": (there - here).normalized()}


## The widest a polygon is: the longest line between two of its corners.
static func _across(polygon: PackedVector2Array) -> float:
	var widest := 0.0
	for p in polygon.size():
		for q in range(p + 1, polygon.size()):
			widest = maxf(widest, polygon[p].distance_to(polygon[q]))
	return widest


## The next step of a turning flight: up from where `step` landed by a similar
## riser, without folding back the way it came.
static func _next_turned_step(ups: Dictionary, step: Dictionary, first_rise: float) -> Dictionary:
	var way: Vector2 = step["way"]
	for candidate in ups.get(step["to"], []):
		if way.dot(candidate["way"]) <= 0.0:
			continue
		var ratio := maxf(candidate["rise"], first_rise) / minf(candidate["rise"], first_rise)
		if ratio <= SAME_RISE:
			return candidate
	return {}


# ---------------------------------------------------------------------------
# Doorways
# ---------------------------------------------------------------------------


## The doorways through the walls of `frame`, each cutter measured in the wall's
## turn.
static func _doorways(frame: Dictionary, cutters: Array, player: Dictionary) -> Array:
	var out: Array = []
	var width_needed := 2.0 * float(player["radius"])
	var standing := float(player["height"])
	var crouched := float(player["crouch_height"])
	for cut in cutters:
		var reach: AABB = cut["box"]
		for wall in frame["boxes"]:
			if not reach.intersects(wall["world"]):
				continue
			var c := _box_in(cut["node"], frame["basis"])
			var w: AABB = wall["box"]
			if not c.intersects(w):
				continue
			# Through the wall's thin way, and the wall upright.
			var thin := 0 if w.size.x <= w.size.z else 2
			var along := 2 - thin
			if w.size.y < w.size[thin] or w.size[along] < w.size[thin]:
				continue
			if c.position[thin] > w.position[thin] + TOUCH or c.end[thin] < w.end[thin] - TOUCH:
				continue
			var bottom := maxf(c.position.y, w.position.y)
			if bottom > w.position.y + float(player["step_height"]):
				continue  # a window
			var height := minf(c.end.y, w.end.y) - bottom
			var width := (
				minf(c.end[along], w.end[along]) - maxf(c.position[along], w.position[along])
			)
			if width >= width_needed and height >= standing:
				continue
			var severity := 1
			var why := ""
			if width < width_needed:
				why = "%.2f m wide, and the player is %.2f m across" % [width, width_needed]
			elif height < crouched:
				why = ("%.2f m high, under the player even crouched at %.2f m" % [height, crouched])
			else:
				severity = 0
				why = (
					"%.2f m high, so the player has to crouch (%.2f m standing)"
					% [height, standing]
				)
			var cutter: DraftBrush = cut["node"]
			var through: DraftBrush = wall["node"]
			var message := "Doorway %s through %s is %s" % [cutter.name, through.name, why]
			out.append(_finding("small_doorway", severity, message, cutter, through))
	return out


# ---------------------------------------------------------------------------
# Ramps
# ---------------------------------------------------------------------------


static func _ramps(wedges: Array, frames: Array, player: Dictionary) -> Array:
	var out: Array = []
	var steepest := float(player["max_slope_degrees"])
	for ramp in wedges:
		var brush: DraftBrush = ramp["node"]
		var slope := _slope_normal(brush)
		if slope == Vector3.ZERO:
			continue
		var degrees := rad_to_deg(acos(clampf(slope.y, -1.0, 1.0)))
		if degrees <= steepest + 0.5 or degrees >= 89.0:
			continue
		# Its landing is a box turned its way. A wedge turned like no box, or tipped,
		# is held to the world's boxes, as every wedge was before #1087.
		var turn := _turn(brush)
		var frame := {} if turn < 0.0 else _frame_of(frames, turn)
		if frame.is_empty():
			frame = frames[0]
		var basis: Basis = frame["basis"]
		var landing: Variant = _landing(
			_box_in(brush, basis), basis.transposed() * slope, frame["boxes"]
		)
		if landing == null:
			continue
		var message := (
			"Ramp %s climbs at %.0f degrees, steeper than the %.0f the player walks up, onto %s"
			% [brush.name, degrees, steepest, (landing as Node).name]
		)
		out.append(_finding("steep_ramp", 1, message, brush, landing))
	return out


## The world normal of a wedge's sloped face, facing up, or zero.
static func _slope_normal(brush: DraftBrush) -> Vector3:
	var to_world := brush.global_transform.basis.inverse().transposed()
	for face in brush.get_faces():
		if face == null:
			continue
		var normal: Vector3 = (to_world * face.normal).normalized()
		if normal.y > 0.01 and normal.y < 0.999 and Vector2(normal.x, normal.z).length() > 0.01:
			return normal
	return Vector3.ZERO


## A box whose top is level with the ramp's top and whose side meets the ramp's
## high end: where the slope leads. The slope climbs against its normal.
static func _landing(ramp: AABB, slope: Vector3, boxes: Array) -> Variant:
	var climb := Vector2(-slope.x, -slope.z)
	var axis := 0 if absf(climb.x) >= absf(climb.y) else 2
	var toward: float = climb.x if axis == 0 else climb.y
	var high_side: float = ramp.position[axis] if toward < 0.0 else ramp.end[axis]
	for entry in boxes:
		var box: AABB = entry["box"]
		if absf(box.end.y - ramp.end.y) > TOUCH:
			continue
		var face: float = box.end[axis] if toward < 0.0 else box.position[axis]
		if absf(face - high_side) > TOUCH:
			continue
		var other := 2 - axis
		if (
			minf(box.end[other], ramp.end[other]) - maxf(box.position[other], ramp.position[other])
			> 0.0
		):
			return entry["node"]
	return null


static func _finding(
	kind: String, severity: int, message: String, node: Node, other: Node
) -> Dictionary:
	return {
		"type": kind, "severity": severity, "message": message, "node": node, "other_node": other
	}
