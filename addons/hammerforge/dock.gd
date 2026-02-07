@tool
extends Control
class_name HammerForgeDock

signal hud_visibility_changed(visible: bool)

const LevelRootType = preload("level_root.gd")
const BrushPreset = preload("brush_preset.gd")
const DraftEntity = preload("draft_entity.gd")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")

const PRESET_MENU_RENAME := 0
const PRESET_MENU_DELETE := 1


class EntityPaletteButton:
	extends Button
	var entity_id: String = ""
	var entity_def: Dictionary = {}
	var dock_ref: HammerForgeDock = null

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if entity_id == "" or not dock_ref:
			return null
		return dock_ref._make_entity_drag_data(entity_id, entity_def, self)


@onready var main_tabs: TabContainer = $Margin/VBox/MainTabs
@onready var build_tab: ScrollContainer = $Margin/VBox/MainTabs/Build
@onready var entity_tab: ScrollContainer = $Margin/VBox/MainTabs/Entities
@onready var manage_tab: ScrollContainer = $Margin/VBox/MainTabs/Manage
@onready var status_bar: HBoxContainer = $Margin/VBox/Footer/StatusFooter
@onready var progress_bar: ProgressBar = $Margin/VBox/Footer/StatusFooter/ProgressBar

@onready var tool_draw: Button = $Margin/VBox/Toolbar/ToolDraw
@onready var tool_select: Button = $Margin/VBox/Toolbar/ToolSelect
@onready var paint_mode: Button = $Margin/VBox/Toolbar/PaintMode
@onready var mode_add: Button = $Margin/VBox/Toolbar/ModeAdd
@onready var mode_subtract: Button = $Margin/VBox/Toolbar/ModeSubtract
@onready
var shape_select: OptionButton = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/ShapeRow/ShapeSelect
@onready var sides_row: HBoxContainer = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/SidesRow
@onready
var sides_spin: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/SidesRow/SidesSpin
@onready
var active_material_button: Button = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/MaterialRow/ActiveMaterial
@onready var material_dialog: FileDialog = $MaterialDialog
@onready var material_palette_dialog: FileDialog = $MaterialPaletteDialog
@onready var surface_paint_texture_dialog: FileDialog = $SurfacePaintTextureDialog
@onready var hflevel_save_dialog: FileDialog = $HFLevelSaveDialog
@onready var hflevel_load_dialog: FileDialog = $HFLevelLoadDialog
@onready var map_import_dialog: FileDialog = $MapImportDialog
@onready var map_export_dialog: FileDialog = $MapExportDialog
@onready var glb_export_dialog: FileDialog = $GLBExportDialog
@onready var autosave_path_dialog: FileDialog = $AutosavePathDialog
@onready var size_x: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/SizeRow/SizeX
@onready var size_y: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/SizeRow/SizeY
@onready var size_z: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/SizeRow/SizeZ
@onready
var paint_tool_select: OptionButton = $Margin/VBox/MainTabs/FloorPaint/FloorPaintMargin/FloorPaintVBox/PaintToolRow/PaintToolSelect
@onready
var paint_radius: SpinBox = $Margin/VBox/MainTabs/FloorPaint/FloorPaintMargin/FloorPaintVBox/PaintRadiusRow/PaintRadius
@onready
var brush_shape_select: OptionButton = $Margin/VBox/MainTabs/FloorPaint/FloorPaintMargin/FloorPaintVBox/BrushShapeRow/BrushShapeSelect
@onready
var paint_layer_select: OptionButton = $Margin/VBox/MainTabs/FloorPaint/FloorPaintMargin/FloorPaintVBox/PaintLayerRow/PaintLayerSelect
@onready
var paint_layer_add: Button = $Margin/VBox/MainTabs/FloorPaint/FloorPaintMargin/FloorPaintVBox/PaintLayerRow/PaintLayerAdd
@onready
var paint_layer_remove: Button = $Margin/VBox/MainTabs/FloorPaint/FloorPaintMargin/FloorPaintVBox/PaintLayerRow/PaintLayerRemove
@onready var grid_snap: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/GridRow/GridSnap
@onready
var collision_layer_opt: OptionButton = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/PhysicsLayerRow/PhysicsLayerOption
@onready
var bake_merge_meshes: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeMergeMeshes
@onready
var bake_generate_lods: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeGenerateLods
@onready
var bake_lightmap_uv2: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeLightmapUV2
@onready
var bake_use_face_materials: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeUseFaceMaterials
@onready
var bake_lightmap_texel_row: HBoxContainer = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeLightmapTexelRow
@onready
var bake_lightmap_texel: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeLightmapTexelRow/BakeLightmapTexel
@onready var bake_navmesh: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmesh
@onready
var bake_navmesh_cell_row: HBoxContainer = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmeshCellRow
@onready
var bake_navmesh_cell_size: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmeshCellRow/BakeNavmeshCellSize
@onready
var bake_navmesh_cell_height: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmeshCellRow/BakeNavmeshCellHeight
@onready
var bake_navmesh_agent_row: HBoxContainer = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmeshAgentRow
@onready
var bake_navmesh_agent_height: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmeshAgentRow/BakeNavmeshAgentHeight
@onready
var bake_navmesh_agent_radius: SpinBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/BakeNavmeshAgentRow/BakeNavmeshAgentRadius
@onready var commit_freeze: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/CommitFreeze
@onready var show_hud: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/ShowHUD
@onready var show_grid: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/ShowGrid
@onready var follow_grid: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/FollowGrid
@onready var debug_logs: CheckBox = $Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/DebugLogs
@onready var floor_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/CreateFloor
@onready var apply_cuts_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/ApplyCuts
@onready var clear_cuts_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/ClearCuts
@onready
var commit_cuts_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/CommitCuts
@onready
var restore_cuts_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/RestoreCuts
@onready
var create_entity_btn: Button = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox/CreateEntity
@onready
var entity_palette: GridContainer = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox/EntityPalette
@onready var bake_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/Bake
@onready var clear_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/Clear
@onready
var save_hflevel_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/SaveHFLevel
@onready
var load_hflevel_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/LoadHFLevel
@onready var import_map_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/ImportMap
@onready var export_map_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/ExportMap
@onready var export_glb_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/ExportGLB
@onready
var autosave_enabled: CheckBox = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/AutosaveEnabled
@onready
var autosave_minutes: SpinBox = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/AutosaveMinutesRow/AutosaveMinutes
@onready
var autosave_path_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/AutosavePath
@onready var status_label: Label = $Margin/VBox/Footer/StatusFooter/StatusLabel
@onready var selection_label: Label = $Margin/VBox/Footer/StatusFooter/SelectionLabel
@onready var perf_label: Label = $Margin/VBox/Footer/StatusFooter/BrushCountLabel
@onready
var undo_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/HistoryControls/Undo
@onready
var redo_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/HistoryControls/Redo
@onready
var history_list: ItemList = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/HistoryList
@onready var quick_play_btn: Button = $Margin/VBox/Footer/QuickPlay

@onready
var materials_list: ItemList = $Margin/VBox/MainTabs/Materials/MaterialsMargin/MaterialsVBox/MaterialsList
@onready
var material_add: Button = $Margin/VBox/MainTabs/Materials/MaterialsMargin/MaterialsVBox/MaterialsButtons/MaterialAdd
@onready
var material_remove: Button = $Margin/VBox/MainTabs/Materials/MaterialsMargin/MaterialsVBox/MaterialsButtons/MaterialRemove
@onready
var material_assign: Button = $Margin/VBox/MainTabs/Materials/MaterialsMargin/MaterialsVBox/MaterialAssign
@onready
var face_select_mode: CheckBox = $Margin/VBox/MainTabs/Materials/MaterialsMargin/MaterialsVBox/FaceSelectMode
@onready
var face_clear: Button = $Margin/VBox/MainTabs/Materials/MaterialsMargin/MaterialsVBox/FaceClear

@onready var uv_editor: UVEditor = $Margin/VBox/MainTabs/UV/UVVBox/UVEditor
@onready var uv_reset: Button = $Margin/VBox/MainTabs/UV/UVVBox/UVReset

@onready
var paint_target_select: OptionButton = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/PaintTargetRow/PaintTargetSelect
@onready
var surface_paint_radius: SpinBox = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/SurfacePaintRadiusRow/SurfacePaintRadius
@onready
var surface_paint_strength: SpinBox = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/SurfacePaintStrengthRow/SurfacePaintStrength
@onready
var surface_paint_layer_select: OptionButton = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/SurfacePaintLayerRow/SurfacePaintLayerSelect
@onready
var surface_paint_layer_add: Button = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/SurfacePaintLayerRow/SurfacePaintLayerAdd
@onready
var surface_paint_layer_remove: Button = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/SurfacePaintLayerRow/SurfacePaintLayerRemove
@onready
var surface_paint_texture: Button = $Margin/VBox/MainTabs/SurfacePaint/PaintMargin/PaintVBox/SurfacePaintTexture

@onready
var save_preset_btn: Button = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/SavePreset
@onready
var preset_grid: GridContainer = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox/PresetGrid
@onready var preset_menu: PopupMenu = $PresetMenu
@onready var preset_rename_dialog: AcceptDialog = $PresetRenameDialog
@onready var preset_rename_line: LineEdit = $PresetRenameDialog/PresetRenameLine

@onready var snap_buttons: Array[Button] = [
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap1,
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap2,
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap4,
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap8,
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap16,
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap32,
	$Margin/VBox/MainTabs/Build/BuildMargin/BuildVBox/QuickSnapGrid/Snap64
]

var level_root: LevelRootType = null
var editor_interface: EditorInterface = null
var editor_base_control: Control = null
var undo_redo: EditorUndoRedoManager = null
var connected_root: Node = null
var snap_button_group: ButtonGroup
var syncing_snap := false
var debug_enabled := false
var syncing_grid := false
var presets_dir := "res://addons/hammerforge/presets"
var entity_defs_path := "res://addons/hammerforge/entities.json"
var entity_defs: Array = []
var preset_buttons: Array[Button] = []
var entity_palette_buttons: Array[Button] = []
var preset_context_button: Button = null
var active_material: Material = null
var active_shape: int = LevelRootType.BrushShape.BOX
var shape_id_to_key: Dictionary = {}
var paint_layers_signature: String = ""
var materials_signature: String = ""
var surface_paint_signature: String = ""
var root_properties: Dictionary = {}
var history_entries: Array = []
var history_max := 50
var shape_icon_candidates := {
	"BOX": ["BoxShape3D"],
	"CYLINDER": ["CylinderShape3D"],
	"SPHERE": ["SphereShape3D"],
	"CONE": ["ConeShape3D"],
	"CAPSULE": ["CapsuleShape3D"],
	"TORUS": ["TorusMesh"],
	"ELLIPSOID": ["SphereShape3D"]
}
var _selected_material_index := -1
var _uv_active_brush: DraftBrush = null
var _uv_active_face: FaceData = null
var _surface_active_brush: DraftBrush = null
var _surface_active_face: FaceData = null
var _pending_surface_texture_layer := -1


func _is_level_root(node: Node) -> bool:
	return node != null and node is LevelRootType


func _cache_root_properties() -> void:
	root_properties.clear()
	if not connected_root:
		return
	for prop in connected_root.get_property_list():
		var name = prop.get("name", "")
		if name != "":
			root_properties[name] = true


func _root_has_property(name: String) -> bool:
	return root_properties.has(name)


func set_editor_interface(iface: EditorInterface) -> void:
	editor_interface = iface
	if editor_interface:
		editor_base_control = editor_interface.get_base_control()
	_apply_pro_styles()


func set_undo_redo(manager: EditorUndoRedoManager) -> void:
	if undo_redo == manager:
		return
	if undo_redo and undo_redo.has_signal("version_changed"):
		if undo_redo.is_connected(
			"version_changed", Callable(self, "_on_undo_redo_version_changed")
		):
			undo_redo.disconnect("version_changed", Callable(self, "_on_undo_redo_version_changed"))
	undo_redo = manager
	if undo_redo and undo_redo.has_signal("version_changed"):
		if not undo_redo.is_connected(
			"version_changed", Callable(self, "_on_undo_redo_version_changed")
		):
			undo_redo.connect("version_changed", Callable(self, "_on_undo_redo_version_changed"))
	_refresh_history_list()


func record_history(action_name: String) -> void:
	if action_name == "":
		return
	if not undo_redo:
		return
	var version = _get_undo_version()
	history_entries.append({"name": action_name, "version": version})
	if history_entries.size() > history_max:
		history_entries.pop_front()
	_refresh_history_list()


func apply_editor_styles(base_control: Control) -> void:
	if not base_control:
		return
	editor_base_control = base_control
	var foreground_style = _resolve_stylebox(base_control, "PanelForeground", "EditorStyles")
	var panel_style = _resolve_stylebox(base_control, "panel", "PanelContainer")
	var inspector_style = _resolve_stylebox(base_control, "panel", "EditorInspector")
	if foreground_style:
		add_theme_stylebox_override("panel", foreground_style)
	elif inspector_style:
		add_theme_stylebox_override("panel", inspector_style)
	elif panel_style:
		add_theme_stylebox_override("panel", panel_style)
	_apply_pro_styles()


func _resolve_stylebox(base_control: Control, name: String, type_name: String) -> StyleBox:
	if base_control.has_theme_stylebox(name, type_name):
		return base_control.get_theme_stylebox(name, type_name)
	if base_control.theme and base_control.theme.has_stylebox(name, type_name):
		return base_control.theme.get_stylebox(name, type_name)
	return null


func _apply_pro_styles() -> void:
	if not is_inside_tree():
		return
	_setup_toolbar_icons()
	_refresh_shape_palette_icons()
	_style_snap_buttons()


func _style_snap_buttons() -> void:
	for button in snap_buttons:
		if not button:
			continue
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE


func _setup_toolbar_icons() -> void:
	_set_toolbar_button_icon(tool_draw, ["Edit", "ToolEdit"], "Draw")
	_set_toolbar_button_icon(tool_select, ["ToolSelect", "Select"], "Select")
	_set_toolbar_button_icon(mode_add, ["Add", "AddNode"], "Add")
	_set_toolbar_button_icon(mode_subtract, ["Remove", "RemoveNode"], "Subtract")
	if paint_mode:
		_set_toolbar_button_icon(paint_mode, ["Paint", "Brush", "ToolPaint"], "Paint")
	_apply_toolbar_tooltips()


func _apply_toolbar_tooltips() -> void:
	_set_tooltip(tool_draw, "Draw Tool\nShift+Click: Place brush\nAlt: Height-only drag")
	_set_tooltip(tool_select, "Select Tool\nClick: Select | Shift+Click: Add\nCtrl+Click: Toggle")
	_set_tooltip(mode_add, "Additive Mode\nBrushes add geometry (union)")
	_set_tooltip(mode_subtract, "Subtractive Mode\nBrushes cut geometry (pending cuts)")
	if paint_mode:
		_set_tooltip(paint_mode, "Paint Mode\nToggle between building and painting")


func _set_tooltip(control: Control, text: String) -> void:
	if not control:
		return
	control.tooltip_text = text


func _apply_all_tooltips() -> void:
	# Build tab - Grid
	_set_tooltip(grid_snap, "Grid snap size in units\nControls brush placement and nudge step")
	for button in snap_buttons:
		if button and button.has_meta("snap_value"):
			_set_tooltip(button, "Quick snap: %s units" % str(button.get_meta("snap_value")))
	# Build tab - Toggles
	_set_tooltip(show_grid, "Show editor grid in 3D viewport")
	_set_tooltip(follow_grid, "Grid follows last placed brush position")
	_set_tooltip(show_hud, "Show keyboard shortcut overlay in viewport")
	_set_tooltip(debug_logs, "Print debug info to Output panel")
	# Build tab - Brush size & shape
	_set_tooltip(size_x, "Brush width (X axis) in units")
	_set_tooltip(size_y, "Brush height (Y axis) in units")
	_set_tooltip(size_z, "Brush depth (Z axis) in units")
	_set_tooltip(shape_select, "Brush shape for new brushes")
	_set_tooltip(sides_spin, "Side count for polygon shapes (Pyramid, Prism)")
	_set_tooltip(commit_freeze, "Keep committed cuts frozen (restorable)\ninstead of deleting them")
	_set_tooltip(collision_layer_opt, "Physics collision layer for baked geometry")
	_set_tooltip(active_material_button, "Active material for Select+Paint brush painting")
	# Build tab - Bake options
	_set_tooltip(bake_merge_meshes, "Merge meshes during bake for better performance")
	_set_tooltip(bake_generate_lods, "Generate LOD meshes during bake")
	_set_tooltip(bake_lightmap_uv2, "Generate UV2 for lightmap baking")
	_set_tooltip(bake_use_face_materials, "Apply per-face materials from the Materials tab")
	_set_tooltip(bake_navmesh, "Generate navigation mesh during bake")
	_set_tooltip(bake_lightmap_texel, "Lightmap texel density (smaller = higher quality)")
	_set_tooltip(bake_navmesh_cell_size, "Navigation mesh cell size (XZ)")
	_set_tooltip(bake_navmesh_cell_height, "Navigation mesh cell height (Y)")
	_set_tooltip(bake_navmesh_agent_height, "Navigation agent height")
	_set_tooltip(bake_navmesh_agent_radius, "Navigation agent radius")
	# FloorPaint tab
	_set_tooltip(
		paint_tool_select, "Floor paint tool\nB: Brush | E: Erase | R: Rect | L: Line | K: Bucket"
	)
	_set_tooltip(paint_radius, "Floor paint brush radius in grid cells")
	_set_tooltip(brush_shape_select, "Brush shape: Square or Circle")
	_set_tooltip(paint_layer_select, "Active floor paint layer")
	_set_tooltip(paint_layer_add, "Add a new floor paint layer")
	_set_tooltip(paint_layer_remove, "Remove the selected floor paint layer")
	# SurfacePaint tab
	_set_tooltip(paint_target_select, "Paint target: Floor (grid) or Surface (UV)")
	_set_tooltip(surface_paint_radius, "Surface paint radius in UV space (0.0 - 1.0)")
	_set_tooltip(surface_paint_strength, "Surface paint opacity/strength (0.0 - 1.0)")
	_set_tooltip(surface_paint_layer_select, "Active surface paint layer")
	_set_tooltip(surface_paint_layer_add, "Add a new surface paint layer")
	_set_tooltip(surface_paint_layer_remove, "Remove the selected surface paint layer")
	_set_tooltip(surface_paint_texture, "Texture for the selected surface paint layer")
	# Materials tab
	_set_tooltip(
		face_select_mode,
		"Enable per-face selection for material assignment\nClick faces in viewport to select them"
	)
	_set_tooltip(material_add, "Add a material to the palette")
	_set_tooltip(material_remove, "Remove selected material from palette")
	_set_tooltip(material_assign, "Assign selected material to selected faces")
	_set_tooltip(face_clear, "Clear face selection")
	# UV tab
	_set_tooltip(uv_reset, "Reset UV coordinates to defaults for selected face")
	# Manage tab
	_set_tooltip(floor_btn, "Create a default floor brush")
	_set_tooltip(apply_cuts_btn, "Move pending cuts into the draft brush tree")
	_set_tooltip(clear_cuts_btn, "Remove all pending cuts without applying")
	_set_tooltip(commit_cuts_btn, "Apply pending cuts, bake, then freeze/remove cut geometry")
	_set_tooltip(restore_cuts_btn, "Restore frozen committed cuts back to draft tree")
	_set_tooltip(bake_btn, "Bake draft brushes into optimized static meshes")
	_set_tooltip(clear_btn, "Remove all brushes and baked geometry")
	_set_tooltip(save_hflevel_btn, "Save level to .hflevel file")
	_set_tooltip(load_hflevel_btn, "Load level from .hflevel file")
	_set_tooltip(import_map_btn, "Import a Quake-style .map file")
	_set_tooltip(export_map_btn, "Export level as .map file")
	_set_tooltip(export_glb_btn, "Export baked geometry as .glb file")
	_set_tooltip(autosave_enabled, "Enable automatic saving at regular intervals")
	_set_tooltip(autosave_minutes, "Autosave interval in minutes")
	_set_tooltip(autosave_path_btn, "Set the autosave file path")
	_set_tooltip(save_preset_btn, "Save current brush settings as a reusable preset")
	_set_tooltip(quick_play_btn, "Bake and play the current scene")
	# Entities tab
	_set_tooltip(create_entity_btn, "Create a new entity at the cursor position")


func _set_toolbar_button_icon(button: Button, icon_names: Array, fallback_text: String) -> void:
	if not button:
		return
	var icon = _find_editor_icon(icon_names)
	if icon:
		button.icon = icon
		button.text = ""
	else:
		button.text = fallback_text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE


func _refresh_shape_palette_icons() -> void:
	if not shape_select:
		return
	for index in range(shape_select.get_item_count()):
		var shape_id = shape_select.get_item_id(index)
		var shape_key = str(shape_id_to_key.get(shape_id, ""))
		if shape_key == "":
			continue
		var icon = _resolve_shape_icon(shape_key)
		if icon:
			shape_select.set_item_icon(index, icon)
		else:
			shape_select.set_item_icon(index, null)


func _resolve_shape_icon(shape_key: String) -> Texture2D:
	var candidates = shape_icon_candidates.get(shape_key, [])
	return _find_editor_icon(candidates)


func _find_editor_icon(icon_names: Array) -> Texture2D:
	for icon_name in icon_names:
		if _has_editor_icon(icon_name):
			return _get_editor_icon(icon_name)
	return null


func _has_editor_icon(icon_name: String) -> bool:
	if editor_base_control and editor_base_control.has_theme_icon(icon_name, "EditorIcons"):
		return true
	return has_theme_icon(icon_name, "EditorIcons")


func _get_editor_icon(icon_name: String) -> Texture2D:
	if editor_base_control and editor_base_control.has_theme_icon(icon_name, "EditorIcons"):
		return editor_base_control.get_theme_icon(icon_name, "EditorIcons")
	return get_theme_icon(icon_name, "EditorIcons")


func _get_editor_color(color_name: String, fallback: Color) -> Color:
	if editor_base_control and editor_base_control.has_theme_color(color_name, "Editor"):
		return editor_base_control.get_theme_color(color_name, "Editor")
	if editor_base_control and editor_base_control.has_theme_color(color_name, "EditorStyles"):
		return editor_base_control.get_theme_color(color_name, "EditorStyles")
	if has_theme_color(color_name, "Editor"):
		return get_theme_color(color_name, "Editor")
	return fallback


func _get_undo_version() -> int:
	if undo_redo and undo_redo.has_method("get_version"):
		return int(undo_redo.get_version())
	return history_entries.size()


func _refresh_history_list() -> void:
	if not history_list:
		return
	history_list.clear()
	var current_version = _get_undo_version()
	for entry in history_entries:
		var name = str(entry.get("name", ""))
		var version = int(entry.get("version", 0))
		var prefix = "• " if version <= current_version else "  "
		history_list.add_item("%s%s" % [prefix, name])
	_update_history_buttons()


func _update_history_buttons() -> void:
	if not undo_btn or not redo_btn:
		return
	if not undo_redo:
		undo_btn.disabled = true
		redo_btn.disabled = true
		return
	var can_undo = true
	var can_redo = true
	if undo_redo.has_method("has_undo"):
		can_undo = undo_redo.has_undo()
	if undo_redo.has_method("has_redo"):
		can_redo = undo_redo.has_redo()
	undo_btn.disabled = not can_undo
	redo_btn.disabled = not can_redo


func _on_undo_redo_version_changed() -> void:
	_refresh_history_list()


func _on_history_undo() -> void:
	if editor_interface and editor_interface.has_method("undo"):
		editor_interface.call("undo")
		return
	if undo_redo and undo_redo.has_method("undo"):
		undo_redo.undo()


func _on_history_redo() -> void:
	if editor_interface and editor_interface.has_method("redo"):
		editor_interface.call("redo")
		return
	if undo_redo and undo_redo.has_method("redo"):
		undo_redo.redo()


func _ready():
	var tool_group = ButtonGroup.new()
	tool_draw.toggle_mode = true
	tool_select.toggle_mode = true
	tool_draw.button_group = tool_group
	tool_select.button_group = tool_group
	tool_draw.button_pressed = true
	if paint_mode:
		paint_mode.toggle_mode = true
		paint_mode.button_pressed = false

	var mode_group = ButtonGroup.new()
	mode_add.toggle_mode = true
	mode_subtract.toggle_mode = true
	mode_add.button_group = mode_group
	mode_subtract.button_group = mode_group
	mode_add.button_pressed = true

	_populate_shape_palette()
	_populate_paint_tools()
	_populate_brush_shapes()
	_populate_paint_targets()
	if (
		shape_select
		and not shape_select.item_selected.is_connected(Callable(self, "_on_shape_selected"))
	):
		shape_select.item_selected.connect(_on_shape_selected)
	if (
		paint_layer_select
		and not paint_layer_select.item_selected.is_connected(
			Callable(self, "_on_paint_layer_selected")
		)
	):
		paint_layer_select.item_selected.connect(_on_paint_layer_selected)
	if (
		paint_layer_add
		and not paint_layer_add.pressed.is_connected(Callable(self, "_on_paint_layer_add"))
	):
		paint_layer_add.pressed.connect(_on_paint_layer_add)
	if (
		paint_layer_remove
		and not paint_layer_remove.pressed.is_connected(Callable(self, "_on_paint_layer_remove"))
	):
		paint_layer_remove.pressed.connect(_on_paint_layer_remove)
	if (
		materials_list
		and not materials_list.item_selected.is_connected(Callable(self, "_on_material_selected"))
	):
		materials_list.item_selected.connect(_on_material_selected)
	if material_add and not material_add.pressed.is_connected(Callable(self, "_on_material_add")):
		material_add.pressed.connect(_on_material_add)
	if (
		material_remove
		and not material_remove.pressed.is_connected(Callable(self, "_on_material_remove"))
	):
		material_remove.pressed.connect(_on_material_remove)
	if (
		material_assign
		and not material_assign.pressed.is_connected(Callable(self, "_on_material_assign"))
	):
		material_assign.pressed.connect(_on_material_assign)
	if face_clear and not face_clear.pressed.is_connected(Callable(self, "_on_face_clear")):
		face_clear.pressed.connect(_on_face_clear)
	if uv_reset and not uv_reset.pressed.is_connected(Callable(self, "_on_uv_reset")):
		uv_reset.pressed.connect(_on_uv_reset)
	if uv_editor and not uv_editor.uv_changed.is_connected(Callable(self, "_on_uv_changed")):
		uv_editor.uv_changed.connect(_on_uv_changed)
	if (
		surface_paint_layer_select
		and not surface_paint_layer_select.item_selected.is_connected(
			Callable(self, "_on_surface_paint_layer_selected")
		)
	):
		surface_paint_layer_select.item_selected.connect(_on_surface_paint_layer_selected)
	if (
		surface_paint_layer_add
		and not surface_paint_layer_add.pressed.is_connected(
			Callable(self, "_on_surface_paint_layer_add")
		)
	):
		surface_paint_layer_add.pressed.connect(_on_surface_paint_layer_add)
	if (
		surface_paint_layer_remove
		and not surface_paint_layer_remove.pressed.is_connected(
			Callable(self, "_on_surface_paint_layer_remove")
		)
	):
		surface_paint_layer_remove.pressed.connect(_on_surface_paint_layer_remove)
	if (
		surface_paint_texture
		and not surface_paint_texture.pressed.is_connected(
			Callable(self, "_on_surface_paint_texture")
		)
	):
		surface_paint_texture.pressed.connect(_on_surface_paint_texture)

	snap_button_group = ButtonGroup.new()
	var snap_values = [1, 2, 4, 8, 16, 32, 64]
	for index in range(snap_buttons.size()):
		var button = snap_buttons[index]
		if not button:
			continue
		button.toggle_mode = true
		button.flat = true
		button.button_group = snap_button_group
		button.set_meta("snap_value", snap_values[index])
		button.toggled.connect(_on_snap_button_toggled.bind(button))

	grid_snap.value_changed.connect(_on_grid_snap_value_changed)
	show_hud.toggled.connect(_on_show_hud_toggled)
	if show_grid:
		show_grid.toggled.connect(_on_show_grid_toggled)
	if follow_grid:
		follow_grid.toggled.connect(_on_follow_grid_toggled)
	if debug_logs:
		debug_logs.toggled.connect(_on_debug_logs_toggled)

	bake_btn.pressed.connect(_on_bake)
	clear_btn.pressed.connect(_on_clear)
	if save_hflevel_btn:
		save_hflevel_btn.pressed.connect(_on_save_hflevel)
	if load_hflevel_btn:
		load_hflevel_btn.pressed.connect(_on_load_hflevel)
	if import_map_btn:
		import_map_btn.pressed.connect(_on_import_map)
	if export_map_btn:
		export_map_btn.pressed.connect(_on_export_map)
	if export_glb_btn:
		export_glb_btn.pressed.connect(_on_export_glb)
	if autosave_path_btn:
		autosave_path_btn.pressed.connect(_on_set_autosave_path)
	floor_btn.pressed.connect(_on_floor)
	apply_cuts_btn.pressed.connect(_on_apply_cuts)
	clear_cuts_btn.pressed.connect(_on_clear_cuts)
	commit_cuts_btn.pressed.connect(_on_commit_cuts)
	restore_cuts_btn.pressed.connect(_on_restore_cuts)
	if create_entity_btn:
		create_entity_btn.pressed.connect(_on_create_entity)
	if undo_btn:
		undo_btn.pressed.connect(_on_history_undo)
	if redo_btn:
		redo_btn.pressed.connect(_on_history_redo)
	if save_preset_btn:
		save_preset_btn.pressed.connect(_on_save_preset)
	if quick_play_btn:
		quick_play_btn.pressed.connect(_on_quick_play)
	if preset_menu:
		preset_menu.clear()
		preset_menu.add_item("Rename", PRESET_MENU_RENAME)
		preset_menu.add_item("Delete", PRESET_MENU_DELETE)
		preset_menu.id_pressed.connect(_on_preset_menu_id_pressed)
	if preset_rename_dialog:
		preset_rename_dialog.confirmed.connect(_on_preset_rename_confirmed)
	if active_material_button:
		active_material_button.pressed.connect(_on_active_material_pressed)
	if material_dialog:
		material_dialog.access = FileDialog.ACCESS_RESOURCES
		material_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		material_dialog.filters = PackedStringArray(["*.tres ; Material", "*.material ; Material"])
		if not material_dialog.file_selected.is_connected(
			Callable(self, "_on_material_file_selected")
		):
			material_dialog.file_selected.connect(_on_material_file_selected)
	_setup_storage_dialogs()
	if bake_lightmap_uv2:
		var lightmap_toggle = Callable(self, "_on_bake_lightmap_uv2_toggled")
		if not bake_lightmap_uv2.toggled.is_connected(lightmap_toggle):
			bake_lightmap_uv2.toggled.connect(lightmap_toggle)
	if bake_navmesh:
		var nav_toggle = Callable(self, "_on_bake_navmesh_toggled")
		if not bake_navmesh.toggled.is_connected(nav_toggle):
			bake_navmesh.toggled.connect(nav_toggle)
	if collision_layer_opt:
		collision_layer_opt.clear()
		collision_layer_opt.add_item("Static World (Layer 1)", 1)
		collision_layer_opt.add_item("Debris/Prop (Layer 2)", 2)
		collision_layer_opt.add_item("Trigger Only (Layer 3)", 4)
		collision_layer_opt.select(0)
	if history_list:
		history_list.focus_mode = Control.FOCUS_NONE
	status_label.text = "Ready"
	if progress_bar:
		progress_bar.value = 0
		progress_bar.hide()
	_sync_snap_buttons(grid_snap.value)
	_ensure_presets_dir()
	_load_presets()
	_load_entity_definitions()
	_apply_pro_styles()
	_apply_all_tooltips()
	_sync_bake_option_visibility()
	set_process(true)


func _process(delta):
	var scene = get_tree().edited_scene_root
	if not scene:
		scene = get_tree().get_current_scene()
	if scene:
		if scene.get_script() == LevelRootType or scene.name == "LevelRoot":
			level_root = scene
		else:
			var candidate = scene.get_node_or_null("LevelRoot")
			if candidate:
				level_root = candidate
			else:
				level_root = null
	else:
		level_root = null
	if level_root != connected_root:
		_disconnect_root_signals()
		connected_root = level_root
		_connect_root_signals()
	if level_root:
		if _root_has_property("commit_freeze"):
			level_root.set("commit_freeze", commit_freeze.button_pressed)
		if _root_has_property("bake_merge_meshes") and bake_merge_meshes:
			level_root.set("bake_merge_meshes", bake_merge_meshes.button_pressed)
		if _root_has_property("bake_generate_lods") and bake_generate_lods:
			level_root.set("bake_generate_lods", bake_generate_lods.button_pressed)
		if _root_has_property("bake_lightmap_uv2") and bake_lightmap_uv2:
			level_root.set("bake_lightmap_uv2", bake_lightmap_uv2.button_pressed)
		if _root_has_property("bake_use_face_materials") and bake_use_face_materials:
			level_root.set("bake_use_face_materials", bake_use_face_materials.button_pressed)
		if _root_has_property("bake_lightmap_texel_size") and bake_lightmap_texel:
			level_root.set("bake_lightmap_texel_size", float(bake_lightmap_texel.value))
		if _root_has_property("bake_navmesh") and bake_navmesh:
			level_root.set("bake_navmesh", bake_navmesh.button_pressed)
		if _root_has_property("bake_navmesh_cell_size") and bake_navmesh_cell_size:
			level_root.set("bake_navmesh_cell_size", float(bake_navmesh_cell_size.value))
		if _root_has_property("bake_navmesh_cell_height") and bake_navmesh_cell_height:
			level_root.set("bake_navmesh_cell_height", float(bake_navmesh_cell_height.value))
		if _root_has_property("bake_navmesh_agent_height") and bake_navmesh_agent_height:
			level_root.set("bake_navmesh_agent_height", float(bake_navmesh_agent_height.value))
		if _root_has_property("bake_navmesh_agent_radius") and bake_navmesh_agent_radius:
			level_root.set("bake_navmesh_agent_radius", float(bake_navmesh_agent_radius.value))
		if _root_has_property("hflevel_autosave_enabled") and autosave_enabled:
			level_root.set("hflevel_autosave_enabled", autosave_enabled.button_pressed)
		if _root_has_property("hflevel_autosave_minutes") and autosave_minutes:
			level_root.set("hflevel_autosave_minutes", int(autosave_minutes.value))
		if show_grid and _root_has_property("grid_visible"):
			level_root.set("grid_visible", show_grid.button_pressed)
		if follow_grid and _root_has_property("grid_follow_brush"):
			level_root.set("grid_follow_brush", follow_grid.button_pressed)
		if _root_has_property("debug_logging"):
			level_root.set("debug_logging", debug_enabled)
		_sync_paint_layers_from_root()
		_sync_materials_from_root()
		_sync_surface_paint_from_root()
	_update_perf_label()


func _sync_paint_layers_from_root() -> void:
	if not level_root:
		return
	var names: Array = level_root.get_paint_layer_names()
	var active_index = int(level_root.get_active_paint_layer_index())
	var joined := ""
	for i in range(names.size()):
		if i > 0:
			joined += "|"
		joined += str(names[i])
	var sig = "%s:%d" % [joined, active_index]
	if sig != paint_layers_signature:
		paint_layers_signature = sig
		_refresh_paint_layers()


func _sync_materials_from_root() -> void:
	if not level_root:
		return
	var names: Array = level_root.get_material_names()
	var joined := ""
	for i in range(names.size()):
		if i > 0:
			joined += "|"
		joined += str(names[i])
	if joined != materials_signature:
		materials_signature = joined
		_refresh_materials_list(names)


func _sync_surface_paint_from_root() -> void:
	if not level_root:
		_set_uv_face(null, null)
		_set_surface_face(null, null)
		return
	var info: Dictionary = level_root.get_primary_selected_face()
	if info.is_empty():
		_set_uv_face(null, null)
		_set_surface_face(null, null)
		return
	var brush = info.get("brush", null)
	var face_idx = int(info.get("face_idx", -1))
	if brush == null or face_idx < 0 or not (brush is DraftBrush):
		_set_uv_face(null, null)
		_set_surface_face(null, null)
		return
	var draft := brush as DraftBrush
	if face_idx >= draft.faces.size():
		_set_uv_face(null, null)
		_set_surface_face(null, null)
		return
	var face: FaceData = draft.faces[face_idx]
	_set_uv_face(draft, face)
	_set_surface_face(draft, face)


func get_operation() -> int:
	return (
		CSGShape3D.OPERATION_UNION if mode_add.button_pressed else CSGShape3D.OPERATION_SUBTRACTION
	)


func get_tool() -> int:
	return 0 if tool_draw.button_pressed else 1


func get_active_material() -> Material:
	return active_material


func is_paint_mode_enabled() -> bool:
	return paint_mode and paint_mode.button_pressed


func is_face_select_mode_enabled() -> bool:
	return face_select_mode and face_select_mode.button_pressed


func get_paint_target() -> int:
	if not paint_target_select:
		return 0
	return paint_target_select.get_selected_id()


func get_brush_size() -> Vector3:
	return Vector3(size_x.value, size_y.value, size_z.value)


func get_shape() -> int:
	return active_shape


func get_sides() -> int:
	if not sides_spin:
		return 4
	return int(sides_spin.value)


func get_grid_snap() -> float:
	return grid_snap.value


func get_paint_tool_id() -> int:
	if not paint_tool_select:
		return 0
	return paint_tool_select.get_selected_id()


func get_paint_radius_cells() -> int:
	if not paint_radius:
		return 1
	return int(paint_radius.value)


func get_brush_shape() -> int:
	if not brush_shape_select:
		return 1
	return brush_shape_select.get_selected_id()


func get_surface_paint_radius() -> float:
	if not surface_paint_radius:
		return 0.1
	return float(surface_paint_radius.value)


func get_surface_paint_strength() -> float:
	if not surface_paint_strength:
		return 1.0
	return float(surface_paint_strength.value)


func get_surface_paint_layer() -> int:
	if not surface_paint_layer_select:
		return 0
	return surface_paint_layer_select.get_selected_id()


func get_collision_layer_mask() -> int:
	if not collision_layer_opt:
		return 0
	return collision_layer_opt.get_selected_id()


func get_show_hud() -> bool:
	return show_hud.button_pressed


func set_show_hud(visible: bool) -> void:
	if show_hud.button_pressed == visible:
		return
	show_hud.button_pressed = visible


func set_paint_tool(tool_id: int) -> void:
	if not paint_tool_select:
		return
	for i in range(paint_tool_select.get_item_count()):
		if paint_tool_select.get_item_id(i) == tool_id:
			paint_tool_select.select(i)
			return


func set_selection_count(count: int) -> void:
	if not selection_label:
		return
	if count <= 0:
		selection_label.text = ""
	elif count == 1:
		selection_label.text = "Sel: 1 brush"
	else:
		selection_label.text = "Sel: %d brushes" % count


func _on_grid_snap_value_changed(value: float) -> void:
	if syncing_snap:
		return
	_apply_grid_snap(value)


func _on_snap_button_toggled(pressed: bool, button: Button) -> void:
	if syncing_snap:
		return
	if not pressed:
		return
	var snap_value = float(button.get_meta("snap_value"))
	_apply_grid_snap(snap_value)


func _apply_grid_snap(value: float) -> void:
	syncing_snap = true
	grid_snap.value = value
	syncing_snap = false
	_sync_snap_buttons(value)
	if level_root and _root_has_property("grid_snap"):
		level_root.set("grid_snap", value)


func _sync_snap_buttons(value: float) -> void:
	syncing_snap = true
	var matched = false
	for button in snap_buttons:
		if not button:
			continue
		var snap_value = float(button.get_meta("snap_value"))
		var is_match = is_equal_approx(value, snap_value)
		button.button_pressed = is_match
		if is_match:
			matched = true
	if not matched:
		for button in snap_buttons:
			if button:
				button.button_pressed = false
	syncing_snap = false


func _on_show_hud_toggled(pressed: bool) -> void:
	hud_visibility_changed.emit(pressed)
	_log("HUD visibility: %s" % ("on" if pressed else "off"))


func _on_follow_grid_toggled(pressed: bool) -> void:
	if syncing_grid:
		return
	if level_root and _root_has_property("grid_follow_brush"):
		level_root.set("grid_follow_brush", pressed)
	_log("Grid follow: %s" % ("on" if pressed else "off"))


func _on_show_grid_toggled(pressed: bool) -> void:
	if syncing_grid:
		return
	if level_root and _root_has_property("grid_visible"):
		level_root.set("grid_visible", pressed)
	_log("Grid visible: %s" % ("on" if pressed else "off"))


func _on_debug_logs_toggled(pressed: bool) -> void:
	if syncing_grid:
		return
	debug_enabled = pressed
	if level_root and _root_has_property("debug_logging"):
		level_root.set("debug_logging", pressed)
	_log("Debug logs: %s" % ("on" if pressed else "off"), true)


func _on_bake_lightmap_uv2_toggled(_pressed: bool) -> void:
	_sync_bake_option_visibility()


func _on_bake_navmesh_toggled(_pressed: bool) -> void:
	_sync_bake_option_visibility()


func _sync_bake_option_visibility() -> void:
	if bake_lightmap_texel_row and bake_lightmap_uv2:
		bake_lightmap_texel_row.visible = bake_lightmap_uv2.button_pressed
	if bake_navmesh_cell_row and bake_navmesh:
		bake_navmesh_cell_row.visible = bake_navmesh.button_pressed
	if bake_navmesh_agent_row and bake_navmesh:
		bake_navmesh_agent_row.visible = bake_navmesh.button_pressed


func _log(message: String, force: bool = false) -> void:
	if not debug_enabled and not force:
		return
	print("[HammerForge Dock] %s" % message)


func _commit_state_action(action_name: String, method_name: String, args: Array = []) -> void:
	if not level_root or not level_root.has_method(method_name):
		return
	if args.size() > 3:
		level_root.callv(method_name, args)
		return
	if not undo_redo:
		level_root.callv(method_name, args)
		return
	var state = level_root.capture_state()
	undo_redo.create_action(action_name)
	match args.size():
		0:
			undo_redo.add_do_method(level_root, method_name)
		1:
			undo_redo.add_do_method(level_root, method_name, args[0])
		2:
			undo_redo.add_do_method(level_root, method_name, args[0], args[1])
		3:
			undo_redo.add_do_method(level_root, method_name, args[0], args[1], args[2])
	undo_redo.add_undo_method(level_root, "restore_state", state)
	undo_redo.commit_action()
	record_history(action_name)


func _commit_full_state_action(action_name: String, method_name: String, args: Array = []) -> void:
	if not level_root or not level_root.has_method(method_name):
		return
	if not undo_redo:
		level_root.callv(method_name, args)
		return
	var state = level_root.capture_full_state()
	undo_redo.create_action(action_name)
	match args.size():
		0:
			undo_redo.add_do_method(level_root, method_name)
		1:
			undo_redo.add_do_method(level_root, method_name, args[0])
		2:
			undo_redo.add_do_method(level_root, method_name, args[0], args[1])
		3:
			undo_redo.add_do_method(level_root, method_name, args[0], args[1], args[2])
		_:
			level_root.callv(method_name, args)
			return
	undo_redo.add_undo_method(level_root, "restore_full_state", state)
	undo_redo.commit_action()
	record_history(action_name)


func _on_bake():
	_log("Bake requested")
	_commit_state_action("Bake", "bake", [true, false, get_collision_layer_mask()])


func _on_clear():
	_log("Clear brushes requested")
	_commit_state_action("Clear Brushes", "clear_brushes")


func _on_floor():
	_log("Create floor requested")
	_commit_state_action("Create Floor", "create_floor")


func _on_apply_cuts():
	_log("Apply cuts requested")
	_commit_state_action("Apply Cuts", "apply_pending_cuts")


func _on_clear_cuts():
	_log("Clear pending cuts requested")
	_commit_state_action("Clear Pending Cuts", "clear_pending_cuts")


func _on_commit_cuts():
	_log("Commit cuts requested (freeze=%s)" % (commit_freeze.button_pressed))
	if editor_interface:
		var selection = editor_interface.get_selection()
		if selection:
			selection.clear()
	_commit_state_action("Commit Cuts", "commit_cuts")


func _on_restore_cuts():
	_log("Restore committed cuts requested")
	_commit_state_action("Restore Committed Cuts", "restore_committed_cuts")


func _on_create_entity() -> void:
	if not level_root:
		return
	var entity = DraftEntity.new()
	entity.name = "DraftEntity"
	entity.set_meta("is_entity", true)
	var def = _get_default_entity_definition()
	if not def.is_empty():
		var type_id = str(def.get("id", def.get("class", "")))
		if type_id != "":
			entity.entity_type = type_id
			entity.entity_class = type_id
	level_root.add_entity(entity)
	_focus_entity_selection(entity)


func _focus_entity_selection(entity: Node) -> void:
	if not editor_interface or not entity:
		return
	var selection = editor_interface.get_selection()
	if selection:
		selection.clear()
		selection.add_node(entity)


func _get_default_entity_definition() -> Dictionary:
	if entity_defs.is_empty():
		return {}
	return entity_defs[0] if entity_defs[0] is Dictionary else {}


func _connect_root_signals() -> void:
	if not connected_root:
		return
	_cache_root_properties()
	if connected_root.has_signal("bake_started"):
		if not connected_root.is_connected("bake_started", Callable(self, "_on_bake_started")):
			connected_root.connect("bake_started", Callable(self, "_on_bake_started"))
	if connected_root.has_signal("bake_finished"):
		if not connected_root.is_connected("bake_finished", Callable(self, "_on_bake_finished")):
			connected_root.connect("bake_finished", Callable(self, "_on_bake_finished"))
	if connected_root.has_signal("grid_snap_changed"):
		if not connected_root.is_connected(
			"grid_snap_changed", Callable(self, "_on_root_grid_snap_changed")
		):
			connected_root.connect(
				"grid_snap_changed", Callable(self, "_on_root_grid_snap_changed")
			)
	_sync_grid_snap_from_root()
	_sync_grid_settings_from_root()
	_refresh_paint_layers()


func _disconnect_root_signals() -> void:
	if not connected_root:
		return
	root_properties.clear()
	if connected_root.has_signal("bake_started"):
		if connected_root.is_connected("bake_started", Callable(self, "_on_bake_started")):
			connected_root.disconnect("bake_started", Callable(self, "_on_bake_started"))
	if connected_root.has_signal("bake_finished"):
		if connected_root.is_connected("bake_finished", Callable(self, "_on_bake_finished")):
			connected_root.disconnect("bake_finished", Callable(self, "_on_bake_finished"))
	if connected_root.has_signal("grid_snap_changed"):
		if connected_root.is_connected(
			"grid_snap_changed", Callable(self, "_on_root_grid_snap_changed")
		):
			connected_root.disconnect(
				"grid_snap_changed", Callable(self, "_on_root_grid_snap_changed")
			)


func _sync_grid_snap_from_root() -> void:
	if connected_root and _root_has_property("grid_snap"):
		var value = float(connected_root.get("grid_snap"))
		syncing_snap = true
		grid_snap.value = value
		syncing_snap = false
		_sync_snap_buttons(value)


func _on_root_grid_snap_changed(value: float) -> void:
	syncing_snap = true
	grid_snap.value = value
	syncing_snap = false
	_sync_snap_buttons(value)


func _sync_grid_settings_from_root() -> void:
	if not connected_root:
		return
	syncing_grid = true
	if show_grid and _root_has_property("grid_visible"):
		show_grid.button_pressed = bool(connected_root.get("grid_visible"))
	if follow_grid and _root_has_property("grid_follow_brush"):
		follow_grid.button_pressed = bool(connected_root.get("grid_follow_brush"))
	if debug_logs and _root_has_property("debug_logging"):
		debug_enabled = bool(connected_root.get("debug_logging"))
		debug_logs.button_pressed = debug_enabled
	if commit_freeze and _root_has_property("commit_freeze"):
		commit_freeze.button_pressed = bool(connected_root.get("commit_freeze"))
	if bake_merge_meshes and _root_has_property("bake_merge_meshes"):
		bake_merge_meshes.button_pressed = bool(connected_root.get("bake_merge_meshes"))
	if bake_generate_lods and _root_has_property("bake_generate_lods"):
		bake_generate_lods.button_pressed = bool(connected_root.get("bake_generate_lods"))
	if bake_lightmap_uv2 and _root_has_property("bake_lightmap_uv2"):
		bake_lightmap_uv2.button_pressed = bool(connected_root.get("bake_lightmap_uv2"))
	if bake_lightmap_texel and _root_has_property("bake_lightmap_texel_size"):
		bake_lightmap_texel.value = float(connected_root.get("bake_lightmap_texel_size"))
	if bake_navmesh and _root_has_property("bake_navmesh"):
		bake_navmesh.button_pressed = bool(connected_root.get("bake_navmesh"))
	if bake_navmesh_cell_size and _root_has_property("bake_navmesh_cell_size"):
		bake_navmesh_cell_size.value = float(connected_root.get("bake_navmesh_cell_size"))
	if bake_navmesh_cell_height and _root_has_property("bake_navmesh_cell_height"):
		bake_navmesh_cell_height.value = float(connected_root.get("bake_navmesh_cell_height"))
	if bake_navmesh_agent_height and _root_has_property("bake_navmesh_agent_height"):
		bake_navmesh_agent_height.value = float(connected_root.get("bake_navmesh_agent_height"))
	if bake_navmesh_agent_radius and _root_has_property("bake_navmesh_agent_radius"):
		bake_navmesh_agent_radius.value = float(connected_root.get("bake_navmesh_agent_radius"))
	if autosave_enabled and _root_has_property("hflevel_autosave_enabled"):
		autosave_enabled.button_pressed = bool(connected_root.get("hflevel_autosave_enabled"))
	if autosave_minutes and _root_has_property("hflevel_autosave_minutes"):
		autosave_minutes.value = float(connected_root.get("hflevel_autosave_minutes"))
	syncing_grid = false
	_sync_bake_option_visibility()


func _on_bake_started() -> void:
	status_label.text = "Baking..."
	if progress_bar:
		progress_bar.value = 0
		progress_bar.show()
	_set_bake_buttons_disabled(true)


func _on_bake_finished(success: bool) -> void:
	if success:
		_set_status("Bake complete", false, 3.0)
	else:
		_set_status("Bake failed - check Output for details", true)
	if progress_bar:
		progress_bar.hide()
	_set_bake_buttons_disabled(false)


func _set_bake_buttons_disabled(disabled: bool) -> void:
	bake_btn.disabled = disabled
	commit_cuts_btn.disabled = disabled
	apply_cuts_btn.disabled = disabled
	if quick_play_btn:
		quick_play_btn.disabled = disabled


func _on_quick_play() -> void:
	_log("Playtest requested")
	if level_root:
		await level_root.bake(true, false, get_collision_layer_mask())
	_notify_running_instances()
	if editor_interface:
		editor_interface.play_current_scene()


func _notify_running_instances() -> void:
	var lock_dir = "res://.hammerforge"
	var abs_lock_dir = ProjectSettings.globalize_path(lock_dir)
	if not DirAccess.dir_exists_absolute(abs_lock_dir):
		DirAccess.make_dir_recursive_absolute(abs_lock_dir)
	var file = FileAccess.open("%s/reload.lock" % lock_dir, FileAccess.WRITE)
	if not file:
		_log("Failed to write reload lock file", true)
		return
	file.store_string(str(Time.get_ticks_msec()))


func _populate_shape_palette() -> void:
	if not shape_select:
		return
	shape_select.clear()
	shape_id_to_key.clear()
	for shape_key in LevelRootType.BrushShape.keys():
		var shape_value = LevelRootType.BrushShape[shape_key]
		shape_id_to_key[shape_value] = shape_key
		var label = _shape_label(shape_key)
		var icon = _resolve_shape_icon(shape_key)
		if icon:
			shape_select.add_icon_item(icon, label, shape_value)
		else:
			shape_select.add_item(label, shape_value)
	_set_active_shape(active_shape)


func _populate_paint_tools() -> void:
	if not paint_tool_select:
		return
	paint_tool_select.clear()
	paint_tool_select.add_item("Paint", 0)
	paint_tool_select.add_item("Erase", 1)
	paint_tool_select.add_item("Rect", 2)
	paint_tool_select.add_item("Line", 3)
	paint_tool_select.add_item("Bucket", 4)
	paint_tool_select.select(0)


func _populate_brush_shapes() -> void:
	if not brush_shape_select:
		return
	brush_shape_select.clear()
	brush_shape_select.add_item("Square", 1)
	brush_shape_select.add_item("Circle", 0)
	brush_shape_select.select(0)


func _populate_paint_targets() -> void:
	if not paint_target_select:
		return
	paint_target_select.clear()
	paint_target_select.add_item("Floor", 0)
	paint_target_select.add_item("Surface", 1)
	paint_target_select.select(0)


func _refresh_paint_layers() -> void:
	if not paint_layer_select:
		return
	paint_layer_select.clear()
	if not level_root:
		paint_layer_select.add_item("Layer 0", 0)
		paint_layer_select.select(0)
		paint_layer_select.disabled = true
		if paint_layer_add:
			paint_layer_add.disabled = true
		if paint_layer_remove:
			paint_layer_remove.disabled = true
		return
	var names: Array = level_root.get_paint_layer_names()
	var active_index = int(level_root.get_active_paint_layer_index())
	paint_layer_select.disabled = false
	if paint_layer_add:
		paint_layer_add.disabled = false
	if paint_layer_remove:
		paint_layer_remove.disabled = names.size() <= 1
	for i in range(names.size()):
		var label = str(names[i])
		paint_layer_select.add_item(label, i)
	if names.size() > 0:
		paint_layer_select.select(clamp(active_index, 0, names.size() - 1))


func _refresh_materials_list(names: Array) -> void:
	if not materials_list:
		return
	materials_list.clear()
	for i in range(names.size()):
		materials_list.add_item(str(names[i]), null, true)
	if names.is_empty():
		_selected_material_index = -1
	else:
		var target = clamp(_selected_material_index, 0, names.size() - 1)
		materials_list.select(target)
		_selected_material_index = target


func _set_uv_face(brush: DraftBrush, face: FaceData) -> void:
	if _uv_active_face == face and _uv_active_brush == brush:
		return
	_uv_active_brush = brush
	_uv_active_face = face
	if uv_editor:
		uv_editor.set_face(face)


func _set_surface_face(brush: DraftBrush, face: FaceData) -> void:
	if _surface_active_face == face and _surface_active_brush == brush:
		return
	_surface_active_brush = brush
	_surface_active_face = face
	if _surface_active_face != null and paint_target_select and paint_target_select.selected != 1:
		paint_target_select.select(1)
	_refresh_surface_paint_layers()


func _refresh_surface_paint_layers() -> void:
	if not surface_paint_layer_select:
		return
	surface_paint_layer_select.clear()
	if _surface_active_face == null:
		surface_paint_layer_select.add_item("No Face", 0)
		surface_paint_layer_select.select(0)
		surface_paint_layer_select.disabled = true
		if surface_paint_layer_add:
			surface_paint_layer_add.disabled = true
		if surface_paint_layer_remove:
			surface_paint_layer_remove.disabled = true
		if surface_paint_texture:
			surface_paint_texture.disabled = true
		return
	var layer_count = _surface_active_face.paint_layers.size()
	var label_count = max(layer_count, 1)
	for i in range(label_count):
		surface_paint_layer_select.add_item("Layer %d" % i, i)
	surface_paint_layer_select.disabled = false
	if surface_paint_layer_add:
		surface_paint_layer_add.disabled = false
	if surface_paint_layer_remove:
		surface_paint_layer_remove.disabled = layer_count <= 1
	if surface_paint_texture:
		surface_paint_texture.disabled = false
	var target = clamp(surface_paint_layer_select.selected, 0, label_count - 1)
	surface_paint_layer_select.select(target)


func _on_paint_layer_selected(index: int) -> void:
	if not level_root:
		return
	level_root.set_active_paint_layer(index)
	_refresh_paint_layers()


func _on_paint_layer_add() -> void:
	if not level_root:
		return
	level_root.add_paint_layer()
	_refresh_paint_layers()


func _on_paint_layer_remove() -> void:
	if not level_root:
		return
	level_root.remove_active_paint_layer()
	_refresh_paint_layers()


func _on_material_selected(index: int) -> void:
	_selected_material_index = index


func _on_material_add() -> void:
	if material_palette_dialog:
		material_palette_dialog.popup_centered_ratio(0.6)


func _on_material_palette_selected(path: String) -> void:
	if path == "":
		return
	if not level_root:
		return
	var resource = ResourceLoader.load(path)
	if resource and resource is Material:
		level_root.add_material_to_palette(resource)
		_sync_materials_from_root()
	else:
		_log("Selected resource is not a material: %s" % path, true)


func _on_material_remove() -> void:
	if _selected_material_index < 0:
		return
	if not level_root:
		return
	level_root.remove_material_from_palette(_selected_material_index)
	_selected_material_index = -1
	_sync_materials_from_root()


func _on_material_assign() -> void:
	if _selected_material_index < 0:
		return
	if not level_root:
		return
	_commit_state_action(
		"Assign Face Material", "assign_material_to_selected_faces", [_selected_material_index]
	)


func _on_face_clear() -> void:
	if level_root:
		level_root.clear_face_selection()


func _on_uv_reset() -> void:
	if _uv_active_face == null:
		return
	_uv_active_face.custom_uvs = PackedVector2Array()
	_uv_active_face.ensure_custom_uvs()
	if level_root and _uv_active_brush:
		level_root.rebuild_brush_preview(_uv_active_brush)


func _on_uv_changed(_face: FaceData) -> void:
	if level_root and _uv_active_brush:
		level_root.rebuild_brush_preview(_uv_active_brush)


func _on_surface_paint_layer_selected(_index: int) -> void:
	pass


func _on_surface_paint_layer_add() -> void:
	if _surface_active_face == null:
		return
	_surface_active_face.paint_layers.append(FaceData.PaintLayer.new())
	_refresh_surface_paint_layers()
	if level_root and _surface_active_brush:
		level_root.rebuild_brush_preview(_surface_active_brush)


func _on_surface_paint_layer_remove() -> void:
	if _surface_active_face == null:
		return
	var idx = surface_paint_layer_select.selected if surface_paint_layer_select else 0
	if idx < 0 or idx >= _surface_active_face.paint_layers.size():
		return
	_surface_active_face.paint_layers.remove_at(idx)
	_refresh_surface_paint_layers()
	if level_root and _surface_active_brush:
		level_root.rebuild_brush_preview(_surface_active_brush)


func _on_surface_paint_texture() -> void:
	if _surface_active_face == null or not surface_paint_texture_dialog:
		return
	_pending_surface_texture_layer = (
		surface_paint_layer_select.selected if surface_paint_layer_select else 0
	)
	surface_paint_texture_dialog.popup_centered_ratio(0.6)


func _on_surface_paint_texture_selected(path: String) -> void:
	if path == "":
		return
	if _surface_active_face == null:
		return
	var resource = ResourceLoader.load(path)
	if not resource or not (resource is Texture2D):
		_log("Selected resource is not a texture: %s" % path, true)
		return
	var idx = _pending_surface_texture_layer
	if idx < 0 or idx >= _surface_active_face.paint_layers.size():
		return
	_surface_active_face.paint_layers[idx].texture = resource
	if level_root and _surface_active_brush:
		level_root.rebuild_brush_preview(_surface_active_brush)


func _shape_label(shape_key: String) -> String:
	var parts = shape_key.to_lower().split("_")
	var label := ""
	for part in parts:
		label += "%s " % part.capitalize()
	return label.strip_edges()


func _on_shape_selected(index: int) -> void:
	if not shape_select:
		return
	var shape_value = shape_select.get_item_id(index)
	_set_active_shape(shape_value)


func _set_active_shape(shape_value: int) -> void:
	active_shape = shape_value
	if shape_select:
		var target_index = -1
		for index in range(shape_select.get_item_count()):
			if shape_select.get_item_id(index) == shape_value:
				target_index = index
				break
		if target_index >= 0 and shape_select.selected != target_index:
			shape_select.select(target_index)
	_update_sides_visibility()


func _shape_requires_sides(shape_value: int) -> bool:
	return (
		shape_value == LevelRootType.BrushShape.PYRAMID
		or shape_value == LevelRootType.BrushShape.PRISM_TRI
		or shape_value == LevelRootType.BrushShape.PRISM_PENT
	)


func _update_sides_visibility() -> void:
	if sides_row:
		sides_row.visible = _shape_requires_sides(active_shape)


func _update_perf_label() -> void:
	if not perf_label:
		return
	if not level_root:
		perf_label.text = "Live Brushes: 0"
		perf_label.remove_theme_color_override("font_color")
		return
	var count = int(level_root.get_live_brush_count())
	perf_label.text = "Live Brushes: %s" % count
	var ok_color = _get_editor_color("success_color", Color(0.2, 0.85, 0.35))
	var warn_color = _get_editor_color("warning_color", Color(0.95, 0.8, 0.2))
	var danger_color = _get_editor_color("error_color", Color(0.95, 0.3, 0.3))
	if count <= 50:
		perf_label.add_theme_color_override("font_color", ok_color)
	elif count <= 100:
		perf_label.add_theme_color_override("font_color", warn_color)
	else:
		perf_label.add_theme_color_override("font_color", danger_color)


func _on_active_material_pressed() -> void:
	if not material_dialog:
		return
	material_dialog.popup_centered_ratio(0.6)


func _on_material_file_selected(path: String) -> void:
	if path == "":
		return
	var resource = ResourceLoader.load(path)
	if resource and resource is Material:
		active_material = resource
		var display_name = resource.resource_name
		if display_name == "":
			display_name = path.get_file()
		if active_material_button:
			active_material_button.text = "Active Material: %s" % display_name
	else:
		_log("Selected resource is not a material: %s" % path, true)


func _setup_storage_dialogs() -> void:
	if hflevel_save_dialog:
		hflevel_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
		hflevel_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		hflevel_save_dialog.filters = PackedStringArray(["*.hflevel ; HammerForge Level"])
		if not hflevel_save_dialog.file_selected.is_connected(
			Callable(self, "_on_hflevel_save_selected")
		):
			hflevel_save_dialog.file_selected.connect(_on_hflevel_save_selected)
	if material_palette_dialog:
		material_palette_dialog.access = FileDialog.ACCESS_FILESYSTEM
		material_palette_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		material_palette_dialog.filters = PackedStringArray(
			["*.tres, *.res ; Material", "*.material ; Material", "*.tres ; Resource"]
		)
		if not material_palette_dialog.file_selected.is_connected(
			Callable(self, "_on_material_palette_selected")
		):
			material_palette_dialog.file_selected.connect(_on_material_palette_selected)
	if surface_paint_texture_dialog:
		surface_paint_texture_dialog.access = FileDialog.ACCESS_FILESYSTEM
		surface_paint_texture_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		surface_paint_texture_dialog.filters = PackedStringArray(
			["*.png, *.jpg, *.tres, *.res ; Texture"]
		)
		if not surface_paint_texture_dialog.file_selected.is_connected(
			Callable(self, "_on_surface_paint_texture_selected")
		):
			surface_paint_texture_dialog.file_selected.connect(_on_surface_paint_texture_selected)
	if hflevel_load_dialog:
		hflevel_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
		hflevel_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		hflevel_load_dialog.filters = PackedStringArray(["*.hflevel ; HammerForge Level"])
		if not hflevel_load_dialog.file_selected.is_connected(
			Callable(self, "_on_hflevel_load_selected")
		):
			hflevel_load_dialog.file_selected.connect(_on_hflevel_load_selected)
	if map_import_dialog:
		map_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		map_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		map_import_dialog.filters = PackedStringArray(["*.map ; Quake Map"])
		if not map_import_dialog.file_selected.is_connected(
			Callable(self, "_on_map_import_selected")
		):
			map_import_dialog.file_selected.connect(_on_map_import_selected)
	if map_export_dialog:
		map_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		map_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		map_export_dialog.filters = PackedStringArray(["*.map ; Quake Map"])
		if not map_export_dialog.file_selected.is_connected(
			Callable(self, "_on_map_export_selected")
		):
			map_export_dialog.file_selected.connect(_on_map_export_selected)
	if glb_export_dialog:
		glb_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		glb_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		glb_export_dialog.filters = PackedStringArray(["*.glb ; GLB"])
		if not glb_export_dialog.file_selected.is_connected(
			Callable(self, "_on_glb_export_selected")
		):
			glb_export_dialog.file_selected.connect(_on_glb_export_selected)
	if autosave_path_dialog:
		autosave_path_dialog.access = FileDialog.ACCESS_FILESYSTEM
		autosave_path_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		autosave_path_dialog.filters = PackedStringArray(["*.hflevel ; HammerForge Level"])
		if not autosave_path_dialog.file_selected.is_connected(
			Callable(self, "_on_autosave_path_selected")
		):
			autosave_path_dialog.file_selected.connect(_on_autosave_path_selected)


func _on_save_hflevel() -> void:
	if hflevel_save_dialog:
		hflevel_save_dialog.popup_centered_ratio(0.6)


func _on_load_hflevel() -> void:
	if hflevel_load_dialog:
		hflevel_load_dialog.popup_centered_ratio(0.6)


func _on_import_map() -> void:
	if map_import_dialog:
		map_import_dialog.popup_centered_ratio(0.6)


func _on_export_map() -> void:
	if map_export_dialog:
		map_export_dialog.popup_centered_ratio(0.6)


func _on_export_glb() -> void:
	if glb_export_dialog:
		glb_export_dialog.popup_centered_ratio(0.6)


func _on_set_autosave_path() -> void:
	if autosave_path_dialog:
		autosave_path_dialog.popup_centered_ratio(0.6)


func _on_hflevel_save_selected(path: String) -> void:
	if not level_root:
		_set_status("No LevelRoot for .hflevel save", true)
		return
	var err = int(level_root.save_hflevel(path, true))
	_set_status("Saved .hflevel" if err == OK else "Failed to save .hflevel", err != OK, 3.0)


func _on_hflevel_load_selected(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_set_status("Invalid .hflevel path", true)
		return
	if not level_root:
		_set_status("No LevelRoot for .hflevel load", true)
		return
	_commit_full_state_action("Load .hflevel", "load_hflevel", [path])
	_set_status("Loaded .hflevel", false, 3.0)


func _on_map_import_selected(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_set_status("Invalid .map path", true)
		return
	if not level_root:
		_set_status("No LevelRoot for .map import", true)
		return
	_commit_full_state_action("Import .map", "import_map", [path])
	_set_status("Imported .map", false, 3.0)


func _on_map_export_selected(path: String) -> void:
	if not level_root:
		_set_status("No LevelRoot for .map export", true)
		return
	var err = int(level_root.export_map(path))
	_set_status("Exported .map" if err == OK else "Failed to export .map", err != OK, 3.0)


func _on_glb_export_selected(path: String) -> void:
	if not level_root:
		_set_status("No LevelRoot for .glb export", true)
		return
	var err = int(level_root.export_baked_gltf(path))
	_set_status("Exported .glb" if err == OK else "Failed to export .glb", err != OK, 3.0)


func _on_autosave_path_selected(path: String) -> void:
	if not level_root or not _root_has_property("hflevel_autosave_path"):
		_set_status("No LevelRoot for autosave path", true)
		return
	level_root.set("hflevel_autosave_path", path)
	_set_status("Autosave path set", false, 3.0)


var _status_timer: Timer = null


func _set_status(message: String, is_error: bool = false, timeout: float = 0.0) -> void:
	if status_label:
		status_label.text = message
		if is_error:
			var error_color = _get_editor_color("error_color", Color(0.95, 0.3, 0.3))
			status_label.add_theme_color_override("font_color", error_color)
		else:
			status_label.remove_theme_color_override("font_color")
	if is_error:
		_log(message, true)
	var clear_time = timeout if timeout > 0.0 else (5.0 if is_error else 0.0)
	if clear_time > 0.0:
		_start_status_timer(clear_time)
	else:
		_stop_status_timer()


func _set_status_warning(message: String, timeout: float = 5.0) -> void:
	if status_label:
		status_label.text = message
		var warn_color = _get_editor_color("warning_color", Color(0.95, 0.8, 0.2))
		status_label.add_theme_color_override("font_color", warn_color)
	_log(message, true)
	if timeout > 0.0:
		_start_status_timer(timeout)


func _start_status_timer(seconds: float) -> void:
	if not _status_timer:
		_status_timer = Timer.new()
		_status_timer.one_shot = true
		_status_timer.timeout.connect(_on_status_timer_timeout)
		add_child(_status_timer)
	_status_timer.stop()
	_status_timer.wait_time = seconds
	_status_timer.start()


func _stop_status_timer() -> void:
	if _status_timer:
		_status_timer.stop()


func _on_status_timer_timeout() -> void:
	if status_label:
		status_label.text = "Ready"
		status_label.remove_theme_color_override("font_color")


func _ensure_presets_dir() -> void:
	var abs_path = ProjectSettings.globalize_path(presets_dir)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)


func _load_presets() -> void:
	_clear_preset_buttons()
	var dir = DirAccess.open(presets_dir)
	if not dir:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for file in files:
		var path = "%s/%s" % [presets_dir, file]
		var preset = load(path)
		if preset and preset is BrushPreset:
			_create_preset_button(preset, path)


func _load_entity_definitions() -> void:
	entity_defs.clear()
	_clear_entity_palette()
	if not ResourceLoader.exists(entity_defs_path):
		return
	var file = FileAccess.open(entity_defs_path, FileAccess.READ)
	if not file:
		_log("Failed to open entity definitions: %s" % entity_defs_path, true)
		return
	var text = file.get_as_text()
	var data = JSON.parse_string(text)
	if data == null:
		_log("Failed to parse entity definitions: %s" % entity_defs_path, true)
		return
	if data is Dictionary:
		var entries = data.get("entities", [])
		if entries is Array and entries.size() > 0:
			entity_defs = entries
			return
		for key in data.keys():
			var entry = data[key]
			if entry is Dictionary:
				var record = entry.duplicate(true)
				record["id"] = str(key)
				entity_defs.append(record)
	elif data is Array:
		entity_defs = data
	_populate_entity_palette()


func get_entity_definitions() -> Array:
	return entity_defs.duplicate()


func _populate_entity_palette() -> void:
	_clear_entity_palette()
	if not entity_palette:
		return
	for entry in entity_defs:
		if not (entry is Dictionary):
			continue
		var entity_id = str(entry.get("id", entry.get("class", "")))
		if entity_id == "":
			continue
		var button = EntityPaletteButton.new()
		button.entity_id = entity_id
		button.entity_def = entry
		button.dock_ref = self
		button.text = _entity_display_name(entry, entity_id)
		button.tooltip_text = entity_id
		button.focus_mode = Control.FOCUS_NONE
		var icon = _resolve_entity_icon(entry)
		if icon:
			button.icon = icon
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_FILL
		entity_palette.add_child(button)
		entity_palette_buttons.append(button)


func _clear_entity_palette() -> void:
	for button in entity_palette_buttons:
		if button and button.get_parent():
			button.get_parent().remove_child(button)
			button.queue_free()
	entity_palette_buttons.clear()


func _entity_display_name(definition: Dictionary, fallback: String) -> String:
	if definition.has("label"):
		return str(definition.get("label", fallback))
	if definition.has("name"):
		return str(definition.get("name", fallback))
	if definition.has("title"):
		return str(definition.get("title", fallback))
	return fallback


func _resolve_entity_icon(definition: Dictionary) -> Texture2D:
	var icon_path = str(definition.get("preview_icon", definition.get("icon", "")))
	if icon_path == "":
		var preview = definition.get("preview", {})
		if preview is Dictionary:
			if str(preview.get("type", "")) == "billboard":
				icon_path = str(preview.get("path", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		if tex is Texture2D:
			return tex
	var class_id = str(definition.get("class", ""))
	if class_id.find("Light") >= 0:
		return _find_editor_icon(["Light3D", "OmniLight3D", "Light"])
	if class_id.find("Camera") >= 0:
		return _find_editor_icon(["Camera3D", "Camera"])
	return _find_editor_icon(["Node3D", "Node"])


func _make_entity_drag_data(entity_id: String, definition: Dictionary, source: Control) -> Variant:
	if entity_id == "":
		return null
	var data = {"type": "hammerforge_entity", "entity_id": entity_id}
	if source:
		var preview = _build_entity_drag_preview(definition, entity_id)
		if preview:
			source.set_drag_preview(preview)
	return data


func _build_entity_drag_preview(definition: Dictionary, entity_id: String) -> Control:
	var container = HBoxContainer.new()
	container.custom_minimum_size = Vector2(140, 28)
	container.size_flags_horizontal = Control.SIZE_FILL
	container.size_flags_vertical = Control.SIZE_FILL
	var icon = _resolve_entity_icon(definition)
	if icon:
		var icon_rect = TextureRect.new()
		icon_rect.texture = icon
		icon_rect.custom_minimum_size = Vector2(20, 20)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.add_child(icon_rect)
	var label = Label.new()
	label.text = _entity_display_name(definition, entity_id)
	container.add_child(label)
	return container


func _clear_preset_buttons() -> void:
	for button in preset_buttons:
		if button and button.get_parent():
			button.get_parent().remove_child(button)
			button.queue_free()
	preset_buttons.clear()


func _create_preset_button(preset: BrushPreset, path: String) -> void:
	if not preset_grid:
		return
	var button := Button.new()
	button.text = _preset_display_name(preset, path)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("preset_path", path)
	button.pressed.connect(_on_preset_button_pressed.bind(button))
	button.gui_input.connect(_on_preset_button_gui_input.bind(button))
	preset_grid.add_child(button)
	preset_buttons.append(button)


func _preset_display_name(preset: BrushPreset, path: String) -> String:
	if preset and preset.resource_name != "":
		return preset.resource_name
	var file_name = path.get_file().get_basename()
	return file_name.replace("_", " ")


func _on_save_preset() -> void:
	_ensure_presets_dir()
	var preset = BrushPreset.new()
	preset.shape = get_shape()
	preset.size = get_brush_size()
	preset.sides = get_sides()
	preset.operation = get_operation()
	var display_name = _suggest_preset_name()
	var path = _unique_preset_path(display_name)
	preset.resource_name = display_name
	var err = ResourceSaver.save(preset, path)
	if err != OK:
		_log("Failed to save preset (%s)" % err, true)
		return
	_load_presets()


func _suggest_preset_name() -> String:
	var base = "Preset"
	var index = preset_buttons.size() + 1
	return "%s %s" % [base, index]


func _sanitize_preset_name(name: String) -> String:
	var safe = name.strip_edges()
	safe = safe.replace("/", "_")
	safe = safe.replace("\\", "_")
	safe = safe.replace(":", "_")
	safe = safe.replace("*", "_")
	safe = safe.replace("?", "_")
	safe = safe.replace('"', "_")
	safe = safe.replace("<", "_")
	safe = safe.replace(">", "_")
	safe = safe.replace("|", "_")
	if safe == "":
		safe = "Preset"
	return safe


func _unique_preset_path(display_name: String) -> String:
	var safe = _sanitize_preset_name(display_name)
	var base = safe.replace(" ", "_")
	var path = "%s/%s.tres" % [presets_dir, base]
	var index = 1
	while ResourceLoader.exists(path):
		path = "%s/%s_%s.tres" % [presets_dir, base, index]
		index += 1
	return path


func _on_preset_button_pressed(button: Button) -> void:
	if not button:
		return
	var path = button.get_meta("preset_path", "")
	if path == "":
		return
	var preset = load(path)
	if preset and preset is BrushPreset:
		_apply_preset(preset)


func _apply_preset(preset: BrushPreset) -> void:
	if not preset:
		return
	size_x.value = preset.size.x
	size_y.value = preset.size.y
	size_z.value = preset.size.z
	_set_active_shape(preset.shape)
	if sides_spin:
		sides_spin.value = preset.sides
	if preset.operation == CSGShape3D.OPERATION_SUBTRACTION:
		mode_subtract.button_pressed = true
	else:
		mode_add.button_pressed = true


func _on_preset_button_gui_input(event: InputEvent, button: Button) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		preset_context_button = button
		if preset_menu:
			preset_menu.position = get_global_mouse_position()
			preset_menu.popup()
		button.accept_event()


func _on_preset_menu_id_pressed(id: int) -> void:
	if not preset_context_button:
		return
	match id:
		PRESET_MENU_RENAME:
			_show_preset_rename_dialog(preset_context_button)
		PRESET_MENU_DELETE:
			_delete_preset(preset_context_button)


func _show_preset_rename_dialog(button: Button) -> void:
	if not preset_rename_dialog or not preset_rename_line:
		return
	preset_rename_line.text = button.text
	preset_rename_line.select_all()
	preset_rename_dialog.popup_centered()


func _on_preset_rename_confirmed() -> void:
	if not preset_context_button:
		return
	var new_name = preset_rename_line.text
	_rename_preset(preset_context_button, new_name)
	preset_context_button = null


func _rename_preset(button: Button, new_name: String) -> void:
	var current_path = button.get_meta("preset_path", "")
	if current_path == "":
		return
	var display_name = _sanitize_preset_name(new_name)
	var base = display_name.replace(" ", "_")
	var candidate_path = "%s/%s.tres" % [presets_dir, base]
	var target_path = (
		candidate_path if candidate_path == current_path else _unique_preset_path(display_name)
	)
	var abs_current = ProjectSettings.globalize_path(current_path)
	var abs_target = ProjectSettings.globalize_path(target_path)
	if abs_current != abs_target:
		var rename_err = DirAccess.rename_absolute(abs_current, abs_target)
		if rename_err != OK:
			_log("Failed to rename preset (%s)" % rename_err, true)
			return
	var preset = load(target_path)
	if preset and preset is BrushPreset:
		preset.resource_name = display_name
		ResourceSaver.save(preset, target_path)
	_load_presets()
	preset_context_button = null


func _delete_preset(button: Button) -> void:
	var path = button.get_meta("preset_path", "")
	if path == "":
		return
	var abs_path = ProjectSettings.globalize_path(path)
	var remove_err = DirAccess.remove_absolute(abs_path)
	if remove_err != OK:
		_log("Failed to delete preset (%s)" % remove_err, true)
		return
	_load_presets()
	preset_context_button = null
