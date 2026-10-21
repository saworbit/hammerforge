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

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFOpResult = preload("hf_op_result.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Panels are `rings × segments`, and each one is a brush. Four rings of twelve is
## a convincing dome at forty-eight brushes; ten of thirty-six is nine hundred and
## nobody meant that.
const MAX_PANELS := 256

## A panel spanning half a turn is not convex.
const MAX_SEGMENT_DEGREES := 179.0
## The smoothing group of the faces on the shell, as a new sphere's (#1429).
const CURVED_SMOOTHING := 1

## The thinnest a box can be, as on the Stairs (`HFBrushSystem.MIN_BRUSH_EXTENT`).
## A panel square to the axes, as a short ring of many panels can be, comes out a
## box brush, and is held to this (#1605).
const MIN_PIECE := 0.1


static func settings_schema() -> Array:
	return [
		{
			"key": "radius",
			"label": "Radius",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.05,
			"max": 4096.0,
			"step": 0.05,
			"default": 3.0,
			"tooltip": "Outer radius of the dome",
		},
		{
			"key": "wall_thickness",
			"label": "Wall",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.05,
			"max": 4096.0,
			"step": 0.05,
			"default": 0.25,
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
			(
				"Dome: a wall %s thick is more than the whole %s radius"
				% [_number(thickness), _number(radius)]
			),
			"Use %s for a solid dome, or less for a shell" % _number(radius)
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
	var thin_refusal := _thin_refusal(merged)
	if thin_refusal != null:
		return thin_refusal
	return HFOpResult.success()


## Why a panel would be too thin to build, or null.
##
## Most panels are not boxes, so they are built from their faces and keep them
## through a save and a reopen at any size (#1603), and only a sliver is refused:
## under Validate's near-zero thickness, measured the narrowest way across, so
## where it lies round the dome makes no difference. A panel square to the axes is
## made a box, which is held to `MIN_PIECE` (#1605). The top ring is the shortest,
## and the panels round the crown the narrowest.
static func _thin_refusal(merged: Dictionary) -> HFOpResult:
	var corner_sets := _panel_corners(merged)
	var ring_sets: Array = []
	for corners: PackedVector3Array in corner_sets:
		ring_sets.append(_panel_rings(corners))
	var thin := HFConvexClip.too_thin(corner_sets, ring_sets, MIN_PIECE)
	if thin.is_empty():
		return null
	var across: float = thin["across"]
	var way := "around"
	var direction: Vector3 = thin["direction"]
	var corners: PackedVector3Array = corner_sets[thin["piece"]]
	# Halfway between its outer corners along its bottom, out from the axis.
	var middle := Vector3(corners[1].x + corners[2].x, 0.0, corners[1].z + corners[2].z)
	if absf(direction.y) >= sqrt(0.5):
		way = "rings"
	elif absf(direction.dot(middle.normalized())) >= sqrt(0.5):
		way = "wall"
	var hint := "Use fewer Segments or Rings, or a larger Radius"
	if way == "rings":
		hint = "Use fewer Rings, or a larger Sweep or Radius"
	elif way == "wall":
		hint = "Use a Wall of %s or more" % _number(MIN_PIECE)
	if thin["box"]:
		return HFOpResult.fail(
			(
				"Dome: a panel square to the axes is a box %s across, thinner than a box can be"
				% _number(across)
			),
			hint
		)
	if way == "rings":
		return HFOpResult.fail(
			"Dome: a ring %s tall is a sliver, too thin to build" % _number(across), hint
		)
	return HFOpResult.fail(
		"Dome: a panel %s across is a sliver, too thin to build" % _number(across), hint
	)


static func _number(value: float) -> String:
	return HFNumberFormat.number(value, 0.0001)


## Build the dome. One `Array[FaceData]` per panel, in the dome's own space.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var out: Array = []
	for corners: PackedVector3Array in _panel_corners(merged):
		# The outer and inner surfaces shade as one round shell across every panel
		# (#1429); the rings' and the meridians' joints stay flat.
		var faces := HFConvexClip.solid_from_rings(
			_panel_rings(corners),
			HFConvexClip.DEFAULT_EPSILON,
			PackedInt32Array([0, 0, CURVED_SMOOTHING, CURVED_SMOOTHING, 0, 0])
		)
		if not faces.is_empty():
			out.append(faces)
	return out


## The eight corners of each panel: inner, outer, outer and inner along its
## bottom, then the same along its top. `build()` and `validate()` both read
## these, and the rings `_panel_rings()` makes of them, so what is measured is
## what is built.
static func _panel_corners(merged: Dictionary) -> Array:
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
			var corners := PackedVector3Array()
			for at: int in [k, k + 1]:
				corners.append(_at(inner_radii[at], a0, heights[at]))
				corners.append(_at(outer_radii[at], a0, heights[at]))
				corners.append(_at(outer_radii[at], a1, heights[at]))
				corners.append(_at(inner_radii[at], a1, heights[at]))
			out.append(corners)
	return out


## One panel's faces, as rings of its corners: the piece between two heights, two
## angles and two conical surfaces.
static func _panel_rings(corners: PackedVector3Array) -> Array:
	var bi0 := corners[0]
	var bo0 := corners[1]
	var bo1 := corners[2]
	var bi1 := corners[3]
	var ti0 := corners[4]
	var to0 := corners[5]
	var to1 := corners[6]
	var ti1 := corners[7]
	# The general eight-corner case, written once. Where the shell pinches — a
	# solid dome, or the crown, where the inner surface has closed onto the axis —
	# corners coincide and `solid_from_rings` returns the wedge that is there.
	return [
		[bi0, bo0, bo1, bi1],
		[ti0, to0, to1, ti1],
		[bo0, bo1, to1, to0],
		[bi0, bi1, ti1, ti0],
		[bi0, bo0, to0, ti0],
		[bi1, bo1, to1, ti1],
	]


static func _at(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(radius * cos(angle), y, radius * sin(angle))
