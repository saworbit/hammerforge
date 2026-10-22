extends GutTest

## Rebinding in the editor (#1733). A key was changed by writing
## `user://hammerforge_keymap.json` by hand and restarting the plugin, a command
## that ships with no key could never be given one, and each command held one
## chord. The shortcut dialog edits the keymap now, live, and writes only what
## differs from the defaults.

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFShortcutDialogType = preload("res://addons/hammerforge/ui/hf_shortcut_dialog.gd")

const DIR := "user://hf_keymap_rebinding_test"
const PATH := DIR + "/keymap.json"
const SHARED := DIR + "/shared.json"


func after_each() -> void:
	HFLog.end_test_capture()
	for path in [PATH, SHARED]:
		for suffix in ["", ".previous", ".writing"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _key(keycode: int, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.pressed = true
	return event


func _saved() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}


func test_a_command_that_ships_with_no_key_can_be_given_one_and_keeps_it():
	var keymap := HFKeymapType.load_or_default(PATH)
	assert_true(keymap.chord_of("uv_wrap", 0).is_empty(), "fixture: Wrap Texture has no key")
	keymap.set_chord("uv_wrap", {"keycode": KEY_J, "ctrl": true})
	assert_eq(keymap.save_changes(), OK)
	assert_true(keymap.matches("uv_wrap", _key(KEY_J, true)), "it answers at once")
	assert_eq(keymap.user_bound_command(_key(KEY_J, true)), "uv_wrap", "and the router finds it")
	var after_restart := HFKeymapType.load_or_default(PATH)
	assert_true(after_restart.matches("uv_wrap", _key(KEY_J, true)), "and after a restart")


func test_the_saved_file_holds_only_what_was_changed():
	var keymap := HFKeymapType.load_or_default(PATH)
	keymap.set_chord("hollow", {"keycode": KEY_F9})
	keymap.clear_chord("clip")
	keymap.save_changes()
	var saved := _saved()
	assert_eq(saved.keys().size(), 2, "two entries: %s" % str(saved))
	assert_eq(int(saved.get("hollow", {}).get("keycode", 0)), KEY_F9)
	assert_eq(saved.get("clip"), {"none": true}, "a key taken off is written as none")
	var reloaded := HFKeymapType.load_or_default(PATH)
	assert_true(reloaded.chord_of("clip", 0).is_empty(), "and read back as none")
	keymap.reset_binding("hollow")
	keymap.save_changes()
	assert_false(_saved().has("hollow"), "a key put back to its default leaves the file")


func test_a_command_can_carry_two_chords_and_both_fire():
	var keymap := HFKeymapType.load_or_default(PATH)
	var first := keymap.chord_of("hollow", 0)
	assert_false(first.is_empty(), "fixture: Hollow has a key")
	keymap.set_chord("hollow", {"keycode": KEY_KP_5}, 1)
	assert_true(keymap.matches("hollow", _key(KEY_KP_5)), "the second chord")
	var first_event := _key(
		int(first["keycode"]),
		bool(first.get("ctrl", false)),
		bool(first.get("shift", false)),
		bool(first.get("alt", false))
	)
	assert_true(keymap.matches("hollow", first_event), "and the first")
	assert_eq(
		keymap.get_display_string("hollow"),
		HFKeymapType.chord_text(first),
		"surfaces show the first"
	)
	keymap.save_changes()
	var reloaded := HFKeymapType.load_or_default(PATH)
	assert_true(reloaded.matches("hollow", _key(KEY_KP_5)), "both survive a restart")
	keymap.clear_chord("hollow", 0)
	assert_true(keymap.matches("hollow", _key(KEY_KP_5)), "taking the first moves the second up")
	assert_true(keymap.chord_of("hollow", 1).is_empty())


func test_a_clash_is_found_before_the_key_is_kept():
	var keymap := HFKeymapType.load_or_default(PATH)
	var clip := keymap.chord_of("clip", 0)
	assert_eq(
		keymap.clashes_if("hollow", clip), PackedStringArray(["clip"]), "another command's key"
	)
	var save_chord := {"keycode": KEY_S, "ctrl": true}
	assert_true(
		keymap.clashes_if("hollow", save_chord).has(HFKeymapType.GODOT_EDITOR), "Godot's Save"
	)
	assert_true(keymap.clashes_if("hollow", {"keycode": KEY_F12}).is_empty(), "a free key")


func test_reset_all_puts_every_key_back():
	var keymap := HFKeymapType.load_or_default(PATH)
	keymap.set_chord("hollow", {"keycode": KEY_F9})
	keymap.set_chord("uv_wrap", {"keycode": KEY_J})
	keymap.reset_all()
	assert_eq(keymap.changes(), {}, "nothing differs from the defaults")


func test_a_file_may_bind_any_command_and_still_not_one_that_is_not():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(
		JSON.stringify({"uv_wrap": {"keycode": "F12"}, "not_a_command": {"keycode": "K"}})
	)
	file.close()
	HFLog.begin_test_capture(["not a HammerForge action"])
	var keymap := HFKeymapType.load_or_default(PATH)
	var said := HFLog.get_captured_warnings().filter(
		func(w): return str(w).contains("not a HammerForge action")
	)
	assert_eq(said.size(), 1, "the made-up one is said")
	assert_true(keymap.matches("uv_wrap", _key(KEY_F12)), "and the real one is kept")


func test_a_shared_keymap_exports_and_imports():
	var keymap := HFKeymapType.load_or_default(PATH)
	keymap.set_chord("uv_wrap", {"keycode": KEY_J, "alt": true})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	assert_eq(keymap.export_to(SHARED), OK)
	var other := HFKeymapType.load_or_default("")
	assert_true(other.import_from(SHARED), "a teammate takes it")
	assert_true(other.matches("uv_wrap", _key(KEY_J, false, false, true)))


# -- The dialog ------------------------------------------------------------------


func _dialog(keymap) -> Node:
	var dialog = HFShortcutDialogType.new()
	add_child_autofree(dialog)
	dialog.populate(keymap)
	return dialog


func _row(dialog: Node, action: String) -> TreeItem:
	var category: TreeItem = dialog._tree.get_root().get_first_child()
	while category:
		var item := category.get_first_child()
		while item:
			if str(item.get_meta("action", "")) == action:
				return item
			item = item.get_next()
		category = category.get_next()
	return null


func test_the_dialog_lists_commands_with_no_key():
	var dialog = _dialog(HFKeymapType.load_or_default(""))
	var row := _row(dialog, "uv_wrap")
	assert_not_null(row, "Wrap Texture has a row")
	if row:
		assert_eq(row.get_text(1), "none")


func test_a_key_pressed_in_the_dialog_binds_the_selected_command():
	var keymap := HFKeymapType.load_or_default(PATH)
	var dialog = _dialog(keymap)
	watch_signals(keymap)
	dialog.start_capture("uv_wrap", 0)
	assert_true(dialog.is_capturing())
	dialog._input(_key(KEY_J, true))
	assert_false(dialog.is_capturing())
	assert_true(keymap.matches("uv_wrap", _key(KEY_J, true)))
	assert_signal_emitted(keymap, "changed", "live")
	assert_eq(int(_saved().get("uv_wrap", {}).get("keycode", 0)), KEY_J, "and written")
	assert_eq(_row(dialog, "uv_wrap").get_text(1), "Ctrl+J")


func test_escape_stops_listening_and_a_lone_modifier_is_not_a_key():
	var keymap := HFKeymapType.load_or_default("")
	var dialog = _dialog(keymap)
	dialog.start_capture("uv_wrap", 0)
	dialog._input(_key(KEY_CTRL, true))
	assert_true(dialog.is_capturing(), "still listening after Ctrl alone")
	dialog._input(_key(KEY_ESCAPE))
	assert_false(dialog.is_capturing())
	assert_true(keymap.chord_of("uv_wrap", 0).is_empty(), "and nothing bound")


func test_a_clash_in_the_dialog_is_swapped_cleared_or_cancelled():
	var keymap := HFKeymapType.load_or_default("")
	var dialog = _dialog(keymap)
	var hollow := keymap.chord_of("hollow", 0)
	var clip := keymap.chord_of("clip", 0)
	dialog.start_capture("hollow", 0)
	dialog.capture_chord(clip)
	assert_eq(
		HFKeymapType.chord_text(keymap.chord_of("hollow", 0)),
		HFKeymapType.chord_text(hollow),
		"nothing kept while asking"
	)
	dialog.resolve_clash("cancel")
	assert_eq(
		HFKeymapType.chord_text(keymap.chord_of("clip", 0)),
		HFKeymapType.chord_text(clip),
		"cancel leaves both"
	)

	dialog.start_capture("hollow", 0)
	dialog.capture_chord(clip)
	dialog.resolve_clash("swap")
	assert_eq(
		HFKeymapType.chord_text(keymap.chord_of("hollow", 0)),
		HFKeymapType.chord_text(clip),
		"swapped"
	)
	assert_eq(HFKeymapType.chord_text(keymap.chord_of("clip", 0)), HFKeymapType.chord_text(hollow))

	dialog.start_capture("hollow", 0)
	dialog.capture_chord(hollow)
	dialog.resolve_clash("clear")
	assert_eq(
		HFKeymapType.chord_text(keymap.chord_of("hollow", 0)), HFKeymapType.chord_text(hollow)
	)
	assert_true(keymap.chord_of("clip", 0).is_empty(), "the other cleared")
	if dialog._clash_dialog:
		dialog._clash_dialog.hide()


func test_a_key_the_editor_takes_can_only_be_cancelled():
	var keymap := HFKeymapType.load_or_default("")
	var dialog = _dialog(keymap)
	var hollow := keymap.chord_of("hollow", 0)
	dialog.start_capture("hollow", 0)
	dialog.capture_chord({"keycode": KEY_S, "ctrl": true})
	dialog.resolve_clash("swap")
	assert_eq(
		HFKeymapType.chord_text(keymap.chord_of("hollow", 0)),
		HFKeymapType.chord_text(hollow),
		"still its own key"
	)
	if dialog._clash_dialog:
		dialog._clash_dialog.hide()
