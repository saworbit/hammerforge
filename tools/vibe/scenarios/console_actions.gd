@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The Status board's action buttons, which are the Console's whole point: every
## row on the board is a problem plus the button that fixes it.
##
## `HFPluginConsole.handle_action()` deliberately owns none of these behaviours
## and routes each one back to the dock. What is worth measuring is whether the
## level ends up in the state the board said it would, and whether the Log tab's
## line about it says the same thing.

const ConsoleType = preload("res://addons/hammerforge/plugin_console.gd")
const LogType = preload("res://addons/hammerforge/hf_console_log.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")


func id() -> String:
	return "console-actions"


func summary() -> String:
	return "whether a Status board action leaves the level in the state it reported"


func run() -> void:
	await _recommended_chunk_size()
	_unknown_action()


## A stand-in for the plugin: `handle_action()` only ever reaches it through
## `get`/`set`/`has_method`, so a bag of the three properties it reads is enough
## and avoids standing up the whole EditorPlugin headlessly.
class FakePlugin:
	extends Object
	var dock = null
	var console_panel = null
	var console_strip = null


func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	await frame()
	return dock


func _recommended_chunk_size() -> void:
	var root: Node3D = await fresh_root("ChunkLevel")
	var dock = await _dock(root)
	# The recommendation is extent/4 snapped, and only appears once the level has
	# 30 brushes and spans 128 units. Build a level big enough to be asked about.
	var span := 4096.0
	var step: float = span / 32.0
	for i in range(36):
		root.create_brush_from_info(
			{"shape": 0, "size": Vector3(64, 64, 64), "center": Vector3(float(i) * step, 0, 0)}
		)
	await frame()
	var recommended: float = root.get_recommended_chunk_size()
	note("brushes", root.brush_system.get_live_brush_count())
	note("recommended chunk size", recommended)
	var spin: SpinBox = dock.get("bake_chunk_size_spin") as SpinBox
	note("the dock spin the Console writes through", [spin.min_value, spin.max_value])

	var buffer = LogType.new()
	LogType._shared = buffer
	var plugin := FakePlugin.new()
	plugin.dock = dock
	ConsoleType.handle_action(plugin, "apply_chunk_size")
	await frame()
	var held: float = float(root.get("bake_chunk_size"))
	note("after Apply recommended chunk size, the level holds", held)
	var said := ""
	for entry in buffer.entries():
		if str(entry["category"]) == "settings":
			said = str(entry["message"])
	note("what the Log tab was told", said)
	if not is_equal_approx(held, recommended):
		known(
			549,
			"Apply recommended chunk size does not apply the recommended chunk size",
			(
				(
					"the board recommends %s, the Console writes it through the dock's spin"
					+ " whose range is %s..%s, and the level ends up holding %s. The Log tab"
					+ " is told %s, which is the number that was asked for rather than the"
					+ " one the level received"
				)
				% [recommended, spin.min_value, spin.max_value, held, said]
			)
		)
	plugin.free()
	dock.queue_free()
	await frame()


func _unknown_action() -> void:
	var buffer = LogType.new()
	LogType._shared = buffer
	var plugin := FakePlugin.new()
	ConsoleType.handle_action(plugin, "no_such_action")
	note("an action id with no handler logged", buffer.size())
	for entry in buffer.entries():
		note("  ", LogType.format_entry(entry))
	plugin.free()
