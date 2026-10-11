extends "res://tests/mcp/mcp_dispatcher_case.gd"

## The bridge's change tools: each is one `MCP: ...` undo step, a refusal
## changes nothing, and what they make survives a save and a reload.

const TOP := 2


func _last_step() -> String:
	return undo.scene_history.get_current_action_name()


# --- hf_transform_brush ----------------------------------------------------


func test_transform_moves_a_brush():
	var level := make_level()
	var id := await place_box([0, 1, 0])
	var r := await call_tool("hf_transform_brush", {"brush_id": id, "position": [4, 1, 2]})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["brush"]["position"], [4.0, 1.0, 2.0])
	assert_eq(brush_node(level, id).global_position, Vector3(4, 1, 2))
	assert_eq(_last_step(), "MCP: transform brush")


func test_transform_turns_a_brush_to_an_angle():
	var level := make_level()
	var id := await place_box([0, 1, 0], [4, 2, 2])
	var r := await call_tool("hf_transform_brush", {"brush_id": id, "rotation_degrees": [0, 90, 0]})
	assert_true(r["ok"], str(r))
	var got: Array = r["result"]["brush"]["rotation_degrees"]
	assert_almost_eq(float(got[1]), 90.0, 0.001)
	assert_almost_eq(brush_node(level, id).global_position.x, 0.0, 0.001, "about its centre")


func test_transform_both_at_once_reads_back_through_get_brushes():
	make_level()
	var id := await place_box([0, 1, 0], [4, 2, 2])
	var params := {
		"brush_id": id, "position": [3, 1, -2], "rotation_degrees": [0, 30, 0], "snap": false
	}
	await call_tool("hf_transform_brush", params)
	var r := await call_tool("hf_get_brushes", {"brush_ids": [id]})
	var brush: Dictionary = r["result"]["brushes"][0]
	assert_eq(brush["position"], [3.0, 1.0, -2.0])
	assert_almost_eq(float(brush["rotation_degrees"][1]), 30.0, 0.001)


func test_transform_needs_something_to_do():
	var level := make_level()
	var id := await place_box()
	var before := snapshot(level)
	assert_refused(await call_tool("hf_transform_brush", {"brush_id": id}), "invalid_argument")
	assert_eq_deep(snapshot(level), before)


func test_transform_a_pending_cut_keeps_it_pending():
	var level := make_level()
	var placed := await call_tool(
		"hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0], "operation": "subtract"}
	)
	var id: String = placed["result"]["brush"]["brush_id"]
	var r := await call_tool("hf_transform_brush", {"brush_id": id, "position": [5, 1, 0]})
	assert_true(r["ok"], str(r))
	assert_true(r["result"]["brush"]["pending"])
	assert_eq(brush_node(level, id).get_parent(), level.pending_node)


func test_an_unknown_brush_is_brush_not_found():
	var level := make_level()
	var before := snapshot(level)
	for method in ["hf_transform_brush", "hf_resize_brush", "hf_delete_brush"]:
		var params := {"brush_id": "nope", "position": [0, 0, 0], "size": [1, 1, 1]}
		assert_refused(await call_tool(method, params), "brush_not_found", method)
	assert_refused(
		await call_tool("hf_delete_brush", {"brush_id": ""}), "invalid_argument", "empty id"
	)
	assert_eq_deep(snapshot(level), before)


# --- hf_resize_brush -------------------------------------------------------


func test_resize_keeps_the_centre_and_snaps():
	var level := make_level()
	var id := await place_box([0, 1, 0], [2, 2, 2])
	var r := await call_tool("hf_resize_brush", {"brush_id": id, "size": [4, 2.2, 6]})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["brush"]["size"], [4.0, 2.0, 6.0])
	assert_eq(brush_node(level, id).global_position, Vector3(0, 1, 0))
	assert_eq(_last_step(), "MCP: resize brush")


func test_resize_refuses_a_custom_brush():
	var level := make_level()
	var info := {
		"shape": LevelRoot.BrushShape.CUSTOM,
		"size": Vector3(2, 2, 2),
		"transform": Transform3D(),
		"brush_id": "custom_1",
	}
	level.create_brush_from_info(info)
	var before := snapshot(level)
	assert_refused(
		await call_tool("hf_resize_brush", {"brush_id": "custom_1", "size": [4, 4, 4]}),
		"unsupported_shape"
	)
	assert_eq_deep(snapshot(level), before)


# --- hf_delete_brush -------------------------------------------------------


func test_delete_then_undo_brings_it_back_with_its_id():
	var level := make_level()
	var id := await place_box()
	var r := await call_tool("hf_delete_brush", {"brush_id": id})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["deleted"], id)
	assert_eq(brushes(level).size(), 0)
	assert_eq(_last_step(), "MCP: delete brush")
	undo.scene_history.undo()
	assert_not_null(brush_node(level, id))


# --- hf_extrude_face -------------------------------------------------------


func test_extrude_by_side_index_and_normal_agree():
	var level := make_level()
	var id := await place_box([0, 1, 0], [4, 2, 4])
	var by_side := await call_tool("hf_extrude_face", {"brush_id": id, "face": "+y", "distance": 3})
	var by_index := await call_tool("hf_extrude_face", {"brush_id": id, "face": TOP, "distance": 3})
	var by_normal := await call_tool(
		"hf_extrude_face", {"brush_id": id, "face": {"normal": [0, 1, 0]}, "distance": 3}
	)
	for r in [by_side, by_index, by_normal]:
		assert_true(r["ok"], str(r))
		assert_eq(r["result"]["brush"]["size"], [4.0, 3.0, 4.0])
		assert_eq(r["result"]["brush"]["position"], [0.0, 3.5, 0.0])
		assert_eq(r["result"]["source_brush_id"], id)
		assert_eq(int(r["result"]["face_index"]), TOP)
	assert_eq(brushes(level).size(), 4, "the source and three new boxes")
	assert_eq(_last_step(), "MCP: extrude face")


func test_extrude_refuses_a_bad_face_or_distance():
	var level := make_level()
	var id := await place_box()
	var before := snapshot(level)
	assert_refused(
		await call_tool("hf_extrude_face", {"brush_id": id, "face": 99, "distance": 1}),
		"face_not_found"
	)
	assert_refused(
		await call_tool("hf_extrude_face", {"brush_id": id, "face": "up", "distance": 1}),
		"invalid_argument"
	)
	assert_refused(
		await call_tool("hf_extrude_face", {"brush_id": id, "face": "+y", "distance": 0}),
		"invalid_argument"
	)
	assert_refused(
		await call_tool("hf_extrude_face", {"brush_id": id, "face": "+y", "distance": 999}),
		"invalid_argument"
	)
	assert_eq_deep(snapshot(level), before)


func test_a_side_two_faces_tie_on_is_ambiguous():
	var level := make_level()
	var id := await place_box([0, 1, 0], [2, 2, 2])
	await call_tool("hf_transform_brush", {"brush_id": id, "rotation_degrees": [0, 45, 0]})
	var before := snapshot(level)
	var r := await call_tool("hf_extrude_face", {"brush_id": id, "face": "+x", "distance": 1})
	assert_refused(r, "ambiguous_face")
	assert_eq((r["error"]["details"]["candidates"] as Array).size(), 2)
	assert_eq_deep(snapshot(level), before)


# --- hf_assign_material ----------------------------------------------------


func test_assign_a_material_to_every_face_by_id():
	var level := make_level_with_palette()
	var id := await place_box()
	var mats: Array = (await call_tool("hf_get_materials"))["result"]["materials"]
	var pick: Dictionary = mats[3]
	var r := await call_tool("hf_assign_material", {"brush_id": id, "material": pick["id"]})
	assert_true(r["ok"], str(r))
	for face in r["result"]["brush"]["faces"]:
		assert_eq(face["material_id"], pick["id"])
	for face in brush_node(level, id).faces:
		assert_eq(int(face.material_idx), 3)
	assert_eq(_last_step(), "MCP: assign material")


func test_assign_a_material_to_one_side_by_name():
	var level := make_level_with_palette()
	var id := await place_box()
	var mats: Array = (await call_tool("hf_get_materials"))["result"]["materials"]
	var pick: Dictionary = mats[5]
	var r := await call_tool(
		"hf_assign_material",
		{"brush_id": id, "material": str(pick["name"]).to_upper(), "faces": ["+y"]}
	)
	assert_true(r["ok"], str(r))
	var faces: Array = brush_node(level, id).faces
	assert_eq(int(faces[TOP].material_idx), 5)
	assert_ne(int(faces[0].material_idx), 5, "the other faces are left alone")


func test_material_lookups_that_fail():
	var level := make_level_with_palette()
	var id := await place_box()
	var twin: Material = level.get_materials()[1].duplicate()
	twin.resource_name = str(level.get_material_names()[0])
	level.add_material_to_palette(twin)
	var before := snapshot(level)
	assert_refused(
		await call_tool("hf_assign_material", {"brush_id": id, "material": "no such thing"}),
		"unknown_material"
	)
	var r := await call_tool(
		"hf_assign_material", {"brush_id": id, "material": level.get_material_names()[0]}
	)
	assert_refused(r, "ambiguous_material")
	assert_eq((r["error"]["details"]["ids"] as Array).size(), 2)
	assert_eq_deep(snapshot(level), before)


# --- hf_set_spawn ----------------------------------------------------------


func test_set_spawn_makes_one_when_there_is_none():
	var level := make_level()
	var r := await call_tool("hf_set_spawn", {"position": [3, 0, -2], "yaw_degrees": 90})
	assert_true(r["ok"], str(r))
	assert_true(r["result"]["spawn"]["created"])
	var spawn: Node3D = level.spawn_system.get_active_spawn()
	assert_not_null(spawn)
	assert_almost_eq(spawn.global_position.x, 3.0, 0.001)
	assert_gt(spawn.global_position.y, 0.0, "stands above the floor point")
	assert_almost_eq(float(spawn.entity_data.get("angle", 0.0)), 90.0, 0.001)
	assert_eq(_last_step(), "MCP: set spawn")


func test_set_spawn_moves_the_one_there_is():
	var level := make_level()
	await call_tool("hf_set_spawn", {"position": [0, 0, 0]})
	var r := await call_tool("hf_set_spawn", {"position": [8, 0, 8]})
	assert_false(r["result"]["spawn"]["created"])
	assert_eq(level.spawn_system.get_all_spawns().size(), 1)


func test_a_spawn_inside_a_brush_is_reported():
	make_level()
	await place_box([0, 2, 0], [4, 4, 4])
	var r := await call_tool("hf_set_spawn", {"position": [0, 0, 0]})
	assert_true(r["ok"], str(r))
	assert_true(r["result"]["inside_brush"], str(r["result"]))


## A floor with collision whose top is at `top`, the way a baked level has one.
func _collision_floor(level: LevelRoot, top: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 2, 40)
	shape.shape = box
	body.add_child(shape)
	level.get_parent().add_child(body)
	body.global_position = Vector3(0, top - 1.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_set_spawn_suggests_feet_that_go_straight_back_in():
	# The answer gave its suggestions as the spawn node's position, 1.1 m over the
	# feet the tool takes, so passing one back lifted the spawn (#1034).
	var level := make_level()
	await _collision_floor(level, 1.0)
	var r := await call_tool("hf_set_spawn", {"position": [0, 3, 0]})
	assert_true(r["ok"], str(r))
	var suggested: Array = r["result"]["validation"]["suggested_position"]
	assert_almost_eq(float(suggested[1]), 1.0, 0.01, "the floor's top, where feet go")
	var again := await call_tool("hf_set_spawn", {"position": suggested})
	assert_eq(again["result"]["validation"]["issues"], [], str(again["result"]))
	assert_almost_eq(float(again["result"]["spawn"]["feet"][1]), 1.0, 0.01)


func test_set_spawn_gives_the_clear_place_as_feet():
	var level := make_level()
	await _collision_floor(level, 1.0)
	var r := await call_tool("hf_set_spawn", {"position": [0, 1, 0]})
	assert_eq(r["result"]["clear_place"], r["result"]["spawn"]["feet"], "already clear: here")


func test_set_spawn_on_a_brush_floor_is_fine_before_the_first_bake():
	# Brushes have no collision until a bake, so the floor was the ground under
	# the plinth, and following the suggestion put the feet inside it (#1059).
	make_level()
	await place_box([0, 0.5, 0], [10, 1, 10])
	var r := await call_tool("hf_set_spawn", {"position": [0, 1, 0]})
	assert_true(r["ok"], str(r))
	assert_eq(r["result"]["validation"]["issues"], [], str(r["result"]))
	assert_false(r["result"]["inside_brush"])


func test_set_spawn_over_a_brush_floor_suggests_its_top():
	make_level()
	await place_box([0, 0.5, 0], [10, 1, 10])
	var r := await call_tool("hf_set_spawn", {"position": [0, 4, 0]})
	var suggested: Array = r["result"]["validation"]["suggested_position"]
	assert_almost_eq(float(suggested[1]), 1.0, 0.01, "the plinth's top, not the ground")


# --- Save and reload -------------------------------------------------------


func test_changes_survive_a_save_and_a_reload():
	var level := make_level_with_palette()
	var id := await place_box([0, 1, 0], [4, 2, 2])
	await call_tool(
		"hf_transform_brush",
		{"brush_id": id, "position": [2, 1, 0], "rotation_degrees": [0, 90, 0]}
	)
	await call_tool("hf_resize_brush", {"brush_id": id, "size": [6, 2, 2]})
	var mats: Array = (await call_tool("hf_get_materials"))["result"]["materials"]
	await call_tool(
		"hf_assign_material", {"brush_id": id, "material": mats[2]["id"], "faces": ["+y"]}
	)
	var made := await call_tool("hf_extrude_face", {"brush_id": id, "face": "+y", "distance": 2})
	var extruded: String = made["result"]["brush"]["brush_id"]
	var gone := await place_box([20, 1, 0])
	await call_tool("hf_delete_brush", {"brush_id": gone})
	var listed: Array = (await call_tool("hf_get_brushes"))["result"]["brushes"]

	var path := "user://mcp_save_reload_test.hflevel"
	assert_eq(level.save_hflevel(path, true), OK)
	await _drain_save(level)
	var fresh := LevelRoot.new()
	make_scene(fresh)
	assert_true(fresh.load_hflevel(path))
	var reread: Array = (await call_tool("hf_get_brushes"))["result"]["brushes"]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_eq(reread.size(), listed.size())
	var by_id := {}
	for brush in reread:
		by_id[brush["brush_id"]] = brush
	assert_false(by_id.has(gone), "the deleted brush stays deleted")
	assert_true(by_id.has(extruded), "the extruded brush came back")
	for before in listed:
		var after: Dictionary = by_id.get(before["brush_id"], {})
		assert_eq(after.get("position"), before["position"], "position of %s" % before["brush_id"])
		assert_eq(after.get("size"), before["size"], "size of %s" % before["brush_id"])
		assert_eq(after.get("rotation_degrees"), before["rotation_degrees"])
		var faces_before: Array = before["faces"]
		var faces_after: Array = after.get("faces", [])
		for i in faces_before.size():
			assert_eq(faces_after[i]["material_id"], faces_before[i]["material_id"])


## The save runs on a write thread. Wait for it, the way the file system's own
## tests do.
func _drain_save(level: LevelRoot) -> void:
	var files = level.file_system
	for i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


# --- What an answer says about snapping (#1038) ---------------------------


func test_snapped_is_false_when_snapping_moved_nothing():
	make_level()
	var r := await call_tool("hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]})
	assert_false(r["result"]["snapped"], "on the grid already: nothing moved")
	assert_false(r["result"].has("requested"))


func test_snapped_says_what_was_asked_when_it_moved_a_brush():
	# A 1.5 m sphere centred on a pillar came back a quarter metre off it, and the
	# answer said snapped: true, as it did for every change with snap on.
	make_level()
	var r := await call_tool(
		"hf_place_brush", {"shape": "sphere", "size": [1.5, 1.5, 1.5], "position": [12, 4.75, 10]}
	)
	assert_true(r["result"]["snapped"], "the centre moved")
	assert_eq(r["result"]["requested"]["position"], [12.0, 4.75, 10.0])
	assert_eq(r["result"]["requested"]["size"], [1.5, 1.5, 1.5])
	assert_ne(r["result"]["brush"]["position"], [12.0, 4.75, 10.0], "applied beside it")


# --- hf_place_brush takes material, rotation and sides (#1039) -------------


func test_place_takes_a_name_and_undo_and_redo_keep_it():
	# Every brush was Box_12 or Wedge_3, so a person reading what an agent built
	# could not tell the gate from the parapet (#1086).
	var level := make_level()
	var r := await call_tool(
		"hf_place_brush", {"size": [4, 4, 1], "position": [0, 2, 0], "name": "Gate"}
	)
	assert_true(r["ok"], str(r))
	var gate_id: String = r["result"]["brush"]["brush_id"]
	assert_eq(r["result"]["brush"]["name"], "Gate")
	assert_eq(str(brush_node(level, gate_id).name), "Gate")
	var again := await call_tool(
		"hf_place_brush", {"size": [4, 4, 1], "position": [8, 2, 0], "name": "Gate"}
	)
	var second: String = again["result"]["brush"]["name"]
	assert_ne(second, "Gate", "a sibling's name is numbered on")
	assert_true(second.begins_with("Gate"), second)
	await call_tool("hf_undo")
	await call_tool("hf_undo")
	await call_tool("hf_redo")
	assert_eq(str(brush_node(level, gate_id).name), "Gate", "redo keeps it")
	assert_refused(
		await call_tool("hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0], "name": "  "}),
		"invalid_argument",
		"a blank name"
	)


func test_place_takes_a_material_in_the_same_step():
	var level := make_level_with_palette()
	var name := str(level.get_material_names()[1])
	var before: int = undo.scene_history.get_history_count()
	var r := await call_tool(
		"hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0], "material": name}
	)
	assert_true(r["ok"], str(r))
	assert_eq(undo.scene_history.get_history_count(), before + 1, "one step")
	var brush := brush_node(level, r["result"]["brush"]["brush_id"])
	for face in brush.faces:
		assert_eq(face.material_idx, 1, "every face")


func test_place_refuses_a_material_it_does_not_know():
	var level := make_level_with_palette()
	var before := snapshot(level)
	var r := await call_tool(
		"hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0], "material": "no such"}
	)
	assert_refused(r, "unknown_material")
	assert_eq_deep(snapshot(level), before)


func test_place_takes_a_rotation():
	var level := make_level()
	var r := await call_tool(
		"hf_place_brush",
		{
			"shape": "wedge",
			"size": [6, 1, 4],
			"position": [0, 0.5, 0],
			"rotation_degrees": [0, 90, 0]
		}
	)
	assert_true(r["ok"], str(r))
	var brush := brush_node(level, r["result"]["brush"]["brush_id"])
	assert_almost_eq(brush.global_rotation_degrees.y, 90.0, 0.01)
	var bounds: Dictionary = r["result"]["brush"]["bounds"]
	assert_almost_eq(float(bounds["max"][2]) - float(bounds["min"][2]), 6.0, 0.01, "6 along z")


func test_place_takes_sides_for_a_round_shape():
	var level := make_level()
	var r := await call_tool(
		"hf_place_brush",
		{"shape": "cylinder", "size": [2, 4, 2], "position": [0, 2, 0], "sides": 8}
	)
	assert_true(r["ok"], str(r))
	var brush := brush_node(level, r["result"]["brush"]["brush_id"])
	assert_eq(brush.sides, 8)
	assert_eq(brush.faces.size(), 10, "an octagonal pillar: eight sides and two caps")


func test_place_refuses_sides_on_a_shape_without_them():
	make_level()
	var r := await call_tool(
		"hf_place_brush", {"shape": "box", "size": [2, 2, 2], "position": [0, 1, 0], "sides": 8}
	)
	assert_refused(r, "invalid_argument")


# --- What the agent is building for (#1045, #1041) -------------------------


func test_status_says_what_the_playtest_player_can_do():
	make_level()
	var player: Dictionary = (await call_tool("hf_get_status"))["result"]["player"]
	assert_almost_eq(float(player["height"]), 1.6, 0.001)
	assert_almost_eq(float(player["radius"]), 0.35, 0.001)
	assert_almost_eq(float(player["eye_height"]), 1.8, 0.001, "above the feet")
	assert_almost_eq(float(player["step_height"]), 0.4, 0.001)
	assert_gt(float(player["jump_height"]), 1.0)
	assert_almost_eq(float(player["max_slope_degrees"]), 45.0, 0.01)


func test_set_spawn_says_which_way_it_faces():
	make_level()
	var r := await call_tool("hf_set_spawn", {"position": [0, 0, 0], "yaw_degrees": 90})
	var facing: Array = r["result"]["spawn"]["facing"]
	assert_almost_eq(float(facing[0]), -1.0, 0.001, "a positive yaw turns from -z toward -x")
	assert_almost_eq(float(facing[2]), 0.0, 0.001)
