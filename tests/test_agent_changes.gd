extends "res://tests/mcp/mcp_dispatcher_case.gd"

## What an agent just changed over the bridge, outlined in the viewport for a
## moment, with an arrow at the edge when it is out of view, and selected by a
## click on the panel's Last line (#1653).

const HFPluginMcp = preload("res://addons/hammerforge/plugin_mcp.gd")
const HFMcpPanel = preload("res://addons/hammerforge/ui/hf_mcp_panel.gd")
const HFAgentHighlight = preload("res://addons/hammerforge/hf_agent_highlight.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFOverlayColors = preload("res://addons/hammerforge/hf_overlay_colors.gd")


class FakeSelection:
	extends RefCounted

	var nodes: Array = []

	func clear() -> void:
		nodes.clear()

	func add_node(node: Node) -> void:
		nodes.append(node)


class FakeEditor:
	extends RefCounted

	var selection := FakeSelection.new()

	func get_selection():
		return selection


class FakeDock:
	extends Node

	var mcp_panel = null


## The fields and delegates of the real plugin that the highlight reads.
class FakePlugin:
	extends Node

	var dock = null
	var mcp_dispatcher = null
	var mcp_listener: Node = null
	var active_root: LevelRoot = null
	var _user_prefs = null
	var _agent_highlight = null
	var _mcp_last_changed: Dictionary = {}
	var editor := FakeEditor.new()
	var redraws := 0

	func get_editor_interface():
		return editor

	func update_overlays() -> int:
		redraws += 1
		return 0

	func _on_mcp_last_pressed() -> void:
		HFPluginMcp.select_last_changed(self, _mcp_last_changed)


var level: LevelRoot
var plugin: FakePlugin
var panel


func before_each() -> void:
	super.before_each()
	level = make_level()
	plugin = FakePlugin.new()
	plugin.dock = FakeDock.new()
	panel = HFMcpPanel.new()
	plugin.dock.mcp_panel = panel
	plugin.dock.add_child(panel)
	plugin.add_child(plugin.dock)
	plugin.active_root = level
	plugin.mcp_dispatcher = dispatcher
	plugin._user_prefs = HFUserPrefsType.new()
	add_child_autoqfree(plugin)
	HFOverlayColors.reset()


func after_each() -> void:
	if plugin._agent_highlight:
		plugin._agent_highlight.clear()
	HFOverlayColors.reset()
	super.after_each()


func _outline() -> Node:
	for child in level.get_children(true):
		if str(child.name) == HFAgentHighlight.NODE_NAME:
			return child
	return null


func _finish(method: String, ok := true) -> void:
	HFPluginMcp.show_last(plugin, method, ok, "" if ok else "invalid_argument", 5)


# --- What the dispatcher records ----------------------------------------------


func test_a_placed_brush_is_recorded_as_changed():
	var brush_id := await place_box()
	assert_eq(dispatcher.last_changed.get("brush_ids"), [brush_id])
	assert_eq(dispatcher.last_changed.get("removed"), 0)


func test_a_moved_brush_is_recorded_and_the_others_are_not():
	var moved := await place_box([0, 1, 0])
	await place_box([6, 1, 0])
	var answer := await call_tool("hf_transform_brush", {"brush_id": moved, "position": [0, 1, 4]})
	assert_true(answer.get("ok", false), str(answer).left(200))
	assert_eq(dispatcher.last_changed.get("brush_ids"), [moved], "only the one it moved")


func test_a_deleted_brush_counts_as_removed_with_nothing_to_outline():
	var brush_id := await place_box()
	var answer := await call_tool("hf_delete_brush", {"brush_id": brush_id})
	assert_true(answer.get("ok", false), str(answer).left(200))
	assert_eq(dispatcher.last_changed.get("brush_ids"), [])
	assert_eq(dispatcher.last_changed.get("removed"), 1)


func test_a_placed_entity_is_recorded():
	var answer := await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [0, 2, 0]}
	)
	assert_true(answer.get("ok", false), str(answer).left(200))
	var entities: Array = dispatcher.last_changed.get("entities", [])
	assert_eq(entities.size(), 1)
	assert_true(entities[0] is Node3D and level.entities_node.is_ancestor_of(entities[0]))


func test_a_moved_entity_is_recorded_and_the_others_are_not():
	await call_tool("hf_place_entity", {"entity_class": "light_point", "position": [0, 2, 0]})
	var placed := await call_tool(
		"hf_place_entity", {"entity_class": "light_point", "position": [6, 2, 0]}
	)
	var path := str(placed["result"]["entity"]["entity"])
	var answer := await call_tool("hf_transform_entity", {"entity": path, "position": [6, 2, 4]})
	assert_true(answer.get("ok", false), str(answer).left(200))
	var entities: Array = dispatcher.last_changed.get("entities", [])
	assert_eq(entities, [level.get_node(NodePath(path))], "only the one it moved")


func test_a_refused_change_records_nothing():
	await place_box()
	dispatcher.last_changed = {}
	var answer := await call_tool("hf_place_brush", {"size": [0, 0, 0]})
	assert_false(answer.get("ok", true))
	assert_eq(dispatcher.last_changed, {})


# --- The outline --------------------------------------------------------------


func test_the_change_is_outlined_in_the_agent_colour_and_fades_away():
	await place_box()
	_finish("hf_place_brush")
	var outline := _outline() as MeshInstance3D
	assert_not_null(outline, "outlined")
	if outline == null:
		return
	assert_eq(outline.owner, null, "never saved with the level")
	var color: Color = outline.material_override.albedo_color
	assert_true(
		Color(color, 1.0).is_equal_approx(HFOverlayColors.DEFAULTS[HFOverlayColors.AGENT_CHANGE])
	)
	assert_eq(dispatcher.last_changed, {}, "taken, so the next answer starts clean")
	await get_tree().create_timer(HFAgentHighlight.SECONDS + 0.3).timeout
	assert_null(_outline(), "gone once it has faded")
	assert_false(plugin._agent_highlight.is_showing())
	assert_gt(plugin.redraws, 1, "the arrow is taken down with it")


func test_the_outline_follows_the_high_contrast_colours():
	var prefs = HFUserPrefsType.new()
	prefs.set_pref(
		HFOverlayColors.AGENT_CHANGE, HFOverlayColors.HIGH_CONTRAST[HFOverlayColors.AGENT_CHANGE]
	)
	HFOverlayColors.apply_prefs(prefs)
	await place_box()
	_finish("hf_place_brush")
	var outline := _outline() as MeshInstance3D
	assert_not_null(outline)
	if outline:
		# The pref keeps eight bits a channel, so near the preset, not exact.
		var color: Color = outline.material_override.albedo_color
		var preset: Color = HFOverlayColors.HIGH_CONTRAST[HFOverlayColors.AGENT_CHANGE]
		for channel in [0, 1, 2]:
			assert_almost_eq(color[channel], preset[channel], 0.005, "channel %d" % channel)


func test_show_agent_changes_off_outlines_nothing():
	plugin._user_prefs.set_pref("show_agent_changes", false)
	await place_box()
	_finish("hf_place_brush")
	assert_null(_outline())


func test_a_refused_call_outlines_nothing():
	await place_box()
	_finish("hf_place_brush", false)
	assert_null(_outline())


func test_the_last_line_says_how_many_it_removed():
	var brush_id := await place_box()
	await call_tool("hf_delete_brush", {"brush_id": brush_id})
	_finish("hf_delete_brush")
	assert_eq(panel.last_label.text, "Last: delete brush, 5 ms, 1 removed")
	assert_null(_outline(), "nothing left to outline")


# --- The Last line --------------------------------------------------------------


func test_clicking_the_last_line_selects_exactly_what_changed():
	var first := await place_box([0, 1, 0])
	var second := await place_box([6, 1, 0])
	var answer := await call_tool("hf_transform_brush", {"brush_id": second, "position": [6, 1, 2]})
	assert_true(answer.get("ok", false))
	_finish("hf_transform_brush")
	HFPluginMcp.setup(plugin, host)
	plugin.mcp_dispatcher = dispatcher
	panel.last_label.pressed.emit()
	assert_eq(plugin.editor.selection.nodes, [level.find_brush_by_id(second)])
	assert_false(plugin.editor.selection.nodes.has(level.find_brush_by_id(first)))
	HFPluginMcp.teardown(plugin)


func test_the_last_line_is_a_button_with_its_old_name():
	assert_true(panel.last_label is Button)
	assert_eq(str(panel.last_label.name), "LastCommand")


# --- The edge arrow -------------------------------------------------------------


func _camera() -> Camera3D:
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.global_transform = Transform3D.IDENTITY
	return camera


func _marker(at: Vector3) -> Node3D:
	var node := Node3D.new()
	level.add_child(node)
	node.global_position = at
	return node


func test_no_arrow_while_any_change_is_in_view():
	var camera := _camera()
	var size := Vector2(800, 600)
	assert_eq(
		HFAgentHighlight.edge_arrow(camera, size, [_marker(Vector3(0, 0, -10))]),
		{},
		"in front of the camera"
	)
	assert_eq(
		HFAgentHighlight.edge_arrow(
			camera, size, [_marker(Vector3(200, 0, -1)), _marker(Vector3(0, 0, -5))]
		),
		{},
		"one of two in view"
	)
	assert_eq(HFAgentHighlight.edge_arrow(camera, size, []), {})


func test_the_arrow_points_toward_a_change_out_of_view():
	var camera := _camera()
	var size := Vector2(800, 600)
	var right := HFAgentHighlight.edge_arrow(camera, size, [_marker(Vector3(200, 0, -1))])
	assert_false(right.is_empty())
	if right.is_empty():
		return
	assert_almost_eq(float(right["angle"]), 0.0, 0.01, "points right")
	assert_almost_eq((right["at"] as Vector2).x, size.x - HFAgentHighlight.ARROW_INSET, 0.5)
	assert_almost_eq((right["at"] as Vector2).y, size.y * 0.5, 0.5)
	var up := HFAgentHighlight.edge_arrow(camera, size, [_marker(Vector3(0, 200, -1))])
	assert_almost_eq(float(up["angle"]), -PI / 2.0, 0.01, "points up the screen")
	assert_almost_eq((up["at"] as Vector2).y, HFAgentHighlight.ARROW_INSET, 0.5)
	var behind := HFAgentHighlight.edge_arrow(camera, size, [_marker(Vector3(-50, 0, 30))])
	assert_lt((behind["at"] as Vector2).x, size.x * 0.5, "behind and to the left aims left")
