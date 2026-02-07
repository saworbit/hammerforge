@tool
extends RefCounted
class_name HFBrushSystem

const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const FaceSelector = preload("../face_selector.gd")
const FaceData = preload("../face_data.gd")

var root: Node3D


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Brush CRUD
# ---------------------------------------------------------------------------


func _create_brush(shape: int, size: Vector3, operation: int, sides: int) -> DraftBrush:
	var brush = DraftBrush.new()
	brush.shape = shape
	brush.size = size
	brush.operation = operation
	brush.sides = sides
	return brush


func place_brush(
	mouse_pos: Vector2,
	operation: int,
	size: Vector3,
	camera: Camera3D = null,
	shape: int = 0,  # BrushShape.BOX
	sides: int = 4
) -> bool:
	if not root.draft_brushes_node:
		return false

	var active_camera = camera if camera else root.get_viewport().get_camera_3d()
	if not active_camera:
		return false

	var hit = root._raycast(active_camera, mouse_pos)
	if not hit:
		return false

	var snapped = root._snap_point(hit.position)
	var brush = _create_brush(shape, size, operation, sides)
	brush.global_position = snapped + Vector3(0, size.y * 0.5, 0)
	if operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node:
		_add_pending_cut(brush)
	else:
		_add_brush_to_draft(brush)
	root.brush_manager.add_brush(brush)
	root._record_last_brush(brush.global_position)
	return true


func create_brush_from_info(info: Dictionary) -> Node:
	if info.is_empty():
		return null
	var shape = info.get("shape", root.BrushShape.BOX)
	var size = info.get("size", root.drag_size_default)
	var sides = int(info.get("sides", 4))
	var operation = info.get("operation", CSGShape3D.OPERATION_UNION)
	var committed = bool(info.get("committed", false))
	var brush = _create_brush(shape, size, operation, sides)
	if not brush:
		return null
	var pending = bool(info.get("pending", false))
	if committed:
		if root.committed_node:
			root.committed_node.add_child(brush)
		brush.visible = false
		brush.operation = CSGShape3D.OPERATION_SUBTRACTION
		brush.set_meta("committed_cut", true)
		brush.set_meta("pending_subtract", false)
		root._assign_owner(brush)
	elif operation == CSGShape3D.OPERATION_SUBTRACTION and pending:
		_add_pending_cut(brush)
	else:
		_add_brush_to_draft(brush)
	if info.has("transform"):
		brush.global_transform = info["transform"]
	else:
		brush.global_position = info.get("center", Vector3.ZERO)
	if (
		info.has("material")
		and not committed
		and not (operation == CSGShape3D.OPERATION_SUBTRACTION and pending)
	):
		brush.material_override = info["material"]
	if root.brush_manager and not committed:
		root.brush_manager.add_brush(brush)
	root._record_last_brush(brush.global_position)
	var brush_id = info.get("brush_id", _next_brush_id())
	brush.brush_id = str(brush_id)
	brush.set_meta("brush_id", brush_id)
	_register_brush_id(str(brush_id))
	if info.has("faces"):
		brush.apply_serialized_faces(info.get("faces", []))
	return brush


func delete_brush(brush: Node, free: bool = true) -> void:
	if not brush:
		return
	if brush is DraftBrush:
		var key = _face_key(brush as DraftBrush)
		if root.face_selection.has(key):
			root.face_selection.erase(key)
			_apply_face_selection()
	if root.brush_manager:
		root.brush_manager.remove_brush(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	if free:
		brush.queue_free()


func delete_brush_by_id(brush_id: String) -> void:
	if brush_id == "":
		return
	var brush = _find_brush_by_id(brush_id)
	if brush:
		delete_brush(brush)


func duplicate_brush(brush: Node) -> Node:
	if not brush:
		return null
	var offset = Vector3(root.grid_snap if root.grid_snap > 0.0 else 1.0, 0.0, 0.0)
	var info = build_duplicate_info(brush, offset)
	return create_brush_from_info(info)


func restore_brush(brush: Node, parent: Node, owner: Node, index: int) -> void:
	if not brush or not parent:
		return
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	parent.add_child(brush)
	if index >= 0 and index < parent.get_child_count():
		parent.move_child(brush, index)
	if owner:
		brush.owner = owner
	if root.brush_manager and brush is Node3D:
		root.brush_manager.add_brush(brush)


# ---------------------------------------------------------------------------
# Brush finding / info
# ---------------------------------------------------------------------------


func _find_brush_by_id(brush_id: String) -> Node:
	for node in root._iter_pick_nodes():
		if node and node is DraftBrush:
			if node.has_meta("brush_id") and str(node.get_meta("brush_id")) == brush_id:
				return node
			if str((node as DraftBrush).brush_id) == brush_id:
				return node
	return null


func find_brush_by_id(brush_id: String) -> Node:
	return _find_brush_by_id(brush_id)


func get_brush_info_from_node(brush: Node) -> Dictionary:
	if not brush or not (brush is DraftBrush):
		return {}
	var draft := brush as DraftBrush
	var info: Dictionary = {}
	info["shape"] = draft.shape
	info["size"] = draft.size
	if _shape_uses_sides(draft.shape):
		info["sides"] = draft.sides
	var pending = (
		draft.get_parent() == root.pending_node or bool(draft.get_meta("pending_subtract", false))
	)
	var committed = (
		draft.get_parent() == root.committed_node or bool(draft.get_meta("committed_cut", false))
	)
	if committed:
		pending = false
	var is_subtract = _is_subtract_brush(draft) or committed
	info["operation"] = (
		CSGShape3D.OPERATION_SUBTRACTION if (pending or is_subtract) else draft.operation
	)
	info["pending"] = pending
	if committed:
		info["committed"] = true
	info["transform"] = draft.global_transform
	if draft.material_override:
		info["material"] = draft.material_override
	if draft.faces.size() > 0:
		info["faces"] = draft.serialize_faces()
	return info


func build_duplicate_info(brush: Node, offset: Vector3) -> Dictionary:
	var info = get_brush_info_from_node(brush)
	if info.is_empty():
		return {}
	info["brush_id"] = _next_brush_id()
	if info.has("transform"):
		var transform: Transform3D = info["transform"]
		transform.origin += offset
		info["transform"] = transform
	else:
		info["center"] = info.get("center", Vector3.ZERO) + offset
	return info


func is_brush_node(node: Node) -> bool:
	if not node or not (node is DraftBrush):
		return false
	if root._is_entity_node(node):
		return false
	if node == root.pending_node:
		return false
	var parent = node.get_parent()
	if parent == root.pending_node:
		return true
	return parent == root.draft_brushes_node


func _is_subtract_brush(node: Node) -> bool:
	return node is DraftBrush and node.operation == CSGShape3D.OPERATION_SUBTRACTION


func get_live_brush_count() -> int:
	var count = 0
	for node in root._iter_pick_nodes():
		if node and node is DraftBrush:
			count += 1
	return count


# ---------------------------------------------------------------------------
# ID management
# ---------------------------------------------------------------------------


func _next_brush_id() -> String:
	root._brush_id_counter += 1
	return "%s_%s" % [str(Time.get_ticks_usec()), str(root._brush_id_counter)]


func _register_brush_id(brush_id: String) -> void:
	if brush_id == "":
		return
	var parts = brush_id.split("_")
	if parts.size() == 0:
		return
	var tail = parts[parts.size() - 1]
	if not tail.is_valid_int():
		return
	var value = int(tail)
	if value > root._brush_id_counter:
		root._brush_id_counter = value


func _shape_uses_sides(shape: int) -> bool:
	return (
		shape == root.BrushShape.PYRAMID
		or shape == root.BrushShape.PRISM_TRI
		or shape == root.BrushShape.PRISM_PENT
	)


# ---------------------------------------------------------------------------
# Pending cuts / committed cuts
# ---------------------------------------------------------------------------


func _add_brush_to_draft(brush: DraftBrush) -> void:
	if not root.draft_brushes_node:
		return
	root.draft_brushes_node.add_child(brush)
	root._assign_owner(brush)


func _add_pending_cut(brush: DraftBrush) -> void:
	if not root.pending_node:
		return
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	_apply_brush_material(brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
	brush.set_meta("pending_subtract", true)
	root.pending_node.add_child(brush)
	root._assign_owner(brush)


func apply_pending_cuts() -> void:
	if not root.pending_node or not root.draft_brushes_node:
		return
	var pending_count = root.pending_node.get_child_count()
	for child in root.pending_node.get_children():
		if child is DraftBrush:
			root.pending_node.remove_child(child)
			root.draft_brushes_node.add_child(child)
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
			_apply_brush_material(
				child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true)
			)
			child.set_meta("pending_subtract", false)
			root._assign_owner(child)
	root._log("Applied pending cuts (%s)" % pending_count)


func clear_pending_cuts() -> void:
	if not root.pending_node:
		return
	var cleared = root.pending_node.get_child_count()
	for child in root.pending_node.get_children():
		if child is DraftBrush:
			child.queue_free()
	if cleared > 0:
		root._log("Cleared pending cuts (%s)" % cleared)


func commit_cuts() -> void:
	root._log("Commit cuts (freeze=%s)" % root.commit_freeze)
	apply_pending_cuts()
	await root.bake(false, true)
	_clear_applied_cuts()


func _clear_applied_cuts() -> void:
	if not root.draft_brushes_node:
		return
	var targets: Array = root.draft_brushes_node.get_children()
	for child in targets:
		if child is DraftBrush and _is_subtract_brush(child):
			if root.commit_freeze:
				_stash_committed_cut(child)
			else:
				if root.brush_manager:
					root.brush_manager.remove_brush(child)
				child.call_deferred("queue_free")


func _stash_committed_cut(brush: DraftBrush) -> void:
	if not root.committed_node:
		return
	if root.brush_manager:
		root.brush_manager.remove_brush(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	root.committed_node.add_child(brush)
	brush.visible = false
	brush.set_meta("committed_cut", true)
	root._assign_owner(brush)


func restore_committed_cuts() -> void:
	if not root.committed_node or not root.draft_brushes_node:
		return
	var restored = 0
	for child in root.committed_node.get_children():
		if child is DraftBrush:
			root.committed_node.remove_child(child)
			root.draft_brushes_node.add_child(child)
			child.visible = true
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
			_apply_brush_material(
				child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true)
			)
			child.set_meta("committed_cut", false)
			root._assign_owner(child)
			if root.brush_manager:
				root.brush_manager.add_brush(child)
			restored += 1
	if root.draft_brushes_node:
		root.draft_brushes_node.visible = true
	if root.pending_node:
		root.pending_node.visible = true
	if restored > 0:
		root._log("Restored committed cuts (%s)" % restored)


func clear_brushes() -> void:
	clear_face_selection()
	if root.brush_manager:
		root.brush_manager.clear_brushes()
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if child is DraftBrush:
				child.queue_free()
	_clear_generated()
	_clear_preview()
	clear_pending_cuts()
	_clear_committed_cuts()
	if root.baked_container:
		root.baked_container.queue_free()
		root.baked_container = null


func _clear_generated() -> void:
	if root.generated_floors:
		for child in root.generated_floors.get_children():
			if child is DraftBrush:
				child.queue_free()
	if root.generated_walls:
		for child in root.generated_walls.get_children():
			if child is DraftBrush:
				child.queue_free()


func _clear_committed_cuts() -> void:
	if not root.committed_node:
		return
	for child in root.committed_node.get_children():
		if child is DraftBrush:
			child.queue_free()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------


func _make_brush_material(operation: int, solid: bool = false, unshaded: bool = false) -> Material:
	var mat = StandardMaterial3D.new()
	if operation == CSGShape3D.OPERATION_SUBTRACTION:
		var alpha = 0.85 if solid else 0.35
		mat.albedo_color = Color(1.0, 0.2, 0.2, alpha)
		mat.emission = Color(1.0, 0.2, 0.2)
		mat.emission_energy = 0.6 if solid else 0.2
		if unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	return mat


func _apply_brush_material(brush: Node, mat: Material) -> void:
	if not brush or not mat:
		return
	if brush is DraftBrush:
		(brush as DraftBrush).set_editor_material(mat)
		return
	brush.set("material", mat)
	brush.set("material_override", mat)


func apply_material_to_brush(brush: Node, mat: Material) -> void:
	if not brush:
		return
	if brush is DraftBrush:
		(brush as DraftBrush).material_override = mat
		return
	brush.set("material_override", mat)
	brush.set("material", mat)


func _refresh_brush_previews() -> void:
	for node in root._iter_pick_nodes():
		if node is DraftBrush:
			node.rebuild_preview()


func rebuild_brush_preview(brush: DraftBrush) -> void:
	if brush:
		brush.rebuild_preview()


# ---------------------------------------------------------------------------
# Preview brush
# ---------------------------------------------------------------------------


func _clear_preview() -> void:
	if root.preview_brush and root.preview_brush.is_inside_tree():
		root.preview_brush.queue_free()
	root.preview_brush = null


# ---------------------------------------------------------------------------
# Picking
# ---------------------------------------------------------------------------


func pick_brush(camera: Camera3D, mouse_pos: Vector2, include_entities: bool = true) -> Node:
	if not root.draft_brushes_node or not camera:
		return null
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos).normalized()
	var closest = null
	var best_t = INF
	var nodes = root._iter_pick_nodes()
	for child in nodes:
		if not (child is DraftBrush) or not is_brush_node(child):
			continue
		var mesh_inst: MeshInstance3D = child.mesh_instance
		if not mesh_inst:
			continue
		var inv = mesh_inst.global_transform.affine_inverse()
		var local_origin = inv * ray_origin
		var local_dir = (inv.basis * ray_dir).normalized()
		var aabb = mesh_inst.get_aabb()
		var t = root._ray_intersect_aabb(local_origin, local_dir, aabb)
		if t >= 0.0 and t < best_t:
			best_t = t
			closest = child
	if closest or not include_entities:
		return closest
	var closest_entity: Node = null
	var best_entity_t = INF
	for child in nodes:
		if not (child is Node3D) or not root.is_entity_node(child):
			continue
		var t_entity = root._entity_pick_distance(child as Node3D, ray_origin, ray_dir)
		if t_entity >= 0.0 and t_entity < best_entity_t:
			best_entity_t = t_entity
			closest_entity = child
	return closest_entity


func update_hover(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not root.hover_highlight or not camera:
		return
	var brush = pick_brush(camera, mouse_pos, false)
	if brush and brush is DraftBrush:
		var mesh_inst: MeshInstance3D = brush.mesh_instance
		if not mesh_inst:
			root.hover_highlight.visible = false
			return
		var aabb = mesh_inst.get_aabb()
		root.hover_highlight.visible = true
		root.hover_highlight.global_transform = mesh_inst.global_transform
		root.hover_highlight.scale = aabb.size
	else:
		root.hover_highlight.visible = false


func clear_hover() -> void:
	if root.hover_highlight:
		root.hover_highlight.visible = false


# ---------------------------------------------------------------------------
# Face selection
# ---------------------------------------------------------------------------


func pick_face(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	if not camera:
		return {}
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos).normalized()
	var brushes: Array = []
	for node in root._iter_pick_nodes():
		if node is DraftBrush and is_brush_node(node):
			brushes.append(node)
	return FaceSelector.intersect_brushes(brushes, ray_origin, ray_dir)


func select_face_at_screen(camera: Camera3D, mouse_pos: Vector2, additive: bool) -> bool:
	var hit = pick_face(camera, mouse_pos)
	if hit.is_empty():
		if not additive:
			clear_face_selection()
		return false
	var brush = hit.get("brush", null)
	var face_idx = int(hit.get("face_idx", -1))
	if brush and face_idx >= 0:
		toggle_face_selection(brush, face_idx, additive)
		return true
	return false


func toggle_face_selection(brush: DraftBrush, face_idx: int, additive: bool) -> void:
	if not brush:
		return
	if not additive:
		root.face_selection.clear()
	var key = _face_key(brush)
	var indices: Array = root.face_selection.get(key, [])
	var idx = indices.find(face_idx)
	if idx >= 0:
		indices.remove_at(idx)
	else:
		indices.append(face_idx)
	root.face_selection[key] = indices
	_apply_face_selection()


func clear_face_selection() -> void:
	root.face_selection.clear()
	_apply_face_selection()


func get_face_selection() -> Dictionary:
	return root.face_selection.duplicate(true)


func get_primary_selected_face() -> Dictionary:
	for key in root.face_selection.keys():
		var indices: Array = root.face_selection.get(key, [])
		if indices.is_empty():
			continue
		var brush = _find_brush_by_key(str(key))
		if brush and indices[0] != null:
			return {"brush": brush, "face_idx": int(indices[0])}
	return {}


func assign_material_to_selected_faces(material_index: int) -> void:
	for key in root.face_selection.keys():
		var brush = _find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = root.face_selection.get(key, [])
		var typed: Array[int] = []
		for idx in indices:
			typed.append(int(idx))
		brush.assign_material_to_faces(material_index, typed)


func _apply_face_selection() -> void:
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var key = _face_key(brush)
		var indices: Array = root.face_selection.get(key, [])
		brush.set_selected_faces(PackedInt32Array(indices))


func _face_key(brush: DraftBrush) -> String:
	if brush == null:
		return ""
	if brush.brush_id != "":
		return brush.brush_id
	return str(brush.get_instance_id())


func _find_brush_by_key(key: String) -> DraftBrush:
	if key == "":
		return null
	var brush = _find_brush_by_id(key)
	if brush and brush is DraftBrush:
		return brush as DraftBrush
	if not key.is_valid_int():
		return null
	var target_id = int(key)
	for node in root._iter_pick_nodes():
		if node is DraftBrush and node.get_instance_id() == target_id:
			return node as DraftBrush
	return null
