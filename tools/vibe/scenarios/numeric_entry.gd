@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Typing a dimension mid-drag: `HFPluginNumericInput`.
##
## While a draw drag is running, digits go into `plugin.numeric_buffer` and the
## HUD shows them. `update_preview()` is meant to make the brush follow what was
## typed, and `apply_value()` commits it on Enter or Tab.
##
## Two things worth measuring. First, whether the preview actually changes while
## the number is being typed -- `update_preview()` writes `drag_end` and then
## calls `root.update_drag()`, and the drag system's own base-stage branch
## recomputes `drag_end` from the mouse. Second, what shape the typed number
## asks for: the base branch builds `Vector3(value, 0, value)` and adds it to the
## drag origin, which is one number for two axes and always in the positive
## direction.

const NumericInput = preload("res://addons/hammerforge/plugin_numeric_input.gd")

## Just enough of the plugin for the two entry points to run.
const STUB := """@tool
extends RefCounted
var numeric_buffer := ""
var last_3d_camera: Camera3D = null
var last_3d_mouse_pos := Vector2(400, 300)
var dock = null
var hud_updates := 0
func _update_hud_context() -> void:
	hud_updates += 1
func _commit_brush_placement(_root, _info) -> void:
	pass
"""


func id() -> String:
	return "numeric-entry"


func summary() -> String:
	return "whether a dimension typed during a draw drag reaches the preview, and what shape it asks for"


func run() -> void:
	await _typing_during_the_base_stage()
	await _which_way_the_typed_extent_goes()
	await _what_the_buffer_accepts()


func _stub() -> RefCounted:
	var script := GDScript.new()
	script.source_code = STUB
	script.reload()
	return script.new()


## A camera looking down at the construction plane, so `_raycast()` resolves the
## way it does in the editor rather than returning nothing.
func _camera(root: Node3D) -> Camera3D:
	var cam := Camera3D.new()
	_tree.get_root().add_child(cam)
	cam.global_position = Vector3(0, 400, 0)
	cam.look_at(Vector3.ZERO, Vector3.BACK)
	await frame()
	return cam


func _begin_base_drag(root: Node3D, cam: Camera3D) -> void:
	root.input_state.begin_drag(
		Vector3.ZERO, 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2(400, 300)
	)
	# One mouse update, so the drag is where a real one would be by now.
	root.update_drag(cam, Vector2(500, 380))


## Type a number while the base is being dragged and see what the preview holds.
func _typing_during_the_base_stage() -> void:
	var root: Node3D = await fresh_root("NumericBase")
	var cam: Camera3D = await _camera(root)
	var plugin := _stub()
	plugin.last_3d_camera = cam

	_begin_base_drag(root, cam)
	var from_mouse: Vector3 = root.input_state.drag_end
	note("drag_end after the mouse moved", from_mouse)
	note("drag stage", "DRAG_BASE" if root.input_state.is_drag_base() else "other")

	plugin.numeric_buffer = "128"
	NumericInput.update_preview(plugin, root)
	var after_typing: Vector3 = root.input_state.drag_end
	note("drag_end after typing 128", after_typing)
	var asked_for: Vector3 = root.input_state.drag_origin + Vector3(128, 0, 128)
	note("what 128 asked for", asked_for)

	if not after_typing.is_equal_approx(asked_for):
		known(
			516,
			"a dimension typed during the base stage never reaches the preview",
			(
				"update_preview() writes drag_end = drag_origin + Vector3(value, 0, value)"
				+ " and then calls root.update_drag(), whose DRAG_BASE branch"
				+ " (hf_drag_system.gd:50-56) recomputes drag_end from the mouse raycast"
				+ " unless Alt is held. Typing 128 asked for %s and left it at %s,"
				% [str(asked_for), str(after_typing)]
				+ " which is the raycast under the cursor. The HUD shows the digits throughout"
			)
		)
	else:
		note("the typed value survives update_drag", "the preview follows what was typed")

	# Alt is the branch that does not overwrite it.
	root.input_state.alt_pressed = true
	plugin.numeric_buffer = "96"
	NumericInput.update_preview(plugin, root)
	note("drag_end after typing 96 with Alt held", root.input_state.drag_end)
	root.input_state.alt_pressed = false

	# Enter takes a different route: advance_to_height() changes mode before
	# update_drag runs, so the base branch is not taken.
	_begin_base_drag(root, cam)
	plugin.numeric_buffer = "128"
	NumericInput.apply_value(plugin, root)
	note("drag_end after typing 128 and pressing Enter", root.input_state.drag_end)
	note("stage after Enter", "DRAG_HEIGHT" if root.input_state.is_drag_height() else "other")
	cam.queue_free()


## The typed extent is one number on two axes, added in the positive direction.
func _which_way_the_typed_extent_goes() -> void:
	var root: Node3D = await fresh_root("NumericDirection")
	var cam: Camera3D = await _camera(root)
	var plugin := _stub()
	plugin.last_3d_camera = cam

	# A drag heading into negative X and Z, which is half of all drags.
	root.input_state.begin_drag(
		Vector3.ZERO, 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2(400, 300)
	)
	root.input_state.drag_end = Vector3(-64, 0, -64)
	note("dragging away from the origin, drag_end", root.input_state.drag_end)
	note("dimensions the HUD reports", root.input_state.get_drag_dimensions())

	plugin.numeric_buffer = "128"
	NumericInput.apply_value(plugin, root)
	var placed: Vector3 = root.input_state.drag_end
	note("drag_end after typing 128 and pressing Enter", placed)
	if placed.x > 0.0 and placed.z > 0.0:
		known(
			517,
			"typing a dimension moves the base to the opposite side of where it was drawn",
			(
				"apply_value() sets drag_end = drag_origin + Vector3(value, 0, value)"
				+ " with no sign, so a drag heading to (-64, 0, -64) becomes %s." % str(placed)
				+ " The brush jumps across the origin to a quadrant the cursor never visited"
			)
		)
	note(
		"the typed extent is square by construction",
		"Vector3(value, 0, value) -- there is no way to type a base of 64 by 128"
	)
	cam.queue_free()


## What the buffer takes, and what it does with what it takes.
func _what_the_buffer_accepts() -> void:
	var root: Node3D = await fresh_root("NumericBuffer")
	var cam: Camera3D = await _camera(root)
	var plugin := _stub()
	plugin.last_3d_camera = cam

	root.input_state.begin_drag(
		Vector3.ZERO, 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2(400, 300)
	)
	root.input_state.advance_to_height(Vector2(400, 300))
	note("stage", "DRAG_HEIGHT")

	for typed in ["0", "0.0", "999999999", "12345678901234567890123456789012345678901234"]:
		root.input_state.drag_height = 32.0
		plugin.numeric_buffer = typed
		NumericInput.update_preview(plugin, root)
		note("typed '%s' -> drag_height" % typed, root.input_state.drag_height)
		if typed == "999999999" and is_equal_approx(root.input_state.drag_height, 32.0):
			known(
				516,
				"a height typed during the height stage never reaches the preview either",
				(
					"update_preview() sets drag_height = 999999999 and then calls"
					+ " root.update_drag(), whose DRAG_HEIGHT branch (hf_drag_system.gd:74-77)"
					+ " overwrites it with _height_from_mouse() unconditionally -- there is not"
					+ " even the Alt guard the base branch has. drag_height is back at 32"
				)
			)
		if not is_finite(root.input_state.drag_height):
			flag(
				"a long enough typed number puts a non-finite height into the drag",
				"'%s' left drag_height at %s" % [typed, str(root.input_state.drag_height)]
			)

	# Enter on a zero clears the buffer and does nothing else.
	root.input_state.drag_height = 32.0
	plugin.numeric_buffer = "0"
	NumericInput.apply_value(plugin, root)
	note("after Enter on '0': buffer", "'%s'" % plugin.numeric_buffer)
	note("after Enter on '0': drag_height", root.input_state.drag_height)
	note("after Enter on '0': still dragging", root.input_state.is_dragging())

	# The digit cap: there is none.
	plugin.numeric_buffer = ""
	var event := InputEventKey.new()
	event.keycode = KEY_9
	event.pressed = true
	for i in range(40):
		NumericInput.handle(plugin, event, root)
	note("digits accepted into the buffer", plugin.numeric_buffer.length())
	note("what that parses to", float(plugin.numeric_buffer))
	cam.queue_free()
