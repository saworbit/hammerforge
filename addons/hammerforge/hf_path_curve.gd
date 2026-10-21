@tool
extends RefCounted

## A smooth path through the points clicked for it, as the straight pieces a sweep
## cuts (#1436).
##
## Between each two clicked points the path is one cubic Bezier span. Every point
## has a handle: the way the path runs through it, and how strongly. A point whose
## handle was pulled out keeps that one, the same on both sides, so the path runs
## straight through it. Every other point takes its tangent from its two
## neighbours, as a centripetal Catmull-Rom curve does. Centripetal rather than
## uniform: the uniform curve overshoots where neighbouring points are unevenly
## spaced, so three points in a line with one gap ten times the other would bend
## back on itself, while the centripetal one never loops or forms a cusp inside a
## span. An open path's end takes its tangent from its neighbour mirrored through
## it, so it sets off straight at the next point.
##
## A point's tangent comes from points alone, never from another point's handle,
## so a handle changes the path's tangent at its own point and nowhere else.

## The exponent the distances between points are taken to: 0.5 is centripetal.
const ALPHA := 0.5

## A sample nearer than this to the one before it, in X and Z, is left out, as the
## sweep leaves out a point that adds no segment.
const MIN_SEGMENT := 0.01


## `points` without any that repeat the one before them in X and Z, or for a
## closed path the first, each keeping its handle. Where a repeat is dropped and
## the point kept has no handle, it takes the repeat's: a handle pulled on a
## second click at the same place was still meant for that place.
## Returns {"points": PackedVector3Array, "handles": PackedVector3Array}.
static func distinct(
	points: PackedVector3Array, handles: PackedVector3Array, closed: bool
) -> Dictionary:
	var kept := PackedVector3Array()
	var kept_handles := PackedVector3Array()
	for i in points.size():
		var handle := handles[i] if i < handles.size() else Vector3.ZERO
		var last := kept.size() - 1
		if last >= 0 and _flat(points[i] - kept[last]).length() < MIN_SEGMENT:
			if kept_handles[last] == Vector3.ZERO:
				kept_handles[last] = handle
			continue
		kept.append(points[i])
		kept_handles.append(handle)
	if closed:
		while kept.size() >= 2 and _flat(kept[kept.size() - 1] - kept[0]).length() < MIN_SEGMENT:
			if kept_handles[0] == Vector3.ZERO:
				kept_handles[0] = kept_handles[kept_handles.size() - 1]
			kept.remove_at(kept.size() - 1)
			kept_handles.remove_at(kept_handles.size() - 1)
	return {"points": kept, "handles": kept_handles}


## Each point's two Bezier controls, as offsets from it: [into, out_of], the path
## arriving from `point - into` and leaving toward `point + out_of`. Both lie
## along the tangent there.
static func controls(
	points: PackedVector3Array, handles: PackedVector3Array, closed: bool
) -> Array:
	var n := points.size()
	var out: Array = []
	for i in n:
		var handle := handles[i] if i < handles.size() else Vector3.ZERO
		if handle != Vector3.ZERO:
			out.append([handle, handle])
			continue
		if n < 2:
			out.append([Vector3.ZERO, Vector3.ZERO])
			continue
		var before: Vector3
		var after: Vector3
		if closed:
			before = points[(i - 1 + n) % n]
			after = points[(i + 1) % n]
		else:
			before = points[i - 1] if i > 0 else points[0] * 2.0 - points[1]
			after = points[i + 1] if i < n - 1 else points[n - 1] * 2.0 - points[n - 2]
		out.append(_catmull_rom(before, points[i], after))
	return out


## The centripetal Catmull-Rom controls at `point` between `before` and `after`,
## as `controls()` gives them. With a and b the distances to each neighbour taken
## to `ALPHA`, the tangent leans toward the nearer neighbour's side, and each
## control is a third of the way along the tangent its own span runs at.
static func _catmull_rom(before: Vector3, point: Vector3, after: Vector3) -> Array:
	var a := pow(point.distance_to(before), ALPHA)
	var b := pow(after.distance_to(point), ALPHA)
	if a <= 0.0 or b <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var tangent := (after - point) * a * a + (point - before) * b * b
	return [tangent / (3.0 * b * (a + b)), tangent / (3.0 * a * (a + b))]


## The path through `points` sampled into `segments` straight pieces per span:
## {"points": the samples, "spans": for each segment between two samples, the
## span it is part of, counted from 0 at the span leaving the first point}. A
## closed path's last segment runs from the last sample back to the first. Any
## sample that would repeat the one before it is left out.
static func sample(
	points: PackedVector3Array, handles: PackedVector3Array, closed: bool, segments: int
) -> Dictionary:
	var n := points.size()
	var pieces := maxi(segments, 1)
	var raw := PackedVector3Array()
	var raw_spans := PackedInt32Array()
	if n >= 2:
		var ctrl := controls(points, handles, closed)
		var spans := n if closed else n - 1
		for span in spans:
			var from: Vector3 = points[span]
			var to: Vector3 = points[(span + 1) % n]
			var leaving: Vector3 = from + ctrl[span][1]
			var arriving: Vector3 = to - ctrl[(span + 1) % n][0]
			for j in pieces:
				raw.append(from.bezier_interpolate(leaving, arriving, to, float(j) / float(pieces)))
				raw_spans.append(span)
		if not closed:
			raw.append(points[n - 1])
			raw_spans.append(spans - 1)
	elif n == 1:
		raw.append(points[0])
		raw_spans.append(0)
	# The span a segment is part of is the span of the sample it leaves from.
	var kept := PackedVector3Array()
	var kept_spans := PackedInt32Array()
	for i in raw.size():
		if kept.size() > 0 and _flat(raw[i] - kept[kept.size() - 1]).length() < MIN_SEGMENT:
			continue
		kept.append(raw[i])
		kept_spans.append(raw_spans[i])
	if closed:
		while kept.size() >= 2 and _flat(kept[kept.size() - 1] - kept[0]).length() < MIN_SEGMENT:
			kept.remove_at(kept.size() - 1)
			kept_spans.remove_at(kept_spans.size() - 1)
	var segment_spans := PackedInt32Array()
	var count := kept.size() if closed else kept.size() - 1
	for k in maxi(count, 0):
		segment_spans.append(kept_spans[k])
	return {"points": kept, "spans": segment_spans}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
