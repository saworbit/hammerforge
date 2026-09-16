@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The custom-tool extension point: `HFToolRegistry` and `HFEditorTool`.
##
## `plugin.gd` scans `res://addons/hammerforge/tools/` on startup, calls `.new()`
## on every `.gd` file it finds there and registers whatever comes back that
## looks like a tool. That is the documented way to add a tool to HammerForge,
## and it is the one path in the plugin where third-party code is constructed
## by name.
##
## What is measured here: what the scan does with a file that is not a tool,
## what the registry does with an id it does not have, and whether a tool's own
## settings are held to the schema the dock builds its controls from.

const ToolRegistry = preload("res://addons/hammerforge/hf_tool_registry.gd")

## Written into a scratch directory and scanned the way plugin.gd scans.
const TOOL_DIR := "user://vibe_tools/"

const GOOD_TOOL := """@tool
extends HFEditorTool
func tool_id() -> int: return 101
func tool_name() -> String: return "Good"
func tool_shortcut_key() -> int: return KEY_F5
func get_settings_schema() -> Array:
	return [
		{"name": "count", "type": "int", "label": "Count", "default": 3, "min": 1, "max": 10},
		{"name": "mode", "type": "enum", "label": "Mode", "default": 0,
			"options": PackedStringArray(["A", "B"])},
	]
"""

const NODE_SCRIPT := """@tool
extends Node3D
func tool_id() -> int: return 102
"""

const RESOURCE_SCRIPT := """@tool
extends Resource
var marker := 1
"""


func id() -> String:
	return "tool-registry"


func summary() -> String:
	return "what the custom-tool scan constructs, and what the registry does with an unknown id"


func run() -> void:
	await _what_the_scan_constructs()
	await _activating_an_id_that_is_not_there()
	await _colliding_ids_and_shortcuts()
	await _settings_against_their_own_schema()


func _write_tool_dir(files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TOOL_DIR))
	var dir := DirAccess.open(TOOL_DIR)
	if dir:
		dir.list_dir_begin()
		var existing := dir.get_next()
		while existing != "":
			if not dir.current_is_dir():
				dir.remove(existing)
			existing = dir.get_next()
		dir.list_dir_end()
	for name in files:
		var f := FileAccess.open(TOOL_DIR.path_join(name), FileAccess.WRITE)
		if f:
			f.store_string(files[name])
			f.close()


## `load_external_tools()` calls `.new()` on every `.gd` file in the directory
## and only then checks what it got. A Node subclass is constructed, rejected,
## and dropped on the floor -- nothing frees it.
func _what_the_scan_constructs() -> void:
	_write_tool_dir(
		{
			"good_tool.gd": GOOD_TOOL,
			"a_node.gd": NODE_SCRIPT,
			"a_resource.gd": RESOURCE_SCRIPT,
		}
	)
	var registry = ToolRegistry.new()
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	registry.load_external_tools(TOOL_DIR)
	await frame()
	var orphans_after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var loaded: Array = registry.get_external_tools()
	note("files in the scanned directory", 3)
	note("tools registered", loaded.size())
	note("orphan nodes", "%d -> %d" % [orphans_before, orphans_after])
	if orphans_after > orphans_before:
		known(
			507,
			"the custom-tool scan leaks a node for every .gd file that is not a tool",
			(
				"load_external_tools() calls script.new() before it checks the type,"
				+ " and a Node subclass that fails the check is assigned null rather than freed"
				+ " (orphan count %d -> %d for one such file)" % [orphans_before, orphans_after]
			)
		)


## The toolbar activates by id. An id the registry does not have.
func _activating_an_id_that_is_not_there() -> void:
	var root: Node3D = await fresh_root("ToolRegistryRoot")
	_write_tool_dir({"good_tool.gd": GOOD_TOOL})
	var registry = ToolRegistry.new()
	registry.load_external_tools(TOOL_DIR)
	registry.activate_tool(101, root, null)
	var active = registry.get_active_tool()
	note("after activating 101", active.tool_name() if active else "nothing")
	if active == null:
		flag("a registered external tool would not activate", "id 101 was loaded but is not active")
		return
	registry.activate_tool(999, root, null)
	var after = registry.get_active_tool()
	note("after activating unknown id 999", after.tool_name() if after else "nothing")
	if after == null:
		known(
			508,
			"activating a tool id the registry does not have turns off the tool that was active",
			(
				"activate_tool() deactivates the current tool before it looks the new id up,"
				+ " so a toolbar button for a tool that failed to load silently clears the"
				+ " active tool instead of doing nothing"
			)
		)


## Two tools that claim the same id, and two that claim the same shortcut.
func _colliding_ids_and_shortcuts() -> void:
	var registry = ToolRegistry.new()
	var first = _make_tool(101, KEY_F5, "First")
	var second = _make_tool(101, KEY_F6, "Second")
	registry.register_tool(first)
	registry.register_tool(second)
	note("registered after two tools claiming id 101", registry.get_all_tools().size())
	note("id 101 resolves to", registry.get_tool_by_id(101).tool_name())
	if registry.get_all_tools().size() == 1:
		note(
			"a duplicate tool id is dropped silently",
			"register_tool() returns early and says nothing; the second tool never appears"
		)

	var registry2 = ToolRegistry.new()
	registry2.register_tool(_make_tool(101, KEY_F5, "First"))
	registry2.register_tool(_make_tool(102, KEY_F5, "Second"))
	var f5 := InputEventKey.new()
	f5.keycode = KEY_F5
	f5.pressed = true
	var winner: int = registry2.check_shortcut(f5)
	note("two tools bound to F5, check_shortcut returns", winner)
	note("registered tools", registry2.get_all_tools().size())


func _make_tool(p_id: int, p_key: int, p_name: String) -> HFEditorTool:
	var script := GDScript.new()
	script.source_code = (
		"""@tool
extends HFEditorTool
func tool_id() -> int: return %d
func tool_shortcut_key() -> int: return %d
func tool_name() -> String: return "%s"
"""
		% [p_id, p_key, p_name]
	)
	script.reload()
	return script.new() as HFEditorTool


## `set_setting()` holds a float or an int to the schema's min and max. An enum
## carries `options` rather than a range, and a colour or a vector carries
## neither, so the dock's generated control is the only thing that limits them.
func _settings_against_their_own_schema() -> void:
	var script := GDScript.new()
	script.source_code = GOOD_TOOL
	script.reload()
	var t = script.new() as HFEditorTool

	t.set_setting("count", 999)
	note("int setting 'count' (max 10) set to 999", t.get_setting("count"))
	if int(t.get_setting("count")) > 10:
		flag("an int tool setting is not held to its schema max", t.get_setting("count"))

	t.set_setting("mode", 7)
	note("enum setting 'mode' (2 options) set to 7", t.get_setting("mode"))
	if int(t.get_setting("mode")) >= 2:
		known(
			509,
			"an enum tool setting accepts an index its own options do not have",
			(
				"set_setting() clamps 'float' and 'int' against min/max and lets every other"
				+ " declared type through, so 'mode' holds 7 against 2 options -- the same shape"
				+ " the dock's generated OptionButton cannot show"
			)
		)

	t.set_setting("not_in_the_schema", "anything")
	note("a key the schema does not declare", t.get_setting("not_in_the_schema"))
