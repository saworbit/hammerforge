@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Face winding and geometric sanity across the primitives and the edit tools.
##
## The convention everything downstream depends on -- the bake, `.map` export,
## the convexity check -- is that a face winds clockwise seen from outside, so
## its normal points away from the brush. A shape or an operation that gets that
## backwards looks perfectly fine in the viewport and falls apart later, which is
## exactly the kind of thing that survives a unit suite.

const SHAPE_NAMES: Array[String] = [
	"BOX",
	"CYLINDER",
	"SPHERE",
	"CONE",
	"WEDGE",
	"PYRAMID",
	"PRISM_TRI",
	"PRISM_PENT",
	"ELLIPSOID",
	"CAPSULE",
	"TORUS",
	"TETRAHEDRON",
	"OCTAHEDRON",
	"DODECAHEDRON",
	"ICOSAHEDRON",
	"CUSTOM",
]

## Genuinely non-convex, so inward-facing surfaces are the shape rather than a
## defect. The winding check does not apply to these at all.
const NON_CONVEX_SHAPES: Array[int] = [10]

## Built from flat polygonal faces, so one inverted face is one too many.
const FLAT_FACED: Array[int] = [0, 4, 5, 6, 7, 11, 12, 13, 14, 15]

## The rest are curved surfaces the CSG node tessellates. A handful of slivers
## reading as inverted is the tessellation, not a finding; a large share of them
## is the winding.
const TESSELLATED_INVERSION_SHARE := 0.25

## Shapes whose inverted winding is already reported.
const KNOWN_INWARD: Array[int] = [6, 7, 12, 13, 14]


func id() -> String:
	return "geometry"


func summary() -> String:
	return "face winding across every primitive, and what bevel does to a brush"


func run() -> void:
	var root: Node3D = await fresh_root()

	note("--- primitive winding")
	for shape in range(SHAPE_NAMES.size()):
		var b = (
			root
			. create_brush_from_info(
				{
					"shape": shape,
					"size": Vector3(64, 64, 64),
					"center": Vector3(0, shape * 200, 0),
					"sides": 8,
				}
			)
		)
		if b == null:
			flag("%s could not be created" % SHAPE_NAMES[shape])
			continue
		var faces = (b.get("faces") as Array).size()
		var inward := HFVibe.inward_face_count(b)
		var convex: bool = root.vertex_system.validate_convexity(b)
		note("%-13s faces=%-5d inward=%-5d convex=%s" % [SHAPE_NAMES[shape], faces, inward, convex])
		if NON_CONVEX_SHAPES.has(shape):
			continue
		var share := float(inward) / float(max(faces, 1))
		var over_budget: bool = (
			inward > 0 if FLAT_FACED.has(shape) else share > TESSELLATED_INVERSION_SHARE
		)
		if over_budget:
			var detail := "%d of %d face normals point at the centroid" % [inward, faces]
			if KNOWN_INWARD.has(shape):
				known(313, "%s is inside-out" % SHAPE_NAMES[shape], detail)
			else:
				flag("%s is inside-out" % SHAPE_NAMES[shape], detail)
		elif inward > 0:
			note(
				"%s has %d tessellation slivers reading as inverted" % [SHAPE_NAMES[shape], inward]
			)
		elif not convex:
			note("%s fails the convexity check with no inverted faces" % SHAPE_NAMES[shape])

	note("--- bevel")
	var cases: Array = [
		[2, 4.0, "ordinary bevel"],
		[3, 8.0, "wider bevel"],
		[2, 0.0, "zero radius"],
		[2, -8.0, "negative radius"],
		[0, 4.0, "zero segments"],
		[10000, 4.0, "ten thousand segments"],
		[2, NAN, "NaN radius"],
		[2, 1e6, "radius far larger than the brush"],
	]
	for entry in cases:
		var b = box(root, Vector3(64, 64, 64), Vector3(500, 0, 0))
		var brush_id := str(b.get_meta("brush_id"))
		var ok: bool = root.bevel_system.bevel_edge(
			brush_id, [0, 1], int(entry[0]), float(entry[1])
		)
		var inward := HFVibe.inward_face_count(b)
		var extent := HFVibe.local_extent(b)
		note(
			(
				"%-32s returned=%-5s inward=%-3d extent=%s"
				% [entry[2], ok, inward, extent.snapped(Vector3.ONE * 0.01)]
			)
		)
		if ok and inward > 0:
			known(314, "%s leaves inverted faces" % entry[2], "%d faces wound inward" % inward)
		if ok and extent.length() > Vector3(64, 64, 64).length() * 2.0:
			known(
				315,
				"%s inflated the brush" % entry[2],
				"geometry spans %s inside a 64-unit brush" % extent.snapped(Vector3.ONE * 0.01)
			)
		if ok and not extent.is_finite():
			flag("%s produced non-finite geometry" % entry[2])
		root.delete_brush(b)

	note("--- clip and merge refusals")
	var target = box(root, Vector3(64, 64, 64), Vector3(-500, 0, 0))
	var target_id := str(target.get_meta("brush_id"))
	var degenerate = root.brush_system.clip_brush_by_plane(target_id, Plane(Vector3.ZERO, 0.0))
	note("clip with a directionless plane", "%s / %s" % [degenerate.ok, degenerate.message])
	if degenerate.ok:
		flag("a clip plane with no direction was accepted")
	var nan_plane = root.brush_system.clip_brush_by_plane(target_id, Plane(Vector3(NAN, 0, 0), NAN))
	note("clip with a NaN plane", "%s / %s" % [nan_plane.ok, nan_plane.message])
	if nan_plane.ok:
		flag("a NaN clip plane was accepted")
	var single = root.brush_system.can_merge_brushes([target_id])
	if single.ok:
		flag("merging a single brush was accepted")
