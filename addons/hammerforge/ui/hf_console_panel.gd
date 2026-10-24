@tool
class_name HFConsolePanel
extends VBoxContainer
## The HammerForge Console — the editor bottom panel behind the HammerForge
## button, and the addon's front door.
##
## Three tabs, in the order a question arrives:
##
##   Status    is anything wrong, and what is the one button that fixes it
##   Controls  every switch, grouped and captioned
##   Log       what HammerForge has actually been doing
##
## The panel never computes anything itself. HFStatusBoard decides severities,
## HFConsoleLog holds the messages, and the dock owns the settings; this draws
## them and routes the button presses back out through `action_requested`.

const HFStatusBoardType = preload("../hf_status_board.gd")
const HFNotesType = preload("../hf_notes.gd")
const HFConsoleLogType = preload("../hf_console_log.gd")
const HFStatusLampType = preload("hf_status_lamp.gd")
const HFStatusRowType = preload("hf_status_row.gd")
const HFConsoleControlsType = preload("hf_console_controls.gd")
const HFConsoleLogViewType = preload("hf_console_log_view.gd")
const HFEntityCensusType = preload("../hf_entity_census.gd")
const HFCommandLineViewType = preload("hf_command_line_view.gd")

const LOCKUP_DARK := "res://addons/hammerforge/branding/hf_lockup_dark.svg"
const LOCKUP_LIGHT := "res://addons/hammerforge/branding/hf_lockup_light.svg"
const PLUGIN_CFG := "res://addons/hammerforge/plugin.cfg"

## Counts and flags are cheap enough to read every second.
const POLL_SECONDS := 1.0

## The level walks behind the vertex estimate and the chunk recommendation are
## not, so they refresh on this slower beat, plus whenever the reader asks.
const DEEP_POLL_TICKS := 10

enum Tab { STATUS, CONTROLS, LOG, ENTITIES, NOTES }

signal action_requested(action_id: String)

var _dock = null
var _prefs = null
var _base_control: Control = null
var _log = null

var _lockup: TextureRect = null
var _version_label: Label = null
var _summary_lamp: HFStatusLamp = null
var _summary_label: Label = null
var _scope_label: Label = null
var _checked_label: Label = null
var _tabs: TabContainer = null
var _status_list: VBoxContainer = null
var _legend: HBoxContainer = null
var _attention_only: CheckButton = null
var _controls: HFConsoleControls = null
var _log_view: HFConsoleLogView = null
var _command_line = null  # The line under the tabs, where a command is typed (#1696)
var _poll: Timer = null
var _census_scope: OptionButton = null  # Entities tab: the whole level, the cordons, a visgroup
var _census_tree: Tree = null  # Entities tab: one row per class, with its count (#1709)
var _census_shown: Array = []  # What the Entities tab shows now: its scopes and its rows
var _notes_tree: Tree = null  # Notes tab: every note by kind (#1700)
var _notes_shown: Array = []  # What the Notes tab shows now
var _compare_label: Label = null  # Compare tab: what was compared, and the summary (#1701)
var _compare_tree: Tree = null  # Compare tab: each change, which selects what it names
var _compare_end: Button = null

var _rows: Dictionary = {}  # check id -> HFStatusRow
var _row_order: Array = []
var _cached: Dictionary = {}
var _tick: int = 0
var _last_deep_context: Dictionary = {}
var _hide_when_fine: bool = false
## Severity of the session-log check, so "Open Log" can land on the lines that
## check counted rather than on the whole buffer.
var _log_severity: int = HFStatusBoardType.Severity.OK


func _init() -> void:
	name = "HammerForge"
	add_theme_constant_override("separation", 0)
	_build()


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _exit_tree() -> void:
	if visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.disconnect(_on_visibility_changed)
	if _poll:
		_poll.stop()
	_log = null


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


func _build() -> void:
	_build_header()
	add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	add_child(_tabs)

	_build_status_tab()
	_build_controls_tab()
	_build_log_tab()
	_build_entities_tab()
	_build_notes_tab()
	_build_compare_tab()

	_command_line = HFCommandLineViewType.new()
	add_child(_inset(_command_line))

	_poll = Timer.new()
	_poll.wait_time = POLL_SECONDS
	_poll.autostart = false
	_poll.timeout.connect(_on_poll)
	add_child(_poll)

	# The lockup and the muted text colours are resolved here rather than
	# waiting for set_theme_source(), so the header is never briefly blank.
	_apply_theme()


func _build_header() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	margin.add_child(header)

	_lockup = TextureRect.new()
	_lockup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lockup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lockup.custom_minimum_size = Vector2(132, 22)
	_lockup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lockup.tooltip_text = "HammerForge — brush-based level editing for Godot."
	header.add_child(_lockup)

	_version_label = Label.new()
	_version_label.add_theme_font_size_override("font_size", 10)
	_version_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_version_label.text = _read_version()
	header.add_child(_version_label)

	header.add_child(_vertical_rule())

	_summary_lamp = HFStatusLampType.new()
	_summary_lamp.custom_minimum_size = Vector2(20, 20)
	_summary_lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_summary_lamp)

	var summary_column := VBoxContainer.new()
	summary_column.add_theme_constant_override("separation", 0)
	summary_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(summary_column)

	_summary_label = Label.new()
	_summary_label.text = "Checking..."
	summary_column.add_child(_summary_label)

	_scope_label = Label.new()
	_scope_label.add_theme_font_size_override("font_size", 10)
	summary_column.add_child(_scope_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_checked_label = Label.new()
	_checked_label.add_theme_font_size_override("font_size", 10)
	_checked_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_checked_label)

	var recheck := Button.new()
	recheck.text = "Re-check"
	recheck.tooltip_text = (
		"Re-run every check now, including the level scan, which is too slow to"
		+ "\nrun on the panel's own refresh."
	)
	recheck.pressed.connect(_on_recheck_pressed)
	header.add_child(recheck)

	var report := Button.new()
	report.text = "Report a Problem"
	report.tooltip_text = (
		"Open the bug form in your browser, filled in with the versions, the level's"
		+ "\nstats and the latest log lines. Nothing is sent until you submit it there."
	)
	report.pressed.connect(func(): action_requested.emit("report_problem"))
	header.add_child(report)

	var open_dock := Button.new()
	open_dock.text = "Open Editor Dock"
	open_dock.tooltip_text = "Bring the HammerForge dock forward — brushes, painting, entities."
	open_dock.pressed.connect(func(): action_requested.emit("focus_dock"))
	header.add_child(open_dock)


func _build_status_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Status"
	page.add_theme_constant_override("separation", 4)
	_tabs.add_child(page)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_inset(scroll))

	_status_list = VBoxContainer.new()
	_status_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_status_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	page.add_child(_inset(footer))

	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 14)
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_legend)
	_build_legend()

	# The board is short enough to read whole, but a bottom panel dragged down
	# to a strip is not. This hides what is already fine rather than reordering
	# the rows, which would move a button out from under the cursor.
	_attention_only = CheckButton.new()
	_attention_only.text = "Needs attention only"
	_attention_only.focus_mode = Control.FOCUS_NONE
	_attention_only.tooltip_text = "Hide the checks that are already fine."
	_attention_only.toggled.connect(_on_attention_only_toggled)
	footer.add_child(_attention_only)


func _build_legend() -> void:
	# Without this the colours are a convention the reader has to infer, and the
	# grey lamp in particular reads as "broken" rather than "not measured".
	var entries := [
		[HFStatusBoardType.Severity.OK, "Nothing to do"],
		[HFStatusBoardType.Severity.WARN, "Works, but will cost you later"],
		[HFStatusBoardType.Severity.PROBLEM, "Will not do what you expect"],
		[HFStatusBoardType.Severity.UNKNOWN, "Not measured yet"],
	]
	for entry in entries:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		var lamp := HFStatusLampType.new()
		lamp.custom_minimum_size = Vector2(12, 12)
		lamp.severity = entry[0]
		lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(lamp)
		var label := Label.new()
		label.text = entry[1]
		label.add_theme_font_size_override("font_size", 10)
		item.add_child(label)
		_legend.add_child(item)


## Every entity class in the level with its count, point entities and brush
## entities both, in the whole level, the active cordons or one visgroup (#1709).
## A click on a class selects every one of it. Export Entities writes the table.
func _build_entities_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Entities"
	page.add_theme_constant_override("separation", 4)
	_tabs.add_child(page)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(_inset(bar))
	var scope_label := Label.new()
	scope_label.text = "Count in"
	bar.add_child(scope_label)
	_census_scope = OptionButton.new()
	_census_scope.tooltip_text = "Count the whole level, what stands inside the active cordons, or one visgroup."
	_census_scope.item_selected.connect(func(_index: int): refresh_census())
	bar.add_child(_census_scope)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var export := Button.new()
	export.text = "Export Entities..."
	export.tooltip_text = "Write every entity in this scope to a CSV, one row each, one column per property."
	export.pressed.connect(func(): action_requested.emit("export_entities"))
	bar.add_child(export)

	_census_tree = Tree.new()
	_census_tree.columns = 2
	_census_tree.column_titles_visible = true
	_census_tree.set_column_title(0, "Class")
	_census_tree.set_column_title(1, "Count")
	_census_tree.set_column_expand(1, false)
	_census_tree.set_column_custom_minimum_width(1, 64)
	_census_tree.hide_root = true
	_census_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_census_tree.tooltip_text = "Click a class to select every one of it."
	_census_tree.item_selected.connect(_on_census_picked)
	page.add_child(_inset(_census_tree))


## What the Entities tab counts in: "" for the whole level, or a scope
## `HFEntityCensus.entities()` takes.
func census_scope() -> String:
	if _census_scope == null or _census_scope.selected < 0:
		return ""
	return str(_census_scope.get_item_metadata(_census_scope.selected))


## Fill the Entities tab from the level as it is now.
func refresh_census() -> void:
	if _census_tree == null:
		return
	var root = _dock.get("level_root") if _dock != null and is_instance_valid(_dock) else null
	if root != null and not is_instance_valid(root):
		root = null
	var keep := census_scope()
	var scopes: Array = [["Whole level", ""], ["Inside cordons", HFEntityCensusType.SCOPE_CORDONS]]
	if root and root.visgroup_system:
		for vg_name in root.visgroup_system.get_visgroup_names():
			scopes.append(["Visgroup: %s" % vg_name, HFEntityCensusType.VISGROUP_SCOPE + vg_name])
	var rows: Array = HFEntityCensusType.table(root, keep) if root else []
	# Rebuilt only when it changed: the poll comes every second, and a rebuild
	# drops the row the mapper is pointing at.
	if [scopes, rows, keep] == _census_shown:
		return
	_census_shown = [scopes, rows, keep]
	_census_scope.clear()
	for i in scopes.size():
		_census_scope.add_item(scopes[i][0], i)
		_census_scope.set_item_metadata(i, scopes[i][1])
		if scopes[i][1] == keep:
			_census_scope.select(i)
	_census_tree.clear()
	var top := _census_tree.create_item()
	for row in rows:
		var item := _census_tree.create_item(top)
		item.set_text(0, str(row[0]))
		item.set_metadata(0, str(row[0]))
		item.set_text(1, str(row[1]))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)


## Deferred: the action refreshes this panel, and the Tree must not change under
## its own selection signal.
## Every note in the level under its kind, open ones counted (#1700). A click
## selects the note, so Focus Selection frames it.
func _build_notes_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Notes"
	page.add_theme_constant_override("separation", 4)
	_tabs.add_child(page)
	_notes_tree = Tree.new()
	_notes_tree.columns = 3
	_notes_tree.column_titles_visible = true
	_notes_tree.set_column_title(0, "Note")
	_notes_tree.set_column_title(1, "Author")
	_notes_tree.set_column_title(2, "Done")
	_notes_tree.set_column_expand(2, false)
	_notes_tree.set_column_custom_minimum_width(2, 56)
	_notes_tree.hide_root = true
	_notes_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_tree.tooltip_text = "Click a note to select it. F frames it in the viewport."
	_notes_tree.item_selected.connect(_on_note_picked)
	page.add_child(_inset(_notes_tree))


## Fill the Notes tab from the level as it is now.
func refresh_notes() -> void:
	if _notes_tree == null:
		return
	var root = _dock.get("level_root") if _dock != null and is_instance_valid(_dock) else null
	if root != null and not is_instance_valid(root):
		root = null
	var rows: Array = []
	for note in HFNotesType.notes(root) if root else []:
		rows.append(
			[note["kind"], note["title"], note["author"], note["done"], note["path"], note["body"]]
		)
	# Rebuilt only when it changed, so the row under the pointer stays.
	if rows == _notes_shown:
		return
	_notes_shown = rows
	_notes_tree.clear()
	var top := _notes_tree.create_item()
	for kind in HFNotesType.KINDS:
		var mine := rows.filter(func(row): return row[0] == kind)
		if mine.is_empty():
			continue
		var open := mine.filter(func(row): return not row[3]).size()
		var group := _notes_tree.create_item(top)
		group.set_text(0, "%s (%d open)" % [kind, open])
		group.set_selectable(0, false)
		group.set_selectable(1, false)
		group.set_selectable(2, false)
		for row in mine:
			var item := _notes_tree.create_item(group)
			item.set_text(0, str(row[1]))
			item.set_tooltip_text(0, str(row[5]) if str(row[5]) != "" else str(row[1]))
			item.set_text(1, str(row[2]))
			item.set_text(2, "yes" if row[3] else "")
			item.set_metadata(0, str(row[4]))
			if row[3]:
				for column in 3:
					item.set_custom_color(column, HFThemeUtils.muted_text(_base_control))


func _on_note_picked() -> void:
	var item := _notes_tree.get_selected()
	if item != null and item.get_metadata(0) != null:
		action_requested.emit.call_deferred("select_note:" + str(item.get_metadata(0)))


func _on_census_picked() -> void:
	var item := _census_tree.get_selected()
	if item != null:
		action_requested.emit.call_deferred("select_entity_class:" + str(item.get_metadata(0)))


## What changed between the open level and a file (#1701), a row each.
func _build_compare_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Compare"
	page.add_theme_constant_override("separation", 4)
	_tabs.add_child(page)
	var head := HBoxContainer.new()
	page.add_child(_inset(head))
	_compare_label = Label.new()
	_compare_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_compare_label)
	_compare_end = Button.new()
	_compare_end.text = "End Compare"
	_compare_end.tooltip_text = "Take the compare's outlines off the viewport"
	_compare_end.pressed.connect(func(): action_requested.emit("compare_end"))
	head.add_child(_compare_end)
	_compare_tree = Tree.new()
	_compare_tree.hide_root = true
	_compare_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_compare_tree.tooltip_text = "Click a change to select what it names. F frames it in the viewport."
	_compare_tree.item_selected.connect(_on_compare_picked)
	page.add_child(_inset(_compare_tree))
	clear_compare()


## Show a compare with `file_name`: `result` is `HFLevelCompare.compare()`'s.
func show_compare(file_name: String, result: Dictionary) -> void:
	if _compare_tree == null:
		return
	var rows: Array = result.get("rows", [])
	_compare_label.text = (
		"Against %s: %s" % [file_name, rows[0]["text"] if not rows.is_empty() else "No changes"]
	)
	_compare_end.disabled = false
	_compare_tree.clear()
	var top := _compare_tree.create_item()
	for row in rows.slice(1):
		var item := _compare_tree.create_item(top)
		item.set_text(0, str(row["text"]))
		item.set_metadata(0, str(row["ref"]))
		item.set_selectable(0, str(row["ref"]) != "")
	var page := _compare_tree.get_parent().get_parent()
	_tabs.current_tab = page.get_index()


func clear_compare() -> void:
	if _compare_tree == null:
		return
	_compare_tree.clear()
	_compare_label.text = "Nothing compared. File > Compare With... in the dock compares the open level with a .hflevel."
	_compare_end.disabled = true


## The rows the Compare tab shows, as text.
func compare_rows() -> PackedStringArray:
	var out: PackedStringArray = []
	if _compare_tree == null or _compare_tree.get_root() == null:
		return out
	for item in _compare_tree.get_root().get_children():
		out.append(item.get_text(0))
	return out


func _on_compare_picked() -> void:
	var item := _compare_tree.get_selected()
	if item != null and str(item.get_metadata(0)) != "":
		action_requested.emit.call_deferred("compare_pick:" + str(item.get_metadata(0)))


func _build_controls_tab() -> void:
	var page := MarginContainer.new()
	page.name = "Controls"
	_inset_margins(page)
	_tabs.add_child(page)
	_controls = HFConsoleControlsType.new()
	_controls.setting_changed.connect(_on_setting_changed)
	page.add_child(_controls)


## The command line under the tabs, which the plugin wires up.
func command_line():
	return _command_line


func _build_log_tab() -> void:
	var page := MarginContainer.new()
	page.name = "Log"
	_inset_margins(page)
	_tabs.add_child(page)
	_log_view = HFConsoleLogViewType.new()
	page.add_child(_log_view)


## Tab bodies sit flush against the panel edges otherwise, which puts the last
## button of a row underneath the scrollbar.
static func _inset_margins(margin: MarginContainer) -> void:
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)


static func _inset(control: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	_inset_margins(margin)
	margin.size_flags_vertical = control.size_flags_vertical
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(control)
	return margin


func _vertical_rule() -> Control:
	var rule := VSeparator.new()
	rule.custom_minimum_size.y = 22
	return rule


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------


func set_dock(dock) -> void:
	_dock = dock
	if _controls:
		_controls.set_dock(dock)
	refresh(true)


func set_prefs(prefs) -> void:
	_prefs = prefs
	if _controls:
		_controls.set_prefs(prefs)


func set_log(buffer) -> void:
	_log = buffer
	if _log_view:
		_log_view.set_log(buffer)
	refresh(false)


func set_theme_source(base_control: Control) -> void:
	_base_control = base_control
	_apply_theme()


## Called by the plugin when something happened that the board should notice at
## once rather than on its next beat — a finished bake, a new scene, a level
## created. Always goes deep: these are exactly the moments the slow numbers
## have changed.
func note_event(message: String = "") -> void:
	if message != "" and _log:
		_log.info(message, "console")
	refresh(true)


## Cache a validation result so the Level check row can report it without the
## panel re-scanning the level on its own schedule.
func record_validation(issues: Array) -> void:
	_cached["validation_run"] = true
	_cached["validation_issues"] = issues.duplicate()
	_cached["validation_stamp"] = Time.get_time_string_from_system()
	refresh(false)


## What a session that died left behind, or {} to take the row away (#1654).
func record_crash(report: Dictionary) -> void:
	if report.is_empty():
		_cached.erase("crash_report")
	else:
		_cached["crash_report"] = report.duplicate()
	refresh(false)


func crash_report() -> Dictionary:
	return _cached.get("crash_report", {})


## A newer HammerForge, `{"latest", "current"}`, or {} to take the row away
## (#1656).
func record_update(notice: Dictionary) -> void:
	if notice.is_empty():
		_cached.erase("update_notice")
	else:
		_cached["update_notice"] = notice.duplicate()
	refresh(false)


func update_notice() -> Dictionary:
	return _cached.get("update_notice", {})


## The End Editor row, for trying the crash report by hand.
func record_crash_test(enabled: bool) -> void:
	_cached["crash_test"] = enabled
	refresh(false)


## The board's headline without drawing anything, for the viewport strip. Kept
## here rather than in the strip so both read the same evaluation.
func compute_summary() -> Dictionary:
	var root = _dock.get("level_root") if _dock != null and is_instance_valid(_dock) else null
	if root != null and not is_instance_valid(root):
		root = null
	var ctx := HFStatusBoardType.collect_context(root, _log, _cached, false)
	return HFStatusBoardType.summarise(HFStatusBoardType.evaluate(ctx))


func show_tab(tab: int) -> void:
	if _tabs and tab >= 0 and tab < _tabs.get_tab_count():
		_tabs.current_tab = tab


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------


func refresh(deep: bool = false) -> void:
	# TabContainer emits tab_changed as its first page is added, which lands here
	# before the rest of the tab bodies exist.
	if _status_list == null or _summary_lamp == null:
		return
	var root = _dock.get("level_root") if _dock != null and is_instance_valid(_dock) else null
	if root != null and not is_instance_valid(root):
		root = null
	var ctx := HFStatusBoardType.collect_context(root, _log, _cached, deep)
	if deep:
		_last_deep_context = ctx
	else:
		# Carry the last deep reading forward so the slow numbers do not blink
		# back to zero between deep passes.
		for key in ["vertex_estimate", "recommended_chunk_size"]:
			if _last_deep_context.has(key):
				ctx[key] = _last_deep_context[key]
	var checks := HFStatusBoardType.evaluate(ctx)
	# The header summary is what the reader sees with the panel collapsed to a
	# strip, so it always updates. The two tab bodies are only redrawn when
	# their tab is the one on screen; a tab change refreshes on the way in.
	_render_summary(HFStatusBoardType.summarise(checks), ctx, deep)
	var tab := _tabs.current_tab if _tabs else Tab.STATUS
	if tab == Tab.STATUS or _rows.is_empty():
		_render_checks(checks)
	if _controls and tab == Tab.CONTROLS:
		_controls.refresh()
	if tab == Tab.ENTITIES:
		refresh_census()
	if tab == Tab.NOTES:
		refresh_notes()


func _render_checks(checks: Array) -> void:
	var seen := {}
	for check in checks:
		var id := str(check["id"])
		seen[id] = true
		var row: HFStatusRow = _rows.get(id)
		if row == null:
			row = HFStatusRowType.new()
			row.action_requested.connect(_on_row_action)
			_status_list.add_child(row)
			_rows[id] = row
			_row_order.append(id)
		row.apply_check(check, _base_control)
		row.visible = not _hide_when_fine or _needs_attention(check)
		if id == "log":
			_log_severity = int(check.get("severity", HFStatusBoardType.Severity.OK))
	# A check that stops being produced should not leave its row behind.
	for id in _row_order.duplicate():
		if not seen.has(id):
			var stale: HFStatusRow = _rows[id]
			_status_list.remove_child(stale)
			stale.queue_free()
			_rows.erase(id)
			_row_order.erase(id)


func _render_summary(summary: Dictionary, ctx: Dictionary, deep: bool) -> void:
	var severity := int(summary["severity"])
	_summary_lamp.theme_source = _base_control
	_summary_lamp.severity = severity
	_summary_label.text = str(summary["label"])
	_summary_label.add_theme_color_override(
		"font_color", HFStatusLampType.color_for(severity, _base_control)
	)

	var scope := "No LevelRoot in the open scene"
	if bool(ctx.get("has_root", false)):
		var bits := PackedStringArray()
		bits.append(str(ctx.get("root_name", "LevelRoot")))
		bits.append("%d brushes" % int(ctx.get("brush_count", 0)))
		bits.append("%d entities" % int(ctx.get("entity_count", 0)))
		var vertices := int(ctx.get("vertex_estimate", 0))
		if vertices > 0:
			bits.append("~%d verts" % vertices)
		var paint_bytes := int(ctx.get("paint_memory_bytes", 0))
		if paint_bytes > 0:
			bits.append("%s paint" % String.humanize_size(paint_bytes))
		scope = " · ".join(bits)
	_scope_label.text = scope
	_scope_label.add_theme_color_override("font_color", HFThemeUtils.muted_text(_base_control))

	if deep:
		_checked_label.text = "Checked %s" % Time.get_time_string_from_system()
		_checked_label.add_theme_color_override(
			"font_color", HFThemeUtils.muted_text(_base_control)
		)
	_version_label.add_theme_color_override("font_color", HFThemeUtils.muted_text(_base_control))


func _apply_theme() -> void:
	var dark := HFThemeUtils.is_dark_theme(_base_control)
	var path := LOCKUP_DARK if dark else LOCKUP_LIGHT
	if _lockup and ResourceLoader.exists(path):
		_lockup.texture = load(path)
	if _summary_lamp:
		_summary_lamp.theme_source = _base_control
	for id in _rows.keys():
		_rows[id].refresh_theme(_base_control)
	for item in _legend.get_children():
		for child in item.get_children():
			if child is HFStatusLamp:
				child.theme_source = _base_control
			elif child is Label:
				child.add_theme_color_override("font_color", HFThemeUtils.muted_text(_base_control))
	if _controls:
		_controls.set_theme_source(_base_control)
	if _log_view:
		_log_view.set_theme_source(_base_control)


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------


func _on_visibility_changed() -> void:
	if not _poll:
		return
	# A collapsed bottom panel is hidden, and polling a panel nobody is looking
	# at is pure cost. Coming back into view is also the right moment to pay for
	# a deep pass, since anything could have changed while it was away.
	if is_visible_in_tree():
		_poll.start()
		refresh(true)
	else:
		_poll.stop()


func _on_poll() -> void:
	_tick += 1
	refresh(_tick % DEEP_POLL_TICKS == 0)


func _on_tab_changed(_tab: int) -> void:
	# Whichever body just came forward has been going unrefreshed while it was
	# hidden, so it is redrawn on arrival — and a deep pass is affordable here
	# because a tab change is a deliberate act, not a timer.
	refresh(true)


func _on_attention_only_toggled(pressed: bool) -> void:
	_hide_when_fine = pressed
	refresh(false)


static func _needs_attention(check: Dictionary) -> bool:
	var severity := int(check.get("severity", HFStatusBoardType.Severity.UNKNOWN))
	return (
		severity == HFStatusBoardType.Severity.WARN
		or severity == HFStatusBoardType.Severity.PROBLEM
	)


func _on_recheck_pressed() -> void:
	action_requested.emit("validate")


func _on_row_action(action_id: String) -> void:
	if action_id == "show_notes":
		show_tab(Tab.NOTES)
		refresh_notes()
		return
	if action_id == "open_log":
		show_tab(Tab.LOG)
		if _log_view:
			# The row said "2 errors". Landing on a full buffer and asking the
			# reader to find them again would waste the click.
			if _log_severity == HFStatusBoardType.Severity.PROBLEM:
				_log_view.isolate_level(HFConsoleLogType.Level.ERROR)
			elif _log_severity == HFStatusBoardType.Severity.WARN:
				_log_view.isolate_level(HFConsoleLogType.Level.WARN)
			_log_view.focus_search()
		return
	action_requested.emit(action_id)


func _on_setting_changed(label: String, value: Variant) -> void:
	if _log:
		_log.info("%s set to %s" % [label, _describe(value)], "settings")
	refresh(false)


static func _describe(value: Variant) -> String:
	if value is bool:
		return "on" if value else "off"
	if value is float and is_equal_approx(value, roundf(value)):
		return str(int(value))
	return str(value)


static func _read_version() -> String:
	var config := ConfigFile.new()
	if config.load(PLUGIN_CFG) != OK:
		return ""
	return "v%s" % str(config.get_value("plugin", "version", "?"))
