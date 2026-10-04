extends GutTest

## A first Draw click creates a level only in a blank scene (#932).
##
## Input forwarding is on in every 3D scene, and Draw is the dock's default tool,
## so one click to select a mesh in a "Player" scene added a LevelRoot to it and
## took the selection away. A new 3D scene, with nothing in it yet, is the one
## place that click can only mean "start a level here".

const HFPluginViewportInput = preload("res://addons/hammerforge/plugin_viewport_input.gd")

const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS


class FakeDock:
	extends RefCounted

	func is_face_select_mode_enabled() -> bool:
		return false

	func get_tool() -> int:
		return 0

	func is_paint_mode_enabled() -> bool:
		return false


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var _rmb_camera_navigation := HFPluginViewportInput.RmbCameraNavigationSession.new()
	var active_root: Node = null
	var last_3d_camera = null
	var last_3d_mouse_pos := Vector2.ZERO
	var blank_scene := false
	var creates := 0
	var hints := 0

	func _ensure_selection_runtime_state() -> void:
		pass

	func _get_level_root() -> Node:
		return null

	func _edited_scene_awaits_a_level() -> bool:
		return blank_scene

	func _hint_create_level_from_banner() -> void:
		hints += 1

	## No level gets built here; the count is the question.
	func _create_level_root() -> Node:
		creates += 1
		return null

	func get_viewport() -> Viewport:
		return null


func _left_press() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func test_a_draw_click_in_a_scene_with_content_is_left_to_godot():
	var plugin := FakePlugin.new()
	plugin.blank_scene = false

	assert_eq(HFPluginViewportInput.handle(plugin, null, _left_press()), PASS)

	assert_eq(plugin.creates, 0, "no LevelRoot is added to someone else's scene")
	assert_eq(plugin.hints, 1, "the dock says how to make a level instead")


func test_a_draw_click_in_a_blank_scene_still_starts_a_level():
	var plugin := FakePlugin.new()
	plugin.blank_scene = true

	HFPluginViewportInput.handle(plugin, null, _left_press())

	assert_eq(plugin.creates, 1)
	assert_eq(plugin.hints, 0)


func test_only_a_plain_empty_node3d_scene_awaits_a_level():
	var blank := Node3D.new()
	autofree(blank)
	assert_true(HFPluginViewportInput.scene_awaits_a_level(blank), "a new 3D scene")

	var player := Node3D.new()
	autofree(player)
	player.add_child(MeshInstance3D.new())
	assert_false(HFPluginViewportInput.scene_awaits_a_level(player), "a scene with a mesh in it")

	var mesh_root := MeshInstance3D.new()
	autofree(mesh_root)
	assert_false(HFPluginViewportInput.scene_awaits_a_level(mesh_root), "a scene that is a mesh")

	var scripted := Node3D.new()
	autofree(scripted)
	var script := GDScript.new()
	script.source_code = """
extends Node3D
"""
	script.reload()
	scripted.set_script(script)
	assert_false(HFPluginViewportInput.scene_awaits_a_level(scripted), "a game's own root")

	assert_false(HFPluginViewportInput.scene_awaits_a_level(null), "no scene open")
