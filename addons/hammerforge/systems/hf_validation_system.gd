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
