extends GutTest
## Floor Paint modifier, preview, feedback, and camera-ownership regressions.

const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const HFPaintLayerManager = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")
const HFStroke = preload("res://addons/hammerforge/paint/hf_stroke.gd")
const HFPluginPaintInput = preload("res://addons/hammerforge/plugin_paint_input.gd")


class FakeUndo:
	extends RefCounted

	var actions: Array = []
	var do_calls: Array = []
	var undo_calls: Array = []

	func create_action(name: String, _merge = 0, _context = null, _backward = false) -> void:
		actions.append(name)

	func add_do_method(object, method: String, state: Dictionary) -> void:
		do_calls.append([object, method, state])

	func add_undo_method(object, method: String, state: Dictionary) -> void:
		undo_calls.append([object, method, state])

	func commit_action(_execute = true) -> void:
		pass


class FakePaintTool:
	extends RefCounted

	var changed := 0
	var active := true
	var cancels := 0

	func get_last_committed_cell_count() -> int:
		return changed

	func is_stroke_active() -> bool:
		return active

	func cancel_stroke() -> bool:
		cancels += 1
		active = false
		return true


class FakePaintRoot:
	extends Node

	var marker := 1
	var restored: Array = []
	var paint_tool := FakePaintTool.new()
	var paint_system = null

	func capture_state() -> Dictionary:
		return {"marker": marker}

	func restore_state(state: Dictionary) -> void:
		restored.append(state.duplicate(true))
		marker = int(state.get("marker", marker))


class FakePlugin:
	extends RefCounted

	var undo_redo_manager := FakeUndo.new()
	var _floor_paint_pre_state: Dictionary = {}
	var history: Array = []
	var hud_updates := 0

	func _record_history(action: String) -> void:
		history.append(action)

	func _update_hud_context() -> void:
		hud_updates += 1

var manager: HFPaintLayerManager
var layer
var tool: HFPaintTool


func before_each():
	manager = HFPaintLayerManager.new()
	add_child_autoqfree(manager)
	layer = manager.create_layer(&"floor", 0.0)
	tool = HFPaintTool.new()
	tool.layer_manager = manager
	add_child_autoqfree(tool)


func after_each():
	manager = null
	layer = null
	tool = null


func _begin_test_stroke(erasing: bool = false) -> void:
	tool._active_stroke = HFStroke.new()
	tool._painting = true
	tool._stroke_erasing = erasing
	tool._start_cell = Vector2i(2, 3)
	tool._last_cell = tool._start_cell


func test_alt_modifier_temporarily_erases_without_changing_the_selected_tool():
	layer.set_cell(Vector2i(4, 5), true)
	layer.consume_dirty_chunks()
	tool.tool = HFStroke.Tool.PAINT
	_begin_test_stroke(true)

	tool._stamp_cell(Vector2i(4, 5))

	assert_false(layer.get_cell(Vector2i(4, 5)))
	assert_eq(tool.tool, HFStroke.Tool.PAINT, "Alt is a temporary action, not a mode switch")


func test_shift_axis_lock_chooses_once_and_stays_stable_for_the_stroke():
	_begin_test_stroke()

	assert_eq(tool._apply_axis_lock(Vector2i(8, 5), true), Vector2i(8, 3))
	assert_eq(tool._apply_axis_lock(Vector2i(4, 12), true), Vector2i(4, 3))
	assert_eq(tool._stroke_axis, 1, "Later diagonal jitter must not flip the chosen axis")


func test_ctrl_eyedropper_picks_the_cell_material_without_starting_a_stroke():
	layer.set_cell(Vector2i(-2, 7), true)
	layer.set_cell_material(Vector2i(-2, 7), 3)

	assert_eq(tool.pick_cell_material(Vector2i(-2, 7)), 3)
	assert_eq(tool.blend_material_id, 3)
	assert_false(tool.is_stroke_active())


func test_live_stroke_status_reports_cells_and_world_metres():
	layer.grid.cell_size = 2.0
	_begin_test_stroke()
	tool._record_stroke_cell(Vector2i(2, 3))
	tool._record_stroke_cell(Vector2i(4, 4))

	var status: String = tool.get_stroke_hud_text()
	assert_true(status.contains("2 cells"))
	assert_true(status.contains("6 m × 4 m"), status)


func test_escape_cancel_restores_rect_preview_without_committing():
	_begin_test_stroke()
	tool.tool = HFStroke.Tool.RECT
	tool._preview_original[Vector2i(6, 6)] = false
	tool._preview_cells[Vector2i(6, 6)] = true
	layer.set_cell(Vector2i(6, 6), true)
	layer.consume_dirty_chunks()

	assert_true(tool.cancel_stroke())
	assert_false(tool.is_stroke_active())
	assert_false(layer.get_cell(Vector2i(6, 6)), "Cancel must restore the pre-preview cell")


func test_floor_paint_tool_never_handles_rmb():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/paint/hf_paint_tool.gd"
	)
	assert_false(source.contains("MOUSE_BUTTON_RIGHT"), "Plain RMB belongs to Godot's camera")


func test_floor_stroke_registers_exactly_one_undo_entry_after_it_changes_cells():
	var plugin := FakePlugin.new()
	var root := FakePaintRoot.new()
	add_child_autoqfree(root)
	HFPluginPaintInput.begin_floor_paint_undo(plugin, root)
	root.marker = 2
	root.paint_tool.changed = 4

	HFPluginPaintInput.commit_floor_paint_undo(plugin, root)

	assert_eq(plugin.undo_redo_manager.actions, ["Paint Floor"])
	assert_eq(plugin.undo_redo_manager.do_calls[0][2], {"marker": 2})
	assert_eq(plugin.undo_redo_manager.undo_calls[0][2], {"marker": 1})
	assert_eq(plugin.history, ["Paint Floor"])
	assert_true(plugin._floor_paint_pre_state.is_empty())


func test_floor_stroke_without_changes_creates_no_undo_entry():
	var plugin := FakePlugin.new()
	var root := FakePaintRoot.new()
	add_child_autoqfree(root)
	HFPluginPaintInput.begin_floor_paint_undo(plugin, root)

	HFPluginPaintInput.commit_floor_paint_undo(plugin, root)

	assert_true(plugin.undo_redo_manager.actions.is_empty())
	assert_true(plugin._floor_paint_pre_state.is_empty())


func test_floor_paint_cancel_restores_pre_state_and_clears_undo_capture():
	var plugin := FakePlugin.new()
	var root := FakePaintRoot.new()
	add_child_autoqfree(root)
	plugin._floor_paint_pre_state = {"marker": 1}
	root.marker = 9

	assert_true(HFPluginPaintInput.cancel_floor_paint(plugin, root))

	assert_eq(root.paint_tool.cancels, 1)
	assert_eq(root.restored, [{"marker": 1}])
	assert_true(plugin._floor_paint_pre_state.is_empty())
