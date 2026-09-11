@tool
extends RefCounted
class_name HFGeneratorSchema

## What a generator's settings are, described well enough to build the controls.
##
## Every generator has its own settings, and before this the dock knew all of them
## by name: a member per control, a row per control, a line in the loader per
## control and a line in the reader per control. Four of those for one generator,
## and four more for the next. The cost of adding a generator was never the
## arithmetic — it was the dock.
##
## So a builder describes its own settings instead, and one section serves every
## type. A field is:
##
##     {"key", "label", "type", "min", "max", "step", "default", "tooltip"}
##
## with `type` one of `float`, `int`, `bool` or `enum`, and `enum` carrying an
## `options` array of labels.
##
## The schema says what a field may be, for everyone. The dock builds a SpinBox
## from its range; `check_ranges()` holds a caller that never saw the dock to the
## same range, which is what a regenerate from a `.hflevel`, an undo replay and a
## script all are. `validate()` on the builder stays the authority on the
## refusals that are relationships between fields — a wall thicker than its own
## radius, an arc too coarse to stay convex — because no per-field range says
## that.

const TYPE_FLOAT := "float"
const TYPE_INT := "int"
const TYPE_BOOL := "bool"
const TYPE_ENUM := "enum"


## Every setting at its default, which is what a generator builds with when the
## caller says nothing.
static func defaults(schema: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in schema:
		if not (entry is Dictionary) or not (entry as Dictionary).has("key"):
			continue
		var field: Dictionary = entry
		out[str(field["key"])] = _coerce(field, field.get("default", 0.0))
	return out


## Settings filled in from the defaults and coerced to the types the schema says.
##
## Unknown keys are dropped rather than carried, so a record written by an older
## version — or by hand — cannot smuggle a value into arithmetic that never
## expected it.
static func merge(schema: Array, settings: Dictionary) -> Dictionary:
	var out := defaults(schema)
	for entry in schema:
		if not (entry is Dictionary) or not (entry as Dictionary).has("key"):
			continue
		var field: Dictionary = entry
		var key := str(field["key"])
		if settings.has(key):
			out[key] = _coerce(field, settings[key])
	return out


static func keys(schema: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in schema:
		if entry is Dictionary and (entry as Dictionary).has("key"):
			out.append(str((entry as Dictionary)["key"]))
	return out


## What is wrong with these settings against the schema, or an empty array.
##
## Two rules, both of which every builder's own `validate()` misses by
## construction: a NaN fails `radius <= 0.0` the way it fails every comparison,
## and an upper bound was only ever the dock's SpinBox. A caller that did not
## come through the dock — a regenerate from a file, an undo replay, a script —
## reached the arithmetic with either.
##
## Returns `[message, hint]` for the first field that is out of range.
static func check_ranges(schema: Array, settings: Dictionary) -> Array:
	var merged := merge(schema, settings)
	for entry in schema:
		if not (entry is Dictionary) or not (entry as Dictionary).has("key"):
			continue
		var field_def: Dictionary = entry
		var type_name := str(field_def.get("type", TYPE_FLOAT))
		if type_name == TYPE_BOOL or type_name == TYPE_ENUM:
			continue
		var key := str(field_def["key"])
		var label := str(field_def.get("label", key))
		# Read finiteness off the value as it arrived. An int field coerces a NaN
		# to some integer on the way through `merge()`, so by then it is gone.
		var raw = settings.get(key, 0.0)
		if (raw is float or raw is int) and not is_finite(float(raw)):
			return ["'%s' is not a number" % label, "Set %s to a number" % label]
		var value := float(merged.get(key, 0.0))
		if field_def.has("max") and value > float(field_def["max"]):
			var ceiling := _number_text(float(field_def["max"]))
			return [
				"'%s' cannot be more than %s" % [label, ceiling],
				"Use %s or less" % ceiling,
			]
	return []


## A number written the way a settings field reads it: whole where it is whole.
static func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return "%.3f" % value


static func field(schema: Array, key: String) -> Dictionary:
	for entry in schema:
		if entry is Dictionary and str((entry as Dictionary).get("key", "")) == key:
			return entry
	return {}


## A value in the type the field says, or the field's default if it cannot be.
##
## Total by construction. `int({})` is not a valid constructor call: it errors and
## evaluates to null, and a null written into the settings dictionary reaches the
## builder's `validate()`, which then never returns, which makes `create()`
## dereference null and hand a caller declared `-> HFOpResult` nothing at all.
## Refusing a value here is what keeps that cascade from starting.
static func _coerce(field: Dictionary, value):
	var type_name := str(field.get("type", TYPE_FLOAT))
	if not _is_number_like(value):
		var fallback = field.get("default", 0.0)
		HFLog.warn(
			(
				"Generator setting '%s' cannot be a %s, so the default is used instead."
				% [str(field.get("key", "?")), type_string(typeof(value))]
			)
		)
		value = fallback if _is_number_like(fallback) else 0.0
	match type_name:
		TYPE_INT, TYPE_ENUM:
			return int(value)
		TYPE_BOOL:
			return bool(value)
		_:
			return float(value)


## Whether int(), bool() and float() will take this value rather than error.
##
## Written with `is` rather than `typeof` because this class defines its own
## TYPE_INT and TYPE_BOOL as strings, which shadow the engine constants of the
## same name. A string counts only when it reads as a number, so a stray label
## does not quietly become zero.
static func _is_number_like(value) -> bool:
	if value is String or value is StringName:
		return str(value).is_valid_float()
	return value is int or value is float or value is bool
