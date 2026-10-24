extends GutTest

## Every length the editor shows reads the same for the same value and grid step,
## whichever tool shows it (#1674). The Measure, Path and Polygon readouts and the
## Hollow and Clip questions printed one decimal, so a 0.25 wall on a 0.25 grid
## read "0.2" in one place and "0.25" in the next.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFMeasureTool = preload("res://addons/hammerforge/hf_measure_tool.gd")
const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const HFPolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")
const HFOpResult = preload("res://addons/hammerforge/hf_op_result.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.grid_snap = 0.25
	add_child_autoqfree(root)


func _joined(lines: PackedStringArray) -> String:
	return "\n".join(lines)


func test_the_measure_readout():
	var tool := HFMeasureTool.new()
	tool.root = root
	tool._measurements.append({"a": Vector3.ZERO, "b": Vector3(0.25, 0, 0)})
	var text := _joined(tool.get_shortcut_hud_lines())
	assert_string_contains(text, "Distance: 0.25")
	assert_string_contains(text, "dX: 0.25")


func test_the_path_readout():
	var tool := HFPathTool.new()
	tool.root = root
	tool.set_setting("path_width", 0.75)
	assert_string_contains(_joined(tool.get_shortcut_hud_lines()), "Width: 0.75")


func test_the_polygon_readout():
	var tool := HFPolygonTool.new()
	tool.root = root
	tool._phase = HFPolygonTool.Phase.SETTING_HEIGHT
	tool._height = 0.25
	assert_string_contains(_joined(tool.get_shortcut_hud_lines()), "Set height (0.25)")


func test_the_hollow_and_clip_questions():
	var hollow := HFPluginEditActions.hollow_question(root, 0.25, HFOpResult.success("6 walls"))
	assert_string_contains(hollow, "wall thickness 0.25 into 6 walls")
	assert_string_contains(HFPluginEditActions.clip_question(root, 0.25), "at 0.25?")
