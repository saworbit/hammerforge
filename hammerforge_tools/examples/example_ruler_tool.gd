@tool
extends HFEditorTool

## A complete, minimal custom tool: click two points on the grid plane and it
## reports the distance between them.
##
## It is here to be copied. Everything a tool needs is in this file - an id above
## 100, a name for the toolbar, an input handler that consumes what it uses, and
## a `deactivate()` that gives back everything `activate()` took.

const TOOL_ID := 100

var _first_point: Variant = null


func tool_name() -> String:
	return "Ruler (example)"


func tool_id() -> int:
	return TOOL_ID


func can_activate(p_root: Node3D) -> bool:
	return p_root != null


func get_poll_fail_reason(p_root: Node3D) -> String:
	if p_root == null:
		return "No LevelRoot in scene"
	return ""


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)
	_first_point = null


func deactivate() -> void:
	# Anything the tool took while active is given back here, or it outlives the
	# tool and turns into the leak the next person has to find.
	_first_point = null
	super.deactivate()


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not (event is InputEventMouseButton):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var point = _ground_point(camera, mouse_pos)
	if point == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if _first_point == null:
		_first_point = point
		_say("Ruler: first point set. Click again for the distance.")
	else:
		var distance: float = (point as Vector3).distance_to(_first_point as Vector3)
		_say("Ruler: %.2f units" % distance)
		_first_point = null
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func cancel_pointer_capture() -> bool:
	if _first_point == null:
		return false
	_first_point = null
	return true


func get_shortcut_hud_lines() -> PackedStringArray:
	return PackedStringArray(["LMB: set point", "Esc: cancel"])


## Where the mouse ray meets the y = 0 plane, or null when it runs parallel to it.
func _ground_point(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	if camera == null:
		return null
	var origin := camera.project_ray_origin(mouse_pos)
	var direction := camera.project_ray_normal(mouse_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


func _say(message: String) -> void:
	if history_callback.is_valid():
		history_callback.call(message)
	else:
		print(message)
