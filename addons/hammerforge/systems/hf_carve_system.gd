@tool
class_name HFCarveSystem
extends RefCounted

## Performs boolean subtraction (carve) of one brush against all overlapping
## brushes, and boolean intersection (intersect) of a selection of brushes.
##
## The carver's volume is cut out of every intersecting brush by progressive
## remainder over the carver's own face planes, so the carver and its targets can
## be rotated, non-box, or both. Intersect runs the same loop and keeps the
## remainder Carve throws away. See `HFConvexClip` for the split itself.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
const FaceData = preload("../face_data.gd")
const HFBrushEntity = preload("../hf_brush_entity.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFHullType = preload("../hf_hull.gd")

## How far a corner may stand off another brush's face plane and still count as
## lying on it, when a face of an intersection looks for the face it was cut by.
const ON_PLANE := 0.01
## A float's step is at most 1 / 2^23 of the number it holds, and a brush's place
## is held to half a step on each axis. Two brushes can be out of line by a step
## on each axis, so a hull of them takes two steps as on a face.
const PLACEMENT_STEPS := 2.0 / 8388608.0

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
	var plan := _plan_carve(brush_id)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		return _op_fail(check.message, check.fix_hint)

	root.tag_full_reconcile()
	var cuts: Array = plan["cuts"]
	var total_pieces := 0
	var hidden := hidden_overlaps(brush_id)
	var locked := locked_overlaps(brush_id)

	for cut in cuts:
		var target_draft: DraftBrush = cut["target"]
		var target_id := _brush_id_of(target_draft)
		var pieces: Array = cut["pieces"]
		HFBrushSystem.warn_lost_sculpts(
			"Carve", target_id, HFConvexClip.carry_surface_detail(pieces, cut["origins"])
		)

		# Build every piece before deleting anything: _piece_infos_from_faces reads
		# the target for its material, visgroups, group and brush entity.
		var infos: Array = root.brush_system._piece_infos_from_faces(target_draft, pieces)

		# The pieces are made before the target is deleted, as Merge makes its
		# brush. Deleting a group's last brush dropped the group, and every wire
		# aimed at its entity, so pieces made after lost both (#1975). A target
		# that gave no pieces stays where it was.
		var made := 0
		for info in infos:
			if root.brush_system.create_brush_from_info(info):
				made += 1
		if made > 0:
			root.brush_system.delete_brush_by_id(target_id)
		total_pieces += made

	# Delete the carver brush
	root.brush_system.delete_brush_by_id(brush_id)

	var msg := "Carve: carved %d brush(es), created %d pieces" % [cuts.size(), total_pieces]
	if hidden > 0:
		msg += ", left %d hidden brush(es) alone" % hidden
	if locked > 0:
		msg += ", left %d locked brush(es) alone" % locked
	root._log(msg)
	return HFOpResult.success(msg)


## Whether carving with this brush would cut anything, and if not, the reason the
## carve gives. Carve's confirmation asks this first, as Hollow and Clip ask
## theirs, so a carve that would cut nothing says so instead of asking and then
## doing nothing (#1267).
func can_carve_brush(brush_id: String) -> HFOpResult:
	return _plan_carve(brush_id, true)["result"]


## What carving with `brush_id` would cut, worked out without cutting anything.
##
## Returns `{"result": HFOpResult, "cuts": Array}`, each cut `{"target":
## DraftBrush, "pieces": Array, "origins": Dictionary}` in the order the carve
## makes them. `first_cut_only` stops at the first target that would be cut, which
## is all the check needs to know. Side effect free, so the check and the carve
## cannot disagree.
func _plan_carve(brush_id: String, first_cut_only: bool = false) -> Dictionary:
	if brush_id == "":
		return _refusal("Carve: no brush ID provided")

	var carver = root.brush_system.find_brush_by_id(brush_id)
	if not carver or not (carver is DraftBrush):
		return _refusal("Carve: brush '%s' not found" % brush_id)

	var carver_draft := carver as DraftBrush
	root.brush_system._ensure_faces(carver_draft)
	if carver_draft.get_faces().size() < 4:
		return _refusal(
			"Carve: the carver has no usable geometry",
			"Rebuild or redraw the carving brush and try again"
		)
	var carver_faces: Array = carver_draft.get_faces()
	var carver_budget: Dictionary = HFConvexClip.boolean_plane_budget(
		carver_faces, HFConvexClip.interior_point(carver_faces)
	)
	if not carver_budget["ok"]:
		return _refusal(
			(
				"Carve: this carver has %d distinct faces, which would shatter every brush it touches"
				% carver_budget["planes"]
			),
			"Carve works with carvers of up to %d faces." % HFConvexClip.MAX_BOOLEAN_PLANES
		)
	if not HFConvexClip.is_convex_solid(carver_faces, HFConvexClip.interior_point(carver_faces)):
		return _refusal(
			"Carve: this carver is not convex, so it would cut out its hull",
			"Carve with a convex brush. A torus is not one"
		)
	var carver_aabb: AABB = root.brush_system.world_bounds_of(carver_draft)

	# Find all overlapping brushes (excluding the carver itself)
	var overlapping := _overlapping_brushes(brush_id, carver_aabb)
	var targets: Array = overlapping["shown"]
	if targets.is_empty():
		var hidden: int = (overlapping["hidden"] as Array).size()
		var locked: int = (overlapping["locked"] as Array).size()
		var hint := "Move the carver so it overlaps other brushes"
		if hidden > 0:
			hint = "It overlaps %d hidden brush(es). Show them to carve them" % hidden
		if locked > 0:
			var unlock := "It overlaps %d locked brush(es). Unlock them to carve them" % locked
			hint = unlock if hidden == 0 else hint + ". " + unlock
		return _refusal("Carve: no overlapping brushes found", hint)

	var cuts: Array = []
	for target in targets:
		var target_draft := target as DraftBrush
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

		var carved: Dictionary = _carve(carver_draft, target_draft)
		var pieces: Array = carved["pieces"]
		if pieces.is_empty():
			continue
		cuts.append({"target": target_draft, "pieces": pieces, "origins": carved["origins"]})
		if first_cut_only:
			break

	# Every overlapping brush was skipped (contact too shallow, or the carver
	# swallows the target whole and leaves no slices).  Nothing was cut, so the
	# carver has to stay where it is instead of being consumed for free.
	if cuts.is_empty():
		return _refusal(
			"Carve: overlap is too shallow to carve",
			"Push the carver further into the brush you want to cut"
		)
	return {"result": HFOpResult.success(), "cuts": cuts}


static func _refusal(msg: String, hint: String = "") -> Dictionary:
	return {"result": HFOpResult.fail(msg, hint), "cuts": []}


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
##
## Returns `{"pieces": Array, "origins": Dictionary}`. `origins` names the face of
## the target each piece face came from: a carve that is kept needs it to carry
## paint and sculpts, and the preview to count the sculpts it would drop.
func _carve(carver: DraftBrush, target: DraftBrush) -> Dictionary:
	var nothing := {"pieces": [], "origins": {}}
	var into_target: Transform3D = (
		target.global_transform.affine_inverse() * carver.global_transform
	)
	var planes: Array = HFConvexClip.face_planes_in_space(carver.get_faces(), into_target)
	if planes.is_empty():
		return nothing
	var result: Dictionary = HFConvexClip.progressive_remainder(target.get_faces(), planes)
	if not result["separated"]:
		return nothing
	var pieces: Array = []
	for piece_faces in result["pieces"]:
		if _is_thick_enough(piece_faces):
			pieces.append(piece_faces)
	return {"pieces": pieces, "origins": result["origins"]}


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


## Find all shown DraftBrush nodes whose world bounds overlap the given AABB,
## excluding the brush with the given ID.
##
## The bounds come from `world_bounds_of()` rather than from `position` and
## `size`, because those two describe the brush before it was turned. A rotated
## brush reaches outside that box, and a rejection that reads the wrong box is
## not a cheap rejection, it is a wrong answer: the carve reported no overlapping
## brushes and did nothing.
##
## A hidden brush is left alone. A mapper hides the outer walls to work inside a
## room, and a doorway carved through an inner wall must not cut the wall they
## cannot see (#1710). A locked brush is left alone too: the carver reaches past
## the selection to what it overlaps, and nothing changes a locked brush (#1973).
func _find_overlapping_brushes(exclude_id: String, aabb: AABB) -> Array:
	return _overlapping_brushes(exclude_id, aabb)["shown"]


## How many hidden brushes the carver `brush_id` overlaps and leaves alone.
func hidden_overlaps(brush_id: String) -> int:
	return (_overlaps_of(brush_id).get("hidden", []) as Array).size()


## How many locked brushes the carver `brush_id` overlaps and leaves alone. A
## brush both hidden and locked is counted as hidden.
func locked_overlaps(brush_id: String) -> int:
	return (_overlaps_of(brush_id).get("locked", []) as Array).size()


## `_overlapping_brushes()` for the carver `brush_id`, or empty when it is not there.
func _overlaps_of(brush_id: String) -> Dictionary:
	var carver = root.brush_system.find_brush_by_id(brush_id)
	if not carver or not (carver is DraftBrush):
		return {}
	return _overlapping_brushes(brush_id, root.brush_system.world_bounds_of(carver))


## `{"shown": Array, "hidden": Array, "locked": Array}`: the brushes whose bounds
## overlap `aabb`, those Carve may cut apart from those it leaves alone.
func _overlapping_brushes(exclude_id: String, aabb: AABB) -> Dictionary:
	var shown: Array = []
	var hidden: Array = []
	var locked: Array = []
	var locks = root.get("visgroup_system")
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var draft := node as DraftBrush
		if _brush_id_of(draft) == exclude_id:
			continue
		if not aabb.intersects(root.brush_system.world_bounds_of(draft)):
			continue
		if _is_hidden(draft):
			hidden.append(draft)
		elif locks != null and locks.is_locked(draft):
			locked.append(draft)
		else:
			shown.append(draft)
	return {"shown": shown, "hidden": hidden, "locked": locked}


func _is_hidden(draft: DraftBrush) -> bool:
	if not draft.visible:
		return true
	var visgroups = root.get("visgroup_system")
	return visgroups != null and visgroups.is_hidden_by_visgroups(draft)


# ---------------------------------------------------------------------------
# Intersect
# ---------------------------------------------------------------------------


## Keep only the volume every one of `brush_ids` shares, as one brush (#1426).
##
## The first is the target. It is cut down by the planes of each of the others in
## turn, and what is left of it replaces them all, in one step. Two convex solids
## overlap in a convex solid, so what is left is always one brush. It is a piece
## of the target, so it has the target's operation, material, visgroups, group and
## brush entity, as a piece of a carve does.
func intersect_brushes_by_ids(brush_ids: Array) -> HFOpResult:
	# The rules live in the plan and hold here as well as at the press that asked
	# first: the undo entry stores this method and these ids.
	var plan := _plan_intersect(brush_ids)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		return _op_fail(check.message, check.fix_hint)

	var drafts: Array = plan["drafts"]
	var target: DraftBrush = drafts[0]
	var faces: Array = plan["faces"]
	var origins: Dictionary = plan["origins"]
	HFBrushSystem.warn_lost_sculpts(
		"Intersect", _brush_id_of(target), HFConvexClip.carry_surface_detail([faces], origins)
	)
	var owner_of := _dress_from_other_brushes(faces, origins, drafts)
	var as_slots := _overrides_as_slots(faces, owner_of, target)

	# Made before anything is deleted: the info reads the target, and a brush that
	# could not be made leaves every source where it was.
	var info: Dictionary = root.brush_system._piece_infos_from_faces(target, [faces])[0]
	# The one entity they all are, with every wire any of them held, as Merge keeps.
	info.merge(HFBrushEntity.carried_by_all(drafts), true)
	if as_slots:
		info.erase("material")
	root.tag_full_reconcile()
	if root.brush_system.create_brush_from_info(info) == null:
		return _op_fail("Intersect: produced no geometry")
	for draft in drafts:
		root.brush_system.delete_brush(draft)

	var msg := "Intersect: kept the volume %d brushes share" % drafts.size()
	root._log(msg)
	return HFOpResult.success(msg)


## Whether these brushes can be intersected, and if not, the reason the intersect
## gives. Asked before the confirmation opens, as Carve asks its own.
func can_intersect_brushes(brush_ids: Array) -> HFOpResult:
	return _plan_intersect(brush_ids)["result"]


## What intersecting `brush_ids` would keep, worked out without changing anything.
##
## Returns `{"result": HFOpResult, "drafts": Array, "faces": Array, "origins":
## Dictionary}`: the brushes, the target first, the faces of what is kept in the
## target's own space, and for each of them that is a piece of one of the target's
## faces, that face. A face that is not lies on another brush's plane. Side effect
## free, so the check, the preview and the intersect cannot disagree.
func _plan_intersect(brush_ids: Array) -> Dictionary:
	var drafts: Array = []
	for brush_id in brush_ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if not brush or not (brush is DraftBrush):
			return _intersect_refusal("Intersect: brush '%s' not found" % str(brush_id))
		# Named twice is one brush, not a second one to trim to.
		if not drafts.has(brush):
			drafts.append(brush)
	if drafts.size() < 2:
		return _intersect_refusal(
			"Intersect: select at least 2 brushes",
			"Select the brush to keep first, then the brushes to trim it to"
		)
	var target := drafts[0] as DraftBrush
	for draft in drafts:
		if (draft as DraftBrush).operation != target.operation:
			return _intersect_refusal(
				"Intersect: all brushes must have the same operation type",
				"Cannot intersect solid brushes with cuts"
			)
	# One brush is kept, of one entity or of none, as Merge keeps one (#1194).
	if not HFBrushEntity.are_one_entity(drafts):
		return _intersect_refusal(
			"Intersect: the selected brushes are not all one entity",
			"Intersect the brushes of one door or trigger, or plain brushes. Tie or untie them first"
		)
	var common := AABB()
	for i in drafts.size():
		var draft := drafts[i] as DraftBrush
		var brush_id := _brush_id_of(draft)
		root.brush_system._ensure_faces(draft)
		var faces: Array = draft.get_faces()
		if faces.size() < 4:
			return _intersect_refusal(
				"Intersect: brush '%s' has no usable geometry" % brush_id,
				"Rebuild or redraw it and try again"
			)
		var interior: Vector3 = HFConvexClip.interior_point(faces)
		# The target is what is cut; every other brush cuts with its planes.
		if i > 0:
			var budget: Dictionary = HFConvexClip.boolean_plane_budget(faces, interior)
			if not budget["ok"]:
				return _intersect_refusal(
					(
						"Intersect: brush '%s' has %d distinct faces, too many to cut with"
						% [brush_id, budget["planes"]]
					),
					(
						"Intersect works with brushes of up to %d faces."
						% HFConvexClip.MAX_BOOLEAN_PLANES
					)
				)
		if not HFConvexClip.is_convex_solid(faces, interior):
			return _intersect_refusal(
				"Intersect: brush '%s' is not convex, so it would be cut to its hull" % brush_id,
				"Intersect convex brushes. A torus is not one"
			)
		var bounds: AABB = root.brush_system.world_bounds_of(draft)
		common = bounds if i == 0 else common.intersection(bounds)

	# Cheap rejection before any splitting: bounds that only touch are no volume.
	var no_volume := _intersect_refusal(
		"Intersect: the brushes share no volume",
		"Move them so one volume lies inside every one of them"
	)
	if (
		common.size.x <= min_thickness
		or common.size.y <= min_thickness
		or common.size.z <= min_thickness
	):
		return no_volume

	var into_target: Transform3D = target.global_transform.affine_inverse()
	var kept: Array = target.get_faces()
	var origins := {}
	for i in range(1, drafts.size()):
		var other := drafts[i] as DraftBrush
		var planes: Array = HFConvexClip.face_planes_in_space(
			other.get_faces(), into_target * other.global_transform
		)
		var cut: Dictionary = HFConvexClip.progressive_remainder(kept, planes)
		if not cut["separated"]:
			return no_volume
		# Each cut names the face of what it was handed, so chain back to the
		# target's own faces. A cap is a piece of nothing at every step.
		var cut_from: Dictionary = cut["origins"]
		var chained := {}
		for face in cut["remainder"]:
			var source = cut_from.get(face)
			if i > 1:
				source = origins.get(source)
			if source != null:
				chained[face] = source
		kept = cut["remainder"]
		origins = chained
	if kept.is_empty() or not _is_thick_enough(kept):
		return no_volume
	return {"result": HFOpResult.success(), "drafts": drafts, "faces": kept, "origins": origins}


static func _intersect_refusal(msg: String, hint: String = "") -> Dictionary:
	return {"result": HFOpResult.fail(msg, hint), "drafts": [], "faces": [], "origins": {}}


## Give each face of an intersection that lies on another brush's plane the look of
## that brush's face there, and say which brush each face takes its look from.
##
## A piece of one of the target's own faces kept its look through the split. A cap
## was given the look of the target face it most resembles, which is right for a
## carve's cut surface and wrong here: it is a piece of the other brush's face. The
## first brush selected with a face on that plane gives it, the target first of all.
## Custom and Cylindrical UVs are read off that face at the cap's corners, as a
## merge reads them off a face that grew; Planar and Box UVs are taken in world
## space and carry on by themselves. Its paint and its sculpt stay where they were.
func _dress_from_other_brushes(faces: Array, origins: Dictionary, drafts: Array) -> Dictionary:
	var target := drafts[0] as DraftBrush
	var owner_of := {}
	for face in faces:
		owner_of[face] = target
	for i in range(1, drafts.size()):
		var other := drafts[i] as DraftBrush
		var into_other: Transform3D = (
			other.global_transform.affine_inverse() * target.global_transform
		)
		for face in faces:
			if origins.has(face) or owner_of[face] != target:
				continue
			var built := face as FaceData
			# The face where the other brush's faces are, to read them there.
			var probe := FaceData.new()
			var corners := PackedVector3Array()
			for corner in built.local_verts:
				corners.append(into_other * corner)
			probe.local_verts = corners
			var source: FaceData = HFConvexClip._largest_on_face(other.get_faces(), probe, ON_PLANE)
			if source == null:
				continue
			built.copy_appearance_from(source)
			if (
				source.custom_uvs.size() == source.local_verts.size()
				or source.uv_projection == FaceData.UVProjection.CYLINDRICAL
			):
				built.custom_uvs = source.shown_uvs_at(corners)
			else:
				built.custom_uvs = PackedVector2Array()
			owner_of[face] = other
	return owner_of


## Keep the material each face showed when the brushes did not share one.
##
## A face with no palette slot shows its brush's material override, and the kept
## brush has the target's override at most. So when a face from another brush
## showed an override other than the target's, every face that showed an override
## takes it as a palette slot instead, as a merged face does, and the kept brush
## has none. True when that was done.
func _overrides_as_slots(faces: Array, owner_of: Dictionary, target: DraftBrush) -> bool:
	var differs := false
	for face in faces:
		var draft := owner_of[face] as DraftBrush
		if (
			(face as FaceData).material_idx < 0
			and draft.material_override != target.material_override
		):
			differs = true
			break
	if not differs or not root.has_method("add_material_to_palette"):
		return false
	var slot_of := {}  # Material -> int
	for face in faces:
		var built := face as FaceData
		var draft := owner_of[face] as DraftBrush
		if built.material_idx >= 0 or draft.material_override == null:
			continue
		if not slot_of.has(draft.material_override):
			slot_of[draft.material_override] = root.add_material_to_palette(draft.material_override)
		built.material_idx = int(slot_of[draft.material_override])
	return true


# ---------------------------------------------------------------------------
# Hull of Selection
# ---------------------------------------------------------------------------


## Replace `brush_ids` with one brush, the convex hull of all their corners,
## whether they touch or not (#1715).
##
## Merge makes the exact union and refuses brushes that do not touch or whose
## union is an L, so a ramp from one ledge down to another, or a column tapering
## from a small top block to a wide base, was built by vertex editing a box. This
## is a command of its own, so nobody asking for a union gets a hull. The brush is
## the first one's: its operation, visgroups, group and bake settings, with the
## one entity they all are and every wire any of them held, as Merge keeps.
func hull_brushes_by_ids(brush_ids: Array) -> HFOpResult:
	# The rules live in the plan and hold here as well as at the press that asked
	# first: the undo entry stores this method and these ids.
	var plan := _plan_hull(brush_ids)
	var check: HFOpResult = plan["result"]
	if not check.ok:
		return _op_fail(check.message, check.fix_hint)
	var drafts: Array = plan["drafts"]
	var target: DraftBrush = drafts[0]
	var faces: Array = plan["faces"]
	var origins: Dictionary = plan["origins"]
	# A face that grew cannot hold its sculpt. The confirmation named them, so the
	# message says how many went rather than a warning in the output.
	var lost := HFConvexClip.carry_onto_union(faces, origins)
	_give_active_material(plan["new_faces"], target)
	var as_slots := _overrides_as_slots(faces, plan["owner_of"], target)
	# Made before anything is deleted, so a brush that could not be made leaves
	# every source where it was.
	var info: Dictionary = root.brush_system._piece_infos_from_faces(target, [faces])[0]
	info.merge(HFBrushEntity.carried_by_all(drafts), true)
	if as_slots:
		info.erase("material")
	root.tag_full_reconcile()
	if root.brush_system.create_brush_from_info(info) == null:
		return _op_fail("Hull: produced no geometry")
	for draft in drafts:
		root.brush_system.delete_brush(draft)
	var msg := "Hull: wrapped %d brushes in one" % drafts.size()
	if lost > 0:
		msg += ", and %d sculpt%s could not follow" % [lost, "" if lost == 1 else "s"]
	root._log(msg)
	return HFOpResult.success(msg)


## Whether these brushes can be wrapped in one, and if not, why. Asked before the
## confirmation opens, as Intersect asks its own.
func can_hull_brushes(brush_ids: Array) -> HFOpResult:
	return _plan_hull(brush_ids)["result"]


## What wrapping `brush_ids` would make, worked out without changing the level.
##
## Returns `{"result", "drafts", "faces", "origins", "owner_of", "new_faces"}`:
## the brushes, the first one first, the hull's faces in its space, for each face
## on an old face's plane that face, the largest there, the brush each face takes
## its look from, and the faces on no old plane. A new face looks like the old
## face it most nearly faces as, until the hull is made and it takes the Active
## Material. Side effect free, so the check, the preview and the hull agree.
func _plan_hull(brush_ids: Array) -> Dictionary:
	var drafts: Array = []
	for brush_id in brush_ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if not brush or not (brush is DraftBrush):
			return _hull_refusal("Hull: brush '%s' not found" % str(brush_id))
		if not drafts.has(brush):
			drafts.append(brush)
	if drafts.size() < 2:
		return _hull_refusal(
			"Hull: select at least 2 brushes", "Clip to Convex in Vertex mode wraps one brush"
		)
	var target := drafts[0] as DraftBrush
	for draft in drafts:
		if (draft as DraftBrush).operation != target.operation:
			return _hull_refusal(
				"Hull: all brushes must have the same operation type",
				"Cannot wrap solid brushes and cuts in one"
			)
	if not HFBrushEntity.are_one_entity(drafts):
		return _hull_refusal(
			"Hull: the selected brushes are not all one entity",
			"Wrap the brushes of one door or trigger, or plain brushes. Tie or untie them first"
		)
	var sources: Array = []
	var source_owner := {}
	var points := PackedVector3Array()
	for draft in drafts:
		root.brush_system._ensure_faces(draft)
		var carried: Array = HFBrushSystem._faces_carried(draft, _in_space_of(target, draft))
		if carried.size() < 4:
			return _hull_refusal(
				"Hull: brush '%s' has no usable geometry" % _brush_id_of(draft),
				"Rebuild or redraw it and try again"
			)
		for face in carried:
			sources.append(face)
			source_owner[face] = draft
			points.append_array((face as FaceData).local_verts)
	var hull: Dictionary = HFHullType.of(points, _placement_rounding(drafts))
	if not hull["ok"]:
		return _hull_refusal("Hull: the brushes hold no solid", hull["reason"])
	var faces: Array = hull["faces"]
	var origins := {}
	var owner_of := {}
	var new_faces: Array = []
	for face in faces:
		var built := face as FaceData
		var source: FaceData = HFConvexClip._largest_on_face(sources, built, ON_PLANE)
		if source == null:
			source = HFConvexClip._nearest_face(sources, built.normal)
			new_faces.append(built)
		else:
			origins[built] = source
		if source != null:
			built.copy_appearance_from(source)
		owner_of[built] = source_owner.get(source, target)
	return {
		"result": HFOpResult.success(),
		"drafts": drafts,
		"faces": faces,
		"origins": origins,
		"owner_of": owner_of,
		"new_faces": new_faces,
	}


## Where `draft` is in `target`'s space. The two origins are taken apart in the
## world before the turn, so the rounding is that of the distance between them
## and not of their distance from the origin. Kilometres out the product of the
## two transforms put a turned brush's corners a few ten-thousandths off, and the
## hull, which holds a corner 0.0001 off a face's plane as off it, came out open
## (#1971).
static func _in_space_of(target: Node3D, draft: Node3D) -> Transform3D:
	var from := target.global_transform
	var to := draft.global_transform
	var unturn := from.basis.inverse()
	return Transform3D(unturn * to.basis, unturn * (to.origin - from.origin))


## How far out of line a float can set two of `drafts`, at the largest coordinate
## of their places. A float's step is 0.0002 three kilometres out, so two brushes
## turned together there need not line up to the hull's 0.0001, and the hull made
## a face of each where one face goes (#1971).
static func _placement_rounding(drafts: Array) -> float:
	var far := 0.0
	for draft in drafts:
		var at: Vector3 = (draft as Node3D).global_transform.origin
		far = maxf(far, maxf(absf(at.x), maxf(absf(at.y), absf(at.z))))
	return far * PLACEMENT_STEPS


static func _hull_refusal(msg: String, hint: String = "") -> Dictionary:
	return {
		"result": HFOpResult.fail(msg, hint),
		"drafts": [],
		"faces": [],
		"origins": {},
		"owner_of": {},
		"new_faces": [],
	}


## Lay the level's Active Material on the hull's new faces, as a palette slot,
## with its texture laid afresh. A cut keeps the cut look, as a drawn one does.
func _give_active_material(new_faces: Array, target: DraftBrush) -> void:
	var material: Variant = root.get("active_material")
	if new_faces.is_empty() or not (material is Material):
		return
	if target.operation == CSGShape3D.OPERATION_SUBTRACTION:
		return
	var slot := -1
	var manager = root.get("material_manager")
	if manager != null:
		slot = (manager.materials as Array).find(material)
	if slot < 0 and root.has_method("add_material_to_palette"):
		slot = root.add_material_to_palette(material)
	for face in new_faces:
		var built := face as FaceData
		built.material_idx = slot
		built.custom_uvs = PackedVector2Array()


func _op_fail(msg: String, hint: String = "") -> HFOpResult:
	if root and root.has_signal("user_message"):
		root.emit_signal("user_message", msg, 1)  # WARNING level
	return HFOpResult.fail(msg, hint)
