@tool
extends AcceptDialog
## Searchable keyboard shortcut dialog, where a key is changed as well as read
## (#1733).
##
## Displays every HammerForge command grouped by category with a live
## search/filter field: its key, a second key if it has one, and none for a
## command that ships without. Select a row and press Set Key, then the new
## chord. A chord another action or the editor already takes is said before it
## is kept. Every change is live and writes the keymap's changes to its file.

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFTranslationType = preload("res://addons/hammerforge/hf_translation.gd")

## A change was made, after the keymap was written.
signal bindings_changed

## The categories in the order the dialog lists them. Transform was missing, so
## Rotate, Flip and Reset Rotation had bindings and no row here.
const CATEGORY_ORDER := [
	"Workflow", "Tools", "Editing", "Transform", "Selection", "Paint", "Axis Lock"
]
const CLASH_COLOR := Color(1.0, 0.6, 0.35, 1.0)
const NO_KEY_COLOR := Color(1, 1, 1, 0.35)

var _search_field: LineEdit
var _tree: Tree
var _category_items: Dictionary = {}  # category name -> TreeItem
var _status: Label = null
var set_key_btn: Button = null
var set_second_btn: Button = null
var clear_btn: Button = null
var reset_btn: Button = null
var reset_all_btn: Button = null
var export_btn: Button = null
var import_btn: Button = null

var _keymap: HFKeymap = null
## The action and slot the next key press goes to, or "" while not listening.
var _capture_action := ""
var _capture_slot := 0
## A chord waiting on the answer to a clash: {action, slot, chord, others}.
var _pending: Dictionary = {}
var _clash_dialog: ConfirmationDialog = null
var _file_dialog: FileDialog = null


func _ready() -> void:
	title = "Keyboard Shortcuts"
	min_size = Vector2i(460, 540)
	_build_ui()


func _build_ui() -> void:
	if _tree != null:
		return
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Filter shortcuts..."
	_search_field.clear_button_enabled = true
	_search_field.text_changed.connect(_on_search_text_changed)
	vbox.add_child(_search_field)

	_tree = Tree.new()
	_tree.columns = 3
	_tree.set_column_title(0, "Action")
	_tree.set_column_title(1, "Key")
	_tree.set_column_title(2, "Second")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, true)
	_tree.set_column_expand(2, true)
	_tree.set_column_expand_ratio(0, 2)
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_update_buttons)
	_tree.item_activated.connect(func(): start_capture(_selected_action(), 0))
	vbox.add_child(_tree)

	var row := HFlowContainer.new()
	set_key_btn = _button(row, "Set Key", "Press the new key for the selected command")
	set_key_btn.pressed.connect(func(): start_capture(_selected_action(), 0))
	set_second_btn = _button(row, "Set Second Key", "Give the selected command a second key")
	set_second_btn.pressed.connect(func(): start_capture(_selected_action(), 1))
	clear_btn = _button(row, "Clear", "Take every key off the selected command")
	clear_btn.pressed.connect(func(): _change(func(): _keymap.clear_chord(_selected_action())))
	reset_btn = _button(row, "Reset", "Put the selected command's key back to its default")
	reset_btn.pressed.connect(func(): _change(func(): _keymap.reset_binding(_selected_action())))
	reset_all_btn = _button(row, "Reset All", "Put every key back to its default")
	reset_all_btn.pressed.connect(func(): _change(func(): _keymap.reset_all()))
	export_btn = _button(row, "Export...", "Write the keys you changed to a file to share")
	export_btn.pressed.connect(_open_file_dialog.bind(true))
	import_btn = _button(row, "Import...", "Take the keys from a shared file")
	import_btn.pressed.connect(_open_file_dialog.bind(false))
	vbox.add_child(row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status)

	var hint = Label.new()
	hint.text = "Type number + Enter during drag for exact size"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	_update_buttons()


static func _button(row: Control, text: String, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	row.add_child(button)
	return button


## List every command `keymap` can bind and edit it in place.
func populate(keymap) -> void:
	_build_ui()
	_keymap = keymap
	_refresh()


func _refresh() -> void:
	var selected := _selected_action()
	_tree.clear()
	_category_items.clear()
	var root_item = _tree.create_item()
	var by_category: Dictionary = {}
	for action in _listed_actions():
		var category := HFKeymapType.get_category(action)
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append(action)
	var order: Array = CATEGORY_ORDER.duplicate()
	for category in by_category:
		if not order.has(category):
			order.append(category)
	for cat in order:
		if not by_category.has(cat):
			continue
		var cat_item: TreeItem = _tree.create_item(root_item)
		cat_item.set_text(0, cat)
		for column in 3:
			cat_item.set_selectable(column, false)
		cat_item.set_custom_color(0, Color(0.7, 0.8, 1.0, 1.0))
		_category_items[cat] = cat_item
		for action in by_category[cat]:
			_add_row(cat_item, action, action == selected)
	_on_search_text_changed(_search_field.text)
	_update_buttons()


## Every action the keymap holds, holds among them, and every command the
## palette runs, bound or not.
func _listed_actions() -> Array:
	var listed: Array = []
	for action in _keymap.get_actions():
		listed.append(action)
	for action in HFCommandRegistry.dispatched_ids():
		if not listed.has(action):
			listed.append(action)
	return listed


func _add_row(parent: TreeItem, action: String, selected: bool) -> void:
	var item: TreeItem = _tree.create_item(parent)
	var label: String = HFKeymapType.get_action_label(action)
	var first: Dictionary = _keymap.chord_of(action, 0)
	var second: Dictionary = _keymap.chord_of(action, 1)
	var binding := HFKeymapType.chord_text(first) if not first.is_empty() else "none"
	item.set_text(0, label)
	item.set_text(1, binding)
	item.set_text(2, HFKeymapType.chord_text(second) if not second.is_empty() else "")
	if first.is_empty():
		item.set_custom_color(1, NO_KEY_COLOR)
	item.set_meta("action", action)
	item.set_meta("label_lower", label.to_lower())
	item.set_meta("binding_lower", binding.to_lower())
	# A chord two actions in the same mode share: the input router returns on
	# the first hit, so one of them never fires. Say so here rather than leaving
	# the user to find out by pressing it.
	var clashes: PackedStringArray = _keymap.conflicts_for(action)
	if not clashes.is_empty():
		item.set_custom_color(1, CLASH_COLOR)
		item.set_tooltip_text(1, "Also used by %s. Only one of them fires." % _labels(clashes))
	if selected:
		item.select(0)


static func _labels(actions: PackedStringArray) -> String:
	var others := PackedStringArray()
	for action in actions:
		others.append(HFKeymapType.get_action_label(action))
	return ", ".join(others)


func _selected_action() -> String:
	var item := _tree.get_selected() if _tree else null
	return str(item.get_meta("action", "")) if item else ""


func _update_buttons() -> void:
	if set_key_btn == null:
		return
	var action := _selected_action()
	var editable := action != "" and not HFKeymapType.HOLDS.has(action)
	set_key_btn.disabled = not editable
	set_second_btn.disabled = (
		not editable or _keymap == null or _keymap.chord_of(action, 0).is_empty()
	)
	clear_btn.disabled = not editable
	reset_btn.disabled = not editable


## Listen for the next key press, for `action`'s chord in `slot`.
func start_capture(action: String, slot: int) -> void:
	if action == "" or HFKeymapType.HOLDS.has(action) or _keymap == null:
		return
	_capture_action = action
	_capture_slot = slot
	var press := (
		HFTranslationType.t("Press the new key for {command}. Escape stops.")
		if slot == 0
		else HFTranslationType.t("Press the new second key for {command}. Escape stops.")
	)
	_say(press.format({"command": HFKeymapType.get_action_label(action)}))


func is_capturing() -> bool:
	return _capture_action != ""


func _input(event: InputEvent) -> void:
	if not is_capturing() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_NONE]:
		return
	set_input_as_handled()
	if key.keycode == KEY_ESCAPE and not key.ctrl_pressed and not key.shift_pressed:
		_capture_action = ""
		_say("Left as it was.")
		return
	capture_chord(HFKeymapType.chord_from_event(key))


## The chord the listened-for key press gave. Kept at once when nothing else
## takes it; otherwise what takes it is said and asked about.
func capture_chord(chord: Dictionary) -> void:
	var action := _capture_action
	var slot := _capture_slot
	_capture_action = ""
	if action == "":
		return
	var others := _keymap.clashes_if(action, chord, slot)
	if others.is_empty():
		_change(func(): _keymap.set_chord(action, chord, slot))
		return
	_pending = {"action": action, "slot": slot, "chord": chord, "others": others}
	_ask_about_clash()


## What the clash is and what can be done about it: another command's chord can
## be swapped or cleared; a key the editor or the palette takes cannot.
func _ask_about_clash() -> void:
	var chord_text := HFKeymapType.chord_text(_pending["chord"])
	var others: PackedStringArray = _pending["others"]
	var commands := PackedStringArray()
	var taken_ahead := PackedStringArray()
	for other in others:
		if _keymap.has_action(other) or HFCommandRegistry.dispatches(other):
			commands.append(other)
		else:
			taken_ahead.append(other)
	if _clash_dialog == null:
		_clash_dialog = ConfirmationDialog.new()
		_clash_dialog.title = "Key already used"
		add_child(_clash_dialog)
		_clash_dialog.add_button("Clear the Other", true, "clear")
		_clash_dialog.confirmed.connect(resolve_clash.bind("swap"))
		_clash_dialog.canceled.connect(resolve_clash.bind("cancel"))
		_clash_dialog.custom_action.connect(resolve_clash)
	if not taken_ahead.is_empty():
		_clash_dialog.dialog_text = (
			HFTranslationType
			. t("{chord} is taken by {commands} ahead of every binding. Choose another key.")
			. format({"chord": chord_text, "commands": _labels(taken_ahead)})
		)
		_clash_dialog.get_ok_button().visible = false
		_clash_dialog.get_cancel_button().text = "OK"
	else:
		_clash_dialog.dialog_text = (
			HFTranslationType
			. t(
				"{chord} is already {commands}. Swap the keys, take it off {commands}, or leave it as it was."
			)
			. format({"chord": chord_text, "commands": _labels(commands)})
		)
		_clash_dialog.get_ok_button().visible = true
		_clash_dialog.get_ok_button().text = "Swap"
		_clash_dialog.get_cancel_button().text = "Cancel"
	_clash_dialog.popup_centered()
	_say(_clash_dialog.dialog_text)


## Answer the clash: "swap" gives the other command the key this one had,
## "clear" takes the key off the other, "cancel" keeps everything as it was. A
## key taken ahead of every binding can only be cancelled.
func resolve_clash(answer: String) -> void:
	if _pending.is_empty():
		return
	var pending := _pending
	_pending = {}
	if _clash_dialog and _clash_dialog.visible:
		_clash_dialog.hide()
	var action: String = pending["action"]
	var slot: int = pending["slot"]
	var chord: Dictionary = pending["chord"]
	var others: PackedStringArray = pending["others"]
	for other in others:
		if not (_keymap.has_action(other) or HFCommandRegistry.dispatches(other)):
			answer = "cancel"
	if answer == "cancel":
		_say("Left as it was.")
		return
	var old_chord := _keymap.chord_of(action, slot)
	_change(
		func():
			for other in others:
				var other_slot := _slot_with(other, chord)
				if answer == "swap" and not old_chord.is_empty():
					_keymap.set_chord(other, old_chord, other_slot)
				else:
					_keymap.clear_chord(other, other_slot)
			_keymap.set_chord(action, chord, slot)
	)


## The slot of `action` that holds `chord`, its first when neither does.
func _slot_with(action: String, chord: Dictionary) -> int:
	for slot in 2:
		var held := _keymap.chord_of(action, slot)
		if HFKeymapType.chord_text(held) == HFKeymapType.chord_text(chord) and not held.is_empty():
			return slot
	return 0


## Make a change, write it, redraw and say so.
func _change(edit: Callable) -> void:
	if _keymap == null:
		return
	edit.call()
	var err := _keymap.save_changes()
	_refresh()
	var failed := HFTranslationType.t("Not saved: {error}").format({"error": error_string(err)})
	_say(HFTranslationType.t("Saved.") if err == OK else failed)
	bindings_changed.emit()


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _open_file_dialog(saving: bool) -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.json ; Keymap"])
		add_child(_file_dialog)
		_file_dialog.file_selected.connect(_on_file_chosen)
	_file_dialog.file_mode = (
		FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	)
	_file_dialog.set_meta("saving", saving)
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_chosen(path: String) -> void:
	if bool(_file_dialog.get_meta("saving", false)):
		export_keymap(path)
	else:
		import_keymap(path)


## Write the changed keys to `path`. OK, or why not.
func export_keymap(path: String) -> int:
	var err := _keymap.export_to(path)
	var exported := HFTranslationType.t("Exported to {file}.").format({"file": path})
	var failed := HFTranslationType.t("Not exported: {error}").format({"error": error_string(err)})
	_say(exported if err == OK else failed)
	return err


## Take the keys `path` holds. False, with nothing changed, for a file that is
## not a keymap.
func import_keymap(path: String) -> bool:
	if not _keymap.import_from(path):
		_say(HFTranslationType.t("{file} is not a keymap file.").format({"file": path}))
		return false
	# Taken already; this writes it and redraws.
	_change(func(): pass)
	return true


func _on_search_text_changed(filter_text: String) -> void:
	var query := filter_text.strip_edges().to_lower()
	for cat in _category_items:
		var cat_item: TreeItem = _category_items[cat]
		var any_visible := false
		var child: TreeItem = cat_item.get_first_child()
		while child:
			if query.is_empty():
				child.visible = true
				any_visible = true
			else:
				var label_lower: String = child.get_meta("label_lower", "")
				var binding_lower: String = child.get_meta("binding_lower", "")
				var match_found: bool = label_lower.contains(query) or binding_lower.contains(query)
				child.visible = match_found
				if match_found:
					any_visible = true
			child = child.get_next()
		cat_item.visible = any_visible
