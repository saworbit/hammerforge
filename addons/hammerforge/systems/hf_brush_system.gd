@tool
extends RefCounted
class_name HFBrushSystem

const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const FaceSelector = preload("../face_selector.gd")
const FaceData = preload("../face_data.gd")

var root: Node3D
var _brush_cache: Dictionary = {}  # brush_id (String) -> Node
var _brush_count: int = 0
var _material_cache: Dictionary = {}  # key (String) -> Material


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
	var brush_id = _next_brush_id()
	brush.brush_id = str(brush_id)
	brush.set_meta("brush_id", str(brush_id))
	_brush_cache[str(brush_id)] = brush
	_brush_count += 1
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
	_register_brush_id(str(brush_id), brush)
	if info.has("faces"):
		brush.apply_serialized_faces(info.get("faces", []))
	if info.has("visgroups"):
		var vgs = PackedStringArray()
		for v in info.get("visgroups", []):
			vgs.append(str(v))
		brush.set_meta("visgroups", vgs)
	if info.has("group_id") and str(info["group_id"]) != "":
		brush.set_meta("group_id", str(info["group_id"]))
	if info.has("brush_entity_class") and str(info["brush_entity_class"]) != "":
		brush.set_meta("brush_entity_class", str(info["brush_entity_class"]))
	if root.has_method("tag_brush_dirty"):
		root.tag_brush_dirty(str(brush_id))
	if root.has_method("_emit_or_batch"):
		root._emit_or_batch("brush_added", [str(brush_id)])
	elif root.has_signal("brush_added"):
		root.brush_added.emit(str(brush_id))
	return brush


func delete_brush(brush: Node, free: bool = true) -> void:
	if not brush:
		return
	# Clean up cross-references before removal
	_cleanup_brush_references(brush)
	var removed_id := ""
	if brush is DraftBrush:
		var bid = str((brush as DraftBrush).brush_id)
		removed_id = bid
		if bid != "":
			_brush_cache.erase(bid)
		var key = _face_key(brush as DraftBrush)
		if root.face_selection.has(key):
			root.face_selection.erase(key)
			_apply_face_selection()
	_brush_count = max(0, _brush_count - 1)
	if root.brush_manager:
		root.brush_manager.remove_brush(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	if free:
		brush.queue_free()
	if removed_id != "":
		if root.has_method("tag_brush_dirty"):
			root.tag_brush_dirty(removed_id)
		if root.has_method("_emit_or_batch"):
			root._emit_or_batch("brush_removed", [removed_id])
		elif root.has_signal("brush_removed"):
			root.brush_removed.emit(removed_id)


func delete_brush_by_id(brush_id: String) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Delete: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush:
		return _op_fail("Delete: brush '%s' not found" % brush_id)
	delete_brush(brush)
	return HFOpResult.success()


func nudge_brushes_by_id(brush_ids: Array, offset: Vector3) -> void:
	if brush_ids.is_empty():
		return
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is Node3D:
			(brush as Node3D).global_position += offset


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
	# Fast path: cache lookup
	if _brush_cache.has(brush_id):
		var cached = _brush_cache[brush_id]
		if is_instance_valid(cached) and cached.is_inside_tree():
			return cached
		_brush_cache.erase(brush_id)
	# Slow path: scan and populate cache
	for node in root._iter_pick_nodes():
		if node and node is DraftBrush:
			if node.has_meta("brush_id") and str(node.get_meta("brush_id")) == brush_id:
				_brush_cache[brush_id] = node
				return node
			if str((node as DraftBrush).brush_id) == brush_id:
				_brush_cache[brush_id] = node
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
	var brush_id = str(draft.brush_id)
	if brush_id == "" and draft.has_meta("brush_id"):
		brush_id = str(draft.get_meta("brush_id"))
	if brush_id == "":
		brush_id = _next_brush_id()
		draft.brush_id = str(brush_id)
		draft.set_meta("brush_id", str(brush_id))
	info["brush_id"] = brush_id
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
	var vgs: PackedStringArray = draft.get_meta("visgroups", PackedStringArray())
	if not vgs.is_empty():
		info["visgroups"] = Array(vgs)
	var gid: String = str(draft.get_meta("group_id", ""))
	if gid != "":
		info["group_id"] = gid
	var bec: String = str(draft.get_meta("brush_entity_class", ""))
	if bec != "":
		info["brush_entity_class"] = bec
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
	if root.is_entity_node(node):
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
	return _brush_count


# ---------------------------------------------------------------------------
# ID management
# ---------------------------------------------------------------------------


func _next_brush_id() -> String:
	root._brush_id_counter += 1
	return "%s_%s" % [str(Time.get_ticks_usec()), str(root._brush_id_counter)]


## Public wrapper for prefab instantiation.
func next_brush_id() -> String:
	return _next_brush_id()


func _register_brush_id(brush_id: String, brush_node: Node = null) -> void:
	if brush_id == "":
		return
	if brush_node:
		_brush_cache[brush_id] = brush_node
	_brush_count += 1
	var parts = brush_id.split("_")
	if parts.size() < 2:
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
	_apply_brush_material(brush, _make_pending_cut_material())
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
			var bid = str((child as DraftBrush).brush_id)
			if bid != "":
				_brush_cache.erase(bid)
			_brush_count = max(0, _brush_count - 1)
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
			var bid = str((child as DraftBrush).brush_id)
			if bid != "":
				_brush_cache.erase(bid)
			_brush_count = max(0, _brush_count - 1)
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
	_brush_cache.clear()
	_brush_count = 0
	if root.brush_manager:
		root.brush_manager.clear_brushes()
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if child is DraftBrush:
				root.draft_brushes_node.remove_child(child)
				child.queue_free()
	_clear_generated()
	_clear_preview()
	clear_pending_cuts()
	_clear_committed_cuts()
	if root.baked_container:
		root.baked_container.queue_free()
		root.baked_container = null


func _clear_generated() -> void:
	# Remove children from tree BEFORE queue_free so the reconciler
	# won't find ghost nodes that are pending deletion.
	if root.generated_floors:
		for child in root.generated_floors.get_children():
			root.generated_floors.remove_child(child)
			child.queue_free()
	if root.generated_walls:
		for child in root.generated_walls.get_children():
			root.generated_walls.remove_child(child)
			child.queue_free()
	if root.generated_heightmap_floors:
		for child in root.generated_heightmap_floors.get_children():
			root.generated_heightmap_floors.remove_child(child)
			child.queue_free()
	if root.generated_region_overlay:
		root.generated_region_overlay.mesh = null


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
	var cache_key = "%d_%d_%d" % [operation, int(solid), int(unshaded)]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
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
	_material_cache[cache_key] = mat
	return mat


func _make_pending_cut_material() -> Material:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.1, 0.5)
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


func apply_material_to_brush_by_id(brush_id: String, mat: Material) -> void:
	if brush_id == "":
		return
	var brush = _find_brush_by_id(brush_id)
	if brush:
		apply_material_to_brush(brush, mat)


func set_brush_transform_by_id(brush_id: String, size: Vector3, position: Vector3) -> void:
	if brush_id == "":
		return
	var brush = _find_brush_by_id(brush_id)
	if brush and brush is DraftBrush:
		var draft := brush as DraftBrush
		var old_size = draft.size
		var old_pos = draft.global_position
		draft.size = size
		draft.global_position = position
		if root.has_method("tag_brush_dirty"):
			root.tag_brush_dirty(brush_id)
		if root.texture_lock and not draft.faces.is_empty():
			_adjust_face_uvs_for_transform(draft, old_size, size, old_pos, position)


func _adjust_face_uvs_for_transform(
	draft: DraftBrush, old_size: Vector3, new_size: Vector3, old_pos: Vector3, new_pos: Vector3
) -> void:
	var pos_delta = new_pos - old_pos
	var size_ratio = Vector3(
		new_size.x / old_size.x if old_size.x > 0.001 else 1.0,
		new_size.y / old_size.y if old_size.y > 0.001 else 1.0,
		new_size.z / old_size.z if old_size.z > 0.001 else 1.0
	)
	for face in draft.faces:
		if face == null:
			continue
		face.adjust_uvs_for_transform(pos_delta, size_ratio)


func _adjust_face_uvs_for_rotation(draft: DraftBrush, angle_rad: float) -> void:
	for face in draft.faces:
		if face == null:
			continue
		face.adjust_uvs_for_rotation(angle_rad)


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


func assign_material_to_selected_faces(material_index: int) -> int:
	var count := 0
	for key in root.face_selection.keys():
		var brush = _find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = root.face_selection.get(key, [])
		var typed: Array[int] = []
		for idx in indices:
			typed.append(int(idx))
		brush.assign_material_to_faces(material_index, typed)
		count += typed.size()
	return count


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


# ---------------------------------------------------------------------------
# Pre-validation (check preconditions without performing the operation)
# ---------------------------------------------------------------------------


func can_hollow_brush(brush_id: String, wall_thickness: float) -> HFOpResult:
	if brush_id == "":
		return HFOpResult.fail("Hollow: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return HFOpResult.fail("Hollow: brush not found")
	var draft := brush as DraftBrush
	var min_dim = min(draft.size.x, min(draft.size.y, draft.size.z))
	if wall_thickness * 2.0 >= min_dim:
		return HFOpResult.fail(
			(
				"Wall thickness %.0f is too large for brush (smallest dim %.0f)"
				% [wall_thickness, min_dim]
			),
			"Use a thickness less than %.0f" % (min_dim / 2.0)
		)
	return HFOpResult.success()


func can_clip_brush(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	if brush_id == "":
		return HFOpResult.fail("Clip: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return HFOpResult.fail("Clip: brush not found")
	var draft := brush as DraftBrush
	var pos = draft.global_position
	var half = draft.size * 0.5
	var brush_min: float
	var brush_max: float
	match axis:
		0:
			brush_min = pos.x - half.x
			brush_max = pos.x + half.x
		1:
			brush_min = pos.y - half.y
			brush_max = pos.y + half.y
		_:
			brush_min = pos.z - half.z
			brush_max = pos.z + half.z
	var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
	if snap > 0.0:
		split_pos = snapped(split_pos, snap)
	var margin = snap if snap > 0.0 else 0.01
	if split_pos <= brush_min + margin or split_pos >= brush_max - margin:
		var axis_name = ["X", "Y", "Z"][clampi(axis, 0, 2)]
		return HFOpResult.fail(
			"Clip: split position %.1f is outside brush bounds on %s axis" % [split_pos, axis_name],
			"Click inside the brush face to pick a valid split point"
		)
	return HFOpResult.success()


# ---------------------------------------------------------------------------
# Hollow
# ---------------------------------------------------------------------------


func hollow_brush_by_id(brush_id: String, wall_thickness: float) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Hollow: no brush ID provided")
	if root.has_method("tag_full_reconcile"):
		root.tag_full_reconcile()
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Hollow: brush not found")
	var draft := brush as DraftBrush
	# Hollow only works on axis-aligned box brushes — reject custom geometry
	if draft.shape == root.BrushShape.CUSTOM:
		return _op_fail(
			"Hollow: not supported on polygon/path brushes",
			"Hollow only works on axis-aligned box brushes"
		)
	var size = draft.size
	var pos = draft.global_position
	var mat = draft.material_override
	var t = wall_thickness

	# Wall thickness must be less than half the smallest dimension
	var min_dim = min(size.x, min(size.y, size.z))
	if t * 2.0 >= min_dim:
		return _op_fail(
			"Wall thickness %.0f is too large for brush (smallest dim %.0f)" % [t, min_dim],
			"Use a thickness less than %.0f" % (min_dim / 2.0)
		)

	var infos: Array = []
	# Top wall
	(
		infos
		. append(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(size.x, t, size.z),
				"center": Vector3(pos.x, pos.y + (size.y - t) / 2.0, pos.z),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": _next_brush_id(),
			}
		)
	)
	# Bottom wall
	(
		infos
		. append(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(size.x, t, size.z),
				"center": Vector3(pos.x, pos.y - (size.y - t) / 2.0, pos.z),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": _next_brush_id(),
			}
		)
	)
	# Left wall (X-)
	(
		infos
		. append(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(t, size.y - 2.0 * t, size.z),
				"center": Vector3(pos.x - (size.x - t) / 2.0, pos.y, pos.z),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": _next_brush_id(),
			}
		)
	)
	# Right wall (X+)
	(
		infos
		. append(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(t, size.y - 2.0 * t, size.z),
				"center": Vector3(pos.x + (size.x - t) / 2.0, pos.y, pos.z),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": _next_brush_id(),
			}
		)
	)
	# Front wall (Z+)
	(
		infos
		. append(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(size.x - 2.0 * t, size.y - 2.0 * t, t),
				"center": Vector3(pos.x, pos.y, pos.z + (size.z - t) / 2.0),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": _next_brush_id(),
			}
		)
	)
	# Back wall (Z-)
	(
		infos
		. append(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(size.x - 2.0 * t, size.y - 2.0 * t, t),
				"center": Vector3(pos.x, pos.y, pos.z - (size.z - t) / 2.0),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": _next_brush_id(),
			}
		)
	)

	# Copy material to all wall infos
	if mat:
		for info in infos:
			info["material"] = mat

	# Capture metadata to copy to walls
	var src_visgroups = draft.get_meta("visgroups", PackedStringArray())
	var src_group_id = draft.get_meta("group_id", "")
	var src_bec = draft.get_meta("brush_entity_class", "")

	# Delete original brush
	delete_brush(brush)

	# Create wall brushes
	var count := 0
	for info in infos:
		var wall = create_brush_from_info(info)
		if wall:
			if src_visgroups.size() > 0:
				wall.set_meta("visgroups", src_visgroups.duplicate())
			if src_group_id != "":
				wall.set_meta("group_id", src_group_id)
			if src_bec != "":
				wall.set_meta("brush_entity_class", src_bec)
			count += 1

	root._log("Hollow: created %d walls (thickness %.1f)" % [count, t])
	return HFOpResult.success("Hollow: created %d walls" % count)


# ---------------------------------------------------------------------------
# Merge Brushes
# ---------------------------------------------------------------------------


func can_merge_brushes(brush_ids: Array) -> HFOpResult:
	if brush_ids.size() < 2:
		return HFOpResult.fail(
			"Merge: select at least 2 brushes", "Select multiple brushes before merging"
		)
	var first_op: int = -1
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if not brush or not (brush is DraftBrush):
			return HFOpResult.fail("Merge: brush '%s' not found" % str(brush_id))
		var draft := brush as DraftBrush
		if first_op < 0:
			first_op = draft.operation
		elif draft.operation != first_op:
			return HFOpResult.fail(
				"Merge: all brushes must have the same operation type",
				"Cannot merge additive and subtractive brushes together"
			)
	return HFOpResult.success()


func merge_brushes_by_ids(brush_ids: Array) -> HFOpResult:
	if brush_ids.size() < 2:
		return _op_fail("Merge: select at least 2 brushes")
	if root.has_method("tag_full_reconcile"):
		root.tag_full_reconcile()

	# Collect all valid brushes
	var brushes: Array = []  # Array of DraftBrush
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			brushes.append(brush as DraftBrush)
	if brushes.size() < 2:
		return _op_fail("Merge: need at least 2 valid brushes")

	var first: DraftBrush = brushes[0]
	var operation: int = first.operation

	# Use first brush's full transform as the merged brush's transform.
	# All source face verts will be mapped: source local → world → merged local.
	var merged_xform: Transform3D = first.global_transform
	var merged_xform_inv: Transform3D = merged_xform.affine_inverse()

	# Build a mapping from material_override → material_idx so faces from
	# brushes with different overrides keep their visual appearance.
	# Faces that already have a per-face material_idx are left unchanged.
	var mat_idx_cache: Dictionary = {}  # Material -> int

	# Collect faces from all brushes, transforming local_verts from
	# each brush's local space through world space into merged local space.
	var serialized_faces: Array = []
	for brush in brushes:
		var draft := brush as DraftBrush
		# Ensure faces exist (auto-generate for box shapes)
		if draft.faces.is_empty():
			draft.rebuild_preview()
		# Full transform: source local → world → merged local
		var to_merged: Transform3D = merged_xform_inv * draft.global_transform
		var to_merged_basis: Basis = to_merged.basis
		var to_merged_origin: Vector3 = to_merged.origin
		# Resolve material_idx for faces that rely on brush material_override
		var brush_mat_idx: int = -1
		if draft.material_override:
			if mat_idx_cache.has(draft.material_override):
				brush_mat_idx = mat_idx_cache[draft.material_override]
			elif root.has_method("add_material_to_palette"):
				brush_mat_idx = root.add_material_to_palette(draft.material_override)
				mat_idx_cache[draft.material_override] = brush_mat_idx
		for face in draft.faces:
			if face == null:
				continue
			var fd: Dictionary = face.to_dict()
			# Transform local_verts through the full basis + origin
			if fd.has("local_verts") and fd["local_verts"] is Array:
				var transformed: Array = []
				for v in fd["local_verts"]:
					if v is Array and v.size() >= 3:
						var src := Vector3(v[0], v[1], v[2])
						var dst: Vector3 = to_merged_basis * src + to_merged_origin
						transformed.append([dst.x, dst.y, dst.z])
					else:
						transformed.append(v)
				fd["local_verts"] = transformed
			# Transform the face normal through the basis (no translation)
			if fd.has("normal") and fd["normal"] is Array and fd["normal"].size() >= 3:
				var src_n := Vector3(fd["normal"][0], fd["normal"][1], fd["normal"][2])
				var dst_n: Vector3 = (to_merged_basis * src_n).normalized()
				fd["normal"] = [dst_n.x, dst_n.y, dst_n.z]
			# Stamp per-face material_idx for faces that relied on brush override
			if int(fd.get("material_idx", -1)) < 0 and brush_mat_idx >= 0:
				fd["material_idx"] = brush_mat_idx
			serialized_faces.append(fd)

	# Capture metadata from first brush
	var src_visgroups: PackedStringArray = first.get_meta("visgroups", PackedStringArray())
	var src_group_id: String = str(first.get_meta("group_id", ""))
	var src_bec: String = str(first.get_meta("brush_entity_class", ""))

	# Delete all original brushes
	for brush in brushes:
		delete_brush(brush)

	# Create merged brush with full transform (not just center position)
	var merged_info: Dictionary = {
		"shape": root.BrushShape.CUSTOM,
		"size": Vector3(32, 32, 32),
		"transform": merged_xform,
		"operation": operation,
		"brush_id": _next_brush_id(),
		"faces": serialized_faces,
	}

	var merged = create_brush_from_info(merged_info)
	if merged:
		if src_visgroups.size() > 0:
			merged.set_meta("visgroups", src_visgroups.duplicate())
		if src_group_id != "":
			merged.set_meta("group_id", src_group_id)
		if src_bec != "":
			merged.set_meta("brush_entity_class", src_bec)

	var count: int = brushes.size()
	root._log("Merge: combined %d brushes into one" % count)
	return HFOpResult.success("Merged %d brushes" % count)


# ---------------------------------------------------------------------------
# Move to Floor / Ceiling
# ---------------------------------------------------------------------------


func move_brushes_to_floor(brush_ids: Array) -> void:
	_move_brushes_vertical(brush_ids, -1.0)


func move_brushes_to_ceiling(brush_ids: Array) -> void:
	_move_brushes_vertical(brush_ids, 1.0)


func _move_brushes_vertical(brush_ids: Array, direction: float) -> void:
	if brush_ids.is_empty():
		return
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if not brush or not (brush is DraftBrush):
			continue
		var draft := brush as DraftBrush
		var half_y = draft.size.y * 0.5
		var origin = draft.global_position
		# Cast ray from brush center in the vertical direction
		var ray_origin = origin + Vector3(0.0, half_y * direction, 0.0)
		var ray_dir = Vector3(0.0, direction, 0.0)
		var space = root.get_world_3d().direct_space_state
		if not space:
			continue
		var query = PhysicsRayQueryParameters3D.new()
		query.from = ray_origin
		query.to = ray_origin + ray_dir * 10000.0
		var result = space.intersect_ray(query)
		if result.is_empty():
			# No physics hit — try raycasting against other brushes
			var best_t = INF
			var best_pos = Vector3.ZERO
			var found = false
			for node in root._iter_pick_nodes():
				if not (node is DraftBrush) or node == brush:
					continue
				var other := node as DraftBrush
				if not other.mesh_instance:
					continue
				var inv = other.mesh_instance.global_transform.affine_inverse()
				var local_origin = inv * ray_origin
				var local_dir = (inv.basis * ray_dir).normalized()
				var aabb = other.mesh_instance.get_aabb()
				var t = root._ray_intersect_aabb(local_origin, local_dir, aabb)
				if t >= 0.0 and t < best_t:
					best_t = t
					best_pos = ray_origin + ray_dir * best_t
					found = true
			if found:
				var new_y = best_pos.y - half_y * direction
				var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
				draft.global_position.y = snapped(new_y, snap) if snap > 0.0 else new_y
		else:
			var hit_pos: Vector3 = result["position"]
			var new_y = hit_pos.y - half_y * direction
			var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
			draft.global_position.y = snapped(new_y, snap) if snap > 0.0 else new_y


# ---------------------------------------------------------------------------
# Clip (Split Brush)
# ---------------------------------------------------------------------------


## Split a brush along an axis-aligned plane.
## axis: 0=X, 1=Y, 2=Z.  split_pos: world coordinate on that axis.
func clip_brush_by_id(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Clip: no brush ID provided")
	if root.has_method("tag_full_reconcile"):
		root.tag_full_reconcile()
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Clip: brush not found")
	var draft := brush as DraftBrush
	# Clip only works on axis-aligned box brushes — reject custom geometry
	if draft.shape == root.BrushShape.CUSTOM:
		return _op_fail(
			"Clip: not supported on polygon/path brushes",
			"Clip only works on axis-aligned box brushes"
		)
	var pos = draft.global_position
	var half = draft.size * 0.5

	# Compute brush min/max along the clip axis
	var brush_min: float
	var brush_max: float
	match axis:
		0:
			brush_min = pos.x - half.x
			brush_max = pos.x + half.x
		1:
			brush_min = pos.y - half.y
			brush_max = pos.y + half.y
		_:
			brush_min = pos.z - half.z
			brush_max = pos.z + half.z

	# Snap the split position to the grid
	var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
	if snap > 0.0:
		split_pos = snapped(split_pos, snap)

	# Reject if split is outside or on the edge of the brush
	var margin = snap if snap > 0.0 else 0.01
	if split_pos <= brush_min + margin or split_pos >= brush_max - margin:
		var axis_name = ["X", "Y", "Z"][clampi(axis, 0, 2)]
		return _op_fail(
			"Clip: split position %.1f is outside brush bounds on %s axis" % [split_pos, axis_name],
			"Click inside the brush face to pick a valid split point"
		)

	var mat = draft.material_override
	var operation = draft.operation

	# Build two brush infos — one for each side
	var size_a = draft.size.abs()
	var size_b = draft.size.abs()
	var center_a = pos
	var center_b = pos

	match axis:
		0:  # X axis
			size_a.x = split_pos - brush_min
			size_b.x = brush_max - split_pos
			center_a.x = (brush_min + split_pos) / 2.0
			center_b.x = (split_pos + brush_max) / 2.0
		1:  # Y axis
			size_a.y = split_pos - brush_min
			size_b.y = brush_max - split_pos
			center_a.y = (brush_min + split_pos) / 2.0
			center_b.y = (split_pos + brush_max) / 2.0
		_:  # Z axis
			size_a.z = split_pos - brush_min
			size_b.z = brush_max - split_pos
			center_a.z = (brush_min + split_pos) / 2.0
			center_b.z = (split_pos + brush_max) / 2.0

	var infos: Array = [
		{
			"shape": root.BrushShape.BOX,
			"size": size_a,
			"center": center_a,
			"operation": operation,
			"brush_id": _next_brush_id(),
		},
		{
			"shape": root.BrushShape.BOX,
			"size": size_b,
			"center": center_b,
			"operation": operation,
			"brush_id": _next_brush_id(),
		},
	]

	if mat:
		for info in infos:
			info["material"] = mat

	# Copy brush entity class if present
	var bec = str(draft.get_meta("brush_entity_class", ""))
	if bec != "":
		for info in infos:
			info["brush_entity_class"] = bec

	# Copy visgroups / group_id
	var vgs: PackedStringArray = draft.get_meta("visgroups", PackedStringArray())
	if not vgs.is_empty():
		for info in infos:
			info["visgroups"] = Array(vgs)
	var gid = str(draft.get_meta("group_id", ""))
	if gid != "":
		for info in infos:
			info["group_id"] = gid

	delete_brush(brush)

	var count := 0
	for info in infos:
		var piece = create_brush_from_info(info)
		if piece:
			count += 1

	var axis_label = ["X", "Y", "Z"][clampi(axis, 0, 2)]
	root._log("Clip: split along %s at %.1f → %d pieces" % [axis_label, split_pos, count])
	return HFOpResult.success("Clip: split into %d pieces" % count)


## Clip brush using a face hit from FaceSelector.
## Determines the axis from the face normal and uses the hit position.
func clip_brush_at_point(brush_id: String, face_idx: int, hit_position: Vector3) -> void:
	if brush_id == "":
		return
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return

	var face: FaceData = draft.faces[face_idx]
	face.ensure_geometry()

	# Transform face normal to world space to determine clip axis
	var world_normal = (draft.global_transform.basis * face.normal).normalized()
	var abs_normal = world_normal.abs()

	var axis: int
	var split_pos: float
	if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
		axis = 0
		split_pos = hit_position.x
	elif abs_normal.y >= abs_normal.x and abs_normal.y >= abs_normal.z:
		axis = 1
		split_pos = hit_position.y
	else:
		axis = 2
		split_pos = hit_position.z

	clip_brush_by_id(brush_id, axis, split_pos)


# ---------------------------------------------------------------------------
# Brush Entity (Tie / Untie)
# ---------------------------------------------------------------------------


func tie_brushes_to_entity(brush_ids: Array, entity_class: String) -> void:
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			brush.set_meta("brush_entity_class", entity_class)
	root._log("Tied %d brushes as '%s'" % [brush_ids.size(), entity_class])


func untie_brushes_from_entity(brush_ids: Array) -> void:
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			if brush.has_meta("brush_entity_class"):
				brush.remove_meta("brush_entity_class")
	root._log("Untied %d brushes" % brush_ids.size())


# ---------------------------------------------------------------------------
# UV Justify
# ---------------------------------------------------------------------------


func justify_selected_faces(mode: String, treat_as_one: bool) -> void:
	if root.face_selection.is_empty():
		return

	# Collect all selected face references
	var face_refs: Array = []
	for key in root.face_selection.keys():
		var brush = _find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = root.face_selection.get(key, [])
		for idx in indices:
			var face_idx = int(idx)
			if face_idx >= 0 and face_idx < brush.faces.size():
				face_refs.append({"brush": brush, "face": brush.faces[face_idx]})

	if face_refs.is_empty():
		return

	if treat_as_one and face_refs.size() > 1:
		# Compute unified bounds across all faces
		var all_min := Vector2(INF, INF)
		var all_max := Vector2(-INF, -INF)
		for ref in face_refs:
			var face: FaceData = ref["face"]
			face.ensure_custom_uvs()
			for uv in face.custom_uvs:
				all_min.x = min(all_min.x, uv.x)
				all_min.y = min(all_min.y, uv.y)
				all_max.x = max(all_max.x, uv.x)
				all_max.y = max(all_max.y, uv.y)
		for ref in face_refs:
			var face: FaceData = ref["face"]
			_justify_face(face, mode, all_min, all_max)
			ref["brush"].rebuild_preview()
	else:
		for ref in face_refs:
			var face: FaceData = ref["face"]
			face.ensure_custom_uvs()
			var uv_min := Vector2(INF, INF)
			var uv_max := Vector2(-INF, -INF)
			for uv in face.custom_uvs:
				uv_min.x = min(uv_min.x, uv.x)
				uv_min.y = min(uv_min.y, uv.y)
				uv_max.x = max(uv_max.x, uv.x)
				uv_max.y = max(uv_max.y, uv.y)
			_justify_face(face, mode, uv_min, uv_max)
			ref["brush"].rebuild_preview()


func _justify_face(face: FaceData, mode: String, uv_min: Vector2, uv_max: Vector2) -> void:
	var uv_size = uv_max - uv_min
	if uv_size.x < 0.0001 and uv_size.y < 0.0001:
		return

	match mode:
		"fit":
			# Scale UVs to fill 0..1 range
			var scale_x = 1.0 / uv_size.x if uv_size.x > 0.0001 else 1.0
			var scale_y = 1.0 / uv_size.y if uv_size.y > 0.0001 else 1.0
			face.uv_scale = Vector2(face.uv_scale.x * scale_x, face.uv_scale.y * scale_y)
			face.uv_offset = Vector2(
				-uv_min.x * scale_x + face.uv_offset.x * scale_x,
				-uv_min.y * scale_y + face.uv_offset.y * scale_y
			)
			face.custom_uvs = PackedVector2Array()
		"center":
			var center = (uv_min + uv_max) * 0.5
			var shift = Vector2(0.5, 0.5) - center
			face.uv_offset += shift
			face.custom_uvs = PackedVector2Array()
		"left":
			var shift_x = -uv_min.x
			face.uv_offset.x += shift_x
			face.custom_uvs = PackedVector2Array()
		"right":
			var shift_x = 1.0 - uv_max.x
			face.uv_offset.x += shift_x
			face.custom_uvs = PackedVector2Array()
		"top":
			var shift_y = -uv_min.y
			face.uv_offset.y += shift_y
			face.custom_uvs = PackedVector2Array()
		"bottom":
			var shift_y = 1.0 - uv_max.y
			face.uv_offset.y += shift_y
			face.custom_uvs = PackedVector2Array()
		"stretch":
			# Scale UVs to exactly fill 0..1, stretching non-uniformly
			var scale_x = 1.0 / uv_size.x if uv_size.x > 0.0001 else 1.0
			var scale_y = 1.0 / uv_size.y if uv_size.y > 0.0001 else 1.0
			face.uv_scale = Vector2(face.uv_scale.x * scale_x, face.uv_scale.y * scale_y)
			face.uv_offset = Vector2(
				-uv_min.x * scale_x + face.uv_offset.x * scale_x,
				-uv_min.y * scale_y + face.uv_offset.y * scale_y
			)
			face.custom_uvs = PackedVector2Array()
		"tile":
			# Scale UVs uniformly so the shorter axis fills 0..1, preserving aspect ratio
			# (the longer axis exceeds 1.0 and tiles)
			var min_dim: float = minf(uv_size.x, uv_size.y)
			var scale_uniform = 1.0 / min_dim if min_dim > 0.0001 else 1.0
			face.uv_scale = face.uv_scale * scale_uniform
			var new_min = uv_min * scale_uniform
			var new_max = uv_max * scale_uniform
			var new_center = (new_min + new_max) * 0.5
			var shift = Vector2(0.5, 0.5) - new_center
			face.uv_offset = face.uv_offset * scale_uniform + shift
			face.custom_uvs = PackedVector2Array()


# ---------------------------------------------------------------------------
# Duplicator / Instanced Geometry
# ---------------------------------------------------------------------------

var _duplicators: Dictionary = {}  # duplicator_id -> HFDuplicator


func create_duplicate_array(
	brush_ids: PackedStringArray, p_count: int, p_offset: Vector3
) -> Variant:
	if brush_ids.is_empty() or p_count < 1:
		return null
	# Clean up any existing duplicator that owns these source brushes.
	for bid in brush_ids:
		var brush = _brush_cache.get(bid)
		if brush and brush.has_meta("duplicator_id"):
			var old_id: String = str(brush.get_meta("duplicator_id"))
			if old_id != "" and _duplicators.has(old_id):
				_duplicators[old_id].clear_instances(self)
				_duplicators.erase(old_id)
	var dup := HFDuplicator.new()
	dup.source_brush_ids = brush_ids
	if not dup.generate(self, p_count, p_offset):
		return null
	_duplicators[dup.duplicator_id] = dup
	return dup


func remove_duplicate_array(duplicator_id: String) -> void:
	if not _duplicators.has(duplicator_id):
		return
	var dup: HFDuplicator = _duplicators[duplicator_id]
	dup.clear_instances(self)
	_duplicators.erase(duplicator_id)


func get_duplicator_for_brush(brush_id: String) -> Variant:
	var brush = _brush_cache.get(brush_id)
	if not is_instance_valid(brush):
		brush = find_brush_by_id(brush_id)
	if not is_instance_valid(brush):
		return null
	var dup_id: String = str(brush.get_meta("duplicator_id", ""))
	if dup_id == "" or not _duplicators.has(dup_id):
		return null
	return _duplicators[dup_id]


# ---------------------------------------------------------------------------
# Reference cleanup on deletion
# ---------------------------------------------------------------------------


func _cleanup_brush_references(brush: Node) -> void:
	if not brush:
		return
	# Strip group membership
	var group_id := str(brush.get_meta("group_id", ""))
	if group_id != "" and root.has_method("visgroup_system"):
		pass  # groups are on visgroup_system
	if group_id != "":
		brush.set_meta("group_id", "")
		if root.get("visgroup_system") and root.visgroup_system.has_method("_cleanup_empty_group"):
			root.visgroup_system._cleanup_empty_group(group_id)
	# Strip visgroup membership
	var vgs: PackedStringArray = brush.get_meta("visgroups", PackedStringArray())
	if not vgs.is_empty():
		brush.set_meta("visgroups", PackedStringArray())
	# Clean up entity I/O connections targeting this brush by name
	var brush_name := brush.name
	if brush_name != "" and root.get("entity_system"):
		var removed_count: int = root.entity_system.cleanup_dangling_connections(brush_name)
		if removed_count > 0 and root.has_signal("user_message"):
			root.user_message.emit(
				(
					"Removed %d I/O connection(s) targeting deleted brush '%s'"
					% [removed_count, brush_name]
				),
				1
			)


# ---------------------------------------------------------------------------
# Operation result helpers
# ---------------------------------------------------------------------------


func _op_fail(msg: String, hint: String = "") -> HFOpResult:
	if root and root.has_signal("user_message"):
		root.user_message.emit(msg, 1)  # WARNING level
	return HFOpResult.fail(msg, hint)
