extends GutTest

## `func_door` describes itself as "Geometry that moves when opened" and ships
## speed, wait and angle. Nothing read any of them: the bake produced a plain
## MeshInstance3D with no script, so `HFIORuntime` delivered `Open` to the last
## branch of its chain and emitted a signal nobody was connected to (#687).

const HFDoorRuntime = preload("res://addons/hammerforge/hf_door_runtime.gd")


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


func test_open_slides_the_door_along_its_own_angle():
	var door := _door()
	door.apply_entity_data({"angle": 0.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(door.position.x, 0.5, "angle 0 is +X, and it moves its own width")
	assert_almost_eq(door.position.z, 0.0, 0.01, "and nothing sideways")


func test_the_angle_decides_the_direction():
	var door := _door()
	door.apply_entity_data({"angle": 90.0, "speed": 1000.0, "wait": 0.0})
	door.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(door.position.z, 0.1, "angle 90 is +Z")
	assert_almost_eq(door.position.x, 0.0, 0.01)


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
