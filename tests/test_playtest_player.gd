extends GutTest

## Where the playtest puts the player, and what crouch does to it.
##
## Two pieces of code hold a model of the same player. `HFSpawnSystem` treats a
## spawn marker as the player's feet: it builds its test capsule at
## `pos + PLAYER_HEIGHT / 2` and places a marker at
## `floor + FEET_OFFSET + height_offset`, which the user guide describes as extra
## height above the floor for safety. `playtest_fps.gd` is a `CharacterBody3D`
## whose capsule is centred on the node. The conversion between the two belongs
## in one place.

const PlaytestPlayer = preload("res://addons/hammerforge/playtest_fps.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _spawn_at(root: LevelRoot, y: float, height_offset: float) -> Node3D:
	var spawn := DraftEntityScript.new()
	spawn.name = "PlayerStart"
	spawn.entity_type = "player_start"
	spawn.entity_class = "player_start"
	spawn.set_meta("is_entity", true)
	root.add_entity(spawn)
	spawn.entity_data["height_offset"] = height_offset
	spawn.global_position = Vector3(0, y, 0)
	return spawn


# ---------------------------------------------------------------------------
# Where the body starts (#468)
# ---------------------------------------------------------------------------


func test_the_players_feet_start_on_the_spawn_marker() -> void:
	var root := _fresh_root()
	# The height the spawn system itself chooses for height_offset 0, against a
	# floor whose top is at y = 0.
	var spawn := _spawn_at(root, HFSpawnSystem.FEET_OFFSET, 0.0)
	var pose: Dictionary = root._resolve_playtest_spawn()
	var feet: float = float(pose["position"].y) - HFSpawnSystem.PLAYER_HEIGHT * 0.5
	assert_almost_eq(
		feet,
		spawn.global_position.y,
		0.001,
		"the body is centred on the capsule, so it goes half a player above the feet"
	)
	assert_gte(feet, 0.0, "and the feet must not start inside the floor they stand on")


func test_height_offset_is_not_counted_twice() -> void:
	var root := _fresh_root()
	# A marker placed the way auto_fix_spawn() places one: floor + FEET_OFFSET +
	# height_offset. The offset is already in the marker's position.
	var offset := 1.0
	var spawn := _spawn_at(root, HFSpawnSystem.FEET_OFFSET + offset, offset)
	var pose: Dictionary = root._resolve_playtest_spawn()
	var feet: float = float(pose["position"].y) - HFSpawnSystem.PLAYER_HEIGHT * 0.5
	assert_almost_eq(
		feet,
		spawn.global_position.y,
		0.001,
		"the feet land on the marker, not height_offset above it a second time"
	)


func test_the_spawn_yaw_still_reaches_the_player() -> void:
	var root := _fresh_root()
	var spawn := _spawn_at(root, HFSpawnSystem.FEET_OFFSET, 0.0)
	spawn.entity_data["angle"] = 90.0
	var pose: Dictionary = root._resolve_playtest_spawn()
	assert_almost_eq(float(pose["yaw"]), deg_to_rad(90.0), 0.001, "the marker's angle is the yaw")


func test_the_two_player_models_agree_about_how_tall_a_player_is() -> void:
	# HFSpawnSystem carries the comment "Player capsule constants (MUST match
	# playtest_fps.gd defaults)". That was the half of the agreement that was
	# written down; this is the half that fails when it stops being true.
	var player = PlaytestPlayer.new()
	add_child_autoqfree(player)
	assert_eq(
		player.capsule_height,
		HFSpawnSystem.PLAYER_HEIGHT,
		"the height the spawn system validates against is the one the player is built with"
	)
	assert_eq(player.capsule_radius, HFSpawnSystem.PLAYER_RADIUS, "and the same for the radius")


# ---------------------------------------------------------------------------
# Crouch (#469)
# ---------------------------------------------------------------------------


func test_crouching_shrinks_the_capsule_and_lowers_the_camera() -> void:
	var player = PlaytestPlayer.new()
	add_child_autoqfree(player)
	player._ensure_collider()
	player.camera_pivot = Node3D.new()
	player.camera_pivot.position.y = player.eye_height
	player.add_child(player.camera_pivot)
	var collider := player.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collider.shape as CapsuleShape3D
	var standing: float = shape.height
	var feet_before: float = player.global_position.y - standing * 0.5

	player._set_crouched(true)
	assert_true(player.is_crouching, "Ctrl crouches")
	assert_lt(shape.height, standing, "and the capsule is the thing that has to change")
	assert_almost_eq(
		player.camera_pivot.position.y,
		player.crouch_eye_height,
		0.001,
		"the camera comes down with it"
	)
	assert_almost_eq(
		player.global_position.y - shape.height * 0.5,
		feet_before,
		0.001,
		"the capsule is centred on the node, so the feet stay where they were"
	)


func test_standing_up_again_restores_the_capsule() -> void:
	var player = PlaytestPlayer.new()
	add_child_autoqfree(player)
	player._ensure_collider()
	player.camera_pivot = Node3D.new()
	player.add_child(player.camera_pivot)
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var standing: float = shape.height

	player._set_crouched(true)
	player._set_crouched(false)
	assert_false(player.is_crouching, "releasing Ctrl stands up when there is room")
	assert_almost_eq(shape.height, standing, 0.001, "and the capsule goes back")
	assert_almost_eq(player.camera_pivot.position.y, player.eye_height, 0.001, "so does the camera")


func test_crouch_speed_follows_the_capsule_and_not_the_key() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/playtest_fps.gd")
	var start := source.find("# 3. Determine Speed based on State")
	var body := source.substr(start, 400)
	# A player under a ledge who asked to stand up and could not is still
	# crouched, so the speed has to read the state rather than the key.
	assert_true(
		body.contains("if is_crouching:"),
		"the speed reads the crouch state, which the headroom check can refuse to leave"
	)
	assert_true(body.contains("_set_crouched("), "and the state is set before it is read")
