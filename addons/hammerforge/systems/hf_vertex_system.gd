@tool
class_name HFVertexSystem
extends RefCounted

## Vertex editing system for HammerForge.
## Extracts vertices from brush faces, supports selection, movement with
## convexity validation, and undo/redo integration.

const FaceData = preload("res://addons/hammerforge/face_data.gd")

var root: Node3D  # LevelRoot
var selected_vertices: Dictionary = {}  # {brush_id: PackedInt32Array}
var _hovered_vertex_idx: int = -1
var _hovered_brush_id: String = ""
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
				root.emit_signal("user_message","Move rejected: would create non-convex brush", 1)
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
			if d > 0.01:  # Small tolerance
				return false
	return true


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


## Clear all vertex selection.
func clear_selection() -> void:
	selected_vertices.clear()
	_hovered_vertex_idx = -1
	_hovered_brush_id = ""


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
			var is_hov = (brush_id == _hovered_brush_id and i == _hovered_vertex_idx)
			result.append({
				"pos": xform * verts[i],
				"selected": is_sel,
				"hovered": is_hov
			})
	return result


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _vertex_key(v: Vector3) -> String:
	# Round to avoid floating point uniqueness issues
	return "%d,%d,%d" % [snappedi(int(v.x * 1000), 1), snappedi(int(v.y * 1000), 1), snappedi(int(v.z * 1000), 1)]


func _find_brush(brush_id: String) -> Node3D:
	if not root:
		return null
	if root.get("brush_system") and root.brush_system and root.brush_system.has_method("find_brush_by_id"):
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
