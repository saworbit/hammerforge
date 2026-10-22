@tool
extends RefCounted
class_name HFBrushSystem

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const FaceSelector = preload("../face_selector.gd")
const FaceData = preload("../face_data.gd")
const HFValidation = preload("../hf_validation.gd")
const HFOutlineUtil = preload("../hf_outline_util.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")
const HFBrushEntity = preload("../hf_brush_entity.gd")
const HFBakeSplit = preload("../hf_bake_split.gd")
const HFGridSystem = preload("hf_grid_system.gd")
const HFUVWrap = preload("../hf_uv_wrap.gd")
@warning_ignore_restore("shadowed_global_identifier")
const CONTAINER_ROLE_META := &"hf_container_role"
const ROLE_DRAFT := "draft"
const ROLE_PENDING := "pending"
const ROLE_COMMITTED := "committed"
## How far a pick grows a brush's world box before asking the ray, so a ray
## along an edge is not lost to rounding. The exact tests follow, so a looser
## box costs a test and never a wrong pick.
const PICK_BOUNDS_SLACK := 0.01

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

	var snapped_pos: Vector3 = root.grid_system.snap_draw_hit(hit)
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
	brush.global_position = snapped_pos + Vector3(0, size.y * 0.5, 0)
	_legacy_manager_add(brush)
	root._record_last_brush(snapped_pos)
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
##
## A brush `built_from_faces` keeps a thin side as it is. Its faces are its
## geometry and its size only describes them, so the floor built nothing: it made
## the size lie, a Path trim 0.05 tall warned once for every piece, and a nudge
## with Texture Lock on read the floor as a stretch and halved the texture on the
## sides of a piece Apply Rotation and Scale had left 0.05 thick (#1592). A zero
## or negative side is still put right, as no faces have one.
static func _usable_size(raw, built_from_faces: bool = false) -> Vector3:
	if not (raw is Vector3):
		return Vector3(MIN_BRUSH_EXTENT, MIN_BRUSH_EXTENT, MIN_BRUSH_EXTENT)
	var size: Vector3 = raw
	var fixed := size.abs()
	for axis in 3:
		if fixed[axis] < MIN_BRUSH_EXTENT and not (built_from_faces and fixed[axis] > 0.0):
			fixed[axis] = MIN_BRUSH_EXTENT
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


## Whether a brush of `shape` with `faces` is built from those faces rather than
## from its size, which is when `DraftBrush._update_visuals()` keeps them. A
## CUSTOM brush with none builds a box from its size.
static func _built_from_faces(shape: int, faces) -> bool:
	return shape == DraftBrush.BrushShape.CUSTOM and faces is Array and not faces.is_empty()


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
	var size = _usable_size(raw_size, _built_from_faces(int(shape), info.get("faces")))
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
		brush.set_pending_cut(false)
		root._assign_owner(brush)
	elif operation == CSGShape3D.OPERATION_SUBTRACTION and pending:
		_add_pending_cut(brush)
	else:
		_add_brush_to_draft(brush)
	# After the brush is in the tree, so Godot resolves a collision against its
	# real siblings. clear_brushes() detaches with remove_child() before it
	# queues the old nodes, so a restore is not competing with a name the freed
	# node still holds.
	var restored_name := str(info.get("name", ""))
	if restored_name != "":
		brush.name = restored_name
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
	if info.get("draw_origin") is Vector3:
		root._record_last_brush(info["draw_origin"])
	# Not `info.get("brush_id", _next_brush_id())`. GDScript evaluates that default
	# whether or not the key is there, so every brush a restore put back minted an
	# id it then threw away and left `_brush_id_counter` one higher than the level
	# it had just rebuilt. `restore_state()` hides it by setting the counter from
	# the snapshot afterwards; a scoped step has no counter to set.
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		brush_id = _next_brush_id()
	brush.brush_id = str(brush_id)
	brush.set_meta("brush_id", brush_id)
	_register_brush_id(str(brush_id), brush)
	if restored_name == "":
		brush.name = _readable_name(int(shape), str(brush_id))
	if info.has("faces"):
		brush.apply_serialized_faces(info.get("faces", []))
	# This is the single door for undo restore, duplication, prefab instancing,
	# .map import and .hflevel load, so it is the one place a stored transform
	# becomes a live brush. A stored mirror bakes inside out and a stored mirrored
	# cutter adds instead of cutting, so take the mirror off here rather than
	# leaving every consumer downstream to cope with it (#749). Faces first: the
	# fold moves each face's appearance to the face that takes its place.
	if brush.global_transform.basis.determinant() < 0.0:
		_transform_system().normalize_handedness(brush)
	if info.has("visgroups"):
		var vgs = PackedStringArray()
		for v in info.get("visgroups", []):
			vgs.append(str(v))
		brush.set_meta("visgroups", vgs)
		# A piece of a hidden brush, or one an undo puts back, is hidden from the
		# start, not once something next refreshes the visgroups (#1710).
		var visgroups = root.get("visgroup_system")
		if not committed and visgroups != null and visgroups.is_hidden_by_visgroups(brush):
			brush.visible = false
	if info.has("group_id") and str(info["group_id"]) != "":
		brush.set_meta("group_id", str(info["group_id"]))
	# Its class, wires, tie, name and properties: a door's speed and a trigger's
	# target are what a `.map` said the entity is, carried so an export can write
	# them back (#663).
	HFBrushEntity.give(brush, info)
	# How it casts shadows and how fine its lightmap is, when it chose (#1444, #1438).
	HFBakeSplit.give(brush, info)
	root.tag_brush_dirty(str(brush_id))
	if root.has_method("_emit_or_batch"):
		root._emit_or_batch("brush_added", [str(brush_id)])
	elif root.has_signal("brush_added"):
		root.brush_added.emit(str(brush_id))
	return brush


## Give the info of a brush about to be made from nothing the level's Active
## Material, as its whole-brush material (#1405). The one rule a Draw, a Polygon,
## a Path and a dropped preset share, asked before the info goes into the undo
## step so a redo makes the same brush. A Cutout keeps the cut look, and an info
## that names a material already, as an Extrude's does, keeps that one.
func give_active_material(info: Dictionary) -> void:
	var mat: Variant = root.get("active_material") if is_instance_valid(root) else null
	if not (mat is Material) or info.has("material"):
		return
	if int(info.get("operation", CSGShape3D.OPERATION_UNION)) == CSGShape3D.OPERATION_SUBTRACTION:
		return
	info["material"] = mat


## The level's transform system, or a bare one in a running game, where the
## level builds only its runtime core and a `.hflevel` load still makes brushes.
func _transform_system() -> HFTransformSystem:
	var existing = root.get("transform_system") if is_instance_valid(root) else null
	if existing is HFTransformSystem:
		return existing
	return HFTransformSystem.new(root)


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
			# The dock's surface panel is still pointed at a face that just went
			# away.
			_announce_face_selection_change()
	_brush_count = max(0, _brush_count - 1)
	_legacy_manager_remove(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	if free:
		brush.queue_free()
	if removed_id != "":
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
	# `is_zero_approx()` is a magnitude test, and a non-finite offset is not
	# approximately zero, so it used to pass. The offset comes from the dock's
	# transform fields and from the arrow-key nudge, which uses `grid_snap` — so
	# one bad number sends the whole selection to a position nothing can reach
	# again: no AABB, nothing drawn to click, and the save keeps it.
	if not offset.is_finite():
		HFLog.warn("HFBrushSystem: nudge offset %s is not an offset" % str(offset))
		return
	if offset.is_zero_approx():
		return
	for brush_id in brush_ids:
		var brush_key := str(brush_id)
		var brush = _find_brush_by_id(brush_key)
		if brush and brush is DraftBrush:
			var draft := brush as DraftBrush
			set_brush_transform_by_id(brush_key, draft.size, _nudged_on_grid(draft, offset))


## Where a nudged brush lands, kept on the grid it was drawn on. Each press is a
## float32 add whose rounding leans the same way every time, so on a decimal grid
## a run of nudges drifted off the grid line, and after about a hundred Check
## Issues called a brush drawn against it a micro-gap (#1203). An axis is put back
## on the grid only when the step is a whole number of grid steps and one of the
## brush's faces on that axis was on the grid already, so a brush placed off the
## grid, or turned, still moves by exactly the step.
func _nudged_on_grid(draft: DraftBrush, offset: Vector3) -> Vector3:
	var target := draft.global_position + offset
	var step: float = root.grid_snap
	if step <= 0.0 or not draft.global_transform.basis.is_equal_approx(Basis.IDENTITY):
		return target
	var half := draft.size * 0.5
	for axis in 3:
		var steps := offset[axis] / step
		if is_zero_approx(offset[axis]) or absf(steps - roundf(steps)) > 0.001:
			continue
		for side in [-1.0, 1.0]:
			var face: float = draft.global_position[axis] + side * half[axis]
			if absf(face - snappedf(face, step)) <= step * 0.01:
				target[axis] = snappedf(face + offset[axis], step) - side * half[axis]
				break
	return target


## Snap to Grid: each brush moved the least distance that puts the minimum corner
## of its world bounds on a grid point. The bounds rather than the position, so a
## turned brush lands with its corner on the grid too. Size and rotation stay, and
## the move goes through `set_brush_transform_by_id()` as a nudge's does, so
## texture lock treats the two alike.
func snap_brushes_to_grid(brush_ids: Array, step: float) -> void:
	if not (step > 0.0):
		return
	for brush_id in brush_ids:
		var brush_key := str(brush_id)
		var brush = _find_brush_by_id(brush_key)
		if not (brush and brush is DraftBrush):
			continue
		var draft := brush as DraftBrush
		var corner := world_bounds_of(draft).position
		var offset := HFGridSystem.nearest_grid_point(corner, step) - corner
		set_brush_transform_by_id(brush_key, draft.size, draft.global_position + offset)


func duplicate_brush(brush: Node) -> Node:
	if not brush:
		return null
	var offset = Vector3(root.grid_snap if root.grid_snap > 0.0 else 1.0, 0.0, 0.0)
	var info = build_duplicate_info(brush, offset)
	# An entity of its own rather than another brush of the one it came from (#1161).
	HFBrushEntity.fresh_identities([info], [], root.entity_system)
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
	info["brush_id"] = ensure_brush_id(draft)
	if _shape_uses_sides(draft.shape):
		info["sides"] = draft.sides
	var pending = (
		draft.get_parent() == root.pending_node
		or bool(draft.get_meta(DraftBrush.PENDING_CUT_META, false))
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
	info.merge(HFBrushEntity.fields(draft))
	info.merge(HFBakeSplit.fields(draft))
	# The node name. restore_state() clears every brush and rebuilds it from this
	# info, so anything not captured here does not survive an undo - and a brush
	# that comes back as @Node3D@27719 has lost what entity I/O outputs target,
	# what the baked Area3D is named after, and what anyone reading the scene
	# tree recognises it by. Entity infos have carried their node name all along.
	# An authored name only. Godot auto-names an unnamed brush `@Node3D@14`, and
	# that is not identity -- `brush_id` is -- nor can it round trip: `@` is not a
	# character a node name may hold, so setting it back gives `_Node3D_14`, and
	# the engine reuses the number once a node is freed, so two live brushes can
	# record the same name and the second to be rebuilt collides with the first
	# and becomes `_Node3D_15`. Either way the record could not match the node it
	# described, and `capture_state()` was not a fixed point for any brush nobody
	# had named (#660). A generated name is left to the engine, which assigns a
	# fresh one and is not asked about it again.
	var node_name := String(draft.name)
	if not node_name.begins_with("@"):
		info["name"] = node_name
	return info


## The id `brush` is filed under: its `brush_id`, else the `brush_id` meta, else
## one minted now and written back to both. The lookups by id accept either, and
## the brush record carries this one, so a command and its undo step name the
## brush alike. Never the instance id: `find_brush_by_id()` does not take one,
## and a brush rebuilt by undo does not keep it (#1455).
func ensure_brush_id(brush: DraftBrush) -> String:
	var brush_id := str(brush.brush_id)
	if brush_id == "" and brush.has_meta("brush_id"):
		brush_id = str(brush.get_meta("brush_id"))
	if brush_id == "":
		brush_id = _next_brush_id()
		brush.brush_id = brush_id
		brush.set_meta("brush_id", brush_id)
	return brush_id


## The ids of the level's brushes among `nodes`, in order, each by
## `ensure_brush_id()`. Anything else, a freed node included, is left out. Every
## command that acts on the selected brushes asks here, so they agree on which
## brushes those are and what they are called (#1455).
func brush_ids_of(nodes: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for node in nodes:
		if is_instance_valid(node) and node is DraftBrush and is_brush_node(node):
			ids.append(ensure_brush_id(node as DraftBrush))
	return ids


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
				_reconcile_container_semantics(child as DraftBrush, role)
				repaired = true
			elif role == ROLE_PENDING and not _is_subtract_brush(child):
				# Saved while the Inspector could still turn a pending cut into a
				# solid. It drew as one, but its record and Apply made it a cut and
				# the bake left it out, so it is the cut its container says (#1551).
				child.operation = CSGShape3D.OPERATION_SUBTRACTION
				repaired = true
			if role != ROLE_COMMITTED:
				cache[brush_id] = child
				manager_brushes.append(child)
	_brush_cache = cache
	_brush_count = manager_brushes.size()
	if root.brush_manager:
		root.brush_manager.brushes = manager_brushes
	return repaired


## Unpick the faces of every brush no longer in the level.
##
## HammerForge's own delete unpicks a brush's faces as it removes it. Godot's
## Delete takes the node out of the scene without asking, and its key stayed in
## `face_selection`, so the HUD counted faces nothing could show or paint (#1515).
## The plugin's change tracker calls this after each editor step, once the step
## is over: a brush that passes out of the tree and back within one (a restore,
## Apply Cuts) is back by then, a brush Godot dragged out of its container has
## been put back, and a scene in another tab keeps its brushes as children, so
## none of them loses its faces. A cutter Commit Cuts put away is still the
## level's and keeps them, as it did before.
func drop_faces_of_departed_brushes() -> void:
	if root.face_selection.is_empty():
		return
	var present: Dictionary = {}
	for container in [
		root.draft_brushes_node, root.pending_node, root.committed_node, root.entities_node
	]:
		if not container:
			continue
		for child in container.get_children():
			if child is DraftBrush:
				present[face_key(child)] = true
				# A face picked while its brush had no id is keyed by instance, and
				# a reconcile may since have given the brush one.
				present[str(child.get_instance_id())] = true
	var departed: Array = []
	for key in root.face_selection:
		if not present.has(str(key)):
			departed.append(key)
	if departed.is_empty():
		return
	for key in departed:
		root.face_selection.erase(key)
	_announce_face_selection_change()


## Tell the dock and the face mark the selection changed. Batched deletes
## coalesce this down to one emission.
func _announce_face_selection_change() -> void:
	if root.has_method("_emit_or_batch"):
		root._emit_or_batch("face_selection_changed", [])
	elif root.has_signal("face_selection_changed"):
		root.face_selection_changed.emit()


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


func _reconcile_container_semantics(brush: DraftBrush, role: String) -> void:
	_set_container_role(brush, role)
	match role:
		ROLE_PENDING:
			brush.visible = true
			brush.operation = CSGShape3D.OPERATION_SUBTRACTION
			brush.set_pending_cut(true)
			brush.set_meta("committed_cut", false)
		ROLE_COMMITTED:
			brush.visible = false
			brush.operation = CSGShape3D.OPERATION_SUBTRACTION
			brush.set_pending_cut(false)
			brush.set_meta("committed_cut", true)
		_:
			brush.visible = true
			brush.set_pending_cut(false)
			brush.set_meta("committed_cut", false)


# ---------------------------------------------------------------------------
# ID management
# ---------------------------------------------------------------------------


## A name for a brush nobody named: its shape and the number its id ends in, such
## as `Wedge_3`. Godot's own name for an unnamed node is `@Node3D@25154`, which is
## what the Scene dock, the saved scene and Validate's messages showed for every
## brush (#1050). A sibling with the same name makes Godot number this one on.
func _readable_name(shape: int, brush_id: String) -> String:
	var number := brush_id.get_slice("_", brush_id.get_slice_count("_") - 1)
	if not number.is_valid_int():
		number = str(root._brush_id_counter)
	return "%s_%s" % [_shape_label(shape), number]


## Give each brush still under a name Godot generated, such as `@Node3D@90`, the
## name a new brush gets, and aim the wires that named it at the new one. Returns
## how many were renamed.
##
## A scene saved before #1065 has one on every brush, and a wire picked from the
## Objects tab aims at it. A brush's record leaves such a name out (#660), so a
## `.hflevel` load, or an undo that rebuilt the brush, named it `Box_3` and the
## wire reached nothing (#1182). Run as the level opens, it leaves every brush
## with a name its record keeps.
func name_brushes_godot_named() -> int:
	var previous: Dictionary = {}
	var current: Dictionary = {}
	for brush in root._iter_managed_brush_nodes():
		var generated := str(brush.name)
		if not generated.begins_with("@"):
			continue
		brush.name = _readable_name(int(brush.shape), str(brush.brush_id))
		previous[brush.get_instance_id()] = generated
		current[brush.get_instance_id()] = str(brush.name)
	if not previous.is_empty() and root.entity_system:
		root.entity_system.reconcile_external_names(previous, current)
	return previous.size()


## Whether a brush still has the name `_readable_name()` gives, `Box_3` and the
## like, rather than one a mapper typed. The bake groups clutter by it (#1139).
## Any shape's label counts: a bevel or a vertex edit turns a `Box_3` CUSTOM and
## keeps its name, which is still not one a mapper typed (#1144).
func has_readable_name(brush: DraftBrush) -> bool:
	var node_name := str(brush.name)
	for shape in root.BrushShape.values():
		var prefix := _shape_label(int(shape)) + "_"
		if node_name.begins_with(prefix) and node_name.trim_prefix(prefix).is_valid_int():
			return true
	return false


func _shape_label(shape: int) -> String:
	var key = root.BrushShape.find_key(shape)
	return str(key).to_pascal_case() if key != null else "Brush"


func _next_brush_id() -> String:
	root._brush_id_counter += 1
	return "%s_%s" % [str(Time.get_ticks_usec()), str(root._brush_id_counter)]


## Public wrapper for prefab instantiation.
func next_brush_id() -> String:
	return _next_brush_id()


## How deep a brush record can nest before the comparison gives up. A record is
## a handful of values and an array of faces, so this is far past anything real.
const _RECORD_COMPARE_DEPTH := 32


## The draft brushes a restore can keep, as `{brush_id: DraftBrush}`.
##
## A brush is keepable when the record the incoming state holds for it is
## identical to what that brush would capture right now, which means restoring it
## would rebuild the brush that is already there. A brush that fails the test is
## rebuilt as before, so a comparison that says no when it could have said yes
## costs time and nothing else. There is no way for it to say yes wrongly: two
## brushes with identical records are identical as far as anything that reads a
## record is concerned, and undo has always been exactly that.
func reusable_draft_brushes(records: Array) -> Dictionary:
	var keep: Dictionary = {}
	if not root.draft_brushes_node:
		return keep
	var wanted: Dictionary = {}
	for entry in records:
		if entry is Dictionary and (entry as Dictionary).has("brush_id"):
			wanted[str((entry as Dictionary)["brush_id"])] = entry
	if wanted.is_empty():
		return keep
	for child in root.draft_brushes_node.get_children():
		if not (child is DraftBrush):
			continue
		var brush := child as DraftBrush
		var brush_id := str(brush.brush_id)
		if not wanted.has(brush_id) or keep.has(brush_id):
			continue
		if record_matches_node(brush, wanted[brush_id]):
			keep[brush_id] = brush
	return keep


## Whether this brush is already exactly what the record describes.
##
## `recursive_equal` rather than `==`, because a record carries an array of face
## dictionaries and `==` does not go down into those.
##
## Deliberately not a field walk. A comparer that knows the record schema is a
## second place to add a field to, and the day someone adds one to
## `get_brush_info_from_node()` and forgets this, a restore reuses a brush that
## has changed and nothing says so. Capturing the record costs an allocation and
## cannot be wrong.
func record_matches_node(brush: Node, record: Dictionary) -> bool:
	var live: Dictionary = get_brush_info_from_node(brush)
	if live.is_empty():
		return false
	return live.recursive_equal(record, _RECORD_COMPARE_DEPTH)


## Put a kept brush back into the registries a cleared level no longer has it in.
##
## Its node was never touched, so there is no tree work here: this is the half of
## `create_brush_from_info()` that is bookkeeping.
func reregister_draft_brush(brush: DraftBrush) -> void:
	if not is_instance_valid(brush):
		return
	var brush_id := str(brush.brush_id)
	if brush_id == "":
		return
	_brush_cache[brush_id] = brush
	_brush_count += 1
	_advance_id_counter(brush_id)
	_legacy_manager_add(brush)


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


## A round shape is built from its sides too. Left out of the record, a cylinder
## or a sphere came back from a reopen or a duplicate at the default count, which
## its saved faces hid until the first resize built them again (#1085).
func _shape_uses_sides(shape: int) -> bool:
	return (
		shape == root.BrushShape.PYRAMID
		or shape == root.BrushShape.PRISM_TRI
		or shape == root.BrushShape.PRISM_PENT
		or shape in DraftBrush.ROUND_SHAPES
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
	brush.set_pending_cut(true)
	root.pending_node.add_child(brush)
	_set_container_role(brush, ROLE_PENDING)
	root._assign_owner(brush)


## A cut moved into another container lands beside brushes it was never named
## against, so it is added with a readable name, as every move between the
## containers is: `add_child()` otherwise names a node that lands beside a
## sibling of the same name `@Box_0@14`, which its record leaves out (#660), so
## the cutter an undo or a redo rebuilt came back as `Box_0` and the two
## captures differed by that one field (#1354). Godot numbers it on past the
## sibling instead, as a new brush is numbered, and a name a mapper typed keeps
## its stem.
func apply_pending_cuts() -> void:
	if not HFValidation.has_draft_containers(root):
		return
	var pending_count = root.pending_node.get_child_count()
	for child in root.pending_node.get_children():
		if child is DraftBrush:
			root.pending_node.remove_child(child)
			root.draft_brushes_node.add_child(child, true)
			_set_container_role(child, ROLE_DRAFT)
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
			child.set_pending_cut(false)
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
			# Out of the tree now, as clear_brushes() does for draft brushes: a
			# reconcile before the frame ends would see the restored cut beside the
			# doomed one and give it a new id (#1262).
			root.pending_node.remove_child(child)
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
	# A closed tab frees the level mid-bake, and the bake answers false a frame
	# later: there is no level left to put the cutters back in (#1357).
	if not is_instance_valid(root):
		return false
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
		root.pending_node.add_child(target, true)
		_set_container_role(target, ROLE_PENDING)
		target.set_pending_cut(true)
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
	root.committed_node.add_child(brush, true)
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
			root.draft_brushes_node.add_child(child, true)
			_set_container_role(child, ROLE_DRAFT)
			child.visible = true
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
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


## Take the level down to nothing, except any draft brush named in `keep_ids`.
##
## The keep set exists for `restore_state()`, which used to free and rebuild every
## brush in the level to take back a nudge of one of them (#600). A kept brush
## stays where it is, in the tree, still owned: only the registries are cleared,
## and the caller puts the kept ones back into them with
## `reregister_draft_brush()`. Everything else about the clear is unchanged, and
## every other caller passes nothing and gets what it always got.
func clear_brushes(keep_ids: Dictionary = {}) -> void:
	clear_face_selection()
	_brush_cache.clear()
	_brush_count = 0
	if root.brush_manager:
		root.brush_manager.clear_brushes()
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if child is DraftBrush:
				if keep_ids.has(str((child as DraftBrush).brush_id)):
					continue
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


## The record fields a live brush can take without being rebuilt.
##
## A transform and a set of faces are what the transform commands change, and
## both can be written straight onto the node. Everything else a record carries
## -- the shape, the size, the number of sides, whether it unions or subtracts --
## is decided when the CSG primitive is built, so a record that differs in one of
## those has to go back through `create_brush_from_info()`.
const IN_PLACE_RECORD_KEYS := ["transform", "faces"]


## Put one brush back to what a record says it was. Returns the live node, or
## null when the record could not be used.
##
## The scoped undo step restores a handful of brushes rather than the level
## (#737), so this is its unit. Three outcomes, cheapest first:
##
## - the brush already matches the record, and nothing happens
## - it differs only in fields that can be written onto the node, so they are,
##   and the node, its name and anything holding a reference to it survive
## - it differs in anything else, or it is not there at all, and it goes through
##   `create_brush_from_info()` -- the one door every other restore uses
##
## The third case is what makes the second safe. The in-place list is closed and
## the test for it is "apply these keys to what the brush records now, and see
## whether that is the record". A field added to `get_brush_info_from_node()` and
## to nothing else fails that test and lands in the rebuild, which is slower and
## right, rather than being quietly skipped.
func apply_brush_record(record: Dictionary) -> Node:
	if record.is_empty():
		return null
	var brush_id := str(record.get("brush_id", ""))
	var existing = _find_brush_by_id(brush_id) if brush_id != "" else null
	if not (existing is DraftBrush) or not is_instance_valid(existing):
		return create_brush_from_info(record)
	var draft := existing as DraftBrush
	var live: Dictionary = get_brush_info_from_node(draft)
	if live.is_empty():
		release_draft_brush(draft)
		return create_brush_from_info(record)
	if live.recursive_equal(record, _RECORD_COMPARE_DEPTH):
		return draft
	var probe: Dictionary = live.duplicate(true)
	for key in IN_PLACE_RECORD_KEYS:
		if record.has(key):
			probe[key] = record[key]
		else:
			probe.erase(key)
	if not probe.recursive_equal(record, _RECORD_COMPARE_DEPTH):
		release_draft_brush(draft)
		return create_brush_from_info(record)
	# Transform, then faces, then the handedness fold, in that order, because
	# that is the order `create_brush_from_info()` does them in and the two paths
	# have to agree on a record either of them could be handed (#749).
	if record.has("transform"):
		draft.global_transform = record["transform"]
	if record.has("faces"):
		draft.apply_serialized_faces(record.get("faces", []))
	if draft.global_transform.basis.determinant() < 0.0:
		_transform_system().normalize_handedness(draft)
	_tag_brush_node_dirty(draft)
	return draft


## Take one draft brush out of the level so a record can rebuild it.
##
## Not `delete_brush()`. That is what a user deleting a brush calls: it strips
## group and visgroup membership and removes the entity I/O connections aimed at
## the node, because when a brush goes those references are meant to go with it.
## A restore is not a delete -- the brush is coming straight back from a record,
## and a record does not carry the connections that pointed at it, so running
## that cleanup would make every undo that rebuilds a brush quietly drop them.
##
## `remove_child()` before `queue_free()`, so the rebuild in the next line is not
## competing with a name the freed node still holds. That is the same order
## `clear_brushes()` uses and for the same reason.
func release_draft_brush(brush: DraftBrush) -> void:
	if not is_instance_valid(brush):
		return
	var brush_id := str(brush.brush_id)
	if brush_id != "":
		_brush_cache.erase(brush_id)
	_brush_count = max(0, _brush_count - 1)
	_legacy_manager_remove(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	brush.queue_free()


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
			root.committed_node.remove_child(child)
			child.queue_free()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------


## The Draw tool's preview look for a brush of `operation`.
func _make_brush_material(operation: int) -> Material:
	var cache_key = "%d" % operation
	if _material_cache.has(cache_key):
		return _material_cache[cache_key]
	var mat = StandardMaterial3D.new()
	if operation == CSGShape3D.OPERATION_SUBTRACTION:
		mat.albedo_color = Color(1.0, 0.2, 0.2, 0.35)
		mat.emission = Color(1.0, 0.2, 0.2)
		mat.emission_energy_multiplier = 0.2
	else:
		mat.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	# A look for the viewport only, which a bake leaves behind (#1518).
	mat.set_meta(DraftBrush.EDITOR_LOOK_META, true)
	_material_cache[cache_key] = mat
	return mat


func _make_pending_cut_material() -> Material:
	return DraftBrush.pending_cut_look()


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


## The resize path, and the same funnel the create path uses.
##
## These two used to disagree about what a size is: `create_brush_from_info()`
## refuses a non-finite one and coerces a zero or negative one with a warning,
## while this wrote whatever it was given straight onto the property. A negative
## size builds the brush inside out, a zero one builds no volume, and a NaN one
## poisons the AABB with no editor action that puts it back. The dock's size
## fields come through here, so the resize path was the easier of the two to
## reach.
func set_brush_transform_by_id(brush_id: String, size: Vector3, position: Vector3) -> void:
	if brush_id == "":
		return
	if not size.is_finite() or not position.is_finite():
		HFLog.warn(
			(
				"HFBrushSystem: refusing to move brush '%s' to size %s at %s"
				% [brush_id, str(size), str(position)]
			)
		)
		return
	var brush = _find_brush_by_id(brush_id)
	if brush and brush is DraftBrush:
		var draft := brush as DraftBrush
		var old_size := draft.size
		var old_pos := draft.global_position
		var usable := _usable_size(size, _built_from_faces(draft.shape, draft.faces))
		var normalized_size := DraftBrush.normalized_size_for_shape(draft.shape, usable)
		if old_size.is_equal_approx(normalized_size) and old_pos.is_equal_approx(position):
			return
		draft.size = normalized_size
		draft.global_position = position
		if root.texture_lock and not draft.faces.is_empty():
			_adjust_face_uvs_for_transform(draft, old_size, draft.size, old_pos, position)
			draft.rebuild_preview()
		refit_texture_groups([draft])
		_tag_brush_node_dirty(draft)


func _tag_brush_node_dirty(brush: Node) -> void:
	if not brush:
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
		# A face in a texture group keeps its group's mapping, which reads on from
		# the rest of the surface wherever it is (#1437).
		if face == null or face.uv_group != 0:
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
	var preview = root.preview_brush
	root.preview_brush = null
	if preview and is_instance_valid(preview) and preview.is_inside_tree():
		# Out of the tree at once, as HFDragSystem._clear_preview() does, so no
		# state captured this frame holds it.
		preview.get_parent().remove_child(preview)
		preview.queue_free()


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
	var brush_hit := pick_face_from_ray(ray_origin, ray_dir)
	if not include_entities:
		return brush_hit.get("brush") as Node
	return pick_node_past_face(brush_hit, ray_origin, ray_dir)


## What a click on the ray picks once the brush face it meets is known: the
## nearest visible entity in front of that face, else the face's brush. The
## prefab ghost hands in the face the hover outline already found, so a motion
## walks the brushes once.
func pick_node_past_face(
	brush_hit: Dictionary, ray_origin: Vector3, ray_direction: Vector3
) -> Node:
	var closest: Node = brush_hit.get("brush") as Node
	if ray_direction.is_zero_approx():
		return closest
	var ray_dir := ray_direction.normalized()
	var best_t := float(brush_hit.get("distance", INF))
	var entities_node: Node = root.entities_node
	for child in root._iter_pick_nodes():
		# Most of this walk is brushes, and asking `is_entity_node()` of each
		# cost 4.6 ms a click at 3,000 of them (#1387). A brush outside the
		# entities container is an entity only by its tag.
		var brush := child as DraftBrush
		if (
			brush
			and not brush.has_meta(&"is_entity")
			and not (entities_node and entities_node.is_ancestor_of(brush))
		):
			continue
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


## Outline the brush under the pointer, and return the face pick that found it
## for the prefab ghost to start from.
func update_hover(camera: Camera3D, mouse_pos: Vector2, selected_nodes: Array = []) -> Dictionary:
	if not camera:
		return {}
	var hit := pick_face(camera, mouse_pos)
	if not root.hover_highlight:
		return hit
	var brush = hit.get("brush", null)
	if brush and brush is DraftBrush:
		if should_suppress_hover(brush, selected_nodes):
			root.hover_highlight.visible = false
			return hit
		var mesh_inst: MeshInstance3D = brush.mesh_instance
		if not mesh_inst:
			root.hover_highlight.visible = false
			return hit
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
	return hit


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
		var brush := node as DraftBrush
		if brush == null:
			continue
		var mesh_inst: MeshInstance3D = brush.mesh_instance
		if mesh_inst == null or not mesh_inst.is_inside_tree():
			continue
		# Every move over the viewport picks, and the exact tests below are
		# several script calls a brush: walking them all cost 16 ms a move at
		# 3,000 brushes (#1387). The world box first is a few engine calls, and
		# it holds the turned box `_visual_pick_distance()` tests, so it only
		# lets more through. Read off the brush each time, so it cannot go stale.
		var world_box: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		if world_box.grow(PICK_BOUNDS_SLACK).intersects_ray(ray_origin, ray_dir) == null:
			continue
		if (
			brush != preview
			and is_brush_node(brush)
			and root._is_pick_visible(brush)
			and root._is_pick_visible(mesh_inst)
			and root._visual_pick_distance(mesh_inst, ray_origin, ray_dir) >= 0.0
		):
			brushes.append(brush)
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


func clear_face_selection() -> void:
	root.face_selection.clear()


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
	# The same refusal the operation makes, so the ghost and the cut agree.
	if not HFTransformSystem.is_valid_axis(axis):
		return HFOpResult.fail(
			"Clip: %d does not name an axis" % axis, "Use 0 for X, 1 for Y or 2 for Z"
		)
	var axis_index := axis
	var brush_min: float = bounds.position[axis_index]
	var brush_max: float = bounds.position[axis_index] + bounds.size[axis_index]
	var snap = root.grid_snap if root.grid_snap > 0.0 else 0.0
	if snap > 0.0:
		split_pos = snapped(split_pos, snap)
	var margin = snap if snap > 0.0 else 0.01
	if split_pos <= brush_min + margin or split_pos >= brush_max - margin:
		var axis_name = ["X", "Y", "Z"][axis_index]
		return HFOpResult.fail(
			"Clip: split position %.1f is outside brush bounds on %s axis" % [split_pos, axis_name],
			"Click inside the brush face to pick a valid split point"
		)
	return HFOpResult.success()


## Where a Clip with no point picked splits a brush: the middle of its world
## bounds on `axis`, snapped as the cut snaps it. Both Clip entry points read a
## `center` that the brush info never had, so every default split was at 0 and a
## brush standing on the floor could not be clipped (#1024).
func default_clip_position(brush_id: String, axis: int) -> float:
	var brush = _find_brush_by_id(brush_id)
	if not (brush is DraftBrush) or not HFTransformSystem.is_valid_axis(axis):
		return 0.0
	var middle: float = world_bounds_of(brush as DraftBrush).get_center()[axis]
	if root.grid_snap > 0.0:
		middle = snappedf(middle, root.grid_snap)
	return middle


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
	root.tag_full_reconcile()
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Hollow: brush not found")
	var draft := brush as DraftBrush
	var plan: Dictionary = _plan_hollow(draft, wall_thickness)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		return _op_fail(check.message, check.fix_hint)

	warn_lost_sculpts(
		"Hollow", brush_id, HFConvexClip.carry_surface_detail(plan["walls"], plan["origins"])
	)
	var infos: Array = _piece_infos_from_faces(draft, plan["walls"])
	# What the solid was, taken before the solid stops existing. This is the whole
	# of what makes a hollow live: without the original there is nothing to shell
	# again at a different thickness.
	var source_info: Dictionary = get_brush_info_from_node(draft)
	var result: HFOpResult = _replace_brush_with_pieces(brush_id, infos, "Hollow", "walls")
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
			HFOpResult.fail(
				(
					"Hollow: this brush has %d distinct faces, so it would become %d walls"
					% [budget["planes"], budget["planes"]]
				),
				"Hollow works on brushes with up to %d faces." % HFConvexClip.MAX_BOOLEAN_PLANES
			),
			"walls": empty
		}
	if not HFConvexClip.is_convex_solid(faces, interior):
		return {
			"result":
			HFOpResult.fail(
				"Hollow: this brush is not convex, so its walls would follow its hull",
				"Hollow works on convex brushes. A torus is not one"
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
	_smooth_inner_walls(walls, shelled["origins"], faces, interior, wall_thickness)
	return {
		"result": HFOpResult.success("%d walls" % walls.size()),
		"walls": walls,
		"origins": shelled["origins"],
	}


## Give each inside wall of a hollow the smoothing group of the face it lies
## behind (#1429), so a round brush hollows into a tube round inside as well as
## out. The inside walls are the faces the cut made, which come out flat, as a
## cut's faces do; these are the ones that face in, across the wall from a face
## of the brush.
static func _smooth_inner_walls(
	walls: Array, origins: Dictionary, faces: Array, interior: Vector3, wall_thickness: float
) -> void:
	var behind: Array = []
	for face in faces:
		var data := face as FaceData
		if data == null or data.smoothing_group <= 0:
			continue
		var plane := HFConvexClip.face_plane(data)
		if plane.normal.length_squared() < 0.5:
			continue
		if plane.distance_to(interior) > 0.0:
			plane = Plane(-plane.normal, -plane.d)
		behind.append([HFConvexClip.offset_plane(plane, -wall_thickness), data.smoothing_group])
	if behind.is_empty():
		return
	for wall: Array in walls:
		for face in wall:
			var data := face as FaceData
			if data == null or origins.has(data) or data.local_verts.is_empty():
				continue
			for entry: Array in behind:
				var inset: Plane = entry[0]
				if (
					data.normal.dot(-inset.normal) > 0.9999
					and absf(inset.distance_to(data.local_verts[0])) <= HFConvexClip.DEFAULT_EPSILON
				):
					data.smoothing_group = entry[1]
					break


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

## How many merges have been planned. Planning is the costly half of a merge, a
## quarter of a second for two 64-sided cylinders. Read by the tests and useful
## when profiling.
var merge_plans_made: int = 0

## The plan a merge press made in its check, kept for the merge the same press
## commits, and the key it was made from. See `can_merge_brushes()`.
var _held_merge_plan: Dictionary = {}


## Whether these brushes can merge, and if not, why not.
##
## `hold_plan` keeps the plan for the next `merge_brushes_by_ids()`, which plans
## again only if the brushes have changed since. The merge command asks here
## before it opens the undo action and then commits the merge, so without this a
## press planned twice, and a round merge plans slowly (#1257). The merge takes
## the plan or drops it, and the command lets go of it after committing either
## way, so no plan outlives its press. A redo does not merge at all: it restores
## the level the merge made (#1275).
func can_merge_brushes(brush_ids: Array, hold_plan: bool = false) -> HFOpResult:
	var plan := _plan_merge(brush_ids)
	var result: HFOpResult = plan["result"]
	_held_merge_plan = {}
	if hold_plan and result.ok:
		_held_merge_plan = {"key": _merge_key(brush_ids), "plan": plan}
	return result


## Let go of a plan `can_merge_brushes()` held, whether or not a merge took it.
func release_merge_plan() -> void:
	_held_merge_plan = {}


## The plan held for these brushes if nothing it was made from has changed, or a
## new one. Nothing is held afterwards, so a held plan is used once at most.
func _held_or_new_merge_plan(brush_ids: Array) -> Dictionary:
	var held := _held_merge_plan
	_held_merge_plan = {}
	if not held.is_empty() and held["key"] == _merge_key(brush_ids):
		return held["plan"]
	return _plan_merge(brush_ids)


## What a merge plan is read from: the brush each id names, where it is, what it
## does, the entity it belongs to and the corners of its faces. A held plan whose
## key has changed was made for a level that has moved on since -- an undo rebuilt
## the brushes, or one was moved or reshaped -- and is not used.
func _merge_key(brush_ids: Array) -> Array:
	var key: Array = []
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if not (brush is DraftBrush):
			key.append([str(brush_id)])
			continue
		var draft := brush as DraftBrush
		var corners: Array = []
		for face in draft.get_faces():
			var data: FaceData = face as FaceData
			corners.append(data.local_verts if data != null else PackedVector3Array())
		var read_from: Array = [
			str(brush_id),
			draft.get_instance_id(),
			draft.global_transform,
			draft.operation,
			HFBrushEntity.entity_class(draft),
			HFBrushEntity.identity(draft),
			corners,
		]
		key.append(read_from)
	return key


## Work out the brush a merge would make, and whether it can happen at all.
##
## Returns `{"result": HFOpResult, "drafts": Array, "placement": Transform3D,
## "faces": Array, "origins": Dictionary, "brush_of": Dictionary}`: where the
## merged brush goes, its faces in that space, the source face each came from, and
## the brush each source face belongs to. Side effect free, so the check and the
## merge cannot disagree.
func _plan_merge(brush_ids: Array) -> Dictionary:
	merge_plans_made += 1
	var plan := {
		"result": HFOpResult.success(),
		"drafts": [],
		"placement": Transform3D.IDENTITY,
		"faces": [],
		"origins": {},
		"brush_of": {},
	}
	if brush_ids.size() < 2:
		plan["result"] = HFOpResult.fail(
			"Merge: select at least 2 brushes", "Select multiple brushes before merging"
		)
		return plan
	var first_op: int = -1
	var drafts: Array = []
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if not brush or not (brush is DraftBrush):
			plan["result"] = HFOpResult.fail("Merge: brush '%s' not found" % str(brush_id))
			return plan
		var draft := brush as DraftBrush
		drafts.append(draft)
		if first_op < 0:
			first_op = draft.operation
		elif draft.operation != first_op:
			plan["result"] = HFOpResult.fail(
				"Merge: all brushes must have the same operation type",
				"Cannot merge additive and subtractive brushes together"
			)
			return plan
	# The merged brush is one brush of one entity or of none. Taking the first
	# brush's class made a door's leaf merged into a wall a door, and two doors one
	# door with the first one's name and nobody's wires (#1194).
	if not HFBrushEntity.are_one_entity(drafts):
		plan["result"] = HFOpResult.fail(
			"Merge: the selected brushes are not all one entity",
			"Merge the brushes of one door or trigger, or plain brushes. Tie or untie them first"
		)
		return plan
	if not _brushes_form_one_solid(brush_ids):
		plan["result"] = HFOpResult.fail(
			"Merge: the selected brushes do not touch",
			"Merge only joins brushes that share a face or overlap"
		)
		return plan

	# The merged brush is the solid the brushes make together, so two boxes side
	# by side become the one box they are. Collecting every face of every brush
	# kept the two faces where they touched, back to back inside the solid: Validate
	# called it not convex, Check Issues found non-manifold edges, and the `.map`
	# export wrote two opposite planes through it, which is an empty brush to any
	# other tool in the lineage (#1200).
	#
	# It is turned as the first brush is and centred on what it holds, as a piece
	# of a cut is, so its size and origin are its own. Built on the first brush's
	# origin, two boxes side by side said they were one box at the first one's
	# place, and Check Issues and the dock read that (#1251).
	var placement := _merged_placement(drafts)
	var into: Transform3D = placement.affine_inverse()
	var face_sets: Array = []
	var brush_of := {}
	for draft in drafts:
		var carried := _faces_carried(draft, into * (draft as DraftBrush).global_transform)
		for face in carried:
			brush_of[face] = draft
		face_sets.append(carried)
	var union: Dictionary = HFConvexClip.union_of(face_sets, 2.0 * _MERGE_ADJACENCY_EPSILON)
	if not union["convex"]:
		plan["result"] = HFOpResult.fail(
			"Merge: the merged brush would not be convex",
			(
				"A brush is convex, and these brushes make an L, a U or another shape with a "
				+ "corner cut out. Merge the parts that make a box, a wedge or a slope"
			)
		)
		return plan
	plan["drafts"] = drafts
	plan["placement"] = placement
	plan["faces"] = union["faces"]
	plan["origins"] = union["origins"]
	plan["brush_of"] = brush_of
	return plan


## Where a merge of `drafts` puts the brush it makes: turned as the first of them
## is, at the middle of the box round all their corners in that turn. A merge goes
## through only when the brushes make a convex solid, and the box round one is the
## box round its corners, so this is the middle of the merged brush.
func _merged_placement(drafts: Array) -> Transform3D:
	var first: Transform3D = (drafts[0] as DraftBrush).global_transform
	var into_first := first.affine_inverse()
	var bounds := AABB()
	var seeded := false
	for draft in drafts:
		_ensure_faces(draft)
		var to_first: Transform3D = into_first * (draft as DraftBrush).global_transform
		for face in (draft as DraftBrush).get_faces():
			var data: FaceData = face as FaceData
			if data == null:
				continue
			for vertex in data.local_verts:
				var point: Vector3 = to_first * vertex
				if seeded:
					bounds = bounds.expand(point)
				else:
					bounds = AABB(point, Vector3.ZERO)
					seeded = true
	return Transform3D(first.basis, first * bounds.get_center())


## Copies of a brush's faces for reading, carried by `to_space` into the space of
## another brush.
##
## A Cylindrical face measures its texture's angle about its own brush's axis, so
## one carried into another brush's space takes the UVs it shows now, as a piece of
## a cut does (#868).
static func _faces_carried(draft: DraftBrush, to_space: Transform3D) -> Array:
	var stays := to_space.is_equal_approx(Transform3D.IDENTITY)
	var carried: Array = []
	for face in draft.get_faces():
		var source: FaceData = face as FaceData
		if source == null or source.local_verts.size() < 3:
			continue
		var copy := FaceData.new()
		copy.copy_appearance_from(source)
		var moved := PackedVector3Array()
		for vertex in source.local_verts:
			moved.append(to_space * vertex)
		copy.local_verts = moved
		copy.custom_uvs = source.custom_uvs
		if (
			not stays
			and source.uv_projection == FaceData.UVProjection.CYLINDRICAL
			and source.custom_uvs.size() != source.local_verts.size()
		):
			copy.custom_uvs = source.shown_uvs_at(source.local_verts)
		copy.paint_layers = source.paint_layers
		copy.displacement = source.displacement
		copy.ensure_geometry()
		carried.append(copy)
	return carried


## How far apart two brushes may be and still count as touching, in metres.
## Faces that meet exactly are the ordinary case, and a float is a float.
const _MERGE_ADJACENCY_EPSILON := 0.001


## Whether these brushes are one connected lump rather than several.
##
## A brush in this lineage is the intersection of its half spaces, so it has to
## be convex. `merge_brushes_by_ids()` collected the faces of every brush into one
## `DraftBrush`, and two brushes with a gap between them became one brush made of
## two disconnected lumps -- which is not convex, and nothing downstream noticed:
## Validate reported nothing, the `.map` export wrote twelve planes describing an
## empty solid, and the bake generated a convex hull spanning the gap, so the
## space between the two pieces became solid to the player and stayed empty to
## the eye (#666).
##
## World AABBs, closed transitively, which is the same sweep
## `_chunking_has_cross_boundary_interactions()` does in `hf_bake_system.gd`. It
## is a conservative test: two brushes whose boxes overlap while their geometry
## does not will pass. That is the right direction -- it refuses the selection a
## mapper plainly did not mean, and does not refuse a legitimate one.
##
## Measured off the faces. The nominal size at the origin is a turned brush's
## unturned box, and a merged brush's was the default drag size whatever it held
## until #1251, so a box touching the far end of one it had just merged was
## refused as not touching it.
func _brushes_form_one_solid(brush_ids: Array) -> bool:
	var boxes: Array[AABB] = []
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if not (brush is DraftBrush):
			return false
		boxes.append(world_bounds_of(brush as DraftBrush).grow(_MERGE_ADJACENCY_EPSILON))
	if boxes.size() < 2:
		return true
	# Grow the group from the first brush until nothing else touches it.
	var joined: Array[int] = [0]
	var reached: Dictionary = {0: true}
	var cursor := 0
	while cursor < joined.size():
		var current: AABB = boxes[joined[cursor]]
		for i in boxes.size():
			if reached.has(i):
				continue
			if current.intersects(boxes[i]):
				reached[i] = true
				joined.append(i)
		cursor += 1
	return joined.size() == boxes.size()


func merge_brushes_by_ids(brush_ids: Array) -> HFOpResult:
	# The rules live in can_merge_brushes() and have to hold here, not only at the
	# one caller that consults it. plugin_edit_actions.gd asks before it opens the
	# undo action, and the undo entry stores this method and these ids — so a redo
	# calls straight in, against a level that has moved on since the check ran.
	# Undo a merge, delete one of the sources, redo, and the operation used to
	# merge the subset and report the count it merged. The other rule is worse: a
	# subtractive brush is a hole, and merged into an additive one its geometry
	# became part of a solid, so the mapper had a doorway and now has a wall,
	# under a message saying "Merged 2 brushes". The plan is side effect free and
	# returns the right message for each case. A plan the check held for this
	# press is used only while these brushes are as they were when it was made.
	var plan := _held_or_new_merge_plan(brush_ids)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		return check
	root.tag_full_reconcile()

	var brushes: Array = plan["drafts"]
	var first: DraftBrush = brushes[0]
	var operation: int = first.operation
	# The plan built its faces in the merged brush's own space.
	var merged_xform: Transform3D = plan["placement"]
	var faces: Array = plan["faces"]
	var origins: Dictionary = plan["origins"]
	var brush_of: Dictionary = plan["brush_of"]
	var lost := HFConvexClip.carry_onto_union(faces, origins)
	if lost > 0:
		var why := "A sculpt is laid on its face's corners, and a face that grew has new ones."
		HFLog.warn("HammerForge: Merge could not keep %d sculpt(s). %s" % [lost, why])

	# The merged brush has one material override at most, so a face that showed its
	# brush's override takes it as a palette slot instead, and keeps its look.
	var slot_of: Dictionary = {}  # Material -> int
	for face in faces:
		var built: FaceData = face as FaceData
		var draft: DraftBrush = brush_of[origins[built]]
		if built.material_idx >= 0 or draft.material_override == null:
			continue
		if not slot_of.has(draft.material_override) and root.has_method("add_material_to_palette"):
			slot_of[draft.material_override] = root.add_material_to_palette(draft.material_override)
		built.material_idx = int(slot_of.get(draft.material_override, -1))

	# Capture metadata from first brush
	var src_visgroups: PackedStringArray = first.get_meta("visgroups", PackedStringArray())
	var src_group_id: String = str(first.get_meta("group_id", ""))
	# The entity they all are, with every wire and property any of them held.
	var entity := HFBrushEntity.carried_by_all(brushes)

	# Delete all original brushes
	for brush in brushes:
		delete_brush(brush)

	# Create merged brush with full transform (not just center position)
	var merged_info: Dictionary = {
		"shape": root.BrushShape.CUSTOM,
		"size": _local_bounds_of_faces(faces).size,
		"transform": merged_xform,
		"operation": operation,
		"brush_id": _next_brush_id(),
		"faces": _serialized(faces),
	}
	merged_info.merge(entity)
	# The first brush's bake settings, as it gives its visgroups and group (#1660).
	merged_info.merge(HFBakeSplit.fields(first))

	var merged = create_brush_from_info(merged_info)
	if merged:
		if src_visgroups.size() > 0:
			merged.set_meta("visgroups", src_visgroups.duplicate())
		if src_group_id != "":
			merged.set_meta("group_id", src_group_id)

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
	warn_lost_sculpts(
		"Clip", brush_id, HFConvexClip.carry_surface_detail([front, back], halves["origins"])
	)

	var infos: Array = _piece_infos_from_faces(draft, [front, back])
	return _replace_brush_with_pieces(brush_id, infos, "Clip")


## Split a brush along an axis-aligned plane.
## axis: 0=X, 1=Y, 2=Z.  split_pos: world coordinate on that axis.
func clip_brush_by_id(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Clip: no brush ID provided")
	var brush = _find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return _op_fail("Clip: brush not found")
	var draft := brush as DraftBrush
	# Refused rather than clamped. Clamping turned an index of 5 into a cut on Z
	# and an index of -1 into a cut on X, and reported the cut it made on the
	# axis it picked, so a caller that got its index wrong got a plausible
	# operation it never described. The dropdown passes 1 today; `LevelRoot`
	# exposes this and the preview takes an axis from anyone.
	if not HFTransformSystem.is_valid_axis(axis):
		return _op_fail("Clip: %d does not name an axis" % axis, "Use 0 for X, 1 for Y or 2 for Z")
	var axis_index := axis
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
	var world_normal: Vector3 = face.normal_through(xform.basis)
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


## Say when a cut could not keep a sculpt on every piece of its face. Paint always
## follows a cut, so a sculpt is the one thing a cut can lose, and it should not
## go without a word.
static func warn_lost_sculpts(op_name: String, brush_id: String, count: int) -> void:
	if count <= 0:
		return
	HFLog.warn(
		(
			(
				"HammerForge: %s could not keep %d sculpt(s) of brush '%s' on every piece. "
				+ "A sculpt follows a cut only onto a piece of its face with four corners."
			)
			% [op_name, count, brush_id]
		)
	)


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


## The faces with a usable polygon, each moved by `offset` in place.
static func _shifted_faces(faces: Array, offset: Vector3) -> Array:
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
		out.append(data)
	return out


## Each face as the dictionary a brush info carries.
static func _serialized(faces: Array) -> Array:
	var out: Array = []
	for face in faces:
		out.append(face.to_dict())
	return out


## Describe one face set as brush info, placed by `placement` and centred on its
## own geometry.
##
## A piece that is still an axis-aligned box in the placing frame is emitted as a
## BOX so it keeps its resize handles, with its faces stored the way the box
## builder makes them. Anything else becomes CUSTOM with the faces as its
## authoritative geometry, and so does a box thinner than `MIN_BRUSH_EXTENT`,
## which a BOX would be widened to when its scene opened (#1598).
func _face_set_info(faces: Array, placement: Transform3D) -> Dictionary:
	var described: Dictionary = HFConvexClip.is_axis_aligned_box(faces)
	var bounds := _local_bounds_of_faces(faces)
	var centre: Vector3 = described["center"] if not described.is_empty() else bounds.get_center()
	var stored := _shifted_faces(faces, -centre)
	if not described.is_empty():
		# A box rebuilds on its first resize and whenever its scene opens, and lists
		# its faces the builder's way when it does. Stored that way already, the
		# rebuild changes nothing: a face index still names the same face, and a
		# hollow's or a structure's record still reads the piece as untouched (#867).
		var ordered: Array = DraftBrush.faces_in_box_order(stored, described["size"])
		if is_same(ordered, stored):
			# The layout did not take it, so as a box it would be squared when its
			# scene opened. The box test leaves room for this, which the float noise
			# of a piece far from its origin can still use up.
			described = {}
		stored = ordered
	return {
		"shape": root.BrushShape.BOX if not described.is_empty() else root.BrushShape.CUSTOM,
		"size": described["size"] if not described.is_empty() else bounds.size,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": _next_brush_id(),
		"transform": Transform3D(placement.basis, placement * centre),
		"faces": _serialized(stored),
	}


## Create one brush per generated face set. The entry point every generator uses.
##
## `cuts` names the face sets that are cuts, as `{index: pending}`. Each is a
## Cutout as a drawn one is: pending while it waits for Apply, and never given
## `material`, so it keeps the cut look.
func create_brushes_from_face_sets(
	face_sets: Array, placement: Transform3D, material: Material = null, cuts: Dictionary = {}
) -> PackedStringArray:
	var created := PackedStringArray()
	for i in face_sets.size():
		var faces: Array = face_sets[i]
		if faces.is_empty():
			continue
		var info := _face_set_info(faces, placement)
		if cuts.has(i):
			info["operation"] = CSGShape3D.OPERATION_SUBTRACTION
			info["pending"] = bool(cuts[i]) and root.pending_node != null
		elif material:
			info["material"] = material
		if create_brush_from_info(info):
			created.append(str(info["brush_id"]))
	return created


## A brush record for each face set, a piece of `draft` with its operation, look,
## visgroups, group and brush entity. Every piece is the whole entity, which since
## #1148 is what brushes alike in class and name or tie are (#1194).
func _piece_infos_from_faces(draft: DraftBrush, face_sets: Array) -> Array:
	var entity := HFBrushEntity.carried_into_pieces(draft)
	var infos: Array = []
	for faces in face_sets:
		var info := _face_set_info(faces, draft.global_transform)
		info["operation"] = draft.operation
		if draft.material_override:
			info["material"] = draft.material_override
		info.merge(entity.duplicate(true))
		var visgroups: PackedStringArray = draft.get_meta("visgroups", PackedStringArray())
		if not visgroups.is_empty():
			info["visgroups"] = Array(visgroups)
		var group_id := str(draft.get_meta("group_id", ""))
		if group_id != "":
			info["group_id"] = group_id
		# How the brush casts shadows and how fine its lightmap is (#1660).
		info.merge(HFBakeSplit.fields(draft))
		infos.append(info)
	return infos


## Delete a brush and put the pieces of it back in its place.
func _replace_brush_with_pieces(
	brush_id: String, infos: Array, op_name: String, piece_noun: String = "pieces"
) -> HFOpResult:
	delete_brush_by_id(brush_id)

	var created: Array = []
	for info in infos:
		var piece = create_brush_from_info(info)
		if piece:
			created.append(piece)
	if created.is_empty():
		return _op_fail("%s: produced no geometry" % op_name)
	# A piece of a face in a texture group is still that surface (#1437).
	refit_texture_groups(created)
	var message := "%s: %d %s" % [op_name, created.size(), piece_noun]
	root._log(message)
	return HFOpResult.success(message)


## Tie brushes to an entity class, and optionally give them a name.
##
## The name is the address every I/O connection is written against:
## `find_entities_by_name()` looks for it on brushes and says so in its own
## comment, and the `.map` exporter writes it. The only code that ever set it was
## the `.map` import path, so a door built in HammerForge could never be
## targeted while a door imported from someone else's `.map` could (#668).
##
## Several brushes tied under one name are one entity -- a two leaf door is two
## brushes and one door -- which is what the `.map` export and the playtest need
## in order to group them.
func tie_brushes_to_entity(
	brush_ids: Array, entity_class: String, entity_name: String = ""
) -> void:
	var authored := entity_name.strip_edges()
	# One tie is one entity. A two leaf door is two brushes and one door, and the
	# mapper said so by tying them together, so the operation mints an identity
	# rather than leaving the export to infer one. The name is an address for
	# wiring; this is identity, and they are different questions -- two unnamed
	# doors must stay two doors (#668).
	var group := HFBrushEntity.mint_tie()
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			var was := str(brush.get_meta("brush_entity_class", ""))
			brush.set_brush_entity_class(entity_class)
			if was != "" and was != entity_class:
				_keep_what_class_declares(brush, entity_class)
			brush.set_meta("brush_entity_group", group)
			if authored != "":
				brush.set_meta("entity_name", authored)
			elif brush.has_meta("entity_name"):
				brush.remove_meta("entity_name")
	if authored == "":
		root._log("Tied %d brushes as '%s'" % [brush_ids.size(), entity_class])
	else:
		root._log("Tied %d brushes as '%s' named '%s'" % [brush_ids.size(), entity_class, authored])


## Give these brushes their own Cast Shadows, or `HFBakeSplit.LEVEL_DEFAULT` to
## leave it to their visgroups and the level (#1444). The ids of those that
## changed.
func set_brushes_cast_shadow(brush_ids: Array, value: int) -> Array:
	if value != HFBakeSplit.LEVEL_DEFAULT and not HFBakeSplit.is_cast_shadow(value):
		HFLog.warn("Cast Shadows: %d is not a shadow casting setting. Left alone." % value)
		return []
	var changed: Array = []
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush is DraftBrush and HFBakeSplit.set_brush_cast_shadow(brush, value):
			changed.append(str(brush_id))
	return changed


## Give these brushes a Lightmap Scale, held to its range (#1438). The ids of
## those that changed.
func set_brushes_lightmap_scale(brush_ids: Array, value: float) -> Array:
	if not is_finite(value):
		HFLog.warn("Lightmap Scale: %s is not a scale. Left alone." % str(value))
		return []
	var changed: Array = []
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush is DraftBrush and HFBakeSplit.set_brush_lightmap_scale(brush, value):
			changed.append(str(brush_id))
	return changed


func untie_brushes_from_entity(brush_ids: Array) -> void:
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush and brush is DraftBrush:
			brush.set_brush_entity_class("")
			# The name went with the class. A brush that is no longer an entity
			# must not keep answering to one, or #620's dangling wire check finds
			# a target that is ordinary geometry.
			if brush.has_meta("entity_name"):
				brush.remove_meta("entity_name")
			if brush.has_meta("brush_entity_group"):
				brush.remove_meta("brush_entity_group")
			# Its wires and properties went with it too. Tied again as something
			# else, a trigger's OnStartTouch and target turned up on a door (#1112).
			for key in ["entity_io_outputs", "brush_entity_data"]:
				if brush.has_meta(key):
					brush.remove_meta(key)
	root._log("Untied %d brushes" % brush_ids.size())


## A brush tied as another class keeps the properties and wires that class
## declares and drops the rest, so a trigger made a door keeps no OnStartTouch
## (#1112). A class with no definition keeps everything, as nothing says what it
## has.
func _keep_what_class_declares(brush: DraftBrush, entity_class: String) -> void:
	var definition: Dictionary = root.get_entity_definition(entity_class)
	if definition.is_empty():
		return
	var names := {}
	for prop in definition.get("properties", []):
		if prop is Dictionary:
			names[str(prop.get("name", ""))] = true
	var data = brush.get_meta("brush_entity_data", {})
	if data is Dictionary:
		var kept := {}
		for key in data:
			if names.has(str(key)):
				kept[key] = data[key]
		if kept.is_empty():
			brush.remove_meta("brush_entity_data")
		else:
			brush.set_meta("brush_entity_data", kept)
	var declared = definition.get("outputs", [])
	var outputs = brush.get_meta("entity_io_outputs", [])
	if declared is Array and outputs is Array:
		var wires: Array = []
		for wire in outputs:
			if wire is Dictionary and declared.has(str(wire.get("output_name", ""))):
				wires.append(wire)
		if wires.is_empty():
			brush.remove_meta("entity_io_outputs")
		else:
			brush.set_meta("entity_io_outputs", wires)


## The brushes that are one entity with `brush`, itself first. The rule is
## `HFBrushEntity.members()`, which the `.map` export groups by as well.
func brushes_of_entity(brush: DraftBrush) -> Array:
	return HFBrushEntity.members(brush, root._iter_managed_brush_nodes())


# ---------------------------------------------------------------------------
# UV Justify
# ---------------------------------------------------------------------------


## Every face in the face selection, with its brush and whether it has a layout
## of its own, as a corner dragged in the UV editor gives it.
func _selected_face_refs() -> Array:
	var face_refs: Array = []
	for key in root.face_selection.keys():
		var brush = _find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = root.face_selection.get(key, [])
		for idx in indices:
			var face_idx = int(idx)
			if face_idx >= 0 and face_idx < brush.faces.size():
				var face_data: FaceData = brush.faces[face_idx]
				(
					face_refs
					. append(
						{
							"brush": brush,
							"face": face_data,
							"had_layout": face_data.has_uv_layout(),
						}
					)
				)
	return face_refs


func justify_selected_faces(mode: String, treat_as_one: bool) -> void:
	var face_refs := _selected_face_refs()
	if face_refs.is_empty():
		return
	# A face in a texture group is one surface with the rest of its group, so the
	# whole group is justified as one, selected or not, and keeps the mode for an
	# edit that reshapes it to fit it again (#1437).
	var units: Array = []
	var loose: Array = []
	var grouped := {}
	for ref in face_refs:
		var group_id: int = (ref["face"] as FaceData).uv_group
		if group_id == 0:
			loose.append(ref)
		elif not grouped.has(group_id):
			grouped[group_id] = true
			units.append(_texture_group_refs(group_id))
	if treat_as_one and face_refs.size() > 1:
		var whole: Array = loose.duplicate()
		for unit in units:
			whole.append_array(unit)
		units = [whole]
	else:
		for ref in loose:
			units.append([ref])
	for unit in units:
		_justify_unit(unit, mode)


## Justify `refs` against the UV bounds of all of them together. A face in a texture
## group is measured and laid on by its group's mapping, a layout dragged by hand
## giving way, and keeps `mode`; any other face keeps a hand layout, moved (#654).
func _justify_unit(refs: Array, mode: String) -> void:
	var uv_min := Vector2(INF, INF)
	var uv_max := Vector2(-INF, -INF)
	for ref in refs:
		var face: FaceData = ref["face"]
		var uvs: PackedVector2Array = (
			face._project_uvs_for_vertices(face.local_verts)
			if face.uv_group != 0
			else face.shown_uvs()
		)
		for uv in uvs:
			uv_min = uv_min.min(uv)
			uv_max = uv_max.max(uv)
	for ref in refs:
		var face: FaceData = ref["face"]
		var before := face.to_dict()
		var keep_layout: bool = face.uv_group == 0 and bool(ref.get("had_layout", false))
		_justify_face(face, mode, uv_min, uv_max, keep_layout)
		if face.uv_group != 0:
			face.uv_group_justify = mode
			face.custom_uvs = PackedVector2Array()
		ref["brush"].rebuild_preview()
		if face.to_dict() != before:
			_tag_brush_node_dirty(ref["brush"])


## Move a hand-made UV layout the way the button says, instead of throwing it away.
##
## `custom_uvs` is per-vertex and in the same space the shift is measured in, so
## every mode is a scale and an offset over the points. `uv_offset` and
## `uv_scale` are deliberately left alone here: the layout already carries the
## result, and applying it to both would count it twice.
##
## The UV editor is what writes `custom_uvs`, so before this the two texturing
## tools in the dock silently undid each other (#654).
func _justify_layout(face: FaceData, mode: String, uv_min: Vector2, uv_max: Vector2) -> void:
	var uv_size := uv_max - uv_min
	var scale := Vector2.ONE
	var shift := Vector2.ZERO
	match mode:
		"fit":
			scale = Vector2(
				1.0 / uv_size.x if uv_size.x > 0.0001 else 1.0,
				1.0 / uv_size.y if uv_size.y > 0.0001 else 1.0
			)
			shift = -uv_min * scale
		"tile", "fit_u", "fit_v":
			var uniform := _one_repeat_scale(mode, uv_size)
			scale = Vector2(uniform, uniform)
			shift = _one_repeat_shift(mode, uv_min * uniform, uv_max * uniform)
		"center":
			shift = Vector2(0.5, 0.5) - (uv_min + uv_max) * 0.5
		"left":
			shift.x = -uv_min.x
		"right":
			shift.x = 1.0 - uv_max.x
		"top":
			shift.y = -uv_min.y
		"bottom":
			shift.y = 1.0 - uv_max.y
		_:
			return
	var moved := PackedVector2Array()
	for uv in face.custom_uvs:
		moved.append(uv * scale + shift)
	face.custom_uvs = moved


func _justify_face(
	face: FaceData, mode: String, uv_min: Vector2, uv_max: Vector2, keep_layout: bool = false
) -> void:
	var uv_size = uv_max - uv_min
	if uv_size.x < 0.0001 and uv_size.y < 0.0001:
		return

	# A face somebody laid out by hand keeps that layout, moved. Every branch
	# below ends by clearing `custom_uvs`, which drops the face back to its
	# projection -- so the shift measured from the hand-made rectangle was then
	# applied to a different one, and the mapper lost the alignment *and* did not
	# get the button's result (#654). For a face nobody has touched the two
	# rectangles are the same one, which is why this never showed up.
	if keep_layout:
		_justify_layout(face, mode, uv_min, uv_max)
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
		"tile", "fit_u", "fit_v":
			# One factor on both axes, so the texture keeps its aspect and the
			# other axis repeats as often as it has room for.
			var scale_uniform := _one_repeat_scale(mode, uv_size)
			face.uv_scale = face.uv_scale * scale_uniform
			var shift := _one_repeat_shift(mode, uv_min * scale_uniform, uv_max * scale_uniform)
			face.uv_offset = face.uv_offset * scale_uniform + shift
			face.custom_uvs = PackedVector2Array()


## The factor Tile, Fit U and Fit V scale a face by: the one that makes a single
## repeat span its shorter side, its width or its height.
static func _one_repeat_scale(mode: String, uv_size: Vector2) -> float:
	var side := minf(uv_size.x, uv_size.y)
	if mode == "fit_u":
		side = uv_size.x
	elif mode == "fit_v":
		side = uv_size.y
	return 1.0 / side if side > 0.0001 else 1.0


## Where those three put the face once scaled to `scaled_min`..`scaled_max`. Tile
## centres it on a repeat. Fit U and Fit V start it on one at its top left corner,
## as Fit does, so a wall four times as long as it is high takes four whole repeats.
static func _one_repeat_shift(mode: String, scaled_min: Vector2, scaled_max: Vector2) -> Vector2:
	if mode == "tile":
		return Vector2(0.5, 0.5) - (scaled_min + scaled_max) * 0.5
	return -scaled_min


## Lay every face in the face selection on `projection`, keeping its scale,
## offset and rotation: Align to Face with the Face projection and Align to World
## with Box UV (#1419). A face already on it is left as it is. A layout dragged
## by hand would hide the new projection, so a face that changes drops it.
## Returns how many faces changed.
func align_selected_faces(projection: int) -> int:
	var changed := 0
	var touched: Array = []
	var laid: Array = []
	for ref in _selected_face_refs():
		var face: FaceData = ref["face"]
		if face.uv_projection == projection:
			continue
		face.uv_projection = projection
		face.custom_uvs = PackedVector2Array()
		changed += 1
		laid.append(face)
		if not touched.has(ref["brush"]):
			touched.append(ref["brush"])
	for brush in touched:
		brush.rebuild_preview()
		_tag_brush_node_dirty(brush)
	spread_texture_groups(laid)
	return changed


## Wrap (#1428): give the face at `target_idx` of the brush `target_key` the
## texture the face at `source_idx` of `source_key` shows, run on over the edge
## the two share, through `HFUVWrap.solve()`. The target takes the source's
## texture and the solved projection, scale, rotation and offset; a layout laid
## by hand on it is replaced. Nothing but its texture and those changes, and
## nothing at all when it is refused. Returns what `solve()` returns.
func wrap_face_texture(
	source_key: String, source_idx: int, target_key: String, target_idx: int
) -> Dictionary:
	var source_brush := _find_brush_by_key(source_key)
	var target_brush := _find_brush_by_key(target_key)
	if (
		source_brush == null
		or target_brush == null
		or source_idx < 0
		or source_idx >= source_brush.faces.size()
		or target_idx < 0
		or target_idx >= target_brush.faces.size()
	):
		return {"ok": false, "reason": "no_shared_edge"}
	# Read where each brush stands now, as its transform notification would.
	source_brush.sync_face_world_transform()
	target_brush.sync_face_world_transform()
	var source: FaceData = source_brush.faces[source_idx]
	var target: FaceData = target_brush.faces[target_idx]
	var result := HFUVWrap.solve(source, target)
	if not bool(result.get("ok", false)):
		return result
	if not root.is_usable_uv_transform(result["scale"], result["offset"], result["rotation"]):
		return {"ok": false, "reason": "target_flat"}
	var before := target.to_dict()
	target.copy_texture_from(source)
	target.uv_projection = int(result["projection"])
	target.uv_scale = result["scale"]
	target.uv_rotation = float(result["rotation"])
	target.uv_offset = result["offset"]
	target.custom_uvs = PackedVector2Array()
	if target.to_dict() != before:
		target_brush.rebuild_preview()
		_tag_brush_node_dirty(target_brush)
		spread_texture_groups([target])
	return result


# ---------------------------------------------------------------------------
# Texture groups (#1437)
# ---------------------------------------------------------------------------

## The Justify modes that fit a texture to a surface's bounds. A group last
## justified with one is fitted again after an edit reshapes it.
const REFIT_MODES := ["fit", "fit_u", "fit_v", "tile"]


## Every face in texture group `group_id`, as `{"brush", "face"}`, in level order.
func _texture_group_refs(group_id: int) -> Array:
	var refs: Array = []
	if group_id == 0 or root.draft_brushes_node == null:
		return refs
	for child in root.draft_brushes_node.get_children():
		var brush := child as DraftBrush
		if brush == null:
			continue
		for face in brush.faces:
			if face != null and face.uv_group == group_id:
				refs.append({"brush": brush, "face": face})
	return refs


## The ids of the brushes besides `brush_ids` with a face in a texture group one of
## `brush_ids` has a face in. A step that changes one face of a group can change
## the rest, so its undo records these brushes as well.
func texture_group_mate_ids(brush_ids: Array) -> Array:
	var out: Array = []
	var groups := {}
	var named := {}
	for raw_id in brush_ids:
		named[str(raw_id)] = true
		var brush := _find_brush_by_key(str(raw_id))
		if brush == null:
			continue
		for face in brush.faces:
			if face != null and face.uv_group != 0:
				groups[face.uv_group] = true
	if groups.is_empty() or root.draft_brushes_node == null:
		return out
	for child in root.draft_brushes_node.get_children():
		var brush := child as DraftBrush
		if brush == null or brush.brush_id == "" or named.has(brush.brush_id):
			continue
		for face in brush.faces:
			if face != null and groups.has(face.uv_group):
				out.append(brush.brush_id)
				break
	return out


## A group id no face in the level has. Drawn at random rather than counted, so a
## face pasted into another level is unlikely to land in a group there, and kept
## under 2^31 so it reads back exactly from an `.hflevel`, whose numbers are floats.
func _new_texture_group_id() -> int:
	var used := {}
	if root.draft_brushes_node != null:
		for child in root.draft_brushes_node.get_children():
			var brush := child as DraftBrush
			if brush == null:
				continue
			for face in brush.faces:
				if face != null:
					used[face.uv_group] = true
	var group_id := 0
	while group_id == 0 or used.has(group_id):
		group_id = randi() & 0x7fffffff
	return group_id


## Link: put the selected faces in one texture group, each laid on the group's
## mapping so they read as one surface. The group is the one the first selected
## face is in, else the first another selected face is in, else a new one with the
## first face's mapping. A face leaves any other group, and a layout dragged by
## hand gives way. Returns how many faces it linked, 0 for fewer than two.
func link_selected_faces() -> int:
	var refs := _selected_face_refs()
	if refs.size() < 2:
		return 0
	var model: FaceData = refs[0]["face"]
	var primary := get_primary_selected_face()
	if not primary.is_empty():
		var primary_brush: DraftBrush = primary["brush"]
		model = primary_brush.faces[int(primary["face_idx"])]
	if model.uv_group == 0:
		for ref in refs:
			if (ref["face"] as FaceData).uv_group != 0:
				model = ref["face"]
				break
	var group_id := model.uv_group if model.uv_group != 0 else _new_texture_group_id()
	var justify := model.uv_group_justify if model.uv_group != 0 else ""
	var touched: Array = []
	for ref in refs:
		var face: FaceData = ref["face"]
		var before := face.to_dict()
		face.uv_group = group_id
		face.uv_group_justify = justify
		face.copy_mapping_from(model)
		face.custom_uvs = PackedVector2Array()
		if face.to_dict() != before and not touched.has(ref["brush"]):
			touched.append(ref["brush"])
	for brush in touched:
		brush.rebuild_preview()
		_tag_brush_node_dirty(brush)
	return refs.size()


## Unlink: the selected faces leave their texture groups, each showing what it
## showed. Returns how many were in one.
func unlink_selected_faces() -> int:
	var count := 0
	var touched: Array = []
	for ref in _selected_face_refs():
		var face: FaceData = ref["face"]
		if face.uv_group == 0:
			continue
		face.uv_group = 0
		face.uv_group_justify = ""
		count += 1
		if not touched.has(ref["brush"]):
			touched.append(ref["brush"])
	for brush in touched:
		_tag_brush_node_dirty(brush)
	return count


## Select Group: every face of the first selected face's texture group, in place of
## the face selection. Returns how many, 0 when that face is in none.
func select_texture_group() -> int:
	var primary := get_primary_selected_face()
	if primary.is_empty():
		return 0
	var brush: DraftBrush = primary["brush"]
	var face: FaceData = brush.faces[int(primary["face_idx"])]
	if face.uv_group == 0:
		return 0
	var refs := _texture_group_refs(face.uv_group)
	root.face_selection.clear()
	for ref in refs:
		var member_brush: DraftBrush = ref["brush"]
		toggle_face_selection(member_brush, member_brush.faces.find(ref["face"]), true, false)
	return refs.size()


## A texture group holds one mapping. After `faces` had theirs changed, every other
## face of their groups takes it, a layout dragged by hand on one giving way, and
## their brushes are rebuilt.
func spread_texture_groups(faces: Array) -> void:
	var spread := {}
	var touched: Array = []
	for candidate in faces:
		var source := candidate as FaceData
		if source == null or source.uv_group == 0 or spread.has(source.uv_group):
			continue
		spread[source.uv_group] = true
		for ref in _texture_group_refs(source.uv_group):
			var member: FaceData = ref["face"]
			if member == source:
				continue
			var laid := member.copy_mapping_from(source)
			if member.has_uv_layout():
				member.custom_uvs = PackedVector2Array()
				laid = true
			if laid and not touched.has(ref["brush"]):
				touched.append(ref["brush"])
	for brush in touched:
		brush.rebuild_preview()
		_tag_brush_node_dirty(brush)


## Fit again every texture group with a face on `brushes` whose last Justify was a
## fit, across all its faces as they now stand: after a move, a resize, a turn, a
## cut or a vertex edit has reshaped the surface. Returns how many groups.
func refit_texture_groups(brushes: Array) -> int:
	var modes := {}
	for candidate in brushes:
		var draft := candidate as DraftBrush
		if draft == null or not is_instance_valid(draft):
			continue
		for face in draft.faces:
			if face != null and face.uv_group != 0 and REFIT_MODES.has(face.uv_group_justify):
				modes[face.uv_group] = face.uv_group_justify
	for group_id in modes:
		var refs := _texture_group_refs(group_id)
		for ref in refs:
			(ref["brush"] as DraftBrush).sync_face_world_transform()
		_justify_unit(refs, modes[group_id])
	return modes.size()


# ---------------------------------------------------------------------------
# UV edits: scale x2 and /2, flip, rotate a quarter
# ---------------------------------------------------------------------------

## The smallest and largest size a face's UV scale is given by the Paint tab's
## Scale boxes, which are built from these. x2 and /2 stop there: /2 never reaches
## zero, which `is_usable_uv_transform()` refuses, and neither leaves a face with a
## scale its boxes cannot show.
const UV_SCALE_STEP := 0.01
const UV_SCALE_LIMIT := 100.0

## What `edit_selected_face_uvs()` takes.
const UV_EDITS := ["scale_up", "scale_down", "flip_u", "flip_v", "rotate_90"]


## Double or halve the UV scale, flip U or V, or turn the texture a quarter, on
## every face in the face selection.
##
## Each is a change to what the face's Scale and Rotate boxes hold, so it is made
## there, and the face's layout, when it has one, is moved the same way. Changing
## only the layout, as Justify does, would leave the boxes showing the old scale,
## and the next edit in them would reproject the face from it.
##
## Scale keeps the offset, as typing a scale does, so a run of faces that line up
## still line up. Flip and Rotate 90 turn about the middle of each face's UV
## rectangle, so the texture does not jump off the face.
func edit_selected_face_uvs(edit: String) -> void:
	if not UV_EDITS.has(edit):
		HFLog.warn("HFBrushSystem: '%s' is not a UV edit" % edit)
		return
	var groups_done := {}
	for ref in _selected_face_refs():
		var face: FaceData = ref["face"]
		# A texture group is edited once, as one surface, about its whole middle,
		# and its other faces take the result (#1437).
		var around := PackedVector2Array()
		if face.uv_group != 0:
			if groups_done.has(face.uv_group):
				continue
			groups_done[face.uv_group] = true
			for member in _texture_group_refs(face.uv_group):
				around.append_array((member["face"] as FaceData).shown_uvs())
		var before: Array = [face.uv_scale, face.uv_offset, face.uv_rotation, face.custom_uvs]
		_edit_face_uvs(face, edit, around)
		if [face.uv_scale, face.uv_offset, face.uv_rotation, face.custom_uvs] != before:
			ref["brush"].rebuild_preview()
			_tag_brush_node_dirty(ref["brush"])
			spread_texture_groups([face])


## A face's UV is `rotated(uv_rotation) * uv_scale + uv_offset` of its projection,
## so every edit here is a map of UV space, `map`, together with the new scale and
## rotation that make the projection come out as `map` of what it was. The offset
## is then `map` of the old offset, and a layout is `map` of the old layout.
func _edit_face_uvs(
	face: FaceData, edit: String, around: PackedVector2Array = PackedVector2Array()
) -> void:
	var scale := face.uv_scale
	if not scale.is_finite() or is_zero_approx(scale.x) or is_zero_approx(scale.y):
		# Nothing here can be divided by it. The boxes refuse such a scale, so it
		# came from somewhere else, and Re-project UVs is the way back.
		HFLog.warn("HFBrushSystem: a face with UV scale %s was left as it is" % str(scale))
		return
	var new_scale := scale
	var new_rotation := face.uv_rotation
	var map := Transform2D.IDENTITY
	var pivot := face.uv_offset
	match edit:
		"scale_up", "scale_down":
			var up := edit == "scale_up"
			new_scale = Vector2(_stepped_uv_scale(scale.x, up), _stepped_uv_scale(scale.y, up))
			map = Transform2D(
				Vector2(new_scale.x / scale.x, 0.0),
				Vector2(0.0, new_scale.y / scale.y),
				Vector2.ZERO
			)
		"flip_u":
			new_scale.x = -scale.x
			map = Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
			pivot = _uv_rect_centre(_uvs_turned_about(face, around))
		"flip_v":
			new_scale.y = -scale.y
			map = Transform2D(Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2.ZERO)
			pivot = _uv_rect_centre(_uvs_turned_about(face, around))
		"rotate_90":
			# A quarter more in Rotate. The scale is applied after the turn, so in
			# UV space the turn is seen through it: take the scale off, turn, and
			# put it back.
			new_rotation = wrapf(face.uv_rotation + PI * 0.5, -PI, PI)
			map = Transform2D(
				Vector2(0.0, scale.y / scale.x), Vector2(-scale.x / scale.y, 0.0), Vector2.ZERO
			)
			pivot = _uv_rect_centre(_uvs_turned_about(face, around))
	map.origin = pivot - map.basis_xform(pivot)
	face.uv_scale = new_scale
	face.uv_rotation = new_rotation
	face.uv_offset = map * face.uv_offset
	if face.has_uv_layout():
		face.custom_uvs = map * face.custom_uvs


## `value` doubled or halved, keeping its sign, and held to the Scale boxes'
## range. A value already past the edge is left where it is rather than moved
## the wrong way.
static func _stepped_uv_scale(value: float, up: bool) -> float:
	var size := absf(value)
	var stepped := (
		minf(size * 2.0, maxf(size, UV_SCALE_LIMIT))
		if up
		else maxf(size * 0.5, minf(size, UV_SCALE_STEP))
	)
	return stepped if value >= 0.0 else -stepped


## The UVs a flip or a quarter turn goes about the middle of: `around` when given,
## a texture group's whole surface, else the face's own.
static func _uvs_turned_about(face: FaceData, around: PackedVector2Array) -> PackedVector2Array:
	return around if not around.is_empty() else face.shown_uvs()


static func _uv_rect_centre(uvs: PackedVector2Array) -> Vector2:
	if uvs.is_empty():
		return Vector2.ZERO
	var low := uvs[0]
	var high := uvs[0]
	for uv in uvs:
		low = low.min(uv)
		high = high.max(uv)
	return (low + high) * 0.5


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
	# The shape leaves out what the paint masks hold, and a wall starts with its
	# solid's paint, so a stroke on it needs this to be seen (#869).
	var wall_paint: Array = []
	for info in wall_infos:
		var wall_id := str(info.get("brush_id", ""))
		if wall_id == "":
			continue
		wall_ids.append(wall_id)
		wall_transforms.append(info.get("transform", Transform3D.IDENTITY))
		var wall = _brush_cache.get(wall_id)
		wall_shapes.append(HFDuplicator.shape_signature(wall))
		wall_paint.append(HFDuplicator.paint_signature(wall))
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
		"wall_paint": wall_paint,
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
## A wall is a hand edit when it is no longer the shape it was made as, when its
## paint masks no longer hold what they did, or when it is no longer where it was
## put. These are read separately because they fail separately: a resized wall has
## not moved, a dragged one is still its own shape, and a stroke inside a layer
## the wall started with changes neither.
##
## Movement is read against what a re-shell would actually do. When every wall
## agrees on one move the whole room has been relocated, `update_hollow()` rebuilds
## it where it now stands, and nothing is lost — so a relocation counts nothing.
## When they disagree the rebuild goes back to the recorded placement, and then any
## wall standing anywhere else is about to be moved back.
##
## Records written before any of these fields answer "cannot tell" for that part
## rather than guessing, which is what lets an older level load and re-shell
## unmigrated.
func edited_hollow_walls(hollow_id: String) -> int:
	if not _hollows.has(hollow_id):
		return 0
	var record: Dictionary = _hollows[hollow_id]
	var ids: Array = record.get("wall_ids", [])
	var placed: Array = record.get("wall_transforms", [])
	var shapes: Array = record.get("wall_shapes", [])
	var paint: Array = record.get("wall_paint", [])
	var placements_known: bool = placed.size() == ids.size() and not ids.is_empty()
	var paint_known: bool = paint.size() == ids.size()
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
		if paint_known and HFDuplicator.paint_signature(wall) != str(paint[i]):
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
		_take_old_wall_shapes_again(record)


## A wall saved before #879 lists its faces the way the cut made them, and it is
## put into the box builder's order as it loads, so the shape recorded over the
## old order no longer matches it though nobody touched it, and every wall of an
## older box hollow read as reworked (#878). A wall whose faces as loaded still
## match the record was untouched when it was saved, and only that wall's record
## is taken again. A wall edited before the save still counts.
func _take_old_wall_shapes_again(record: Dictionary) -> void:
	var ids: Array = record.get("wall_ids", [])
	var shapes: Array = record.get("wall_shapes", [])
	for i in mini(ids.size(), shapes.size()):
		var wall = _brush_cache.get(str(ids[i]))
		if not (wall is DraftBrush) or wall.faces_as_loaded.is_empty():
			continue
		var now := HFDuplicator.shape_signature(wall)
		if (
			now != str(shapes[i])
			and HFDuplicator.shape_signature(wall, wall.faces_as_loaded) == str(shapes[i])
		):
			shapes[i] = now


## Let go of the faces box pieces kept as they were loaded, once the records that
## needed them are back.
func forget_faces_as_loaded() -> void:
	for brush in _brush_cache.values():
		if brush is DraftBrush and is_instance_valid(brush):
			(brush as DraftBrush).faces_as_loaded = []


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
	if not HFDuplicator.can_generate(p_count, brush_ids.size(), {"offset": p_offset}).ok:
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
	if not (
		HFDuplicator
		. can_generate(
			p_count, brush_ids.size(), {"step_degrees": step_degrees, "pivot": pivot, "rise": rise}
		)
		. ok
	):
		return null
	var dup := _new_duplicator_for(brush_ids)
	if not dup.generate_radial(self, p_count, axis_index, step_degrees, pivot, rise):
		return null
	_duplicators[dup.duplicator_id] = dup
	return dup


## Lattice of copies. `counts` includes the source cell on each axis.
func create_grid_array(brush_ids: PackedStringArray, counts: Vector3i, spacing: Vector3) -> Variant:
	if not (
		HFDuplicator
		. can_generate(HFDuplicator.grid_copy_count(counts), brush_ids.size(), {"spacing": spacing})
		. ok
	):
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
		. can_generate(dup.requested_copy_count(mode, params), dup.source_brush_ids.size(), params)
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
