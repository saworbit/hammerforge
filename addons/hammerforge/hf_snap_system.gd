@tool
extends RefCounted
class_name HFSnapSystem
## Centralized snap system with grid, vertex, center, edge, and perpendicular modes.

const DraftBrush = preload("brush_instance.gd")

enum SnapMode { GRID = 1, VERTEX = 2, CENTER = 4, EDGE = 8, PERPENDICULAR = 16 }

## Past this many faces a brush's `faces` array is engine tessellation rather
## than geometry anyone could aim at: a cylinder brush is one FaceData per
## triangle, a sphere is thousands. Those brushes keep the bounding box they
## always had, now oriented by the brush transform. Hand built geometry
## (polygon, path, merged, bevelled, vertex edited) sits well under this.
const MAX_SNAP_FACES := 64

## Corner order for _box_corners(), and the 12 box edges as index pairs into it.
const BOX_EDGE_INDICES: Array = [
	[0, 1],
	[0, 2],
	[0, 4],
	[1, 3],
	[1, 5],
	[2, 3],
	[2, 6],
	[3, 7],
	[4, 5],
	[4, 6],
	[5, 7],
	[6, 7],
]

## Millimetre precision for _vertex_key. Two vertices closer than 1/1000 of a
## unit are the same snap target.
const VERTEX_KEY_SCALE := 1000.0

var root: Node3D
var enabled_modes: int = SnapMode.GRID
var snap_threshold: float = 2.0
var _custom_snap_origin: Vector3 = Vector3.ZERO
var _custom_snap_dir: Vector3 = Vector3.ZERO
var _has_custom_snap := false

## Face snap geometry per brush id. Brush space does not move with the brush,
## so an entry survives every drag, rotate and resize of everything around it
## and only goes stale when a brush's own faces change.
var _face_geometry_cache: Dictionary = {}


func _init(level_root: Node3D) -> void:
	root = level_root
	if root == null:
		return
	for sig in ["brush_changed", "brush_removed"]:
		if root.has_signal(sig):
			root.connect(sig, Callable(self, "_on_brush_geometry_invalidated"))


## Drop one brush's cached geometry. Both signals carry the id that changed.
func _on_brush_geometry_invalidated(brush_id: String) -> void:
	_face_geometry_cache.erase(brush_id)


## Drop every cached entry. For callers that rebuild the level wholesale.
func clear_geometry_cache() -> void:
	_face_geometry_cache.clear()


func set_mode(mode: int, on: bool) -> void:
	if on:
		enabled_modes = enabled_modes | mode
	else:
		enabled_modes = enabled_modes & ~mode


func is_mode_on(mode: int) -> bool:
	return (enabled_modes & mode) != 0


func snap_point(point: Vector3, grid_snap: float, exclude_ids: Array = []) -> Vector3:
	var best := point
	var best_dist := INF

	# Grid snap candidate
	if is_mode_on(SnapMode.GRID) and grid_snap > 0.0:
		var grid_vec := Vector3(grid_snap, grid_snap, grid_snap)
		var grid_snapped := point.snapped(grid_vec)
		var d := point.distance_to(grid_snapped)
		if d < best_dist:
			best = grid_snapped
			best_dist = d

	# Geometry snap candidates (vertex / center / edge / perpendicular)
	if (
		is_mode_on(SnapMode.VERTEX)
		or is_mode_on(SnapMode.CENTER)
		or is_mode_on(SnapMode.EDGE)
		or is_mode_on(SnapMode.PERPENDICULAR)
	):
		var candidates := _collect_candidates(exclude_ids, point)
		for c in candidates:
			var d := point.distance_to(c)
			if d < snap_threshold and d < best_dist:
				best = c
				best_dist = d

	# Custom snap line (from measure tool "Align to this")
	if _has_custom_snap:
		var projected := _project_onto_line(point, _custom_snap_origin, _custom_snap_dir)
		var d := point.distance_to(projected)
		if d < snap_threshold and d < best_dist:
			best = projected
			best_dist = d

	if best_dist == INF:
		return point
	return best


func set_custom_snap_line(origin: Vector3, direction: Vector3) -> void:
	_custom_snap_origin = origin
	_custom_snap_dir = direction.normalized()
	_has_custom_snap = true


func clear_custom_snap_line() -> void:
	_has_custom_snap = false
	_custom_snap_origin = Vector3.ZERO
	_custom_snap_dir = Vector3.ZERO


func _project_onto_line(point: Vector3, line_origin: Vector3, line_dir: Vector3) -> Vector3:
	var to_point: Vector3 = point - line_origin
	var t: float = to_point.dot(line_dir)
	return line_origin + line_dir * t


func _collect_candidates(exclude_ids: Array, point: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not root or not root.has_method("_iter_pick_nodes"):
		return out
	var do_vertex := is_mode_on(SnapMode.VERTEX)
	var do_center := is_mode_on(SnapMode.CENTER)
	var do_edge := is_mode_on(SnapMode.EDGE)
	var do_perp := is_mode_on(SnapMode.PERPENDICULAR)
	var preview = root.get("preview_brush")
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		if node == preview:
			continue
		var brush := node as DraftBrush
		if exclude_ids.has(str(brush.brush_id)):
			continue
		if do_center:
			out.append(brush.global_position)
		if not (do_vertex or do_edge or do_perp):
			continue
		# Snap points live in brush space. Going through the transform is what
		# carries the rotation and scale that world axis offsets threw away.
		var xform := brush.global_transform
		var geometry := _snap_geometry_local(brush)
		var local_verts: PackedVector3Array = geometry["verts"]
		var verts := PackedVector3Array()
		for local_vert in local_verts:
			verts.append(xform * local_vert)
		if do_vertex:
			out.append_array(verts)
		if do_edge or do_perp:
			for edge in geometry["edges"]:
				var a: Vector3 = verts[edge[0]]
				var b: Vector3 = verts[edge[1]]
				if do_edge:
					out.append((a + b) * 0.5)
				if do_perp:
					out.append(_closest_point_on_segment(point, a, b))
	return out


## Snap targets for one brush in brush-local space: unique vertices, plus the
## unique edges between them as index pairs into that vertex list.
##
## A brush that carries its own faces is described by them, so a wedge, prism,
## polygon, path or merged brush snaps to real corners instead of the corners of
## a box it does not fill. Everything else falls back to its bounding box.
func _snap_geometry_local(brush: DraftBrush) -> Dictionary:
	# A BOX brush is defined by its size: _rebuild_faces regenerates its faces
	# from size alone, so its corners are the size corners. Boxes are most of a
	# level, so take them straight rather than deduping six faces every query.
	if brush.shape == DraftBrush.BrushShape.BOX:
		return {"verts": _box_corners(brush.size * 0.5), "edges": BOX_EDGE_INDICES}
	var faces: Array = brush.faces
	if not faces.is_empty() and faces.size() <= MAX_SNAP_FACES:
		var face_geometry := _cached_face_geometry(brush, faces)
		var face_verts: PackedVector3Array = face_geometry["verts"]
		if face_verts.size() >= 2:
			return face_geometry
	return {"verts": _box_corners(brush.size * 0.5), "edges": BOX_EDGE_INDICES}


## Deduping a brush's faces is the expensive half of a snap query and it runs
## per brush per mouse motion event. The result is in brush space, so it only
## depends on the faces themselves.
##
## `brush_changed` is what says those faces moved. The stamp covers the paths
## that change geometry without announcing it first: a node swapped in under the
## same id by an undo, a face array replaced outright, and a resize, which
## rebuilds a wedge or prism's faces to the same count on the same node. A brush
## with no id is never cached, because nothing would name it to invalidate it.
func _cached_face_geometry(brush: DraftBrush, faces: Array) -> Dictionary:
	var brush_id := str(brush.brush_id)
	if brush_id == "":
		return _face_snap_geometry(faces)
	var instance_id := brush.get_instance_id()
	var face_count := faces.size()
	var size: Vector3 = brush.size
	var entry = _face_geometry_cache.get(brush_id)
	if (
		entry != null
		and entry["instance_id"] == instance_id
		and entry["face_count"] == face_count
		and entry["size"] == size
	):
		return entry["geometry"]
	var geometry := _face_snap_geometry(faces)
	_face_geometry_cache[brush_id] = {
		"instance_id": instance_id,
		"face_count": face_count,
		"size": size,
		"geometry": geometry,
	}
	return geometry


## Unique vertices and unique edges read off a brush's faces. A hull corner
## belongs to three or more faces and an edge to two, so both are deduped by
## rounded position.
static func _face_snap_geometry(faces: Array) -> Dictionary:
	var verts := PackedVector3Array()
	var index_by_key: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		for v in face.local_verts:
			var key := _vertex_key(v)
			if not index_by_key.has(key):
				index_by_key[key] = verts.size()
				verts.append(v)
	var edges: Array = []
	var seen_edges: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		var ring: PackedVector3Array = face.local_verts
		var count := ring.size()
		if count < 2:
			continue
		for i in range(count):
			var ia: int = index_by_key.get(_vertex_key(ring[i]), -1)
			var ib: int = index_by_key.get(_vertex_key(ring[(i + 1) % count]), -1)
			if ia < 0 or ib < 0 or ia == ib:
				continue
			var lo := mini(ia, ib)
			var hi := maxi(ia, ib)
			var edge_key := Vector2i(lo, hi)
			if seen_edges.has(edge_key):
				continue
			seen_edges[edge_key] = true
			edges.append([lo, hi])
	return {"verts": verts, "edges": edges}


## Vertices dedupe at millimetre precision. Keying by Vector3i holds that
## tolerance without formatting a string per vertex, which matters because this
## runs for every vertex of every non box brush on every mouse motion event.
static func _vertex_key(v: Vector3) -> Vector3i:
	return Vector3i(
		roundi(v.x * VERTEX_KEY_SCALE),
		roundi(v.y * VERTEX_KEY_SCALE),
		roundi(v.z * VERTEX_KEY_SCALE)
	)


## The 8 corners of a box, in the order BOX_EDGE_INDICES expects.
static func _box_corners(half: Vector3) -> PackedVector3Array:
	return PackedVector3Array(
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
		]
	)


func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return a
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t
