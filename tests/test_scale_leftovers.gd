extends GutTest

## Numbers left on the pre-#625 scale (#658).
##
## #625 made one world unit one metre: the player is 1.6, a default drawn brush
## is 2, the grid snaps at 0.5 and the shipped examples are 8 unit rooms. These
## are the distances that conversion did not reach, where a value that used to be
## a small nudge became several rooms.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const PolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


# ===========================================================================
# The Polygon tool
# ===========================================================================


func test_a_polygon_starts_at_the_level_s_own_brush_height():
	var root := _fresh_root()
	var tool_instance := PolygonTool.new()
	tool_instance.root = root
	assert_almost_eq(
		float(tool_instance.call("_starting_height")),
		root.brush_size_default.y,
		0.001,
		"not a literal 32, which since #625 is twenty players tall"
	)


func test_a_polygon_remembers_the_height_the_mapper_set():
	# The resets used the literal too, so dragging it down to something usable
	# gave 32 back on the next polygon.
	var root := _fresh_root()
	var tool_instance := PolygonTool.new()
	tool_instance.root = root
	tool_instance.set("_remembered_height", 1.5)
	assert_almost_eq(
		float(tool_instance.call("_starting_height")),
		1.5,
		0.001,
		"the next polygon starts where the last one ended"
	)


func test_no_hard_coded_height_is_left_in_the_polygon_tool():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/hf_polygon_tool.gd")
	var code := ""
	for line in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	assert_false(code.contains("_height = 32.0"), "the two resets no longer hold a literal")


# ===========================================================================
# Shipped entity defaults
# ===========================================================================


func test_the_shipped_door_moves_at_a_speed_the_player_can_see():
	# The playtest player walks at 6.5 units a second and a doorway is about 2
	# units across. At 200 the door was open in ten milliseconds.
	var root := _fresh_root()
	var defs: Dictionary = root.get_entity_definitions()
	assert_true(defs.has("door_basic"), "the door still ships")
	var speed := 0.0
	for prop in defs["door_basic"].get("properties", []):
		if str(prop.get("name", "")) == "speed":
			speed = float(prop.get("default", 0.0))
	assert_gt(speed, 0.0, "the door has a speed")
	assert_lt(speed, 20.0, "on the same scale as a player who walks at 6.5")
