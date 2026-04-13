@tool
class_name HFDisplacementSystem
extends RefCounted

## Displacement surface management for HammerForge.
## Creates, destroys, paints (raise/lower/smooth/noise), and sews
## displacement surfaces on brush faces.

const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")

enum PaintMode { RAISE, LOWER, SMOOTH, NOISE, ALPHA }

var root: Node3D  # LevelRoot


func _init(p_root: Node3D = null) -> void:
	root = p_root


# ---------------------------------------------------------------------------
# Create / Destroy
# ---------------------------------------------------------------------------


## Create a displacement surface on the given face of a brush.
## The face must be a quad (4 vertices). Returns true on success.
func create_displacement(brush_id: String, face_index: int, power: int = 3) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		HFLog.warn("HFDisplacementSystem: brush not found: %s" % brush_id)
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		HFLog.warn("HFDisplacementSystem: face index out of range: %d" % face_index)
		return false
	var face: FaceData = faces[face_index]
	if face.local_verts.size() != 4:
		HFLog.warn(
			(
				"HFDisplacementSystem: displacement requires a quad face (4 verts), got %d"
				% face.local_verts.size()
			)
		)
		return false
	var disp = HFDisplacementData.new()
	disp.init_flat(power)
	face.displacement = disp
	_mark_brush_dirty(brush)
	return true


## Remove displacement from a face, reverting it to a flat quad.
func destroy_displacement(brush_id: String, face_index: int) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	face.displacement = null
	_mark_brush_dirty(brush)
	return true


## Check if a face has displacement data.
func has_displacement(brush_id: String, face_index: int) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	return faces[face_index].displacement != null


## Change the subdivision power of an existing displacement.
func set_power(brush_id: String, face_index: int, power: int) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	var old_disp: HFDisplacementData = face.displacement
	if old_disp.power == power:
		return true
	# Resample existing distances to new grid via bilinear interpolation.
	var new_disp = HFDisplacementData.new()
	new_disp.init_flat(power)
	new_disp.elevation = old_disp.elevation
	new_disp.sew_group = old_disp.sew_group
	var old_dim: int = old_disp.get_dim()
	var new_dim: int = new_disp.get_dim()
	for row in range(new_dim):
		for col in range(new_dim):
			var u: float = float(col) / float(new_dim - 1) * float(old_dim - 1)
			var v: float = float(row) / float(new_dim - 1) * float(old_dim - 1)
			var c0: int = int(floor(u))
			var c1: int = mini(c0 + 1, old_dim - 1)
			var r0: int = int(floor(v))
			var r1: int = mini(r0 + 1, old_dim - 1)
			var fu: float = u - float(c0)
			var fv: float = v - float(r0)
			var d00: float = old_disp.get_distance(r0, c0)
			var d10: float = old_disp.get_distance(r0, c1)
			var d01: float = old_disp.get_distance(r1, c0)
			var d11: float = old_disp.get_distance(r1, c1)
			var val: float = lerpf(lerpf(d00, d10, fu), lerpf(d01, d11, fu), fv)
			new_disp.set_distance(row, col, val)
	face.displacement = new_disp
	_mark_brush_dirty(brush)
	return true


# ---------------------------------------------------------------------------
# Paint operations
# ---------------------------------------------------------------------------


## Paint displacement at a world-space position. Uses a circular brush.
## Returns true if any vertex was modified.
func paint(
	brush_id: String,
	face_index: int,
	world_pos: Vector3,
	radius: float,
	strength: float,
	mode: int = PaintMode.RAISE  # PaintMode enum
) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	var disp: HFDisplacementData = face.displacement
	var d: int = disp.get_dim()
	if face.local_verts.size() != 4:
		return false
	var corners: Array[Vector3] = [
		face.local_verts[0], face.local_verts[1], face.local_verts[3], face.local_verts[2]
	]
	var basis: Basis = brush.global_transform.basis
	var origin: Vector3 = brush.global_transform.origin
	var modified := false
	for row in range(d):
		for col in range(d):
			var local_pos: Vector3 = disp.get_displaced_position(row, col, corners, face.normal)
			var global_pos: Vector3 = origin + basis * local_pos
			var dist_sq: float = global_pos.distance_squared_to(world_pos)
			if dist_sq > radius * radius:
				continue
			var falloff: float = 1.0 - sqrt(dist_sq) / radius
			falloff = falloff * falloff  # quadratic falloff
			var amount: float = strength * falloff
			match mode:
				PaintMode.RAISE:
					disp.set_distance(row, col, disp.get_distance(row, col) + amount)
					modified = true
				PaintMode.LOWER:
					disp.set_distance(row, col, disp.get_distance(row, col) - amount)
					modified = true
				PaintMode.SMOOTH:
					disp.smooth(amount * 0.5)
					modified = true
					break  # smooth operates on entire grid
				PaintMode.NOISE:
					# Per-vertex noise seeded by grid position for deterministic strokes.
					var noise_val: float = (
						sin(float(row) * 12.9898 + float(col) * 78.233) * 43758.5453
					)
					noise_val = noise_val - floor(noise_val)  # fract → [0,1)
					noise_val = (noise_val - 0.5) * 2.0  # remap to [-1, 1]
					disp.set_distance(row, col, disp.get_distance(row, col) + noise_val * amount)
					modified = true
				PaintMode.ALPHA:
					var cur: float = disp.get_alpha(row, col)
					disp.set_alpha(row, col, clampf(cur + amount, 0.0, 1.0))
					modified = true
	if modified:
		_mark_brush_dirty(brush)
	return modified


## Apply noise to a displacement surface.
func apply_noise(
	brush_id: String, face_index: int, noise: FastNoiseLite, scale: float = 1.0
) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	face.displacement.apply_noise(noise, scale)
	_mark_brush_dirty(brush)
	return true


## Smooth the entire displacement surface.
func smooth_all(brush_id: String, face_index: int, strength: float = 0.5) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	face.displacement.smooth(strength)
	_mark_brush_dirty(brush)
	return true


## Set elevation scale for the displacement.
func set_elevation(brush_id: String, face_index: int, elevation: float) -> bool:
	var brush: Node3D = _find_brush(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	face.displacement.elevation = elevation
	_mark_brush_dirty(brush)
	return true


# ---------------------------------------------------------------------------
# Sew — snap shared boundary vertices between adjacent displacements
# ---------------------------------------------------------------------------


## Sew all displacements sharing the same sew_group along shared edges.
## Averages boundary vertices that are within tolerance.
func sew_group(sew_group_id: int, tolerance: float = 0.5) -> int:
	if sew_group_id < 0:
		return 0
	var disp_faces: Array = _collect_displacements_in_group(sew_group_id)
	if disp_faces.size() < 2:
		return 0
	var sewn_count := 0
	for i in range(disp_faces.size()):
		for j in range(i + 1, disp_faces.size()):
			sewn_count += _sew_pair(disp_faces[i], disp_faces[j], tolerance)
	return sewn_count


## Sew all displacement groups in the scene.
func sew_all(tolerance: float = 0.5) -> int:
	var groups: Dictionary = {}
	var brushes: Array = _get_all_brushes()
	for brush in brushes:
		if not brush or not brush.get("faces"):
			continue
		for fi in range(brush.faces.size()):
			var face: FaceData = brush.faces[fi]
			if face.displacement == null:
				continue
			var sg: int = face.displacement.sew_group
			if sg < 0:
				continue
			if not groups.has(sg):
				groups[sg] = []
			groups[sg].append({"brush": brush, "face_index": fi, "face": face})
	var total := 0
	for sg in groups:
		var faces: Array = groups[sg]
		if faces.size() < 2:
			continue
		for i in range(faces.size()):
			for j in range(i + 1, faces.size()):
				total += _sew_pair(faces[i], faces[j], tolerance)
	return total


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


func _get_all_brushes() -> Array:
	if not root:
		return []
	if root.has_method("get_all_draft_brushes"):
		return root.get_all_draft_brushes()
	return []


func _collect_displacements_in_group(sg_id: int) -> Array:
	var result: Array = []
	var brushes: Array = _get_all_brushes()
	for brush in brushes:
		if not brush or not brush.get("faces"):
			continue
		for fi in range(brush.faces.size()):
			var face: FaceData = brush.faces[fi]
			if face.displacement != null and face.displacement.sew_group == sg_id:
				result.append({"brush": brush, "face_index": fi, "face": face})
	return result


func _sew_pair(entry_a: Dictionary, entry_b: Dictionary, tolerance: float) -> int:
	var face_a: FaceData = entry_a["face"]
	var face_b: FaceData = entry_b["face"]
	var disp_a: HFDisplacementData = face_a.displacement
	var disp_b: HFDisplacementData = face_b.displacement
	if disp_a == null or disp_b == null:
		return 0
	var brush_a: Node3D = entry_a["brush"]
	var brush_b: Node3D = entry_b["brush"]
	var basis_a: Basis = brush_a.global_transform.basis
	var origin_a: Vector3 = brush_a.global_transform.origin
	var basis_b: Basis = brush_b.global_transform.basis
	var origin_b: Vector3 = brush_b.global_transform.origin
	if face_a.local_verts.size() != 4 or face_b.local_verts.size() != 4:
		return 0
	var corners_a: Array[Vector3] = [
		face_a.local_verts[0], face_a.local_verts[1], face_a.local_verts[3], face_a.local_verts[2]
	]
	var corners_b: Array[Vector3] = [
		face_b.local_verts[0], face_b.local_verts[1], face_b.local_verts[3], face_b.local_verts[2]
	]
	var da: int = disp_a.get_dim()
	var db: int = disp_b.get_dim()
	var sewn := 0
	# Check boundary vertices of A against boundary vertices of B.
	var boundary_a: Array = _get_boundary_indices(da)
	var boundary_b: Array = _get_boundary_indices(db)
	for idx_a in boundary_a:
		var ra: int = idx_a / da
		var ca: int = idx_a % da
		var local_a: Vector3 = disp_a.get_displaced_position(ra, ca, corners_a, face_a.normal)
		var world_a: Vector3 = origin_a + basis_a * local_a
		for idx_b in boundary_b:
			var rb: int = idx_b / db
			var cb: int = idx_b % db
			var local_b: Vector3 = disp_b.get_displaced_position(rb, cb, corners_b, face_b.normal)
			var world_b: Vector3 = origin_b + basis_b * local_b
			if world_a.distance_to(world_b) < tolerance:
				var mid: Vector3 = (world_a + world_b) * 0.5
				# Project back to local and compute new distance
				var new_local_a: Vector3 = basis_a.inverse() * (mid - origin_a)
				var base_a: Vector3 = _get_base_position(ra, ca, da, corners_a)
				var diff_a: float = (new_local_a - base_a).dot(face_a.normal)
				disp_a.set_distance(
					ra, ca, diff_a / disp_a.elevation if disp_a.elevation != 0.0 else 0.0
				)
				var new_local_b: Vector3 = basis_b.inverse() * (mid - origin_b)
				var base_b: Vector3 = _get_base_position(rb, cb, db, corners_b)
				var diff_b: float = (new_local_b - base_b).dot(face_b.normal)
				disp_b.set_distance(
					rb, cb, diff_b / disp_b.elevation if disp_b.elevation != 0.0 else 0.0
				)
				sewn += 1
	if sewn > 0:
		_mark_brush_dirty(brush_a)
		_mark_brush_dirty(brush_b)
	return sewn


func _get_base_position(row: int, col: int, dim: int, corners: Array[Vector3]) -> Vector3:
	var u: float = float(col) / float(dim - 1)
	var v: float = float(row) / float(dim - 1)
	var top: Vector3 = corners[0].lerp(corners[1], u)
	var bot: Vector3 = corners[2].lerp(corners[3], u)
	return top.lerp(bot, v)


func _get_boundary_indices(dim: int) -> Array:
	var indices: Array = []
	for i in range(dim):
		indices.append(i)  # top row
		indices.append((dim - 1) * dim + i)  # bottom row
		if i > 0 and i < dim - 1:
			indices.append(i * dim)  # left column
			indices.append(i * dim + dim - 1)  # right column
	return indices
