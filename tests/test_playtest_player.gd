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


# ---------------------------------------------------------------------------
# A spawn turned some other way than Rotate
# ---------------------------------------------------------------------------


## `node` turned about world up by `degrees` round itself, written straight onto
## it as Godot's gizmo, the Inspector and their undo write it.
func _turn_natively(node: Node3D, degrees: float) -> void:
	node.global_transform = HFTransformSystem.rotated_transform(
		node.global_transform, Basis(Vector3.UP, deg_to_rad(degrees)), node.global_position
	)


func _spawn_yaw(root: LevelRoot) -> float:
	return rad_to_deg(float(root._resolve_playtest_spawn()["yaw"]))


func test_a_spawn_turned_with_the_gizmo_faces_the_player_the_way_it_was_turned() -> void:
	# Test Level faces the player along the spawn's stored angle, and only Rotate
	# turned it, so a spawn turned with Godot's gizmo or Inspector put the player
	# facing the way it used to.
	var root := _fresh_root()
	var spawn := root.spawn_system.create_default_spawn() as DraftEntity
	var tracker := HFBrushChangeTracker.new()
	tracker.prime(root)
	var square := spawn.global_transform
	# The gizmo's commit, then its undo and redo, over and over.
	for i in 3:
		_turn_natively(spawn, 90.0)
		tracker.reconcile(root)
		assert_eq(spawn.entity_data.get("angle"), 90.0, "turned with it, round %d" % i)
		assert_almost_eq(_spawn_yaw(root), 90.0, 0.001, "and so is the player, round %d" % i)
		spawn.global_transform = square
		tracker.reconcile(root)
		assert_eq(spawn.entity_data.get("angle"), 0.0, "and back exactly, round %d" % i)


func test_a_spawn_hammerforge_turned_is_not_turned_again() -> void:
	# Rotate turns the angle itself and the tracker reconciles after every command.
	var root := _fresh_root()
	var spawn := _spawn_at(root, HFSpawnSystem.FEET_OFFSET, 0.0)
	spawn.entity_data["angle"] = 0.0
	var path := root.get_path_to(spawn)
	var tracker := HFBrushChangeTracker.new()
	tracker.prime(root)
	var before: Dictionary = root.capture_brush_scope([], [path])
	root.rotate_managed_nodes([], [path], 1, 90.0, spawn.global_position)
	tracker.reconcile(root)
	assert_eq(spawn.entity_data.get("angle"), 90.0, "turned once")
	root.restore_brush_scope(before)
	tracker.reconcile(root)
	assert_eq(spawn.entity_data.get("angle"), 0.0, "and its undo puts back the angle it recorded")


func test_only_a_turn_about_up_turns_a_spawn() -> void:
	var root := _fresh_root()
	var spawn := _spawn_at(root, HFSpawnSystem.FEET_OFFSET, 0.0)
	spawn.entity_data["angle"] = 0.0
	var tracker := HFBrushChangeTracker.new()
	tracker.prime(root)
	var edits := {
		"tipped forward": func(n): n.rotation = Vector3(deg_to_rad(30.0), 0, 0),
		"rolled": func(n): n.rotation = Vector3(0, 0, deg_to_rad(30.0)),
		"moved": func(n): n.position += Vector3(3, 1, 2),
		"scaled": func(n): n.scale = Vector3(2, 1, 0.5),
	}
	for label in edits:
		spawn.transform = Transform3D.IDENTITY
		tracker.reconcile(root)
		edits[label].call(spawn)
		tracker.reconcile(root)
		assert_eq(spawn.entity_data.get("angle"), 0.0, "%s: not a turn of the compass" % label)


func test_a_spot_lights_cone_angle_is_not_a_bearing() -> void:
	# A spot light's `angle` is its cone, and its aim is the node's own turn.
	var root := _fresh_root()
	var lamp := DraftEntityScript.new()
	lamp.entity_type = "light_spot"
	lamp.entity_class = "light_spot"
	root.add_entity(lamp)
	lamp.entity_data["angle"] = 45.0
	var tracker := HFBrushChangeTracker.new()
	tracker.prime(root)
	_turn_natively(lamp, 90.0)
	tracker.reconcile(root)
	assert_eq(lamp.entity_data.get("angle"), 45.0)


func test_the_exported_playtest_player_faces_the_turned_spawn() -> void:
	var root := _fresh_root()
	var spawn := _spawn_at(root, HFSpawnSystem.FEET_OFFSET, 0.0)
	spawn.entity_data["angle"] = 0.0
	var tracker := HFBrushChangeTracker.new()
	tracker.prime(root)
	_turn_natively(spawn, 90.0)
	tracker.reconcile(root)
	var out := "user://test_turned_spawn_playtest.tscn"
	assert_true(root.export_playtest_scene(out, true), "fixture: exported")
	var scene := (load(out) as PackedScene).instantiate()
	var player := scene.get_node("PlaytestPlayer") as Node3D
	var marker := scene.get_node("PlayerStart") as Node3D
	assert_almost_eq(rad_to_deg(player.rotation.y), 90.0, 0.001, "the player faces the turn")
	assert_almost_eq(float(marker.get_meta("entity_data", {}).get("angle")), 90.0, 0.001)
	scene.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))


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
