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
const HFConsoleLogType = preload("../hf_console_log.gd")
const HFStatusLampType = preload("hf_status_lamp.gd")
const HFStatusRowType = preload("hf_status_row.gd")
const HFConsoleControlsType = preload("hf_console_controls.gd")
const HFConsoleLogViewType = preload("hf_console_log_view.gd")

const LOCKUP_DARK := "res://addons/hammerforge/branding/hf_lockup_dark.svg"
const LOCKUP_LIGHT := "res://addons/hammerforge/branding/hf_lockup_light.svg"
const PLUGIN_CFG := "res://addons/hammerforge/plugin.cfg"

## Counts and flags are cheap enough to read every second.
const POLL_SECONDS := 1.0

## The level walks behind the vertex estimate and the chunk recommendation are
## not, so they refresh on this slower beat, plus whenever the reader asks.
const DEEP_POLL_TICKS := 10

enum Tab { STATUS, CONTROLS, LOG }

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
var _poll: Timer = null

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


func _build_controls_tab() -> void:
	var page := MarginContainer.new()
	page.name = "Controls"
	_inset_margins(page)
	_tabs.add_child(page)
	_controls = HFConsoleControlsType.new()
	_controls.setting_changed.connect(_on_setting_changed)
	page.add_child(_controls)


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
