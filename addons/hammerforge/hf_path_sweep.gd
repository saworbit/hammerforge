@tool
extends RefCounted

## Sweeps a band along a path, one convex piece per segment, with every corner
## mitred (#1412). The Path tool builds its walls and its trim here.
##
## A band is the strip between two offsets from the clicked line, measured to the
## right of the direction of travel as seen from above: a wall of width w centred
## on the line is [-w/2, w/2], one standing to the left of it is [-w, 0]. A
## segment's piece is the strip between its two offset lines, cut at each end by
## the vertical plane that bisects the corner there. Two parallel sides and two
## cut ends make a trapezoid, which is convex, and the two pieces at a corner are
## cut by the one plane, so they meet on it with no overlap and nothing between.
##
## A sharp corner sends its outside tip a long way out: nearly six band widths at
## 20 degrees. Past `MITRE_LIMIT` widths from the inside corner the tip is cut
## flat, square to the bisector, which gives each piece there one more face and
## keeps it convex. That flat cut belongs to the corner, worked out once for the
## band the path is swept with, so any other band laid along the same cuts (trim
## beside a wall, the pieces of a profile) is cut on the same plane.
##
## Everything happens in X and Z. Points are Vector3; their Y is the caller's,
## and footprints come back at Y = 0.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFConvexClip = preload("hf_convex_clip.gd")
@warning_ignore_restore("shadowed_global_identifier")

## A point nearer than this to the one before it, in X and Z, adds no segment: it
## has no direction for a corner to be cut across.
const MIN_SEGMENT := 0.01

## The least a piece's side may measure once both its ends are cut. Any less and
## the two cuts meet or cross inside the segment.
const MIN_ROOM := 0.001

## How far an outside tip may reach from the inside corner, in band widths, before
## it is cut flat. 4 is the usual default for a mitre limit, and cuts any corner
## sharper than about 29 degrees.
const MITRE_LIMIT := 4.0

## How near a turn may come to doubling straight back, as one plus the cosine of
## the turn. At zero the two segments lie along one line, running opposite ways,
## and the corner has no bisector to cut along.
const REVERSAL := 0.0001


## `points` without any that repeat the one before them in X and Z, and, for a
## closed path, without any at the end that repeat the first.
static func distinct(points: PackedVector3Array, closed: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in points:
		if out.size() > 0 and _flat(point - out[out.size() - 1]).length() < MIN_SEGMENT:
			continue
		out.append(point)
	if closed:
		while out.size() >= 2 and _flat(out[out.size() - 1] - out[0]).length() < MIN_SEGMENT:
			out.remove_at(out.size() - 1)
	return out


## How many segments `count` points make: one back to the first when closed.
static func segment_count(count: int, closed: bool) -> int:
	if count < 2:
		return 0
	return count if closed else count - 1


## Cut the corners of `points` (from `distinct()`) and sweep the band [lo, hi]
## along them. Returns a Dictionary:
##
## - "cuts": one [start, end] pair per segment. A cut holds the corner's "point";
##   its "mitre", the vector that takes the point to offset o as point + mitre * o;
##   the "normal" of its plane, facing the way the path runs; and, past the mitre
##   limit, the "tip" Plane that cuts the outside flat, keeping what is behind it.
##   The two segments at a corner hold the same cut.
## - "footprints": each segment's piece, as `footprints()` makes it.
## - "fault": "" when the band fits. "doubles_back" when the path turns straight
##   back on itself at point "at". "too_short" when segment "at", "length" long,
##   has no room for its two cuts, which need it longer than "needs".
##
## Not mitred, every end is cut square to its own segment, as separate boxes are.
static func sweep(
	points: PackedVector3Array,
	closed: bool,
	mitred: bool,
	lo: float,
	hi: float,
	limit: float = MITRE_LIMIT
) -> Dictionary:
	var result := _empty_result()
	result["cuts"] = []
	var n := points.size()
	var segments := segment_count(n, closed)
	if segments < 1:
		return result
	var directions: Array[Vector3] = []
	for k in segments:
		directions.append(_flat(points[(k + 1) % n] - points[k]).normalized())
	# A corner is where two segments meet: every point of a closed path, and the
	# points between the ends of an open one.
	var corners: Array = []
	corners.resize(n)
	if mitred:
		for i in n:
			if not closed and (i == 0 or i == n - 1):
				continue
			var corner := _corner(
				points[i],
				directions[(i - 1 + segments) % segments],
				directions[i % segments],
				hi - lo,
				lo,
				limit
			)
			if corner.is_empty():
				result["fault"] = "doubles_back"
				result["at"] = i
				return result
			corners[i] = corner
	var cuts: Array = []
	for k in segments:
		var start: Variant = corners[k]
		var end: Variant = corners[(k + 1) % n]
		if start == null:
			start = _square(points[k], directions[k])
		if end == null:
			end = _square(points[(k + 1) % n], directions[k])
		cuts.append([start, end])
	var swept := footprints(points, cuts, lo, hi)
	swept["cuts"] = cuts
	return swept


## Each segment's piece of the band [lo, hi] under `cuts` from `sweep()`, as a
## ring of corners in X and Z at Y = 0. A band other than the one the cuts were
## worked out for is cut flat on the same planes. Returns a Dictionary with
## "footprints", "fault", "at", "length" and "needs", the fault being
## "too_short" as `sweep()` describes it.
static func footprints(points: PackedVector3Array, cuts: Array, lo: float, hi: float) -> Dictionary:
	var result := _empty_result()
	var n := points.size()
	for k in cuts.size():
		var start: Dictionary = cuts[k][0]
		var end: Dictionary = cuts[k][1]
		var run := _flat(points[(k + 1) % n] - points[k])
		var direction := run.normalized()
		var room := minf(_room(start, end, direction, lo), _room(start, end, direction, hi))
		if room <= MIN_ROOM:
			result["fault"] = "too_short"
			result["at"] = k
			result["length"] = run.length()
			# Moving the far end out moves its cut with it, so every side gains
			# exactly what the segment does.
			result["needs"] = run.length() - room
			result["footprints"] = []
			return result
		var ring := PackedVector3Array(
			[_offset(start, lo), _offset(end, lo), _offset(end, hi), _offset(start, hi)]
		)
		for cut: Dictionary in [start, end]:
			if cut.has("tip"):
				ring = (
					HFConvexClip
					. clip_polygon(ring, PackedVector2Array(), cut["tip"], false)["verts"]
				)
		result["footprints"].append(ring)
	return result


## A footprint stood up from `bottom` to `top`: the faces of a convex prism, local
## to `origin` and wound clockwise from outside. Empty when it encloses nothing.
static func prism(
	footprint: PackedVector3Array, bottom: float, top: float, origin: Vector3
) -> Array:
	var low := PackedVector3Array()
	var high := PackedVector3Array()
	for corner in footprint:
		low.append(Vector3(corner.x, bottom, corner.z) - origin)
		high.append(Vector3(corner.x, top, corner.z) - origin)
	var rings: Array = [low, high]
	var count := footprint.size()
	for i in count:
		var j := (i + 1) % count
		rings.append(PackedVector3Array([low[i], low[j], high[j], high[i]]))
	return HFConvexClip.solid_from_rings(rings)


## A section swept along one segment, from its `start` cut to its `end` cut: the
## faces of a convex solid, local to `origin` and wound clockwise from outside.
## `section` is a convex ring of corners, each an offset as a band's are and a
## height above `base`. Every corner runs straight from one cut to the other, so
## the solid's ends lie on the cuts, and two segments that share a cut meet on it
## face to face. A cut's flat tip is taken off as `footprints()` takes it off a
## footprint. Empty when it encloses nothing.
##
## A section that is a band [lo, hi] by a height is what `prism()` stands up from
## the band's footprint. A trim profile is the reason for this one: its bands
## slope (#1413).
static func section_solid(
	start: Dictionary, end: Dictionary, section: PackedVector2Array, base: float, origin: Vector3
) -> Array:
	var near := PackedVector3Array()
	var far := PackedVector3Array()
	for corner in section:
		var up := Vector3(0.0, base + corner.y, 0.0)
		near.append(_offset(start, corner.x) + up - origin)
		far.append(_offset(end, corner.x) + up - origin)
	var rings: Array = [near, far]
	var count := section.size()
	for i in count:
		var j := (i + 1) % count
		rings.append(PackedVector3Array([near[i], near[j], far[j], far[i]]))
	var faces := HFConvexClip.solid_from_rings(rings)
	for cut: Dictionary in [start, end]:
		if cut.has("tip") and not faces.is_empty():
			# The tip is a plane in the path's own space, and the faces are local.
			var tip: Plane = cut["tip"]
			faces = (
				HFConvexClip.split(faces, Plane(tip.normal, tip.d - tip.normal.dot(origin)))["back"]
			)
	return faces


## The part of a segment's `footprint` between the fractions `from` and `to` of
## its length, given its `start` and `end` cuts. Where the part stops short of an
## end it is cut across on a line leaning part way from one end's cut to the
## other's, so the parts of one segment fan between its two cuts and never cross,
## and two parts meeting there share the line. A stair's tread is one (#1436).
static func slice(
	footprint: PackedVector3Array, start: Dictionary, end: Dictionary, from: float, to: float
) -> PackedVector3Array:
	var ring := footprint
	if from > 0.0:
		ring = (
			HFConvexClip
			. clip_polygon(ring, PackedVector2Array(), _plane_between(start, end, from), true)["verts"]
		)
	if to < 1.0:
		ring = (
			HFConvexClip
			. clip_polygon(ring, PackedVector2Array(), _plane_between(start, end, to), false)["verts"]
		)
	return ring if ring.size() >= 3 else PackedVector3Array()


## The upright plane across a segment at fraction `t` of its length, leaning as
## far from its `start` cut toward its `end` cut, facing the way the path runs.
static func _plane_between(start: Dictionary, end: Dictionary, t: float) -> Plane:
	var point: Vector3 = (start["point"] as Vector3).lerp(end["point"], t)
	var mitre: Vector3 = (start["mitre"] as Vector3).lerp(end["mitre"], t)
	# The plane holds the mitre and the upright, so its normal is the mitre turned
	# back a quarter: the inverse of `right_of()`.
	var normal := Vector3(mitre.z, 0.0, -mitre.x).normalized()
	return Plane(normal, normal.dot(point))


## The right of `direction` as seen from above, which is where positive offsets
## lie. Godot looks down on X running right and Z running down the screen.
static func right_of(direction: Vector3) -> Vector3:
	return Vector3(-direction.z, 0.0, direction.x)


static func _empty_result() -> Dictionary:
	return {"footprints": [], "fault": "", "at": -1, "length": 0.0, "needs": 0.0}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## An end cut square across a segment running in `direction`.
static func _square(point: Vector3, direction: Vector3) -> Dictionary:
	return {"point": _flat(point), "mitre": right_of(direction), "normal": direction}


## The cut where a segment running `d_in` turns to run `d_out`, or an empty
## Dictionary when it turns straight back. A point at offset o on both segments'
## offset lines is o along each one's right, so `mitre` has a dot product of 1
## with both rights: their sum over one plus the cosine of the turn.
static func _corner(
	point: Vector3, d_in: Vector3, d_out: Vector3, width: float, lo: float, limit: float
) -> Dictionary:
	var bend := 1.0 + d_in.dot(d_out)
	if bend < REVERSAL:
		return {}
	var mitre := (right_of(d_in) + right_of(d_out)) / bend
	var cut := {"point": _flat(point), "mitre": mitre, "normal": (d_in + d_out).normalized()}
	# Inside corner to outside tip is width * |mitre|, so the limit reads on
	# |mitre| alone and the angle it cuts at does not depend on the band.
	if width > 0.0 and mitre.length() > limit:
		# A turn to the right has its outside on the left, the lower offset.
		var turns_right := right_of(d_in).dot(d_out) > 0.0
		var outer := lo if turns_right else lo + width
		var inner := lo + width if turns_right else lo
		var outward := (mitre * (outer - inner)).normalized()
		var flat_at: Vector3 = cut["point"] + mitre * inner + outward * (limit * width)
		cut["tip"] = Plane(outward, outward.dot(flat_at))
	return cut


static func _offset(cut: Dictionary, offset: float) -> Vector3:
	return cut["point"] + cut["mitre"] * offset


## How long the side of a segment's piece at `offset` is between its two ends,
## each cut by its mitre and any flat tip. Negative when the cuts cross.
static func _room(start: Dictionary, end: Dictionary, direction: Vector3, offset: float) -> float:
	var origin: Vector3 = start["point"] + right_of(direction) * offset
	var start_normal: Vector3 = start["normal"]
	var end_normal: Vector3 = end["normal"]
	# Every plane keeps the side behind it: the start's mitre faces back.
	var planes: Array = [
		Plane(-start_normal, -start_normal.dot(start["point"])),
		Plane(end_normal, end_normal.dot(end["point"])),
	]
	for cut: Dictionary in [start, end]:
		if cut.has("tip"):
			planes.append(cut["tip"])
	var from := -INF
	var to := INF
	for plane: Plane in planes:
		var along := plane.normal.dot(direction)
		var past := plane.distance_to(origin)
		if absf(along) < 0.000001:
			if past > 0.0:
				return -INF
			continue
		var t := -past / along
		if along > 0.0:
			to = minf(to, t)
		else:
			from = maxf(from, t)
	return to - from
