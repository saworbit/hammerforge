@tool
class_name HFCarveSystem
extends RefCounted

## Performs boolean subtraction (carve) of one brush against all overlapping brushes.
## The carver's volume is "cut out" of every intersecting brush, splitting each
## into up to 6 box slices that surround the carved region.

const DraftBrush = preload("../brush_instance.gd")

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
	var carver_pos: Vector3 = carver_draft.global_position
	var carver_size: Vector3 = carver_draft.size
	var carver_aabb := AABB(carver_pos - carver_size * 0.5, carver_size)

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
		var target_id := str(target_draft.brush_id)
		if target_id == "" and target_draft.has_meta("brush_id"):
			target_id = str(target_draft.get_meta("brush_id"))
		var target_pos: Vector3 = target_draft.global_position
		var target_size: Vector3 = target_draft.size
		var target_aabb := AABB(target_pos - target_size * 0.5, target_size)

		# Compute intersection — skip if ANY axis has zero/negligible overlap
		# (face/edge contact only, not a volumetric intersection)
		var inter := target_aabb.intersection(carver_aabb)
		if (
			inter.size.x <= min_thickness
			or inter.size.y <= min_thickness
			or inter.size.z <= min_thickness
		):
			continue

		# Gather metadata from target to copy to pieces
		var target_mat = target_draft.material_override
		var target_operation: int = target_draft.operation
		var target_visgroups: PackedStringArray = target_draft.get_meta(
			"visgroups", PackedStringArray()
		)
		var target_group_id: String = str(target_draft.get_meta("group_id", ""))
		var target_bec: String = str(target_draft.get_meta("brush_entity_class", ""))
		var target_faces: Array = target_draft.faces

		# Build up to 6 slices around the carved-out region
		var slices: Array = _compute_slices(target_pos, target_size, carver_pos, carver_size)

		if slices.is_empty():
			continue

		# Delete original target brush
		root.brush_system.delete_brush_by_id(target_id)

		# Create replacement pieces
		for slice_info in slices:
			slice_info["operation"] = target_operation
			slice_info["brush_id"] = root.brush_system._next_brush_id()
			if target_mat:
				slice_info["material"] = target_mat
			var piece = root.brush_system.create_brush_from_info(slice_info)
			if piece:
				if not target_visgroups.is_empty():
					piece.set_meta("visgroups", target_visgroups)
				if target_group_id != "":
					piece.set_meta("group_id", target_group_id)
				if target_bec != "":
					piece.set_meta("brush_entity_class", target_bec)
				var slice_center: Vector3 = slice_info.get("center", Vector3.ZERO)
				_copy_uv_settings_to_piece(piece, target_faces, target_pos, slice_center)
				total_pieces += 1

		targets_carved += 1

	# Delete the carver brush
	root.brush_system.delete_brush_by_id(brush_id)

	var msg := "Carve: carved %d brush(es), created %d pieces" % [targets_carved, total_pieces]
	root._log(msg)
	return HFOpResult.success(msg)


## Compute up to 6 box slices of target_brush that remain after carving out the
## carver volume.  Each slice is a dict with "shape", "size", "center" keys.
##
## The slices are:
##   -X (left), +X (right), -Y (bottom), +Y (top), -Z (back), +Z (front)
## computed by progressive remainder — each successive slice uses the space
## remaining after the previous axis was consumed.
func _compute_slices(
	target_pos: Vector3, target_size: Vector3, carver_pos: Vector3, carver_size: Vector3
) -> Array:
	# Target bounds
	var t_min := target_pos - target_size * 0.5
	var t_max := target_pos + target_size * 0.5

	# Carver bounds, clamped to target
	var c_min := Vector3(
		maxf(carver_pos.x - carver_size.x * 0.5, t_min.x),
		maxf(carver_pos.y - carver_size.y * 0.5, t_min.y),
		maxf(carver_pos.z - carver_size.z * 0.5, t_min.z)
	)
	var c_max := Vector3(
		minf(carver_pos.x + carver_size.x * 0.5, t_max.x),
		minf(carver_pos.y + carver_size.y * 0.5, t_max.y),
		minf(carver_pos.z + carver_size.z * 0.5, t_max.z)
	)

	var slices: Array = []

	# Left slice (X-): full Y and Z extent of target, from t_min.x to c_min.x
	var left_w := c_min.x - t_min.x
	if left_w > min_thickness:
		slices.append(
			_make_slice(
				Vector3(left_w, target_size.y, target_size.z),
				Vector3(t_min.x + left_w * 0.5, target_pos.y, target_pos.z)
			)
		)

	# Right slice (X+): full Y and Z extent, from c_max.x to t_max.x
	var right_w := t_max.x - c_max.x
	if right_w > min_thickness:
		slices.append(
			_make_slice(
				Vector3(right_w, target_size.y, target_size.z),
				Vector3(c_max.x + right_w * 0.5, target_pos.y, target_pos.z)
			)
		)

	# Remaining X span for Y and Z slices
	var mid_x_min := c_min.x
	var mid_x_max := c_max.x
	var mid_x_size := mid_x_max - mid_x_min
	var mid_x_center := (mid_x_min + mid_x_max) * 0.5

	# Bottom slice (Y-): uses middle X span, full Z extent
	var bottom_h := c_min.y - t_min.y
	if bottom_h > min_thickness and mid_x_size > min_thickness:
		slices.append(
			_make_slice(
				Vector3(mid_x_size, bottom_h, target_size.z),
				Vector3(mid_x_center, t_min.y + bottom_h * 0.5, target_pos.z)
			)
		)

	# Top slice (Y+): uses middle X span, full Z extent
	var top_h := t_max.y - c_max.y
	if top_h > min_thickness and mid_x_size > min_thickness:
		slices.append(
			_make_slice(
				Vector3(mid_x_size, top_h, target_size.z),
				Vector3(mid_x_center, c_max.y + top_h * 0.5, target_pos.z)
			)
		)

	# Remaining Y span for Z slices
	var mid_y_min := c_min.y
	var mid_y_max := c_max.y
	var mid_y_size := mid_y_max - mid_y_min
	var mid_y_center := (mid_y_min + mid_y_max) * 0.5

	# Back slice (Z-): uses middle X and Y span
	var back_d := c_min.z - t_min.z
	if back_d > min_thickness and mid_x_size > min_thickness and mid_y_size > min_thickness:
		slices.append(
			_make_slice(
				Vector3(mid_x_size, mid_y_size, back_d),
				Vector3(mid_x_center, mid_y_center, t_min.z + back_d * 0.5)
			)
		)

	# Front slice (Z+): uses middle X and Y span
	var front_d := t_max.z - c_max.z
	if front_d > min_thickness and mid_x_size > min_thickness and mid_y_size > min_thickness:
		slices.append(
			_make_slice(
				Vector3(mid_x_size, mid_y_size, front_d),
				Vector3(mid_x_center, mid_y_center, c_max.z + front_d * 0.5)
			)
		)

	return slices


func _make_slice(size: Vector3, center: Vector3) -> Dictionary:
	return {
		"shape": root.BrushShape.BOX,
		"size": size,
		"center": center,
	}


## Find all DraftBrush nodes whose AABB overlaps the given AABB,
## excluding the brush with the given ID.
func _find_overlapping_brushes(exclude_id: String, aabb: AABB) -> Array:
	var result: Array = []
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var draft := node as DraftBrush
		var bid := str(draft.brush_id)
		if bid == "" and draft.has_meta("brush_id"):
			bid = str(draft.get_meta("brush_id"))
		if bid == exclude_id:
			continue
		var node_pos: Vector3 = draft.global_position
		var node_size: Vector3 = draft.size
		var node_aabb := AABB(node_pos - node_size * 0.5, node_size)
		if aabb.intersects(node_aabb):
			result.append(draft)
	return result


## Copy UV settings from the original target's faces to a carved slice piece.
## Each new face gets BOX_UV projection and inherits UV scale/offset/rotation
## from the best-matching original face (matched by normal direction).
## Compensates UV offset for the positional difference between the original
## brush center and the slice center so textures stay aligned.
func _copy_uv_settings_to_piece(
	piece: Node, target_faces: Array, target_pos: Vector3, slice_center: Vector3
) -> void:
	if not (piece is DraftBrush):
		return
	var draft := piece as DraftBrush
	if draft.faces.is_empty() or target_faces.is_empty():
		return
	var pos_delta: Vector3 = slice_center - target_pos
	for face in draft.faces:
		if face == null:
			continue
		face.uv_projection = FaceData.UVProjection.BOX_UV
		var best_face: FaceData = null
		var best_dot: float = -2.0
		for src_face in target_faces:
			if src_face == null:
				continue
			var d: float = face.normal.dot(src_face.normal)
			if d > best_dot:
				best_dot = d
				best_face = src_face
		if best_face:
			face.uv_scale = best_face.uv_scale
			face.uv_rotation = best_face.uv_rotation
			face.material_idx = best_face.material_idx
			# Compensate offset for the slice's different position in world space.
			# The slice center moved by pos_delta, so each face's local vertices
			# shift by -pos_delta, making projected UVs: uv_new = uv_old - delta_2d.
			# Under new transform order uv.rotated(R)*S + O, solving for O_new:
			#   O_new = O_old + delta_2d.rotated(R) * S
			var resolved_proj: int = best_face.uv_projection
			if resolved_proj == FaceData.UVProjection.BOX_UV:
				resolved_proj = face._box_projection_axis()
			var delta_2d := Vector2.ZERO
			match resolved_proj:
				FaceData.UVProjection.PLANAR_X:
					delta_2d = Vector2(pos_delta.z, pos_delta.y)
				FaceData.UVProjection.PLANAR_Y:
					delta_2d = Vector2(pos_delta.x, pos_delta.z)
				FaceData.UVProjection.PLANAR_Z:
					delta_2d = Vector2(pos_delta.x, pos_delta.y)
			var rotated_delta: Vector2 = delta_2d
			if best_face.uv_rotation != 0.0:
				rotated_delta = delta_2d.rotated(best_face.uv_rotation)
			face.uv_offset = best_face.uv_offset + rotated_delta * best_face.uv_scale
	draft.rebuild_preview()


func _op_fail(msg: String, hint: String = "") -> HFOpResult:
	if root and root.has_signal("user_message"):
		root.emit_signal("user_message", msg, 1)  # WARNING level
	return HFOpResult.fail(msg, hint)
