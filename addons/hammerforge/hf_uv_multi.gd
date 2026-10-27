@tool
extends RefCounted
## Texture settings on every selected face at once, and the keys that slide and
## turn the texture (#1728).
##
## The Paint tab's boxes edited the face on show only, so a scale for twenty faces
## was typed twenty times, and with faces that differed the boxes showed one
## face's numbers as if all matched. Lining a texture up by eye meant typing
## offsets, in steps of 0.01 that a 2 m brick never notices. A typed field now
## goes to every selected face and leaves their other fields alone, a field the
## faces disagree on says so, and in Face Select the arrows slide each selected
## face's texture the way the arrow points on screen.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The fields the Paint tab's UV boxes edit. Rotation is in degrees, as the box
## shows it.
const FIELDS := ["scale_x", "scale_y", "offset_x", "offset_y", "rotation"]
## How far a face's plane may turn from the screen before the slide keys pass
## it by: a face seen edge on has no screen direction to slide along.
const EDGE_ON := 0.2
## The turn steps in degrees: a press, with Alt, and Up or Down.
const TURN_STEP := 15.0
const FINE_TURN_STEP := 1.0
const QUARTER_TURN := 90.0
## A slide with Alt is a tenth of the grid step.
const FINE_SLIDE := 0.1


## The selected faces: `{"brush_id", "index", "face"}` for each face the level's
## face selection names that is there.
static func picked(root: Node) -> Array:
	var out: Array = []
	if root == null or not (root.get("face_selection") is Dictionary):
		return out
	for key in root.face_selection.keys():
		var brush = root.brush_system._find_brush_by_key(str(key))
		if brush == null:
			continue
		for index in root.face_selection[key]:
			var at := int(index)
			if at >= 0 and at < brush.faces.size() and brush.faces[at] != null:
				out.append({"brush_id": str(brush.brush_id), "index": at, "face": brush.faces[at]})
	return out


## The value `face` holds for `field`, rotation in degrees.
static func value_of(face: FaceData, field: String) -> float:
	match field:
		"scale_x":
			return face.uv_scale.x
		"scale_y":
			return face.uv_scale.y
		"offset_x":
			return face.uv_offset.x
		"offset_y":
			return face.uv_offset.y
		"rotation":
			return rad_to_deg(face.uv_rotation)
	return 0.0


## Whether `records` disagree on `field`.
static func mixed(records: Array, field: String) -> bool:
	if records.size() < 2:
		return false
	var first := value_of(records[0]["face"], field)
	for record in records:
		if not is_equal_approx(value_of(record["face"], field), first):
			return true
	return false


## The changes that set `field` to `value` on each of `records` and leave their
## other fields as they are, for `LevelRoot.set_uv_params_on_faces()`. With
## `linked`, a typed scale sets the other axis to the same size, its sign kept.
static func field_changes(records: Array, field: String, value: float, linked: bool) -> Array:
	var out: Array = []
	for record in records:
		var face: FaceData = record["face"]
		var uv_scale := face.uv_scale
		var offset := face.uv_offset
		var turn := face.uv_rotation
		match field:
			"scale_x":
				uv_scale.x = value
				if linked:
					uv_scale.y = absf(value) * (-1.0 if uv_scale.y < 0.0 else 1.0)
			"scale_y":
				uv_scale.y = value
				if linked:
					uv_scale.x = absf(value) * (-1.0 if uv_scale.x < 0.0 else 1.0)
			"offset_x":
				offset.x = value
			"offset_y":
				offset.y = value
			"rotation":
				turn = deg_to_rad(value)
		out.append([record["brush_id"], record["index"], uv_scale, offset, turn])
	return out


## The changes that slide each face's texture `step` metres the way `screen`
## points on screen, `screen` (1, 0) right and (0, 1) up, worked out from the
## camera's right and up and each face's own texture axes. A face seen edge on,
## or Cylindrical, which has no flat axes, is left out. Returns `{"changes",
## "skipped"}`.
static func slide_changes(
	records: Array, right: Vector3, up: Vector3, screen: Vector2, step: float
) -> Dictionary:
	var out: Array = []
	var skipped := 0
	var along := (right * screen.x + up * screen.y).normalized()
	for record in records:
		var face: FaceData = record["face"]
		var axes := face.texture_axes()
		var normal := face.normal_through(face.world_transform.basis).normalized()
		var on_face := along - normal * along.dot(normal)
		if axes.is_empty() or on_face.length() < EDGE_ON:
			skipped += 1
			continue
		var moved := on_face.normalized() * step
		# Read off what the face shows from its middle to `moved` along, so a face
		# with a layout of its own slides the way the key points (#1993).
		var middle := _middle_of(face)
		var there: Vector3 = (
			face.world_transform.affine_inverse() * (face.world_transform * middle + moved)
		)
		var reading := face.raw_uvs_at(PackedVector3Array([middle, there]))
		var raw: Vector2 = reading[1] - reading[0]
		var offset := face.uv_offset - raw.rotated(face.uv_rotation) * face.uv_scale
		out.append([record["brush_id"], record["index"], face.uv_scale, offset, face.uv_rotation])
	return {"changes": out, "skipped": skipped}


## The changes that turn each face's texture by `degrees` about the middle of the
## face, so the texture there stays where it is. Cylindrical faces are left out.
static func turn_changes(records: Array, degrees: float) -> Dictionary:
	var out: Array = []
	var skipped := 0
	for record in records:
		var face: FaceData = record["face"]
		var axes := face.texture_axes()
		if axes.is_empty() or face.local_verts.is_empty():
			skipped += 1
			continue
		# What the face shows at its middle, so one with a layout of its own turns
		# about its middle too (#1993).
		var raw: Vector2 = face.raw_uvs_at(PackedVector3Array([_middle_of(face)]))[0]
		var turn := wrapf(face.uv_rotation + deg_to_rad(degrees), -PI, PI)
		var offset := (
			face.uv_offset
			+ raw.rotated(face.uv_rotation) * face.uv_scale
			- raw.rotated(turn) * face.uv_scale
		)
		out.append([record["brush_id"], record["index"], face.uv_scale, offset, turn])
	return {"changes": out, "skipped": skipped}


## The middle of `face`'s corners, in its brush's space.
static func _middle_of(face: FaceData) -> Vector3:
	var middle := Vector3.ZERO
	for corner in face.local_verts:
		middle += corner
	return middle / maxf(1.0, float(face.local_verts.size()))


## The brush ids `changes` touch, for an undo step's scope.
static func brush_ids_of(changes: Array) -> Array:
	var out: Array = []
	for change in changes:
		if not out.has(change[0]):
			out.append(change[0])
	return out
