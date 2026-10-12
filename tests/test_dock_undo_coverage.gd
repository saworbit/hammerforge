extends GutTest

## Which dock commands register an undo step, and what their redo is made of.
##
## Two halves, for the same reason `test_undo_collation.gd` has two: an
## `EditorUndoRedoManager` cannot be constructed outside the editor. What a
## command redoes is driven through `register_action()` against the stand-in that
## file already carries, replayed against a real `LevelRoot`. Which wrapper a
## button reaches for is read off the handler source, because that is the part a
## null `undo_redo` in a test would hide.
##
## The invariant behind the whole set: `restore_state()` clears the brushes and
## entities and rebuilds them from their captured info, so any command holding a
## live node has to redo from a state snapshot rather than from the call.

const CollationTests = preload("res://tests/test_undo_collation.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

const HANDLER_SOURCES := [
	"res://addons/hammerforge/dock_visgroup_handler.gd",
	"res://addons/hammerforge/dock_entity_handler.gd",
	"res://addons/hammerforge/dock_paint_handler.gd",
	"res://addons/hammerforge/dock_file_handler.gd",
]

const MERGE_DISABLE := 0


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _fake_undo():
	return CollationTests.FakeUndoRedo.new()


## Register one command the way the dock now does, against the stand-in.
func _commit(fake, root: LevelRoot, name: String, method: String, args: Array, absolute: bool):
	var before: Dictionary = root.capture_state()
	HFUndoHelper.register_action(
		fake, root, name, MERGE_DISABLE, method, args, before, false, absolute
	)


func _body(function_name: String) -> String:
	for path in HANDLER_SOURCES:
		var source := FileAccess.get_file_as_string(path)
		var start := source.find("\nstatic func %s(" % function_name)
		if start < 0:
			continue
		var rest := source.substr(start + 1)
		var end := rest.find("\n\n\n")
		return rest if end < 0 else rest.substr(0, end)
	return ""


func _box(root: LevelRoot, brush_id: String, center: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": LevelRoot.BrushShape.BOX,
				"size": Vector3(64, 64, 64),
				"center": center,
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
			}
		)
	)


func _first_child(parent: Node) -> Node:
	return parent.get_child(0) if parent and parent.get_child_count() > 0 else null


# ---------------------------------------------------------------------------
# What the redo is made of
# ---------------------------------------------------------------------------


func test_create_entity_redo_survives_the_undo_that_freed_the_entity() -> void:
	var root := _fresh_root()
	var fake = _fake_undo()
	var entity := DraftEntity.new()
	entity.name = "DraftEntity"
	entity.set_meta("is_entity", true)

	_commit(fake, root, "Create Entity", "add_entity", [entity], true)
	assert_eq(root.entities_node.get_child_count(), 1, "Create Entity must add the entity")

	var do_calls: Array = fake.entries[-1]["do"]
	assert_eq(do_calls.size(), 1)
	assert_eq(
		do_calls[0]["method"],
		"restore_state",
		"A command holding a live node must redo from a state snapshot, not the call"
	)

	fake.undo()
	assert_eq(root.entities_node.get_child_count(), 0, "Undo must take the entity back out")
	# The undo took the node the call was made with out of the tree and queued it
	# for release. The redo has to rebuild from the snapshot rather than re-add
	# that node: before the fix it handed add_entity() a reference on its way out.
	fake.redo()
	assert_eq(root.entities_node.get_child_count(), 1, "Redo must put the entity back")
	assert_ne(
		_first_child(root.entities_node),
		entity,
		"Redo must rebuild the entity from the snapshot, not re-add the original node"
	)


func test_without_an_absolute_redo_the_same_command_redoes_a_dead_node() -> void:
	# Why the flag is not optional on these commands. Registered the ordinary way,
	# the do operation names the call and carries the node, and the undo in
	# between is what takes that node out of the tree.
	var root := _fresh_root()
	var fake = _fake_undo()
	var entity := DraftEntity.new()
	entity.name = "DraftEntity"
	entity.set_meta("is_entity", true)

	_commit(fake, root, "Create Entity", "add_entity", [entity], false)
	var do_calls: Array = fake.entries[-1]["do"]
	assert_eq(do_calls[0]["method"], "add_entity", "The ordinary path registers the call itself")
	assert_eq(
		do_calls[0]["args"][0],
		entity,
		"and holds the node, which is the reference the undo invalidates"
	)

	fake.undo()
	assert_eq(root.entities_node.get_child_count(), 0)
	assert_false(
		root.entities_node.get_children().has(entity),
		"The undo removed the node the redo would be handed"
	)


func test_delete_visgroup_undo_restores_the_record_and_the_membership() -> void:
	var root := _fresh_root()
	var fake = _fake_undo()
	var brush := _box(root, "undo_brush", Vector3.ZERO)
	root.create_visgroup("Lights")
	root.add_selection_to_visgroup("Lights", [brush])
	assert_eq(Array(brush.get_meta("visgroups", PackedStringArray())), ["Lights"])

	_commit(fake, root, "Delete Visgroup", "remove_visgroup", ["Lights"], false)
	assert_eq(Array(root.visgroup_system.get_visgroup_names()), [], "Delete must remove the record")

	fake.undo()
	assert_eq(
		Array(root.visgroup_system.get_visgroup_names()),
		["Lights"],
		"Undo must bring the visgroup record back"
	)
	var restored := _first_child(root.draft_brushes_node)
	assert_not_null(restored, "Undo must leave the brush in place")
	assert_eq(
		Array(restored.get_meta("visgroups", PackedStringArray())),
		["Lights"],
		"Undo must bring the membership back, not just the record"
	)


func test_group_selection_undo_clears_the_group_and_its_member_meta() -> void:
	var root := _fresh_root()
	var fake = _fake_undo()
	var brush_a := _box(root, "undo_brush_a", Vector3.ZERO)
	var brush_b := _box(root, "undo_brush_b", Vector3(128, 0, 0))

	_commit(fake, root, "Group Selection", "group_selection", ["group_1", [brush_a, brush_b]], true)
	assert_true(root.capture_state().get("groups", {}).has("group_1"), "Group must be recorded")

	fake.undo()
	assert_false(
		root.capture_state().get("groups", {}).has("group_1"), "Undo must remove the group"
	)
	for child in root.draft_brushes_node.get_children():
		assert_false(child.has_meta("group_id"), "Undo must clear group_id from the members")


func test_remove_entity_output_undo_restores_the_connection() -> void:
	var root := _fresh_root()
	var fake = _fake_undo()
	var entity := DraftEntity.new()
	entity.name = "DraftEntity"
	entity.set_meta("is_entity", true)
	root.add_entity(entity)
	entity.entity_data["targetname"] = "door_1"
	root.add_entity_output(entity, "OnPressed", "door_1", "Open", "", 0.0, false)
	assert_eq(root.get_entity_outputs(entity).size(), 1)

	_commit(fake, root, "Remove Entity Output", "remove_entity_output", [entity, 0], true)
	assert_eq(root.get_entity_outputs(entity).size(), 0, "Remove must drop the connection")

	fake.undo()
	var restored := _first_child(root.entities_node)
	assert_not_null(restored, "Undo must rebuild the entity")
	assert_eq(root.get_entity_outputs(restored).size(), 1, "Undo must bring the connection back")


func test_remove_paint_layer_undo_restores_the_layer_and_what_was_painted() -> void:
	var root := _fresh_root()
	if not root.paint_layers:
		pass_test("no paint layer manager on this build")
		return
	var fake = _fake_undo()
	root.add_paint_layer()
	var layer = root.paint_layers.get_active_layer()
	assert_not_null(layer, "Add Paint Layer must produce an active layer")
	layer.set_cell(Vector2i(0, 0), true)
	layer.set_cell(Vector2i(1, 0), true)
	var layers_before: int = root.paint_layers.layers.size()

	_commit(fake, root, "Remove Paint Layer", "remove_active_paint_layer", [], false)
	assert_eq(root.paint_layers.layers.size(), layers_before - 1, "Remove must take the layer out")

	fake.undo()
	assert_eq(root.paint_layers.layers.size(), layers_before, "Undo must bring the layer back")
	var back = root.paint_layers.get_active_layer()
	assert_not_null(back)
	assert_true(back.get_cell(Vector2i(0, 0)), "Undo must bring back what was painted into it")


# ---------------------------------------------------------------------------
# Which wrapper each button reaches for
# ---------------------------------------------------------------------------


func test_every_level_changing_dock_command_registers_an_undo_step() -> void:
	# The handler, and the level method it must no longer call straight.
	var commands := {
		"on_visgroup_add": "create_visgroup",
		"on_visgroup_delete": "remove_visgroup",
		"on_visgroup_add_selection": "add_selection_to_visgroup",
		"on_visgroup_remove_selection": "remove_selection_from_visgroup",
		"on_group_selection": "group_selection",
		"on_ungroup_selection": "ungroup_nodes",
		"on_create_entity": "add_entity",
		"on_io_add": "add_entity_output",
		"on_paint_layer_remove": "remove_active_paint_layer",
		"on_heightmap_generate": "generate_heightmap_noise",
		"on_heightmap_import_selected": "import_heightmap",
		"on_material_library_load_selected": "load_material_library",
		"on_terrain_slot_texture_selected": "set_terrain_slot_texture",
		"on_terrain_slot_scale_changed": "set_terrain_slot_uv_scale",
	}
	for function_name in commands:
		var body := _body(function_name)
		assert_ne(body, "", "%s must exist in a handler source" % function_name)
		assert_true(
			body.contains("_commit_state_action"),
			"%s changes the level and must register an undo step" % function_name
		)
		assert_false(
			body.contains("dock.level_root.%s(" % commands[function_name]),
			(
				"%s must not call level_root.%s() outside the undo wrapper"
				% [function_name, commands[function_name]]
			)
		)


func test_load_material_library_undo_brings_the_old_palette_back() -> void:
	var root := _fresh_root()
	var fake = _fake_undo()
	root.add_material_to_palette(StandardMaterial3D.new())
	root.add_material_to_palette(StandardMaterial3D.new())
	var before: int = root.material_manager.materials.size()
	assert_eq(before, 2, "Two materials to lose")

	var library := "user://hf_test_library.json"
	var file := FileAccess.open(library, FileAccess.WRITE)
	file.store_string(JSON.stringify({"materials": []}))
	file.close()

	_commit(fake, root, "Load Material Library", "load_material_library", [library], false)
	assert_eq(root.material_manager.materials.size(), 0, "The load replaces the whole palette")

	fake.undo()
	assert_eq(root.material_manager.materials.size(), before, "Undo must bring the palette back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(library))


func test_a_terrain_slot_texture_undo_puts_the_old_slot_back() -> void:
	var root := _fresh_root()
	if not root.paint_layers:
		pass_test("no paint layer manager on this build")
		return
	var fake = _fake_undo()
	var layer = root.paint_layers.get_active_layer()
	assert_not_null(layer, "A level comes up with an active paint layer")
	layer.set_terrain_slot_texture(1, "res://old.tres")

	_commit(
		fake,
		root,
		"Set Terrain Slot Texture",
		"set_terrain_slot_texture",
		[1, "res://new.tres"],
		false
	)
	assert_eq(
		root.paint_layers.get_active_layer().terrain_slot_paths[1],
		"res://new.tres",
		"The command points the slot at the new texture"
	)

	fake.undo()
	assert_eq(
		root.paint_layers.get_active_layer().terrain_slot_paths[1],
		"res://old.tres",
		"Undo must put the old one back"
	)


func test_a_terrain_slot_refuses_an_index_it_does_not_have() -> void:
	var root := _fresh_root()
	if not root.paint_layers:
		pass_test("no paint layer manager on this build")
		return
	var layer = root.paint_layers.get_active_layer()
	assert_false(layer.set_terrain_slot_texture(9, "res://x.tres"), "Slot 9 is not a slot")
	assert_false(layer.set_terrain_slot_uv_scale(-1, 2.0), "Neither is slot -1")
	assert_false(layer.set_terrain_slot_uv_scale(0, NAN), "A scale has to be a number")


func test_commands_holding_live_nodes_ask_for_an_absolute_redo() -> void:
	# Anything passing dock._selection_nodes or an entity into the wrapper: the
	# redo cannot be a re-call, because the undo freed what it would be handed.
	for function_name in [
		"on_visgroup_add_selection",
		"on_visgroup_remove_selection",
		"on_group_selection",
		"on_ungroup_selection",
		"on_create_entity",
		"on_io_add",
	]:
		var flat := _body(function_name).replace("\n", " ").replace("\t", "")
		while flat.contains("  "):
			flat = flat.replace("  ", " ")
		assert_true(
			flat.contains(", true )") or flat.contains(", true)"),
			"%s passes a live node and must commit with absolute_redo" % function_name
		)


func test_convert_to_heightmap_registers_the_work_it_already_did() -> void:
	var body := _body("on_heightmap_convert")
	assert_true(
		body.contains("capture_full_state()"),
		"Convert builds the layer itself, so it must take a before state"
	)
	assert_true(
		body.contains("_commit_done_state_action"),
		"Convert must register the work it already did as one step"
	)


func test_wiring_panel_announces_a_change_before_it_makes_one() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/ui/hf_io_wiring_panel.gd")
	var wire := source.find("func _on_wire_pressed")
	var announce := source.find("will_change.emit", wire)
	var mutate := source.find("_entity_system.add_entity_output", wire)
	assert_true(announce > wire and announce < mutate, "The panel must announce before it wires")

	var preset := source.find("func _on_preset_apply")
	assert_true(
		source.find("change_abandoned.emit", preset) > preset,
		"A preset that applies nothing must drop the before state it asked for"
	)


func test_add_selection_to_visgroup_leaves_the_row_it_used_selected() -> void:
	var root := _fresh_root()
	var dock := preload("res://addons/hammerforge/dock.tscn").instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	var brush := _box(root, "undo_brush", Vector3.ZERO)
	root.create_visgroup("Lights")
	HFDockVisgroupHandler.refresh_visgroup_ui(dock)
	dock.visgroup_list.select(0)
	dock._selection_nodes = [brush]

	dock._on_visgroup_add_selection()
	assert_eq(
		Array(brush.get_meta("visgroups", PackedStringArray())),
		["Lights"],
		"Add Sel must add the selection to the highlighted visgroup"
	)
	assert_false(
		dock.visgroup_list.get_selected_items().is_empty(),
		"Add Sel must leave the row selected so the next press is not a no-op"
	)
	assert_eq(
		HFDockVisgroupHandler.get_selected_visgroup_name(dock),
		"Lights",
		"The same visgroup must still be the one a second Add Sel would use"
	)


# ---------------------------------------------------------------------------
# Undo steps opened outside the helper (#1108)
# ---------------------------------------------------------------------------

## Every function outside `HFUndoHelper` that opens an undo step itself, and why
## its step survives `restore_state()`: it redoes from a snapshot or from values,
## or it adds a node of its own that a restore never frees. A new one is read and
## added here with its reason, so a step that holds a level node is seen before it
## ships. Keys are the file under the addon, then the function.
const DIRECT_UNDO_STEPS := {
	"dock.gd::_commit_done_state_action": "full state snapshots both ways",
	"dock.gd::_commit_precomputed_state_action": "state and bake snapshots both ways",
	"dock_brush_handler.gd::on_disp_sew": "state snapshots both ways",
	"dock_manage_handler.gd::record_bake_profile": "bake option values, no node",
	"dock_manage_handler.gd::_record_spawn_step": "state snapshots both ways",
	"dock_paint_handler.gd::_commit_scatter_node":
	"adds its own node, held by the step, under a parent no restore frees",
	"dock_visgroup_handler.gd::record_cordon_edit": "cordon values, no node",
	"hf_decal_tool.gd::_place_decal": "state snapshots both ways",
	"hf_level_factory.gd::create_starter_undoable": "adds a new level; restores work inside one",
	"hf_path_tool.gd::_build_path": "state snapshots both ways",
	"hf_polygon_tool.gd::_finalize_brush": "state snapshots both ways",
	"plugin.gd::_create_level_root": "adds a new level; restores work inside one",
	"plugin_drop_handler.gd::handle_prefab_drop": "state snapshots both ways",
	"plugin_paint_input.gd::commit_floor_paint_undo": "state snapshots both ways",
	"plugin_prefab_commands.gd::_commit_state_change": "state snapshots both ways",
	"plugin_vertex_ops.gd::commit_op": "faces by brush id, looked up when it runs",
}

const ADDON := "res://addons/hammerforge/"


func _scripts_under(dir_path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append(dir_path.path_join(file_name))
	for sub in dir.get_directories():
		found.append_array(_scripts_under(dir_path.path_join(sub)))
	return found


## "file::function" for each `create_action(` outside comments, by the top level
## function it sits in.
func _direct_undo_steps() -> Dictionary:
	var steps := {}
	for path in _scripts_under(ADDON.trim_suffix("/")):
		if path.ends_with("/undo_helper.gd"):
			continue
		var function_name := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("func ") or line.begins_with("static func "):
				function_name = line.get_slice("func ", 1).get_slice("(", 0)
			if line.strip_edges().begins_with("#") or not line.contains("create_action("):
				continue
			steps["%s::%s" % [path.trim_prefix(ADDON), function_name]] = true
	return steps


func test_every_undo_step_opened_outside_the_helper_has_been_read() -> void:
	var steps := _direct_undo_steps()
	assert_gt(steps.size(), 0, "the scan found the steps")
	for key in steps:
		assert_true(
			DIRECT_UNDO_STEPS.has(key),
			(
				"%s opens an undo step itself. Check it holds no level node a restore frees, then add it with its reason"
				% key
			)
		)
	for key in DIRECT_UNDO_STEPS:
		assert_true(steps.has(key), "%s no longer opens a step; take it off the list" % key)


## The editor's undo manager as far as a spawn step uses it, with a history to
## step back through more than one action and forward again. Like Godot's own, it
## skips a call whose object has been freed rather than failing.
class SteppingUndoRedo:
	extends RefCounted

	var _steps: Array = []
	var _done := 0
	var _open: Dictionary = {}

	func create_action(
		name: String, _merge_mode: int = 0, _context = null, _backward: bool = false
	) -> void:
		_open = {"name": name, "do": [], "undo": []}

	func add_do_method(target: Object, method: StringName, a = null) -> void:
		_open["do"].append({"target": target, "method": method, "args": [] if a == null else [a]})

	func add_undo_method(target: Object, method: StringName, a = null) -> void:
		_open["undo"].append({"target": target, "method": method, "args": [] if a == null else [a]})

	func add_do_property(target: Object, property: StringName, value) -> void:
		_open["do"].append({"target": target, "property": property, "value": value})

	func add_undo_property(target: Object, property: StringName, value) -> void:
		_open["undo"].append({"target": target, "property": property, "value": value})

	func commit_action(execute: bool = true) -> void:
		if execute:
			_run(_open["do"])
		_steps.resize(_done)
		_steps.append(_open)
		_done += 1
		_open = {}

	func has_undo() -> bool:
		return _done > 0

	func has_redo() -> bool:
		return _done < _steps.size()

	func undo() -> void:
		_done -= 1
		_run(_steps[_done]["undo"])

	func redo() -> void:
		_run(_steps[_done]["do"])
		_done += 1

	func _run(calls: Array) -> void:
		for each in calls:
			var target = each["target"]
			if not is_instance_valid(target):
				continue
			if each.has("property"):
				target.set(each["property"], each["value"])
			else:
				target.callv(each["method"], each["args"])


class SpawnDock:
	extends RefCounted

	var undo_redo := SteppingUndoRedo.new()
	var level_root: LevelRoot


func test_a_spawn_fix_redoes_after_the_spawn_was_freed_and_built_again() -> void:
	var root := _fresh_root()
	var dock := SpawnDock.new()
	dock.level_root = root
	var before_create: Dictionary = root.state_system.capture_state(true)
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	var made_at := spawn.global_position
	HFDockManageHandler.record_spawn_create_undo(dock, before_create)
	var before_move: Dictionary = root.state_system.capture_state(true)
	var fixed_at := made_at + Vector3(3, 0, 0)
	spawn.global_position = fixed_at
	HFDockManageHandler.record_spawn_move_undo(dock, before_move)
	# Back past the create and forward again: the create's undo frees the spawn and
	# its redo builds a new one, so a step holding the first node has nothing left.
	dock.undo_redo.undo()
	dock.undo_redo.undo()
	assert_null(root.spawn_system.get_active_spawn(), "the create is undone")
	dock.undo_redo.redo()
	dock.undo_redo.redo()
	var again: Node3D = root.spawn_system.get_active_spawn()
	assert_not_null(again)
	if again != null:
		assert_eq(again.global_position, fixed_at, "the fix redoes on the spawn there now")
	dock.undo_redo.undo()
	again = root.spawn_system.get_active_spawn()
	if again != null:
		assert_eq(again.global_position, made_at, "and undoes on it")
