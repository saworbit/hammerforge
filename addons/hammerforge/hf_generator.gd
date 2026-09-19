@tool
extends RefCounted
class_name HFGenerator

## A record of what a generator made, so it can be made again differently.
##
## An arch is eight to sixty-four brushes produced from six numbers, and radius
## and segment count are exactly the values a designer tunes by looking at the
## result. Without a record the numbers are gone the moment the brushes exist, and
## a slightly wider arch means deleting everything and starting over.
##
## Shaped like `HFDuplicator`, which already remembers its sources, its count and
## the brushes it created, and serializes all three.

var generator_id := ""
## Which builder made this, and therefore which one can make it again.
var type := ""
var settings: Dictionary = {}
## Where the structure was placed. Its geometry is built about its own origin.
var placement: Transform3D = Transform3D.IDENTITY
var brush_ids: PackedStringArray = PackedStringArray()
## What each piece was when it was made: where it was put, how it was turned, and
## a hash of what it is. Two different questions get answered from this — has the
## structure been moved, and have its pieces been edited — and they need different
## answers. A record written before turning was understood has no basis for its
## pieces; the reader answers that with the placement's own basis, which is what
## every piece the generator built was given.
var brush_signatures: Dictionary = {}


func _init() -> void:
	generator_id = "gen_%d" % Time.get_ticks_usec()


func to_dict() -> Dictionary:
	var basis := placement.basis
	return {
		"generator_id": generator_id,
		"type": type,
		"settings": settings.duplicate(true),
		"brush_ids": Array(brush_ids),
		"placement_origin": [placement.origin.x, placement.origin.y, placement.origin.z],
		"placement_basis":
		[
			[basis.x.x, basis.x.y, basis.x.z],
			[basis.y.x, basis.y.y, basis.y.z],
			[basis.z.x, basis.z.y, basis.z.z],
		],
		"brush_signatures": _signatures_to_dict(),
	}


func _signatures_to_dict() -> Dictionary:
	var out: Dictionary = {}
	for brush_id in brush_signatures:
		var signature: Dictionary = brush_signatures[brush_id]
		var origin: Vector3 = signature.get("origin", Vector3.ZERO)
		var entry := {
			"origin": [origin.x, origin.y, origin.z],
			"geometry": str(signature.get("geometry", "")),
		}
		# Written only when it is known. A record that never had one must not come
		# back claiming its pieces were built square, because the reader has a
		# better answer for a missing basis than any value written here could be.
		if signature.has("basis"):
			entry["basis"] = _basis_to_rows(signature["basis"])
		out[str(brush_id)] = entry
	return out


static func _basis_to_rows(basis: Basis) -> Array:
	return [
		[basis.x.x, basis.x.y, basis.x.z],
		[basis.y.x, basis.y.y, basis.y.z],
		[basis.z.x, basis.z.y, basis.z.z],
	]


## A basis from serialized rows, or `null` when the rows are missing or unusable.
static func _basis_from_rows(rows_value) -> Variant:
	if not (rows_value is Array) or (rows_value as Array).size() < 3:
		return null
	var columns: Array = []
	for row in rows_value:
		if not (row is Array) or (row as Array).size() < 3:
			return null
		columns.append(Vector3(float(row[0]), float(row[1]), float(row[2])))
	return Basis(columns[0], columns[1], columns[2])


## Rebuild a record from a serialized dictionary. Anything missing takes its
## default, so a level saved before a field existed still opens.
static func from_dict(data: Dictionary) -> HFGenerator:
	var record := HFGenerator.new()
	record.generator_id = str(data.get("generator_id", record.generator_id))
	record.type = str(data.get("type", ""))
	var stored_settings = data.get("settings", {})
	record.settings = (
		(stored_settings as Dictionary).duplicate(true) if stored_settings is Dictionary else {}
	)
	var ids := PackedStringArray()
	for brush_id in data.get("brush_ids", []):
		ids.append(str(brush_id))
	record.brush_ids = ids

	var origin := Vector3.ZERO
	var origin_arr = data.get("placement_origin", [])
	if origin_arr is Array and origin_arr.size() >= 3:
		origin = Vector3(float(origin_arr[0]), float(origin_arr[1]), float(origin_arr[2]))
	var basis := Basis.IDENTITY
	var stored_basis = _basis_from_rows(data.get("placement_basis", []))
	if stored_basis != null:
		basis = stored_basis
	record.placement = Transform3D(basis, origin)

	var stored_signatures = data.get("brush_signatures", {})
	if stored_signatures is Dictionary:
		for brush_id in stored_signatures:
			var entry = stored_signatures[brush_id]
			if not (entry is Dictionary):
				continue
			var point := Vector3.ZERO
			var point_arr = (entry as Dictionary).get("origin", [])
			if point_arr is Array and (point_arr as Array).size() >= 3:
				point = Vector3(float(point_arr[0]), float(point_arr[1]), float(point_arr[2]))
			var signature := {
				"origin": point,
				"geometry": str((entry as Dictionary).get("geometry", "")),
			}
			var piece_basis = _basis_from_rows((entry as Dictionary).get("basis", []))
			if piece_basis != null:
				signature["basis"] = piece_basis
			record.brush_signatures[str(brush_id)] = signature
	return record
