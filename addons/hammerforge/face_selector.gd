@tool
extends RefCounted
class_name FaceSelector


static func intersect_brushes(brushes: Array, ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	var best_distance = INF
	var best_hit: Dictionary = {}
	for brush in brushes:
		if brush == null:
			continue
		if not brush.has_method("get_faces"):
			continue
		var hit = _intersect_brush(brush, ray_origin, ray_dir, best_distance)
		if not hit.is_empty():
			best_distance = float(hit.get("distance", best_distance))
			best_hit = hit
	return best_hit


static func _intersect_brush(
	brush: Node3D, ray_origin: Vector3, ray_dir: Vector3, best_distance: float
) -> Dictionary:
	var faces: Array = brush.call("get_faces") if brush.has_method("get_faces") else []
	if faces.is_empty():
		return {}
	var inv = brush.global_transform.affine_inverse()
	var local_origin = inv * ray_origin
	var local_dir = (inv.basis * ray_dir).normalized()
	var face_index = 0
	var best_hit: Dictionary = {}
	for face in faces:
		if face == null or not face.has_method("triangulate"):
			face_index += 1
			continue
		var tri = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
		var tri_count = verts.size() / 3
		for t in range(tri_count):
			var idx = t * 3
			var a = verts[idx]
			var b = verts[idx + 1]
			var c = verts[idx + 2]
			var t_hit = _ray_triangle(local_origin, local_dir, a, b, c)
			if t_hit < 0.0:
				continue
			var hit_local = local_origin + local_dir * t_hit
			var hit_world = brush.global_transform * hit_local
			var distance = ray_origin.distance_to(hit_world)
			if distance >= best_distance:
				continue
			var bary = _barycentric(hit_local, a, b, c)
			var uv = Vector2.ZERO
			if uvs.size() >= idx + 3:
				uv = _bary_uv(uvs[idx], uvs[idx + 1], uvs[idx + 2], bary)
			best_distance = distance
			best_hit = {
				"brush": brush,
				"face_idx": face_index,
				"position": hit_world,
				"uv": uv,
				"distance": distance
			}
		face_index += 1
	return best_hit


static func _ray_triangle(
	origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, c: Vector3
) -> float:
	var e1 = b - a
	var e2 = c - a
	var p = dir.cross(e2)
	var det = e1.dot(p)
	if abs(det) < 0.000001:
		return -1.0
	var inv_det = 1.0 / det
	var tvec = origin - a
	var u = tvec.dot(p) * inv_det
	if u < 0.0 or u > 1.0:
		return -1.0
	var qvec = tvec.cross(e1)
	var v = dir.dot(qvec) * inv_det
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t = e2.dot(qvec) * inv_det
	return t if t >= 0.0 else -1.0


static func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 = b - a
	var v1 = c - a
	var v2 = p - a
	var d00 = v0.dot(v0)
	var d01 = v0.dot(v1)
	var d11 = v1.dot(v1)
	var d20 = v2.dot(v0)
	var d21 = v2.dot(v1)
	var denom = d00 * d11 - d01 * d01
	if abs(denom) < 0.000001:
		return Vector3(1, 0, 0)
	var v = (d11 * d20 - d01 * d21) / denom
	var w = (d00 * d21 - d01 * d20) / denom
	var u = 1.0 - v - w
	return Vector3(u, v, w)


static func _bary_uv(uv0: Vector2, uv1: Vector2, uv2: Vector2, bary: Vector3) -> Vector2:
	return uv0 * bary.x + uv1 * bary.y + uv2 * bary.z
