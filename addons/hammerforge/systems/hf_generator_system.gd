@tool
extends RefCounted
class_name HFGeneratorSystem

## Keeps generated structures editable after they exist.
##
## A generator turns a handful of numbers into a lot of brushes. Without a record
## of that, the numbers are lost the moment the brushes appear, and changing your
## mind about a radius means rebuilding by hand. This holds the records, and
## rebuilds a structure in place when its settings change.
##
## The record is a hint, never a guarantee. Brushes can be deleted, carved or
## merged away without this system knowing, so every use filters the record
## against what actually exists.

const HFArchBuilder = preload("../hf_arch_builder.gd")
const HFDomeBuilder = preload("../hf_dome_builder.gd")
const HFGenerator = preload("../hf_generator.gd")
const HFOpResult = preload("../hf_op_result.gd")
const HFSpiralStairsBuilder = preload("../hf_spiral_stairs_builder.gd")
const HFStairsBuilder = preload("../hf_stairs_builder.gd")

const GENERATOR_META := &"hf_generator_id"

## Generator types this system can build. A builder owns its own settings, its own
## validation and its own arithmetic, so adding one means writing the builder and
## naming it in `builder_for()`. Nothing else in the system, and nothing at all in
## the dock, has to know it exists.
const TYPE_ARCH := "arch"
const TYPE_STAIRS := "stairs"
const TYPE_SPIRAL_STAIRS := "spiral_stairs"
const TYPE_DOME := "dome"

## How far two pieces can disagree about how far they have moved and still count
## as having moved together. A user dragging a structure moves every piece by
## exactly the same amount; anything looser than this is individual editing.
const RELOCATION_EPSILON := 0.01

## How far two pieces can disagree about how far they have been *turned* and
## still count as having been turned together. Basis columns are unit length, so
## this is an angle in disguise: about a twentieth of a degree.
const ROTATION_EPSILON := 0.001

var root: Node3D
var generators: Dictionary = {}  # generator_id -> HFGenerator


func _init(level_root: Node3D = null) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# The builders this system knows
# ---------------------------------------------------------------------------


static func known_types() -> PackedStringArray:
	return PackedStringArray([TYPE_ARCH, TYPE_STAIRS, TYPE_SPIRAL_STAIRS, TYPE_DOME])


## The one place that knows which builder is which. Everything below asks here.
static func builder_for(type: String):
	match type:
		TYPE_ARCH:
			return HFArchBuilder
		TYPE_STAIRS:
			return HFStairsBuilder
		TYPE_SPIRAL_STAIRS:
			return HFSpiralStairsBuilder
		TYPE_DOME:
			return HFDomeBuilder
		_:
			return null


## What to call this in the dock. Derived rather than tabled, so a new type gets a
## readable name without a second list to keep in step.
static func display_name(type: String) -> String:
	return type.replace("_", " ").capitalize()


static func default_settings(type: String) -> Dictionary:
	var builder = builder_for(type)
	return builder.default_settings() if builder else {}


## The fields a type has, described well enough for the dock to build controls.
static func settings_schema(type: String) -> Array:
	var builder = builder_for(type)
	return builder.settings_schema() if builder else []


static func validate(type: String, settings: Dictionary) -> HFOpResult:
	var builder = builder_for(type)
	if builder == null:
		return HFOpResult.fail(
			"Generator: '%s' is not a generator type" % type,
			"Known types: %s" % ", ".join(known_types())
		)
	var result = builder.validate(settings)
	# A builder that returns nothing is a bug in the builder, but it must not
	# become a null out of create_generator(), which is declared to hand back a
	# result every caller then reads `.ok` off.
	if result == null:
		return HFOpResult.fail(
			"Generator: '%s' could not check those settings" % type,
			"Check the settings for a value of the wrong type"
		)
	return result


## One face set per piece the structure is made of, in the structure's own space.
static func build_faces(type: String, settings: Dictionary) -> Array:
	var builder = builder_for(type)
	return builder.build(settings) if builder else []


## Whether these settings would build, without building anything that lasts.
##
## Each field can be in range while the combination is not: a wall as thick as
## the arch is wide, an arc of zero, a wide arc across too few segments. The
## builder refuses those, so the dock has to be able to ask before it opens an
## undo action and tells the user it worked.
static func can_build(type: String, settings: Dictionary) -> HFOpResult:
	var check := validate(type, settings)
	if not check.ok:
		return check
	if build_faces(type, settings).is_empty():
		return HFOpResult.fail(
			"%s: those settings produce no geometry" % display_name(type),
			"Widen the structure or add segments"
		)
	return HFOpResult.success()


# ---------------------------------------------------------------------------
# Creating, changing and forgetting
# ---------------------------------------------------------------------------


func create(type: String, settings: Dictionary, placement: Transform3D) -> HFOpResult:
	var check := validate(type, settings)
	if not check.ok:
		return check
	var face_sets := build_faces(type, settings)
	if face_sets.is_empty():
		return HFOpResult.fail("Generator: '%s' produced no geometry" % type)

	var record := HFGenerator.new()
	record.type = type
	record.settings = settings.duplicate(true)
	record.placement = placement
	record.brush_ids = _spawn(face_sets, placement, record.generator_id, [])
	if record.brush_ids.is_empty():
		return HFOpResult.fail("Generator: '%s' produced no geometry" % type)
	_record_signatures(record)

	generators[record.generator_id] = record
	var message := "%s: created %d pieces" % [type.capitalize(), record.brush_ids.size()]
	if root and root.has_method("_log"):
		root._log(message)
	return HFOpResult.success(message)


## Rebuild a structure in place from new settings.
##
## Nothing is deleted until the new settings are known to be buildable, so a bad
## edit leaves the existing structure exactly as it was rather than removing it
## and then failing to replace it.
func regenerate(generator_id: String, settings: Dictionary) -> HFOpResult:
	if not generators.has(generator_id):
		return HFOpResult.fail("Generator: no structure with id '%s'" % generator_id)
	var record: HFGenerator = generators[generator_id]
	var check := validate(record.type, settings)
	if not check.ok:
		return check
	var face_sets := build_faces(record.type, settings)
	if face_sets.is_empty():
		return HFOpResult.fail("Generator: those settings produce no geometry")

	# Appearance is what a designer adds after generating, so losing it on every
	# radius nudge would make this not worth using. Captured in order and put back
	# by index; when the piece count changes there is no correspondence past the
	# shorter list, and the extra pieces take the default.
	var appearance := _capture_appearance(record)
	# Where the structure is now, not where it was made. Read before anything is
	# deleted, because it is the existing pieces that say where they have gone.
	record.placement = relocation_transform(generator_id) * record.placement
	_delete_brushes(record.brush_ids, generator_id)

	record.settings = settings.duplicate(true)
	record.brush_ids = _spawn(face_sets, record.placement, generator_id, appearance)
	if record.brush_ids.is_empty():
		generators.erase(generator_id)
		return HFOpResult.fail("Generator: those settings produce no geometry")
	_record_signatures(record)
	var message := "%s: rebuilt as %d pieces" % [record.type.capitalize(), record.brush_ids.size()]
	if root and root.has_method("_log"):
		root._log(message)
	return HFOpResult.success(message)


## Forget the record and leave the brushes as ordinary geometry.
##
## The escape hatch for a structure that has been edited by hand and should stop
## being rebuilt out from under those edits.
func detach(generator_id: String) -> bool:
	if not generators.has(generator_id):
		return false
	var record: HFGenerator = generators[generator_id]
	for brush_id in record.brush_ids:
		var brush = _brush(str(brush_id))
		if brush and brush.has_meta(GENERATOR_META):
			brush.remove_meta(GENERATOR_META)
	generators.erase(generator_id)
	return true


## Delete the structure and its record together.
func remove(generator_id: String) -> bool:
	if not generators.has(generator_id):
		return false
	var record: HFGenerator = generators[generator_id]
	_delete_brushes(record.brush_ids, generator_id)
	generators.erase(generator_id)
	return true


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------


func generator_for_id(generator_id: String) -> HFGenerator:
	return generators.get(generator_id, null)


func generator_for_brush(brush_id: String) -> HFGenerator:
	var brush = _brush(brush_id)
	if brush == null or not brush.has_meta(GENERATOR_META):
		return null
	var generator_id := str(brush.get_meta(GENERATOR_META))
	return generators.get(generator_id, null)


## The generator that owns the first brush in a selection that belongs to one.
func generator_for_selection(brush_ids: Array) -> HFGenerator:
	for brush_id in brush_ids:
		var record := generator_for_brush(str(brush_id))
		if record != null:
			return record
	return null


# ---------------------------------------------------------------------------
# What has happened to a structure since it was made
# ---------------------------------------------------------------------------


## How far the whole structure has been dragged since it was last built.
##
## A user who moves a structure moves every piece of it by exactly the same
## amount, so that is the test: if every surviving piece agrees on the delta, the
## structure was relocated and it should rebuild where it now is. If the pieces
## disagree they were moved individually, which is editing rather than
## relocating, and the placement stays where it was.
##
## Without this, dragging an arch into a doorway and then widening it puts the
## arch back where it was created — which is where the whole premise of changing
## your mind after seeing it in place falls down.
func relocation_transform(generator_id: String) -> Transform3D:
	var vote := _relocation_vote(generator_id)
	return vote["move"]


## Whether the pieces could not agree on where the structure is, having plainly
## been moved from where they were put.
##
## The honest reading of a structure nobody can locate: a rebuild has nowhere to
## put it but the placement it was created at, which may be across the level. The
## section says that rather than only counting shapes.
func pieces_disagree_about_placement(generator_id: String) -> bool:
	var vote := _relocation_vote(generator_id)
	return not vote["agreed"] and vote["moved"]


## Where the structure has gone, decided by vote rather than by unanimity.
##
## Unanimity sounds like the stricter test and is in fact the worse one. Nudge a
## single brush of a twelve-piece arch you have dragged across the level and the
## eleven that agree are overruled: the structure reads as twelve hand edits
## instead of one, and Update carries the whole thing back to the origin it was
## created at. More than half the pieces agreeing is enough to say where the
## structure went, and the ones outside that majority are the hand edits — which
## is exactly what they are.
##
## A piece whose move is not rigid never joins a group, so a mirrored or squashed
## structure cannot out-vote its own refusal however many pieces it has.
##
## Returns `move` (the relocation, identity when undecided), `agreed` (whether a
## majority was found) and `moved` (whether any piece has left its recorded spot).
func _relocation_vote(generator_id: String) -> Dictionary:
	var undecided := {"move": Transform3D.IDENTITY, "agreed": false, "moved": false}
	if not generators.has(generator_id):
		return undecided
	var record: HFGenerator = generators[generator_id]
	var groups: Array = []
	var voters := 0
	for brush_id in record.brush_ids:
		var reading = _piece_move(record, str(brush_id), generator_id)
		if reading == null:
			continue
		voters += 1
		var move: Transform3D = reading
		if not _same_move(move, Transform3D.IDENTITY):
			undecided["moved"] = true
		if not _is_rigid(move):
			continue
		var joined := false
		for group in groups:
			if _same_move(move, group["move"]):
				group["votes"] = int(group["votes"]) + 1
				joined = true
				break
		if not joined:
			groups.append({"move": move, "votes": 1})

	var best: Dictionary = {}
	for group in groups:
		if best.is_empty() or int(group["votes"]) > int(best["votes"]):
			best = group
	if best.is_empty() or int(best["votes"]) * 2 <= voters:
		return undecided
	return {"move": best["move"], "agreed": true, "moved": undecided["moved"]}


## How one piece has moved since it was recorded, or `null` when it cannot say:
## no signature, not ours any more, or a signature that never was a usable frame.
func _piece_move(record: HFGenerator, brush_id: String, generator_id: String) -> Variant:
	var signature: Dictionary = record.brush_signatures.get(brush_id, {})
	if signature.is_empty():
		return null
	var brush = _owned_brush(brush_id, generator_id)
	if brush == null:
		return null
	var was := _signature_transform(record, signature)
	if is_zero_approx(was.basis.determinant()):
		return null
	return brush.global_transform * was.affine_inverse()


## How far the structure has been dragged, ignoring any turn.
##
## Kept because a translation is what most callers mean and what most of the
## tests ask about. The rebuild itself uses the whole transform.
func relocation_delta(generator_id: String) -> Vector3:
	return relocation_transform(generator_id).origin


## Where a piece was put, as a transform rather than a point.
##
## A record written before turning was understood has no basis for its pieces,
## and the right answer for one of those is the placement's own basis: that is
## what every piece the generator built was given, so a record that predates the
## field reads exactly as it would have been written today.
static func _signature_transform(record: HFGenerator, signature: Dictionary) -> Transform3D:
	return Transform3D(
		signature.get("basis", record.placement.basis), signature.get("origin", Vector3.ZERO)
	)


static func _same_move(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > RELOCATION_EPSILON:
		return false
	for axis in 3:
		if a.basis[axis].distance_to(b.basis[axis]) > ROTATION_EPSILON:
			return false
	return true


## Whether a move is one a structure could have been given as a whole: a turn and
## a slide, nothing else.
##
## A squash or a stretch is not a relocation, and a mirror is worse than not one —
## rebuilding through a negative-determinant basis would invert the winding of
## every face in the structure and not look wrong until the bake. Both answer no,
## which leaves the placement alone and lets the pieces read as edited, which is
## what they are.
static func _is_rigid(move: Transform3D) -> bool:
	return HFTransformSystem.is_rotation_basis(move.basis)


## The pieces of a structure that are no longer the shape they were generated as.
##
## Vertex-dragged, clipped, bevelled, resized or turned — anything that changes
## what the piece *is* rather than only where it is. A rebuild replaces these, so
## the count is worth saying out loud before it happens.
func edited_brush_ids(generator_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not generators.has(generator_id):
		return out
	var record: HFGenerator = generators[generator_id]
	var moved := relocation_transform(generator_id)
	for brush_id in record.brush_ids:
		var signature: Dictionary = record.brush_signatures.get(str(brush_id), {})
		if signature.is_empty():
			continue
		var brush = _owned_brush(str(brush_id), generator_id)
		if brush == null:
			continue
		var was := _signature_transform(record, signature)
		# The shape is asked about in the basis the piece was recorded in, not the
		# one it is standing in now. Hashing the same Basis value on both sides is
		# exact, where un-turning the current one would compare rounded floats
		# against the rounding of a different arithmetic path.
		if _geometry_hash_in_basis(brush, was.basis) != str(signature.get("geometry", "")):
			out.append(str(brush_id))
			continue
		# A piece that has moved on its own has been edited even though its shape
		# is untouched, because a rebuild will put it back in the row.
		if not _same_move(brush.global_transform, moved * was):
			out.append(str(brush_id))
	return out


func edited_piece_count(generator_id: String) -> int:
	return edited_brush_ids(generator_id).size()


## Where a rebuild of this structure would put it.
##
## Which is not where it was created: a structure dragged or turned into place
## rebuilds where it now stands, and a preview of the rebuild has to stand in the
## same spot and at the same angle or it is showing the wrong answer.
func rebuild_placement(generator_id: String) -> Transform3D:
	if not generators.has(generator_id):
		return Transform3D.IDENTITY
	return relocation_transform(generator_id) * generators[generator_id].placement


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func capture() -> Array:
	var out: Array = []
	for generator_id in generators:
		out.append(generators[generator_id].to_dict())
	return out


## Restore records and put the meta back on the brushes that belong to them.
func restore(records: Array) -> void:
	generators.clear()
	for entry in records:
		if not (entry is Dictionary):
			continue
		var record := HFGenerator.from_dict(entry)
		if record.type == "":
			continue
		generators[record.generator_id] = record
		for brush_id in record.brush_ids:
			var brush = _brush(str(brush_id))
			if brush:
				brush.set_meta(GENERATOR_META, record.generator_id)


func clear() -> void:
	generators.clear()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _spawn(
	face_sets: Array, placement: Transform3D, generator_id: String, appearance: Array
) -> PackedStringArray:
	if root == null or root.get("brush_system") == null:
		return PackedStringArray()
	var created: PackedStringArray = root.brush_system.create_brushes_from_face_sets(
		face_sets, placement
	)
	for i in created.size():
		var brush = _brush(str(created[i]))
		if brush == null:
			continue
		brush.set_meta(GENERATOR_META, generator_id)
		if i < appearance.size():
			_apply_appearance(brush, appearance[i])
	return created


## What each piece looks like, in the order the pieces were built.
##
## The override material is the whole-brush one. The face entries are what the
## Paint tab writes, which is per face and is the work most worth not losing:
## painting a generated arch and then nudging its radius should not reset it.
func _capture_appearance(record: HFGenerator) -> Array:
	var out: Array = []
	for brush_id in record.brush_ids:
		var brush = _brush(str(brush_id))
		if brush == null:
			out.append({})
			continue
		var faces: Array = []
		for face in brush.faces:
			faces.append(_face_appearance(face))
		out.append({"override": brush.material_override, "faces": faces})
	return out


static func _face_appearance(face) -> Dictionary:
	if face == null:
		return {}
	return {
		"material_idx": face.material_idx,
		"uv_projection": face.uv_projection,
		"uv_scale": face.uv_scale,
		"uv_offset": face.uv_offset,
		"uv_rotation": face.uv_rotation,
		"custom_uvs": face.custom_uvs,
		"paint_layers": face.paint_layers,
	}


## Put back what a piece looked like.
##
## Faces are matched by index, which is a real correspondence only while the
## rebuilt piece has the same faces in the same order. A piece whose face count
## changed keeps the whole-brush material and takes default faces, and
## `appearance_at_risk()` is what says so before the rebuild happens.
static func _apply_appearance(brush, appearance) -> void:
	if not (appearance is Dictionary) or appearance.is_empty():
		return
	if appearance.get("override", null) != null:
		brush.material_override = appearance["override"]
	var stored: Array = appearance.get("faces", [])
	var faces: Array = brush.faces
	if stored.size() != faces.size():
		return
	for i in faces.size():
		_restore_face(faces[i], stored[i])
	brush.rebuild_preview()


static func _restore_face(face, stored) -> void:
	if face == null or not (stored is Dictionary) or stored.is_empty():
		return
	face.material_idx = int(stored.get("material_idx", -1))
	face.uv_projection = int(stored.get("uv_projection", face.uv_projection))
	face.uv_scale = stored.get("uv_scale", face.uv_scale)
	face.uv_offset = stored.get("uv_offset", face.uv_offset)
	face.uv_rotation = float(stored.get("uv_rotation", 0.0))
	var uvs: PackedVector2Array = stored.get("custom_uvs", PackedVector2Array())
	if uvs.size() == face.local_verts.size():
		face.custom_uvs = uvs
	var layers: Array = stored.get("paint_layers", [])
	if not layers.is_empty():
		face.paint_layers.assign(layers)


## The pieces whose authored appearance a rebuild with these settings could not
## put back: the ones a shorter piece list drops, and the ones whose faces would
## no longer line up one to one.
##
## Asked before an Update, because that is the last moment the user can choose
## Detach instead. A piece with nothing authored on it is never at risk; there is
## nothing there to lose.
func appearance_at_risk(generator_id: String, settings: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not generators.has(generator_id):
		return out
	var record: HFGenerator = generators[generator_id]
	var face_sets := build_faces(record.type, settings)
	for i in record.brush_ids.size():
		var brush = _owned_brush(str(record.brush_ids[i]), generator_id)
		if brush == null or not _has_authored_faces(brush):
			continue
		if i >= face_sets.size() or face_sets[i].size() != brush.faces.size():
			out.append(str(record.brush_ids[i]))
	return out


## True when any face of the piece carries appearance the Paint tab put there.
static func _has_authored_faces(brush) -> bool:
	for face in brush.faces:
		if face == null:
			continue
		if face.material_idx != -1 or not face.paint_layers.is_empty():
			return true
		if not face.custom_uvs.is_empty() or not is_zero_approx(face.uv_rotation):
			return true
		if not face.uv_scale.is_equal_approx(Vector2.ONE):
			return true
		if not face.uv_offset.is_equal_approx(Vector2.ZERO):
			return true
	return false


## Delete only the brushes that still say they belong to this generator.
##
## The record is a hint. Brush ids are reissued as the counter moves, and a stale
## entry could otherwise name a brush that now belongs to something else — so a
## rebuild would quietly delete a neighbour's geometry. The meta on the brush is
## the authority, not the list.
func _delete_brushes(brush_ids: PackedStringArray, generator_id: String) -> void:
	if root == null or root.get("brush_system") == null:
		return
	for brush_id in brush_ids:
		var brush = _brush(str(brush_id))
		if brush == null:
			continue
		if str(brush.get_meta(GENERATOR_META, "")) != generator_id:
			continue
		root.brush_system.delete_brush_by_id(str(brush_id))


func _brush(brush_id: String):
	if brush_id == "" or root == null or root.get("brush_system") == null:
		return null
	return root.brush_system.find_brush_by_id(brush_id)


## A brush, but only if it still says it belongs to this generator.
##
## The record is a hint. Ids are reissued as the counter moves, so asking about a
## brush by id alone can answer about somebody else's geometry.
func _owned_brush(brush_id: String, generator_id: String):
	var brush = _brush(brush_id)
	if brush == null or str(brush.get_meta(GENERATOR_META, "")) != generator_id:
		return null
	return brush


## Remember what each piece was, so a later question about what has changed has
## something to compare against.
func _record_signatures(record: HFGenerator) -> void:
	record.brush_signatures.clear()
	for brush_id in record.brush_ids:
		var brush = _brush(str(brush_id))
		if brush == null:
			continue
		record.brush_signatures[str(brush_id)] = {
			"origin": brush.global_transform.origin,
			"basis": brush.global_transform.basis,
			"geometry": _geometry_hash(brush),
		}


## What a piece *is*, independent of where it is: its rotation, its shape, its
## size and its face vertices, rounded to a thousandth so that the float
## formatting a save and reload goes through does not read as an edit.
func _geometry_hash(brush) -> String:
	if brush == null:
		return ""
	return _geometry_hash_in_basis(brush, brush.global_transform.basis)


## The same question asked about a basis the piece is not necessarily standing
## in. A structure turned as a whole has every piece in a new basis and none of
## them changed, so the comparison has to be made in the basis each piece was
## recorded in rather than the one it is standing in now.
static func _geometry_hash_in_basis(brush, basis: Basis) -> String:
	if brush == null:
		return ""
	var parts := PackedStringArray()
	parts.append("s%d" % int(brush.shape))
	parts.append(_rounded(brush.size))
	parts.append(_rounded(basis.x))
	parts.append(_rounded(basis.y))
	parts.append(_rounded(basis.z))
	for face in brush.faces:
		if face == null:
			continue
		for vertex in face.local_verts:
			parts.append(_rounded(vertex))
		parts.append("/")
	return str(", ".join(parts).hash())


static func _rounded(v: Vector3) -> String:
	return "%.3f %.3f %.3f" % [v.x, v.y, v.z]
