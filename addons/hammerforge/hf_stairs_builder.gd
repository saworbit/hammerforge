@tool
extends RefCounted
class_name HFStairsBuilder

## A straight flight of stairs: one description, one brush per step.
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

const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFOpResult = preload("hf_op_result.gd")

## Each step is a brush, so the count is the cost. A flight past this is a ramp
## with extra steps, and the refusal says so rather than making 500 brushes.
const MAX_STEPS := 128

## A step from its own top down to the floor, so the flight is solid underneath.
const FILL_SOLID := 0
## A slab at its own height, floating. Everything under it is open.
const FILL_OPEN := 1


static func settings_schema() -> Array:
	return [
		{
			"key": "width",
			"label": "Width",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 4096.0,
			"step": 1.0,
			"default": 128.0,
			"tooltip": "How wide the flight is, across the direction of travel",
		},
		{
			"key": "tread",
			"label": "Tread",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 1024.0,
			"step": 1.0,
			"default": 32.0,
			"tooltip": "How far one step carries you forward",
		},
		{
			"key": "rise",
			"label": "Rise",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 1024.0,
			"step": 1.0,
			"default": 16.0,
			"tooltip": "How far one step carries you up. Keep it under what the player can climb",
		},
		{
			"key": "steps",
			"label": "Steps",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": MAX_STEPS,
			"step": 1,
			"default": 8,
			"tooltip": "One brush per step",
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
			"min": 1.0,
			"max": 1024.0,
			"step": 1.0,
			"default": 8.0,
			"tooltip": "How thick a floating tread is. Only used when Fill is Open",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var steps: int = merged["steps"]
	if steps < 1:
		return HFOpResult.fail("Stairs: needs at least one step", "Set steps to 1 or more")
	if steps > MAX_STEPS:
		return HFOpResult.fail(
			"Stairs: %d steps is more brushes than a staircase should be" % steps,
			"Use %d steps or fewer, or build the flight in sections" % MAX_STEPS
		)
	for pair in [["width", "width"], ["tread", "tread depth"], ["rise", "rise"]]:
		if float(merged[pair[0]]) <= 0.0:
			return HFOpResult.fail(
				"Stairs: %s must be greater than zero" % pair[1], "Set a positive %s" % pair[1]
			)
	if int(merged["fill"]) == FILL_OPEN:
		var thickness: float = merged["tread_thickness"]
		if thickness <= 0.0:
			return HFOpResult.fail(
				"Stairs: tread thickness must be greater than zero", "Set a positive thickness"
			)
		if thickness > float(merged["rise"]) * float(steps):
			return HFOpResult.fail(
				(
					"Stairs: a tread %.1f thick is deeper than the whole %.1f climb"
					% [thickness, float(merged["rise"]) * float(steps)]
				),
				"Use a thickness below the total rise"
			)
	return HFOpResult.success()


## Build the flight. One `Array[FaceData]` per step, in the flight's own space.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var half_width: float = float(merged["width"]) * 0.5
	var tread: float = merged["tread"]
	var rise: float = merged["rise"]
	var steps: int = merged["steps"]
	var open_treads := int(merged["fill"]) == FILL_OPEN
	var thickness: float = merged["tread_thickness"]

	# Centred on its own middle, the way every other generator is, so placing it
	# on a selection puts the middle of the flight where you were looking. That
	# has to be the middle of the geometry actually emitted: an open flight starts
	# at the underside of its first tread, not at the foot of the climb, so
	# centring on the nominal climb would leave it half a tread out.
	var lowest := (rise - thickness) if open_treads else 0.0
	var highest := float(steps) * rise
	var y_shift := -(lowest + highest) * 0.5
	var z_shift := -float(steps) * tread * 0.5

	var out: Array = []
	for i in steps:
		var top := float(i + 1) * rise + y_shift
		var bottom := (top - thickness) if open_treads else (y_shift)
		var near := float(i) * tread + z_shift
		var far := float(i + 1) * tread + z_shift
		out.append(_box_faces(Vector3(-half_width, bottom, near), Vector3(half_width, top, far)))
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
