@tool
extends CharacterBody3D

# --- Movement Settings ---
@export_group("Movement")
@export var walk_speed := 6.5
@export var sprint_speed := 10.0
@export var crouch_speed := 3.0
@export var jump_velocity := 6.5
@export var acceleration := 10.0
@export var deceleration := 8.0
@export var air_control := 0.3

# --- Camera & Game Feel ---
@export_group("Game Feel")
@export var mouse_sensitivity := 0.002
@export var head_bob_freq := 2.4
@export var head_bob_amp := 0.08
@export var base_fov := 75.0
@export var sprint_fov_multiplier := 1.15
@export var coyote_time := 0.15
@export var jump_action := "ui_accept"
## The Use key, and how far in front of the camera it reaches.
@export var use_action := "hf_use"
@export var use_distance := 2.5
## The tallest riser the player will walk up.
##
## Godot's `CharacterBody3D` has no automatic step-up, so before this every
## vertical face was a wall to it whatever its height: a five centimetre riser
## stopped the player exactly as a twenty-five centimetre one did, and the stairs
## the plugin's own generators build were unwalkable (#711). Defaults above
## `bake_connector_stair_height`, so the auto-connector's stairs are climbable
## without anybody changing anything.
@export var max_step_height := 0.4
@export var capsule_radius := 0.35
@export var capsule_height := 1.6
## The capsule while crouched. A crawl space is the thing a playtest is meant to
## answer, so this has to be a real shape change and not only a slower walk.
@export var crouch_height := 0.9
## Camera height above the body origin, standing and crouched.
@export var eye_height := 1.0
@export var crouch_eye_height := 0.55

# --- Spawn (set by Quick Play before adding to scene tree) ---
@export var player_start_position: Vector3 = Vector3.ZERO
@export var player_start_rotation_y: float = 0.0

# --- State Variables ---
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var camera_pivot: Node3D
var camera: Camera3D
var head_bob_time := 0.0
var time_since_on_floor := 0.0
var is_crouching := false
var _hud: CanvasLayer
var _reticle: Control
var _pause_overlay: Control


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_ensure_input_map()
	_ensure_collider()

	# Setup Camera Hierarchy for separate Bobbing/Tilting
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = eye_height
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = base_fov
	camera_pivot.add_child(camera)
	camera.make_current()

	# Apply spawn position/rotation if set by Quick Play
	if player_start_position != Vector3.ZERO:
		global_position = player_start_position
	if player_start_rotation_y != 0.0:
		rotation.y = player_start_rotation_y

	# Long enough to catch the drop onto a step after the body has been lifted over
	# its riser, or the player floats forward and falls off the front of it.
	floor_snap_length = maxf(floor_snap_length, max_step_height + 0.05)

	_ensure_hud()
	_set_cursor_captured(true)


func _ensure_hud() -> void:
	if _hud and is_instance_valid(_hud):
		return
	_hud = CanvasLayer.new()
	_hud.name = "PlaytestHUD"
	_hud.layer = 100
	add_child(_hud)

	_reticle = Label.new()
	_reticle.name = "Reticle"
	_reticle.text = "+"
	_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reticle.add_theme_font_size_override("font_size", 22)
	_reticle.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_hud.add_child(_reticle)

	_pause_overlay = PanelContainer.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.visible = false
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pause_overlay.offset_left = -140
	_pause_overlay.offset_right = 140
	_pause_overlay.offset_top = 24
	_pause_overlay.offset_bottom = 160
	var pause_label := Label.new()
	pause_label.text = ("WASD move\nShift sprint\nSpace jump\nCtrl crouch\nEsc capture mouse")
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_overlay.add_child(pause_label)
	_hud.add_child(_pause_overlay)


func _set_cursor_captured(captured: bool) -> void:
	Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE)
	if _reticle:
		_reticle.visible = captured
	if _pause_overlay:
		_pause_overlay.visible = not captured


func _ensure_collider() -> void:
	var existing = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if existing:
		return
	var shape = CapsuleShape3D.new()
	shape.radius = max(0.05, capsule_radius)
	shape.height = max(shape.radius * 2.0, capsule_height)
	var collider = CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	add_child(collider)


## Crouch, for real: the capsule shrinks and the camera comes down with it.
##
## The capsule is centred on the node, so changing its height moves the feet.
## The body moves by half the change to leave them where they were.
func _set_crouched(want_crouch: bool) -> void:
	if want_crouch == is_crouching:
		return
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not (collider.shape is CapsuleShape3D):
		return
	var shape := collider.shape as CapsuleShape3D
	var standing: float = maxf(shape.radius * 2.0, capsule_height)
	var crouched: float = maxf(shape.radius * 2.0, minf(crouch_height, capsule_height))
	var half_delta := (standing - crouched) * 0.5
	if half_delta <= 0.0:
		is_crouching = want_crouch
		return
	if not want_crouch and not _can_stand_up(shape.radius, standing, half_delta):
		# Still under something. Stay down rather than pushing through it.
		return
	shape.height = crouched if want_crouch else standing
	global_position.y += -half_delta if want_crouch else half_delta
	if camera_pivot:
		camera_pivot.position.y = crouch_eye_height if want_crouch else eye_height
	is_crouching = want_crouch


## Whether the standing capsule fits where the body would be if it stood up.
func _can_stand_up(radius: float, standing: float, half_delta: float) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = standing
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, half_delta, 0))
	return space.collide_shape(query, 1).is_empty()


func _ensure_input_map() -> void:
	var defaults := {
		"ui_up": [KEY_W, KEY_UP],
		"ui_down": [KEY_S, KEY_DOWN],
		"ui_left": [KEY_A, KEY_LEFT],
		"ui_right": [KEY_D, KEY_RIGHT],
		"ui_accept": [KEY_SPACE],
		"hf_use": [KEY_E]
	}

	for action_name in defaults.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var existing = InputMap.action_get_events(action_name)
		for keycode in defaults[action_name]:
			var has_key := false
			for event in existing:
				if event is InputEventKey and event.keycode == keycode:
					has_key = true
					break
			if not has_key:
				var key_event := InputEventKey.new()
				key_event.keycode = keycode
				key_event.physical_keycode = keycode
				InputMap.action_add_event(action_name, key_event)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI * 0.5, PI * 0.5)

	if event.is_action_pressed("ui_cancel"):
		_set_cursor_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

	if InputMap.has_action(use_action) and event.is_action_pressed(use_action):
		_press_what_is_under_the_reticle()


## Fire `OnPressed` on the button the reticle is on.
##
## A trigger volume raises its own output, because a body entering it is the
## whole event. Pressing is not: it is something a player decides to do, so the
## game is the only thing that can say it happened (#686). This is the playtest
## player saying it, and it is also the shape a game's own player wants - ray
## from the camera, find a button, hand its name to the dispatcher.
func _press_what_is_under_the_reticle() -> void:
	if not camera or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if not space:
		return
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * use_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Every layer. Which one the level baked onto is the mapper's choice and is
	# not a statement about what can be pressed.
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Variant = hit.get("collider")
	if not (collider is Node):
		return
	var node := collider as Node
	if str(node.get_meta("brush_entity_class", "")) != "func_button":
		return
	var pressed := str(node.get_meta("entity_name", ""))
	if pressed == "":
		return
	var dispatcher: Node = get_tree().get_first_node_in_group(HFIORuntime.DISPATCHER_GROUP)
	if dispatcher and dispatcher.has_method("fire"):
		dispatcher.call("fire", pressed, "OnPressed", "")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# 1. Handle Gravity & Coyote Time
	if is_on_floor():
		time_since_on_floor = 0.0
	else:
		time_since_on_floor += delta
		velocity.y -= gravity * delta

	# 2. Handle Jump with Coyote Time
	var wants_jump = (
		Input.is_action_just_pressed(jump_action) or Input.is_action_just_pressed("ui_accept")
	)
	if wants_jump and time_since_on_floor < coyote_time:
		velocity.y = jump_velocity
		time_since_on_floor = coyote_time

	# 3. Determine Speed based on State
	# The crouch is applied before the speed is read, because a player under a
	# ledge asked to stand up and could not is still crouched.
	_set_crouched(Input.is_key_pressed(KEY_CTRL))
	var current_speed = walk_speed
	if is_crouching:
		current_speed = crouch_speed
	elif Input.is_key_pressed(KEY_SHIFT):
		current_speed = sprint_speed

	# 4. Movement Logic with Smooth Acceleration
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var has_input = direction.length() > 0.0
	var accel = acceleration if has_input else deceleration
	if not is_on_floor():
		accel *= air_control
	var target_vel = direction * current_speed if has_input else Vector3.ZERO

	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	_step_up_if_blocked(delta)
	move_and_slide()

	# 5. Effects (FOV and Head Bob)
	_apply_camera_effects(delta, has_input)


## Lift a grounded body over a riser it is about to walk into. Returns whether it
## did.
##
## Godot's `CharacterBody3D` has no automatic step-up, so a vertical face is a
## wall to it whatever its height - a five centimetre riser stopped the player
## exactly as a twenty-five centimetre one did, and the stairs the plugin's own
## generators build were unwalkable (#711).
##
## Three tests, and all three have to hold. The motion is blocked from where the
## feet are, or there is nothing in the way. It is clear from a step height above
## them, or this is a wall rather than a step. And there is something to land on
## up there, or it is a lip over a hole. The caller's `move_and_slide()` then
## carries the body forward the same frame, and `floor_snap_length` pulls it back
## down onto the step.
##
## Static, and taking the body, so the thing that ships is the thing a test or a
## scenario can drive without an input device.
static func step_body_up(body: CharacterBody3D, motion: Vector3, max_height: float) -> bool:
	if max_height <= 0.0 or not body.is_on_floor():
		return false
	var flat := Vector3(motion.x, 0.0, motion.z)
	if flat.length_squared() <= 0.0:
		return false
	var here := body.global_transform
	if not body.test_move(here, flat):
		return false
	var lifted := here.translated(Vector3.UP * max_height)
	if body.test_move(lifted, flat):
		return false
	if not body.test_move(lifted, Vector3.DOWN * (max_height + 0.05)):
		return false
	body.global_transform = lifted
	return true


func _step_up_if_blocked(delta: float) -> void:
	step_body_up(self, Vector3(velocity.x, 0.0, velocity.z) * delta, max_step_height)


func _apply_camera_effects(delta: float, is_moving: bool) -> void:
	if not camera:
		return

	# Head Bobbing Logic
	var horizontal_speed = Vector3(velocity.x, 0.0, velocity.z).length()
	if is_moving and is_on_floor():
		head_bob_time += delta * max(1.0, horizontal_speed)
		camera.position.y = sin(head_bob_time * head_bob_freq) * head_bob_amp
		camera.position.x = cos(head_bob_time * head_bob_freq * 0.5) * head_bob_amp
	else:
		head_bob_time = 0.0
		camera.position = camera.position.lerp(Vector3.ZERO, delta * 10.0)

	# FOV Stretching while sprinting
	var target_fov = base_fov
	if horizontal_speed > walk_speed + 1.0:
		target_fov = base_fov * sprint_fov_multiplier
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
