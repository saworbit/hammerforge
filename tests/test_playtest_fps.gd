extends GutTest

const PlaytestFPS = preload("res://addons/hammerforge/playtest_fps.gd")


func test_gravity_uses_project_setting_with_fallback():
	var player := CharacterBody3D.new()
	player.set_script(PlaytestFPS)
	add_child_autoqfree(player)
	assert_gt(player.gravity, 0.0, "Playtest gravity must not be zero in a default project")


func test_ensure_hud_creates_reticle_and_pause_overlay():
	var player := CharacterBody3D.new()
	player.set_script(PlaytestFPS)
	add_child_autoqfree(player)
	player._ensure_hud()
	var hud := player.get_node_or_null("PlaytestHUD")
	assert_not_null(hud, "Playtest HUD canvas should exist")
	assert_not_null(hud.get_node_or_null("Reticle"), "Crosshair reticle should exist")
	var pause := hud.get_node_or_null("PauseOverlay")
	assert_not_null(pause, "Pause/controls overlay should exist")
	assert_false(pause.visible, "Pause overlay starts hidden while mouse is captured")
	player._set_cursor_captured(false)
	assert_true(pause.visible, "Pause overlay shows when the cursor is released")


# ===========================================================================
# Stairs the plugin builds have to be walkable (#711)
# ===========================================================================


func _static_box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = at


func _capsule_body(parent: Node3D, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.35
	shape.shape = capsule
	body.add_child(shape)
	parent.add_child(body)
	body.floor_snap_length = 0.45
	body.global_position = at
	return body


## Drop the body onto whatever is under it, without moving it forward.
func _settle(body: CharacterBody3D) -> void:
	var fall := 0.0
	for _i in 30:
		fall = 0.0 if body.is_on_floor() else fall - 9.8 / 60.0
		body.velocity = Vector3(0.0, fall, 0.0)
		body.move_and_slide()
		fall = body.velocity.y
		await get_tree().physics_frame


## Walk toward +z the way `playtest_fps.gd` moves: gravity only while airborne,
## and the step-up run before each `move_and_slide()`. Stops at `stop_z` so the
## body does not walk off the end of the test floor and fall out of the world.
func _walk_forward(
	body: CharacterBody3D, frames: int, step_height: float, stop_z: float = 4.5
) -> void:
	var fall := 0.0
	for _i in frames:
		if body.global_position.z >= stop_z:
			return
		if body.is_on_floor():
			fall = 0.0
		else:
			fall -= 9.8 / 60.0
		body.velocity = Vector3(0.0, fall, 3.0)
		PlaytestFPS.step_body_up(body, Vector3(0.0, 0.0, 3.0) / 60.0, step_height)
		body.move_and_slide()
		fall = body.velocity.y
		await get_tree().physics_frame


func test_the_player_climbs_a_staircase_the_plugin_builds():
	# Godot's CharacterBody3D has no step-up, so every vertical face was a wall to
	# it whatever its height and the plugin's own generated stairs were unwalkable.
	var world := Node3D.new()
	add_child_autoqfree(world)
	_static_box(world, Vector3(12, 0.3, 12), Vector3(0, -0.15, 0))
	for i in 8:
		_static_box(world, Vector3(3, 0.25, 0.5), Vector3(0, 0.25 * (i + 0.5), 1.0 + i * 0.5))
	var body := _capsule_body(world, Vector3(0, 0.9, -1.0))
	await _settle(body)
	var base: float = body.global_position.y
	await _walk_forward(body, 400, 0.4)
	assert_gt(body.global_position.y - base, 1.5, "eight 0.25 steps should be climbed")
	assert_gt(body.global_position.z, 3.0, "and the player should be up the stairs")


func test_the_player_does_not_climb_a_wall():
	# The step-up has to tell a step from a wall, or it is a cheat rather than a
	# fix: the same total height as the staircase above, in one face.
	var world := Node3D.new()
	add_child_autoqfree(world)
	_static_box(world, Vector3(12, 0.3, 12), Vector3(0, -0.15, 0))
	_static_box(world, Vector3(3, 2.0, 0.5), Vector3(0, 1.0, 1.0))
	var body := _capsule_body(world, Vector3(0, 0.9, -1.0))
	await _settle(body)
	var base: float = body.global_position.y
	await _walk_forward(body, 200, 0.4)
	assert_almost_eq(body.global_position.y, base, 0.1, "a wall is not a step")
	assert_lt(body.global_position.z, 0.75, "and it stops the player")


func test_a_step_taller_than_the_limit_is_a_wall():
	var world := Node3D.new()
	add_child_autoqfree(world)
	_static_box(world, Vector3(12, 0.3, 12), Vector3(0, -0.15, 0))
	_static_box(world, Vector3(3, 0.6, 4), Vector3(0, 0.3, 2.5))
	var body := _capsule_body(world, Vector3(0, 0.9, -1.0))
	await _settle(body)
	var base: float = body.global_position.y
	await _walk_forward(body, 200, 0.2)
	assert_almost_eq(
		body.global_position.y, base, 0.1, "max_step_height is the limit it says it is"
	)


# ===========================================================================
# The player walks up its step height and no higher (#1216)
# ===========================================================================


## A floor and one block `riser` high across the way at z 0.5, wide enough for a
## walk at an angle to stay on it, then a capsule standing a metre short of it.
## Each in its own world, far from the others, so one walk does not meet another.
func _riser_and_body(riser: float, slot: int) -> CharacterBody3D:
	var world := Node3D.new()
	add_child_autoqfree(world)
	world.position = Vector3(100.0 * slot, 0, 0)
	_static_box(world, Vector3(60, 0.3, 60), world.position + Vector3(0, -0.15, 0))
	_static_box(world, Vector3(40, riser, 4), world.position + Vector3(0, riser * 0.5, 2.5))
	return _capsule_body(world, world.position + Vector3(0, 0.9, -0.5))


## Walk each body at the playtest player's own speed, `degrees[i]` off head on
## into its block, the way `playtest_fps.gd` moves, all in the same frames.
## Returns how far above where it settled each one stood.
func _walk_into(bodies: Array, degrees: Array, step_height: float) -> Array:
	var speed := float((PlaytestFPS as Script).get_property_default_value("walk_speed"))
	var falls: Array = []
	var bases: Array = []
	var highest: Array = []
	for body in bodies:
		falls.append(0.0)
	for frame in 30 + 90:
		var walking := frame >= 30
		if frame == 30:
			for body in bodies:
				bases.append(body.global_position.y)
				highest.append(body.global_position.y)
		for i in bodies.size():
			var body: CharacterBody3D = bodies[i]
			var a := deg_to_rad(float(degrees[i]))
			var along := Vector3(sin(a), 0.0, cos(a)) * speed if walking else Vector3.ZERO
			falls[i] = 0.0 if body.is_on_floor() else float(falls[i]) - 9.8 / 60.0
			body.velocity = Vector3(along.x, falls[i], along.z)
			if walking:
				PlaytestFPS.step_body_up(body, along / 60.0, step_height)
			body.move_and_slide()
			falls[i] = body.velocity.y
			if walking and body.is_on_floor():
				highest[i] = maxf(highest[i], body.global_position.y)
		await get_tree().physics_frame
	var climbed: Array = []
	for i in bodies.size():
		climbed.append(float(highest[i]) - float(bases[i]))
	return climbed


## Each riser walked into head on, 30 and 60 degrees off by a player with a 0.4 m
## step: `{label, riser, climbed}` for each walk.
func _climbs(risers: Array) -> Array:
	var bodies: Array = []
	var degrees: Array = []
	var walks: Array = []
	for riser in risers:
		for angle in [0.0, 30.0, 60.0]:
			bodies.append(_riser_and_body(riser, bodies.size()))
			degrees.append(angle)
			var label := "a %.2f m riser walked into %.0f degrees off head on" % [riser, angle]
			walks.append({"label": label, "riser": riser})
	var climbed: Array = await _walk_into(bodies, degrees, 0.4)
	for i in walks.size():
		walks[i]["climbed"] = climbed[i]
	return walks


func test_a_riser_a_little_over_the_step_height_is_a_wall_from_any_angle():
	# Lifted by its step height, the capsule's rounded base rode on over a nose up
	# to a tenth of a metre higher, so a 0.4 m step climbed 0.45 m risers from
	# every angle and Validate's stair warning was wrong about them.
	for walk in await _climbs([0.42, 0.45, 0.5]):
		assert_lt(float(walk["climbed"]), 0.1, walk["label"])


func test_a_riser_at_the_step_height_is_climbed_from_any_angle():
	for walk in await _climbs([0.2, 0.35, 0.4]):
		assert_almost_eq(float(walk["climbed"]), float(walk["riser"]), 0.05, walk["label"])


## A 20 degree ramp up a metre from z 1, running on into a landing level with its
## top, and a block `riser` high on the landing whose face stands at the ramp's
## top edge. Then a capsule on the floor before the ramp.
func _ramp_step_and_body(riser: float, slot: int) -> CharacterBody3D:
	var world := Node3D.new()
	add_child_autoqfree(world)
	var o := Vector3(100.0 * slot, 0, 0)
	_static_box(world, Vector3(60, 0.3, 60), o + Vector3(0, -0.15, 0))
	var slope := deg_to_rad(20.0)
	var run := 1.0 / tan(slope)
	var span := run + 0.3
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, span / cos(slope))
	shape.shape = box
	ramp.add_child(shape)
	world.add_child(ramp)
	var middle := Vector3(0, span * 0.5 * tan(slope), 1.0 + span * 0.5)
	var up := Vector3(0, cos(slope), -sin(slope))
	ramp.global_transform = Transform3D(Basis(Vector3.RIGHT, -slope), o + middle - up * 0.1)
	_static_box(world, Vector3(20, 1.0, 4), o + Vector3(0, 0.5, 1.0 + run + 2.0))
	_static_box(world, Vector3(20, riser, 3), o + Vector3(0, 1.0 + riser * 0.5, 1.0 + run + 1.5))
	return _capsule_body(world, o + Vector3(0, 0.9, -0.5))


func test_a_step_at_the_top_of_a_ramp_is_measured_from_the_ramp():
	# Walking up a slope, the capsule meets the step's face with its feet still
	# down the slope, lower than the step's foot. The step is no taller for that.
	var bodies := [_ramp_step_and_body(0.38, 40), _ramp_step_and_body(0.45, 41)]
	var climbed: Array = await _walk_into(bodies, [0.0, 0.0], 0.4)
	assert_almost_eq(float(climbed[0]), 1.38, 0.05, "a 0.38 m step at a ramp's top")
	assert_lt(float(climbed[1]), 1.05, "a 0.45 m one stops it on the ramp")


# ===========================================================================
# Use presses a button through its lock and its wait (#1121)
# ===========================================================================


## A dispatcher whose clock the test sets, so a wait is checked without sleeping.
class ClockedRuntime:
	extends HFIORuntime
	var now := 0.0

	func _now() -> float:
		return now


## A player looking down -Z at a baked button a metre and a half away, wired to a
## door, with a dispatcher over all of it. Returns the player and the dispatcher.
func _player_facing_a_button(data: Dictionary) -> Array:
	var world := Node3D.new()
	add_child_autoqfree(world)
	var door := Node3D.new()
	door.name = "gate"
	world.add_child(door)
	var mesh := MeshInstance3D.new()
	mesh.name = "vault_button"
	mesh.set_meta("entity_name", "vault_button")
	mesh.set_meta("brush_entity_class", "func_button")
	mesh.set_meta("entity_data", data.duplicate())
	mesh.set_meta(
		"entity_io_outputs",
		[{"output_name": "OnPressed", "target_name": "gate", "input_name": "Open"}]
	)
	world.add_child(mesh)
	var body := StaticBody3D.new()
	body.set_meta("entity_name", "vault_button")
	body.set_meta("brush_entity_class", "func_button")
	body.set_meta("entity_data", data.duplicate())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = Vector3(0, 1, -1.5)
	var player := CharacterBody3D.new()
	player.set_script(PlaytestFPS)
	world.add_child(player)
	var clocked := ClockedRuntime.new()
	world.add_child(clocked)
	clocked.wire()
	watch_signals(clocked)
	await wait_physics_frames(2)
	return [player, clocked]


func test_use_twice_inside_a_buttons_wait_presses_it_once():
	# The Use key fired OnPressed by name every time, whatever the button's wait.
	var setup: Array = await _player_facing_a_button({"wait": 1.0})
	var player = setup[0]
	var clocked: ClockedRuntime = setup[1]

	player._press_what_is_under_the_reticle()
	clocked.now = 0.5
	player._press_what_is_under_the_reticle()
	assert_signal_emit_count(clocked, "io_received", 1, "two presses half a second apart")

	clocked.now = 1.0
	player._press_what_is_under_the_reticle()
	assert_signal_emit_count(clocked, "io_received", 2, "and one once the wait is up")


func test_use_does_not_press_a_locked_button():
	var setup: Array = await _player_facing_a_button({"wait": 0.0, "locked": true})
	var player = setup[0]
	var clocked: ClockedRuntime = setup[1]

	player._press_what_is_under_the_reticle()

	assert_signal_emit_count(clocked, "io_received", 0, "a locked button is not pressed")
