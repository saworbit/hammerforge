@tool
extends RefCounted
## Adjust Last (#1867): change the settings of the command that just ran.
##
## Hollow at the wrong wall thickness, a clip in the wrong place, an array one
## copy too long: the way back was Ctrl+Z, change the dock, run it again. Now the
## command's call site notes what it ran, with its settings and how to run it
## again with others, and the panel in the corner of the viewport shows those
## settings as controls built from the command's `params`. Changing one undoes the
## step and makes it again with the new value, so the history holds one step for
## it, and one Ctrl+Z still gives back what was there before the command.
##
## The run is kept on the plugin as `last_run`: `{id, settings, version, recipe}`,
## with `version` the scene history's version after its step. A step that is not
## its own, a version the run did not leave, closes the panel; the run is kept so
## Adjust Last can say why it has nothing to change.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFPluginOverlays = preload("plugin_overlays.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFAdjustLastPanel = preload("ui/hf_adjust_last_panel.gd")
const HFUndoNavType = preload("ui/hf_undo_nav.gd")

## Settings whose amount adds up when the same command collates into one step,
## as held arrow keys or repeated R presses do: the step holds them all.
const ADDS_UP := {"nudge": ["offset"], "rotate_cw": ["angle"], "rotate_ccw": ["angle"]}
## Where named settings are kept in the preferences.
const PRESETS_PREF := "command_presets"


## Note that `id` ran with `settings` and its step has landed. `recipe` says how
## to make the step again with other settings: `{action, method, args, scope_ids,
## scope_paths, absolute_redo}`, `args` a Callable taking the settings and giving
## the method's arguments. A command that can refuse a value adds `check`, a
## Callable taking the settings and the level and giving an `HFOpResult`, which is
## asked before the step is undone (#1995). A repeat of the same command on the
## same targets that collated into the step before adds to it.
static func note(plugin: Object, id: String, settings: Dictionary, recipe: Dictionary) -> void:
	if plugin == null or HFCommandRegistry.params(id).is_empty():
		return
	var version := _version(plugin)
	var run: Dictionary = plugin.get("last_run") if plugin.get("last_run") is Dictionary else {}
	var kept := settings.duplicate(true)
	if (
		not run.is_empty()
		and str(run.get("id", "")) == id
		and int(run.get("version", -2)) == version
		and run.get("targets") == _targets(recipe)
	):
		for key in ADDS_UP.get(id, []):
			if kept.has(key) and (run["settings"] as Dictionary).has(key):
				kept[key] = run["settings"][key] + kept[key]
	(
		plugin
		. set(
			"last_run",
			{
				"id": id,
				"settings": kept,
				"version": version,
				"recipe": recipe,
				"targets": _targets(recipe),
			}
		)
	)
	show(plugin)


## Show the last run's settings, or say why there are none to change.
static func show(plugin: Object) -> bool:
	var run: Dictionary = plugin.get("last_run") if plugin.get("last_run") is Dictionary else {}
	if run.is_empty() or int(run.get("version", -2)) != _version(plugin):
		_say(plugin, "Nothing to adjust: no command with settings is the last step", 1)
		return false
	var panel := _panel(plugin)
	var id := str(run["id"])
	panel.show_command(
		HFCommandRegistry.label(id),
		HFCommandRegistry.params(id),
		run["settings"],
		_preset_names(plugin, id)
	)
	HFPluginOverlays.place_viewport_overlay(plugin, panel)
	return true


static func close(plugin: Object) -> void:
	var panel = plugin.get("_adjust_last_panel")
	if panel is Control and is_instance_valid(panel):
		panel.visible = false


## A step landed or was undone. One the last run did not make closes the panel.
static func on_version_changed(plugin: Object) -> void:
	if plugin == null or bool(plugin.get("_adjusting_last")):
		return
	var run: Dictionary = plugin.get("last_run") if plugin.get("last_run") is Dictionary else {}
	if run.is_empty() or int(run.get("version", -2)) != _version(plugin):
		close(plugin)


## Make the last run's step again with `key` at `value`: undo it, and run it with
## the new settings, as one step in its place. False when the last step is not
## the run's own, or the command refuses the value, and nothing changes. A
## coroutine: the undo frees what it takes away at the end of the frame, so the
## step is made again on the next one. A change asked for while one is being
## made is made after it, the last one asked for winning, as a dragged spin box
## asks many times.
static func adjust(plugin: Object, key: String, value: Variant) -> bool:
	var run: Dictionary = plugin.get("last_run") if plugin.get("last_run") is Dictionary else {}
	if run.is_empty():
		return false
	if bool(plugin.get("_adjusting_last")):
		var pending: Dictionary = run.get(
			"pending", (run["settings"] as Dictionary).duplicate(true)
		)
		pending[key] = value
		run["pending"] = pending
		return true
	var root: Node = plugin.call("_get_level_root")
	var history := _history(plugin, root)
	if root == null or history == null:
		return false
	if history.get_version() != int(run["version"]):
		close(plugin)
		return false
	var settings: Dictionary = (run["settings"] as Dictionary).duplicate(true)
	settings[key] = value
	return await _run_again(plugin, root, history, run, settings)


## The settings kept as `preset_name` for the last run's command, on the panel
## and in a step in place of the run's own.
static func pick_preset(plugin: Object, preset_name: String) -> bool:
	var run: Dictionary = plugin.get("last_run") if plugin.get("last_run") is Dictionary else {}
	if run.is_empty():
		return false
	var presets: Dictionary = _presets(plugin).get(str(run["id"]), {})
	if not presets.has(preset_name):
		return false
	var root: Node = plugin.call("_get_level_root")
	var history := _history(plugin, root)
	if root == null or history == null or history.get_version() != int(run["version"]):
		close(plugin)
		return false
	if bool(plugin.get("_adjusting_last")):
		return false
	var settings: Dictionary = (run["settings"] as Dictionary).duplicate(true)
	settings.merge(_from_storable(str(run["id"]), presets[preset_name]), true)
	return await _run_again(plugin, root, history, run, settings)


## Keep the last run's settings as `preset_name`, in the preferences.
static func save_preset(plugin: Object, preset_name: String) -> void:
	var run: Dictionary = plugin.get("last_run") if plugin.get("last_run") is Dictionary else {}
	var prefs = plugin.get("_user_prefs")
	if run.is_empty() or prefs == null or preset_name.strip_edges() == "":
		return
	var all := _presets(plugin).duplicate(true)
	var mine: Dictionary = all.get(str(run["id"]), {})
	mine[preset_name] = _storable(run["settings"])
	all[str(run["id"])] = mine
	prefs.set_pref(PRESETS_PREF, all)
	prefs.save()
	show(plugin)


static func _run_again(
	plugin: Object, root: Node, history: UndoRedo, run: Dictionary, settings: Dictionary
) -> bool:
	var recipe: Dictionary = run["recipe"]
	# Asked before the undo. A value the command refuses would take its step away
	# and leave an empty one in its place, so the level and the panel keep what
	# they had, and the refusal says why (#1995).
	var refusal := _refusal(recipe, settings, root)
	if refusal != "":
		_say(plugin, refusal, 1)
		var shown = plugin.get("_adjust_last_panel")
		if shown is Control and is_instance_valid(shown):
			shown.fill(run["settings"])
		return false
	plugin.set("_adjusting_last", true)
	history.undo()
	# What the undo took away is freed at the end of this frame, and a capture
	# before then would still hold it.
	if plugin is Node and (plugin as Node).is_inside_tree():
		await (plugin as Node).get_tree().process_frame
	if not is_instance_valid(root):
		plugin.set("_adjusting_last", false)
		return false
	var args: Array = (recipe["args"] as Callable).call(settings)
	HFUndoHelper.commit(
		plugin.call("_get_undo_redo"),
		root,
		str(recipe["action"]),
		str(recipe["method"]),
		args,
		false,
		Callable(plugin, "_record_history"),
		"",
		bool(recipe.get("absolute_redo", true)),
		recipe.get("scope_ids", []),
		recipe.get("scope_paths", [])
	)
	# The dock's own controls take the settings too, so the next press of the
	# command and Repeat Last Command run what is in the level (#1896).
	var to_dock: Variant = recipe.get("dock")
	if to_dock is Callable and (to_dock as Callable).is_valid():
		(to_dock as Callable).call(settings)
	run["settings"] = settings
	run["version"] = history.get_version()
	plugin.set("last_run", run)
	if plugin.has_method("_note_run_adjusted"):
		plugin.call("_note_run_adjusted", str(run["id"]), settings, int(run["version"]))
	plugin.set("_adjusting_last", false)
	var panel = plugin.get("_adjust_last_panel")
	if panel is Control and is_instance_valid(panel):
		panel.fill(settings)
	if run.has("pending"):
		var next: Dictionary = run["pending"]
		run.erase("pending")
		if next != settings:
			return await _run_again(plugin, root, history, run, next)
	return true


## Why the recipe's command refuses `settings`, or "" when it takes them or the
## recipe has no check to ask.
static func _refusal(recipe: Dictionary, settings: Dictionary, root: Node) -> String:
	var check: Variant = recipe.get("check")
	if not (check is Callable and (check as Callable).is_valid()):
		return ""
	var verdict: Variant = (check as Callable).call(settings, root)
	if verdict is Object and not bool(verdict.get("ok")):
		return str(verdict.call("user_text"))
	return ""


static func _panel(plugin: Object) -> Control:
	var panel = plugin.get("_adjust_last_panel")
	if panel is Control and is_instance_valid(panel):
		return panel
	panel = HFAdjustLastPanel.new()
	var base = plugin.get("base_control")
	if base is Control:
		panel.theme = base.theme
	panel.setting_changed.connect(func(key, value): adjust(plugin, key, value))
	panel.preset_saved.connect(func(preset_name): save_preset(plugin, preset_name))
	panel.preset_picked.connect(func(preset_name): pick_preset(plugin, preset_name))
	panel.close_requested.connect(func(): close(plugin))
	plugin.set("_adjust_last_panel", panel)
	HFPluginOverlays.attach_viewport_overlay(plugin, panel)
	return panel


static func teardown(plugin: Object) -> void:
	var panel = plugin.get("_adjust_last_panel")
	if panel is Control and is_instance_valid(panel):
		HFPluginOverlays.detach_viewport_overlay(plugin, panel)
		panel.queue_free()
	plugin.set("_adjust_last_panel", null)


static func _targets(recipe: Dictionary) -> Array:
	return [Array(recipe.get("scope_ids", [])), Array(recipe.get("scope_paths", []))]


static func _history(plugin: Object, root: Node) -> UndoRedo:
	var manager = plugin.get("undo_redo_manager")
	if manager == null or root == null:
		return null
	return HFUndoNavType.get_scene_undo_redo(manager, root)


static func _version(plugin: Object) -> int:
	var history := _history(plugin, plugin.call("_get_level_root"))
	return history.get_version() if history else -1


static func _presets(plugin: Object) -> Dictionary:
	var prefs = plugin.get("_user_prefs")
	var kept = prefs.get_pref(PRESETS_PREF, {}) if prefs else {}
	return kept if kept is Dictionary else {}


static func _preset_names(plugin: Object, id: String) -> PackedStringArray:
	var names := PackedStringArray()
	for preset_name in _presets(plugin).get(id, {}) as Dictionary:
		names.append(str(preset_name))
	names.sort()
	return names


## Settings as the preferences file can hold them: a Vector3 as `[x, y, z]`.
static func _storable(settings: Dictionary) -> Dictionary:
	var out := {}
	for key in settings:
		var value: Variant = settings[key]
		out[key] = [value.x, value.y, value.z] if value is Vector3 else value
	return out


## Settings read back from the preferences file, a `vec3` setting's `[x, y, z]`
## made a Vector3 again.
static func _from_storable(id: String, kept: Dictionary) -> Dictionary:
	var out := kept.duplicate(true)
	for field_def in HFCommandRegistry.params(id):
		var key := str(field_def.get("key", ""))
		var value: Variant = out.get(key)
		if str(field_def.get("type", "")) == "vec3" and value is Array and value.size() == 3:
			out[key] = Vector3(float(value[0]), float(value[1]), float(value[2]))
	return out


static func _say(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock and is_instance_valid(dock) and dock.has_method("show_toast"):
		dock.show_toast(message, level)
