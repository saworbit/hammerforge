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
const HFGenerator = preload("../hf_generator.gd")
const HFOpResult = preload("../hf_op_result.gd")

const GENERATOR_META := &"hf_generator_id"

## Generator types this system can build. Adding one means adding a branch in
## `build_faces()` and `validate()` and nothing else.
const TYPE_ARCH := "arch"

var root: Node3D
var generators: Dictionary = {}  # generator_id -> HFGenerator


func _init(level_root: Node3D = null) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# The builders this system knows
# ---------------------------------------------------------------------------


static func known_types() -> PackedStringArray:
	return PackedStringArray([TYPE_ARCH])


static func default_settings(type: String) -> Dictionary:
	match type:
		TYPE_ARCH:
			return HFArchBuilder.default_settings()
		_:
			return {}


static func validate(type: String, settings: Dictionary) -> HFOpResult:
	match type:
		TYPE_ARCH:
			return HFArchBuilder.validate(settings)
		_:
			return HFOpResult.fail(
				"Generator: '%s' is not a generator type" % type,
				"Known types: %s" % ", ".join(known_types())
			)


## One face set per piece the structure is made of, in the structure's own space.
static func build_faces(type: String, settings: Dictionary) -> Array:
	match type:
		TYPE_ARCH:
			return HFArchBuilder.build(settings)
		_:
			return []


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
	_delete_brushes(record.brush_ids, generator_id)

	record.settings = settings.duplicate(true)
	record.brush_ids = _spawn(face_sets, record.placement, generator_id, materials)
	if record.brush_ids.is_empty():
		generators.erase(generator_id)
		return HFOpResult.fail("Generator: those settings produce no geometry")
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
