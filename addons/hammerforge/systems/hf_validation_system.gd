@tool
extends RefCounted
class_name HFValidationSystem

const DraftBrush = preload("../brush_instance.gd")
const HFPaintGrid = preload("../paint/hf_paint_grid.gd")

var root: Node3D

## Vertex welding tolerance — vertices closer than this are considered coincident.
## Increase for legacy .map imports with floating-point drift (e.g. 0.01–0.1).
var weld_tolerance: float = 0.001

## Maximum allowed distance a vertex may deviate from its face plane before
## the face is flagged as non-planar. Increase for imported geometry.
var planarity_tolerance: float = 0.01


func _init(level_root: Node3D) -> void:
	root = level_root


func check_missing_dependencies() -> Array:
	var warnings: Array = []
	if not root:
		return warnings
	# Material palette checks
	if root.material_manager:
		var materials: Array = root.material_manager.materials
		for i in range(materials.size()):
			var mat = materials[i]
			if mat == null:
				warnings.append("Material palette entry %d is null" % i)
				continue
			if mat.resource_path != "" and not ResourceLoader.exists(mat.resource_path):
				warnings.append("Material %d path missing: %s" % [i, mat.resource_path])
			if mat is ShaderMaterial:
				var shader_mat := mat as ShaderMaterial
				if shader_mat.shader == null:
					warnings.append("ShaderMaterial %d has no shader" % i)
	# Blend shader check for heightmaps
	var has_heightmap := false
	if root.paint_layers:
		for layer in root.paint_layers.layers:
			if layer and layer.has_heightmap():
				has_heightmap = true
				break
	if not has_heightmap and root.generated_heightmap_floors:
		has_heightmap = root.generated_heightmap_floors.get_child_count() > 0
	if has_heightmap:
		var blend_path := "res://addons/hammerforge/paint/hf_blend.gdshader"
		if not ResourceLoader.exists(blend_path):
			warnings.append("Missing blend shader: %s" % blend_path)
	# Face material bake without palette
	if root.bake_use_face_materials and root.material_manager:
		if root.material_manager.materials.is_empty():
			warnings.append("Face material bake enabled but material palette is empty")
	return warnings


func validate(auto_fix: bool = false) -> Dictionary:
	var issues: Array = []
	var fixed := 0
	if not root:
		return {"issues": issues, "fixed": fixed}

	# Dependencies
	for warning in check_missing_dependencies():
		issues.append("Dependency: %s" % str(warning))

	# Zero-size brushes
	var brush_nodes: Array = []
	if root.draft_brushes_node:
		brush_nodes.append_array(root.draft_brushes_node.get_children())
	if root.pending_node:
		brush_nodes.append_array(root.pending_node.get_children())
	if root.committed_node:
		brush_nodes.append_array(root.committed_node.get_children())
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var size = brush.size
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			issues.append("Zero-size brush: %s" % brush.name)
			if auto_fix:
				var next = Vector3(
					max(0.1, abs(size.x)), max(0.1, abs(size.y)), max(0.1, abs(size.z))
				)
				brush.size = next
				fixed += 1

	# Invalid face indices in selection
	var invalid_indices := 0
	var next_selection: Dictionary = {}
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		var indices: Array = root.face_selection.get(key, [])
		if not brush or not (brush is DraftBrush):
			invalid_indices += indices.size()
			continue
		var max_idx = (brush as DraftBrush).faces.size()
		var filtered: Array = []
		for idx in indices:
			var value = int(idx)
			if value >= 0 and value < max_idx:
				filtered.append(value)
			else:
				invalid_indices += 1
		if filtered.size() > 0:
			next_selection[key] = filtered
	if invalid_indices > 0:
		issues.append("Face selection contains %d invalid indices" % invalid_indices)
		if auto_fix:
			root.face_selection = next_selection
			root._apply_face_selection()
			fixed += invalid_indices

	# Face material indices out of palette bounds
	var palette_count = root.material_manager.materials.size() if root.material_manager else 0
	var invalid_face_mats := 0
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		for face in brush.faces:
			if face == null:
				continue
			var idx = int(face.material_idx)
			if idx >= palette_count and idx >= 0:
				invalid_face_mats += 1
				if auto_fix:
					face.material_idx = -1
	if invalid_face_mats > 0:
		issues.append("Faces reference missing materials: %d" % invalid_face_mats)
		if auto_fix:
			fixed += invalid_face_mats
			if root.brush_system:
				root.brush_system._refresh_brush_previews()

	# Paint layers without grid
	if root.paint_layers:
		var grid_template: HFPaintGrid = root.paint_layers.base_grid
		for layer in root.paint_layers.layers:
			if layer == null:
				continue
			if layer.grid == null:
				issues.append("Paint layer %s has no grid" % str(layer.layer_id))
				if auto_fix:
					if grid_template == null:
						grid_template = HFPaintGrid.new()
						root.paint_layers.base_grid = grid_template
					var grid = grid_template.duplicate() as HFPaintGrid
					if grid == null:
						grid = HFPaintGrid.new()
					grid.layer_y = root.grid_plane_origin.y
					layer.grid = grid
					fixed += 1

	return {"issues": issues, "fixed": fixed}


# ---------------------------------------------------------------------------
# Bake-specific issue detection
# ---------------------------------------------------------------------------


## Scan for issues that affect bake quality. Returns Array of Dictionaries:
## {type: String, severity: int (0=info,1=warn,2=error), message: String, node: Node3D or null}
func check_bake_issues() -> Array:
	var issues: Array = []
	if not root:
		return issues
	var brush_nodes: Array = []
	if root.draft_brushes_node:
		brush_nodes.append_array(root.draft_brushes_node.get_children())
	if root.committed_node:
		brush_nodes.append_array(root.committed_node.get_children())

	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		_check_degenerate_brush(brush, issues)
		_check_floating_subtract(brush, brush_nodes, issues)
		_check_non_manifold(brush, issues)
		_check_non_planar_faces(brush, issues)

	_check_overlapping_subtracts(brush_nodes, issues)
	_check_micro_gaps(brush_nodes, issues)
	return issues


func _check_degenerate_brush(brush: DraftBrush, issues: Array) -> void:
	var size = brush.size
	var min_dim := min(size.x, min(size.y, size.z))
	if min_dim < 0.01 and (size.x > 0.0 or size.y > 0.0 or size.z > 0.0):
		issues.append(
			{
				"type": "degenerate",
				"severity": 2,
				"message": "Near-zero thickness brush '%s' (%.3f)" % [brush.name, min_dim],
				"node": brush
			}
		)
	var max_dim := max(size.x, max(size.y, size.z))
	if max_dim > 2048.0:
		issues.append(
			{
				"type": "oversized",
				"severity": 1,
				"message": "Very large brush '%s' (%.0f units)" % [brush.name, max_dim],
				"node": brush
			}
		)


func _check_floating_subtract(brush: DraftBrush, all_brushes: Array, issues: Array) -> void:
	if brush.operation != CSGShape3D.OPERATION_SUBTRACTION:
		return
	var half = brush.size * 0.5
	var sub_aabb = AABB(brush.global_position - half, brush.size)
	var intersects_any := false
	for other in all_brushes:
		if other == brush or not (other is DraftBrush):
			continue
		var ob := other as DraftBrush
		if ob.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if root.is_entity_node(ob):
			continue
		var other_half = ob.size * 0.5
		var other_aabb = AABB(ob.global_position - other_half, ob.size)
		if sub_aabb.intersects(other_aabb):
			intersects_any = true
			break
	if not intersects_any:
		issues.append(
			{
				"type": "floating_subtract",
				"severity": 1,
				"message": "Subtraction '%s' doesn't intersect any additive brush" % brush.name,
				"node": brush
			}
		)


func _check_overlapping_subtracts(all_brushes: Array, issues: Array) -> void:
	var subtracts: Array = []
	for node in all_brushes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if brush.operation == CSGShape3D.OPERATION_SUBTRACTION and not root.is_entity_node(brush):
			subtracts.append(brush)
	for i in range(subtracts.size()):
		var a: DraftBrush = subtracts[i]
		var a_half = a.size * 0.5
		var a_aabb = AABB(a.global_position - a_half, a.size)
		for j in range(i + 1, subtracts.size()):
			var b: DraftBrush = subtracts[j]
			var b_half = b.size * 0.5
			var b_aabb = AABB(b.global_position - b_half, b.size)
			if a_aabb.intersects(b_aabb):
				issues.append(
					{
						"type": "overlapping_subtract",
						"severity": 1,
						"message": "Overlapping subtractions: '%s' and '%s'" % [a.name, b.name],
						"node": a
					}
				)


## Check for non-manifold and open-edge geometry by analyzing the edge adjacency
## of a brush's faces. An edge shared by exactly 2 faces is manifold; 1 = open edge;
## 3+ = non-manifold edge.
func _check_non_manifold(brush: DraftBrush, issues: Array) -> void:
	if brush.faces.is_empty():
		return
	# Build edge→face count map. Edge key = sorted pair of rounded vertex positions.
	var edge_counts: Dictionary = {}  # String -> int
	for face_idx in range(brush.faces.size()):
		var face = brush.faces[face_idx]
		if not face or face.local_verts.size() < 3:
			continue
		var verts: PackedVector3Array = face.local_verts
		for i in range(verts.size()):
			var a: Vector3 = verts[i]
			var b: Vector3 = verts[(i + 1) % verts.size()]
			var key: String = _edge_key(a, b)
			edge_counts[key] = edge_counts.get(key, 0) + 1
	var open_count := 0
	var non_manifold_count := 0
	for key: String in edge_counts:
		var count: int = edge_counts[key]
		if count == 1:
			open_count += 1
		elif count > 2:
			non_manifold_count += 1
	if open_count > 0:
		issues.append(
			{
				"type": "open_edge",
				"severity": 1,
				"message":
				(
					"Brush '%s' has %d open edge(s) — geometry is not watertight"
					% [brush.name, open_count]
				),
				"node": brush
			}
		)
	if non_manifold_count > 0:
		issues.append(
			{
				"type": "non_manifold",
				"severity": 2,
				"message":
				(
					"Brush '%s' has %d non-manifold edge(s) — may cause bake artifacts"
					% [brush.name, non_manifold_count]
				),
				"node": brush
			}
		)


## Create a canonical edge key from two vertices (order-independent, rounded to 0.001).
## This tolerance is intentionally fixed — it must NOT vary with weld_tolerance,
## because non-manifold/open-edge detection depends on stable topology hashing.
func _edge_key(a: Vector3, b: Vector3) -> String:
	var ax := snapped(a.x, 0.001)
	var ay := snapped(a.y, 0.001)
	var az := snapped(a.z, 0.001)
	var bx := snapped(b.x, 0.001)
	var by := snapped(b.y, 0.001)
	var bz := snapped(b.z, 0.001)
	# Sort so edge (A,B) == edge (B,A)
	if ax < bx or (ax == bx and ay < by) or (ax == bx and ay == by and az < bz):
		return "%s,%s,%s-%s,%s,%s" % [ax, ay, az, bx, by, bz]
	return "%s,%s,%s-%s,%s,%s" % [bx, by, bz, ax, ay, az]


# ---------------------------------------------------------------------------
# Non-planar face detection
# ---------------------------------------------------------------------------


## Check whether any face has vertices that deviate from the face plane beyond
## planarity_tolerance.  Returns issues appended to the provided array.
func _check_non_planar_faces(brush: DraftBrush, issues: Array) -> void:
	for face_idx in range(brush.faces.size()):
		var face = brush.faces[face_idx]
		if not face or face.local_verts.size() < 4:
			continue  # triangles are always planar
		var verts: PackedVector3Array = face.local_verts
		var normal: Vector3 = face.normal
		if normal.length_squared() < 0.0001:
			# Compute from first 3 verts
			normal = (verts[2] - verts[0]).cross(verts[1] - verts[0]).normalized()
		if normal.length_squared() < 0.0001:
			continue
		var plane_d: float = normal.dot(verts[0])
		var max_deviation := 0.0
		for i in range(1, verts.size()):
			var dev: float = absf(normal.dot(verts[i]) - plane_d)
			if dev > max_deviation:
				max_deviation = dev
		if max_deviation > planarity_tolerance:
			issues.append(
				{
					"type": "non_planar",
					"severity": 1,
					"message":
					(
						"Brush '%s' face %d has %.4f unit vertex drift (tolerance %.4f)"
						% [brush.name, face_idx, max_deviation, planarity_tolerance]
					),
					"node": brush
				}
			)


# ---------------------------------------------------------------------------
# Micro-gap detection (near-coincident but not welded vertices between brushes)
# ---------------------------------------------------------------------------


## Detect vertices across different brushes that are within weld_tolerance of each
## other but not exactly coincident.  These cause micro-gaps after bake.
## Uses spatial hashing with 27-cell neighbor lookup so pairs straddling a bucket
## boundary are never missed.
func _check_micro_gaps(all_brushes: Array, issues: Array) -> void:
	var tol: float = weld_tolerance
	# Collect all world-space vertices into spatial hash
	var entries: Array = []  # Array of {brush: DraftBrush, pos: Vector3}
	var cells: Dictionary = {}  # cell_key -> Array[int] (indices into entries)
	for node in all_brushes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		for face in brush.faces:
			if not face or face.local_verts.size() < 3:
				continue
			for vi in range(face.local_verts.size()):
				var world_v: Vector3 = brush.global_transform * face.local_verts[vi]
				var idx: int = entries.size()
				entries.append({"brush": brush, "pos": world_v})
				var key: String = _snap_key(world_v, tol)
				if not cells.has(key):
					cells[key] = []
				(cells[key] as Array).append(idx)
	# For each vertex, search own cell + 26 neighbors for cross-brush near-pairs
	var flagged_pairs: Dictionary = {}  # avoid duplicate warnings
	for i in range(entries.size()):
		var pos_i: Vector3 = entries[i]["pos"]
		for cell_key: String in _cell_keys(pos_i, tol):
			for j: int in cells.get(cell_key, []):
				if j <= i:
					continue  # ordered pair dedup
				if entries[i]["brush"] == entries[j]["brush"]:
					continue
				var dist: float = pos_i.distance_to(entries[j]["pos"])
				if dist > 0.0 and dist <= tol:
					var pair_key: String = _brush_pair_key(entries[i]["brush"], entries[j]["brush"])
					flagged_pairs[pair_key] = flagged_pairs.get(pair_key, 0) + 1
	for pair_key: String in flagged_pairs:
		var count: int = flagged_pairs[pair_key]
		issues.append(
			{
				"type": "micro_gap",
				"severity": 1,
				"message":
				(
					"Micro-gap: %d near-coincident vertex pair(s) between %s (weld tolerance %.4f)"
					% [count, pair_key, weld_tolerance]
				),
				"node": null
			}
		)


func _brush_pair_key(a: DraftBrush, b: DraftBrush) -> String:
	var na: String = a.name if a.name <= b.name else b.name
	var nb: String = b.name if a.name <= b.name else a.name
	return "'%s' and '%s'" % [na, nb]


# ---------------------------------------------------------------------------
# Auto-fix: weld near-coincident vertices within a brush
# ---------------------------------------------------------------------------


## Snap vertices that are within weld_tolerance of each other to a shared position.
## Operates on face local_verts in local space.  Uses BFS over a spatial hash with
## 27-cell neighbor lookup so pairs straddling a bucket boundary are never missed.
## Returns number of vertices welded.
func weld_brush_vertices(brush: DraftBrush) -> int:
	if not brush or brush.faces.is_empty():
		return 0
	var tol: float = weld_tolerance
	# Collect every vertex reference into a flat list + spatial hash
	var entries: Array = []  # Array of {fi: int, vi: int, pos: Vector3}
	var cells: Dictionary = {}  # cell_key -> Array[int]
	for fi in range(brush.faces.size()):
		var face = brush.faces[fi]
		if not face:
			continue
		for vi in range(face.local_verts.size()):
			var idx: int = entries.size()
			var pos: Vector3 = face.local_verts[vi]
			entries.append({"fi": fi, "vi": vi, "pos": pos})
			var key: String = _snap_key(pos, tol)
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(idx)
	# BFS grouping: vertices within tolerance are transitively merged
	var group_of: PackedInt32Array = PackedInt32Array()
	group_of.resize(entries.size())
	group_of.fill(-1)
	var groups: Array = []  # Array of Array[int]
	for seed_idx in range(entries.size()):
		if group_of[seed_idx] >= 0:
			continue
		var gid: int = groups.size()
		var members: Array = [seed_idx]
		group_of[seed_idx] = gid
		var queue: Array = [seed_idx]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var cur_pos: Vector3 = entries[cur]["pos"]
			for cell_key: String in _cell_keys(cur_pos, tol):
				for neighbor_idx: int in cells.get(cell_key, []):
					if group_of[neighbor_idx] >= 0:
						continue
					if cur_pos.distance_to(entries[neighbor_idx]["pos"]) <= tol:
						group_of[neighbor_idx] = gid
						members.append(neighbor_idx)
						queue.append(neighbor_idx)
		groups.append(members)
	# Compute group averages and write back
	var welded := 0
	var dirty_faces: Dictionary = {}  # fi -> true
	for members: Array in groups:
		if members.size() < 2:
			continue
		var avg := Vector3.ZERO
		for idx: int in members:
			avg += entries[idx]["pos"]
		avg /= float(members.size())
		for idx: int in members:
			var fi: int = entries[idx]["fi"]
			var vi: int = entries[idx]["vi"]
			var face = brush.faces[fi]
			var verts: PackedVector3Array = face.local_verts
			if verts[vi].distance_to(avg) > 0.0:
				verts[vi] = avg
				face.local_verts = verts
				welded += 1
				dirty_faces[fi] = true
	# Refresh derived state (normal, bounds) on every modified face
	for fi: int in dirty_faces:
		brush.faces[fi].ensure_geometry()
	return welded


# ---------------------------------------------------------------------------
# Auto-fix: project drifting vertices back onto their face plane
# ---------------------------------------------------------------------------


## For each face with >3 vertices, compute the best-fit plane from the first 3
## vertices and project any drifting vertices back onto it.  Returns number of
## vertices corrected.
func fix_non_planar_faces(brush: DraftBrush) -> int:
	if not brush or brush.faces.is_empty():
		return 0
	var fixed := 0
	for face in brush.faces:
		if not face or face.local_verts.size() < 4:
			continue
		var verts: PackedVector3Array = face.local_verts
		var normal: Vector3 = (verts[2] - verts[0]).cross(verts[1] - verts[0]).normalized()
		if normal.length_squared() < 0.0001:
			continue
		var plane_d: float = normal.dot(verts[0])
		for i in range(1, verts.size()):
			var dev: float = normal.dot(verts[i]) - plane_d
			if absf(dev) > planarity_tolerance:
				verts[i] = verts[i] - normal * dev
				fixed += 1
		face.local_verts = verts
		if fixed > 0:
			face.ensure_geometry()
	return fixed


func _snap_key(v: Vector3, tol: float) -> String:
	return "%s,%s,%s" % [snapped(v.x, tol), snapped(v.y, tol), snapped(v.z, tol)]


## Return all 27 cell keys (self + 26 neighbors) for a spatial hash lookup.
## Guarantees that any point within `cell_size` distance shares at least one cell.
func _cell_keys(v: Vector3, cell_size: float) -> Array:
	var cx: float = snapped(v.x, cell_size)
	var cy: float = snapped(v.y, cell_size)
	var cz: float = snapped(v.z, cell_size)
	var keys: Array = []
	for dx in [-cell_size, 0.0, cell_size]:
		for dy in [-cell_size, 0.0, cell_size]:
			for dz in [-cell_size, 0.0, cell_size]:
				keys.append("%s,%s,%s" % [cx + dx, cy + dy, cz + dz])
	return keys
