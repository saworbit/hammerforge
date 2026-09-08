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
	return builder.validate(settings)


## One face set per piece the structure is made of, in the structure's own space.
static func build_faces(type: String, settings: Dictionary) -> Array:
	var builder = builder_for(type)
	return builder.build(settings) if builder else []


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

	# Materials are what a designer adds after generating, so losing them on every
	# radius nudge would make this not worth using. Captured in order and put back
	# by index; when the piece count changes there is no correspondence past the
	# shorter list, and the extra pieces take the default.
	var materials := _capture_materials(record)
	# Where the structure is now, not where it was made. Read before anything is
	# deleted, because it is the existing pieces that say where they have gone.
	record.placement.origin += relocation_delta(generator_id)
	_delete_brushes(record.brush_ids, generator_id)

	record.settings = settings.duplicate(true)
	record.brush_ids = _spawn(face_sets, record.placement, generator_id, materials)
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
func relocation_delta(generator_id: String) -> Vector3:
	if not generators.has(generator_id):
		return Vector3.ZERO
	var record: HFGenerator = generators[generator_id]
	var delta := Vector3.ZERO
	var seen := false
	for brush_id in record.brush_ids:
		var signature: Dictionary = record.brush_signatures.get(str(brush_id), {})
		if signature.is_empty():
			continue
		var brush = _owned_brush(str(brush_id), generator_id)
		if brush == null:
			continue
		var moved: Vector3 = brush.global_transform.origin - signature.get("origin", Vector3.ZERO)
		if not seen:
			delta = moved
			seen = true
		elif moved.distance_to(delta) > RELOCATION_EPSILON:
			return Vector3.ZERO
	return delta if seen else Vector3.ZERO


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
	var moved := relocation_delta(generator_id)
	for brush_id in record.brush_ids:
		var signature: Dictionary = record.brush_signatures.get(str(brush_id), {})
		if signature.is_empty():
			continue
		var brush = _owned_brush(str(brush_id), generator_id)
		if brush == null:
			continue
		if _geometry_hash(brush) != str(signature.get("geometry", "")):
			out.append(str(brush_id))
			continue
		# A piece that has moved on its own has been edited even though its shape
		# is untouched, because a rebuild will put it back in the row.
		var expected: Vector3 = signature.get("origin", Vector3.ZERO) + moved
		if brush.global_transform.origin.distance_to(expected) > RELOCATION_EPSILON:
			out.append(str(brush_id))
	return out


func edited_piece_count(generator_id: String) -> int:
	return edited_brush_ids(generator_id).size()


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
	face_sets: Array, placement: Transform3D, generator_id: String, materials: Array
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
		if i < materials.size() and materials[i] != null:
			brush.material_override = materials[i]
	return created


func _capture_materials(record: HFGenerator) -> Array:
	var out: Array = []
	for brush_id in record.brush_ids:
		var brush = _brush(str(brush_id))
		out.append(brush.material_override if brush else null)
	return out


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
			"geometry": _geometry_hash(brush),
		}


## What a piece *is*, independent of where it is: its rotation, its shape, its
## size and its face vertices, rounded to a thousandth so that the float
## formatting a save and reload goes through does not read as an edit.
func _geometry_hash(brush) -> String:
	if brush == null:
		return ""
	var parts := PackedStringArray()
	parts.append("s%d" % int(brush.shape))
	parts.append(_rounded(brush.size))
	var basis: Basis = brush.global_transform.basis
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
