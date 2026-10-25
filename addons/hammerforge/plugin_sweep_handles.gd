@tool
class_name HFPluginSweepHandles
extends RefCounted
## The Sweep dialog's handles in the viewport (#1885): while it is open on an Arc,
## one handle stands where the bend turns about, with a line along the axis it
## turns about, and one stands on the end of the run.
##
## Typed values were the only way to say where a bend goes, and a radius of 4
## turning toward 90 was a guess until the outline showed it. Dragging the pivot
## along the faces' plane sets Radius, its distance from the faces' middle, in
## grid steps, and Toward, its direction, in the rotate snap's steps. Dragging the
## end handle turns it about the pivot and sets Angle in the rotate snap's steps,
## 15 degrees unless the dock says otherwise. The fields follow each drag and the
## handles follow what is typed. A right click or Escape mid drag puts the values
## back as the press found them. The snap invert key frees both.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## How near the pointer has to be to a handle, in pixels, for a press to take it.
const PICK_PIXELS := 12.0

enum Grip { NONE, PIVOT, END }

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFSweepBuilder = preload("hf_sweep_builder.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFFaceSweep = preload("hf_face_sweep.gd")

## Whether the dialog is open with handles to drag.
var active := false
## The dialog's values, the same dictionary it reads, so a drag changes what OK
## makes.
var _values: Dictionary = {}
## The sweep's start frame: the faces' middle, facing out of them.
var _placement := Transform3D.IDENTITY
## How far the faces reach from their middle, which sizes the handles.
var _reach := 1.0
## The dialog's outline, which draws the handles.
var _preview = null
## Called after a drag changes the values, so the fields and the outline follow.
var _changed := Callable()
## The level the dialog was opened in, by instance id.
var _root_id := 0
var _grip := Grip.NONE
## Whether the left release still to come belongs to a drag a right click put
## back, so the Select tool never sees the end of a click it never saw begin.
var _release_owed := false
## The values as the press found them, for a cancel.
var _before: Dictionary = {}
## The end drag's angle so far, unwound past a half turn, and the pointer's last
## angle about the pivot.
var _turned := 0.0
var _last := 0.0


## Show handles for the Sweep dialog's `values` on the faces `cut` read, as
## `HFPluginFaceSweep.section()` gives them, drawn by `preview`. `changed` runs
## after each drag step.
func attach(root: Node, cut: Dictionary, values: Dictionary, preview, changed: Callable) -> void:
	active = true
	_values = values
	_placement = cut["placement"]
	_preview = preview
	_changed = changed
	_root_id = root.get_instance_id() if root else 0
	_grip = Grip.NONE
	_release_owed = false
	_reach = 1.0
	for ring in HFSweepBuilder.rings_of(cut["run"]):
		for corner in ring:
			_reach = maxf(_reach, Vector2(corner.x, corner.y).length())
	draw()


## Let go of the dialog: no handles, and a drag under way is dropped.
func detach() -> void:
	active = false
	_grip = Grip.NONE
	_release_owed = false
	_values = {}
	_preview = null
	_changed = Callable()
	_root_id = 0


## Let go of the dialog whose values are `values`, and of no other.
func let_go(values: Dictionary) -> void:
	if active and is_same(_values, values):
		detach()


func dragging() -> bool:
	return active and _grip != Grip.NONE


## Whether the handles show: the dialog is open on an Arc, the one path they set.
func shown() -> bool:
	return active and int(_values.get("path", -1)) == HFFaceSweep.Path.ARC


## Where the bend turns about, in the level.
func pivot_point() -> Vector3:
	return _placement * HFSweepBuilder.pivot_of(_values)


## Where one turn of the arc ends, in the level.
func end_point() -> Vector3:
	return _placement * HFSweepBuilder.end_of(_values)


## The line the bend turns about, through `pivot_point()`.
func axis() -> Vector3:
	return (_placement.basis * HFSweepBuilder.axis_of(_values)).normalized()


## Draw the handles where the values put them, or take them away off an Arc.
func draw() -> void:
	if _preview == null:
		return
	if not shown():
		_preview.show_handles(PackedVector3Array(), PackedVector3Array())
		return
	var size := _reach * 0.3
	var pivot := pivot_point()
	var end := end_point()
	var along := axis()
	var pivot_lines := PackedVector3Array()
	_cross(
		pivot_lines, pivot, _placement.basis.x.normalized(), _placement.basis.y.normalized(), size
	)
	pivot_lines.append_array([pivot - along * _reach * 1.5, pivot + along * _reach * 1.5])
	pivot_lines.append_array([_placement.origin, pivot])
	var end_lines := PackedVector3Array()
	var spoke := (end - pivot).normalized() if not end.is_equal_approx(pivot) else along
	_cross(end_lines, end, along, spoke, size)
	end_lines.append_array([pivot, end])
	_preview.show_handles(pivot_lines, end_lines)


static func _cross(
	lines: PackedVector3Array, at: Vector3, one: Vector3, other: Vector3, size: float
) -> void:
	lines.append_array([at - one * size, at + one * size, at - other * size, at + other * size])


## The handle under `mouse_pos`, the nearer of the two within `PICK_PIXELS`.
func grip_at(camera: Camera3D, mouse_pos: Vector2) -> Grip:
	if not shown() or camera == null:
		return Grip.NONE
	var found := Grip.NONE
	var nearest := PICK_PIXELS
	for pair in [[Grip.PIVOT, pivot_point()], [Grip.END, end_point()]]:
		var point: Vector3 = pair[1]
		if camera.is_position_behind(point):
			continue
		var gap := camera.unproject_position(point).distance_to(mouse_pos)
		if gap <= nearest:
			nearest = gap
			found = pair[0] as Grip
	return found


## The viewport's pointer while the handles show: a press on one takes it, and the
## drag has every move and the release, so Godot never sees them. Everything else
## goes on as though the handles were not there.
func handle_input(
	_plugin: Object, event: InputEvent, root: Node, camera: Camera3D, mouse_pos: Vector2
) -> int:
	if not shown() or root == null or root.get_instance_id() != _root_id or camera == null:
		_grip = Grip.NONE
		return PASS
	if event is InputEventMouseMotion:
		if _grip == Grip.NONE:
			return PASS
		_drag(root, camera, mouse_pos)
		return STOP
	if not (event is InputEventMouseButton):
		return PASS
	var button := event as InputEventMouseButton
	if _release_owed and button.button_index == MOUSE_BUTTON_LEFT:
		_release_owed = false
		if not button.pressed:
			return STOP
	if _grip != Grip.NONE:
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			cancel()
		elif button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_drag(root, camera, mouse_pos)
			_grip = Grip.NONE
		return STOP
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return PASS
	var grip := grip_at(camera, mouse_pos)
	if grip == Grip.NONE:
		return PASS
	_grip = grip
	_before = _values.duplicate()
	if grip == Grip.END:
		_turned = float(_values.get("angle", 0.0))
		var at: Variant = _about_pivot(camera, mouse_pos)
		_last = float(at) if at != null else 0.0
	return STOP


## Put the values back as the press found them, mid drag. True when a drag was
## under way.
func cancel() -> bool:
	if not dragging():
		return false
	_grip = Grip.NONE
	_release_owed = true
	for key in _before:
		_values[key] = _before[key]
	_tell()
	return true


func _drag(root: Node, camera: Camera3D, mouse_pos: Vector2) -> void:
	var step := float(root.call("drag_grid_step")) if root.has_method("drag_grid_step") else 0.0
	var turn_step := 0.0
	if step > 0.0:
		var snap: Variant = root.get("rotate_snap_degrees")
		turn_step = float(snap) if snap != null else 15.0
	if _grip == Grip.PIVOT:
		var faces := Plane(_placement.basis.z.normalized(), _placement.origin)
		var hit: Variant = _on_plane(camera, mouse_pos, faces)
		if hit == null:
			return
		var local: Vector3 = _placement.affine_inverse() * (hit as Vector3)
		var moved := HFSweepBuilder.pivot_settings(_values, local, step, turn_step)
		_values["radius"] = moved["radius"]
		_values["toward"] = moved["toward"]
	elif _grip == Grip.END:
		var at: Variant = _about_pivot(camera, mouse_pos)
		if at == null:
			return
		_turned += wrapf(float(at) - _last, -180.0, 180.0)
		_last = float(at)
		var angle := snappedf(_turned, turn_step if turn_step > 0.0 else 1.0)
		_values["angle"] = clampf(angle, -360.0, 360.0)
	_tell()


## The pointer's angle about the axis, in degrees from the faces' middle, on the
## plane the arc turns in, or null when the pointer's ray misses that plane.
func _about_pivot(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	var pivot := pivot_point()
	var along := axis()
	var hit: Variant = _on_plane(camera, mouse_pos, Plane(along, pivot))
	if hit == null:
		return null
	var from := _placement.origin - pivot
	var to: Vector3 = (hit as Vector3) - pivot
	if to.length_squared() < 0.000001 or from.length_squared() < 0.000001:
		return null
	return rad_to_deg(atan2(along.dot(from.cross(to)), from.dot(to)))


static func _on_plane(camera: Camera3D, mouse_pos: Vector2, plane: Plane) -> Variant:
	return plane.intersects_ray(
		camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos)
	)


func _tell() -> void:
	if _changed.is_valid():
		_changed.call()
	else:
		draw()
