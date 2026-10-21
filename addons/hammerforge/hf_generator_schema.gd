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
## from its range; `read_field()` holds a caller that never saw the dock to the
## same range, and it is the one rule for a structure's settings and a command's
## params over the bridge and for `check_ranges()`, which is what a regenerate
## from a `.hflevel`, an undo replay and a script go through. `validate()` on
## the builder stays the authority on the refusals that are relationships
## between fields — a wall thicker than its own radius, an arc too coarse to
## stay convex — because no per-field range says that.

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
		var spec: Dictionary = entry
		out[str(spec["key"])] = _coerce(spec, spec.get("default", 0.0))
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
		var spec: Dictionary = entry
		var key := str(spec["key"])
		if settings.has(key):
			out[key] = _coerce(spec, settings[key])
	return out


static func keys(schema: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in schema:
		if entry is Dictionary and (entry as Dictionary).has("key"):
			out.append(str((entry as Dictionary)["key"]))
	return out


## What is wrong with these settings against the schema, or an empty string.
##
## Two rules, both of which every builder's own `validate()` misses by
## construction: a NaN fails `radius <= 0.0` the way it fails every comparison,
## and an upper bound was only ever the dock's SpinBox. A caller that did not
## come through the dock — a regenerate from a file, an undo replay, a script —
## reached the arithmetic with either. Each field goes through `read_field()`,
## its default standing in for one not given, and the first refusal is the
## answer, naming the field by its label.
static func check_ranges(schema: Array, settings: Dictionary) -> String:
	var filled := defaults(schema)
	for entry in schema:
		if not (entry is Dictionary) or not (entry as Dictionary).has("key"):
			continue
		var field_def: Dictionary = entry
		var key := str(field_def["key"])
		var read := read_field(field_def, settings.get(key, filled[key]))
		if not read["ok"]:
			return str(read["message"])
	return ""


## One value for one field: `{ok, value}` with the value in the field's type, or
## `{ok, message}` saying what is wrong with it.
##
## The rule every surface applies, so a value one of them takes they all take,
## coerced the same way: a structure's settings and a command's params over the
## bridge, and every generator create through `check_ranges()`. A number is a
## number rather than a string or a bool, finite, whole for an int field and
## inside the field's min and max. A bool is a bool. An enum is one of its
## options, by index or by its label in any case, and comes back as the index
## the builder indexes its options with. `name` is what the message calls the
## field: the key for an agent, or the quoted label a mapper reads, which is
## the default.
static func read_field(field_def: Dictionary, value, name := "") -> Dictionary:
	var type_name := str(field_def.get("type", TYPE_FLOAT))
	if name == "":
		name = "'%s'" % str(field_def.get("label", field_def.get("key", "")))
	if type_name == TYPE_BOOL:
		if not (value is bool):
			return _refused("%s must be true or false" % name)
		return {"ok": true, "value": value}
	if type_name == TYPE_ENUM:
		var options: Array = Array(field_def.get("options", []))
		var index := option_index(options, value)
		if index < 0:
			var choices := ", ".join(PackedStringArray(options))
			return _refused("%s is one of %s, or its index from 0" % [name, choices])
		return {"ok": true, "value": index}
	# A bool is its own type here, so true is not 1 the way it is to float().
	if not (value is float or value is int):
		return _refused("%s must be a number" % name)
	var number := float(value)
	if not is_finite(number):
		return _refused("%s must be finite" % name)
	if type_name == TYPE_INT and number != floorf(number):
		return _refused("%s must be a whole number" % name)
	var too_low := field_def.has("min") and number < float(field_def["min"])
	var too_high := field_def.has("max") and number > float(field_def["max"])
	if too_low or too_high:
		return _refused("%s %s" % [name, _range_text(field_def)])
	if type_name == TYPE_INT:
		return {"ok": true, "value": int(number)}
	return {"ok": true, "value": number}


## Which of `options` a value picks: its index as a whole number, or its label
## in any case. -1 when it is neither.
static func option_index(options: Array, value) -> int:
	if value is float or value is int:
		var number := float(value)
		if number == floorf(number) and number >= 0 and number < options.size():
			return int(number)
		return -1
	if value is String or value is StringName:
		for i in options.size():
			if str(options[i]).to_lower() == str(value).to_lower():
				return i
	return -1


static func _refused(message: String) -> Dictionary:
	return {"ok": false, "message": message}


## The range the way a refusal says it: both ends when the field has both.
static func _range_text(field_def: Dictionary) -> String:
	if field_def.has("min") and field_def.has("max"):
		var ends := [_number_text(float(field_def["min"])), _number_text(float(field_def["max"]))]
		return "must be from %s to %s" % ends
	if field_def.has("min"):
		return "must be %s or more" % _number_text(float(field_def["min"]))
	return "must be %s or less" % _number_text(float(field_def["max"]))


## A number written the way a settings field reads it: whole where it is whole.
static func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return str(value)


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
static func _coerce(spec: Dictionary, value):
	var type_name := str(spec.get("type", TYPE_FLOAT))
	# A label picks the choice it does through `read_field()`, so what the check
	# took is what the build gets.
	if type_name == TYPE_ENUM and (value is String or value is StringName):
		var index := option_index(Array(spec.get("options", [])), value)
		if index >= 0:
			return index
	if not _is_number_like(value):
		var fallback = spec.get("default", 0.0)
		HFLog.warn(
			(
				"Generator setting '%s' cannot be a %s, so the default is used instead."
				% [str(spec.get("key", "?")), type_string(typeof(value))]
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
