@tool
class_name HFFaceSelectionOverlay
extends RefCounted
## The mark on each face picked in Face Select: a see-through fill with an
## outline, drawn from `LevelRoot.face_selection` (#1491). Without it a mapper saw
## a face count and nothing in the viewport, so could not tell which faces a
## material, Justify or Clip was about to act on.
##
## The plugin holds one and points it at the level it is editing. It draws on an
## ImmediateMesh, as the vertex overlay does, hung off that level as an internal
## child with no owner: never saved, never listed in the Scene tree, never copied
## with the level. The node is made when there is a face to mark, and freed when
## there is none, when the plugin points it at another level and when the plugin
## goes.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFOverlayColors = preload("hf_overlay_colors.gd")

const NODE_NAME := &"_FaceSelectionOverlay"

var _watched_root: WeakRef = null
var _mesh_instance: MeshInstance3D = null
var _mesh: ImmediateMesh = null
## One per face the mark covers, `{"key", "face_idx", "points"}`, the points
## being the face's corners in world space.
var _entries: Array[Dictionary] = []
var _refresh_queued := false


## Mark the faces of [param root] from now on, taking the mark off the level it
## was on. Null marks nothing.
func watch(root: Node) -> void:
	if root != null and not is_instance_valid(root):
		root = null
	if root != null and root == _root():
		return
	_stop_watching()
	if root != null and root.has_signal("face_selection_changed"):
		root.connect("face_selection_changed", _on_face_selection_changed)
		root.connect("state_loaded", _on_face_selection_changed)
		root.connect("brush_changed", _on_brush_changed)
		_watched_root = weakref(root)
	refresh()


## Stop marking and take the mark down, as the plugin does on its way out.
func reset() -> void:
	_stop_watching()


## Redraw once the frame's changes are in. A nudge of a hundred brushes tags each
## of them, and one redraw covers the lot.
func queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_run_queued_refresh.call_deferred()


## Redraw the mark from the watched level's face selection.
func refresh() -> void:
	_entries.clear()
	var root := _root()
	# Off the tree, a brush has no global transform to read, and nothing would
	# show the mark anyway.
	if root == null or not root.is_inside_tree():
		_clear()
		return
	var selection = root.get("face_selection")
	if not (selection is Dictionary):
		_clear()
		return
	var fill := PackedVector3Array()
	for key in (selection as Dictionary).keys():
		# A key can name a brush with nothing to mark: one Godot deleted this
		# frame, until the reconcile after the step unpicks it.
		var brush := root.call("_find_brush_by_key", str(key)) as DraftBrush
		if brush == null or not brush.is_inside_tree():
			continue
		var xform := brush.global_transform
		for index in (selection as Dictionary).get(key, []):
			var face_idx := int(index)
			if face_idx < 0 or face_idx >= brush.faces.size():
				continue
			var face: FaceData = brush.faces[face_idx]
			if face == null or face.local_verts.size() < 3:
				continue
			face.ensure_geometry()
			# A displaced face's own triangles, so the fill sits on the sculpt.
			var triangles: PackedVector3Array = face.triangulate().get(
				"verts", PackedVector3Array()
			)
			fill.append_array(xform * triangles)
			_entries.append(
				{"key": str(key), "face_idx": face_idx, "points": xform * face.local_verts}
			)
	if _entries.is_empty():
		_clear()
		return
	_draw(root, fill)


## What the mark covers now, one entry per face.
func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## The node the mark is drawn on, or null while there is nothing to mark.
func get_mesh_instance() -> MeshInstance3D:
	return _mesh_instance if is_instance_valid(_mesh_instance) else null


## The fill is the Selected face colour, orange unless a mapper picked another,
## and the outline the same colour at full strength.
func _draw(root: Node, fill: PackedVector3Array) -> void:
	_ensure_mesh_instance(root)
	_mesh.clear_surfaces()
	var color := HFOverlayColors.get_color(HFOverlayColors.SELECTED_FACE)
	if not fill.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_mesh.surface_set_color(color)
		for point in fill:
			_mesh.surface_add_vertex(point)
		_mesh.surface_end()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(HFOverlayColors.with_alpha(color, 1.0))
	for entry in _entries:
		var points: PackedVector3Array = entry["points"]
		for i in range(points.size()):
			_mesh.surface_add_vertex(points[i])
			_mesh.surface_add_vertex(points[(i + 1) % points.size()])
	_mesh.surface_end()


func _ensure_mesh_instance(root: Node) -> void:
	if is_instance_valid(_mesh_instance) and _mesh_instance.get_parent() == root:
		return
	_free_mesh_instance()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = NODE_NAME
	# The points are world space, so the level's own transform must not move them.
	_mesh_instance.top_level = true
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Drawn over everything, like the hover highlight, so a picked face behind
	# another brush still shows that it is picked.
	material.no_depth_test = true
	_mesh_instance.material_override = material
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	root.add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)


func _clear() -> void:
	_entries.clear()
	_free_mesh_instance()


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
	if root != null:
		if root.is_connected("face_selection_changed", _on_face_selection_changed):
			root.disconnect("face_selection_changed", _on_face_selection_changed)
		if root.is_connected("state_loaded", _on_face_selection_changed):
			root.disconnect("state_loaded", _on_face_selection_changed)
		if root.is_connected("brush_changed", _on_brush_changed):
			root.disconnect("brush_changed", _on_brush_changed)
	_watched_root = null
	_clear()


func _root() -> Node:
	if _watched_root == null:
		return null
	return _watched_root.get_ref() as Node


func _run_queued_refresh() -> void:
	_refresh_queued = false
	refresh()


func _on_face_selection_changed() -> void:
	queue_refresh()


## A move, a resize or a vertex edit tags the brush it changed. Only a brush with
## a picked face changes the mark.
func _on_brush_changed(brush_id: String) -> void:
	var root := _root()
	if root == null:
		return
	var selection = root.get("face_selection")
	if selection is Dictionary and (selection as Dictionary).has(brush_id):
		queue_refresh()
