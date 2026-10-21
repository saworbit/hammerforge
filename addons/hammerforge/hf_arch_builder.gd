@tool
extends RefCounted
class_name HFArchBuilder

## Parametric arches: one description, one brush per segment.
##
## Curved openings, tunnel rings and vaulted ceilings are staple level geometry,
## and placing each voussoir by hand is the kind of work a computer should be
## doing. A radial array can repeat a shape; it cannot compute the wedge an arch
## is made of, which is what this does.
##
## Like `HFConvexClip`, this never touches the scene: settings in, face sets out,
## so it and its callers test without a level. The arch is built centred on its
## own origin, lying in the XY plane and extruded along Z, and the caller places
## it.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFOpResult = preload("hf_op_result.gd")
@warning_ignore_restore("shadowed_global_identifier")

## A segment spanning half a turn or more is not convex, and every brush in
## HammerForge is convex. Three segments is the fewest that can close a ring.
const MAX_SEGMENT_DEGREES := 179.0
## The smoothing group of the faces on the curve, as a new cylinder's sides (#1429).
const CURVED_SMOOTHING := 1

## The thinnest a box can be, as on the Stairs (`HFBrushSystem.MIN_BRUSH_EXTENT`).
## A segment square to an axis, as the ones at the ends of an arch of many segments
## are, comes out a box brush, and is held to this (#1605).
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
			"tooltip": "Outer radius of the arch",
		},
		{
			"key": "wall_thickness",
			"label": "Wall",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.05,
			"max": 2048.0,
			"step": 0.05,
			"default": 0.5,
			"tooltip": "How thick the arch ring is; the opening is the rest",
		},
		{
			"key": "depth",
			"label": "Depth",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.05,
			"max": 2048.0,
			"step": 0.05,
			"default": 1.5,
			"tooltip": "How far the arch extends along its own axis",
		},
		{
			"key": "arc_degrees",
			"label": "Arc",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 180.0,
			"tooltip": "Degrees the arch sweeps. 180 is a half arch, 360 a full ring",
		},
		{
			"key": "segments",
			"label": "Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": 128,
			"step": 1,
			"default": 8,
			"tooltip": "One brush per segment. More segments, smoother curve",
		},
		{
			"key": "start_degrees",
			"label": "Start",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 0.0,
			"tooltip": "Angle the arch begins at",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


## Check settings before anything is created, so a bad arch refuses rather than
## producing rubbish the user then has to delete.
static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var radius: float = merged["radius"]
	var thickness: float = merged["wall_thickness"]
	var depth: float = merged["depth"]
	var arc: float = merged["arc_degrees"]
	var segments: int = merged["segments"]

	if segments < 1:
		return HFOpResult.fail("Arch: needs at least one segment", "Set segments to 1 or more")
	if radius <= 0.0:
		return HFOpResult.fail("Arch: radius must be greater than zero", "Set a positive radius")
	if depth <= 0.0:
		return HFOpResult.fail("Arch: depth must be greater than zero", "Set a positive depth")
	if thickness <= 0.0:
		return HFOpResult.fail(
			"Arch: wall thickness must be greater than zero", "Set a positive wall thickness"
		)
	if thickness >= radius:
		return HFOpResult.fail(
			(
				"Arch: wall thickness %s leaves no opening inside radius %s"
				% [_number(thickness), _number(radius)]
			),
			"Use a thickness below %s" % _number(radius)
		)
	if is_zero_approx(arc):
		return HFOpResult.fail(
			"Arch: arc angle must not be zero", "Try 180 degrees for a half arch"
		)
	if absf(arc) > 360.0:
		return HFOpResult.fail(
			"Arch: arc angle %.0f is more than a full turn" % arc, "Use 360 degrees or less"
		)
	var step: float = absf(arc) / float(segments)
	if step > MAX_SEGMENT_DEGREES:
		var needed := int(ceil(absf(arc) / MAX_SEGMENT_DEGREES))
		return HFOpResult.fail(
			(
				"Arch: %.0f degrees across %d segment(s) is too coarse to stay convex"
				% [absf(arc), segments]
			),
			"Use at least %d segments for this arc" % needed
		)
	var thin_refusal := _thin_refusal(merged)
	if thin_refusal != null:
		return thin_refusal
	return HFOpResult.success()


## Why a segment would be too thin to build, or null.
##
## Most segments are not boxes, so they are built from their faces and keep them
## through a save and a reopen at any size (#1603), and only a sliver is refused:
## under Validate's near-zero thickness, measured the narrowest way across, so
## where it lies on the arch makes no difference. A segment square to an axis is
## made a box, which is held to `MIN_PIECE` (#1605).
static func _thin_refusal(merged: Dictionary) -> HFOpResult:
	var thin := thin_segment(merged)
	if thin.is_empty():
		return null
	var across: float = thin["across"]
	var turn := deg_to_rad(absf(float(merged["arc_degrees"]))) / float(int(merged["segments"]))
	var hint := "Use fewer segments, or a larger Radius"
	match str(thin["way"]):
		"depth":
			hint = "Use a Depth of %s or more" % _number(MIN_PIECE)
		"wall":
			hint = "Use a Wall of %s or more" % _number(MIN_PIECE)
	if turn > PI * 0.5:
		# Near half a turn, both ends of a segment lie almost along one line.
		hint = "Use more segments"
	if thin["box"]:
		return HFOpResult.fail(
			(
				"Arch: a segment square to an axis is a box %s across, thinner than a box can be"
				% _number(across)
			),
			hint
		)
	return HFOpResult.fail(
		"Arch: a segment %s across is a sliver, too thin to build" % _number(across), hint
	)


## The thinnest segment too thin to build, as `HFConvexClip.too_thin()` gives it,
## or an empty dictionary. `way` says which way it is thin: through its `depth`,
## through its `wall`, or `along` the curve. The Door Frame asks this of its
## arched head.
static func thin_segment(settings: Dictionary) -> Dictionary:
	var corner_sets := _segment_corners(HFGeneratorSchema.merge(settings_schema(), settings))
	var ring_sets: Array = []
	for corners: PackedVector3Array in corner_sets:
		ring_sets.append(_segment_rings(corners))
	var thin := HFConvexClip.too_thin(corner_sets, ring_sets, MIN_PIECE)
	if thin.is_empty():
		return thin
	var way := "along"
	var direction: Vector3 = thin["direction"]
	var corners: PackedVector3Array = corner_sets[thin["piece"]]
	# Halfway between its outer corners, out from the centre.
	var middle := Vector3(corners[0].x + corners[1].x, corners[0].y + corners[1].y, 0.0)
	if absf(direction.z) >= sqrt(0.5):
		way = "depth"
	elif absf(direction.dot(middle.normalized())) >= sqrt(0.5):
		way = "wall"
	thin["way"] = way
	return thin


static func _number(value: float) -> String:
	return HFNumberFormat.number(value, 0.0001)


## Build the arch. Returns one `Array[FaceData]` per segment, in its own space.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var out: Array = []
	for corners: PackedVector3Array in _segment_corners(merged):
		# The outer and inner faces lie on the curve and shade as one across the
		# segments (#1429); the faces and the joints between segments stay flat.
		out.append(
			HFConvexClip.solid_from_rings(
				_segment_rings(corners),
				HFConvexClip.DEFAULT_EPSILON,
				PackedInt32Array([0, 0, CURVED_SMOOTHING, CURVED_SMOOTHING, 0, 0])
			)
		)
	return out


## The eight corners of each segment: outer then inner at its start and end, at
## the front and then at the back. `build()` and `validate()` both read these, and
## the rings `_segment_rings()` makes of them, so what is measured is what is built.
static func _segment_corners(merged: Dictionary) -> Array:
	var outer: float = merged["radius"]
	var inner: float = outer - float(merged["wall_thickness"])
	var half_depth: float = float(merged["depth"]) * 0.5
	var segments: int = merged["segments"]
	var step := deg_to_rad(float(merged["arc_degrees"])) / float(segments)
	var start := deg_to_rad(float(merged["start_degrees"]))

	var out: Array = []
	for i in segments:
		var a0 := start + step * float(i)
		var a1 := start + step * float(i + 1)
		var corners := PackedVector3Array()
		for z: float in [half_depth, -half_depth]:
			corners.append(_at(outer, a0, z))
			corners.append(_at(outer, a1, z))
			corners.append(_at(inner, a1, z))
			corners.append(_at(inner, a0, z))
		out.append(corners)
	return out


## One voussoir's faces, as rings of its corners: the wedge between two angles, at
## two radii, across the depth.
static func _segment_rings(corners: PackedVector3Array) -> Array:
	var outer_0_front := corners[0]
	var outer_1_front := corners[1]
	var inner_1_front := corners[2]
	var inner_0_front := corners[3]
	var outer_0_back := corners[4]
	var outer_1_back := corners[5]
	var inner_1_back := corners[6]
	var inner_0_back := corners[7]

	# Winding is settled by measurement in `solid_from_rings()`, not by the order
	# the corners are listed in. A voussoir is convex, so every face of it points
	# away from its centre, and that is checkable — which is the difference between
	# geometry that bakes and geometry that bakes inside out.
	return [
		[outer_0_front, outer_1_front, inner_1_front, inner_0_front],
		[outer_0_back, outer_1_back, inner_1_back, inner_0_back],
		[outer_0_front, outer_1_front, outer_1_back, outer_0_back],
		[inner_0_front, inner_1_front, inner_1_back, inner_0_back],
		[outer_0_front, inner_0_front, inner_0_back, outer_0_back],
		[outer_1_front, inner_1_front, inner_1_back, outer_1_back],
	]


static func _at(radius: float, angle: float, z: float) -> Vector3:
	return Vector3(radius * cos(angle), radius * sin(angle), z)
