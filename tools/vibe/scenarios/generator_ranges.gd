@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Every generator setting at both ends of the range its own schema declares.
##
## `HFGeneratorSchema`'s own class comment states the contract:
##
## > The schema says what a field may be, for everyone. The dock builds a SpinBox
## > from its range; `check_ranges()` holds a caller that never saw the dock to
## > the same range, which is what a regenerate from a `.hflevel`, an undo replay
## > and a script all are.
##
## So for every numeric field of every builder, this pushes the value one step
## past each declared bound and records whether `validate()` refuses it, whether
## the builder's own `validate()` catches what the schema did not, and what
## `create()` puts in the level when nothing does.

const GeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const GeneratorSchema = preload("res://addons/hammerforge/hf_generator_schema.gd")


func id() -> String:
	return "generator-ranges"


func summary() -> String:
	return "every generator setting one step outside the range its own schema declares"


func run() -> void:
	await _both_bounds_of_every_field()
	await _enum_fields()
	await _what_reaches_the_level()


## One step outside a bound, in the field's own units.
func _past(bound: float, direction: float, step: float) -> float:
	var reach: float = maxf(step, maxf(absf(bound) * 0.5, 1.0))
	return bound + direction * reach


func _both_bounds_of_every_field() -> void:
	var below_accepted: Array = []
	var above_accepted: Array = []
	var checked := 0
	for type in GeneratorSystem.known_types():
		var schema: Array = GeneratorSystem.settings_schema(type)
		var defaults: Dictionary = GeneratorSystem.default_settings(type)
		note("--- %s" % type, "%d fields" % schema.size())
		for entry in schema:
			if not (entry is Dictionary) or not entry.has("key"):
				continue
			var kind := str(entry.get("type", "float"))
			if kind != "float" and kind != "int":
				continue
			var key := str(entry["key"])
			var step := float(entry.get("step", 1.0))
			for bound_name in ["min", "max"]:
				if not entry.has(bound_name):
					continue
				checked += 1
				var bound := float(entry[bound_name])
				var direction := -1.0 if bound_name == "min" else 1.0
				var value: float = _past(bound, direction, step)
				if kind == "int":
					value = float(int(value))
				var settings: Dictionary = defaults.duplicate(true)
				settings[key] = value
				var result = GeneratorSystem.validate(type, settings)
				var schema_said: Array = GeneratorSchema.check_ranges(schema, settings)
				var who := "refused"
				if result.ok:
					who = "ACCEPTED"
				elif schema_said.is_empty():
					who = "refused by the builder"
				note(
					"%s.%s %s %s -> %s" % [type, key, bound_name, _fmt(bound), _fmt(value)], who
				)
				if result.ok:
					if bound_name == "min":
						below_accepted.append("%s.%s (min %s, sent %s)" % [type, key, _fmt(bound), _fmt(value)])
					else:
						above_accepted.append("%s.%s (max %s, sent %s)" % [type, key, _fmt(bound), _fmt(value)])
	note("fields checked at a bound", checked)
	note("accepted below min", below_accepted.size())
	note("accepted above max", above_accepted.size())

	if not below_accepted.is_empty() and above_accepted.is_empty():
		known(
			518,
			"check_ranges() enforces the schema's max and never its min",
			(
				"%d of %d bound checks passed a value below the field's declared minimum"
				% [below_accepted.size(), checked]
				+ " and none passed one above the maximum. HFGeneratorSchema.check_ranges()"
				+ " tests `field_def.has(\"max\")` and has no corresponding min branch, so the"
				+ " half of the range the dock's SpinBox enforces by its min_value is enforced"
				+ " nowhere else: %s" % str(below_accepted.slice(0, 8))
			)
		)
	elif not below_accepted.is_empty() or not above_accepted.is_empty():
		flag(
			"some generator settings are accepted outside their declared range",
			"below min: %s; above max: %s" % [str(below_accepted), str(above_accepted)]
		)


func _fmt(v: float) -> String:
	return "%d" % int(roundf(v)) if is_equal_approx(v, roundf(v)) else "%.2f" % v


## `check_ranges()` skips bool and enum outright. An enum index the options
## array does not have.
func _enum_fields() -> void:
	var accepted: Array = []
	for type in GeneratorSystem.known_types():
		var schema: Array = GeneratorSystem.settings_schema(type)
		var defaults: Dictionary = GeneratorSystem.default_settings(type)
		for entry in schema:
			if not (entry is Dictionary) or str(entry.get("type", "")) != "enum":
				continue
			var key := str(entry["key"])
			var options: Array = Array(entry.get("options", []))
			var settings: Dictionary = defaults.duplicate(true)
			settings[key] = options.size() + 5
			var result = GeneratorSystem.validate(type, settings)
			note(
				"%s.%s enum with %d options, sent %d" % [type, key, options.size(), options.size() + 5],
				"ACCEPTED" if result.ok else "refused"
			)
			if result.ok:
				accepted.append("%s.%s (%d options)" % [type, key, options.size()])
	if accepted.is_empty():
		note("no enum field accepted an index outside its options", "or there are none")
	else:
		known(
			519,
			"a generator enum setting accepts an index its options array does not have",
			(
				"check_ranges() returns early for TYPE_BOOL and TYPE_ENUM, so nothing between"
				+ " the dock's OptionButton and the builder holds an enum to its own options:"
				+ " %s" % str(accepted)
			)
		)


## What a value the schema would have refused actually builds.
func _what_reaches_the_level() -> void:
	var root: Node3D = await fresh_root("GeneratorRanges")
	for type in GeneratorSystem.known_types():
		var schema: Array = GeneratorSystem.settings_schema(type)
		var defaults: Dictionary = GeneratorSystem.default_settings(type)
		var target := ""
		var bound := 0.0
		for entry in schema:
			if entry is Dictionary and entry.has("min") and str(entry.get("type", "")) == "int":
				target = str(entry["key"])
				bound = float(entry["min"])
				break
		if target == "":
			continue
		var settings: Dictionary = defaults.duplicate(true)
		settings[target] = int(bound) - 3
		var before: int = root.brush_system.get_live_brush_count()
		var result = root.generator_system.create(type, settings, Transform3D.IDENTITY)
		await frame()
		var after: int = root.brush_system.get_live_brush_count()
		note(
			"%s with %s = %d (min %s)" % [type, target, int(bound) - 3, _fmt(bound)],
			"create %s, brushes %d -> %d" % ["ok" if result.ok else "refused", before, after]
		)
		if result.ok:
			var records: Array = root.generator_system.capture()
			note("  the record the level now carries", records.size())

	# The four fields nothing refused, built for real.
	for case in [
		["stairs", "tread_thickness", 0.0],
		["arch", "start_degrees", -540.0],
		["spiral_stairs", "start_degrees", -540.0],
		["dome", "start_degrees", -540.0],
	]:
		var settings: Dictionary = GeneratorSystem.default_settings(case[0]).duplicate(true)
		settings[case[1]] = case[2]
		var before: int = root.brush_system.get_live_brush_count()
		var made = root.generator_system.create(case[0], settings, Transform3D.IDENTITY)
		await frame()
		var after: int = root.brush_system.get_live_brush_count()
		var faces := 0
		var degenerate := 0
		for node in root._iter_managed_brush_nodes():
			if not is_instance_valid(node) or node.get("faces") == null:
				continue
			for face in node.faces:
				faces += 1
				if face.bounds.size.length() < 0.0001:
					degenerate += 1
		note(
			"%s with %s = %s" % [case[0], case[1], _fmt(case[2])],
			(
				"create %s, brushes %d -> %d, %d faces total, %d with no extent"
				% ["ok" if made.ok else "refused", before, after, faces, degenerate]
			)
		)
