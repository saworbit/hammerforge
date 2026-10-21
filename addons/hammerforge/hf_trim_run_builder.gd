@tool
extends RefCounted
class_name HFTrimRunBuilder

## A skirting or a cornice run along a room's walls (#1414): a trim profile swept
## along the bottom or top edges of wall faces picked in Face Select, mitred at
## every corner and stopped square at every doorway.
##
## By hand a room's skirting is one strip per wall, each cut to length and mitred
## where it meets the next, and moving a wall means redoing the strips either
## side. Here the faces' edges are read once, chained into runs and kept on the
## structure's record beside its settings, so an Update lays another profile or
## size along the same run, and Re-pick reads the run again from the faces picked
## now.
##
## Unlike the other builders this one is not built about its own middle from its
## settings alone. `read()` turns faces of the level into a run, and
## `build_along()` lays the trim along it. A run is plain data, as a level file
## holds it:
##
##     {"bottom": [run, ...], "top": [run, ...]}
##
## both edges read at once, so switching Edge needs no Re-pick. Each run is
## `{"points": [[x, y, z], ...], "closed": bool, "gaps": [...], "faces": [...]}`:
## its corners in order, with the faces' room side on the right of travel seen
## from above, which is where `HFPathSweep` lays a band of positive offsets; one
## list of doorways per segment, each the outline a Cutout brush makes on the
## face as `[[along, up], ...]`, measured from the segment's start and from its
## edge's height; and the face each segment was read from, for a message to name.
## The doorways are kept as outlines rather than as gaps because whether a
## doorway breaks the trim depends on the trim's height and offset, which an
## Update may change: a window cut above a skirting leaves it whole, and the same
## window ends a dado rail run at its sill height.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFOpResult = preload("hf_op_result.gd")
const PathSweep = preload("hf_path_sweep.gd")
const TrimProfile = preload("hf_trim_profile.gd")
@warning_ignore_restore("shadowed_global_identifier")

const EDGE_BOTTOM := 0
const EDGE_TOP := 1

## How far a face's normal may lean from level, as its height, and still count as
## upright. About a twentieth of a degree: a wall turned about Y comes out well
## inside it, and a sloped face is nowhere near.
const UPRIGHT := 0.001

## How far in front of a face another brush has to reach to hide it. A floor that
## stops at the wall hides the wall's foot; one that stops short of it by more
## than this does not.
const COVER := 0.01

## How near two edges' ends have to be to meet at a corner.
const JOIN := 0.01

## How far from a face's lowest or highest point a corner may be and still lie
## on that edge.
const LEVEL := 0.001

## A piece of a face thinner than this, its area over its perimeter, is the
## rounding of a cut rather than anything a mapper can see.
const THIN := 0.0002


static func settings_schema() -> Array:
	return [
		{
			"key": "edge",
			"label": "Edge",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": ["Bottom", "Top"],
			"default": EDGE_BOTTOM,
			"tooltip":
			"Run along the faces' bottom edges, a skirting, or their top edges, a cornice",
		},
		{
			"key": "offset",
			"label": "Offset",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.0,
			"max": 1024.0,
			"step": 0.01,
			"default": 0.0,
			"tooltip":
			"How far in from that edge the trim stands: up from the bottom, down from the top",
		},
		{
			"key": "profile",
			"label": "Profile",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": TrimProfile.NAMES.duplicate(),
			"default": TrimProfile.Profile.FLAT,
			"tooltip": "The shape the trim shows cut square across",
		},
		{
			"key": "width",
			"label": "Width",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.01,
			"max": 64.0,
			"step": 0.01,
			"default": 0.1,
			"tooltip": "How far the trim stands out from the wall",
		},
		{
			"key": "height",
			"label": "Height",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.01,
			"max": 64.0,
			"step": 0.01,
			"default": 0.2,
			"tooltip": "How tall the trim is up the wall",
		},
		{
			"key": "segments",
			"label": "Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": 16,
			"step": 1,
			"default": 4,
			"tooltip": "How many pieces a curve of the profile is cut into",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


## The settings alone. Every field's range is the schema's, and no two fields
## refuse each other: what a trim this size cannot do is turn a corner of a run,
## which `check_along()` answers.
static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	for key in ["width", "height"]:
		if float(merged[key]) <= 0.0:
			return HFOpResult.fail(
				"Trim Run: %s must be greater than zero" % key, "Set a positive %s" % key
			)
	return HFOpResult.success()


# ===========================================================================
# Reading a run from faces
# ===========================================================================


## The run along `picked` faces, read in world space. Each picked face is
## `{"id", "name", "verts", "normal"}`: its brush's id, what a message calls it,
## its corners and its outward normal. `solids` are the brushes that can hide part
## of a face, and `cutters` the Cutout brushes, each `{"id", "planes", "box"}`
## with its outward planes and its bounds.
##
## Returns `{"run", "used", "hidden"}`: the run, how many faces gave it an edge,
## and the names of the faces with none open to the room. Or `{"refused",
## "hint"}`, naming a face that is not upright, or saying no face gave an edge.
static func read(picked: Array, solids: Array, cutters: Array) -> Dictionary:
	if picked.is_empty():
		return _refused(
			"Trim Run: no faces are picked",
			"Enter Face Select and click the wall faces the trim should run along"
		)
	for face: Dictionary in picked:
		var normal: Vector3 = face["normal"]
		if absf(normal.y) > UPRIGHT or Vector2(normal.x, normal.z).length() < 0.5:
			return _refused(
				"Trim Run: %s is not upright, so it has no wall edge to run along" % face["name"],
				"Pick only upright wall faces"
			)
	var bottoms: Array = []
	var tops: Array = []
	var used := 0
	var hidden := PackedStringArray()
	for face: Dictionary in picked:
		var edges := _face_edges(face, solids, cutters)
		if edges["bottom"].is_empty() and edges["top"].is_empty():
			hidden.append(str(face["name"]))
			continue
		used += 1
		bottoms.append_array(edges["bottom"])
		tops.append_array(edges["top"])
	if used == 0:
		return _refused(
			"Trim Run: none of the picked faces has an edge open to the room",
			"Pick the faces you can see, not ones another brush covers"
		)
	return {"run": {"bottom": _chain(bottoms), "top": _chain(tops)}, "used": used, "hidden": hidden}


## The run as it reads in the space `placement` sets up: every corner carried back
## through the placement. The doorways are measured along each segment and up
## from its edge, so they need nothing.
static func in_space(run: Dictionary, placement: Transform3D) -> Dictionary:
	var back := placement.affine_inverse()
	var out := {}
	for edge in ["bottom", "top"]:
		var runs: Array = []
		for one in run.get(edge, []):
			if not (one is Dictionary):
				continue
			var moved: Dictionary = (one as Dictionary).duplicate(true)
			var points: Array = []
			for corner in _points_of(moved.get("points", [])):
				points.append(_plain_point(back * corner))
			moved["points"] = points
			runs.append(moved)
		out[edge] = runs
	return out


## Where a run's structure goes: the middle of its corners, on the ground at
## their lowest, facing the world's way.
static func anchor(run: Dictionary) -> Transform3D:
	var box := AABB()
	var seeded := false
	for edge in ["bottom", "top"]:
		for one in run.get(edge, []):
			if not (one is Dictionary):
				continue
			for corner in _points_of((one as Dictionary).get("points", [])):
				if not seeded:
					box = AABB(corner, Vector3.ZERO)
					seeded = true
				else:
					box = box.expand(corner)
	var middle := box.get_center()
	return Transform3D(Basis.IDENTITY, Vector3(middle.x, box.position.y, middle.z))


## Two runs that build the same trim, read to a thousandth.
static func same_run(a: Dictionary, b: Dictionary) -> bool:
	return _run_text(a) == _run_text(b)


static func _run_text(run: Dictionary) -> String:
	var parts := PackedStringArray()
	for edge in ["bottom", "top"]:
		parts.append(edge)
		for one in _runs_of(run, edge == "top"):
			parts.append("closed" if one["closed"] else "open")
			for corner in one["points"]:
				parts.append("%.3f %.3f %.3f" % [corner.x, corner.y, corner.z])
			for doorways: Array in one["gaps"]:
				parts.append("|")
				for outline: PackedVector2Array in doorways:
					for corner in outline:
						parts.append("%.3f %.3f" % [corner.x, corner.y])
	return ",".join(parts)


## A face's bottom and top edges where they are open to the room, as
## `{"bottom": [edge, ...], "top": [edge, ...]}`. An edge is `{"a", "b", "name",
## "gaps"}`, running with the face's outward side on its right.
static func _face_edges(face: Dictionary, solids: Array, cutters: Array) -> Dictionary:
	var normal: Vector3 = face["normal"]
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var along := Vector3(flat.z, 0.0, -flat.x)
	var verts: PackedVector3Array = face["verts"]
	var origin: Vector3 = verts[0]
	var reach := _bounds(verts).grow(COVER * 2.0)
	# What another brush hides is what lies just in front of the face inside it:
	# a floor that stops at the wall hides the wall's foot, and the wall it butts
	# into hides the end of the face that runs on past the corner.
	var pieces: Array = [verts]
	for solid: Dictionary in solids:
		if str(solid["id"]) == str(face["id"]) or not (solid["box"] as AABB).intersects(reach):
			continue
		# A brush with no faces encloses nothing, and must not read as hiding all.
		if (solid["planes"] as Array).is_empty():
			continue
		var shifted: Array = []
		for plane: Plane in solid["planes"]:
			shifted.append(Plane(plane.normal, plane.d - COVER * plane.normal.dot(flat)))
		pieces = _without(pieces, shifted)
		if pieces.is_empty():
			return {"bottom": [], "top": []}
	# A doorway takes away the wall just behind the face. A cut that only stands
	# against the face from the room's side, a pit in the floor beside the wall,
	# takes none of it and leaves the trim whole.
	var doorways: Array = []
	for cutter: Dictionary in cutters:
		if not (cutter["box"] as AABB).intersects(reach) or (cutter["planes"] as Array).is_empty():
			continue
		var behind: Array = []
		for plane: Plane in cutter["planes"]:
			behind.append(Plane(plane.normal, plane.d + COVER * plane.normal.dot(flat)))
		var hole := _inside(verts, behind)
		if not hole.is_empty():
			doorways.append(hole)
	var low := INF
	var high := -INF
	for piece: PackedVector3Array in pieces:
		for corner in piece:
			low = minf(low, corner.y)
			high = maxf(high, corner.y)
	var out := {"bottom": [], "top": []}
	for edge in ["bottom", "top"]:
		var height := low if edge == "bottom" else high
		for span: Vector2 in _level_spans(pieces, height, along, origin):
			var a := origin + along * span.x
			var b := origin + along * span.y
			a.y = height
			b.y = height
			var gaps: Array = []
			for hole: PackedVector3Array in doorways:
				var outline := PackedVector2Array()
				for corner in hole:
					outline.append(
						Vector2((corner - origin).dot(along) - span.x, corner.y - height)
					)
				gaps.append(outline)
			out[edge].append({"a": a, "b": b, "name": str(face["name"]), "gaps": gaps})
	return out


## The stretches of the pieces' edges that lie level at `height`, as spans of
## distance along the face from `origin`, joined where they touch.
static func _level_spans(pieces: Array, height: float, along: Vector3, origin: Vector3) -> Array:
	var spans: Array = []
	for piece: PackedVector3Array in pieces:
		for i in piece.size():
			var a := piece[i]
			var b := piece[(i + 1) % piece.size()]
			if absf(a.y - height) > LEVEL or absf(b.y - height) > LEVEL:
				continue
			var from := (a - origin).dot(along)
			var to := (b - origin).dot(along)
			spans.append(Vector2(minf(from, to), maxf(from, to)))
	spans.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
	var joined: Array = []
	for span: Vector2 in spans:
		if not joined.is_empty() and span.x <= (joined[-1] as Vector2).y + JOIN:
			joined[-1] = Vector2(joined[-1].x, maxf(joined[-1].y, span.y))
		else:
			joined.append(span)
	var out: Array = []
	for span: Vector2 in joined:
		if span.y - span.x >= PathSweep.MIN_SEGMENT:
			out.append(span)
	return out


## Edges that meet end to start, chained into runs. A run that comes back to its
## first edge is closed. One that does not starts at an edge nothing leads into,
## so it is read whole from its start.
static func _chain(edges: Array) -> Array:
	var used: Array[bool] = []
	used.resize(edges.size())
	used.fill(false)
	var chains: Array = []
	for first in edges.size():
		if not used[first] and _edge_into(edges, used, first) < 0:
			chains.append(_follow(edges, used, first))
	for first in edges.size():
		if not used[first]:
			chains.append(_follow(edges, used, first))
	var runs: Array = []
	for chain: Array in chains:
		runs.append(_run_of(edges, chain))
	return runs


## An unused edge, other than `index`, that ends where `index` starts. -1 for none.
static func _edge_into(edges: Array, used: Array[bool], index: int) -> int:
	var start: Vector3 = edges[index]["a"]
	for other in edges.size():
		if (
			other != index
			and not used[other]
			and (edges[other]["b"] as Vector3).distance_to(start) <= JOIN
		):
			return other
	return -1


static func _follow(edges: Array, used: Array[bool], first: int) -> Array:
	var chain: Array = [first]
	used[first] = true
	while true:
		var end: Vector3 = edges[chain[-1]]["b"]
		var next := -1
		for other in edges.size():
			if not used[other] and (edges[other]["a"] as Vector3).distance_to(end) <= JOIN:
				next = other
				break
		if next < 0:
			break
		used[next] = true
		chain.append(next)
	return chain


## A chain of edges as a run's plain data. A corner where two edges' ends do not
## quite agree is put halfway between them.
static func _run_of(edges: Array, chain: Array) -> Dictionary:
	var last: Dictionary = edges[chain[-1]]
	var closed: bool = (
		chain.size() >= 3 and (last["b"] as Vector3).distance_to(edges[chain[0]]["a"]) <= JOIN
	)
	var points: Array = []
	var gaps: Array = []
	var faces: Array = []
	for i in chain.size():
		var edge: Dictionary = edges[chain[i]]
		var corner: Vector3 = edge["a"]
		if i > 0 or closed:
			var before: Dictionary = edges[chain[(i - 1 + chain.size()) % chain.size()]]
			corner = (corner + (before["b"] as Vector3)) * 0.5
		points.append(_plain_point(corner))
		var outlines: Array = []
		for outline: PackedVector2Array in edge["gaps"]:
			var plain: Array = []
			for at in outline:
				plain.append([at.x, at.y])
			outlines.append(plain)
		gaps.append(outlines)
		faces.append(str(edge["name"]))
	if not closed:
		points.append(_plain_point(last["b"]))
	return {"points": points, "closed": closed, "gaps": gaps, "faces": faces}


## `pieces` with the region behind every one of `planes` taken out: each piece
## that reaches into it is cut into the convex pieces that lie outside it, one
## in front of each plane in turn.
static func _without(pieces: Array, planes: Array) -> Array:
	var out: Array = []
	for piece: PackedVector3Array in pieces:
		if _inside(piece, planes).is_empty():
			out.append(piece)
			continue
		var rest := piece
		for plane: Plane in planes:
			var front := _clip(rest, plane, true)
			if not front.is_empty():
				out.append(front)
			rest = _clip(rest, plane, false)
			if rest.is_empty():
				break
	return out


## The part of a convex `ring` behind every one of `planes`, or empty.
static func _inside(ring: PackedVector3Array, planes: Array) -> PackedVector3Array:
	var rest := ring
	for plane: Plane in planes:
		rest = _clip(rest, plane, false)
		if rest.is_empty():
			break
	return rest


## The part of `ring` on one side of `plane`, or empty when it encloses nothing a
## mapper could see.
static func _clip(ring: PackedVector3Array, plane: Plane, keep_front: bool) -> PackedVector3Array:
	var verts: PackedVector3Array = (
		HFConvexClip.clip_polygon(ring, PackedVector2Array(), plane, keep_front)["verts"]
	)
	if verts.size() < 3:
		return PackedVector3Array()
	var twice := Vector3.ZERO
	var perimeter := 0.0
	for i in verts.size():
		var a := verts[i]
		var b := verts[(i + 1) % verts.size()]
		twice += a.cross(b)
		perimeter += a.distance_to(b)
	var area := twice.length() * 0.5
	if perimeter <= 0.0 or area / perimeter < THIN:
		return PackedVector3Array()
	return verts


static func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for corner in points:
		box = box.expand(corner)
	return box


static func _refused(message: String, hint: String) -> Dictionary:
	return {"refused": message, "hint": hint}


static func _plain_point(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# ===========================================================================
# Building along a run
# ===========================================================================


## Whether these settings build along `run`, and if not, why not: the run has
## no edge of the chosen kind, it turns straight back on itself, or one of its
## faces is too short for a trim this wide to turn both its corners.
static func check_along(settings: Dictionary, run: Dictionary) -> HFOpResult:
	var check := validate(settings)
	if not check.ok:
		return check
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var top := int(merged["edge"]) == EDGE_TOP
	var runs := _runs_of(run, top)
	if runs.is_empty():
		return HFOpResult.fail(
			"Trim Run: its faces have no %s edge to run along" % ("top" if top else "bottom"),
			"Re-pick faces that have one, or switch Edge"
		)
	var width: float = merged["width"]
	for one: Dictionary in runs:
		var points: PackedVector3Array = one["points"]
		var faces: PackedStringArray = one["faces"]
		var swept := PathSweep.sweep(points, one["closed"], true, 0.0, width)
		var at := int(swept["at"])
		match str(swept["fault"]):
			"doubles_back":
				return HFOpResult.fail(
					(
						"Trim Run: %s and %s meet back to back, so the trim cannot turn there"
						% [_face_name(faces, at - 1), _face_name(faces, at)]
					),
					"Re-pick without one of them"
				)
			"too_short":
				var short := [_face_name(faces, at), float(swept["length"]), width]
				var text := "Trim Run: %s is %.2f long, too short for trim %.2f wide to turn its corners"
				return HFOpResult.fail(
					text % short, "Narrow the trim, or Re-pick without that face"
				)
	return HFOpResult.success()


## The trim laid along `run`: one piece per band of the profile per stretch of
## each segment, in the structure's own space. Empty when `check_along()` refuses.
static func build_along(settings: Dictionary, run: Dictionary) -> Array:
	if not check_along(settings, run).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var top := int(merged["edge"]) == EDGE_TOP
	var width: float = merged["width"]
	var height: float = merged["height"]
	var offset: float = merged["offset"]
	# A cornice hangs its profile from the top: the section turned upside down,
	# its foot `offset` and its own height below the edge.
	var foot := -offset - height if top else offset
	var bands := TrimProfile.bands(
		int(merged["profile"]), width, height, int(merged["segments"]), top
	)
	var out: Array = []
	for one: Dictionary in _runs_of(run, top):
		var points: PackedVector3Array = one["points"]
		var cuts: Array = PathSweep.sweep(points, one["closed"], true, 0.0, width)["cuts"]
		for k in cuts.size():
			var a := points[k]
			var b := points[(k + 1) % points.size()]
			var base := (a.y + b.y) * 0.5 + foot
			var direction := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var length := direction.length()
			direction /= length
			for span: Vector2 in _open_spans(one["gaps"][k], length, foot, height):
				var start: Dictionary = cuts[k][0]
				var end: Dictionary = cuts[k][1]
				# A stretch that stops at a doorway ends square across, as the
				# doorway's own side does.
				if span.x > 0.0:
					start = PathSweep.square_cut(a + direction * span.x, direction)
				if span.y < length:
					end = PathSweep.square_cut(a + direction * span.y, direction)
				var ends := PackedVector3Array([a + direction * span.x, a + direction * span.y])
				# A sliver between a corner's mitre and a doorway too near it has no
				# room for both cuts, and is left out.
				if PathSweep.footprints(ends, [[start, end]], 0.0, width)["fault"] != "":
					continue
				for band: PackedVector2Array in bands:
					var faces := PathSweep.section_solid(start, end, band, base, Vector3.ZERO)
					if not faces.is_empty():
						out.append(faces)
	return out


## The stretches of a segment `length` long left open by its doorways, as spans
## along it. A doorway breaks the trim where its outline reaches into the band
## from `foot` to `foot + height` above the edge.
static func _open_spans(doorways: Array, length: float, foot: float, height: float) -> Array:
	var closed_off: Array = []
	for outline: PackedVector2Array in doorways:
		var ring := PackedVector3Array()
		for corner in outline:
			ring.append(Vector3(corner.x, corner.y, 0.0))
		ring = _clip(ring, Plane(Vector3.UP, foot), true)
		ring = _clip(ring, Plane(Vector3.UP, foot + height), false)
		if ring.is_empty():
			continue
		var from := INF
		var to := -INF
		for corner in ring:
			from = minf(from, corner.x)
			to = maxf(to, corner.x)
		if to > 0.0 and from < length:
			closed_off.append(Vector2(maxf(from, 0.0), minf(to, length)))
	closed_off.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
	var out: Array = []
	var at := 0.0
	for gap: Vector2 in closed_off:
		if gap.x - at >= PathSweep.MIN_SEGMENT:
			out.append(Vector2(at, gap.x))
		at = maxf(at, gap.y)
	if length - at >= PathSweep.MIN_SEGMENT:
		out.append(Vector2(at, length))
	return out


## The runs of one edge of `run`, read from its plain data: `{"points":
## PackedVector3Array, "closed", "gaps": one Array of PackedVector2Array per
## segment, "faces": PackedStringArray}`. A run whose data is not a run's, as a
## file edited by hand can make, is left out rather than read wrongly.
static func _runs_of(run: Dictionary, top: bool) -> Array:
	var out: Array = []
	var listed = run.get("top" if top else "bottom", [])
	if not (listed is Array):
		return out
	for one in listed:
		if not (one is Dictionary):
			continue
		var points := _points_of((one as Dictionary).get("points", []))
		var closed := bool((one as Dictionary).get("closed", false)) and points.size() >= 3
		var count := PathSweep.segment_count(points.size(), closed)
		if count < 1 or PathSweep.distinct(points, closed).size() != points.size():
			continue
		var gaps: Array = []
		var stored = (one as Dictionary).get("gaps", [])
		for k in count:
			var doorways: Array = []
			if stored is Array and k < (stored as Array).size() and stored[k] is Array:
				for outline in stored[k]:
					var corners := _outline_of(outline)
					if corners.size() >= 3:
						doorways.append(corners)
			gaps.append(doorways)
		var faces := PackedStringArray()
		var names = (one as Dictionary).get("faces", [])
		for k in count:
			var named := names is Array and k < (names as Array).size()
			faces.append(str(names[k]) if named else "face %d of the run" % (k + 1))
		out.append({"points": points, "closed": closed, "gaps": gaps, "faces": faces})
	return out


static func _points_of(value) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not (value is Array):
		return out
	for entry in value:
		if not (entry is Array) or (entry as Array).size() < 3:
			return PackedVector3Array()
		var corner := Vector3(_number(entry[0]), _number(entry[1]), _number(entry[2]))
		if not corner.is_finite():
			return PackedVector3Array()
		out.append(corner)
	return out


static func _outline_of(value) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (value is Array):
		return out
	for entry in value:
		if not (entry is Array) or (entry as Array).size() < 2:
			return PackedVector2Array()
		var corner := Vector2(_number(entry[0]), _number(entry[1]))
		if not corner.is_finite():
			return PackedVector2Array()
		out.append(corner)
	return out


static func _number(value) -> float:
	return float(value) if value is float or value is int else NAN


static func _face_name(faces: PackedStringArray, index: int) -> String:
	if faces.is_empty():
		return "a face"
	return faces[posmod(index, faces.size())]
