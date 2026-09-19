extends GutTest

## What the Bake status row says when a bake finishes.
##
## The release gate asks for two things here: that the row goes green, and that
## it names how long the bake took. It did neither -- the message was the literal
## "Bake complete", and `_set_status(msg, false, ...)` *removes* the colour
## override rather than setting one, so the row was ordinary body text (#773).

const HFDockManageHandler = preload("res://addons/hammerforge/dock_manage_handler.gd")

var dock: Node


func before_each() -> void:
	dock = Node.new()
	dock.set_script(_dock_shim_script())
	add_child_autoqfree(dock)
	dock.bake_btn = Button.new()
	dock.commit_cuts_btn = Button.new()
	dock.apply_cuts_btn = Button.new()
	for b in [dock.bake_btn, dock.commit_cuts_btn, dock.apply_cuts_btn]:
		add_child_autoqfree(b)


func after_each() -> void:
	dock = null


func _dock_shim_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """
extends Node

signal bake_state_changed(running: bool, failed: bool)

# update_bake_estimate() returns early on either of these being unset, which is
# what keeps this shim small.
var level_root = null
var bake_estimate_label = null

var progress_bar = null
var _hints_dirty: bool = false
var _bake_disabled: bool = false
var _bake_started_msec: int = 0
var bake_btn
var commit_cuts_btn
var apply_cuts_btn
var quick_play_btn = null
var bake_selected_btn = null
var bake_changed_btn = null
var quick_play_camera_btn = null
var quick_play_area_btn = null

func _update_disabled_hints() -> void:
	pass

var statuses: Array = []
var toasts: Array = []

func _set_status(message: String, is_error: bool = false, timeout: float = 0.0) -> void:
	statuses.append({"message": message, "kind": "error" if is_error else "plain", "timeout": timeout})

func _set_status_success(message: String, timeout: float = 0.0) -> void:
	statuses.append({"message": message, "kind": "success", "timeout": timeout})

func _set_status_warning(message: String, timeout: float = 5.0) -> void:
	statuses.append({"message": message, "kind": "warning", "timeout": timeout})

func show_toast(message: String, level: int = 0) -> void:
	toasts.append({"message": message, "level": level})

func _log(_msg: String, _is_error: bool = false) -> void:
	pass

func last_status() -> Dictionary:
	return statuses[-1] if statuses.size() > 0 else {}
"""
	s.reload()
	return s


# ---------------------------------------------------------------------------
# What the row says
# ---------------------------------------------------------------------------


func test_a_finished_bake_names_how_long_it_took() -> void:
	HFDockManageHandler.on_bake_started(dock)
	HFDockManageHandler.on_bake_finished(dock, true)

	var message: String = dock.last_status().get("message", "")
	assert_true(
		message.begins_with("Bake complete in "),
		'the row reports a duration, not just that it happened -- got "%s"' % message
	)
	var tail := message.trim_prefix("Bake complete in ")
	assert_true(
		tail.ends_with(" ms") or tail.ends_with(" s") or tail.ends_with(" min"),
		'and reports it with a unit -- got "%s"' % message
	)


func test_a_finished_bake_colours_the_row_as_a_success() -> void:
	HFDockManageHandler.on_bake_started(dock)
	HFDockManageHandler.on_bake_finished(dock, true)

	assert_eq(
		dock.last_status().get("kind", ""),
		"success",
		"a clean bake is reported as one, rather than as body text the eye slides off"
	)


func test_a_failed_bake_is_still_an_error() -> void:
	# The other half. Colouring success must not colour failure the same way.
	HFDockManageHandler.on_bake_started(dock)
	HFDockManageHandler.on_bake_finished(dock, false)

	assert_eq(dock.last_status().get("kind", ""), "error", "a refused bake still reads as refused")


func test_a_bake_that_was_never_started_still_reports_cleanly() -> void:
	# on_bake_finished can arrive without this dock having seen the start - a
	# bake kicked off elsewhere, or a dock rebuilt mid-bake. It must not report a
	# duration measured from zero.
	HFDockManageHandler.on_bake_finished(dock, true)

	var message: String = dock.last_status().get("message", "")
	assert_eq(message, "Bake complete", "with no start to measure from, it says only what it knows")
	assert_eq(dock.last_status().get("kind", ""), "success", "and is still a success")


# ---------------------------------------------------------------------------
# The formatter, which the estimate label already used
# ---------------------------------------------------------------------------


func test_durations_are_formatted_the_way_the_estimate_label_formats_them() -> void:
	assert_eq(HFDockManageHandler.format_duration_ms(340), "340 ms", "under a second, whole ms")
	assert_eq(HFDockManageHandler.format_duration_ms(1200), "1.2 s", "under a minute, one decimal")
	assert_eq(HFDockManageHandler.format_duration_ms(90000), "1.5 min", "beyond that, minutes")
