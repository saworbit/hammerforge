extends GutTest

## The Structure section as the user drives it: a real dock, a real LevelRoot,
## and the advertised shortcut sent as a real key event.
##
## Settings that are each in range can still be a combination the builder
## refuses, so what the dock says afterwards is the thing worth checking.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFPluginInputRouter = preload("res://addons/hammerforge/plugin_input_router.gd")
const HFKeymapScript = preload("res://addons/hammerforge/hf_keymap.gd")

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	_choose_arch()


func after_each() -> void:
	dock = null
	root = null


func _choose_arch() -> void:
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == "arch":
			dock.structure_type_option.selected = index
			break
	HFDockBrushHandler.rebuild_structure_fields(dock)


func _set_field(key: String, value: float) -> void:
	var control = dock.structure_fields.get(key, null)
	assert_not_null(control, "the arch has a %s control" % key)
	control.set_value_no_signal(value)


func _status() -> String:
	return dock.status_label.text if dock.status_label else ""


func _only_record():
	for generator_id in root.generator_system.generators:
		return root.generator_system.generators[generator_id]
	return null


func _generated_brushes() -> Array:
	var out: Array = []
	var record = _only_record()
	if record == null:
		return out
	for brush_id in record.brush_ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if brush != null:
			out.append(brush)
	return out


# ===========================================================================
# Create
# ===========================================================================


func test_a_valid_create_builds_and_says_what_it_made():
	dock._on_create_structure()

	assert_eq(root.generator_count(), 1, "the control case has to actually build")
	assert_eq(_status(), "Created a arch")


func test_a_wall_as_thick_as_the_radius_is_refused_out_loud():
	# Each field is inside its own range. The combination leaves no opening.
	_set_field("radius", 128.0)
	_set_field("wall_thickness", 128.0)

	dock._on_create_structure()

	assert_eq(root.generator_count(), 0, "nothing was built")
	assert_true(
		_status().begins_with("Arch: wall thickness"),
		"the dock has to say why, not report success: got '%s'" % _status()
	)


func test_a_zero_arc_is_refused_out_loud():
	_set_field("arc_degrees", 0.0)

	dock._on_create_structure()

	assert_eq(root.generator_count(), 0)
	assert_true(_status().contains("arc angle"), "got '%s'" % _status())


func test_an_arc_across_too_few_segments_is_refused_out_loud():
	_set_field("arc_degrees", 360.0)
	_set_field("segments", 1.0)

	dock._on_create_structure()

	assert_eq(root.generator_count(), 0)
	assert_true(_status().contains("segment"), "got '%s'" % _status())


# ===========================================================================
# Update
# ===========================================================================


func _create_then_select_a_piece() -> void:
	dock._on_create_structure()
	assert_eq(root.generator_count(), 1, "the update tests need something to update")
	dock.set_selection_nodes([_generated_brushes()[0]])
	assert_ne(str(dock._active_generator_id), "", "selecting a piece switches to Update")


func test_a_valid_update_rebuilds_and_says_so():
	_create_then_select_a_piece()
	_set_field("radius", 192.0)

	dock._on_create_structure()

	assert_eq(_status(), "Arch rebuilt")
	assert_almost_eq(float(_only_record().settings["radius"]), 192.0, 0.001)


func test_a_refused_update_leaves_the_structure_exactly_as_it_was():
	_create_then_select_a_piece()
	var settings_before: Dictionary = _only_record().settings.duplicate(true)
	var ids_before := Array(_only_record().brush_ids)

	_set_field("arc_degrees", 0.0)
	dock._on_create_structure()

	assert_true(
		_status().begins_with("Arch not changed"),
		"a refused update must say the structure was left alone: got '%s'" % _status()
	)
	assert_eq(_only_record().settings, settings_before, "the stored settings are untouched")
	assert_eq(Array(_only_record().brush_ids), ids_before, "and so is the geometry")


func test_a_refused_update_does_not_report_a_rebuild():
	_create_then_select_a_piece()
	_set_field("wall_thickness", 4096.0)

	dock._on_create_structure()

	assert_false(_status().contains("rebuilt"), "got '%s'" % _status())
	assert_eq(root.generator_count(), 1, "and the structure is still there")


# ===========================================================================
# Rebuilding over painted faces
# ===========================================================================


func test_an_update_that_would_drop_paint_warns_before_it_does_it():
	_set_field("segments", 9.0)
	_create_then_select_a_piece()
	# The last piece is the one a shorter arch would not have.
	var last := str(_only_record().brush_ids[8])
	root.assign_material_to_faces_by_id(last, [0], 7)
	_set_field("segments", 5.0)

	dock._on_create_structure()

	assert_eq(_only_record().brush_ids.size(), 9, "the first press must not rebuild")
	assert_true(dock.structure_warning.visible, "the warning has to be shown")
	assert_true(
		dock.structure_warning.text.contains("Detach"),
		"and has to offer the other way out: got '%s'" % dock.structure_warning.text
	)


func test_pressing_update_again_goes_ahead():
	_set_field("segments", 9.0)
	_create_then_select_a_piece()
	root.assign_material_to_faces_by_id(str(_only_record().brush_ids[8]), [0], 7)
	_set_field("segments", 5.0)

	dock._on_create_structure()
	dock._on_create_structure()

	assert_eq(_status(), "Arch rebuilt")
	assert_eq(_only_record().brush_ids.size(), 5)


func test_an_update_that_keeps_the_paint_does_not_warn():
	_create_then_select_a_piece()
	root.assign_material_to_faces_by_id(str(_only_record().brush_ids[0]), [0], 7)
	_set_field("radius", 192.0)

	dock._on_create_structure()

	assert_eq(_status(), "Arch rebuilt", "a radius nudge keeps every face, so it just rebuilds")
	var rebuilt = root.brush_system.find_brush_by_id(str(_only_record().brush_ids[0]))
	assert_eq(rebuilt.faces[0].material_idx, 7, "and the paint is still there")


# ===========================================================================
# The advertised shortcut (#198)
# ===========================================================================


class FakeInputState:
	extends RefCounted

	func is_dragging() -> bool:
		return false

	func is_extruding() -> bool:
		return false

	func is_idle() -> bool:
		return true


class RecordingDock:
	extends RefCounted

	var creates := 0

	func _on_create_structure() -> void:
		creates += 1

	func show_toast(_text: String, _level: int = 0) -> void:
		pass


class FakePlugin:
	extends RefCounted

	var dock := RecordingDock.new()
	var _keymap = null
	var _hotkey_palette = null
	var _radial_menu = null
	var _tool_registry = null
	var _operation_replay = null

	func _handle_numeric_input(_event, _root) -> int:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	func _cancel_escape_step(_root) -> bool:
		return false


func _ctrl_shift_a() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.pressed = true
	event.ctrl_pressed = true
	event.shift_pressed = true
	return event


func test_ctrl_shift_a_reaches_the_structure_command():
	var plugin := FakePlugin.new()
	var keymap := HFKeymapScript.new()
	keymap._bindings = HFKeymapScript._default_bindings()
	plugin._keymap = keymap
	var router_root := Node3D.new()
	router_root.set_script(_router_root_script())
	add_child_autoqfree(router_root)
	router_root.input_state = FakeInputState.new()

	var handled: int = HFPluginInputRouter.handle_keyboard(
		plugin, _ctrl_shift_a(), router_root, 0, false
	)

	assert_eq(plugin.dock.creates, 1, "the advertised binding has to reach the command")
	assert_eq(handled, EditorPlugin.AFTER_GUI_INPUT_STOP, "and consume the key")


func test_the_binding_is_still_the_one_that_is_advertised():
	var keymap := HFKeymapScript.new()
	keymap._bindings = HFKeymapScript._default_bindings()
	var binding: Dictionary = keymap.get_all_bindings()["create_arch"]
	assert_eq(int(binding["keycode"]), KEY_A)
	assert_true(bool(binding.get("ctrl", false)))
	assert_true(bool(binding.get("shift", false)))
	assert_eq(HFKeymapScript.get_action_label("create_arch"), "Create Structure")


func _router_root_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var input_state = null
"""
	script.reload()
	return script
