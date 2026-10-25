@tool
extends "hf_preview_system.gd"
## The pieces a sweep would make, outlined before they exist (#1714): cyan for a
## piece it can make, red for one that folds back on itself.

const HFOutlineUtil = preload("../hf_outline_util.gd")

var _good: StandardMaterial3D
var _bad: StandardMaterial3D


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


func _preview_name() -> String:
	return "SweepPreview"
