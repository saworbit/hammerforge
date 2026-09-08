@tool
extends RefCounted
class_name HFDomeBuilder

## A dome in rings: one description, one brush per panel.
##
## The construction has to be chosen rather than assumed. Four points on a sphere
## at two latitudes and two longitudes are **not coplanar**, so the obvious "one
## brush per patch of sphere" is not a brush at all — every brush here is a convex
## solid with planar faces, and a warped quad is neither.
##
## Rings solve it. Bound each band by two horizontal planes rather than by the
## sphere, and a panel becomes the piece between two horizontal planes, two
## meridian planes through the axis, and the outer and inner conical surfaces
## between them. The four outer corners of that piece *are* coplanar — they are
## `r0·u0`, `r1·u0`, `r0·u1`, `r1·u1` for two unit directions, which is a plane
## through the origin — so every face is a plane and the panel is a proper brush.
##
## A brush dome is faceted. That is not a compromise here; it is what a dome made
## of convex solids is.
##
## Built about its own centre, standing on the XZ plane and climbing +Y.

const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFOpResult = preload("hf_op_result.gd")

## Panels are `rings × segments`, and each one is a brush. Four rings of twelve is
## a convincing dome at forty-eight brushes; ten of thirty-six is nine hundred and
## nobody meant that.
const MAX_PANELS := 256

## A panel spanning half a turn is not convex.
const MAX_SEGMENT_DEGREES := 179.0


static func settings_schema() -> Array:
	return [
		{
			"key": "radius",
			"label": "Radius",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 4096.0,
			"step": 1.0,
			"default": 128.0,
			"tooltip": "Outer radius of the dome",
		},
		{
			"key": "wall_thickness",
			"label": "Wall",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 4096.0,
			"step": 1.0,
			"default": 16.0,
			"tooltip": "How thick the shell is. A thickness equal to the radius makes it solid",
		},
		{
			"key": "rings",
			"label": "Rings",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": 64,
			"step": 1,
			"default": 4,
			"tooltip": "Bands of panels stacked from the base to the crown",
		},
		{
			"key": "segments",
			"label": "Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 3,
			"max": 64,
			"step": 1,
			"default": 12,
			"tooltip": "Panels around the dome. More segments, rounder dome",
		},
		{
			"key": "arc_degrees",
			"label": "Arc",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 360.0,
			"tooltip": "Degrees the dome sweeps around. Less than 360 makes a slice",
		},
		{
			"key": "sweep_degrees",
			"label": "Sweep",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 1.0,
			"max": 90.0,
			"step": 5.0,
			"default": 90.0,
			"tooltip": "Degrees the dome climbs. 90 reaches the crown, less leaves it open",
		},
		{
			"key": "start_degrees",
			"label": "Start",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 0.0,
			"tooltip": "Angle the dome begins at",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var radius: float = merged["radius"]
	var thickness: float = merged["wall_thickness"]
	var rings: int = merged["rings"]
	var segments: int = merged["segments"]
	var arc: float = merged["arc_degrees"]
	var sweep: float = merged["sweep_degrees"]

	if radius <= 0.0:
		return HFOpResult.fail("Dome: radius must be greater than zero", "Set a positive radius")
	if thickness <= 0.0:
		return HFOpResult.fail(
			"Dome: wall thickness must be greater than zero", "Set a positive wall thickness"
		)
	if thickness > radius:
		return HFOpResult.fail(
			"Dome: a wall %.1f thick is more than the whole %.1f radius" % [thickness, radius],
			"Use %.1f for a solid dome, or less for a shell" % radius
		)
	if rings < 1:
		return HFOpResult.fail("Dome: needs at least one ring", "Set rings to 1 or more")
	if segments < 3:
		return HFOpResult.fail(
			"Dome: %d segments cannot close a ring" % segments, "Use at least 3 segments"
		)
	if is_zero_approx(arc):
		return HFOpResult.fail("Dome: arc angle must not be zero", "Try 360 for a whole dome")
	if absf(arc) > 360.0:
		return HFOpResult.fail(
			"Dome: arc angle %.0f is more than a full turn" % arc, "Use 360 degrees or less"
		)
	if sweep <= 0.0 or sweep > 90.0:
		return HFOpResult.fail(
			"Dome: sweep must be between 1 and 90 degrees", "Use 90 for a hemisphere"
		)
	var step: float = absf(arc) / float(segments)
	if step > MAX_SEGMENT_DEGREES:
		var needed := int(ceil(absf(arc) / MAX_SEGMENT_DEGREES))
		return HFOpResult.fail(
			(
				"Dome: %.0f degrees across %d segment(s) is too coarse to stay convex"
				% [absf(arc), segments]
			),
			"Use at least %d segments for this arc" % needed
		)
	var panels := rings * segments
	if panels > MAX_PANELS:
		return HFOpResult.fail(
			"Dome: %d rings of %d segments is %d brushes" % [rings, segments, panels],
			"Keep rings x segments at or below %d" % MAX_PANELS
		)
	return HFOpResult.success()


## Build the dome. One `Array[FaceData]` per panel, in the dome's own space.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var radius: float = merged["radius"]
	var inner_radius: float = maxf(0.0, radius - float(merged["wall_thickness"]))
	var rings: int = merged["rings"]
	var segments: int = merged["segments"]
	var sweep := deg_to_rad(float(merged["sweep_degrees"]))
	var arc_step := deg_to_rad(float(merged["arc_degrees"])) / float(segments)
	var start := deg_to_rad(float(merged["start_degrees"]))

	# Ring boundaries: a height, and the horizontal radius the outer and inner
	# spheres have at that height. Above where the inner sphere ends, the inner
	# radius is zero and the shell closes onto the axis — which is what a shell
	# does near the crown, and what makes the top ring a wedge rather than a box.
	var heights := PackedFloat32Array()
	var outer_radii := PackedFloat32Array()
	var inner_radii := PackedFloat32Array()
	var y_shift := -radius * sin(sweep) * 0.5
	for k in rings + 1:
		var phi := sweep * float(k) / float(rings)
		var y := radius * sin(phi)
		heights.append(y + y_shift)
		outer_radii.append(radius * cos(phi))
		inner_radii.append(sqrt(maxf(0.0, inner_radius * inner_radius - y * y)))

	var out: Array = []
	for k in rings:
		for j in segments:
			var a0 := start + arc_step * float(j)
			var a1 := start + arc_step * float(j + 1)
			var faces := _panel_faces(
				a0,
				a1,
				heights[k],
				heights[k + 1],
				outer_radii[k],
				outer_radii[k + 1],
				inner_radii[k],
				inner_radii[k + 1]
			)
			if not faces.is_empty():
				out.append(faces)
	return out


## One panel: the piece between two heights, two angles and two conical surfaces.
static func _panel_faces(
	a0: float,
	a1: float,
	low: float,
	high: float,
	outer_low: float,
	outer_high: float,
	inner_low: float,
	inner_high: float
) -> Array:
	var bi0 := _at(inner_low, a0, low)
	var bo0 := _at(outer_low, a0, low)
	var bo1 := _at(outer_low, a1, low)
	var bi1 := _at(inner_low, a1, low)
	var ti0 := _at(inner_high, a0, high)
	var to0 := _at(outer_high, a0, high)
	var to1 := _at(outer_high, a1, high)
	var ti1 := _at(inner_high, a1, high)
	# The general eight-corner case, written once. Where the shell pinches — a
	# solid dome, or the crown, where the inner surface has closed onto the axis —
	# corners coincide and `solid_from_rings` returns the wedge that is there.
	return (
		HFConvexClip
		. solid_from_rings(
			[
				[bi0, bo0, bo1, bi1],
				[ti0, to0, to1, ti1],
				[bo0, bo1, to1, to0],
				[bi0, bi1, ti1, ti0],
				[bi0, bo0, to0, ti0],
				[bi1, bo1, to1, ti1],
			]
		)
	)


static func _at(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(radius * cos(angle), y, radius * sin(angle))
