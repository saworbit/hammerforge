extends GutTest
## The HammerForge Console's editor surface: the panel, its status rows, the
## controls grid and the log view.
##
## The two drift guards here matter most. The Controls tab addresses the dock's
## controls and LevelRoot's properties by name, and a rename in either place
## would silently turn a switch into a dead one rather than break the build.

const HFConsolePanelType = preload("res://addons/hammerforge/ui/hf_console_panel.gd")
const HFConsoleControlsType = preload("res://addons/hammerforge/ui/hf_console_controls.gd")
const HFConsoleLogViewType = preload("res://addons/hammerforge/ui/hf_console_log_view.gd")
const HFStatusRowType = preload("res://addons/hammerforge/ui/hf_status_row.gd")
const HFStatusLampType = preload("res://addons/hammerforge/ui/hf_status_lamp.gd")
const HFStatusBoardType = preload("res://addons/hammerforge/hf_status_board.gd")
const HFConsoleLogType = preload("res://addons/hammerforge/hf_console_log.gd")
const HFPluginConsoleType = preload("res://addons/hammerforge/plugin_console.gd")
const HFStatusStripType = preload("res://addons/hammerforge/ui/hf_status_strip.gd")


func after_each():
	HFConsoleLogType.reset_shared()


func _panel() -> HFConsolePanel:
	var panel = HFConsolePanelType.new()
	add_child_autofree(panel)
	return panel


# --- panel ---------------------------------------------------------------


func test_panel_builds_without_a_dock_or_a_log():
	var panel := _panel()
	panel.refresh(true)
	assert_eq(panel.name, "HammerForge", "The bottom-panel tab has to name the addon")


func test_panel_draws_one_row_per_check():
	var panel := _panel()
	panel.refresh(true)
	var expected := HFStatusBoardType.evaluate({}).size()
	assert_eq(_status_rows(panel).size(), expected)


func test_panel_reuses_rows_across_refreshes():
	var panel := _panel()
	panel.refresh(true)
	var first: Array = _status_rows(panel)
	panel.refresh(true)
	var second: Array = _status_rows(panel)
	assert_eq(first.size(), second.size())
	for i in range(first.size()):
		assert_eq(
			first[i].get_instance_id(),
			second[i].get_instance_id(),
			"Rebuilding rows would drop a tooltip mid-read and steal button focus"
		)


func test_panel_rows_carry_the_check_ids():
	var panel := _panel()
	panel.refresh(true)
	var ids := []
	for row in _status_rows(panel):
		ids.append(row.check_id)
	assert_has(ids, "level_root")
	assert_has(ids, "bake")
	assert_has(ids, "log")


func test_row_action_reaches_the_panel_signal():
	var panel := _panel()
	panel.refresh(true)
	watch_signals(panel)
	var row: HFStatusRow = _status_rows(panel)[0]
	row.action_requested.emit("create_starter")
	assert_signal_emitted_with_parameters(panel, "action_requested", ["create_starter"])


func test_open_log_is_handled_inside_the_panel():
	var panel := _panel()
	panel.refresh(true)
	watch_signals(panel)
	var row: HFStatusRow = _status_rows(panel)[0]
	row.action_requested.emit("open_log")
	assert_signal_not_emitted(
		panel, "action_requested", "Switching tabs is the panel's own business"
	)


func test_recording_a_validation_result_turns_the_check_green():
	var panel := _panel()
	var dock := FakeDock.new()
	panel.set_dock(dock)
	panel.record_validation([])
	var row = _row_with_id(panel, "validation")
	assert_not_null(row)
	assert_eq(row._lamp.severity, HFStatusBoardType.Severity.OK)
	dock.free()


func test_recording_validation_issues_turns_the_check_amber():
	var panel := _panel()
	var dock := FakeDock.new()
	panel.set_dock(dock)
	panel.record_validation(["Brush 2 is zero-size"])
	var row = _row_with_id(panel, "validation")
	assert_eq(row._lamp.severity, HFStatusBoardType.Severity.WARN)
	dock.free()


func test_a_recorded_result_stays_grey_while_no_level_is_open():
	# "Clean" has to mean "scanned and clean". With nothing loaded there is
	# nothing to have scanned, and a green light there would be a lie.
	var panel := _panel()
	panel.record_validation([])
	assert_eq(
		_row_with_id(panel, "validation")._lamp.severity, HFStatusBoardType.Severity.UNKNOWN
	)


func test_panel_survives_a_freed_level_root():
	var panel := _panel()
	var dock := FakeDock.new()
	var root := Node3D.new()
	dock.level_root = root
	panel.set_dock(dock)
	root.free()
	panel.refresh(true)
	assert_eq(_row_with_id(panel, "level_root")._lamp.severity, HFStatusBoardType.Severity.PROBLEM)
	dock.free()


func test_show_tab_is_bounded():
	var panel := _panel()
	panel.show_tab(99)
	panel.show_tab(-1)
	pass_test("Out-of-range tab requests must not crash the editor panel")


# --- status row and lamp -------------------------------------------------


func test_row_hides_its_button_when_a_check_has_no_action():
	var row = HFStatusRowType.new()
	add_child_autofree(row)
	row.apply_check(
		{"id": "x", "title": "T", "severity": 0, "value": "v", "detail": "d", "help": "h"}
	)
	assert_false(row._action.visible)


func test_row_tooltip_names_the_severity_so_colour_is_not_the_only_signal():
	var row = HFStatusRowType.new()
	add_child_autofree(row)
	row.apply_check(
		{
			"id": "x",
			"title": "T",
			"severity": HFStatusBoardType.Severity.PROBLEM,
			"value": "v",
			"detail": "d",
			"help": "why this matters",
			"action_id": "",
			"action_label": "",
		}
	)
	assert_string_contains(row.tooltip_text, "Problem")
	assert_string_contains(row.tooltip_text, "why this matters")


func test_lamp_colours_differ_per_severity():
	var seen := {}
	for severity in [
		HFStatusBoardType.Severity.OK,
		HFStatusBoardType.Severity.WARN,
		HFStatusBoardType.Severity.PROBLEM,
		HFStatusBoardType.Severity.UNKNOWN,
	]:
		var colour: Color = HFStatusLampType.color_for(severity)
		var key := colour.to_html(false)
		assert_false(seen.has(key), "Two severities share a colour: %s" % key)
		seen[key] = true


# --- controls tab --------------------------------------------------------


func test_every_control_addresses_a_dock_property_that_exists():
	# A rename in dock.gd would otherwise leave a switch here that silently
	# writes nowhere.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	for spec in _all_control_specs():
		var dock_name := str(spec.get("dock", ""))
		if dock_name == "":
			continue
		assert_string_contains(
			source,
			"var %s" % dock_name,
			"Controls tab points at dock.%s, which dock.gd no longer declares" % dock_name
		)


func test_every_control_addresses_a_level_root_property_that_exists():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")
	for spec in _all_control_specs():
		var key := str(spec.get("key", ""))
		if key == "":
			continue
		assert_true(
			source.contains("var %s:" % key) or source.contains("var %s " % key),
			"Controls tab points at LevelRoot.%s, which level_root.gd no longer declares" % key
		)


func test_every_control_has_a_caption_explaining_it():
	for spec in _all_control_specs():
		assert_true(spec.has("help"), "%s has no explanation" % spec.get("label", "?"))
		assert_gt(
			str(spec["help"]).length(), 20, "%s's explanation says nothing" % spec["label"]
		)


func test_every_control_reaches_somewhere():
	for spec in _all_control_specs():
		var reachable := (
			str(spec.get("key", "")) != ""
			or str(spec.get("dock", "")) != ""
			or str(spec.get("pref", "")) != ""
		)
		assert_true(reachable, "%s is a switch wired to nothing" % spec.get("label", "?"))


func test_control_labels_are_unique():
	var seen := {}
	for spec in _all_control_specs():
		var label := str(spec["label"])
		assert_false(seen.has(label), "Two controls both called %s" % label)
		seen[label] = true


func test_controls_are_disabled_without_a_level():
	var controls = HFConsoleControlsType.new()
	add_child_autofree(controls)
	controls.set_dock(null)
	var disabled := 0
	for entry in controls._rows:
		if entry["kind"] == "toggle" and entry["control"].disabled:
			disabled += 1
	assert_gt(disabled, 0, "A switch with nowhere to write must not look available")


func test_controls_write_through_the_dock_control():
	var controls = HFConsoleControlsType.new()
	add_child_autofree(controls)
	var dock := FakeDock.new()
	controls.set_dock(dock)
	controls._write({"dock": "show_grid", "key": "grid_visible"}, true)
	assert_true(dock.show_grid.button_pressed, "The dock's own handler has to stay in charge")
	dock.free()


func test_controls_fall_back_to_the_level_root_when_the_dock_has_no_control():
	var controls = HFConsoleControlsType.new()
	add_child_autofree(controls)
	var dock := FakeDock.new()
	controls.set_dock(dock)
	controls._write({"key": "bake_use_thread_pool"}, false)
	assert_false(dock.level_root.bake_use_thread_pool)
	dock.free()


func test_search_hides_controls_that_do_not_match():
	var controls = HFConsoleControlsType.new()
	add_child_autofree(controls)
	controls._on_search_changed("navmesh")
	var visible := 0
	for entry in controls._rows:
		if entry["container"].visible:
			visible += 1
	assert_gt(visible, 0, "\"navmesh\" must still find the navmesh switch")
	assert_lt(visible, controls._rows.size(), "and must hide the ones that do not match")


func test_clearing_the_search_shows_everything_again():
	var controls = HFConsoleControlsType.new()
	add_child_autofree(controls)
	controls._on_search_changed("navmesh")
	controls._on_search_changed("")
	for entry in controls._rows:
		assert_true(entry["container"].visible)


func test_search_matches_the_description_not_only_the_label():
	var controls = HFConsoleControlsType.new()
	add_child_autofree(controls)
	controls._on_search_changed("pathfinding")
	var visible := 0
	for entry in controls._rows:
		if entry["container"].visible:
			visible += 1
	assert_gt(visible, 0, "Searching for what a switch does should find it")


# --- log view ------------------------------------------------------------


func test_log_view_shows_entries_that_pass_the_filter():
	var view = HFConsoleLogViewType.new()
	add_child_autofree(view)
	var buffer = HFConsoleLogType.new()
	view.set_log(buffer)
	buffer.warn("something went sideways")
	assert_string_contains(view._output.get_parsed_text(), "something went sideways")


func test_log_view_hides_debug_by_default():
	var view = HFConsoleLogViewType.new()
	add_child_autofree(view)
	var buffer = HFConsoleLogType.new()
	view.set_log(buffer)
	buffer.debug("per-drag noise")
	assert_false(
		view._output.get_parsed_text().contains("per-drag noise"),
		"Debug is the level HammerForge writes on every drag"
	)


func test_log_view_isolates_a_level_on_request():
	var view = HFConsoleLogViewType.new()
	add_child_autofree(view)
	var buffer = HFConsoleLogType.new()
	view.set_log(buffer)
	buffer.info("routine")
	buffer.error("the actual fault")
	view.isolate_level(HFConsoleLogType.Level.ERROR)
	var text: String = view._output.get_parsed_text()
	assert_string_contains(text, "the actual fault")
	assert_false(text.contains("routine"))


func test_log_view_escapes_bbcode_in_a_message():
	var view = HFConsoleLogViewType.new()
	add_child_autofree(view)
	var buffer = HFConsoleLogType.new()
	view.set_log(buffer)
	buffer.warn("brush [b]Wall01[/b] is non-planar")
	assert_string_contains(
		view._output.get_parsed_text(),
		"[b]Wall01[/b]",
		"A bracket in a brush name must show, not style the line"
	)


func test_log_view_detaches_cleanly():
	var view = HFConsoleLogViewType.new()
	add_child(view)
	var buffer = HFConsoleLogType.new()
	view.set_log(buffer)
	remove_child(view)
	view.free()
	buffer.warn("after the view is gone")
	pass_test("Logging after the view is freed must not reach a dangling listener")


func test_log_view_survives_having_no_log():
	var view = HFConsoleLogViewType.new()
	add_child_autofree(view)
	view.rebuild()
	view._on_copy_pressed()
	view._on_clear_pressed()
	pass_test("Every log control is safe before a buffer is attached")


# --- plugin wiring -------------------------------------------------------


func test_console_actions_are_null_safe():
	HFPluginConsoleType.handle_action(null, "bake")
	HFPluginConsoleType.setup(null)
	HFPluginConsoleType.teardown(null)
	HFPluginConsoleType.apply_icons(null)
	HFPluginConsoleType.focus_dock(null)
	pass_test("Console entry points run before, during and after plugin teardown")


func test_every_status_action_has_a_handler():
	# A status row offering a button that does nothing is worse than no button.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_console.gd")
	var offered := {}
	for ctx in [{}, _rich_context()]:
		for check in HFStatusBoardType.evaluate(ctx):
			var action := str(check.get("action_id", ""))
			if action != "":
				offered[action] = true
	for action in offered.keys():
		if action == "open_log":
			continue  # handled inside the panel, never routed out
		assert_string_contains(
			source, '"%s"' % action, "Status board offers '%s' with no handler" % action
		)


func test_plugin_installs_and_removes_the_console():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_string_contains(source, "HFPluginConsoleType.setup(self)")
	assert_string_contains(source, "HFPluginConsoleType.teardown(self)")
	assert_string_contains(
		source, "_on_console_action", "Console actions need a route back into the plugin"
	)


func test_dock_tab_names_the_addon():
	var scene := FileAccess.get_file_as_string("res://addons/hammerforge/dock.tscn")
	assert_string_contains(
		scene,
		'[node name="HammerForge" type="PanelContainer"]',
		"Godot titles a dock tab from its root node, so the tab has to say HammerForge"
	)


func test_console_uses_the_repo_brand_assets():
	assert_true(
		ResourceLoader.exists(HFConsolePanelType.LOCKUP_DARK),
		"The dark-ground lockup ships inside the addon"
	)
	assert_true(ResourceLoader.exists(HFConsolePanelType.LOCKUP_LIGHT))
	assert_true(
		ResourceLoader.exists(HFPluginConsoleType.ICON_PATH),
		"The dock tab and the custom node types wear the HammerForge mark"
	)


func test_brand_assets_are_generated_not_hand_placed():
	var build := FileAccess.get_file_as_string("res://docs/brand/build.py")
	assert_string_contains(
		build,
		"addons/hammerforge/branding",
		"BRAND.md's rule is that geometry lives in one place; the addon's copies derive from it"
	)


# --- helpers -------------------------------------------------------------


func _rich_context() -> Dictionary:
	return {
		"has_root": true,
		"root_name": "Arena",
		"brush_count": 4,
		"baked_count": 0,
		"material_count": 0,
		"spawn_count": 0,
		"auto_spawn_player": false,
		"autosave_enabled": true,
		"autosave_exists": true,
		"autosave_minutes": 5,
		"recommended_chunk_size": 64.0,
		"chunk_size": 32.0,
		"validation_run": true,
		"validation_issues": ["one"],
		"log_error": 1,
	}


func _status_rows(panel) -> Array:
	var rows := []
	for child in panel._status_list.get_children():
		if child is HFStatusRow:
			rows.append(child)
	return rows


func _row_with_id(panel, id: String):
	for row in _status_rows(panel):
		if row.check_id == id:
			return row
	return null


func _all_control_specs() -> Array:
	var specs := []
	for group in HFConsoleControlsType.GROUPS:
		for spec in group["rows"]:
			specs.append(spec)
	for spec in HFConsoleControlsType.NUMBERS:
		specs.append(spec)
	return specs


## Enough of the dock and LevelRoot for the Controls tab to read and write.
class FakeRoot:
	extends Node3D

	var grid_visible := false
	var bake_use_thread_pool := true


class FakeDock:
	extends Node

	var level_root: Node3D = null
	var show_grid: CheckBox = null

	func _init() -> void:
		level_root = FakeRoot.new()
		add_child(level_root)
		show_grid = CheckBox.new()
		add_child(show_grid)


func test_open_log_from_an_error_row_lands_on_the_errors():
	# The row said "1 error". Opening the tab onto the whole buffer would make
	# the reader find it a second time.
	var panel := _panel()
	var buffer = HFConsoleLogType.new()
	panel.set_log(buffer)
	buffer.info("routine chatter")
	buffer.error("the actual fault")
	panel.refresh(true)
	var row = _row_with_id(panel, "log")
	assert_eq(row._lamp.severity, HFStatusBoardType.Severity.PROBLEM)
	row.action_requested.emit("open_log")
	assert_eq(panel._log_view._level_mask, 1 << HFConsoleLogType.Level.ERROR)


func test_open_log_from_a_warning_row_lands_on_the_warnings():
	var panel := _panel()
	var buffer = HFConsoleLogType.new()
	panel.set_log(buffer)
	buffer.warn("worth a look")
	panel.refresh(true)
	_row_with_id(panel, "log").action_requested.emit("open_log")
	assert_eq(panel._log_view._level_mask, 1 << HFConsoleLogType.Level.WARN)


func test_open_log_from_a_quiet_row_leaves_the_filter_alone():
	var panel := _panel()
	var buffer = HFConsoleLogType.new()
	panel.set_log(buffer)
	buffer.info("nothing wrong here")
	panel.refresh(true)
	_row_with_id(panel, "log").action_requested.emit("open_log")
	assert_eq(
		panel._log_view._level_mask,
		HFConsoleLogViewType.DEFAULT_MASK,
		"With nothing to isolate, the reader keeps the filter they had"
	)


func test_plugin_declares_a_main_screen():
	# The main-screen switcher is the one row of the editor chrome that draws a
	# plugin icon at all. Godot 4.7 bottom panel is text-only, and a docked
	# control icon lives on the EditorDock wrapper.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_string_contains(source, "func _has_main_screen()")
	assert_string_contains(source, "func _get_plugin_icon()")
	assert_string_contains(source, "func _get_plugin_name()")
	assert_string_contains(source, "func _make_visible(")


func test_console_fills_the_main_screen():
	# The main screen is a box container, so a child without expand flags gets
	# its minimum height and the status board collapses to a strip.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_console.gd")
	assert_string_contains(source, "panel.size_flags_vertical = Control.SIZE_EXPAND_FILL")


func test_dock_tab_icon_is_forced_on_the_editor_dock_wrapper():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_console.gd")
	assert_string_contains(source, "force_show_icon = true")


func test_switcher_icon_is_authored_at_the_size_the_switcher_draws():
	# A 64px source renders at 64px in that row and lifts the whole top bar.
	assert_true(ResourceLoader.exists(HFPluginConsoleType.EDITOR_ICON_PATH))
	var texture: Texture2D = load(HFPluginConsoleType.EDITOR_ICON_PATH)
	assert_eq(texture.get_width(), 32, "The other addons in this editor use 32")
	assert_eq(texture.get_height(), 32)


# --- viewport strip ------------------------------------------------------


func test_strip_reads_its_summary_from_the_console():
	var panel := _panel()
	var strip = HFStatusStripType.new()
	add_child_autofree(strip)
	strip.set_source(panel)
	assert_eq(strip._lamp.severity, panel.compute_summary()["severity"])
	assert_eq(strip._button.text, str(panel.compute_summary()["label"]))


func test_strip_is_safe_without_a_source():
	var strip = HFStatusStripType.new()
	add_child_autofree(strip)
	strip.refresh()
	strip.set_source(null)
	strip.refresh()
	pass_test("The lamp is built before the Console it reads from")


func test_strip_asks_for_the_console_when_pressed():
	var strip = HFStatusStripType.new()
	add_child_autofree(strip)
	watch_signals(strip)
	strip._button.pressed.emit()
	assert_signal_emitted(strip, "console_requested")


func test_strip_tooltip_breaks_the_summary_down():
	var panel := _panel()
	var strip = HFStatusStripType.new()
	add_child_autofree(strip)
	strip.set_source(panel)
	assert_string_contains(strip._button.tooltip_text, "Click to open the Console")
