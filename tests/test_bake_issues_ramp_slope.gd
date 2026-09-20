extends GutTest

## Bake Check told a mapper when connector stairs were too tall for the navmesh
## agent to climb and said nothing when a connector ramp was too steep for the
## same agent to walk (#798). Ramp is the default connector mode, so the half
## with the check was the half almost nobody used. These tests pin the ramp half
## against the slope the agent is actually given.

const HFValidationSystem = preload("res://addons/hammerforge/systems/hf_validation_system.gd")
const HFConnectorToolScript = preload("res://addons/hammerforge/paint/hf_connector_tool.gd")
const HFPaintLayerManagerScript = preload(
	"res://addons/hammerforge/paint/hf_paint_layer_manager.gd"
)
const HFPaintGridScript = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

# HFAutoConnector.ConnectorMode, which is what `bake_connector_mode` holds.
const MODE_RAMP := 0
const MODE_STAIRS := 1
const MODE_AUTO := 2

var root: Node3D
var val_sys: HFValidationSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	var committed = Node3D.new()
	committed.name = "Committed"
	root.add_child(committed)
	root.committed_node = committed
	val_sys = HFValidationSystem.new(root)


func after_each():
	root = null
	val_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var committed_node: Node3D
var paint_layers = null
var paint_tool = null
var bake_navmesh: bool = true
var bake_auto_connectors: bool = true
var bake_navmesh_agent_max_slope: float = 45.0
var bake_navmesh_agent_max_climb: float = 0.25
var bake_connector_mode: int = 0
var bake_connector_stair_height: float = 0.25
var bake_connector_width: int = 2
var bake_connector_stair_threshold: float = 2.0

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")
"""
	s.reload()
	return s


## Two painted layers a cell apart, the lower one at world Y 0 and the upper one
## at `rise`. That is one boundary, so the bake builds one connector across one
## cell of run.
func _two_layers_one_cell_apart(rise: float, cell_size: float = 1.0) -> void:
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	mgr.base_grid.cell_size = cell_size
	add_child_autoqfree(mgr)
	mgr.clear_layers()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", rise)
	mgr.layers[0].set_cell(Vector2i(0, 0), true)
	mgr.layers[1].set_cell(Vector2i(1, 0), true)
	root.paint_layers = mgr


## A connector the mapper committed with the connector tool, which bakes whether
## or not auto-connectors are on.
func _commit_connector(from_cell: Vector2i, to_cell: Vector2i) -> void:
	root.paint_layers.layers[1].set_cell(to_cell, true)
	var def := HFConnectorToolScript.ConnectorDef.new()
	def.from_layer_index = 0
	def.to_layer_index = 1
	def.from_cell = from_cell
	def.to_cell = to_cell
	def.connector_type = HFConnectorToolScript.ConnectorType.RAMP
	var tool_shim := _paint_tool_shim()
	tool_shim.connector_defs = [def]
	root.paint_tool = tool_shim


func _paint_tool_shim() -> RefCounted:
	var s = GDScript.new()
	s.source_code = """
extends RefCounted

var connector_defs: Array = []
"""
	s.reload()
	return s.new()


func _ramp_issues() -> Array:
	var found: Array = []
	for issue in val_sys.check_bake_issues():
		if issue is Dictionary and issue.get("type", "") == "ramp_above_agent_slope":
			found.append(issue)
	return found


# ---------------------------------------------------------------------------
# The slope the agent is given
# ---------------------------------------------------------------------------


func test_a_ramp_the_agent_can_walk_is_not_reported():
	# 0.5 over one cell is about 27 degrees, well inside the default 45.
	_two_layers_one_cell_apart(0.5)
	assert_eq(_ramp_issues().size(), 0, "a gentle ramp has nothing to say")


func test_a_ramp_steeper_than_the_agent_is_reported():
	# 3.0 over one cell is about 72 degrees. This is the shape the nav bake has
	# been quietly producing no polygons for.
	_two_layers_one_cell_apart(3.0)
	var issues := _ramp_issues()
	assert_eq(issues.size(), 1, "the steep ramp is reported once")
	if issues.is_empty():
		return
	assert_eq(issues[0]["severity"], 1, "a warning, same as the stairs check")
	assert_string_contains(issues[0]["message"], "71.6", "it names the slope it measured")
	assert_string_contains(issues[0]["message"], "45.0", "and the slope the agent accepts")


func test_raising_the_agent_slope_clears_the_report():
	_two_layers_one_cell_apart(3.0)
	assert_eq(_ramp_issues().size(), 1, "reported at the default 45")
	root.bake_navmesh_agent_max_slope = 80.0
	assert_eq(_ramp_issues().size(), 0, "an agent that walks 80 degrees can use it")


func test_a_vertical_agent_slope_reports_nothing():
	# 90 degrees accepts a wall, so there is no ramp left to complain about and
	# the arctangent never reaches it anyway.
	_two_layers_one_cell_apart(3.0)
	root.bake_navmesh_agent_max_slope = 90.0
	assert_eq(_ramp_issues().size(), 0, "nothing is steeper than vertical")


func test_a_wider_cell_makes_the_same_rise_walkable():
	# Slope is rise over run, and the run is one cell of the grid.
	_two_layers_one_cell_apart(3.0, 4.0)
	assert_eq(_ramp_issues().size(), 0, "3 over 4 cell units is about 37 degrees")


# ---------------------------------------------------------------------------
# Only the connectors that will actually be ramps
# ---------------------------------------------------------------------------


func test_no_navmesh_means_no_report():
	_two_layers_one_cell_apart(3.0)
	root.bake_navmesh = false
	assert_eq(_ramp_issues().size(), 0, "nothing pathfinds, so nothing is unwalkable")


func test_stairs_mode_has_no_ramp_to_report():
	_two_layers_one_cell_apart(3.0)
	root.bake_connector_mode = MODE_STAIRS
	assert_eq(_ramp_issues().size(), 0, "the bake builds stairs here, not a ramp")


func test_auto_mode_above_the_stair_threshold_builds_stairs():
	_two_layers_one_cell_apart(3.0)
	root.bake_connector_mode = MODE_AUTO
	root.bake_connector_stair_threshold = 2.0
	assert_eq(_ramp_issues().size(), 0, "3.0 clears the threshold, so Auto picks stairs")


func test_auto_mode_below_the_stair_threshold_still_reports():
	# The band Auto leaves open: too steep for the agent, too short for stairs.
	# 1.5 over one cell is about 56 degrees.
	_two_layers_one_cell_apart(1.5)
	root.bake_connector_mode = MODE_AUTO
	root.bake_connector_stair_threshold = 2.0
	var issues := _ramp_issues()
	assert_eq(issues.size(), 1, "Auto builds a ramp below the threshold, and it is too steep")
	if issues.is_empty():
		return
	assert_string_contains(issues[0]["message"], "56.3", "it names the slope it measured")


func test_one_layer_has_no_boundaries():
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	add_child_autoqfree(mgr)
	mgr.clear_layers()
	mgr.create_layer(&"only", 0.0)
	mgr.layers[0].set_cell(Vector2i(0, 0), true)
	root.paint_layers = mgr
	assert_eq(_ramp_issues().size(), 0, "one layer cannot make a connector")


func test_no_paint_layers_at_all():
	assert_eq(_ramp_issues().size(), 0, "a level with no paint layers has no connectors")


# ---------------------------------------------------------------------------
# Connectors the mapper placed by hand
# ---------------------------------------------------------------------------


func test_a_committed_connector_is_measured_with_auto_connectors_off():
	# A committed connector bakes whether or not auto-connectors are on, so the
	# check has to look at it either way.
	_two_layers_one_cell_apart(3.0)
	root.bake_auto_connectors = false
	_commit_connector(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(_ramp_issues().size(), 1, "the hand-placed ramp is just as unwalkable")


func test_a_null_in_the_committed_connectors_is_skipped():
	# `generate_definitions()` skips anything that is not a definition, so the
	# bake survives one and this has to as well.
	_two_layers_one_cell_apart(3.0)
	root.bake_auto_connectors = false
	var tool_shim := _paint_tool_shim()
	tool_shim.connector_defs = [null]
	root.paint_tool = tool_shim
	assert_eq(_ramp_issues().size(), 0, "nothing to measure and nothing thrown")


func test_a_height_that_is_not_a_number_is_not_reported():
	# Every comparison against NaN is false, so an unguarded slope would count as
	# too steep and then print itself as a negative angle.
	_two_layers_one_cell_apart(3.0)
	root.paint_layers.layers[1].grid.layer_y = NAN
	assert_eq(_ramp_issues().size(), 0, "an unmeasurable ramp is not a steep one")


func test_a_freed_layer_manager_is_not_walked():
	# A freed node is neither null nor safe to call into. Built and freed here
	# rather than through the helper, so nothing else holds it.
	var mgr := HFPaintLayerManagerScript.new()
	mgr.base_grid = HFPaintGridScript.new()
	root.paint_layers = mgr
	mgr.free()
	assert_eq(_ramp_issues().size(), 0, "nothing left to scan")


func test_a_long_committed_connector_has_the_run_to_match():
	# Auto-detected boundaries are always one cell apart. A committed one is not,
	# and four cells of run turns the same 3.0 rise into about 37 degrees.
	_two_layers_one_cell_apart(3.0)
	root.bake_auto_connectors = false
	_commit_connector(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(_ramp_issues().size(), 0, "3 over 4 is inside the agent's 45")
