extends GutTest

## Bake Check warns when connector stairs rise higher per step than the navmesh
## agent can climb (#701). The check was four lines of control flow with nothing
## asserting any of them (#801), and one of those lines is a boundary that has
## to stay exactly where it is: `bake_connector_stair_height` and
## `bake_navmesh_agent_max_climb` both default to 0.25, so a stock project sits
## on the limit and must not be warned about. Read as an off-by-one and tightened
## to `<`, that warns every default project and the suite stayed green.
##
## The sibling check on the ramp half is pinned in
## `tests/test_bake_issues_ramp_slope.gd`.

const HFValidationSystem = preload("res://addons/hammerforge/systems/hf_validation_system.gd")

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
## gates the whole check is silence. These tests turn it on and then vary the
## two numbers, which is the state a mapper who wants generated stairs is in.
##
## The mode is Stairs because that is the level this warning is about, not
## because the check reads it. It does not, and in Ramp mode it still warns
## about stairs the bake will never build (#802). Written this way so the tests
## describe a level with stairs in it either way.
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
	assert_eq(root.bake_connector_stair_height, root.bake_navmesh_agent_max_climb)
	assert_eq(_stair_issues().size(), 0, "a stair exactly on the limit is climbable")


func test_a_step_taller_than_the_climb_is_reported():
	root.bake_connector_stair_height = 0.5
	var issues := _stair_issues()
	assert_eq(issues.size(), 1, "the unclimbable stair is reported once")
	if issues.is_empty():
		return
	assert_eq(issues[0]["severity"], 1, "a warning, same as the ramp check")
	# Anchored on the words either side, because both numbers appear in the
	# message and an assertion for the bare digits reads the same whichever way
	# round they are printed.
	assert_string_contains(
		issues[0]["message"], "rise 0.50 per step", "it names the step it measured"
	)
	assert_string_contains(issues[0]["message"], "can climb 0.25", "and the climb the agent has")
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
	root.bake_connector_stair_height = DEFAULT_CLIMB + 0.001
	assert_eq(_stair_issues().size(), 1, "anything above the limit is above it")


func test_raising_the_agent_climb_clears_the_report():
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported at the default climb")
	root.bake_navmesh_agent_max_climb = 0.6
	assert_eq(_stair_issues().size(), 0, "an agent that climbs 0.6 can use a 0.5 step")


func test_lowering_the_step_clears_the_report():
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported at a 0.5 step")
	root.bake_connector_stair_height = 0.2
	assert_eq(_stair_issues().size(), 0, "a shorter step is within reach again")


# ---------------------------------------------------------------------------
# The three early returns
# ---------------------------------------------------------------------------


func test_no_navmesh_means_no_report():
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported while the navmesh is on")
	root.bake_navmesh = false
	assert_eq(_stair_issues().size(), 0, "nothing pathfinds, so nothing is stuck")


func test_no_auto_connectors_means_no_report():
	root.bake_connector_stair_height = 0.5
	assert_eq(_stair_issues().size(), 1, "reported while auto-connectors are on")
	root.bake_auto_connectors = false
	assert_eq(_stair_issues().size(), 0, "the bake builds no stairs to be stuck on")


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
	# report that the agent can climb 0.00.
	root.bake_connector_stair_height = 0.5
	root.bake_navmesh_agent_max_climb = 0.0
	assert_eq(_stair_issues().size(), 0, "an unset climb is unknown, not zero")
