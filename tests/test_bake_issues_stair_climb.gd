extends GutTest

## Bake Check warns when connector stairs rise higher per step than the navmesh
## agent can climb (#701). The check was four lines of control flow with nothing
## asserting any of them (#801), and one of those lines is a boundary that has
## to stay exactly where it is: `bake_connector_stair_height` and
## `bake_navmesh_agent_max_climb` both default to 0.25, so a stock project sits
## on the limit and must not be warned about. Read as an off-by-one and tightened
## to `<`, that warns every default project and the suite stayed green.
##
## Those tests compared two settings, because that is all the check did. It did
## not read the connector mode, so it warned about generated stairs in Ramp mode
## where the bake builds none, and said nothing about a staircase the mapper
## committed by hand, which bakes whether or not auto-connectors are on (#802).
## The check now works out the connectors the bake will actually build, so these
## describe a level with stairs in it rather than a root with two numbers on it.
##
## The sibling check on the ramp half is pinned in
## `tests/test_bake_issues_ramp_slope.gd`.

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

# Both defaults, held here so a test that changes one says which way it moved.
const DEFAULT_STEP := 0.25
const DEFAULT_CLIMB := 0.25

var root: Node3D
var val_sys: HFValidationSystem


func before_each():
	root = _root_with_bake_settings()
	val_sys = HFValidationSystem.new(root)


func after_each():
	root = null
	val_sys = null


## A root carrying the bake settings the check reads, with auto-connectors on
## and the connector mode set to Stairs.
##
## `bake_auto_connectors` ships off, so the stock value of the one setting that
## gates generated connectors is silence. These tests turn it on and then vary
## the mode and the two numbers, which is the state a mapper who wants generated
## stairs is in.
func _root_with_bake_settings() -> Node3D:
	var node := Node3D.new()
	var s = GDScript.new()
	s.source_code = (
		"""
extends Node3D

var draft_brushes_node: Node3D
var committed_node: Node3D
var paint_layers = null
var paint_tool = null
var bake_navmesh: bool = true
var bake_auto_connectors: bool = true
var bake_navmesh_agent_max_slope: float = 45.0
var bake_navmesh_agent_max_climb: float = %f
var bake_connector_mode: int = 1
var bake_connector_stair_height: float = %f
var bake_connector_width: int = 2
var bake_connector_stair_threshold: float = 2.0

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")
"""
		% [DEFAULT_CLIMB, DEFAULT_STEP]
	)
	s.reload()
	node.set_script(s)
	add_child_autoqfree(node)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	node.add_child(draft)
	node.draft_brushes_node = draft
	var committed = Node3D.new()
	committed.name = "Committed"
	node.add_child(committed)
	node.committed_node = committed
	return node


## Two painted layers a cell apart, the lower one at world Y 0 and the upper one
## at `rise`. That is one boundary, so the bake builds one connector across it.
func _two_layers_one_cell_apart(rise: float) -> void:
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	mgr.base_grid.cell_size = 1.0
	add_child_autoqfree(mgr)
	mgr.clear_layers()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", rise)
	mgr.layers[0].set_cell(Vector2i(0, 0), true)
	mgr.layers[1].set_cell(Vector2i(1, 0), true)
	root.paint_layers = mgr


## A staircase the mapper committed with the connector tool, which bakes whether
## or not auto-connectors are on and carries its own step height.
func _commit_stairs(step_height: float, to_cell: Vector2i = Vector2i(1, 0)) -> void:
	root.paint_layers.layers[1].set_cell(to_cell, true)
	var def := HFConnectorToolScript.ConnectorDef.new()
	def.from_layer_index = 0
	def.to_layer_index = 1
	def.from_cell = Vector2i(0, 0)
	def.to_cell = to_cell
	def.connector_type = HFConnectorToolScript.ConnectorType.STAIRS
	def.stair_step_height = step_height
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


func _stair_issues() -> Array:
	var found: Array = []
	for issue in val_sys.check_bake_issues():
		if issue is Dictionary and issue.get("type", "") == "stairs_above_agent_climb":
			found.append(issue)
	return found


# ---------------------------------------------------------------------------
# The boundary
# ---------------------------------------------------------------------------


func test_a_step_equal_to_the_climb_is_the_stock_project():
	# The reason the comparison is `<=` and not `<`. Godot's NavigationMesh
	# defaults agent_max_climb to 0.25 and the auto-connector's step defaults to
	# the same, so every fresh project lands exactly here. Tighten the guard and
	# this is the test that goes red.
	_two_layers_one_cell_apart(1.0)
	assert_eq(root.bake_connector_stair_height, root.bake_navmesh_agent_max_climb)
	assert_eq(_stair_issues().size(), 0, "a stair exactly on the limit is climbable")


func test_a_step_taller_than_the_climb_is_reported():
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = 0.5
	var issues := _stair_issues()
	assert_eq(issues.size(), 1, "the unclimbable staircase is reported once")
	if issues.is_empty():
		return
	assert_eq(issues[0]["severity"], 1, "a warning, same as the ramp check")
	# Anchored on the words either side, because both numbers appear in the
	# message and an assertion for the bare digits reads the same whichever way
	# round they are printed.
	assert_string_contains(
		issues[0]["message"], "rises 0.50 per step", "it names the step it measured"
	)
	assert_string_contains(issues[0]["message"], "agent climbs 0.25", "and the climb the agent has")
	assert_string_contains(issues[0]["message"], "cell (0, 0)", "and where the boundary is")
	# By id: `assert_eq` stringifies what it is given, and a node carrying a
	# dynamic shim script has no resource file for `inst_to_dict()` to read.
	assert_eq(
		issues[0]["node"].get_instance_id(),
		root.get_instance_id(),
		"the report points at the level, which is what the Bake Check clicks through to"
	)


func test_a_step_a_hair_over_the_climb_is_still_reported():
	# The other side of the same boundary. Equal is silence, over is not, and
	# there is no tolerance band between them.
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = DEFAULT_CLIMB + 0.001
	assert_eq(_stair_issues().size(), 1, "anything above the limit is above it")


func test_raising_the_agent_climb_clears_the_report():
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported at the default climb")
	root.bake_navmesh_agent_max_climb = 0.6
	assert_eq(_stair_issues().size(), 0, "an agent that climbs 0.6 can use a 0.5 step")


func test_lowering_the_step_clears_the_report():
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported at a 0.5 step")
	root.bake_connector_stair_height = 0.2
	assert_eq(_stair_issues().size(), 0, "a shorter step is within reach again")


# ---------------------------------------------------------------------------
# Only the connectors that will actually be stairs
# ---------------------------------------------------------------------------


func test_ramp_mode_has_no_stairs_to_report():
	# Ramp is the default mode, and in it `HFAutoConnector` sets every boundary
	# to a ramp and never reads the step height at all. Warning here told a
	# mapper their stairs were unclimbable when the bake was not building any
	# (#802).
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_mode = MODE_RAMP
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 0, "the bake builds a ramp here, not stairs")


func test_auto_mode_below_the_stair_threshold_builds_no_stairs():
	# Auto picks per boundary, and a drop shorter than the threshold is a ramp.
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_mode = MODE_AUTO
	root.bake_connector_stair_threshold = 2.0
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 0, "1.0 is under the threshold, so Auto picks a ramp")


func test_auto_mode_above_the_stair_threshold_is_reported():
	_two_layers_one_cell_apart(3.0)
	root.bake_connector_mode = MODE_AUTO
	root.bake_connector_stair_threshold = 2.0
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "3.0 clears the threshold, so Auto builds stairs")


func test_no_navmesh_means_no_report():
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported while the navmesh is on")
	root.bake_navmesh = false
	assert_eq(_stair_issues().size(), 0, "nothing pathfinds, so nothing is stuck")


func test_no_auto_connectors_means_no_generated_stairs():
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported while auto-connectors are on")
	root.bake_auto_connectors = false
	assert_eq(_stair_issues().size(), 0, "nothing detects the boundary, so nothing is built")


func test_no_paint_layers_at_all():
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 0, "a level with no paint layers has no connectors")


func test_one_layer_has_no_boundaries():
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	add_child_autoqfree(mgr)
	mgr.clear_layers()
	mgr.create_layer(&"only", 0.0)
	mgr.layers[0].set_cell(Vector2i(0, 0), true)
	root.paint_layers = mgr
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 0, "one layer cannot make a connector")


func test_a_root_with_neither_setting_reports_nothing():
	# `LevelRoot` bounds both numbers at 0.01, so zero is not a value a mapper
	# can reach. What this guards is a root that does not carry the properties at
	# all, which `get()` answers with null and `_root_number()` reads as zero.
	var bare := Node3D.new()
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var committed_node: Node3D
var paint_layers = null
var paint_tool = null
var bake_navmesh: bool = true
var bake_auto_connectors: bool = true

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")
"""
	s.reload()
	bare.set_script(s)
	add_child_autoqfree(bare)
	val_sys = HFValidationSystem.new(bare)
	assert_eq(_stair_issues().size(), 0, "no numbers to compare and nothing thrown")


func test_a_zero_climb_reports_nothing():
	# The only half of the zero guard that does any work. A zero step is already
	# silent through `step <= climb`, so a test for it would pass with the guard
	# deleted; a zero climb with a real step is the case that would otherwise
	# report that the agent climbs 0.00.
	_two_layers_one_cell_apart(1.0)
	root.bake_connector_stair_height = 0.5
	root.bake_navmesh_agent_max_climb = 0.0
	assert_eq(_stair_issues().size(), 0, "an unset climb is unknown, not zero")


# ---------------------------------------------------------------------------
# Staircases the mapper placed by hand
# ---------------------------------------------------------------------------


func test_a_committed_staircase_is_measured_with_auto_connectors_off():
	# A committed connector bakes whether or not auto-connectors are on, so the
	# check has to look at it either way. It returned at the first line before
	# (#802), which is the half of this that reported nothing at all.
	_two_layers_one_cell_apart(1.0)
	root.bake_auto_connectors = false
	_commit_stairs(0.5)
	assert_eq(_stair_issues().size(), 1, "the hand-placed staircase is just as unclimbable")


func test_a_committed_staircase_carries_its_own_step():
	# The root setting is the generator's, not the connector's. A committed
	# staircase keeps the step it was drawn with, and that is the number to
	# measure and the number to print.
	_two_layers_one_cell_apart(1.0)
	root.bake_auto_connectors = false
	root.bake_connector_stair_height = DEFAULT_STEP
	_commit_stairs(0.75)
	var issues := _stair_issues()
	assert_eq(issues.size(), 1, "measured against its own step, not the root's")
	if issues.is_empty():
		return
	assert_string_contains(issues[0]["message"], "rises 0.75 per step", "it names that step")


func test_a_committed_ramp_is_not_a_staircase():
	_two_layers_one_cell_apart(1.0)
	root.bake_auto_connectors = false
	root.paint_layers.layers[1].set_cell(Vector2i(1, 0), true)
	var def := HFConnectorToolScript.ConnectorDef.new()
	def.from_layer_index = 0
	def.to_layer_index = 1
	def.from_cell = Vector2i(0, 0)
	def.to_cell = Vector2i(1, 0)
	def.connector_type = HFConnectorToolScript.ConnectorType.RAMP
	def.stair_step_height = 0.5
	var tool_shim := _paint_tool_shim()
	tool_shim.connector_defs = [def]
	root.paint_tool = tool_shim
	assert_eq(_stair_issues().size(), 0, "a ramp's step height is a field the bake never reads")


func test_a_committed_staircase_over_erased_cells_is_not_measured():
	# `generate_connector()` returns null when the definition does not point at
	# two painted cells, so this one bakes nothing. A definition outliving the
	# cells it was drawn between is what erasing a terrace does.
	_two_layers_one_cell_apart(1.0)
	root.bake_auto_connectors = false
	_commit_stairs(0.5)
	root.paint_layers.layers[0].set_cell(Vector2i(0, 0), false)
	assert_eq(_stair_issues().size(), 0, "nothing will be built, so nothing is unclimbable")


func test_a_null_in_the_committed_connectors_is_skipped():
	# `generate_definitions()` skips anything that is not a definition, so the
	# bake survives one and this has to as well.
	_two_layers_one_cell_apart(1.0)
	root.bake_auto_connectors = false
	var tool_shim := _paint_tool_shim()
	tool_shim.connector_defs = [null]
	root.paint_tool = tool_shim
	assert_eq(_stair_issues().size(), 0, "nothing to measure and nothing thrown")


func test_a_step_that_is_not_a_number_is_not_reported():
	# Every comparison against NaN is false, so an unguarded step would fall
	# through the limit test and print itself as a nan rise. `ConnectorDef`'s
	# `from_dict()` floors the step with `maxf()`, which passes NaN straight
	# through, so a corrupt level file is a way to reach this.
	_two_layers_one_cell_apart(1.0)
	root.bake_auto_connectors = false
	_commit_stairs(NAN)
	assert_eq(_stair_issues().size(), 0, "an unmeasurable step is not a tall one")


func test_a_freed_layer_manager_is_not_walked():
	# A freed node is neither null nor safe to call into. Built and freed here
	# rather than through the helper, so nothing else holds it.
	var mgr := HFPaintLayerManagerScript.new()
	mgr.base_grid = HFPaintGridScript.new()
	root.paint_layers = mgr
	root.bake_connector_stair_height = 0.5
	mgr.free()
	assert_eq(_stair_issues().size(), 0, "nothing left to scan")


# ---------------------------------------------------------------------------
# The cost of asking twice
# ---------------------------------------------------------------------------


func test_both_connector_checks_share_one_scan():
	# The stairs half used to compare two settings and the ramp half worked the
	# connectors out, so only one of them paid for the walk. Now both want the
	# same list, and `detect_boundaries()` visits every cell of every chunk of
	# every layer. Without the memo this doubles on every Bake Check press.
	_two_layers_one_cell_apart(1.0)
	val_sys.check_bake_issues()
	assert_eq(val_sys.connector_scans, 1, "both checks read one list")


func test_the_scan_is_redone_on_the_next_press():
	# The memo is per pass, not per system. Painting a cell changes the answer
	# and nothing tells this system when that happens, so holding it between
	# presses would report on a level that is no longer there.
	_two_layers_one_cell_apart(1.0)
	val_sys.check_bake_issues()
	root.paint_layers.layers[1].set_cell(Vector2i(2, 0), true)
	val_sys.check_bake_issues()
	assert_eq(val_sys.connector_scans, 1, "counted fresh, so the second press rebuilt it")
