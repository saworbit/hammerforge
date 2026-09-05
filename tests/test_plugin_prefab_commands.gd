extends GutTest
## Boundary coverage for the extracted prefab selection commands.

const HFPluginPrefabCommands = preload("res://addons/hammerforge/plugin_prefab_commands.gd")


class FakeStateSystem:
	extends RefCounted

	var captures := 0
	var restored: Array = []

	func capture_state(_full: bool = false) -> Dictionary:
		captures += 1
		return {"seq": captures}

	func restore_state(state: Dictionary) -> void:
		restored.append(state)


class FakePrefabSystem:
	extends RefCounted

	var suggested_name := "Crate"
	var save_path := "res://prefabs/crate.tres"
	var next_variant := ""
	var push_ok := true
	var propagate_count := 0
	var saved_calls: Array = []
	var pushed: Array = []
	var propagated: Array = []
	var cycled: Array = []

	func suggest_prefab_name(_brushes: Array, _entities: Array) -> String:
		return suggested_name

	func quick_save_prefab(brushes: Array, entities: Array, name: String, linked: bool) -> String:
		saved_calls.append(
			{"brushes": brushes.size(), "entities": entities.size(), "name": name, "linked": linked}
		)
		return save_path

	func cycle_variant(iid: String) -> String:
		cycled.append(iid)
		return next_variant

	func push_instance_to_source(iid: String) -> bool:
		pushed.append(iid)
		return push_ok

	func propagate_from_source(source: String) -> int:
		propagated.append(source)
		return propagate_count


class FakeRoot:
	extends Node3D

	var prefab_system := FakePrefabSystem.new()
	var state_system := FakeStateSystem.new()
	var brush_nodes: Array = []
	var entity_nodes: Array = []

	func is_brush_node(node) -> bool:
		return brush_nodes.has(node)

	func is_entity_node(node) -> bool:
		return entity_nodes.has(node)


class FakePrefabLibrary:
	extends RefCounted

	var refreshes := 0

	func on_prefab_saved() -> void:
		refreshes += 1


class FakeDock:
	extends RefCounted

	var toasts: Array = []
	var _prefab_library := FakePrefabLibrary.new()

	func show_toast(message: String, level: int = 0) -> void:
		toasts.append({"message": message, "level": level})

	func last_toast() -> Dictionary:
		return toasts[-1] if not toasts.is_empty() else {}


class FakeUndoRedo:
	extends RefCounted

	var actions: Array = []
	var do_args: Array = []
	var undo_args: Array = []
	var commits := 0

	func create_action(name: String, _mode: int = 0, _obj = null, _backward: bool = false) -> void:
		actions.append(name)

	func add_do_method(_target, _method: String, arg) -> void:
		do_args.append(arg)

	func add_undo_method(_target, _method: String, arg) -> void:
		undo_args.append(arg)

	func commit_action(_execute: bool = true) -> void:
		commits += 1


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var hf_selection: Array = []
	var undo_redo_manager = null
	var hud_updates := 0

	func _update_hud_context() -> void:
		hud_updates += 1


var plugin: FakePlugin
var root: FakeRoot


func before_each():
	plugin = FakePlugin.new()
	root = FakeRoot.new()
	add_child_autoqfree(root)


func after_each():
	plugin = null
	root = null


func _make_node(metas: Dictionary = {}) -> Node3D:
	var node := Node3D.new()
	for key in metas:
		node.set_meta(str(key), metas[key])
	root.add_child(node)
	return node


func _instance_node() -> Node3D:
	return _make_node({"hf_prefab_instance": "iid_1", "hf_prefab_source": "res://p/crate.tres"})


# ---------------------------------------------------------------------------
# Reading the selection
# ---------------------------------------------------------------------------


func test_empty_selection_is_silent():
	var value := HFPluginPrefabCommands.selected_meta(plugin, "hf_prefab_instance")
	assert_eq(value, "")
	assert_eq(plugin.dock.toasts.size(), 0, "Nothing selected is not worth warning about")


func test_freed_selection_entry_is_silent():
	var node := Node3D.new()
	plugin.hf_selection = [node]
	node.free()

	var value := HFPluginPrefabCommands.selected_meta(plugin, "hf_prefab_instance")

	assert_eq(value, "")
	assert_eq(plugin.dock.toasts.size(), 0, "A stale selection entry should not warn")


func test_non_prefab_node_warns():
	plugin.hf_selection = [_make_node()]

	var value := HFPluginPrefabCommands.selected_meta(plugin, "hf_prefab_instance")

	assert_eq(value, "")
	assert_eq(plugin.dock.last_toast().get("message"), "Not a prefab instance")
	assert_eq(plugin.dock.last_toast().get("level"), 1)


func test_prefab_instance_returns_its_id_without_warning():
	plugin.hf_selection = [_instance_node()]

	assert_eq(HFPluginPrefabCommands.selected_meta(plugin, "hf_prefab_instance"), "iid_1")
	assert_eq(plugin.dock.toasts.size(), 0)


# ---------------------------------------------------------------------------
# Quick save
# ---------------------------------------------------------------------------


func test_quick_save_ignores_a_selection_with_nothing_savable():
	plugin.hf_selection = [_make_node()]

	HFPluginPrefabCommands.quick_save(plugin, root, false)

	assert_eq(root.prefab_system.saved_calls.size(), 0)
	assert_eq(plugin.dock.toasts.size(), 0)


func test_quick_save_splits_brushes_from_entities():
	var brush := _make_node()
	var entity := _make_node()
	root.brush_nodes = [brush]
	root.entity_nodes = [entity]
	plugin.hf_selection = [brush, entity]

	HFPluginPrefabCommands.quick_save(plugin, root, false)

	assert_eq(root.prefab_system.saved_calls.size(), 1)
	assert_eq(root.prefab_system.saved_calls[0]["brushes"], 1)
	assert_eq(root.prefab_system.saved_calls[0]["entities"], 1)
	assert_eq(plugin.dock._prefab_library.refreshes, 1)
	assert_eq(plugin.dock.last_toast().get("message"), "Saved prefab: Crate")


func test_quick_save_marks_a_linked_prefab_in_the_toast():
	var brush := _make_node()
	root.brush_nodes = [brush]
	plugin.hf_selection = [brush]

	HFPluginPrefabCommands.quick_save(plugin, root, true)

	assert_true(root.prefab_system.saved_calls[0]["linked"])
	assert_eq(plugin.dock.last_toast().get("message"), "Saved prefab: Crate (linked)")


func test_quick_save_that_writes_nothing_does_not_claim_success():
	var brush := _make_node()
	root.brush_nodes = [brush]
	plugin.hf_selection = [brush]
	root.prefab_system.save_path = ""

	HFPluginPrefabCommands.quick_save(plugin, root, false)

	assert_eq(plugin.dock.toasts.size(), 0)
	assert_eq(plugin.dock._prefab_library.refreshes, 0)


# ---------------------------------------------------------------------------
# Cycle variant
# ---------------------------------------------------------------------------


func test_cycle_variant_undoes_to_the_state_captured_before_the_cycle():
	plugin.hf_selection = [_instance_node()]
	plugin.undo_redo_manager = FakeUndoRedo.new()
	root.prefab_system.next_variant = "Damaged"

	HFPluginPrefabCommands.cycle_variant(plugin, root)

	var undo_redo: FakeUndoRedo = plugin.undo_redo_manager
	assert_eq(undo_redo.actions, ["Cycle Prefab Variant"])
	assert_eq(undo_redo.undo_args[0], {"seq": 1}, "Undo restores the pre-cycle capture")
	assert_eq(undo_redo.do_args[0], {"seq": 2}, "Redo restores the state after cycling")
	assert_eq(undo_redo.commits, 1)
	assert_eq(plugin.hud_updates, 1)


func test_cycle_variant_with_no_other_variant_records_nothing():
	plugin.hf_selection = [_instance_node()]
	plugin.undo_redo_manager = FakeUndoRedo.new()
	root.prefab_system.next_variant = ""

	HFPluginPrefabCommands.cycle_variant(plugin, root)

	var undo_redo: FakeUndoRedo = plugin.undo_redo_manager
	assert_eq(undo_redo.actions.size(), 0, "Nothing changed, so nothing goes on the undo stack")
	assert_eq(plugin.dock.toasts.size(), 0)


func test_cycle_variant_still_applies_without_an_undo_manager():
	plugin.hf_selection = [_instance_node()]
	root.prefab_system.next_variant = "Damaged"

	HFPluginPrefabCommands.cycle_variant(plugin, root)

	assert_eq(root.prefab_system.cycled, ["iid_1"])
	assert_eq(plugin.dock.last_toast().get("message"), "Variant: Damaged")


# ---------------------------------------------------------------------------
# Push to source
# ---------------------------------------------------------------------------


func test_push_to_source_refreshes_the_library_on_success():
	plugin.hf_selection = [_instance_node()]

	HFPluginPrefabCommands.push_to_source(plugin, root)

	assert_eq(root.prefab_system.pushed, ["iid_1"])
	assert_eq(plugin.dock.last_toast().get("message"), "Pushed changes to prefab source")
	assert_eq(plugin.dock._prefab_library.refreshes, 1)


func test_failed_push_warns_and_leaves_the_library_alone():
	plugin.hf_selection = [_instance_node()]
	root.prefab_system.push_ok = false

	HFPluginPrefabCommands.push_to_source(plugin, root)

	assert_eq(plugin.dock.last_toast().get("message"), "Failed to push to source")
	assert_eq(plugin.dock.last_toast().get("level"), 1)
	assert_eq(plugin.dock._prefab_library.refreshes, 0, "A failed push has nothing to show")


# ---------------------------------------------------------------------------
# Propagate
# ---------------------------------------------------------------------------


func test_propagate_undoes_to_the_state_captured_before_propagating():
	plugin.hf_selection = [_instance_node()]
	plugin.undo_redo_manager = FakeUndoRedo.new()
	root.prefab_system.propagate_count = 3

	HFPluginPrefabCommands.propagate(plugin, root)

	var undo_redo: FakeUndoRedo = plugin.undo_redo_manager
	assert_eq(undo_redo.actions, ["Propagate Prefab"])
	assert_eq(undo_redo.undo_args[0], {"seq": 1}, "Undo restores the pre-propagate capture")
	assert_eq(plugin.dock.last_toast().get("message"), "Propagated to 3 linked instances")


func test_propagate_reads_the_source_meta_not_the_instance_id():
	plugin.hf_selection = [_instance_node()]
	root.prefab_system.propagate_count = 1

	HFPluginPrefabCommands.propagate(plugin, root)

	assert_eq(root.prefab_system.propagated, ["res://p/crate.tres"])
	assert_eq(plugin.dock.last_toast().get("message"), "Propagated to 1 linked instance")


func test_propagate_with_no_linked_instances_records_nothing():
	plugin.hf_selection = [_instance_node()]
	plugin.undo_redo_manager = FakeUndoRedo.new()
	root.prefab_system.propagate_count = 0

	HFPluginPrefabCommands.propagate(plugin, root)

	var undo_redo: FakeUndoRedo = plugin.undo_redo_manager
	assert_eq(undo_redo.actions.size(), 0)
	assert_eq(plugin.dock.last_toast().get("message"), "No linked instances to propagate")
	assert_eq(plugin.dock.last_toast().get("level"), 1)
