@tool
class_name HFSubtractPreview
extends RefCounted
## Real-time wireframe overlay showing AABB intersections between
## subtractive and additive brushes.  Reuses the cordon-wireframe
## ImmediateMesh pattern from level_root.gd.

var root: Node3D  # LevelRoot — untyped to avoid circular preload

var _preview_container: Node3D
var _mesh_pool: Array = []  # Array[MeshInstance3D]
var _active_count: int = 0
var _needs_rebuild: bool = false
var _debounce: float = 0.0
var _enabled: bool = false
var _material: StandardMaterial3D

const DEBOUNCE_SEC := 0.15
const MAX_PREVIEWS := 50


func _init(p_root: Node3D) -> void:
	root = p_root
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 0.3, 0.3, 0.7)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true


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
	if not _needs_rebuild:
		return
	_debounce -= delta
	if _debounce > 0.0:
		return
	_needs_rebuild = false
	_rebuild()


func clear() -> void:
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
	# Free pool children via the container (they are parented to it), then
	# free the container itself.  No need to remove_child individually —
	# freeing the container takes its children with it.
	_mesh_pool.clear()
	_active_count = 0
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
		if not child is CSGShape3D:
			continue
		if child.operation == CSGShape3D.OPERATION_SUBTRACTION:
			subtractive.append(child)
		elif child.operation == CSGShape3D.OPERATION_UNION:
			additive.append(child)

	var intersections: Array = []  # Array[AABB]
	for sub in subtractive:
		var sub_aabb: AABB = _get_world_aabb(sub)
		for add in additive:
			var add_aabb: AABB = _get_world_aabb(add)
			var isect: AABB = get_intersection_aabb(sub_aabb, add_aabb)
			if _is_valid_aabb(isect):
				intersections.append(isect)
				if intersections.size() >= MAX_PREVIEWS:
					break
		if intersections.size() >= MAX_PREVIEWS:
			break

	_ensure_container()

	# Grow pool if needed
	while _mesh_pool.size() < intersections.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material
		_preview_container.add_child(mi)
		_mesh_pool.append(mi)

	# Update active wireframes
	for i in intersections.size():
		var mi: MeshInstance3D = _mesh_pool[i]
		mi.mesh = _build_wireframe_mesh(intersections[i])
		mi.visible = true

	# Hide unused
	for i in range(intersections.size(), _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false

	_active_count = intersections.size()
	_preview_container.visible = _active_count > 0


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


static func _is_valid_aabb(aabb: AABB) -> bool:
	return aabb.size.x > 0.001 and aabb.size.y > 0.001 and aabb.size.z > 0.001


func _get_world_aabb(node: Node3D) -> AABB:
	if node.has_method("get_aabb"):
		var local_aabb: AABB = node.get_aabb()
		return node.global_transform * local_aabb
	# Fallback: use position ± half scale
	var pos := node.global_position
	var half := node.scale * 0.5
	return AABB(pos - half, node.scale)


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
