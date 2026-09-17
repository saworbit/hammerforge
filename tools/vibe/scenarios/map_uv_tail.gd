@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The UV tail on an exported `.map` face, against the numbers the face holds.
##
## Both adapters end a face line with offset, rotation and scale. Those fields
## have a fixed meaning in the Quake family -- the rotation is in degrees, the
## scale is texels per world unit, and a scale of zero is not a texture -- and
## `FaceData` holds its own numbers in its own units. Nothing sits between them:
## `HFMapQuake` and `HFMapValve220` both read `fd.uv_rotation` and `fd.uv_scale`
## and print them.
##
## So the question is whether a face that looks one way in the viewport says the
## same thing to the compiler that reads the file.

const FaceDataType = preload("res://addons/hammerforge/face_data.gd")


func id() -> String:
	return "map-uv-tail"


func summary() -> String:
	return "whether the UV tail of an exported .map face means what the face means"


func run() -> void:
	await _rotation_units()
	await _scale_direction()
	await _degenerate_scale()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Every face line in an exported file, as the raw text.
func _face_lines(root: Node3D, format: String, tag: String) -> Array:
	var path := "user://vibe_map_uv_%s.map" % tag
	root.export_map(path, format)
	var text := FileAccess.get_file_as_string(path)
	var out: Array = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("( ") and trimmed.count("(") >= 3:
			out.append(trimmed)
	return out


## The numeric tail of a Quake face line, with the texture token dropped:
## `( a ) ( b ) ( c ) TEX xoff yoff rot xscale yscale` -> the last five.
func _quake_tail(line: String) -> PackedStringArray:
	var after := line.substr(line.rfind(")") + 1).strip_edges()
	var fields := after.split(" ", false)
	return fields.slice(1) if fields.size() > 1 else fields


## The tail of a Valve 220 line, which puts the axes in brackets:
## `... TEX [ ux uy uz uoff ] [ vx vy vz voff ] rot uscale vscale`
func _valve_tail(line: String) -> PackedStringArray:
	var after := line.substr(line.rfind("]") + 1).strip_edges()
	return after.split(" ", false)


## A `.map` rotation field is degrees. `FaceData.uv_rotation` is radians -- the
## dock writes `deg_to_rad(spin.value)` into it. Whether anything converts.
func _rotation_units() -> void:
	var root: Node3D = await fresh_root("MapUVRotation")
	var b = box(root, Vector3(64, 64, 64))
	var degrees := 45.0
	for face in b.faces:
		face.uv_rotation = deg_to_rad(degrees)
	b.rebuild_preview()
	await frame()
	note("face uv_rotation set", "%.1f deg, stored as %.5f rad" % [degrees, b.faces[0].uv_rotation])

	for format in ["quake", "valve220"]:
		var lines := _face_lines(root, format, "rot_" + format)
		if lines.is_empty():
			flag("%s export produced no face lines" % format)
			continue
		var tail: PackedStringArray = (
			_quake_tail(lines[0]) if format == "quake" else _valve_tail(lines[0])
		)
		if tail.size() < 3:
			flag("%s face tail has %d fields" % [format, tail.size()], lines[0])
			continue
		# Quake: xoff yoff rot xscale yscale. Valve: rot uscale vscale.
		var emitted := float(tail[2]) if format == "quake" else float(tail[0])
		note("%s full tail" % format, " ".join(tail))
		note("%s rotation field" % format, "%s (face holds %.1f deg)" % [str(emitted), degrees])
		if absf(emitted - degrees) > 0.5:
			if absf(emitted - deg_to_rad(degrees)) < 0.001:
				known(
					503,
					"%s writes the UV rotation in radians into a degrees field" % format,
					(
						"a face turned %.0f deg exports as %s, which the compiler reads as %s deg"
						% [degrees, str(emitted), str(emitted)]
					)
				)
			else:
				flag(
					"%s rotation field does not match the face" % format,
					"face %.1f deg, file %s" % [degrees, str(emitted)]
				)


## A `.map` scale is texels per unit: a bigger number is a bigger texture and
## fewer repeats. `_apply_uv_transform()` multiplies the projected UV by
## `uv_scale`, so a bigger number there is *more* repeats. If both are printed
## straight through, the two disagree by a reciprocal.
func _scale_direction() -> void:
	var root: Node3D = await fresh_root("MapUVScale")
	var b = box(root, Vector3(64, 64, 64))
	for face in b.faces:
		face.uv_projection = FaceDataType.UVProjection.BOX_UV
		face.uv_scale = Vector2(2.0, 2.0)
		face.custom_uvs = PackedVector2Array()
	b.rebuild_preview()
	await frame()

	# What the face itself does with a scale of 2: measure the UV span the
	# mesh gets, against the same face at scale 1.
	var span_two := _uv_span(b.faces[0])
	for face in b.faces:
		face.uv_scale = Vector2.ONE
		face.custom_uvs = PackedVector2Array()
	b.rebuild_preview()
	await frame()
	var span_one := _uv_span(b.faces[0])
	note("UV span at uv_scale 1", "%.3f" % span_one)
	note("UV span at uv_scale 2", "%.3f" % span_two)
	var repeats_more := span_two > span_one * 1.5

	for face in b.faces:
		face.uv_scale = Vector2(2.0, 2.0)
		face.custom_uvs = PackedVector2Array()
	b.rebuild_preview()
	await frame()
	for format in ["quake", "valve220"]:
		var lines := _face_lines(root, format, "scale_" + format)
		if lines.is_empty():
			continue
		var tail: PackedStringArray = (
			_quake_tail(lines[0]) if format == "quake" else _valve_tail(lines[0])
		)
		var u_scale := float(tail[3]) if format == "quake" else float(tail[1])
		note("%s full tail" % format, " ".join(tail))
		note("%s uscale field" % format, str(u_scale))
		# The field is not unitless any more (#713): it is the reciprocal times
		# however many `.map` units one of ours is, so a face at `uv_scale` 2
		# exported at 32 writes 16 and not 0.5. Comparing it against 1, which is
		# what this did, reported #504 as reproducing on a file that is correct,
		# and #504 is fixed. Against what the reciprocal should be instead.
		var inverted := MapIO.QUAKE_UNITS_PER_METRE / 2.0
		var not_inverted := MapIO.QUAKE_UNITS_PER_METRE * 2.0
		note("%s uscale if the reciprocal was taken" % format, inverted)
		note("%s uscale if it was not" % format, not_inverted)
		if repeats_more and absf(u_scale - inverted) > absf(u_scale - not_inverted):
			known(
				504,
				"%s exports the UV scale without inverting it" % format,
				(
					"uv_scale 2 tiles the texture twice as often in the viewport"
					+ (
						" (UV span %.1f against %.1f), and a .map scale of %s is nearer %s than"
						% [span_two, span_one, str(u_scale), str(not_inverted)]
					)
					+ (
						" %s, so the texture comes out twice as large and repeats half as often"
						% str(inverted)
					)
				)
			)


## The largest UV extent across a face, in UV units.
func _uv_span(face: Variant) -> float:
	var tri: Dictionary = face.triangulate()
	var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
	if uvs.is_empty():
		return 0.0
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = Vector2(minf(lo.x, uv.x), minf(lo.y, uv.y))
		hi = Vector2(maxf(hi.x, uv.x), maxf(hi.y, uv.y))
	return maxf(hi.x - lo.x, hi.y - lo.y)


## A scale of zero is a division by zero in every compiler that reads one, and a
## negative V scale is what `adjust_uvs_for_rotation()` writes when a turn puts
## the projection plane back the other way up. Whether either reaches the file.
func _degenerate_scale() -> void:
	var root: Node3D = await fresh_root("MapUVDegenerate")
	var b = box(root, Vector3(64, 64, 64))
	for face in b.faces:
		face.uv_scale = Vector2(0.0, 0.0)
	b.rebuild_preview()
	await frame()
	var lines := _face_lines(root, "valve220", "zero")
	if not lines.is_empty():
		var tail := _valve_tail(lines[0])
		note("valve220 tail at uv_scale 0", " ".join(tail))
		if tail.size() >= 3 and float(tail[1]) == 0.0:
			known(
				505,
				"a UV scale of zero is exported as a .map texture scale of 0",
				(
					"every Quake-family compiler divides by the scale;"
					+ " the face line is '%s'" % lines[0].substr(0, 160)
				)
			)

	# A rotation about the projection axis flips the V scale negative by design.
	var root2: Node3D = await fresh_root("MapUVFlip")
	var b2 = box(root2, Vector3(64, 64, 64))
	var face0 = b2.faces[0]
	face0.uv_projection = FaceDataType.UVProjection.PLANAR_Z
	var flipped: bool = face0.adjust_uvs_for_rotation(Basis(Vector3.RIGHT, PI))
	note("flip turn adjusted the UVs", flipped)
	note("uv_scale after a half turn about X", face0.uv_scale)
	if face0.uv_scale.y < 0.0:
		b2.rebuild_preview()
		await frame()
		var flip_lines := _face_lines(root2, "valve220", "flip")
		if not flip_lines.is_empty():
			for line in flip_lines:
				var tail := _valve_tail(line)
				if tail.size() >= 3 and float(tail[2]) < 0.0:
					note("valve220 vscale field", tail[2])
					break
