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

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBakeSystemType = preload("hf_bake_system.gd")
const HFPlayerMetrics = preload("../hf_player_metrics.gd")

## Faces this close count as touching.
const TOUCH := 0.05
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
	var boxes: Array = []
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
		elif brush.shape == DraftBrush.BrushShape.BOX and _square(brush):
			boxes.append(entry)
	var out: Array = []
	out.append_array(_stairs(boxes, player))
	out.append_array(_doorways(boxes, cutters, player))
	out.append_array(_ramps(wedges, boxes, player))
	return out


## Turned only by quarter turns, so its box is the brush.
static func _square(brush: Node3D) -> bool:
	var basis := brush.global_transform.basis.orthonormalized()
	for column in [basis.x, basis.y, basis.z]:
		var c: Vector3 = column
		if maxf(absf(c.x), maxf(absf(c.y), absf(c.z))) < 0.999:
			return false
	return true


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
			var tallest: float = rises.max()
			if tallest <= float(player["step_height"]) + 0.005:
				continue
			var low: DraftBrush = boxes[flight[0]]["node"]
			var high: DraftBrush = boxes[flight[-1]]["node"]
			var message := (
				(
					"Stairs from %s to %s rise %.2f m a step, over the %.2f m the player "
					+ "steps up; it climbs them only head on, or not at all"
				)
				% [low.name, high.name, tallest, float(player["step_height"])]
			)
			out.append(_finding("steep_stairs", 1, message, low, high))
	return out


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
# Doorways
# ---------------------------------------------------------------------------


static func _doorways(boxes: Array, cutters: Array, player: Dictionary) -> Array:
	var out: Array = []
	var width_needed := 2.0 * float(player["radius"])
	var standing := float(player["height"])
	var crouched := float(player["crouch_height"])
	for cut in cutters:
		var c: AABB = cut["box"]
		for wall in boxes:
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


static func _ramps(wedges: Array, boxes: Array, player: Dictionary) -> Array:
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
		var landing: Variant = _landing(ramp["box"], slope, boxes)
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
