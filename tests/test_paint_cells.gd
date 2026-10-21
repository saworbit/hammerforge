extends GutTest
## Floor paint in cell space: the paint system's calls that take a layer and
## cells with no screen or mouse in them (#1299), the geometry they rebuild, and
## the one level state that takes all of it back.

const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const HFPaintSystem = preload("res://addons/hammerforge/systems/hf_paint_system.gd")
const HFConnectorTool = preload("res://addons/hammerforge/paint/hf_connector_tool.gd")

var root: LevelRoot
var sys: HFPaintSystem


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.grid_snap = 1.0
	add_child_autoqfree(root)
	sys = root.paint_system


func after_each() -> void:
	root = null
	sys = null


func ground() -> HFPaintLayer:
	return root.paint_layers.layers[0]


func upper() -> HFPaintLayer:
	return root.paint_layers.create_layer(&"upper", 3.0)


func cell(x: int, z: int) -> Vector2i:
	return Vector2i(x, z)


## The wall heights the synth builds for the layer's first chunk.
func wall_heights(layer: HFPaintLayer) -> Dictionary:
	var model = root.paint_tool.geometry.build_for_chunks(
		layer, [Vector2i.ZERO], root.paint_tool.synth_settings
	)
	var heights := {}
	for wall in model.walls:
		heights[snappedf(wall.height, 0.001)] = true
	return heights


# ===========================================================================
# Painting a rectangle
# ===========================================================================


func test_paint_cells_fills_the_rectangle_and_builds_its_floor_before_answering():
	var r: Dictionary = sys.paint_cells(0, cell(3, 1), cell(0, 2), true)
	assert_true(r["ok"], str(r))
	assert_eq(r["cells"], 8, "corners in any order")
	assert_eq(r["changed"], 8)
	for c in HFPaintTool.rect_cells(cell(0, 1), cell(3, 2)):
		assert_true(ground().get_cell(c), "%s is painted" % str(c))
	assert_false(ground().get_cell(cell(4, 1)), "the cell past the edge is not")
	assert_false(ground().get_cell(cell(0, 0)))
	assert_gt(root.generated_floors.get_child_count(), 0, "the floor was built")
	assert_gt(root.generated_walls.get_child_count(), 0, "with walls round it")


func test_painting_again_changes_nothing_and_erasing_takes_the_floor_away():
	sys.paint_cells(0, cell(0, 0), cell(1, 1), true)
	var again: Dictionary = sys.paint_cells(0, cell(0, 0), cell(1, 1), true)
	assert_eq(again["changed"], 0, "already painted")
	assert_eq(again["cells"], 4)
	var erased: Dictionary = sys.paint_cells(0, cell(0, 0), cell(0, 1), false)
	assert_eq(erased["changed"], 2)
	assert_false(ground().get_cell(cell(0, 0)))
	assert_true(ground().get_cell(cell(1, 0)), "the other column stays")
	sys.paint_cells(0, cell(1, 0), cell(1, 1), false)
	assert_eq(root.generated_floors.get_child_count(), 0, "nothing painted, no floor")
	assert_eq(ground().filled_cell_count(), 0)


func test_a_material_goes_on_the_painted_cells():
	var r: Dictionary = sys.paint_cells(0, cell(2, 2), cell(3, 3), true, 2)
	assert_true(r["ok"], str(r))
	for c in HFPaintTool.rect_cells(cell(2, 2), cell(3, 3)):
		assert_eq(ground().get_cell_material(c), 2, "%s carries the material" % str(c))
	assert_eq(ground().get_cell_material(cell(1, 1)), 0)


func test_material_only_repaint_reports_material_changes_separately():
	sys.paint_cells(0, cell(0, 0), cell(1, 1), true)
	var repainted: Dictionary = sys.paint_cells(0, cell(0, 0), cell(1, 1), true, 3)
	assert_eq(repainted["changed"], 0, "the filled bits did not flip")
	assert_eq(repainted.get("materials_changed", -1), 4)
	var again: Dictionary = sys.paint_cells(0, cell(0, 0), cell(1, 1), true, 3)
	assert_eq(again.get("materials_changed", -1), 0)


func test_raising_to_the_default_counts_new_height_overrides():
	sys.paint_cells(0, cell(0, 0), cell(1, 1), true)
	var height: float = root.paint_tool.synth_settings.wall_height
	var raised: Dictionary = sys.raise_cells(0, cell(0, 0), cell(1, 1), height)
	assert_eq(raised["changed"], 4, "new overrides pin these cells to the current default")
	assert_eq(ground().get_wall_height_entries().size(), 4)
	var again: Dictionary = sys.raise_cells(0, cell(0, 0), cell(1, 1), height)
	assert_eq(again["changed"], 0)


func test_one_cell_is_a_rectangle_of_one():
	var r: Dictionary = sys.paint_cells(0, cell(5, 5), cell(5, 5), true)
	assert_eq(r["cells"], 1)
	assert_eq(ground().filled_cell_count(), 1)


# ===========================================================================
# Raising
# ===========================================================================


func test_raise_cells_sets_the_height_of_the_painted_cells_only():
	sys.paint_cells(0, cell(0, 0), cell(2, 0), true)
	var r: Dictionary = sys.raise_cells(0, cell(0, 0), cell(3, 0), 4.5)
	assert_true(r["ok"], str(r))
	assert_eq(r["raised"], 3, "the three painted cells")
	assert_eq(r["changed"], 3)
	for x in 3:
		assert_almost_eq(ground().get_wall_height(cell(x, 0), 9.0), 4.5, 0.001)
	assert_almost_eq(ground().get_wall_height(cell(3, 0), 9.0), 9.0, 0.001, "unpainted, untouched")
	assert_true(wall_heights(ground()).has(4.5), "the walls stand at the new height")
	var same: Dictionary = sys.raise_cells(0, cell(0, 0), cell(2, 0), 4.5)
	assert_eq(same["changed"], 0, "the same height again moves nothing")
	assert_eq(same["raised"], 3)


func test_raise_cells_over_nothing_painted_is_refused():
	var r: Dictionary = sys.raise_cells(0, cell(5, 5), cell(6, 6), 2.0)
	assert_false(r["ok"])
	assert_string_contains(r["error"], "No painted cells")
	assert_eq(ground().get_wall_height_entries().size(), 0)


func test_a_height_of_zero_is_refused():
	sys.paint_cells(0, cell(0, 0), cell(0, 0), true)
	assert_false(sys.raise_cells(0, cell(0, 0), cell(0, 0), 0.0)["ok"])
	assert_false(sys.raise_cells(0, cell(0, 0), cell(0, 0), -1.0)["ok"])


# ===========================================================================
# Stamping a room
# ===========================================================================


func test_stamp_room_paints_from_its_corner_and_raises_the_walls():
	var r: Dictionary = sys.stamp_room(0, cell(2, 3), 3, 2, 2.5)
	assert_true(r["ok"], str(r))
	assert_eq(r["from"], cell(2, 3))
	assert_eq(r["to"], cell(4, 4))
	assert_eq(r["cells"], 6)
	assert_eq(r["changed"], 6)
	assert_eq(r["raised"], 6)
	for c in HFPaintTool.rect_cells(cell(2, 3), cell(4, 4)):
		assert_true(ground().get_cell(c))
		assert_almost_eq(ground().get_wall_height(c, 9.0), 2.5, 0.001)
	assert_false(ground().get_cell(cell(5, 3)), "three wide")
	assert_false(ground().get_cell(cell(2, 5)), "two deep")


func test_stamp_room_without_a_height_leaves_the_default_walls():
	var r: Dictionary = sys.stamp_room(0, cell(10, 10), 2, 2)
	assert_true(r["ok"], str(r))
	assert_eq(r["raised"], 0)
	assert_almost_eq(ground().get_wall_height(cell(10, 10), 7.0), 7.0, 0.001, "no override")
	assert_false(sys.stamp_room(0, cell(0, 0), 0, 2)["ok"], "no room is zero wide")


func test_stamp_room_refuses_nonfinite_heights_before_painting():
	for height in [INF, NAN]:
		var before: Dictionary = root.capture_state()
		var result: Dictionary = sys.stamp_room(0, cell(0, 0), 2, 2, height)
		assert_false(result["ok"], "invalid height is refused")
		assert_eq(root.capture_state(), before, "a refused room leaves no painted cells")


# ===========================================================================
# Connectors
# ===========================================================================


func test_confirm_connectors_keeps_the_boundary_between_two_layers_once():
	upper()
	sys.paint_cells(0, cell(0, 0), cell(0, 0), true)
	sys.paint_cells(1, cell(1, 0), cell(1, 0), true)
	var found: Dictionary = sys.connector_candidates(0, cell(0, 0), cell(0, 0))
	assert_true(found["ok"], str(found))
	assert_eq((found["new"] as Array).size(), 1)
	assert_eq((found["already"] as Array).size(), 0)

	var r: Dictionary = sys.confirm_connectors(0, cell(0, 0), cell(0, 0))
	assert_true(r["ok"], str(r))
	assert_eq(r["added"], 1)
	assert_eq(r["already"], 0)
	var connector: Dictionary = r["connectors"][0]
	assert_eq(connector["from_layer"], 0)
	assert_eq(connector["to_layer"], 1)
	assert_eq(connector["from_cell"], [0, 0])
	assert_eq(connector["to_cell"], [1, 0])
	assert_eq(connector["type"], "ramp", "the level's connector mode")
	assert_eq(root.paint_tool.connector_defs.size(), 1, "kept on the tool, where a save reads it")

	var again: Dictionary = sys.confirm_connectors(0, cell(0, 0), cell(0, 0))
	assert_false(again["ok"], "the same boundary is not confirmed twice")
	assert_string_contains(again["error"], "already")
	var other_side: Dictionary = sys.confirm_connectors(1, cell(1, 0), cell(1, 0))
	assert_false(other_side["ok"], "nor from the other layer")
	assert_eq(root.paint_tool.connector_defs.size(), 1)


func test_confirm_connectors_takes_the_level_s_mode_and_can_be_held_to_a_layer():
	upper()
	root.paint_layers.create_layer(&"top", 6.0)
	sys.paint_cells(0, cell(0, 0), cell(0, 0), true)
	sys.paint_cells(1, cell(1, 0), cell(1, 0), true)
	sys.paint_cells(2, cell(0, 1), cell(0, 1), true)
	root.bake_connector_mode = HFAutoConnector.ConnectorMode.STAIRS
	var only_top: Dictionary = sys.confirm_connectors(0, cell(0, 0), cell(0, 0), 2)
	assert_true(only_top["ok"], str(only_top))
	assert_eq(only_top["added"], 1, "the boundary with the top layer alone")
	assert_eq(only_top["connectors"][0]["to_layer"], 2)
	assert_eq(only_top["connectors"][0]["type"], "stairs", "the Bake tab's mode")
	var rest: Dictionary = sys.confirm_connectors(0, cell(0, 0), cell(0, 0))
	assert_eq(rest["added"], 1, "the one with the upper layer is still there to confirm")
	assert_eq(rest["already"], 1, "and the top one is counted, not repeated")
	assert_false(sys.confirm_connectors(0, cell(0, 0), cell(0, 0), 7)["ok"], "no layer 7")
	assert_false(sys.confirm_connectors(0, cell(0, 0), cell(0, 0), 0)["ok"], "not to itself")


func test_confirm_connectors_with_one_layer_or_no_neighbour_is_refused():
	sys.paint_cells(0, cell(0, 0), cell(0, 0), true)
	var alone: Dictionary = sys.confirm_connectors(0, cell(0, 0), cell(0, 0))
	assert_false(alone["ok"])
	assert_string_contains(alone["error"], "one paint layer")
	upper()
	var apart: Dictionary = sys.confirm_connectors(0, cell(0, 0), cell(0, 0))
	assert_false(apart["ok"])
	assert_string_contains(apart["error"], "No boundary")
	assert_eq(root.paint_tool.connector_defs.size(), 0)


func test_the_tool_s_ghosts_still_confirm_through_the_shared_add():
	var ghost := HFConnectorTool.ConnectorDef.new()
	ghost.from_layer_index = 0
	ghost.to_layer_index = 1
	ghost.from_cell = cell(0, 0)
	ghost.to_cell = cell(1, 0)
	root.paint_tool._pending_connector_defs = [ghost]
	assert_eq(root.paint_tool.confirm_connector_ghosts(), 1)
	assert_eq(root.paint_tool.add_connector_defs([ghost]), [], "known already")
	assert_eq(root.paint_tool.connector_defs.size(), 1)


# ===========================================================================
# Refusals and lookups
# ===========================================================================


func test_a_call_is_refused_mid_stroke_and_past_the_limits():
	root.paint_tool._painting = true
	var busy: Dictionary = sys.paint_cells(0, cell(0, 0), cell(0, 0), true)
	assert_false(busy["ok"])
	assert_string_contains(busy["error"], "stroke")
	root.paint_tool._painting = false
	var huge: Dictionary = sys.paint_cells(0, cell(0, 0), cell(300, 300), true)
	assert_false(huge["ok"])
	assert_string_contains(huge["error"], "90601 cells")
	var far: Dictionary = sys.paint_cells(
		0, cell(HFPaintSystem.CELL_LIMIT + 1, 0), cell(0, 0), true
	)
	assert_false(far["ok"])
	assert_string_contains(far["error"], "from the origin")
	var missing: Dictionary = sys.paint_cells(3, cell(0, 0), cell(0, 0), true)
	assert_false(missing["ok"])
	assert_string_contains(missing["error"], "No paint layer 3")
	assert_eq(ground().filled_cell_count(), 0, "none of them painted anything")


func test_layers_are_found_by_name_or_index_and_described():
	ground().display_name = "Ground"
	upper()
	assert_eq(sys.find_paint_layer("Ground"), 0, "by display name")
	assert_eq(sys.find_paint_layer("layer_0"), 0, "by id")
	assert_eq(sys.find_paint_layer("upper"), 1)
	assert_eq(sys.find_paint_layer("UPPER"), 1, "case does not matter when nothing matches exactly")
	assert_eq(sys.find_paint_layer("nope"), -1)
	assert_eq(sys.find_paint_layer(""), -1)
	assert_null(sys.paint_layer_at(2))
	assert_null(sys.paint_layer_at(-1))
	sys.paint_cells(1, cell(0, 0), cell(1, 1), true)
	var listed: Array = sys.describe_paint_layers()
	assert_eq(listed.size(), 2)
	assert_eq(listed[0]["index"], 0)
	assert_eq(listed[0]["id"], "layer_0")
	assert_eq(listed[0]["name"], "Ground")
	assert_eq(listed[0]["cells"], 0)
	assert_eq(listed[1]["name"], "upper", "the id when there is no display name")
	assert_almost_eq(float(listed[1]["layer_y"]), 3.0, 0.001)
	assert_almost_eq(float(listed[1]["cell_size"]), 1.0, 0.001)
	assert_eq(listed[1]["cells"], 4)


# ===========================================================================
# One level state holds all of it
# ===========================================================================


func test_the_level_state_takes_a_paint_a_raise_and_a_connector_back_together():
	upper()
	var before: Dictionary = root.capture_state()
	sys.paint_cells(0, cell(0, 0), cell(1, 1), true)
	sys.raise_cells(0, cell(0, 0), cell(1, 1), 4.0)
	sys.paint_cells(1, cell(2, 0), cell(2, 1), true)
	sys.confirm_connectors(0, cell(1, 0), cell(1, 1))
	var after: Dictionary = root.capture_state()
	assert_eq(root.paint_tool.connector_defs.size(), 1)

	root.restore_state(before)
	assert_eq(ground().filled_cell_count(), 0, "the paint is gone")
	assert_eq(ground().get_wall_height_entries().size(), 0, "so are the heights")
	assert_eq(root.paint_layers.layers[1].filled_cell_count(), 0)
	assert_eq(root.paint_tool.connector_defs.size(), 0, "and the connector")
	assert_eq(root.generated_floors.get_child_count(), 0)

	root.restore_state(after)
	assert_eq(ground().filled_cell_count(), 4, "put back")
	assert_almost_eq(ground().get_wall_height(cell(1, 1), 9.0), 4.0, 0.001)
	assert_eq(root.paint_tool.connector_defs.size(), 1)
	assert_gt(root.generated_floors.get_child_count(), 0)


func test_with_region_streaming_on_the_regions_are_loaded_and_the_pins_let_go():
	sys.set_region_streaming_enabled(true)
	var r: Dictionary = sys.paint_cells(0, cell(0, 0), cell(70, 1), true)
	assert_true(r["ok"], str(r))
	assert_eq(r["changed"], 142)
	assert_true(ground().get_cell(cell(70, 1)))
	assert_true(sys._paint_region_pins.is_empty(), "the pins were released")
	assert_gt(sys.get_loaded_regions().size(), 0)
	var raised: Dictionary = sys.raise_cells(0, cell(69, 0), cell(70, 1), 2.0)
	assert_true(raised["ok"], str(raised))
	assert_eq(raised["raised"], 4)
	assert_true(sys._paint_region_pins.is_empty())
