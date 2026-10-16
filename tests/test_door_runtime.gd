extends GutTest

## `func_door` describes itself as "Geometry that moves when opened" and ships
## speed, wait and angle. Nothing read any of them: the bake produced a plain
## MeshInstance3D with no script, so `HFIORuntime` delivered `Open` to the last
## branch of its chain and emitted a signal nobody was connected to (#687).

const HFDoorRuntime = preload("res://addons/hammerforge/hf_door_runtime.gd")
const MapIOScript = preload("res://addons/hammerforge/map_io.gd")


func _door(at: Vector3 = Vector3.ZERO, size: Vector3 = Vector3(1, 2, 0.2)) -> Node3D:
	var holder := Node3D.new()
	holder.set_script(HFDoorRuntime)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	holder.add_child(mesh)
	add_child_autoqfree(holder)
	holder.position = at
	return holder


func after_each() -> void:
	get_tree().paused = false


func test_open_slides_the_door_along_its_own_angle():
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(door.position.x, 0.5, "angle 0 is +X, and it moves its own width")
	assert_almost_eq(door.position.z, 0.0, 0.01, "and nothing sideways")


func test_the_angle_decides_the_direction():
	# The Quake family's way round: 90 is north, which a `.map` import brings in
	# as -Z. It was +Z, so a door crossing a `.map` opened backwards (#1210).
	var door := _door(Vector3.ZERO, Vector3(0.2, 2, 1))
	door.apply_entity_data({"angle": 90.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.z, -1.0, 0.01, "angle 90 is -Z, by its own width")
	assert_almost_eq(door.position.x, 0.0, 0.01)
	var south := _door(Vector3(5, 0, 0), Vector3(0.2, 2, 1))
	south.apply_entity_data({"angle": 270.0, "speed": 1000.0, "wait": 0.0})
	south.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(south.position.z, 1.0, 0.01, "and 270 is +Z")


func test_an_angle_means_what_it_means_in_a_map_file():
	# A `.map` is Z-up with angle 0 along +X and 90 along +Y, and the import turns
	# its axes with `from_map_axes()` and keeps the key as written. So the door
	# has to open along the file's bearing brought in the same way.
	for degrees in [0.0, 30.0, 90.0, 135.0, 180.0, 270.0, 315.0]:
		var radians := deg_to_rad(degrees)
		var in_file := Vector3(cos(radians), sin(radians), 0.0)
		var expected: Vector3 = MapIOScript.from_map_axes(in_file)
		var got: Vector3 = HFDoorRuntime.travel_direction(degrees)
		assert_true(
			got.is_equal_approx(expected), "angle %s: %s, not %s" % [degrees, expected, got]
		)


func test_angle_minus_one_lifts_the_door_by_its_height():
	# The Quake family's up, how a portcullis is made. It slid the door sideways
	# out of its wall, as a bearing one degree off +X (#1210).
	var door := _door(Vector3.ZERO, Vector3(1, 2, 0.2))
	door.apply_entity_data({"angle": -1.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.y, 2.0, 0.01, "up by its height")
	assert_almost_eq(door.position.x, 0.0, 0.01, "and nothing sideways")
	assert_almost_eq(door.position.z, 0.0, 0.01)


func test_angle_minus_two_lowers_the_door_by_its_height():
	var door := _door(Vector3.ZERO, Vector3(1, 2, 0.2))
	door.apply_entity_data({"angle": -2.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.y, -2.0, 0.01, "down by its height")
	assert_almost_eq(door.position.x, 0.0, 0.01)


func test_a_turned_leaf_travels_its_own_width_not_its_box():
	# A 1.6 m leaf turned 30 degrees, sliding along its own width. Its bounds
	# squared to the holder made that 1.77 m, past the pocket it slides into.
	var door := _door(Vector3.ZERO, Vector3(0.2, 2.2, 1.6))
	(door.get_child(0) as Node3D).rotation_degrees.y = 30.0
	door.apply_entity_data({"angle": 120.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.length(), 1.6, 0.01, "its own width")
	var own_width := Basis(Vector3.UP, deg_to_rad(30.0)) * Vector3(0, 0, 1)
	assert_almost_eq(absf(door.position.normalized().dot(own_width)), 1.0, 0.001, "along it")


func test_close_puts_it_back_where_it_started():
	var door := _door(Vector3(3, 0, 0))
	door.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	door.close()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.x, 3.0, 0.05, "back to where it was shut")


func test_opening_twice_does_not_walk_the_door_down_the_corridor():
	# The closed position is recorded once, before it has moved.
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var first := door.position
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.x, first.x, 0.01, "already open is already open")


func test_a_locked_door_does_not_open():
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 1000.0, "locked": true})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.x, 0.0, 0.01, "locked is locked")
	door.unlock()
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(door.position.x, 0.5, "and Unlock lets it through")


func test_toggle_goes_both_ways():
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	door.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(door.position.x, 0.5, "shut, so Toggle opens it")
	door.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(door.position.x, 0.0, 0.05, "open, so Toggle shuts it")


func test_it_travels_its_own_width_rather_than_a_fixed_distance():
	var narrow := _door(Vector3.ZERO, Vector3(1, 2, 0.2))
	narrow.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	var wide := _door(Vector3(0, 0, 10), Vector3(4, 2, 0.2))
	wide.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	narrow.open()
	wide.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(wide.position.x, narrow.position.x + 1.0, "a wider door slides further")


func test_it_slides_rather_than_teleporting():
	# A door that arrives in one frame is not what a property called speed is for,
	# and a door that shuts in one frame can leave a body inside it.
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 0.5, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	assert_lt(door.position.x, 0.5, "one frame is not the whole journey at 0.5 m/s")


func test_the_class_defaults_stand_when_nothing_was_authored():
	var door := _door()
	assert_almost_eq(door.speed, 2.0, 0.001)
	assert_almost_eq(door.wait, 3.0, 0.001)
	assert_almost_eq(door.angle, 90.0, 0.001)
	assert_false(door.locked)


# ===========================================================================
# What the mapper authored reaches the door (#728)
# ===========================================================================

const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const HFLevelFactory = preload("res://addons/hammerforge/hf_level_factory.gd")


func _level() -> LevelRoot:
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	return HFLevelFactory.create_level_root(parent, parent, {"hflevel_autosave_enabled": false})


func _bake_door_from(level: LevelRoot, brush_id: String, door_name: String) -> Node:
	var container := Node3D.new()
	level.add_child(container)
	level.bake_system._append_nonstructural_brushes(container)
	return container.get_node_or_null("Nonstructural").get_node_or_null(door_name)


func test_an_authored_speed_reaches_the_baked_door():
	var level := _level()
	var brush = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 2, 0.2), "center": Vector3.ZERO, "brush_id": "d1"}
	)
	level.tie_brushes_to_entity(["d1"], "func_door", "gate")
	HFEntityPropUtils.set_entity_property(brush, "speed", 7.0)
	HFEntityPropUtils.set_entity_property(brush, "angle", 0.0)
	var mover: Node = _bake_door_from(level, "d1", "gate")
	assert_not_null(mover, "the door bakes under its own name")
	assert_almost_eq(mover.speed, 7.0, 0.001, "the authored speed, not the class default")
	assert_almost_eq(mover.angle, 0.0, 0.001, "and the authored angle")


func test_a_door_with_nothing_authored_uses_the_class_defaults():
	var level := _level()
	level.create_brush_from_info(
		{"shape": 0, "size": Vector3(1, 2, 0.2), "center": Vector3.ZERO, "brush_id": "d2"}
	)
	level.tie_brushes_to_entity(["d2"], "func_door", "gate2")
	var mover: Node = _bake_door_from(level, "d2", "gate2")
	assert_not_null(mover)
	assert_almost_eq(mover.speed, 2.0, 0.001, "entities.json says 2.0")
	assert_almost_eq(mover.wait, 3.0, 0.001, "and 3.0")


# -- Wait counts from when it is open (#910) ------------------------------------


## A 4 m door at 10 m/s takes 0.4 s to open. With a wait of 0.2 s the old timer
## fired half way and sent it back before it was ever open.
func test_a_door_slower_than_its_wait_opens_all_the_way_first():
	var door := _door(Vector3.ZERO, Vector3(4, 2, 0.2))
	door.apply_entity_data({"angle": 0.0, "speed": 10.0, "wait": 0.2})
	door.open()
	await get_tree().create_timer(0.3).timeout
	assert_true(door._is_open, "still opening at 0.3 s")
	await get_tree().create_timer(0.15).timeout
	assert_almost_eq(door.position.x, 4.0, 0.05, "and open all the way at 0.45 s")
	assert_true(door._is_open, "where it waits")
	await get_tree().create_timer(0.4).timeout
	assert_false(door._is_open, "until it closes itself, its wait after it got there")


func test_a_door_closed_on_the_way_does_not_close_itself_later():
	var door := _door(Vector3.ZERO, Vector3(4, 2, 0.2))
	door.apply_entity_data({"angle": 0.0, "speed": 10.0, "wait": 0.2})
	door.open()
	await get_tree().create_timer(0.1).timeout
	door.close()
	var closes := [0]
	door.closed.connect(func() -> void: closes[0] += 1)
	await get_tree().create_timer(0.8).timeout
	assert_eq(closes[0], 0, "no timer was left to close it again")
	assert_almost_eq(door.position.x, 0.0, 0.05, "and it is back where it was shut")


func test_a_door_reads_locked_as_a_map_import_wrote_it():
	# A `.map` import stores every value as the text it read, and `bool()` takes
	# no String, so the bake stopped on a script error and the door stayed
	# unlocked (#1127).
	for value in ["true", "1", "yes", "on", 1, true]:
		var door := _door()
		door.apply_entity_data({"locked": value})
		assert_true(door.locked, "%s is locked" % [value])
	for value in ["false", "0", "", 0, false]:
		var door := _door()
		door.apply_entity_data({"locked": value})
		assert_false(door.locked, "%s is not" % [value])


func test_a_pause_holds_a_door_open():
	# Its wait was a `SceneTreeTimer` that runs through a pause, so a door ran out
	# its wait behind a pause menu and shut as play resumed (#1140).
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 100.0, "wait": 0.2})
	door.open()
	await get_tree().create_timer(0.1).timeout
	get_tree().paused = true
	await get_tree().create_timer(0.4, true).timeout
	var open_while_paused: bool = door._is_open
	get_tree().paused = false
	assert_true(open_while_paused, "its wait does not run out while paused")
	await get_tree().create_timer(0.4).timeout
	assert_false(door._is_open, "and does once play resumes")


func _two_brush_entity(level: LevelRoot, entity_class: String, entity_name: String) -> Array:
	var ids: Array = []
	var brushes: Array = []
	for i in 2:
		var brush_id := "%s_%d" % [entity_class, i]
		brushes.append(
			level.create_brush_from_info(
				{
					"shape": 0,
					"size": Vector3(1, 2, 0.2),
					"center": Vector3(i, 1, 0),
					"brush_id": brush_id
				}
			)
		)
		ids.append(brush_id)
	level.tie_brushes_to_entity(ids, entity_class, entity_name)
	return brushes


func _baked_pieces(level: LevelRoot) -> Array:
	var container := Node3D.new()
	level.add_child(container)
	level.bake_system._append_nonstructural_brushes(container)
	return container.get_node("Nonstructural").get_children()


func test_both_leaves_of_a_named_door_bake_under_readable_names():
	# Both holders were called `gate`, so Godot named the second `@Node3D@20` and
	# that is what the game scene showed (#1169). It takes its brush's node name,
	# which it answers to already, rather than `gate2`, which another door might
	# be called.
	var level := _level()
	var leaves := _two_brush_entity(level, "func_door", "gate")
	var names: Array = _baked_pieces(level).map(func(n): return str(n.name))
	names.sort()
	var expected: Array = ["gate", str(leaves[1].name)]
	expected.sort()
	assert_eq(names, expected)


func test_every_piece_of_a_named_brush_entity_bakes_under_a_readable_name():
	var level := _level()
	_two_brush_entity(level, "func_wall", "wall")
	_two_brush_entity(level, "trigger_multiple", "zone")
	_two_brush_entity(level, "func_button", "btn")
	var pieces := _baked_pieces(level)
	assert_gt(pieces.size(), 6)
	for piece in pieces:
		assert_false(str(piece.name).begins_with("@"), "%s is readable" % piece.name)
	var answering: Dictionary = {}
	for piece in pieces:
		var entity_name := str(piece.get_meta("entity_name", ""))
		answering[entity_name] = int(answering.get(entity_name, 0)) + 1
	assert_eq(answering.get("wall", 0), 4, "two meshes and two bodies answer to the wall")
	assert_eq(answering.get("zone", 0), 2, "and two volumes to the trigger")


# -- A door of several leaves, and a turned door (#1217, #1210) ----------------


## Leaves 0.2 thick, 2 high and 1.6 wide, side by side along Z from `from_z`, all
## tied under `entity_name`.
func _leaves_across(level: LevelRoot, entity_name: String, from_z: float, count: int) -> Array:
	var ids: Array = []
	for i in count:
		var brush_id := "%s_leaf_%d" % [entity_name, i]
		level.create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(0.2, 2, 1.6),
				"center": Vector3(0, 1, from_z + 0.8 + 1.6 * i),
				"brush_id": brush_id
			}
		)
		ids.append(brush_id)
	level.tie_brushes_to_entity(ids, "func_door", entity_name)
	for brush_id in ids:
		var brush: Node3D = level.find_brush_by_id(brush_id)
		HFEntityPropUtils.set_entity_property(brush, "speed", 1000.0)
		HFEntityPropUtils.set_entity_property(brush, "wait", 0.0)
	return ids


func _open_every_door(level: LevelRoot) -> Dictionary:
	var moved: Dictionary = {}
	var origins: Dictionary = {}
	var doors: Array = _baked_pieces(level).filter(func(n): return n.has_method("open"))
	for door in doors:
		origins[door] = door.position
	for door in doors:
		door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	for door in doors:
		moved[str(door.name)] = door.position - origins[door]
	return moved


func test_two_leaves_of_one_door_clear_the_doorway():
	# Each leaf slid its own 1.6 m the same way, so the first ended where the
	# second had been and half the 3.2 m doorway stayed shut. A Quake-family door
	# of several brushes is one mover and travels the whole door (#1217).
	var level := _level()
	_leaves_across(level, "pair", -1.6, 2)
	var moved: Dictionary = await _open_every_door(level)
	assert_eq(moved.size(), 2, "two leaves")
	for leaf in moved:
		assert_true(
			(moved[leaf] as Vector3).is_equal_approx(Vector3(0, 0, -3.2)),
			"%s travels the whole door: %s" % [leaf, moved[leaf]]
		)


func test_two_doors_side_by_side_each_travel_their_own_width():
	# Two names are two doors, which is how a pair that parts in the middle is
	# built, and neither reaches across to measure the other.
	var level := _level()
	_leaves_across(level, "left", -1.6, 1)
	_leaves_across(level, "right", 0.0, 1)
	var moved: Dictionary = await _open_every_door(level)
	assert_eq(moved.size(), 2)
	for leaf in moved:
		assert_true(
			(moved[leaf] as Vector3).is_equal_approx(Vector3(0, 0, -1.6)),
			"%s travels its own width: %s" % [leaf, moved[leaf]]
		)


func test_a_door_turned_with_its_wall_slides_along_it():
	# Turning the brushes turns the angle, as turning a point entity does. Left
	# behind, a door turned 90 degrees slid out of its wall by its thickness
	# and the doorway stayed shut (#1210).
	for yaw in [90.0, 30.0]:
		var level := _level()
		var ids := _leaves_across(level, "gate", -0.8, 1)
		level.rotate_managed_nodes(ids, [], 1, yaw, Vector3(0, 1, 0))
		var moved: Dictionary = await _open_every_door(level)
		var travel: Vector3 = moved.values()[0]
		var own_width := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 1)
		assert_almost_eq(travel.length(), 1.6, 0.01, "turned %s: its own width" % yaw)
		assert_almost_eq(
			absf(travel.normalized().dot(own_width)), 1.0, 0.001, "turned %s: along it" % yaw
		)
