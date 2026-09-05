@tool
class_name HFPluginConsole
extends RefCounted
## Installs the HammerForge Console into the editor, and routes the buttons on
## it back to the handlers that already exist on the dock.
##
## Four pieces of editor surface, all of them optional to the rest of the plugin
## — if any of this fails the editor keeps working, it just gets less
## HammerForge:
##
##   * a main screen, so HammerForge sits in the top switcher beside 2D, 3D and
##     Script wearing its own mark. That row is where Godot puts an addon with a
##     screen of its own, and it is the only place in the editor chrome that
##     actually draws a plugin icon
##   * the mark on the left dock tab, through the EditorDock wrapper Godot 4.7
##     puts around a docked control
##   * a lamp in the 3D viewport toolbar, because the Console is not on screen
##     while you are building
##   * a warning sink, so anything HFLog raises reaches the Console Log tab
##     instead of only Godot shared Output panel

const HFConsolePanelType = preload("ui/hf_console_panel.gd")
const HFConsoleLogType = preload("hf_console_log.gd")
const HFStatusStripType = preload("ui/hf_status_strip.gd")

const PANEL_TITLE := "HammerForge"
## The Scene-tree icon, drawn at about 16px, is the compact weight of the mark.
## The switcher draws its icon at the texture size, so that one is authored at
## 32 — the same size Godot own main screens and the other addons here use.
const ICON_PATH := "res://addons/hammerforge/icon.svg"
const EDITOR_ICON_PATH := "res://addons/hammerforge/branding/hf_mark_editor.svg"

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

	# A main screen owns the whole editor area, so the panel anchors to it and
	# starts hidden. Godot shows it through _make_visible when its button in the
	# top switcher is pressed.
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The main screen is a box container, so a child without expand flags gets
	# its minimum height and nothing more — which collapses the status board to
	# a strip and leaves the rest of the screen blank.
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.visible = false
	var main_screen := EditorInterface.get_editor_main_screen()
	if main_screen:
		main_screen.add_child(panel)

	var strip = HFStatusStripType.new()
	plugin.set("console_strip", strip)
	strip.set_theme_source(plugin.get("base_control"))
	strip.set_source(panel)
	strip.console_requested.connect(Callable(plugin, "_on_console_requested"))
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, strip)

	apply_icons(plugin)
	log_buffer.info("HammerForge %s ready." % _version(), "plugin")


static func teardown(plugin: Object) -> void:
	if plugin == null:
		return
	HFLog.set_sink(null)
	var strip = plugin.get("console_strip")
	if strip and is_instance_valid(strip):
		if strip.console_requested.is_connected(Callable(plugin, "_on_console_requested")):
			strip.console_requested.disconnect(Callable(plugin, "_on_console_requested"))
		plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, strip)
		strip.queue_free()
	plugin.set("console_strip", null)

	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel):
		if panel.action_requested.is_connected(Callable(plugin, "_on_console_action")):
			panel.action_requested.disconnect(Callable(plugin, "_on_console_action"))
		var main_screen := EditorInterface.get_editor_main_screen()
		if main_screen and panel.get_parent() == main_screen:
			main_screen.remove_child(panel)
		panel.queue_free()
	plugin.set("console_panel", null)


## Stamp the HammerForge mark onto the dock tab. Re-run whenever the editor
## theme changes, because the editor rebuilds its tab bars around a theme change
## and drops icons set from outside it.
##
## The main-screen icon is not set here. Godot asks for that through
## _get_plugin_icon() whenever it needs to draw the switcher.
static func apply_icons(plugin: Object) -> void:
	if plugin == null:
		return
	var icon := _icon()
	if icon == null:
		return
	var dock = plugin.get("dock")
	if dock == null or not is_instance_valid(dock):
		return
	if plugin.has_method("set_dock_tab_icon"):
		plugin.set_dock_tab_icon(dock, icon)
	# Godot 4.7 wraps a docked control in an EditorDock, and that wrapper draws
	# its icon only when told to. Left alone, a dock wide enough for its title
	# shows the title and nothing else.
	var wrapper = dock.get_parent()
	if wrapper and wrapper is EditorDock:
		wrapper.dock_icon = icon
		wrapper.force_show_icon = true


## Bring the dock tab forward and leave the Console behind. "Open Editor Dock"
## is often the first thing a new user presses, and a dock that is present but
## behind another tab, with the Console still filling the screen, looks like
## nothing happened at all.
static func focus_dock(plugin: Object) -> void:
	var dock = plugin.get("dock") if plugin else null
	if dock == null or not is_instance_valid(dock) or not dock.is_inside_tree():
		return
	EditorInterface.set_main_screen_editor("3D")
	var wrapper = dock.get_parent()
	if wrapper and wrapper is EditorDock:
		wrapper.make_visible()


## Raise the Console main screen. Sent by the viewport lamp.
static func open_console() -> void:
	EditorInterface.set_main_screen_editor(PANEL_TITLE)


## Godot calls this through _make_visible as the main-screen switcher moves.
static func set_console_visible(plugin: Object, visible: bool) -> void:
	if plugin == null:
		return
	var panel = plugin.get("console_panel")
	if panel and is_instance_valid(panel):
		panel.visible = visible


## The mark, for the main-screen switcher.
static func plugin_icon() -> Texture2D:
	var icon := _icon(EDITOR_ICON_PATH)
	return icon if icon else _icon()


static func _icon(path: String = ICON_PATH) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
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
