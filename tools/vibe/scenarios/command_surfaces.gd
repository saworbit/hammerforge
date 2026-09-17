@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Every action name a surface can emit, against the one function that runs them.
##
## `HFPluginCommands.execute()` is the single dispatcher: the keymap, the radial
## menu, the viewport context menu, the hotkey palette, the context toolbar and
## the console all end up there with a string. A string on one side and not the
## other is a control that does nothing when pressed, or a command nobody can
## reach.
##
## Nothing here needs a level. It reads the action names out of the sources, so
## it stays true as surfaces are added -- `shortcut-surfaces` covers whether the
## HUD and the tooltips still *describe* a rebind correctly, which is the other
## half of the same question.

const COMMANDS_PATH := "res://addons/hammerforge/plugin_commands.gd"
const KEYMAP_PATH := "res://addons/hammerforge/hf_keymap.gd"
const RADIAL_PATH := "res://addons/hammerforge/ui/hf_radial_menu.gd"
const DOCK_PATH := "res://addons/hammerforge/dock.gd"


func id() -> String:
	return "command-surfaces"


func summary() -> String:
	return "every action a surface can emit against the dispatcher that runs it"


func run() -> void:
	var handled := _handled_actions()
	note("actions HFPluginCommands.execute() handles", handled.size())

	await _the_radial_menu(handled)
	await _the_keymap(handled)
	await _the_context_menu(handled)
	await _commands_no_surface_reaches(handled)


## The `match` arms of `execute()`. An arm can name several actions at once --
## `"extrude_up", "tool_extrude_up", "tool_extrude":` -- so a pattern that only
## reads the first name reports the rest as unhandled, which is a scenario
## finding bugs in itself.
func _handled_actions() -> Dictionary:
	var source := FileAccess.get_file_as_string(COMMANDS_PATH)
	var out: Dictionary = {}
	var arm := RegEx.create_from_string('^\\t+("[a-z_0-9]+"(,\\s*"[a-z_0-9]+")*):$')
	var name := RegEx.create_from_string('"([a-z_0-9]+)"')
	for line in source.split("\n"):
		var m := arm.search(line)
		if not m:
			continue
		for n in name.search_all(m.get_string(1)):
			out[n.get_string(1)] = true
	return out


func _names_from(path: String, pattern: String) -> Array[String]:
	var source := FileAccess.get_file_as_string(path)
	var out: Array[String] = []
	var re := RegEx.create_from_string(pattern)
	for m in re.search_all(source):
		var name := m.get_string(1)
		if not (name in out):
			out.append(name)
	return out


func _the_radial_menu(handled: Dictionary) -> void:
	note("-- the backtick radial menu --")
	var actions := _names_from(RADIAL_PATH, '"action"\\s*:\\s*"([a-z_0-9]+)"')
	note("segments", actions)
	var dead: Array[String] = []
	for a in actions:
		if not handled.has(a):
			dead.append(a)
	note("segments the dispatcher does not handle", dead)
	if not dead.is_empty():
		flag(
			"a radial menu segment names an action nothing runs",
			(
				"pressing %s in the pie does nothing at all -- `HFPluginCommands."
				+ "execute()` has no arm for it and the dispatcher's `match` has no "
				+ "default, so the press is swallowed with no message"
			) % str(dead)
		)


func _the_keymap(handled: Dictionary) -> void:
	note("-- the keymap --")
	var bindings := _names_from(KEYMAP_PATH, '(?m)^\\t\\t"([a-z_0-9]+)":\\s*\\{')
	note("bound actions", bindings.size())
	var labelled := _names_from(KEYMAP_PATH, '(?m)^\\t\\t"([a-z_0-9]+)":\\s*"')
	note("actions with a display label", labelled.size())

	var no_label: Array[String] = []
	for a in bindings:
		if not (a in labelled):
			no_label.append(a)
	# Recorded, not flagged: `label_for()` falls back to a capitalised id, so a
	# missing entry reads as "Grid increase" rather than as nothing.
	note("bound actions with no entry in the label table", no_label)

	# A binding for something the dispatcher cannot run. Some actions are handled
	# by the plugin's own input path rather than the dispatcher, so this is
	# recorded rather than flagged unless the name appears nowhere at all.
	var plugin_source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var overlays := FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin_overlays.gd"
	)
	var input_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin_input.gd"
	)
	var orphaned: Array[String] = []
	for a in bindings:
		if handled.has(a):
			continue
		var mentioned := (
			plugin_source.find('"%s"' % a) >= 0
			or overlays.find('"%s"' % a) >= 0
			or input_source.find('"%s"' % a) >= 0
		)
		if not mentioned:
			orphaned.append(a)
	note("bound actions no dispatcher and no input path names", orphaned)
	if not orphaned.is_empty():
		flag(
			"a key is bound to an action nothing anywhere runs",
			(
				"%s are in the keymap with a keycode, appear in the rebind dialog, and "
				+ "are named by neither `HFPluginCommands.execute()` nor the plugin's "
				+ "own input handling. Pressing them does nothing and rebinding them "
				+ "can take a key away from something that works"
			) % str(orphaned)
		)


func _the_context_menu(handled: Dictionary) -> void:
	note("-- the viewport context menu and the hotkey palette --")
	for path in [
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd",
		"res://addons/hammerforge/ui/hf_hotkey_palette.gd",
		"res://addons/hammerforge/ui/hf_context_toolbar.gd",
	]:
		if not FileAccess.file_exists(path):
			note("not present", path)
			continue
		# Three shapes across the three files: an `action = "name"` assignment, an
		# `action_requested.emit("name", ...)`, and the trailing argument to the
		# toolbar's button builder.
		var actions := _names_from(path, 'action\\s*=\\s*"([a-z_0-9]+)"')
		for a in _names_from(path, 'action_requested\\.emit\\("([a-z_0-9]+)"'):
			if not (a in actions):
				actions.append(a)
		for a in _names_from(path, '_add_tool_button\\([^\\n]*"([a-z_0-9]+)"\\)'):
			if not (a in actions):
				actions.append(a)
		note("%s names" % path.get_file(), actions)
		var dead: Array[String] = []
		for a in actions:
			if not handled.has(a):
				dead.append(a)
		if dead.is_empty():
			continue
		# An action name with no `add_item` behind it is a menu entry that does
		# not exist, which is different from a button that does nothing.
		var source := FileAccess.get_file_as_string(path)
		var unreachable: Array[String] = []
		var orphaned_ids: Array[String] = []
		for a in dead:
			var menu_id := _menu_id_for(source, a)
			if menu_id != "" and source.find("%s)" % menu_id) < 0:
				orphaned_ids.append("%s (%s)" % [a, menu_id])
			else:
				unreachable.append(a)
		if not orphaned_ids.is_empty():
			flag(
				"%s maps a menu id to an action and never adds the item" % path.get_file(),
				(
					"%s: the const, the `match` arm and the action name all exist and no "
					+ "`add_item()` call uses the id, so the entry is not in the menu and "
					+ "the action behind it has no way in"
				) % ", ".join(orphaned_ids)
			)
		if not unreachable.is_empty():
			flag(
				"%s offers actions the dispatcher does not handle" % path.get_file(),
				str(unreachable)
			)


## The `_ID_*` const whose `match` arm sets `action` to `name`, if there is one.
## The menu is written as a const per entry, an `add_item()` that uses the const,
## and a `match` that turns it back into an action string; a const that only
## appears in two of those three places is an entry nobody can click.
func _menu_id_for(source: String, action_name: String) -> String:
	var marker := 'action = "%s"' % action_name
	var at := source.find(marker)
	if at < 0:
		return ""
	var before := source.substr(0, at)
	var arm := before.rfind("_ID_")
	if arm < 0:
		return ""
	var tail := before.substr(arm)
	var end := tail.find(":")
	if end < 0:
		return ""
	return tail.substr(0, end).strip_edges()


## The other direction: a command with no way in.
func _commands_no_surface_reaches(handled: Dictionary) -> void:
	note("-- commands with no surface --")
	var surfaces: Array[String] = [
		KEYMAP_PATH,
		RADIAL_PATH,
		DOCK_PATH,
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd",
		"res://addons/hammerforge/ui/hf_hotkey_palette.gd",
		"res://addons/hammerforge/ui/hf_context_toolbar.gd",
		"res://addons/hammerforge/plugin_console.gd",
		"res://addons/hammerforge/plugin.gd",
		"res://addons/hammerforge/plugin_input.gd",
		"res://addons/hammerforge/plugin_overlays.gd",
	]
	var text := ""
	for path in surfaces:
		if FileAccess.file_exists(path):
			text += FileAccess.get_file_as_string(path)
	var unreachable: Array[String] = []
	for action in handled.keys():
		if text.find('"%s"' % action) < 0:
			unreachable.append(str(action))
	unreachable.sort()
	note("commands no surface in the plugin names", unreachable)
	if not unreachable.is_empty():
		flag(
			"%s commands exist that nothing can ask for" % unreachable.size(),
			(
				"`HFPluginCommands.execute()` implements %s, and no keymap entry, menu, "
				+ "palette, toolbar, radial segment, dock button or console command "
				+ "names them"
			) % str(unreachable)
		)
