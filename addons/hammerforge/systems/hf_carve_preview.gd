@tool
class_name HFCarvePreview
extends "hf_preview_system.gd"
## Real-time wireframe preview showing the resulting slice pieces that would
## be created by a carve operation.  Uses the same ImmediateMesh wireframe
## pattern as HFSubtractPreview, but draws the 1-6 remaining pieces in green
## rather than the intersection volume in red. Intersect shows the one brush it
## keeps here too, in the same green, before its confirmation (#1426).

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFOutlineUtil = preload("../hf_outline_util.gd")

var _active_count: int = 0
var _material: StandardMaterial3D

## Currently previewing carve for this brush ID. Empty string = inactive.
var _carver_id: String = ""
## Currently previewing an intersection of these brush IDs, the target first.
var _intersect_ids: Array = []
## Currently previewing the hull of these brush IDs (#1715).
var _hull_ids: Array = []
## How many sculpts the pieces on show would drop, for the confirmation to name.
var sculpts_dropped: int = 0

const MAX_PREVIEWS := 50


func _init(p_root: Node3D = null) -> void:
	super(p_root)
	_enabled = false
	_material = ghost_material(Color(0.3, 0.9, 0.3, 0.6))


## Show preview for a specific carver brush.
func show_preview(carver_id: String) -> void:
	_intersect_ids = []
	_carver_id = carver_id
	set_enabled(true)
	_rebuild()


## Show the brush intersecting `brush_ids` would keep.
func show_intersect_preview(brush_ids: Array) -> void:
	_carver_id = ""
	_hull_ids = []
	_intersect_ids = brush_ids.duplicate()
	set_enabled(true)
	_rebuild()


## Show the one brush Hull of Selection would wrap `brush_ids` in (#1715).
func show_hull_preview(brush_ids: Array) -> void:
	_carver_id = ""
	_intersect_ids = []
	_hull_ids = brush_ids.duplicate()
	set_enabled(true)
	_rebuild()


## Hide the preview and reset state.
func clear() -> void:
	_carver_id = ""
	_intersect_ids = []
	_hull_ids = []
	_active_count = 0
	sculpts_dropped = 0
	super()


## Free all resources immediately.
func destroy() -> void:
	_active_count = 0
	super()


## Compute and display preview slices for the current carver brush.
func _rebuild() -> void:
	if root and not _intersect_ids.is_empty():
		_rebuild_intersection()
		return
	if root and not _hull_ids.is_empty():
		_rebuild_hull()
		return
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
	sculpts_dropped = 0

	for target in targets:
		var target_draft := target as DraftBrush
		root.brush_system._ensure_faces(target_draft)
		if target_draft.get_faces().size() < 4:
			continue
		var target_aabb: AABB = root.brush_system.world_bounds_of(target_draft)
		var inter := target_aabb.intersection(carver_aabb)
		if inter.size.x <= 0.01 or inter.size.y <= 0.01 or inter.size.z <= 0.01:
			continue

		var carved: Dictionary = root.carve_system._carve(carver_draft, target_draft)
		sculpts_dropped += HFConvexClip.sculpts_a_cut_would_drop(
			carved["pieces"], carved["origins"]
		)
		for piece_faces in carved["pieces"]:
			previews.append({"faces": piece_faces, "transform": target_draft.global_transform})
			if previews.size() >= MAX_PREVIEWS:
				break
		if previews.size() >= MAX_PREVIEWS:
			break

	_show_previews(previews)


## The one brush the intersection keeps, from the plan the intersect itself makes.
func _rebuild_intersection() -> void:
	var plan: Dictionary = root.carve_system._plan_intersect(_intersect_ids)
	if not (plan["result"] as HFOpResult).ok:
		clear()
		return
	var target: DraftBrush = plan["drafts"][0]
	sculpts_dropped = HFConvexClip.sculpts_a_cut_would_drop([plan["faces"]], plan["origins"])
	_show_previews([{"faces": plan["faces"], "transform": target.global_transform}])


## The one brush the hull makes, from the plan the hull itself makes.
func _rebuild_hull() -> void:
	var plan: Dictionary = root.carve_system._plan_hull(_hull_ids)
	if not (plan["result"] as HFOpResult).ok:
		clear()
		return
	var target: DraftBrush = plan["drafts"][0]
	sculpts_dropped = HFConvexClip.sculpts_a_cut_would_drop([plan["faces"]], plan["origins"])
	_show_previews([{"faces": plan["faces"], "transform": target.global_transform}])


## Outline each of `previews`, `{"faces", "transform"}`, and hide the rest.
func _show_previews(previews: Array) -> void:
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
