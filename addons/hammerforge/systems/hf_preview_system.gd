@tool
class_name HFPreviewSystem
extends "hf_system.gd"
## Shared mechanics for the overlays that show geometry before it exists.
##
## Six previews — hollow, carve, clip, subtract, structure and array — each owned
## a container node, a set of `MeshInstance3D`, a ghost material and a teardown,
## and each wrote all four out again. Two of them even called the container by a
## different name from the other four.
##
## That duplication is what let four of them drift into placing their meshes in
## the wrong space: each was fixed on its own, because there was nowhere to fix
## it once. `tests/test_preview_placement.gd` holds the property they share; this
## holds the mechanics, so the next preview inherits them rather than copying
## them.
##
## What stays with each preview is what actually differs: what it draws, what
## colour it draws in, and how it decides there is nothing to draw.

var _preview_container: Node3D
## Every `MeshInstance3D` this preview has made, whether it addresses them by
## index or keeps named references alongside. Hiding and freeing go through the
## pool, so a preview cannot leave one of its own meshes on screen.
var _mesh_pool: Array = []


## The name the container carries in the scene tree, so the tree still says which
## overlay a node belongs to. Overridden by each preview.
func _preview_name() -> String:
	return "Preview"


## A pale, unshaded, always-on-top material for geometry that does not exist yet.
##
## Depth testing is off in every one of them on purpose: a ghost you cannot see
## because the solid it is about to replace is in front of it is not a preview.
static func ghost_material(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## The container, made on first use and shown.
##
## Overridable, because a preview whose meshes are named rather than indexed makes
## them here. Anything the base needs the container for goes through
## `_build_container()` instead, so an override that makes meshes cannot be
## re-entered by the making of them.
func _ensure_container() -> void:
	_build_container()


func _build_container() -> void:
	if is_instance_valid(_preview_container):
		_preview_container.visible = true
		return
	if not is_instance_valid(root):
		return
	_preview_container = Node3D.new()
	_preview_container.name = _preview_name()
	root.add_child(_preview_container)


## One more mesh under the container, remembered in the pool.
func _make_mesh(material: Material) -> MeshInstance3D:
	_build_container()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = material
	if is_instance_valid(_preview_container):
		_preview_container.add_child(mesh_instance)
	_mesh_pool.append(mesh_instance)
	return mesh_instance


## Grow the pool to `count` meshes, all sharing one material.
func _grow_pool(count: int, material: Material) -> void:
	while _mesh_pool.size() < count:
		_make_mesh(material)


## Hide every mesh from `index` on, which is how a preview that drew fewer pieces
## this time puts the leftovers away without freeing them.
func _hide_meshes_from(index: int) -> void:
	for i in range(maxi(0, index), _mesh_pool.size()):
		if is_instance_valid(_mesh_pool[i]):
			_mesh_pool[i].visible = false


func clear() -> void:
	_enabled = false
	_hide_meshes_from(0)
	if is_instance_valid(_preview_container):
		_preview_container.visible = false


func set_enabled(value: bool) -> void:
	if value:
		_enabled = true
		_ensure_container()
	else:
		clear()


## Free the container and everything under it.
##
## `remove_child()` before `free()`, and `free()` rather than `queue_free()`:
## teardown can be the last thing that happens to this tree, and a frame that
## never arrives cannot collect a queued node.
func destroy() -> void:
	_enabled = false
	_mesh_pool.clear()
	if is_instance_valid(_preview_container):
		if _preview_container.get_parent():
			_preview_container.get_parent().remove_child(_preview_container)
		_preview_container.free()
	_preview_container = null
