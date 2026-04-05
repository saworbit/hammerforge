@tool
extends RefCounted
class_name HFValidationSystem

const DraftBrush = preload("../brush_instance.gd")
const HFPaintGrid = preload("../paint/hf_paint_grid.gd")

var root: Node3D


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

	_check_overlapping_subtracts(brush_nodes, issues)
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
		issues.append({
			"type": "open_edge",
			"severity": 1,
			"message": "Brush '%s' has %d open edge(s) — geometry is not watertight" % [brush.name, open_count],
			"node": brush
		})
	if non_manifold_count > 0:
		issues.append({
			"type": "non_manifold",
			"severity": 2,
			"message": "Brush '%s' has %d non-manifold edge(s) — may cause bake artifacts" % [brush.name, non_manifold_count],
			"node": brush
		})


## Create a canonical edge key from two vertices (order-independent, rounded to 0.001).
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
