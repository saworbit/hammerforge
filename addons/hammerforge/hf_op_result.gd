@tool
extends RefCounted
class_name HFOpResult
## Lightweight result object returned by operations that can fail.
## Carries a human-readable message and an optional actionable fix hint.

var ok: bool
var message: String
var fix_hint: String


static func success(msg: String = "") -> HFOpResult:
	var r = HFOpResult.new()
	r.ok = true
	r.message = msg
	return r


static func fail(msg: String, hint: String = "") -> HFOpResult:
	var r = HFOpResult.new()
	r.ok = false
	r.message = msg
	r.fix_hint = hint
	return r


## Format message with fix_hint appended (if present) for user-facing display.
func user_text() -> String:
	if fix_hint != "":
		return message + " — " + fix_hint
	return message
