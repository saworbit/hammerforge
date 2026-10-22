extends GutTest

## 2.1 over 0.3 is 7.000000000000001 in floats. The Stairs builder counts that
## as 7 steps; the Path tool, its curved stairs and the Connector tool took a bare
## ceil and built 8 (#1676). They all count through `step_count()` now. A smooth
## path's preview counted each curve piece on its own and drew more step marks
## than the treads it built.

const HFStairsBuilder = preload("res://addons/hammerforge/hf_stairs_builder.gd")
const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const HFConnectorTool = preload("res://addons/hammerforge/paint/hf_connector_tool.gd")


func test_the_stairs_builder_climbs_2_1_in_seven_steps_of_0_3():
	assert_eq(HFStairsBuilder.step_count(2.1, 0.3), 7)
	assert_eq(HFStairsBuilder.step_count(-2.1, 0.3), 7, "down as well as up")
	assert_eq(HFStairsBuilder.step_count(2.2, 0.3), 8, "a part step is a step")
	var fit := {"height_from": HFStairsBuilder.HEIGHT_FROM_FIT, "total": 2.1, "rise": 0.3}
	assert_eq(HFStairsBuilder.climb(fit)["steps"], 7, "as Fit counts")


## A point holds float32, so 1.2 is a hair over and a bare ceil made 5 steps.
func test_a_straight_path_climbs_1_2_in_four_steps_of_0_3():
	var tool := HFPathTool.new()
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 1.2, 0)])
	tool.set_setting("stair_step_height", 0.3)
	tool._ground_y = 0.0
	assert_eq(tool._build_stairs(4.0, 4.0, "grp", 99).size(), 4)


func test_a_connector_climbs_2_1_in_seven_steps():
	var tool := HFConnectorTool.new()
	var grid := HFPaintGrid.new()
	grid.cell_size = 1.0
	var def := HFConnectorTool.ConnectorDef.new()
	def.from_cell = Vector2i.ZERO
	def.to_cell = Vector2i(6, 0)
	var mesh: ArrayMesh = tool._generate_stairs(def, grid, 0.0, 2.1, 0.3)
	assert_not_null(mesh)
	var heights := {}
	for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		heights[snappedf(v.y, 0.0001)] = true
	assert_eq(heights.size(), 8, "the floor and the tops of seven steps")


func test_a_smooth_path_previews_one_mark_for_each_tread_it_builds():
	var tool := HFPathTool.new()
	tool.set_setting("path_curve", HFPathTool.CurveMode.SMOOTH)
	tool.set_setting("curve_segments", 8)
	tool.set_setting("stair_step_height", 0.3)
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 1.2, 0), Vector3(8, 2.1, 8)])
	var ends: Array = tool._curved_step_ends()
	var treads := {}
	for info: Dictionary in tool._build_curved_stairs(2.0, "grp", 99):
		treads[snappedf((info["center"] as Vector3).y, 0.0001)] = true
	assert_eq(ends.size(), 4 + 3, "1.2 in four steps of 0.3, then 0.9 in three")
	assert_eq(ends.size(), treads.size(), "a mark for each tread built")
