@tool
extends "hf_preview_system.gd"
## The pieces a sweep would make, outlined before they exist (#1714): cyan for a
## piece it can make, red for one that folds back on itself. On an Arc, the
## handles that set where it turns about and how far are drawn over them (#1885).

const HFOutlineUtil = preload("../hf_outline_util.gd")

var _good: StandardMaterial3D
var _bad: StandardMaterial3D
## The pivot handle and the end handle, kept out of the pool, whose meshes are
## the pieces by index.
var _pivot: MeshInstance3D = null
var _end: MeshInstance3D = null


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
	_good = ghost_material(Color(0.3, 0.85, 1.0, 0.8))
	_bad = ghost_material(Color(1.0, 0.25, 0.2, 0.9))


## Outline `pieces`, as `HFFaceSweep.pieces()` gives them, faces in world space.
## A piece with no faces, one that folded, is outlined by its two sections.
func show_pieces(pieces: Array, rings_of: Callable = Callable()) -> void:
	set_enabled(true)
	_grow_pool(pieces.size(), _good)
	for i in pieces.size():
		var piece: Dictionary = pieces[i]
		var mesh_instance: MeshInstance3D = _mesh_pool[i]
		var lines := PackedVector3Array()
		if not (piece["faces"] as Array).is_empty():
			lines = HFOutlineUtil.face_boundary_lines(piece["faces"])
		elif rings_of.is_valid():
			for ring in rings_of.call(piece):
				for j in (ring as PackedVector3Array).size():
					lines.append(ring[j])
					lines.append(ring[(j + 1) % ring.size()])
		mesh_instance.mesh = HFOutlineUtil.line_mesh(lines)
		mesh_instance.material_override = _good if bool(piece["ok"]) else _bad
		mesh_instance.global_transform = Transform3D.IDENTITY
		mesh_instance.visible = true
	_hide_meshes_from(pieces.size())
	_preview_container.visible = not pieces.is_empty()


## Draw the pivot handle's `pivot_lines` and the end handle's `end_lines`, in
## world space. Empty lines take that handle away.
func show_handles(pivot_lines: PackedVector3Array, end_lines: PackedVector3Array) -> void:
	_build_container()
	if not is_instance_valid(_preview_container):
		return
	_pivot = _handle_mesh(_pivot, "SweepPivotHandle", Color(1.0, 0.6, 0.1, 0.95), pivot_lines)
	_end = _handle_mesh(_end, "SweepEndHandle", Color(1.0, 0.9, 0.2, 0.95), end_lines)


func _handle_mesh(
	mesh_instance: MeshInstance3D, mesh_name: String, color: Color, lines: PackedVector3Array
) -> MeshInstance3D:
	if not is_instance_valid(mesh_instance):
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = mesh_name
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = ghost_material(color)
		_preview_container.add_child(mesh_instance)
	mesh_instance.visible = not lines.is_empty()
	if not lines.is_empty():
		mesh_instance.mesh = HFOutlineUtil.line_mesh(lines)
	return mesh_instance


func _preview_name() -> String:
	return "SweepPreview"
