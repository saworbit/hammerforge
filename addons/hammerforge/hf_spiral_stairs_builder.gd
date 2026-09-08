@tool
extends RefCounted
class_name HFSpiralStairsBuilder

## A flight of stairs turning about an axis: one description, one brush per tread.
##
## The roadmap's answer to a spiral stair has been a radial array with a rise,
## which repeats one shape around an axis. That is the same limitation that made
## the arch worth building — an array can copy a wedge but it cannot compute the
## wedge, so every tread comes out the shape of whatever brush you happened to
## start with rather than the shape a tread at that radius actually is.
##
## A tread here is an annular wedge: the arch's voussoir, lying flat. Optionally
## there is a newel post down the middle, which is what stops a spiral stair
## reading as a stack of floating shelves.
##
## Built about its own centre, climbing +Y and turning about the Y axis.

const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFOpResult = preload("hf_op_result.gd")

const MAX_STEPS := 128

## A tread spanning half a turn or more is not convex, and every brush is convex.
const MAX_STEP_DEGREES := 179.0

## Sides on the newel post. Eight reads as round at the scale a post is seen from
## and costs one brush; more sides would cost the same brush and buy nothing.
const POST_SIDES := 8


static func settings_schema() -> Array:
	return [
		{
			"key": "outer_radius",
			"label": "Outer R",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 4096.0,
			"step": 1.0,
			"default": 128.0,
			"tooltip": "How far the treads reach from the axis",
		},
		{
			"key": "inner_radius",
			"label": "Inner R",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.0,
			"max": 4096.0,
			"step": 1.0,
			"default": 16.0,
			"tooltip": "The hole down the middle. Zero makes treads that meet at the axis",
		},
		{
			"key": "steps",
			"label": "Steps",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": MAX_STEPS,
			"step": 1,
			"default": 12,
			"tooltip": "One brush per tread",
		},
		{
			"key": "degrees_per_step",
			"label": "Turn",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -MAX_STEP_DEGREES,
			"max": MAX_STEP_DEGREES,
			"step": 1.0,
			"default": 30.0,
			"tooltip": "Degrees one tread turns through. Negative turns the other way",
		},
		{
			"key": "rise",
			"label": "Rise",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.0,
			"max": 1024.0,
			"step": 1.0,
			"default": 16.0,
			"tooltip": "How far one tread carries you up. Zero makes a flat fan",
		},
		{
			"key": "tread_thickness",
			"label": "Slab",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 1024.0,
			"step": 1.0,
			"default": 8.0,
			"tooltip": "How thick one tread is",
		},
		{
			"key": "start_degrees",
			"label": "Start",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 0.0,
			"tooltip": "Angle the first tread begins at",
		},
		{
			"key": "center_post",
			"label": "Newel post",
			"type": HFGeneratorSchema.TYPE_BOOL,
			"default": true,
			"tooltip": "Fill the middle with a post the full height of the flight",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var steps: int = merged["steps"]
	var outer: float = merged["outer_radius"]
	var inner: float = merged["inner_radius"]
	var turn: float = merged["degrees_per_step"]

	if steps < 1:
		return HFOpResult.fail("Spiral stairs: needs at least one tread", "Set steps to 1 or more")
	if steps > MAX_STEPS:
		return HFOpResult.fail(
			"Spiral stairs: %d treads is more brushes than a staircase should be" % steps,
			"Use %d steps or fewer" % MAX_STEPS
		)
	if outer <= 0.0:
		return HFOpResult.fail(
			"Spiral stairs: outer radius must be greater than zero", "Set a positive outer radius"
		)
	if inner < 0.0:
		return HFOpResult.fail(
			"Spiral stairs: inner radius cannot be negative", "Use zero for treads that meet"
		)
	if inner >= outer:
		return HFOpResult.fail(
			"Spiral stairs: an inner radius of %.1f leaves no tread inside %.1f" % [inner, outer],
			"Use an inner radius below %.1f" % outer
		)
	if float(merged["tread_thickness"]) <= 0.0:
		return HFOpResult.fail(
			"Spiral stairs: tread thickness must be greater than zero", "Set a positive thickness"
		)
	if float(merged["rise"]) < 0.0:
		return HFOpResult.fail(
			"Spiral stairs: rise cannot be negative", "Use zero for a flat fan of treads"
		)
	if is_zero_approx(turn):
		return HFOpResult.fail(
			"Spiral stairs: treads that turn through zero degrees sit on top of each other",
			"Try 30 degrees a step"
		)
	if absf(turn) > MAX_STEP_DEGREES:
		return HFOpResult.fail(
			"Spiral stairs: a tread turning %.0f degrees is not convex" % absf(turn),
			"Use %.0f degrees or fewer a step" % MAX_STEP_DEGREES
		)
	if bool(merged["center_post"]) and inner <= 0.0:
		return HFOpResult.fail(
			"Spiral stairs: a newel post needs an inner radius to occupy",
			"Set an inner radius, or turn the post off"
		)
	return HFOpResult.success()


## Build the flight. One `Array[FaceData]` per tread, and the post last if asked.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var outer: float = merged["outer_radius"]
	var inner: float = merged["inner_radius"]
	var steps: int = merged["steps"]
	var turn := deg_to_rad(float(merged["degrees_per_step"]))
	var rise: float = merged["rise"]
	var thickness: float = merged["tread_thickness"]
	var start := deg_to_rad(float(merged["start_degrees"]))

	var climb := float(steps) * rise
	var has_post := bool(merged["center_post"])
	var post_height := maxf(climb, thickness)
	# Centred on the geometry actually emitted. The treads start at the underside
	# of the first one rather than at the foot of the climb, so a flight without a
	# post to fill that gap would otherwise sit half a tread high. With a post this
	# comes out at the same place it always did.
	var lowest := rise - thickness
	var highest := climb
	if has_post:
		lowest = minf(lowest, 0.0)
		highest = maxf(highest, post_height)
	var y_shift := -(lowest + highest) * 0.5

	var out: Array = []
	for i in steps:
		var top := float(i + 1) * rise + y_shift
		var a0 := start + turn * float(i)
		var a1 := start + turn * float(i + 1)
		out.append(_tread_faces(outer, inner, a0, a1, top - thickness, top))
	if has_post:
		out.append(_post_faces(inner, y_shift, y_shift + post_height))
	return out


## One tread: the annular wedge between two angles, at two radii, one slab thick.
static func _tread_faces(
	outer: float, inner: float, a0: float, a1: float, low: float, high: float
) -> Array:
	var oi0 := _at(inner, a0, low)
	var oo0 := _at(outer, a0, low)
	var oo1 := _at(outer, a1, low)
	var oi1 := _at(inner, a1, low)
	var ti0 := _at(inner, a0, high)
	var to0 := _at(outer, a0, high)
	var to1 := _at(outer, a1, high)
	var ti1 := _at(inner, a1, high)
	# Written as the general eight-corner case. When the inner radius is zero the
	# inner corners collapse onto the axis and `solid_from_rings` returns the wedge
	# that is actually there.
	return (
		HFConvexClip
		. solid_from_rings(
			[
				[oi0, oo0, oo1, oi1],
				[ti0, to0, to1, ti1],
				[oo0, oo1, to1, to0],
				[oi0, oi1, ti1, ti0],
				[oi0, oo0, to0, ti0],
				[oi1, oo1, to1, ti1],
			]
		)
	)


## The newel post: a prism the flight turns around.
static func _post_faces(radius: float, low: float, high: float) -> Array:
	var rings: Array = []
	var bottom: Array = []
	var top: Array = []
	for i in POST_SIDES:
		var angle := TAU * float(i) / float(POST_SIDES)
		bottom.append(_at(radius, angle, low))
		top.append(_at(radius, angle, high))
	rings.append(bottom)
	rings.append(top)
	for i in POST_SIDES:
		var j := (i + 1) % POST_SIDES
		rings.append([bottom[i], bottom[j], top[j], top[i]])
	return HFConvexClip.solid_from_rings(rings)


static func _at(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(radius * cos(angle), y, radius * sin(angle))
