@tool
extends RefCounted
class_name HFOpResult
## Lightweight result object returned by operations that can fail.
## Carries a human-readable message and an optional actionable fix hint.
##
## Both stay English, as the Console's log and the bridge read them, and go
## through `HFTranslation.message()`, so a toast or the status line shows them in
## the language shown. Text put together in code is made with `message()` first.

const HFTranslationType = preload("res://addons/hammerforge/hf_translation.gd")

var ok: bool
var message: String
var fix_hint: String


static func success(msg: String = "") -> HFOpResult:
	var r = HFOpResult.new()
	r.ok = true
	r.message = HFTranslationType.message(msg)
	return r


static func fail(msg: String, hint: String = "") -> HFOpResult:
	var r = HFOpResult.new()
	r.ok = false
	r.message = HFTranslationType.message(msg)
	r.fix_hint = HFTranslationType.message(hint)
	return r


## Format message with fix_hint appended (if present) for user-facing display.
func user_text() -> String:
	if fix_hint != "":
		var parts := {"message": message, "hint": fix_hint}
		return HFTranslationType.message("{message} — {hint}", {}, parts)
	return message
