@tool
extends RefCounted
class_name HFLog

const SUPPRESSED_WARNING_PATTERNS_META := "_hf_suppressed_warning_patterns"
const CAPTURED_WARNINGS_META := "_hf_captured_warnings"

## The Console installs a session log. Save workers also report through it.
static var _sink = null
static var _sink_mutex := Mutex.new()


## Set by the Console on install and cleared on teardown.
static func set_sink(sink) -> void:
	_sink_mutex.lock()
	_sink = sink
	_sink_mutex.unlock()


static func _current_sink():
	_sink_mutex.lock()
	var sink = _sink
	_sink_mutex.unlock()
	return sink


static func warn(message: String) -> void:
	_capture_warning(message)
	var sink = _current_sink()
	if is_instance_valid(sink):
		sink.warn(message, "warning")
	if _is_suppressed(message):
		return
	push_warning(message)


static func error(message: String, category := "error") -> void:
	record_error(message, category)
	push_error(message)


## Record an error whose caller already reports it in Godot's Output.
static func record_error(message: String, category: String) -> void:
	var sink = _current_sink()
	if is_instance_valid(sink):
		sink.error(message, category)


static func begin_test_capture(suppressed_patterns: Array = []) -> void:
	var patterns := PackedStringArray()
	for pattern in suppressed_patterns:
		patterns.append(str(pattern))
	Engine.set_meta(SUPPRESSED_WARNING_PATTERNS_META, patterns)
	Engine.set_meta(CAPTURED_WARNINGS_META, [])


static func end_test_capture() -> void:
	if Engine.has_meta(SUPPRESSED_WARNING_PATTERNS_META):
		Engine.remove_meta(SUPPRESSED_WARNING_PATTERNS_META)
	if Engine.has_meta(CAPTURED_WARNINGS_META):
		Engine.remove_meta(CAPTURED_WARNINGS_META)


static func get_captured_warnings() -> Array:
	var captured = Engine.get_meta(CAPTURED_WARNINGS_META, [])
	return captured.duplicate() if captured is Array else []


static func _capture_warning(message: String) -> void:
	# Check has_meta first: Object.get_meta() only honours its default when that
	# default is not null, and otherwise raises "Method/function failed". Outside
	# a test capture the key is absent, so passing null here made every warning
	# print a bogus engine error alongside it.
	if not Engine.has_meta(CAPTURED_WARNINGS_META):
		return
	var captured = Engine.get_meta(CAPTURED_WARNINGS_META)
	if captured is Array:
		captured.append(message)
		Engine.set_meta(CAPTURED_WARNINGS_META, captured)


static func _is_suppressed(message: String) -> bool:
	var patterns = Engine.get_meta(SUPPRESSED_WARNING_PATTERNS_META, PackedStringArray())
	if patterns is PackedStringArray:
		for pattern in patterns:
			if message.contains(pattern):
				return true
	elif patterns is Array:
		# Defensive fallback: Engine metadata can come back as a plain Array in tests.
		for pattern in patterns:
			if message.contains(str(pattern)):
				return true
	return false
