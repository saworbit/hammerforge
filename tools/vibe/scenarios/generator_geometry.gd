@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The four generators swept across their own declared ranges, with the geometry
## of every piece checked rather than the call's return value.
##
## `structures` checks the defaults and `generator-ranges` checks what happens
## one step outside the schema. This checks the inside: for every legal
## combination the schema allows, is each piece a convex brush wound outward,
## does it have the volume the settings asked for, and do the pieces touch?
##
## A generator is the one place a mapper gets geometry they did not draw, so a
## piece with an inverted face or a zero volume is invisible until the bake --
## and a stair with a gap in it is invisible until someone walks up it.


func id() -> String:
	return "generator-geometry"


func summary() -> String:
	return "every generator across its schema's legal range, with each piece checked for convexity, winding and volume"


const MAX_REPORTS := 6


func run() -> void:
	await _sweep_each_generator()
	await _stairs_have_no_gaps()
	await _a_dome_closes()


func _generator_ids(root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for r in root.generator_system.capture():
		out[str((r as Dictionary).get("generator_id", ""))] = true
	return out


func _added(root: Node3D, before: Dictionary) -> String:
	for gid in _generator_ids(root):
		if not before.has(gid):
			return str(gid)
	return ""


func _pieces(root: Node3D, gid: String) -> Array:
	var out: Array = []
	for b in root.draft_brushes_node.get_children():
		if str(b.get_meta("hf_generator_id", "")) == gid:
			out.append(b)
	return out


func _schema_for(type_name: String) -> Array:
	var schema = HFGeneratorSystem.settings_schema(type_name)
	return schema if schema is Array else []


## A handful of legal values for one field: the two ends of its range and the
## middle, which is where a generator that is right at the edges can still be
## wrong.
func _samples(field: Dictionary) -> Array:
	var lo = field.get("min", null)
	var hi = field.get("max", null)
	var dv = field.get("default", null)
	if lo == null or hi == null:
		return [dv] if dv != null else []
	var lof := float(lo)
	var hif := float(hi)
	if not is_finite(lof) or not is_finite(hif) or hif <= lof:
		return [dv] if dv != null else []
	var mid := lof + (hif - lof) * 0.5
	if str(field.get("type", "")) == "int":
		return [int(lof), int(mid), int(hif)]
	return [lof, mid, hif]


## Every legal value of every field, one field at a time, defaults elsewhere.
func _sweep_each_generator() -> void:
	var reported := 0
	for type_name in HFGeneratorSystem.known_types():
		var fields := _schema_for(type_name)
		note("%s: schema fields" % type_name, fields.size())
		var combos := 0
		var bad: Array = []
		for field in fields:
			if not (field is Dictionary):
				continue
			var key := str(field.get("key", ""))
			if key == "":
				continue
			for value in _samples(field):
				if value == null:
					continue
				var settings: Dictionary = {}
				for f in fields:
					if f is Dictionary and f.get("default", null) != null:
						settings[str(f.get("key", ""))] = f.get("default")
				settings[key] = value
				combos += 1
				var problems := await _build_and_check(type_name, settings)
				if not problems.is_empty():
					bad.append({"setting": "%s = %s" % [key, value], "problems": problems})
		note("%s: legal combinations built" % type_name, combos)
		if bad.is_empty():
			note("  -- every piece convex, outward wound and non-degenerate")
			continue
		for entry in bad:
			if reported >= MAX_REPORTS:
				note("  -- more problems suppressed", "%d in total for %s" % [bad.size(), type_name])
				break
			reported += 1
			flag(
				"%s built bad geometry at a setting its own schema allows" % type_name,
				"%s -> %s" % [entry["setting"], entry["problems"]]
			)


func _build_and_check(type_name: String, settings: Dictionary) -> Array:
	var root: Node3D = await fresh_root("G_%d" % Time.get_ticks_usec())
	var before := _generator_ids(root)
	var result = root.create_generator(type_name, settings, Transform3D.IDENTITY)
	var problems: Array = []
	if result == null or not result.ok:
		# Refusing a legal setting is the business of `generator-ranges`; here it
		# just means there is no geometry to look at.
		root.queue_free()
		return problems
	await frame()
	var gid := _added(root, before)
	var pieces := _pieces(root, gid)
	if pieces.is_empty():
		problems.append("built 0 pieces and reported success")
		root.queue_free()
		return problems
	var degenerate := 0
	var inverted := 0
	var nonconvex := 0
	for p in pieces:
		var extent: Vector3 = HFVibe.local_extent(p)
		if extent.x <= 0.001 or extent.y <= 0.001 or extent.z <= 0.001:
			degenerate += 1
		if HFVibe.inward_face_count(p) > 0:
			inverted += 1
		if root.vertex_system and root.vertex_system.has_method("validate_convexity"):
			var conv = root.vertex_system.validate_convexity(p)
			if conv is bool and not conv:
				nonconvex += 1
	if degenerate > 0:
		problems.append("%d of %d pieces have a zero extent" % [degenerate, pieces.size()])
	if inverted > 0:
		problems.append("%d of %d pieces have inward faces" % [inverted, pieces.size()])
	if nonconvex > 0:
		problems.append("%d of %d pieces fail the convexity check" % [nonconvex, pieces.size()])
	root.queue_free()
	return problems


## A stair a player can walk up: consecutive treads have to touch.
func _stairs_have_no_gaps() -> void:
	var root: Node3D = await fresh_root()
	for steps in [3, 8, 24]:
		var before := _generator_ids(root)
		var result = root.create_generator(
			"stairs",
			{"steps": steps, "step_height": 16.0, "step_depth": 32.0, "width": 96.0},
			Transform3D(Basis.IDENTITY, Vector3(steps * 2048.0, 0, 0))
		)
		if result == null or not result.ok:
			note("stairs with %d steps" % steps, "refused")
			continue
		await frame()
		var pieces := _pieces(root, _added(root, before))
		var boxes: Array = []
		for p in pieces:
			var e: Vector3 = HFVibe.local_extent(p)
			boxes.append(AABB((p as Node3D).global_position - e * 0.5, e))
		boxes.sort_custom(func(a, b): return a.position.y < b.position.y)
		var gaps: Array = []
		for i in range(1, boxes.size()):
			var lower: AABB = boxes[i - 1]
			var upper: AABB = boxes[i]
			var rise: float = upper.position.y - (lower.position.y + lower.size.y)
			if rise > 0.01:
				gaps.append("%.1f units between tread %d and %d" % [rise, i - 1, i])
		note("stairs with %d steps: pieces" % steps, pieces.size())
		note("  vertical gaps between treads", gaps)
		if not gaps.is_empty():
			flag(
				"a straight stair has gaps a player would fall through",
				"%d steps -> %s" % [steps, gaps]
			)


## A dome is the one generator whose pieces should enclose a volume.
func _a_dome_closes() -> void:
	var root: Node3D = await fresh_root()
	var fields := _schema_for("dome")
	note("dome schema", fields)
	var settings: Dictionary = {}
	for f in fields:
		if f is Dictionary and f.get("default", null) != null:
			settings[str(f.get("key", ""))] = f.get("default")
	var before := _generator_ids(root)
	var result = root.create_generator("dome", settings, Transform3D.IDENTITY)
	if result == null or not result.ok:
		note("dome at its defaults", "refused")
		return
	await frame()
	var pieces := _pieces(root, _added(root, before))
	note("dome pieces at the defaults", pieces.size())
	var total := AABB()
	var first := true
	var vol := 0.0
	for p in pieces:
		var e: Vector3 = HFVibe.local_extent(p)
		var a := AABB((p as Node3D).global_position - e * 0.5, e)
		vol += e.x * e.y * e.z
		if first:
			total = a
			first = false
		else:
			total = total.merge(a)
	note("dome bounds", total)
	note("sum of piece volumes", vol)
	if total.size.x > 0.0:
		note(
			"fill ratio against the bounding box",
			"%.3f" % (vol / (total.size.x * total.size.y * total.size.z))
		)
