extends GutTest

## The tools' own keys are keymap actions (#1820). Clip, Measure, Decal, Polygon
## and Path each started on a bare key of their own, from `tool_shortcut_key()`,
## that the keymap did not hold. So the Shortcuts dialog had no row for them, a
## key it gave another command never reported the clash, and the tool won the
## key anyway because the router asks the tools before a key the dialog gave.

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFShortcutDialogType = preload("res://addons/hammerforge/ui/hf_shortcut_dialog.gd")
const HFToolRegistryType = preload("res://addons/hammerforge/hf_tool_registry.gd")
const HFMeasureToolType = preload("res://addons/hammerforge/hf_measure_tool.gd")
const HFDecalToolType = preload("res://addons/hammerforge/hf_decal_tool.gd")
const HFPolygonToolType = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const HFPathToolType = preload("res://addons/hammerforge/hf_path_tool.gd")
const HFClipToolType = preload("res://addons/hammerforge/hf_clip_tool.gd")

## Each tool, the action it starts on, the key that action ships with, and how
## the key is written.
const TOOLS := [
	[HFMeasureToolType, "measure", KEY_M, "M"],
	[HFDecalToolType, "tool_decal", KEY_N, "N"],
	[HFPolygonToolType, "tool_polygon", KEY_P, "P"],
	[HFPathToolType, "tool_path", KEY_SEMICOLON, ";"],
	[HFClipToolType, "tool_clip", KEY_C, "C"],
]

var registry: HFToolRegistry


func before_each() -> void:
	registry = HFToolRegistryType.new()
	for entry in TOOLS:
		registry.register_tool(entry[0].new())


func after_each() -> void:
	if registry:
		for entry in TOOLS:
			registry.unregister_tool(entry[0].new().tool_id())
	registry = null


static func _key(keycode: int, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	return event


func test_each_tool_starts_on_the_key_it_always_had_from_the_keymap():
	var keymap := HFKeymapType.load_or_default()
	for entry in TOOLS:
		var tool = entry[0].new()
		assert_eq(tool.keymap_action(), entry[1], "%s names its action" % tool.tool_name())
		assert_eq(
			keymap.get_display_string(entry[1]),
			entry[3],
			"%s ships on its old key" % tool.tool_name()
		)
		assert_eq(
			registry.check_shortcut(_key(entry[2]), keymap),
			tool.tool_id(),
			"%s starts on it" % tool.tool_name()
		)
		assert_eq(
			registry.check_shortcut(_key(entry[2], false, false, true), keymap),
			-1,
			"Alt with it is not the tool"
		)


func test_moving_a_tool_s_key_in_the_keymap_moves_the_tool():
	var keymap := HFKeymapType.load_or_default()
	keymap.set_chord("tool_clip", {"keycode": KEY_F8, "shift": true})
	assert_eq(registry.check_shortcut(_key(KEY_C), keymap), -1, "C no longer starts Clip")
	assert_eq(registry.check_shortcut(_key(KEY_F8, false, true), keymap), 104, "Shift+F8 does")
	keymap.clear_chord("tool_clip")
	assert_eq(registry.check_shortcut(_key(KEY_F8, false, true), keymap), -1, "and no key, none")


func test_a_tool_s_action_is_found_by_its_name():
	for entry in TOOLS:
		assert_eq(registry.tool_id_for_action(entry[1]), entry[0].new().tool_id())
	assert_eq(registry.tool_id_for_action("tool_draw"), -1, "a built in tool is not external")
	assert_eq(registry.tool_id_for_action(""), -1)


func test_giving_a_command_a_tool_s_key_reports_the_clash():
	var keymap := HFKeymapType.load_or_default()
	assert_true(keymap.chord_of("cycle_io_wires", 0).is_empty(), "fixture: no key of its own")
	for entry in TOOLS:
		var clashes := keymap.clashes_if("cycle_io_wires", {"keycode": entry[2]})
		assert_has(clashes, entry[1], "%s is reported" % entry[1])


func test_the_shortcut_dialog_lists_and_changes_each_tool_s_key():
	var keymap := HFKeymapType.load_or_default()
	var dialog = HFShortcutDialogType.new()
	add_child_autofree(dialog)
	dialog.populate(keymap)
	var rows := {}
	var category := {}
	var cat_item: TreeItem = dialog._tree.get_root().get_first_child()
	while cat_item:
		var row := cat_item.get_first_child()
		while row:
			rows[str(row.get_meta("action"))] = row.get_text(1)
			category[str(row.get_meta("action"))] = cat_item.get_text(0)
			row = row.get_next()
		cat_item = cat_item.get_next()
	for entry in TOOLS:
		assert_true(rows.has(entry[1]), "a row for %s" % entry[1])
		assert_eq(category.get(entry[1], ""), "Tools", "%s is listed under Tools" % entry[1])
	assert_eq(rows.get("tool_clip", ""), "C")
	var free_chord := {"keycode": KEY_J, "ctrl": true}
	assert_eq(keymap.clashes_if("tool_clip", free_chord), PackedStringArray(), "fixture: free")
	dialog.start_capture("tool_clip", 0)
	dialog.capture_chord(free_chord)
	assert_true(keymap.matches("tool_clip", _key(KEY_J, true)), "the dialog changes it")


## The issue's repro: a command given C in the dialog, the clash accepted by
## taking C off Clip, and C pressed in the viewport.
func test_c_runs_what_the_dialog_gave_it_once_the_clash_is_settled():
	var rig = load("res://tests/support/plugin_rig.gd").new()
	await rig.bring_up(self)
	assert_not_null(rig.plugin, rig.error())
	if rig.plugin == null:
		return
	var level = await rig.make_level()
	var box = rig.box(level, "pick", Vector3(0, 2, 0))
	rig.select([box])
	var keymap: HFKeymap = rig.plugin._keymap
	var dock = rig.plugin.dock
	var showing_before: bool = dock._show_io_lines.button_pressed
	var mode_before: int = dock.io_wire_mode_opt.selected

	var dialog = HFShortcutDialogType.new()
	add_child_autofree(dialog)
	dialog.populate(keymap)
	dialog.start_capture("cycle_io_wires", 0)
	dialog.capture_chord({"keycode": KEY_C})
	assert_false(dialog._pending.is_empty(), "the dialog stops on the clash")
	dialog.resolve_clash("clear")
	assert_true(keymap.chord_of("tool_clip", 0).is_empty(), "Clip gave C up")

	assert_eq(rig.forward(rig.key(KEY_C)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	var active = rig.plugin._tool_registry.get_active_tool()
	assert_false(active is HFClipToolType, "the Clip tool did not start")
	var changed: bool = (
		dock._show_io_lines.button_pressed != showing_before
		or dock.io_wire_mode_opt.selected != mode_before
	)
	assert_true(changed, "the wires changed")

	# Four presses go round once, so the wire setting is left as it was.
	for _i in 3:
		rig.forward(rig.key(KEY_C))
	keymap.reset_all()
	await rig.leave_level(level)
	await rig.take_down()
