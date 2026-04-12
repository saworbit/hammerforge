@tool
class_name HFCarvePreview
extends RefCounted
## Real-time wireframe preview showing the resulting slice pieces that would
## be created by a carve operation.  Uses the same ImmediateMesh wireframe
## pattern as HFSubtractPreview, but draws the 1-6 remaining pieces in green
## rather than the intersection volume in red.

const DraftBrush = preload("../brush_instance.gd")

var root: Node3D  # LevelRoot — untyped to avoid circular preload

var _preview_container: Node3D
var _mesh_pool: Array = []  # Array[MeshInstance3D]
var _active_count: int = 0
var _material: StandardMaterial3D
var _enabled: bool = false

## Currently previewing carve for this brush ID. Empty string = inactive.
var _carver_id: String = ""

const MAX_PREVIEWS := 50


func _init(p_root: Node3D) -> void:
	root = p_root
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.3, 0.9, 0.3, 0.6)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true


func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	if _enabled:
		_ensure_container()
	else:
		clear()


func is_enabled() -> bool:
	return _enabled


## Show preview for a specific carver brush.
func show_preview(carver_id: String) -> void:
	_carver_id = carver_id
	set_enabled(true)
	_rebuild()


## Hide the preview and reset state.
func clear() -> void:
	_carver_id = ""
	for i in _mesh_pool.size():
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false
	_active_count = 0
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = false


## Free all resources immediately.
func destroy() -> void:
	_mesh_pool.clear()
	_active_count = 0
	if _preview_container and is_instance_valid(_preview_container):
		if _preview_container.get_parent():
			_preview_container.get_parent().remove_child(_preview_container)
		_preview_container.free()
	_preview_container = null
	_enabled = false


## Compute and display preview slices for the current carver brush.
func _rebuild() -> void:
	if not root or _carver_id == "":
		clear()
		return

	var carver = root.brush_system.find_brush_by_id(_carver_id)
	if not carver or not (carver is DraftBrush):
		clear()
		return

	var carver_draft := carver as DraftBrush
	var carver_pos: Vector3 = carver_draft.global_position
	var carver_size: Vector3 = carver_draft.size
	var carver_aabb := AABB(carver_pos - carver_size * 0.5, carver_size)

	# Find overlapping targets — reuse carve_system logic
	var targets: Array = root.carve_system._find_overlapping_brushes(_carver_id, carver_aabb)

	var all_slices: Array = []  # Array[AABB]

	for target in targets:
		var target_draft := target as DraftBrush
		var target_pos: Vector3 = target_draft.global_position
		var target_size: Vector3 = target_draft.size
		var target_aabb := AABB(target_pos - target_size * 0.5, target_size)

		var inter := target_aabb.intersection(carver_aabb)
		if inter.size.x <= 0.01 or inter.size.y <= 0.01 or inter.size.z <= 0.01:
			continue

		# Compute slice boxes
		var slices: Array = root.carve_system._compute_slices(
			target_pos, target_size, carver_pos, carver_size
		)
		for slice_info in slices:
			var s_size: Vector3 = slice_info["size"]
			var s_center: Vector3 = slice_info["center"]
			all_slices.append(AABB(s_center - s_size * 0.5, s_size))
			if all_slices.size() >= MAX_PREVIEWS:
				break
		if all_slices.size() >= MAX_PREVIEWS:
			break

	# Also draw the carved-out volume in a dimmer color (handled by subtract_preview)
	# We only draw the resulting pieces here.

	_ensure_container()

	# Grow pool if needed
	while _mesh_pool.size() < all_slices.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material
		_preview_container.add_child(mi)
		_mesh_pool.append(mi)

	# Update active wireframes
	for i in all_slices.size():
		var mi: MeshInstance3D = _mesh_pool[i]
		mi.mesh = _build_wireframe_mesh(all_slices[i])
		mi.visible = true

	# Hide unused
	for i in range(all_slices.size(), _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false

	_active_count = all_slices.size()
	_preview_container.visible = _active_count > 0


func _ensure_container() -> void:
	if _preview_container and is_instance_valid(_preview_container):
		_preview_container.visible = true
		return
	_preview_container = Node3D.new()
	_preview_container.name = "CarvePreview"
	root.add_child(_preview_container)


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
