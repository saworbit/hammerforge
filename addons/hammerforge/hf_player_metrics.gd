extends RefCounted
## What the playtest player can do, read from its own script, so Validate, the
## Agent Bridge and the player itself cannot disagree (#1045, #1046).

const PlaytestFPS = preload("playtest_fps.gd")


## The standing player: `height` and `radius` of its capsule, `eye_height` above
## its feet, the `step_height` it walks up, the `jump_height` it reaches, the
## `crouch_height` it fits under, and `max_slope_degrees`, the steepest floor it
## walks. The camera sits `eye_height` over the body's centre, which is half the
## capsule over the feet.
static func standing() -> Dictionary:
	var script: Script = PlaytestFPS
	var height := float(script.get_property_default_value("capsule_height"))
	var jump := float(script.get_property_default_value("jump_velocity"))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var slope := float(
		ClassDB.class_get_property_default_value("CharacterBody3D", "floor_max_angle")
	)
	return {
		"height": height,
		"radius": float(script.get_property_default_value("capsule_radius")),
		"eye_height": height * 0.5 + float(script.get_property_default_value("eye_height")),
		"step_height": float(script.get_property_default_value("max_step_height")),
		"jump_height": jump * jump / (2.0 * gravity),
		"crouch_height": float(script.get_property_default_value("crouch_height")),
		"max_slope_degrees": rad_to_deg(slope),
	}
