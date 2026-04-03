extends GutTest

const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFIOVisualizer = preload("res://addons/hammerforge/systems/hf_io_visualizer.gd")

var root: Node3D
var sys: HFEntitySystem
var viz: HFIOVisualizer


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.entity_definitions = {}
	root.entity_definitions_path = ""
	sys = HFEntitySystem.new(root)
	root.entity_system = sys
	viz = HFIOVisualizer.new(root)


func after_each():
	viz.cleanup()
	root = null
	sys = null
	viz = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
var entity_system = null

func _assign_owner(node: Node) -> void:
	pass

func get_selected_entities() -> Array:
	return []
"""
	s.reload()
	return s


func _make_entity(entity_name: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var e = Node3D.new()
	e.name = entity_name
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	e.global_position = pos
	return e


# ===========================================================================
# Color logic
# ===========================================================================


func test_get_connection_color_selected():
	var color = viz._get_connection_color("OnTrigger", false, 0.0, true)
	assert_eq(color, HFIOVisualizer.SELECTED_COLOR, "Selected connection should be yellow")


func test_get_connection_color_fire_once():
	var color = viz._get_connection_color("OnTrigger", true, 0.0, false)
	assert_eq(color, HFIOVisualizer.FIRE_ONCE_COLOR, "Fire-once should be orange")


func test_get_connection_color_by_type():
	var color = viz._get_connection_color("OnTrigger", false, 0.0, false)
	assert_eq(color, HFIOVisualizer.TYPE_COLORS["OnTrigger"], "OnTrigger should be cyan")


func test_get_connection_color_on_damage():
	var color = viz._get_connection_color("OnDamage", false, 0.0, false)
	assert_eq(color, HFIOVisualizer.TYPE_COLORS["OnDamage"], "OnDamage should be red")


func test_get_connection_color_default():
	var color = viz._get_connection_color("CustomOutput", false, 0.0, false)
	assert_eq(color, HFIOVisualizer.DEFAULT_COLOR, "Unknown output should use default green")


func test_get_connection_color_delay_dims():
	var c_no_delay = viz._get_connection_color("CustomOutput", false, 0.0, false)
	var c_with_delay = viz._get_connection_color("CustomOutput", false, 5.0, false)
	assert_true(c_with_delay.v < c_no_delay.v, "Delayed connection should be darker")


# ===========================================================================
# Bézier math
# ===========================================================================


func test_quadratic_bezier_endpoints():
	var p0 = Vector3(0, 0, 0)
	var p1 = Vector3(1, 2, 0)
	var p2 = Vector3(2, 0, 0)
	var start = viz._quadratic_bezier(p0, p1, p2, 0.0)
	var end = viz._quadratic_bezier(p0, p1, p2, 1.0)
	assert_almost_eq(start.x, 0.0, 0.001)
	assert_almost_eq(start.y, 0.0, 0.001)
	assert_almost_eq(end.x, 2.0, 0.001)
	assert_almost_eq(end.y, 0.0, 0.001)


func test_quadratic_bezier_midpoint():
	var p0 = Vector3(0, 0, 0)
	var p1 = Vector3(1, 2, 0)
	var p2 = Vector3(2, 0, 0)
	var mid = viz._quadratic_bezier(p0, p1, p2, 0.5)
	assert_almost_eq(mid.x, 1.0, 0.001)
	assert_almost_eq(mid.y, 1.0, 0.001, "Midpoint should be at control point influence")


func test_quadratic_bezier_tangent_not_zero():
	var p0 = Vector3(0, 0, 0)
	var p1 = Vector3(1, 2, 0)
	var p2 = Vector3(2, 0, 0)
	var tangent = viz._quadratic_bezier_tangent(p0, p1, p2, 0.5)
	assert_true(tangent.length() > 0.01, "Tangent should not be zero at midpoint")


# ===========================================================================
# Connection summary
# ===========================================================================


func test_connection_summary_empty():
	_make_entity("trigger_1")
	var summary = viz.get_connection_summary("trigger_1")
	assert_eq(summary["triggers"], 0)
	assert_eq(summary["triggered_by"], 0)


func test_connection_summary_outgoing():
	var e = _make_entity("trigger_1")
	_make_entity("door_1")
	_make_entity("light_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open")
	sys.add_entity_output(e, "OnTrigger", "light_1", "TurnOn")
	var summary = viz.get_connection_summary("trigger_1")
	assert_eq(summary["triggers"], 2, "Should have 2 outgoing connections")
	assert_eq(summary["target_names"].size(), 2, "Should have 2 unique targets")


func test_connection_summary_incoming():
	var e1 = _make_entity("button_1")
	var e2 = _make_entity("switch_1")
	_make_entity("door_1")
	sys.add_entity_output(e1, "OnPressed", "door_1", "Open")
	sys.add_entity_output(e2, "OnActivate", "door_1", "Toggle")
	var summary = viz.get_connection_summary("door_1")
	assert_eq(summary["triggered_by"], 2, "Should have 2 incoming connections")
	assert_eq(summary["source_names"].size(), 2)


func test_connection_summary_both_directions():
	var e1 = _make_entity("relay_1")
	var e2 = _make_entity("door_1")
	sys.add_entity_output(e1, "OnTrigger", "door_1", "Open")
	sys.add_entity_output(e2, "OnClose", "relay_1", "Reset")
	var summary = viz.get_connection_summary("relay_1")
	assert_eq(summary["triggers"], 1)
	assert_eq(summary["triggered_by"], 1)


func test_connection_summary_details():
	var e = _make_entity("trigger_1")
	_make_entity("door_1")
	sys.add_entity_output(e, "OnTrigger", "door_1", "Open")
	var summary = viz.get_connection_summary("trigger_1")
	assert_eq(summary["details"].size(), 1)
	assert_eq(summary["details"][0], "OnTrigger → door_1.Open")


# ===========================================================================
# Highlight Connected
# ===========================================================================


func test_highlight_connected_default_off():
	assert_false(viz.highlight_connected, "Highlight should be off by default")


func test_set_highlight_connected():
	viz.set_highlight_connected(true)
	assert_true(viz.highlight_connected)
	viz.set_highlight_connected(false)
	assert_false(viz.highlight_connected)


func test_highlight_off_clears_overlays():
	viz.set_enabled(true)
	viz.set_highlight_connected(true)
	# Add some overlays manually
	var overlay = MeshInstance3D.new()
	overlay.set_meta("_io_pulse_overlay", true)
	root.add_child(overlay)
	viz._highlight_overlays.append(overlay)
	# Turn off
	viz.set_highlight_connected(false)
	assert_eq(viz._highlight_overlays.size(), 0, "Overlays should be cleared")


# ===========================================================================
# Enable/disable
# ===========================================================================


func test_enable_disable():
	viz.set_enabled(true)
	assert_true(viz.enabled)
	viz.set_enabled(false)
	assert_false(viz.enabled)


func test_disable_clears_overlays():
	viz.set_enabled(true)
	viz.set_highlight_connected(true)
	var overlay = MeshInstance3D.new()
	overlay.set_meta("_io_pulse_overlay", true)
	root.add_child(overlay)
	viz._highlight_overlays.append(overlay)
	viz.set_enabled(false)
	assert_eq(viz._highlight_overlays.size(), 0)


func test_cleanup():
	viz.set_enabled(true)
	viz.refresh()
	viz.cleanup()
	assert_eq(viz._highlight_overlays.size(), 0)
	assert_null(viz._immediate_mesh)
