@tool
extends PanelContainer
## Searchable hotkey command palette with live gray-out for invalid states.
##
## Toggle with ? key or dedicated button. Shows all HammerForge actions
## grouped by category, with real-time enable/disable based on current
## context (selection, mode, tool state).

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

signal action_invoked(action: String)

var _search_field: LineEdit
var _list: VBoxContainer
var _scroll: ScrollContainer
var _suggest_label: Label  # "Did you mean: ..." suggestion
var _keymap = null  # HFKeymap
var _entries: Array = []  # Array of {action, label, binding, button, category}
var _state: Dictionary = {}  # Current context for graying out


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_style()
	_build_ui()
	# Deferred populate: if populate() was called before _ready (before _list
	# existed), replay it now that the UI is built.
	if _deferred_keymap != null:
		populate(_deferred_keymap)
		_deferred_keymap = null


var _deferred_keymap = null  # Holds keymap if populate() is called before _ready()


func _build_style() -> void:
	var style = HFThemeUtils.make_panel_stylebox()
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(320, 380)


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Command Palette"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", HFThemeUtils.primary_text())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Search
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search actions..."
	_search_field.clear_button_enabled = true
	_search_field.text_changed.connect(_on_search_changed)
	_search_field.gui_input.connect(_on_search_input)
	vbox.add_child(_search_field)

	# Scrollable list
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	# "Did you mean" suggestion label
	_suggest_label = Label.new()
	_suggest_label.add_theme_font_size_override("font_size", 11)
	_suggest_label.add_theme_color_override("font_color", HFThemeUtils.accent())
	_suggest_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_suggest_label.visible = false
	vbox.add_child(_suggest_label)

	# Hint
	var hint = Label.new()
	hint.text = "Press Enter to execute, Esc to close  |  Ctrl+K"
	hint.add_theme_font_size_override("font_size", 10)
	var hint_color = HFThemeUtils.muted_text()
	hint_color.a = 0.45
	hint.add_theme_color_override("font_color", hint_color)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func populate(keymap) -> void:
	_keymap = keymap
	# Guard: if _list hasn't been built yet (populate called before _ready),
	# stash the keymap and replay in _ready().
	if _list == null:
		_deferred_keymap = keymap
		return
	_entries.clear()
	for child in _list.get_children():
		child.queue_free()

	var category_order := ["Tools", "Editing", "Paint", "Axis Lock"]
	var categorized: Dictionary = {}
	for cat in category_order:
		categorized[cat] = []

	var actions: PackedStringArray = keymap.get_actions()
	for action in actions:
		var cat: String = HFKeymapType.get_category(action)
		if not categorized.has(cat):
			categorized[cat] = []
		categorized[cat].append(action)

	for cat in category_order:
		if not categorized.has(cat) or categorized[cat].is_empty():
			continue
		# Category header
		var header = Label.new()
		header.text = cat
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", HFThemeUtils.muted_text())
		header.name = "Cat_" + cat.replace(" ", "_")
		_list.add_child(header)

		for action in categorized[cat]:
			var label_text: String = HFKeymapType.get_action_label(action)
			var binding: String = keymap.get_display_string(action)
			var entry = _create_entry(action, label_text, binding, cat)
			_entries.append(entry)


func _create_entry(
	action: String, label_text: String, binding: String, category: String
) -> Dictionary:
	var btn = Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size = Vector2(0, 26)

	# Use rich label effect via button text with binding right-aligned
	btn.text = label_text + "    " + binding
	btn.tooltip_text = label_text + " (" + binding + ")"
	btn.pressed.connect(_on_entry_pressed.bind(action))
	_list.add_child(btn)

	# Overlay binding label (right-aligned)
	var bind_lbl = Label.new()
	bind_lbl.text = binding
	bind_lbl.add_theme_font_size_override("font_size", 11)
	bind_lbl.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	bind_lbl.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	bind_lbl.position.x = -8
	bind_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bind_lbl)

	# Make the main text exclude binding portion
	btn.text = label_text

	return {
		"action": action,
		"label": label_text,
		"label_lower": label_text.to_lower(),
		"binding": binding,
		"binding_lower": binding.to_lower(),
		"button": btn,
		"bind_label": bind_lbl,
		"category": category,
	}


func refresh_theme_colors() -> void:
	_build_style()


func update_state(state: Dictionary) -> void:
	_state = state
	_apply_gray_out()


func _apply_gray_out() -> void:
	for entry in _entries:
		var action: String = entry["action"]
		var btn: Button = entry["button"]
		var enabled := _is_action_available(action)
		btn.disabled = not enabled
		var alpha := 1.0 if enabled else 0.35
		btn.modulate = Color(1, 1, 1, alpha)
		var bind_lbl: Label = entry["bind_label"]
		bind_lbl.modulate = Color(1, 1, 1, alpha)


func _is_action_available(action: String) -> bool:
	var has_selection: bool = _state.get("brush_count", 0) > 0 or _state.get("entity_count", 0) > 0
	var has_brush_sel: bool = _state.get("brush_count", 0) > 0
	var is_paint: bool = _state.get("paint_mode", false)
	var is_vertex: bool = _state.get("vertex_mode", false)
	var is_dragging: bool = _state.get("input_mode", 0) in [1, 2]
	var tool_id: int = _state.get("tool", 0)

	match action:
		# Selection-dependent editing actions
		"delete", "duplicate":
			return has_selection
		"hollow", "clip", "carve", "move_to_floor", "move_to_ceiling":
			return has_brush_sel
		"group", "ungroup":
			return has_brush_sel
		# Paint tools only in paint mode
		"paint_bucket", "paint_erase", "paint_ramp", "paint_line", "paint_blend":
			return is_paint
		# Vertex tools only in vertex mode
		"vertex_edge_mode", "vertex_merge", "vertex_split_edge":
			return is_vertex
		# Axis lock not in select mode
		"axis_x", "axis_y", "axis_z":
			return tool_id != 1
		# Select similar needs a selection or face selection
		"select_similar":
			return has_selection or _state.get("face_count", 0) > 0
		# Apply last texture needs a selection
		"apply_last_texture":
			return has_selection or _state.get("face_count", 0) > 0
		# Selection filter always available
		"selection_filter":
			return true
		# Tool switches always available
		"tool_draw", "tool_select", "tool_extrude_up", "tool_extrude_down", "vertex_edit", "texture_picker":
			return true

	return true


func toggle_visible() -> void:
	visible = not visible
	if visible:
		_search_field.text = ""
		_on_search_changed("")
		_apply_gray_out()
		# Defer focus grab to next idle frame and re-check tree membership
		# at execution time so we never call grab_focus() on a stale node.
		call_deferred("_grab_search_focus_if_ready")


func _grab_search_focus_if_ready() -> void:
	if is_instance_valid(_search_field) and _search_field.is_inside_tree():
		_search_field.grab_focus()


func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	var cat_visible: Dictionary = {}
	_suggest_label.visible = false

	if query.is_empty():
		for entry in _entries:
			entry["button"].visible = true
			cat_visible[entry["category"]] = true
	else:
		# Phase 1: exact substring match
		var exact_count := 0
		for entry in _entries:
			var match_found: bool = (
				entry["label_lower"].contains(query) or entry["binding_lower"].contains(query)
			)
			entry["button"].visible = match_found
			if match_found:
				cat_visible[entry["category"]] = true
				exact_count += 1

		# Phase 2: fuzzy match if no exact hits
		if exact_count == 0:
			var scored: Array = []
			for i in range(_entries.size()):
				var entry: Dictionary = _entries[i]
				var score := _fuzzy_score(query, entry["label_lower"])
				var binding_score := _fuzzy_score(query, entry["binding_lower"])
				var best: int = maxi(score, binding_score)
				if best > 0:
					scored.append({"index": i, "score": best, "label": entry["label"]})

			scored.sort_custom(func(a, b): return a["score"] > b["score"])

			# Show top fuzzy results (up to 5)
			var shown := 0
			for item in scored:
				if shown >= 5:
					break
				var entry: Dictionary = _entries[item["index"]]
				entry["button"].visible = true
				cat_visible[entry["category"]] = true
				shown += 1

			# Show "Did you mean" if we have suggestions
			if scored.size() > 0:
				var suggestion: String = scored[0]["label"]
				_suggest_label.text = "Did you mean: %s?" % suggestion
				_suggest_label.visible = true

	# Show/hide category headers
	for child in _list.get_children():
		if child is Label and child.name.begins_with("Cat_"):
			var cat_name = child.text
			child.visible = cat_visible.get(cat_name, false)


## Fuzzy matching: returns a score > 0 if all query chars appear in order in target.
## Higher score = tighter match. Returns 0 for no match.
static func _fuzzy_score(query: String, target: String) -> int:
	if query.is_empty():
		return 0
	var qi := 0
	var score := 0
	var last_match_pos := -1
	for ti in range(target.length()):
		if qi < query.length() and target[ti] == query[qi]:
			# Bonus for consecutive matches
			if last_match_pos >= 0 and ti == last_match_pos + 1:
				score += 3
			# Bonus for matching at word boundary
			elif ti == 0 or target[ti - 1] == " " or target[ti - 1] == "_":
				score += 2
			else:
				score += 1
			last_match_pos = ti
			qi += 1
	if qi < query.length():
		return 0  # Not all query chars found
	return score


func _on_search_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			visible = false
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Execute first visible enabled entry
			_execute_first_match()
			get_viewport().set_input_as_handled()


func _execute_first_match() -> void:
	for entry in _entries:
		if entry["button"].visible and not entry["button"].disabled:
			_on_entry_pressed(entry["action"])
			return


## Execute the "Did you mean" suggestion (first fuzzy match).
func _accept_suggestion() -> void:
	_execute_first_match()


func _on_entry_pressed(action: String) -> void:
	visible = false
	action_invoked.emit(action)
