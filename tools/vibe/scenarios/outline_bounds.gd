@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The selection outline every brush shape draws, against the geometry that
## brush actually has.
##
## `BrushInstance.get_editor_outline_lines()` is the one source for both the
## idle hover highlight and the native selection gizmo, and it is built from the
## brush's `size` by a set of per-shape line functions in `HFOutlineUtil` rather
## than from the brush's faces. Nothing checks that the two describe the same
## solid. When they disagree the mapper is shown a box that is not where the
## brush is, which is the one piece of feedback a click-to-select editor cannot
## get wrong.

const SHAPES := [
	["box", 0],
	["cylinder", 1],
	["sphere", 2],
	["cone", 3],
	["wedge", 4],
	["pyramid", 5],
	["prism_tri", 6],
	["prism_pent", 7],
	["ellipsoid", 8],
	["capsule", 9],
	["torus", 10],
	["tetrahedron", 11],
	["octahedron", 12],
	["dodecahedron", 13],
	["icosahedron", 14],
]

## Deliberately not a cube: a shape function that drops an axis, or reads one
## axis where it meant another, only shows up against an asymmetric request.
const REQUEST := Vector3(96.0, 48.0, 32.0)


func id() -> String:
	return "outline-bounds"


func summary() -> String:
	return "whether each shape's selection outline encloses the geometry it is drawn around"


func run() -> void:
	await _outline_against_geometry()


static func _bounds(points: PackedVector3Array) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return hi - lo


func _outline_against_geometry() -> void:
	var root: Node3D = await fresh_root("OutlineLevel")
	var mismatches: Array = []
	var empties: Array = []
	for entry in SHAPES:
		var label: String = entry[0]
		var shape: int = entry[1]
		var brush = root.create_brush_from_info({"shape": shape, "size": REQUEST})
		await frame()
		if brush == null:
			note("%s: no brush built" % label)
			continue
		var lines: PackedVector3Array = brush.get_editor_outline_lines()
		var outline: Vector3 = _bounds(lines)
		var geometry: Vector3 = HFVibe.local_extent(brush)
		note(
			"%s: outline %s" % [label, outline],
			"geometry %s, segments %d" % [geometry, lines.size() / 2]
		)
		if lines.is_empty():
			empties.append(label)
			continue
		# An outline may legitimately sit inside a curved hull -- a 16-segment
		# circle is a little smaller than the cylinder it traces. It may not be
		# larger than the solid on any axis, and it may not be a different size
		# on an axis the shape actually uses.
		for axis in range(3):
			var drawn: float = outline[axis]
			var real: float = geometry[axis]
			if real <= 0.0001:
				continue
			var ratio: float = drawn / real
			if ratio > 1.02 or ratio < 0.85:
				mismatches.append(
					(
						"%s axis %s: outline %.2f against geometry %.2f (%.2fx)"
						% [label, "xyz"[axis], drawn, real, ratio]
					)
				)
	note("shapes whose outline does not fit the geometry", mismatches.size())
	if not empties.is_empty():
		flag(
			"a brush shape draws no selection outline at all",
			"nothing is highlighted on hover and the selection gizmo has no wire: %s" % str(empties)
		)
	if not mismatches.is_empty():
		flag(
			"the selection outline is not the size of the brush it is drawn around",
			(
				(
					"the outline is built from `size` by a per-shape line function and the"
					+ " geometry is built from `size` by a different one, and these two"
					+ " disagree, so hover highlight and the selection wire sit where the"
					+ " brush is not: %s"
				)
				% str(mismatches)
			)
		)
	await frame()
