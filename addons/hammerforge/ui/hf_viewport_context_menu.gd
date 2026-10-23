@tool
extends PopupMenu
## Space-key context menu that appears at cursor position in the 3D viewport.
## Context-sensitive: shows different actions based on current selection and mode.

signal action_requested(action: String, args: Array)

enum Context { NONE, BRUSH_SELECTED, FACE_SELECTED, ENTITY_SELECTED, DRAW_IDLE, VERTEX_EDIT }

# ── ID ranges (avoid collisions between sections) ──────────────────────────
const _ID_EXTRUDE_UP := 100
const _ID_EXTRUDE_DOWN := 101
const _ID_HOLLOW := 102
const _ID_CLIP := 103
const _ID_CLIP_TO_FACE := 112
const _ID_CARVE := 104
const _ID_MERGE := 105
const _ID_INTERSECT := 117
const _ID_OFFSET := 118
const _ID_ROTATE_CCW := 106
const _ID_ROTATE_CW := 107
const _ID_FLIP := 108
const _ID_RESET_ROTATION := 109
const _ID_DUPLICATE := 110
const _ID_DELETE := 111
const _ID_SELECT_SIMILAR := 113
const _ID_APPLY_LAST_TEX := 114
const _ID_SELECTION_FILTER := 115
const _ID_PLACE_PREFAB := 116
const _ID_CONVERT_TO_BRUSHES := 119
const _ID_APPLY_TO_BRUSH := 121
const _ID_RUN_TRIM := 122
const _ID_REPICK_TRIM := 123
const _ID_JUSTIFY_FIT := 130
const _ID_JUSTIFY_CENTER := 131
const _ID_JUSTIFY_LEFT := 132
const _ID_JUSTIFY_RIGHT := 133
const _ID_JUSTIFY_TOP := 134
const _ID_JUSTIFY_BOTTOM := 135
const _ID_ENTITY_IO := 140
const _ID_ENTITY_PROPS := 141
const _ID_HIGHLIGHT_CONN := 142
const _ID_SHAPE_BOX := 150
const _ID_SHAPE_CYLINDER := 151
const _ID_SHAPE_SPHERE := 152
const _ID_SHAPE_CONE := 153
const _ID_TOGGLE_GRID := 154
const _ID_VERTEX_MERGE := 160
const _ID_VERTEX_SPLIT := 161
const _ID_VERTEX_CONVEX := 162
const _ID_VERTEX_EXIT := 163
const _ID_VERTEX_SUBMODE := 164
const _ID_EDGE_SUBMODE := 165
const _ID_SELECT_ALL := 170
const _ID_DESELECT_ALL := 171
const _ID_INVERT_SELECTION := 172
const _ID_SELECT_INSIDE := 173
const _ID_SELECT_PARTLY_INSIDE := 174
const _ID_SELECT_TOUCHING := 175
const _ID_SELECT_COLUMN := 176
const _ID_GROUP := 180
const _ID_UNGROUP := 181
const _ID_BACK_TO_WORLD := 182
const _ID_NEW_VISGROUP := 183
const _ID_SHOW_MATERIAL := 184
const _ID_DRAW_ADD := 185
const _ID_DRAW_CUT := 186
const _ID_QUICK_BAKE := 200
const _ID_UNDO := 201
const _ID_REDO := 202
# Grid snap IDs: 300 + value
const _ID_GRID_BASE := 300
## The entity, brush entity and visgroup submenus are filled as the menu opens;
## an item's id is its place in the list kept beside it, plus one of these.
const _ID_PLACE_BASE := 1000
const _ID_BRUSH_ENTITY_BASE := 2000
const _ID_VISGROUP_BASE := 3000

var _grid_submenu: PopupMenu
var _uv_submenu: PopupMenu
var _shape_submenu: PopupMenu
var _select_with_submenu: PopupMenu
var _state: Dictionary = {}

var _place_submenu: PopupMenu
var _brush_entity_submenu: PopupMenu
var _visgroup_submenu: PopupMenu
var _place_classes: Array[String] = []
var _brush_entity_classes: Array[String] = []
var _visgroup_names: Array[String] = []


func _init() -> void:
	name = "HFViewportContextMenu"
	# Grid snap submenu
	_grid_submenu = PopupMenu.new()
	_grid_submenu.name = "GridSnap"
	# The id is the rung, not the value: the value is a float now and an item id
	# cannot carry one.
	for index in range(HFSnapSystem.GRID_PRESETS.size()):
		var val: float = HFSnapSystem.GRID_PRESETS[index]
		_grid_submenu.add_item("%s m" % str(val), _ID_GRID_BASE + index)
	_grid_submenu.id_pressed.connect(_on_grid_id_pressed)
	add_child(_grid_submenu)
	# UV submenu
	_uv_submenu = PopupMenu.new()
	_uv_submenu.name = "UV"
	_uv_submenu.add_item("Fit", _ID_JUSTIFY_FIT)
	_uv_submenu.add_item("Center", _ID_JUSTIFY_CENTER)
	_uv_submenu.add_item("Left", _ID_JUSTIFY_LEFT)
	_uv_submenu.add_item("Right", _ID_JUSTIFY_RIGHT)
	_uv_submenu.add_item("Top", _ID_JUSTIFY_TOP)
	_uv_submenu.add_item("Bottom", _ID_JUSTIFY_BOTTOM)
	_uv_submenu.id_pressed.connect(_on_id_pressed)
	add_child(_uv_submenu)
	# Shape submenu
	_shape_submenu = PopupMenu.new()
	_shape_submenu.name = "Shapes"
	_shape_submenu.add_item("Box", _ID_SHAPE_BOX)
	_shape_submenu.add_item("Cylinder", _ID_SHAPE_CYLINDER)
	_shape_submenu.add_item("Sphere", _ID_SHAPE_SPHERE)
	_shape_submenu.add_item("Cone", _ID_SHAPE_CONE)
	_shape_submenu.id_pressed.connect(_on_id_pressed)
	add_child(_shape_submenu)
	# Select with the selected brush, then delete it (#1717)
	_select_with_submenu = PopupMenu.new()
	_select_with_submenu.name = "SelectWithBrush"
	_select_with_submenu.add_item("Select Inside", _ID_SELECT_INSIDE)
	_select_with_submenu.add_item("Select Partly Inside", _ID_SELECT_PARTLY_INSIDE)
	_select_with_submenu.add_item("Select Touching", _ID_SELECT_TOUCHING)
	_select_with_submenu.add_item("Select Column", _ID_SELECT_COLUMN)
	_select_with_submenu.id_pressed.connect(_on_id_pressed)
	add_child(_select_with_submenu)
	# Filled as the menu opens, from the level (#1724).
	_place_submenu = PopupMenu.new()
	_place_submenu.name = "PlaceEntity"
	_place_submenu.id_pressed.connect(_on_place_pressed)
	add_child(_place_submenu)
	_brush_entity_submenu = PopupMenu.new()
	_brush_entity_submenu.name = "BrushEntity"
	_brush_entity_submenu.id_pressed.connect(_on_brush_entity_pressed)
	add_child(_brush_entity_submenu)
	_visgroup_submenu = PopupMenu.new()
	_visgroup_submenu.name = "Visgroup"
	_visgroup_submenu.id_pressed.connect(_on_visgroup_pressed)
	add_child(_visgroup_submenu)
	# Own signal
	id_pressed.connect(_on_id_pressed)


func show_at(pos: Vector2, state: Dictionary) -> void:
	clear()
	_state = state
	var ctx := _determine_context(state)
	if state.get("mixed_selection", false):
		add_item("Edit HammerForge and Godot nodes separately")
		set_item_disabled(0, true)
	else:
		# Godot meshes and CSG shapes selected, which can join the level as brushes.
		if int(state.get("convertible_count", 0)) > 0 and state.get("has_root", false):
			add_item("Convert to Brushes", _ID_CONVERT_TO_BRUSHES)
			add_separator()
		_build_context_items(ctx)
		# The prefab selected in the library, put where the cursor is, as a drop
		# would put it (#1301).
		var library_prefab := str(state.get("library_prefab", ""))
		if library_prefab != "" and state.get("has_root", false):
			add_separator()
			add_item("Place %s Here" % library_prefab.get_file().get_basename(), _ID_PLACE_PREFAB)
	# Common footer
	add_separator()
	add_item("Select All", _ID_SELECT_ALL)
	add_item("Deselect All", _ID_DESELECT_ALL)
	add_item("Invert Selection", _ID_INVERT_SELECTION)
	add_separator()
	add_submenu_node_item("Grid Snap", _grid_submenu)
	add_item("Quick Bake", _ID_QUICK_BAKE)
	add_separator()
	add_item("Undo", _ID_UNDO)
	add_item("Redo", _ID_REDO)
	popup(Rect2i(int(pos.x), int(pos.y), 0, 0))


func _build_context_items(ctx: Context) -> void:
	match ctx:
		Context.VERTEX_EDIT:
			add_item("Vertex Sub-mode", _ID_VERTEX_SUBMODE)
			add_item("Edge Sub-mode", _ID_EDGE_SUBMODE)
			add_separator()
			add_item("Merge Vertices", _ID_VERTEX_MERGE)
			add_item("Split Edge", _ID_VERTEX_SPLIT)
			add_item("Clip to Convex", _ID_VERTEX_CONVEX)
			add_item("Offset...", _ID_OFFSET)
			add_separator()
			add_item("Exit Vertex Mode", _ID_VERTEX_EXIT)
		Context.FACE_SELECTED:
			add_item("Apply Last Texture", _ID_APPLY_LAST_TEX)
			add_item("Apply to Whole Brush", _ID_APPLY_TO_BRUSH)
			if int(_state.get("face_material", -1)) >= 0:
				add_item("Show Material in Browser", _ID_SHOW_MATERIAL)
			add_separator()
			add_submenu_node_item("UV Operations", _uv_submenu)
			add_item("Offset...", _ID_OFFSET)
			add_separator()
			# A skirting or cornice along the picked wall faces (#1414).
			add_item("Run Trim Along Faces", _ID_RUN_TRIM)
			if _state.get("repick_trim_run", false):
				add_item("Re-pick Trim Run", _ID_REPICK_TRIM)
			add_separator()
			add_item("Select Similar", _ID_SELECT_SIMILAR)
			add_item("Selection Filters...", _ID_SELECTION_FILTER)
		Context.ENTITY_SELECTED:
			_add_place_entity()
			add_item("I/O Connections", _ID_ENTITY_IO)
			add_item("Edit Properties", _ID_ENTITY_PROPS)
			add_check_item("Highlight Connected", _ID_HIGHLIGHT_CONN)
			set_item_checked(
				get_item_index(_ID_HIGHLIGHT_CONN), _state.get("highlight_connected", false)
			)
			add_separator()
			_add_visgroup_submenu()
			add_item("Offset...", _ID_OFFSET)
			add_item("Duplicate", _ID_DUPLICATE)
			add_item("Delete", _ID_DELETE)
		Context.BRUSH_SELECTED:
			_add_place_entity()
			add_item("Extrude Up", _ID_EXTRUDE_UP)
			add_item("Extrude Down", _ID_EXTRUDE_DOWN)
			add_separator()
			add_item("Hollow", _ID_HOLLOW)
			add_item("Clip", _ID_CLIP)
			add_item("Clip to Face Plane", _ID_CLIP_TO_FACE)
			add_item("Carve", _ID_CARVE)
			add_item("Merge", _ID_MERGE)
			add_item("Intersect", _ID_INTERSECT)
			add_separator()
			add_item("Rotate CCW", _ID_ROTATE_CCW)
			add_item("Rotate CW", _ID_ROTATE_CW)
			add_item("Flip", _ID_FLIP)
			add_item("Reset Rotation", _ID_RESET_ROTATION)
			add_item("Offset...", _ID_OFFSET)
			add_separator()
			_add_brush_entity_submenu()
			if _state.get("tied", false):
				add_item("Back to World", _ID_BACK_TO_WORLD)
			add_item("Group", _ID_GROUP)
			if _state.get("grouped", false):
				add_item("Ungroup", _ID_UNGROUP)
			_add_visgroup_submenu()
			add_separator()
			add_item("Select Similar", _ID_SELECT_SIMILAR)
			add_item("Selection Filters...", _ID_SELECTION_FILTER)
			add_submenu_node_item("Select With This Brush", _select_with_submenu)
			add_separator()
			add_item("Duplicate", _ID_DUPLICATE)
			add_item("Delete", _ID_DELETE)
		Context.DRAW_IDLE, Context.NONE:
			_add_place_entity()
			add_submenu_node_item("Draw Shape", _shape_submenu)
			var cutting: bool = _state.get("is_subtract", false)
			add_radio_check_item("Draw as Add", _ID_DRAW_ADD)
			set_item_checked(get_item_index(_ID_DRAW_ADD), not cutting)
			add_radio_check_item("Draw as Cut", _ID_DRAW_CUT)
			set_item_checked(get_item_index(_ID_DRAW_CUT), cutting)
			add_item("Toggle Grid", _ID_TOGGLE_GRID)


## Place Entity Here, by category, when there is a level and a point under the
## cursor to put it on.
func _add_place_entity() -> void:
	var classes: Dictionary = _state.get("entity_classes", {})
	if not _state.get("has_root", false) or classes.is_empty():
		return
	if not (_state.get("cursor_screen") is Vector2):
		return
	_place_submenu.clear()
	_place_classes.clear()
	var categories: Array = classes.keys()
	categories.sort()
	for category in categories:
		_place_submenu.add_separator(str(category))
		for entity_class in classes[category]:
			_place_submenu.add_item(str(entity_class), _ID_PLACE_BASE + _place_classes.size())
			_place_classes.append(str(entity_class))
	add_submenu_node_item("Place Entity Here", _place_submenu)
	add_separator()


func _add_brush_entity_submenu() -> void:
	var classes: Array = _state.get("brush_entity_classes", [])
	if classes.is_empty():
		return
	_brush_entity_submenu.clear()
	_brush_entity_classes.clear()
	for entity_class in classes:
		_brush_entity_submenu.add_item(
			str(entity_class), _ID_BRUSH_ENTITY_BASE + _brush_entity_classes.size()
		)
		_brush_entity_classes.append(str(entity_class))
	add_submenu_node_item("Make Brush Entity", _brush_entity_submenu)


func _add_visgroup_submenu() -> void:
	_visgroup_submenu.clear()
	_visgroup_names.clear()
	for visgroup in _state.get("visgroups", []):
		_visgroup_submenu.add_item(str(visgroup), _ID_VISGROUP_BASE + _visgroup_names.size())
		_visgroup_names.append(str(visgroup))
	if not _visgroup_names.is_empty():
		_visgroup_submenu.add_separator()
	_visgroup_submenu.add_item("New Visgroup", _ID_NEW_VISGROUP)
	add_submenu_node_item("Add to Visgroup", _visgroup_submenu)


func _on_place_pressed(id: int) -> void:
	var index := id - _ID_PLACE_BASE
	if index >= 0 and index < _place_classes.size():
		action_requested.emit(
			"place_entity_here", [_place_classes[index], _state.get("cursor_screen")]
		)


func _on_brush_entity_pressed(id: int) -> void:
	var index := id - _ID_BRUSH_ENTITY_BASE
	if index >= 0 and index < _brush_entity_classes.size():
		action_requested.emit("make_brush_entity", [_brush_entity_classes[index]])


func _on_visgroup_pressed(id: int) -> void:
	if id == _ID_NEW_VISGROUP:
		action_requested.emit("new_visgroup", [])
		return
	var index := id - _ID_VISGROUP_BASE
	if index >= 0 and index < _visgroup_names.size():
		action_requested.emit("add_to_visgroup", [_visgroup_names[index]])


func _determine_context(state: Dictionary) -> Context:
	if state.get("mixed_selection", false):
		return Context.NONE
	var input_mode: int = state.get("input_mode", 0)
	if state.get("vertex_mode", false):
		return Context.VERTEX_EDIT
	var face_count: int = state.get("face_count", 0)
	if face_count > 0:
		return Context.FACE_SELECTED
	var entity_count: int = state.get("entity_count", 0)
	if entity_count > 0:
		return Context.ENTITY_SELECTED
	var brush_count: int = state.get("brush_count", 0)
	if brush_count > 0:
		return Context.BRUSH_SELECTED
	var tool_id: int = state.get("tool", 0)
	if tool_id == 0 and input_mode == 0:
		return Context.DRAW_IDLE
	return Context.NONE


func _on_id_pressed(id: int) -> void:
	var action := ""
	var args: Array = []
	match id:
		_ID_EXTRUDE_UP:
			action = "extrude_up"
		_ID_EXTRUDE_DOWN:
			action = "extrude_down"
		_ID_HOLLOW:
			action = "hollow"
		_ID_CLIP:
			action = "clip"
		_ID_CLIP_TO_FACE:
			action = "clip_to_face"
		_ID_CARVE:
			action = "carve"
		_ID_MERGE:
			action = "merge"
		_ID_INTERSECT:
			action = "intersect"
		_ID_ROTATE_CCW:
			action = "rotate_ccw"
		_ID_ROTATE_CW:
			action = "rotate_cw"
		_ID_FLIP:
			action = "flip_selection"
		_ID_RESET_ROTATION:
			action = "reset_rotation"
		_ID_OFFSET:
			action = "offset_selection"
		_ID_DUPLICATE:
			action = "duplicate"
		_ID_DELETE:
			action = "delete"
		_ID_SELECT_SIMILAR:
			action = "select_similar"
		_ID_APPLY_LAST_TEX:
			action = "apply_last_texture"
		_ID_SELECTION_FILTER:
			action = "selection_filter"
		_ID_PLACE_PREFAB:
			action = "place_prefab"
		_ID_CONVERT_TO_BRUSHES:
			action = "convert_to_brushes"
		_ID_APPLY_TO_BRUSH:
			action = "apply_to_brush"
		_ID_RUN_TRIM:
			action = "run_trim_along_faces"
		_ID_REPICK_TRIM:
			action = "repick_trim_run"
		_ID_JUSTIFY_FIT:
			action = "justify_fit"
		_ID_JUSTIFY_CENTER:
			action = "justify_center"
		_ID_JUSTIFY_LEFT:
			action = "justify_left"
		_ID_JUSTIFY_RIGHT:
			action = "justify_right"
		_ID_JUSTIFY_TOP:
			action = "justify_top"
		_ID_JUSTIFY_BOTTOM:
			action = "justify_bottom"
		_ID_ENTITY_IO:
			action = "entity_io"
		_ID_ENTITY_PROPS:
			action = "entity_props"
		_ID_HIGHLIGHT_CONN:
			action = "highlight_connected"
			# Toggle: invert the current state so the menu works as on/off
			args = [not _state.get("highlight_connected", false)]
		_ID_SHAPE_BOX:
			action = "shape_box"
		_ID_SHAPE_CYLINDER:
			action = "shape_cylinder"
		_ID_SHAPE_SPHERE:
			action = "shape_sphere"
		_ID_SHAPE_CONE:
			action = "shape_cone"
		_ID_TOGGLE_GRID:
			action = "toggle_grid"
		_ID_VERTEX_MERGE:
			action = "vertex_merge"
		_ID_VERTEX_SPLIT:
			action = "vertex_split"
		_ID_VERTEX_CONVEX:
			action = "vertex_clip_convex"
		_ID_VERTEX_EXIT:
			action = "vertex_exit"
		_ID_VERTEX_SUBMODE:
			action = "vertex_submode"
		_ID_EDGE_SUBMODE:
			action = "edge_submode"
		_ID_SELECT_ALL:
			action = "select_all"
		_ID_DESELECT_ALL:
			action = "deselect_all"
		_ID_INVERT_SELECTION:
			action = "invert_selection"
		_ID_SELECT_INSIDE:
			action = "select_inside"
		_ID_SELECT_PARTLY_INSIDE:
			action = "select_partly_inside"
		_ID_SELECT_TOUCHING:
			action = "select_touching"
		_ID_SELECT_COLUMN:
			action = "select_column"
		_ID_QUICK_BAKE:
			action = "quick_bake"
		_ID_UNDO:
			action = "undo"
		_ID_REDO:
			action = "redo"
		_ID_GROUP:
			action = "group"
		_ID_UNGROUP:
			action = "ungroup"
		_ID_BACK_TO_WORLD:
			action = "back_to_world"
		_ID_SHOW_MATERIAL:
			action = "show_material_in_browser"
		_ID_DRAW_ADD:
			if _state.get("is_subtract", false):
				action = "toggle_operation"
		_ID_DRAW_CUT:
			if not _state.get("is_subtract", false):
				action = "toggle_operation"
	if action != "":
		action_requested.emit(action, args)


func _on_grid_id_pressed(id: int) -> void:
	var index: int = id - _ID_GRID_BASE
	if index < 0 or index >= HFSnapSystem.GRID_PRESETS.size():
		return
	action_requested.emit("set_grid_snap", [HFSnapSystem.GRID_PRESETS[index]])
