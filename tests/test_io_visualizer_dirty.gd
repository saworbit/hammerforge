extends GutTest

## The wiring overlay used to rebuild every ten editor frames whether or not the
## graph had moved. These tests hold it still over idle frames and then make each
## kind of edit that has to bring it back.

const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFIOVisualizer = preload("res://addons/hammerforge/systems/hf_io_visualizer.gd")

const FRAME := 1.0 / 60.0

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


func _make_brush_entity(brush_name: String) -> Node3D:
	var b = Node3D.new()
	b.name = brush_name
	b.set_meta("brush_entity_class", "func_door")
	root.draft_brushes_node.add_child(b)
	return b


## A wired pair, drawn once, with the counter zeroed so a test measures only the
## rebuilds its own edit caused.
func _wired_pair() -> Array:
	var a = _make_entity("button_a", Vector3.ZERO)
	var b = _make_entity("door_b", Vector3(4, 0, 0))
	sys.add_entity_output(a, "OnUse", "door_b", "Open")
	viz.set_enabled(true)
	viz.refresh_count = 0
	return [a, b]


func _idle(frames: int) -> void:
	for i in range(frames):
		viz.process(FRAME)


# ===========================================================================
# Idle frames
# ===========================================================================


func test_idle_frames_do_not_rebuild_geometry():
	_wired_pair()
	_idle(60)
	assert_eq(viz.refresh_count, 0, "Idle frames should not rebuild the connection mesh")


func test_disabled_visualizer_does_no_work():
	_wired_pair()
	viz.set_enabled(false)
	viz.refresh_count = 0
	_idle(60)
	assert_eq(viz.refresh_count, 0, "A disabled overlay should not rebuild at all")


func test_enabling_draws_once():
	var a = _make_entity("button_a", Vector3.ZERO)
	_make_entity("door_b", Vector3(4, 0, 0))
	sys.add_entity_output(a, "OnUse", "door_b", "Open")
	viz.refresh_count = 0
	viz.set_enabled(true)
	assert_eq(viz.refresh_count, 1, "Enabling should draw exactly once")


# ===========================================================================
# Every edit that has to bring the overlay back
# ===========================================================================


func test_output_edit_rebuilds():
	var pair = _wired_pair()
	sys.add_entity_output(pair[0], "OnUse", "door_b", "Close")
	_idle(15)
	assert_eq(viz.refresh_count, 1, "A new output should rebuild the overlay")


func test_output_removal_rebuilds():
	var pair = _wired_pair()
	sys.remove_entity_output(pair[0], 0)
	_idle(15)
	assert_eq(viz.refresh_count, 1, "Removing an output should rebuild the overlay")


func test_delay_change_rebuilds():
	var pair = _wired_pair()
	var outputs: Array = pair[0].get_meta("entity_io_outputs", [])
	outputs[0]["delay"] = 2.5
	pair[0].set_meta("entity_io_outputs", outputs)
	_idle(15)
	assert_eq(viz.refresh_count, 1, "Delay drives the line colour, so it must rebuild")


func test_native_rename_rebuilds():
	var pair = _wired_pair()
	pair[1].name = "door_renamed"
	_idle(15)
	assert_eq(viz.refresh_count, 1, "A rename in the Scene dock should rebuild the overlay")


func test_alias_edit_rebuilds():
	var pair = _wired_pair()
	pair[1].set_meta("entity_name", "door_alias")
	_idle(15)
	assert_eq(viz.refresh_count, 1, "An authored-name edit should rebuild the overlay")


func test_transform_rebuilds():
	var pair = _wired_pair()
	pair[1].global_position = Vector3(9, 2, 0)
	_idle(15)
	assert_eq(viz.refresh_count, 1, "A moved entity should redraw its lines")


func test_entity_added_rebuilds():
	_wired_pair()
	_make_entity("lamp_c", Vector3(0, 3, 0))
	_idle(15)
	assert_eq(viz.refresh_count, 1, "A new entity should rebuild the overlay")


func test_entity_removed_rebuilds():
	var pair = _wired_pair()
	root.entities_node.remove_child(pair[1])
	pair[1].free()
	_idle(15)
	assert_eq(viz.refresh_count, 1, "A removed entity should rebuild the overlay")


func test_brush_entity_move_rebuilds():
	var a = _make_entity("button_a", Vector3.ZERO)
	var brush = _make_brush_entity("door_brush")
	sys.add_entity_output(a, "OnUse", "door_brush", "Open")
	viz.set_enabled(true)
	viz.refresh_count = 0
	brush.global_position = Vector3(0, 6, 0)
	_idle(15)
	assert_eq(viz.refresh_count, 1, "Brush entities are drawn too, so they count as state")


func test_selection_change_rebuilds():
	var pair = _wired_pair()
	viz.set_selected_entities([pair[0]])
	assert_eq(viz.refresh_count, 1, "Selection recolours the lines, so it redraws")


func test_mark_dirty_forces_one_rebuild():
	_wired_pair()
	viz.mark_dirty()
	_idle(15)
	assert_eq(viz.refresh_count, 1, "mark_dirty should be honoured")
	_idle(30)
	assert_eq(viz.refresh_count, 1, "and it should not stick on")


func test_freed_mesh_instance_rebuilds():
	_wired_pair()
	var mesh_instance: MeshInstance3D = viz._mesh_instance
	root.remove_child(mesh_instance)
	mesh_instance.free()
	_idle(15)
	assert_eq(viz.refresh_count, 1, "A lost mesh node should be rebuilt")


# ===========================================================================
# Highlight overlays
# ===========================================================================


func test_highlight_overlays_are_reused_across_rebuilds():
	var pair = _wired_pair()
	viz.set_highlight_connected(true)
	viz.set_selected_entities([pair[0]])
	assert_eq(viz._highlight_overlays.size(), 1, "The connected door should be highlighted")
	var first_id = viz._highlight_overlays[0].get_instance_id()
	pair[1].global_position = Vector3(7, 0, 0)
	_idle(15)
	assert_eq(viz._highlight_overlays.size(), 1, "Still one highlighted entity")
	assert_eq(
		viz._highlight_overlays[0].get_instance_id(),
		first_id,
		"The pulse sphere should be moved, not thrown away and remade"
	)


func test_highlight_overlays_follow_the_entity():
	var pair = _wired_pair()
	viz.set_highlight_connected(true)
	viz.set_selected_entities([pair[0]])
	pair[1].global_position = Vector3(7, 0, 0)
	_idle(15)
	assert_almost_eq(
		viz._highlight_overlays[0].global_position,
		Vector3(7, 0.3, 0),
		Vector3.ONE * 0.001,
		"A reused sphere has to be moved onto its entity"
	)


func test_highlight_overlays_shrink_when_connections_go():
	var pair = _wired_pair()
	var c = _make_entity("door_c", Vector3(0, 0, 4))
	sys.add_entity_output(pair[0], "OnUse", "door_c", "Open")
	viz.set_highlight_connected(true)
	viz.set_selected_entities([pair[0]])
	assert_eq(viz._highlight_overlays.size(), 2, "Both doors are connected")
	root.entities_node.remove_child(c)
	c.free()
	_idle(15)
	assert_eq(viz._highlight_overlays.size(), 1, "The spare sphere should be released")


func test_idle_frames_do_not_churn_overlay_nodes():
	var pair = _wired_pair()
	viz.set_highlight_connected(true)
	viz.set_selected_entities([pair[0]])
	var first_id = viz._highlight_overlays[0].get_instance_id()
	var child_count = root.get_child_count()
	_idle(60)
	assert_eq(root.get_child_count(), child_count, "Idle frames should not add scene nodes")
	assert_eq(
		viz._highlight_overlays[0].get_instance_id(), first_id, "Nor replace the pulse spheres"
	)


func test_pulse_uses_the_real_delta():
	var pair = _wired_pair()
	viz.set_highlight_connected(true)
	viz.set_selected_entities([pair[0]])
	viz._pulse_phase = 0.0
	viz.process(0.5)
	assert_almost_eq(
		viz._pulse_phase,
		0.5 * HFIOVisualizer.PULSE_SPEED,
		0.0001,
		"The pulse should advance by the frame time it was given"
	)


# ===========================================================================
# Name index
# ===========================================================================


func test_name_index_matches_lookup_for_node_names():
	var e = _make_entity("button_a")
	var index = sys.build_name_index()
	assert_eq(index.get("button_a", []), [e], "Node name should resolve to the node")
	assert_eq(index.get("button_a", []), sys.find_entities_by_name("button_a"))


func test_name_index_matches_lookup_for_aliases():
	var e = _make_entity("Node3D42")
	e.set_meta("entity_name", "big_red_button")
	var index = sys.build_name_index()
	assert_eq(index.get("big_red_button", []), [e], "The authored name is an address too")
	assert_eq(index.get("big_red_button", []), sys.find_entities_by_name("big_red_button"))


func test_name_index_lists_an_entity_once_when_both_names_agree():
	var e = _make_entity("button_a")
	e.set_meta("entity_name", "button_a")
	var index = sys.build_name_index()
	assert_eq(index.get("button_a", []).size(), 1, "One node, one entry")
	assert_eq(index.get("button_a", []), sys.find_entities_by_name("button_a"))


func test_name_index_holds_both_entities_sharing_a_name():
	var first = _make_entity("Node3D1")
	first.set_meta("entity_name", "shared")
	var second = _make_entity("Node3D2")
	second.set_meta("entity_name", "shared")
	var index = sys.build_name_index()
	assert_eq(index.get("shared", []), [first, second], "Duplicated names both resolve")
	assert_eq(index.get("shared", []), sys.find_entities_by_name("shared"))


func test_name_index_covers_brush_entities_by_node_name_only():
	var brush = _make_brush_entity("door_brush")
	brush.set_meta("entity_name", "brush_alias")
	var index = sys.build_name_index()
	assert_eq(index.get("door_brush", []), [brush], "Brush entities answer to their node name")
	assert_false(
		index.has("brush_alias"), "and not to an alias, the way find_entities_by_name has it"
	)
	assert_eq(sys.find_entities_by_name("brush_alias"), [], "Lookup agrees")


func test_name_index_skips_plain_brushes():
	var plain = Node3D.new()
	plain.name = "brush_1"
	root.draft_brushes_node.add_child(plain)
	var index = sys.build_name_index()
	assert_false(index.has("brush_1"), "A brush with no entity class is not an I/O target")


# ===========================================================================
# Nothing left to draw
# ===========================================================================


func test_dangling_only_graph_hides_the_mesh():
	var pair = _wired_pair()
	pair[1].name = "door_renamed"
	_idle(15)
	assert_false(viz._mesh_instance.visible, "Nothing resolves, so nothing should be drawn")


func test_graph_comes_back_when_the_target_returns():
	var pair = _wired_pair()
	pair[1].name = "door_renamed"
	_idle(15)
	pair[1].name = "door_b"
	_idle(15)
	assert_true(viz._mesh_instance.visible, "Renaming back should redraw the line")
