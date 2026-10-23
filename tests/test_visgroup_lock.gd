extends GutTest

## A locked visgroup, and Godot's own lock, keep what they hold from every tool,
## command and agent (#1697). `test_palette_action_sweep.gd` runs every action in
## its `locked` state; this covers the rest.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginSelectionCommands = preload("res://addons/hammerforge/plugin_selection_commands.gd")
const HFMcpDispatcher = preload("res://addons/hammerforge/mcp/hf_mcp_dispatcher.gd")
const HostStandIn = preload("res://tests/mcp/mcp_test_host.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Dictionary:
	var level = await rig.make_level()
	var held = rig.box(level, "held", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var free = rig.box(level, "free", Vector3(6, 1, 0), Vector3(2, 2, 2))
	level.visgroup_system.add_to_visgroup(held, "Done")
	level.visgroup_system.set_visgroup_locked("Done", true)
	return {"level": level, "held": held, "free": free}


func _selected() -> Array:
	return rig.plugin.stand_in_editor.selection.get_selected_nodes()


func test_a_locked_brush_is_drawn_faded_and_freed_again():
	var s: Dictionary = await _level()
	assert_gt(s.held.mesh_instance.transparency, 0.0, "faded")
	assert_eq(s.free.mesh_instance.transparency, 0.0, "the other is not")
	s.level.visgroup_system.set_visgroup_locked("Done", false)
	assert_eq(s.held.mesh_instance.transparency, 0.0, "drawn plainly once unlocked")
	await rig.leave_level(s.level)


func test_a_locked_brush_never_stays_selected():
	var s: Dictionary = await _level()
	rig.select([s.held, s.free])
	assert_eq(_selected(), [s.free], "only the free one")
	rig.plugin._on_hotkey_palette_action("select_all")
	assert_false(_selected().has(s.held), "Select All leaves it out")
	rig.select([])
	await rig.leave_level(s.level)


func test_godot_s_own_lock_does_the_same():
	var s: Dictionary = await _level()
	s.free.set_meta("_edit_lock_", true)
	assert_true(s.level.visgroup_system.is_locked(s.free))
	rig.select([s.free])
	assert_eq(_selected(), [], "the padlock in the Scene dock keeps it out")
	rig.select([])
	await rig.leave_level(s.level)


func test_a_locked_brush_s_faces_are_not_picked():
	var s: Dictionary = await _level()
	var key: String = s.level.brush_system.face_key(s.held)
	HFPluginSelectionCommands.apply_face_selection(rig.plugin, s.level, {key: [0, 1]})
	assert_false(s.level.face_selection.has(key), "Similar and the filters leave them out")
	var free_key: String = s.level.brush_system.face_key(s.free)
	HFPluginSelectionCommands.apply_face_selection(rig.plugin, s.level, {free_key: [0]})
	assert_true(s.level.face_selection.has(free_key))
	s.level.face_selection = {}
	await rig.leave_level(s.level)


func test_replace_material_leaves_a_locked_brush_alone():
	var s: Dictionary = await _level()
	s.level.add_prototype_materials()
	var every_face: Array[int] = [0, 1, 2, 3, 4, 5]
	for brush in [s.held, s.free]:
		brush.assign_material_to_faces(0, every_face)
	s.level.brush_system.replace_material(0, 1)
	assert_eq(s.held.faces[0].material_idx, 0, "the locked brush keeps its material")
	assert_eq(s.free.faces[0].material_idx, 1, "the free one takes the new")
	await rig.leave_level(s.level)


func test_the_bridge_refuses_a_locked_brush_and_says_so():
	var s: Dictionary = await _level()
	var host = HostStandIn.new()
	host.undo = rig.undo()
	host.tree = get_tree()
	host.scene = s.level.get_parent()
	var dispatcher = HFMcpDispatcher.new(host)
	var held_id := str(s.held.brush_id)
	var moved: Dictionary = await dispatcher.handle(
		{
			"type": "request",
			"id": "l1",
			"method": "hf_transform_brush",
			"params": {"brush_id": held_id, "position": [0, 5, 0]}
		}
	)
	assert_false(moved.get("ok", true))
	assert_eq(str(moved.get("error", {}).get("code", "")), "locked")
	assert_eq(s.held.global_position, Vector3(0, 1, 0), "it did not move")
	var command: Dictionary = await dispatcher.handle(
		{
			"type": "request",
			"id": "l2",
			"method": "hf_run_command",
			"params": {"command": "hollow", "brush_ids": [held_id]}
		}
	)
	assert_eq(str(command.get("error", {}).get("code", "")), "locked", "hf_run_command too")
	var listed: Dictionary = await dispatcher.handle(
		{"type": "request", "id": "l3", "method": "hf_get_brushes", "params": {}}
	)
	var lock_by_id: Dictionary = {}
	for brush in listed.get("result", {}).get("brushes", []):
		lock_by_id[str(brush.get("brush_id", ""))] = brush.get("locked")
	assert_eq(lock_by_id.get(held_id), true, "hf_get_brushes says it is locked")
	assert_eq(lock_by_id.get(str(s.free.brush_id)), false)
	dispatcher.shutdown()
	await rig.leave_level(s.level)


func test_lock_and_unlock_are_steps_previous_visibility_takes_back():
	var s: Dictionary = await _level()
	assert_true(s.level.visgroup_system.previous_view(), "back over the lock")
	assert_false(s.level.visgroup_system.is_locked(s.held))
	await rig.leave_level(s.level)


func test_a_lock_is_kept_with_the_level():
	var s: Dictionary = await _level()
	var saved: Dictionary = s.level.visgroup_system.capture_visgroups()
	assert_true(saved["Done"]["locked"])
	s.level.visgroup_system.restore_visgroups({})
	s.level.visgroup_system.restore_visgroups(saved)
	assert_true(s.level.visgroup_system.is_visgroup_locked("Done"), "read back")
	await rig.leave_level(s.level)
