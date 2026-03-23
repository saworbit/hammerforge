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


func test_activate_same_tool_twice_no_op():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	tool.activated = false
	registry.activate_tool(100, null, null)
	assert_false(tool.activated, "Should not re-activate same tool")


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


func test_activate_unknown_id_deactivates_current():
	var tool = MockTool.new(100)
	registry.register_tool(tool)
	registry.activate_tool(100, null, null)
	assert_true(tool.activated)
	# Activating an ID that doesn't exist deactivates the current tool.
	registry.activate_tool(-1, null, null)
	assert_true(tool.deactivated)
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
