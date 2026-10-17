extends "res://tests/mcp/mcp_dispatcher_case.gd"

## place_prefab through hf_run_command, and the library hf_list_commands lists
## for it (#1301). The library is a scratch folder under `user://`, never the
## project's `res://prefabs`.

const HFPrefab = preload("res://addons/hammerforge/hf_prefab.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")

const LIBRARY := "user://hf_test_mcp_prefab_library"


func before_each() -> void:
	super.before_each()
	_clear_library()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LIBRARY))
	dispatcher.commands.prefab_dir = LIBRARY


func after_each() -> void:
	super.after_each()
	_clear_library()


func _clear_library() -> void:
	if not DirAccess.dir_exists_absolute(LIBRARY):
		return
	for file_name in DirAccess.get_files_at(LIBRARY):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LIBRARY.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIBRARY))


## A prefab saved into the library, built in a level of its own: a 4 m box and a
## 2 m box side by side, the big one a door named door_a when `door` is set, a
## lamp when `lamp` is, the big one painted with a material the placing level
## lacks when `painted` is, and a second variant "small" of the small box alone
## when `variants` is.
func save_prefab(prefab_name: String, options := {}) -> void:
	var shop := LevelRoot.new()
	shop.auto_spawn_player = false
	shop.hflevel_autosave_enabled = false
	add_child_autoqfree(shop)
	var big = shop.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3(10, 2, 0), "brush_id": "big"}
	)
	var small = shop.create_brush_from_info(
		{"size": Vector3(2, 2, 2), "center": Vector3(14, 1, 0), "brush_id": "small"}
	)
	var brushes := [big, small]
	if options.get("one_brush", false):
		brushes = [small]
	if options.get("door", false):
		shop.tie_brushes_to_entity(["big"], "func_door", "door_a")
	if options.get("painted", false):
		var paint := StandardMaterial3D.new()
		paint.resource_name = "prefab_paint"
		shop.add_material_to_palette(paint)
		shop.assign_material_to_faces_by_id("big", [0], shop.get_materials().size() - 1)
	var entities: Array = []
	if options.get("lamp", false):
		var lamp = DraftEntityScript.new()
		lamp.name = "lamp"
		lamp.entity_type = "light_point"
		lamp.entity_class = "light_point"
		shop.add_entity(lamp)
		lamp.global_position = Vector3(12, 5, 0)
		entities.append(lamp)
	var prefab = HFPrefab.capture_from_selection(
		shop.brush_system, shop.entity_system, brushes, entities
	)
	prefab.prefab_name = prefab_name
	if options.get("variants", false):
		var base: Dictionary = prefab.get_variant_data("base").duplicate(true)
		prefab.set_variant_data("small", [base["brush_infos"].back()], [])
	assert_eq(prefab.save_to_file(LIBRARY.path_join(prefab_name + ".hfprefab")), OK)


func place(args: Dictionary, brush_ids = null) -> Dictionary:
	var params := {"command": "place_prefab", "params": args}
	if brush_ids != null:
		params["brush_ids"] = brush_ids
	return await call_tool("hf_run_command", params)


func top_step() -> String:
	return undo.scene_history.get_current_action_name()


## Where a copy's pieces centre, measured the way the prefab format measures it.
func centre_of(level: LevelRoot, brush_ids: Array) -> Vector3:
	var nodes: Array = []
	for brush_id in brush_ids:
		nodes.append(brush_node(level, str(brush_id)))
	return HFPrefab.compute_selection_centroid(nodes, [])


func made_ids(response: Dictionary) -> Array:
	var out: Array = []
	for brush in response["result"]["made"]:
		out.append(brush["brush_id"])
	return out


func assert_checked_refusal(response: Dictionary, code: String, before: Dictionary, note: String):
	assert_refused(response, code, note)
	if response.get("ok", true):
		return
	assert_false(response["error"]["details"].has("rolled_back"), "%s: refused in the check" % note)
	assert_eq(snapshot(host.level_root_in(host.scene)), before, "%s: nothing changed" % note)


# ===========================================================================
# Placing
# ===========================================================================


func test_a_prefab_is_placed_as_one_step_and_recorded_as_a_copy():
	var level := make_level()
	save_prefab("crate")
	var r := await place({"prefab": "crate", "position": [30, 0, 5]})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: place prefab")
	var ids := made_ids(r)
	assert_eq(ids.size(), 2, "both boxes")
	assert_almost_eq(centre_of(level, ids), Vector3(30, 0, 5), Vector3.ONE * 0.001, "centred")
	var record = level.prefab_system.get_instance(r["result"]["instance_id"])
	assert_not_null(record, "recorded as a copy")
	if record != null:
		assert_eq(record.source_path, LIBRARY.path_join("crate.hfprefab"))
		assert_eq(record.variant_name, "base")
		assert_false(record.linked)
	assert_eq(r["result"]["made"][0]["prefab"]["instance_id"], r["result"]["instance_id"])
	await call_tool("hf_undo")
	assert_eq(brushes(level).size(), 0, "undo takes the pieces")
	assert_null(level.prefab_system.get_instance(r["result"]["instance_id"]), "and the record")
	await call_tool("hf_redo")
	assert_eq(brushes(level).size(), 2, "redo brings both back")
	assert_not_null(level.prefab_system.get_instance(r["result"]["instance_id"]))


func test_a_turned_copy_stays_turned_through_a_variant_switch():
	# A copy is rebuilt at the frame read back off its nodes, node times record
	# inverse. Placed any other way, the first switch would un-turn or walk it.
	var level := make_level()
	save_prefab("crate", {"variants": true})
	var r := await place(
		{"prefab": "crate", "position": [30, 0, 0], "rotation_degrees": [0, 90, 0]}
	)
	assert_true(r.get("ok", false), str(r))
	var turned := Basis.from_euler(Vector3(0, deg_to_rad(90), 0))
	var first: DraftBrush = brush_node(level, made_ids(r)[0])
	assert_almost_eq(first.global_transform.basis.x, turned.x, Vector3.ONE * 0.001, "turned")
	var iid: String = r["result"]["instance_id"]
	var small_at: Vector3 = brush_node(level, made_ids(r)[1]).global_position
	var switched := await call_tool(
		"hf_run_command", {"command": "cycle_variant", "brush_ids": [made_ids(r)[1]]}
	)
	assert_true(switched.get("ok", false), str(switched))
	var record = level.prefab_system.get_instance(iid)
	assert_eq(record.variant_name, "small")
	var piece: DraftBrush = brush_node(level, str(record.brush_ids[0]))
	assert_almost_eq(piece.global_transform.basis.x, turned.x, Vector3.ONE * 0.001, "still turned")
	assert_almost_eq(piece.global_position, small_at, Vector3.ONE * 0.01, "and where it was")


func test_a_linked_turned_copy_stays_put_when_propagated():
	var level := make_level()
	save_prefab("crate")
	var r := await place(
		{"prefab": "crate", "position": [0, 0, 30], "rotation_degrees": [0, 45, 0], "linked": true}
	)
	assert_true(r.get("ok", false), str(r))
	assert_true(r["result"]["linked"])
	var before := centre_of(level, made_ids(r))
	var count: int = level.prefab_system.propagate_from_source(LIBRARY.path_join("crate.hfprefab"))
	assert_eq(count, 1, "the linked copy follows its file")
	var record = level.prefab_system.get_instance(r["result"]["instance_id"])
	var after := centre_of(level, Array(record.brush_ids))
	assert_almost_eq(after, before, Vector3.ONE * 0.01, "where it was")
	var piece: DraftBrush = brush_node(level, str(record.brush_ids[0]))
	var turned := Basis.from_euler(Vector3(0, deg_to_rad(45), 0))
	assert_almost_eq(piece.global_transform.basis.x, turned.x, Vector3.ONE * 0.001, "as it was")


func test_each_copy_gets_names_and_ties_of_its_own():
	var level := make_level()
	save_prefab("doorway", {"door": true, "lamp": true})
	var first := await place({"prefab": "doorway", "position": [0, 0, 0]})
	var second := await place({"prefab": "doorway", "position": [40, 0, 0]})
	assert_true(first.get("ok", false) and second.get("ok", false), str(first) + str(second))
	assert_eq(first["result"]["entities_made"].size(), 1, "the lamp, listed")
	assert_eq(second["result"]["entities_made"].size(), 1)
	var names := []
	for r in [first, second]:
		for brush in r["result"]["made"]:
			if brush["brush_entity"] != null:
				names.append(brush["brush_entity"]["name"])
	assert_eq(names.size(), 2, "a door in each copy")
	if names.size() == 2:
		assert_ne(names[0], names[1], "each its own door")
	assert_ne(
		first["result"]["entities_made"][0],
		second["result"]["entities_made"][0],
		"and its own lamp"
	)
	assert_ne(first["result"]["instance_id"], second["result"]["instance_id"])


func test_a_variant_is_placed_by_name():
	var level := make_level()
	save_prefab("crate", {"variants": true})
	var r := await place({"prefab": "crate", "position": [0, 0, 0], "variant": "small"})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["variant"], "small")
	assert_eq(r["result"]["made"].size(), 1, "the small box alone")
	assert_eq(level.prefab_system.get_instance(r["result"]["instance_id"]).variant_name, "small")


func test_undo_takes_back_the_palette_slots_a_prefab_brought():
	var level := make_level()
	save_prefab("painted", {"painted": true})
	var palette_before: int = level.get_materials().size()
	var r := await place({"prefab": "painted", "position": [0, 0, 0]})
	assert_true(r.get("ok", false), str(r))
	assert_gt(level.get_materials().size(), palette_before, "the paint came with it")
	var painted_size: int = level.get_materials().size()
	await call_tool("hf_undo")
	assert_eq(level.get_materials().size(), palette_before, "undo takes the slot back")
	await call_tool("hf_redo")
	assert_eq(level.get_materials().size(), painted_size, "redo brings it back")


func test_a_batch_can_name_the_brush_a_placement_made():
	var level := make_level()
	save_prefab("block", {"one_brush": true})
	var r := await call_tool(
		"hf_batch",
		{
			"ops":
			[
				{
					"tool": "hf_run_command",
					"params":
					{
						"command": "place_prefab",
						"params": {"prefab": "block", "position": [0, 1, 0]}
					}
				},
				{
					"tool": "hf_transform_brush",
					"params": {"brush_id": "$0.brush_id", "position": [6, 1, 0]}
				},
			]
		}
	)
	assert_true(r.get("ok", false), str(r))
	assert_eq(brushes(level).size(), 1)
	assert_almost_eq(brushes(level)[0].global_position.x, 6.0, 0.001, "moved in the same step")


# ===========================================================================
# What an agent reads, and refusals
# ===========================================================================


func test_the_listing_gives_the_library():
	save_prefab("crate", {"variants": true, "lamp": true})
	save_prefab("block", {"one_brush": true})
	var r := await call_tool("hf_list_commands")
	var entry := {}
	for command in r["result"]["commands"]:
		if command["command"] == "place_prefab":
			entry = command
	assert_eq(entry["params"]["required"], ["prefab", "position"])
	assert_eq(
		entry["prefabs"],
		[
			{
				"name": "block",
				"readable": true,
				"variants": ["base"],
				"tags": [],
				"brushes": 1,
				"entities": 0
			},
			{
				"name": "crate",
				"readable": true,
				"variants": ["base", "small"],
				"tags": [],
				"brushes": 2,
				"entities": 1
			},
		]
	)


func test_a_placement_is_checked_before_anything_changes():
	var level := make_level()
	var before := snapshot(level)
	var empty := await place({"prefab": "crate", "position": [0, 0, 0]})
	assert_checked_refusal(empty, "invalid_argument", before, "an empty library")
	assert_string_contains(str(empty["error"]["message"]), "holds no prefabs")
	save_prefab("crate", {"variants": true})
	save_prefab("block", {"one_brush": true})
	var cases := [
		[{"prefab": "barrel", "position": [0, 0, 0]}, "params.prefab"],
		[{"prefab": "../crate", "position": [0, 0, 0]}, "params.prefab"],
		[{"prefab": "crate.hfprefab", "position": [0, 0, 0]}, "params.prefab"],
		[{"prefab": "crate"}, "params.position"],
		[{"prefab": "crate", "position": [0, 0, 0], "variant": "huge"}, "params.variant"],
		[{"prefab": "crate", "position": [0, 0, 0], "linked": "yes"}, "params.linked"],
		[{"prefab": "crate", "position": [0, 0, 0], "angle": 90}, "params.angle"],
	]
	for case in cases:
		before = snapshot(level)
		var r := await place(case[0])
		assert_checked_refusal(r, "invalid_argument", before, str(case[0]))
		if not r.get("ok", true):
			assert_eq(r["error"]["details"]["param"], case[1], str(case[0]))
	var unknown := await place({"prefab": "barrel", "position": [0, 0, 0]})
	assert_string_contains(str(unknown["error"]["message"]), "block, crate", "names what it has")
	var variant := await place({"prefab": "crate", "position": [0, 0, 0], "variant": "huge"})
	assert_string_contains(str(variant["error"]["message"]), "base, small")
	before = snapshot(level)
	var on_brush := await place({"prefab": "crate", "position": [0, 0, 0]}, ["x"])
	assert_checked_refusal(on_brush, "invalid_argument", before, "it takes no brushes")


func test_a_file_that_will_not_read_is_listed_as_such_and_refused():
	var level := make_level()
	var file := FileAccess.open(LIBRARY.path_join("broken.hfprefab"), FileAccess.WRITE)
	file.store_string("[1, 2]")
	file.close()
	var r := await call_tool("hf_list_commands")
	for command in r["result"]["commands"]:
		if command["command"] == "place_prefab":
			assert_eq(command["prefabs"], [{"name": "broken", "readable": false}])
	var before := snapshot(level)
	var refused := await place({"prefab": "broken", "position": [0, 0, 0]})
	assert_checked_refusal(refused, "operation_failed", before, "an unreadable file")
