@tool
extends RefCounted
class_name HFBrushSystem

const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const FaceSelector = preload("../face_selector.gd")
const FaceData = preload("../face_data.gd")
const HFValidation = preload("../hf_validation.gd")
const HFOutlineUtil = preload("../hf_outline_util.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")
const CONTAINER_ROLE_META := &"hf_container_role"
const ROLE_DRAFT := "draft"
const ROLE_PENDING := "pending"
const ROLE_COMMITTED := "committed"

var root: Node3D
var _brush_cache: Dictionary = {}  # brush_id (String) -> Node
var _brush_count: int = 0
var _material_cache: Dictionary = {}  # key (String) -> Material
var _hover_outline_key := ""


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
	var brush_id = _next_brush_id()
	brush.brush_id = str(brush_id)
	brush.set_meta("brush_id", str(brush_id))
	_brush_cache[str(brush_id)] = brush
	_brush_count += 1
	if operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node:
		_add_pending_cut(brush)
	else:
		_add_brush_to_draft(brush)
	brush.global_position = snapped + Vector3(0, size.y * 0.5, 0)
	_legacy_manager_add(brush)
	root._record_last_brush(brush.global_position)
	return true


## The smallest floor a brush may be on any axis. The same figure the validator's
## auto fix uses, so the two agree about what counts as too small.
const MIN_BRUSH_EXTENT := 0.1


## A size a brush can actually be built from, and a warning when it was not.
##
## create_brush_from_info() is the single door into the level for undo restore,
## duplication, prefab instancing, .map import and .hflevel load, so a bad size
## from any of those used to become a brush that looked fine in the tree. A
## negative component gives the basis a negative determinant, which inverts the
## face winding invisibly: each FaceData ends up with a normal pointing the
## opposite way from the vertices it holds, and that only shows up at bake or in
## an exported plane. A zero component gives a brush with no volume at all. Both
## landed in the draft container with an id and counted as live.
##
## The validator did catch them, but only if somebody ran Validate.
static func _usable_size(raw) -> Vector3:
	if not (raw is Vector3):
		return Vector3(MIN_BRUSH_EXTENT, MIN_BRUSH_EXTENT, MIN_BRUSH_EXTENT)
	var size: Vector3 = raw
	var fixed := Vector3(
		maxf(MIN_BRUSH_EXTENT, absf(size.x)),
		maxf(MIN_BRUSH_EXTENT, absf(size.y)),
		maxf(MIN_BRUSH_EXTENT, absf(size.z))
	)
	if not fixed.is_equal_approx(size):
		HFLog.warn(
			(
				(
					"Brush size %s cannot be built. Using %s instead. A negative size builds the "
					+ "brush inside out and a zero size builds no volume."
				)
				% [str(size), str(fixed)]
			)
		)
	return fixed


func create_brush_from_info(info: Dictionary) -> Node:
	if info.is_empty():
		return null
	var raw_size = info.get("size", root.drag_size_default)
	if raw_size is Vector3 and not (raw_size as Vector3).is_finite():
		# A zero or negative size is coerced, because there is a nearest size a
		# user plainly meant. There is no nearest size to a NaN, and once one is
		# on a brush the AABB, the level AABB, the chunking and the saved file all
		# take it and no editor action gets the brush back.
		HFLog.warn("HFBrushSystem: brush size %s is not a size" % str(raw_size))
		return null
	var shape = info.get("shape", root.BrushShape.BOX)
	var size = _usable_size(raw_size)
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
		brush.set_meta(CONTAINER_ROLE_META, ROLE_COMMITTED)
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
	if not committed:
		_legacy_manager_add(brush)
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
		brush.set_brush_entity_class(str(info["brush_entity_class"]))
	if info.has("entity_io_outputs"):
		var outputs: Array = info.get("entity_io_outputs", [])
		if not outputs.is_empty():
			brush.set_meta("entity_io_outputs", outputs.duplicate(true))
	if info.has("entity_name") and str(info["entity_name"]) != "":
		brush.set_meta("entity_name", str(info["entity_name"]))
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
		var key = face_key(brush as DraftBrush)
		if root.face_selection.has(key):
			root.face_selection.erase(key)
			_apply_face_selection()
			# The dock's surface panel is still pointed at a face that just went
			# away. Batched deletes coalesce this down to one emission.
			if root.has_method("_emit_or_batch"):
				root._emit_or_batch("face_selection_changed", [])
			elif root.has_signal("face_selection_changed"):
				root.face_selection_changed.emit()
	_brush_count = max(0, _brush_count - 1)
	_legacy_manager_remove(brush)
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
	if brush_ids.is_empty() or offset.is_zero_approx():
		return
	for brush_id in brush_ids:
		var brush_key := str(brush_id)
		var brush = _find_brush_by_id(brush_key)
		if brush and brush is DraftBrush:
			var draft := brush as DraftBrush
			set_brush_transform_by_id(brush_key, draft.size, draft.global_position + offset)


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
	_set_container_role(brush, _container_role(parent))
	if index >= 0 and index < parent.get_child_count():
		parent.move_child(brush, index)
	if owner:
		brush.owner = owner
	if brush is Node3D:
		_legacy_manager_add(brush)


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
	# Slow path: scan editable brush containers and populate the live cache.
	for node in root._iter_pick_nodes():
		if node and node is DraftBrush:
			if node.has_meta("brush_id") and str(node.get_meta("brush_id")) == brush_id:
				_brush_cache[brush_id] = node
				return node
			if str((node as DraftBrush).brush_id) == brush_id:
				_brush_cache[brush_id] = node
				return node
	return null


func find_managed_brush_by_id(brush_id: String) -> Node:
	var nodes: Array = (
		root._iter_managed_brush_nodes()
		if root.has_method("_iter_managed_brush_nodes")
		else root._iter_pick_nodes()
	)
	for node in nodes:
		if node and node is DraftBrush:
			if node.has_meta("brush_id") and str(node.get_meta("brush_id")) == brush_id:
				return node
			if str((node as DraftBrush).brush_id) == brush_id:
				return node
	return null


func find_brush_by_id(brush_id: String) -> Node:
	return _find_brush_by_id(brush_id)


func get_cached_brushes() -> Array:
	var out: Array = []
	for brush in _brush_cache.values():
		if is_instance_valid(brush):
			out.append(brush)
	return out


func get_cached_brush_count() -> int:
	return get_cached_brushes().size()


func _legacy_manager_add(brush: Node) -> void:
	if root and root.brush_manager and brush:
		root.brush_manager.add_brush(brush)


func _legacy_manager_remove(brush: Node) -> void:
	if root and root.brush_manager and brush:
		root.brush_manager.remove_brush(brush)


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
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		info["entity_io_outputs"] = outputs.duplicate(true)
	var ename: String = str(draft.get_meta("entity_name", ""))
	if ename != "":
		info["entity_name"] = ename
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


## Repair caches after a Godot-owned Scene-tree duplicate/delete. Those edits
## bypass HammerForge CRUD, so rebuild from the authoritative containers after
## the change tracker has normalized missing/colliding stable IDs.
func reconcile_external_structure() -> bool:
	var cache: Dictionary = {}
	var manager_brushes: Array = []
	var reserved_ids: Dictionary = {}
	var repaired := false
	for container in [root.draft_brushes_node, root.pending_node, root.committed_node]:
		if not container:
			continue
		var role := _container_role(container)
		for child in container.get_children():
			if not child is DraftBrush or root.is_entity_node(child):
				continue
			var brush_id := _brush_id_from_node(child)
			var duplicate_id := not brush_id.is_empty() and reserved_ids.has(brush_id)
			if duplicate_id and child.has_method("make_face_resources_unique"):
				child.call("make_face_resources_unique")
			if brush_id.is_empty() or duplicate_id:
				brush_id = _next_available_brush_id(reserved_ids)
			repaired = _sync_brush_id(child, brush_id) or repaired
			reserved_ids[brush_id] = true
			_advance_id_counter(brush_id)
			var previous_role := str(child.get_meta(CONTAINER_ROLE_META, ""))
			if previous_role != role:
				_reconcile_container_semantics(child as DraftBrush, role, previous_role)
				repaired = true
			if role != ROLE_COMMITTED:
				cache[brush_id] = child
				manager_brushes.append(child)
	_brush_cache = cache
	_brush_count = manager_brushes.size()
	if root.brush_manager:
		root.brush_manager.brushes = manager_brushes
	return repaired


static func _brush_id_from_node(brush: Node) -> String:
	# Metadata is the internal authority when upgrading a scene from an older
	# version where brush_id was visible and editable in the Inspector.
	var brush_id := str(brush.get_meta("brush_id", ""))
	if brush_id.is_empty():
		brush_id = str(brush.get("brush_id"))
	return brush_id


func _next_available_brush_id(reserved_ids: Dictionary) -> String:
	var brush_id := _next_brush_id()
	while reserved_ids.has(brush_id):
		brush_id = _next_brush_id()
	return brush_id


static func _sync_brush_id(brush: Node, brush_id: String) -> bool:
	var changed := false
	if str(brush.get("brush_id")) != brush_id:
		brush.set("brush_id", brush_id)
		changed = true
	if str(brush.get_meta("brush_id", "")) != brush_id:
		brush.set_meta("brush_id", brush_id)
		changed = true
	return changed


func _container_role(container: Node) -> String:
	if container == root.pending_node:
		return ROLE_PENDING
	if container == root.committed_node:
		return ROLE_COMMITTED
	return ROLE_DRAFT


static func _set_container_role(brush: Node, role: String) -> void:
	if brush:
		brush.set_meta(CONTAINER_ROLE_META, role)


func _reconcile_container_semantics(brush: DraftBrush, role: String, previous_role: String) -> void:
	_set_container_role(brush, role)
	match role:
		ROLE_PENDING:
			brush.visible = true
			brush.operation = CSGShape3D.OPERATION_SUBTRACTION
			brush.set_meta("pending_subtract", true)
			brush.set_meta("committed_cut", false)
			if previous_role != "":
				_apply_brush_material(brush, _make_pending_cut_material())
		ROLE_COMMITTED:
			brush.visible = false
			brush.operation = CSGShape3D.OPERATION_SUBTRACTION
			brush.set_meta("pending_subtract", false)
			brush.set_meta("committed_cut", true)
		_:
			brush.visible = true
			brush.set_meta("pending_subtract", false)
			brush.set_meta("committed_cut", false)
			if previous_role in [ROLE_PENDING, ROLE_COMMITTED]:
				_apply_brush_material(
					brush,
					_make_brush_material(brush.operation, true, true),
				)


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
	_advance_id_counter(brush_id)


func _advance_id_counter(brush_id: String) -> void:
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
	_set_container_role(brush, ROLE_DRAFT)
	root._assign_owner(brush)


func _add_pending_cut(brush: DraftBrush) -> void:
	if not root.pending_node:
		return
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	_apply_brush_material(brush, _make_pending_cut_material())
	brush.set_meta("pending_subtract", true)
	root.pending_node.add_child(brush)
	_set_container_role(brush, ROLE_PENDING)
	root._assign_owner(brush)


func apply_pending_cuts() -> void:
	if not HFValidation.has_draft_containers(root):
		return
	var pending_count = root.pending_node.get_child_count()
	for child in root.pending_node.get_children():
		if child is DraftBrush:
			root.pending_node.remove_child(child)
			root.draft_brushes_node.add_child(child)
			_set_container_role(child, ROLE_DRAFT)
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


func prepare_commit_cuts() -> bool:
	root._log("Commit cuts (freeze=%s)" % root.commit_freeze)
	var commit_targets: Array = []
	var pending_targets: Array = []
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if child is DraftBrush and _is_subtract_brush(child):
				commit_targets.append(child)
	if root.pending_node:
		for child in root.pending_node.get_children():
			if child is DraftBrush:
				commit_targets.append(child)
				pending_targets.append(child)
	if commit_targets.is_empty():
		root.emit_signal("user_message", "No cutouts to commit", 1)
		return false
	apply_pending_cuts()
	# Commit must evaluate subtraction. The optional face-material bake path
	# triangulates positive faces independently and cannot consume cutters.
	var bake_succeeded: bool = await root.bake(false, true, 0, 0, true)
	if bake_succeeded:
		_prepared_commit_cutters = commit_targets
		return true
	_restore_pending_after_failed_commit(pending_targets)
	root._log("Commit cuts cancelled: bake failed; cutters were preserved")
	return false


func finalize_commit_cuts() -> void:
	var targets := _prepared_commit_cutters.duplicate()
	_prepared_commit_cutters.clear()
	_clear_applied_cuts(targets)


func commit_cuts() -> bool:
	if not await prepare_commit_cuts():
		return false
	finalize_commit_cuts()
	return true


func _restore_pending_after_failed_commit(pending_targets: Array) -> void:
	for target in pending_targets:
		if (
			not is_instance_valid(target)
			or target.get_parent() != root.draft_brushes_node
			or not _is_subtract_brush(target)
		):
			continue
		root.draft_brushes_node.remove_child(target)
		root.pending_node.add_child(target)
		_set_container_role(target, ROLE_PENDING)
		target.set_meta("pending_subtract", true)
		_apply_brush_material(target, _make_pending_cut_material())
		root._assign_owner(target)


var _prepared_commit_cutters: Array = []


func _clear_applied_cuts(targets: Array) -> void:
	if not root.draft_brushes_node:
		return
	for child in targets:
		if (
			is_instance_valid(child)
			and child.get_parent() == root.draft_brushes_node
			and child is DraftBrush
			and _is_subtract_brush(child)
		):
			var bid = str((child as DraftBrush).brush_id)
			if bid != "":
				_brush_cache.erase(bid)
			_brush_count = max(0, _brush_count - 1)
			if root.commit_freeze:
				_stash_committed_cut(child)
			else:
				_legacy_manager_remove(child)
				# Detach before returning so post-action snapshots and a scene
				# save in this frame cannot capture a cutter already committed.
				root.draft_brushes_node.remove_child(child)
				child.queue_free()


func _stash_committed_cut(brush: DraftBrush) -> void:
	if not root.committed_node:
		return
	_legacy_manager_remove(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	root.committed_node.add_child(brush)
	_set_container_role(brush, ROLE_COMMITTED)
	brush.visible = false
	brush.set_meta("committed_cut", true)
	root._assign_owner(brush)


func restore_committed_cuts() -> void:
	if not HFValidation.has_nodes(root, ["committed_node", "draft_brushes_node"]):
		return
	var restored = 0
	for child in root.committed_node.get_children():
		if child is DraftBrush:
			root.committed_node.remove_child(child)
			root.draft_brushes_node.add_child(child)
			_set_container_role(child, ROLE_DRAFT)
			child.visible = true
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
			_apply_brush_material(
				child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true)
			)
			child.set_meta("committed_cut", false)
			root._assign_owner(child)
			_legacy_manager_add(child)
			restored += 1
	if root.draft_brushes_node:
		root.draft_brushes_node.visible = true
	if root.pending_node:
		root.pending_node.visible = true
	if restored > 0:
		reconcile_external_structure()
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
	# The records describe geometry that has just gone. Keeping them would leave
	# orphans in the next save and in every undo snapshot after this one.
	# Restoring a state puts the records for that state back afterwards, and
	# deleting a single generated piece still goes nowhere near here, because that
	# record is what warns about the gap and rebuilds it.
	if root.generator_system:
		root.generator_system.clear()
	_clear_preview()
	clear_pending_cuts()
	_clear_committed_cuts()
	root.clear_baked_geometry()


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
		var draft := brush as DraftBrush
		if draft.material_override == mat:
			return
		draft.material_override = mat
		_tag_brush_node_dirty(draft)
		return
	brush.set("material_override", mat)
	brush.set("material", mat)
	_tag_brush_node_dirty(brush)


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
		var old_size := draft.size
		var old_pos := draft.global_position
		var normalized_size := DraftBrush.normalized_size_for_shape(draft.shape, size)
		if old_size.is_equal_approx(normalized_size) and old_pos.is_equal_approx(position):
			return
		draft.size = normalized_size
		draft.global_position = position
		if root.texture_lock and not draft.faces.is_empty():
			_adjust_face_uvs_for_transform(draft, old_size, draft.size, old_pos, position)
			draft.rebuild_preview()
		_tag_brush_node_dirty(draft)


func _tag_brush_node_dirty(brush: Node) -> void:
	if not brush or not root.has_method("tag_brush_dirty"):
		return
	var brush_id := ""
	if brush is DraftBrush:
		brush_id = str((brush as DraftBrush).brush_id)
	if brush_id == "" and brush.has_meta("brush_id"):
		brush_id = str(brush.get_meta("brush_id"))
	if brush_id != "":
		root.tag_brush_dirty(brush_id)


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
		var old_uv_scale: Vector2 = face.uv_scale
		var old_uv_offset: Vector2 = face.uv_offset
		face.adjust_uvs_for_transform(pos_delta, size_ratio)
		if (
			not face.uv_scale.is_equal_approx(old_uv_scale)
			or not face.uv_offset.is_equal_approx(old_uv_offset)
		):
			face.custom_uvs = PackedVector2Array()


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
	return pick_node_from_ray(
		camera.project_ray_origin(mouse_pos),
		camera.project_ray_normal(mouse_pos),
		include_entities,
	)


## Ray-based core shared by viewport picking and focused editor tests.
func pick_node_from_ray(
	ray_origin: Vector3, ray_direction: Vector3, include_entities: bool = true
) -> Node:
	if not root.draft_brushes_node or ray_direction.is_zero_approx():
		return null
	var ray_dir := ray_direction.normalized()
	var closest: Node = null
	var best_t = INF
	var nodes = root._iter_pick_nodes()
	var brush_hit := pick_face_from_ray(ray_origin, ray_dir)
	if not brush_hit.is_empty():
		best_t = float(brush_hit.get("distance", INF))
		closest = brush_hit.get("brush") as Node
	if not include_entities:
		return closest
	for child in nodes:
		if (
			not (child is Node3D)
			or not root.is_entity_node(child)
			or not root._is_pick_visible(child)
		):
			continue
		var t_entity: float = root._entity_pick_distance(child as Node3D, ray_origin, ray_dir)
		if t_entity >= 0.0 and t_entity < best_t:
			best_t = t_entity
			closest = child
	return closest


func update_hover(camera: Camera3D, mouse_pos: Vector2, selected_nodes: Array = []) -> void:
	if not root.hover_highlight or not camera:
		return
	var brush = pick_brush(camera, mouse_pos, false)
	if brush and brush is DraftBrush:
		if should_suppress_hover(brush, selected_nodes):
			root.hover_highlight.visible = false
			return
		var mesh_inst: MeshInstance3D = brush.mesh_instance
		if not mesh_inst:
			root.hover_highlight.visible = false
			return
		var mesh_id := mesh_inst.mesh.get_instance_id() if mesh_inst.mesh else 0
		var outline_key := (
			"%d:%d:%s:%d" % [brush.get_instance_id(), brush.shape, brush.size, mesh_id]
		)
		if outline_key != _hover_outline_key:
			root.hover_highlight.mesh = HFOutlineUtil.line_mesh(brush.get_editor_outline_lines())
			_hover_outline_key = outline_key
		root.hover_highlight.visible = true
		root.hover_highlight.global_transform = brush.global_transform
	else:
		root.hover_highlight.visible = false


static func should_suppress_hover(candidate: Node, selected_nodes: Array) -> bool:
	return candidate != null and selected_nodes.has(candidate)


func clear_hover() -> void:
	if root.hover_highlight:
		root.hover_highlight.visible = false


# ---------------------------------------------------------------------------
# Face selection
# ---------------------------------------------------------------------------


func pick_face(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	if not camera:
		return {}
	return pick_face_from_ray(
		camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos)
	)


## Ray-based face picker that applies the same visibility rules as object picks.
##
## The in-progress drag preview is deliberately not a target. It is parented
## under draft_brushes_node the moment a drag starts and stands a full grid step
## tall, and draft brushes carry no physics body, so `_raycast` reaches this
## fallback for every placement ray. Left in, a drag heading away from the
## camera meets the preview's own roof before the construction plane: the hit
## sits nearer the eye, the box pulls back off the cursor, the next ray misses
## it and the box springs out again — one edge twitching for as long as the
## mouse moves. The snap system excludes it for the same reason.
func pick_face_from_ray(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	if ray_direction.is_zero_approx():
		return {}
	var ray_dir := ray_direction.normalized()
	var preview = root.preview_brush
	var brushes: Array = []
	for node in root._iter_pick_nodes():
		if node == preview:
			continue
		if (
			node is DraftBrush
			and is_brush_node(node)
			and root._is_pick_visible(node)
			and root._is_pick_visible((node as DraftBrush).mesh_instance)
		):
			var mesh_inst: MeshInstance3D = (node as DraftBrush).mesh_instance
			if root._visual_pick_distance(mesh_inst, ray_origin, ray_dir) >= 0.0:
				brushes.append(node)
	return FaceSelector.intersect_brushes(brushes, ray_origin, ray_dir)


func select_face_at_screen(
	camera: Camera3D, mouse_pos: Vector2, additive: bool, toggle: bool = false
) -> bool:
	var hit = pick_face(camera, mouse_pos)
	if hit.is_empty():
		if not additive:
			clear_face_selection()
		return false
	var brush = hit.get("brush", null)
	var face_idx = int(hit.get("face_idx", -1))
	if brush and face_idx >= 0:
		toggle_face_selection(brush, face_idx, additive, toggle)
		return true
	return false


func toggle_face_selection(
	brush: DraftBrush, face_idx: int, additive: bool, toggle: bool = true
) -> void:
	if not brush:
		return
	if not additive:
		root.face_selection.clear()
	var key = face_key(brush)
	var indices: Array = root.face_selection.get(key, [])
	var idx = indices.find(face_idx)
	if idx >= 0 and toggle:
		indices.remove_at(idx)
	elif idx < 0:
		indices.append(face_idx)
	if indices.is_empty():
		root.face_selection.erase(key)
	else:
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
		var changed := false
		for idx in indices:
			var face_idx := int(idx)
			typed.append(face_idx)
			if (
				face_idx >= 0
				and face_idx < brush.faces.size()
				and brush.faces[face_idx].material_idx != material_index
			):
				changed = true
		brush.assign_material_to_faces(material_index, typed)
		if changed:
			_tag_brush_node_dirty(brush)
		count += typed.size()
	return count


func _apply_face_selection() -> void:
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var key = face_key(brush)
		var indices: Array = root.face_selection.get(key, [])
		brush.set_selected_faces(PackedInt32Array(indices))


## The key a brush is filed under in face_selection. Takes Node rather than
## DraftBrush because selection filters see whatever the editor hands them.
static func face_key(brush: Node) -> String:
	if brush == null:
		return ""
	if brush is DraftBrush and (brush as DraftBrush).brush_id != "":
		return (brush as DraftBrush).brush_id
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
# Shape guards for box-only operations
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Pre-validation (check preconditions without performing the operation)
# ---------------------------------------------------------------------------


func can_hollow_brush(brush_id: String, wall_thickness: float) -> HFOpResult:
	if brush_id == "":
		return HFOpResult.fail("Hollow: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return HFOpResult.fail("Hollow: brush not found")
	return _plan_hollow(brush as DraftBrush, wall_thickness)["result"]


func can_clip_brush(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	if brush_id == "":
		return HFOpResult.fail("Clip: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return HFOpResult.fail("Clip: brush not found")
	var draft := brush as DraftBrush
	var bounds := world_bounds_of(draft)
	var axis_index := clampi(axis, 0, 2)
	var brush_min: float = bounds.position[axis_index]
	var brush_max: float = bounds.position[axis_index] + bounds.size[axis_index]
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


## Hollow a brush into walls of the given thickness.
##
## A hollow brush is the original with its own faces pushed inward carved out of
## it, so this is the same progressive remainder carve uses, with the brush
## supplying its own planes. One face gives one wall, which means a box gives six
## and a cylinder gives a tube.
## Shell a solid into walls, and remember the solid so it can be shelled again.
##
## `hollow_id` is passed only by `update_hollow()`, which is re-shelling a hollow
## that already exists and has to keep its identity across the rebuild the way an
## array keeps its own.
func hollow_brush_by_id(
	brush_id: String, wall_thickness: float, hollow_id: String = ""
) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Hollow: no brush ID provided")
	if root.has_method("tag_full_reconcile"):
		root.tag_full_reconcile()
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Hollow: brush not found")
	var draft := brush as DraftBrush
	var plan: Dictionary = _plan_hollow(draft, wall_thickness)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		return _op_fail(check.message, check.fix_hint)

	var infos: Array = []
	for wall_faces in plan["walls"]:
		infos.append(_piece_info_from_faces(draft, wall_faces))
	# What the solid was, taken before the solid stops existing. This is the whole
	# of what makes a hollow live: without the original there is nothing to shell
	# again at a different thickness.
	var source_info: Dictionary = get_brush_info_from_node(draft)
	var result: HFOpResult = _replace_brush_with_pieces(draft, brush_id, infos, "Hollow", "walls")
	if result.ok:
		_record_hollow(source_info, wall_thickness, infos, hollow_id)
	return result


## Work out the walls a hollow would produce, and whether it can happen at all.
##
## Returns `{"result": HFOpResult, "walls": Array}`. Validation falls out of the
## geometry: if the inset planes leave no interior, they crossed each other and the
## wall thickness is too large for this brush. That is exact for any shape, where
## comparing twice the thickness against the smallest dimension only ever meant
## anything for a box.
func _plan_hollow(draft: DraftBrush, wall_thickness: float) -> Dictionary:
	var empty: Array = []
	if wall_thickness <= 0.0:
		return {
			"result":
			HFOpResult.fail(
				"Hollow: wall thickness must be greater than zero",
				"Enter a positive wall thickness"
			),
			"walls": empty
		}
	_ensure_faces(draft)
	var faces: Array = draft.get_faces()
	if faces.size() < 4:
		return {
			"result":
			HFOpResult.fail(
				"Hollow: brush has no usable geometry", "Rebuild or redraw the brush and try again"
			),
			"walls": empty
		}

	var interior: Vector3 = HFConvexClip.interior_point(faces)
	var budget: Dictionary = HFConvexClip.boolean_plane_budget(faces, interior)
	if not budget["ok"]:
		return {
			"result":
			(
				HFOpResult
				. fail(
					(
						"Hollow: this brush has %d distinct faces, so it would become %d walls"
						% [budget["planes"], budget["planes"]]
					),
					(
						"Hollow works on brushes with up to %d faces. A sphere or capsule has thousands."
						% HFConvexClip.MAX_BOOLEAN_PLANES
					)
				)
			),
			"walls": empty
		}
	var inset_planes: Array = []
	for plane in HFConvexClip.outward_planes(faces, interior):
		inset_planes.append(HFConvexClip.offset_plane(plane, -wall_thickness))
	if inset_planes.is_empty():
		return {"result": HFOpResult.fail("Hollow: brush has no usable geometry"), "walls": empty}

	var shelled: Dictionary = HFConvexClip.progressive_remainder(faces, inset_planes)
	var walls: Array = shelled["pieces"]
	var void_faces: Array = shelled["remainder"]
	if not shelled["separated"] or void_faces.is_empty() or walls.is_empty():
		var largest := _largest_inradius(faces)
		return {
			"result":
			HFOpResult.fail(
				"Wall thickness %.1f leaves no room inside the brush" % wall_thickness,
				"Use a thickness less than %.1f" % largest
			),
			"walls": empty
		}
	return {"result": HFOpResult.success("%d walls" % walls.size()), "walls": walls}


## The largest wall thickness that still leaves an interior: the distance from the
## brush's own centre to its nearest face.
func _largest_inradius(faces: Array) -> float:
	var centre: Vector3 = HFConvexClip.interior_point(faces)
	var nearest := INF
	for plane in HFConvexClip.outward_planes(faces, centre):
		nearest = minf(nearest, absf(plane.distance_to(centre)))
	return 0.0 if is_inf(nearest) else nearest


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
			merged.set_brush_entity_class(src_bec)

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
				var new_position: Vector3 = origin
				new_position.y = snapped(new_y, snap) if snap > 0.0 else new_y
				set_brush_transform_by_id(str(brush_id), draft.size, new_position)
		else:
			var hit_pos: Vector3 = result["position"]
			var new_y = hit_pos.y - half_y * direction
			var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
			var new_position: Vector3 = origin
			new_position.y = snapped(new_y, snap) if snap > 0.0 else new_y
			set_brush_transform_by_id(str(brush_id), draft.size, new_position)


# ---------------------------------------------------------------------------
# Clip (Split Brush)
# ---------------------------------------------------------------------------


## Split a brush along a world-space plane.
##
## Works on any convex brush at any rotation: the plane is taken into the brush's
## own frame and the split runs there, so both pieces inherit the original
## transform untouched and rotation is carried rather than handled.
func clip_brush_by_plane(brush_id: String, plane: Plane) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Clip: no brush ID provided")
	if root.has_method("tag_full_reconcile"):
		root.tag_full_reconcile()
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Clip: brush not found")
	var draft := brush as DraftBrush
	if plane.normal.length_squared() < 0.5:
		return _op_fail("Clip: the cut plane has no direction")
	_ensure_faces(draft)
	var faces: Array = draft.get_faces()
	if faces.size() < 4:
		return _op_fail(
			"Clip: brush has no usable geometry", "Rebuild or redraw the brush and try again"
		)

	var xform := draft.global_transform
	var local_plane := xform.affine_inverse() * plane
	var halves: Dictionary = HFConvexClip.split(faces, local_plane)
	var front: Array = halves["front"]
	var back: Array = halves["back"]
	if front.is_empty() or back.is_empty():
		return _op_fail(
			"Clip: the cut plane does not pass through the brush",
			"Move the split point inside the brush"
		)

	var infos: Array = [_piece_info_from_faces(draft, front), _piece_info_from_faces(draft, back)]
	return _replace_brush_with_pieces(draft, brush_id, infos, "Clip")


## Split a brush along an axis-aligned plane.
## axis: 0=X, 1=Y, 2=Z.  split_pos: world coordinate on that axis.
func clip_brush_by_id(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Clip: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Clip: brush not found")
	var draft := brush as DraftBrush
	var axis_index := clampi(axis, 0, 2)
	var bounds := world_bounds_of(draft)
	var brush_min: float = bounds.position[axis_index]
	var brush_max: float = bounds.position[axis_index] + bounds.size[axis_index]

	# Snap the split position to the grid
	var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
	if snap > 0.0:
		split_pos = snapped(split_pos, snap)

	# Reject if split is outside or on the edge of the brush
	var margin = snap if snap > 0.0 else 0.01
	if split_pos <= brush_min + margin or split_pos >= brush_max - margin:
		var axis_name = ["X", "Y", "Z"][axis_index]
		return _op_fail(
			"Clip: split position %.1f is outside brush bounds on %s axis" % [split_pos, axis_name],
			"Click inside the brush face to pick a valid split point"
		)

	var normal := HFConvexClip.axis_normal(axis_index)
	return clip_brush_by_plane(brush_id, Plane(normal, split_pos))


## Split a brush along the plane of one face of another (or the same) brush.
##
## With rotation available this is the cheapest route to an angled cut: pick the
## face whose plane you want, and cut along it.
func clip_brush_to_face_plane(
	brush_id: String, source_brush_id: String, face_index: int
) -> HFOpResult:
	var plane := face_world_plane(source_brush_id, face_index)
	if plane.normal.length_squared() < 0.5:
		return _op_fail(
			"Clip: no usable reference face selected", "Select a face to cut along, then clip"
		)
	return clip_brush_by_plane(brush_id, plane)


## The world-space plane a brush face lies in. A zero normal means there is no
## usable face there.
##
## Read once and passed around as a plain Plane so a cut survives its reference
## brush: the reference can itself be one of the targets, and then it no longer
## exists by the time a redo replays the cut.
func face_world_plane(source_brush_id: String, face_index: int) -> Plane:
	var source = _find_brush_by_id(source_brush_id)
	if not source or not (source is DraftBrush):
		return Plane()
	var source_draft := source as DraftBrush
	_ensure_faces(source_draft)
	var faces: Array = source_draft.get_faces()
	if face_index < 0 or face_index >= faces.size():
		return Plane()
	var face: FaceData = faces[face_index]
	if face == null or face.local_verts.size() < 3:
		return Plane()
	var xform := source_draft.global_transform
	var world_normal: Vector3 = (xform.basis * face.normal).normalized()
	if world_normal.length_squared() < 0.5:
		return Plane()
	var world_point: Vector3 = xform * face.local_verts[0]
	return Plane(world_normal, world_normal.dot(world_point))


## True when the plane actually passes through the brush, so a clip would produce
## two pieces. Asked before an undo action is opened, so a cut that would do
## nothing never reaches the history.
func plane_splits_brush(brush_id: String, plane: Plane) -> bool:
	if brush_id == "" or plane.normal.length_squared() < 0.5:
		return false
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return false
	var draft := brush as DraftBrush
	_ensure_faces(draft)
	var faces: Array = draft.get_faces()
	if faces.size() < 4:
		return false
	var local_plane := draft.global_transform.affine_inverse() * plane
	var halves: Dictionary = HFConvexClip.split(faces, local_plane)
	return not halves["front"].is_empty() and not halves["back"].is_empty()


## Cut every named brush along one plane. Returns how many were cut.
##
## One call so the whole batch is a single undo action: a multi-brush cut that
## undid a piece at a time would leave the level half cut.
func clip_brushes_by_plane(brush_ids: Array, plane: Plane) -> int:
	var cut := 0
	for brush_id in brush_ids:
		if clip_brush_by_plane(str(brush_id), plane).ok:
			cut += 1
	return cut


# ---------------------------------------------------------------------------
# Shared cutting helpers (clip and carve)
# ---------------------------------------------------------------------------


## Make sure a brush has its face data before anything reads geometry off it.
func _ensure_faces(draft: DraftBrush) -> void:
	if draft.get_faces().is_empty():
		draft.rebuild_preview()


## World bounds measured through the brush's own transform, so a rotated or
## non-box brush reports the extent it actually occupies rather than
## `global_position` plus half its nominal size.
func world_bounds_of(draft: DraftBrush) -> AABB:
	_ensure_faces(draft)
	var xform := draft.global_transform
	var bounds := AABB()
	var seeded := false
	for face in draft.get_faces():
		var data: FaceData = face as FaceData
		if data == null:
			continue
		for vertex in data.local_verts:
			var world_point: Vector3 = xform * vertex
			if seeded:
				bounds = bounds.expand(world_point)
			else:
				bounds = AABB(world_point, Vector3.ZERO)
				seeded = true
	if seeded:
		return bounds
	var half: Vector3 = draft.size * 0.5
	return AABB(draft.global_position - half, draft.size)


static func _local_bounds_of_faces(faces: Array) -> AABB:
	var bounds := AABB()
	var seeded := false
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null:
			continue
		for vertex in data.local_verts:
			if seeded:
				bounds = bounds.expand(vertex)
			else:
				bounds = AABB(vertex, Vector3.ZERO)
				seeded = true
	return bounds


## Move faces so the piece's own centre becomes its origin, then serialize them.
## Two pieces left sharing the original's origin would both sit under the same
## gizmo, which makes them awkward to tell apart and to select.
static func _serialize_shifted_faces(faces: Array, offset: Vector3) -> Array:
	var out: Array = []
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		if not offset.is_zero_approx():
			var moved := PackedVector3Array()
			for vertex in data.local_verts:
				moved.append(vertex + offset)
			data.local_verts = moved
			data.ensure_geometry()
		out.append(data.to_dict())
	return out


## Describe one piece of a cut as brush info, inheriting the original's settings.
##
## A piece that is still an axis-aligned box in the brush's own frame is emitted
## as a BOX so it keeps its resize handles; anything else becomes CUSTOM with the
## split faces as its authoritative geometry.
## Describe one face set as brush info, placed by `placement` and centred on its
## own geometry.
##
## A piece that is still an axis-aligned box in the placing frame is emitted as a
## BOX so it keeps its resize handles; anything else becomes CUSTOM with the faces
## as its authoritative geometry.
func _face_set_info(faces: Array, placement: Transform3D) -> Dictionary:
	var described: Dictionary = HFConvexClip.is_axis_aligned_box(faces)
	var bounds := _local_bounds_of_faces(faces)
	var centre: Vector3 = described["center"] if not described.is_empty() else bounds.get_center()
	return {
		"shape": root.BrushShape.BOX if not described.is_empty() else root.BrushShape.CUSTOM,
		"size": described["size"] if not described.is_empty() else bounds.size,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": _next_brush_id(),
		"transform": Transform3D(placement.basis, placement * centre),
		"faces": _serialize_shifted_faces(faces, -centre),
	}


## Create one brush per generated face set. The entry point every generator uses.
func create_brushes_from_face_sets(
	face_sets: Array, placement: Transform3D, material: Material = null
) -> PackedStringArray:
	var created := PackedStringArray()
	for faces in face_sets:
		if (faces as Array).is_empty():
			continue
		var info := _face_set_info(faces, placement)
		if material:
			info["material"] = material
		if create_brush_from_info(info):
			created.append(str(info["brush_id"]))
	return created


func _piece_info_from_faces(draft: DraftBrush, faces: Array) -> Dictionary:
	var info := _face_set_info(faces, draft.global_transform)
	info["operation"] = draft.operation
	if draft.material_override:
		info["material"] = draft.material_override
	var entity_class := str(draft.get_meta("brush_entity_class", ""))
	if entity_class != "":
		info["brush_entity_class"] = entity_class
	var visgroups: PackedStringArray = draft.get_meta("visgroups", PackedStringArray())
	if not visgroups.is_empty():
		info["visgroups"] = Array(visgroups)
	var group_id := str(draft.get_meta("group_id", ""))
	if group_id != "":
		info["group_id"] = group_id
	return info


## Delete a brush and put the pieces of it back in its place.
##
## The first piece is treated as the continuation of the original and inherits its
## entity name and I/O wiring; the others are new geometry of the same class.
## Entity names have to stay unique, so they cannot simply be copied to both.
func _replace_brush_with_pieces(
	draft: DraftBrush,
	brush_id: String,
	infos: Array,
	op_name: String,
	piece_noun: String = "pieces"
) -> HFOpResult:
	var entity_name := str(draft.get_meta("entity_name", ""))
	var io_outputs: Array = draft.get_meta("entity_io_outputs", [])
	if entity_name != "" and not infos.is_empty():
		infos[0]["entity_name"] = entity_name
	if not io_outputs.is_empty() and not infos.is_empty():
		infos[0]["entity_io_outputs"] = io_outputs.duplicate(true)

	delete_brush_by_id(brush_id)

	var created := 0
	for info in infos:
		if create_brush_from_info(info):
			created += 1
	if created == 0:
		return _op_fail("%s: produced no geometry" % op_name)
	var message := "%s: %d %s" % [op_name, created, piece_noun]
	root._log(message)
	return HFOpResult.success(message)


func tie_brushes_to_entity(brush_ids: Array, entity_class: String) -> void:
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			brush.set_brush_entity_class(entity_class)
	root._log("Tied %d brushes as '%s'" % [brush_ids.size(), entity_class])


func untie_brushes_from_entity(brush_ids: Array) -> void:
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			brush.set_brush_entity_class("")
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
			var before := face.to_dict()
			_justify_face(face, mode, all_min, all_max)
			ref["brush"].rebuild_preview()
			if face.to_dict() != before:
				_tag_brush_node_dirty(ref["brush"])
	else:
		for ref in face_refs:
			var face: FaceData = ref["face"]
			face.ensure_custom_uvs()
			var before := face.to_dict()
			var uv_min := Vector2(INF, INF)
			var uv_max := Vector2(-INF, -INF)
			for uv in face.custom_uvs:
				uv_min.x = min(uv_min.x, uv.x)
				uv_min.y = min(uv_min.y, uv.y)
				uv_max.x = max(uv_max.x, uv.x)
				uv_max.y = max(uv_max.y, uv.y)
			_justify_face(face, mode, uv_min, uv_max)
			ref["brush"].rebuild_preview()
			if face.to_dict() != before:
				_tag_brush_node_dirty(ref["brush"])


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
# Hollow records
# ---------------------------------------------------------------------------

## hollow_id -> {hollow_id, thickness, source, wall_ids}
##
## `source` is the brush info of the solid the walls were shelled out of, which is
## the only thing here that could not be recovered from the walls themselves.
var _hollows: Dictionary = {}


func _record_hollow(
	source_info: Dictionary, thickness: float, wall_infos: Array, hollow_id: String = ""
) -> void:
	var record_id := hollow_id
	if record_id == "":
		record_id = "hol_%d" % Time.get_ticks_usec()
	var wall_ids := PackedStringArray()
	# Each wall stands at its own centroid rather than at the solid's origin, so
	# telling a room that has been dragged from walls moved one at a time needs
	# where each wall was put, not just which walls there are.
	var wall_transforms: Array = []
	# And the shape each one was made as, because a wall that has been resized,
	# retextured or painted since is a hand edit a re-shell would rebuild over, and
	# nothing else in the record can tell. Values only, so it survives being saved.
	var wall_shapes: Array = []
	for info in wall_infos:
		var wall_id := str(info.get("brush_id", ""))
		if wall_id == "":
			continue
		wall_ids.append(wall_id)
		wall_transforms.append(info.get("transform", Transform3D.IDENTITY))
		var wall = _brush_cache.get(wall_id)
		wall_shapes.append(HFDuplicator.shape_signature(wall))
		if is_instance_valid(wall):
			wall.set_meta("hollow_instance_of", record_id)
	if wall_ids.is_empty():
		return
	_hollows[record_id] = {
		"hollow_id": record_id,
		"thickness": thickness,
		"source": source_info.duplicate(true),
		"wall_ids": Array(wall_ids),
		"wall_transforms": wall_transforms,
		"wall_shapes": wall_shapes,
	}


## Shell the same solid again at a different thickness, keeping the same hollow.
##
## The solid is rebuilt and the new walls are planned on it *before* the old walls
## are touched, so a thickness this brush cannot take leaves the level exactly as
## it was rather than deleting the walls and failing to replace them.
func update_hollow(hollow_id: String, thickness: float) -> HFOpResult:
	if not _hollows.has(hollow_id):
		return _op_fail("Hollow: that hollow is no longer in the level")
	var record: Dictionary = _hollows[hollow_id]
	var source_info: Dictionary = (record["source"] as Dictionary).duplicate(true)
	source_info["brush_id"] = _next_brush_id()
	# A hollowed room dragged across the level rebuilds where it now stands.
	# Rebuilding it back where it was made is the surprise the structure records'
	# relocation vote exists to prevent, and the walls answer it without a vote:
	# every one of them was created at the solid's own transform, so they either
	# still agree on one placement or they have been edited individually.
	var placement: Variant = _hollow_placement(record)
	if placement != null:
		source_info["transform"] = placement
	var source = create_brush_from_info(source_info)
	if not is_instance_valid(source):
		return _op_fail("Hollow: the original solid could not be rebuilt")
	var source_id := str(source_info["brush_id"])
	var plan: Dictionary = _plan_hollow(source as DraftBrush, thickness)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		# Put the level back the way it was: the walls were never touched.
		delete_brush_by_id(source_id)
		return _op_fail(check.message, check.fix_hint)
	for wall_id in record["wall_ids"]:
		delete_brush_by_id(str(wall_id))
	_hollows.erase(hollow_id)
	return hollow_brush_by_id(source_id, thickness, hollow_id)


## Where the solid should be rebuilt, when every surviving wall agrees on the
## move it has been given.
##
## Answers with nothing when they disagree, which is walls moved one at a time —
## editing rather than relocating, so the placement stays where it was. Also
## nothing for a record written before wall placements were kept, which is what
## makes those records load and re-shell with no migration.
func _hollow_placement(record: Dictionary) -> Variant:
	var ids: Array = record.get("wall_ids", [])
	var placed: Array = record.get("wall_transforms", [])
	if placed.size() != ids.size() or ids.is_empty():
		return null
	var shared: Variant = null
	for i in ids.size():
		var wall = _brush_cache.get(str(ids[i]))
		if not is_instance_valid(wall):
			continue
		var was: Transform3D = placed[i]
		var delta: Transform3D = wall.global_transform * was.affine_inverse()
		if shared == null:
			shared = delta
		elif not HFTransformSystem.same_transform(shared, delta):
			return null
	if shared == null:
		return null
	var source_transform: Transform3D = (record["source"] as Dictionary).get(
		"transform", Transform3D.IDENTITY
	)
	return (shared as Transform3D) * source_transform


## How many walls a Re-hollow would rebuild over.
##
## A wall is a hand edit when it is no longer the shape it was made as, or when it
## is no longer where it was put. The two are read separately because they fail
## separately: a resized wall has not moved, and a dragged one is still its own
## shape.
##
## Movement is read against what a re-shell would actually do. When every wall
## agrees on one move the whole room has been relocated, `update_hollow()` rebuilds
## it where it now stands, and nothing is lost — so a relocation counts nothing.
## When they disagree the rebuild goes back to the recorded placement, and then any
## wall standing anywhere else is about to be moved back.
##
## Records written before either field answer "cannot tell" for that half rather
## than guessing, which is what lets an older level load and re-shell unmigrated.
func edited_hollow_walls(hollow_id: String) -> int:
	if not _hollows.has(hollow_id):
		return 0
	var record: Dictionary = _hollows[hollow_id]
	var ids: Array = record.get("wall_ids", [])
	var placed: Array = record.get("wall_transforms", [])
	var shapes: Array = record.get("wall_shapes", [])
	var placements_known: bool = placed.size() == ids.size() and not ids.is_empty()
	var relocated: bool = placements_known and _hollow_placement(record) != null
	var edited := 0
	for i in ids.size():
		var wall = _brush_cache.get(str(ids[i]))
		if not is_instance_valid(wall):
			continue
		if i < shapes.size() and str(shapes[i]) != "":
			if HFDuplicator.shape_signature(wall) != str(shapes[i]):
				edited += 1
				continue
		if not placements_known or relocated:
			continue
		var was: Transform3D = placed[i]
		if not HFTransformSystem.same_transform(wall.global_transform, was):
			edited += 1
	return edited


## Forget a hollow's record, leaving its walls as ordinary brushes.
func detach_hollow(hollow_id: String) -> bool:
	if not _hollows.has(hollow_id):
		return false
	for wall_id in _hollows[hollow_id]["wall_ids"]:
		var wall = _brush_cache.get(str(wall_id))
		if is_instance_valid(wall) and wall.has_meta("hollow_instance_of"):
			wall.remove_meta("hollow_instance_of")
	_hollows.erase(hollow_id)
	return true


func hollow_for_id(hollow_id: String) -> Variant:
	return _hollows.get(hollow_id, null)


## The hollow that owns the first brush in a selection that belongs to one.
func hollow_for_selection(brush_ids: Array) -> Variant:
	for brush_id in brush_ids:
		var brush = _brush_cache.get(str(brush_id))
		if not is_instance_valid(brush):
			continue
		var record_id := str(brush.get_meta("hollow_instance_of", ""))
		if record_id != "" and _hollows.has(record_id):
			return _hollows[record_id]
	return null


## Every hollow record, for state capture.
func capture_hollows() -> Array:
	var out: Array = []
	for hollow_id in _hollows:
		out.append((_hollows[hollow_id] as Dictionary).duplicate(true))
	return out


## Put the records back and re-tag the walls, which carry no tag of their own
## through a brush info.
func restore_hollows(records: Array) -> void:
	_hollows.clear()
	for entry in records:
		if not (entry is Dictionary):
			continue
		var record: Dictionary = (entry as Dictionary).duplicate(true)
		var hollow_id := str(record.get("hollow_id", ""))
		if hollow_id == "":
			continue
		_hollows[hollow_id] = record
		for wall_id in record.get("wall_ids", []):
			var wall = _brush_cache.get(str(wall_id))
			if is_instance_valid(wall):
				wall.set_meta("hollow_instance_of", hollow_id)


# ---------------------------------------------------------------------------
# Duplicator / Instanced Geometry
# ---------------------------------------------------------------------------

var _duplicators: Dictionary = {}  # duplicator_id -> HFDuplicator


func create_duplicate_array(
	brush_ids: PackedStringArray, p_count: int, p_offset: Vector3
) -> Variant:
	# Asked before _new_duplicator_for, which retires whatever array already owns
	# these sources and takes its copies with it. A refusal must not cost the user
	# the array they already had.
	if not HFDuplicator.can_generate(p_count, brush_ids.size()).ok:
		return null
	var dup := _new_duplicator_for(brush_ids)
	if not dup.generate(self, p_count, p_offset):
		return null
	_duplicators[dup.duplicator_id] = dup
	return dup


## Ring of copies rotated `step_degrees` apart about `pivot`. Pass
## `360.0 / (count + 1)` as the step to close a full circle.
func create_radial_array(
	brush_ids: PackedStringArray,
	p_count: int,
	axis_index: int,
	step_degrees: float,
	pivot: Vector3,
	rise: float = 0.0
) -> Variant:
	if not HFDuplicator.can_generate(p_count, brush_ids.size()).ok:
		return null
	var dup := _new_duplicator_for(brush_ids)
	if not dup.generate_radial(self, p_count, axis_index, step_degrees, pivot, rise):
		return null
	_duplicators[dup.duplicator_id] = dup
	return dup


## Lattice of copies. `counts` includes the source cell on each axis.
func create_grid_array(brush_ids: PackedStringArray, counts: Vector3i, spacing: Vector3) -> Variant:
	if not HFDuplicator.can_generate(HFDuplicator.grid_copy_count(counts), brush_ids.size()).ok:
		return null
	var dup := _new_duplicator_for(brush_ids)
	if not dup.generate_grid(self, counts, spacing):
		return null
	_duplicators[dup.duplicator_id] = dup
	return dup


## Retire any duplicator that already owns these source brushes, then hand back a
## fresh one bound to them. One source set owns at most one array at a time.
func _new_duplicator_for(brush_ids: PackedStringArray) -> HFDuplicator:
	for bid in brush_ids:
		var brush = _brush_cache.get(bid)
		if brush and brush.has_meta("duplicator_id"):
			var old_id: String = str(brush.get_meta("duplicator_id"))
			if old_id != "" and _duplicators.has(old_id):
				_duplicators[old_id].clear_instances(self)
				_duplicators.erase(old_id)
	var dup := HFDuplicator.new()
	dup.source_brush_ids = brush_ids
	return dup


func remove_duplicate_array(duplicator_id: String) -> void:
	if not _duplicators.has(duplicator_id):
		return
	var dup: HFDuplicator = _duplicators[duplicator_id]
	dup.clear_instances(self)
	_duplicators.erase(duplicator_id)


## Rebuild an existing array from new numbers, keeping the same array.
##
## The alternative was to delete the copies and make a second array, which loses
## the identity the section is holding on to and leaves the level with a record
## nobody can reach.
func update_duplicate_array(duplicator_id: String, mode: int, params: Dictionary) -> bool:
	if not _duplicators.has(duplicator_id):
		return false
	var dup: HFDuplicator = _duplicators[duplicator_id]
	# A layout that cannot be built is refused with the array untouched, so the
	# user can correct the number they typed. Nothing is torn down and the record
	# stays reachable.
	if not (
		HFDuplicator
		. can_generate(dup.requested_copy_count(mode, params), dup.source_brush_ids.size())
		. ok
	):
		return false
	if not dup.regenerate(self, mode, params):
		# Past that check, a rebuild that produced nothing means the sources
		# themselves are gone, so the record no longer describes anything that
		# could exist.
		_duplicators.erase(duplicator_id)
		return false
	return true


## Forget an array's record, leaving its copies as ordinary brushes.
func detach_duplicate_array(duplicator_id: String) -> bool:
	if not _duplicators.has(duplicator_id):
		return false
	var dup: HFDuplicator = _duplicators[duplicator_id]
	dup.detach(self)
	_duplicators.erase(duplicator_id)
	return true


func duplicator_for_id(duplicator_id: String) -> Variant:
	return _duplicators.get(duplicator_id, null)


## The array a brush belongs to, whether it is one of the sources or one of the
## copies.
##
## A copy is what you click on: the sources are usually buried under the ring or
## the lattice they seeded. Resolving only from the source is why the array
## controls could never be brought back up on an array you could actually see.
func get_duplicator_for_brush(brush_id: String) -> Variant:
	var brush = _brush_cache.get(brush_id)
	if not is_instance_valid(brush):
		brush = find_brush_by_id(brush_id)
	if not is_instance_valid(brush):
		return null
	var dup_id: String = str(brush.get_meta("duplicator_id", ""))
	if dup_id == "":
		dup_id = str(brush.get_meta("duplicator_instance_of", ""))
	if dup_id == "" or not _duplicators.has(dup_id):
		return null
	return _duplicators[dup_id]


## The array that owns the first brush in a selection that belongs to one.
##
## The companion to `generator_for_selection`, and deliberately the same shape:
## the two sections answer a selection the same way.
func duplicator_for_selection(brush_ids: Array) -> Variant:
	for brush_id in brush_ids:
		var dup = get_duplicator_for_brush(str(brush_id))
		if dup != null:
			return dup
	return null


# ---------------------------------------------------------------------------
# Reference cleanup on deletion
# ---------------------------------------------------------------------------


func _cleanup_brush_references(brush: Node) -> void:
	if not brush:
		return
	# Strip group membership
	var group_id := str(brush.get_meta("group_id", ""))
	if group_id != "":
		brush.set_meta("group_id", "")
		if root.get("visgroup_system") and root.visgroup_system.has_method("_cleanup_empty_group"):
			root.visgroup_system._cleanup_empty_group(group_id)
	# Strip visgroup membership
	var vgs: PackedStringArray = brush.get_meta("visgroups", PackedStringArray())
	if not vgs.is_empty():
		brush.set_meta("visgroups", PackedStringArray())
	# Clean up entity I/O connections targeting this brush by name
	# By both of its addresses: a brush entity carries an authored name as well as
	# its node name, and an output can be aimed at either.
	var brush_name := brush.name
	if brush_name != "" and root.get("entity_system"):
		var removed_count: int = root.entity_system.cleanup_connections_for_deleted(brush)
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
