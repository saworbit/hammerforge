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
@export var capsule_radius := 0.35
@export var capsule_height := 1.6

# --- State Variables ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_pivot: Node3D
var camera: Camera3D
var head_bob_time := 0.0
var time_since_on_floor := 0.0
var is_crouching := false

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_ensure_input_map()
	_ensure_collider()

	# Setup Camera Hierarchy for separate Bobbing/Tilting
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = 1.0
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = base_fov
	camera_pivot.add_child(camera)
	camera.make_current()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

func _ensure_input_map() -> void:
	var defaults := {
		"ui_up": [KEY_W, KEY_UP],
		"ui_down": [KEY_S, KEY_DOWN],
		"ui_left": [KEY_A, KEY_LEFT],
		"ui_right": [KEY_D, KEY_RIGHT],
		"ui_accept": [KEY_SPACE]
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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

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
	var wants_jump = Input.is_action_just_pressed(jump_action) or Input.is_action_just_pressed("ui_accept")
	if wants_jump and time_since_on_floor < coyote_time:
		velocity.y = jump_velocity
		time_since_on_floor = coyote_time

	# 3. Determine Speed based on State
	var current_speed = walk_speed
	var sprinting = Input.is_key_pressed(KEY_SHIFT)
	var crouching = Input.is_key_pressed(KEY_CTRL)
	if sprinting:
		current_speed = sprint_speed
	elif crouching:
		current_speed = crouch_speed
	is_crouching = crouching

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

	move_and_slide()

	# 5. Effects (FOV and Head Bob)
	_apply_camera_effects(delta, has_input)

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
