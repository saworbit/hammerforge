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
## The Hidden swatch was pressed: make the selected faces Hidden (#1719).
signal hidden_swatch_applied
## How many materials the grid shows, for the dock to put in the section header
## rather than on a row of its own.
signal status_changed(text: String)
## A Recent material the level's palette does not hold was clicked. The dock adds
## it to the palette, as the Add button would, and selects it.
signal material_add_requested(path: String)

const HFUIFactoryType = preload("hf_ui_factory.gd")
const HFHiddenFaces = preload("../hf_hidden_faces.gd")
const HFTranslationType = preload("res://addons/hammerforge/hf_translation.gd")

const THUMB_SIZE := 64
## The thumbnail sizes the size slider goes between, in pixels (#1725).
const THUMB_SIZE_MIN := 48
const THUMB_SIZE_MAX := 192
## The Recent row's thumbnails, smaller than the grid's so the row stays one line.
const RECENT_THUMB_SIZE := 32
## How many favourites have a number: the context toolbar's strip and Alt+1 to
## Alt+9 (#1439). The first nine in palette order, the order the strip shows.
const FAVORITE_SLOTS := 9
## Thumbnails a row before the browser knows its width. After that the row holds
## as many as fit, see _fit_grid_columns().
const GRID_COLUMNS := 5
## Rows of thumbnails the grid keeps however short the dock is. The grid takes
## whatever height the tab has left above that, so a 1200 px dock shows four
## rows (#1332). A floor of four held the Paint tab past a 1000 px dock, and the
## tab scrolled with the grid inside it (#1366).
const GRID_MIN_ROWS := 2

## The width the search field keeps when the filters share its row, so a narrow
## dock moves the view picker to a line of its own before the field gets too
## short to type in.
const SEARCH_MIN_WIDTH := 120

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

## In Use lists what the open level's faces wear, most used first (#1725).
enum ViewMode { PROTOTYPES, PALETTE, FAVORITES, IN_USE }

var _search_line: LineEdit
var _pattern_filter: OptionButton
var _color_filter_row: HBoxContainer
var _view_toggle: OptionButton
var _scroll: ScrollContainer
var _grid: GridContainer
var _recent_row: HBoxContainer
var _recent_cells: HBoxContainer

## Maps grid child index -> palette material index, or -1 for a marker cell
## that has no material to pick: a missing favourite or an empty palette slot.
var _cell_to_palette_index: Array[int] = []
## Marker cells by grid child index: {"favorite": path} for a starred material
## whose file is gone, {"slot": index} for an empty palette slot (#1422).
var _cell_markers: Dictionary = {}
## The path the marker menu was opened on.
var _marker_menu_path := ""
var _marker_menu: PopupMenu
## Recent materials the palette does not hold, loaded once for their thumbnail
## and name (path -> Material).
var _recent_loaded: Dictionary = {}
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
var _user_prefs = null  # HFUserPrefs
## Reference to the material manager.
var _material_manager: MaterialManager = null
## Cached textures for prototype materials (material_path -> Texture2D).
var _thumb_cache: Dictionary = {}
## How many faces of the open level use each palette slot, asked of
## `use_provider` at each redraw (#1725), and the switches that read it.
var use_provider: Callable = Callable()
var _use_counts: Dictionary = {}
var _size_slider: HSlider
## The Hidden swatch (#1719), beside the colour filters rather than in the grid, so
## it is there whatever the view and the search, and every cell of the grid is a slot.
var hidden_swatch: Button
## The thumbnail size, kept in the preferences as `material_thumb_size`.
var _thumb_size: int = THUMB_SIZE


func _ready() -> void:
	# --- Search and filters, one row while the dock is wide enough ---
	var filter_row := HFUIFactoryType.make_wrap_row()
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(filter_row)

	_search_line = LineEdit.new()
	_search_line.placeholder_text = "Search textures..."
	_search_line.clear_button_enabled = true
	_search_line.custom_minimum_size.x = SEARCH_MIN_WIDTH
	_search_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_line.text_changed.connect(_on_search_changed)
	filter_row.add_child(_search_line)

	# Pattern dropdown
	_pattern_filter = OptionButton.new()
	_pattern_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pattern_filter.add_item("All Patterns", 0)
	for i in range(HFPrototypeTextures.PATTERNS.size()):
		_pattern_filter.add_item(
			HFPrototypeTextures.PATTERNS[i].replace("_", " ").capitalize(), i + 1
		)
	_pattern_filter.item_selected.connect(_on_pattern_filter_changed)
	HFUIFactoryType.fit_option(_pattern_filter)
	filter_row.add_child(_pattern_filter)

	# View toggle
	_view_toggle = OptionButton.new()
	_view_toggle.add_item("Prototypes", ViewMode.PROTOTYPES)
	_view_toggle.add_item("Palette", ViewMode.PALETTE)
	_view_toggle.add_item("Favorites", ViewMode.FAVORITES)
	_view_toggle.add_item("In Use", ViewMode.IN_USE)
	_view_toggle.item_selected.connect(_on_view_mode_changed)
	_view_toggle.fit_to_longest_item = false
	filter_row.add_child(_view_toggle)

	# How big the thumbnails are (#1725), in the same row, so the Paint tab is no
	# taller for it.
	_size_slider = HSlider.new()
	_size_slider.name = "ThumbSize"
	_size_slider.min_value = THUMB_SIZE_MIN
	_size_slider.max_value = THUMB_SIZE_MAX
	_size_slider.step = 8
	_size_slider.value = _thumb_size
	_size_slider.custom_minimum_size.x = 48
	_size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size_slider.tooltip_text = "Thumbnail size"
	_size_slider.value_changed.connect(_on_thumb_size_changed)
	filter_row.add_child(_size_slider)

	# --- Color swatch row ---
	_color_filter_row = HBoxContainer.new()
	_color_filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_color_filter_row)
	_build_color_swatches()

	# Not a material: a face made Hidden keeps its slot, wears these stripes in
	# the editor and is left out of the bake's mesh and lightmap (#1719). At the
	# end of the colour row, which has room, so the browser is no taller for it.
	hidden_swatch = Button.new()
	hidden_swatch.name = "HiddenSwatch"
	# Narrow and stretched like the colour swatches, so it does not set how narrow
	# the dock can be. The stripes are its face.
	hidden_swatch.custom_minimum_size = Vector2(14, 20)
	hidden_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stripes := StyleBoxTexture.new()
	stripes.texture = HFHiddenFaces.swatch_texture(20)
	hidden_swatch.add_theme_stylebox_override("normal", stripes)
	var lit := stripes.duplicate() as StyleBoxTexture
	lit.modulate_color = Color(1.3, 1.3, 1.3)
	hidden_swatch.add_theme_stylebox_override("hover", lit)
	hidden_swatch.add_theme_stylebox_override("pressed", lit)
	hidden_swatch.tooltip_text = (
		"Hidden: for a face nobody will see, such as the underside of a floor or the"
		+ " back of a wall against another. It keeps its collision, and the bake leaves"
		+ " it out of the mesh and the lightmap."
		+ "\n\nClick: make the selected faces Hidden"
		+ "\nDrag onto a face: make it Hidden"
		+ "\nA material applied to a Hidden face shows it again"
	)
	hidden_swatch.pressed.connect(func(): hidden_swatch_applied.emit())
	hidden_swatch.set_drag_forwarding(_hidden_drag_data, Callable(), Callable())
	_color_filter_row.add_child(hidden_swatch)

	# --- Recent materials, newest first, hidden while there are none ---
	_recent_row = HBoxContainer.new()
	_recent_row.name = "RecentRow"
	_recent_row.visible = false
	add_child(_recent_row)
	var recent_label := Label.new()
	recent_label.text = "Recent"
	recent_label.add_theme_font_size_override("font_size", 10)
	recent_label.add_theme_color_override("font_color", HFThemeUtils.muted_text())
	_recent_row.add_child(recent_label)
	_recent_cells = HBoxContainer.new()
	_recent_cells.name = "RecentCells"
	_recent_cells.add_theme_constant_override("separation", 2)
	_recent_row.add_child(_recent_cells)

	# --- Scroll + Grid ---
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Not DISABLED: that makes the grid's width the browser's minimum width, and
	# five thumbnails a row held the Paint tab at 376 px however narrow the dock.
	# The columns follow the width instead, so nothing needs scrolling sideways.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.resized.connect(_fit_grid_columns)
	add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	var gap := _grid.get_theme_constant("v_separation")
	_scroll.custom_minimum_size.y = GRID_MIN_ROWS * (THUMB_SIZE + 22) + (GRID_MIN_ROWS - 1) * gap
	# The preferences may have been handed over before the row existed.
	refresh_recent()


func set_material_manager(manager: MaterialManager) -> void:
	_material_manager = manager
	rebuild()
	refresh_recent()


## Hand the browser the preferences its favourites live in.
##
## Without this the stars lived on the control and the control is rebuilt by the
## dock, so they were gone at the next theme change or project reload.
func set_user_prefs(prefs) -> void:
	_user_prefs = prefs
	_favorites.clear()
	if _user_prefs:
		for path in _user_prefs.get_favorite_materials():
			var text := str(path)
			if text != "":
				_favorites[text] = true
		_thumb_size = clampi(
			int(_user_prefs.get_pref("material_thumb_size", THUMB_SIZE)),
			THUMB_SIZE_MIN,
			THUMB_SIZE_MAX
		)
		if _size_slider:
			_size_slider.set_value_no_signal(_thumb_size)
	rebuild()
	refresh_recent()


func get_selected_index() -> int:
	return _selected_index


## Show the palette, where a palette slot can be seen selected.
func show_palette() -> void:
	if _view_mode == ViewMode.PALETTE:
		return
	if _view_toggle:
		_view_toggle.select(ViewMode.PALETTE)
	_on_view_mode_changed(ViewMode.PALETTE)


func set_selected_index(index: int) -> void:
	_selected_index = index
	_update_selection_visual()


## Star a material. False when it cannot be starred, so the caller can say why.
##
## A material built in the editor session and not written to disk has an empty
## `resource_path`, and that is what a favourite is keyed on - so every unsaved
## material in the palette shared one key. Starring one starred the lot, and
## un-starring any one of them cleared them all. There is no way to tell two of
## them apart from here, and the palette index that could is only stable while
## the palette is, which is no good for something that outlives the level.
func add_favorite(resource_path: String) -> bool:
	if resource_path == "":
		return false
	_favorites[resource_path] = true
	_write_favorites()
	return true


func remove_favorite(resource_path: String) -> void:
	if resource_path == "":
		return
	_favorites.erase(resource_path)
	_write_favorites()


func is_favorite(resource_path: String) -> bool:
	return resource_path != "" and _favorites.has(resource_path)


func _write_favorites() -> void:
	if not _user_prefs:
		return
	var paths: Array = []
	for path in _favorites.keys():
		paths.append(str(path))
	_user_prefs.set_favorite_materials(paths)


## Returns up to `limit` favorite materials as [{index, name}] for the context
## toolbar, in palette order. Entry N - 1 is favourite N: the strip's button, Alt+N
## and the number on the Favorites view's thumbnail all read this order.
func get_favorite_infos(limit: int = FAVORITE_SLOTS) -> Array:
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
		if not is_favorite(mat_path):
			continue
		result.append({"index": i, "name": MaterialManager.material_label(mat)})
	return result


## Full rebuild of the thumbnail grid.
func rebuild() -> void:
	if not _grid:
		return
	_use_counts = use_provider.call() if use_provider.is_valid() else {}
	_clear_grid()

	if _view_mode == ViewMode.PROTOTYPES:
		_build_prototype_grid()
	elif _view_mode == ViewMode.PALETTE:
		_build_palette_grid()
	elif _view_mode == ViewMode.FAVORITES:
		_build_favorites_grid()
	elif _view_mode == ViewMode.IN_USE:
		_build_in_use_grid()

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


## The materials the open level's faces wear, most used first, through the same
## search and filters (#1725).
func _build_in_use_grid() -> void:
	if not _material_manager:
		return
	var cells: Array = []
	for i in range(_material_manager.materials.size()):
		var mat = _material_manager.materials[i]
		if mat == null or use_count(i) == 0:
			continue
		var mat_path: String = mat.resource_path
		if _passes_filters(mat_path, mat):
			cells.append([i, mat, mat_path])
	cells.sort_custom(func(a, b): return use_count(a[0]) > use_count(b[0]))
	for cell in cells:
		_add_thumb_cell(cell[0], cell[1], cell[2])


func _build_palette_grid() -> void:
	if not _material_manager:
		return
	for i in range(_material_manager.materials.size()):
		var mat = _material_manager.materials[i]
		if mat == null:
			# Faces index the palette, so an empty slot stays where it is, and is
			# shown there rather than left out with every later slot seeming to
			# move up one. A filter narrows materials, and this is not one.
			if not _filters_active():
				var empty_tip := (
					"Slot %d is empty: its material could not be found." % i
					+ "\nFaces that use it keep the slot."
				)
				_add_marker_cell({"slot": i}, "Slot %d" % i, empty_tip)
			continue
		var mat_path: String = mat.resource_path
		if not _passes_filters(mat_path, mat):
			continue
		_add_thumb_cell(i, mat, mat_path)


func _build_favorites_grid() -> void:
	if not _material_manager:
		return
	var numbers := {}
	var infos := get_favorite_infos(FAVORITE_SLOTS)
	for n in infos.size():
		numbers[int(infos[n]["index"])] = n + 1
	for i in range(_material_manager.materials.size()):
		var mat = _material_manager.materials[i]
		if mat == null:
			continue
		var mat_path: String = mat.resource_path
		if not is_favorite(mat_path):
			continue
		if not _passes_filters(mat_path, mat):
			continue
		_add_thumb_cell(i, mat, mat_path, str(numbers[i]) if numbers.has(i) else "")
	if _filters_active():
		return
	# A star whose file was moved or deleted used to vanish, with nothing to say
	# it had been there or where it lived.
	for path in missing_favorites():
		var missing_tip := (
			"Missing: %s" % path
			+ "\nThe file is gone, so it cannot be applied."
			+ "\n\nRight-click: Remove Favorite"
		)
		_add_marker_cell({"favorite": path}, path.get_file().get_basename(), missing_tip)


## Starred paths that no palette slot holds and whose file is gone, in the order
## they were starred.
func missing_favorites() -> Array[String]:
	var out: Array[String] = []
	for key in _favorites.keys():
		var path := str(key)
		if palette_slot_of(path) >= 0:
			continue
		# A material saved inside a scene is `scene.tscn::id`: the scene is the file.
		if ResourceLoader.exists(path.get_slice("::", 0)):
			continue
		out.append(path)
	return out


## The first palette slot holding the material saved at `path`, or -1.
func palette_slot_of(path: String) -> int:
	if not _material_manager:
		return -1
	return _material_manager.slot_of_path(path)


func _filters_active() -> bool:
	return _search_text != "" or _active_pattern_filter != "" or _active_color_filter != ""


## How many faces of the open level use `slot`.
func use_count(slot: int) -> int:
	return int(_use_counts.get(slot, 0))


## Ask how the level uses its materials again, and redraw when that moved. The
## dock calls this now and then while the browser is on screen.
func refresh_use() -> void:
	var now: Dictionary = use_provider.call() if use_provider.is_valid() else {}
	if now != _use_counts:
		rebuild()


## Whether every word of the search is in `haystack`, in any order (#1725), so
## `brick red` finds `wall_brick_red_02`.
static func matches_words(query: String, haystack: String) -> bool:
	var lower := haystack.to_lower()
	for word in query.to_lower().split(" ", false):
		if lower.find(word) < 0:
			return false
	return true


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
	# Search text: every word, in the name or the path.
	if _search_text != "":
		if not matches_words(_search_text, MaterialManager.material_label(mat) + " " + mat_path):
			return false
	return true


func _on_thumb_size_changed(value: float) -> void:
	set_thumb_size(int(value))


## Draw the thumbnails `pixels` across, and remember it.
func set_thumb_size(pixels: int) -> void:
	_thumb_size = clampi(pixels, THUMB_SIZE_MIN, THUMB_SIZE_MAX)
	if _size_slider and int(_size_slider.value) != _thumb_size:
		_size_slider.set_value_no_signal(_thumb_size)
	if _user_prefs:
		_user_prefs.set_pref("material_thumb_size", _thumb_size)
		_user_prefs.save()
	_fit_grid_columns()
	rebuild()


func get_thumb_size() -> int:
	return _thumb_size


func _add_thumb_cell(
	palette_index: int, mat: Material, mat_path: String, badge: String = ""
) -> void:
	var cell = _create_thumb_button(palette_index, mat, mat_path)
	if badge != "":
		cell.add_child(_make_badge(badge))
	var used := use_count(palette_index)
	if used > 0:
		cell.add_child(_make_use_marker(used))
	_grid.add_child(cell)
	_cell_to_palette_index.append(palette_index)


## A favourite's number in the corner of its thumbnail: the number its button on
## the context toolbar shows and the digit Alt applies it with.
## The corner mark of a material the open level uses, with how many faces.
func _make_use_marker(faces: int) -> Label:
	var mark := Label.new()
	mark.name = "InUse"
	mark.text = "●"
	mark.tooltip_text = (
		HFTranslationType
		. tn("Used on {count} face", "Used on {count} faces", faces)
		. format({"count": faces})
	)
	mark.position = Vector2(_thumb_size - 6, 2)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_size_override("font_size", 12)
	mark.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5))
	mark.add_theme_color_override("font_outline_color", Color.BLACK)
	mark.add_theme_constant_override("outline_size", 4)
	return mark


func _make_badge(text: String) -> Label:
	var badge := Label.new()
	badge.name = "SlotNumber"
	badge.text = text
	badge.position = Vector2(4, 2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	return badge


## What dragging the Hidden swatch carries: the viewport's drop makes the face it
## lands on Hidden.
func _hidden_drag_data(_at_position: Vector2) -> Variant:
	return {"type": "hammerforge_material", "index": -1, "hidden": true}


## A cell with no material to pick, a "!" with `label` under it. It takes no
## click, hover or drag, so nothing can select or apply what is not there.
func _add_marker_cell(marker: Dictionary, label: String, tip: String) -> void:
	var cell_idx: int = _cell_to_palette_index.size()
	var btn := Button.new()
	btn.flat = true
	btn.name = "Marker%d" % cell_idx
	btn.custom_minimum_size = Vector2(_thumb_size + 8, _thumb_size + 22)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = tip
	btn.gui_input.connect(_on_cell_gui_input.bind(cell_idx))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var mark := Label.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.custom_minimum_size = Vector2(_thumb_size, _thumb_size)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 32)
	mark.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	box.add_child(mark)
	var name_label := Label.new()
	name_label.text = label
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = _thumb_size
	box.add_child(name_label)
	_grid.add_child(btn)
	_cell_markers[cell_idx] = marker
	_cell_to_palette_index.append(-1)


func _create_thumb_button(_palette_index: int, mat: Material, mat_path: String) -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(_thumb_size + 8, _thumb_size + 22)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Thumbnail
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(_thumb_size, _thumb_size)
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
	label.custom_minimum_size.x = _thumb_size
	container.add_child(label)

	# Tooltip
	var tip := MaterialManager.material_label(mat)
	if is_favorite(mat_path):
		tip += " [Favorite]"
	var used := use_count(_palette_index)
	if used > 0:
		tip += "\nUsed on %d face%s" % [used, "" if used == 1 else "s"]
	var texture := _get_thumbnail(mat, mat_path)
	if texture != null:
		tip += "\n%d x %d px" % [texture.get_width(), texture.get_height()]
	if mat_path != "":
		tip += "\n%s" % mat_path
	tip += (
		"\n\nLeft-click: Select material"
		+ "\nHover: Preview on selected faces"
		+ "\nDouble-click: Apply to selected faces"
		+ "\nRight-click: Apply to whole brush, Active Material, favorite, copy name"
	)
	container.tooltip_text = tip

	# Wrap in a button-like panel for click/hover
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(_thumb_size + 8, _thumb_size + 22)
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


## The thumbnail the grid shows for `mat`. One made in the session has no path,
## so it is kept by its own id rather than under the empty one they all share.
func thumbnail_of(mat: Material) -> Texture2D:
	if mat == null:
		return null
	var key := mat.resource_path if mat.resource_path != "" else "id:%d" % mat.get_instance_id()
	return _get_thumbnail(mat, key)


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


func _get_short_label(mat: Material, _mat_path: String) -> String:
	var full := MaterialManager.material_label(mat)
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
	if _cell_to_palette_index[cell_index] < 0:
		return
	_selected_index = _cell_to_palette_index[cell_index]
	_update_selection_visual()
	material_selected.emit(_selected_index)


func _on_cell_mouse_entered(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _cell_to_palette_index.size():
		return
	if _cell_to_palette_index[cell_index] < 0:
		return
	material_hovered.emit(_cell_to_palette_index[cell_index])


func _on_cell_mouse_exited() -> void:
	material_hover_ended.emit()


func _on_cell_gui_input(event: InputEvent, cell_index: int) -> void:
	if cell_index < 0 or cell_index >= _cell_to_palette_index.size():
		return
	if event is InputEventMouseButton and event.pressed:
		var mb = event as InputEventMouseButton
		if _cell_to_palette_index[cell_index] < 0:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_show_marker_menu(cell_index, mb.global_position)
			return
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
		if (
			_selected_index >= 0
			and i < _cell_to_palette_index.size()
			and _cell_to_palette_index[i] == _selected_index
		):
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
	if palette_idx < 0:
		return null
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
		# Narrow and stretched, so the eleven swatches fill the row at any dock width
		# rather than setting how narrow the dock can be.
		btn.custom_minimum_size = Vector2(14, 20)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	popup.add_item("Set as Active Material", 5)
	popup.add_item("Replace Material...", 6)
	popup.add_separator()
	popup.add_item("Select Faces Using This", 7)
	popup.add_item("Select Brushes Using This", 8)
	popup.add_separator()
	popup.add_item("Toggle Favorite", 2)
	popup.add_separator()
	popup.add_item("Copy Name", 3)
	return popup


## The right-click menu of a marker cell. Only a missing favourite has one: its
## star is the one thing left to act on. An empty palette slot offers nothing.
func _show_marker_menu(cell_index: int, global_pos: Vector2) -> void:
	var marker: Dictionary = _cell_markers.get(cell_index, {})
	var path := str(marker.get("favorite", ""))
	if path == "":
		return
	_marker_menu_path = path
	if not _marker_menu:
		_marker_menu = PopupMenu.new()
		_marker_menu.name = "MarkerMenu"
		_marker_menu.add_item("Remove Favorite", 0)
		_marker_menu.id_pressed.connect(_on_marker_menu_id_pressed)
		add_child(_marker_menu)
	_marker_menu.position = Vector2i(int(global_pos.x), int(global_pos.y))
	_marker_menu.popup()


func _on_marker_menu_id_pressed(id: int) -> void:
	if id != 0 or _marker_menu_path == "":
		return
	remove_favorite(_marker_menu_path)
	_marker_menu_path = ""
	rebuild()


# ---------------------------------------------------------------------------
# Recent row
# ---------------------------------------------------------------------------


## Fill the Recent row from the preferences, newest first. The dock calls this
## when a material has been applied, and the row follows a change of palette or
## preferences. A recent material whose file is gone is left out.
func refresh_recent() -> void:
	if not _recent_cells:
		return
	for child in _recent_cells.get_children():
		_recent_cells.remove_child(child)
		child.free()
	if _user_prefs:
		for entry in _user_prefs.get_recent_materials():
			var path := str(entry)
			var slot := palette_slot_of(path)
			var mat: Material = _material_manager.get_material(slot) if slot >= 0 else null
			if mat == null:
				mat = _load_recent(path)
			if mat == null:
				continue
			_recent_cells.add_child(_make_recent_button(path, mat, slot))
	_recent_row.visible = _recent_cells.get_child_count() > 0


## The paths the Recent row shows, newest first.
func get_recent_paths() -> Array[String]:
	var out: Array[String] = []
	if _recent_cells:
		for child in _recent_cells.get_children():
			out.append(str(child.get_meta("hf_recent_path", "")))
	return out


func _load_recent(path: String) -> Material:
	if _recent_loaded.has(path):
		return _recent_loaded[path]
	if path == "" or not ResourceLoader.exists(path):
		return null
	var mat := ResourceLoader.load(path) as Material
	if mat:
		_recent_loaded[path] = mat
	return mat


func _make_recent_button(path: String, mat: Material, slot: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(RECENT_THUMB_SIZE, RECENT_THUMB_SIZE)
	btn.expand_icon = true
	btn.icon = _get_thumbnail(mat, path)
	if btn.icon == null:
		btn.text = _get_short_label(mat, path).left(3)
	btn.set_meta("hf_recent_path", path)
	var tip := "%s\n%s" % [MaterialManager.material_label(mat), path]
	if slot >= 0:
		tip += "\n\nClick: Select material"
	else:
		tip += "\n\nNot in this level's palette. Click: add it and select it"
	btn.tooltip_text = tip
	btn.pressed.connect(_on_recent_pressed.bind(path))
	return btn


## A Recent thumbnail selects its material as a grid cell does. One the palette
## does not hold has no slot to select until it is added.
func _on_recent_pressed(path: String) -> void:
	var slot := palette_slot_of(path)
	if slot < 0:
		# After the click: adding to the palette rebuilds this row, and the
		# button cannot be freed while it is still sending the click.
		material_add_requested.emit.call_deferred(path)
		return
	_selected_index = slot
	_update_selection_visual()
	material_selected.emit(slot)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## As many thumbnails a row as the browser is wide, and at least one.
func _fit_grid_columns() -> void:
	if not _grid or not _scroll:
		return
	var separation := _grid.get_theme_constant("h_separation")
	var cell := _thumb_size + 8 + separation
	_grid.columns = maxi(1, int((_scroll.size.x + separation) / cell))


func _clear_grid() -> void:
	_cell_to_palette_index.clear()
	_cell_markers.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()


func _update_status() -> void:
	var shown := 0
	for palette_index in _cell_to_palette_index:
		if palette_index >= 0:
			shown += 1
	var total = _material_manager.materials.size() if _material_manager else 0
	var text := ""
	if shown == 0 and total == 0:
		text = "No materials loaded. Refresh Prototypes is under Material Library."
	elif shown == 0:
		text = "No materials match filters (%d total)" % total
	elif shown == total:
		text = "%d materials" % shown
	else:
		text = "%d of %d materials" % [shown, total]
	status_changed.emit(text)
