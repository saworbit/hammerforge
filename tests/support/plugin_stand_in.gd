extends RefCounted
## The real `plugin.gd`, built for a headless test.
##
## `EditorPlugin` can only be built by the editor, so this compiles the source of
## `plugin.gd` over `editor_plugin_stand_in.gd` and adds it to the tree, where its
## own `_enter_tree` builds the dock, HUD, palette and menus. Every rewrite is
## counted: if `plugin.gd` changes so that one no longer matches, `build()` says
## which and returns null instead of quietly running something else.

const PLUGIN_PATH := "res://addons/hammerforge/plugin.gd"
const BASE_PATH := "res://tests/support/editor_plugin_stand_in.gd"
const EditorPluginStandIn = preload(BASE_PATH)
const ADDON_DIR := "res://addons/hammerforge/"
const COMPILED_PATH := "res://tests/support/plugin_stand_in.compiled.gd"

## [find, replace, times]. `times` is how often `plugin.gd` holds `find`; 0 means
## at least once. Run in order: the gizmo line goes before preloads are made
## absolute.
const REWRITES := [
	["extends EditorPlugin", 'extends "%s"' % BASE_PATH, 1],
	['preload("brush_gizmo_plugin.gd").new()', "_stand_in_gizmo_plugin()", 1],
	[
		'HFKeymap.load_or_default("user://hammerforge_keymap.json")',
		'HFKeymap.load_or_default("")',
		1
	],
	["HFUserPrefs.load_prefs()", "_stand_in_user_prefs()", 1],
	# The dock types these as the editor's own classes, so it gets neither, as in
	# every other dock test.
	["dock.set_editor_interface(get_editor_interface())", "dock.set_editor_interface(null)", 1],
	["dock.set_plugin(self)", "dock.set_plugin(null)", 1],
	["EditorInterface.", "get_editor_interface().", 0],
	['preload("', 'preload("%s' % ADDON_DIR, 0],
]

static var _script: GDScript = null
static var _error := ""


## The compiled stand-in, or null with `error()` saying why.
static func compiled() -> GDScript:
	if _script != null or _error != "":
		return _script
	var source := FileAccess.get_file_as_string(PLUGIN_PATH)
	if source.contains('preload("res://'):
		_error = "plugin.gd now has an absolute preload; the relative-preload rewrite needs a look"
		return null
	for rewrite in REWRITES:
		var find: String = rewrite[0]
		var times: int = rewrite[2]
		var found := source.count(find)
		if found == 0 or (times > 0 and found != times):
			_error = (
				"plugin.gd holds %d of %s, expected %s"
				% [found, find.strip_edges(), str(times) if times > 0 else "some"]
			)
			return null
		source = source.replace(find, rewrite[1])
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	if err != OK:
		_error = "the rewritten plugin.gd does not compile (error %d)" % err
		return null
	# A path of its own, so GUT can name it in a failure; nothing is written there.
	script.resource_path = COMPILED_PATH
	_script = script
	return _script


static func error() -> String:
	return _error


## A plugin in the tree under `parent`, set up by its own `_enter_tree`, with
## `scene_root` as the edited scene. With `with_undo` it commits through an undo
## manager stand-in, `plugin.stand_in_undo`; without, every action commits
## directly. Take it down with `teardown()`.
static func build(parent: Node, scene_root: Node, with_undo: bool = false) -> Node:
	var script := compiled()
	if script == null:
		return null
	var base_control := Control.new()
	base_control.name = "StandInBaseControl"
	parent.add_child(base_control)
	var plugin: Node = script.new()
	plugin.stand_in_editor.base_control = base_control
	plugin.stand_in_editor.scene_root = scene_root
	plugin.stand_in_editor.main_screen = base_control
	if with_undo:
		plugin.stand_in_undo = EditorPluginStandIn.FakeUndoRedoManager.new()
	parent.add_child(plugin)
	return plugin


## `_exit_tree` first, as the editor runs it on disabling the plugin, then the
## base control and anything still parked on it.
static func teardown(plugin: Node) -> void:
	if plugin == null or not is_instance_valid(plugin):
		return
	var base_control: Control = plugin.stand_in_editor.base_control
	var undo = plugin.stand_in_undo
	plugin.stand_in_editor.selection.clear()
	if plugin.get_parent():
		plugin.get_parent().remove_child(plugin)
	plugin.free()
	if base_control and is_instance_valid(base_control):
		if base_control.get_parent():
			base_control.get_parent().remove_child(base_control)
		base_control.free()
	# `UndoRedo` is an Object, so its histories go by hand, after everything that
	# listened to them.
	if undo != null:
		undo.free_histories()
