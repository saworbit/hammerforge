@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The player spawn and the validation that runs before a playtest.
##
## `validate_spawn()` raycasts down from the spawn to find a floor and reports
## "Floating in space" when it finds none. Every one of those rays carries a
## collision mask, and the collision it is looking for was put there by the
## bake, which has a configurable layer. Whether the two agree about which layer
## that is decides whether a perfectly good level can be playtested.


func id() -> String:
	return "spawn"


func summary() -> String:
	return "spawn validation against the layer the bake actually put the collision on"


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func run() -> void:
	await _spawn_validation_on_the_default_layer()
	await _spawn_validation_when_the_bake_layer_is_not_one()


func physics_frame() -> void:
	await _tree.physics_frame


## A floor, a spawn standing on it, baked and validated. This is the case that
## has to work.
func _validate_on_layer(layer_index: int) -> Dictionary:
	var root: Node3D = await fresh_root()
	root.bake_collision_layer_index = layer_index
	# A wide, thin floor with its top face at y = 0.
	root.create_brush_from_info(
		{"shape": 0, "size": Vector3(512, 16, 512), "center": Vector3(0, -8, 0)}
	)
	await frame()

	var spawn: Node3D = root.spawn_system.create_default_spawn()
	if spawn == null:
		flag("create_default_spawn() returned nothing")
		return {}
	spawn.global_position = Vector3(0, 1.0, 0)
	await frame()

	# The dock passes the mask from its layer dropdown; 0 is what it returns when
	# that control is not up, and is the value every bake path treats as
	# "use bake_collision_layer_index".
	var baked: bool = await root.bake(true, false, 0)
	await frame()
	await physics_frame()
	await physics_frame()

	var validation: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	return {
		"baked": baked,
		"layer_index": layer_index,
		"layer_bits": root._layer_from_index(layer_index),
		"valid": validation.get("valid", false),
		"issues": Array(validation.get("issues", PackedStringArray())),
		"severity": validation.get("severity", -1),
		"floor_hit": validation.get("floor_hit", null) != null,
	}


func _spawn_validation_on_the_default_layer() -> void:
	var r: Dictionary = await _validate_on_layer(1)
	if r.is_empty():
		return
	note("bake_collision_layer_index = 1", r)
	if not bool(r["floor_hit"]):
		flag(
			"spawn validation finds no floor under a spawn standing on a baked floor",
			"on the default collision layer: %s" % r["issues"]
		)


## `bake_collision_layer_index` is `@export_range(1, 32, 1)` and configurable in
## the dock. `validate_spawn()` falls back to a literal `1` when it is handed no
## mask, and `1` is the bit for layer 1, not the layer the bake used.
func _spawn_validation_when_the_bake_layer_is_not_one() -> void:
	var r: Dictionary = await _validate_on_layer(3)
	if r.is_empty():
		return
	note("bake_collision_layer_index = 3", r)
	note(
		"the layer the bake put collision on",
		"index 3 -> bits %d, while validate_spawn's fallback mask is 1" % r["layer_bits"]
	)
	if not bool(r["floor_hit"]):
		flag(
			"spawn validation cannot see the floor when the bake collision layer is not 1",
			(
				"the same level that validates cleanly with bake_collision_layer_index = 1 reports %s with it set to 3. The bake put the collision on layer bits %d; validate_spawn() is written `var mask := collision_mask if collision_mask > 0 else 1`, so with no mask passed it rays against layer 1 and finds nothing. Every playtest path in dock_manage_handler.gd passes get_collision_layer_mask(), which returns 0 when the dropdown is not up -- and 0 is exactly the value that reaches this fallback."
				% [r["issues"], r["layer_bits"]]
			)
		)
	else:
		note("validation still found the floor", "the fallback and the bake layer agree here")
