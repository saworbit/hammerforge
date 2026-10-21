@tool
extends RefCounted

## The cross-section of a trim strip (#1413): a kerb, plinth, skirting, dado rail
## or cornice, as the shape the strip shows when it is cut square across.
##
## A section is measured in two numbers: "out", how far from the face the strip
## stands against, and "up", how high above the strip's base. It fills the corner
## between the face and the base out to the strip's width and up to its height,
## and its outline is the strip's outer edge, from the base's outer corner
## (width, 0) up to the top against the face (0, height).
##
## A brush has to be convex, and a cove or an ogee is not. So a section is handed
## out as bands: horizontal slices, each bounded by the face, two levels and the
## piece of outline between them, every one convex. A run of outline that bulges
## outward stays whole in one band. A run that curves inward is one band per
## piece, a trapezoid, because a straight piece between two levels is all a slice
## of it can hold and stay convex. Nothing here knows about paths: a sweep takes
## the bands and lays them along whatever it follows.

enum Profile { FLAT, CHAMFER, ROUND, COVE, OGEE, STEPPED }

## The profiles' names, in `Profile` order, for a setting's options.
const NAMES := ["Flat", "Chamfer", "Round", "Cove", "Ogee", "Stepped"]

## How many steps Stepped has. Segments counts the pieces a curve is cut into,
## and a step has no curve.
const STEPS := 3

## The least a band may measure up, or out at its widest, where a finer cut of a
## curve would make it: the thickness under which Validate calls a brush
## near-zero. Such a curve point is left out instead, so a small trim gets fewer
## bands than its Segments asks for.
const MIN_BAND := 0.01

## How far from straight a turn in a band's outline has to be, as the sine of its
## angle, to count as a turn rather than a straight run through a point.
const STRAIGHT := 0.000001


## The outline of `profile`, `width` out by `height` up, with each curve cut into
## `segments` pieces: its corners from the base's outer corner up to the top
## against the face, as `bands()` slices it.
static func outline(profile: int, width: float, height: float, segments: int) -> PackedVector2Array:
	return _thinned(_raw_outline(profile, width, height, segments))["points"]


## The section of `profile`, `width` out by `height` up, as convex bands, each a
## ring of (out, up) corners wound anticlockwise, bottom band first. Flipped, the
## section is turned upside down within its own height, for a cornice hung from
## the top of a wall rather than a skirting standing on the floor.
static func bands(
	profile: int, width: float, height: float, segments: int, flipped := false
) -> Array:
	if width <= 0.0 or height <= 0.0:
		return []
	var points: PackedVector2Array = _thinned(_raw_outline(profile, width, height, segments))["points"]
	var out: Array = []
	for range_of: Vector2i in _band_ranges(points):
		var ring := _band_ring(points, range_of.x, range_of.y)
		# A level run of outline at a band's foot gives a ring with no area.
		if ring.size() < 3 or area(ring) < 0.000000001:
			continue
		out.append(_upside_down(ring, height) if flipped else ring)
	return out


## The area a ring encloses, whichever way round it runs.
static func area(ring: PackedVector2Array) -> float:
	var twice := 0.0
	for i in ring.size():
		twice += ring[i].cross(ring[(i + 1) % ring.size()])
	return absf(twice) * 0.5


## The outline with nothing left out, and which of its corners are the profile's
## own rather than points along a curve: {"points", "fixed"}.
static func _raw_outline(profile: int, w: float, h: float, segments: int) -> Dictionary:
	var points := PackedVector2Array()
	var fixed: Array[bool] = []
	var pieces := maxi(segments, 1)
	match profile:
		Profile.CHAMFER:
			# The top outer corner cut off at 45 degrees, half as far as it can go.
			var cut := minf(w, h) * 0.5
			for corner in [
				Vector2(w, 0.0), Vector2(w, h - cut), Vector2(w - cut, h), Vector2(0.0, h)
			]:
				_add(points, fixed, corner, true)
		Profile.ROUND:
			# A bullnose: the top outer corner rounded as far as the strip allows.
			var radius := minf(w, h)
			var centre := Vector2(w - radius, h - radius)
			_add(points, fixed, Vector2(w, 0.0), true)
			_add_arc(points, fixed, centre, Vector2(radius, radius), 0.0, PI * 0.5, pieces)
			_add(points, fixed, Vector2(0.0, h), true)
		Profile.COVE:
			# A quarter of an ellipse hollowed out of the outer corner: all the way out
			# at the base, in to the face at the top.
			_add_arc(points, fixed, Vector2(w, h), Vector2(w, h), -PI * 0.5, -PI, pieces)
		Profile.OGEE:
			# An S: hollow below, rounded above, meeting upright halfway up.
			var half := Vector2(w * 0.5, h * 0.5)
			_add_arc(points, fixed, Vector2(w, h * 0.5), half, -PI * 0.5, -PI, pieces)
			_add_arc(points, fixed, Vector2(0.0, h * 0.5), half, 0.0, PI * 0.5, pieces)
		Profile.STEPPED:
			# Each step in from the one below by the same amount.
			for step in STEPS:
				var reach := w * float(STEPS - step) / float(STEPS)
				_add(points, fixed, Vector2(reach, h * float(step) / float(STEPS)), true)
				_add(points, fixed, Vector2(reach, h * float(step + 1) / float(STEPS)), true)
			_add(points, fixed, Vector2(0.0, h), true)
		_:
			for corner in [Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h)]:
				_add(points, fixed, corner, true)
	return {"points": points, "fixed": fixed}


## Append the arc of the ellipse centred at `centre` with radii `radii` from the
## angle `from` to the angle `to`, cut into `pieces`. Its two ends are the
## profile's own corners; the points between are a curve's, which `_thinned()`
## may leave out.
static func _add_arc(
	points: PackedVector2Array,
	fixed: Array[bool],
	centre: Vector2,
	radii: Vector2,
	from: float,
	to: float,
	pieces: int
) -> void:
	for i in pieces + 1:
		var angle := lerpf(from, to, float(i) / float(pieces))
		var corner := centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		_add(points, fixed, corner, i == 0 or i == pieces)


## Append `corner`, or, where it repeats the last one, mark that one fixed if
## either is.
static func _add(
	points: PackedVector2Array, fixed: Array[bool], corner: Vector2, is_fixed: bool
) -> void:
	var last := points.size() - 1
	if last >= 0 and points[last].distance_to(corner) < 0.000001:
		fixed[last] = fixed[last] or is_fixed
		return
	points.append(corner)
	fixed.append(is_fixed)


## The outline with any curve point left out that would make a band thinner than
## `MIN_BAND`. A thin band of one piece takes in the piece above it, or else the
## one below, by losing the point between them, which keeps it one straight
## piece and so convex. The profile's own corners always stay.
static func _thinned(raw: Dictionary) -> Dictionary:
	var points: PackedVector2Array = raw["points"].duplicate()
	var fixed: Array[bool] = raw["fixed"].duplicate()
	while true:
		var ranges := _band_ranges(points)
		var drop := -1
		for r in ranges.size():
			var band: Vector2i = ranges[r]
			if band.y != band.x + 1 or not _thin(points[band.x], points[band.y]):
				continue
			if not fixed[band.y] and r + 1 < ranges.size() and _one_piece(ranges[r + 1]):
				drop = band.y
			elif not fixed[band.x] and r > 0 and _one_piece(ranges[r - 1]):
				drop = band.x
			if drop >= 0:
				break
		if drop < 0:
			break
		points.remove_at(drop)
		fixed.remove_at(drop)
	return {"points": points, "fixed": fixed}


static func _one_piece(range_of: Vector2i) -> bool:
	return range_of.y == range_of.x + 1


## Whether the band of the one piece from `low` to `high` is thinner than a band
## may be, up or out.
static func _thin(low: Vector2, high: Vector2) -> bool:
	return high.y - low.y < MIN_BAND or maxf(low.x, high.x) < MIN_BAND


## The outline cut into the fewest bands, each the outline from one corner to a
## later one: [first, last] index pairs, bottom band first. A band takes in each
## next corner for as long as it stays convex.
static func _band_ranges(points: PackedVector2Array) -> Array:
	var ranges: Array = []
	var last := points.size() - 1
	var start := 0
	while start < last:
		var end := start + 1
		while end < last and _is_convex(_band_ring(points, start, end + 1)):
			end += 1
		ranges.append(Vector2i(start, end))
		start = end
	return ranges


## The band from outline corner `first` to `last`: back across to the face at
## each end's level, and down the face. Anticlockwise, with no corner repeated
## and none in a straight run.
static func _band_ring(points: PackedVector2Array, first: int, last: int) -> PackedVector2Array:
	var ring := PackedVector2Array([Vector2(0.0, points[first].y)])
	for i in range(first, last + 1):
		ring.append(points[i])
	ring.append(Vector2(0.0, points[last].y))
	return _without_straight_runs(_without_repeats(ring))


static func _without_repeats(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in ring:
		if out.size() > 0 and out[out.size() - 1].distance_to(corner) < 0.000001:
			continue
		out.append(corner)
	while out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) < 0.000001:
		out.remove_at(out.size() - 1)
	return out


static func _without_straight_runs(ring: PackedVector2Array) -> PackedVector2Array:
	var out := ring
	var changed := true
	while changed and out.size() > 3:
		changed = false
		for i in out.size():
			if absf(_turn(out, i)) <= STRAIGHT:
				out.remove_at(i)
				changed = true
				break
	return out


## The sine of the turn at corner `i` of `ring`: positive turning left, which
## every corner of an anticlockwise convex ring does.
static func _turn(ring: PackedVector2Array, i: int) -> float:
	var count := ring.size()
	var into := ring[i] - ring[(i - 1 + count) % count]
	var out_of := ring[(i + 1) % count] - ring[i]
	var lengths := into.length() * out_of.length()
	if lengths <= 0.0:
		return 0.0
	return into.cross(out_of) / lengths


static func _is_convex(ring: PackedVector2Array) -> bool:
	if ring.size() < 3:
		return false
	for i in ring.size():
		if _turn(ring, i) < -STRAIGHT:
			return false
	return true


## `ring` turned upside down within `height`, and wound back the other way, so it
## stays anticlockwise.
static func _upside_down(ring: PackedVector2Array, height: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(ring.size() - 1, -1, -1):
		out.append(Vector2(ring[i].x, height - ring[i].y))
	return out
