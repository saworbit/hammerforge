@tool
extends RefCounted
class_name HFRingBuilder

## A ring with a round section: one description, one brush per segment.
##
## A pipe bend, a ring moulding or a curved handrail. The torus brush is one
## non-convex brush whose tube only grows with its size, so it cannot be hollowed,
## carved or vertex edited; the Arch sweeps, but always with a square section.
## This sweeps a polygon of the tube's own radius instead.
##
## Each piece joins the tube polygon at one angle to the same polygon at the next.
## The two polygons are mirror images across the plane halfway between them, so
## each side joining them is a flat trapezoid, and the piece is the convex solid
## those sides and the two end polygons bound while it spans less than half a turn.
##
## Built about its own centre, lying flat in the XZ plane around +Y. Angle zero is
## +X, and a positive sweep turns towards +Z.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFOpResult = preload("hf_op_result.gd")
@warning_ignore_restore("shadowed_global_identifier")

## A piece spanning half a turn or more is not convex, as an Arch segment is not.
const MAX_SEGMENT_DEGREES := 179.0

## The thinnest a box can be, as on the Stairs (`HFBrushSystem.MIN_BRUSH_EXTENT`).
## A piece of a four-sided tube square to an axis comes out a box brush only when it
## is at least this on every side (#1598); a thinner one is built from its faces.
const MIN_PIECE := 0.1

## The sides of the tube. Three is the fewest that bound anything, and a piece has
## two faces more than its tube has sides, so 32 keeps it far inside
## `HFConvexClip.MAX_BOOLEAN_PLANES`.
const MIN_TUBE_SEGMENTS := 3
const MAX_TUBE_SEGMENTS := 32


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
			"tooltip": "From the centre of the ring to the middle of the tube",
		},
		{
			"key": "tube_radius",
			"label": "Tube Radius",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.05,
			"max": 2048.0,
			"step": 0.05,
			"default": 0.5,
			"tooltip": "How thick the tube is, from its middle to its outside. Less than Radius",
		},
		{
			"key": "ring_segments",
			"label": "Ring Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": 128,
			"step": 1,
			"default": 16,
			"tooltip": "One brush per segment. More segments, smoother curve",
		},
		{
			"key": "tube_segments",
			"label": "Tube Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": MIN_TUBE_SEGMENTS,
			"max": MAX_TUBE_SEGMENTS,
			"step": 1,
			"default": 8,
			"tooltip": "Sides around the tube. More sides, rounder tube",
		},
		{
			"key": "start_degrees",
			"label": "Start",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 0.0,
			"tooltip": "Angle the ring begins at",
		},
		{
			"key": "sweep_degrees",
			"label": "Sweep",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": -360.0,
			"max": 360.0,
			"step": 5.0,
			"default": 360.0,
			"tooltip": "Degrees the ring goes round. 360 closes it, 90 is a quarter bend",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


## Check settings before anything is created, so a bad ring refuses rather than
## producing pieces that are not brushes.
static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var radius: float = merged["radius"]
	var tube: float = merged["tube_radius"]
	var ring_segments: int = merged["ring_segments"]
	var tube_segments: int = merged["tube_segments"]
	var sweep: float = merged["sweep_degrees"]

	if ring_segments < 1:
		return HFOpResult.fail("Ring: needs at least one segment", "Set Ring Segments to 1 or more")
	if tube_segments < MIN_TUBE_SEGMENTS or tube_segments > MAX_TUBE_SEGMENTS:
		return HFOpResult.fail(
			"Ring: a tube of %d sides cannot be built" % tube_segments,
			"Use %d to %d tube segments" % [MIN_TUBE_SEGMENTS, MAX_TUBE_SEGMENTS]
		)
	if radius <= 0.0:
		return HFOpResult.fail("Ring: radius must be greater than zero", "Set a positive radius")
	if tube <= 0.0:
		return HFOpResult.fail(
			"Ring: tube radius must be greater than zero", "Set a positive tube radius"
		)
	# A tube that reaches the axis folds over itself there, and the pieces stop
	# being convex.
	if tube >= radius:
		return HFOpResult.fail(
			"Ring: a tube radius of %.2f reaches the centre of a %.2f ring" % [tube, radius],
			"Use a tube radius below %.2f" % radius
		)
	if is_zero_approx(sweep):
		return HFOpResult.fail("Ring: sweep must not be zero", "Try 360 degrees for a whole ring")
	if absf(sweep) > 360.0:
		return HFOpResult.fail(
			"Ring: a sweep of %.0f degrees is more than a full turn" % sweep,
			"Use 360 degrees or less"
		)
	var step: float = absf(sweep) / float(ring_segments)
	if step > MAX_SEGMENT_DEGREES:
		var needed := int(ceil(absf(sweep) / MAX_SEGMENT_DEGREES))
		return HFOpResult.fail(
			(
				"Ring: %.0f degrees across %d segment(s) is too coarse to stay convex"
				% [absf(sweep), ring_segments]
			),
			"Use at least %d ring segments for this sweep" % needed
		)
	var thin_refusal := _thin_refusal(merged)
	if thin_refusal != null:
		return thin_refusal
	return HFOpResult.success()


## Why a piece would be too thin to build, or null.
##
## Most pieces are not boxes, so they are built from their faces and keep them
## through a save and a reopen at any size (#1603), and only a sliver is refused:
## under Validate's near-zero thickness, measured the narrowest way across, so
## where it lies round the ring makes no difference. A piece square to an axis is a
## box only at `MIN_PIECE` or more (#1598), so no box is ever refused here.
static func _thin_refusal(merged: Dictionary) -> HFOpResult:
	var corner_sets := _piece_corners(merged)
	var ring_sets: Array = []
	for corners: PackedVector3Array in corner_sets:
		ring_sets.append(_piece_rings(corners))
	var thin := HFConvexClip.too_thin(corner_sets, ring_sets)
	if thin.is_empty():
		return null
	var across: float = thin["across"]
	var tube: float = merged["tube_radius"]
	var ring_segments: int = merged["ring_segments"]
	var turn := deg_to_rad(absf(float(merged["sweep_degrees"]))) / float(ring_segments)
	var direction: Vector3 = thin["direction"]
	var corners: PackedVector3Array = corner_sets[thin["piece"]]
	var sides: int = merged["tube_segments"]
	# Halfway between a corner of the section where the piece starts and the same
	# corner where it ends, out from the axis.
	var middle := Vector3(corners[0].x + corners[sides].x, 0.0, corners[0].z + corners[sides].z)
	var hint := "Use fewer Ring Segments, or a larger Radius"
	if turn > PI * 0.5:
		# Near half a turn, both ends of a piece lie almost along one line.
		hint = "Use more Ring Segments"
	elif absf(direction.y) >= sqrt(0.5):
		# The tube's height grows with its radius, so the radius that makes it tall
		# enough is in proportion.
		var least: float = HFConvexClip.NEAR_ZERO_THICKNESS
		var enough := ceilf(tube * least / across * 100.0) / 100.0
		hint = "Use a Tube Radius of %s or more" % _number(enough)
	elif absf(direction.dot(middle.normalized())) >= sqrt(0.5):
		hint = "Use a larger Tube Radius, or more Ring Segments"
	return HFOpResult.fail(
		"Ring: a piece %s across is a sliver, too thin to build" % _number(across), hint
	)


static func _number(value: float) -> String:
	return HFNumberFormat.number(value, 0.0001)


## Build the ring. Returns one `Array[FaceData]` per segment, in its own space.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var out: Array = []
	for corners: PackedVector3Array in _piece_corners(merged):
		# Winding is measured, not listed: `solid_from_rings` turns every face to
		# point away from the middle of the piece.
		out.append(HFConvexClip.solid_from_rings(_piece_rings(corners)))
	return out


## The corners of each piece: the tube's section where the piece starts, then
## where it ends. `build()` and `validate()` both read these, and the rings
## `_piece_rings()` makes of them, so what is measured is what is built.
static func _piece_corners(merged: Dictionary) -> Array:
	var radius: float = merged["radius"]
	var tube: float = merged["tube_radius"]
	var ring_segments: int = merged["ring_segments"]
	var tube_segments: int = merged["tube_segments"]
	var step := deg_to_rad(float(merged["sweep_degrees"])) / float(ring_segments)
	var start := deg_to_rad(float(merged["start_degrees"]))

	# The tube's section as (out from the axis, up) pairs. It is turned half a
	# side, so a tube of an even number of sides has a flat top and bottom.
	var section := PackedVector2Array()
	for k in tube_segments:
		var around := TAU * (float(k) + 0.5) / float(tube_segments)
		section.append(Vector2(radius + tube * cos(around), tube * sin(around)))

	var out: Array = []
	for i in ring_segments:
		var corners := PackedVector3Array()
		for angle: float in [start + step * float(i), start + step * float(i + 1)]:
			for corner in section:
				corners.append(_at(corner.x, angle, corner.y))
		out.append(corners)
	return out


## One piece's faces, as rings of its corners: the section at one angle, the same
## section at the next, and a side for each side of the section between them. The
## end faces come first and the sides follow round the section, so a face keeps
## its index when only a radius changes and an Update puts its paint back on it.
static func _piece_rings(corners: PackedVector3Array) -> Array:
	@warning_ignore("integer_division")
	var sides := corners.size() / 2
	var near := corners.slice(0, sides)
	var far := corners.slice(sides)
	var rings: Array = [near, far]
	for k in sides:
		var next := (k + 1) % sides
		rings.append([near[k], near[next], far[next], far[k]])
	return rings


static func _at(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(radius * cos(angle), y, radius * sin(angle))
