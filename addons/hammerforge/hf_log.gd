@tool
extends RefCounted
class_name HFLog

const SUPPRESSED_WARNING_PATTERNS_META := "_hf_suppressed_warning_patterns"
const CAPTURED_WARNINGS_META := "_hf_captured_warnings"


static func warn(message: String) -> void:
	_capture_warning(message)
	if _is_suppressed(message):
		return
	push_warning(message)


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
	var captured = Engine.get_meta(CAPTURED_WARNINGS_META, null)
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
