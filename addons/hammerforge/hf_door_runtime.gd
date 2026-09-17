@tool
extends Node3D
class_name HFDoorRuntime

## The thing that makes a `func_door` a door.
##
## `func_door` describes itself as "Geometry that moves when opened" and ships
## `speed`, `wait` and `angle`. Nothing read any of them: the bake produced a
## plain `MeshInstance3D` with no script, so `HFIORuntime` delivered `Open` to
## the fourth branch of its chain and emitted a signal nobody was connected to.
## The door was where it was (#687).
##
## Attached by the bake to the holder a mover class gets, so the mesh and its
## collision travel together. A door that slid its mesh and left its collision
## behind would be worse than one that does not move at all.

## How the properties are named in `entities.json`, and what they mean here.
##
## `speed` is metres per second. `wait` is seconds open before it closes itself,
## and a value of zero or less means it stays open until something closes it.
## `angle` is the compass direction it slides, in degrees, measured the way the
## Quake-family editors measure it: 0 is +X and it turns towards +Z.
@export var speed: float = 2.0
@export var wait: float = 3.0
@export var angle: float = 90.0
@export var locked: bool = false

## Where the door sits when it is shut, and how far it slides from there.
##
## Both are worked out at the first Open rather than in `_ready()`, because at
## `_ready()` the door is an empty holder: the bake adds it to the tree and then
## puts the mesh and the collision inside it, so there is nothing to measure yet
## and no guarantee it has been placed. Recorded once, so repeated Opens do not
## walk the door down the corridor.
var _closed_origin: Vector3 = Vector3.ZERO
var _travel: Vector3 = Vector3.ZERO
var _measured := false
var _is_open := false
var _tween: Tween = null
var _close_timer: SceneTreeTimer = null

signal opened
signal closed


func _measure_once() -> void:
	if _measured:
		return
	_measured = true
	_closed_origin = position
	_travel = _travel_vector()


## How far and in which direction the door slides.
##
## Its own width along the direction of travel, which is what a door sliding into
## a wall pocket does and what the Quake-family editors compute from the brush.
## Falls back to one metre when there is no geometry to measure, so a door with
## nothing under it still moves rather than silently doing nothing.
func _travel_vector() -> Vector3:
	var radians := deg_to_rad(angle)
	var direction := Vector3(cos(radians), 0.0, sin(radians))
	var bounds := _visual_bounds()
	var distance: float = absf(bounds.x * direction.x) + absf(bounds.z * direction.z)
	if distance <= 0.001:
		distance = 1.0
	return direction * distance


## The size of the geometry under this holder, in the holder's own space.
func _visual_bounds() -> Vector3:
	var merged := AABB()
	var first := true
	for child in get_children():
		if not (child is VisualInstance3D):
			continue
		var box: AABB = (child as VisualInstance3D).get_aabb()
		box = (child as Node3D).transform * box
		if first:
			merged = box
			first = false
		else:
			merged = merged.merge(box)
	return merged.size if not first else Vector3.ZERO


## The inputs `func_door` declares are `Open`, `Close` and `Toggle`, and
## `HFIORuntime` converts an input name to snake_case before looking for a method
## of that name. So these are what it finds, and none of them collides with
## anything the engine already defines on a `Node3D`.
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func lock() -> void:
	locked = true


func unlock() -> void:
	locked = false


func open() -> void:
	if locked or _is_open:
		return
	_measure_once()
	_is_open = true
	_move_to(_closed_origin + _travel)
	if wait > 0.0:
		_arm_self_close()
	opened.emit()
	HFIORuntime.fire_on(self, "OnOpen")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_close_timer = null
	_move_to(_closed_origin)
	closed.emit()
	HFIORuntime.fire_on(self, "OnClose")


## Slide there over the time the speed implies, rather than in one frame.
##
## A door that teleports shut can leave a body inside it, and a door that
## teleports open is not what the property is called speed for.
func _move_to(target: Vector3) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var distance: float = position.distance_to(target)
	var duration: float = distance / maxf(speed, 0.01)
	if duration <= 0.0 or not is_inside_tree():
		position = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "position", target, duration)


## Close itself after `wait` seconds, unless something closed or reopened it
## first. The timer is compared against the one held here rather than cancelled,
## because a `SceneTreeTimer` cannot be stopped once it is running.
func _arm_self_close() -> void:
	if not is_inside_tree():
		return
	var timer := get_tree().create_timer(wait)
	_close_timer = timer
	timer.timeout.connect(
		func() -> void:
			if is_instance_valid(self) and _close_timer == timer:
				close()
	)


## Read the authored properties off the metadata the bake copied over.
##
## Called by the bake after the script is attached, because `_ready()` has
## already run by then and the exports still hold their defaults. A property the
## mapper never set is absent, and the default in `entities.json` stands.
func apply_entity_data(data: Dictionary) -> void:
	if data.has("speed"):
		speed = float(data["speed"])
	if data.has("wait"):
		wait = float(data["wait"])
	if data.has("angle"):
		angle = float(data["angle"])
	if data.has("locked"):
		locked = bool(data["locked"])
	# Not a measurement: the angle may have changed, and the door has not moved
	# yet, so the next Open works both out from where it actually is.
	_measured = false
