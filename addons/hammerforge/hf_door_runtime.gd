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

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFBrushEntity = preload("hf_brush_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The two angles that are not a compass bearing. The Quake family reads -1 as up
## and -2 as down, which is how a portcullis or a lift gate is made (#1210).
const ANGLE_UP := -1.0
const ANGLE_DOWN := -2.0

## How the properties are named in `entities.json`, and what they mean here.
##
## `speed` is metres per second. `wait` is seconds open before it closes itself,
## and a value of zero or less means it stays open until something closes it.
## `angle` is the compass direction it slides, in degrees, measured the way the
## Quake-family editors measure it: 0 is +X and it turns towards -Z, which is a
## `.map`'s +Y once `MapIO.from_map_axes()` has brought it in, so a door opens the
## same way here as in the file. It turned towards +Z, and a door crossing a
## `.map` opened backwards (#1210). `ANGLE_UP` and `ANGLE_DOWN` lift and lower it.
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
## The whole door's extent along the direction of travel, which is what a door
## sliding into a wall pocket does and what the Quake-family editors compute from
## the brush. Falls back to one metre when there is no geometry to measure, so a
## door with nothing under it still moves rather than silently doing nothing.
func _travel_vector() -> Vector3:
	var direction := travel_direction(angle)
	var distance := _door_extent_along(direction)
	if distance <= 0.001:
		distance = 1.0
	return direction * distance


## The direction an `angle` slides a door, in the space of the door's parent.
static func travel_direction(angle_degrees: float) -> Vector3:
	if is_equal_approx(angle_degrees, ANGLE_UP):
		return Vector3.UP
	if is_equal_approx(angle_degrees, ANGLE_DOWN):
		return Vector3.DOWN
	var radians := deg_to_rad(angle_degrees)
	return Vector3(cos(radians), 0.0, -sin(radians))


## How far the whole door reaches along `direction`: every leaf of it, each where
## it stands shut, measured from the points its geometry is made of. Bounds
## squared to the holder overfill a turned leaf, which then slid past its own
## width (#1210). Every leaf travels the lot, as a Quake-family door of several
## brushes is one mover, so two leaves across a doorway clear it rather than one
## sliding into the other's place (#1217).
func _door_extent_along(direction: Vector3) -> float:
	var lowest := INF
	var highest := -INF
	for leaf in _leaves():
		var shut: Transform3D = leaf._shut_transform()
		for child in leaf.get_children():
			if not (child is VisualInstance3D):
				continue
			var placed: Transform3D = shut * (child as Node3D).transform
			for point in _points_of(child as VisualInstance3D):
				var along := direction.dot(placed * point)
				lowest = minf(lowest, along)
				highest = maxf(highest, along)
	return highest - lowest if highest > lowest else 0.0


## This leaf and the others of the same door: the movers beside it baked from the
## same brush entity, which the bake puts under one holder. A door with neither a
## name nor a tie is a door of one leaf.
func _leaves() -> Array:
	var leaves: Array = [self]
	var identity := HFBrushEntity.baked_identity(self)
	var parent := get_parent()
	if identity == "" or parent == null:
		return leaves
	var entity_class := HFBrushEntity.entity_class(self)
	for other in parent.get_children():
		if other == self or other.get_script() != get_script():
			continue
		if HFBrushEntity.entity_class(other) != entity_class:
			continue
		if HFBrushEntity.baked_identity(other) == identity:
			leaves.append(other)
	return leaves


## Where this leaf stands when it is shut, in its parent's space: where it was at
## its first Open, or where it is now if it has not opened yet.
func _shut_transform() -> Transform3D:
	var shut := transform
	if _measured:
		shut.origin = _closed_origin
	return shut


## The corners of a leaf's triangles, in the leaf's own space, or of its box when
## it has no mesh to read. Nothing at all for a visual with no size, which would
## otherwise stretch the door to its origin.
static func _points_of(visual: VisualInstance3D) -> PackedVector3Array:
	if visual is MeshInstance3D and (visual as MeshInstance3D).mesh:
		var faces := (visual as MeshInstance3D).mesh.get_faces()
		if not faces.is_empty():
			return faces
	var points := PackedVector3Array()
	var box := visual.get_aabb()
	if box.size == Vector3.ZERO:
		return points
	for i in 8:
		points.append(box.get_endpoint(i))
	return points


## The inputs `func_door` declares are `Open`, `Close` and `Toggle`, and
## `HFIORuntime` converts an input name to snake_case before looking for a method
## of that name. So these are what it finds, and none of them collides with
## anything the engine already defines on a `Node3D`.
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Whether it is open, or on its way there.
func is_open() -> bool:
	return _is_open


func lock() -> void:
	locked = true


func unlock() -> void:
	locked = false


func open() -> void:
	if locked or _is_open:
		return
	_measure_once()
	_is_open = true
	var slide := _move_to(_closed_origin + _travel)
	if wait > 0.0:
		# `wait` is how long it stays open, so the count starts when it gets
		# there. Armed at Open, a door slower to open than its wait reversed
		# before it was ever open (#910). A Close on the way kills the slide, and
		# a killed tween never finishes, so nothing is armed then.
		if slide:
			slide.finished.connect(_arm_self_close)
		else:
			_arm_self_close()
	opened.emit()
	HFIORuntime.fire_door_on(self, "OnOpen")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_close_timer = null
	_move_to(_closed_origin)
	closed.emit()
	HFIORuntime.fire_door_on(self, "OnClose")


## Slide there over the time the speed implies, rather than in one frame.
##
## A door that teleports shut can leave a body inside it, and a door that
## teleports open is not what the property is called speed for. Returns the
## slide, or null when the door was put there at once.
func _move_to(target: Vector3) -> Tween:
	if _tween and _tween.is_valid():
		_tween.kill()
	var distance: float = position.distance_to(target)
	var duration: float = distance / maxf(speed, 0.01)
	if duration <= 0.0 or not is_inside_tree():
		position = target
		return null
	_tween = create_tween()
	_tween.tween_property(self, "position", target, duration)
	return _tween


## Close itself after `wait` seconds, unless something closed or reopened it
## first. The timer is compared against the one held here rather than cancelled,
## because a `SceneTreeTimer` cannot be stopped once it is running. Held by a
## pause, as a trigger's wait is, rather than running out behind it (#1140).
func _arm_self_close() -> void:
	if not is_inside_tree() or not _is_open:
		return
	var timer := get_tree().create_timer(wait, false)
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
		# Through `read_flag()`: a `.map` import stores "true", and `bool()` takes
		# no String, so the bake stopped here and the door stayed unlocked (#1127).
		locked = HFIORuntime.read_flag(data["locked"])
	# Not a measurement: the angle may have changed, and the door has not moved
	# yet, so the next Open works both out from where it actually is.
	_measured = false
