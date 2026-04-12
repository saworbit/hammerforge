@tool
extends PopupMenu
## Right-click context menu that appears at cursor position in the 3D viewport.
## Context-sensitive: shows different actions based on current selection and mode.

signal action_requested(action: String, args: Array)

enum Context { NONE, BRUSH_SELECTED, FACE_SELECTED, ENTITY_SELECTED, DRAW_IDLE, VERTEX_EDIT }

# ── ID ranges (avoid collisions between sections) ──────────────────────────
const _ID_EXTRUDE_UP := 100
const _ID_EXTRUDE_DOWN := 101
const _ID_HOLLOW := 102
const _ID_CLIP := 103
const _ID_CARVE := 104
const _ID_MERGE := 105
const _ID_DUPLICATE := 110
const _ID_DELETE := 111
const _ID_SET_PLAYER_START := 112
const _ID_SELECT_SIMILAR := 113
const _ID_APPLY_LAST_TEX := 114
const _ID_SELECTION_FILTER := 115
const _ID_APPLY_MATERIAL := 120
const _ID_APPLY_TO_BRUSH := 121
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
const _ID_QUICK_BAKE := 200
const _ID_UNDO := 201
const _ID_REDO := 202
# Grid snap IDs: 300 + value
const _ID_GRID_BASE := 300

var _grid_submenu: PopupMenu
var _uv_submenu: PopupMenu
var _shape_submenu: PopupMenu
var _state: Dictionary = {}


func _init() -> void:
	name = "HFViewportContextMenu"
	# Grid snap submenu
	_grid_submenu = PopupMenu.new()
	_grid_submenu.name = "GridSnap"
	for val in [1, 2, 4, 8, 16, 32, 64]:
		_grid_submenu.add_item("%d units" % val, _ID_GRID_BASE + val)
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
	# Own signal
	id_pressed.connect(_on_id_pressed)


func show_at(pos: Vector2, state: Dictionary) -> void:
	clear()
	_state = state
	var ctx := _determine_context(state)
	match ctx:
		Context.VERTEX_EDIT:
			add_item("Vertex Sub-mode", _ID_VERTEX_SUBMODE)
			add_item("Edge Sub-mode", _ID_EDGE_SUBMODE)
			add_separator()
			add_item("Merge Vertices", _ID_VERTEX_MERGE)
			add_item("Split Edge", _ID_VERTEX_SPLIT)
			add_item("Clip to Convex", _ID_VERTEX_CONVEX)
			add_separator()
			add_item("Exit Vertex Mode", _ID_VERTEX_EXIT)
		Context.FACE_SELECTED:
			add_item("Apply Last Texture", _ID_APPLY_LAST_TEX)
			add_item("Apply to Whole Brush", _ID_APPLY_TO_BRUSH)
			add_separator()
			add_submenu_node_item("UV Operations", _uv_submenu)
			add_separator()
			add_item("Select Similar", _ID_SELECT_SIMILAR)
			add_item("Selection Filters...", _ID_SELECTION_FILTER)
		Context.ENTITY_SELECTED:
			add_item("I/O Connections", _ID_ENTITY_IO)
			add_item("Edit Properties", _ID_ENTITY_PROPS)
			add_check_item("Highlight Connected", _ID_HIGHLIGHT_CONN)
			set_item_checked(
				get_item_index(_ID_HIGHLIGHT_CONN), _state.get("highlight_connected", false)
			)
			add_separator()
			add_item("Duplicate", _ID_DUPLICATE)
			add_item("Delete", _ID_DELETE)
		Context.BRUSH_SELECTED:
			add_item("Extrude Up", _ID_EXTRUDE_UP)
			add_item("Extrude Down", _ID_EXTRUDE_DOWN)
			add_separator()
			add_item("Hollow", _ID_HOLLOW)
			add_item("Clip", _ID_CLIP)
			add_item("Carve", _ID_CARVE)
			add_item("Merge", _ID_MERGE)
			add_separator()
			add_item("Select Similar", _ID_SELECT_SIMILAR)
			add_item("Selection Filters...", _ID_SELECTION_FILTER)
			add_item("Set Player Start", _ID_SET_PLAYER_START)
			add_separator()
			add_item("Duplicate", _ID_DUPLICATE)
			add_item("Delete", _ID_DELETE)
		Context.DRAW_IDLE, Context.NONE:
			add_submenu_node_item("Draw Shape", _shape_submenu)
			add_item("Toggle Grid", _ID_TOGGLE_GRID)
	# Common footer
	add_separator()
	add_item("Select All", _ID_SELECT_ALL)
	add_item("Deselect All", _ID_DESELECT_ALL)
	add_separator()
	add_submenu_node_item("Grid Snap", _grid_submenu)
	add_item("Quick Bake", _ID_QUICK_BAKE)
	add_separator()
	add_item("Undo", _ID_UNDO)
	add_item("Redo", _ID_REDO)
	popup(Rect2i(int(pos.x), int(pos.y), 0, 0))


func _determine_context(state: Dictionary) -> Context:
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
		_ID_CARVE:
			action = "carve"
		_ID_MERGE:
			action = "merge"
		_ID_DUPLICATE:
			action = "duplicate"
		_ID_DELETE:
			action = "delete"
		_ID_SET_PLAYER_START:
			action = "set_player_start"
		_ID_SELECT_SIMILAR:
			action = "select_similar"
		_ID_APPLY_LAST_TEX:
			action = "apply_last_texture"
		_ID_SELECTION_FILTER:
			action = "selection_filter"
		_ID_APPLY_MATERIAL:
			action = "apply_material"
		_ID_APPLY_TO_BRUSH:
			action = "apply_to_brush"
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
		_ID_QUICK_BAKE:
			action = "quick_bake"
		_ID_UNDO:
			action = "undo"
		_ID_REDO:
			action = "redo"
	if action != "":
		action_requested.emit(action, args)


func _on_grid_id_pressed(id: int) -> void:
	var snap_val: int = id - _ID_GRID_BASE
	action_requested.emit("set_grid_snap", [snap_val])
