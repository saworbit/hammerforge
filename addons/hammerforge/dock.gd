@tool
extends Control
class_name HammerForgeDock

signal hud_visibility_changed(visible: bool)
signal builtin_tool_changed
signal vertex_mode_toggled(enabled: bool)
signal selection_clear_requested

const LevelRootType = preload("level_root.gd")
const BrushPreset = preload("brush_preset.gd")
const DraftEntity = preload("draft_entity.gd")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFCollapsibleSection = preload("ui/collapsible_section.gd")
const HFToast = preload("ui/hf_toast.gd")
const HFWelcomePanel = preload("ui/hf_welcome_panel.gd")
const HFTutorialWizard = preload("ui/hf_tutorial_wizard.gd")
const HFEntityDef = preload("hf_entity_def.gd")
const UVEditorScene = preload("uv_editor.tscn")
const PaintTabBuilder = preload("ui/paint_tab_builder.gd")
const EntityTabBuilder = preload("ui/entity_tab_builder.gd")
const ManageTabBuilder = preload("ui/manage_tab_builder.gd")
const SelectionToolsBuilder = preload("ui/selection_tools_builder.gd")

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


class BrushPresetButton:
	extends Button
	var preset_path: String = ""
	var dock_ref: HammerForgeDock = null

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if preset_path == "" or not dock_ref:
			return null
		return dock_ref._make_brush_drag_data(preset_path, text, self)


@onready var main_tabs: TabContainer = $Margin/VBox/MainTabs
@onready var brush_tab: ScrollContainer = $Margin/VBox/MainTabs/Brush
@onready var paint_tab: ScrollContainer = $Margin/VBox/MainTabs/Paint
@onready var entity_tab: ScrollContainer = $Margin/VBox/MainTabs/Entities
@onready var manage_tab: ScrollContainer = $Margin/VBox/MainTabs/Manage
@onready var no_root_banner: PanelContainer = $Margin/VBox/NoRootBanner
@onready var status_bar: HBoxContainer = $Margin/VBox/Footer/StatusFooter
@onready var progress_bar: ProgressBar = $Margin/VBox/Footer/StatusFooter/ProgressBar

@onready var tool_draw: Button = $Margin/VBox/Toolbar/ToolDraw
@onready var tool_select: Button = $Margin/VBox/Toolbar/ToolSelect
@onready var paint_mode: Button = $Margin/VBox/Toolbar/PaintMode
@onready var mode_add: Button = $Margin/VBox/Toolbar/ModeAdd
@onready var mode_subtract: Button = $Margin/VBox/Toolbar/ModeSubtract
@onready
var shape_select: OptionButton = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/ShapeRow/ShapeSelect
@onready var sides_row: HBoxContainer = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/SidesRow
@onready
var sides_spin: SpinBox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/SidesRow/SidesSpin
@onready
var active_material_button: Button = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/MaterialRow/ActiveMaterial
@onready var material_dialog: FileDialog = $MaterialDialog
@onready var material_palette_dialog: FileDialog = $MaterialPaletteDialog
@onready var surface_paint_texture_dialog: FileDialog = $SurfacePaintTextureDialog
@onready var hflevel_save_dialog: FileDialog = $HFLevelSaveDialog
@onready var hflevel_load_dialog: FileDialog = $HFLevelLoadDialog
@onready var map_import_dialog: FileDialog = $MapImportDialog
@onready var map_export_dialog: FileDialog = $MapExportDialog
@onready var glb_export_dialog: FileDialog = $GLBExportDialog
@onready var autosave_path_dialog: FileDialog = $AutosavePathDialog
@onready var size_x: SpinBox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/SizeRow/SizeX
@onready var size_y: SpinBox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/SizeRow/SizeY
@onready var size_z: SpinBox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/SizeRow/SizeZ
# -- Paint tab controls (built programmatically in _build_paint_tab) --
var paint_tool_select: OptionButton = null
var paint_radius: SpinBox = null
var brush_shape_select: OptionButton = null
var paint_layer_select: OptionButton = null
var paint_layer_add: Button = null
var paint_layer_remove: Button = null
var paint_layer_rename: Button = null
var region_enable: CheckBox = null
var region_size_spin: SpinBox = null
var region_radius_spin: SpinBox = null
var region_memory_spin: SpinBox = null
var region_grid_toggle: CheckBox = null
var heightmap_import: Button = null
var heightmap_generate: Button = null
var height_scale_spin: SpinBox = null
var layer_y_spin: SpinBox = null
var blend_strength_spin: SpinBox = null
var blend_slot_select: OptionButton = null
var terrain_slot_a_button: Button = null
var terrain_slot_a_scale: SpinBox = null
var terrain_slot_b_button: Button = null
var terrain_slot_b_scale: SpinBox = null
var terrain_slot_c_button: Button = null
var terrain_slot_c_scale: SpinBox = null
var terrain_slot_d_button: Button = null
var terrain_slot_d_scale: SpinBox = null
@onready var terrain_slot_texture_dialog: FileDialog = $TerrainSlotTextureDialog
@onready var heightmap_import_dialog: FileDialog = $HeightmapImportDialog
@onready var grid_snap: SpinBox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/GridRow/GridSnap
@onready
var collision_layer_opt: OptionButton = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/PhysicsLayerRow/PhysicsLayerOption
# -- Bake options (built programmatically in _build_manage_tab) --
var bake_merge_meshes: CheckBox = null
var bake_generate_lods: CheckBox = null
var bake_lightmap_uv2: CheckBox = null
var bake_use_face_materials: CheckBox = null
var bake_lightmap_texel_row: HBoxContainer = null
var bake_lightmap_texel: SpinBox = null
var bake_navmesh: CheckBox = null
var bake_navmesh_cell_row: HBoxContainer = null
var bake_navmesh_cell_size: SpinBox = null
var bake_navmesh_cell_height: SpinBox = null
var bake_navmesh_agent_row: HBoxContainer = null
var bake_navmesh_agent_height: SpinBox = null
var bake_navmesh_agent_radius: SpinBox = null
# -- Editor toggles (built programmatically in _build_manage_tab) --
var commit_freeze: CheckBox = null
var show_hud: CheckBox = null
var show_grid: CheckBox = null
var follow_grid: CheckBox = null
var debug_logs: CheckBox = null
# -- Manage tab action buttons (built programmatically) --
var floor_btn: Button = null
var apply_cuts_btn: Button = null
var clear_cuts_btn: Button = null
var commit_cuts_btn: Button = null
var restore_cuts_btn: Button = null
var bake_dry_run_btn: Button = null
var validate_btn: Button = null
var validate_fix_btn: Button = null
@onready
var create_entity_btn: Button = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox/CreateEntity
@onready
var entity_palette: GridContainer = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox/EntityPalette
var bake_btn: Button = null
var clear_btn: Button = null
# -- File buttons (built programmatically) --
var save_hflevel_btn: Button = null
var load_hflevel_btn: Button = null
var import_map_btn: Button = null
var export_map_btn: Button = null
var map_format_select: OptionButton = null
var export_glb_btn: Button = null
# -- Autosave controls (built programmatically) --
var autosave_enabled: CheckBox = null
var autosave_minutes: SpinBox = null
var autosave_path_btn: Button = null
var autosave_keep: SpinBox = null
@onready var _mode_indicator: PanelContainer = $Margin/VBox/ModeIndicator
@onready var _mode_label: Label = $Margin/VBox/ModeIndicator/ModeLabel
var _mode_style: StyleBoxFlat = null
var _mode_last_color := Color.TRANSPARENT
@onready var status_label: Label = $Margin/VBox/Footer/StatusFooter/StatusLabel
@onready var selection_label: Label = $Margin/VBox/Footer/StatusFooter/SelectionLabel
@onready var perf_label: Label = $Margin/VBox/Footer/StatusFooter/BrushCountLabel
# -- History (built programmatically) --
var undo_btn: Button = null
var redo_btn: Button = null
var history_list: ItemList = null
@onready var quick_play_btn: Button = $Margin/VBox/Footer/QuickPlay
# -- Settings (built programmatically) --
var export_settings_btn: Button = null
var import_settings_btn: Button = null
@onready var settings_export_dialog: FileDialog = $SettingsExportDialog
@onready var settings_import_dialog: FileDialog = $SettingsImportDialog
# -- Performance (built programmatically) --
var perf_brushes_value: Label = null
var perf_paint_mem_value: Label = null
var perf_bake_chunks_value: Label = null
var perf_bake_time_value: Label = null
# -- Materials (built programmatically in _build_paint_tab) --
var material_browser: HFMaterialBrowser = null
var materials_list: ItemList = null
var material_add: Button = null
var material_remove: Button = null
var material_load_prototypes: Button = null
var material_assign: Button = null
var face_select_mode: CheckBox = null
var face_clear: Button = null
var _material_context_popup: PopupMenu = null
var _material_context_index: int = -1
var _hover_preview_faces: Array = []
# -- UV (built programmatically in _build_paint_tab) --
var uv_editor: UVEditor = null
var uv_reset: Button = null
# -- Surface paint (built programmatically in _build_paint_tab) --
var paint_target_select: OptionButton = null
var surface_paint_radius: SpinBox = null
var surface_paint_strength: SpinBox = null
var surface_paint_layer_select: OptionButton = null
var surface_paint_layer_add: Button = null
var surface_paint_layer_remove: Button = null
var surface_paint_texture: Button = null
# -- Presets (built programmatically) --
var save_preset_btn: Button = null
var preset_grid: GridContainer = null
@onready var preset_menu: PopupMenu = $PresetMenu
@onready var preset_rename_dialog: AcceptDialog = $PresetRenameDialog
@onready var preset_rename_line: LineEdit = $PresetRenameDialog/PresetRenameLine

@onready var snap_buttons: Array[Button] = [
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap1,
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap2,
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap4,
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap8,
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap16,
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap32,
	$Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/QuickSnapGrid/Snap64
]
var snap_preset_values: Array = [1, 2, 4, 8, 16, 32, 64]

var level_root: LevelRootType = null
var editor_interface: EditorInterface = null
var editor_base_control: Control = null
var undo_redo: EditorUndoRedoManager = null
var connected_root: Node = null
var snap_button_group: ButtonGroup
var syncing_snap := false
var snap_grid_btn: Button = null
var snap_vertex_btn: Button = null
var snap_center_btn: Button = null
var _axis_lock_x: Button = null
var _axis_lock_y: Button = null
var _axis_lock_z: Button = null
var _show_io_lines: CheckBox = null
var _show_subtract_preview: CheckBox = null
var _show_spawn_debug: CheckBox = null
var _spawn_validate_btn: Button = null
var _spawn_auto_create_btn: Button = null
var _prefab_library = null  # HFPrefabLibrary
var _sculpt_raise_btn: Button = null
var _sculpt_lower_btn: Button = null
var _sculpt_smooth_btn: Button = null
var _sculpt_flatten_btn: Button = null
var _sculpt_strength_spin: SpinBox = null
var _sculpt_radius_spin: SpinBox = null
var _sculpt_falloff_spin: SpinBox = null
var debug_enabled := false
@onready var _autosave_warning: Label = $Margin/VBox/AutosaveWarning
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
var terrain_slot_buttons: Array[Button] = []
var terrain_slot_scales: Array[SpinBox] = []
var _terrain_slot_pick_index: int = -1
var _terrain_slot_refreshing := false
var _region_settings_refreshing := false
var _bake_disabled := false
var _perf_frame_counter: int = 0
var _hints_dirty: bool = true
var _prop_cache: Dictionary = {}
var tool_extrude_up: Button = null
var tool_extrude_down: Button = null
var tool_vertex: Button = null

# Wave 1 UI controls
var _selection_nodes: Array = []
var _all_sections: Dictionary = {}
var _selection_tools_section: HFCollapsibleSection = null
var _sel_tools_hint_label: Label = null
var _uv_hint_label: Label = null
var _toast_container: VBoxContainer = null
var _clear_sel_btn: Button = null
var _welcome_panel: PanelContainer = null
var _tutorial_wizard = null
var _brush_hint: Label = null
var _paint_hint: Label = null
var _entity_hint: Label = null
var _manage_hint: Label = null
var texture_lock_check: CheckBox = null
var visgroup_list: ItemList = null
var visgroup_name_input: LineEdit = null
var visgroup_add_btn: Button = null
var visgroup_add_sel_btn: Button = null
var visgroup_rem_sel_btn: Button = null
var visgroup_delete_btn: Button = null
var group_sel_btn: Button = null
var ungroup_btn: Button = null
var cordon_enabled_check: CheckBox = null
var cordon_min_x: SpinBox = null
var cordon_min_y: SpinBox = null
var cordon_min_z: SpinBox = null
var cordon_max_x: SpinBox = null
var cordon_max_y: SpinBox = null
var cordon_max_z: SpinBox = null
var cordon_from_sel_btn: Button = null

# Wave 2 UI controls
var hollow_thickness: SpinBox = null
var hollow_btn: Button = null
var move_floor_btn: Button = null
var move_ceiling_btn: Button = null
var tie_entity_btn: Button = null
var untie_entity_btn: Button = null
var brush_entity_class_opt: OptionButton = null
var justify_fit_btn: Button = null
var justify_center_btn: Button = null
var justify_left_btn: Button = null
var justify_right_btn: Button = null
var justify_top_btn: Button = null
var justify_bottom_btn: Button = null
var justify_treat_as_one: CheckBox = null
var clip_btn: Button = null
# Duplicator controls
var dup_count_spin: SpinBox = null
var dup_offset_x: SpinBox = null
var dup_offset_y: SpinBox = null
var dup_offset_z: SpinBox = null
# Entity I/O controls
var io_output_name: LineEdit = null
var io_target_name: LineEdit = null
var io_input_name: LineEdit = null
var io_parameter: LineEdit = null
var io_delay: SpinBox = null
var io_fire_once: CheckBox = null
var io_add_btn: Button = null
var io_list: ItemList = null
var io_remove_btn: Button = null
# Entity Properties controls
var _entity_props_section: VBoxContainer = null
var _entity_props_controls: Array = []
var _entity_props_entity: Node3D = null


func _is_level_root(node: Node) -> bool:
	return node != null and node is LevelRootType


func _find_level_root_in(scene: Node) -> Node:
	if not scene:
		return null
	# Check scene root itself
	if scene.get_script() == LevelRootType or scene is LevelRootType:
		return scene
	# Check direct child named "LevelRoot" (fast path)
	var candidate = scene.get_node_or_null("LevelRoot")
	if candidate:
		return candidate
	# Deep search — find any LevelRoot anywhere in the tree
	for child in scene.get_children():
		var found = _find_level_root_recursive(child)
		if found:
			return found
	return null


func _find_level_root_recursive(node: Node) -> Node:
	if node.get_script() == LevelRootType or node is LevelRootType:
		return node
	for child in node.get_children():
		var found = _find_level_root_recursive(child)
		if found:
			return found
	return null


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


func _on_setting_toggled(pressed: bool, prop: String) -> void:
	if level_root and _root_has_property(prop):
		level_root.set(prop, pressed)


func _on_setting_float_changed(value: float, prop: String) -> void:
	if level_root and _root_has_property(prop):
		level_root.set(prop, value)


func _on_setting_int_changed(value: float, prop: String) -> void:
	if level_root and _root_has_property(prop):
		level_root.set(prop, int(value))


func _on_debug_toggled(pressed: bool) -> void:
	debug_enabled = pressed
	if level_root and _root_has_property("debug_logging"):
		level_root.set("debug_logging", pressed)


func _connect_setting_signals() -> void:
	# CheckBox → bool property
	var toggle_bindings: Array = [
		[bake_merge_meshes, "bake_merge_meshes"],
		[bake_generate_lods, "bake_generate_lods"],
		[bake_lightmap_uv2, "bake_lightmap_uv2"],
		[bake_use_face_materials, "bake_use_face_materials"],
		[bake_navmesh, "bake_navmesh"],
		[commit_freeze, "commit_freeze"],
		[autosave_enabled, "hflevel_autosave_enabled"],
		[show_grid, "grid_visible"],
		[follow_grid, "grid_follow_brush"],
	]
	for binding in toggle_bindings:
		var ctrl: CheckBox = binding[0] as CheckBox
		var prop: String = binding[1]
		if ctrl:
			ctrl.toggled.connect(_on_setting_toggled.bind(prop))
	# SpinBox → float property
	var float_bindings: Array = [
		[bake_lightmap_texel, "bake_lightmap_texel_size"],
		[bake_navmesh_cell_size, "bake_navmesh_cell_size"],
		[bake_navmesh_cell_height, "bake_navmesh_cell_height"],
		[bake_navmesh_agent_height, "bake_navmesh_agent_height"],
		[bake_navmesh_agent_radius, "bake_navmesh_agent_radius"],
	]
	for binding in float_bindings:
		var ctrl: SpinBox = binding[0] as SpinBox
		var prop: String = binding[1]
		if ctrl:
			ctrl.value_changed.connect(_on_setting_float_changed.bind(prop))
	# SpinBox → int property
	var int_bindings: Array = [
		[autosave_minutes, "hflevel_autosave_minutes"],
		[autosave_keep, "hflevel_autosave_keep"],
	]
	for binding in int_bindings:
		var ctrl: SpinBox = binding[0] as SpinBox
		var prop: String = binding[1]
		if ctrl:
			ctrl.value_changed.connect(_on_setting_int_changed.bind(prop))
	# Debug checkbox (special — also sets local debug_enabled bool)
	if debug_logs:
		debug_logs.toggled.connect(_on_debug_toggled)


func _apply_ui_state_to_root() -> void:
	if not level_root:
		return
	var toggle_pairs: Array = [
		[bake_merge_meshes, "bake_merge_meshes"],
		[bake_generate_lods, "bake_generate_lods"],
		[bake_lightmap_uv2, "bake_lightmap_uv2"],
		[bake_use_face_materials, "bake_use_face_materials"],
		[bake_navmesh, "bake_navmesh"],
		[commit_freeze, "commit_freeze"],
		[autosave_enabled, "hflevel_autosave_enabled"],
		[show_grid, "grid_visible"],
		[follow_grid, "grid_follow_brush"],
	]
	for pair in toggle_pairs:
		var ctrl: CheckBox = pair[0] as CheckBox
		var prop: String = pair[1]
		if ctrl and _root_has_property(prop):
			level_root.set(prop, ctrl.button_pressed)
	var float_pairs: Array = [
		[bake_lightmap_texel, "bake_lightmap_texel_size"],
		[bake_navmesh_cell_size, "bake_navmesh_cell_size"],
		[bake_navmesh_cell_height, "bake_navmesh_cell_height"],
		[bake_navmesh_agent_height, "bake_navmesh_agent_height"],
		[bake_navmesh_agent_radius, "bake_navmesh_agent_radius"],
	]
	for pair in float_pairs:
		var ctrl: SpinBox = pair[0] as SpinBox
		var prop: String = pair[1]
		if ctrl and _root_has_property(prop):
			level_root.set(prop, float(ctrl.value))
	var int_pairs: Array = [
		[autosave_minutes, "hflevel_autosave_minutes"],
		[autosave_keep, "hflevel_autosave_keep"],
	]
	for pair in int_pairs:
		var ctrl: SpinBox = pair[0] as SpinBox
		var prop: String = pair[1]
		if ctrl and _root_has_property(prop):
			level_root.set(prop, int(ctrl.value))
	if _root_has_property("debug_logging"):
		level_root.set("debug_logging", debug_enabled)


var _keymap: HFKeymap = null
var _user_prefs: HFUserPrefs = null


func set_user_prefs(prefs: HFUserPrefs) -> void:
	_user_prefs = prefs
	_apply_user_prefs()


## Read persisted prefs and apply them to dock controls.
func _apply_user_prefs() -> void:
	if not _user_prefs:
		return
	# Grid snap default
	var snap_val = _user_prefs.get_pref("grid_snap", 16.0)
	if grid_snap and float(snap_val) > 0.0:
		grid_snap.value = float(snap_val)
	# Show HUD
	var hud_vis = _user_prefs.get_pref("show_hud", true)
	if show_hud:
		show_hud.button_pressed = bool(hud_vis)
	# Restore collapsed section state
	for sec_name in _all_sections:
		var collapsed = _user_prefs.get_section_collapsed(sec_name)
		if collapsed != null:
			_all_sections[sec_name].set_expanded(not bool(collapsed))
	# Show welcome panel on first launch
	if _user_prefs.get_pref("show_welcome", true) and not _welcome_panel:
		_show_welcome_panel()


func _make_context_hint() -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.55))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _setup_context_hints() -> void:
	var brush_vbox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox
	if brush_vbox:
		_brush_hint = _make_context_hint()
		brush_vbox.add_child(_brush_hint)

	var paint_vbox = $Margin/VBox/MainTabs/Paint/PaintMargin/PaintVBox
	if paint_vbox:
		_paint_hint = _make_context_hint()
		paint_vbox.add_child(_paint_hint)

	var ent_vbox = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox
	if ent_vbox:
		_entity_hint = _make_context_hint()
		ent_vbox.add_child(_entity_hint)

	var manage_vbox = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox
	if manage_vbox:
		_manage_hint = _make_context_hint()
		manage_vbox.add_child(_manage_hint)

	_update_context_hints()


func _update_context_hints() -> void:
	var has_root = level_root != null
	var has_brushes = (
		has_root and level_root.has_method("get_brush_count") and level_root.get_brush_count() > 0
	)
	var has_selection = _selection_nodes.size() > 0

	if _brush_hint:
		if not has_root:
			_brush_hint.text = "Add a LevelRoot node to your scene to begin"
		elif not has_brushes:
			_brush_hint.text = "Click and drag in the viewport to draw your first brush"
		elif has_selection:
			_brush_hint.text = "Try: Hollow (Ctrl+H), Clip (Shift+X), or Extrude (U)"
		else:
			_brush_hint.text = "Click a brush in the viewport to select it"

	if _paint_hint:
		if not has_root:
			_paint_hint.text = ""
		elif has_brushes:
			_paint_hint.text = ""
		else:
			_paint_hint.text = "Draw some brushes first, then paint them here"

	if _entity_hint:
		if has_root:
			_entity_hint.text = "Drag an entity from the palette into the viewport"
		else:
			_entity_hint.text = ""

	if _manage_hint:
		if has_root and has_brushes:
			_manage_hint.text = "When ready, use Bake to convert brushes into final geometry"
		else:
			_manage_hint.text = ""


func _show_welcome_panel() -> void:
	var start_step: int = 0
	if _user_prefs:
		start_step = int(_user_prefs.get_pref("tutorial_step", 0))
	# If tutorial was already completed, don't show again
	if start_step >= HFTutorialWizard.get_step_count():
		return
	_tutorial_wizard = HFTutorialWizard.new()
	_tutorial_wizard.set_user_prefs(_user_prefs)
	_tutorial_wizard.dismissed.connect(_on_tutorial_dismissed)
	_tutorial_wizard.completed.connect(_on_tutorial_completed)
	var vbox = $Margin/VBox
	var tabs = $Margin/VBox/MainTabs
	var idx = tabs.get_index()
	vbox.add_child(_tutorial_wizard)
	vbox.move_child(_tutorial_wizard, idx)
	# Always call start() so labels/progress are populated immediately.
	# If level_root is null, the wizard shows text but can't auto-advance
	# until set_root() connects signals later.
	_tutorial_wizard.start(level_root, self, start_step)


func _on_tutorial_dismissed(dont_show_again: bool) -> void:
	if dont_show_again and _user_prefs:
		_user_prefs.set_pref("show_welcome", false)
		_user_prefs.save()
	_close_tutorial()


func _on_tutorial_completed() -> void:
	# Auto-close after a brief delay so user sees the "Done!" message
	if is_instance_valid(_tutorial_wizard):
		var tree := get_tree()
		if tree:
			tree.create_timer(2.0).timeout.connect(_close_tutorial)


func _close_tutorial() -> void:
	if _tutorial_wizard and is_instance_valid(_tutorial_wizard):
		_tutorial_wizard.queue_free()
		_tutorial_wizard = null
	# Legacy compat
	if _welcome_panel:
		_welcome_panel.queue_free()
		_welcome_panel = null


## Highlight a dock tab by name (brief flash effect for tutorial).
func highlight_tab(tab_name: String) -> void:
	var tabs_node = $Margin/VBox/MainTabs
	if not tabs_node:
		return
	for i in tabs_node.get_tab_count():
		if tabs_node.get_tab_title(i) == tab_name:
			tabs_node.current_tab = i
			break


func _on_welcome_dismissed(dont_show_again: bool) -> void:
	if dont_show_again and _user_prefs:
		_user_prefs.set_pref("show_welcome", false)
		_user_prefs.save()
	var tabs = $Margin/VBox/MainTabs
	if tabs:
		tabs.visible = true
	if _welcome_panel:
		_welcome_panel.queue_free()
		_welcome_panel = null


## Persist a pref change to disk.
func _save_user_pref(key: String, value: Variant) -> void:
	if not _user_prefs:
		return
	_user_prefs.set_pref(key, value)
	_user_prefs.save()


func _register_section(section: HFCollapsibleSection, section_name: String) -> void:
	_all_sections[section_name] = section
	section.toggled.connect(_on_section_toggled.bind(section_name))


func _on_section_toggled(expanded: bool, section_name: String) -> void:
	if _user_prefs:
		_user_prefs.set_section_collapsed(section_name, not expanded)
		_user_prefs.save()


func set_keymap(km: HFKeymap) -> void:
	_keymap = km
	_update_toolbar_shortcut_labels()


func _update_toolbar_shortcut_labels() -> void:
	if not _keymap:
		return
	if tool_draw:
		var key = _keymap.get_display_string("tool_draw")
		tool_draw.text = key
		tool_draw.tooltip_text = "Draw (%s)" % key
	if tool_select:
		var key = _keymap.get_display_string("tool_select")
		tool_select.text = key
		tool_select.tooltip_text = "Select (%s)" % key
	if tool_extrude_up:
		var key = _keymap.get_display_string("tool_extrude_up")
		tool_extrude_up.text = "\u25b2"
		tool_extrude_up.tooltip_text = "Extrude Up (%s)\nClick face + drag to extrude upward" % key
	if tool_extrude_down:
		var key = _keymap.get_display_string("tool_extrude_down")
		tool_extrude_down.text = "\u25bc"
		tool_extrude_down.tooltip_text = (
			"Extrude Down (%s)\nClick face + drag to extrude downward" % key
		)


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
	_set_toolbar_button_icon(mode_subtract, ["Remove", "RemoveNode"], "Sub")
	if paint_mode:
		_set_toolbar_button_icon(paint_mode, ["Paint", "Brush", "ToolPaint"], "Paint")
	if tool_extrude_up:
		_set_toolbar_button_icon(tool_extrude_up, ["MoveUp", "ArrowUp", "ToolMove"], "Ext Up")
	if tool_extrude_down:
		_set_toolbar_button_icon(tool_extrude_down, ["MoveDown", "ArrowDown", "ToolMove"], "Ext Dn")
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
	if not control.has_meta("default_tooltip"):
		control.set_meta("default_tooltip", text)
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
	_set_tooltip(
		active_material_button,
		(
			"Brush-level material override for whole brushes"
			+ "\nThis is separate from per-face materials in the Materials tab"
		)
	)
	# Build tab - Bake options
	_set_tooltip(bake_merge_meshes, "Merge meshes during bake for better performance")
	_set_tooltip(bake_generate_lods, "Generate LOD meshes during bake")
	_set_tooltip(bake_lightmap_uv2, "Generate UV2 for lightmap baking")
	_set_tooltip(
		bake_use_face_materials,
		(
			"Bake per-face materials into the final mesh"
			+ "\nTurn off to ignore face assignments and use brush-level materials instead"
		)
	)
	_set_tooltip(bake_navmesh, "Generate navigation mesh during bake")
	_set_tooltip(bake_lightmap_texel, "Lightmap texel density (smaller = higher quality)")
	_set_tooltip(bake_navmesh_cell_size, "Navigation mesh cell size (XZ)")
	_set_tooltip(bake_navmesh_cell_height, "Navigation mesh cell height (Y)")
	_set_tooltip(bake_navmesh_agent_height, "Navigation agent height")
	_set_tooltip(bake_navmesh_agent_radius, "Navigation agent radius")
	# FloorPaint tab
	_set_tooltip(
		paint_tool_select,
		"Floor paint tool\nB: Brush | E: Erase | R: Rect | L: Line | K: Bucket | N: Blend"
	)
	_set_tooltip(paint_radius, "Floor paint brush radius in grid cells")
	_set_tooltip(brush_shape_select, "Brush shape: Square or Circle")
	_set_tooltip(paint_layer_select, "Active floor paint layer")
	_set_tooltip(paint_layer_add, "Add a new floor paint layer")
	_set_tooltip(paint_layer_remove, "Remove the selected floor paint layer")
	_set_tooltip(paint_layer_rename, "Rename the selected floor paint layer")
	_set_tooltip(region_enable, "Enable region streaming for floor paint data")
	_set_tooltip(region_size_spin, "Region size in grid cells (power of two recommended)")
	_set_tooltip(region_radius_spin, "Streaming radius in regions around the cursor")
	_set_tooltip(region_memory_spin, "Memory budget for loaded regions (MB)")
	_set_tooltip(region_grid_toggle, "Show region boundaries in the viewport")
	_set_tooltip(heightmap_import, "Import a heightmap image (PNG/EXR) for the active layer")
	_set_tooltip(heightmap_generate, "Generate a procedural noise heightmap for the active layer")
	_set_tooltip(height_scale_spin, "Height scale multiplier for the heightmap")
	_set_tooltip(layer_y_spin, "Vertical Y offset for the active paint layer")
	_set_tooltip(blend_strength_spin, "Blend strength when using the Blend paint tool")
	_set_tooltip(blend_slot_select, "Blend target slot (B, C, or D)")
	_set_tooltip(
		terrain_slot_a_button,
		"Choose terrain texture for Slot A (base layer)\nBlend between slots with the Blend paint tool"
	)
	_set_tooltip(terrain_slot_a_scale, "UV scale for Slot A texture")
	_set_tooltip(
		terrain_slot_b_button,
		"Choose terrain texture for Slot B\nBlend between slots with the Blend paint tool"
	)
	_set_tooltip(terrain_slot_b_scale, "UV scale for Slot B texture")
	_set_tooltip(
		terrain_slot_c_button,
		"Choose terrain texture for Slot C\nBlend between slots with the Blend paint tool"
	)
	_set_tooltip(terrain_slot_c_scale, "UV scale for Slot C texture")
	_set_tooltip(
		terrain_slot_d_button,
		"Choose terrain texture for Slot D\nBlend between slots with the Blend paint tool"
	)
	_set_tooltip(terrain_slot_d_scale, "UV scale for Slot D texture")
	# SurfacePaint tab
	_set_tooltip(paint_target_select, "Paint target: Floor (grid) or Surface (UV)")
	_set_tooltip(surface_paint_radius, "Surface paint radius in UV space (0.0 - 1.0)")
	_set_tooltip(surface_paint_strength, "Surface paint opacity/strength (0.0 - 1.0)")
	_set_tooltip(surface_paint_layer_select, "Active surface paint layer")
	_set_tooltip(surface_paint_layer_add, "Add a new surface paint layer")
	_set_tooltip(surface_paint_layer_remove, "Remove the selected surface paint layer")
	_set_tooltip(
		surface_paint_texture,
		(
			"Choose the texture for the selected surface-paint layer"
			+ "\nRequires a selected face and an existing paint layer"
		)
	)
	# Materials tab
	_set_tooltip(
		face_select_mode,
		(
			"Enable per-face texturing"
			+ "\nClick faces in the viewport to select them"
			+ "\nShift+Click adds more faces"
			+ "\nRequired for per-face assign, UV edit, and surface paint"
		)
	)
	_set_tooltip(material_add, "Add a material to the palette")
	_set_tooltip(material_remove, "Remove selected material from palette")
	_set_tooltip(
		material_load_prototypes,
		(
			"Load built-in prototype textures into the palette"
			+ "\nUse this first if the browser looks empty"
		)
	)
	_set_tooltip(
		material_assign,
		(
			"Apply the selected material to all selected faces"
			+ "\nTip: choose a texture in the browser, then click faces in Face Select Mode"
		)
	)
	_set_tooltip(face_clear, "Clear face selection")
	# UV tab
	_set_tooltip(
		uv_reset,
		(
			"Reset this face to default projected UVs"
			+ "\nUse after stretching or before Fit/Center/Left/Right justify"
		)
	)
	# Manage tab
	_set_tooltip(floor_btn, "Create a default floor brush")
	_set_tooltip(apply_cuts_btn, "Move pending cuts into the draft brush tree")
	_set_tooltip(clear_cuts_btn, "Remove all pending cuts without applying")
	_set_tooltip(commit_cuts_btn, "Apply pending cuts, bake, then freeze/remove cut geometry")
	_set_tooltip(restore_cuts_btn, "Restore frozen committed cuts back to draft tree")
	_set_tooltip(hollow_btn, "Convert selected solid brush into a hollow room (Ctrl+H)")
	_set_tooltip(hollow_thickness, "Wall thickness for the hollow operation")
	_set_tooltip(
		move_floor_btn, "Snap selected brushes to the nearest surface below (Ctrl+Shift+F)"
	)
	_set_tooltip(
		move_ceiling_btn, "Snap selected brushes to the nearest surface above (Ctrl+Shift+C)"
	)
	_set_tooltip(tie_entity_btn, "Tag selected brushes as a brush entity class")
	_set_tooltip(untie_entity_btn, "Remove brush entity tag from selected brushes")
	_set_tooltip(brush_entity_class_opt, "Choose brush entity class (func_detail, trigger, etc.)")
	_set_tooltip(justify_fit_btn, "Scale UVs to fit the face exactly")
	_set_tooltip(justify_center_btn, "Center UVs on the face")
	_set_tooltip(justify_left_btn, "Align UVs to the left edge")
	_set_tooltip(justify_right_btn, "Align UVs to the right edge")
	_set_tooltip(justify_top_btn, "Align UVs to the top edge")
	_set_tooltip(justify_bottom_btn, "Align UVs to the bottom edge")
	_set_tooltip(bake_btn, "Bake draft brushes into optimized static meshes")
	_set_tooltip(bake_dry_run_btn, "Report what will be baked without generating geometry")
	_set_tooltip(validate_btn, "Scan the level for common issues")
	_set_tooltip(validate_fix_btn, "Scan and auto-fix common issues")
	_set_tooltip(clear_btn, "Remove all brushes and baked geometry")
	_set_tooltip(save_hflevel_btn, "Save level to .hflevel file")
	_set_tooltip(load_hflevel_btn, "Load level from .hflevel file")
	_set_tooltip(import_map_btn, "Import a Quake-style .map file")
	_set_tooltip(export_map_btn, "Export level as .map file")
	_set_tooltip(export_glb_btn, "Export baked geometry as .glb file")
	_set_tooltip(autosave_enabled, "Enable automatic saving at regular intervals")
	_set_tooltip(autosave_minutes, "Autosave interval in minutes")
	_set_tooltip(autosave_path_btn, "Set the autosave file path")
	_set_tooltip(autosave_keep, "Keep the last N autosave history files")
	_set_tooltip(export_settings_btn, "Export editor preferences to a settings file")
	_set_tooltip(import_settings_btn, "Import editor preferences from a settings file")
	_set_tooltip(save_preset_btn, "Save current brush settings as a reusable preset")
	_set_tooltip(quick_play_btn, "Bake and play the current scene")
	_set_tooltip(clip_btn, "Split selected brush along nearest axis plane (Shift+X)")
	# Entities tab
	_set_tooltip(create_entity_btn, "Create a new entity at the cursor position")
	_set_tooltip(io_output_name, "Output event name (e.g. OnTrigger, OnDamaged)")
	_set_tooltip(io_target_name, "Target entity name to fire the input on")
	_set_tooltip(io_input_name, "Input action on target entity (e.g. Open, Kill)")
	_set_tooltip(io_parameter, "Optional parameter string passed to the input")
	_set_tooltip(io_delay, "Delay in seconds before firing the input")
	_set_tooltip(io_fire_once, "If checked, connection fires only once then auto-removes")
	_set_tooltip(io_add_btn, "Add an output connection to the selected entity")
	_set_tooltip(io_remove_btn, "Remove the selected output connection")


func _set_toolbar_button_icon(button: Button, icon_names: Array, fallback_text: String) -> void:
	if not button:
		return
	var icon = _find_editor_icon(icon_names)
	if icon:
		button.icon = icon
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


func _get_scene_history_id() -> int:
	if undo_redo and level_root and is_instance_valid(level_root):
		return undo_redo.get_object_history_id(level_root)
	return EditorUndoRedoManager.GLOBAL_HISTORY


func _get_scene_undo_redo() -> UndoRedo:
	if not undo_redo:
		return null
	return undo_redo.get_history_undo_redo(_get_scene_history_id())


func _get_undo_version() -> int:
	var ur := _get_scene_undo_redo()
	if ur:
		return ur.get_version()
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
	var ur := _get_scene_undo_redo()
	if ur:
		undo_btn.disabled = not ur.has_undo()
		redo_btn.disabled = not ur.has_redo()
	else:
		undo_btn.disabled = true
		redo_btn.disabled = true


func _on_undo_redo_version_changed() -> void:
	_refresh_history_list()


func _on_history_undo() -> void:
	var ur := _get_scene_undo_redo()
	if ur and ur.has_undo():
		ur.undo()


func _on_history_redo() -> void:
	var ur := _get_scene_undo_redo()
	if ur and ur.has_redo():
		ur.redo()


# ===========================================================================
# UI builders — construct Paint and Manage tabs with collapsible sections
# ===========================================================================


func _make_label_row(label_text: String, control: Control) -> HBoxContainer:
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_spin(min_val: float, max_val: float, step_val: float, default_val: float) -> SpinBox:
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.value = default_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _make_check(label_text: String, default_on: bool = false) -> CheckBox:
	var check = CheckBox.new()
	check.text = label_text
	check.button_pressed = default_on
	return check


func _make_button(label_text: String) -> Button:
	var btn = Button.new()
	btn.text = label_text
	return btn


func _build_paint_tab() -> void:
	var root_vbox = $Margin/VBox/MainTabs/Paint/PaintMargin/PaintVBox
	if not root_vbox:
		return
	var builder = PaintTabBuilder.new(self)
	builder.build(root_vbox)


func _build_entity_props_section() -> void:
	pass  # Now built by EntityTabBuilder


func _rebuild_entity_props(entity: Node3D) -> void:
	_clear_entity_props()
	if not entity or not is_instance_valid(entity):
		return
	if not level_root or not level_root.is_entity_node(entity):
		return

	# Look up entity definition from dock entity_defs
	var entity_type_key := ""
	if entity is DraftEntity:
		entity_type_key = entity.entity_type
	elif entity.has_meta("entity_type"):
		entity_type_key = str(entity.get_meta("entity_type"))
	if entity_type_key == "":
		return

	var definition: Dictionary = {}
	for entry in entity_defs:
		if not (entry is Dictionary):
			continue
		var eid = str(entry.get("id", entry.get("class", "")))
		if eid == entity_type_key:
			definition = entry
			break

	var props: Array = definition.get("properties", [])
	if props.is_empty():
		return

	_entity_props_section.visible = true
	_entity_props_entity = entity
	var content = _entity_props_section.get_content()

	var e_data: Dictionary = {}
	if entity is DraftEntity:
		e_data = entity.entity_data
	elif entity.has_meta("entity_data"):
		e_data = entity.get_meta("entity_data")

	for prop in props:
		if not (prop is Dictionary):
			continue
		var prop_name: String = str(prop.get("name", ""))
		if prop_name == "":
			continue
		var prop_type: String = str(prop.get("type", "string"))
		var prop_label: String = str(prop.get("label", prop_name))
		var prop_default: Variant = prop.get("default", null)
		var default_val: Variant = _entity_prop_default(prop_type, prop_default)
		var current_val: Variant = e_data.get(prop_name, default_val)

		var row = HBoxContainer.new()
		content.add_child(row)
		_entity_props_controls.append(row)

		var lbl = Label.new()
		lbl.text = prop_label + ":"
		lbl.custom_minimum_size.x = 70
		row.add_child(lbl)

		match prop_type:
			"string":
				var le = LineEdit.new()
				le.text = str(current_val)
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.text_changed.connect(_on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(le)
			"int":
				var sb = SpinBox.new()
				sb.step = 1
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = int(current_val)
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(_on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(sb)
			"float":
				var sb = SpinBox.new()
				sb.step = 0.01
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.value = float(current_val)
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(_on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(sb)
			"bool":
				var cb = CheckBox.new()
				cb.button_pressed = bool(current_val)
				cb.toggled.connect(_on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(cb)
			"enum":
				var ob = OptionButton.new()
				var enum_vals: Array = prop.get("enum_values", [])
				for ev in enum_vals:
					ob.add_item(str(ev))
				var idx = enum_vals.find(current_val)
				if idx >= 0:
					ob.select(idx)
				ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ob.item_selected.connect(
					_on_entity_prop_enum_changed.bind(entity, prop_name, enum_vals)
				)
				row.add_child(ob)
			"color":
				var cpb = ColorPickerButton.new()
				if current_val is Color:
					cpb.color = current_val
				elif current_val is String:
					cpb.color = Color(current_val)
				else:
					cpb.color = Color.WHITE
				cpb.custom_minimum_size = Vector2(40, 24)
				cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cpb.color_changed.connect(_on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(cpb)
			"vector3":
				var vec: Vector3 = Vector3.ZERO
				if current_val is Vector3:
					vec = current_val
				elif current_val is Array and current_val.size() == 3:
					vec = Vector3(current_val[0], current_val[1], current_val[2])
				for axis_i in range(3):
					var sb = SpinBox.new()
					sb.step = 0.01
					sb.allow_greater = true
					sb.allow_lesser = true
					sb.value = vec[axis_i]
					sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					sb.custom_minimum_size.x = 70
					sb.value_changed.connect(
						_on_entity_prop_vec3_changed.bind(entity, prop_name, axis_i)
					)
					row.add_child(sb)
			_:
				var le = LineEdit.new()
				le.text = str(current_val)
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.text_changed.connect(_on_entity_prop_changed.bind(entity, prop_name))
				row.add_child(le)


func _clear_entity_props() -> void:
	for ctrl in _entity_props_controls:
		if is_instance_valid(ctrl):
			ctrl.queue_free()
	_entity_props_controls.clear()
	_entity_props_entity = null
	if _entity_props_section:
		_entity_props_section.visible = false


func _on_entity_prop_changed(value: Variant, entity: Node3D, prop_name: String) -> void:
	if not is_instance_valid(entity):
		return
	if entity is DraftEntity:
		entity.entity_data[prop_name] = value
		entity.notify_property_list_changed()
	elif entity.has_meta("entity_data"):
		var d: Dictionary = entity.get_meta("entity_data")
		d[prop_name] = value
		entity.set_meta("entity_data", d)


func _on_entity_prop_enum_changed(
	index: int, entity: Node3D, prop_name: String, enum_vals: Array
) -> void:
	if not is_instance_valid(entity):
		return
	var value: Variant = enum_vals[index] if index < enum_vals.size() else ""
	if entity is DraftEntity:
		entity.entity_data[prop_name] = value
		entity.notify_property_list_changed()
	elif entity.has_meta("entity_data"):
		var d: Dictionary = entity.get_meta("entity_data")
		d[prop_name] = value
		entity.set_meta("entity_data", d)


func _on_entity_prop_vec3_changed(
	value: float, entity: Node3D, prop_name: String, axis_index: int
) -> void:
	if not is_instance_valid(entity):
		return
	var vec: Vector3 = Vector3.ZERO
	if entity is DraftEntity:
		var cur = entity.entity_data.get(prop_name, Vector3.ZERO)
		if cur is Vector3:
			vec = cur
		vec[axis_index] = value
		entity.entity_data[prop_name] = vec
		entity.notify_property_list_changed()
	elif entity.has_meta("entity_data"):
		var d: Dictionary = entity.get_meta("entity_data")
		var cur = d.get(prop_name, Vector3.ZERO)
		if cur is Vector3:
			vec = cur
		vec[axis_index] = value
		d[prop_name] = vec
		entity.set_meta("entity_data", d)


func _entity_prop_default(type_name: String, value: Variant) -> Variant:
	match type_name:
		"float":
			return float(value) if value != null else 0.0
		"int":
			return int(value) if value != null else 0
		"bool":
			return bool(value) if value != null else false
		"color":
			if value is Color:
				return value
			if value is String:
				return Color(value)
			return Color.WHITE
		"vector3":
			if value is Vector3:
				return value
			if value is Array and value.size() == 3:
				return Vector3(value[0], value[1], value[2])
			return Vector3.ZERO
		"string":
			return str(value) if value != null else ""
		_:
			return value


# ---------------------------------------------------------------------------
# External Tool Settings — auto-generated UI from HFEditorTool.get_settings_schema()
# ---------------------------------------------------------------------------

var _tool_settings_controls: Array = []
const HFEditorToolType = preload("hf_editor_tool.gd")


## Rebuild the tool settings panel from an external tool's schema.
## Called when an external tool is activated via the registry.
func rebuild_tool_settings(tool: HFEditorToolType, parent: Control) -> void:
	_clear_tool_settings(parent)
	if not tool:
		return
	var schema: Array = tool.get_settings_schema()
	if schema.is_empty():
		return
	for prop in schema:
		if not (prop is Dictionary):
			continue
		var prop_name: String = str(prop.get("name", ""))
		if prop_name == "":
			continue
		var prop_type: String = str(prop.get("type", "string"))
		var prop_label: String = str(prop.get("label", prop_name))
		var current_val: Variant = tool.get_setting(prop_name)
		var row = HBoxContainer.new()
		parent.add_child(row)
		_tool_settings_controls.append(row)
		var lbl = Label.new()
		lbl.text = prop_label + ":"
		lbl.custom_minimum_size.x = 70
		row.add_child(lbl)
		match prop_type:
			"bool":
				var cb = CheckBox.new()
				cb.button_pressed = bool(current_val) if current_val != null else false
				cb.toggled.connect(_on_tool_setting_changed.bind(tool, prop_name))
				row.add_child(cb)
			"int":
				var sb = SpinBox.new()
				sb.step = 1
				sb.min_value = float(prop.get("min", 0))
				sb.max_value = float(prop.get("max", 100))
				sb.value = int(current_val) if current_val != null else 0
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(_on_tool_setting_changed.bind(tool, prop_name))
				row.add_child(sb)
			"float":
				var sb = SpinBox.new()
				sb.step = 0.01
				sb.min_value = float(prop.get("min", 0.0))
				sb.max_value = float(prop.get("max", 100.0))
				sb.value = float(current_val) if current_val != null else 0.0
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value_changed.connect(_on_tool_setting_changed.bind(tool, prop_name))
				row.add_child(sb)
			"string":
				var le = LineEdit.new()
				le.text = str(current_val) if current_val != null else ""
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.text_changed.connect(_on_tool_setting_changed.bind(tool, prop_name))
				row.add_child(le)
			"enum":
				var ob = OptionButton.new()
				var options: Array = prop.get("options", [])
				for opt in options:
					ob.add_item(str(opt))
				var idx = options.find(current_val) if current_val != null else 0
				if idx >= 0:
					ob.select(idx)
				ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ob.item_selected.connect(
					_on_tool_setting_enum_changed.bind(tool, prop_name, options)
				)
				row.add_child(ob)
			"color":
				var cp = ColorPickerButton.new()
				cp.color = current_val if current_val is Color else Color.WHITE
				cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cp.color_changed.connect(_on_tool_setting_changed.bind(tool, prop_name))
				row.add_child(cp)


func _clear_tool_settings(parent: Control) -> void:
	for ctrl in _tool_settings_controls:
		if is_instance_valid(ctrl):
			ctrl.queue_free()
	_tool_settings_controls.clear()


func _on_tool_setting_changed(value: Variant, tool: HFEditorToolType, prop_name: String) -> void:
	if tool:
		tool.set_setting(prop_name, value)


func _on_tool_setting_enum_changed(
	index: int, tool: HFEditorToolType, prop_name: String, options: Array
) -> void:
	if tool and index < options.size():
		tool.set_setting(prop_name, options[index])


func _build_entity_io_section() -> void:
	var entities_vbox = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox
	if not entities_vbox:
		return
	var builder = EntityTabBuilder.new(self)
	builder.build(entities_vbox)


func _build_manage_tab() -> void:
	var root_vbox = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox
	if not root_vbox:
		return
	var builder = ManageTabBuilder.new(self)
	builder.build(root_vbox)


func _build_selection_tools_section() -> void:
	var brush_vbox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox
	if not brush_vbox:
		return
	var builder = SelectionToolsBuilder.new(self)
	builder.build(brush_vbox)


func _ready():
	# --- Build programmatic tabs first ---
	_build_paint_tab()
	_build_manage_tab()
	_build_entity_io_section()
	_build_selection_tools_section()

	# --- Toolbar setup ---
	var tool_group = ButtonGroup.new()
	tool_group.pressed.connect(_on_builtin_tool_pressed)
	tool_draw.toggle_mode = true
	tool_select.toggle_mode = true
	tool_draw.button_group = tool_group
	tool_select.button_group = tool_group
	tool_draw.button_pressed = true
	tool_draw.text = "D"
	tool_draw.tooltip_text = "Draw (D)"
	tool_select.text = "S"
	tool_select.tooltip_text = "Select (S)"
	if paint_mode:
		paint_mode.toggle_mode = true
		paint_mode.button_pressed = false

	# Extrude tool buttons (added programmatically to toolbar)
	var toolbar = tool_draw.get_parent()
	if toolbar:
		var ext_sep = VSeparator.new()
		toolbar.add_child(ext_sep)

		tool_extrude_up = Button.new()
		tool_extrude_up.toggle_mode = true
		tool_extrude_up.button_group = tool_group
		tool_extrude_up.flat = true
		tool_extrude_up.focus_mode = Control.FOCUS_NONE
		tool_extrude_up.text = "\u25b2"
		tool_extrude_up.tooltip_text = "Extrude Up (U)\nClick face + drag to extrude upward"
		toolbar.add_child(tool_extrude_up)

		tool_extrude_down = Button.new()
		tool_extrude_down.toggle_mode = true
		tool_extrude_down.button_group = tool_group
		tool_extrude_down.flat = true
		tool_extrude_down.focus_mode = Control.FOCUS_NONE
		tool_extrude_down.text = "\u25bc"
		tool_extrude_down.tooltip_text = "Extrude Down (J)\nClick face + drag to extrude downward"
		toolbar.add_child(tool_extrude_down)

		var vert_sep = VSeparator.new()
		toolbar.add_child(vert_sep)

		tool_vertex = Button.new()
		tool_vertex.toggle_mode = true
		tool_vertex.flat = true
		tool_vertex.focus_mode = Control.FOCUS_NONE
		tool_vertex.text = "V"
		tool_vertex.tooltip_text = "Vertex Edit (V)\nSelect and drag brush vertices"
		tool_vertex.toggled.connect(_on_vertex_tool_toggled)
		toolbar.add_child(tool_vertex)

	# --- Shortcuts help button ---
	if toolbar:
		var help_sep = VSeparator.new()
		toolbar.add_child(help_sep)
		var help_btn = Button.new()
		help_btn.text = "?"
		help_btn.tooltip_text = "Show keyboard shortcuts"
		help_btn.flat = true
		help_btn.focus_mode = Control.FOCUS_NONE
		help_btn.pressed.connect(_on_shortcuts_help)
		toolbar.add_child(help_btn)

	var mode_group = ButtonGroup.new()
	mode_add.toggle_mode = true
	mode_subtract.toggle_mode = true
	mode_add.button_group = mode_group
	mode_subtract.button_group = mode_group
	mode_add.button_pressed = true

	# --- Populate dropdowns ---
	_populate_shape_palette()
	_populate_paint_tools()
	_populate_brush_shapes()
	_populate_paint_targets()
	_populate_blend_slots()
	_bind_terrain_slot_controls()

	# --- Connect signals (brush tab — non-builder) ---
	if shape_select:
		shape_select.item_selected.connect(_on_shape_selected)

	# --- Snap buttons ---
	snap_button_group = ButtonGroup.new()
	for index in range(snap_buttons.size()):
		var button = snap_buttons[index]
		if not button:
			continue
		var preset = (
			snap_preset_values[index]
			if index < snap_preset_values.size()
			else snap_preset_values[snap_preset_values.size() - 1]
		)
		button.toggle_mode = true
		button.flat = true
		button.button_group = snap_button_group
		button.set_meta("snap_value", preset)
		button.text = str(preset)
		button.toggled.connect(_on_snap_button_toggled.bind(button))

	# --- Snap mode buttons (Grid / Vertex / Center) ---
	_build_snap_mode_buttons()

	# --- Connect builder signals ---
	PaintTabBuilder.new(self).connect_signals()
	ManageTabBuilder.new(self).connect_signals()
	SelectionToolsBuilder.new(self).connect_signals()
	EntityTabBuilder.new(self).connect_signals()

	# --- Connect signals (brush tab — non-builder) ---
	grid_snap.value_changed.connect(_on_grid_snap_value_changed)
	if create_entity_btn:
		create_entity_btn.pressed.connect(_on_create_entity)
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
		material_dialog.file_selected.connect(_on_material_file_selected)
	_setup_storage_dialogs()
	if collision_layer_opt:
		collision_layer_opt.clear()
		collision_layer_opt.add_item("Static World (Layer 1)", 1)
		collision_layer_opt.add_item("Debris/Prop (Layer 2)", 2)
		collision_layer_opt.add_item("Trigger Only (Layer 3)", 4)
		collision_layer_opt.select(0)

	# --- Final setup ---
	status_label.text = "Ready"
	if progress_bar:
		progress_bar.value = 0
		progress_bar.hide()
	if no_root_banner:
		no_root_banner.visible = true
	_sync_snap_buttons(grid_snap.value)
	_ensure_presets_dir()
	_load_presets()
	_load_entity_definitions()
	_apply_pro_styles()
	_apply_all_tooltips()
	_sync_bake_option_visibility()
	_setup_texture_lock_ui()
	_setup_visgroup_ui()
	_setup_cordon_ui()
	_connect_setting_signals()
	_setup_toast_container()
	_setup_clear_selection_button()
	_setup_context_hints()
	set_process(true)


func _process(_delta):
	var scene = get_tree().edited_scene_root
	if not scene:
		scene = get_tree().get_current_scene()
	# Keep current root if it's still valid — avoids losing connection when
	# the user selects a non-LevelRoot node.
	if level_root and is_instance_valid(level_root) and level_root.is_inside_tree():
		pass  # keep it
	elif scene:
		level_root = _find_level_root_in(scene)
	else:
		level_root = null
	if level_root != connected_root:
		_disconnect_root_signals()
		connected_root = level_root
		_connect_root_signals()
		# Pass root to tutorial wizard if active
		if _tutorial_wizard and is_instance_valid(_tutorial_wizard) and level_root:
			_tutorial_wizard.set_root(level_root, self)
	# Show/hide the "no root" banner
	if no_root_banner:
		no_root_banner.visible = level_root == null
	# Paint layers, materials, and surface paint sync are now signal-driven
	# (see _connect_root_signals for paint_layer_changed, material_list_changed,
	# selection_changed connections).
	# Throttled UI updates
	if _hints_dirty:
		_hints_dirty = false
		_update_disabled_hints()
		_update_context_hints()
	_perf_frame_counter += 1
	if _perf_frame_counter >= 30:
		_perf_frame_counter = 0
		_update_perf_panel()
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
	_sync_region_settings_from_root()


func _sync_region_settings_from_root() -> void:
	_region_settings_refreshing = true
	if not level_root:
		_region_settings_refreshing = false
		return
	var settings: Dictionary = level_root.get_region_settings()
	if settings.is_empty():
		_region_settings_refreshing = false
		return
	if region_enable:
		region_enable.button_pressed = bool(settings.get("enabled", false))
	if region_size_spin:
		region_size_spin.value = float(settings.get("region_size_cells", region_size_spin.value))
	if region_radius_spin:
		region_radius_spin.value = float(settings.get("streaming_radius", region_radius_spin.value))
	if region_memory_spin:
		region_memory_spin.value = float(settings.get("memory_budget_mb", region_memory_spin.value))
	if region_grid_toggle:
		region_grid_toggle.button_pressed = bool(settings.get("show_grid", false))
	_region_settings_refreshing = false


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
		_refresh_material_browser()


func _refresh_material_browser() -> void:
	if not material_browser or not level_root:
		return
	material_browser.set_material_manager(level_root.material_manager)
	material_browser.set_selected_index(_selected_material_index)


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


func _on_builtin_tool_pressed(_button: BaseButton) -> void:
	builtin_tool_changed.emit()


func _on_shortcuts_help() -> void:
	var HFShortcutDialog = preload("res://addons/hammerforge/ui/hf_shortcut_dialog.gd")
	var dialog = HFShortcutDialog.new()
	add_child(dialog)
	dialog.populate(_keymap)
	dialog.popup_centered(Vector2i(380, 460))
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())


func get_tool() -> int:
	if tool_draw.button_pressed:
		return 0
	if tool_extrude_up and tool_extrude_up.button_pressed:
		return 2
	if tool_extrude_down and tool_extrude_down.button_pressed:
		return 3
	return 1


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


func get_extrude_direction() -> int:
	if tool_extrude_up and tool_extrude_up.button_pressed:
		return 1  # UP
	if tool_extrude_down and tool_extrude_down.button_pressed:
		return -1  # DOWN
	return 1


func set_extrude_tool(direction: int) -> void:
	if direction > 0 and tool_extrude_up:
		tool_extrude_up.button_pressed = true
	elif direction < 0 and tool_extrude_down:
		tool_extrude_down.button_pressed = true


func set_paint_tool(tool_id: int) -> void:
	if not paint_tool_select:
		return
	for i in range(paint_tool_select.get_item_count()):
		if paint_tool_select.get_item_id(i) == tool_id:
			paint_tool_select.select(i)
			return


## Update the mode indicator banner and status bar.
func set_status_mode(mode_name: String) -> void:
	if status_label:
		status_label.text = mode_name
	_update_mode_indicator(mode_name)


## Update the prominent mode indicator with structured info.
## stage_hint: e.g. "Step 1/2: Draw base", numeric: e.g. "64"
func set_mode_indicator(mode_name: String, stage_hint: String = "", numeric: String = "") -> void:
	if status_label:
		status_label.text = mode_name
	var display = mode_name
	if stage_hint != "":
		display += "  —  " + stage_hint
	if numeric != "":
		display += "  [" + numeric + "]"
	_update_mode_indicator_text(display, mode_name)


func _update_mode_indicator(mode_name: String) -> void:
	_update_mode_indicator_text(mode_name, mode_name)


func _update_mode_indicator_text(display_text: String, mode_key: String) -> void:
	if not _mode_indicator or not _mode_label:
		return
	_mode_label.text = display_text
	var color := Color(0.25, 0.25, 0.25, 1.0)
	if mode_key.begins_with("Draw"):
		color = Color(0.18, 0.35, 0.55, 1.0)
	elif mode_key.begins_with("Select"):
		color = Color(0.2, 0.35, 0.2, 1.0)
	elif mode_key.begins_with("Extrude"):
		if "▲" in mode_key:
			color = Color(0.15, 0.4, 0.25, 1.0)
		else:
			color = Color(0.45, 0.18, 0.18, 1.0)
	elif mode_key.begins_with("Paint"):
		color = Color(0.45, 0.3, 0.12, 1.0)
	# Reuse cached StyleBoxFlat — only update bg_color if changed
	if not _mode_style:
		_mode_style = StyleBoxFlat.new()
		_mode_style.set_corner_radius_all(3)
		_mode_style.content_margin_left = 6
		_mode_style.content_margin_right = 6
		_mode_style.content_margin_top = 2
		_mode_style.content_margin_bottom = 2
		_mode_indicator.add_theme_stylebox_override("panel", _mode_style)
	if _mode_last_color != color:
		_mode_last_color = color
		_mode_style.bg_color = color


func _setup_toast_container() -> void:
	_toast_container = HFToast.new()
	# Insert above footer (BottomSeparator is 2nd-to-last in VBox)
	var vbox = $Margin/VBox
	var footer_idx = vbox.get_child_count() - 1  # Footer is last
	vbox.add_child(_toast_container)
	vbox.move_child(_toast_container, footer_idx)


func _setup_clear_selection_button() -> void:
	var footer = $Margin/VBox/Footer/StatusFooter
	if not footer:
		return
	_clear_sel_btn = Button.new()
	_clear_sel_btn.text = "x"
	_clear_sel_btn.tooltip_text = "Clear selection (Esc)"
	_clear_sel_btn.flat = true
	_clear_sel_btn.focus_mode = Control.FOCUS_NONE
	_clear_sel_btn.custom_minimum_size = Vector2(20, 0)
	_clear_sel_btn.visible = false
	_clear_sel_btn.pressed.connect(_on_clear_selection_pressed)
	# Insert right after the SelectionLabel
	var idx = footer.get_children().find(selection_label)
	if idx >= 0:
		footer.add_child(_clear_sel_btn)
		footer.move_child(_clear_sel_btn, idx + 1)
	else:
		footer.add_child(_clear_sel_btn)


func _on_clear_selection_pressed() -> void:
	_selection_nodes = []
	set_selection_count(0)
	set_selection_nodes([])
	selection_clear_requested.emit()
	if editor_interface:
		var sel = editor_interface.get_selection()
		if sel:
			sel.clear()


## Show a transient toast notification in the dock.
## level: 0=INFO, 1=WARNING, 2=ERROR
func show_toast(message: String, level: int = 0) -> void:
	if _toast_container:
		_toast_container.show_toast(message, level)


## Update the grid display in the status bar.
func set_status_grid(snap_value: float) -> void:
	if perf_label:
		# Perf label doubles as grid indicator when not showing brush counts
		pass  # Grid is already visible in the Brush tab SpinBox


func set_selection_count(count: int) -> void:
	if not selection_label:
		return
	var face_count := _count_selected_faces()
	if count <= 0 and face_count <= 0:
		selection_label.text = ""
	elif face_count > 0 and count > 0:
		selection_label.text = (
			"Sel: %d brush%s, %d face%s"
			% [count, "" if count == 1 else "es", face_count, "" if face_count == 1 else "s"]
		)
	elif face_count > 0:
		selection_label.text = "Sel: %d face%s" % [face_count, "" if face_count == 1 else "s"]
	elif count == 1:
		selection_label.text = "Sel: 1 brush"
	else:
		selection_label.text = "Sel: %d brushes" % count
	if _clear_sel_btn:
		_clear_sel_btn.visible = count > 0 or face_count > 0


func set_selection_nodes(nodes: Array) -> void:
	_selection_nodes = nodes
	# Show/hide selection tools in Brush tab
	if _selection_tools_section:
		_selection_tools_section.visible = _selection_nodes.size() > 0
	# Mark hints dirty so selection-dependent buttons update
	_hints_dirty = true
	_update_context_hints()
	# Refresh Entity I/O list and property form when selection changes
	if not nodes.is_empty() and level_root and level_root.is_entity_node(nodes[0]):
		_refresh_io_list(nodes[0])
		_rebuild_entity_props(nodes[0])
	else:
		if io_list:
			io_list.clear()
		_clear_entity_props()


func _build_snap_mode_buttons() -> void:
	# Find the GridRow parent to add snap mode row after it
	var grid_row = grid_snap.get_parent() if grid_snap else null
	if not grid_row or not grid_row.get_parent():
		return
	var parent = grid_row.get_parent()
	var idx = grid_row.get_index() + 1
	var row = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Snap:"
	lbl.custom_minimum_size.x = 70
	row.add_child(lbl)
	snap_grid_btn = Button.new()
	snap_grid_btn.text = "G"
	snap_grid_btn.tooltip_text = "Grid snap"
	snap_grid_btn.toggle_mode = true
	snap_grid_btn.button_pressed = true
	snap_grid_btn.custom_minimum_size.x = 32
	snap_grid_btn.toggled.connect(_on_snap_mode_toggled.bind(1))
	row.add_child(snap_grid_btn)
	snap_vertex_btn = Button.new()
	snap_vertex_btn.text = "V"
	snap_vertex_btn.tooltip_text = "Vertex snap (brush corners)"
	snap_vertex_btn.toggle_mode = true
	snap_vertex_btn.custom_minimum_size.x = 32
	snap_vertex_btn.toggled.connect(_on_snap_mode_toggled.bind(2))
	row.add_child(snap_vertex_btn)
	snap_center_btn = Button.new()
	snap_center_btn.text = "C"
	snap_center_btn.tooltip_text = "Center snap (brush centers)"
	snap_center_btn.toggle_mode = true
	snap_center_btn.custom_minimum_size.x = 32
	snap_center_btn.toggled.connect(_on_snap_mode_toggled.bind(4))
	row.add_child(snap_center_btn)
	parent.add_child(row)
	parent.move_child(row, idx)
	# Axis Lock row
	var axis_row = HBoxContainer.new()
	var axis_lbl = Label.new()
	axis_lbl.text = "Axis:"
	axis_lbl.custom_minimum_size.x = 70
	axis_row.add_child(axis_lbl)
	_axis_lock_x = Button.new()
	_axis_lock_x.text = "X"
	_axis_lock_x.tooltip_text = "Lock to X axis"
	_axis_lock_x.toggle_mode = true
	_axis_lock_x.custom_minimum_size.x = 32
	_axis_lock_x.add_theme_color_override("font_pressed_color", Color(1.0, 0.3, 0.3))
	_axis_lock_x.toggled.connect(_on_axis_lock_toggled.bind(1))
	axis_row.add_child(_axis_lock_x)
	_axis_lock_y = Button.new()
	_axis_lock_y.text = "Y"
	_axis_lock_y.tooltip_text = "Lock to Y axis"
	_axis_lock_y.toggle_mode = true
	_axis_lock_y.custom_minimum_size.x = 32
	_axis_lock_y.add_theme_color_override("font_pressed_color", Color(0.3, 1.0, 0.3))
	_axis_lock_y.toggled.connect(_on_axis_lock_toggled.bind(2))
	axis_row.add_child(_axis_lock_y)
	_axis_lock_z = Button.new()
	_axis_lock_z.text = "Z"
	_axis_lock_z.tooltip_text = "Lock to Z axis"
	_axis_lock_z.toggle_mode = true
	_axis_lock_z.custom_minimum_size.x = 32
	_axis_lock_z.add_theme_color_override("font_pressed_color", Color(0.3, 0.5, 1.0))
	_axis_lock_z.toggled.connect(_on_axis_lock_toggled.bind(3))
	axis_row.add_child(_axis_lock_z)
	parent.add_child(axis_row)
	parent.move_child(axis_row, idx + 1)


func _on_axis_lock_toggled(pressed: bool, axis: int) -> void:
	if not level_root:
		return
	if pressed:
		# Unpress the other two buttons
		if axis != 1 and _axis_lock_x:
			_axis_lock_x.set_pressed_no_signal(false)
		if axis != 2 and _axis_lock_y:
			_axis_lock_y.set_pressed_no_signal(false)
		if axis != 3 and _axis_lock_z:
			_axis_lock_z.set_pressed_no_signal(false)
		level_root.set_axis_lock(axis, true)
	else:
		level_root.set_axis_lock(0, false)


func update_axis_lock_buttons(axis: int) -> void:
	if _axis_lock_x:
		_axis_lock_x.set_pressed_no_signal(axis == 1)
	if _axis_lock_y:
		_axis_lock_y.set_pressed_no_signal(axis == 2)
	if _axis_lock_z:
		_axis_lock_z.set_pressed_no_signal(axis == 3)


func _on_snap_mode_toggled(pressed: bool, mode: int) -> void:
	if level_root and level_root.get("snap_system"):
		level_root.snap_system.set_mode(mode, pressed)


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
	_save_user_pref("grid_snap", value)


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
	_save_user_pref("show_hud", pressed)
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


func _on_show_io_lines_toggled(pressed: bool) -> void:
	if level_root and level_root.io_visualizer:
		level_root.io_visualizer.set_enabled(pressed)


func _on_show_subtract_preview_toggled(pressed: bool) -> void:
	if level_root:
		level_root.show_subtract_preview = pressed


func _on_prefab_save_requested(prefab_name: String) -> void:
	if not level_root:
		return
	var HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in _selection_nodes:
		if node is CSGShape3D:
			brush_nodes.append(node)
		elif node.has_meta("is_entity"):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	var prefab = HFPrefabType.capture_from_selection(
		level_root.brush_system, level_root.entity_system, brush_nodes, entity_nodes
	)
	prefab.prefab_name = prefab_name
	# Ensure directory exists
	var dir_path := "res://prefabs"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file_name := prefab_name.to_snake_case() + ".hfprefab"
	var path := dir_path.path_join(file_name)
	var err := prefab.save_to_file(path)
	if err == OK and _prefab_library:
		_prefab_library.on_prefab_saved()


func _on_prefab_save_linked_requested(prefab_name: String) -> void:
	if not level_root:
		return
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in _selection_nodes:
		if node is CSGShape3D:
			brush_nodes.append(node)
		elif node.has_meta("is_entity"):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	var path := level_root.prefab_system.quick_save_prefab(
		brush_nodes, entity_nodes, prefab_name, true
	)
	if path != "" and _prefab_library:
		_prefab_library.on_prefab_saved()


func _on_prefab_delete_requested(prefab_path: String) -> void:
	if prefab_path == "" or not FileAccess.file_exists(prefab_path):
		return
	DirAccess.remove_absolute(prefab_path)
	if _prefab_library:
		_prefab_library.on_prefab_saved()


func _on_prefab_variant_add_requested(prefab_path: String, variant_name: String) -> void:
	if not level_root or prefab_path == "" or variant_name == "":
		return
	var HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
	var prefab = HFPrefabType.load_from_file(prefab_path)
	if not prefab:
		return
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in _selection_nodes:
		if node is CSGShape3D:
			brush_nodes.append(node)
		elif node.has_meta("is_entity"):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	prefab.add_variant_from_selection(
		variant_name, level_root.brush_system, level_root.entity_system,
		brush_nodes, entity_nodes
	)
	prefab.save_to_file(prefab_path)
	if _prefab_library:
		_prefab_library.on_prefab_saved()


func _on_vertex_tool_toggled(pressed: bool) -> void:
	vertex_mode_toggled.emit(pressed)


## Called by plugin to sync vertex button state.
func set_vertex_mode(enabled: bool) -> void:
	if tool_vertex:
		tool_vertex.set_pressed_no_signal(enabled)


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
	if not level_root:
		return
	HFUndoHelper.commit(
		undo_redo,
		level_root,
		action_name,
		method_name,
		args,
		false,
		Callable(self, "record_history")
	)


func _commit_full_state_action(action_name: String, method_name: String, args: Array = []) -> void:
	if not level_root:
		return
	HFUndoHelper.commit(
		undo_redo,
		level_root,
		action_name,
		method_name,
		args,
		true,
		Callable(self, "record_history")
	)


func _on_bake():
	_log("Bake requested")
	_warn_missing_dependencies()
	_commit_state_action("Bake", "bake", [true, false, get_collision_layer_mask()])


func _on_bake_dry_run() -> void:
	if not level_root:
		_set_status("No LevelRoot for bake dry run", true)
		return
	var info: Dictionary = level_root.bake_dry_run()
	if info.is_empty():
		_set_status("Bake dry run failed", true)
		return
	var draft = int(info.get("draft", 0))
	var pending = int(info.get("pending", 0))
	var committed = int(info.get("committed", 0))
	var gen_floors = int(info.get("generated_floors", 0))
	var gen_walls = int(info.get("generated_walls", 0))
	var hm = int(info.get("heightmap_floors", 0))
	var chunks = int(info.get("chunk_count", 0))
	var summary = (
		"Dry run: draft %d, pending %d, committed %d, floors %d, walls %d, heightmap %d, chunks %d"
		% [draft, pending, committed, gen_floors, gen_walls, hm, chunks]
	)
	_set_status(summary, false, 5.0)
	_log(summary)


func _on_validate_level() -> void:
	_run_validation(false)


func _on_validate_fix() -> void:
	_run_validation(true)


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
	_warn_missing_dependencies()
	selection_clear_requested.emit()
	if editor_interface:
		var selection = editor_interface.get_selection()
		if selection:
			selection.clear()
	_commit_state_action("Commit Cuts", "commit_cuts")


func _on_restore_cuts():
	_log("Restore committed cuts requested")
	_commit_state_action("Restore Committed Cuts", "restore_committed_cuts")


func _on_hollow() -> void:
	if not level_root or _selection_nodes.is_empty():
		_set_status("Select a brush to hollow", true)
		return
	var brush = _selection_nodes[0]
	if not level_root.is_brush_node(brush):
		_set_status("Select a brush to hollow", true)
		return
	var info = level_root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	var thickness = hollow_thickness.value if hollow_thickness else 4.0
	var check: HFOpResult = level_root.can_hollow_brush(brush_id, thickness)
	if not check.ok:
		show_toast(check.user_text(), 1)
		return
	_commit_state_action("Hollow", "hollow_brush_by_id", [brush_id, thickness])


func _on_move_to_floor() -> void:
	if not level_root or _selection_nodes.is_empty():
		return
	var brush_ids: Array = []
	for node in _selection_nodes:
		if level_root.is_brush_node(node):
			var info = level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	_commit_state_action("Move to Floor", "move_brushes_to_floor", [brush_ids])


func _on_move_to_ceiling() -> void:
	if not level_root or _selection_nodes.is_empty():
		return
	var brush_ids: Array = []
	for node in _selection_nodes:
		if level_root.is_brush_node(node):
			var info = level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	_commit_state_action("Move to Ceiling", "move_brushes_to_ceiling", [brush_ids])


func _on_create_duplicate_array() -> void:
	if not level_root or _selection_nodes.is_empty():
		_set_status("Select brushes first", true)
		return
	var brush_ids = PackedStringArray()
	for node in _selection_nodes:
		if level_root.is_brush_node(node):
			var info = level_root.get_brush_info_from_node(node)
			if info and info.has("brush_id"):
				brush_ids.append(info["brush_id"])
	if brush_ids.is_empty():
		_set_status("No brushes selected", true)
		return
	var cnt = int(dup_count_spin.value) if dup_count_spin else 3
	var off = Vector3(
		dup_offset_x.value if dup_offset_x else 8,
		dup_offset_y.value if dup_offset_y else 0,
		dup_offset_z.value if dup_offset_z else 0,
	)
	_commit_state_action("Create Duplicate Array", "create_duplicate_array", [brush_ids, cnt, off])
	_set_status("Created %d copies" % cnt)


func _on_remove_duplicate_array() -> void:
	if not level_root or _selection_nodes.is_empty():
		_set_status("Select a duplicator source brush", true)
		return
	for node in _selection_nodes:
		if not level_root.is_brush_node(node):
			continue
		var dup_id: String = str(node.get_meta("duplicator_id", ""))
		if dup_id != "":
			_commit_state_action("Remove Duplicate Array", "remove_duplicate_array", [dup_id])
			_set_status("Removed duplicate array")
			return
	_set_status("Selected brush is not a duplicator source", true)


func _on_tie_entity() -> void:
	if not level_root or _selection_nodes.is_empty():
		_set_status("Select brushes to tie", true)
		return
	var class_name_str := "func_detail"
	if (
		brush_entity_class_opt
		and brush_entity_class_opt.item_count > 0
		and brush_entity_class_opt.selected >= 0
	):
		class_name_str = brush_entity_class_opt.get_item_text(brush_entity_class_opt.selected)
	var brush_ids: Array = []
	for node in _selection_nodes:
		if level_root.is_brush_node(node):
			var info = level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	_commit_state_action("Tie to Entity", "tie_brushes_to_entity", [brush_ids, class_name_str])


func _on_untie_entity() -> void:
	if not level_root or _selection_nodes.is_empty():
		return
	var brush_ids: Array = []
	for node in _selection_nodes:
		if level_root.is_brush_node(node):
			var info = level_root.get_brush_info_from_node(node)
			var bid = str(info.get("brush_id", ""))
			if bid != "":
				brush_ids.append(bid)
	if brush_ids.is_empty():
		return
	_commit_state_action("Untie Entity", "untie_brushes_from_entity", [brush_ids])


func _on_justify(mode: String) -> void:
	if not level_root:
		return
	var treat_as_one = justify_treat_as_one.button_pressed if justify_treat_as_one else false
	_commit_state_action("Justify UV (%s)" % mode, "justify_selected_faces", [mode, treat_as_one])


func get_hollow_thickness() -> float:
	return hollow_thickness.value if hollow_thickness else 4.0


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
	if connected_root.has_signal("bake_progress"):
		if not connected_root.is_connected("bake_progress", Callable(self, "_on_bake_progress")):
			connected_root.connect("bake_progress", Callable(self, "_on_bake_progress"))
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
	if connected_root.has_signal("autosave_failed"):
		if not connected_root.is_connected(
			"autosave_failed", Callable(self, "_on_autosave_failed")
		):
			connected_root.connect("autosave_failed", Callable(self, "_on_autosave_failed"))
	if connected_root.has_signal("paint_layer_changed"):
		if not connected_root.is_connected(
			"paint_layer_changed", Callable(self, "_on_root_paint_layer_changed")
		):
			connected_root.connect(
				"paint_layer_changed", Callable(self, "_on_root_paint_layer_changed")
			)
	if connected_root.has_signal("material_list_changed"):
		if not connected_root.is_connected(
			"material_list_changed", Callable(self, "_on_root_material_list_changed")
		):
			connected_root.connect(
				"material_list_changed", Callable(self, "_on_root_material_list_changed")
			)
	if connected_root.has_signal("selection_changed"):
		if not connected_root.is_connected(
			"selection_changed", Callable(self, "_on_root_selection_for_surface")
		):
			connected_root.connect(
				"selection_changed", Callable(self, "_on_root_selection_for_surface")
			)
	if connected_root.has_signal("face_selection_changed"):
		if not connected_root.is_connected(
			"face_selection_changed", Callable(self, "_on_root_face_selection_changed")
		):
			connected_root.connect(
				"face_selection_changed", Callable(self, "_on_root_face_selection_changed")
			)
	if connected_root.has_signal("user_message"):
		if not connected_root.is_connected("user_message", Callable(self, "_on_root_user_message")):
			connected_root.connect("user_message", Callable(self, "_on_root_user_message"))
	_sync_grid_snap_from_root()
	_sync_grid_settings_from_root()
	_refresh_paint_layers()
	_sync_materials_from_root()
	_sync_surface_paint_from_root()
	_apply_ui_state_to_root()
	_hints_dirty = true


func _disconnect_root_signals() -> void:
	if not connected_root:
		return
	root_properties.clear()
	_hints_dirty = true
	if connected_root.has_signal("bake_started"):
		if connected_root.is_connected("bake_started", Callable(self, "_on_bake_started")):
			connected_root.disconnect("bake_started", Callable(self, "_on_bake_started"))
	if connected_root.has_signal("bake_progress"):
		if connected_root.is_connected("bake_progress", Callable(self, "_on_bake_progress")):
			connected_root.disconnect("bake_progress", Callable(self, "_on_bake_progress"))
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
	if connected_root.has_signal("autosave_failed"):
		if connected_root.is_connected("autosave_failed", Callable(self, "_on_autosave_failed")):
			connected_root.disconnect("autosave_failed", Callable(self, "_on_autosave_failed"))
	if connected_root.has_signal("paint_layer_changed"):
		if connected_root.is_connected(
			"paint_layer_changed", Callable(self, "_on_root_paint_layer_changed")
		):
			connected_root.disconnect(
				"paint_layer_changed", Callable(self, "_on_root_paint_layer_changed")
			)
	if connected_root.has_signal("material_list_changed"):
		if connected_root.is_connected(
			"material_list_changed", Callable(self, "_on_root_material_list_changed")
		):
			connected_root.disconnect(
				"material_list_changed", Callable(self, "_on_root_material_list_changed")
			)
	if connected_root.has_signal("selection_changed"):
		if connected_root.is_connected(
			"selection_changed", Callable(self, "_on_root_selection_for_surface")
		):
			connected_root.disconnect(
				"selection_changed", Callable(self, "_on_root_selection_for_surface")
			)
	if connected_root.has_signal("face_selection_changed"):
		if connected_root.is_connected(
			"face_selection_changed", Callable(self, "_on_root_face_selection_changed")
		):
			connected_root.disconnect(
				"face_selection_changed", Callable(self, "_on_root_face_selection_changed")
			)
	if connected_root.has_signal("user_message"):
		if connected_root.is_connected("user_message", Callable(self, "_on_root_user_message")):
			connected_root.disconnect("user_message", Callable(self, "_on_root_user_message"))


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


func _on_root_paint_layer_changed(_index: int) -> void:
	_sync_paint_layers_from_root()


func _on_root_material_list_changed() -> void:
	_sync_materials_from_root()


func _on_root_selection_for_surface(_brush_ids: Array) -> void:
	_sync_surface_paint_from_root()


func _on_root_face_selection_changed() -> void:
	_sync_surface_paint_from_root()
	_hints_dirty = true


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
	if autosave_keep and _root_has_property("hflevel_autosave_keep"):
		autosave_keep.value = float(connected_root.get("hflevel_autosave_keep"))
	if texture_lock_check and _root_has_property("texture_lock"):
		texture_lock_check.button_pressed = bool(connected_root.get("texture_lock"))
	if cordon_enabled_check and _root_has_property("cordon_enabled"):
		cordon_enabled_check.button_pressed = bool(connected_root.get("cordon_enabled"))
	if _root_has_property("cordon_aabb"):
		var aabb: AABB = connected_root.get("cordon_aabb")
		if cordon_min_x:
			cordon_min_x.value = aabb.position.x
		if cordon_min_y:
			cordon_min_y.value = aabb.position.y
		if cordon_min_z:
			cordon_min_z.value = aabb.position.z
		if cordon_max_x:
			cordon_max_x.value = aabb.position.x + aabb.size.x
		if cordon_max_y:
			cordon_max_y.value = aabb.position.y + aabb.size.y
		if cordon_max_z:
			cordon_max_z.value = aabb.position.z + aabb.size.z
	refresh_visgroup_ui()
	syncing_grid = false
	_sync_bake_option_visibility()


func _on_bake_started() -> void:
	_set_status("Baking...", false, 0.0)
	if progress_bar:
		progress_bar.max_value = 100
		progress_bar.value = 0
		progress_bar.show()
	_set_bake_buttons_disabled(true)
	_hints_dirty = true


func _on_bake_progress(value: float, label: String) -> void:
	var clamped = clamp(value, 0.0, 1.0)
	var pct = int(round(clamped * 100.0))
	if progress_bar:
		progress_bar.max_value = 100
		progress_bar.value = pct
		if not progress_bar.visible:
			progress_bar.show()
	var message = "Baking"
	if label != "":
		message = "%s: %s" % [message, label]
	message += " (%d%%)" % pct
	_set_status(message, false, 0.0)


func _on_autosave_failed(error_message: String) -> void:
	push_warning("HammerForge autosave failed: %s" % error_message)
	show_toast("Autosave failed: %s" % error_message, 2)
	if _autosave_warning:
		_autosave_warning.text = "Autosave failed! Save manually."
		_autosave_warning.tooltip_text = error_message
		_autosave_warning.visible = true
		# Auto-hide after 30 seconds (will reappear if it fails again)
		if _autosave_warning.is_inside_tree():
			get_tree().create_timer(30.0).timeout.connect(
				func():
					if is_instance_valid(_autosave_warning):
						_autosave_warning.visible = false
			)


func _on_root_user_message(text: String, level: int) -> void:
	show_toast(text, level)


func _on_bake_finished(success: bool) -> void:
	if success:
		_set_status("Bake complete", false, 3.0)
		show_toast("Bake complete", 0)
	else:
		_set_status("Bake failed - check Output for details", true)
		show_toast("Bake failed — check Output for details", 2)
	if progress_bar:
		progress_bar.hide()
	_set_bake_buttons_disabled(false)
	_hints_dirty = true


func _set_bake_buttons_disabled(disabled: bool) -> void:
	_bake_disabled = disabled
	bake_btn.disabled = disabled
	commit_cuts_btn.disabled = disabled
	apply_cuts_btn.disabled = disabled
	if quick_play_btn:
		quick_play_btn.disabled = disabled


func _on_quick_play() -> void:
	_log("Playtest requested")
	_warn_missing_dependencies()
	if not level_root:
		return

	# --- Ensure a spawn exists (before bake, so it's included in the scene) ---
	var spawn: Node3D = null
	if level_root.spawn_system:
		spawn = level_root.spawn_system.get_active_spawn()
	if not spawn:
		show_toast("No player_start found — auto-creating default spawn", 1)
		if level_root.spawn_system:
			var pre_state: Dictionary = {}
			if undo_redo and level_root.state_system:
				pre_state = level_root.state_system.capture_state(true)
			spawn = level_root.spawn_system.create_default_spawn()
			if undo_redo and spawn and not pre_state.is_empty():
				_record_spawn_create_undo(pre_state)

	# --- Bake FIRST so collision bodies exist for validation ---
	var mask := get_collision_layer_mask()
	await level_root.bake(true, false, mask)

	# --- Validate AFTER bake against real collision geometry ---
	if spawn and level_root.spawn_system:
		var validation: Dictionary = level_root.spawn_system.validate_spawn(spawn, mask)
		var severity: int = validation.get("severity", 0)
		var issues: PackedStringArray = validation.get("issues", PackedStringArray())

		if severity >= 2:  # ERROR
			level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
			var issue_text := "\n".join(issues)
			show_toast("Spawn issues: %s" % issue_text, 2)
			_show_spawn_fix_dialog(spawn, validation, mask)
			return
		if severity >= 1:  # WARNING
			level_root.spawn_system.show_validation_debug(spawn, validation, 6.0)
			show_toast("Spawn warning: %s" % "\n".join(issues), 1)

	_notify_running_instances()
	if editor_interface:
		editor_interface.play_current_scene()


func _show_spawn_fix_dialog(spawn: Node3D, validation: Dictionary, mask: int) -> void:
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	var dialog := ConfirmationDialog.new()
	dialog.title = "Quick Play — Spawn Warning"
	dialog.dialog_text = (
		"Player spawn may be invalid:\n\n"
		+ "\n".join(issues)
		+ "\n\nFix automatically and play, or cancel?"
	)
	dialog.ok_button_text = "Fix & Play"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(
		func():
			if is_instance_valid(spawn) and level_root and level_root.spawn_system:
				var old_pos := spawn.global_position
				level_root.spawn_system.auto_fix_spawn(spawn, validation)
				level_root.spawn_system.cleanup_debug()
				_record_spawn_move_undo(spawn, old_pos, spawn.global_position)
				show_toast("Spawn fixed — launching playtest", 0)
			_notify_running_instances()
			if editor_interface:
				editor_interface.play_current_scene()
			dialog.queue_free()
	)
	dialog.canceled.connect(
		func():
			show_toast("Quick Play cancelled", 0)
			dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


## Record an undo entry for auto-creating a spawn entity.
## Uses state capture/restore so redo correctly re-creates the entity.
## [before_state]: captured BEFORE the spawn was added to the tree.
func _record_spawn_create_undo(before_state: Dictionary) -> void:
	if not undo_redo or not level_root or not level_root.state_system:
		return
	var after_state: Dictionary = level_root.state_system.capture_state(true)
	undo_redo.create_action("Auto-create player_start")
	undo_redo.add_do_method(level_root.state_system, "restore_state", after_state)
	undo_redo.add_undo_method(level_root.state_system, "restore_state", before_state)
	undo_redo.commit_action(false)


## Record an undo entry for auto-fixing spawn position.
func _record_spawn_move_undo(spawn: Node3D, old_pos: Vector3, new_pos: Vector3) -> void:
	if not undo_redo or not level_root or old_pos == new_pos:
		return
	undo_redo.create_action("Fix player_start position")
	undo_redo.add_do_property(spawn, "global_position", new_pos)
	undo_redo.add_undo_property(spawn, "global_position", old_pos)
	undo_redo.commit_action(false)


func _on_spawn_validate() -> void:
	if not level_root or not level_root.spawn_system:
		show_toast("No LevelRoot available", 1)
		return
	var spawn := level_root.spawn_system.get_active_spawn()
	if not spawn:
		show_toast("No player_start entity found", 1)
		return
	# Bake first so validation queries real collision geometry, not stale state
	var mask := get_collision_layer_mask()
	show_toast("Baking before validation…", 0)
	await level_root.bake(true, false, mask)
	# Re-check spawn is still valid after async bake
	if not is_instance_valid(spawn) or not spawn.is_inside_tree():
		show_toast("Spawn was removed during bake", 2)
		return
	var validation: Dictionary = level_root.spawn_system.validate_spawn(spawn, mask)
	level_root.spawn_system.show_validation_debug(spawn, validation, 10.0)
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	if validation.get("valid", false):
		show_toast("Spawn is valid", 0)
	else:
		show_toast("Spawn issues: %s" % "\n".join(issues), 2)


func _on_spawn_auto_create() -> void:
	if not level_root or not level_root.spawn_system:
		show_toast("No LevelRoot available", 1)
		return
	var existing := level_root.spawn_system.get_active_spawn()
	if existing:
		show_toast("player_start already exists — select and move it instead", 1)
		return
	var pre_state: Dictionary = {}
	if undo_redo and level_root.state_system:
		pre_state = level_root.state_system.capture_state(true)
	var spawn := level_root.spawn_system.create_default_spawn()
	if spawn and not pre_state.is_empty():
		_record_spawn_create_undo(pre_state)
	show_toast("Default player_start created", 0)


func _on_show_spawn_debug_toggled(enabled: bool) -> void:
	if not level_root or not level_root.spawn_system:
		return
	if enabled:
		var spawn := level_root.spawn_system.get_active_spawn()
		if not spawn:
			show_toast("No player_start to preview", 1)
			if _show_spawn_debug:
				_show_spawn_debug.set_pressed_no_signal(false)
			return
		# Bake first so the debug overlay reflects real collision state
		var mask := get_collision_layer_mask()
		await level_root.bake(true, false, mask)
		if not is_instance_valid(spawn) or not spawn.is_inside_tree():
			show_toast("Spawn was removed during bake", 2)
			if _show_spawn_debug:
				_show_spawn_debug.set_pressed_no_signal(false)
			return
		var validation: Dictionary = level_root.spawn_system.validate_spawn(spawn, mask)
		level_root.spawn_system.show_validation_debug(spawn, validation, 0.0)
	else:
		level_root.spawn_system.cleanup_debug()


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


func _warn_missing_dependencies() -> void:
	if not level_root:
		return
	var warnings: Array = level_root.check_missing_dependencies()
	if warnings.is_empty():
		return
	_set_status_warning("Missing dependencies: %d (see Output)" % warnings.size(), 5.0)
	for warning in warnings:
		_log("Dependency: %s" % str(warning), true)


func _run_validation(auto_fix: bool) -> void:
	if not level_root:
		_set_status("No LevelRoot for validation", true)
		return
	var result: Dictionary = {}
	var issues: Array = []
	var fixed := 0
	if auto_fix:
		result = level_root.validate_level(false)
		issues = result.get("issues", [])
		var before_count = issues.size()
		HFUndoHelper.commit(
			undo_redo,
			level_root,
			"Validate + Fix",
			"validate_level",
			[true],
			false,
			Callable(self, "record_history")
		)
		var after = level_root.validate_level(false)
		var after_count = int(after.get("issues", []).size())
		fixed = max(0, before_count - after_count)
	else:
		result = level_root.validate_level(false)
		issues = result.get("issues", [])
	if issues.is_empty():
		_set_status("Validate: no issues found", false, 3.0)
		return
	var message = "Validate: %d issue(s)" % issues.size()
	if auto_fix:
		message += ", fixed %d" % fixed
	_set_status_warning(message, 6.0)
	for issue in issues:
		_log("[Validate] %s" % str(issue), true)


func _update_perf_panel() -> void:
	if not perf_brushes_value or not perf_paint_mem_value or not perf_bake_chunks_value:
		return
	if not level_root:
		perf_brushes_value.text = "0"
		perf_paint_mem_value.text = "0 KB"
		perf_bake_chunks_value.text = "0"
		if perf_bake_time_value:
			perf_bake_time_value.text = "-"
		return
	perf_brushes_value.text = str(level_root.get_live_brush_count())
	var bytes = level_root.get_paint_memory_bytes()
	perf_paint_mem_value.text = _format_bytes(bytes)
	perf_bake_chunks_value.text = str(level_root.get_bake_chunk_count())
	if perf_bake_time_value:
		var ms = int(level_root.get_last_bake_duration_ms())
		perf_bake_time_value.text = ("%d ms" % ms) if ms > 0 else "-"


func _format_bytes(count: int) -> String:
	var value = float(count)
	if value >= 1024.0 * 1024.0:
		return "%.2f MB" % (value / (1024.0 * 1024.0))
	if value >= 1024.0:
		return "%.1f KB" % (value / 1024.0)
	return "%d B" % int(value)


func _update_disabled_hints() -> void:
	var has_root = level_root != null
	var need_root_hint = "Requires LevelRoot (click viewport to create)"
	_set_control_disabled_hint(bake_btn, not has_root or _bake_disabled, need_root_hint)
	_set_control_disabled_hint(bake_dry_run_btn, not has_root or _bake_disabled, need_root_hint)
	_set_control_disabled_hint(validate_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(validate_fix_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(clear_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(save_hflevel_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(load_hflevel_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(import_map_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(export_map_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(autosave_enabled, not has_root, need_root_hint)
	_set_control_disabled_hint(autosave_minutes, not has_root, need_root_hint)
	_set_control_disabled_hint(autosave_keep, not has_root, need_root_hint)
	_set_control_disabled_hint(autosave_path_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(floor_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(apply_cuts_btn, not has_root or _bake_disabled, need_root_hint)
	_set_control_disabled_hint(clear_cuts_btn, not has_root, need_root_hint)
	_set_control_disabled_hint(commit_cuts_btn, not has_root or _bake_disabled, need_root_hint)
	_set_control_disabled_hint(restore_cuts_btn, not has_root, need_root_hint)
	var has_face = _uv_active_face != null or _surface_active_face != null
	var face_hint = "Requires a selected face"
	_set_control_disabled_hint(material_assign, not has_root or not has_face, face_hint)
	_set_control_disabled_hint(face_clear, not has_root or not has_face, face_hint)
	_set_control_disabled_hint(uv_reset, not has_root or not has_face, face_hint)
	var baked_ready = has_root and level_root.baked_container != null
	_set_control_disabled_hint(export_glb_btn, not baked_ready, "Requires a successful bake")
	# Selection-dependent tools: gray out when nothing is selected
	var has_selection = _selection_nodes.size() > 0
	var need_sel_hint = "Requires a selected brush"
	_set_control_disabled_hint(hollow_btn, not has_root or not has_selection, need_sel_hint)
	_set_control_disabled_hint(clip_btn, not has_root or not has_selection, need_sel_hint)
	_set_control_disabled_hint(move_floor_btn, not has_root or not has_selection, need_sel_hint)
	_set_control_disabled_hint(move_ceiling_btn, not has_root or not has_selection, need_sel_hint)
	# Inline hint labels
	if _sel_tools_hint_label:
		_sel_tools_hint_label.visible = not has_selection
	if _uv_hint_label:
		_uv_hint_label.visible = not has_face


func _set_control_disabled_hint(control: Control, disabled: bool, hint: String) -> void:
	if not control:
		return
	_set_control_disabled(control, disabled)
	var default_tip = control.get_meta("default_tooltip", "")
	if disabled:
		control.tooltip_text = hint
	elif default_tip != "":
		control.tooltip_text = str(default_tip)


func _set_control_disabled(control: Control, disabled: bool) -> void:
	if control is SpinBox:
		control.editable = not disabled
		control.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
		control.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
		)
		return
	if control is BaseButton:
		control.disabled = disabled
		return
	if _control_has_property(control, "disabled"):
		control.set("disabled", disabled)
	elif _control_has_property(control, "editable"):
		control.set("editable", not disabled)


func _control_has_property(control: Object, property_name: String) -> bool:
	if not control or property_name == "":
		return false
	var key = "%d_%s" % [control.get_instance_id(), property_name]
	if _prop_cache.has(key):
		return _prop_cache[key]
	for prop in control.get_property_list():
		if prop.get("name", "") == property_name:
			_prop_cache[key] = true
			return true
	_prop_cache[key] = false
	return false


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
	paint_tool_select.add_item("Blend", 5)
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


func _populate_blend_slots() -> void:
	if not blend_slot_select:
		return
	blend_slot_select.clear()
	blend_slot_select.add_item("Slot B", 1)
	blend_slot_select.add_item("Slot C", 2)
	blend_slot_select.add_item("Slot D", 3)
	blend_slot_select.select(0)


func _bind_terrain_slot_controls() -> void:
	terrain_slot_buttons = [
		terrain_slot_a_button, terrain_slot_b_button, terrain_slot_c_button, terrain_slot_d_button
	]
	terrain_slot_scales = [
		terrain_slot_a_scale, terrain_slot_b_scale, terrain_slot_c_scale, terrain_slot_d_scale
	]


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
		_refresh_terrain_slots()
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
	_refresh_terrain_slots()


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


func _on_paint_layer_rename() -> void:
	if not level_root or not paint_layer_select:
		return
	var idx = paint_layer_select.selected
	if idx < 0:
		return
	var current_name = paint_layer_select.get_item_text(idx)
	# Create inline rename dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Rename Layer"
	var line_edit = LineEdit.new()
	line_edit.text = current_name
	line_edit.select_all()
	dialog.add_child(line_edit)
	dialog.confirmed.connect(
		func():
			var new_name = line_edit.text.strip_edges()
			if new_name != "" and new_name != current_name:
				level_root.rename_paint_layer(idx, new_name)
				_refresh_paint_layers()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free(), CONNECT_DEFERRED)
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 80))
	line_edit.grab_focus()


func _on_paint_layer_remove() -> void:
	if not level_root:
		return
	level_root.remove_active_paint_layer()
	_refresh_paint_layers()


func _on_heightmap_import() -> void:
	if heightmap_import_dialog:
		heightmap_import_dialog.popup_centered(Vector2i(600, 400))


func _on_heightmap_import_selected(path: String) -> void:
	if not level_root:
		return
	level_root.import_heightmap(path)


func _on_heightmap_generate() -> void:
	if not level_root:
		return
	level_root.generate_heightmap_noise()


func _on_sculpt_tool_toggled(pressed: bool, tool_id: int) -> void:
	if not level_root or not level_root.paint_tool:
		return
	# Unpress other sculpt buttons (radio behavior)
	var btns = [_sculpt_raise_btn, _sculpt_lower_btn, _sculpt_smooth_btn, _sculpt_flatten_btn]
	var ids = [
		HFStroke.Tool.SCULPT_RAISE,
		HFStroke.Tool.SCULPT_LOWER,
		HFStroke.Tool.SCULPT_SMOOTH,
		HFStroke.Tool.SCULPT_FLATTEN
	]
	if pressed:
		for i in range(btns.size()):
			if ids[i] != tool_id and btns[i]:
				btns[i].set_pressed_no_signal(false)
		level_root.paint_tool.tool = tool_id
	else:
		# If unpressing active sculpt, revert to PAINT
		level_root.paint_tool.tool = HFStroke.Tool.PAINT


func _on_sculpt_strength_changed(value: float) -> void:
	if level_root and level_root.paint_tool:
		level_root.paint_tool.sculpt_strength = value


func _on_sculpt_radius_changed(value: float) -> void:
	if level_root and level_root.paint_tool:
		level_root.paint_tool.sculpt_radius = value


func _on_sculpt_falloff_changed(value: float) -> void:
	if level_root and level_root.paint_tool:
		level_root.paint_tool.sculpt_falloff = value


func _on_height_scale_changed(value: float) -> void:
	if not level_root:
		return
	level_root.set_heightmap_scale(value)


func _on_layer_y_changed(value: float) -> void:
	if not level_root:
		return
	level_root.set_layer_y(value)


func _on_blend_strength_changed(value: float) -> void:
	if not level_root or not level_root.paint_tool:
		return
	level_root.paint_tool.blend_strength = value


func _on_region_enable_toggled(enabled: bool) -> void:
	if _region_settings_refreshing:
		return
	if not level_root:
		return
	level_root.set_region_streaming_enabled(enabled)


func _on_region_size_changed(value: float) -> void:
	if _region_settings_refreshing:
		return
	if not level_root:
		return
	level_root.set_region_size_cells(int(value))


func _on_region_radius_changed(value: float) -> void:
	if _region_settings_refreshing:
		return
	if not level_root:
		return
	level_root.set_region_streaming_radius(int(value))


func _on_region_memory_changed(value: float) -> void:
	if _region_settings_refreshing:
		return
	if not level_root:
		return
	level_root.set_region_memory_budget_mb(int(value))


func _on_region_grid_toggled(enabled: bool) -> void:
	if _region_settings_refreshing:
		return
	if not level_root:
		return
	level_root.set_region_show_grid(enabled)


func _on_blend_slot_selected(index: int) -> void:
	if not level_root or not level_root.paint_tool or not blend_slot_select:
		return
	var slot_id = blend_slot_select.get_item_id(index)
	level_root.paint_tool.blend_slot = int(slot_id)


func _on_terrain_slot_pressed(slot: int) -> void:
	if not terrain_slot_texture_dialog:
		return
	_terrain_slot_pick_index = slot
	terrain_slot_texture_dialog.popup_centered(Vector2i(600, 400))


func _on_terrain_slot_texture_selected(path: String) -> void:
	if _terrain_slot_pick_index < 0:
		return
	if not level_root or not level_root.paint_layers:
		return
	var layer = level_root.paint_layers.get_active_layer()
	if not layer:
		return
	layer._ensure_terrain_slots()
	layer.terrain_slot_paths[_terrain_slot_pick_index] = path
	_refresh_terrain_slots()
	level_root._regenerate_paint_layers()


func _on_terrain_slot_scale_changed(value: float, slot: int) -> void:
	if _terrain_slot_refreshing:
		return
	if not level_root or not level_root.paint_layers:
		return
	var layer = level_root.paint_layers.get_active_layer()
	if not layer:
		return
	layer._ensure_terrain_slots()
	var current = float(layer.terrain_slot_uv_scales[slot])
	if is_equal_approx(current, value):
		return
	layer.terrain_slot_uv_scales[slot] = float(value)
	level_root._regenerate_paint_layers()


func _refresh_terrain_slots() -> void:
	_terrain_slot_refreshing = true
	if not level_root or not level_root.paint_layers:
		_set_terrain_slot_controls_enabled(false)
		_terrain_slot_refreshing = false
		return
	var layer = level_root.paint_layers.get_active_layer()
	if not layer:
		_set_terrain_slot_controls_enabled(false)
		_terrain_slot_refreshing = false
		return
	layer._ensure_terrain_slots()
	_set_terrain_slot_controls_enabled(true)
	for i in range(terrain_slot_buttons.size()):
		var button = terrain_slot_buttons[i]
		var scale = terrain_slot_scales[i]
		if button:
			var path = layer.terrain_slot_paths[i]
			button.text = _terrain_slot_label(path)
		if scale:
			scale.value = float(layer.terrain_slot_uv_scales[i])
	if blend_slot_select and level_root.paint_tool:
		var slot = clamp(level_root.paint_tool.blend_slot, 1, 3)
		_select_option_by_id(blend_slot_select, slot)
	_terrain_slot_refreshing = false


func _terrain_slot_label(path: String) -> String:
	if path == "":
		return "Texture..."
	return path.get_file()


func _set_terrain_slot_controls_enabled(enabled: bool) -> void:
	for button in terrain_slot_buttons:
		if button:
			button.disabled = not enabled
	for spin in terrain_slot_scales:
		if spin:
			spin.editable = enabled


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
		_commit_state_action("Add Material", "add_material_to_palette", [resource])
		_sync_materials_from_root()
	else:
		_log("Selected resource is not a material: %s" % path, true)


func _on_material_remove() -> void:
	if _selected_material_index < 0:
		return
	if not level_root:
		return
	_commit_state_action(
		"Remove Material", "remove_material_from_palette", [_selected_material_index]
	)
	_selected_material_index = -1
	_sync_materials_from_root()


func _on_material_load_prototypes() -> void:
	if not level_root:
		return
	_commit_state_action("Load Prototypes", "add_prototype_materials")
	_sync_materials_from_root()
	show_toast("Prototype materials loaded", 0)


func _on_material_assign() -> void:
	if _selected_material_index < 0:
		return
	if not level_root:
		return
	var decision := resolve_material_assign_action(_selected_material_index)
	if decision.action == "":
		show_toast(decision.toast, 1)
		return
	_commit_state_action(decision.action, decision.method, decision.args)
	show_toast(decision.toast, 0)


## Pure decision helper for material assignment.  Returns a Dictionary with
## keys: action (String – empty on error), method (String), args (Array),
## toast (String).  Separated from side-effects so tests can exercise the
## face-vs-brush fallback without undo/redo infrastructure.
func resolve_material_assign_action(mat_index: int) -> Dictionary:
	var face_count := _count_selected_faces()
	if face_count > 0:
		var mat_name := _material_display_name(mat_index)
		return {
			"action": "Assign Face Material",
			"method": "assign_material_to_selected_faces",
			"args": [mat_index],
			"toast":
			"Applied %s to %d face%s" % [mat_name, face_count, "" if face_count == 1 else "s"],
		}
	var brush_ids := _get_selected_brush_ids()
	if brush_ids.is_empty():
		return {
			"action": "",
			"method": "",
			"args": [],
			"toast": "No brushes selected — select a brush first"
		}
	var mat_name := _material_display_name(mat_index)
	return {
		"action": "Assign Brush Material",
		"method": "assign_material_to_whole_brushes",
		"args": [mat_index, brush_ids],
		"toast":
		(
			"Applied %s to %d brush%s"
			% [mat_name, brush_ids.size(), "" if brush_ids.size() == 1 else "es"]
		),
	}


func _count_selected_faces() -> int:
	if not level_root:
		return 0
	var total := 0
	for key in level_root.face_selection.keys():
		var brush = level_root._find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = level_root.face_selection.get(key, [])
		for idx in indices:
			if int(idx) >= 0 and int(idx) < brush.faces.size():
				total += 1
	return total


func _material_display_name(index: int) -> String:
	if not level_root or not level_root.material_manager:
		return "material"
	var mat = level_root.material_manager.get_material(index)
	if mat == null:
		return "material"
	var name: String = (
		mat.resource_name if mat.resource_name != "" else mat.resource_path.get_file()
	)
	return name if name != "" else "material"


func _on_face_clear() -> void:
	if level_root:
		_commit_state_action("Clear Face Selection", "clear_face_selection")


# ---------------------------------------------------------------------------
# Material Browser handlers
# ---------------------------------------------------------------------------


func _on_browser_material_selected(index: int) -> void:
	_selected_material_index = index
	if material_browser:
		material_browser.set_selected_index(index)


func _on_browser_material_double_clicked(index: int) -> void:
	_selected_material_index = index
	if material_browser:
		material_browser.set_selected_index(index)
	# Double-click triggers immediate face assignment.
	if level_root and index >= 0:
		var decision := resolve_material_assign_action(index)
		if decision.action == "":
			show_toast(decision.toast, 1)
			return
		_commit_state_action(decision.action, decision.method, decision.args)
		show_toast(decision.toast, 0)


func _on_browser_context_menu(index: int, global_pos: Vector2) -> void:
	_material_context_index = index
	if not _material_context_popup:
		_material_context_popup = (
			material_browser.create_context_popup() if material_browser else PopupMenu.new()
		)
		add_child(_material_context_popup)
		_material_context_popup.id_pressed.connect(_on_material_context_action)
	_material_context_popup.position = Vector2i(int(global_pos.x), int(global_pos.y))
	_material_context_popup.popup()


func _on_material_context_action(id: int) -> void:
	if not level_root:
		return
	var idx = _material_context_index
	if idx < 0:
		return
	var mat_name := _material_display_name(idx)
	match id:
		0:  # Apply to Selected Faces
			_selected_material_index = idx
			var face_count := _count_selected_faces()
			if face_count == 0:
				show_toast("No faces selected — select faces first", 1)
				return
			_commit_state_action("Assign Face Material", "assign_material_to_selected_faces", [idx])
			show_toast(
				"Applied %s to %d face%s" % [mat_name, face_count, "" if face_count == 1 else "s"],
				0
			)
		1:  # Apply to Whole Brush — assign material to ALL faces on selected brushes
			_selected_material_index = idx
			var brush_ids := _get_selected_brush_ids()
			if brush_ids.is_empty():
				show_toast("No brushes selected", 1)
				return
			_commit_state_action(
				"Assign Brush Material", "assign_material_to_whole_brushes", [idx, brush_ids]
			)
			show_toast(
				(
					"Applied %s to %d brush%s"
					% [mat_name, brush_ids.size(), "" if brush_ids.size() == 1 else "es"]
				),
				0
			)
		2:  # Toggle Favorite
			if material_browser:
				var mat = level_root.material_manager.get_material(idx)
				if mat:
					if material_browser.is_favorite(mat.resource_path):
						material_browser.remove_favorite(mat.resource_path)
					else:
						material_browser.add_favorite(mat.resource_path)
					material_browser.rebuild()
		3:  # Copy Name
			var mat = level_root.material_manager.get_material(idx)
			if mat:
				var label = mat.resource_name
				if label == "":
					label = mat.resource_path.get_file().get_basename()
				DisplayServer.clipboard_set(label)
				show_toast("Copied: " + label, 0)


func _get_selected_brush_ids() -> Array:
	var ids: Array = []
	for node in _selection_nodes:
		if node is DraftBrush and is_instance_valid(node):
			var bid: String = (node as DraftBrush).brush_id
			if bid != "":
				ids.append(bid)
			else:
				ids.append(str(node.get_instance_id()))
	return ids


func _on_browser_material_hovered(index: int) -> void:
	if not level_root:
		return
	var mat_idx: int = index
	if mat_idx < 0:
		return
	_apply_hover_preview(mat_idx)


func _on_browser_material_hover_ended() -> void:
	_revert_hover_preview()


func _apply_hover_preview(mat_idx: int) -> void:
	if not level_root or not level_root.brush_system:
		return
	var face_sel: Dictionary = level_root.face_selection
	if face_sel.is_empty():
		return
	_revert_hover_preview()
	var mat_mgr: MaterialManager = level_root.get_material_manager()
	var preview_mat: Material = mat_mgr.get_material(mat_idx) if mat_mgr else null
	if preview_mat == null:
		return
	for key in face_sel.keys():
		var brush: DraftBrush = level_root.brush_system.find_brush_by_id(str(key))
		if not brush or not is_instance_valid(brush):
			continue
		var indices: Array = face_sel.get(key, [])
		if indices.is_empty():
			continue
		# Build an overlay mesh from just the selected faces.
		var overlay_mesh := _build_face_overlay_mesh(brush, indices, preview_mat)
		if overlay_mesh == null:
			continue
		var overlay := MeshInstance3D.new()
		overlay.name = "_HoverPreview"
		overlay.mesh = overlay_mesh
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		brush.add_child(overlay)
		overlay.owner = null
		_hover_preview_faces.append({"brush": brush, "overlay": overlay})


func _build_face_overlay_mesh(brush: DraftBrush, face_indices: Array, mat: Material) -> ArrayMesh:
	const NORMAL_OFFSET := 0.001
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var vert_count := 0
	for face_idx in face_indices:
		var fi: int = int(face_idx)
		if fi < 0 or fi >= brush.faces.size():
			continue
		var face: FaceData = brush.faces[fi]
		if face == null:
			continue
		face.ensure_geometry()
		var tri: Dictionary = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
		var offset: Vector3 = face.normal.normalized() * NORMAL_OFFSET
		for i in range(verts.size()):
			st.set_normal(face.normal)
			if uvs.size() > i:
				st.set_uv(uvs[i])
			st.add_vertex(verts[i] + offset)
			vert_count += 1
	if vert_count == 0:
		return null
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


func _revert_hover_preview() -> void:
	for entry in _hover_preview_faces:
		var brush: DraftBrush = entry.get("brush")
		var overlay: MeshInstance3D = entry.get("overlay")
		if is_instance_valid(overlay):
			if is_instance_valid(brush):
				brush.remove_child(overlay)
			overlay.queue_free()
	_hover_preview_faces.clear()


func _on_uv_reset() -> void:
	if _uv_active_face == null or _uv_active_brush == null:
		return
	if not level_root:
		return
	if _uv_active_brush.brush_id == "" and true:
		level_root.get_brush_info_from_node(_uv_active_brush)
	var brush_id = _uv_active_brush.brush_id
	var face_idx = _uv_active_brush.faces.find(_uv_active_face)
	if brush_id == "" or face_idx < 0:
		return
	_commit_state_action("Reset UV", "reset_uv_on_face", [brush_id, face_idx])


func _on_uv_changed(_face: FaceData) -> void:
	if level_root and _uv_active_brush:
		level_root.rebuild_brush_preview(_uv_active_brush)


func _on_surface_paint_layer_selected(_index: int) -> void:
	pass


func _on_surface_paint_layer_add() -> void:
	if _surface_active_face == null or _surface_active_brush == null:
		return
	if not level_root:
		return
	if _surface_active_brush.brush_id == "" and true:
		level_root.get_brush_info_from_node(_surface_active_brush)
	var brush_id = _surface_active_brush.brush_id
	var face_idx = _surface_active_brush.faces.find(_surface_active_face)
	if brush_id == "" or face_idx < 0:
		return
	_commit_state_action("Add Surface Paint Layer", "add_surface_paint_layer", [brush_id, face_idx])
	_refresh_surface_paint_layers()


func _on_surface_paint_layer_remove() -> void:
	if _surface_active_face == null or _surface_active_brush == null:
		return
	var idx = surface_paint_layer_select.selected if surface_paint_layer_select else 0
	if idx < 0 or idx >= _surface_active_face.paint_layers.size():
		return
	if not level_root:
		return
	if _surface_active_brush.brush_id == "" and true:
		level_root.get_brush_info_from_node(_surface_active_brush)
	var brush_id = _surface_active_brush.brush_id
	var face_idx = _surface_active_brush.faces.find(_surface_active_face)
	if brush_id == "" or face_idx < 0:
		return
	_commit_state_action(
		"Remove Surface Paint Layer", "remove_surface_paint_layer", [brush_id, face_idx, idx]
	)
	_refresh_surface_paint_layers()


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
	if _surface_active_face == null or _surface_active_brush == null:
		return
	var resource = ResourceLoader.load(path)
	if not resource or not (resource is Texture2D):
		_log("Selected resource is not a texture: %s" % path, true)
		return
	var idx = _pending_surface_texture_layer
	if idx < 0 or idx >= _surface_active_face.paint_layers.size():
		return
	if not level_root:
		return
	if _surface_active_brush.brush_id == "" and true:
		level_root.get_brush_info_from_node(_surface_active_brush)
	var brush_id = _surface_active_brush.brush_id
	var face_idx = _surface_active_brush.faces.find(_surface_active_face)
	if brush_id == "" or face_idx < 0:
		return
	_commit_state_action(
		"Set Surface Paint Texture",
		"set_surface_paint_layer_texture",
		[brush_id, Vector2i(face_idx, idx), resource]
	)


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
	if settings_export_dialog:
		settings_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		settings_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		settings_export_dialog.filters = PackedStringArray(
			["*.hfsettings ; HammerForge Settings", "*.json ; JSON"]
		)
		if not settings_export_dialog.file_selected.is_connected(
			Callable(self, "_on_settings_export_selected")
		):
			settings_export_dialog.file_selected.connect(_on_settings_export_selected)
	if settings_import_dialog:
		settings_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		settings_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		settings_import_dialog.filters = PackedStringArray(
			["*.hfsettings ; HammerForge Settings", "*.json ; JSON"]
		)
		if not settings_import_dialog.file_selected.is_connected(
			Callable(self, "_on_settings_import_selected")
		):
			settings_import_dialog.file_selected.connect(_on_settings_import_selected)


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
	if err != OK:
		show_toast("Failed to save .hflevel: %s" % path.get_file(), 2)
	else:
		show_toast("Saved: %s" % path.get_file(), 0)
	if err == OK and _user_prefs:
		_user_prefs.add_recent_file(path)
		_user_prefs.save()


func _on_hflevel_load_selected(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_set_status("Invalid .hflevel path", true)
		return
	if not level_root:
		_set_status("No LevelRoot for .hflevel load", true)
		return
	_commit_full_state_action("Load .hflevel", "load_hflevel", [path])
	_set_status("Loaded .hflevel", false, 3.0)
	if _user_prefs:
		_user_prefs.add_recent_file(path)
		_user_prefs.save()


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
	var format = "valve220" if map_format_select and map_format_select.selected == 1 else "quake"
	var err = int(level_root.export_map(path, format))
	var fmt_name = "Valve 220" if format == "valve220" else "Classic Quake"
	var msg = "Exported .map (%s)" % fmt_name if err == OK else "Failed to export .map"
	_set_status(msg, err != OK, 3.0)
	if err != OK:
		show_toast("Failed to export .map", 2)
	else:
		show_toast("Exported .map (%s)" % fmt_name, 0)


func _on_glb_export_selected(path: String) -> void:
	if not level_root:
		_set_status("No LevelRoot for .glb export", true)
		return
	_warn_missing_dependencies()
	var err = int(level_root.export_baked_gltf(path))
	_set_status("Exported .glb" if err == OK else "Failed to export .glb", err != OK, 3.0)
	if err != OK:
		show_toast("Failed to export .glb", 2)
	else:
		show_toast("Exported .glb", 0)


func _on_autosave_path_selected(path: String) -> void:
	if not level_root or not _root_has_property("hflevel_autosave_path"):
		_set_status("No LevelRoot for autosave path", true)
		return
	level_root.set("hflevel_autosave_path", path)
	_set_status("Autosave path set", false, 3.0)


func _on_export_settings() -> void:
	if settings_export_dialog:
		settings_export_dialog.popup_centered_ratio(0.6)


func _on_import_settings() -> void:
	if settings_import_dialog:
		settings_import_dialog.popup_centered_ratio(0.6)


func _on_settings_export_selected(path: String) -> void:
	if path == "":
		_set_status("Invalid settings path", true)
		return
	var data = _collect_editor_settings()
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_set_status("Failed to export settings", true)
		return
	file.store_string(json)
	_set_status("Exported settings", false, 3.0)


func _on_settings_import_selected(path: String) -> void:
	if path == "":
		_set_status("Invalid settings path", true)
		return
	if not FileAccess.file_exists(path):
		_set_status("Settings file not found", true)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_set_status("Failed to open settings file", true)
		return
	var text = file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_set_status("Invalid settings file", true)
		return
	_apply_editor_settings(parsed)
	_set_status("Imported settings", false, 3.0)


func _collect_editor_settings() -> Dictionary:
	var snap_values: Array = []
	for button in snap_buttons:
		if button and button.has_meta("snap_value"):
			snap_values.append(int(button.get_meta("snap_value")))
	var brush_size = {"x": size_x.value, "y": size_y.value, "z": size_z.value}
	var bake_settings: Dictionary = {
		"merge_meshes": bake_merge_meshes.button_pressed if bake_merge_meshes else false,
		"generate_lods": bake_generate_lods.button_pressed if bake_generate_lods else false,
		"lightmap_uv2": bake_lightmap_uv2.button_pressed if bake_lightmap_uv2 else false,
		"lightmap_texel_size": float(bake_lightmap_texel.value) if bake_lightmap_texel else 0.1,
		"use_face_materials":
		bake_use_face_materials.button_pressed if bake_use_face_materials else false,
		"navmesh": bake_navmesh.button_pressed if bake_navmesh else false,
		"navmesh_cell_size": float(bake_navmesh_cell_size.value) if bake_navmesh_cell_size else 0.3,
		"navmesh_cell_height":
		float(bake_navmesh_cell_height.value) if bake_navmesh_cell_height else 0.25,
		"navmesh_agent_height":
		float(bake_navmesh_agent_height.value) if bake_navmesh_agent_height else 2.0,
		"navmesh_agent_radius":
		float(bake_navmesh_agent_radius.value) if bake_navmesh_agent_radius else 0.4,
		"collision_mask": get_collision_layer_mask()
	}
	if level_root and _root_has_property("bake_chunk_size"):
		bake_settings["chunk_size"] = float(level_root.get("bake_chunk_size"))
	return {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"grid_snap": float(grid_snap.value),
		"snap_presets": snap_values,
		"brush_size": brush_size,
		"bake": bake_settings
	}


func _apply_editor_settings(data: Dictionary) -> void:
	if data.has("grid_snap"):
		_apply_grid_snap(float(data.get("grid_snap", grid_snap.value)))
	if data.has("snap_presets") and data["snap_presets"] is Array:
		_apply_snap_presets(data["snap_presets"])
	if data.has("brush_size") and data["brush_size"] is Dictionary:
		var size = data["brush_size"]
		size_x.value = float(size.get("x", size_x.value))
		size_y.value = float(size.get("y", size_y.value))
		size_z.value = float(size.get("z", size_z.value))
		if level_root:
			level_root.drag_size_default = Vector3(size_x.value, size_y.value, size_z.value)
			if _root_has_property("brush_size_default"):
				level_root.set(
					"brush_size_default", Vector3(size_x.value, size_y.value, size_z.value)
				)
	if data.has("bake") and data["bake"] is Dictionary:
		var bake = data["bake"]
		if bake_merge_meshes:
			bake_merge_meshes.button_pressed = bool(
				bake.get("merge_meshes", bake_merge_meshes.button_pressed)
			)
		if bake_generate_lods:
			bake_generate_lods.button_pressed = bool(
				bake.get("generate_lods", bake_generate_lods.button_pressed)
			)
		if bake_lightmap_uv2:
			bake_lightmap_uv2.button_pressed = bool(
				bake.get("lightmap_uv2", bake_lightmap_uv2.button_pressed)
			)
		if bake_lightmap_texel:
			bake_lightmap_texel.value = float(
				bake.get("lightmap_texel_size", bake_lightmap_texel.value)
			)
		if bake_use_face_materials:
			bake_use_face_materials.button_pressed = bool(
				bake.get("use_face_materials", bake_use_face_materials.button_pressed)
			)
		if bake_navmesh:
			bake_navmesh.button_pressed = bool(bake.get("navmesh", bake_navmesh.button_pressed))
		if bake_navmesh_cell_size:
			bake_navmesh_cell_size.value = float(
				bake.get("navmesh_cell_size", bake_navmesh_cell_size.value)
			)
		if bake_navmesh_cell_height:
			bake_navmesh_cell_height.value = float(
				bake.get("navmesh_cell_height", bake_navmesh_cell_height.value)
			)
		if bake_navmesh_agent_height:
			bake_navmesh_agent_height.value = float(
				bake.get("navmesh_agent_height", bake_navmesh_agent_height.value)
			)
		if bake_navmesh_agent_radius:
			bake_navmesh_agent_radius.value = float(
				bake.get("navmesh_agent_radius", bake_navmesh_agent_radius.value)
			)
		if collision_layer_opt and bake.has("collision_mask"):
			_select_option_by_id(collision_layer_opt, int(bake.get("collision_mask", 1)))
		if level_root and bake.has("chunk_size") and _root_has_property("bake_chunk_size"):
			level_root.set("bake_chunk_size", float(bake.get("chunk_size", 0.0)))
		_sync_bake_option_visibility()


func _apply_snap_presets(values: Array) -> void:
	if values.is_empty():
		return
	snap_preset_values.clear()
	for value in values:
		var v = float(value)
		if v <= 0.0:
			continue
		snap_preset_values.append(v)
	if snap_preset_values.is_empty():
		snap_preset_values = [1, 2, 4, 8, 16, 32, 64]
	for index in range(snap_buttons.size()):
		var button = snap_buttons[index]
		if not button:
			continue
		var preset = (
			snap_preset_values[index]
			if index < snap_preset_values.size()
			else snap_preset_values[snap_preset_values.size() - 1]
		)
		button.set_meta("snap_value", preset)
		button.text = str(preset)
	_sync_snap_buttons(grid_snap.value)
	_apply_all_tooltips()


func _select_option_by_id(option: OptionButton, id: int) -> void:
	if not option:
		return
	for i in range(option.get_item_count()):
		if option.get_item_id(i) == id:
			option.select(i)
			return


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


func _populate_brush_entity_classes() -> void:
	if not brush_entity_class_opt:
		return
	brush_entity_class_opt.clear()
	var defs = HFEntityDef.load_definitions(entity_defs_path)
	var brush_defs = HFEntityDef.filter_brush_entities(defs)
	if brush_defs.is_empty():
		# Fallback: ensure at least the built-in brush entity classes are available.
		brush_entity_class_opt.add_item("func_detail", 0)
		brush_entity_class_opt.add_item("func_wall", 1)
		brush_entity_class_opt.add_item("trigger_once", 2)
		brush_entity_class_opt.add_item("trigger_multiple", 3)
	else:
		for i in range(brush_defs.size()):
			brush_entity_class_opt.add_item(brush_defs[i].classname, i)
			if brush_defs[i].description != "":
				brush_entity_class_opt.set_item_tooltip(i, brush_defs[i].description)


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


func _make_brush_drag_data(preset_path: String, display_name: String, source: Control) -> Variant:
	if preset_path == "":
		return null
	var data = {"type": "hammerforge_brush_preset", "preset_path": preset_path}
	if source:
		var preview = _build_brush_drag_preview(display_name)
		if preview:
			source.set_drag_preview(preview)
	return data


func _build_brush_drag_preview(display_name: String) -> Control:
	var container = HBoxContainer.new()
	container.custom_minimum_size = Vector2(140, 28)
	container.size_flags_horizontal = Control.SIZE_FILL
	container.size_flags_vertical = Control.SIZE_FILL
	var label = Label.new()
	label.text = display_name
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
	var button := BrushPresetButton.new()
	button.preset_path = path
	button.dock_ref = self
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


# ===========================================================================
# Wave 1: Texture Lock UI
# ===========================================================================


func _setup_texture_lock_ui() -> void:
	var brush_vbox = brush_tab.get_node_or_null("BrushMargin/BrushVBox")
	if not brush_vbox:
		return
	texture_lock_check = CheckBox.new()
	texture_lock_check.text = "Texture Lock"
	texture_lock_check.button_pressed = true
	texture_lock_check.tooltip_text = "Keep texture alignment while moving, resizing, hollowing, or clipping brushes"
	texture_lock_check.toggled.connect(_on_texture_lock_toggled)
	brush_vbox.add_child(texture_lock_check)


func _on_texture_lock_toggled(pressed: bool) -> void:
	if syncing_grid:
		return
	if level_root and _root_has_property("texture_lock"):
		level_root.set("texture_lock", pressed)


# ===========================================================================
# Wave 1: Visgroups & Groups UI
# ===========================================================================


func _setup_visgroup_ui() -> void:
	var manage_vbox = manage_tab.get_node_or_null("ManageMargin/ManageVBox")
	if not manage_vbox:
		return

	# --- Visgroups & Groups section (collapsible, placed after Bake) ---
	var vg_sec = HFCollapsibleSection.create("Visgroups & Groups", true)
	# Insert after the Bake section (index 0) for visibility
	manage_vbox.add_child(vg_sec)
	manage_vbox.move_child(vg_sec, 1)
	_register_section(vg_sec, "Visgroups & Groups")
	var vgc = vg_sec.get_content()

	visgroup_list = ItemList.new()
	visgroup_list.custom_minimum_size.y = 80
	visgroup_list.select_mode = ItemList.SELECT_SINGLE
	visgroup_list.allow_reselect = true
	vgc.add_child(visgroup_list)
	visgroup_list.item_clicked.connect(_on_visgroup_item_clicked)

	var name_row = HBoxContainer.new()
	visgroup_name_input = LineEdit.new()
	visgroup_name_input.placeholder_text = "Visgroup name"
	visgroup_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(visgroup_name_input)
	visgroup_add_btn = Button.new()
	visgroup_add_btn.text = "New"
	visgroup_add_btn.tooltip_text = "Create a new visgroup"
	visgroup_add_btn.pressed.connect(_on_visgroup_add)
	name_row.add_child(visgroup_add_btn)
	vgc.add_child(name_row)

	var vg_btn_row = HBoxContainer.new()
	visgroup_add_sel_btn = Button.new()
	visgroup_add_sel_btn.text = "Add Sel"
	visgroup_add_sel_btn.tooltip_text = "Add selected brushes/entities to the highlighted visgroup"
	visgroup_add_sel_btn.pressed.connect(_on_visgroup_add_selection)
	vg_btn_row.add_child(visgroup_add_sel_btn)
	visgroup_rem_sel_btn = Button.new()
	visgroup_rem_sel_btn.text = "Rem Sel"
	visgroup_rem_sel_btn.tooltip_text = ("Remove selected brushes/entities from the highlighted visgroup")
	visgroup_rem_sel_btn.pressed.connect(_on_visgroup_remove_selection)
	vg_btn_row.add_child(visgroup_rem_sel_btn)
	visgroup_delete_btn = Button.new()
	visgroup_delete_btn.text = "Delete"
	visgroup_delete_btn.tooltip_text = "Delete the highlighted visgroup"
	visgroup_delete_btn.pressed.connect(_on_visgroup_delete)
	vg_btn_row.add_child(visgroup_delete_btn)
	vgc.add_child(vg_btn_row)

	# --- Groups subsection ---
	var grp_sep = HSeparator.new()
	vgc.add_child(grp_sep)

	var grp_btn_row = HBoxContainer.new()
	group_sel_btn = Button.new()
	group_sel_btn.text = "Group Sel (Ctrl+G)"
	group_sel_btn.tooltip_text = "Group the current selection"
	group_sel_btn.pressed.connect(_on_group_selection)
	grp_btn_row.add_child(group_sel_btn)
	ungroup_btn = Button.new()
	ungroup_btn.text = "Ungroup (Ctrl+U)"
	ungroup_btn.tooltip_text = "Remove selected brushes/entities from their group"
	ungroup_btn.pressed.connect(_on_ungroup_selection)
	grp_btn_row.add_child(ungroup_btn)
	vgc.add_child(grp_btn_row)


func refresh_visgroup_ui() -> void:
	if not visgroup_list:
		return
	visgroup_list.clear()
	if not level_root or not level_root.get("visgroup_system"):
		return
	var sys = level_root.get("visgroup_system")
	if not sys:
		return
	var names: PackedStringArray = sys.get_visgroup_names()
	for vg_name in names:
		var visible = sys.is_visgroup_visible(vg_name)
		var icon_text = "[V] " if visible else "[H] "
		visgroup_list.add_item(icon_text + vg_name)


func _get_selected_visgroup_name() -> String:
	if not visgroup_list:
		return ""
	var selected = visgroup_list.get_selected_items()
	if selected.is_empty():
		return ""
	var text = visgroup_list.get_item_text(selected[0])
	# Strip the [V]/[H] prefix
	if text.begins_with("[V] "):
		return text.substr(4)
	if text.begins_with("[H] "):
		return text.substr(4)
	return text


func _on_visgroup_add() -> void:
	if not visgroup_name_input:
		return
	var vg_name = visgroup_name_input.text.strip_edges()
	if vg_name == "" or not level_root:
		return
	level_root.create_visgroup(vg_name)
	visgroup_name_input.text = ""
	refresh_visgroup_ui()


func _on_visgroup_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	# Double-click or single click toggles visibility
	var text = visgroup_list.get_item_text(index)
	var vg_name = ""
	var was_visible = true
	if text.begins_with("[V] "):
		vg_name = text.substr(4)
		was_visible = true
	elif text.begins_with("[H] "):
		vg_name = text.substr(4)
		was_visible = false
	else:
		return
	if vg_name == "" or not level_root:
		return
	level_root.set_visgroup_visible(vg_name, not was_visible)
	refresh_visgroup_ui()
	# Reselect same index
	if index < visgroup_list.item_count:
		visgroup_list.select(index)


func _on_visgroup_add_selection() -> void:
	var vg_name = _get_selected_visgroup_name()
	if vg_name == "" or not level_root:
		return
	level_root.add_selection_to_visgroup(vg_name, _selection_nodes)
	refresh_visgroup_ui()


func _on_visgroup_remove_selection() -> void:
	var vg_name = _get_selected_visgroup_name()
	if vg_name == "" or not level_root:
		return
	level_root.remove_selection_from_visgroup(vg_name, _selection_nodes)
	refresh_visgroup_ui()


func _on_visgroup_delete() -> void:
	var vg_name = _get_selected_visgroup_name()
	if vg_name == "" or not level_root:
		return
	level_root.remove_visgroup(vg_name)
	refresh_visgroup_ui()


func _on_group_selection() -> void:
	if not level_root or _selection_nodes.size() < 2:
		return
	var group_name = "group_%d" % Time.get_ticks_usec()
	level_root.group_selection(group_name, _selection_nodes)
	record_history("Group Selection")


func _on_ungroup_selection() -> void:
	if not level_root or _selection_nodes.is_empty():
		return
	level_root.ungroup_nodes(_selection_nodes)
	record_history("Ungroup Selection")


# ===========================================================================
# Wave 1: Cordon (Partial Bake) UI
# ===========================================================================


func _setup_cordon_ui() -> void:
	var manage_vbox = manage_tab.get_node_or_null("ManageMargin/ManageVBox")
	if not manage_vbox:
		return

	var cordon_sec = HFCollapsibleSection.create("Cordon (Partial Bake)", false)
	# Insert after Visgroups section (index 2)
	manage_vbox.add_child(cordon_sec)
	manage_vbox.move_child(cordon_sec, 2)
	_register_section(cordon_sec, "Cordon (Partial Bake)")
	var cc = cordon_sec.get_content()

	cordon_enabled_check = CheckBox.new()
	cordon_enabled_check.text = "Enable Cordon"
	cordon_enabled_check.tooltip_text = "Only bake geometry inside the cordon AABB"
	cordon_enabled_check.toggled.connect(_on_cordon_toggled)
	cc.add_child(cordon_enabled_check)

	var min_label = Label.new()
	min_label.text = "Min (X, Y, Z):"
	cc.add_child(min_label)

	var min_row = HBoxContainer.new()
	cordon_min_x = _make_cordon_spin(-9999, 9999, -128)
	cordon_min_y = _make_cordon_spin(-9999, 9999, -128)
	cordon_min_z = _make_cordon_spin(-9999, 9999, -128)
	min_row.add_child(cordon_min_x)
	min_row.add_child(cordon_min_y)
	min_row.add_child(cordon_min_z)
	cc.add_child(min_row)

	var max_label = Label.new()
	max_label.text = "Max (X, Y, Z):"
	cc.add_child(max_label)

	var max_row = HBoxContainer.new()
	cordon_max_x = _make_cordon_spin(-9999, 9999, 128)
	cordon_max_y = _make_cordon_spin(-9999, 9999, 128)
	cordon_max_z = _make_cordon_spin(-9999, 9999, 128)
	max_row.add_child(cordon_max_x)
	max_row.add_child(cordon_max_y)
	max_row.add_child(cordon_max_z)
	cc.add_child(max_row)

	cordon_from_sel_btn = Button.new()
	cordon_from_sel_btn.text = "Set from Selection"
	cordon_from_sel_btn.tooltip_text = "Set cordon bounds to encompass the selected brushes"
	cordon_from_sel_btn.pressed.connect(_on_cordon_from_selection)
	cc.add_child(cordon_from_sel_btn)


func _make_cordon_spin(min_val: float, max_val: float, default_val: float) -> SpinBox:
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.step = 1.0
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_cordon_value_changed)
	return spin


func _on_cordon_toggled(pressed: bool) -> void:
	if syncing_grid:
		return
	if level_root and _root_has_property("cordon_enabled"):
		level_root.set("cordon_enabled", pressed)
		if level_root.has_method("update_cordon_visual"):
			level_root.update_cordon_visual()


func _on_cordon_value_changed(_value: float) -> void:
	if syncing_grid:
		return
	if not level_root or not _root_has_property("cordon_aabb"):
		return
	var min_pt = Vector3(
		cordon_min_x.value if cordon_min_x else -128,
		cordon_min_y.value if cordon_min_y else -128,
		cordon_min_z.value if cordon_min_z else -128
	)
	var max_pt = Vector3(
		cordon_max_x.value if cordon_max_x else 128,
		cordon_max_y.value if cordon_max_y else 128,
		cordon_max_z.value if cordon_max_z else 128
	)
	level_root.set("cordon_aabb", AABB(min_pt, max_pt - min_pt))
	level_root.update_cordon_visual()


func _on_cordon_from_selection() -> void:
	if not level_root or _selection_nodes.is_empty():
		return
	level_root.set_cordon_from_selection(_selection_nodes)
	# Sync spinboxes from updated AABB
	if _root_has_property("cordon_aabb"):
		var aabb: AABB = level_root.get("cordon_aabb")
		if cordon_min_x:
			cordon_min_x.value = aabb.position.x
		if cordon_min_y:
			cordon_min_y.value = aabb.position.y
		if cordon_min_z:
			cordon_min_z.value = aabb.position.z
		if cordon_max_x:
			cordon_max_x.value = aabb.position.x + aabb.size.x
		if cordon_max_y:
			cordon_max_y.value = aabb.position.y + aabb.size.y
		if cordon_max_z:
			cordon_max_z.value = aabb.position.z + aabb.size.z
	if cordon_enabled_check:
		cordon_enabled_check.button_pressed = true


func _on_clip() -> void:
	if not level_root or _selection_nodes.is_empty():
		_set_status("Select a brush to clip", true)
		return
	var brush = _selection_nodes[0]
	if not level_root.is_brush_node(brush):
		_set_status("Select a brush to clip", true)
		return
	var info = level_root.get_brush_info_from_node(brush)
	var brush_id = str(info.get("brush_id", ""))
	if brush_id == "":
		return
	# Default clip: split along Y axis at center
	var center = info.get("center", Vector3.ZERO)
	var split_pos: float = center.y if center is Vector3 else 0.0
	var check: HFOpResult = level_root.can_clip_brush(brush_id, 1, split_pos)
	if not check.ok:
		show_toast(check.user_text(), 1)
		return
	_commit_state_action("Clip Brush", "clip_brush_by_id", [brush_id, 1, split_pos])


func _on_io_add() -> void:
	if not level_root or _selection_nodes.is_empty():
		_set_status("Select an entity to add output", true)
		return
	var entity = _selection_nodes[0]
	if not level_root.is_entity_node(entity):
		_set_status("Select an entity to add output", true)
		return
	var output_name = io_output_name.text.strip_edges() if io_output_name else ""
	var target_name = io_target_name.text.strip_edges() if io_target_name else ""
	var input_name = io_input_name.text.strip_edges() if io_input_name else ""
	if output_name == "" or target_name == "" or input_name == "":
		_set_status("Fill in Output, Target, and Input fields", true)
		return
	var parameter = io_parameter.text.strip_edges() if io_parameter else ""
	var delay = io_delay.value if io_delay else 0.0
	var fire_once = io_fire_once.button_pressed if io_fire_once else false
	level_root.add_entity_output(
		entity, output_name, target_name, input_name, parameter, delay, fire_once
	)
	_refresh_io_list(entity)
	_set_status("Added output: %s → %s.%s" % [output_name, target_name, input_name])


func _on_io_remove() -> void:
	if not level_root or _selection_nodes.is_empty():
		return
	var entity = _selection_nodes[0]
	if not level_root.is_entity_node(entity):
		return
	if not io_list:
		return
	var selected_items = io_list.get_selected_items()
	if selected_items.is_empty():
		_set_status("Select a connection to remove", true)
		return
	var index = selected_items[0]
	level_root.remove_entity_output(entity, index)
	_refresh_io_list(entity)
	_set_status("Removed output connection")


func _refresh_io_list(entity: Node = null) -> void:
	if not io_list:
		return
	io_list.clear()
	if not entity:
		if _selection_nodes.is_empty():
			return
		entity = _selection_nodes[0]
	if not level_root or not level_root.is_entity_node(entity):
		return
	var outputs = level_root.get_entity_outputs(entity)
	for conn in outputs:
		if not (conn is Dictionary):
			continue
		var out_name = str(conn.get("output_name", ""))
		var tgt = str(conn.get("target_name", ""))
		var inp = str(conn.get("input_name", ""))
		var delay = float(conn.get("delay", 0.0))
		var once = bool(conn.get("fire_once", false))
		var label = "%s → %s.%s" % [out_name, tgt, inp]
		if delay > 0.0:
			label += " (%.1fs)" % delay
		if once:
			label += " [once]"
		io_list.add_item(label)


# ---------------------------------------------------------------------------
# Context toolbar helper methods
# ---------------------------------------------------------------------------


## Apply the currently selected material to ALL faces on selected brushes.
func _apply_material_to_whole_brush() -> void:
	if not level_root or _selected_material_index < 0:
		show_toast("No material selected", 1)
		return
	var brush_ids := _get_selected_brush_ids()
	if brush_ids.is_empty():
		show_toast("No brushes selected", 1)
		return
	_commit_state_action(
		"Assign Brush Material",
		"assign_material_to_whole_brushes",
		[_selected_material_index, brush_ids]
	)
	var mat_name := _material_display_name(_selected_material_index)
	show_toast(
		(
			"Applied %s to %d brush%s"
			% [mat_name, brush_ids.size(), "" if brush_ids.size() == 1 else "es"]
		),
		0
	)


## Assign face material — called by context toolbar for quick material apply.
func _on_face_assign_material() -> void:
	_on_material_assign()
