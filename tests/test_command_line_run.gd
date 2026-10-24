extends "res://tests/mcp/mcp_dispatcher_case.gd"

## What the Console's command line runs, and how (#1696): a bridge command goes
## to the plugin's dispatcher as a person's request, on the selection, as one
## undo step named for the command; any other runs as the palette runs it; a
## script runs line by line and stops at the first refusal.

const HFPluginCommandLine = preload("res://addons/hammerforge/plugin_command_line.gd")
const HFCommandLine = preload("res://addons/hammerforge/hf_command_line.gd")

const SCRIPT_PATH := "user://test_command_line_run.hfcmd"


## The plugin fields and delegates the runner reads.
class FakePlugin:
	extends Node

	var mcp_dispatcher = null
	var hf_selection: Array = []
	var level: Node = null
	var palette_ran: Array = []

	func _get_level_root() -> Node:
		return level

	func _on_hotkey_palette_action(id: String) -> void:
		palette_ran.append(id)


var level: LevelRoot
var plugin: FakePlugin


func before_each() -> void:
	super.before_each()
	level = make_level_with_palette()
	plugin = FakePlugin.new()
	plugin.level = level
	plugin.mcp_dispatcher = dispatcher
	add_child_autoqfree(plugin)


func after_each() -> void:
	if FileAccess.file_exists(SCRIPT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRIPT_PATH))
	super.after_each()


func _box() -> Node:
	var brush_id := await place_box([0.3, 5.3, 0.3], [4, 2, 4])
	return level.find_brush_by_id(brush_id)


func _line(text: String) -> Dictionary:
	var read := HFCommandLine.read(text)
	assert_true(read["ok"], "%s reads" % text)
	return await HFPluginCommandLine.run(plugin, read["id"], read["params"], text)


func test_hollow_on_the_selection_is_one_step_named_for_the_command():
	var box := await _box()
	plugin.hf_selection = [box]
	var steps: int = undo.scene_history.get_history_count()
	var outcome := await _line("hollow 0.125")
	assert_true(outcome["ok"], outcome["message"])
	assert_eq(undo.scene_history.get_history_count(), steps + 1, "one undo step")
	assert_eq(undo.scene_history.get_current_action_name(), "Hollow", "named for the command")
	var hollows: Array = level.brush_system.capture_hollows()
	assert_eq(hollows.size(), 1, "the box is a hollow now")
	if hollows.size() == 1:
		assert_almost_eq(float(hollows[0]["thickness"]), 0.125, 0.0001, "with 0.125 walls")
		assert_eq((hollows[0]["wall_ids"] as Array).size(), 6, "six of them")
	assert_string_contains(outcome["message"], "Hollow:")


func test_the_agent_does_not_take_a_typed_step_for_its_own():
	var box := await _box()
	plugin.hf_selection = [box]
	box.rotation_degrees = Vector3(0, 30, 0)
	var reset := await _line("reset rotation")
	assert_true(reset["ok"], reset["message"])
	var status := await call_tool("hf_get_status")
	assert_eq(
		status["result"].get("last_agent_revision"), null, "the status does not call it the agent's"
	)
	var undone := await call_tool("hf_undo")
	assert_true(undone.has("error"), "hf_undo refuses a step the person made")


func test_a_refusal_names_the_value_the_bridge_refused():
	var box := await _box()
	plugin.hf_selection = [box]
	var steps: int = undo.scene_history.get_history_count()
	var outcome := await _line("hollow 500")
	assert_false(outcome["ok"])
	assert_string_contains(outcome["message"], "thickness")
	assert_eq(undo.scene_history.get_history_count(), steps, "nothing was committed")


func test_a_command_with_no_selection_is_refused_as_the_bridge_refuses_it():
	var outcome := await _line("move to floor")
	assert_false(outcome["ok"])
	assert_string_contains(outcome["message"], "move_to_floor")


func test_a_command_the_bridge_does_not_run_goes_the_palette_s_way():
	var outcome := await _line("toggle paint mode")
	assert_true(outcome["ok"])
	assert_eq(plugin.palette_ran, ["toggle_paint_mode"])


func test_a_script_runs_line_by_line_and_stops_at_the_first_refusal_naming_it():
	var box := await _box()
	plugin.hf_selection = [box]
	var file := FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
	box.rotation_degrees = Vector3(0, 30, 0)
	file.store_string(
		"# square it, then a bad hollow\nreset rotation\n\nhollow 500\nsnap_to_grid\n"
	)
	file.close()
	var steps: int = undo.scene_history.get_history_count()
	var outcome := await HFPluginCommandLine.run_script(plugin, SCRIPT_PATH)
	assert_false(outcome["ok"])
	assert_eq(outcome["ran"], 1, "the line before ran")
	assert_string_contains(outcome["message"], "line 4")
	assert_string_contains(outcome["message"], "thickness")
	assert_eq(undo.scene_history.get_history_count(), steps + 1, "one step for the line that ran")


func test_a_script_with_a_line_that_does_not_read_stops_before_it():
	var file := FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
	file.store_string("hollw 0.5\n")
	file.close()
	var outcome := await HFPluginCommandLine.run_script(plugin, SCRIPT_PATH)
	assert_false(outcome["ok"])
	assert_eq(outcome["ran"], 0)
	assert_string_contains(outcome["message"], "line 1")
	assert_string_contains(outcome["message"], "There is no command 'hollw'")
