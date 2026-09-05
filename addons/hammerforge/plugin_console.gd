@tool
class_name HFPluginConsole
extends RefCounted
## Installs the HammerForge Console into the editor, and routes the buttons on
## it back to the handlers that already exist on the dock.
##
## Three pieces of editor surface, all of them optional to the rest of the
## plugin — if any of this fails the editor keeps working, it just gets less
## HammerForge branding:
##
##   * a bottom-panel button carrying the HammerForge mark, which is the thing
##     that makes the addon findable at all
##   * the mark on the left dock's tab, so the dock is identifiable as ours
##     rather than reading as a generic "Dock"
##   * a warning sink, so anything HFLog raises reaches the Console's Log tab
##     instead of only Godot's shared Output panel

const HFConsolePanelType = preload("ui/hf_console_panel.gd")
const HFConsoleLogType = preload("hf_console_log.gd")

const PANEL_TITLE := "HammerForge"
const ICON_PATH := "res://addons/hammerforge/icon.svg"

# ---------------------------------------------------------------------------
# Install / teardown
# ---------------------------------------------------------------------------


static func setup(plugin: Object) -> void:
	if plugin == null:
		return
	var log_buffer = HFConsoleLogType.shared()
	HFLog.set_sink(log_buffer)

	var panel = HFConsolePanelType.new()
	plugin.set("console_panel", panel)
	panel.set_log(log_buffer)
	panel.set_theme_source(plugin.get("base_control"))
	panel.set_prefs(plugin.get("_user_prefs"))
	panel.set_dock(plugin.get("dock"))
	panel.action_requested.connect(Callable(plugin, "_on_console_action"))

	var button = plugin.add_control_to_bottom_panel(panel, PANEL_TITLE)
	plugin.set("console_button", button)
	apply_icons(plugin)
	log_buffer.info("HammerForge %s ready." % _version(), "plugin")


static func teardown(plugin: Object) -> void:
	if plugin == null:
		return
	HFLog.set_sink(null)
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel):
		if panel.action_requested.is_connected(Callable(plugin, "_on_console_action")):
			panel.action_requested.disconnect(Callable(plugin, "_on_console_action"))
		plugin.remove_control_from_bottom_panel(panel)
		panel.queue_free()
	plugin.set("console_panel", null)
	plugin.set("console_button", null)


## Stamp the HammerForge mark onto the bottom-panel button and the dock tab.
## Re-run whenever the editor theme changes, because the editor rebuilds its
## tab bars around a theme change and drops icons set from outside.
static func apply_icons(plugin: Object) -> void:
	if plugin == null:
		return
	var icon := _icon()
	if icon == null:
		return
	var button = plugin.get("console_button")
	if button and is_instance_valid(button):
		button.icon = icon
		# The editor hands back the bottom-panel button with no text of its own,
		# so an icon-only button is what a first-time user would be looking for.
		if button.text == "":
			button.text = PANEL_TITLE
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and plugin.has_method("set_dock_tab_icon"):
		plugin.set_dock_tab_icon(dock, icon)


## Bring the dock's tab forward. The Console's "Open Editor Dock" button is
## often the first thing a new user presses, and a dock that is present but
## behind another tab looks like nothing happened.
static func focus_dock(plugin: Object) -> void:
	var dock = plugin.get("dock") if plugin else null
	if dock == null or not is_instance_valid(dock) or not dock.is_inside_tree():
		return
	var container = dock.get_parent()
	if container is TabContainer:
		var index: int = container.get_tab_idx_from_control(dock)
		if index >= 0:
			container.current_tab = index


static func _icon() -> Texture2D:
	if not ResourceLoader.exists(ICON_PATH):
		return null
	var resource = load(ICON_PATH)
	return resource if resource is Texture2D else null


static func _version() -> String:
	var config := ConfigFile.new()
	if config.load("res://addons/hammerforge/plugin.cfg") != OK:
		return ""
	return str(config.get_value("plugin", "version", ""))


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------


## Every action on the Status board resolves to a handler the dock already has.
## The console deliberately owns none of these behaviours — it is a place to
## see them from, not a second implementation of them.
static func handle_action(plugin: Object, action_id: String) -> void:
	if plugin == null:
		return
	var panel = plugin.get("console_panel")
	var dock = plugin.get("dock")
	if dock != null and not is_instance_valid(dock):
		dock = null

	match action_id:
		"focus_dock":
			focus_dock(plugin)
		"create_starter":
			if dock and dock.has_method("_on_create_level_root"):
				dock._on_create_level_root(true)
				_note(panel, "Created a starter level.")
		"bake":
			if dock and dock.has_method("_on_bake"):
				dock._on_bake()
				_note(panel, "Bake started.")
		"validate", "validate_fix":
			_run_validation(plugin, action_id == "validate_fix")
		"apply_chunk_size":
			_apply_recommended_chunk_size(plugin)
		"load_palette":
			if dock and dock.has_method("_on_material_add"):
				dock._on_material_add()
		"add_spawn":
			if dock and dock.has_method("_on_spawn_auto_create"):
				dock._on_spawn_auto_create()
				_note(panel, "Added a player spawn.")
		"enable_autosave":
			_enable_autosave(plugin)
		"reveal_autosave":
			_reveal_autosave(plugin)
		_:
			HFConsoleLogType.shared().warn(
				"Console action '%s' has no handler." % action_id, "console"
			)
	if panel and is_instance_valid(panel):
		panel.refresh(true)


static func _run_validation(plugin: Object, auto_fix: bool) -> void:
	var panel = plugin.get("console_panel")
	var dock = plugin.get("dock")
	var root = dock.get("level_root") if dock and is_instance_valid(dock) else null
	if root == null or not is_instance_valid(root) or not root.has_method("validate_level"):
		if panel and is_instance_valid(panel):
			panel.record_validation([])
		return
	if auto_fix and dock and dock.has_method("_on_validate_fix"):
		dock._on_validate_fix()
	var result: Dictionary = root.validate_level(false)
	var issues: Array = result.get("issues", [])
	if panel and is_instance_valid(panel):
		panel.record_validation(issues)
	var buffer = HFConsoleLogType.shared()
	if issues.is_empty():
		buffer.info("Level check found no issues.", "check")
	else:
		buffer.warn(
			(
				"Level check found %d issue%s: %s"
				% [issues.size(), "" if issues.size() == 1 else "s", str(issues[0])]
			),
			"check"
		)


static func _apply_recommended_chunk_size(plugin: Object) -> void:
	var dock = plugin.get("dock")
	var root = dock.get("level_root") if dock and is_instance_valid(dock) else null
	if root == null or not is_instance_valid(root):
		return
	if not root.has_method("get_recommended_chunk_size"):
		return
	var recommended: float = root.get_recommended_chunk_size()
	if recommended <= 0.0:
		return
	# Through the dock's spinbox where there is one, so the dock's own handler
	# runs and its Advanced Bake section shows the new value too.
	var spin = dock.get("bake_chunk_size_spin") if dock else null
	if spin != null and is_instance_valid(spin):
		spin.value = recommended
	else:
		root.set("bake_chunk_size", recommended)
	HFConsoleLogType.shared().info("Chunk size set to %d." % int(recommended), "settings")


static func _enable_autosave(plugin: Object) -> void:
	var dock = plugin.get("dock")
	var check = dock.get("autosave_enabled") if dock and is_instance_valid(dock) else null
	if check != null and is_instance_valid(check):
		check.button_pressed = true
		return
	var root = dock.get("level_root") if dock and is_instance_valid(dock) else null
	if root != null and is_instance_valid(root):
		root.set("hflevel_autosave_enabled", true)


static func _reveal_autosave(plugin: Object) -> void:
	var dock = plugin.get("dock")
	var root = dock.get("level_root") if dock and is_instance_valid(dock) else null
	if root == null or not is_instance_valid(root):
		return
	var path_value = root.get("hflevel_autosave_path")
	var path := "" if path_value == null else str(path_value)
	if path == "":
		return
	var folder := ProjectSettings.globalize_path(path.get_base_dir())
	if folder != "" and DirAccess.dir_exists_absolute(folder):
		OS.shell_open(folder)
	else:
		HFConsoleLogType.shared().warn(
			"Autosave folder %s does not exist yet." % path.get_base_dir(), "autosave"
		)


static func _note(panel, message: String) -> void:
	if panel and is_instance_valid(panel):
		panel.note_event(message)
