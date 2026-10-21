@tool
class_name HFPivotMarker
extends RefCounted
## The cross at the picked pivot, drawn while the level's Pivot is Pick, so the
## point Rotate, Flip and the radial array turn about is always in view. Without
## it a pivot picked a while ago is a number on the level and nowhere on screen.
##
## The plugin holds one and points it at the level it is editing, as it does the
## face selection's mark. It draws on an ImmediateMesh hung off that level as an
## internal child with no owner: never saved, never listed in the Scene tree,
## never copied with the level. The node is made while the mode is Pick, and freed
## when it is not, when the plugin points it at another level and when the plugin
## goes.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFTransformSystem = preload("systems/hf_transform_system.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Cyan, a colour no selection or hover uses.
const COLOR := Color(0.2, 0.9, 1.0, 1.0)
## Half the length of each arm, in world units. A little larger than the vertex
## handles' 0.4, so a pivot on a vertex shows past the handle drawn there.
const ARM := 0.6
const NODE_NAME := &"_PivotMarker"

var _watched_root: WeakRef = null
var _mesh_instance: MeshInstance3D = null
var _mesh: ImmediateMesh = null


## Mark the pivot of [param root] from now on, taking the mark off the level it
## was on. Null marks nothing.
func watch(root: Node) -> void:
	if root != null and not is_instance_valid(root):
		root = null
	if root != null and root == _root():
		return
	_stop_watching()
	if root != null and root.has_signal("transform_pivot_changed"):
		root.connect("transform_pivot_changed", refresh)
		_watched_root = weakref(root)
	refresh()


## Stop marking and take the mark down, as the plugin does on its way out.
func reset() -> void:
	_stop_watching()


## Draw the cross where the watched level's pivot is, or take it down when the
## level's Pivot is not Pick.
func refresh() -> void:
	var root := _root()
	if (
		root == null
		or not root.is_inside_tree()
		or int(root.get("transform_pivot_mode")) != HFTransformSystem.PivotMode.CUSTOM
	):
		_free_mesh_instance()
		return
	var point: Vector3 = root.get("transform_pivot_point")
	_ensure_mesh_instance(root)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(COLOR)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_mesh.surface_add_vertex(point - axis * ARM)
		_mesh.surface_add_vertex(point + axis * ARM)
	_mesh.surface_end()


## The node the cross is drawn on, or null while there is none.
func get_mesh_instance() -> MeshInstance3D:
	return _mesh_instance if is_instance_valid(_mesh_instance) else null


func _ensure_mesh_instance(root: Node) -> void:
	if is_instance_valid(_mesh_instance) and _mesh_instance.get_parent() == root:
		return
	_free_mesh_instance()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = NODE_NAME
	# The point is world space, so the level's own transform must not move it.
	_mesh_instance.top_level = true
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	# Over everything, so a pivot behind a wall still shows where it is.
	material.no_depth_test = true
	_mesh_instance.material_override = material
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	root.add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)


func _free_mesh_instance() -> void:
	if is_instance_valid(_mesh_instance):
		var parent := _mesh_instance.get_parent()
		if parent:
			parent.remove_child(_mesh_instance)
		_mesh_instance.free()
	_mesh_instance = null
	_mesh = null


func _stop_watching() -> void:
	var root := _root()
	if root != null and root.is_connected("transform_pivot_changed", refresh):
		root.disconnect("transform_pivot_changed", refresh)
	_watched_root = null
	_free_mesh_instance()


func _root() -> Node:
	if _watched_root == null:
		return null
	return _watched_root.get_ref() as Node
