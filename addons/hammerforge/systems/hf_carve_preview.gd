@tool
class_name HFCarvePreview
extends "hf_preview_system.gd"
## Real-time wireframe preview showing the resulting slice pieces that would
## be created by a carve operation.  Uses the same ImmediateMesh wireframe
## pattern as HFSubtractPreview, but draws the 1-6 remaining pieces in green
## rather than the intersection volume in red.

const DraftBrush = preload("../brush_instance.gd")
const HFOutlineUtil = preload("../hf_outline_util.gd")

var _active_count: int = 0
var _material: StandardMaterial3D

## Currently previewing carve for this brush ID. Empty string = inactive.
var _carver_id: String = ""

const MAX_PREVIEWS := 50


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
	_material = ghost_material(Color(0.3, 0.9, 0.3, 0.6))


## Show preview for a specific carver brush.
func show_preview(carver_id: String) -> void:
	_carver_id = carver_id
	set_enabled(true)
	_rebuild()


## Hide the preview and reset state.
func clear() -> void:
	_carver_id = ""
	_active_count = 0
	super()


## Free all resources immediately.
func destroy() -> void:
	_active_count = 0
	super()


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
	root.brush_system._ensure_faces(carver_draft)
	if carver_draft.get_faces().size() < 4:
		clear()
		return
	var carver_aabb: AABB = root.brush_system.world_bounds_of(carver_draft)

	# Find overlapping targets — reuse carve_system logic
	var targets: Array = root.carve_system._find_overlapping_brushes(_carver_id, carver_aabb)

	# Each entry is one resulting piece: the faces to outline, and the transform
	# they are expressed in. Carve works in each target's own frame now, so the
	# preview has to carry that frame rather than assume world-aligned boxes.
	var previews: Array = []

	for target in targets:
		var target_draft := target as DraftBrush
		root.brush_system._ensure_faces(target_draft)
		if target_draft.get_faces().size() < 4:
			continue
		var target_aabb: AABB = root.brush_system.world_bounds_of(target_draft)
		var inter := target_aabb.intersection(carver_aabb)
		if inter.size.x <= 0.01 or inter.size.y <= 0.01 or inter.size.z <= 0.01:
			continue

		for piece_faces in root.carve_system._carve_pieces(carver_draft, target_draft):
			previews.append({"faces": piece_faces, "transform": target_draft.global_transform})
			if previews.size() >= MAX_PREVIEWS:
				break
		if previews.size() >= MAX_PREVIEWS:
			break

	_ensure_container()

	_grow_pool(previews.size(), _material)

	# Update active wireframes with the real outline of each resulting piece.
	for i in previews.size():
		var mi: MeshInstance3D = _mesh_pool[i]
		var entry: Dictionary = previews[i]
		mi.mesh = HFOutlineUtil.line_mesh(HFOutlineUtil.face_boundary_lines(entry["faces"]))
		# World space: the entry carries the target brush's own global transform.
		mi.global_transform = entry["transform"]
		mi.visible = true

	_hide_meshes_from(previews.size())

	_active_count = previews.size()
	_preview_container.visible = _active_count > 0


func _preview_name() -> String:
	return "CarvePreview"
