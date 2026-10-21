@tool
extends RefCounted

## Splits a flat outline into convex pieces, for the Polygon tool (#1430).
##
## Every brush has to be convex, and most floor plans are not: an L shaped room,
## a T junction, a platform with a notch. The outline is cut until every piece
## is convex, each cut chosen so it settles at least one corner that bends the
## wrong way (a reflex corner), and each one carrying on the line of a wall:
##
## 1. A line between two reflex corners that settles both, if there is one. A T
##    junction is the bar and the stem, with no new corner made.
## 2. Otherwise one wall of a reflex corner, run on across the inside until it
##    meets the outline again. The piece gains a corner where it lands.
##
## Because every cut follows a wall the mapper drew, a plan drawn along the grid
## comes apart into rectangles. Godot's `Geometry2D.decompose_polygon_in_convex()`
## was the first choice, and its pieces do cover the outline exactly, but it only
## ever cuts from one corner to another, wherever that runs: an L comes out as
## two trapezoids meeting on the diagonal, and a T as four pieces, two of them
## slivers. Each cut here settles a reflex corner, so an outline with r of them
## makes at most r + 1 pieces.
##
## Points are Vector2 in the XZ plane: x is X and y is Z.

## How far off a line a point may be and still count as on it, in metres.
const ON_LINE := 0.0001

## Cuts to try before giving up on an outline. Each cut settles a reflex corner,
## so a simple outline needs fewer than its corner count; this is a backstop.
const MAX_CUTS := 256


## Whether the outline, closed back to its first point, runs across itself: two
## edges that cross or touch away from the corner they share, or an edge that
## doubles back along the one before it. A brush cannot be built from either.
static func crosses_itself(ring: PackedVector2Array) -> bool:
	var n := ring.size()
	if n < 3:
		return false
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		for j in range(i + 1, n):
			var c := ring[j]
			var d := ring[(j + 1) % n]
			if j == i + 1:
				if _doubles_back(a, b, d):
					return true
			elif i == 0 and j == n - 1:
				if _doubles_back(c, a, b):
					return true
			elif _segments_meet(a, b, c, d):
				return true
	return false


## Twice the area the ring encloses, positive when it runs anticlockwise with X
## to the right and Z up.
static func signed_area(ring: PackedVector2Array) -> float:
	var twice := 0.0
	var n := ring.size()
	for i in n:
		twice += ring[i].cross(ring[(i + 1) % n])
	return twice * 0.5


## The convex pieces of a simple outline, and the cuts between them, as
## `{"parts": [PackedVector2Array], "cuts": [[Vector2, Vector2]]}`. Each part runs
## anticlockwise and has no corner on a straight line. Both lists are empty when
## the outline cannot be split: it crosses itself, encloses nothing, or the
## pieces did not come out convex and covering it exactly, which is checked here
## rather than trusted, so a failure is a refusal and never a wrong brush.
static func convex_parts(outline: PackedVector2Array) -> Dictionary:
	var failed := {"parts": [], "cuts": []}
	var ring := _tidy(outline)
	if ring.size() < 3 or crosses_itself(ring):
		return failed
	var parts: Array = []
	var cuts: Array = []
	var pending: Array = [ring]
	while not pending.is_empty():
		var piece: PackedVector2Array = pending.pop_back()
		if piece.size() < 3:
			return failed
		var cut := _next_cut(piece)
		if cut.is_empty():
			if not _reflex_corners(piece).is_empty():
				return failed
			parts.append(piece)
			continue
		if cuts.size() >= MAX_CUTS:
			return failed
		cuts.append([piece[cut["from"]], cut["point"]])
		for half in _split(piece, cut):
			pending.append(_tidy(half))
	var total := 0.0
	for part: PackedVector2Array in parts:
		total += signed_area(part)
	var whole := signed_area(ring)
	if absf(total - whole) > maxf(whole, 1.0) * 0.0001:
		return failed
	return {"parts": parts, "cuts": cuts}


# ---------------------------------------------------------------------------
# Cuts
# ---------------------------------------------------------------------------


## The cut to make in `piece` next, or an empty dictionary when it is convex.
## `from` is the reflex corner the cut starts at and `point` where it ends; `to`
## is the corner it ends on, or -1 when it lands part way along `edge`.
static func _next_cut(piece: PackedVector2Array) -> Dictionary:
	var reflex := _reflex_corners(piece)
	if reflex.is_empty():
		return {}
	var n := piece.size()
	var best := {}
	var best_length := INF
	# A line between two reflex corners that leaves neither of them reflex, on
	# the line of a wall of one of them. One that runs off at an angle to both
	# would settle two corners at once and leave a slanted seam across a plan
	# drawn square.
	for i in reflex:
		for j in reflex:
			if j <= i or (j - i) % n == 1 or (i - j + n) % n == 1:
				continue
			var length := piece[i].distance_to(piece[j])
			if length >= best_length:
				continue
			if not (_on_wall_line(piece, i, piece[j]) or _on_wall_line(piece, j, piece[i])):
				continue
			if _settles(piece, i, piece[j]) and _settles(piece, j, piece[i]):
				if _is_diagonal(piece, i, j):
					best = {"from": i, "to": j, "point": piece[j], "edge": -1}
					best_length = length
	if not best.is_empty():
		return best
	# A wall of a reflex corner run on until it meets the outline.
	for i in reflex:
		var corner := piece[i]
		for wall_end: Vector2 in [piece[(i - 1 + n) % n], piece[(i + 1) % n]]:
			var hit := _cast(piece, i, (corner - wall_end).normalized())
			if not hit.is_empty() and float(hit["length"]) < best_length:
				best = hit
				best_length = float(hit["length"])
	return best


## Corners of an anticlockwise ring that turn clockwise.
static func _reflex_corners(piece: PackedVector2Array) -> Array[int]:
	var out: Array[int] = []
	var n := piece.size()
	for i in n:
		if _side(piece[(i - 1 + n) % n], piece[i], piece[(i + 1) % n]) < 0:
			out.append(i)
	return out


## Whether a cut from corner `i` toward `target` leaves the corner convex on both
## sides of it: the cut has to run between the two walls carried on past the
## corner, which is also what keeps it inside the outline there.
static func _settles(piece: PackedVector2Array, i: int, target: Vector2) -> bool:
	var n := piece.size()
	var corner := piece[i]
	var incoming := corner - piece[(i - 1 + n) % n]
	var outgoing := piece[(i + 1) % n] - corner
	var cut := target - corner
	var slack := ON_LINE * cut.length()
	return (
		incoming.cross(cut) >= -slack * incoming.length()
		and cut.cross(outgoing) <= slack * outgoing.length()
	)


## Whether a cut from corner `i` toward `target` carries on the line of one of the
## corner's two walls.
static func _on_wall_line(piece: PackedVector2Array, i: int, target: Vector2) -> bool:
	var n := piece.size()
	return (
		_side(piece[(i - 1 + n) % n], piece[i], target) == 0
		or _side(piece[(i + 1) % n], piece[i], target) == 0
	)


## Whether the segment from corner `i` to corner `j` touches the outline nowhere
## but its two ends.
static func _is_diagonal(piece: PackedVector2Array, i: int, j: int) -> bool:
	var n := piece.size()
	for k in n:
		var k_next := (k + 1) % n
		if k == i or k == j or k_next == i or k_next == j:
			continue
		if _segments_meet(piece[i], piece[j], piece[k], piece[k_next]):
			return false
	return true


## The first place a ray from corner `i` along `direction` meets the outline,
## as a cut, or an empty dictionary if it meets nothing.
static func _cast(piece: PackedVector2Array, i: int, direction: Vector2) -> Dictionary:
	var n := piece.size()
	var origin := piece[i]
	var nearest := INF
	var hit := {}
	for k in n:
		var k_next := (k + 1) % n
		if k == i or k_next == i:
			continue
		var a := piece[k]
		var edge := piece[k_next] - a
		var denominator := direction.cross(edge)
		if absf(denominator) <= ON_LINE * edge.length():
			continue
		var along_ray := (a - origin).cross(edge) / denominator
		var along_edge := (a - origin).cross(direction) / denominator
		var edge_slack := ON_LINE / edge.length()
		if along_ray <= ON_LINE or along_edge < -edge_slack or along_edge > 1.0 + edge_slack:
			continue
		if along_ray >= nearest:
			continue
		nearest = along_ray
		var to := -1
		if along_edge <= edge_slack:
			to = k
		elif along_edge >= 1.0 - edge_slack:
			to = k_next
		var point: Vector2 = piece[to] if to >= 0 else origin + direction * along_ray
		hit = {"from": i, "to": to, "point": point, "edge": k, "length": along_ray}
	return hit


## The two rings either side of `cut`, both still anticlockwise.
static func _split(piece: PackedVector2Array, cut: Dictionary) -> Array:
	var from: int = cut["from"]
	var to: int = cut["to"]
	if to >= 0:
		return [_corners(piece, from, to), _corners(piece, to, from)]
	# The cut lands part way along the edge that starts at corner `edge`.
	var edge: int = cut["edge"]
	var point: Vector2 = cut["point"]
	var first := _corners(piece, from, edge)
	first.append(point)
	var second := PackedVector2Array([point])
	second.append_array(_corners(piece, (edge + 1) % piece.size(), from))
	return [first, second]


## The corners of `piece` from `start` round to `stop`, both included.
static func _corners(piece: PackedVector2Array, start: int, stop: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var k := start
	while true:
		out.append(piece[k])
		if k == stop:
			break
		k = (k + 1) % piece.size()
	return out


# ---------------------------------------------------------------------------
# Small geometry
# ---------------------------------------------------------------------------


## The ring without repeated points or corners on a straight line, anticlockwise.
static func _tidy(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(ring)
	var changed := true
	while changed and out.size() >= 3:
		changed = false
		for i in out.size():
			var n := out.size()
			var before := out[(i - 1 + n) % n]
			var here := out[i]
			var after := out[(i + 1) % n]
			var repeated := here.distance_to(after) <= ON_LINE
			var straight := (
				_side(before, here, after) == 0 and (here - before).dot(after - here) > 0.0
			)
			if repeated or straight:
				out.remove_at(i)
				changed = true
				break
	if signed_area(out) < 0.0:
		out.reverse()
	return out


## Which side of the line through `a` and `b` the point `p` is on: 1 left, -1
## right, 0 within `ON_LINE` of it.
static func _side(a: Vector2, b: Vector2, p: Vector2) -> int:
	var length := a.distance_to(b)
	if length <= ON_LINE:
		return 0
	var offset := (b - a).cross(p - a) / length
	if absf(offset) <= ON_LINE:
		return 0
	return 1 if offset > 0.0 else -1


## Whether segments ab and cd share any point, touching and overlapping included.
static func _segments_meet(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _side(a, b, c)
	var ab_d := _side(a, b, d)
	var cd_a := _side(c, d, a)
	var cd_b := _side(c, d, b)
	if ab_c * ab_d < 0 and cd_a * cd_b < 0:
		return true
	return (
		(ab_c == 0 and _within(a, b, c))
		or (ab_d == 0 and _within(a, b, d))
		or (cd_a == 0 and _within(c, d, a))
		or (cd_b == 0 and _within(c, d, b))
	)


## Whether `p`, already on the line through `a` and `b`, lies between them.
static func _within(a: Vector2, b: Vector2, p: Vector2) -> bool:
	var length := a.distance_to(b)
	var along := (p - a).dot(b - a) / maxf(length, ON_LINE)
	return along >= -ON_LINE and along <= length + ON_LINE


## Whether the edge from `b` to `c` runs back along the edge from `a` to `b`.
static func _doubles_back(a: Vector2, b: Vector2, c: Vector2) -> bool:
	return _side(a, b, c) == 0 and (b - a).dot(c - b) < 0.0
