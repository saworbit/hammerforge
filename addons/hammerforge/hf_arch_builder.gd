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

const FaceData = preload("face_data.gd")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFOpResult = preload("hf_op_result.gd")

## A segment spanning half a turn or more is not convex, and every brush in
## HammerForge is convex. Three segments is the fewest that can close a ring.
const MAX_SEGMENT_DEGREES := 179.0


static func default_settings() -> Dictionary:
	return {
		"radius": 128.0,
		"wall_thickness": 32.0,
		"depth": 64.0,
		"arc_degrees": 180.0,
		"segments": 8,
		"start_degrees": 0.0,
	}


## Check settings before anything is created, so a bad arch refuses rather than
## producing rubbish the user then has to delete.
static func validate(settings: Dictionary) -> HFOpResult:
	var merged := _merged(settings)
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
			"Arch: wall thickness %.1f leaves no opening inside radius %.1f" % [thickness, radius],
			"Use a thickness below %.1f" % radius
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
	return HFOpResult.success()


## Build the arch. Returns one `Array[FaceData]` per segment, in its own space.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := _merged(settings)
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
		out.append(_segment_faces(outer, inner, half_depth, a0, a1))
	return out


## One voussoir: the wedge between two angles, at two radii, across the depth.
static func _segment_faces(
	outer: float, inner: float, half_depth: float, a0: float, a1: float
) -> Array:
	var outer_0_front := _at(outer, a0, half_depth)
	var outer_1_front := _at(outer, a1, half_depth)
	var inner_1_front := _at(inner, a1, half_depth)
	var inner_0_front := _at(inner, a0, half_depth)
	var outer_0_back := _at(outer, a0, -half_depth)
	var outer_1_back := _at(outer, a1, -half_depth)
	var inner_1_back := _at(inner, a1, -half_depth)
	var inner_0_back := _at(inner, a0, -half_depth)

	var faces: Array = [
		_quad(outer_0_front, outer_1_front, inner_1_front, inner_0_front),
		_quad(outer_0_back, outer_1_back, inner_1_back, inner_0_back),
		_quad(outer_0_front, outer_1_front, outer_1_back, outer_0_back),
		_quad(inner_0_front, inner_1_front, inner_1_back, inner_0_back),
		_quad(outer_0_front, inner_0_front, inner_0_back, outer_0_back),
		_quad(outer_1_front, inner_1_front, inner_1_back, outer_1_back),
	]
	# Winding is settled by measurement, not by the order the corners were listed
	# above. A voussoir is convex, so every face of it points away from its centre,
	# and that is checkable — which is the difference between geometry that bakes
	# and geometry that bakes inside out.
	return HFConvexClip.orient_faces_outward(faces, HFConvexClip.interior_point(faces))


static func _at(radius: float, angle: float, z: float) -> Vector3:
	return Vector3(radius * cos(angle), radius * sin(angle), z)


static func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> FaceData:
	var face := FaceData.new()
	face.local_verts = PackedVector3Array([a, b, c, d])
	face.ensure_geometry()
	return face


static func _merged(settings: Dictionary) -> Dictionary:
	var merged := default_settings()
	for key in settings:
		if merged.has(key):
			merged[key] = settings[key]
	merged["segments"] = int(merged["segments"])
	for key in ["radius", "wall_thickness", "depth", "arc_degrees", "start_degrees"]:
		merged[key] = float(merged[key])
	return merged
