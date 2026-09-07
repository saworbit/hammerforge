@tool
class_name HFCarveSystem
extends RefCounted

## Performs boolean subtraction (carve) of one brush against all overlapping brushes.
##
## The carver's volume is cut out of every intersecting brush by progressive
## remainder over the carver's own face planes, so the carver and its targets can
## be rotated, non-box, or both. See `HFConvexClip` for the split itself.

const DraftBrush = preload("../brush_instance.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")

var root: Node3D

## Minimum thickness (in world units) for a carved slice to be created.
## Slices thinner than this are discarded to avoid degenerate geometry.
var min_thickness: float = 0.01


func _init(p_root: Node3D = null) -> void:
	root = p_root


## Carve the shape of the given brush out of every overlapping brush.
## The carver itself is deleted after the operation.
## Returns an HFOpResult indicating success or failure.
func carve_with_brush(brush_id: String) -> HFOpResult:
	if brush_id == "":
		return _op_fail("Carve: no brush ID provided")

	if root.has_method("tag_full_reconcile"):
		root.tag_full_reconcile()

	var carver = root.brush_system.find_brush_by_id(brush_id)
	if not carver or not (carver is DraftBrush):
		return _op_fail("Carve: brush '%s' not found" % brush_id)

	var carver_draft := carver as DraftBrush
	root.brush_system._ensure_faces(carver_draft)
	if carver_draft.get_faces().size() < 4:
		return _op_fail(
			"Carve: the carver has no usable geometry",
			"Rebuild or redraw the carving brush and try again"
		)
	var carver_aabb: AABB = root.brush_system.world_bounds_of(carver_draft)

	# Find all overlapping brushes (excluding the carver itself)
	var targets: Array = _find_overlapping_brushes(brush_id, carver_aabb)
	if targets.is_empty():
		return _op_fail(
			"Carve: no overlapping brushes found", "Move the carver so it overlaps other brushes"
		)

	var total_pieces := 0
	var targets_carved := 0

	for target in targets:
		var target_draft := target as DraftBrush
		var target_id := _brush_id_of(target_draft)
		root.brush_system._ensure_faces(target_draft)
		if target_draft.get_faces().size() < 4:
			continue

		# Cheap rejection before any splitting: touching bounds is not a volume.
		var target_aabb: AABB = root.brush_system.world_bounds_of(target_draft)
		var inter := target_aabb.intersection(carver_aabb)
		if (
			inter.size.x <= min_thickness
			or inter.size.y <= min_thickness
			or inter.size.z <= min_thickness
		):
			continue

		var pieces: Array = _carve_pieces(carver_draft, target_draft)
		if pieces.is_empty():
			continue

		# Build every piece before deleting anything: _piece_info_from_faces reads
		# the target for its material, visgroups, group and entity class.
		var infos: Array = []
		for piece_faces in pieces:
			infos.append(root.brush_system._piece_info_from_faces(target_draft, piece_faces))

		root.brush_system.delete_brush_by_id(target_id)
		for info in infos:
			if root.brush_system.create_brush_from_info(info):
				total_pieces += 1

		targets_carved += 1

	# Every overlapping brush was skipped (contact too shallow, or the carver
	# swallows the target whole and leaves no slices).  Nothing was cut, so the
	# carver has to stay where it is instead of being consumed for free.
	if targets_carved == 0:
		return _op_fail(
			"Carve: overlap is too shallow to carve",
			"Push the carver further into the brush you want to cut"
		)

	# Delete the carver brush
	root.brush_system.delete_brush_by_id(brush_id)

	var msg := "Carve: carved %d brush(es), created %d pieces" % [targets_carved, total_pieces]
	root._log(msg)
	return HFOpResult.success(msg)


## The pieces of `target` that survive carving `carver` out of it.
##
## Classic progressive-remainder carving, generalised off boxes: for each plane
## bounding the carver, split what is left of the target. The half outside that
## plane is finished, because nothing else can remove it, and the half inside
## carries on to the next plane. What survives every plane is the intersection,
## and that is exactly what the carve takes away.
##
## Working from the carver's real face planes rather than the six sides of its
## bounding box is what lets the carver be rotated, or a cylinder, or a merged
## brush, or anything else convex.
func _carve_pieces(carver: DraftBrush, target: DraftBrush) -> Array:
	var into_target: Transform3D = (
		target.global_transform.affine_inverse() * carver.global_transform
	)
	var planes: Array = HFConvexClip.face_planes_in_space(carver.get_faces(), into_target)
	if planes.is_empty():
		return []
	var result: Dictionary = HFConvexClip.progressive_remainder(target.get_faces(), planes)
	if not result["separated"]:
		return []
	var pieces: Array = []
	for piece_faces in result["pieces"]:
		if _is_thick_enough(piece_faces):
			pieces.append(piece_faces)
	return pieces


## Reject pieces too thin to be worth a brush, the way the box carve did.
func _is_thick_enough(faces: Array) -> bool:
	var bounds: AABB = HFBrushSystem._local_bounds_of_faces(faces)
	return (
		bounds.size.x > min_thickness
		and bounds.size.y > min_thickness
		and bounds.size.z > min_thickness
	)


## Brush ids normally live on the property, but brushes restored from a scene can
## still carry only the metadata copy.
static func _brush_id_of(brush: Node) -> String:
	var bid := str(brush.get("brush_id"))
	if bid == "" and brush.has_meta("brush_id"):
		bid = str(brush.get_meta("brush_id"))
	return bid


## Find all DraftBrush nodes whose AABB overlaps the given AABB,
## excluding the brush with the given ID.
func _find_overlapping_brushes(exclude_id: String, aabb: AABB) -> Array:
	var result: Array = []
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var draft := node as DraftBrush
		if _brush_id_of(draft) == exclude_id:
			continue
		var node_pos: Vector3 = draft.global_position
		var node_size: Vector3 = draft.size
		var node_aabb := AABB(node_pos - node_size * 0.5, node_size)
		if aabb.intersects(node_aabb):
			result.append(draft)
	return result


func _op_fail(msg: String, hint: String = "") -> HFOpResult:
	if root and root.has_signal("user_message"):
		root.emit_signal("user_message", msg, 1)  # WARNING level
	return HFOpResult.fail(msg, hint)
