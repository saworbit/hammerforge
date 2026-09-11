@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The four live generators -- arch, stairs, spiral stairs, dome -- driven
## through `LevelRoot`, which is how the Structure dock drives them.
##
## Three shapes of question. Does the geometry come out wound the right way?
## Does a setting outside the schema's own range get refused, or built? And is
## regenerating with the settings a structure already has a no-op, or does it
## move the structure?


func id() -> String:
	return "structures"


func summary() -> String:
	return "arch/stairs/spiral/dome winding, schema range enforcement, regenerate round trip"


func run() -> void:
	await _defaults_build_clean()
	await _regenerate_is_a_no_op()
	await _placement_is_honoured()
	await _out_of_range_settings()
	await _nonsense_settings()


func _types() -> PackedStringArray:
	return HFGeneratorSystem.known_types()


## Every structure id currently on the level.
##
## `create_generator` reports success but not which structure it made, so the
## only way back to the record it just wrote is to diff the system's capture
## across the call. Ids sort as strings, not as the microsecond counts they are
## built from, so "newest" cannot be read off an ordering.
func _generator_ids(root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for r in root.generator_system.capture():
		out[str((r as Dictionary).get("generator_id", ""))] = true
	return out


func _added_generator(root: Node3D, before: Dictionary) -> String:
	for gid in _generator_ids(root):
		if not before.has(gid):
			return str(gid)
	return ""


func _pieces(root: Node3D, generator_id: String) -> Array:
	var out: Array = []
	for b in root.draft_brushes_node.get_children():
		if str(b.get_meta("hf_generator_id", "")) == generator_id:
			out.append(b)
	return out


## Every type at its own defaults. A structure a mapper places from the dock
## without touching a setting is the most-travelled path there is.
func _defaults_build_clean() -> void:
	var root: Node3D = await fresh_root()
	for type in _types():
		var settings: Dictionary = HFGeneratorSystem.default_settings(type)
		var seen := _generator_ids(root)
		var result = root.create_generator(type, settings, Transform3D.IDENTITY)
		if result == null or not result.ok:
			flag("%s at its defaults will not build" % type, result.message if result else "null")
			continue
		var gid := _added_generator(root, seen)
		var pieces := _pieces(root, gid)
		var inward := 0
		var degenerate := 0
		for p in pieces:
			inward += HFVibe.inward_face_count(p)
			if HFVibe.local_extent(p).length() < 0.001:
				degenerate += 1
		note("%s defaults" % type, "%d pieces, %d inward faces" % [pieces.size(), inward])
		if inward > 0:
			flag(
				"%s builds %d inward-facing faces at its defaults" % [type, inward],
				"across %d pieces -- these bake inside out" % pieces.size()
			)
		if degenerate > 0:
			flag("%s builds %d zero-extent pieces at its defaults" % [type, degenerate])
		for problem in HFVibe.check_invariants(root):
			flag("%s at defaults broke an invariant" % type, problem)


## Regenerating with the settings a structure already has should change nothing.
## It is what the dock does every time a spinner is touched and put back.
func _regenerate_is_a_no_op() -> void:
	for type in _types():
		var root: Node3D = await fresh_root()
		var settings: Dictionary = HFGeneratorSystem.default_settings(type)
		var placement := Transform3D(Basis.IDENTITY, Vector3(128, 64, -32))
		var seen := _generator_ids(root)
		var result = root.create_generator(type, settings, placement)
		if result == null or not result.ok:
			continue
		var gid := _added_generator(root, seen)
		var before := HFVibe.describe_brushes(root)
		var again = root.regenerate_generator(gid, settings.duplicate())
		await frame()
		if again == null or not again.ok:
			flag(
				"%s will not regenerate with the settings it was built from" % type,
				again.message if again else "null"
			)
			continue
		var after := HFVibe.describe_brushes(root)
		diff_levels({"b": before}, {"b": after}, "%s regenerated with identical settings" % type)


## A structure placed away from the origin belongs where it was placed.
func _placement_is_honoured() -> void:
	for type in _types():
		var root: Node3D = await fresh_root()
		var origin := Vector3(512, 128, -256)
		var placement := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(45), 0)), origin)
		var seen := _generator_ids(root)
		var result = root.create_generator(
			type, HFGeneratorSystem.default_settings(type), placement
		)
		if result == null or not result.ok:
			continue
		var gid := _added_generator(root, seen)
		var pieces := _pieces(root, gid)
		if pieces.is_empty():
			continue
		var bounds := AABB(pieces[0].global_position, Vector3.ZERO)
		for p in pieces:
			bounds = bounds.expand(p.global_position)
		var nearest := INF
		for p in pieces:
			nearest = minf(nearest, p.global_position.distance_to(origin))
		note(
			"%s placed at %s" % [type, origin],
			(
				"centre %s, nearest piece %.1f away"
				% [bounds.get_center().snapped(Vector3.ONE), nearest]
			)
		)
		# The placement is a point on the structure, not necessarily its centre,
		# so the test is that *something* is near it -- not that everything is.
		var span: float = maxf(bounds.size.length(), 1.0)
		if nearest > span:
			flag(
				"%s lands nowhere near its placement" % type,
				(
					"nearest of %d pieces is %.1f from %s, and the structure spans %.1f"
					% [pieces.size(), nearest, origin, span]
				)
			)
		var rebuilt: Transform3D = root.generator_rebuild_placement(gid)
		if not rebuilt.origin.is_equal_approx(origin):
			flag(
				"%s does not remember where it was placed" % type,
				"placed at %s, rebuild placement reports %s" % [origin, rebuilt.origin]
			)


## The schema carries a min and a max per field. Feeding a value outside that
## range is what a hand-edited `.hflevel`, an undo replay and a script all do.
func _out_of_range_settings() -> void:
	for type in _types():
		var root: Node3D = await fresh_root()
		var schema: Array = HFGeneratorSystem.settings_schema(type)
		for entry in schema:
			if not (entry is Dictionary):
				continue
			var field: Dictionary = entry
			var key := str(field.get("key", ""))
			var ftype := str(field.get("type", ""))
			if key == "" or ftype == HFGeneratorSchema.TYPE_BOOL:
				continue
			if not field.has("max"):
				continue
			var over: float = float(field["max"]) * 1000.0 + 1000.0
			var settings: Dictionary = HFGeneratorSystem.default_settings(type)
			settings[key] = over
			var check = root.can_build_generator(type, settings)
			var seen := _generator_ids(root)
			var built = root.create_generator(type, settings, Transform3D.IDENTITY)
			var ok: bool = built != null and built.ok
			if not ok:
				continue
			var gid := _added_generator(root, seen)
			var pieces := _pieces(root, gid)
			var inward := 0
			var biggest := 0.0
			for p in pieces:
				inward += HFVibe.inward_face_count(p)
				biggest = maxf(biggest, HFVibe.local_extent(p).length())
			note(
				"%s %s = %s (schema max %s)" % [type, key, over, field["max"]],
				(
					"can_build %s, %d pieces, %d inward, largest piece %.0f units"
					% [check.ok if check else "null", pieces.size(), inward, biggest]
				)
			)
			if inward > 0:
				flag(
					(
						"%s with %s far above its schema max builds %d inward faces"
						% [type, key, inward]
					)
				)
			if pieces.size() > 1000:
				known(
					337,
					"%s builds %d pieces from %s = %s" % [type, pieces.size(), key, over],
					"the schema caps that field at %s and nothing else does" % field["max"]
				)
			if biggest > 1000000.0:
				known(
					338,
					(
						"%s accepts %s = %s and builds a piece %.0f units across"
						% [type, key, over, biggest]
					),
					"the schema caps that field at %s" % field["max"]
				)
			for problem in HFVibe.check_invariants(root):
				known(338, "%s with %s out of range broke an invariant" % [type, key], problem)


## Non-finite numbers, which is what a corrupt record hands the builder.
func _nonsense_settings() -> void:
	var root: Node3D = await fresh_root()
	for type in _types():
		var schema: Array = HFGeneratorSystem.settings_schema(type)
		for entry in schema:
			if not (entry is Dictionary):
				continue
			var key := str((entry as Dictionary).get("key", ""))
			if key == "":
				continue
			for bad in [NAN, INF, -INF]:
				var settings: Dictionary = HFGeneratorSystem.default_settings(type)
				settings[key] = bad
				var seen := _generator_ids(root)
				var built = root.create_generator(type, settings, Transform3D.IDENTITY)
				if built == null:
					flag("%s with %s = %s returned null, not a result" % [type, key, bad])
					continue
				if not built.ok:
					continue
				var gid := _added_generator(root, seen)
				var pieces := _pieces(root, gid)
				var bad_geometry := 0
				for p in pieces:
					if not p.global_position.is_finite() or not HFVibe.local_extent(p).is_finite():
						bad_geometry += 1
				if bad_geometry > 0:
					known(
						336,
						"%s accepts %s = %s and builds non-finite geometry" % [type, key, bad],
						(
							"%d of %d pieces have a non-finite position or extent"
							% [bad_geometry, pieces.size()]
						)
					)
				else:
					note("%s %s = %s" % [type, key, bad], "built %d finite pieces" % pieces.size())
				for problem in HFVibe.check_invariants(root):
					known(336, "%s with %s = %s broke an invariant" % [type, key, bad], problem)
