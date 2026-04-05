@tool
class_name HFVertexSystem
extends RefCounted

## Vertex editing system for HammerForge.
## Extracts vertices from brush faces, supports selection, movement with
## convexity validation, and undo/redo integration.

const FaceData = preload("res://addons/hammerforge/face_data.gd")

enum VertexSubMode { VERTEX, EDGE }

var root: Node3D  # LevelRoot
var sub_mode: int = VertexSubMode.VERTEX
var selected_vertices: Dictionary = {}  # {brush_id: PackedInt32Array}
var selected_edges: Dictionary = {}  # {brush_id: Array of [int, int] pairs}
var _hovered_vertex_idx: int = -1
var _hovered_brush_id: String = ""
var _hovered_edge: Array = []  # [brush_id, idx_a, idx_b] or empty
var _drag_active := false
var _drag_start_pos := Vector3.ZERO
var _pre_drag_faces: Dictionary = {}  # {brush_id: Array[Dict]} — face snapshots before drag


func _init(p_root: Node3D = null) -> void:
	root = p_root


## Extract unique vertex positions from a brush's faces.
## Returns PackedVector3Array of unique vertices (in local space).
func get_brush_vertices(brush: Node3D) -> PackedVector3Array:
	var verts := PackedVector3Array()
	var seen: Dictionary = {}
	if not brush or not brush.get("faces"):
		return verts
	var faces: Array = brush.faces
	for face in faces:
		if face == null:
			continue
		var local_verts: PackedVector3Array = face.local_verts
		for v in local_verts:
			var key := _vertex_key(v)
			if not seen.has(key):
				seen[key] = true
				verts.append(v)
	return verts


## Move selected vertices by delta. Updates all faces sharing those vertices.
## Returns true if the move was valid (all brushes remain convex).
func move_vertices(delta: Vector3) -> bool:
	if selected_vertices.is_empty():
		return false
	# Snapshot faces before move if not already captured
	if _pre_drag_faces.is_empty():
		_capture_face_snapshots()
	# Apply move
	for brush_id in selected_vertices:
		var brush = _find_brush(brush_id)
		if not brush:
			continue
		var vert_indices: PackedInt32Array = selected_vertices[brush_id]
		var unique_verts = get_brush_vertices(brush)
		var target_positions: Dictionary = {}
		for vi in vert_indices:
			if vi >= 0 and vi < unique_verts.size():
				var old_pos = unique_verts[vi]
				target_positions[_vertex_key(old_pos)] = old_pos + delta
		# Update face vertices
		var faces: Array = brush.faces
		for face in faces:
			if face == null:
				continue
			var changed := false
			var new_verts := PackedVector3Array()
			for v in face.local_verts:
				var key = _vertex_key(v)
				if target_positions.has(key):
					new_verts.append(target_positions[key])
					changed = true
				else:
					new_verts.append(v)
			if changed:
				face.local_verts = new_verts
				face.ensure_geometry()
	# Validate convexity
	for brush_id in selected_vertices:
		var brush = _find_brush(brush_id)
		if brush and not validate_convexity(brush):
			_restore_face_snapshots()
			if root and root.has_signal("user_message"):
				root.emit_signal("user_message", "Move rejected: would create non-convex brush", 1)
			return false
	# Rebuild previews
	for brush_id in selected_vertices:
		var brush = _find_brush(brush_id)
		if brush and brush.has_method("rebuild_preview"):
			brush.rebuild_preview()
	return true


## Validate that all faces of a brush form a convex shape.
## Checks that no vertex lies in front of any face plane.
func validate_convexity(brush: Node3D) -> bool:
	if not brush or not brush.get("faces"):
		return true
	var faces: Array = brush.faces
	if faces.size() < 4:
		return true  # Degenerate, allow
	# Collect all unique vertices
	var all_verts := get_brush_vertices(brush)
	if all_verts.is_empty():
		return true
	# For each face, check that all vertices are behind or on the plane
	for face in faces:
		if face == null or face.local_verts.size() < 3:
			continue
		var plane_point: Vector3 = face.local_verts[0]
		var plane_normal: Vector3 = face.normal
		if plane_normal.length() < 0.001:
			continue
		for v in all_verts:
			var d = plane_normal.dot(v - plane_point)
			if d > 0.02:  # Small tolerance for floating-point imprecision
				return false
	return true


## Clip a non-convex brush to its convex hull. Recomputes faces from the convex
## hull of the brush's vertices. Returns true if the brush was modified.
func clip_to_convex(brush_id: String) -> bool:
	var brush = _find_brush(brush_id)
	if not brush or not brush.get("faces"):
		return false
	if validate_convexity(brush):
		return false  # Already convex, nothing to do

	var all_verts := get_brush_vertices(brush)
	if all_verts.size() < 4:
		return false

	# Snapshot for undo
	_capture_face_snapshots_for([brush_id])

	# Use Geometry3D.compute_convex_mesh_points to get hull vertices,
	# then rebuild faces from the hull planes.
	var hull_points: PackedVector3Array = _convex_hull_3d(all_verts)
	if hull_points.size() < 4:
		_pre_drag_faces.clear()
		return false

	var new_faces := _faces_from_convex_hull(hull_points, brush.faces)
	if new_faces.is_empty():
		_pre_drag_faces.clear()
		return false

	# Replace brush faces
	brush.faces.clear()
	for f in new_faces:
		brush.faces.append(f)

	if brush.has_method("rebuild_preview"):
		brush.rebuild_preview()
	return true


## Compute the convex hull of a set of 3D points.
## Returns only the points that lie on the hull surface.
func _convex_hull_3d(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 4:
		return points
	# Build planes from all triangle combinations, keep points on the hull.
	# Use Geometry3D.build_convex_mesh_points (available in Godot 4.x) if possible.
	# Fallback: iterative convex hull via extreme-point method.
	var hull_planes: Array[Plane] = []

	# Build planes from all face triples — brute force for small vertex counts.
	# For brush editing, vertex count is typically < 100.
	var n := points.size()
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a: Vector3 = points[i]
				var b: Vector3 = points[j]
				var c: Vector3 = points[k]
				var normal: Vector3 = (b - a).cross(c - a)
				if normal.length_squared() < 0.0001:
					continue
				normal = normal.normalized()
				var d: float = normal.dot(a)
				# Check if all other points are on the same side (behind or on)
				var all_behind := true
				var all_in_front := true
				for m in range(n):
					if m == i or m == j or m == k:
						continue
					var dist: float = normal.dot(points[m]) - d
					if dist > 0.01:
						all_behind = false
					if dist < -0.01:
						all_in_front = false
				if all_behind:
					hull_planes.append(Plane(normal, d))
				elif all_in_front:
					hull_planes.append(Plane(-normal, -d))

	# Collect hull vertices: points that lie on at least one hull plane
	var hull_verts := PackedVector3Array()
	var seen: Dictionary = {}
	for p in points:
		for plane in hull_planes:
			if abs(plane.normal.dot(p) - plane.d) < 0.02:
				var key := _vertex_key(p)
				if not seen.has(key):
					seen[key] = true
					hull_verts.append(p)
				break
	return hull_verts


## Build FaceData objects from convex hull vertices grouped by coplanar sets.
## Inherits UV settings from the closest original face.
func _faces_from_convex_hull(hull_verts: PackedVector3Array, original_faces: Array) -> Array:
	# Group vertices by hull plane.
	# A vertex can belong to multiple faces (e.g. cube corner → 3 faces),
	# so we track discovered *planes* (not vertices) to avoid duplicates.
	var plane_groups: Array = []  # [{normal: Vector3, verts: PackedVector3Array}]
	var found_planes: Array = []  # Array[{normal: Vector3, d: float}] for dedup

	# Discover hull planes by finding coplanar groups from all vertex triples
	for i in range(hull_verts.size()):
		for j in range(i + 1, hull_verts.size()):
			for k in range(j + 1, hull_verts.size()):
				var a: Vector3 = hull_verts[i]
				var b: Vector3 = hull_verts[j]
				var c: Vector3 = hull_verts[k]
				var normal: Vector3 = (b - a).cross(c - a)
				if normal.length_squared() < 0.0001:
					continue
				normal = normal.normalized()
				var d: float = normal.dot(a)
				# Verify this is a hull face (all verts on or behind the plane)
				var is_hull_face := true
				for m in range(hull_verts.size()):
					if normal.dot(hull_verts[m]) - d > 0.02:
						is_hull_face = false
						break
				if not is_hull_face:
					normal = -normal
					d = -d
					var still_valid := true
					for m in range(hull_verts.size()):
						if normal.dot(hull_verts[m]) - d > 0.02:
							still_valid = false
							break
					if not still_valid:
						continue
				# Check if we already found this plane (same normal & distance)
				var is_duplicate := false
				for existing in found_planes:
					var en: Vector3 = existing["normal"]
					var ed: float = existing["d"]
					if en.dot(normal) > 0.99 and abs(ed - d) < 0.02:
						is_duplicate = true
						break
				if is_duplicate:
					continue
				# Collect all coplanar hull verts
				var coplanar := PackedVector3Array()
				for m in range(hull_verts.size()):
					if abs(normal.dot(hull_verts[m]) - d) < 0.02:
						coplanar.append(hull_verts[m])
				if coplanar.size() >= 3:
					var sorted_verts := _sort_coplanar_verts(coplanar, normal)
					if sorted_verts.size() >= 3:
						plane_groups.append({"normal": normal, "verts": sorted_verts})
						found_planes.append({"normal": normal, "d": d})

	# Create FaceData for each plane group
	var result: Array = []
	for group in plane_groups:
		var face = FaceData.new()
		face.local_verts = group["verts"]
		face.normal = group["normal"]
		# Inherit UV settings from closest original face by normal similarity
		var best_dot := -2.0
		var best_face: FaceData = null
		for orig in original_faces:
			if orig == null:
				continue
			var dot_val: float = group["normal"].dot(orig.normal)
			if dot_val > best_dot:
				best_dot = dot_val
				best_face = orig
		if best_face:
			face.material_idx = best_face.material_idx
			face.uv_projection = best_face.uv_projection
			face.uv_scale = best_face.uv_scale
			face.uv_offset = best_face.uv_offset
			face.uv_rotation = best_face.uv_rotation
		face.ensure_geometry()
		result.append(face)
	return result


## Sort coplanar vertices in winding order around their centroid.
func _sort_coplanar_verts(verts: PackedVector3Array, normal: Vector3) -> PackedVector3Array:
	if verts.size() < 3:
		return verts
	var centroid := Vector3.ZERO
	for v in verts:
		centroid += v
	centroid /= float(verts.size())
	# Build a local 2D basis on the plane
	var arbitrary := Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var u: Vector3 = normal.cross(arbitrary).normalized()
	var v_axis: Vector3 = normal.cross(u).normalized()
	# Project to 2D and sort by angle
	var angles: Array = []
	for i in range(verts.size()):
		var rel: Vector3 = verts[i] - centroid
		var angle: float = atan2(rel.dot(v_axis), rel.dot(u))
		angles.append({"idx": i, "angle": angle})
	angles.sort_custom(func(a, b): return a["angle"] < b["angle"])
	var sorted := PackedVector3Array()
	for entry in angles:
		sorted.append(verts[entry["idx"]])
	return sorted


## Find the closest vertex to screen position. Returns {brush_id, vertex_index, distance}
## or empty dict if none within threshold.
func pick_vertex(camera: Camera3D, screen_pos: Vector2, threshold_px: float = 12.0) -> Dictionary:
	if not camera or not root:
		return {}
	var best_dist := threshold_px
	var best := {}
	var brushes = _get_selected_brushes()
	for brush in brushes:
		if not brush:
			continue
		var verts = get_brush_vertices(brush)
		var brush_id = brush.brush_id if brush.get("brush_id") else ""
		var world_xform: Transform3D = brush.global_transform
		for i in range(verts.size()):
			var world_pos = world_xform * verts[i]
			if not camera.is_position_behind(world_pos):
				var screen = camera.unproject_position(world_pos)
				var dist = screen.distance_to(screen_pos)
				if dist < best_dist:
					best_dist = dist
					best = {
						"brush_id": brush_id,
						"vertex_index": i,
						"world_pos": world_pos,
						"distance": dist
					}
	return best


## Select a vertex. If additive is true, toggle selection; otherwise replace.
func select_vertex(brush_id: String, vertex_index: int, additive: bool = false) -> void:
	if not additive:
		selected_vertices.clear()
	if not selected_vertices.has(brush_id):
		selected_vertices[brush_id] = PackedInt32Array()
	var indices: PackedInt32Array = selected_vertices[brush_id]
	if additive and indices.has(vertex_index):
		# Remove from selection
		var new_indices := PackedInt32Array()
		for idx in indices:
			if idx != vertex_index:
				new_indices.append(idx)
		if new_indices.is_empty():
			selected_vertices.erase(brush_id)
		else:
			selected_vertices[brush_id] = new_indices
	else:
		if not indices.has(vertex_index):
			indices.append(vertex_index)
			selected_vertices[brush_id] = indices


## Clear all vertex and edge selection.
func clear_selection() -> void:
	selected_vertices.clear()
	selected_edges.clear()
	_hovered_vertex_idx = -1
	_hovered_brush_id = ""
	_hovered_edge = []


## Update hover state for a vertex near the cursor.
func update_hover(camera: Camera3D, screen_pos: Vector2) -> void:
	var pick = pick_vertex(camera, screen_pos)
	if pick.is_empty():
		_hovered_vertex_idx = -1
		_hovered_brush_id = ""
	else:
		_hovered_vertex_idx = pick.get("vertex_index", -1)
		_hovered_brush_id = pick.get("brush_id", "")


## Begin a vertex drag operation.
func begin_drag(start_world_pos: Vector3) -> void:
	_drag_active = true
	_drag_start_pos = start_world_pos
	_capture_face_snapshots()


## End drag and return the face snapshots for undo.
func end_drag() -> Dictionary:
	_drag_active = false
	var snapshots = _pre_drag_faces.duplicate(true)
	_pre_drag_faces.clear()
	return snapshots


## Cancel drag, restoring original face data.
func cancel_drag() -> void:
	if _drag_active:
		_restore_face_snapshots()
	_drag_active = false
	_pre_drag_faces.clear()


func is_dragging() -> bool:
	return _drag_active


## Get total number of selected vertices across all brushes.
func get_selection_count() -> int:
	var count := 0
	for indices in selected_vertices.values():
		count += indices.size()
	return count


## Has any vertices selected?
func has_selection() -> bool:
	return not selected_vertices.is_empty()


## Get world positions of all selected vertices (for gizmo rendering).
func get_selected_world_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	for brush_id in selected_vertices:
		var brush = _find_brush(brush_id)
		if not brush:
			continue
		var verts = get_brush_vertices(brush)
		var xform: Transform3D = brush.global_transform
		var indices: PackedInt32Array = selected_vertices[brush_id]
		for vi in indices:
			if vi >= 0 and vi < verts.size():
				positions.append(xform * verts[vi])
	return positions


## Get world positions of all vertices in selected brushes (for gizmo rendering).
func get_all_vertex_world_positions() -> Array:
	var result: Array = []  # Array of {pos: Vector3, selected: bool, hovered: bool}
	var brushes = _get_selected_brushes()
	for brush in brushes:
		if not brush:
			continue
		var brush_id = brush.brush_id if brush.get("brush_id") else ""
		var verts = get_brush_vertices(brush)
		var xform: Transform3D = brush.global_transform
		var sel_indices: PackedInt32Array = selected_vertices.get(brush_id, PackedInt32Array())
		for i in range(verts.size()):
			var is_sel = sel_indices.has(i)
			var is_hov = brush_id == _hovered_brush_id and i == _hovered_vertex_idx
			result.append({"pos": xform * verts[i], "selected": is_sel, "hovered": is_hov})
	return result


# ---------------------------------------------------------------------------
# Edge operations
# ---------------------------------------------------------------------------


## Extract unique edges from a brush's faces as pairs of vertex indices.
## Returns Array of [idx_a, idx_b] where indices refer to get_brush_vertices() order.
func get_brush_edges(brush: Node3D) -> Array:
	var verts := get_brush_vertices(brush)
	if verts.is_empty():
		return []
	# Build position→index lookup
	var pos_to_idx: Dictionary = {}
	for i in range(verts.size()):
		pos_to_idx[_vertex_key(verts[i])] = i
	var seen_edges: Dictionary = {}
	var edges: Array = []
	if not brush or not brush.get("faces"):
		return edges
	var faces: Array = brush.faces
	for face in faces:
		if face == null:
			continue
		var fv: PackedVector3Array = face.local_verts
		var n := fv.size()
		if n < 2:
			continue
		for j in range(n):
			var ka: String = _vertex_key(fv[j])
			var kb: String = _vertex_key(fv[(j + 1) % n])
			var ia: int = pos_to_idx.get(ka, -1)
			var ib: int = pos_to_idx.get(kb, -1)
			if ia < 0 or ib < 0:
				continue
			# Canonical order for dedup
			var edge_key: String
			if ka < kb:
				edge_key = ka + "|" + kb
			else:
				edge_key = kb + "|" + ka
			if not seen_edges.has(edge_key):
				seen_edges[edge_key] = true
				edges.append([mini(ia, ib), maxi(ia, ib)])
	return edges


## Find the closest edge to screen position.
## Returns {brush_id, edge: [a, b], world_midpoint, distance} or empty dict.
func pick_edge(camera: Camera3D, screen_pos: Vector2, threshold_px: float = 15.0) -> Dictionary:
	if not camera or not root:
		return {}
	var best_dist := threshold_px
	var best := {}
	var brushes = _get_selected_brushes()
	for brush in brushes:
		if not brush:
			continue
		var verts := get_brush_vertices(brush)
		var brush_id: String = brush.brush_id if brush.get("brush_id") else ""
		var xform: Transform3D = brush.global_transform
		var edges := get_brush_edges(brush)
		for edge in edges:
			var wa: Vector3 = xform * verts[edge[0]]
			var wb: Vector3 = xform * verts[edge[1]]
			if camera.is_position_behind(wa) and camera.is_position_behind(wb):
				continue
			var sa: Vector2 = camera.unproject_position(wa)
			var sb: Vector2 = camera.unproject_position(wb)
			var dist := _point_to_segment_dist_2d(screen_pos, sa, sb)
			if dist < best_dist:
				best_dist = dist
				best = {
					"brush_id": brush_id,
					"edge": edge,
					"world_midpoint": (wa + wb) * 0.5,
					"distance": dist,
				}
	return best


## Select an edge. Also selects both endpoint vertices for move compatibility.
func select_edge(brush_id: String, edge: Array, additive: bool = false) -> void:
	if not additive:
		selected_edges.clear()
		selected_vertices.clear()
	if not selected_edges.has(brush_id):
		selected_edges[brush_id] = []
	# Check if edge already selected
	var existing: Array = selected_edges[brush_id]
	var found := false
	if additive:
		for i in range(existing.size()):
			var e: Array = existing[i]
			if e[0] == edge[0] and e[1] == edge[1]:
				existing.remove_at(i)
				found = true
				break
	if not found:
		existing.append(edge)
	selected_edges[brush_id] = existing
	# Sync vertex selection from all selected edges
	_sync_vertices_from_edges()


## Clear edge selection and corresponding vertex selection.
func clear_edge_selection() -> void:
	selected_edges.clear()
	_hovered_edge = []


## Update hover state for an edge near the cursor.
func update_edge_hover(camera: Camera3D, screen_pos: Vector2) -> void:
	var pick := pick_edge(camera, screen_pos)
	if pick.is_empty() or pick.edge.size() < 2:
		_hovered_edge = []
	else:
		_hovered_edge = [pick.brush_id, pick.edge[0], pick.edge[1]]


## Split an edge by inserting a midpoint vertex. Returns true on success.
func split_edge(brush_id: String, edge: Array) -> bool:
	var brush = _find_brush(brush_id)
	if not brush or not brush.get("faces"):
		return false
	if edge.size() < 2:
		return false
	var verts := get_brush_vertices(brush)
	if edge[0] < 0 or edge[0] >= verts.size() or edge[1] < 0 or edge[1] >= verts.size():
		return false
	# Capture snapshot for undo
	_capture_face_snapshots_for([brush_id])
	var va: Vector3 = verts[edge[0]]
	var vb: Vector3 = verts[edge[1]]
	var midpoint: Vector3 = (va + vb) * 0.5
	var key_a: String = _vertex_key(va)
	var key_b: String = _vertex_key(vb)
	# Insert midpoint into every face containing this edge
	var modified := false
	var faces: Array = brush.faces
	for face in faces:
		if face == null:
			continue
		var fv: PackedVector3Array = face.local_verts
		var n := fv.size()
		if n < 2:
			continue
		# Find the edge in this face (consecutive vertices matching a→b or b→a)
		for j in range(n):
			var kj: String = _vertex_key(fv[j])
			var kn: String = _vertex_key(fv[(j + 1) % n])
			if (kj == key_a and kn == key_b) or (kj == key_b and kn == key_a):
				# Insert midpoint between j and (j+1)%n
				var new_verts := PackedVector3Array()
				for k in range(n):
					new_verts.append(fv[k])
					if k == j:
						new_verts.append(midpoint)
				face.local_verts = new_verts
				face.ensure_geometry()
				modified = true
				break
	if not modified:
		_pre_drag_faces.clear()
		return false
	# Splitting an edge on a convex hull always stays convex — the midpoint lies
	# exactly on the surface.  Skip the heavy convexity check here; the standard
	# validate_convexity (0.01 tolerance) is used for vertex moves where the user
	# can break convexity.  For splits we only need to verify face integrity.
	if brush.has_method("rebuild_preview"):
		brush.rebuild_preview()
	return true


## Merge selected vertices in a brush to their centroid. Returns true on success.
func merge_vertices(brush_id: String, vert_indices: PackedInt32Array) -> bool:
	if vert_indices.size() < 2:
		return false
	var brush = _find_brush(brush_id)
	if not brush or not brush.get("faces"):
		return false
	var verts := get_brush_vertices(brush)
	# Compute centroid
	var centroid := Vector3.ZERO
	var merge_keys: Dictionary = {}
	var valid_count := 0
	for vi in vert_indices:
		if vi < 0 or vi >= verts.size():
			continue
		centroid += verts[vi]
		merge_keys[_vertex_key(verts[vi])] = true
		valid_count += 1
	if valid_count == 0:
		return false
	centroid /= float(valid_count)
	# Capture snapshot
	_capture_face_snapshots_for([brush_id])
	# Replace all merge-target vertices with centroid in all faces
	var faces: Array = brush.faces
	var centroid_key: String = _vertex_key(centroid)
	var faces_to_remove: Array = []
	for fi in range(faces.size()):
		var face = faces[fi]
		if face == null:
			continue
		var new_verts := PackedVector3Array()
		var seen_keys: Dictionary = {}
		for v in face.local_verts:
			var k: String = _vertex_key(v)
			var out_v: Vector3
			if merge_keys.has(k):
				out_v = centroid
				k = centroid_key
			else:
				out_v = v
			# Deduplicate consecutive vertices
			if not seen_keys.has(k):
				seen_keys[k] = true
				new_verts.append(out_v)
		if new_verts.size() < 3:
			faces_to_remove.append(fi)
		else:
			face.local_verts = new_verts
			face.ensure_geometry()
	# Remove degenerate faces (reverse order)
	for i in range(faces_to_remove.size() - 1, -1, -1):
		faces.remove_at(faces_to_remove[i])
	# Validate
	if not validate_convexity(brush):
		_restore_face_snapshots()
		return false
	if brush.has_method("rebuild_preview"):
		brush.rebuild_preview()
	return true


## Get edge world positions for all selected brushes (for overlay rendering).
func get_all_edge_world_positions() -> Array:
	var result: Array = []  # Array of {a: Vector3, b: Vector3, selected: bool, hovered: bool}
	var brushes = _get_selected_brushes()
	for brush in brushes:
		if not brush:
			continue
		var brush_id: String = brush.brush_id if brush.get("brush_id") else ""
		var verts := get_brush_vertices(brush)
		var xform: Transform3D = brush.global_transform
		var edges := get_brush_edges(brush)
		var sel_edges: Array = selected_edges.get(brush_id, [])
		for edge in edges:
			var is_sel := false
			for se in sel_edges:
				if se[0] == edge[0] and se[1] == edge[1]:
					is_sel = true
					break
			var is_hov := false
			if (
				_hovered_edge.size() == 3
				and _hovered_edge[0] == brush_id
				and _hovered_edge[1] == edge[0]
				and _hovered_edge[2] == edge[1]
			):
				is_hov = true
			(
				result
				. append(
					{
						"a": xform * verts[edge[0]],
						"b": xform * verts[edge[1]],
						"selected": is_sel,
						"hovered": is_hov,
					}
				)
			)
	return result


## Get the single selected edge if exactly one is selected, else empty.
func get_single_selected_edge() -> Array:
	var count := 0
	var result: Array = []
	var result_brush := ""
	for brush_id in selected_edges:
		var edges: Array = selected_edges[brush_id]
		for e in edges:
			count += 1
			result = e
			result_brush = brush_id
	if count == 1:
		return [result_brush, result]
	return []


## Get the face snapshot for undo after split/merge.
func get_pre_op_snapshots() -> Dictionary:
	var snapshots = _pre_drag_faces.duplicate(true)
	_pre_drag_faces.clear()
	return snapshots


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


func _sync_vertices_from_edges() -> void:
	selected_vertices.clear()
	for brush_id in selected_edges:
		var indices := PackedInt32Array()
		for edge in selected_edges[brush_id]:
			if not indices.has(edge[0]):
				indices.append(edge[0])
			if not indices.has(edge[1]):
				indices.append(edge[1])
		if not indices.is_empty():
			selected_vertices[brush_id] = indices


func _capture_face_snapshots_for(brush_ids: Array) -> void:
	_pre_drag_faces.clear()
	for brush_id in brush_ids:
		var brush = _find_brush(brush_id)
		if not brush or not brush.get("faces"):
			continue
		var snapshots: Array = []
		for face in brush.faces:
			if face:
				snapshots.append(face.to_dict())
		_pre_drag_faces[brush_id] = snapshots


## Distance from point p to line segment (a, b) in 2D.
static func _point_to_segment_dist_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf(ab.dot(p - a) / len_sq, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_to(proj)


func _vertex_key(v: Vector3) -> String:
	# Round to avoid floating point uniqueness issues
	return (
		"%d,%d,%d"
		% [snappedi(int(v.x * 1000), 1), snappedi(int(v.y * 1000), 1), snappedi(int(v.z * 1000), 1)]
	)


func _find_brush(brush_id: String) -> Node3D:
	if not root:
		return null
	if (
		root.get("brush_system")
		and root.brush_system
		and root.brush_system.has_method("find_brush_by_id")
	):
		return root.brush_system.find_brush_by_id(brush_id)
	# Fallback: search selection list
	for b in _selection_brushes:
		if b and b.get("brush_id") == brush_id:
			return b
	return null


func _get_selected_brushes() -> Array:
	# Vertex mode operates on whatever brushes are editor-selected.
	# The plugin passes the selection list; fall back to empty.
	if not root:
		return []
	return _selection_brushes


## Set by plugin when selection changes so vertex system knows which brushes to show vertices for.
var _selection_brushes: Array = []


func set_selection(brushes: Array) -> void:
	_selection_brushes = brushes


func _capture_face_snapshots() -> void:
	_pre_drag_faces.clear()
	for brush_id in selected_vertices:
		var brush = _find_brush(brush_id)
		if not brush or not brush.get("faces"):
			continue
		var snapshots: Array = []
		for face in brush.faces:
			if face:
				snapshots.append(face.to_dict())
		_pre_drag_faces[brush_id] = snapshots


func _restore_face_snapshots() -> void:
	for brush_id in _pre_drag_faces:
		var brush = _find_brush(brush_id)
		if not brush or not brush.has_method("apply_serialized_faces"):
			continue
		brush.apply_serialized_faces(_pre_drag_faces[brush_id])
