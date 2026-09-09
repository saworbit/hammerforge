@tool
class_name HFArrayPreview
extends "hf_preview_system.gd"
## A wireframe of the copies an array would make, before it makes them.
##
## The Structure section learned to draw itself; the array section next to it did
## not. It has three layouts, up to nine numbers between them, and a button that
## turns them into as many brushes as the numbers ask for — and a grid of thirty-two
## cells a side asks for thirty-two thousand. Nothing said so until they existed.
##
## So the copies draw first. What is drawn is the selection itself, repeated at the
## placements the command would use, which is the honest picture: an array does not
## invent geometry, it repeats what you already have.

const HFOutlineUtil = preload("../hf_outline_util.gd")

## The same ghost as the structure preview, and for the same reason: this is
## geometry that does not exist yet, and every other overlay colour belongs to
## something that does.
const GHOST_COLOR := Color(0.9, 0.95, 1.0, 0.5)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _copy_count: int = 0


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
	_material = ghost_material(GHOST_COLOR)


func _preview_name() -> String:
	return "ArrayPreview"


## Draw the copies these placements would make of these brushes.
##
## Returns the number of copies shown. Zero means nothing is showing, and the
## reason is the one `HFDuplicator.can_generate()` would give.
func show_preview(brush_ids: Array, placements: Array) -> int:
	if not is_instance_valid(root) or root.get("brush_system") == null:
		return 0
	var sources: Array = []
	for brush_id in brush_ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if brush != null:
			sources.append(brush)
	if sources.is_empty() or placements.is_empty():
		clear()
		return 0
	# The same budget the command refuses on. A ghost of thirty-two thousand
	# brushes is the hang it is there to prevent, arriving one keystroke earlier.
	if not HFDuplicator.can_generate(placements.size(), sources.size()).ok:
		clear()
		return 0

	var lines := PackedVector3Array()
	for placement in placements:
		for brush in sources:
			var xform: Transform3D = placement.applied_to(brush.global_transform)
			for point in HFOutlineUtil.face_boundary_lines(brush.faces):
				lines.append(xform * point)
	if lines.is_empty():
		clear()
		return 0

	_enabled = true
	_ensure_nodes()
	_mesh_instance.mesh = HFOutlineUtil.line_mesh(lines)
	# The outlines were transformed into world space one by one, because each copy
	# stands somewhere different; the mesh itself carries no placement of its own.
	_mesh_instance.global_transform = Transform3D.IDENTITY
	_mesh_instance.visible = true
	_preview_container.visible = true
	_copy_count = placements.size()
	return _copy_count


## How many copies the ghost is currently showing. Zero when nothing is showing.
func copy_count() -> int:
	return _copy_count


func clear() -> void:
	_copy_count = 0
	if is_instance_valid(_mesh_instance):
		_mesh_instance.mesh = null
	super()


func set_enabled(value: bool) -> void:
	if value:
		_ensure_nodes()
	super(value)


func destroy() -> void:
	_copy_count = 0
	_mesh_instance = null
	super()


func _ensure_nodes() -> void:
	_ensure_container()
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = _make_mesh(_material)
