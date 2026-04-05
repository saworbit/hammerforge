@tool
extends PanelContainer
## Floating contextual mini-toolbar that appears in the 3D viewport.
##
## Shows context-sensitive actions based on what is selected/hovered:
## - Selected faces → material thumbnails, UV justify, Apply to Whole Brush
## - Selected brushes → extrude, hollow, clip, carve, duplicate
## - Selected entities → I/O connect, property quick-edit
## - Empty/drag mode → drawing primitives, operation toggle, numeric input

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

signal action_requested(action: String, args: Array)
signal operation_toggle_requested
signal tool_switch_requested(tool_id: int)
signal material_quick_apply(index: int)
signal hotkey_palette_requested

enum Context {
	NONE,
	BRUSH_SELECTED,
	FACE_SELECTED,
	ENTITY_SELECTED,
	DRAW_IDLE,
	DRAGGING,
	VERTEX_EDIT,
}

var _context := Context.NONE
var _style: StyleBoxFlat
var _content: HBoxContainer
var _label: Label
var _auto_hint_bar: PanelContainer
var _auto_hint_label: Label
var _auto_hint_btn: Button
var _auto_hint_tween: Tween
var _sections: Dictionary = {}  # Context -> Control
var _material_thumbs: Array[Button] = []
var _favorite_materials: Array = []  # Array of {index, material, texture}
var _brush_count := 0
var _entity_count := 0
var _face_count := 0
var _has_root := false
var _is_subtract := false
var _keymap = null  # HFKeymap


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_style()
	_build_content()
	_build_auto_hint_bar()
	visible = false


func _build_style() -> void:
	_style = HFThemeUtils.make_panel_stylebox()
	_style.content_margin_left = 6
	_style.content_margin_right = 6
	_style.content_margin_top = 4
	_style.content_margin_bottom = 4
	_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", _style)


func _build_content() -> void:
	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)

	# Context label (left side)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_content.add_child(_label)

	var sep = VSeparator.new()
	_content.add_child(sep)

	# Build context-specific sections (all hidden initially)
	_build_brush_section()
	_build_face_section()
	_build_entity_section()
	_build_draw_section()
	_build_drag_section()
	_build_vertex_section()


func _build_auto_hint_bar() -> void:
	_auto_hint_bar = PanelContainer.new()
	var hint_style = StyleBoxFlat.new()
	var dark_theme := HFThemeUtils.is_dark_theme()
	hint_style.bg_color = Color(0.2, 0.3, 0.5, 0.88) if dark_theme else Color(0.7, 0.78, 0.92, 0.88)
	hint_style.set_corner_radius_all(3)
	hint_style.content_margin_left = 8
	hint_style.content_margin_right = 8
	hint_style.content_margin_top = 3
	hint_style.content_margin_bottom = 3
	_auto_hint_bar.add_theme_stylebox_override("panel", hint_style)
	_auto_hint_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_auto_hint_bar.add_child(hbox)

	_auto_hint_label = Label.new()
	_auto_hint_label.add_theme_font_size_override("font_size", 11)
	_auto_hint_label.add_theme_color_override("font_color", HFThemeUtils.primary_text())
	hbox.add_child(_auto_hint_label)

	_auto_hint_btn = Button.new()
	_auto_hint_btn.flat = true
	_auto_hint_btn.focus_mode = Control.FOCUS_NONE
	_auto_hint_btn.add_theme_font_size_override("font_size", 11)
	_auto_hint_btn.add_theme_color_override("font_color", HFThemeUtils.accent())
	_auto_hint_btn.pressed.connect(_on_auto_hint_action)
	hbox.add_child(_auto_hint_btn)

	_auto_hint_bar.visible = false
	add_child(_auto_hint_bar)


# --- Section Builders ---


func _build_brush_section() -> void:
	var section = HBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	_content.add_child(section)
	_sections[Context.BRUSH_SELECTED] = section

	_add_tool_button(section, "Ext\u25b2", "Extrude Up (U)", "extrude_up")
	_add_tool_button(section, "Ext\u25bc", "Extrude Down (J)", "extrude_down")
	_add_sep(section)
	_add_tool_button(section, "Hol", "Hollow (Ctrl+H)", "hollow")
	_add_tool_button(section, "Clip", "Clip (Shift+X)", "clip")
	_add_tool_button(section, "Carve", "Carve (Ctrl+Shift+R)", "carve")
	_add_sep(section)
	_add_tool_button(section, "Dup", "Duplicate (Ctrl+D)", "duplicate")
	_add_tool_button(section, "Del", "Delete (Del)", "delete")
	_add_sep(section)
	_add_tool_button(section, "\u2302", "Set as Player Start", "set_player_start")
	_add_tool_button(section, "Sim", "Select Similar brushes (Shift+S)", "select_similar")
	_add_tool_button(section, "Flt", "Selection Filters (Shift+F)", "selection_filter")
	_add_sep(section)
	_add_tool_button(section, "Pfb", "Save selection as Prefab (Ctrl+Shift+P)", "quick_save_prefab")
	_add_tool_button(section, "Lnk", "Save as Live-Linked Prefab", "quick_save_linked_prefab")
	# Prefab instance buttons — hidden by default, shown when prefab instance selected
	_add_sep(section).name = "PfbSep"
	_add_tool_button(section, "Var\u25b6", "Cycle Variant (Ctrl+Shift+V)", "cycle_variant").name = "PfbVarBtn"
	_add_tool_button(section, "Push", "Push changes to prefab source", "push_to_source").name = "PfbPushBtn"
	_add_tool_button(section, "Pull", "Propagate source to all linked instances", "propagate_prefab").name = "PfbPullBtn"
	_set_prefab_buttons_visible(section, false)


func _build_face_section() -> void:
	var section = HBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	_content.add_child(section)
	_sections[Context.FACE_SELECTED] = section

	# Material thumbnail strip (up to 5 favorites)
	for i in range(5):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(28, 28)
		btn.tooltip_text = "Apply material"
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_material_thumb.bind(i))
		btn.visible = false
		section.add_child(btn)
		_material_thumbs.append(btn)

	_add_sep(section)
	# UV justify buttons
	_add_tool_button(section, "Fit", "UV Fit", "justify_fit")
	_add_tool_button(section, "Ctr", "UV Center", "justify_center")
	_add_tool_button(section, "\u2190", "UV Left", "justify_left")
	_add_tool_button(section, "\u2192", "UV Right", "justify_right")
	_add_tool_button(section, "\u2191", "UV Top", "justify_top")
	_add_tool_button(section, "\u2193", "UV Bottom", "justify_bottom")
	_add_sep(section)
	_add_tool_button(section, "All", "Apply to Whole Brush", "apply_to_brush")
	_add_sep(section)
	_add_tool_button(section, "Sim", "Select Similar faces (Shift+S)", "select_similar")
	_add_tool_button(section, "Last", "Apply Last Texture (Shift+T)", "apply_last_texture")


func _build_entity_section() -> void:
	var section = HBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	_content.add_child(section)
	_sections[Context.ENTITY_SELECTED] = section

	_add_tool_button(section, "I/O", "Edit I/O Connections", "entity_io")
	_add_tool_button(section, "Props", "Quick-Edit Properties", "entity_props")
	_add_sep(section)
	var hl_btn = Button.new()
	hl_btn.text = "HL"
	hl_btn.tooltip_text = "Highlight Connected — pulse linked entities"
	hl_btn.toggle_mode = true
	hl_btn.flat = true
	hl_btn.focus_mode = Control.FOCUS_NONE
	hl_btn.add_theme_font_size_override("font_size", 11)
	hl_btn.custom_minimum_size = Vector2(32, 0)
	hl_btn.toggled.connect(
		func(pressed: bool): action_requested.emit("highlight_connected", [pressed])
	)
	hl_btn.name = "HighlightBtn"
	section.add_child(hl_btn)
	# Connection summary label (updated dynamically)
	var io_summary = Label.new()
	io_summary.name = "IOSummary"
	io_summary.add_theme_font_size_override("font_size", 10)
	io_summary.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.7))
	section.add_child(io_summary)
	_add_sep(section)
	_add_tool_button(section, "Dup", "Duplicate (Ctrl+D)", "duplicate")
	_add_tool_button(section, "Del", "Delete (Del)", "delete")
	_add_sep(section)
	_add_tool_button(section, "Pfb", "Save selection as Prefab (Ctrl+Shift+P)", "quick_save_prefab")
	# Prefab instance buttons — hidden by default, shown when prefab instance selected
	_add_sep(section).name = "PfbSep"
	_add_tool_button(section, "Var\u25b6", "Cycle Variant (Ctrl+Shift+V)", "cycle_variant").name = "PfbVarBtn"
	_add_tool_button(section, "Push", "Push changes to prefab source", "push_to_source").name = "PfbPushBtn"
	_add_tool_button(section, "Pull", "Propagate source to all linked instances", "propagate_prefab").name = "PfbPullBtn"
	_set_prefab_buttons_visible(section, false)


func _build_draw_section() -> void:
	var section = HBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	_content.add_child(section)
	_sections[Context.DRAW_IDLE] = section

	_add_tool_button(section, "Box", "Box brush", "shape_box")
	_add_tool_button(section, "Cyl", "Cylinder brush", "shape_cylinder")
	_add_tool_button(section, "Sph", "Sphere brush", "shape_sphere")
	_add_tool_button(section, "Cone", "Cone brush", "shape_cone")
	_add_sep(section)
	var toggle = Button.new()
	toggle.text = "Add"
	toggle.tooltip_text = "Toggle Add/Subtract — click to switch"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.custom_minimum_size = Vector2(40, 0)
	toggle.pressed.connect(func(): operation_toggle_requested.emit())
	toggle.name = "OpToggle"
	section.add_child(toggle)


func _build_drag_section() -> void:
	var section = HBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	_content.add_child(section)
	_sections[Context.DRAGGING] = section

	var dim_label = Label.new()
	dim_label.name = "DimLabel"
	dim_label.add_theme_font_size_override("font_size", 11)
	dim_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.9))
	section.add_child(dim_label)

	_add_sep(section)
	_add_tool_button(section, "X", "Lock X axis", "axis_x")
	_add_tool_button(section, "Y", "Lock Y axis", "axis_y")
	_add_tool_button(section, "Z", "Lock Z axis", "axis_z")
	_add_sep(section)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.tooltip_text = "Cancel drag (Right-click)"
	cancel_btn.flat = true
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.add_theme_font_size_override("font_size", 11)
	cancel_btn.pressed.connect(func(): action_requested.emit("cancel_drag", []))
	section.add_child(cancel_btn)


func _build_vertex_section() -> void:
	var section = HBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	section.visible = false
	_content.add_child(section)
	_sections[Context.VERTEX_EDIT] = section

	_add_tool_button(section, "Vtx", "Vertex sub-mode", "vertex_submode")
	_add_tool_button(section, "Edge", "Edge sub-mode (E)", "edge_submode")
	_add_sep(section)
	_add_tool_button(section, "Merge", "Merge vertices (Ctrl+W)", "vertex_merge")
	_add_tool_button(section, "Split", "Split edge (Ctrl+E)", "vertex_split")
	_add_tool_button(section, "Convex", "Clip to convex hull", "vertex_clip_convex")
	_add_sep(section)
	_add_tool_button(section, "Exit", "Exit vertex mode (V)", "vertex_exit")


# --- Helpers ---


func _add_tool_button(parent: Control, text: String, tooltip: String, action: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(32, 0)
	btn.pressed.connect(func(): action_requested.emit(action, []))
	parent.add_child(btn)
	return btn


func _add_sep(parent: Control) -> VSeparator:
	var sep = VSeparator.new()
	parent.add_child(sep)
	return sep


# --- Public API ---


func refresh_theme_colors() -> void:
	_build_style()
	if _label:
		_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())


func set_keymap(keymap) -> void:
	_keymap = keymap


func update_state(state: Dictionary) -> void:
	var new_context := _determine_context(state)
	var should_show: bool = new_context != Context.NONE and state.get("has_root", false)

	if new_context != _context:
		_context = new_context
		_apply_context(state)

	# Update dynamic content even if context didn't change
	_update_dynamic_content(state)

	visible = should_show

	# Auto-hint bar for drag mode suggestion
	_update_auto_hint(state)


func set_favorite_materials(materials: Array) -> void:
	_favorite_materials = materials
	_refresh_material_thumbs()


# --- Context Logic ---


func _determine_context(state: Dictionary) -> Context:
	if not state.get("has_root", false):
		return Context.NONE

	var mode: int = state.get("input_mode", 0)

	# Vertex editing
	if state.get("vertex_mode", false) or mode == 5:
		return Context.VERTEX_EDIT

	# Dragging (base or height)
	if mode == 1 or mode == 2:
		return Context.DRAGGING

	# Face selection active
	if state.get("face_count", 0) > 0:
		return Context.FACE_SELECTED

	# Entity selected
	if state.get("entity_count", 0) > 0:
		return Context.ENTITY_SELECTED

	# Brush selected
	if state.get("brush_count", 0) > 0:
		return Context.BRUSH_SELECTED

	# Draw tool idle
	var tool_id: int = state.get("tool", 0)
	if tool_id == 0 and mode == 0:
		return Context.DRAW_IDLE

	return Context.NONE


func _apply_context(state: Dictionary) -> void:
	# Hide all sections
	for ctx_key in _sections:
		_sections[ctx_key].visible = false

	# Show active section
	if _sections.has(_context):
		_sections[_context].visible = true

	# Prefab instance info badge
	var pfb_src: String = state.get("prefab_source", "")
	var pfb_variant: String = state.get("prefab_variant", "")
	var pfb_linked: bool = state.get("prefab_linked", false)
	var is_prefab_context: bool = (
		pfb_src != ""
		and (_context == Context.BRUSH_SELECTED or _context == Context.ENTITY_SELECTED)
	)
	# Show/hide prefab instance buttons on relevant sections
	for ctx_key in [Context.BRUSH_SELECTED, Context.ENTITY_SELECTED]:
		var sec = _sections.get(ctx_key)
		if sec:
			_set_prefab_buttons_visible(sec, is_prefab_context and _context == ctx_key)

	if is_prefab_context:
		var pfb_name: String = pfb_src.get_file().get_basename()
		var badge := pfb_name
		if pfb_variant != "" and pfb_variant != "base":
			badge += " (%s)" % pfb_variant
		if pfb_linked:
			badge += " [linked]"
		_label.text = badge
		return

	# Update label with selection count badge
	match _context:
		Context.BRUSH_SELECTED:
			var bc: int = state.get("brush_count", 0)
			var ec: int = state.get("entity_count", 0)
			if ec > 0:
				_label.text = (
					"%d brush%s + %d entit%s"
					% [bc, "" if bc == 1 else "es", ec, "y" if ec == 1 else "ies"]
				)
			else:
				_label.text = "%d brush%s selected" % [bc, "" if bc == 1 else "es"]
		Context.FACE_SELECTED:
			var fc: int = state.get("face_count", 0)
			var bc: int = state.get("brush_count", 0)
			if bc > 0:
				_label.text = (
					"%d face%s on %d brush%s"
					% [fc, "" if fc == 1 else "s", bc, "" if bc == 1 else "es"]
				)
			else:
				_label.text = "%d face%s selected" % [fc, "" if fc == 1 else "s"]
		Context.ENTITY_SELECTED:
			var count: int = state.get("entity_count", 0)
			_label.text = "%d entit%s selected" % [count, "y" if count == 1 else "ies"]
		Context.DRAW_IDLE:
			_label.text = "Draw"
		Context.DRAGGING:
			_label.text = "Drawing"
		Context.VERTEX_EDIT:
			_label.text = "Vertex"
		_:
			_label.text = ""


func _update_dynamic_content(state: Dictionary) -> void:
	# Update entity I/O summary badge and highlight toggle
	if _context == Context.ENTITY_SELECTED:
		var section = _sections.get(Context.ENTITY_SELECTED)
		if section:
			var io_summary = section.get_node_or_null("IOSummary")
			if io_summary:
				var io_text: String = state.get("io_summary", "")
				io_summary.text = io_text
				io_summary.visible = io_text != ""
			# Sync highlight button pressed state from the authoritative visualizer
			var hl_btn = section.get_node_or_null("HighlightBtn") as Button
			if hl_btn and state.has("highlight_connected"):
				var hl_state: bool = state["highlight_connected"]
				if hl_btn.button_pressed != hl_state:
					hl_btn.set_pressed_no_signal(hl_state)

	# Update operation toggle label
	if _context == Context.DRAW_IDLE:
		var section = _sections.get(Context.DRAW_IDLE)
		if section:
			var toggle = section.get_node_or_null("OpToggle")
			if toggle:
				var is_sub: bool = state.get("is_subtract", false)
				toggle.text = "Sub" if is_sub else "Add"
				var c = Color(0.9, 0.5, 0.4) if is_sub else Color(0.5, 0.9, 0.5)
				toggle.add_theme_color_override("font_color", c)

	# Update drag dimensions
	if _context == Context.DRAGGING:
		var section = _sections.get(Context.DRAGGING)
		if section:
			var dim_label = section.get_node_or_null("DimLabel")
			if dim_label:
				var dims: String = state.get("dimensions", "")
				dim_label.text = dims if dims != "" else "..."


func _update_auto_hint(state: Dictionary) -> void:
	var mode: int = state.get("input_mode", 0)
	var tool_id: int = state.get("tool", 0)

	# Show auto-hint when dragging in Draw mode with Add operation
	if mode == 1 and tool_id == 0:
		var is_sub: bool = state.get("is_subtract", false)
		if is_sub:
			_show_auto_hint("Drawing in Subtract mode", "Switch to Add", "toggle_add")
		else:
			_show_auto_hint(
				"Drawing in Add mode \u2014 press Subtract to toggle",
				"Switch to Subtract",
				"toggle_subtract"
			)
		return

	# Show hint when selecting brushes without selection tools visible
	if tool_id == 1 and state.get("brush_count", 0) > 0:
		_hide_auto_hint()
		return

	_hide_auto_hint()


var _auto_hint_action := ""


func _show_auto_hint(text: String, btn_text: String, action: String) -> void:
	_auto_hint_label.text = text
	_auto_hint_btn.text = btn_text
	_auto_hint_action = action
	if not _auto_hint_bar.visible:
		_auto_hint_bar.visible = true
		_auto_hint_bar.modulate = Color(1, 1, 1, 0)
		if _auto_hint_tween and _auto_hint_tween.is_valid():
			_auto_hint_tween.kill()
		_auto_hint_tween = create_tween()
		_auto_hint_tween.tween_property(_auto_hint_bar, "modulate:a", 1.0, 0.2)


func _hide_auto_hint() -> void:
	if _auto_hint_bar.visible:
		_auto_hint_bar.visible = false
		if _auto_hint_tween and _auto_hint_tween.is_valid():
			_auto_hint_tween.kill()


func _on_auto_hint_action() -> void:
	match _auto_hint_action:
		"toggle_add":
			operation_toggle_requested.emit()
		"toggle_subtract":
			operation_toggle_requested.emit()
	_hide_auto_hint()


func _on_material_thumb(index: int) -> void:
	if index < _favorite_materials.size():
		var mat_idx: int = _favorite_materials[index].get("index", -1)
		if mat_idx >= 0:
			material_quick_apply.emit(mat_idx)


func _set_prefab_buttons_visible(section: Control, vis: bool) -> void:
	for child_name in ["PfbSep", "PfbVarBtn", "PfbPushBtn", "PfbPullBtn"]:
		var child = section.get_node_or_null(child_name)
		if child:
			child.visible = vis


func _refresh_material_thumbs() -> void:
	for i in range(_material_thumbs.size()):
		var btn = _material_thumbs[i]
		if i < _favorite_materials.size():
			var info = _favorite_materials[i]
			btn.text = str(i + 1)
			btn.tooltip_text = "Apply: %s" % info.get("name", "Material %d" % info.get("index", i))
			btn.visible = true
		else:
			btn.visible = false
