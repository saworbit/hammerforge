@tool
extends ConfirmationDialog
## Replace Material (#1726): every face that wears one material takes another,
## across the level, within the selection or on what is shown, as one undo step.
##
## Find lists the materials the level's faces wear, with how many faces wear each.
## While the dialog is open the faces it would change are the face selection, so
## the viewport marks them; Cancel puts the selection back as it was.

## Replace pressed: `scope` is what `LevelRoot.replace_material()` takes.
signal replace_requested(from_index: int, to_index: int, scope: Dictionary, reset_uv: bool)

enum Scope { LEVEL, SELECTION, VISIBLE }

var find_list: ItemList = null
var with_list: ItemList = null
var use_picked_btn: Button = null
var scope_option: OptionButton = null
var reset_uv_check: CheckBox = null
var preview_label: Label = null

var _root: Node = null
## The selection as it was when the dialog opened: picked faces and whole brushes.
var _selection_scope: Dictionary = {}
var _face_selection_before: Dictionary = {}
var _picked_index := -1
## Palette slot of each Find row, and of each Replace with row.
var _find_slots: Array[int] = []
var _with_slots: Array[int] = []


func _init() -> void:
	title = "Replace Material"
	ok_button_text = "Replace"
	min_size = Vector2i(420, 520)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var find_row := HBoxContainer.new()
	var find_label := Label.new()
	find_label.text = "Find"
	find_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_row.add_child(find_label)
	use_picked_btn = Button.new()
	use_picked_btn.text = "Use Picked"
	use_picked_btn.tooltip_text = "Find the material the Texture Picker (T) last read"
	use_picked_btn.pressed.connect(_on_use_picked)
	find_row.add_child(use_picked_btn)
	box.add_child(find_row)
	find_list = _make_list()
	find_list.tooltip_text = "The materials the level's faces wear, and how many faces wear each"
	box.add_child(find_list)

	var with_label := Label.new()
	with_label.text = "Replace with"
	box.add_child(with_label)
	with_list = _make_list()
	with_list.tooltip_text = "Any material in the palette"
	box.add_child(with_list)

	var scope_row := HBoxContainer.new()
	var scope_label := Label.new()
	scope_label.text = "Where"
	scope_row.add_child(scope_label)
	scope_option = OptionButton.new()
	scope_option.add_item("Whole level", Scope.LEVEL)
	scope_option.add_item("Selected faces and brushes", Scope.SELECTION)
	scope_option.add_item("Shown brushes only", Scope.VISIBLE)
	scope_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scope_option.item_selected.connect(_on_choice_changed.unbind(1))
	scope_row.add_child(scope_option)
	box.add_child(scope_row)

	reset_uv_check = CheckBox.new()
	reset_uv_check.text = "Reset UVs"
	reset_uv_check.tooltip_text = (
		"Put each face's UV scale, offset and rotation back to none\n"
		+ "Off, the faces keep how their texture was laid"
	)
	reset_uv_check.toggled.connect(_on_choice_changed.unbind(1))
	box.add_child(reset_uv_check)

	preview_label = Label.new()
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(preview_label)

	find_list.item_selected.connect(_on_choice_changed.unbind(1))
	with_list.item_selected.connect(_on_choice_changed.unbind(1))
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


static func _make_list() -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 150)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(32, 32)
	list.select_mode = ItemList.SELECT_SINGLE
	return list


## Fill the lists from `root` and open. `selection_scope` is the selection as
## `LevelRoot.replace_material()` takes it, empty when nothing is selected.
## `find_index` starts Find on that slot, and `picked_index` is the slot Use
## Picked takes, -1 for none. `name_of` and `thumbnail_of` name and show a slot.
func open_for(
	root: Node,
	selection_scope: Dictionary,
	find_index: int,
	picked_index: int,
	name_of: Callable,
	thumbnail_of: Callable
) -> void:
	_root = root
	_selection_scope = selection_scope.duplicate(true)
	_face_selection_before = (root.face_selection as Dictionary).duplicate(true)
	_picked_index = picked_index
	var counts := use_counts(root)
	find_list.clear()
	with_list.clear()
	_find_slots.clear()
	_with_slots.clear()
	var palette_size := int(root.material_manager.materials.size()) if root.material_manager else 0
	var slots: Array = counts.keys()
	slots.sort()
	for slot in slots:
		var label := (
			"%s (%d face%s)" % [name_of.call(slot), counts[slot], "" if counts[slot] == 1 else "s"]
		)
		find_list.add_item(label, thumbnail_of.call(slot))
		_find_slots.append(int(slot))
	for slot in palette_size:
		with_list.add_item(str(name_of.call(slot)), thumbnail_of.call(slot))
		_with_slots.append(slot)
	_select_slot(find_list, _find_slots, find_index)
	use_picked_btn.disabled = not _find_slots.has(picked_index)
	var has_selection := not _selection_scope.is_empty()
	scope_option.set_item_disabled(scope_option.get_item_index(Scope.SELECTION), not has_selection)
	scope_option.select(
		scope_option.get_item_index(Scope.SELECTION if has_selection else Scope.LEVEL)
	)
	reset_uv_check.button_pressed = false
	_on_choice_changed()
	popup_centered()


## How many faces wear each palette slot, across the level.
static func use_counts(root: Node) -> Dictionary:
	var counts: Dictionary = {}
	for brush in root._iter_managed_brush_nodes():
		for face in brush.faces:
			if face and int(face.material_idx) >= 0:
				counts[int(face.material_idx)] = int(counts.get(int(face.material_idx), 0)) + 1
	return counts


static func _select_slot(list: ItemList, slots: Array[int], slot: int) -> void:
	var row := slots.find(slot)
	if row < 0 and not slots.is_empty():
		row = 0
	if row >= 0:
		list.select(row)
		list.ensure_current_is_visible()


func _selected_slot(list: ItemList, slots: Array[int]) -> int:
	var rows := list.get_selected_items()
	return slots[rows[0]] if not rows.is_empty() else -1


func from_slot() -> int:
	return _selected_slot(find_list, _find_slots)


func to_slot() -> int:
	return _selected_slot(with_list, _with_slots)


## What `LevelRoot.replace_material()` takes for the chosen Where.
func current_scope() -> Dictionary:
	match scope_option.get_selected_id():
		Scope.SELECTION:
			return _selection_scope.duplicate(true)
		Scope.VISIBLE:
			return {"visible_only": true}
	return {}


func _on_use_picked() -> void:
	_select_slot(find_list, _find_slots, _picked_index)
	_on_choice_changed()


## Count what Replace would change, say it, and mark those faces.
func _on_choice_changed() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var from := from_slot()
	var to := to_slot()
	var ok_button := get_ok_button()
	if from < 0 or to < 0:
		preview_label.text = "Choose a material to find and one to replace it with."
		ok_button.disabled = true
		_show_faces(_face_selection_before)
		return
	var found: Dictionary = _root.faces_wearing_material(from, current_scope())
	var faces := 0
	for key in found:
		faces += (found[key] as Array).size()
	if from == to and not reset_uv_check.button_pressed:
		preview_label.text = "Find and Replace with are the same material."
		ok_button.disabled = true
	elif faces == 0:
		preview_label.text = "No face there wears that material."
		ok_button.disabled = true
	else:
		preview_label.text = (
			"Changes %d face%s on %d brush%s."
			% [faces, "" if faces == 1 else "s", found.size(), "" if found.size() == 1 else "es"]
		)
		ok_button.disabled = false
	_show_faces(found)


func _show_faces(faces: Dictionary) -> void:
	if _root.face_selection == faces:
		return
	_root.face_selection = faces.duplicate(true)
	_root.face_selection_changed.emit()


func _on_confirmed() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	# Back as it was first, so the step's own selection is the one it leaves.
	_show_faces(_face_selection_before)
	# OK is off when there is nothing to replace, and a press sent past it is too.
	if get_ok_button().disabled:
		return
	replace_requested.emit(from_slot(), to_slot(), current_scope(), reset_uv_check.button_pressed)


func _on_canceled() -> void:
	if _root != null and is_instance_valid(_root):
		_show_faces(_face_selection_before)
