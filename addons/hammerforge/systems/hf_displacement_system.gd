@tool
class_name HFDisplacementSystem
extends RefCounted

## Displacement surface management for HammerForge.
## Creates, destroys, paints (raise/lower/smooth/noise), and sews
## displacement surfaces on brush faces.
##
## Displacements stay on brush faces. Heightmap paint layers are a separate
## terrain path; convert-to-heightmap uses the displaced mesh bounds and skips
## subtract brushes so the two representations do not double-count.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
@warning_ignore_restore("shadowed_global_identifier")

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
	var brush: Node3D = root.find_brush_by_id(brush_id)
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
	if face.displacement != null:
		# init_flat() resets distances, offsets, alphas, sew_group and elevation,
		# so building a fresh one here would throw away the sculpt on this face
		# and still report success. destroy_displacement() is the deliberate way
		# to clear one, and it is undoable.
		HFLog.warn(
			(
				"HFDisplacementSystem: face %d already has a displacement, destroy it first"
				% face_index
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
	var brush: Node3D = root.find_brush_by_id(brush_id)
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
	var brush: Node3D = root.find_brush_by_id(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	return faces[face_index].displacement != null


## Change the subdivision power of an existing displacement.
func set_power(brush_id: String, face_index: int, power: int) -> bool:
	var brush: Node3D = root.find_brush_by_id(brush_id)
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
	# The resample keeps the grid the way round it was, so a mirrored sculpt's
	# cells still have to fold the mirrored way.
	new_disp.flip_diagonals = old_disp.flip_diagonals
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
	# world_pos comes from a raycast. A miss, a degenerate camera or an
	# off-surface hit produces a non-finite vector at that boundary, and this is
	# the last place that can catch it: one NaN centre fills every distance in
	# the grid with NaN, and smooth, noise and further paint all stay NaN.
	if not world_pos.is_finite() or not is_finite(radius) or not is_finite(strength):
		HFLog.warn("HFDisplacementSystem: paint needs a finite centre, radius and strength")
		return false
	if radius <= 0.0:
		return false
	var brush: Node3D = root.find_brush_by_id(brush_id)
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
	var brush: Node3D = root.find_brush_by_id(brush_id)
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
	var brush: Node3D = root.find_brush_by_id(brush_id)
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
	var brush: Node3D = root.find_brush_by_id(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	var face: FaceData = faces[face_index]
	if face.displacement == null:
		return false
	if not is_finite(elevation):
		HFLog.warn("HFDisplacementSystem: elevation must be finite")
		return false
	# elevation multiplies distances that are already in world units, so the
	# scale that means anything is the face's own size. An elevation past that
	# moves one unit of sculpt further than the face it sits on is wide.
	var limit: float = maxf(_face_extent(face), 1.0)
	var bounded: float = clampf(elevation, -limit, limit)
	if not is_equal_approx(bounded, elevation):
		HFLog.warn(
			"HFDisplacementSystem: elevation %f is beyond the face, using %f" % [elevation, bounded]
		)
	face.displacement.elevation = bounded
	_mark_brush_dirty(brush)
	return true


## Longest distance between any two corners of a face. Used as the scale the
## face's own displacement is measured against.
func _face_extent(face: FaceData) -> float:
	var extent := 0.0
	for i in range(face.local_verts.size()):
		for j in range(i + 1, face.local_verts.size()):
			extent = maxf(extent, face.local_verts[i].distance_to(face.local_verts[j]))
	return extent


# ---------------------------------------------------------------------------
# Sew — snap shared boundary vertices between adjacent displacements
# ---------------------------------------------------------------------------

## How far apart two boundary vertices may sit on their faces, before any sculpt,
## and still be one point of a seam. Float error only: faces that share an edge
## put their vertices at the same places. It was 0.5 between sculpted positions,
## half a Quake unit until the metric scale change made it half a metre: wider
## than the gap between edge vertices on any tile under 8 m, so a seam vertex was
## averaged with its partner's neighbours and vertices off the seam moved (#1195).
const SEW_MATCH := 0.001

## How many boundary vertices the last sew found on another face's edge with no
## vertex of that face to meet, as where a power 3 tile meets a power 4 one.
## Sew leaves them where they are.
var unmatched_seam_vertices := 0


## Sew all displacements sharing the same sew_group along shared edges.
## Returns how many seam points it sewed.
func sew_group(sew_group_id: int) -> int:
	unmatched_seam_vertices = 0
	if sew_group_id < 0:
		return 0
	return _sew_faces(_collect_displacements_in_group(sew_group_id))


## Sew all displacement groups in the scene.
func sew_all() -> int:
	unmatched_seam_vertices = 0
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
		total += _sew_faces(groups[sg])
	return total


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _mark_brush_dirty(brush: Node3D) -> void:
	if brush.has_method("rebuild_preview"):
		brush.rebuild_preview()
	if root and brush.get("brush_id"):
		root.tag_brush_dirty(brush.brush_id)


func _get_all_brushes() -> Array:
	if not root:
		return []
	if root.has_method("get_all_draft_brushes"):
		return root.get_all_draft_brushes()
	# Lightweight consumers may expose only the shared authoritative iterator.
	if root.has_method("_iter_managed_brush_nodes"):
		return root._iter_managed_brush_nodes()
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


## Sews one group's faces. A boundary vertex is placed by where it sits on its
## face before any sculpt, since the sculpted heights are what sew is there to
## reconcile, and every vertex at one place moves to their average at once: where
## four tiles share a corner, sewing them two at a time would leave each pair
## agreeing and the four not. A vertex with no other face's vertex at its place
## stays where it is.
func _sew_faces(entries: Array) -> int:
	if entries.size() < 2:
		return 0
	# Every boundary vertex in the group, where it sits on its face and where it
	# is drawn, in world space. Each face's outline, to find T junctions on.
	var vertices: Array = []
	var outlines: Array = []
	for e in entries.size():
		var face: FaceData = entries[e]["face"]
		var disp: HFDisplacementData = face.displacement
		var xform: Transform3D = (entries[e]["brush"] as Node3D).global_transform
		var outline := PackedVector3Array()
		if disp != null and face.local_verts.size() == 4:
			for corner in face.local_verts:
				outline.append(xform * corner)
		outlines.append(outline)
		if outline.is_empty():
			continue
		var corners := _sew_corners(face)
		var dim: int = disp.get_dim()
		for idx in _get_boundary_indices(dim):
			var row: int = idx / dim
			var col: int = idx % dim
			var base: Vector3 = xform * _get_base_position(row, col, dim, corners)
			var drawn: Vector3 = xform * disp.get_displaced_position(row, col, corners, face.normal)
			vertices.append({"entry": e, "row": row, "col": col, "base": base, "drawn": drawn})
	# Each vertex joins the nearest place within SEW_MATCH, looking only in its
	# own cell of a grid that fine and the cells round it, or starts a place.
	var places: Array = []
	var cells := {}
	for i in vertices.size():
		var base: Vector3 = vertices[i]["base"]
		var cell := Vector3i((base / SEW_MATCH).floor())
		var nearest := -1
		var nearest_gap := SEW_MATCH
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for p in cells.get(cell + Vector3i(dx, dy, dz), []):
						var gap: float = (places[p]["base"] as Vector3).distance_to(base)
						if gap <= nearest_gap:
							nearest = p
							nearest_gap = gap
		if nearest < 0:
			nearest = places.size()
			places.append({"base": base, "members": []})
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(nearest)
		places[nearest]["members"].append(i)
	var sewn := 0
	var touched := {}
	for place in places:
		var members: Array = place["members"]
		var faces_here := {}
		for i in members:
			faces_here[vertices[i]["entry"]] = true
		if faces_here.size() < 2:
			if _on_another_outline(place["base"], vertices[members[0]]["entry"], outlines):
				unmatched_seam_vertices += 1
			continue
		var target := Vector3.ZERO
		for i in members:
			var drawn: Vector3 = vertices[i]["drawn"]
			target += drawn
		target /= float(members.size())
		for i in members:
			var entry: Dictionary = entries[vertices[i]["entry"]]
			_sew_vertex_to(entry, vertices[i]["row"], vertices[i]["col"], target)
			touched[entry["brush"]] = true
		sewn += 1
	for brush in touched:
		_mark_brush_dirty(brush)
	return sewn


## A quad face's corners in the order its displacement grid reads them:
## TL, TR, BL, BR.
func _sew_corners(face: FaceData) -> Array[Vector3]:
	var corners: Array[Vector3] = [
		face.local_verts[0], face.local_verts[1], face.local_verts[3], face.local_verts[2]
	]
	return corners


## Moves one boundary vertex along its face's normal to the height of `target`,
## a point in world space.
func _sew_vertex_to(entry: Dictionary, row: int, col: int, target: Vector3) -> void:
	var face: FaceData = entry["face"]
	var disp: HFDisplacementData = face.displacement
	var xform: Transform3D = (entry["brush"] as Node3D).global_transform
	var base := _get_base_position(row, col, disp.get_dim(), _sew_corners(face))
	var height: float = (xform.affine_inverse() * target - base).dot(face.normal)
	disp.set_distance(row, col, height / disp.elevation if disp.elevation != 0.0 else 0.0)


## Whether a point lies on the edge of any face in the group but its own.
func _on_another_outline(point: Vector3, own: int, outlines: Array) -> bool:
	for e in outlines.size():
		var outline: PackedVector3Array = outlines[e]
		if e == own:
			continue
		for k in outline.size():
			var next: Vector3 = outline[(k + 1) % outline.size()]
			var on_edge := Geometry3D.get_closest_point_to_segment(point, outline[k], next)
			if on_edge.distance_to(point) <= SEW_MATCH:
				return true
	return false


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
