@tool
class_name HFStructurePreview
extends "hf_system.gd"
## A wireframe of the structure the Structure section would build, before it builds it.
##
## Every other way of making geometry in HammerForge shows you the shape while you
## are still choosing it: a drag has its box, a hollow has its walls, a clip has
## its cut. A structure had eight numbers and a button. You pressed the button to
## find out what "sweep 60, rings 6" meant, and if it was wrong you undid it and
## pressed it again.
##
## So the numbers draw. The ghost stands where Create would put the structure, and
## for a structure that already exists it stands over the real pieces, which is
## the moment that matters: you can see the arch getting wider before you agree
## to rebuild it.
##
## It is drawn as one mesh rather than one per piece. A dome is up to a few
## hundred pieces and the builders cap themselves well below the point where a
## rebuild per keystroke costs anything, but a few hundred `MeshInstance3D` nodes
## created and freed per keystroke would not be free at all.

const HFOutlineUtil = preload("../hf_outline_util.gd")

## Pale and translucent on purpose: this is geometry that does not exist yet, and
## every other overlay colour is already spoken for by something that does —
## yellow hollow walls, green carve pieces, cyan clip wires, red subtract volumes.
const GHOST_COLOR := Color(0.9, 0.95, 1.0, 0.5)

var _container: Node3D
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _piece_count: int = 0


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
	_material = StandardMaterial3D.new()
	_material.albedo_color = GHOST_COLOR
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true


## Draw what these settings would build, at the placement they would build at.
##
## Returns the number of pieces drawn. Zero means nothing is showing, and the
## reason is the same reason `can_build()` would give: settings each in range can
## still be a combination the builder refuses.
func show_preview(type: String, settings: Dictionary, placement: Transform3D) -> int:
	if not is_instance_valid(root):
		return 0
	if not HFGeneratorSystem.validate(type, settings).ok:
		clear()
		return 0
	var face_sets: Array = HFGeneratorSystem.build_faces(type, settings)
	if face_sets.is_empty():
		clear()
		return 0

	var lines := PackedVector3Array()
	var drawn := 0
	for faces in face_sets:
		if not (faces is Array) or (faces as Array).is_empty():
			continue
		lines.append_array(HFOutlineUtil.face_boundary_lines(faces))
		drawn += 1
	if lines.is_empty():
		clear()
		return 0

	_enabled = true
	_ensure_nodes()
	_mesh_instance.mesh = HFOutlineUtil.line_mesh(lines)
	# The builders describe a structure in its own space and the placement is
	# where that space lands in the world, which is exactly what a brush created
	# from the same face sets is given.
	_mesh_instance.global_transform = placement
	_mesh_instance.visible = true
	_container.visible = true
	_piece_count = drawn
	return drawn


## How many pieces the ghost currently shows. Zero when nothing is showing.
func piece_count() -> int:
	return _piece_count


func clear() -> void:
	_piece_count = 0
	_enabled = false
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false
		_mesh_instance.mesh = null
	if is_instance_valid(_container):
		_container.visible = false


func set_enabled(value: bool) -> void:
	if value:
		_enabled = true
		_ensure_nodes()
	else:
		clear()


func destroy() -> void:
	_piece_count = 0
	_enabled = false
	_mesh_instance = null
	if is_instance_valid(_container):
		if _container.get_parent():
			_container.get_parent().remove_child(_container)
		_container.free()
	_container = null


func _ensure_nodes() -> void:
	if not is_instance_valid(_container):
		_container = Node3D.new()
		_container.name = "StructurePreview"
		root.add_child(_container)
	_container.visible = true
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_instance.material_override = _material
		_container.add_child(_mesh_instance)
