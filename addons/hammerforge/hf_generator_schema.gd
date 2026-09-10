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
## The schema is a description, not a validator. Its ranges keep a SpinBox
## sensible; `validate()` on the builder stays the authority on whether settings
## can be built, because the refusals that matter are relationships between fields
## — a wall thicker than its own radius, an arc too coarse to stay convex — and no
## per-field range says that.

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
