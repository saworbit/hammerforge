@tool
extends VBoxContainer
class_name HFMaterialBrowser
## Visual texture browser with thumbnail grid, search, pattern/color filters,
## favorites, and drag-and-drop support.

signal material_selected(index: int)
signal material_double_clicked(index: int)
signal material_drag_started(index: int, at_position: Vector2)
signal material_context_menu(index: int, global_pos: Vector2)
signal material_hovered(index: int)
signal material_hover_ended

const THUMB_SIZE := 64
const GRID_COLUMNS := 5

## Color swatches keyed by HFPrototypeTextures color name.
const COLOR_HEX: Dictionary = {
	"blue": Color(0.2, 0.4, 0.9),
	"brown": Color(0.55, 0.35, 0.17),
	"cyan": Color(0.0, 0.8, 0.8),
	"green": Color(0.2, 0.7, 0.2),
	"grey": Color(0.5, 0.5, 0.5),
	"orange": Color(0.95, 0.55, 0.1),
	"pink": Color(0.95, 0.45, 0.65),
	"purple": Color(0.55, 0.25, 0.85),
	"red": Color(0.85, 0.2, 0.2),
	"yellow": Color(0.95, 0.85, 0.15),
}

enum ViewMode { PROTOTYPES, PALETTE, FAVORITES }

var _search_line: LineEdit
var _pattern_filter: OptionButton
var _color_filter_row: HBoxContainer
var _view_toggle: OptionButton
var _scroll: ScrollContainer
var _grid: GridContainer
var _status_label: Label

## Maps grid child index -> palette material index.
var _cell_to_palette_index: Array[int] = []
## Current selected palette index (-1 = none).
var _selected_index: int = -1
## View mode.
var _view_mode: int = ViewMode.PROTOTYPES
## Active color filter ("" = all).
var _active_color_filter: String = ""
## Active pattern filter ("" = all).
var _active_pattern_filter: String = ""
## Search text.
var _search_text: String = ""
## Favorites set (material resource paths).
var _favorites: Dictionary = {}
## Reference to the material manager.
var _material_manager: MaterialManager = null
## Cached textures for prototype materials (material_path -> Texture2D).
var _thumb_cache: Dictionary = {}


func _ready() -> void:
	# --- Search bar ---
	_search_line = LineEdit.new()
	_search_line.placeholder_text = "Search textures..."
	_search_line.clear_button_enabled = true
	_search_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_line.text_changed.connect(_on_search_changed)
	add_child(_search_line)

	# --- Filters row ---
	var filter_row = HBoxContainer.new()
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(filter_row)

	# Pattern dropdown
	_pattern_filter = OptionButton.new()
	_pattern_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pattern_filter.add_item("All Patterns", 0)
	for i in range(HFPrototypeTextures.PATTERNS.size()):
		_pattern_filter.add_item(
			HFPrototypeTextures.PATTERNS[i].replace("_", " ").capitalize(), i + 1
		)
	_pattern_filter.item_selected.connect(_on_pattern_filter_changed)
	filter_row.add_child(_pattern_filter)

	# View toggle
	_view_toggle = OptionButton.new()
	_view_toggle.add_item("Prototypes", ViewMode.PROTOTYPES)
	_view_toggle.add_item("Palette", ViewMode.PALETTE)
	_view_toggle.add_item("Favorites", ViewMode.FAVORITES)
	_view_toggle.item_selected.connect(_on_view_mode_changed)
	filter_row.add_child(_view_toggle)

	# --- Color swatch row ---
	_color_filter_row = HBoxContainer.new()
	_color_filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_color_filter_row)
	_build_color_swatches()

	# --- Scroll + Grid ---
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 180)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	# --- Status ---
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)


func set_material_manager(manager: MaterialManager) -> void:
	_material_manager = manager
	rebuild()


func get_selected_index() -> int:
	return _selected_index


func set_selected_index(index: int) -> void:
	_selected_index = index
	_update_selection_visual()


func add_favorite(resource_path: String) -> void:
	_favorites[resource_path] = true


func remove_favorite(resource_path: String) -> void:
	_favorites.erase(resource_path)


func is_favorite(resource_path: String) -> bool:
	return _favorites.has(resource_path)


## Returns up to `limit` favorite materials as [{index, name}] for the context toolbar.
func get_favorite_infos(limit: int = 5) -> Array:
	var result: Array = []
	if not _material_manager:
		return result
	for i in range(_material_manager.materials.size()):
		if result.size() >= limit:
			break
		var mat = _material_manager.materials[i]
		if mat == null:
			continue
		var mat_path: String = mat.resource_path
		if not _favorites.has(mat_path):
			continue
		var mat_name: String = mat.resource_name if mat.resource_name != "" else mat_path.get_file()
		result.append({"index": i, "name": mat_name})
	return result


## Full rebuild of the thumbnail grid.
func rebuild() -> void:
	if not _grid:
		return
	_clear_grid()

	if _view_mode == ViewMode.PROTOTYPES:
		_build_prototype_grid()
	elif _view_mode == ViewMode.PALETTE:
		_build_palette_grid()
	elif _view_mode == ViewMode.FAVORITES:
		_build_favorites_grid()

	_update_status()
	_update_selection_visual()


# ---------------------------------------------------------------------------
# Grid builders
# ---------------------------------------------------------------------------


func _build_prototype_grid() -> void:
	if not _material_manager:
		return
	for i in range(_material_manager.materials.size()):
		var mat = _material_manager.materials[i]
		if mat == null:
			continue
		var mat_path: String = mat.resource_path
		# Only show prototype materials in this view.
		if not mat_path.begins_with(HFPrototypeTextures.MATERIALS_DIR):
			continue
		if not _passes_filters(mat_path, mat):
			continue
		_add_thumb_cell(i, mat, mat_path)


func _build_palette_grid() -> void:
	if not _material_manager:
		return
	for i in range(_material_manager.materials.size()):
		var mat = _material_manager.materials[i]
		if mat == null:
			continue
		var mat_path: String = mat.resource_path
		if not _passes_filters(mat_path, mat):
			continue
		_add_thumb_cell(i, mat, mat_path)


func _build_favorites_grid() -> void:
	if not _material_manager:
		return
	for i in range(_material_manager.materials.size()):
		var mat = _material_manager.materials[i]
		if mat == null:
			continue
		var mat_path: String = mat.resource_path
		if not _favorites.has(mat_path):
			continue
		if not _passes_filters(mat_path, mat):
			continue
		_add_thumb_cell(i, mat, mat_path)


func _passes_filters(mat_path: String, mat: Material) -> bool:
	# Pattern filter
	if _active_pattern_filter != "":
		if mat_path.find(_active_pattern_filter) < 0:
			return false
	# Color filter
	if _active_color_filter != "":
		if (
			mat_path.find("_" + _active_color_filter + ".") < 0
			and mat_path.find("_" + _active_color_filter + "/") < 0
		):
			# For non-prototype materials, skip color filter entirely
			if not mat_path.begins_with(HFPrototypeTextures.MATERIALS_DIR):
				pass
			else:
				return false
	# Search text
	if _search_text != "":
		var label = _get_material_label(mat)
		if label.to_lower().find(_search_text.to_lower()) < 0:
			return false
	return true


func _add_thumb_cell(palette_index: int, mat: Material, mat_path: String) -> void:
	var cell = _create_thumb_button(palette_index, mat, mat_path)
	_grid.add_child(cell)
	_cell_to_palette_index.append(palette_index)


func _create_thumb_button(palette_index: int, mat: Material, mat_path: String) -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(THUMB_SIZE + 8, THUMB_SIZE + 22)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Thumbnail
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	tex_rect.texture = _get_thumbnail(mat, mat_path)
	container.add_child(tex_rect)

	# Label
	var label = Label.new()
	label.text = _get_short_label(mat, mat_path)
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = THUMB_SIZE
	container.add_child(label)

	# Tooltip
	var tip := _get_material_label(mat)
	if _favorites.has(mat_path):
		tip += " [Favorite]"
	tip += (
		"\n\nLeft-click: Select material"
		+ "\nHover: Preview on selected faces"
		+ "\nDouble-click: Apply to selected faces"
		+ "\nRight-click: Apply to whole brush, favorite, copy name"
	)
	container.tooltip_text = tip

	# Wrap in a button-like panel for click/hover
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(THUMB_SIZE + 8, THUMB_SIZE + 22)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	btn.add_child(container)
	var cell_idx: int = _cell_to_palette_index.size()
	btn.pressed.connect(_on_cell_pressed.bind(cell_idx))
	btn.mouse_entered.connect(_on_cell_mouse_entered.bind(cell_idx))
	btn.mouse_exited.connect(_on_cell_mouse_exited)
	btn.gui_input.connect(_on_cell_gui_input.bind(cell_idx))
	btn.set_drag_forwarding(_get_drag_data_for_index.bind(cell_idx), Callable(), Callable())

	return btn


func _get_thumbnail(mat: Material, mat_path: String) -> Texture2D:
	if _thumb_cache.has(mat_path):
		return _thumb_cache[mat_path]

	var tex: Texture2D = null
	# For prototype materials, load the matching SVG.
	if mat_path.begins_with(HFPrototypeTextures.MATERIALS_DIR):
		var filename: String = mat_path.get_file().trim_prefix("proto_").replace(".tres", ".svg")
		var svg_path: String = HFPrototypeTextures.BASE_DIR + filename
		if ResourceLoader.exists(svg_path):
			tex = ResourceLoader.load(svg_path)
	# For StandardMaterial3D, try albedo texture.
	if tex == null and mat is StandardMaterial3D:
		tex = (mat as StandardMaterial3D).albedo_texture
	_thumb_cache[mat_path] = tex
	return tex


func _get_material_label(mat: Material) -> String:
	if mat.resource_name != "":
		return mat.resource_name
	var f: String = mat.resource_path.get_file()
	if f != "":
		return f.get_basename()
	return "Material"


func _get_short_label(mat: Material, mat_path: String) -> String:
	var full = _get_material_label(mat)
	# Strip "proto_" prefix for prototype materials.
	if full.begins_with("proto_"):
		full = full.substr(6)
	return full


# ---------------------------------------------------------------------------
# Grid interaction
# ---------------------------------------------------------------------------


func _on_cell_pressed(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _cell_to_palette_index.size():
		return
	_selected_index = _cell_to_palette_index[cell_index]
	_update_selection_visual()
	material_selected.emit(_selected_index)


func _on_cell_mouse_entered(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _cell_to_palette_index.size():
		return
	material_hovered.emit(_cell_to_palette_index[cell_index])


func _on_cell_mouse_exited() -> void:
	material_hover_ended.emit()


func _on_cell_gui_input(event: InputEvent, cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _cell_to_palette_index.size():
		return
	if event is InputEventMouseButton and event.pressed:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			var palette_idx = _cell_to_palette_index[cell_index]
			material_context_menu.emit(palette_idx, mb.global_position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			# Double-click = select + apply immediately
			var palette_idx = _cell_to_palette_index[cell_index]
			_selected_index = palette_idx
			_update_selection_visual()
			material_double_clicked.emit(palette_idx)


func _update_selection_visual() -> void:
	for i in range(_grid.get_child_count()):
		var btn = _grid.get_child(i) as Button
		if not btn:
			continue
		if i < _cell_to_palette_index.size() and _cell_to_palette_index[i] == _selected_index:
			btn.add_theme_stylebox_override("normal", _make_selected_stylebox())
		else:
			btn.remove_theme_stylebox_override("normal")


func _make_selected_stylebox() -> StyleBox:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.5, 1.0, 0.3)
	sb.border_color = Color(0.4, 0.6, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	return sb


# ---------------------------------------------------------------------------
# Drag support
# ---------------------------------------------------------------------------


## Per-button drag forwarding callback. Bound with .bind(cell_idx) in
## _create_thumb_button() so each grid button provides its own drag data.
func _get_drag_data_for_index(at_position: Vector2, cell_idx: int) -> Variant:
	if cell_idx < 0 or cell_idx >= _cell_to_palette_index.size():
		return null
	var palette_idx: int = _cell_to_palette_index[cell_idx]
	var mat = _material_manager.get_material(palette_idx) if _material_manager else null
	var preview = _build_drag_preview(mat)
	if preview:
		var used := false
		if get_viewport() and get_viewport().gui_is_dragging():
			var btn = _grid.get_child(cell_idx) as Control
			if btn:
				btn.set_drag_preview(preview)
				used = true
		if not used:
			preview.free()
	material_drag_started.emit(palette_idx, at_position)
	return {"type": "hammerforge_material", "index": palette_idx}


## Legacy helper — finds the cell at global position and delegates.
func get_drag_data_for_cell(at_position: Vector2) -> Variant:
	for i in range(_grid.get_child_count()):
		var btn = _grid.get_child(i) as Button
		if not btn:
			continue
		if btn.get_global_rect().has_point(at_position):
			return _get_drag_data_for_index(at_position, i)
	return null


func _build_drag_preview(mat: Material) -> Control:
	if mat == null:
		return null
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(120, 36)
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(32, 32)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	tex_rect.texture = _get_thumbnail(mat, mat.resource_path)
	hbox.add_child(tex_rect)
	var lbl = Label.new()
	lbl.text = _get_short_label(mat, mat.resource_path)
	hbox.add_child(lbl)
	return hbox


# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------


func _build_color_swatches() -> void:
	# "All" button
	var all_btn = Button.new()
	all_btn.text = "All"
	all_btn.custom_minimum_size = Vector2(32, 20)
	all_btn.add_theme_font_size_override("font_size", 10)
	all_btn.pressed.connect(_on_color_filter.bind(""))
	_color_filter_row.add_child(all_btn)
	# Color buttons
	for color_name in HFPrototypeTextures.COLORS:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(20, 20)
		btn.tooltip_text = color_name.capitalize()
		var sb = StyleBoxFlat.new()
		sb.bg_color = COLOR_HEX.get(color_name, Color.WHITE)
		sb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", sb)
		var sb_hover = sb.duplicate()
		sb_hover.border_color = Color.WHITE
		sb_hover.set_border_width_all(2)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.pressed.connect(_on_color_filter.bind(color_name))
		_color_filter_row.add_child(btn)


func _on_color_filter(color_name: String) -> void:
	_active_color_filter = color_name
	rebuild()


func _on_pattern_filter_changed(idx: int) -> void:
	if idx == 0:
		_active_pattern_filter = ""
	else:
		_active_pattern_filter = HFPrototypeTextures.PATTERNS[idx - 1]
	rebuild()


func _on_view_mode_changed(idx: int) -> void:
	_view_mode = idx
	rebuild()


func _on_search_changed(text: String) -> void:
	_search_text = text
	rebuild()


# ---------------------------------------------------------------------------
# Context menu
# ---------------------------------------------------------------------------


func create_context_popup() -> PopupMenu:
	var popup = PopupMenu.new()
	popup.add_item("Apply to Selected Faces", 0)
	popup.add_item("Apply to Whole Brush", 1)
	popup.add_item("Apply + Re-project (Box UV)", 4)
	popup.add_separator()
	popup.add_item("Toggle Favorite", 2)
	popup.add_separator()
	popup.add_item("Copy Name", 3)
	return popup


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _clear_grid() -> void:
	_cell_to_palette_index.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()


func _update_status() -> void:
	if not _status_label:
		return
	var shown = _cell_to_palette_index.size()
	var total = _material_manager.materials.size() if _material_manager else 0
	if shown == 0 and total == 0:
		_status_label.text = "No materials loaded. Use Refresh Prototypes to add."
	elif shown == 0:
		_status_label.text = "No materials match filters (%d total)" % total
	elif shown == total:
		_status_label.text = "%d materials" % shown
	else:
		_status_label.text = "%d of %d materials" % [shown, total]
