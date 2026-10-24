class_name HFPluginNumericInput
extends RefCounted
## Owns numeric dimension entry for active draw and extrude gestures.

const HFExtrudeToolType = preload("hf_extrude_tool.gd")
const HFPluginPointerToolsType = preload("plugin_pointer_tools.gd")

const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP


static func handle(plugin: Object, event: InputEventKey, root: Node) -> int:
	if plugin == null or event == null or root == null or root.input_state == null:
		return PASS
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return PASS

	var keycode := event.keycode
	# The keypad counts. Typing a dimension mid-drag is the numeric entry path and
	# a numeric keypad is where people type numbers, and KEY_KP_ENTER was already
	# accepted below, so the keypad could end a gesture at whatever size the mouse
	# happened to be at without ever having put a digit in the buffer.
	#
	# Mapped by keycode rather than by reading numlock, because with numlock off
	# these keys arrive as arrows and navigation keys and never reach here at all.
	var digit := _digit_of(keycode)
	if digit >= 0:
		plugin.numeric_buffer += str(digit)
		update_preview(plugin, root)
		return STOP

	if keycode in [KEY_PERIOD, KEY_KP_PERIOD] and "." not in _typing_part(plugin.numeric_buffer):
		plugin.numeric_buffer += "."
		update_preview(plugin, root)
		return STOP

	# A draw's base takes width, depth and height in one entry (#1693): a comma,
	# or Tab, moves to the next value, and a minus flips the side it starts.
	# Ctrl and the minus key are the grid's, so a held modifier passes.
	var base: bool = (
		root.input_state.is_drag_base() and not event.ctrl_pressed and not event.meta_pressed
	)
	if base and keycode == KEY_COMMA and plugin.numeric_buffer.count(",") < MAX_COMMAS:
		plugin.numeric_buffer += ","
		update_preview(plugin, root)
		return STOP
	if (
		base
		and keycode in [KEY_MINUS, KEY_KP_SUBTRACT]
		and _typing_part(plugin.numeric_buffer) == ""
	):
		plugin.numeric_buffer += "-"
		update_preview(plugin, root)
		return STOP
	if (
		base
		and keycode == KEY_TAB
		and plugin.numeric_buffer.length() > 0
		and plugin.numeric_buffer.count(",") < MAX_COMMAS
	):
		plugin.numeric_buffer += ","
		update_preview(plugin, root)
		return STOP

	if keycode == KEY_BACKSPACE and plugin.numeric_buffer.length() > 0:
		plugin.numeric_buffer = plugin.numeric_buffer.substr(0, plugin.numeric_buffer.length() - 1)
		if plugin.numeric_buffer.length() == 0:
			# Backspaced away to nothing, so the mouse has the gesture back.
			root.input_state.clear_numeric_override()
		update_preview(plugin, root)
		return STOP

	if keycode in [KEY_ENTER, KEY_KP_ENTER] and plugin.numeric_buffer.length() > 0:
		apply_value(plugin, root)
		return STOP

	if keycode == KEY_TAB and plugin.numeric_buffer.length() > 0:
		apply_value(plugin, root)
		return STOP

	return PASS


## The digit a keycode types, on the top row or the keypad, or -1 for anything
## else.
static func _digit_of(keycode: int) -> int:
	if keycode >= KEY_0 and keycode <= KEY_9:
		return keycode - KEY_0
	if keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		return keycode - KEY_KP_0
	return -1


## How many commas a base entry takes: width, depth and height.
const MAX_COMMAS := 2


## The values a base entry holds, `6`, `6,4`, `6,4,3` or `6,` (#1693): one per
## comma-separated part, each a number or null where nothing is typed yet. A
## comma always separates, so a decimal comma is not read as one.
static func typed_values(buffer: String) -> Array:
	var out: Array = []
	for part in buffer.split(","):
		if part.is_valid_float():
			out.append(float(part))
		else:
			out.append(null)
	return out


## The part of the entry being typed: what follows the last comma.
static func _typing_part(buffer: String) -> String:
	var at := buffer.rfind(",")
	return buffer.substr(at + 1) if at >= 0 else buffer


## A base entry with more than one value: width, depth and maybe height. One
## number alone is the square base it always was.
static func _is_separate(buffer: String) -> bool:
	return buffer.contains(",")


static func update_preview(plugin: Object, root: Node) -> void:
	if plugin == null or root == null or root.input_state == null:
		return
	if not root.input_state.is_dragging() and not root.input_state.is_extruding():
		return
	if plugin.numeric_buffer.length() == 0:
		root.input_state.clear_numeric_override()
		return
	if root.input_state.is_drag_base() and _is_separate(plugin.numeric_buffer):
		_preview_separate_base(plugin, root)
		return
	var value := float(plugin.numeric_buffer) if plugin.numeric_buffer.is_valid_float() else 0.0
	# A minus before a base's one number flips both its sides (#1693).
	var length := absf(value) if root.input_state.is_drag_base() else value
	if _refusal(root, length) != "":
		return
	# Set the override before the redraw. `update_drag()` and `update_extrude()`
	# read it and leave the field alone; without it the mouse recomputes the same
	# field from the cursor and the typed number never reaches the screen.
	root.input_state.numeric_override = length
	root.input_state.typed_lock_x = true
	root.input_state.typed_lock_z = true
	if root.input_state.is_extruding():
		root.set_extrude_height(value)
	elif root.input_state.is_drag_height():
		root.input_state.drag_height = value
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	elif root.input_state.is_drag_base():
		root.input_state.drag_end = root.input_state.drag_origin + _base_extent(root, value)
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	plugin._update_hud_context()


static func apply_value(plugin: Object, root: Node) -> void:
	if plugin == null or root == null or root.input_state == null:
		return
	if plugin.numeric_buffer.length() == 0:
		return
	if root.input_state.is_drag_base() and _is_separate(plugin.numeric_buffer):
		_apply_separate_base(plugin, root)
		return
	var value := float(plugin.numeric_buffer) if plugin.numeric_buffer.is_valid_float() else 0.0
	plugin.numeric_buffer = ""
	root.input_state.clear_numeric_override()
	# Refused, the gesture keeps going for the mouse or another number, and the
	# toast says why. The number used to be dropped here without a word.
	var refusal := _refusal(root, absf(value) if root.input_state.is_drag_base() else value)
	if refusal != "":
		if plugin.dock and plugin.dock.has_method("show_toast"):
			plugin.dock.show_toast(refusal, 1)
		plugin._update_hud_context()
		return
	if root.input_state.is_drag_height():
		root.input_state.drag_height = value
		var size = plugin.dock.get_brush_size()
		var info_result = root.end_drag_info(plugin.last_3d_camera, plugin.last_3d_mouse_pos, size)
		if info_result.get("placed", false):
			plugin._commit_brush_placement(root, info_result.get("info", {}))
		plugin._update_hud_context()
	elif root.input_state.is_drag_base():
		root.input_state.drag_end = root.input_state.drag_origin + _base_extent(root, value)
		root.input_state.advance_to_height(plugin.last_3d_mouse_pos)
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
		plugin._update_hud_context()
	elif root.input_state.is_extruding():
		# The Extrude's own depth. This used to go into the Draw's `drag_height`,
		# which the Extrude never reads, so it ended at the mouse's depth, and with
		# the mouse not yet moved that was none and nothing was placed.
		root.set_extrude_height(value)
		HFPluginPointerToolsType.finish_extrude(plugin, root)
		plugin._update_hud_context()


## Why a typed `value` cannot be used for the gesture in progress, or "" when it
## can: a size has to be more than 0, and an extrusion is held to the depth the
## Extrude tool goes to, as `LevelRoot.extrude_face_info()` holds it.
static func _refusal(root: Node, value: float) -> String:
	if value <= 0.0:
		return "Type a size greater than 0"
	if root.input_state.is_extruding() and value > HFExtrudeToolType.MAX_EXTRUDE_HEIGHT:
		return "An extrusion goes at most %d deep" % int(HFExtrudeToolType.MAX_EXTRUDE_HEIGHT)
	return ""


## Put a base entry of separate values on the draw: the width along X and the
## depth along Z, each in the direction the drag is heading unless typed with a
## minus, and a typed height. A side with nothing typed stays the mouse's. False
## for a value of 0, with the toast said when `say` is set, as on Enter; a preview
## passes through 0 on the way to 0.5 and says nothing.
static func _set_separate_base(plugin: Object, root: Node, say: bool) -> bool:
	var values := typed_values(plugin.numeric_buffer)
	for value in values:
		if value != null and is_zero_approx(float(value)):
			if say and plugin.dock and plugin.dock.has_method("show_toast"):
				plugin.dock.show_toast("Type a size greater than 0", 1)
			return false
	var state = root.input_state
	var width: Variant = values[0]
	var depth: Variant = values[1] if values.size() > 1 else null
	var height: Variant = values[2] if values.size() > 2 else null
	# A side left to the mouse takes the mouse's heading again once typed.
	if width == null:
		state.typed_heading.x = 0.0
	if depth == null:
		state.typed_heading.z = 0.0
	var heading := _heading(root)
	if width != null:
		state.drag_end.x = state.drag_origin.x + _along(float(width), heading.x)
	if depth != null:
		state.drag_end.z = state.drag_origin.z + _along(float(depth), heading.z)
	if height != null:
		state.drag_height = absf(float(height))
	state.typed_lock_x = width != null
	state.typed_lock_z = depth != null
	var held := (
		absf(float(width)) if width != null else (absf(float(depth)) if depth != null else 0.0)
	)
	state.numeric_override = held if held > 0.0 else -1.0
	return true


## A typed side's length along the drag: the way the drag `heading` goes for a
## plain number, the other way for one typed with a minus.
static func _along(value: float, heading: float) -> float:
	return absf(value) * (-heading if value < 0.0 else heading)


## Which way the drag goes on X and Z, as it went when each side was first typed.
## Read from the drag the first time, then kept, because a typed minus moves the
## drag's end and a second read would turn the side back.
static func _heading(root: Node) -> Vector3:
	var state = root.input_state
	var delta: Vector3 = state.drag_end - state.drag_origin
	if is_zero_approx(state.typed_heading.x):
		state.typed_heading.x = -1.0 if delta.x < 0.0 else 1.0
	if is_zero_approx(state.typed_heading.z):
		state.typed_heading.z = -1.0 if delta.z < 0.0 else 1.0
	return state.typed_heading


static func _preview_separate_base(plugin: Object, root: Node) -> void:
	if not _set_separate_base(plugin, root, false):
		return
	root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	plugin._update_hud_context()


## Enter on a base entry: the base as typed, then the height stage, or with a
## height typed too the brush itself, with no height click.
static func _apply_separate_base(plugin: Object, root: Node) -> void:
	var typed: String = plugin.numeric_buffer
	if not _set_separate_base(plugin, root, true):
		plugin._update_hud_context()
		return
	var values := typed_values(typed)
	plugin.numeric_buffer = ""
	root.input_state.clear_numeric_override()
	root.input_state.advance_to_height(plugin.last_3d_mouse_pos)
	if values.size() > 2 and values[2] != null:
		var size = plugin.dock.get_brush_size()
		var placed = root.end_drag_info(plugin.last_3d_camera, plugin.last_3d_mouse_pos, size)
		if placed.get("placed", false):
			plugin._commit_brush_placement(root, placed.get("info", {}))
	else:
		root.update_drag(plugin.last_3d_camera, plugin.last_3d_mouse_pos)
	plugin._update_hud_context()


## The base extent a typed dimension asks for, along the direction the drag is
## already heading.
##
## One number goes onto both X and Z, so a typed base is square. It used to be a
## positive square whichever way the drag went, which put the brush in the
## opposite quadrant from the cursor for half of all drags: `get_drag_dimensions()`
## takes `absf()` of the delta, so the HUD read the same either way and gave no
## clue. A drag with no delta yet has no direction to keep, and positive is the
## right default there. A minus turns both sides the other way (#1693).
static func _base_extent(root: Node, value: float) -> Vector3:
	var heading := _heading(root)
	return Vector3(_along(value, heading.x), 0.0, _along(value, heading.z))
