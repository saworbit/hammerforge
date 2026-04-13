@tool
class_name HFBevelSystem
extends RefCounted

## Bevel (chamfer) system for HammerForge.
## Supports edge bevel (replace a sharp edge with rounded segments) and
## face inset (shrink a face inward and connect with angled transition faces).

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")

var root: Node3D  # LevelRoot


func _init(p_root: Node3D = null) -> void:
	root = p_root


# ---------------------------------------------------------------------------
# Edge Bevel
# ---------------------------------------------------------------------------


## Bevel an edge shared between two faces of a brush. Replaces the sharp edge
## with `segments` intermediate faces approximating a rounded profile.
## `radius` controls how far the bevel cuts into the brush.
## Returns true on success.
func bevel_edge(brush_id: String, edge: Array, segments: int = 2, radius: float = 2.0) -> bool:
	if edge.size() < 2:
		HFLog.warn("HFBevelSystem: edge needs 2 vertex indices")
		return false
	segments = clampi(segments, 1, 16)
	radius = maxf(radius, 0.01)
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if faces.is_empty():
		return false
	var vi_a: int = edge[0]
	var vi_b: int = edge[1]
	var all_verts: PackedVector3Array = _get_unique_verts(faces)
	if vi_a < 0 or vi_a >= all_verts.size() or vi_b < 0 or vi_b >= all_verts.size():
		HFLog.warn("HFBevelSystem: vertex index out of range")
		return false
	var va: Vector3 = all_verts[vi_a]
	var vb: Vector3 = all_verts[vi_b]
	# Find the two faces sharing this edge.
	var adjacent: Array = _find_faces_sharing_edge(faces, va, vb)
	if adjacent.size() < 2:
		HFLog.warn(
			"HFBevelSystem: edge must be shared by exactly 2 faces, found %d" % adjacent.size()
		)
		return false
	var face_idx_0: int = adjacent[0]
	var face_idx_1: int = adjacent[1]
	var face0: FaceData = faces[face_idx_0]
	var face1: FaceData = faces[face_idx_1]
	# Compute bevel geometry.
	var edge_dir: Vector3 = (vb - va).normalized()
	var n0: Vector3 = face0.normal
	var n1: Vector3 = face1.normal
	# The bevel arc goes from face0's plane to face1's plane.
	# Compute the two pull-back directions (perpendicular to edge, in each face plane).
	var pull0: Vector3 = n0.cross(edge_dir).normalized()
	var pull1: Vector3 = edge_dir.cross(n1).normalized()
	# Ensure pull directions point inward (toward brush center).
	var center: Vector3 = _compute_centroid(all_verts)
	if pull0.dot(center - va) < 0:
		pull0 = -pull0
	if pull1.dot(center - va) < 0:
		pull1 = -pull1
	# Generate intermediate vertices along the arc for both edge endpoints.
	var arc_verts_a: PackedVector3Array = _compute_arc(va, pull0, pull1, radius, segments)
	var arc_verts_b: PackedVector3Array = _compute_arc(vb, pull0, pull1, radius, segments)
	# Pull back original face vertices from the edge.
	var new_va0: Vector3 = va + pull0 * radius
	var new_vb0: Vector3 = vb + pull0 * radius
	var new_va1: Vector3 = va + pull1 * radius
	var new_vb1: Vector3 = vb + pull1 * radius
	# Modify face0: replace va→new_va0, vb→new_vb0
	_replace_vertex_in_face(face0, va, new_va0)
	_replace_vertex_in_face(face0, vb, new_vb0)
	face0.ensure_geometry()
	# Modify face1: replace va→new_va1, vb→new_vb1
	_replace_vertex_in_face(face1, va, new_va1)
	_replace_vertex_in_face(face1, vb, new_vb1)
	face1.ensure_geometry()
	# Build bevel strip faces (segments quads between arc vertices).
	var new_faces: Array[FaceData] = []
	for i in range(segments):
		var bevel_face = FaceData.new()
		var p0a: Vector3 = arc_verts_a[i]
		var p1a: Vector3 = arc_verts_a[i + 1]
		var p0b: Vector3 = arc_verts_b[i]
		var p1b: Vector3 = arc_verts_b[i + 1]
		# CW winding from outside: p0a → p0b → p1b → p1a
		bevel_face.local_verts = PackedVector3Array([p0a, p0b, p1b, p1a])
		bevel_face.material_idx = face0.material_idx
		bevel_face.uv_projection = face0.uv_projection
		bevel_face.uv_scale = face0.uv_scale
		bevel_face.uv_offset = face0.uv_offset
		bevel_face.uv_rotation = face0.uv_rotation
		bevel_face.ensure_geometry()
		new_faces.append(bevel_face)
	# Build corner cap triangle fans at each endpoint to close the gap
	# between the two pulled-back positions and the bevel arc.
	# At endpoint va: the arc goes from new_va0 (= arc_verts_a[0]) to
	# new_va1 (= arc_verts_a[segments]). We fan from the original corner
	# toward the center to fill the hole.
	if segments >= 1:
		for endpoint_arc in [arc_verts_a, arc_verts_b]:
			for i in range(segments - 1):
				var cap = FaceData.new()
				# Fan from the first arc point through the intermediate arc points.
				# CW winding from outside: arc[0] → arc[i+2] → arc[i+1]
				cap.local_verts = PackedVector3Array(
					[endpoint_arc[0], endpoint_arc[i + 2], endpoint_arc[i + 1]]
				)
				cap.material_idx = face0.material_idx
				cap.uv_projection = face0.uv_projection
				cap.uv_scale = face0.uv_scale
				cap.ensure_geometry()
				new_faces.append(cap)
	# Update neighboring faces that share va or vb but are not face0/face1.
	# Each neighbor is assigned to the side (face0 or face1) whose normal it
	# is closer to, and its copy of va/vb is replaced with the corresponding
	# bevel-pullback vertex so the mesh stays manifold.
	for fi in range(faces.size()):
		if fi == face_idx_0 or fi == face_idx_1:
			continue
		var face: FaceData = faces[fi]
		if face == null:
			continue
		var side0_dot: float = face.normal.dot(n0)
		var side1_dot: float = face.normal.dot(n1)
		var on_side0: bool = side0_dot >= side1_dot
		for vi in range(face.local_verts.size()):
			if face.local_verts[vi].distance_to(va) < 0.01:
				face.local_verts[vi] = new_va0 if on_side0 else new_va1
			elif face.local_verts[vi].distance_to(vb) < 0.01:
				face.local_verts[vi] = new_vb0 if on_side0 else new_vb1
		face.ensure_geometry()
	for nf in new_faces:
		brush.faces.append(nf)
	_mark_brush_dirty(brush)
	return true


# ---------------------------------------------------------------------------
# Face Inset (Bevel)
# ---------------------------------------------------------------------------


## Inset a face: shrink it inward by `inset_distance` and create connecting
## side faces between the original boundary and the inset boundary.
## If `height` != 0, the inset face is also extruded along its normal.
## Returns true on success.
func inset_face(
	brush_id: String, face_index: int, inset_distance: float = 2.0, height: float = 0.0
) -> bool:
	inset_distance = maxf(inset_distance, 0.01)
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	var verts: PackedVector3Array = face.local_verts
	var count: int = verts.size()
	if count < 3:
		return false
	# Compute face centroid and inset vertices.
	var centroid := Vector3.ZERO
	for v in verts:
		centroid += v
	centroid /= float(count)
	var inset_verts := PackedVector3Array()
	for v in verts:
		var to_center: Vector3 = centroid - v
		var max_dist: float = to_center.length()
		if inset_distance >= max_dist - 0.01:
			HFLog.warn("HFBevelSystem: inset distance too large, face collapsed")
			return false
		var dir: Vector3 = to_center.normalized()
		var inset_v: Vector3 = v + dir * inset_distance
		if height != 0.0:
			inset_v += face.normal * height
		inset_verts.append(inset_v)
	# Replace original face with the inset face.
	face.local_verts = inset_verts
	face.ensure_geometry()
	# Create connecting side faces between original boundary and inset boundary.
	var new_faces: Array[FaceData] = []
	for i in range(count):
		var next: int = (i + 1) % count
		var side_face = FaceData.new()
		# CW winding from outside: orig[i] → orig[next] → inset[next] → inset[i]
		side_face.local_verts = PackedVector3Array(
			[verts[i], verts[next], inset_verts[next], inset_verts[i]]
		)
		side_face.material_idx = face.material_idx
		side_face.uv_projection = face.uv_projection
		side_face.uv_scale = face.uv_scale
		side_face.ensure_geometry()
		new_faces.append(side_face)
	for nf in new_faces:
		brush.faces.append(nf)
	_mark_brush_dirty(brush)
	return true


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _find_brush(brush_id: String) -> Node3D:
	if not root:
		return null
	if root.has_method("find_brush_by_id"):
		return root.find_brush_by_id(brush_id)
	return null


func _mark_brush_dirty(brush: Node3D) -> void:
	if brush.has_method("rebuild_preview"):
		brush.rebuild_preview()
	if root and brush.get("brush_id") and root.has_method("tag_brush_dirty"):
		root.tag_brush_dirty(brush.brush_id)


func _get_unique_verts(faces: Array) -> PackedVector3Array:
	var verts := PackedVector3Array()
	var seen: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		for v in face.local_verts:
			var key: String = "%0.3f,%0.3f,%0.3f" % [v.x, v.y, v.z]
			if not seen.has(key):
				seen[key] = true
				verts.append(v)
	return verts


func _find_faces_sharing_edge(faces: Array, va: Vector3, vb: Vector3, tol: float = 0.01) -> Array:
	var result: Array = []
	for fi in range(faces.size()):
		var face: FaceData = faces[fi]
		if face == null:
			continue
		var has_a := false
		var has_b := false
		for v in face.local_verts:
			if v.distance_to(va) < tol:
				has_a = true
			if v.distance_to(vb) < tol:
				has_b = true
		if has_a and has_b:
			result.append(fi)
	return result


func _replace_vertex_in_face(
	face: FaceData, old_v: Vector3, new_v: Vector3, tol: float = 0.01
) -> void:
	var new_verts := PackedVector3Array()
	for v in face.local_verts:
		if v.distance_to(old_v) < tol:
			new_verts.append(new_v)
		else:
			new_verts.append(v)
	face.local_verts = new_verts


func _compute_centroid(verts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in verts:
		c += v
	if verts.size() > 0:
		c /= float(verts.size())
	return c


## Compute arc vertices from `origin` sweeping from `dir0` to `dir1`
## at the given `radius` with `segments` steps. Returns segments+1 points.
func _compute_arc(
	origin: Vector3, dir0: Vector3, dir1: Vector3, radius: float, segments: int
) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		# Spherical-linear interpolation between the two pull directions.
		var dir: Vector3 = _slerp_vec3(dir0, dir1, t)
		points.append(origin + dir * radius)
	return points


func _slerp_vec3(a: Vector3, b: Vector3, t: float) -> Vector3:
	var dot_val: float = clampf(a.dot(b), -1.0, 1.0)
	if dot_val > 0.9999:
		return a.lerp(b, t).normalized()
	var theta: float = acos(dot_val)
	var sin_theta: float = sin(theta)
	if sin_theta < 0.0001:
		return a.lerp(b, t).normalized()
	var wa: float = sin((1.0 - t) * theta) / sin_theta
	var wb: float = sin(t * theta) / sin_theta
	return (a * wa + b * wb).normalized()
