@tool
class_name HFUVWrap
extends RefCounted
## Wrap a texture onto the next face (#1428): the texture one face shows, carried
## over an edge it shares with another face, so it runs on round a pillar's corner,
## down a step's lip or along a corridor that turns rather than restarting.
##
## The target keeps its projection and takes the source's texture and the size of
## its scale. Its rotation, offset and the sign of its scale are solved so the UVs
## at both ends of the shared edge are the ones the source shows there. Which way
## the texture goes on across the edge, rather than folding back over it, is read
## off the source's texture continued past the edge into the target's place, as
## though the target were folded flat beside it.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

## How close two corners have to be to be one, in level units.
const EDGE_EPSILON := 0.001
## How far the target's measure of the edge may differ from the source's, as a
## fraction, before its scale is changed to make up the difference.
const LENGTH_TOLERANCE := 0.0001
## How short a face may measure the edge, as a fraction of what an even reading of
## it at that face's scale would give, before it counts as reading no edge at all:
## a projection seen edge on, rather than a short edge or a small scale.
const FLAT_READING := 0.001

## Why a wrap was refused, as the toast says it.
const REFUSALS := {
	"same_face": "Click a face beside the one the texture comes from",
	"no_shared_edge": "That face shares no edge with the one the texture comes from",
	"back_to_back": "That face lies against the one the texture comes from",
	"source_flat": "The face the texture comes from shows no texture along the shared edge",
	"target_flat": "That face's projection lays no texture along the shared edge",
	"no_scale": "The face the texture comes from has a scale of zero",
}


## What `target` takes for the texture `source` shows to run on over the edge the
## two share. Both faces have to know where their brushes stand. Returns
## `{"ok": true, "projection", "scale", "rotation", "offset", "adjusted", "edge"}`:
## `adjusted` is -1, or the axis whose scale was changed for a target that measures
## the edge differently from the source (0 U, 1 V, 2 both), and `edge` the two ends
## of the shared edge in the level. Or `{"ok": false, "reason"}`, a key of
## `REFUSALS`.
static func solve(source: FaceData, target: FaceData) -> Dictionary:
	if source == target:
		return _refused("same_face")
	if is_zero_approx(source.uv_scale.x) or is_zero_approx(source.uv_scale.y):
		return _refused("no_scale")
	var source_points := _in_level(source)
	var target_points := _in_level(target)
	if source_points.size() < 3 or target_points.size() < 3:
		return _refused("no_shared_edge")
	var edge := shared_edge(source_points, target_points)
	if edge.is_empty():
		return _refused("no_shared_edge")
	var source_normal := _facing(source)
	if source_normal.dot(_facing(target)) < -1.0 + FaceData.UV_TURN_TOLERANCE:
		return _refused("back_to_back")
	# Where the source's texture is at each end of the edge, and where the target's
	# projection reads those ends and its own middle.
	var to_source := source.world_transform.affine_inverse()
	var shown := source.shown_uvs_at(PackedVector3Array([to_source * edge[0], to_source * edge[1]]))
	var projection := target.uv_projection
	if not target.projection_lies_on_face(projection):
		# Cylindrical, or a planar axis seen edge on, lays nothing flat to wrap.
		projection = FaceData.UVProjection.FACE
	var middle := _middle(target_points)
	var to_target := target.world_transform.affine_inverse()
	var read := target.projected_points(
		PackedVector3Array([to_target * edge[0], to_target * edge[1], to_target * middle]),
		projection
	)
	var edge_read: Vector2 = read[1] - read[0]
	var edge_shown: Vector2 = shown[1] - shown[0]
	var edge_length := edge[0].distance_to(edge[1])
	var smallest_scale := minf(absf(source.uv_scale.x), absf(source.uv_scale.y))
	if edge_shown.length() < edge_length * smallest_scale * FLAT_READING:
		return _refused("source_flat")
	if edge_read.length() < edge_length * FLAT_READING:
		return _refused("target_flat")
	var continued := _continued(source, source_points, source_normal, edge, middle)
	# The two ways round the edge, one of them the mirror of the other across it.
	# Each matches the edge; the one nearer the continued texture runs on.
	var size := source.uv_scale.abs()
	var signs := Vector2(
		-1.0 if source.uv_scale.x < 0.0 else 1.0, -1.0 if source.uv_scale.y < 0.0 else 1.0
	)
	var best := {}
	var best_miss := INF
	for flip in [Vector2.ONE, Vector2(-1.0, 1.0)]:
		var fit := _fit_edge(edge_read, edge_shown, size * signs * flip)
		var scale: Vector2 = fit[0]
		var rotation: float = fit[1]
		var offset: Vector2 = shown[0] - (read[0] as Vector2).rotated(rotation) * scale
		var miss := ((read[2] as Vector2).rotated(rotation) * scale + offset).distance_to(continued)
		if miss < best_miss:
			best_miss = miss
			best = {
				"ok": true,
				"projection": projection,
				"scale": scale,
				"rotation": wrapf(rotation, -PI, PI),
				"offset": offset,
				"adjusted": fit[2],
				"edge": edge,
			}
	if best.is_empty():
		return _refused("target_flat")
	return best


## The longest stretch of an edge of `a` that an edge of `b` runs along, as its two
## ends, or empty when no edge of one lies along an edge of the other. Corners
## that are not shared count: a short wall against a long one shares the short
## one's edge.
static func shared_edge(a: PackedVector3Array, b: PackedVector3Array) -> PackedVector3Array:
	var best := PackedVector3Array()
	var best_length := EDGE_EPSILON
	for i in a.size():
		var a0: Vector3 = a[i]
		var along := a[(i + 1) % a.size()] - a0
		var length := along.length()
		if length <= EDGE_EPSILON:
			continue
		along /= length
		for j in b.size():
			var b0: Vector3 = b[j]
			var b1: Vector3 = b[(j + 1) % b.size()]
			if _off_line(b0, a0, along) > EDGE_EPSILON or _off_line(b1, a0, along) > EDGE_EPSILON:
				continue
			var t0 := (b0 - a0).dot(along)
			var t1 := (b1 - a0).dot(along)
			var low := maxf(0.0, minf(t0, t1))
			var high := minf(length, maxf(t0, t1))
			if high - low > best_length:
				best_length = high - low
				best = PackedVector3Array([a0 + along * low, a0 + along * high])
	return best


## The rotation and scale that lay `edge_read`, the edge as the target's projection
## reads it, onto `edge_shown`, as the source shows it, at the scale `scale`. Where
## the two measure the edge differently, as on a slope Box UV reads short, the scale
## along the texture axis the edge runs with is changed to make up the difference,
## or both are when that cannot. Returns `[scale, rotation, adjusted]`.
static func _fit_edge(edge_read: Vector2, edge_shown: Vector2, scale: Vector2) -> Array:
	var length := edge_read.length()
	var unscaled := edge_shown / scale
	var adjusted := -1
	if absf(unscaled.length() - length) > LENGTH_TOLERANCE * length:
		var major := 0 if absf(unscaled.x) >= absf(unscaled.y) else 1
		var minor := 1 - major
		var room := length * length - unscaled[minor] * unscaled[minor]
		if room > pow(LENGTH_TOLERANCE * length, 2.0) and absf(edge_shown[major]) > EDGE_EPSILON:
			var reach := sqrt(room) * (-1.0 if unscaled[major] < 0.0 else 1.0)
			scale[major] = edge_shown[major] / reach
			adjusted = major
		else:
			scale *= unscaled.length() / length
			adjusted = 2
		unscaled = edge_shown / scale
	return [scale, unscaled.angle() - edge_read.angle(), adjusted]


## The UV the source's texture would show at the target's middle, were the target
## folded flat beside the source across the edge: what the target is to show there
## for the texture to run on rather than fold back.
static func _continued(
	source: FaceData,
	source_points: PackedVector3Array,
	source_normal: Vector3,
	edge: PackedVector3Array,
	point: Vector3
) -> Vector2:
	var along := (edge[1] - edge[0]).normalized()
	var offset := point - edge[0]
	var down_edge := offset.dot(along)
	var off_edge := (offset - along * down_edge).length()
	var away := source_normal.cross(along).normalized()
	if (_middle(source_points) - edge[0]).dot(away) > 0.0:
		away = -away
	var folded := edge[0] + along * down_edge + away * off_edge
	var local := source.world_transform.affine_inverse() * folded
	return source.shown_uvs_at(PackedVector3Array([local]))[0]


static func _in_level(face: FaceData) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in face.local_verts:
		out.append(face.world_transform * point)
	return out


static func _facing(face: FaceData) -> Vector3:
	return face.normal_through(face.world_transform.basis)


static func _middle(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / maxf(1.0, float(points.size()))


static func _off_line(point: Vector3, origin: Vector3, along: Vector3) -> float:
	var offset := point - origin
	return (offset - along * offset.dot(along)).length()


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
