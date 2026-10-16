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
# Use presses a button through its lock and its wait (#1121)
# ===========================================================================


## A dispatcher whose clock the test sets, so a wait is checked without sleeping.
class ClockedRuntime:
	extends HFIORuntime
	var now := 0.0

	func _now() -> float:
		return now


## A level holding a baked button at `button_at`, wired to a door, with a
## dispatcher over it. Returns the level and the dispatcher.
func _button_level(data: Dictionary, button_at: Vector3) -> Array:
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
	body.global_position = button_at
	var clocked := ClockedRuntime.new()
	world.add_child(clocked)
	clocked.wire()
	watch_signals(clocked)
	return [world, clocked]


## A player looking down -Z at a baked button a metre and a half away, wired to a
## door, with a dispatcher over all of it. Returns the player and the dispatcher.
func _player_facing_a_button(data: Dictionary) -> Array:
	var level: Array = _button_level(data, Vector3(0, 1, -1.5))
	var player := CharacterBody3D.new()
	player.set_script(PlaytestFPS)
	(level[0] as Node3D).add_child(player)
	await wait_physics_frames(2)
	return [player, level[1]]


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


func test_use_presses_a_button_through_the_dispatcher_of_its_own_level():
	# Another level loaded first, with a button of the same name out of reach. The
	# Use key took the first dispatcher in the tree, that level's, and the press
	# fired that level's wires (#1211).
	var other: Array = _button_level({"wait": 0.0}, Vector3(40, 1, -1.5))
	var setup: Array = await _player_facing_a_button({"wait": 0.0})
	var player = setup[0]

	player._press_what_is_under_the_reticle()

	assert_signal_emit_count(setup[1], "io_received", 1, "the press reaches the button's level")
	assert_signal_emit_count(other[1], "io_received", 0, "and not the level loaded first")
