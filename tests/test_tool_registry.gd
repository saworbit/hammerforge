extends GutTest

const HFEditorToolType = preload("res://addons/hammerforge/hf_editor_tool.gd")
const HFToolRegistryType = preload("res://addons/hammerforge/hf_tool_registry.gd")

var registry: HFToolRegistryType


func before_each():
	registry = HFToolRegistryType.new()


func after_each():
	registry = null


# -- Mock tool for testing --------------------------------------------------


class MockTool:
	extends HFEditorTool

	var _id: int
	var _key: int
	var activated := false
	var deactivated := false
	var last_event: InputEvent = null
	var recovered_pointer := false
	var cancelled_pointer := false

	func _init(id: int = 100, key: int = 0):
		_id = id
		_key = key

	func tool_id() -> int:
		return _id

	func tool_name() -> String:
		return "Mock %d" % _id

	func tool_shortcut_key() -> int:
		return _key

	func activate(p_root: Node3D, p_camera: Camera3D) -> void:
		super.activate(p_root, p_camera)
		activated = true

	func deactivate() -> void:
		super.deactivate()
		deactivated = true

	func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
		last_event = event
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	func handle_keyboard(event: InputEventKey) -> int:
		last_event = event
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	func recover_lost_pointer_capture() -> bool:
		recovered_pointer = true
		return true

	func cancel_pointer_capture() -> bool:
		cancelled_pointer = true
		return true


# -- Tests -------------------------------------------------------------------


func test_register_and_retrieve():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	assert_eq(registry.get_tool_by_id(100), tool)
	assert_eq(registry.get_all_tools().size(), 1)


func test_register_null_ignored():
	registry.register_tool(null)
	assert_eq(registry.get_all_tools().size(), 0)


func test_register_duplicate_id_ignored():
	var t1 = MockTool.new(100)
	var t2 = MockTool.new(100)
	registry.register_tool(t1)
	registry.register_tool(t2)
	assert_eq(registry.get_all_tools().size(), 1)
	assert_eq(registry.get_tool_by_id(100), t1)


func test_unregister():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.unregister_tool(100)
	assert_eq(registry.get_all_tools().size(), 0)
	assert_null(registry.get_tool_by_id(100))


func test_unregister_active_deactivates():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	registry.unregister_tool(100)
	assert_true(tool.deactivated)
	assert_null(registry.get_active_tool())


func test_unregister_nonexistent_no_crash():
	registry.unregister_tool(999)
	assert_eq(registry.get_all_tools().size(), 0)


func test_activate_deactivate():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	assert_true(tool.activated)
	assert_true(tool.is_active)
	assert_eq(registry.get_active_tool(), tool)


func test_activate_switches_deactivates_previous():
	var t1 = MockTool.new(100)
	var t2 = MockTool.new(101)
	registry.register_tool(t1)
	registry.register_tool(t2)
	registry.activate_tool(100, null, null)
	registry.activate_tool(101, null, null)
	assert_true(t1.deactivated)
	assert_false(t1.is_active)
	assert_true(t2.activated)
	assert_true(t2.is_active)


func test_activate_same_tool_toggles_off():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	assert_true(tool.is_active, "Tool should be active after first activation")
	tool.activated = false
	registry.activate_tool(100, null, null)
	assert_false(tool.activated, "Should not re-activate same tool")
	assert_true(tool.deactivated, "Tool should be deactivated on second press")
	assert_false(tool.is_active, "Tool should no longer be active")
	assert_eq(registry.get_active_tool(), null, "Registry should have no active tool")


func test_dispatch_input_routes_to_active_external():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	var ev = InputEventMouseButton.new()
	var result = registry.dispatch_input(ev, null, Vector2.ZERO)
	assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool.last_event, ev)


func test_dispatch_input_passes_for_builtin():
	var tool = MockTool.new(1)
	registry.register_tool(tool)
	registry.activate_tool(1, null, null)
	var ev = InputEventMouseButton.new()
	var result = registry.dispatch_input(ev, null, Vector2.ZERO)
	assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_PASS)


func test_dispatch_keyboard_routes_to_active_external():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	var ev = InputEventKey.new()
	var result = registry.dispatch_keyboard(ev)
	assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool.last_event, ev)


func test_dispatch_keyboard_passes_for_builtin():
	var tool = MockTool.new(2)
	registry.register_tool(tool)
	registry.activate_tool(2, null, null)
	var ev = InputEventKey.new()
	var result = registry.dispatch_keyboard(ev)
	assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_PASS)


func test_pointer_recovery_routes_to_active_external_tool_without_deactivating_it():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	assert_true(registry.recover_active_pointer_capture())
	assert_true(tool.recovered_pointer)
	assert_true(registry.cancel_active_pointer_capture())
	assert_true(tool.cancelled_pointer)
	assert_true(tool.is_active)
	assert_eq(registry.get_active_tool(), tool)


func test_pointer_recovery_ignores_builtin_and_inactive_tools():
	assert_false(registry.recover_active_pointer_capture())
	assert_false(registry.cancel_active_pointer_capture())
	var tool = MockTool.new(1)
	registry.register_tool(tool)
	registry.activate_tool(1, null, null)
	assert_false(registry.recover_active_pointer_capture())
	assert_false(registry.cancel_active_pointer_capture())


func test_check_shortcut_finds_external():
	var tool = MockTool.new(100, KEY_F5)
	registry.register_tool(tool)
	assert_eq(registry.check_shortcut(KEY_F5), 100)


func test_check_shortcut_ignores_builtin():
	var tool = MockTool.new(1, KEY_D)
	registry.register_tool(tool)
	assert_eq(registry.check_shortcut(KEY_D), -1)


func test_check_shortcut_no_match():
	var tool = MockTool.new(100, KEY_F5)
	registry.register_tool(tool)
	assert_eq(registry.check_shortcut(KEY_F6), -1)


func test_get_external_tools():
	var t_builtin = MockTool.new(1)
	var t_ext = MockTool.new(100)
	registry.register_tool(t_builtin)
	registry.register_tool(t_ext)
	var ext = registry.get_external_tools()
	assert_eq(ext.size(), 1)
	assert_eq(ext[0], t_ext)


func test_load_external_tools_missing_dir_no_crash():
	registry.load_external_tools("res://nonexistent_tools_dir/")
	assert_eq(registry.get_all_tools().size(), 0)


func test_dispatch_no_active_tool_passes():
	var ev = InputEventMouseButton.new()
	var result = registry.dispatch_input(ev, null, Vector2.ZERO)
	assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_PASS)


func test_deactivate_current_clears_active():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	assert_eq(registry.get_active_tool(), tool)
	registry.deactivate_current()
	assert_null(registry.get_active_tool())
	assert_true(tool.deactivated)
	assert_false(tool.is_active)


func test_deactivate_current_no_op_when_empty():
	registry.deactivate_current()
	assert_null(registry.get_active_tool())


func test_has_active_external_tool():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	assert_false(registry.has_active_external_tool())
	registry.activate_tool(100, null, null)
	assert_true(registry.has_active_external_tool())
	registry.deactivate_current()
	assert_false(registry.has_active_external_tool())


func test_has_active_external_tool_false_for_builtin():
	var tool = MockTool.new(1)
	registry.register_tool(tool)
	registry.activate_tool(1, null, null)
	assert_false(registry.has_active_external_tool())


## An id that is not registered is a tool whose script failed to load, or a
## button wired to an id that has since changed. Turning off the tool in hand and
## saying nothing reads as the editor losing its place rather than as a button
## that does not work.
func test_activate_unknown_id_leaves_the_active_tool_alone():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	assert_true(tool.activated)

	registry.activate_tool(-1, null, null)

	assert_false(tool.deactivated, "the tool the mapper was using stays on")
	assert_eq(registry.get_active_tool(), tool)


func test_activate_unknown_id_with_nothing_active_activates_nothing():
	registry.activate_tool(999, null, null)
	assert_null(registry.get_active_tool())


func test_external_tool_stays_active_across_dispatch():
	# Simulates the bug where external tools were deactivated per-frame.
	# After activation, dispatch should still route to the external tool.
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	# Multiple dispatch calls should keep the tool active.
	for i in range(5):
		var ev = InputEventMouseButton.new()
		var result = registry.dispatch_input(ev, null, Vector2.ZERO)
		assert_eq(result, EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_true(registry.has_active_external_tool())
	assert_eq(registry.get_active_tool(), tool)


# -- load_external_tools constructs only what it is going to keep -------------


## A directory the class documents as an extension point. Writing a script into
## it that is not a tool used to construct it anyway: a Node subclass leaked for
## the life of the editor session, and an `_init()` with arguments or side
## effects got run.
func _write_tool_dir(files: Dictionary) -> String:
	var dir_path := "user://vibe_tools_%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir_path)
	for file_name in files:
		var f := FileAccess.open(dir_path.path_join(str(file_name)), FileAccess.WRITE)
		f.store_string(str(files[file_name]))
		f.close()
	return dir_path


func _remove_tool_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		DirAccess.remove_absolute(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func test_a_non_tool_node_script_in_the_directory_is_not_constructed():
	var dir_path := _write_tool_dir({"not_a_tool.gd": "@tool\nextends Node3D\n"})
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	registry.load_external_tools(dir_path)

	assert_eq(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		before,
		"a script that is not a tool left an orphan behind"
	)
	assert_eq(registry.get_all_tools().size(), 0)
	_remove_tool_dir(dir_path)


func test_a_script_whose_init_takes_arguments_is_not_constructed():
	var dir_path := _write_tool_dir(
		{"needs_args.gd": "@tool\nextends RefCounted\nfunc _init(required: int):\n\tpass\n"}
	)

	registry.load_external_tools(dir_path)

	assert_eq(registry.get_all_tools().size(), 0, "and it did not take the scan down with it")
	_remove_tool_dir(dir_path)


func test_a_real_tool_in_the_directory_is_still_registered():
	var source := (
		'@tool\nextends "res://addons/hammerforge/hf_editor_tool.gd"\n'
		+ "func tool_id() -> int:\n\treturn 101\n"
		+ 'func tool_name() -> String:\n\treturn "Good"\n'
	)
	var dir_path := _write_tool_dir({"good_tool.gd": source})

	registry.load_external_tools(dir_path)

	assert_eq(registry.get_all_tools().size(), 1, "the extension point still works")
	assert_eq(registry.get_tool_by_id(101).tool_name(), "Good")
	_remove_tool_dir(dir_path)


# -- An enum setting is held to its own options (#509) ------------------------


class EnumTool:
	extends HFEditorTool

	func tool_id() -> int:
		return 120

	func get_settings_schema() -> Array:
		return [
			{
				"name": "mode",
				"type": "enum",
				"label": "Mode",
				"default": 0,
				"options": PackedStringArray(["A", "B"]),
			},
		]


func test_an_enum_setting_refuses_an_index_its_options_do_not_have():
	var tool = EnumTool.new()

	tool.set_setting("mode", 7)

	assert_eq(tool.get_setting("mode"), 0, "an OptionButton has no item 7 to show")


func test_an_enum_setting_refuses_a_negative_index():
	var tool = EnumTool.new()
	tool.set_setting("mode", 1)

	tool.set_setting("mode", -1)

	assert_eq(tool.get_setting("mode"), 1, "the last legal value is kept")


func test_an_enum_setting_takes_every_index_its_options_have():
	var tool = EnumTool.new()
	for index in 2:
		tool.set_setting("mode", index)
		assert_eq(tool.get_setting("mode"), index)
