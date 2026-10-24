@tool
extends PanelContainer
## Searchable hotkey command palette with live gray-out for invalid states.
##
## Toggle with ? key or dedicated button. Shows all HammerForge actions
## grouped by category, with real-time enable/disable based on current
## context (selection, mode, tool state).

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFCommandRegistryType = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFCommandAliasesType = preload("res://addons/hammerforge/hf_command_aliases.gd")
const HFNameMatchType = preload("res://addons/hammerforge/hf_name_match.gd")

signal action_invoked(action: String)

var _search_field: LineEdit
var _list: VBoxContainer
var _scroll: ScrollContainer
var _suggest_label: Label  # "Did you mean: ..." suggestion
var _keymap = null  # HFKeymap
var _entries: Array = []  # Array of {action, label, binding, button, category}
var _state: Dictionary = {}  # Current context for graying out
## Where the project's own aliases are read when the palette fills (#1695).
var aliases_path := HFCommandAliasesType.USER_FILE
var _rows: Array = []  # Every header and button of the list, in listed order
var _shown: Array = []  # The entries the list shows, top first
var _headers: Dictionary = {}  # category -> its header
var _recent_header: Label = null  # Over the commands run lately (#1694)


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


## Gap between a row's binding text and the right edge of the row.
const BIND_INSET := 8.0


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
	_rows.clear()
	_shown.clear()
	_headers.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_recent_header = _header("Recent")
	_recent_header.visible = false
	var aliases := HFCommandAliasesType.by_command(HFCommandAliasesType.read_user(aliases_path))

	var category_order := [
		"Workflow", "Tools", "Editing", "Transform", "Selection", "Paint", "Axis Lock"
	]
	for group in _palette_groups(keymap, category_order):
		var cat: String = group[0]
		var header := _header(cat)
		header.name = "Cat_" + cat.replace(" ", "_")
		_headers[cat] = header
		_rows.append(header)

		for action in group[1]:
			var label_text: String = HFKeymapType.get_action_label(action)
			var binding: String = (
				keymap.get_display_string(action) if keymap.has_action(action) else ""
			)
			var entry = _create_entry(action, label_text, binding, cat)
			entry["aliases"] = aliases.get(action, [])
			_entries.append(entry)
			_rows.append(entry["button"])
	_arrange_unsearched()


func _header(text: String) -> Label:
	var header = Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_list.add_child(header)
	return header


## The keymap's actions by category, in `order`, with the commands the registry
## lists here although no key is bound to them added to their categories.
static func _palette_groups(keymap, order: Array) -> Array:
	var by_category: Dictionary = {}
	for group in keymap.grouped_actions(order):
		by_category[group[0]] = (group[1] as Array).duplicate()
	for action in HFCommandRegistryType.palette_ids():
		if keymap.has_action(action):
			continue
		var category := HFKeymapType.get_category(action)
		if not by_category.has(category):
			by_category[category] = []
		(by_category[category] as Array).append(action)
	var out: Array = []
	for category in order:
		if by_category.has(category):
			out.append([category, by_category[category]])
	return out


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
	var help := HFCommandRegistryType.help(action)
	if help != "":
		btn.tooltip_text += "\n" + help
	btn.pressed.connect(_on_entry_pressed.bind(action))
	_list.add_child(btn)

	# Overlay binding label (right-aligned)
	var bind_lbl = Label.new()
	bind_lbl.text = binding
	bind_lbl.add_theme_font_size_override("font_size", 11)
	bind_lbl.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	# Stretched across the row with the text right-aligned, rather than anchored
	# to the centre-right point: Godot's PRESET_CENTER_RIGHT puts the label's
	# top-left corner there, so every binding started at the row's right edge and
	# ran off it, leaving the scroll container to clip all but the first
	# character or two — "Ctrl+K" showed as "Ctr".
	bind_lbl.anchor_left = 0.0
	bind_lbl.anchor_top = 0.0
	bind_lbl.anchor_right = 1.0
	bind_lbl.anchor_bottom = 1.0
	bind_lbl.offset_left = 0.0
	bind_lbl.offset_top = 0.0
	bind_lbl.offset_right = -BIND_INSET
	bind_lbl.offset_bottom = 0.0
	bind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bind_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	var lifted := [_state.get("repeat_text", ""), _state.get("recent_commands", [])]
	_state = state
	_apply_gray_out()
	var searching := _search_field != null and not _search_field.text.strip_edges().is_empty()
	if not searching and lifted != [state.get("repeat_text", ""), state.get("recent_commands", [])]:
		_arrange_unsearched()


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
	var mixed_selection: bool = _state.get("mixed_selection", false)
	var has_selection: bool = (
		not mixed_selection
		and (_state.get("brush_count", 0) > 0 or _state.get("entity_count", 0) > 0)
	)
	var has_brush_sel: bool = not mixed_selection and _state.get("brush_count", 0) > 0
	var is_paint: bool = _state.get("paint_mode", false)
	var is_vertex: bool = _state.get("vertex_mode", false)
	var tool_id: int = _state.get("tool", 0)
	var is_idle: bool = (
		_state.get("input_mode", 0) == 0 and not _state.get("has_active_external_tool", false)
	)

	# Repeat waits for something to repeat (#1694).
	if action == "repeat_last_command":
		return str(_state.get("repeat_command", "")) != ""
	# A favourite goes on the selected faces, or else the selected brushes.
	if action.begins_with("apply_favorite_"):
		return not mixed_selection and (has_brush_sel or _state.get("face_count", 0) > 0)
	match action:
		# Selection-dependent editing actions
		"delete", "duplicate":
			return has_selection
		"hollow", "clip", "carve", "merge", "intersect", "hull", "move_to_floor", "move_to_ceiling":
			return has_brush_sel
		"select_inside", "select_partly_inside", "select_touching", "select_column":
			return has_brush_sel
		# In vertex mode the chord snaps the selected vertices instead.
		"snap_to_grid":
			return has_selection and not is_vertex
		# Objects, the picked faces, or in vertex mode the picked vertices.
		"offset_selection":
			return (
				not mixed_selection
				and (has_selection or is_vertex or _state.get("face_count", 0) > 0)
			)
		"group", "ungroup":
			return has_selection
		# Paint tools only in paint mode
		"paint_bucket", "paint_erase", "paint_ramp", "paint_line", "paint_fill", "paint_blend":
			return is_paint
		# Vertex tools only in vertex mode
		"vertex_edge_mode", "vertex_merge", "vertex_split_edge", "vertex_snap_to_grid":
			return is_vertex and not mixed_selection
		# Axis lock not in select mode
		"axis_x", "axis_y", "axis_z":
			return tool_id != 1
		# Select similar, Grow and Shrink need a selection or face selection
		"select_similar", "grow_selection", "shrink_selection":
			return not mixed_selection and (has_selection or _state.get("face_count", 0) > 0)
		# Apply last texture needs a selection
		"apply_last_texture":
			return not mixed_selection and (has_selection or _state.get("face_count", 0) > 0)
		# Apply picked look, Wrap and a Trim Run (#1414) work on faces alone
		"apply_picked_look", "uv_wrap", "run_trim_along_faces":
			return not mixed_selection and _state.get("face_count", 0) > 0
		# Selection filter always available
		"selection_filter":
			return not mixed_selection
		# Tool switches always available
		"vertex_edit":
			return has_brush_sel
		"tool_draw", "tool_select", "tool_extrude_up", "tool_extrude_down", "texture_picker":
			return true
		# Viewport menus only when idle (no active operation or external tool)
		"context_menu", "radial_menu":
			return is_idle

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
	var query := HFCommandAliasesType.normal(text)
	_suggest_label.visible = false
	for entry in _entries:
		entry["button"].text = entry["label"]
	if query.is_empty():
		_arrange_unsearched()
		return

	# The best match first, with no headers: Enter runs the top row.
	var ranked := _ranked(query, _entries)
	var fuzzy := ranked.is_empty()
	if fuzzy:
		ranked = _fuzzy_ranked(query, _entries).slice(0, 5)
	for row in _rows:
		row.visible = false
	_recent_header.visible = false
	_shown.clear()
	for i in ranked.size():
		var entry: Dictionary = ranked[i]["entry"]
		var btn: Button = entry["button"]
		_list.move_child(btn, i)
		btn.visible = true
		if ranked[i]["alias"] != "":
			btn.text = "%s (%s)" % [entry["label"], ranked[i]["alias"]]
		_shown.append(entry)
	if fuzzy and not ranked.is_empty():
		_suggest_label.text = "Did you mean: %s?" % ranked[0]["entry"]["label"]
		_suggest_label.visible = true


## The list with nothing searched: Repeat on top when there is something to
## repeat, as "Repeat: Hollow", then the commands run lately, newest first, then
## every command by category (#1694).
func _arrange_unsearched() -> void:
	if _recent_header == null:
		return
	var top: Array = []
	var repeat = _entry_of("repeat_last_command")
	var repeat_text := str(_state.get("repeat_text", ""))
	if repeat != null:
		repeat["button"].text = repeat["label"]
		if repeat_text != "":
			repeat["button"].text = "Repeat: %s" % repeat_text
			top.append(repeat)
	var recent: Array = []
	for action in _state.get("recent_commands", []):
		var entry = _entry_of(str(action))
		if entry != null and not top.has(entry) and not recent.has(entry):
			recent.append(entry)
	var lifted: Dictionary = {}
	var order: Array = []
	for entry in top + recent:
		lifted[entry["button"]] = true
		order.append(entry["button"])
	order.insert(top.size(), _recent_header)
	for row in _rows:
		if not lifted.has(row):
			order.append(row)
	for i in order.size():
		_list.move_child(order[i], i)
		order[i].visible = true
	_recent_header.visible = not recent.is_empty()
	var left_in: Dictionary = {}
	_shown = top + recent
	for entry in _entries:
		if not lifted.has(entry["button"]):
			left_in[entry["category"]] = true
			_shown.append(entry)
	for category in _headers:
		_headers[category].visible = left_in.has(category)


func _entry_of(action: String):
	for entry in _entries:
		if entry["action"] == action:
			return entry
	return null


## The entries `query` is in, best first: an exact label, an exact alias, the
## start of the label, the start of a word in it, anywhere in it, in an alias, in
## the key. Each as `{entry, alias}`, with the alias it matched through or "".
static func _ranked(query: String, entries: Array) -> Array:
	var scored: Array = []
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var hit := _match(query, entry)
		if hit[0] > 0:
			scored.append({"entry": entry, "alias": hit[1], "score": hit[0], "index": i})
	scored.sort_custom(_better)
	return scored


static func _match(query: String, entry: Dictionary) -> Array:
	var label: String = entry["label_lower"]
	var aliases: Array = entry.get("aliases", [])
	if label == query:
		return [7, ""]
	if aliases.has(query):
		return [6, query]
	if label.begins_with(query):
		return [5, ""]
	if label.contains(" " + query):
		return [4, ""]
	if label.contains(query):
		return [3, ""]
	for alias in aliases:
		if alias.contains(query):
			return [2, alias]
	if entry["binding_lower"].contains(query):
		return [1, ""]
	return [0, ""]


## The entries whose label, key or an alias holds `query`'s letters in order,
## tightest first, for a search nothing holds whole.
static func _fuzzy_ranked(query: String, entries: Array) -> Array:
	var scored: Array = []
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var best := maxi(
			HFNameMatchType.fuzzy_score(query, entry["label_lower"]),
			HFNameMatchType.fuzzy_score(query, entry["binding_lower"])
		)
		var through := ""
		for alias in entry.get("aliases", []):
			var score := HFNameMatchType.fuzzy_score(query, alias)
			if score > best:
				best = score
				through = alias
		if best > 0:
			scored.append({"entry": entry, "alias": through, "score": best, "index": i})
	scored.sort_custom(_better)
	return scored


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	return a["index"] < b["index"]


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
	for entry in _shown:
		if entry["button"].visible and not entry["button"].disabled:
			_on_entry_pressed(entry["action"])
			return


func _on_entry_pressed(action: String) -> void:
	visible = false
	action_invoked.emit(action)
