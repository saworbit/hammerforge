@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Where the playtest player is put, against where the spawn validator says a
## player stands.
##
## Two pieces of code hold a model of the same player. `HFSpawnSystem` places a
## 1.6 by 0.35 capsule with the spawn point at its **feet**: `validate_spawn()`
## builds the capsule at `pos + height/2` and wants the spawn at
## `floor + FEET_OFFSET + height_offset`, which is also where
## `create_default_spawn()` puts it and where `auto_fix_spawn()` moves it back
## to. `LevelRoot._start_playtest()` then adds `height_offset` a second time and
## assigns the result to the `CharacterBody3D`'s `global_position`, which is the
## **centre** of that capsule.

const PLAYER_HEIGHT := 1.6  # HFSpawnSystem.PLAYER_HEIGHT, and playtest_fps.gd's capsule
const FEET_OFFSET := 0.1


func id() -> String:
	return "playtest-spawn"


func summary() -> String:
	return "where the playtest player's feet end up against the spawn the validator approved"


func run() -> void:
	await _a_spawn_the_validator_is_happy_with()
	await _a_spawn_asked_to_sit_on_the_floor()
	await _what_crouch_does()


func physics_frame() -> void:
	await _tree.physics_frame


## A floor with its top at y = 0, baked so the validator's rays have something
## to hit, and a spawn standing exactly where the spawn system puts one.
func _level_with_spawn(height_offset: float) -> Dictionary:
	var root: Node3D = await fresh_root()
	root.create_brush_from_info(
		{"shape": 0, "size": Vector3(512, 16, 512), "center": Vector3(0, -8, 0)}
	)
	await frame()
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	if spawn == null:
		flag("create_default_spawn() returned nothing")
		return {}
	spawn.entity_data["height_offset"] = height_offset
	spawn.global_position = Vector3(0, FEET_OFFSET + height_offset, 0)
	await frame()
	var baked: bool = await root.bake(true, false, 0)
	await frame()
	await physics_frame()
	await physics_frame()
	note("bake succeeded", baked)
	return {"root": root, "spawn": spawn}


func _a_spawn_the_validator_is_happy_with() -> void:
	var level: Dictionary = await _level_with_spawn(1.0)
	if level.is_empty():
		return
	var root: Node3D = level["root"]
	var spawn: Node3D = level["spawn"]
	var validation: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	note("spawn position", spawn.global_position)
	note("validator severity", validation.get("severity", 0))
	note("validator issues", validation.get("issues", PackedStringArray()))

	var pose: Dictionary = root._resolve_playtest_spawn()
	var centre: Vector3 = pose["position"]
	var feet: float = float(centre.y) - PLAYER_HEIGHT * 0.5
	note("where _start_playtest() puts the body (capsule centre)", centre)
	note("so the player's feet start at", feet)
	note("the spawn point, which the validator reads as the feet", spawn.global_position.y)
	note("the floor is at", 0.0)

	if absf(feet - float(spawn.global_position.y)) > 0.05:
		flag(
			"the playtest player does not start on the spawn the validator approved",
			(
				(
					"the spawn passes validation at y %.2f, and HFSpawnSystem reads that point as"
					+ " the player's feet: validate_spawn() puts the test capsule at pos +"
					+ " height/2, and both create_default_spawn() and auto_fix_spawn() place the"
					+ " spawn at floor + %.2f + height_offset. _resolve_playtest_spawn() then adds"
					+ " height_offset again (%.2f -> %.2f) and _start_playtest() assigns that to"
					+ " the body's global_position, which is the capsule centre. Feet land at %.2f,"
					+ " %.2f above the point the mapper placed, so every playtest opens with the"
					+ " player dropping."
				)
				% [
					spawn.global_position.y,
					FEET_OFFSET,
					spawn.global_position.y,
					centre.y,
					feet,
					feet - float(spawn.global_position.y),
				]
			)
		)


## The offset a mapper sets when they want the marker on the floor rather than
## floating above it. The validator still approves the placement.
func _a_spawn_asked_to_sit_on_the_floor() -> void:
	var level: Dictionary = await _level_with_spawn(0.0)
	if level.is_empty():
		return
	var root: Node3D = level["root"]
	var spawn: Node3D = level["spawn"]
	var validation: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	note("spawn position with height_offset 0", spawn.global_position)
	note("validator severity", validation.get("severity", 0))
	note("validator issues", validation.get("issues", PackedStringArray()))
	var pose: Dictionary = root._resolve_playtest_spawn()
	var feet: float = float(pose["position"].y) - PLAYER_HEIGHT * 0.5
	note("player feet", feet)
	if feet < 0.0:
		flag(
			"a spawn with height_offset 0 starts the player inside the floor",
			(
				(
					"the marker sits at the height the spawn system itself would choose for that"
					+ " offset, and the playtest centres the 1.6 capsule on it: the feet are at"
					+ " %.2f against a floor at 0.00, so the body starts %.2f units inside the"
					+ " geometry it was meant to stand on. Whether it is pushed out, falls through"
					+ " or catches is left to move_and_slide()."
				)
				% [feet, -feet]
			)
		)


## Crouch is on the playtest HUD. What it does to the body.
func _what_crouch_does() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/playtest_fps.gd")
	var shrinks := source.contains("shape.height = crouched")
	var lowers := source.contains("crouch_eye_height")
	var checks_headroom := source.contains("_can_stand_up")
	note("times playtest_fps.gd names is_crouching", source.count("is_crouching"))
	note("the pause overlay advertises crouch", source.contains("Ctrl crouch"))
	note("crouch changes the capsule height", shrinks)
	note("crouch lowers the camera pivot", lowers)
	note("standing up again checks for headroom", checks_headroom)
	if source.contains("Ctrl crouch") and not (shrinks and lowers and checks_headroom):
		flag(
			"the playtest advertises crouch without shrinking the player",
			(
				"a crawl space is the thing a playtest is meant to answer. If Ctrl only picks"
				+ " crouch_speed, a mapper testing one walks into the wall slowly and cannot"
				+ " tell whether the gap is too low or the crouch does not work. Shrinks the"
				+ (
					" capsule: %s. Lowers the camera: %s. Checks headroom before standing: %s."
					% [shrinks, lowers, checks_headroom]
				)
			)
		)
