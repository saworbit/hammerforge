@tool
class_name HFSubtractPreview
extends "hf_system.gd"
## Live subtract overlay. Broad-phase AABB finds overlapping additive/subtract
## DraftBrushes, then CSG intersection shows the actual cut volume. AABB
## wireframes stay as a fallback when CSG is pending, capped, or empty.

const DraftBrush = preload("../brush_instance.gd")

var _preview_container: Node3D
var _mesh_pool: Array = []  # Array[MeshInstance3D]
var _active_count: int = 0
var _needs_rebuild: bool = false
var _debounce: float = 0.0
var _material: StandardMaterial3D
var _csg_material: StandardMaterial3D
var _csg_scratch: Array = []  # Array[CSGCombiner3D]
var _csg_wait_frames: int = 0
var _csg_result_count: int = 0

const DEBOUNCE_SEC := 0.15
const MAX_PREVIEWS := 50
const MAX_CSG_SUBTRACTORS := 8
const CSG_WAIT_FRAMES := 2


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 0.3, 0.3, 0.45)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_csg_material = StandardMaterial3D.new()
	_csg_material.albedo_color = Color(1.0, 0.2, 0.15, 0.55)
	_csg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_csg_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_csg_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_csg_material.no_depth_test = true


func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	if _enabled:
		_ensure_container()
		_connect_signals()
		request_update()
	else:
		_disconnect_signals()
		clear()


func is_enabled() -> bool:
	return _enabled


func request_update() -> void:
	_needs_rebuild = true
	_debounce = DEBOUNCE_SEC


func process(delta: float) -> void:
	if _csg_wait_frames > 0:
		_csg_wait_frames -= 1
		if _csg_wait_frames == 0:
			_capture_csg_results()
	if not _needs_rebuild:
		return
	_debounce -= delta
	if _debounce > 0.0:
		return
	_needs_rebuild = false
	_rebuild()


func clear() -> void:
	_free_csg_scratch()
	_csg_result_count = 0
	for i in _mesh_pool.size():
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false
	_active_count = 0
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = false


## Free all pooled meshes and the container node.  Call when the preview
## system is no longer needed (plugin unload, scene change, etc.).
## Uses immediate free() rather than queue_free() so that nodes are not
## orphaned during tree teardown where the next frame may never arrive.
func destroy() -> void:
	_disconnect_signals()
	_free_csg_scratch()
	_mesh_pool.clear()
	_active_count = 0
	_csg_result_count = 0
	if _preview_container and is_instance_valid(_preview_container):
		if _preview_container.get_parent():
			_preview_container.get_parent().remove_child(_preview_container)
		_preview_container.free()
	_preview_container = null
	_enabled = false


func _ensure_container() -> void:
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = true
		return
	_preview_container = Node3D.new()
	_preview_container.name = "SubtractPreview"
	root.add_child(_preview_container)


func _connect_signals() -> void:
	if not root:
		return
	var signals := ["brush_added", "brush_removed", "brush_changed"]
	for sig in signals:
		if root.has_signal(sig) and not root.is_connected(sig, Callable(self, "_on_brush_event")):
			root.connect(sig, Callable(self, "_on_brush_event"))


func _disconnect_signals() -> void:
	if not root:
		return
	var signals := ["brush_added", "brush_removed", "brush_changed"]
	for sig in signals:
		if root.has_signal(sig) and root.is_connected(sig, Callable(self, "_on_brush_event")):
			root.disconnect(sig, Callable(self, "_on_brush_event"))


func _on_brush_event(_arg = null) -> void:
	request_update()


func _rebuild() -> void:
	if not root:
		clear()
		return
	var draft_node = root.get("draft_brushes_node")
	if not draft_node:
		clear()
		return

	var subtractive: Array = []
	var additive: Array = []
	for child in draft_node.get_children():
		var op := preview_operation(child)
		if op == CSGShape3D.OPERATION_SUBTRACTION:
			subtractive.append(child)
		elif op == CSGShape3D.OPERATION_UNION:
			additive.append(child)

	var groups: Array = collect_cut_groups(subtractive, additive)
	var intersections: Array = []
	for group in groups:
		if group is Dictionary and group.has("aabb"):
			intersections.append(group["aabb"])
			if intersections.size() >= MAX_PREVIEWS:
				break

	_ensure_container()
	_show_aabb_wireframes(intersections)
	_begin_csg_preview(groups)


## Pair each subtractor with overlapping additives. Each group has the
## subtractor, additive list, and union of pair AABBs for the wireframe fallback.
static func collect_cut_groups(subtractive: Array, additive: Array) -> Array:
	var groups: Array = []
	for sub in subtractive:
		if not sub is Node3D:
			continue
		var sub_aabb: AABB = world_aabb(sub)
		var adds: Array = []
		var union_aabb := AABB()
		var have_union := false
		for add in additive:
			if not add is Node3D:
				continue
			var add_aabb: AABB = world_aabb(add)
			var isect: AABB = get_intersection_aabb(sub_aabb, add_aabb)
			if not is_valid_aabb(isect):
				continue
			adds.append(add)
			if have_union:
				union_aabb = union_aabb.merge(isect)
			else:
				union_aabb = isect
				have_union = true
			if adds.size() + groups.size() >= MAX_PREVIEWS:
				break
		if adds.is_empty():
			continue
		groups.append({"sub": sub, "adds": adds, "aabb": union_aabb})
		if groups.size() >= MAX_PREVIEWS:
			break
	return groups


func _show_aabb_wireframes(intersections: Array) -> void:
	while _mesh_pool.size() < intersections.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material
		_preview_container.add_child(mi)
		_mesh_pool.append(mi)

	for i in intersections.size():
		var mi: MeshInstance3D = _mesh_pool[i]
		mi.mesh = _build_wireframe_mesh(intersections[i])
		mi.material_override = _material
		mi.transform = Transform3D.IDENTITY
		mi.visible = true

	for i in range(intersections.size(), _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false

	_active_count = intersections.size()
	_csg_result_count = 0
	_preview_container.visible = _active_count > 0


func _begin_csg_preview(groups: Array) -> void:
	_free_csg_scratch()
	if not root or not root.is_inside_tree():
		return
	var started := 0
	for group in groups:
		if started >= MAX_CSG_SUBTRACTORS:
			break
		if not group is Dictionary:
			continue
		if _start_cut_combiner(group):
			started += 1
	if started > 0:
		_csg_wait_frames = CSG_WAIT_FRAMES


func _start_cut_combiner(group: Dictionary) -> bool:
	var sub: Node3D = group.get("sub") as Node3D
	var adds: Array = group.get("adds", [])
	if sub == null or adds.is_empty():
		return false
	var combiner := CSGCombiner3D.new()
	combiner.name = "SubtractPreviewCSG"
	combiner.visible = false
	combiner.use_collision = false
	root.add_child(combiner)
	for add in adds:
		var add_csg := mesh_to_csg(add as Node3D, CSGShape3D.OPERATION_UNION)
		if add_csg:
			_add_csg_child(combiner, add_csg)
	var sub_csg := mesh_to_csg(sub, CSGShape3D.OPERATION_INTERSECTION)
	if sub_csg == null or combiner.get_child_count() == 0:
		combiner.get_parent().remove_child(combiner)
		combiner.free()
		return false
	_add_csg_child(combiner, sub_csg)
	_csg_scratch.append(combiner)
	return true


func _add_csg_child(combiner: CSGCombiner3D, csg: CSGMesh3D) -> void:
	var world_xform: Transform3D = csg.get_meta("world_xform", csg.transform)
	combiner.add_child(csg)
	csg.global_transform = world_xform


func _capture_csg_results() -> void:
	var result_meshes: Array = []
	for combiner in _csg_scratch:
		if not is_instance_valid(combiner):
			continue
		var extracted: Array = extract_csg_meshes(combiner)
		for item in extracted:
			result_meshes.append(item)
	_free_csg_scratch()
	if result_meshes.is_empty():
		return
	_ensure_container()
	var needed := result_meshes.size()
	while _mesh_pool.size() < needed:
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview_container.add_child(mi)
		_mesh_pool.append(mi)
	for i in needed:
		var item: Dictionary = result_meshes[i]
		var mi: MeshInstance3D = _mesh_pool[i]
		mi.mesh = item.get("mesh")
		mi.transform = item.get("transform", Transform3D.IDENTITY)
		mi.material_override = _csg_material
		mi.visible = true
	for i in range(needed, _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false
	_active_count = needed
	_csg_result_count = needed
	_preview_container.visible = needed > 0


func _free_csg_scratch() -> void:
	_csg_wait_frames = 0
	for combiner in _csg_scratch:
		if is_instance_valid(combiner):
			if combiner.get_parent():
				combiner.get_parent().remove_child(combiner)
			combiner.free()
	_csg_scratch.clear()


## Pull Mesh/Transform pairs from CSGShape3D.get_meshes() (flat or nested).
static func extract_csg_meshes(csg: CSGShape3D) -> Array:
	var out: Array = []
	if csg == null:
		return out
	var entries: Array = csg.get_meshes()
	if entries.is_empty():
		return out
	if entries.size() >= 2 and entries[0] is Transform3D and entries[1] is Mesh:
		out.append({"transform": entries[0], "mesh": entries[1]})
		return out
	for entry in entries:
		var mesh: Mesh = null
		var mesh_xform := Transform3D.IDENTITY
		if entry is Mesh:
			mesh = entry
		elif entry is Array:
			if entry.size() > 0 and entry[0] is Transform3D:
				mesh_xform = entry[0]
			if entry.size() > 1 and entry[1] is Mesh:
				mesh = entry[1]
			elif entry.size() > 0 and entry[0] is Mesh:
				mesh = entry[0]
			if entry.size() > 1 and entry[1] is Transform3D:
				mesh_xform = entry[1]
		if mesh:
			out.append({"transform": mesh_xform, "mesh": mesh})
	return out


static func mesh_to_csg(node: Node3D, operation: int) -> CSGMesh3D:
	if node == null:
		return null
	var mi: MeshInstance3D = null
	if node is DraftBrush:
		mi = (node as DraftBrush).mesh_instance
	elif node is MeshInstance3D:
		mi = node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	var csg := CSGMesh3D.new()
	csg.mesh = mi.mesh
	csg.operation = operation
	csg.use_collision = false
	csg.set_meta("world_xform", mi.global_transform)
	return csg


## Compute the intersection of two AABBs. Returns a zero-size AABB if none.
static func get_intersection_aabb(a: AABB, b: AABB) -> AABB:
	var min_pt := Vector3(
		maxf(a.position.x, b.position.x),
		maxf(a.position.y, b.position.y),
		maxf(a.position.z, b.position.z),
	)
	var a_end := a.position + a.size
	var b_end := b.position + b.size
	var max_pt := Vector3(
		minf(a_end.x, b_end.x),
		minf(a_end.y, b_end.y),
		minf(a_end.z, b_end.z),
	)
	var size := max_pt - min_pt
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return AABB()
	return AABB(min_pt, size)


static func is_valid_aabb(aabb: AABB) -> bool:
	return aabb.size.x > 0.001 and aabb.size.y > 0.001 and aabb.size.z > 0.001


static func _is_valid_aabb(aabb: AABB) -> bool:
	return is_valid_aabb(aabb)


## Operation used for subtract preview. DraftBrush stores CSG operation ints.
## Returns -1 when the node is not a previewable brush.
static func preview_operation(node: Node) -> int:
	if node is DraftBrush:
		return int((node as DraftBrush).operation)
	if node is CSGShape3D:
		return int((node as CSGShape3D).operation)
	return -1


static func world_aabb(node: Node3D) -> AABB:
	var xform := node.transform
	if node.is_inside_tree():
		xform = node.global_transform
	if node is DraftBrush:
		var draft := node as DraftBrush
		if (
			draft.mesh_instance
			and is_instance_valid(draft.mesh_instance)
			and draft.mesh_instance.mesh
		):
			var mesh_xform := xform * draft.mesh_instance.transform
			if draft.mesh_instance.is_inside_tree():
				mesh_xform = draft.mesh_instance.global_transform
			return mesh_xform * draft.mesh_instance.mesh.get_aabb()
		var half := draft.size * 0.5
		return AABB(xform.origin - half, draft.size)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var mi_xform := xform
		if mi.is_inside_tree():
			mi_xform = mi.global_transform
		return mi_xform * mi.mesh.get_aabb()
	if node.has_method("get_aabb"):
		var local_aabb: AABB = node.get_aabb()
		return xform * local_aabb
	var half_scale := node.scale * 0.5
	return AABB(xform.origin - half_scale, node.scale)


func _get_world_aabb(node: Node3D) -> AABB:
	return world_aabb(node)


func _build_wireframe_mesh(aabb: AABB) -> ImmediateMesh:
	var im = ImmediateMesh.new()
	var min_pt = aabb.position
	var max_pt = aabb.position + aabb.size
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners = [
		Vector3(min_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, max_pt.y, max_pt.z),
		Vector3(min_pt.x, max_pt.y, max_pt.z),
	]
	var edges = [
		[0, 1],
		[1, 2],
		[2, 3],
		[3, 0],
		[4, 5],
		[5, 6],
		[6, 7],
		[7, 4],
		[0, 4],
		[1, 5],
		[2, 6],
		[3, 7],
	]
	for edge in edges:
		im.surface_add_vertex(corners[edge[0]])
		im.surface_add_vertex(corners[edge[1]])
	im.surface_end()
	return im
