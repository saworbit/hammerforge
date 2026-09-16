extends GutTest

## Every default that has an opinion about size is in the same world as the player.
##
## HammerForge drew on a Quake-family grid: a 16 unit snap, a 32 unit brush, a
## 128 unit arch. The playtest player, the spawn checks and the shipped examples
## were all metres, so a default brush was twenty player heights tall and the
## Draw then Test Level loop did not survive its own defaults (#625). One world
## unit is one metre, which is the convention Godot's own physics documentation
## uses and the one `physics/3d/default_gravity` of 9.8 already assumed.
##
## These assertions are deliberately loose. They are not a claim that 0.5 is the
## right grid; they are the tripwire that fails if a default drifts back onto the
## other scale, which is the only thing that was ever wrong.

const InputStateScript = preload("res://addons/hammerforge/input_state.gd")
const HFUserPrefsScript = preload("res://addons/hammerforge/hf_user_prefs.gd")
const HFArchBuilderScript = preload("res://addons/hammerforge/hf_arch_builder.gd")
const HFDomeBuilderScript = preload("res://addons/hammerforge/hf_dome_builder.gd")
const HFStairsBuilderScript = preload("res://addons/hammerforge/hf_stairs_builder.gd")
const HFSpiralStairsBuilderScript = preload("res://addons/hammerforge/hf_spiral_stairs_builder.gd")
const HFSpawnSystemScript = preload("res://addons/hammerforge/systems/hf_spawn_system.gd")
const HFSnapSystemScript = preload("res://addons/hammerforge/hf_snap_system.gd")

## The player the level is drawn for. Read off the spawn system rather than
## restated, so moving the player moves what counts as a sane default.
const PLAYER_HEIGHT := HFSpawnSystemScript.PLAYER_HEIGHT

## A drawn thing is furniture, a room or a structure. Nothing a default produces
## should be larger than a building.
const MAX_STRUCTURE_HEIGHTS := 8.0


func _root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


## Name to schema, so a failure says which generator drifted.
func _schemas() -> Dictionary:
	return {
		"arch": HFArchBuilderScript.settings_schema(),
		"dome": HFDomeBuilderScript.settings_schema(),
		"stairs": HFStairsBuilderScript.settings_schema(),
		"spiral stairs": HFSpiralStairsBuilderScript.settings_schema(),
	}


# ===========================================================================
# The drawing defaults
# ===========================================================================


func test_the_player_is_the_scale_the_runtime_assumes():
	assert_almost_eq(PLAYER_HEIGHT, 1.6, 0.001, "a person is about 1.6 metres")


func test_a_default_brush_is_a_thing_the_player_could_stand_next_to():
	var size: Vector3 = _root().brush_size_default
	for axis in [size.x, size.y, size.z]:
		assert_gt(axis, 0.0, "a default brush has size")
		assert_lt(
			axis / PLAYER_HEIGHT,
			MAX_STRUCTURE_HEIGHTS,
			"a default brush is a block, not a cathedral"
		)


func test_a_click_with_no_drag_makes_the_same_brush_as_the_default():
	# The drag path has its own copy of the default, and the two used to be the
	# same number in two places. A click with no drag is the first brush most
	# people make, so it is the one that has to match.
	var input_state = InputStateScript.new()
	assert_eq(
		input_state.drag_size_default,
		_root().brush_size_default,
		"the drag default and the brush default are the same brush"
	)


func test_one_grid_step_is_smaller_than_the_player():
	var snap: float = _root().grid_snap
	assert_gt(snap, 0.0, "the default grid snaps")
	assert_lt(snap, PLAYER_HEIGHT, "a single grid step is not taller than a person")


func test_the_saved_preference_default_is_the_level_default():
	# The dock reads the grid from the preferences file and writes it to the root,
	# so a preference default on the other scale reimposes it on every new user.
	assert_almost_eq(
		float(HFUserPrefsScript._defaults()["grid_snap"]),
		_root().grid_snap,
		0.0001,
		"a fresh install draws on the grid the level says it draws on"
	)


func test_geometry_snapping_does_not_swallow_the_grid():
	# The threshold is how far a vertex may sit from the point and still beat the
	# grid. 2.0 was an eighth of a step when a step was 16 units. The same number
	# against a half metre step would be four steps, so every vertex in the room
	# would win and grid snap would stop meaning anything.
	var root := _root()
	var snap := HFSnapSystemScript.new(root)
	assert_lt(
		snap.snap_threshold, root.grid_snap, "a vertex has to be nearer than a grid point to win"
	)


func test_the_quick_grid_sizes_are_grid_sizes_for_this_scale():
	# One ladder, read by the dock buttons and the viewport context menu both.
	var presets: Array[float] = HFSnapSystemScript.GRID_PRESETS
	assert_false(presets.is_empty(), "there are quick grid sizes")
	for value in presets:
		assert_gt(value, 0.0, "a grid size is a size")
		assert_lt(value, MAX_STRUCTURE_HEIGHTS * PLAYER_HEIGHT, "%s is not a grid step" % value)
	assert_true(
		presets.has(_root().grid_snap), "the default grid is one of the buttons you can get back to"
	)


# ===========================================================================
# The generator defaults
# ===========================================================================


## The fields of a schema that are lengths. Angles, counts and enums are not
## lengths and have no scale to be wrong on.
func _length_fields(schema: Array) -> Array:
	var out: Array = []
	for entry in schema:
		var field: Dictionary = entry
		if str(field.get("type", "")) != "float":
			continue
		# "arc_degrees", "start_degrees", "sweep_degrees", "degrees_per_step".
		if str(field["key"]).contains("degrees"):
			continue
		out.append(field)
	return out


func test_every_generator_default_length_is_a_size_in_metres():
	var schemas := _schemas()
	for name in schemas:
		var fields: Array = _length_fields(schemas[name])
		assert_false(fields.is_empty(), "%s has lengths to check" % name)
		for entry in fields:
			var field: Dictionary = entry
			var value := float(field["default"])
			assert_lt(
				value / PLAYER_HEIGHT,
				MAX_STRUCTURE_HEIGHTS,
				(
					"%s '%s' defaults to %s metres, which is not a %s"
					% [name, field["key"], value, name]
				)
			)


func test_a_generator_can_be_asked_for_something_smaller_than_a_person():
	# The ranges were the other half of it: every length started at a minimum of
	# 1.0, so at this scale the thinnest wall the dock could offer was a metre.
	var schemas := _schemas()
	for name in schemas:
		for entry in _length_fields(schemas[name]):
			var field: Dictionary = entry
			if not field.has("min"):
				continue
			assert_lte(
				float(field["min"]),
				0.25,
				"%s '%s' cannot be set to a trim-sized number" % [name, field["key"]]
			)


func test_the_defaults_still_build_what_they_describe():
	# Loosening the ranges and moving the defaults must not walk into a refusal
	# the builders make about the relationships between fields.
	assert_true(HFArchBuilderScript.validate({}).ok, "the default arch builds")
	assert_true(HFDomeBuilderScript.validate({}).ok, "the default dome builds")
	assert_true(HFStairsBuilderScript.validate({}).ok, "the default flight builds")
	assert_true(HFSpiralStairsBuilderScript.validate({}).ok, "the default spiral builds")


func test_generated_stairs_are_not_steeper_than_the_baker_thinks_a_step_is():
	# The auto connector builds steps `bake_connector_stair_height` high and the
	# stairs generator builds them `rise` high. They are the same act, so the
	# drawn one must not be the taller of the two.
	var rise: float = float(HFStairsBuilderScript.default_settings()["rise"])
	var spiral_rise: float = float(HFSpiralStairsBuilderScript.default_settings()["rise"])
	var connector: float = _root().bake_connector_stair_height
	assert_lte(rise, connector, "a drawn step is no taller than a generated one")
	assert_lte(spiral_rise, connector, "and neither is a spiral one")
