@tool
extends RefCounted
class_name HFDrawHover
## Where a draw will land, shown before the click (#1400).
##
## Over a busy area a mapper could not tell whether a draw would start on the
## grid, on the table in the way, or halfway up the wall behind it until the
## brush appeared in the wrong place. With Draw idle, and with Polygon or Path
## before their first point, the face under the cursor is tinted by what a draw
## there starts on, a small cross marks the snapped start point, and the two
## grid lines through it brighten. Over empty space only the cross and the lines
## show.
##
## This only draws. What a draw starts on is `HFDragSystem.draw_start()`'s
## answer, the one `begin_drag()` starts from, and the plugin decides when the
## preview belongs on screen. View state: nothing here is saved or undone.

const HFDragSystemType = preload("hf_drag_system.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
const HFOutlineUtil = preload("../hf_outline_util.gd")
@warning_ignore_restore("shadowed_global_identifier")

## One tint per start kind: blue on a face level with the grid, green on a
## raised face the draw starts on, amber on a face that is not flat, and violet
## on a face a Draw on Face builds on (#1401). Over empty space nothing is
## tinted, and the cross takes the grid's own colour.
const KIND_COLORS := {
	HFDragSystemType.StartKind.GRID: Color(0.85, 0.95, 1.0, 0.9),
	HFDragSystemType.StartKind.LEVEL: Color(0.35, 0.7, 1.0, 0.3),
	HFDragSystemType.StartKind.RAISED: Color(0.3, 0.9, 0.4, 0.3),
	HFDragSystemType.StartKind.SLOPED: Color(1.0, 0.6, 0.15, 0.35),
	HFDragSystemType.StartKind.FACE: Color(0.75, 0.45, 1.0, 0.35),
}
## Half the cross's width, in grid steps.
const CROSS_REACH := 0.5

var root: Node3D
## The start on screen, `{}` while nothing is shown.
var shown: Dictionary = {}
var _face: MeshInstance3D = null
var _cross: MeshInstance3D = null
## The face the tint was built for, so a pointer moving across one face does
## not rebuild it.
var _face_key: Array = []
## The half width the cross mesh was built at, so it is built once per grid size.
var _cross_reach := -1.0
## The pointer and the view the preview was worked out for. While they stay the
## same the plugin skips the pick (#1387 measured what a pick costs).
var _view_key: Array = []


func _init(level_root: Node3D) -> void:
	root = level_root


static func color_for(kind: int) -> Color:
	return KIND_COLORS.get(kind, KIND_COLORS[HFDragSystemType.StartKind.GRID])


## Whether the preview on screen was worked out for `view_key`.
func is_current(view_key: Array) -> bool:
	return not _view_key.is_empty() and _view_key == view_key


## Show `start`, a `HFDragSystem.describe_start()` answer, or take the preview
## down for an empty one.
func show_start(start: Dictionary, view_key: Array = []) -> void:
	if start.is_empty() or not (start.get("point") is Vector3):
		clear()
		_view_key = view_key
		return
	shown = start
	_view_key = view_key
	var color := color_for(int(start.get("kind", HFDragSystemType.StartKind.GRID)))
	_show_face(start, color)
	_show_cross(start, color)
	if root.grid_system:
		root.grid_system.set_cursor(start["point"], true)


## Cheap when nothing is shown, as the HUD asks on every update.
func clear() -> void:
	_view_key = []
	if shown.is_empty():
		return
	shown = {}
	if _face and is_instance_valid(_face):
		_face.visible = false
	if _cross and is_instance_valid(_cross):
		_cross.visible = false
	if root and is_instance_valid(root) and root.grid_system:
		root.grid_system.set_cursor(Vector3.ZERO, false)


func is_showing() -> bool:
	return not shown.is_empty()


## Whether the face tint is up, for the tests.
func shows_face() -> bool:
	return _face != null and is_instance_valid(_face) and _face.visible


func _show_face(start: Dictionary, color: Color) -> void:
	var brush = start.get("brush", null)
	var face_idx := int(start.get("face_idx", -1))
	if (
		not (brush is DraftBrush)
		or not is_instance_valid(brush)
		or face_idx < 0
		or face_idx >= brush.faces.size()
		or brush.faces[face_idx] == null
	):
		if _face and is_instance_valid(_face):
			_face.visible = false
		return
	_face = _ensure_node(_face, "_DrawHoverFace")
	(_face.material_override as StandardMaterial3D).albedo_color = color
	var face = brush.faces[face_idx]
	var key: Array = [brush.get_instance_id(), face_idx, brush.global_transform, face.local_verts]
	if key != _face_key:
		_face_key = key
		var verts: PackedVector3Array = face.triangulate().get("verts", PackedVector3Array())
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex in verts:
			surface.add_vertex(brush.global_transform * vertex)
		_face.mesh = surface.commit()
	_face.global_transform = Transform3D.IDENTITY
	_face.visible = true


## The cross lies on the plane the base will be drawn on: the face's own with
## Draw on Face, level otherwise, as a draw builds its base level wherever it
## starts.
func _show_cross(start: Dictionary, color: Color) -> void:
	_cross = _ensure_node(_cross, "_DrawHoverCross")
	var reach := maxf(float(root.get("grid_snap")), 0.1) * CROSS_REACH
	if reach != _cross_reach:
		_cross_reach = reach
		_cross.mesh = (
			HFOutlineUtil
			. line_mesh(
				PackedVector3Array(
					[
						Vector3(-reach, 0, 0),
						Vector3(reach, 0, 0),
						Vector3(0, 0, -reach),
						Vector3(0, 0, reach),
					]
				)
			)
		)
	var cross_color := color
	cross_color.a = 0.95
	(_cross.material_override as StandardMaterial3D).albedo_color = cross_color
	var basis := Basis.IDENTITY
	if start.get("frame") is Transform3D:
		basis = (start["frame"] as Transform3D).basis
	_cross.global_transform = Transform3D(basis, start["point"])
	_cross.visible = true


func _ensure_node(node: MeshInstance3D, node_name: String) -> MeshInstance3D:
	if node and is_instance_valid(node):
		return node
	# A new node has no mesh, whatever the caches say was built.
	_face_key = []
	_cross_reach = -1.0
	node = MeshInstance3D.new()
	node.name = node_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	node.material_override = material
	root.add_child(node, false, Node.INTERNAL_MODE_BACK)
	node.owner = null
	return node
