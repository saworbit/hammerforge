@tool
extends RefCounted
class_name HFStairsBuilder

## A flight of stairs: one description, one brush per step.
##
## After the box, a staircase is the most common piece of built geometry in a
## level, and building one by hand is twelve brushes that each have to be offset
## from the last by exactly the same amount in two axes at once. Every one of
## those offsets is a chance to be a unit out, and a stair that is a unit out is a
## stair the player catches on.
##
## Like the other builders this never touches the scene: settings in, face sets
## out. The flight is built about its own centre, climbing +Y as it runs +Z, and
## its width lies along X. The caller places it.
##
## A stair can turn at a landing, left or right, a quarter turn (L) or a half
## (U), and every piece is still a box (#1410). The frame is the straight
## flight's of the same steps whatever the turn, so an Update that changes the
## turn leaves the first flight where it stands and rebuilds the landing and the
## flight after it.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFOpResult = preload("hf_op_result.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Each step is a brush, so the count is the cost. A flight past this is a ramp
## with extra steps, and the refusal says so rather than making 500 brushes.
const MAX_STEPS := 128
## The same cost counted in pieces, which is what it is measured in: a nosed
## solid step is two brushes, so the step cap alone would let nosing quietly
## double a flight.
const MAX_PIECES := 128

## The thinnest a piece is let be, the brush minimum
## (`HFBrushSystem.MIN_BRUSH_EXTENT`). Every field that sizes a piece starts here
## (#1582). `validate()` holds the pieces a field only feeds: a solid step's
## nosing, and a solid first step one shared riser tall.
const MIN_PIECE := 0.1

## A step from its own top down to the floor, so the flight is solid underneath.
const FILL_SOLID := 0
## A slab at its own height, floating. Everything under it is open.
const FILL_OPEN := 1

## Rise and Steps say the height, as they always have.
const HEIGHT_FROM_RISE := 0
## Total says the height, shared between Steps.
const HEIGHT_FROM_TOTAL := 1
## Total says the height, in the fewest steps that keep each riser at or under Rise.
const HEIGHT_FROM_FIT := 2

const TURN_STRAIGHT := 0
const TURN_L_LEFT := 1
const TURN_L_RIGHT := 2
const TURN_U_LEFT := 3
const TURN_U_RIGHT := 4

## The steps collide as they look.
const COLLISION_STEPS := 0
## The bake lays a smooth slope over each flight instead, for a player body that
## cannot step up (#1416). `ramp_collision()` is what it lays.
const COLLISION_RAMP := 1

## Fit divides one float by another, and 3.0 over 0.2 is 15 only to within a
## rounding. Without this a total that is a whole number of risers could take a
## step more than it needs.
const FIT_SLACK := 0.000001


static func settings_schema() -> Array:
	return [
		{
			"key": "width",
			"label": "Width",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 4096.0,
			"step": 0.05,
			"default": 1.5,
			"tooltip": "How wide the flight is, across the direction of travel",
		},
		{
			"key": "tread",
			"label": "Tread",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 1024.0,
			"step": 0.05,
			"default": 0.3,
			"tooltip": "How far one step carries you forward",
		},
		{
			"key": "height_from",
			"label": "Height from",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": ["Rise", "Total", "Fit"],
			"default": HEIGHT_FROM_RISE,
			"tooltip":
			(
				"Rise: each step climbs Rise. Total: Steps share the Total. Fit: the fewest "
				+ "steps no higher than Rise that climb the Total"
			),
		},
		{
			"key": "total",
			"label": "Total",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 4096.0,
			"step": 0.05,
			"default": 1.6,
			"tooltip": "The height the stair climbs, floor to floor. Used by Total and Fit",
		},
		{
			"key": "rise",
			"label": "Rise",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 1024.0,
			"step": 0.05,
			"default": 0.2,
			"tooltip":
			(
				"How far one step carries you up, or with Fit the most it may. Keep it under "
				+ "what the player can climb. Not used by Total"
			),
		},
		{
			"key": "steps",
			"label": "Steps",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": MAX_STEPS,
			"step": 1,
			"default": 8,
			"tooltip": "How many risers the stair climbs, one brush each. Not used by Fit",
		},
		{
			"key": "fill",
			"label": "Fill",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": ["Solid", "Open"],
			"default": FILL_SOLID,
			"tooltip": "Solid fills under each step to the base; Open leaves floating treads",
		},
		{
			"key": "tread_thickness",
			"label": "Slab",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 1024.0,
			"step": 0.05,
			"default": 0.1,
			"tooltip": "How thick a floating tread or a nosing is",
		},
		{
			"key": "nosing",
			"label": "Nosing",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.0,
			"max": 1024.0,
			"step": 0.01,
			"default": 0.0,
			"tooltip":
			"How far a tread overhangs the riser below. 0 is none; on a solid flight, 0.1 or more",
		},
		{
			"key": "collision",
			"label": "Collision",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": ["Steps", "Ramp"],
			"default": COLLISION_STEPS,
			"tooltip":
			(
				"Steps collide as they look. Ramp bakes a smooth slope over each flight, for "
				+ "a player that cannot step up"
			),
		},
		{
			"key": "turn",
			"label": "Turn",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": ["Straight", "L left", "L right", "U left", "U right"],
			"default": TURN_STRAIGHT,
			"tooltip": "Which way the stair turns at a landing, seen walking up it",
		},
		{
			"key": "before_landing",
			"label": "Before landing",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": MAX_STEPS - 1,
			"step": 1,
			"default": 4,
			"tooltip": "Risers in the first flight, the last onto the landing. Used by a turn",
		},
		{
			"key": "landing",
			"label": "Landing",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 4096.0,
			"step": 0.05,
			"default": 1.5,
			"tooltip":
			"How deep the landing is along the first flight. An L's is at least the width",
		},
		{
			"key": "gap",
			"label": "Gap",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.0,
			"max": 4096.0,
			"step": 0.05,
			"default": 0.2,
			"tooltip": "The space between the two flights of a U, which the landing spans",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


## How many steps the stair climbs and how far each one rises, from whichever
## settings say the height: `{"steps": int, "rise": float}`.
static func climb(settings: Dictionary) -> Dictionary:
	return _climb(HFGeneratorSchema.merge(settings_schema(), settings))


## How many steps of at most `rise` climb `height`: the count every stairs
## builder takes, the Path and Connector tools as well as this one. The slack
## keeps float noise in a division that comes out whole from adding a step, as
## 2.1 over 0.3 would (#1676). At least one.
static func step_count(height: float, rise: float) -> int:
	if rise <= 0.0:
		return 1
	var count := ceilf(absf(height) / rise - FIT_SLACK)
	return int(clampf(count, 1.0, 1000000.0)) if is_finite(count) else 1


static func _climb(merged: Dictionary) -> Dictionary:
	var steps: int = merged["steps"]
	var rise: float = merged["rise"]
	var total: float = merged["total"]
	match int(merged["height_from"]):
		HEIGHT_FROM_TOTAL:
			rise = total / float(steps) if steps > 0 else 0.0
		HEIGHT_FROM_FIT:
			var count := ceilf(total / rise - FIT_SLACK) if rise > 0.0 else 0.0
			# Held to a number an int can carry, so a refusal can say it.
			steps = int(clampf(count, 1.0, 1000000.0)) if is_finite(count) else 0
			rise = total / float(steps) if steps > 0 else 0.0
	return {"steps": steps, "rise": rise}


static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	for pair in [["width", "width"], ["tread", "tread depth"], ["rise", "rise"]]:
		if float(merged[pair[0]]) <= 0.0:
			return HFOpResult.fail(
				"Stairs: %s must be greater than zero" % pair[1], "Set a positive %s" % pair[1]
			)
	var height_from := int(merged["height_from"])
	if height_from != HEIGHT_FROM_RISE and float(merged["total"]) <= 0.0:
		return HFOpResult.fail(
			"Stairs: the total height must be greater than zero", "Set a positive Total"
		)
	var shape := _climb(merged)
	var steps: int = shape["steps"]
	var rise: float = shape["rise"]
	if steps < 1:
		return HFOpResult.fail("Stairs: needs at least one step", "Set steps to 1 or more")
	if steps > MAX_STEPS:
		if height_from == HEIGHT_FROM_FIT:
			return HFOpResult.fail(
				(
					"Stairs: climbing %s in risers of %s or less takes %d steps"
					% [_number(merged["total"]), _number(merged["rise"]), steps]
				),
				"Raise the rise, so it fits in %d steps or fewer" % MAX_STEPS
			)
		return HFOpResult.fail(
			"Stairs: %d steps is more brushes than a staircase should be" % steps,
			"Use %d steps or fewer, or build the flight in sections" % MAX_STEPS
		)
	# A solid flight's first step is one riser tall. Rise starts at the minimum,
	# but a Total shared between Steps, or Fit, can come to a thinner riser. The
	# slack lets a division a rounding under, as 0.3 over 3 is, build.
	if int(merged["fill"]) == FILL_SOLID and rise < MIN_PIECE - FIT_SLACK:
		return HFOpResult.fail(
			(
				"Stairs: %d steps of %s make a solid first step thinner than a brush can be"
				% [steps, _number(rise, 0.0001)]
			),
			_thin_riser_hint(merged, height_from)
		)
	var thickness: float = merged["tread_thickness"]
	if int(merged["fill"]) == FILL_OPEN:
		if thickness <= 0.0:
			return HFOpResult.fail(
				"Stairs: tread thickness must be greater than zero", "Set a positive thickness"
			)
		if thickness > rise * float(steps):
			return HFOpResult.fail(
				(
					"Stairs: a tread %.1f thick is deeper than the whole %.1f climb"
					% [thickness, rise * float(steps)]
				),
				"Use a thickness below the total rise"
			)
	var nosing_refusal := _nosing_refusal(merged, rise)
	if nosing_refusal != null:
		return nosing_refusal
	var turn_refusal := _turn_refusal(merged, steps)
	if turn_refusal != null:
		return turn_refusal
	var pieces := _piece_count(merged, steps)
	if pieces > MAX_PIECES:
		return HFOpResult.fail(
			"Stairs: %d pieces is more brushes than a staircase should be" % pieces,
			"Use fewer steps, or no nosing on a solid flight"
		)
	return HFOpResult.success()


## What to change when a solid flight's riser is thinner than a brush, said in
## the fields that made it.
static func _thin_riser_hint(merged: Dictionary, height_from: int) -> String:
	var floor_to := "Use a Rise of %s or more" % _number(MIN_PIECE)
	match height_from:
		HEIGHT_FROM_TOTAL:
			var most := int(floorf(float(merged["total"]) / MIN_PIECE + FIT_SLACK))
			if most >= 1:
				floor_to = "Use %d steps or fewer" % most
			else:
				floor_to = "Use a Total of %s or more" % _number(MIN_PIECE)
		HEIGHT_FROM_FIT:
			floor_to = "Raise the Rise, so fewer steps climb the Total"
	return floor_to + ", or Open fill"


## Why this nosing cannot be built, or null.
static func _nosing_refusal(merged: Dictionary, rise: float) -> HFOpResult:
	var nosing: float = merged["nosing"]
	var tread: float = merged["tread"]
	if nosing < 0.0:
		return HFOpResult.fail("Stairs: a nosing cannot be negative", "Use 0 for no nosing")
	if nosing >= tread:
		return HFOpResult.fail(
			"Stairs: a nosing of %s reaches over the whole tread below" % _number(nosing),
			"Use a nosing under the %s tread" % _number(tread)
		)
	var thickness: float = merged["tread_thickness"]
	if nosing > 0.0 and int(merged["fill"]) == FILL_SOLID:
		for pair in [[nosing, "deep", "a nosing"], [thickness, "thick", "a Slab"]]:
			if float(pair[0]) < MIN_PIECE:
				return HFOpResult.fail(
					(
						"Stairs: a solid step's nosing %s %s is thinner than a brush can be"
						% [_number(float(pair[0])), pair[1]]
					),
					"Use %s of %s or more, or Open fill" % [pair[2], _number(MIN_PIECE)]
				)
	# A nosing hangs at the top of its step, one slab deep. Deeper than the riser
	# under it, it reaches down into the step below.
	if nosing > 0.0 and thickness > rise:
		return HFOpResult.fail(
			(
				"Stairs: a nosing %s thick runs into the step below a %s riser"
				% [_number(thickness), _number(rise, 0.0001)]
			),
			"Use a Slab of %s or less, or no nosing" % _number(rise, 0.0001)
		)
	return null


## Why this turn cannot be built, or null.
static func _turn_refusal(merged: Dictionary, steps: int) -> HFOpResult:
	var turn := int(merged["turn"])
	if turn == TURN_STRAIGHT:
		return null
	var before: int = merged["before_landing"]
	if before < 1 or before >= steps:
		return HFOpResult.fail(
			"Stairs: a landing after %d of %d risers leaves no flight after it" % [before, steps],
			(
				"Set Before landing from 1 to %d" % (steps - 1)
				if steps > 1
				else "Use two steps or more"
			)
		)
	var landing: float = merged["landing"]
	if landing <= 0.0:
		return HFOpResult.fail(
			"Stairs: the landing must be deeper than zero", "Set a positive landing depth"
		)
	var width: float = merged["width"]
	if (turn == TURN_L_LEFT or turn == TURN_L_RIGHT) and landing < width:
		# The second flight leaves from the landing's side, and it is as wide as the
		# first. A shallower landing would leave part of it standing on nothing.
		return HFOpResult.fail(
			(
				"Stairs: an L landing %s deep is shallower than the %s wide flight that leaves it"
				% [_number(landing), _number(width)]
			),
			"Make the landing at least %s deep" % _number(width)
		)
	if float(merged["gap"]) < 0.0:
		return HFOpResult.fail("Stairs: the gap cannot be negative", "Use 0 for flights that touch")
	return null


## The brushes these settings make. A landing stands in for one step, and a solid
## step's nosing is a brush of its own.
static func _piece_count(merged: Dictionary, steps: int) -> int:
	var landing := 0 if int(merged["turn"]) == TURN_STRAIGHT else 1
	var count := steps
	if float(merged["nosing"]) > 0.0 and int(merged["fill"]) == FILL_SOLID:
		count += steps - landing
	return count


## What the settings came to, said the way the section shows it: the steps, the
## rise of each and the climb, and the ramp's slope when the collision is one.
## Empty when the settings cannot build.
static func summary(settings: Dictionary) -> String:
	if not validate(settings).ok:
		return ""
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var shape := _climb(merged)
	var steps: int = shape["steps"]
	var rise: float = shape["rise"]
	var text := (
		"%d steps of %s climb %s"
		% [steps, _number(rise, 0.0001), _number(rise * float(steps), 0.0001)]
	)
	if int(merged["turn"]) != TURN_STRAIGHT:
		var before: int = merged["before_landing"]
		text += ", landing at %s" % _number(rise * float(before), 0.0001)
	if int(merged["collision"]) == COLLISION_RAMP:
		text += ", ramp at %.1f degrees" % _slope_degrees(rise, float(merged["tread"]))
	return text


static func _number(value: float, step := 0.0) -> String:
	return HFNumberFormat.number(value, step)


static func _slope_degrees(rise: float, run: float) -> float:
	return rad_to_deg(atan2(rise, run))


## Build the stair. One `Array[FaceData]` per piece, in the stair's own space:
## the first flight's steps, the landing, the second flight's steps, then the
## nosing of each step in that order, so turning nosing on or off leaves every
## step in its place in the list.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var out: Array = []
	for piece in _layout(HFGeneratorSchema.merge(settings_schema(), settings))["pieces"]:
		out.append(_box_faces(piece[0], piece[1]))
	return out


## The collision the bake lays in place of the steps when Collision is Ramp
## (#1416), in the stair's own space, or `{}` when it is Steps or the settings
## cannot build.
##
## `pieces` is one convex point cloud for each flight and each landing, which the
## bake hulls. A flight's top runs through the front edge of every tread, from
## the floor one tread before the first, so it never dips under a tread and is
## never more than a riser over one, and lies flat over the top tread so it meets
## the floor above level. `over` is the piece each stands over, `covers` the
## pieces whose own collision it replaces (all of them), and `slope_degrees` how
## steep the flights are. `{"refused": String}` when a ramp cannot be laid.
static func ramp_collision(settings: Dictionary) -> Dictionary:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	if int(merged["collision"]) != COLLISION_RAMP or not validate(settings).ok:
		return {}
	var layout := _layout(merged)
	var tread: float = merged["tread"]
	var nosing: float = merged["nosing"]
	var pieces: Array = []
	var over := PackedInt32Array()
	var landing: Dictionary = layout["landing"]
	for flight: Dictionary in layout["flights"]:
		# The floor it climbs from has to reach one tread back from its first front
		# edge. A landing shallower than that leaves the slope starting in the air.
		if float(flight["room"]) < tread + nosing - HFConvexClip.DEFAULT_EPSILON:
			return {
				"refused":
				(
					"its landing is %s deep, short of the %s the ramp needs to start on"
					% [_number(float(flight["room"])), _number(tread + nosing)]
				)
			}
		pieces.append(_flight_ramp(flight, layout, merged))
		over.append(int(flight["first_piece"]))
		if flight.has("onto_landing"):
			pieces.append(landing["corners"])
			over.append(int(landing["piece"]))
	var covers := PackedInt32Array()
	for i in (layout["pieces"] as Array).size():
		covers.append(i)
	return {
		"pieces": pieces,
		"over": over,
		"covers": covers,
		"slope_degrees": _slope_degrees(float(layout["rise"]), tread),
	}


## One flight's ramp: the corners of every piece of it, the toe on the floor it
## climbs from, and where it runs onto a landing, the landing's front edge and the
## point a nosing's width before it, so the top meets the landing flat.
static func _flight_ramp(
	flight: Dictionary, layout: Dictionary, merged: Dictionary
) -> PackedVector3Array:
	var tread: float = merged["tread"]
	var nosing: float = merged["nosing"]
	var points := PackedVector3Array()
	for index in flight["pieces"]:
		var piece: Array = layout["pieces"][index]
		points.append_array(_corners(piece[0], piece[1]))
	var floor_y: float = flight["floor"]
	points.append_array(_across(flight, -tread - nosing, floor_y, layout))
	if flight.has("onto_landing"):
		var end := float(int(flight["count"])) * tread
		var top: float = flight["onto_landing"]
		points.append_array(_across(flight, end - nosing, top, layout))
		points.append_array(_across(flight, end, top, layout))
		points.append_array(_across(flight, end, float(flight["landing_bottom"]), layout))
	return points


## The two points across a flight's width, `along` its run from its foot, at `y`.
static func _across(
	flight: Dictionary, along: float, y: float, layout: Dictionary
) -> PackedVector3Array:
	var half_width: float = layout["half_width"]
	return PackedVector3Array(
		[
			_flight_point(flight, along, -half_width, y, layout),
			_flight_point(flight, along, half_width, y, layout),
		]
	)


## Every piece as the two opposite corners of its box, and each flight and the
## landing as the ramp reads them, in the stair's own space.
static func _layout(merged: Dictionary) -> Dictionary:
	var shape := _climb(merged)
	var steps: int = shape["steps"]
	var rise: float = shape["rise"]
	var tread: float = merged["tread"]
	var width: float = merged["width"]
	var half_width := width * 0.5
	var open_treads := int(merged["fill"]) == FILL_OPEN
	var thickness: float = merged["tread_thickness"]
	var nosing: float = merged["nosing"]
	var turn := int(merged["turn"])

	# Centred on its own middle, the way every other generator is, so placing it
	# on a selection puts the middle of the flight where you were looking. That
	# has to be the middle of the geometry actually emitted: an open flight starts
	# at the underside of its first tread, not at the foot of the climb, so
	# centring on the nominal climb would leave it half a tread out.
	#
	# A turned stair keeps the straight flight's middle, so changing the turn moves
	# nothing that stays.
	var lowest := (rise - thickness) if open_treads else 0.0
	var highest := float(steps) * rise
	var y_shift := -(lowest + highest) * 0.5
	var z_shift := -float(steps) * tread * 0.5
	var layout := {
		"pieces": [],
		"flights": [],
		"landing": {},
		"rise": rise,
		"y_shift": y_shift,
		"z_shift": z_shift,
		"half_width": half_width,
	}

	var first := {
		"start": Vector2.ZERO,
		"run": Vector2(0.0, 1.0),
		"riser": 1,
		"count": steps,
		"floor": y_shift,
		"room": INF,
	}
	var second := {}
	if turn != TURN_STRAIGHT:
		var before: int = merged["before_landing"]
		var depth: float = merged["landing"]
		var gap: float = merged["gap"]
		# The landing is the top of the last riser of the first flight, so it stands
		# in for that step.
		first["count"] = before - 1
		var near := float(before - 1) * tread
		var far := near + depth
		var left := -half_width
		var right := half_width
		match turn:
			TURN_U_LEFT:
				right = half_width + gap + width
			TURN_U_RIGHT:
				left = -half_width - gap - width
		var top := float(before) * rise + y_shift
		var bottom := (top - thickness) if open_treads else y_shift
		first["onto_landing"] = top
		first["landing_bottom"] = bottom
		second = {"riser": before + 1, "count": steps - before, "floor": top}
		# Seen walking up the first flight, +X is on the left. An L's second flight
		# leaves the landing's side at its far end, and a U's comes back beside the
		# first from the landing's near edge, the gap between them.
		match turn:
			TURN_L_LEFT:
				second["start"] = Vector2(half_width, far - half_width)
				second["run"] = Vector2(1.0, 0.0)
				second["room"] = width
			TURN_L_RIGHT:
				second["start"] = Vector2(-half_width, far - half_width)
				second["run"] = Vector2(-1.0, 0.0)
				second["room"] = width
			TURN_U_LEFT:
				second["start"] = Vector2(half_width + gap + half_width, near)
				second["run"] = Vector2(0.0, -1.0)
				second["room"] = depth
			TURN_U_RIGHT:
				second["start"] = Vector2(-half_width - gap - half_width, near)
				second["run"] = Vector2(0.0, -1.0)
				second["room"] = depth
		layout["landing"] = {
			"low": Vector3(left, bottom, near + z_shift),
			"high": Vector3(right, top, far + z_shift),
		}

	var steps_of: Array = []  # [flight, its step index] for each step, in build order
	_add_flight(layout, first, merged, steps_of)
	if not second.is_empty():
		var landing: Dictionary = layout["landing"]
		landing["piece"] = (layout["pieces"] as Array).size()
		landing["corners"] = _corners(landing["low"], landing["high"])
		layout["pieces"].append([landing["low"], landing["high"]])
		_add_flight(layout, second, merged, steps_of)
	if nosing > 0.0 and not open_treads:
		# The nosing of a solid step: a slab the depth of the nosing at the top of
		# its riser, over the step below. The step and its lip together are an L in
		# section, which is not convex, so they are two brushes.
		for entry in steps_of:
			var flight: Dictionary = entry[0]
			var k: int = entry[1]
			var top := float(int(flight["riser"]) + k) * rise + y_shift
			var front := float(k) * tread
			var box := _flight_box(flight, front - nosing, front, top - thickness, top, layout)
			flight["pieces"].append((layout["pieces"] as Array).size())
			layout["pieces"].append(box)
	return layout


## The steps of one flight onto `layout`, the flight recorded for the ramp.
static func _add_flight(
	layout: Dictionary, flight: Dictionary, merged: Dictionary, steps_of: Array
) -> void:
	var tread: float = merged["tread"]
	var rise: float = layout["rise"]
	var y_shift: float = layout["y_shift"]
	var open_treads := int(merged["fill"]) == FILL_OPEN
	var thickness: float = merged["tread_thickness"]
	# An open tread has nothing under it to be an L with, so it just grows forward.
	var reach: float = merged["nosing"] if open_treads else 0.0
	flight["pieces"] = []
	# A first flight of no steps runs straight onto the landing, which comes next
	# and is the piece its ramp stands over.
	flight["first_piece"] = (layout["pieces"] as Array).size()
	for k in int(flight["count"]):
		var top := float(int(flight["riser"]) + k) * rise + y_shift
		var bottom := (top - thickness) if open_treads else y_shift
		var near := float(k) * tread - reach
		var far := float(k + 1) * tread
		flight["pieces"].append((layout["pieces"] as Array).size())
		layout["pieces"].append(_flight_box(flight, near, far, bottom, top, layout))
		steps_of.append([flight, k])
	layout["flights"].append(flight)


## The box from `along_low` to `along_high` up a flight's run, across its width,
## from `bottom` to `top`: `[low corner, high corner]`.
static func _flight_box(
	flight: Dictionary,
	along_low: float,
	along_high: float,
	bottom: float,
	top: float,
	layout: Dictionary
) -> Array:
	var half_width: float = layout["half_width"]
	var a := _flight_point(flight, along_low, -half_width, bottom, layout)
	var b := _flight_point(flight, along_high, half_width, top, layout)
	return [a.min(b), a.max(b)]


## A point `along` a flight's run from its foot and `side` across it, at `y`.
##
## Written out so that a straight flight's coordinates come out of exactly the
## arithmetic they always did. A level's stairs are recognised as untouched by a
## hash of their corners, so a corner a rounding away would read as an edit.
static func _flight_point(
	flight: Dictionary, along: float, side: float, y: float, layout: Dictionary
) -> Vector3:
	var start: Vector2 = flight["start"]
	var run: Vector2 = flight["run"]
	var x := start.x + run.x * along + run.y * side
	var z := start.y + run.y * along - run.x * side
	return Vector3(x, y, z + float(layout["z_shift"]))


## The eight corners of the box between two opposite corners.
static func _corners(low: Vector3, high: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for x in [low.x, high.x]:
		for y in [low.y, high.y]:
			for z in [low.z, high.z]:
				out.append(Vector3(x, y, z))
	return out


## The six faces of the box between two opposite corners.
static func _box_faces(low: Vector3, high: Vector3) -> Array:
	var a := Vector3(low.x, low.y, low.z)
	var b := Vector3(high.x, low.y, low.z)
	var c := Vector3(high.x, low.y, high.z)
	var d := Vector3(low.x, low.y, high.z)
	var e := Vector3(low.x, high.y, low.z)
	var f := Vector3(high.x, high.y, low.z)
	var g := Vector3(high.x, high.y, high.z)
	var h := Vector3(low.x, high.y, high.z)
	return (
		HFConvexClip
		. solid_from_rings(
			[
				[a, b, c, d],
				[e, f, g, h],
				[a, b, f, e],
				[d, c, g, h],
				[a, d, h, e],
				[b, c, g, f],
			]
		)
	)
