@tool
extends RefCounted
## Which world axis an arrow key moves along, for the view it is pressed in
## (#1716).
##
## The arrows used to move along fixed axes: Up was always -Z. In Godot's Front
## view the screen's up is +Y, so Up moved the selection into the screen, where
## nothing visible happened. Now each arrow moves along the world axis nearest
## its direction on screen:
##
## - an orthographic view (Top, Front, Side) takes the camera's own up and right,
##   so Top view moves as before and Front view's Up is +Y;
## - a perspective view takes the camera's heading on the ground, snapped to the
##   nearest horizontal axis, so facing +X makes Up +X; one looking straight down
##   takes its up instead.
##
## Page Up and Page Down stay vertical in every view.

const FIXED := {
	KEY_UP: Vector3(0.0, 0.0, -1.0),
	KEY_DOWN: Vector3(0.0, 0.0, 1.0),
	KEY_LEFT: Vector3(-1.0, 0.0, 0.0),
	KEY_RIGHT: Vector3(1.0, 0.0, 0.0),
	KEY_PAGEUP: Vector3(0.0, 1.0, 0.0),
	KEY_PAGEDOWN: Vector3(0.0, -1.0, 0.0),
}

const AXES: Array[Vector3] = [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
]


## The move for `keycode`: by the view when `camera` is given, else the fixed
## mapping. Zero for a key that is no nudge key.
static func nudge_direction(keycode: int, camera: Camera3D = null) -> Vector3:
	if not FIXED.has(keycode):
		return Vector3.ZERO
	if keycode == KEY_PAGEUP or keycode == KEY_PAGEDOWN:
		return FIXED[keycode]
	if camera == null or not is_instance_valid(camera):
		return FIXED[keycode]
	var basis := camera.global_transform.basis.orthonormalized()
	var screen_up: Vector3 = basis.y
	var screen_right: Vector3 = basis.x
	var horizontal := camera.projection != Camera3D.PROJECTION_ORTHOGONAL
	if horizontal:
		var heading := -basis.z
		heading.y = 0.0
		# Straight down, the heading on the ground is the camera's up.
		if heading.length_squared() < 0.0001:
			heading = basis.y
			heading.y = 0.0
		screen_up = heading
		screen_right.y = 0.0
	match keycode:
		KEY_UP:
			return nearest_axis(screen_up, horizontal)
		KEY_DOWN:
			return nearest_axis(-screen_up, horizontal)
		KEY_LEFT:
			return nearest_axis(-screen_right, horizontal)
		_:
			return nearest_axis(screen_right, horizontal)


## The world axis nearest `direction`, among the horizontal four when
## `horizontal`.
static func nearest_axis(direction: Vector3, horizontal: bool = false) -> Vector3:
	var best := Vector3.ZERO
	var best_dot := -INF
	for axis in AXES:
		if horizontal and axis.y != 0.0:
			continue
		var along := direction.dot(axis)
		if along > best_dot:
			best_dot = along
			best = axis
	return best


## How a move reads on the HUD: "+Y 0.25 m".
static func describe(offset: Vector3) -> String:
	for i in 3:
		if absf(offset[i]) > 0.0:
			return (
				"%s%s %s m"
				% ["+" if offset[i] > 0.0 else "-", "XYZ"[i], String.num(absf(offset[i]), 4)]
			)
	return ""
