@tool
class_name HFPluginUpdateCheck
extends RefCounted
## The once a day question "is a newer HammerForge out", asked a few seconds
## after the editor starts, and the Status board line that answers it (#1656).
## `HFUpdateCheck` decides; this asks and shows.

const HFUpdateCheckType = preload("hf_update_check.gd")
const HFProblemReportType = preload("hf_problem_report.gd")
const HFConsoleLogType = preload("hf_console_log.gd")

const START_DELAY_SECONDS := 5.0
const REQUEST_NAME := "HFUpdateCheckRequest"

## Test seams. `editor_state` answers `{"online": bool, "checks": bool}` in place
## of the editor's settings; `version` stands in for `plugin.cfg`'s; `fetch` is
## called with the URL and a callback taking (ok: bool, body: PackedByteArray)
## in place of a request; `open_url` in place of the browser.
static var editor_state := Callable()
static var version := ""
static var fetch := Callable()
static var open_url := Callable()


## Ask a few seconds after the editor starts, so start up is not slowed by it.
static func setup(plugin: Object) -> void:
	if not Engine.is_editor_hint():
		return
	var tree: SceneTree = plugin.get_tree() if plugin.has_method("get_tree") else null
	if tree == null:
		return
	tree.create_timer(START_DELAY_SECONDS).timeout.connect(
		func():
			if is_instance_valid(plugin) and plugin.is_inside_tree():
				start(plugin)
	)


## Ask now, if allowed. Returns whether a request went out.
static func start(plugin: Object) -> bool:
	var prefs = plugin.get("_user_prefs")
	var state := _editor_state(plugin)
	var reason := HFUpdateCheckType.why_not(
		current_version(), prefs, state.get("online") == true, state.get("checks") == true, _now()
	)
	if reason != "":
		HFConsoleLogType.shared().debug("Update check skipped: %s." % reason, "update")
		return false
	if prefs:
		prefs.set_pref(HFUpdateCheckType.LAST_CHECKED, _now())
		prefs.save()
	var done := func(ok: bool, body: PackedByteArray): answered(plugin, ok, body)
	if fetch.is_valid():
		fetch.call(HFUpdateCheckType.ASSET_URL, done)
		return true
	var request := HTTPRequest.new()
	request.name = REQUEST_NAME
	request.timeout = HFUpdateCheckType.TIMEOUT_SECONDS
	plugin.add_child(request)
	request.request_completed.connect(
		func(result: int, code: int, _headers, body: PackedByteArray):
			request.queue_free()
			done.call(result == HTTPRequest.RESULT_SUCCESS and code == 200, body)
	)
	if request.request(HFUpdateCheckType.ASSET_URL) != OK:
		request.queue_free()
		done.call(false, PackedByteArray())
	return true


## The Asset Library answered, or did not. A failure says one debug line and
## shows nothing.
static func answered(plugin: Object, ok: bool, body: PackedByteArray) -> void:
	var latest := HFUpdateCheckType.version_from(body) if ok else ""
	if latest == "":
		HFConsoleLogType.shared().debug(
			"Update check: no usable answer from the Asset Library.", "update"
		)
		return
	var notice := HFUpdateCheckType.notice_for(
		latest, current_version(), plugin.get("_user_prefs"), _now()
	)
	var panel = plugin.get("console_panel")
	if not notice.is_empty() and panel and is_instance_valid(panel):
		panel.record_update(notice)


## The Status board line's buttons.
static func handle_action(plugin: Object, action_id: String) -> void:
	var panel = plugin.get("console_panel")
	if panel == null or not is_instance_valid(panel):
		return
	var notice: Dictionary = panel.update_notice()
	var latest := str(notice.get("latest", ""))
	var prefs = plugin.get("_user_prefs")
	match action_id:
		"update_notes":
			var url := HFUpdateCheckType.RELEASE_URL % latest
			if open_url.is_valid():
				open_url.call(url)
			else:
				OS.shell_open(url)
		"update_skip":
			if prefs:
				prefs.set_pref(HFUpdateCheckType.SKIPPED, latest)
				prefs.save()
			panel.record_update({})
		"update_later":
			if prefs:
				prefs.set_pref(
					HFUpdateCheckType.LATER_UNTIL,
					_now() + HFUpdateCheckType.LATER_DAYS * HFUpdateCheckType.DAY_SECONDS
				)
				prefs.save()
			panel.record_update({})


static func current_version() -> String:
	return version if version != "" else HFProblemReportType.hammerforge_version()


## Whether the editor is online and its own update check is on.
static func _editor_state(plugin: Object) -> Dictionary:
	if editor_state.is_valid():
		return editor_state.call()
	var editor = (
		plugin.get_editor_interface() if plugin.has_method("get_editor_interface") else null
	)
	var settings = (
		editor.get_editor_settings()
		if editor and editor.has_method("get_editor_settings")
		else null
	)
	if settings == null:
		return {"online": false, "checks": false}
	var mode: Variant = settings.get_setting("network/connection/network_mode")
	var checks: Variant = settings.get_setting("network/connection/check_for_updates")
	return {
		"online": (mode is int or mode is float) and int(mode) != 0,
		"checks": (checks is int or checks is float) and int(checks) != 0,
	}


static func _now() -> float:
	return Time.get_unix_time_from_system()
