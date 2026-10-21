extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_list_commands and hf_run_command: the palette commands an agent runs with
## explicit brush ids and parameters, through the dispatcher's one wrapper.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFPrefab = preload("res://addons/hammerforge/hf_prefab.gd")
const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFGeneratorSchema = preload("res://addons/hammerforge/hf_generator_schema.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")
## For its table of each command's required params.
const CommandSweep = preload("res://tests/test_mcp_command_sweep.gd")

const PREFAB_PATH := "user://hf_test_mcp_commands.hfprefab"


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(PREFAB_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFAB_PATH))


func box(level: LevelRoot, id: String, center: Vector3, size := Vector3(4, 4, 4)) -> DraftBrush:
	return level.create_brush_from_info({"size": size, "center": center, "brush_id": id})


func run(command: String, brush_ids = null, args = null, extra := {}) -> Dictionary:
	var params := {"command": command}
	if brush_ids != null:
		params["brush_ids"] = brush_ids
	if args != null:
		params["params"] = args
	return await call_tool("hf_run_command", params, extra)


func ids_of(level: LevelRoot) -> Array:
	var out: Array = []
	for node in brushes(level):
		out.append((node as DraftBrush).brush_id)
	out.sort()
	return out


func top_step() -> String:
	return undo.scene_history.get_current_action_name()


## A check refusal is made before anything is captured, so it has nothing to
## roll back and says nothing about rolling back.
func assert_checked_refusal(response: Dictionary, code: String, before: Dictionary, note: String):
	assert_refused(response, code, note)
	if response.get("ok", true):
		return
	assert_false(response["error"]["details"].has("rolled_back"), "%s: refused in the check" % note)
	assert_eq(snapshot(level_of()), before, "%s: nothing changed" % note)


func level_of() -> LevelRoot:
	return host.level_root_in(host.scene) as LevelRoot


## Every key under `node`, anywhere in it.
static func all_keys(node, into: Array) -> Array:
	if node is Dictionary:
		for key in node:
			into.append(str(key))
			all_keys(node[key], into)
	elif node is Array:
		for item in node:
			all_keys(item, into)
	return into


# ===========================================================================
# hf_list_commands
# ===========================================================================


func test_the_listing_needs_no_scene_and_names_every_bridge_command():
	var r := await call_tool("hf_list_commands")
	assert_true(r.get("ok", false), str(r))
	var listed: Array = []
	for entry in r["result"]["commands"]:
		listed.append(entry["command"])
		assert_ne(entry["description"], "", "%s says what it does" % entry["command"])
		assert_eq(entry["params"]["type"], "object")
		assert_false(entry["params"]["additionalProperties"])
	assert_eq(listed, Array(HFCommandRegistry.bridge_ids()))
	var keys := all_keys(r["result"], [])
	for word in ["gt", "ge", "lt", "le", "exclusiveMinimum"]:
		assert_false(keys.has(word), "JSON Schema words only: no %s" % word)


func test_the_listing_describes_hollow_and_each_structure_type():
	var r := await call_tool("hf_list_commands")
	var by_id := {}
	for entry in r["result"]["commands"]:
		by_id[entry["command"]] = entry
	var thickness: Dictionary = by_id["hollow"]["params"]["properties"]["thickness"]
	assert_eq(
		[thickness["minimum"], thickness["maximum"], thickness["default"]], [0.05, 128.0, 0.25]
	)
	assert_eq(by_id["hollow"]["targets"], {"min": 1, "max": 1, "entities": false})
	assert_eq(by_id["merge"]["targets"]["max"], null, "no cap")
	var structure: Dictionary = by_id["create_arch"]
	assert_eq(
		structure["params"]["properties"]["type"]["enum"], Array(HFGeneratorSystem.known_types())
	)
	assert_eq(structure["params"]["required"], ["type", "position"])
	for type_name in HFGeneratorSystem.known_types():
		var settings: Dictionary = structure["settings_by_type"][type_name]
		assert_gt(settings["properties"].size(), 0, "%s has settings" % type_name)
	var rise: Dictionary = structure["settings_by_type"]["stairs"]["properties"]["rise"]
	assert_true(rise.has("minimum") and rise.has("maximum"), "a range the agent can read")


# ===========================================================================
# Refusals that change nothing
# ===========================================================================


func test_an_unknown_command_and_a_palette_only_one_are_refused():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	var before := snapshot(level)
	var r := await run("nope", ["a"])
	assert_checked_refusal(r, "unknown_command", before, "nope")
	assert_has(r["error"]["details"]["commands"], "hollow")
	r = await run("tool_draw", [])
	assert_checked_refusal(r, "unknown_command", before, "tool_draw")
	assert_string_contains(r["error"]["message"], "palette")


func test_bad_targets_are_refused_before_anything_changes():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	var frozen = (
		level
		. create_brush_from_info(
			{
				"size": Vector3(1, 1, 1),
				"transform": Transform3D(Basis(), Vector3(0, 2, 10)),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"committed": true,
				"brush_id": "frozen",
			}
		)
	)
	assert_eq(frozen.get_parent(), level.committed_node, "the setup made a committed cut")
	var before := snapshot(level)
	var cases := [
		[null, "invalid_argument", "brush_ids missing"],
		[[], "invalid_argument", "brush_ids empty"],
		[[""], "invalid_argument", "an empty id"],
		[["nope"], "brush_not_found", "a made-up id"],
		[["frozen"], "brush_not_found", "a committed cut"],
		[["a", "a"], "invalid_argument", "an id twice"],
		[["a", "nope"], "brush_not_found", "one good id and one made up"],
	]
	for case in cases:
		var r := await run("move_to_floor", case[0])
		assert_checked_refusal(r, case[1], before, case[2])
	var r := await call_tool(
		"hf_run_command", {"command": "move_to_floor", "brush_ids": ["a"], "entities": ["x"]}
	)
	assert_checked_refusal(r, "invalid_argument", before, "entities on a brushes-only command")
	assert_eq(r["error"]["details"]["param"], "entities")
	r = await call_tool("hf_run_command", {"command": "move_to_floor", "brush_ids": ["a"], "x": 1})
	assert_checked_refusal(r, "invalid_argument", before, "an argument the tool does not take")
	r = await run("move_to_floor", ["a"], {"speed": 2})
	assert_checked_refusal(r, "invalid_argument", before, "a param the command does not take")
	assert_eq(r["error"]["details"]["param"], "params.speed")
	r = await run("move_to_floor", ["a"], [1, 2])
	assert_checked_refusal(r, "invalid_argument", before, "params not an object")


func test_every_numeric_param_is_held_to_its_range():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	for command in HFCommandRegistry.bridge_ids():
		var spec := HFCommandRegistry.bridge(command)
		# A brush for a command that takes one, none for one that takes none, and
		# its required params given, so the refusal names the param probed.
		var ids: Array = [] if int(spec["targets"]["max"]) == 0 else ["a"]
		var given: Dictionary = (CommandSweep.REQUIRED.get(command, {}) as Dictionary).duplicate()
		for field_def in spec.get("params", []):
			if not (field_def.has("min") and field_def.has("max")):
				continue
			var key := str(field_def["key"])
			var step := float(field_def.get("step", 0.01))
			for value in [float(field_def["min"]) - step, float(field_def["max"]) + step, "x"]:
				var before := snapshot(level)
				var args := given.duplicate()
				args[key] = value
				var r := await run(command, ids, args)
				assert_refused(r, "invalid_argument", "%s %s=%s" % [command, key, value])
				if not r.get("ok", true):
					assert_eq(r["error"]["details"].get("param"), "params." + key)
				assert_eq(snapshot(level), before)


## A command's params and a structure's settings are read by one rule,
## `HFGeneratorSchema.read_field()` (#1341): an enum by its label in any case
## or by its index, a number held to its range in the schema's own words.
func test_a_param_is_read_by_the_rule_a_structure_setting_is():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	var r := await run("clip", ["a"], {"axis": "X"})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["axis"], "x", "a label in any case")
	box(level, "b", Vector3(20, 2, 0))
	r = await run("clip", ["b"], {"axis": 2})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["axis"], "z", "or its index")
	r = await run("create_arch", null, {"type": "STAIRS", "position": [0, 0, 0]})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["type"], "stairs")
	box(level, "c", Vector3(40, 2, 0))
	var before := snapshot(level)
	r = await run("clip", ["c"], {"axis": 3})
	assert_checked_refusal(r, "invalid_argument", before, "no fourth axis")
	assert_eq(r["error"]["message"], "axis is one of x, y, z, or its index from 0")
	var rise := HFGeneratorSchema.field(HFGeneratorSystem.settings_schema("stairs"), "rise")
	r = await run(
		"create_arch", null, {"type": "stairs", "position": [0, 0, 0], "settings": {"rise": 5000}}
	)
	assert_checked_refusal(r, "invalid_argument", before, "rise past its max")
	assert_eq(
		r["error"]["message"],
		HFGeneratorSchema.read_field(rise, 5000, "rise")["message"],
		"the bridge refuses in the schema's words"
	)
	var hollow_params: Array = HFCommandRegistry.bridge("hollow")["params"]
	var thickness := HFGeneratorSchema.field(hollow_params, "thickness")
	r = await run("hollow", ["c"], {"thickness": 0.01})
	assert_checked_refusal(r, "invalid_argument", before, "thickness under its min")
	assert_eq(r["error"]["message"], "thickness must be from 0.05 to 128")
	assert_eq(
		r["error"]["message"], HFGeneratorSchema.read_field(thickness, 0.01, "thickness")["message"]
	)


# ===========================================================================
# Move to Floor, Move to Ceiling, Reset Rotation
# ===========================================================================


func test_move_to_floor_is_one_step_the_agent_can_undo_and_redo():
	var level := make_level()
	box(level, "floor", Vector3(0, -1, 0), Vector3(20, 2, 20))
	box(level, "a", Vector3(0, 10, 0), Vector3(2, 2, 2))
	var r := await run("move_to_floor", ["a"])
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: move to floor")
	var landed: float = brush_node(level, "a").global_position.y
	assert_almost_eq(landed, 1.0, 0.01, "rests on the floor brush")
	assert_eq(r["result"]["changed"][0]["brush_id"], "a")
	assert_eq(r["result"]["made"], [])
	assert_eq(r["result"]["removed"], [])
	var undone := await call_tool("hf_undo")
	assert_true(undone.get("ok", false), str(undone))
	assert_almost_eq(brush_node(level, "a").global_position.y, 10.0, 0.01, "undo lifts it back")
	var redone := await call_tool("hf_redo")
	assert_true(redone.get("ok", false), str(redone))
	assert_almost_eq(brush_node(level, "a").global_position.y, landed, 0.01, "redo drops it again")


func test_move_to_ceiling_and_reset_rotation():
	var level := make_level()
	box(level, "roof", Vector3(0, 21, 0), Vector3(20, 2, 20))
	box(level, "a", Vector3(0, 4, 0), Vector3(2, 2, 2))
	var r := await run("move_to_ceiling", ["a"])
	assert_true(r.get("ok", false), str(r))
	assert_almost_eq(brush_node(level, "a").global_position.y, 19.0, 0.01, "its top meets the roof")
	level.set_brush_rotation_by_id("a", Vector3(0, 30, 0))
	r = await run("reset_rotation", ["a"])
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: reset rotation")
	assert_true(
		brush_node(level, "a").global_transform.basis.orthonormalized().is_equal_approx(
			Basis.IDENTITY
		),
		"no rotation left"
	)


func test_snap_to_grid_puts_a_brush_corner_on_the_grid_as_one_step():
	var level := make_level()
	level.grid_snap = 0.5
	box(level, "a", Vector3(0.3, 0, 0.1), Vector3.ONE)
	var r := await run("snap_to_grid", ["a"])
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: snap to grid")
	var node: DraftBrush = brush_node(level, "a")
	assert_true(node.global_position.is_equal_approx(Vector3(0.5, 0, 0)), str(node.global_position))
	assert_eq(node.size, Vector3.ONE, "the same size")
	var again := await run("snap_to_grid", ["a"])
	assert_true(again["result"].get("no_change", false), "on the grid already: %s" % str(again))
	var undone := await call_tool("hf_undo")
	assert_true(undone.get("ok", false), str(undone))
	assert_true(
		brush_node(level, "a").global_position.is_equal_approx(Vector3(0.3, 0, 0.1)),
		"undo puts it back"
	)
	level.grid_snap = 0.0
	var before := snapshot(level)
	var refused := await run("snap_to_grid", ["a"])
	assert_checked_refusal(refused, "operation_failed", before, "no grid to snap to")


## On brushes already where the command would put them, the command changes
## nothing: no step, the revision where it was, and an answer that says so. The
## agent's undo chain then still ends at its last real step (#1365).
func test_a_command_that_changes_nothing_records_no_step():
	var level := make_level()
	box(level, "floor", Vector3(0, -1, 0), Vector3(20, 2, 20))
	box(level, "roof", Vector3(0, 21, 0), Vector3(20, 2, 20))
	box(level, "a", Vector3(0, 10, 0), Vector3(2, 2, 2))
	box(level, "b", Vector3(5, 19, 0), Vector3(2, 2, 2))
	var dropped := await run("move_to_floor", ["a"])
	assert_true(dropped.get("ok", false), str(dropped))
	assert_false(dropped["result"].has("no_change"), "a real move says nothing of the kind")
	var steps: int = undo.scene_history.get_history_count()
	var revision: int = dropped["revision"]
	for case in [["move_to_floor", "a"], ["move_to_ceiling", "b"], ["reset_rotation", "a"]]:
		var r := await run(case[0], [case[1]])
		assert_true(r.get("ok", false), "%s: %s" % [case[0], str(r)])
		if not r.get("ok", false):
			continue
		assert_eq(r["result"].get("no_change"), true, "%s says it changed nothing" % case[0])
		assert_eq(r["result"]["changed"], [], "%s lists no brush as changed" % case[0])
		assert_eq(undo.scene_history.get_history_count(), steps, "%s: no step" % case[0])
		assert_eq(r["revision"], revision, "%s: the revision stays" % case[0])
		assert_eq(top_step(), "MCP: move to floor", "%s: the agent's step is on top" % case[0])
	assert_almost_eq(
		brush_node(level, "b").global_position.y, 19.0, 0.01, "b stayed under the roof"
	)
	var undone := await call_tool("hf_undo")
	assert_true(undone.get("ok", false), str(undone))
	assert_eq(undone.get("result", {}).get("undone"), "MCP: move to floor")
	assert_almost_eq(brush_node(level, "a").global_position.y, 10.0, 0.01, "the real move undone")


func test_a_replay_answers_from_the_cache_and_a_changed_one_conflicts():
	var level := make_level()
	box(level, "floor", Vector3(0, -1, 0), Vector3(20, 2, 20))
	box(level, "a", Vector3(0, 10, 0), Vector3(2, 2, 2))
	box(level, "b", Vector3(5, 10, 0), Vector3(2, 2, 2))
	var first := await run("move_to_floor", ["a"], null, {"operation_id": "op-1"})
	var steps: int = undo.scene_history.get_history_count()
	var again := await run("move_to_floor", ["a"], null, {"operation_id": "op-1"})
	assert_true(again.get("replayed", false), "the same call is answered, not run")
	assert_eq(undo.scene_history.get_history_count(), steps, "and adds no step")
	assert_eq(again["result"], first["result"])
	var other := await run("move_to_floor", ["b"], null, {"operation_id": "op-1"})
	assert_refused(other, "operation_id_conflict")


func test_undo_after_a_human_edit_conflicts_and_another_target_is_refused():
	var level := make_level()
	box(level, "floor", Vector3(0, -1, 0), Vector3(20, 2, 20))
	box(level, "a", Vector3(0, 10, 0), Vector3(2, 2, 2))
	await run("move_to_floor", ["a"])
	var marker := Node.new()
	add_child_autoqfree(marker)
	undo.scene_history.create_action("Human edit")
	undo.scene_history.add_do_property(marker, "name", "after")
	undo.scene_history.add_undo_property(marker, "name", "before")
	undo.scene_history.commit_action()
	assert_refused(await call_tool("hf_undo"), "undo_conflict")
	var elsewhere := await run("move_to_floor", ["a"], null, {"expect_target": "1:2:3"})
	assert_refused(elsewhere, "target_changed")


## The real plugin, with a box selected in it. A command naming other brushes, or
## none that exist, never falls back to what is selected.
func test_a_command_never_falls_back_to_the_selection():
	var rig := PluginRig.new()
	await rig.bring_up(self, true)
	if rig.plugin == null:
		fail_test(rig.error())
		await rig.take_down()
		return
	host.scene = rig.scene_root
	var level: LevelRoot = await rig.make_level()
	level.grid_snap = 1.0
	rig.box(level, "floor", Vector3(0, -1, 0), Vector3(40, 2, 40))
	var a: DraftBrush = rig.box(level, "a", Vector3(0, 10, 0), Vector3(2, 2, 2))
	var b: DraftBrush = rig.box(level, "b", Vector3(8, 10, 0), Vector3(2, 2, 2))
	rig.select([a])
	var selection = rig.plugin.stand_in_editor.selection

	var refused := await run("move_to_floor", ["nope"])
	assert_refused(refused, "brush_not_found")
	assert_almost_eq(a.global_position.y, 10.0, 0.01, "the selected box did not move")
	assert_eq(selection.get_selected_nodes(), [a], "the selection is as it was")

	var moved := await run("move_to_floor", ["b"])
	assert_true(moved.get("ok", false), str(moved))
	assert_almost_eq(b.global_position.y, 1.0, 0.01, "the named box moved")
	assert_almost_eq(a.global_position.y, 10.0, 0.01, "the selected one did not")
	assert_eq(selection.get_selected_nodes(), [a], "and the selection is untouched")
	host.scene = null
	await rig.leave_level(level)
	await rig.take_down()


# ===========================================================================
# Hollow, Clip, Clip to Face, Carve, Merge
# ===========================================================================


func test_hollow_makes_walls_in_one_step_that_undo_takes_back():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	var before := ids_of(level)
	var r := await run("hollow", ["a"], {"thickness": 0.5})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: hollow")
	assert_eq(r["result"]["removed"], ["a"])
	assert_eq(r["result"]["made"].size(), 6, "a box shells into six walls")
	assert_eq(r["result"]["thickness"], 0.5)
	assert_false(r["result"]["made"][0].has("faces"), "made brushes come without faces")
	var walls := ids_of(level)
	await call_tool("hf_undo")
	assert_eq(ids_of(level), before, "undo puts the box back")
	await call_tool("hf_redo")
	assert_eq(ids_of(level), walls, "redo puts the same walls back")


func test_a_hollow_the_box_cannot_take_says_what_the_palette_says():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	var before := snapshot(level)
	var r := await run("hollow", ["a"], {"thickness": 3.0})
	assert_checked_refusal(r, "operation_failed", before, "walls thicker than the box")
	assert_eq(r["error"]["message"], level.can_hollow_brush("a", 3.0).user_text())


## The palette's own Hollow, pressed through the real plugin with the same
## thickness, refuses in the same words.
func test_the_palette_and_the_bridge_refuse_a_hollow_alike():
	var rig := PluginRig.new()
	await rig.bring_up(self)
	if rig.plugin == null:
		fail_test(rig.error())
		await rig.take_down()
		return
	var level: LevelRoot = await rig.make_level()
	var a: DraftBrush = rig.box(level, "a", Vector3(0, 2, 0))
	rig.plugin.dock.hollow_thickness.value = 3.0
	var said: Array = []
	level.user_message.connect(func(text, _level): said.append(text))
	rig.select([a])
	rig.plugin._on_hotkey_palette_action("hollow")
	await rig.frame()
	host.scene = rig.scene_root
	var r := await run("hollow", ["a"], {"thickness": 3.0})
	assert_refused(r, "operation_failed")
	assert_has(said, r["error"]["message"], "the palette said it in the same words")
	host.scene = null
	await rig.leave_level(level)
	await rig.take_down()


func test_clip_splits_through_the_middle_or_where_it_is_told():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	var r := await run("clip", ["a"])
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: clip")
	assert_eq(r["result"]["made"].size(), 2)
	assert_eq(r["result"]["removed"], ["a"])
	assert_eq([r["result"]["axis"], r["result"]["split_position"]], ["y", 2.0])
	box(level, "b", Vector3(20, 2, 0), Vector3(8, 4, 4))
	r = await run("clip", ["b"], {"axis": "x", "position": 21.2})
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["split_position"], 21.0, "snapped to the grid")
	box(level, "c", Vector3(40, 2, 0))
	var before := snapshot(level)
	r = await run("clip", ["c"], {"axis": "x", "position": 100.0})
	assert_checked_refusal(r, "operation_failed", before, "outside the brush")
	assert_eq(r["error"]["message"], level.can_clip_brush("c", 0, 100.0).user_text())
	r = await run("clip", ["c"], {"axis": "w"})
	assert_checked_refusal(r, "invalid_argument", before, "no such axis")


func test_clip_to_face_cuts_what_the_plane_crosses_and_lists_the_rest():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	box(level, "b", Vector3(20, 2, 0))
	box(level, "p", Vector3(0, 2, 10), Vector3(2, 2, 2))
	var r := await run("clip_to_face", ["a", "b"], {"plane_brush_id": "p", "plane_face": "+x"})
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: clip to face plane")
	assert_eq(r["result"]["skipped"], ["b"])
	assert_eq(r["result"]["removed"], ["a"])
	assert_eq(r["result"]["made"].size(), 2)
	var before := snapshot(level)
	r = await run("clip_to_face", ["b"], {"plane_brush_id": "p", "plane_face": "-z"})
	assert_checked_refusal(r, "operation_failed", before, "a plane through nothing named")
	r = await run("clip_to_face", ["b"], {"plane_brush_id": "nope", "plane_face": "+x"})
	assert_checked_refusal(r, "brush_not_found", before, "an unknown plane brush")
	level.set_brush_rotation_by_id("p", Vector3(0, 45, 0))
	before = snapshot(level)
	r = await run("clip_to_face", ["b"], {"plane_brush_id": "p", "plane_face": "+x"})
	assert_checked_refusal(r, "ambiguous_face", before, "two faces equally +x")


func test_carve_cuts_with_the_carvers_that_overlap_and_lists_the_rest():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	box(level, "c", Vector3(2, 2, 0), Vector3(2, 2, 2))
	box(level, "d", Vector3(50, 2, 0), Vector3(2, 2, 2))
	var r := await run("carve", ["c", "d"])
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: carve")
	assert_eq(r["result"]["skipped"], ["d"])
	assert_has(r["result"]["removed"], "a")
	assert_gt(r["result"]["made"].size(), 0)
	assert_has(r["result"]["removed"], "c", "the carver is used up")
	assert_not_null(brush_node(level, "d"), "the one that cut nothing is left alone")
	var before := snapshot(level)
	r = await run("carve", ["d"])
	assert_checked_refusal(r, "operation_failed", before, "a carver over nothing")
	assert_eq(r["error"]["message"], level.can_carve_brush("d").user_text())


func test_merge_plans_once_and_answers_the_brush_it_made():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	box(level, "b", Vector3(4, 2, 0))
	var plans: int = level.brush_system.merge_plans_made
	var r := await run("merge", ["a", "b"])
	assert_true(r.get("ok", false), str(r))
	assert_eq(level.brush_system.merge_plans_made - plans, 1, "one plan for one call (#1257)")
	assert_eq(top_step(), "MCP: merge brushes")
	assert_true(r["result"].has("brush"), "the one brush made is named")
	assert_eq(r["result"]["removed"], ["a", "b"])
	var before := snapshot(level)
	assert_checked_refusal(
		await run("merge", [r["result"]["brush"]["brush_id"]]),
		"invalid_argument",
		before,
		"one brush"
	)


func test_a_merge_that_is_not_convex_says_what_the_palette_says():
	var level := make_level()
	box(level, "a", Vector3(0, 2, 0))
	box(level, "b", Vector3(4, 2, 4))
	var before := snapshot(level)
	var r := await run("merge", ["a", "b"])
	assert_checked_refusal(r, "operation_failed", before, "an L")
	assert_eq(r["error"]["message"], level.can_merge_brushes(["a", "b"]).user_text())


# ===========================================================================
# Create Structure
# ===========================================================================


func test_a_structure_is_one_step_with_its_record():
	var level := make_level()
	var r := await run(
		"create_arch", null, {"type": "stairs", "position": [10, 0, 0], "settings": {"steps": 4}}
	)
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: create structure")
	assert_eq(r["result"]["made"].size(), 4, "one brush per step")
	assert_not_null(r["result"]["generator_id"])
	assert_eq(r["result"]["settings"]["steps"], 4)
	assert_eq(level.generator_count(), 1)
	await call_tool("hf_undo")
	assert_eq(level.generator_count(), 0, "undo takes the record")
	assert_eq(brushes(level).size(), 0, "and the pieces")
	await call_tool("hf_redo")
	assert_eq(level.generator_count(), 1, "redo brings both back")
	assert_eq(brushes(level).size(), 4)


func test_every_structure_type_builds_on_its_defaults():
	make_level()
	for type_name in HFGeneratorSystem.known_types():
		var r := await run("create_arch", null, {"type": type_name, "position": [0, 0, 0]})
		assert_true(r.get("ok", false), "%s: %s" % [type_name, str(r)])


func test_structure_settings_are_checked_and_never_quietly_defaulted():
	var level := make_level()
	var before := snapshot(level)
	var cases := [
		[{"rise": "high"}, "params.settings.rise"],
		[{"rize": 0.2}, "params.settings.rize"],
		[{"rise": 5000}, "params.settings.rise"],
		[{"steps": 2.5}, "params.settings.steps"],
		[{"fill": 7}, "params.settings.fill"],
		[{"fill": "Glass"}, "params.settings.fill"],
	]
	for case in cases:
		var r := await run(
			"create_arch", null, {"type": "stairs", "position": [0, 0, 0], "settings": case[0]}
		)
		assert_checked_refusal(r, "invalid_argument", before, str(case[0]))
		if not r.get("ok", true):
			assert_eq(r["error"]["details"]["param"], case[1])
	var named := await run(
		"create_arch", null, {"type": "stairs", "position": [0, 0, 0], "settings": {"fill": "open"}}
	)
	assert_true(named.get("ok", false), "an enum by its label: %s" % str(named))
	assert_eq(named["result"]["settings"]["fill"], 1)
	for case in [
		[{"type": "tower", "position": [0, 0, 0]}, "params.type"],
		[{"type": "stairs"}, "params.position"],
	]:
		before = snapshot(level)
		var r := await run("create_arch", null, case[0])
		assert_checked_refusal(r, "invalid_argument", before, str(case[0]))
		assert_eq(r["error"]["details"]["param"], case[1])
	before = snapshot(level)
	var on_brush := await run("create_arch", ["x"], {"type": "stairs", "position": [0, 0, 0]})
	assert_checked_refusal(on_brush, "invalid_argument", before, "a structure takes no brushes")


func test_a_structure_the_builder_refuses_says_what_the_dock_says():
	var level := make_level()
	var settings := {"radius": 2.0, "wall_thickness": 3.0}
	var before := snapshot(level)
	var r := await run(
		"create_arch", null, {"type": "arch", "position": [0, 0, 0], "settings": settings}
	)
	assert_checked_refusal(r, "operation_failed", before, "a wall thicker than the radius")
	var merged := HFGeneratorSchema.merge(HFGeneratorSystem.settings_schema("arch"), settings)
	assert_eq(r["error"]["message"], level.can_build_generator("arch", merged).user_text())


# ===========================================================================
# Prefab variant and propagate
# ===========================================================================


## A one-box prefab with a second variant, saved, and `copies` copies placed,
## linked or not. Returns the instance ids.
func place_prefab(level: LevelRoot, copies: int, linked: bool, variants := true) -> Array:
	var source := box(level, "src", Vector3(0, 2, -20))
	var prefab = HFPrefab.capture_from_selection(
		level.brush_system, level.entity_system, [source], []
	)
	if variants:
		var base: Dictionary = prefab.get_variant_data("base").duplicate(true)
		prefab.set_variant_data("tall", base["brush_infos"], [])
	assert_eq(prefab.save_to_file(PREFAB_PATH), OK)
	var out: Array = []
	for i in copies:
		var placed: Dictionary = prefab.instantiate(
			level.brush_system, level.entity_system, level, Vector3(10 * (i + 1), 0, 0)
		)
		out.append(
			level.prefab_system.register_instance(
				PREFAB_PATH, placed["brush_ids"], placed["entity_nodes"], linked
			)
		)
	return out


func test_cycle_variant_switches_a_copy_named_by_any_piece():
	var level := make_level()
	var iid: String = place_prefab(level, 1, false)[0]
	var piece: String = level.prefab_system.get_instance(iid).brush_ids[0]
	var listed := await call_tool("hf_get_brushes", {"brush_ids": [piece, "src"]})
	var prefab_of := {}
	for brush in listed["result"]["brushes"]:
		prefab_of[brush["brush_id"]] = brush["prefab"]
	assert_eq(prefab_of[piece]["instance_id"], iid, "a piece says which copy it is")
	assert_null(prefab_of["src"], "the source box is plain geometry")
	var r := await run("cycle_variant", [piece])
	assert_true(r.get("ok", false), str(r))
	assert_eq(top_step(), "MCP: cycle prefab variant")
	assert_eq(r["result"]["variant"], "tall")
	assert_eq(level.prefab_system.get_instance(iid).variant_name, "tall")
	await call_tool("hf_undo")
	assert_eq(level.prefab_system.get_instance(iid).variant_name, "base", "undo switches back")
	var before := snapshot(level)
	assert_checked_refusal(
		await run("cycle_variant", ["src"]), "invalid_argument", before, "not a piece"
	)


func test_cycle_variant_refuses_a_prefab_with_one_variant():
	var level := make_level()
	var iid: String = place_prefab(level, 1, false, false)[0]
	var piece: String = level.prefab_system.get_instance(iid).brush_ids[0]
	var before := snapshot(level)
	assert_checked_refusal(
		await run("cycle_variant", [piece]), "operation_failed", before, "one variant"
	)


func test_propagate_rebuilds_every_linked_copy():
	var level := make_level()
	var iids := place_prefab(level, 2, true)
	var piece: String = level.prefab_system.get_instance(iids[0]).brush_ids[0]
	var r := await run("propagate_prefab", [piece])
	assert_true(r.get("ok", false), str(r))
	assert_eq(r["result"]["instances"], 2)
	assert_eq(top_step(), "MCP: propagate prefab")


func test_propagate_with_no_linked_copy_is_refused():
	var level := make_level()
	var iid: String = place_prefab(level, 1, false)[0]
	var piece: String = level.prefab_system.get_instance(iid).brush_ids[0]
	var before := snapshot(level)
	var r := await run("propagate_prefab", [piece])
	assert_checked_refusal(r, "operation_failed", before, "nothing linked")
	assert_eq(r["error"]["message"], "No linked instances to propagate")


func test_move_to_floor_reports_only_targets_that_changed():
	var level := make_level()
	box(level, "floor", Vector3(0, -1, 0), Vector3(30, 2, 30))
	box(level, "already_down", Vector3(-4, 1, 0), Vector3(2, 2, 2))
	box(level, "above", Vector3(4, 10, 0), Vector3(2, 2, 2))
	var answer := await run("move_to_floor", ["already_down", "above"])
	assert_true(answer.get("ok", false), str(answer))
	var changed: Array = answer["result"]["changed"]
	assert_eq(changed.size(), 1)
	assert_eq(changed[0]["brush_id"], "above")
	assert_almost_eq(brush_node(level, "above").global_position.y, 1.0, 0.01)
	brush_node(level, "already_down").global_position.y = 7
	brush_node(level, "above").global_position.y = 9
	answer = await run("move_to_floor", ["already_down", "above"])
	changed = answer["result"]["changed"]
	assert_eq(changed.size(), 2, "Every moved target is still listed")
