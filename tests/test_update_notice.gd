extends GutTest

## Saying when a newer HammerForge is out, and asking only when allowed (#1656).

const HFUpdateCheck = preload("res://addons/hammerforge/hf_update_check.gd")
const HFPluginUpdateCheck = preload("res://addons/hammerforge/plugin_update_check.gd")
const HFUserPrefs = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFConsoleLog = preload("res://addons/hammerforge/hf_console_log.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")

const PREFS := "user://hf_test_update_notice_prefs.json"

var rig: PluginRig = null
var _fetched: Array = []
var _opened: Array = []
var _online := true
var _checks := true
var _saved_prefs_path := ""


func before_each() -> void:
	_fetched = []
	_opened = []
	_online = true
	_checks = true
	HFPluginUpdateCheck.editor_state = func() -> Dictionary:
		return {"online": _online, "checks": _checks}
	HFPluginUpdateCheck.version = "0.4.0"
	HFPluginUpdateCheck.fetch = func(url: String, done: Callable) -> void:
		_fetched.append([url, done])
	HFPluginUpdateCheck.open_url = func(url: String) -> void: _opened.append(url)
	_saved_prefs_path = HFUserPrefs.prefs_path


func after_each() -> void:
	if rig:
		await rig.take_down()
		rig = null
	HFPluginUpdateCheck.editor_state = Callable()
	HFPluginUpdateCheck.version = ""
	HFPluginUpdateCheck.fetch = Callable()
	HFPluginUpdateCheck.open_url = Callable()
	HFUserPrefs.prefs_path = _saved_prefs_path
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _prefs() -> HFUserPrefs:
	var prefs := HFUserPrefs.new()
	prefs.persistence_enabled = false
	return prefs


func _answer(version: String) -> PackedByteArray:
	return JSON.stringify({"title": "HammerForge", "version_string": version}).to_utf8_buffer()


func test_versions_compare_as_numbers():
	assert_true(HFUpdateCheck.newer("0.10.0", "0.9.0"))
	assert_true(HFUpdateCheck.newer("0.4.2", "0.4.1"))
	assert_true(HFUpdateCheck.newer("v1.0", "0.9.9"))
	assert_false(HFUpdateCheck.newer("0.4.1", "0.4.1"))
	assert_false(HFUpdateCheck.newer("0.4.0", "0.4.1"))
	assert_false(HFUpdateCheck.newer("0.4.1", "0.4.1-dev"), "a suffix is not a version")


func test_it_asks_only_when_everything_allows_it():
	var prefs := _prefs()
	var now := 1_000_000.0
	assert_eq(HFUpdateCheck.why_not("0.4.0", prefs, true, true, now), "")
	assert_eq(HFUpdateCheck.why_not("0.4.1-dev", prefs, true, true, now), "a development build")
	assert_eq(HFUpdateCheck.why_not("0.4.0", prefs, false, true, now), "the editor is offline")
	assert_eq(
		HFUpdateCheck.why_not("0.4.0", prefs, true, false, now), "the editor's update check is off"
	)
	prefs.set_pref(HFUpdateCheck.LAST_CHECKED, now - 3600.0)
	assert_eq(HFUpdateCheck.why_not("0.4.0", prefs, true, true, now), "asked within the last day")
	prefs.set_pref(HFUpdateCheck.LAST_CHECKED, now - 90000.0)
	prefs.set_pref(HFUpdateCheck.ENABLED, false)
	assert_eq(HFUpdateCheck.why_not("0.4.0", prefs, true, true, now), "turned off in Settings")


func test_only_a_well_formed_answer_has_a_version():
	assert_eq(HFUpdateCheck.version_from(_answer("0.4.2")), "0.4.2")
	assert_eq(HFUpdateCheck.version_from("not json".to_utf8_buffer()), "")
	assert_eq(HFUpdateCheck.version_from(JSON.stringify({"a": 1}).to_utf8_buffer()), "")
	assert_eq(
		HFUpdateCheck.version_from(JSON.stringify({"version_string": 4}).to_utf8_buffer()), ""
	)


func test_a_newer_version_is_news_unless_skipped_or_put_off():
	var prefs := _prefs()
	var now := 2_000_000.0
	assert_eq(
		HFUpdateCheck.notice_for("0.4.2", "0.4.0", prefs, now),
		{"latest": "0.4.2", "current": "0.4.0"}
	)
	assert_eq(HFUpdateCheck.notice_for("0.4.0", "0.4.0", prefs, now), {}, "equal")
	assert_eq(HFUpdateCheck.notice_for("0.3.2", "0.4.0", prefs, now), {}, "older")
	prefs.set_pref(HFUpdateCheck.SKIPPED, "0.4.2")
	assert_eq(HFUpdateCheck.notice_for("0.4.2", "0.4.0", prefs, now), {}, "skipped")
	assert_false(
		HFUpdateCheck.notice_for("0.4.3", "0.4.0", prefs, now).is_empty(), "a later one is news"
	)
	prefs.set_pref(HFUpdateCheck.LATER_UNTIL, now + 100.0)
	assert_eq(HFUpdateCheck.notice_for("0.4.3", "0.4.0", prefs, now), {}, "put off")
	assert_false(HFUpdateCheck.notice_for("0.4.3", "0.4.0", prefs, now + 200.0).is_empty())


func test_offline_or_a_dev_build_makes_no_request():
	rig = PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return
	_online = false
	assert_false(HFPluginUpdateCheck.start(rig.plugin))
	HFPluginUpdateCheck.version = "0.4.1-dev"
	_online = true
	assert_false(HFPluginUpdateCheck.start(rig.plugin))
	assert_eq(_fetched, [], "no request either way")


func test_a_newer_answer_shows_the_line_and_its_buttons_work():
	rig = PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return
	assert_true(HFPluginUpdateCheck.start(rig.plugin))
	assert_eq(_fetched.size(), 1)
	assert_eq(_fetched[0][0], HFUpdateCheck.ASSET_URL)
	assert_false(HFPluginUpdateCheck.start(rig.plugin), "once a day")
	(_fetched[0][1] as Callable).call(true, _answer("0.4.2"))
	var panel = rig.plugin.console_panel
	assert_eq(panel.update_notice().get("latest"), "0.4.2", "the line shows")
	rig.plugin._on_console_action("update_notes")
	assert_eq(_opened, [HFUpdateCheck.RELEASE_URL % "0.4.2"])
	rig.plugin._on_console_action("update_later")
	assert_true(panel.update_notice().is_empty(), "Later takes the row away")
	var until := float(rig.plugin._user_prefs.get_pref(HFUpdateCheck.LATER_UNTIL))
	var three_days := Time.get_unix_time_from_system() + 3 * HFUpdateCheck.DAY_SECONDS
	assert_almost_eq(until, three_days, 60.0, "for three days")


func test_an_equal_answer_or_a_failure_shows_nothing_and_says_one_debug_line():
	rig = PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		return
	HFPluginUpdateCheck.answered(rig.plugin, true, _answer("0.4.0"))
	assert_true(rig.plugin.console_panel.update_notice().is_empty(), "equal is no news")
	var before := _debug_lines()
	HFPluginUpdateCheck.answered(rig.plugin, false, PackedByteArray())
	HFPluginUpdateCheck.answered(rig.plugin, true, "<html>".to_utf8_buffer())
	assert_true(rig.plugin.console_panel.update_notice().is_empty())
	assert_eq(_debug_lines() - before, 2, "one debug line each")


## The update check's debug lines, a repeat counted as many times as it came.
func _debug_lines() -> int:
	var total := 0
	for entry in HFConsoleLog.shared().entries():
		if str(entry.get("message", "")).begins_with("Update check:"):
			total += int(entry.get("repeat", 1))
	return total


func test_a_skipped_version_stays_skipped_across_restarts():
	HFUserPrefs.prefs_path = PREFS
	var prefs := HFUserPrefs.load_prefs()
	prefs.set_pref(HFUpdateCheck.SKIPPED, "0.4.2")
	prefs.save()
	var again := HFUserPrefs.load_prefs()
	assert_eq(again.get_pref(HFUpdateCheck.SKIPPED), "0.4.2")
	assert_eq(
		HFUpdateCheck.notice_for("0.4.2", "0.4.0", again, Time.get_unix_time_from_system()), {}
	)


func test_the_setting_is_on_the_controls_tab():
	var labels := []
	for group in load("res://addons/hammerforge/ui/hf_console_controls.gd").GROUPS:
		for row in group["rows"]:
			if row.get("pref") == HFUpdateCheck.ENABLED:
				labels.append(row["label"])
	assert_eq(labels, ["Check for a newer HammerForge"])
	assert_true(_prefs().get_pref(HFUpdateCheck.ENABLED), "on by default")
