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

## How many boundary vertices the last sew left on another face's edge with the
## crack there still open. A vertex with no vertex of the other face to meet, as
## where a power 3 tile meets a power 4 one, goes onto that face's edge once the
## edge's vertices either side of it have settled. Where two faces' edge vertices
## interleave, as where a 3 m tile meets a 4 m one at one power, each waits on
## the other, and Sew leaves them where they are. So does a vertex on two faces'
## edges that draw different lines through its place, and one that cannot reach
## the line, as a wall's foot vertex between two sculpted floor vertices. Where
## two finer tiles share such a place they still meet each other there, and both
## are counted, since neither is on the edge.
var unmatched_seam_vertices := 0


## Sew all displacements sharing the same sew_group along shared edges.
## Returns how many seam points it sewed: places where vertices met, and
## vertices it put on another face's edge.
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
## agreeing and the four not. Each moves only along its own face's normal, so
## where the normals differ, as where a floor meets a wall, the vertices meet at
## the place itself, the one point every one of them reaches. A place on the edge
## of a face with no vertex there, a T junction, then goes onto that edge,
## whether one vertex is there or the corner two finer tiles share. Where it
## cannot, the finer tiles still meet each other there.
func _sew_faces(entries: Array) -> int:
	if entries.size() < 2:
		return 0
	# Every boundary vertex in the group, where it sits on its face and where it
	# is drawn, in world space, and by face and grid cell. Each face's outline, to
	# find T junctions on.
	var vertices: Array = []
	var index_of := {}
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
		var dir: Vector3 = (xform.basis * face.normal).normalized()
		for idx in _get_boundary_indices(dim):
			var row: int = idx / dim
			var col: int = idx % dim
			var base: Vector3 = xform * _get_base_position(row, col, dim, corners)
			var drawn: Vector3 = _drawn_at(entries[e], row, col)
			index_of[Vector3i(e, row, col)] = vertices.size()
			vertices.append(
				{"entry": e, "row": row, "col": col, "base": base, "drawn": drawn, "dir": dir}
			)
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
		vertices[i]["place"] = nearest
	var sewn := 0
	var touched := {}
	# T junctions, by place, each with the other faces' edges it lies on.
	var waiting := {}
	for p in places.size():
		var faces_here := _faces_at(places[p], vertices)
		# A place on the edge of a face that has no vertex there goes onto that
		# edge below, whether it is one tile's vertex or the corner two finer
		# tiles share: their average is no more on the coarser edge (#1337).
		var edges := _edges_under(places[p]["base"], faces_here, entries, outlines, index_of)
		if not edges.is_empty():
			waiting[p] = edges
			continue
		if faces_here.size() < 2:
			continue
		_meet(places[p], vertices, entries, touched)
		sewn += 1
	# The other face draws a straight line between its vertices either side of a
	# T junction, so the vertex goes onto that line or the seam keeps a crack. The
	# coarser edge wins whichever tile was sculpted, since it has no vertex there
	# to bend. A place waits until both ends of its edge have settled, which the
	# shared vertices sewn above already have. On two edges that draw different
	# lines through it, no one point closes both cracks, so it stays off them and
	# is counted. So does a vertex that cannot reach its line, a wall's foot vertex
	# between two sculpted floor vertices: the floor has no vertex there to bend.
	var settled_one := true
	while settled_one:
		settled_one = false
		for p in waiting.keys():
			var edges: Array = waiting[p]
			var ends_settled := true
			for edge in edges:
				ends_settled = ends_settled and not waiting.has(vertices[edge["from"]]["place"])
				ends_settled = ends_settled and not waiting.has(vertices[edge["to"]]["place"])
			if not ends_settled:
				continue
			var on_edges: Array[Vector3] = []
			var target := Vector3.ZERO
			for edge in edges:
				var a: Dictionary = vertices[edge["from"]]
				var b: Dictionary = vertices[edge["to"]]
				var on_a := _drawn_at(entries[a["entry"]], a["row"], a["col"])
				var on_b := _drawn_at(entries[b["entry"]], b["row"], b["col"])
				on_edges.append(on_a.lerp(on_b, edge["t"]))
				target += on_edges[-1]
			target /= float(edges.size())
			var agree := true
			for point in on_edges:
				agree = agree and point.distance_to(target) <= SEW_MATCH
			for i in places[p]["members"]:
				agree = agree and _reaches(vertices[i], target)
			if not agree:
				continue
			for i in places[p]["members"]:
				var entry: Dictionary = entries[vertices[i]["entry"]]
				_sew_vertex_to(entry, vertices[i]["row"], vertices[i]["col"], target)
				touched[entry["brush"]] = true
			waiting.erase(p)
			sewn += 1
			settled_one = true
	# A place left off the edge is still a corner its own faces share. Two finer
	# tiles there meet each other, as they would anywhere else, and close their
	# own crack; each still misses the coarser edge, so both stay counted (#1474).
	for p in waiting:
		unmatched_seam_vertices += (places[p]["members"] as Array).size()
		if _faces_at(places[p], vertices).size() < 2:
			continue
		_meet(places[p], vertices, entries, touched)
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


## The faces, by entry, that have a vertex at one place of `_sew_faces`.
func _faces_at(place: Dictionary, vertices: Array) -> Dictionary:
	var faces := {}
	for i in place["members"]:
		faces[vertices[i]["entry"]] = true
	return faces


## Moves every vertex at one place of `_sew_faces` to their average, and marks
## their brushes touched. A wall's foot cannot take the height a floor's seam
## vertex averages with it to: the floor went halfway there, the wall stayed, and
## the next Sew went halfway again (#1346). The place is the one point every face
## reaches, so where one of them cannot reach the average, all go to the place.
func _meet(place: Dictionary, vertices: Array, entries: Array, touched: Dictionary) -> void:
	var members: Array = place["members"]
	var target := Vector3.ZERO
	for i in members:
		var drawn: Vector3 = vertices[i]["drawn"]
		target += drawn
	target /= float(members.size())
	for i in members:
		if not _reaches(vertices[i], target):
			target = place["base"]
			break
	for i in members:
		var entry: Dictionary = entries[vertices[i]["entry"]]
		_sew_vertex_to(entry, vertices[i]["row"], vertices[i]["col"], target)
		touched[entry["brush"]] = true


## Moves one boundary vertex along its face's normal to the height of `target`,
## a point in world space.
func _sew_vertex_to(entry: Dictionary, row: int, col: int, target: Vector3) -> void:
	var face: FaceData = entry["face"]
	var disp: HFDisplacementData = face.displacement
	var xform: Transform3D = (entry["brush"] as Node3D).global_transform
	var base := _get_base_position(row, col, disp.get_dim(), _sew_corners(face))
	var height: float = (xform.affine_inverse() * target - base).dot(face.normal)
	disp.set_distance(row, col, height / disp.elevation if disp.elevation != 0.0 else 0.0)


## Whether a boundary vertex of `_sew_faces` can be sewn to `target`: it moves
## only along its face's normal, so the target has to lie on that line through
## its place. A wall's foot cannot take a floor's height.
func _reaches(vertex: Dictionary, target: Vector3) -> bool:
	var off: Vector3 = target - vertex["base"]
	var dir: Vector3 = vertex["dir"]
	return (off - dir * off.dot(dir)).length() <= SEW_MATCH


## Where a face in the group draws one of its grid vertices now, in world space.
func _drawn_at(entry: Dictionary, row: int, col: int) -> Vector3:
	var face: FaceData = entry["face"]
	var disp: HFDisplacementData = face.displacement
	var xform: Transform3D = (entry["brush"] as Node3D).global_transform
	return xform * disp.get_displaced_position(row, col, _sew_corners(face), face.normal)


## The edges of the group's other faces that a point lies on, skipping the faces
## in `own`, the entries whose vertex the point is. Each is the two boundary
## vertices of that face either side of the point, by their index in `index_of`,
## and how far the point is from the first towards the second.
func _edges_under(
	point: Vector3, own: Dictionary, entries: Array, outlines: Array, index_of: Dictionary
) -> Array:
	var edges: Array = []
	for e in outlines.size():
		var outline: PackedVector3Array = outlines[e]
		if own.has(e) or outline.is_empty():
			continue
		var disp: HFDisplacementData = (entries[e]["face"] as FaceData).displacement
		var dim: int = disp.get_dim()
		for k in outline.size():
			var start: Vector3 = outline[k]
			var side: Vector3 = outline[(k + 1) % outline.size()] - start
			if side.is_zero_approx():
				continue
			var along: float = clampf((point - start).dot(side) / side.length_squared(), 0.0, 1.0)
			if (start + side * along).distance_to(point) > SEW_MATCH:
				continue
			# How many of the face's vertices along this side the point is.
			var step: float = along * float(dim - 1)
			var before: int = mini(floori(step), dim - 2)
			var cell_from := _side_cell(k, before, dim)
			var cell_to := _side_cell(k, before + 1, dim)
			var from: int = index_of[Vector3i(e, cell_from.x, cell_from.y)]
			var to: int = index_of[Vector3i(e, cell_to.x, cell_to.y)]
			edges.append({"from": from, "to": to, "t": step - float(before)})
			break
	return edges


## The grid cell, as (row, col), `step` vertices along side `k` of a face's
## outline: the side from the face's corner k to the next one round.
func _side_cell(k: int, step: int, dim: int) -> Vector2i:
	var start: Vector2i = HFDisplacementData.CORNER_CELLS[k]
	var end: Vector2i = HFDisplacementData.CORNER_CELLS[(k + 1) % 4]
	return start * (dim - 1) + (end - start) * step


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
