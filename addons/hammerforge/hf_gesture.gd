@tool
class_name HFGesture
extends RefCounted

## Base class for gesture trackers (inspired by TrenchBroom's GestureTracker).
##
## A gesture encapsulates all state for a mouse-driven interaction (drag, paint
## stroke, extrusion).  The plugin holds at most one active gesture; while it
## is non-null, all input is routed to the gesture rather than the normal tool
## dispatch.
##
## Subclasses override update(), commit(), and cancel().

## The LevelRoot this gesture operates on.
var root: Node3D

## Camera used for raycasting.
var camera: Camera3D

## Starting mouse position (viewport coords).
var start_position := Vector2.ZERO

## Current mouse position.
var current_position := Vector2.ZERO

## Accumulated numeric input buffer (digits typed during drag).
var numeric_buffer := ""


func _init(p_root: Node3D, p_camera: Camera3D, p_start: Vector2) -> void:
	root = p_root
	camera = p_camera
	start_position = p_start
	current_position = p_start


## Called every frame with the latest mouse event while the gesture is active.
## Return EditorPlugin.AFTER_GUI_INPUT_STOP to consume the event.
func update(event: InputEvent) -> int:
	if event is InputEventMouseMotion:
		current_position = event.position
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Finalize the gesture (e.g., place the brush, commit the extrusion).
func commit() -> void:
	pass


## Abort the gesture, restoring any preview state.
func cancel() -> void:
	pass


## Feed a digit, period, or backspace into the numeric buffer.
## Returns true if the key was consumed.
func handle_numeric_key(keycode: int) -> bool:
	if keycode >= KEY_0 and keycode <= KEY_9:
		numeric_buffer += str(keycode - KEY_0)
		return true
	if keycode == KEY_PERIOD and "." not in numeric_buffer:
		numeric_buffer += "."
		return true
	if keycode == KEY_BACKSPACE and numeric_buffer.length() > 0:
		numeric_buffer = numeric_buffer.substr(0, numeric_buffer.length() - 1)
		return true
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_apply_numeric_value()
		numeric_buffer = ""
		return true
	return false


## Override in subclass to apply typed numeric value during drag.
func _apply_numeric_value() -> void:
	pass


## Get the current numeric value (or -1 if empty).
func get_numeric_value() -> float:
	if numeric_buffer == "" or numeric_buffer == ".":
		return -1.0
	return float(numeric_buffer)
