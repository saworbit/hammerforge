extends "res://tests/mcp/mcp_dispatcher_case.gd"

## What the phase 2 review found: the spawn's own height, snapping by the size a
## shape really has, committed cuts left alone, palette slots by number, and an
## undo chain that ends when the editor moves to another level.


func test_set_spawn_stands_the_spawn_at_its_own_height():
	var level := make_level()
	var r := await call_tool("hf_set_spawn", {"position": [3, 2, -1]})
	var spawn: Node3D = level.spawn_system.get_active_spawn()
	assert_almost_eq(spawn.global_position.y, 2.0 + 0.1 + 1.0, 0.0001, "feet + 0.1 + 1.0")
	assert_eq(r["result"]["spawn"]["feet"], [3.0, 2.0, -1.0])
	spawn.entity_data["height_offset"] = 0.5
	await call_tool("hf_set_spawn", {"position": [3, 2, -1]})
	assert_almost_eq(spawn.global_position.y, 2.0 + 0.1 + 0.5, 0.0001, "its own 0.5")
	var feet: Vector3 = level.spawn_system._floor_of(spawn)
	assert_true(feet.is_equal_approx(Vector3(3, 2, -1)), "validation sees those feet: %s" % feet)


func test_snapping_uses_the_size_a_shape_really_has():
	make_level()
	# A cylinder is as deep as it is wide: [2, 3, 1] is really [2, 3, 2]. Its faces
	# have to land on grid lines at that size, not at the one asked for.
	var r := await call_tool(
		"hf_place_brush", {"shape": "cylinder", "size": [2, 3, 1], "position": [0, 1.5, 0.2]}
	)
	assert_true(r["ok"], str(r))
	var brush: Dictionary = r["result"]["brush"]
	assert_eq(brush["size"], [2.0, 3.0, 2.0])
	var low: Array = brush["bounds"]["min"]
	assert_almost_eq(
		float(low[2]), roundf(float(low[2])), 0.0001, "the near face is on a grid line"
	)


func test_a_committed_cut_is_left_alone():
	var level := make_level()
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(2, 2, 2),
		"transform": Transform3D(),
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
		"committed": true,
		"brush_id": "cut_1",
	}
	var made = level.create_brush_from_info(info)
	assert_eq(made.get_parent(), level.committed_node, "the setup made a committed cut")
	var before := snapshot(level)
	var r := await call_tool("hf_transform_brush", {"brush_id": "cut_1", "position": [5, 0, 0]})
	assert_refused(r, "brush_not_found")
	assert_true(r["error"]["details"]["committed"])
	assert_string_contains(r["error"]["message"], "committed cut")
	assert_eq_deep(snapshot(level), before)


func test_a_palette_slot_by_number_works_for_any_material():
	var level := make_level_with_palette()
	var id := await place_box()
	var r := await call_tool("hf_assign_material", {"brush_id": id, "material": "palette:4"})
	assert_true(r["ok"], str(r))
	assert_eq(int(brush_node(level, id).faces[0].material_idx), 4)
	assert_refused(
		await call_tool("hf_assign_material", {"brush_id": id, "material": "palette:9999"}),
		"unknown_material"
	)


func test_a_scene_change_ends_the_agent_undo_chain():
	make_level()
	await place_box()
	make_scene(LevelRoot.new())
	await call_tool("hf_get_status")
	var r := await call_tool("hf_undo")
	assert_refused(r, "undo_conflict")
	assert_null(r["error"]["details"]["last_agent_revision"])


func test_a_rotation_of_a_full_turn_snaps_like_a_square_brush():
	var level := make_level()
	var id := await place_box([0, 1, 0], [3, 2, 2])
	await call_tool(
		"hf_transform_brush",
		{"brush_id": id, "position": [0.2, 1, 0], "rotation_degrees": [0, 360, 0]}
	)
	var bounds: AABB = level.brush_system.world_bounds_of(brush_node(level, id))
	assert_almost_eq(
		bounds.position.x, roundf(bounds.position.x), 0.001, "the corner, not the centre"
	)


func test_create_starter_says_where_the_spawn_feet_are():
	make_scene()
	var r := await call_tool("hf_create_starter")
	assert_true(r["ok"], str(r))
	var feet: Array = r["result"]["spawn_feet"]
	assert_almost_eq(float(feet[1]), float(r["result"]["floor_top"]), 0.001, "on the floor")
