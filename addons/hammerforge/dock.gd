@tool
extends Control
class_name HammerForgeDock

signal hud_visibility_changed(visible: bool)
signal builtin_tool_changed
signal vertex_mode_toggled(enabled: bool)
signal face_select_mode_toggled(enabled: bool)
signal selection_clear_requested
signal grid_snap_applied(value: float)
signal bake_state_changed(baking: bool, success: bool)
signal command_palette_requested
signal power_user_overlays_changed(enabled: bool)

const LevelRootType = preload("level_root.gd")
const BrushPreset = preload("brush_preset.gd")
const DraftEntity = preload("draft_entity.gd")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFCollapsibleSection = preload("ui/collapsible_section.gd")
const HFUIFactory = preload("ui/hf_ui_factory.gd")
const HFEditorTheme = preload("ui/hf_editor_theme.gd")
const HFShapeIcons = preload("ui/hf_shape_icons.gd")
const HFUndoNav = preload("ui/hf_undo_nav.gd")
const HFEntityPropUtils = preload("ui/hf_entity_prop_utils.gd")
const HFTooltipText = preload("ui/hf_tooltip_text.gd")
const HFToast = preload("ui/hf_toast.gd")
const HFTutorialWizard = preload("ui/hf_tutorial_wizard.gd")
const HFEntityDef = preload("hf_entity_def.gd")
const HFPrefabType = preload("hf_prefab.gd")
const UVEditorScene = preload("uv_editor.tscn")
const PaintTabBuilder = preload("ui/paint_tab_builder.gd")
const EntityTabBuilder = preload("ui/entity_tab_builder.gd")
const ManageTabBuilder = preload("ui/manage_tab_builder.gd")
const SelectionToolsBuilder = preload("ui/selection_tools_builder.gd")
const HFDockPaintHandler = preload("dock_paint_handler.gd")
const HFDockBrushHandler = preload("dock_brush_handler.gd")
const HFDockEntityHandler = preload("dock_entity_handler.gd")
const HFDockManageHandler = preload("dock_manage_handler.gd")
const HFDockConnections = preload("dock_connections.gd")
const HFDockVisgroupHandler = preload("dock_visgroup_handler.gd")
const HFDockFileHandler = preload("dock_file_handler.gd")

const PRESET_MENU_RENAME := 0
const PRESET_MENU_DELETE := 1
const TAB_ALIASES := {"Brush": "Build", "Entities": "Objects", "Manage": "Test"}
const MIXED_SELECTION_MESSAGE := (
	"This action is unavailable for a mixed selection of HammerForge objects and ordinary Godot "
	+ "nodes. Use one selection type at a time; no nodes were changed."
)

enum DockSelectionScope { EMPTY, MANAGED, NATIVE, MIXED }
enum DockSelectionRequirement { MANAGED, BRUSHES_ONLY, ENTITIES_ONLY, NATIVE_ALLOWED }


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
@onready
var create_starter_btn: Button = $Margin/VBox/NoRootBanner/BannerContent/BannerActions/CreateStarter
@onready
var create_empty_root_btn: Button = $Margin/VBox/NoRootBanner/BannerContent/BannerActions/CreateEmpty
@onready var status_bar: HBoxContainer = $Margin/VBox/Footer/StatusFooter
@onready var progress_bar: ProgressBar = $Margin/VBox/Footer/StatusFooter/ProgressBar

@onready var tool_draw: Button = $Margin/VBox/Toolbar/ToolDraw
@onready var tool_select: Button = $Margin/VBox/Toolbar/ToolSelect
@onready var paint_mode: Button = $Margin/VBox/Toolbar/PaintMode
@onready
var mode_add: Button = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/OperationRow/ModeAdd
@onready
var mode_subtract: Button = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox/OperationRow/ModeSubtract
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
var heightmap_convert_btn: Button = null
# -- Foliage & Scatter controls (built by paint_tab_builder) --
var scatter_mesh_btn: Button = null
var scatter_density_spin: SpinBox = null
var scatter_radius_spin: SpinBox = null
var scatter_min_height_spin: SpinBox = null
var scatter_max_height_spin: SpinBox = null
var scatter_max_slope_spin: SpinBox = null
var scatter_scale_min_spin: SpinBox = null
var scatter_scale_max_spin: SpinBox = null
var scatter_align_normal: CheckBox = null
var scatter_random_rotation: CheckBox = null
var scatter_shape_select: OptionButton = null
var scatter_spline_width_spin: SpinBox = null
var scatter_preview_select: OptionButton = null
var scatter_preview_btn: Button = null
var scatter_commit_btn: Button = null
var scatter_clear_btn: Button = null
var _scatter_mesh_path: String = ""
var _scatter_preview_node: MultiMeshInstance3D = null
var _scatter_last_result: Array[Transform3D] = []
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
var bake_unwrap_uv0: CheckBox = null
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
# -- Bake optimization controls (built programmatically) --
var bake_selected_btn: Button = null
var bake_changed_btn: Button = null
var bake_check_issues_btn: Button = null
var bake_preview_mode_opt: OptionButton = null
var bake_estimate_label: Label = null
var bake_chunk_size_spin: SpinBox = null
var bake_visible_only_check: CheckBox = null
var bake_use_multimesh_check: CheckBox = null
var bake_use_atlas_check: CheckBox = null
var bake_auto_connectors_check: CheckBox = null
var bake_generate_occluders_check: CheckBox = null
var bake_occluder_min_area_spin: SpinBox = null
var bake_connector_mode_opt: OptionButton = null
var bake_connector_stair_height_spin: SpinBox = null
var bake_connector_width_spin: SpinBox = null
# -- Quick Play mode controls --
var primary_quick_play_btn: Button = null
var quick_play_camera_btn: Button = null
var quick_play_area_btn: Button = null
var export_playtest_btn: Button = null
# -- Editor toggles (built programmatically in _build_manage_tab) --
var commit_freeze: CheckBox = null
var show_hud: CheckBox = null
var power_user_overlays: CheckBox = null
var show_grid: CheckBox = null
var follow_grid: CheckBox = null
var debug_logs: CheckBox = null
# -- Manage tab action buttons (built programmatically) --
var new_level_btn: Button = null
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
var history_list: ItemList = null  # Legacy — kept for compat, may be null
var history_browser: HFHistoryBrowser = null
@onready var quick_play_btn: Button = $Margin/VBox/Footer/QuickPlay
# -- Settings (built programmatically) --
var export_settings_btn: Button = null
var import_settings_btn: Button = null
@onready var settings_export_dialog: FileDialog = $SettingsExportDialog
@onready var settings_import_dialog: FileDialog = $SettingsImportDialog
# -- Performance (built programmatically) --
var perf_brushes_value: Label = null
var perf_entity_value: Label = null
var perf_vertex_value: Label = null
var perf_paint_mem_value: Label = null
var perf_bake_chunks_value: Label = null
var perf_bake_time_value: Label = null
var perf_chunk_rec_value: Label = null
var perf_health_label: Label = null
var perf_brush_bar: ProgressBar = null
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
var uv_projection_opt: OptionButton = null
var uv_reproject_btn: Button = null
var uv_scale_x: SpinBox = null
var uv_scale_y: SpinBox = null
var uv_offset_x: SpinBox = null
var uv_offset_y: SpinBox = null
var uv_rotation_spin: SpinBox = null
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
var _plugin: EditorPlugin = null
var editor_base_control: Control = null
var undo_redo: EditorUndoRedoManager = null
var connected_root: Node = null
var snap_button_group: ButtonGroup
var syncing_snap := false
var snap_grid_btn: Button = null
var snap_vertex_btn: Button = null
var snap_center_btn: Button = null
var snap_edge_btn: Button = null
var snap_perp_btn: Button = null
var _axis_lock_x: Button = null
var _axis_lock_y: Button = null
var _axis_lock_z: Button = null
var _show_io_lines: CheckBox = null
var _show_subtract_preview: CheckBox = null
var _show_spawn_debug: CheckBox = null
var _spawn_validate_btn: Button = null
var _spawn_auto_create_btn: Button = null
var _prefab_library = null  # HFPrefabLibrary
var _example_library = null  # HFExampleLibrary
var _operation_replay = null  # HFOperationReplay
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
var _syncing_paint_tab: bool = false
var _prop_cache: Dictionary = {}
var tool_extrude_up: Button = null
var tool_extrude_down: Button = null
var tool_vertex: Button = null
var _edit_tools_separator: VSeparator = null
var _vertex_tool_separator: VSeparator = null
var _snap_mode_row: HBoxContainer = null
var _axis_lock_row: HBoxContainer = null
var _advanced_build_section: HFCollapsibleSection = null

# Wave 1 UI controls
var _selection_nodes: Array = []
var _all_sections: Dictionary = {}
var _selection_tools_section: HFCollapsibleSection = null
var _sel_tools_hint_label: Label = null
var _uv_hint_label: Label = null
var _toast_container: VBoxContainer = null
var _clear_sel_btn: Button = null
var _command_palette_btn: Button = null
var _guide_btn: Button = null
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
var _io_wiring_panel = null  # HFIOWiringPanel
# Entity I/O sections (context-hidden when no entity selected)
var _entity_io_section: VBoxContainer = null
var _io_wiring_section: VBoxContainer = null
# Entity Properties controls
var _entity_props_section: VBoxContainer = null
var _entity_props_controls: Array = []
var _entity_props_entity: Node3D = null

# Displacement / Bevel UI controls
var _disp_section: HFCollapsibleSection = null
var _disp_power_spin: SpinBox = null
var _disp_elevation_spin: SpinBox = null
var _disp_create_btn: Button = null
var _disp_destroy_btn: Button = null
var _disp_smooth_btn: Button = null
var _disp_noise_btn: Button = null
var _disp_sew_btn: Button = null
var _disp_sew_group_spin: SpinBox = null
var _disp_paint_mode_opt: OptionButton = null
var _disp_radius_spin: SpinBox = null
var _disp_strength_spin: SpinBox = null
var _bevel_section: HFCollapsibleSection = null
var _bevel_edge_btn: Button = null
var _bevel_inset_btn: Button = null
var _bevel_segments_spin: SpinBox = null
var _bevel_radius_spin: SpinBox = null
var _bevel_inset_dist_spin: SpinBox = null
var _bevel_inset_height_spin: SpinBox = null


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
		_tag_bake_setting_change(prop)


func _on_setting_float_changed(value: float, prop: String) -> void:
	if level_root and _root_has_property(prop):
		level_root.set(prop, value)
		_tag_bake_setting_change(prop)


func _on_setting_int_changed(value: float, prop: String) -> void:
	if level_root and _root_has_property(prop):
		level_root.set(prop, int(value))
		_tag_bake_setting_change(prop)


func _tag_bake_setting_change(prop: String) -> void:
	if (
		level_root
		and (prop.begins_with("bake_") or prop in ["cordon_enabled", "cordon_aabb"])
		and level_root.has_method("tag_full_reconcile")
	):
		level_root.tag_full_reconcile()


func _on_debug_toggled(pressed: bool) -> void:
	debug_enabled = pressed
	if level_root and _root_has_property("debug_logging"):
		level_root.set("debug_logging", pressed)


func _connect_setting_signals() -> void:
	HFDockConnections.connect_settings(self)


func _apply_ui_state_to_root() -> void:
	if not level_root:
		return
	var toggle_pairs: Array = [
		[bake_merge_meshes, "bake_merge_meshes"],
		[bake_generate_lods, "bake_generate_lods"],
		[bake_unwrap_uv0, "bake_unwrap_uv0"],
		[bake_lightmap_uv2, "bake_lightmap_uv2"],
		[bake_use_face_materials, "bake_use_face_materials"],
		[bake_navmesh, "bake_navmesh"],
		[bake_visible_only_check, "bake_visible_only"],
		[bake_use_multimesh_check, "bake_use_multimesh"],
		[bake_use_atlas_check, "bake_use_atlas"],
		[bake_auto_connectors_check, "bake_auto_connectors"],
		[bake_generate_occluders_check, "bake_generate_occluders"],
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
		[bake_chunk_size_spin, "bake_chunk_size"],
		[bake_lightmap_texel, "bake_lightmap_texel_size"],
		[bake_navmesh_cell_size, "bake_navmesh_cell_size"],
		[bake_navmesh_cell_height, "bake_navmesh_cell_height"],
		[bake_navmesh_agent_height, "bake_navmesh_agent_height"],
		[bake_navmesh_agent_radius, "bake_navmesh_agent_radius"],
		[bake_connector_stair_height_spin, "bake_connector_stair_height"],
		[bake_occluder_min_area_spin, "bake_occluder_min_area"],
	]
	for pair in float_pairs:
		var ctrl: SpinBox = pair[0] as SpinBox
		var prop: String = pair[1]
		if ctrl and _root_has_property(prop):
			level_root.set(prop, float(ctrl.value))
	var int_pairs: Array = [
		[autosave_minutes, "hflevel_autosave_minutes"],
		[autosave_keep, "hflevel_autosave_keep"],
		[bake_connector_width_spin, "bake_connector_width"],
	]
	for pair in int_pairs:
		var ctrl: SpinBox = pair[0] as SpinBox
		var prop: String = pair[1]
		if ctrl and _root_has_property(prop):
			level_root.set(prop, int(ctrl.value))
	if bake_connector_mode_opt and _root_has_property("bake_connector_mode"):
		level_root.set("bake_connector_mode", bake_connector_mode_opt.get_selected_id())
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
	if power_user_overlays:
		power_user_overlays.set_pressed_no_signal(
			bool(_user_prefs.get_pref("power_user_overlays", false))
		)
	# Restore collapsed section state
	for sec_name in _all_sections:
		var collapsed = _user_prefs.get_section_collapsed(sec_name)
		if collapsed != null:
			_all_sections[sec_name].set_expanded(not bool(collapsed))
	# Show welcome panel on first launch
	if _user_prefs.get_pref("show_welcome", true) and not is_instance_valid(_tutorial_wizard):
		_show_welcome_panel()


func _make_context_hint() -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0, 0.9))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(0, 34)
	return label


func _setup_context_hints() -> void:
	var brush_vbox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox
	if brush_vbox:
		_brush_hint = _make_context_hint()
		brush_vbox.add_child(_brush_hint)
		brush_vbox.move_child(_brush_hint, 0)

	var paint_vbox = $Margin/VBox/MainTabs/Paint/PaintMargin/PaintVBox
	if paint_vbox:
		_paint_hint = _make_context_hint()
		paint_vbox.add_child(_paint_hint)
		paint_vbox.move_child(_paint_hint, 0)

	var ent_vbox = $Margin/VBox/MainTabs/Entities/EntitiesMargin/EntitiesVBox
	if ent_vbox:
		_entity_hint = _make_context_hint()
		ent_vbox.add_child(_entity_hint)
		ent_vbox.move_child(_entity_hint, 0)

	var manage_vbox = $Margin/VBox/MainTabs/Manage/ManageMargin/ManageVBox
	if manage_vbox:
		_manage_hint = _make_context_hint()
		manage_vbox.add_child(_manage_hint)
		manage_vbox.move_child(_manage_hint, 0)

	_update_context_hints()


func _setup_simplified_workflow() -> void:
	# Keep the dock's primary path legible: Build -> Paint/Objects -> Test.
	if main_tabs:
		main_tabs.set_tab_title(brush_tab.get_index(), "Build")
		main_tabs.set_tab_title(paint_tab.get_index(), "Paint")
		main_tabs.set_tab_title(entity_tab.get_index(), "Objects")
		main_tabs.set_tab_title(manage_tab.get_index(), "Test")

	if quick_play_btn:
		quick_play_btn.text = "Test Level  (Bake + Play)"
		quick_play_btn.custom_minimum_size.y = 34
		quick_play_btn.tooltip_text = "Bake the level and run it in one step"

	if tool_draw:
		tool_draw.custom_minimum_size.x = 52
	if tool_select:
		tool_select.custom_minimum_size.x = 52
	if paint_mode:
		paint_mode.custom_minimum_size.x = 52

	if size_x:
		size_x.suffix = " X"
		size_x.tooltip_text = "Brush width (X)"
	if size_y:
		size_y.suffix = " Y"
		size_y.tooltip_text = "Brush height (Y)"
	if size_z:
		size_z.suffix = " Z"
		size_z.tooltip_text = "Brush depth (Z)"
	if grid_snap:
		grid_snap.suffix = " units"
		grid_snap.tooltip_text = "Movement and drawing grid size"

	# Put infrequent snapping and collision choices behind one collapsed disclosure.
	var brush_vbox := brush_tab.get_node_or_null("BrushMargin/BrushVBox") as VBoxContainer
	if not brush_vbox or _advanced_build_section:
		return
	_advanced_build_section = HFCollapsibleSection.create("More build settings", false)
	brush_vbox.add_child(_advanced_build_section)
	_register_section(_advanced_build_section, "More build settings")
	var advanced_content := _advanced_build_section.get_content()
	if not advanced_content:
		return

	var note := Label.new()
	note.text = "Snap presets, snap targets, axis locks, and collision layer."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.58))
	advanced_content.add_child(note)

	var quick_snaps := brush_vbox.get_node_or_null("QuickSnapGrid")
	if quick_snaps:
		quick_snaps.reparent(advanced_content)
	if _snap_mode_row:
		_snap_mode_row.reparent(advanced_content)
	if _axis_lock_row:
		_axis_lock_row.reparent(advanced_content)
	var physics_row := brush_vbox.get_node_or_null("PhysicsLayerRow")
	if physics_row:
		physics_row.reparent(advanced_content)
	if _disp_section:
		_disp_section.reparent(advanced_content)
	if _bevel_section:
		_bevel_section.reparent(advanced_content)

	var material_row := brush_vbox.get_node_or_null("MaterialRow")
	if material_row:
		brush_vbox.move_child(_advanced_build_section, material_row.get_index() + 1)

	if snap_grid_btn:
		snap_grid_btn.text = "Grid"
	if snap_vertex_btn:
		snap_vertex_btn.text = "Corners"
	if snap_center_btn:
		snap_center_btn.text = "Centers"
	if snap_edge_btn:
		snap_edge_btn.text = "Edges"
	if snap_perp_btn:
		snap_perp_btn.text = "Perp"


func _update_context_hints() -> void:
	var has_root = level_root != null
	var has_brushes = (
		has_root
		and level_root.has_method("get_live_brush_count")
		and level_root.get_live_brush_count() > 0
	)
	var selection_scope := _current_selection_scope()
	var managed_counts := _get_managed_selection_counts(_selection_nodes)
	var has_selection: bool = (
		selection_scope == DockSelectionScope.MANAGED
		and int(managed_counts["brushes"]) > 0
		and int(managed_counts["entities"]) == 0
	)
	var mixed_selection := selection_scope == DockSelectionScope.MIXED
	var heterogeneous_selection := (
		selection_scope == DockSelectionScope.MANAGED
		and int(managed_counts["brushes"]) > 0
		and int(managed_counts["entities"]) > 0
	)

	if _brush_hint:
		if not has_root:
			_brush_hint.text = "Start here: create the Starter Level above."
		elif not has_brushes:
			_brush_hint.text = "Drag in the 3D viewport to create a solid brush."
		elif mixed_selection:
			_brush_hint.text = "Mixed selection: select only HammerForge objects to edit brushes."
		elif heterogeneous_selection:
			_brush_hint.text = "Select only brushes to use brush editing tools."
		elif has_selection:
			_brush_hint.text = "Brush selected. Edit tools are now available above."
		else:
			_brush_hint.text = "Draw another brush, or choose Select to edit one."

	if _paint_hint:
		if not has_root:
			_paint_hint.text = ""
		elif has_brushes:
			_paint_hint.text = "Choose a paint tool, then drag across the level."
		else:
			_paint_hint.text = "Draw a brush first, then return here to texture and paint it."

	if _entity_hint:
		if has_root:
			_entity_hint.text = "Drag an object into the viewport, then select it to edit."
		else:
			_entity_hint.text = ""

	if _manage_hint:
		_manage_hint.text = (
			"Use Test Level for the one-click path. Check or Bake separately only when needed."
			if has_root
			else ""
		)


func _show_welcome_panel() -> void:
	if is_instance_valid(_tutorial_wizard):
		return
	_tutorial_wizard = null
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
	_tutorial_wizard.action_requested.connect(_on_tutorial_action_requested)
	var vbox = $Margin/VBox
	var tabs = $Margin/VBox/MainTabs
	var idx = tabs.get_index()
	vbox.add_child(_tutorial_wizard)
	vbox.move_child(_tutorial_wizard, idx)
	# Always call start() so labels/progress are populated immediately.
	# If level_root is null, the wizard shows text but can't auto-advance
	# until set_root() connects signals later.
	_tutorial_wizard.start(level_root, self, start_step)


func _restart_tutorial() -> void:
	_close_tutorial()
	if _user_prefs:
		_user_prefs.set_pref("show_welcome", true)
		_user_prefs.set_pref("tutorial_step", 0)
		_user_prefs.save()
	_show_welcome_panel()


func _on_tutorial_action_requested(action: String) -> void:
	match action:
		"setup_draw":
			if not level_root:
				_on_create_level_root(true)
			highlight_tab("Brush")
			paint_mode.button_pressed = false
			mode_add.button_pressed = true
			tool_draw.button_pressed = true
			builtin_tool_changed.emit()
			show_toast("Draw is ready - drag in the 3D viewport", 0)
		"setup_subtract":
			highlight_tab("Brush")
			paint_mode.button_pressed = false
			mode_subtract.button_pressed = true
			tool_draw.button_pressed = true
			builtin_tool_changed.emit()
			show_toast("Cut mode is ready - draw through existing geometry", 0)
		"setup_paint":
			highlight_tab("Paint")
			paint_mode.button_pressed = true
			show_toast("Paint mode enabled", 0)
		"setup_entities":
			highlight_tab("Entities")
			show_toast("Drag an entity into the viewport", 0)
		"setup_bake":
			highlight_tab("Manage")
			var bake_section = _all_sections.get("Bake")
			if bake_section:
				bake_section.set_expanded(true)
			show_toast("Validate first, then Bake or Quick Play", 0)
		"quick_play":
			highlight_tab("Manage")
			show_toast("Checking, baking, and starting the level", 0)
			call_deferred("_on_quick_play")


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
			tree.create_timer(2.0).timeout.connect(
				func():
					if is_instance_valid(self):
						_close_tutorial()
			)


func _close_tutorial() -> void:
	if _tutorial_wizard and is_instance_valid(_tutorial_wizard):
		_tutorial_wizard.queue_free()
		_tutorial_wizard = null


## Highlight a dock tab by name (brief flash effect for tutorial).
func highlight_tab(tab_name: String) -> void:
	var tabs_node = main_tabs
	if not tabs_node:
		return
	var display_name: String = str(TAB_ALIASES.get(tab_name, tab_name))
	for i in tabs_node.get_tab_count():
		if tabs_node.get_tab_title(i) == display_name:
			tabs_node.current_tab = i
			break


func _on_main_tab_changed(tab_index: int) -> void:
	if _syncing_paint_tab or not paint_mode or not main_tabs:
		return
	var paint_tab_active := main_tabs.get_tab_title(tab_index) == "Paint"
	# Face Select's controls live on Paint, but its modal state must never remain
	# hidden after the user moves to another workflow tab.
	if not paint_tab_active and face_select_mode and face_select_mode.button_pressed:
		face_select_mode.button_pressed = false
	if paint_mode.button_pressed == paint_tab_active:
		return
	_syncing_paint_tab = true
	paint_mode.set_pressed_no_signal(paint_tab_active)
	_syncing_paint_tab = false
	builtin_tool_changed.emit()
	show_toast("Paint mode enabled" if paint_tab_active else "Build mode enabled", 0)


func _on_paint_mode_toggled(enabled: bool) -> void:
	if _syncing_paint_tab:
		return
	_syncing_paint_tab = true
	highlight_tab("Paint" if enabled else "Brush")
	_syncing_paint_tab = false
	builtin_tool_changed.emit()


func _on_welcome_dismissed(dont_show_again: bool) -> void:
	if dont_show_again and _user_prefs:
		_user_prefs.set_pref("show_welcome", false)
		_user_prefs.save()
	var tabs = $Margin/VBox/MainTabs
	if tabs:
		tabs.visible = true


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
		tool_draw.text = "Draw"
		tool_draw.tooltip_text = "Draw (%s)\nDrag in the viewport to create a brush" % key
	if tool_select:
		var key = _keymap.get_display_string("tool_select")
		tool_select.text = "Select"
		tool_select.tooltip_text = "Select (%s)\nClick a brush; Shift adds to selection" % key
	if tool_extrude_up:
		var key = _keymap.get_display_string("tool_extrude_up")
		tool_extrude_up.text = "Up"
		tool_extrude_up.tooltip_text = "Extrude Up (%s)\nClick face + drag to extrude upward" % key
	if tool_extrude_down:
		var key = _keymap.get_display_string("tool_extrude_down")
		tool_extrude_down.text = "Down"
		tool_extrude_down.tooltip_text = (
			"Extrude Down (%s)\nClick face + drag to extrude downward" % key
		)
	if tool_vertex:
		var key = _keymap.get_display_string("vertex_edit")
		tool_vertex.text = "Vertex"
		tool_vertex.tooltip_text = "Vertex Edit (%s)\nSelect and drag brush vertices" % key
	if mode_add and mode_subtract:
		var key = _keymap.get_display_string("toggle_operation")
		mode_add.tooltip_text = "Solid brush | Toggle Solid/Cutout: %s" % key
		mode_subtract.tooltip_text = "Cutout brush | Toggle Solid/Cutout: %s" % key
	if paint_mode:
		var key = _keymap.get_display_string("toggle_paint_mode")
		paint_mode.tooltip_text = "Toggle Paint Mode (%s)" % key
	if quick_play_btn:
		var key = _keymap.get_display_string("quick_play")
		quick_play_btn.tooltip_text = "Bake the level and run it (%s)" % key


func set_editor_interface(iface: EditorInterface) -> void:
	editor_interface = iface
	if editor_interface:
		editor_base_control = editor_interface.get_base_control()
	_apply_pro_styles()


func set_plugin(p: EditorPlugin) -> void:
	_plugin = p


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
	# Also record into the rich history browser
	if history_browser:
		history_browser.record_entry(action_name, version)


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
	return HFEditorTheme.resolve_stylebox(base_control, name, type_name)


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
	if paint_mode:
		_set_toolbar_button_icon(paint_mode, ["Paint", "Brush", "ToolPaint"], "Paint")
	if tool_extrude_up:
		_set_toolbar_button_icon(tool_extrude_up, ["MoveUp", "ArrowUp", "ToolMove"], "Up")
	if tool_extrude_down:
		_set_toolbar_button_icon(tool_extrude_down, ["MoveDown", "ArrowDown", "ToolMove"], "Down")
	if tool_vertex:
		_set_toolbar_button_icon(tool_vertex, ["EditPivot", "ToolMove"], "Vertex")
	if _command_palette_btn:
		_set_toolbar_button_icon(_command_palette_btn, ["Search", "Zoom"], "More")
	if _guide_btn:
		_set_toolbar_button_icon(_guide_btn, ["Info", "Help"], "Help")
	_apply_toolbar_tooltips()


func _apply_toolbar_tooltips() -> void:
	var draw_key := _keymap.get_display_string("tool_draw") if _keymap else "D"
	var select_key := _keymap.get_display_string("tool_select") if _keymap else "S"
	var operation_key := _keymap.get_display_string("toggle_operation") if _keymap else "Q"
	var paint_key := _keymap.get_display_string("toggle_paint_mode") if _keymap else "Shift+P"
	_set_tooltip(tool_draw, "Draw (%s)\nDrag: create brush | Alt: height-only" % draw_key)
	_set_tooltip(tool_select, "Select (%s)\nClick: select | Shift: add | Ctrl: toggle" % select_key)
	_set_tooltip(mode_add, "Solid brush\nDrag to add geometry | Toggle: %s" % operation_key)
	_set_tooltip(
		mode_subtract, "Cutout brush\nDrag through solids to carve | Toggle: %s" % operation_key
	)
	if paint_mode:
		_set_tooltip(
			paint_mode, "Paint Mode (%s)\nToggle between building and painting" % paint_key
		)
	if _command_palette_btn:
		_set_tooltip(_command_palette_btn, "Find any HammerForge action (Ctrl+K)")
	if _guide_btn:
		_set_tooltip(_guide_btn, "Restart the interactive getting-started guide")


func _set_tooltip(control: Control, text: String) -> void:
	HFTooltipText.set_tooltip(control, text)


func _apply_all_tooltips() -> void:
	HFTooltipText.apply_all(self)
	HFTooltipText.apply_snap_buttons(snap_buttons)


func _set_toolbar_button_icon(button: Button, icon_names: Array, fallback_text: String) -> void:
	HFEditorTheme.style_toolbar_button(editor_base_control, self, button, icon_names, fallback_text)


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
	var hammerforge_icon := HFShapeIcons.get_icon(shape_key)
	if hammerforge_icon:
		return hammerforge_icon
	var candidates = shape_icon_candidates.get(shape_key, [])
	return _find_editor_icon(candidates)


func _find_editor_icon(icon_names: Array) -> Texture2D:
	return HFEditorTheme.find_editor_icon(editor_base_control, self, icon_names)


func _has_editor_icon(icon_name: String) -> bool:
	return HFEditorTheme.has_editor_icon(editor_base_control, self, icon_name)


func _get_editor_icon(icon_name: String) -> Texture2D:
	return HFEditorTheme.get_editor_icon(editor_base_control, self, icon_name)


func _get_editor_color(color_name: String, fallback: Color) -> Color:
	return HFEditorTheme.get_editor_color(editor_base_control, self, color_name, fallback)


func _get_scene_history_id() -> int:
	return HFUndoNav.get_scene_history_id(undo_redo, level_root)


func _get_scene_undo_redo() -> UndoRedo:
	return HFUndoNav.get_scene_undo_redo(undo_redo, level_root)


func _get_undo_version() -> int:
	var ur := _get_scene_undo_redo()
	if ur:
		return ur.get_version()
	return history_entries.size()


func _refresh_history_list() -> void:
	if history_list:
		history_list.clear()
		var current_version = _get_undo_version()
		for entry in history_entries:
			var entry_name = str(entry.get("name", ""))
			var version = int(entry.get("version", 0))
			var prefix = "• " if version <= current_version else "  "
			history_list.add_item("%s%s" % [prefix, entry_name])
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


func _on_history_navigate(version: int) -> void:
	HFUndoNav.navigate_to_version(_get_scene_undo_redo(), version)


# ===========================================================================
# UI builders — construct Paint and Manage tabs with collapsible sections
# ===========================================================================


func _make_label_row(label_text: String, control: Control) -> HBoxContainer:
	return HFUIFactory.make_label_row(label_text, control)


func _make_spin(min_val: float, max_val: float, step_val: float, default_val: float) -> SpinBox:
	return HFUIFactory.make_spin(min_val, max_val, step_val, default_val)


func _make_check(label_text: String, default_on: bool = false) -> CheckBox:
	return HFUIFactory.make_check(label_text, default_on)


func _make_button(label_text: String) -> Button:
	return HFUIFactory.make_button(label_text)


func _build_paint_tab() -> void:
	var root_vbox = $Margin/VBox/MainTabs/Paint/PaintMargin/PaintVBox
	if not root_vbox:
		return
	var builder = PaintTabBuilder.new(self)
	builder.build(root_vbox)


func _build_entity_props_section() -> void:
	pass  # Now built by EntityTabBuilder


func _rebuild_entity_props(entity: Node3D) -> void:
	HFDockEntityHandler.rebuild_entity_props(self, entity)


func _clear_entity_props() -> void:
	HFDockEntityHandler.clear_entity_props(self)


func _on_entity_prop_changed(value: Variant, entity: Node3D, prop_name: String) -> void:
	HFDockEntityHandler.on_entity_prop_changed(self, value, entity, prop_name)


func _on_entity_prop_enum_changed(
	index: int, entity: Node3D, prop_name: String, enum_vals: Array
) -> void:
	HFDockEntityHandler.on_entity_prop_enum_changed(self, index, entity, prop_name, enum_vals)


func _on_entity_prop_vec3_changed(
	value: float, entity: Node3D, prop_name: String, axis_index: int
) -> void:
	HFDockEntityHandler.on_entity_prop_vec3_changed(self, value, entity, prop_name, axis_index)


func _can_edit_selected_entity(entity: Node3D) -> bool:
	return HFDockEntityHandler.can_edit_selected_entity(self, entity)


func _entity_prop_default(type_name: String, value: Variant) -> Variant:
	return HFDockEntityHandler.entity_prop_default(type_name, value)


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


func _build_displacement_bevel_section() -> void:
	var brush_vbox = $Margin/VBox/MainTabs/Brush/BrushMargin/BrushVBox
	if not brush_vbox:
		return
	# --- Displacement Section ---
	_disp_section = HFCollapsibleSection.create("Displacement", false)
	brush_vbox.add_child(_disp_section)
	var dbox: VBoxContainer = _disp_section.get_content()
	# Create / Destroy row
	var cd_row = HBoxContainer.new()
	_disp_create_btn = Button.new()
	_disp_create_btn.text = "Create"
	_disp_create_btn.tooltip_text = "Create displacement on selected quad face"
	_disp_create_btn.pressed.connect(_on_disp_create)
	cd_row.add_child(_disp_create_btn)
	_disp_destroy_btn = Button.new()
	_disp_destroy_btn.text = "Destroy"
	_disp_destroy_btn.tooltip_text = "Remove displacement from selected face"
	_disp_destroy_btn.pressed.connect(_on_disp_destroy)
	cd_row.add_child(_disp_destroy_btn)
	dbox.add_child(cd_row)
	# Power
	var pow_row = HBoxContainer.new()
	pow_row.add_child(_make_label("Power:"))
	_disp_power_spin = SpinBox.new()
	_disp_power_spin.min_value = 2
	_disp_power_spin.max_value = 4
	_disp_power_spin.step = 1
	_disp_power_spin.value = 3
	_disp_power_spin.tooltip_text = "Subdivision: 2=5x5, 3=9x9, 4=17x17"
	pow_row.add_child(_disp_power_spin)
	dbox.add_child(pow_row)
	# Elevation
	var elev_row = HBoxContainer.new()
	elev_row.add_child(_make_label("Elevation:"))
	_disp_elevation_spin = SpinBox.new()
	_disp_elevation_spin.min_value = 0.01
	_disp_elevation_spin.max_value = 100.0
	_disp_elevation_spin.step = 0.1
	_disp_elevation_spin.value = 1.0
	_disp_elevation_spin.tooltip_text = "Scale multiplier for displacement heights"
	_disp_elevation_spin.value_changed.connect(_on_disp_elevation_changed)
	elev_row.add_child(_disp_elevation_spin)
	dbox.add_child(elev_row)
	# Paint mode
	var pm_row = HBoxContainer.new()
	pm_row.add_child(_make_label("Paint:"))
	_disp_paint_mode_opt = OptionButton.new()
	_disp_paint_mode_opt.add_item("Raise", 0)
	_disp_paint_mode_opt.add_item("Lower", 1)
	_disp_paint_mode_opt.add_item("Smooth", 2)
	_disp_paint_mode_opt.add_item("Noise", 3)
	_disp_paint_mode_opt.add_item("Alpha", 4)
	_disp_paint_mode_opt.tooltip_text = "Displacement paint brush mode"
	pm_row.add_child(_disp_paint_mode_opt)
	dbox.add_child(pm_row)
	# Radius / Strength
	var rs_row = HBoxContainer.new()
	rs_row.add_child(_make_label("R:"))
	_disp_radius_spin = SpinBox.new()
	_disp_radius_spin.min_value = 0.5
	_disp_radius_spin.max_value = 64.0
	_disp_radius_spin.step = 0.5
	_disp_radius_spin.value = 4.0
	_disp_radius_spin.tooltip_text = "Displacement paint brush radius"
	rs_row.add_child(_disp_radius_spin)
	rs_row.add_child(_make_label("S:"))
	_disp_strength_spin = SpinBox.new()
	_disp_strength_spin.min_value = 0.01
	_disp_strength_spin.max_value = 10.0
	_disp_strength_spin.step = 0.05
	_disp_strength_spin.value = 0.5
	_disp_strength_spin.tooltip_text = "Displacement paint brush strength"
	rs_row.add_child(_disp_strength_spin)
	dbox.add_child(rs_row)
	# Smooth / Noise / Sew buttons
	var ops_row = HBoxContainer.new()
	_disp_smooth_btn = Button.new()
	_disp_smooth_btn.text = "Smooth"
	_disp_smooth_btn.tooltip_text = "Smooth entire displacement surface"
	_disp_smooth_btn.pressed.connect(_on_disp_smooth)
	ops_row.add_child(_disp_smooth_btn)
	_disp_noise_btn = Button.new()
	_disp_noise_btn.text = "Noise"
	_disp_noise_btn.tooltip_text = "Apply noise to displacement"
	_disp_noise_btn.pressed.connect(_on_disp_noise)
	ops_row.add_child(_disp_noise_btn)
	_disp_sew_btn = Button.new()
	_disp_sew_btn.text = "Sew"
	_disp_sew_btn.tooltip_text = "Sew adjacent displacements sharing a sew group"
	_disp_sew_btn.pressed.connect(_on_disp_sew)
	ops_row.add_child(_disp_sew_btn)
	dbox.add_child(ops_row)
	# Sew group
	var sg_row = HBoxContainer.new()
	sg_row.add_child(_make_label("Sew Group:"))
	_disp_sew_group_spin = SpinBox.new()
	_disp_sew_group_spin.min_value = -1
	_disp_sew_group_spin.max_value = 99
	_disp_sew_group_spin.step = 1
	_disp_sew_group_spin.value = -1
	_disp_sew_group_spin.tooltip_text = "Sew group ID (-1 = none)"
	_disp_sew_group_spin.value_changed.connect(_on_disp_sew_group_changed)
	sg_row.add_child(_disp_sew_group_spin)
	dbox.add_child(sg_row)
	_register_section(_disp_section, "Displacement")
	# --- Bevel Section ---
	_bevel_section = HFCollapsibleSection.create("Bevel", false)
	brush_vbox.add_child(_bevel_section)
	var bbox: VBoxContainer = _bevel_section.get_content()
	# Edge Bevel
	var eb_row = HBoxContainer.new()
	_bevel_edge_btn = Button.new()
	_bevel_edge_btn.text = "Bevel Edge"
	_bevel_edge_btn.tooltip_text = "Bevel the selected edge (vertex mode, edge sub-mode)"
	_bevel_edge_btn.pressed.connect(_on_bevel_edge)
	eb_row.add_child(_bevel_edge_btn)
	bbox.add_child(eb_row)
	# Segments / Radius
	var sr_row = HBoxContainer.new()
	sr_row.add_child(_make_label("Segments:"))
	_bevel_segments_spin = SpinBox.new()
	_bevel_segments_spin.min_value = 1
	_bevel_segments_spin.max_value = 16
	_bevel_segments_spin.step = 1
	_bevel_segments_spin.value = 2
	_bevel_segments_spin.tooltip_text = "Number of bevel segments (1 = chamfer)"
	sr_row.add_child(_bevel_segments_spin)
	sr_row.add_child(_make_label("Radius:"))
	_bevel_radius_spin = SpinBox.new()
	_bevel_radius_spin.min_value = 0.1
	_bevel_radius_spin.max_value = 64.0
	_bevel_radius_spin.step = 0.1
	_bevel_radius_spin.value = 2.0
	_bevel_radius_spin.tooltip_text = "Bevel radius (how far the bevel extends)"
	sr_row.add_child(_bevel_radius_spin)
	bbox.add_child(sr_row)
	# Face Inset
	var fi_lbl = Label.new()
	fi_lbl.text = "Face Inset"
	bbox.add_child(fi_lbl)
	var fi_row = HBoxContainer.new()
	fi_row.add_child(_make_label("Inset:"))
	_bevel_inset_dist_spin = SpinBox.new()
	_bevel_inset_dist_spin.min_value = 0.1
	_bevel_inset_dist_spin.max_value = 64.0
	_bevel_inset_dist_spin.step = 0.1
	_bevel_inset_dist_spin.value = 2.0
	_bevel_inset_dist_spin.tooltip_text = "Distance to inset the face boundary"
	fi_row.add_child(_bevel_inset_dist_spin)
	fi_row.add_child(_make_label("Height:"))
	_bevel_inset_height_spin = SpinBox.new()
	_bevel_inset_height_spin.min_value = -64.0
	_bevel_inset_height_spin.max_value = 64.0
	_bevel_inset_height_spin.step = 0.1
	_bevel_inset_height_spin.value = 0.0
	_bevel_inset_height_spin.tooltip_text = "Extrude the inset face along its normal (0 = flat inset)"
	fi_row.add_child(_bevel_inset_height_spin)
	bbox.add_child(fi_row)
	_bevel_inset_btn = Button.new()
	_bevel_inset_btn.text = "Inset Face"
	_bevel_inset_btn.tooltip_text = "Inset the selected face and create connecting side faces"
	_bevel_inset_btn.pressed.connect(_on_bevel_inset)
	bbox.add_child(_bevel_inset_btn)
	_register_section(_bevel_section, "Bevel")


func _make_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	return lbl


# --- Displacement callbacks ---


func _get_selected_face_info() -> Dictionary:
	# Returns {brush_id, face_index} for the first selected face, or empty dict.
	# Face selection lives in level_root.face_selection: {brush_key: [face_indices]}.
	if not level_root:
		return {}
	if not level_root.get("face_selection") is Dictionary:
		return {}
	var fs: Dictionary = level_root.face_selection
	for key in fs.keys():
		var indices: Array = fs.get(key, [])
		if indices.is_empty():
			continue
		var brush_id: String = str(key)
		var brush: Node3D = (
			level_root._find_brush_by_key(brush_id)
			if level_root.has_method("_find_brush_by_key")
			else null
		)
		if not brush:
			continue
		var fi: int = int(indices[0])
		if fi >= 0 and fi < brush.faces.size():
			return {"brush_id": brush.brush_id, "face_index": fi}
	return {}


func _selected_face_has_displacement(info: Dictionary) -> bool:
	if info.is_empty() or not level_root:
		return false
	var brush: Node3D = level_root.find_brush_by_id(info["brush_id"])
	if not brush:
		return false
	var fi: int = info["face_index"]
	if fi < 0 or fi >= brush.faces.size():
		return false
	return brush.faces[fi].displacement != null


## Execute a LevelRoot method that returns bool, wrapping in undo + history
## only when the call succeeds. Returns the bool result.
func _try_undoable_action(action_name: String, method_name: String, args: Array = []) -> bool:
	if not level_root or not level_root.has_method(method_name):
		return false
	var pre_state: Dictionary = (
		level_root.capture_state() if level_root.has_method("capture_state") else {}
	)
	var ok: bool = level_root.callv(method_name, args)
	if ok and undo_redo and not pre_state.is_empty():
		var post_state: Dictionary = level_root.capture_state()
		undo_redo.create_action(action_name, 0, null, false)
		undo_redo.add_do_method(level_root, "restore_state", post_state)
		undo_redo.add_undo_method(level_root, "restore_state", pre_state)
		undo_redo.commit_action(false)
		record_history(action_name)
	return ok


func _on_disp_create() -> void:
	HFDockBrushHandler.on_disp_create(self)


func _on_disp_destroy() -> void:
	HFDockBrushHandler.on_disp_destroy(self)


func _on_disp_elevation_changed(value: float) -> void:
	HFDockBrushHandler.on_disp_elevation_changed(self, value)


func _on_disp_smooth() -> void:
	HFDockBrushHandler.on_disp_smooth(self)


func _on_disp_noise() -> void:
	HFDockBrushHandler.on_disp_noise(self)


func _on_disp_sew() -> void:
	HFDockBrushHandler.on_disp_sew(self)


func _on_disp_sew_group_changed(value: float) -> void:
	HFDockBrushHandler.on_disp_sew_group_changed(self, value)


func _on_bevel_edge() -> void:
	HFDockBrushHandler.on_bevel_edge(self)


func _on_bevel_inset() -> void:
	HFDockBrushHandler.on_bevel_inset(self)


func _ready():
	# --- Build programmatic tabs first ---
	_build_paint_tab()
	_build_manage_tab()
	_build_entity_io_section()
	_build_selection_tools_section()
	_build_displacement_bevel_section()

	# --- Toolbar setup ---
	var tool_group = ButtonGroup.new()
	tool_group.pressed.connect(_on_builtin_tool_pressed)
	tool_draw.toggle_mode = true
	tool_select.toggle_mode = true
	tool_draw.button_group = tool_group
	tool_select.button_group = tool_group
	tool_draw.button_pressed = true
	tool_draw.text = "Draw"
	tool_draw.tooltip_text = "Draw (D)"
	tool_select.text = "Select"
	tool_select.tooltip_text = "Select (S)"
	if paint_mode:
		paint_mode.toggle_mode = true
		paint_mode.button_pressed = false
		paint_mode.toggled.connect(_on_paint_mode_toggled)
	if main_tabs:
		main_tabs.tab_changed.connect(_on_main_tab_changed)

	# Extrude tool buttons (added programmatically to toolbar)
	var toolbar = tool_draw.get_parent()
	if toolbar:
		_edit_tools_separator = VSeparator.new()
		_edit_tools_separator.visible = false
		toolbar.add_child(_edit_tools_separator)

		tool_extrude_up = Button.new()
		tool_extrude_up.toggle_mode = true
		tool_extrude_up.button_group = tool_group
		tool_extrude_up.flat = true
		tool_extrude_up.focus_mode = Control.FOCUS_NONE
		tool_extrude_up.text = "Up"
		tool_extrude_up.tooltip_text = "Extrude Up (U)\nClick face + drag to extrude upward"
		tool_extrude_up.visible = false
		toolbar.add_child(tool_extrude_up)

		tool_extrude_down = Button.new()
		tool_extrude_down.toggle_mode = true
		tool_extrude_down.button_group = tool_group
		tool_extrude_down.flat = true
		tool_extrude_down.focus_mode = Control.FOCUS_NONE
		tool_extrude_down.text = "Down"
		tool_extrude_down.tooltip_text = "Extrude Down (J)\nClick face + drag to extrude downward"
		tool_extrude_down.visible = false
		toolbar.add_child(tool_extrude_down)

		_vertex_tool_separator = VSeparator.new()
		_vertex_tool_separator.visible = false
		toolbar.add_child(_vertex_tool_separator)

		tool_vertex = Button.new()
		tool_vertex.toggle_mode = true
		tool_vertex.flat = true
		tool_vertex.focus_mode = Control.FOCUS_NONE
		tool_vertex.text = "Vertex"
		tool_vertex.tooltip_text = "Vertex Edit (V)\nSelect and drag brush vertices"
		tool_vertex.visible = false
		tool_vertex.toggled.connect(_on_vertex_tool_toggled)
		toolbar.add_child(tool_vertex)

	# --- Discoverability buttons ---
	if toolbar:
		var help_sep = VSeparator.new()
		toolbar.add_child(help_sep)

		_command_palette_btn = Button.new()
		_command_palette_btn.text = "More"
		_command_palette_btn.tooltip_text = "Find any HammerForge action (Ctrl+K)"
		_command_palette_btn.flat = true
		_command_palette_btn.focus_mode = Control.FOCUS_NONE
		_command_palette_btn.pressed.connect(func(): command_palette_requested.emit())
		toolbar.add_child(_command_palette_btn)

		_guide_btn = Button.new()
		_guide_btn.text = "Help"
		_guide_btn.tooltip_text = "Restart the interactive getting-started guide"
		_guide_btn.flat = true
		_guide_btn.focus_mode = Control.FOCUS_NONE
		_guide_btn.pressed.connect(_restart_tutorial)
		toolbar.add_child(_guide_btn)

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
	_setup_simplified_workflow()

	# --- Connect builder signals ---
	PaintTabBuilder.new(self).connect_signals()
	ManageTabBuilder.new(self).connect_signals()
	SelectionToolsBuilder.new(self).connect_signals()
	EntityTabBuilder.new(self).connect_signals()

	# --- Connect signals (brush tab — non-builder) ---
	grid_snap.value_changed.connect(_on_grid_snap_value_changed)
	if create_entity_btn:
		create_entity_btn.pressed.connect(_on_create_entity)
	if create_starter_btn:
		create_starter_btn.pressed.connect(_on_create_level_root.bind(true))
	if create_empty_root_btn:
		create_empty_root_btn.pressed.connect(_on_create_level_root.bind(false))
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
	if paint_mode and paint_mode.button_pressed:
		_syncing_paint_tab = true
		paint_mode.set_pressed_no_signal(false)
		highlight_tab("Brush")
		_syncing_paint_tab = false
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


func _on_face_select_mode_toggled(enabled: bool) -> void:
	face_select_mode_toggled.emit(enabled)


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
	_update_mode_indicator(mode_name)


## Update the prominent mode indicator with structured info.
## stage_hint: e.g. "Step 1/2: Draw base", numeric: e.g. "64"
func set_mode_indicator(mode_name: String, stage_hint: String = "", numeric: String = "") -> void:
	var display = mode_name
	if stage_hint != "":
		display += "  —  " + stage_hint
	if numeric != "":
		display += "  [" + numeric + "]"
	_update_mode_indicator_text(display, mode_name)


func _update_mode_indicator(mode_name: String) -> void:
	var instruction := mode_name
	if mode_name.begins_with("Draw"):
		instruction = "Draw - drag in the 3D viewport"
	elif mode_name.begins_with("Select"):
		instruction = "Select - click geometry to edit"
	elif mode_name.begins_with("Extrude"):
		instruction = "Extrude - click a face, then drag"
	elif mode_name.begins_with("Paint"):
		instruction = "Paint - drag across the level"
	elif mode_name.begins_with("Vertex"):
		instruction = "Vertex - drag a highlighted point"
	_update_mode_indicator_text(instruction, mode_name)


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
	# `count` is kept for API compatibility; selection labels are derived from
	# actual node types so cameras, entities, and LevelRoot are never called brushes.
	var counts := _get_selection_counts(_selection_nodes)
	var brush_count: int = counts["brushes"]
	var entity_count: int = counts["entities"]
	var other_count: int = counts["other"]
	var face_count := _count_selected_faces()
	var parts: PackedStringArray = []
	if brush_count > 0:
		parts.append("%d brush%s" % [brush_count, "" if brush_count == 1 else "es"])
	if entity_count > 0:
		parts.append("%d entit%s" % [entity_count, "y" if entity_count == 1 else "ies"])
	if other_count > 0:
		parts.append("%d other" % other_count)
	if face_count > 0:
		parts.append("%d face%s" % [face_count, "" if face_count == 1 else "s"])
	if parts.is_empty():
		selection_label.text = ""
	else:
		selection_label.text = "Sel: " + ", ".join(parts)
	if _clear_sel_btn:
		_clear_sel_btn.visible = not parts.is_empty()


func _get_selection_counts(nodes: Array) -> Dictionary:
	var brushes := 0
	var entities := 0
	var other := 0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node is DraftBrush:
			brushes += 1
		elif node is DraftEntity or (level_root and level_root.is_entity_node(node)):
			entities += 1
		else:
			other += 1
	return {"brushes": brushes, "entities": entities, "other": other}


## Classify the editor selection without depending on the editor plugin. A node
## is managed only when the active LevelRoot recognizes it as one of its own
## brushes/entities; class names and metadata alone are not sufficient.
func _classify_selection_scope(nodes: Array) -> int:
	var has_managed := false
	var has_native := false
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var is_managed := false
		if level_root:
			is_managed = level_root.is_brush_node(node) or level_root.is_entity_node(node)
		if is_managed:
			has_managed = true
		else:
			has_native = true
		if has_managed and has_native:
			return DockSelectionScope.MIXED
	if has_managed:
		return DockSelectionScope.MANAGED
	if has_native:
		return DockSelectionScope.NATIVE
	return DockSelectionScope.EMPTY


func _current_selection_scope() -> int:
	return _classify_selection_scope(_selection_nodes)


func _get_managed_selection_counts(nodes: Array) -> Dictionary:
	var brushes := 0
	var entities := 0
	if not level_root:
		return {"brushes": brushes, "entities": entities, "total": 0}
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if level_root.is_brush_node(node):
			brushes += 1
		elif level_root.is_entity_node(node):
			entities += 1
	return {"brushes": brushes, "entities": entities, "total": brushes + entities}


func _first_selected_brush() -> Node:
	if not level_root:
		return null
	for node in _selection_nodes:
		if is_instance_valid(node) and level_root.is_brush_node(node):
			return node
	return null


func _first_selected_entity() -> Node:
	if not level_root:
		return null
	for node in _selection_nodes:
		if is_instance_valid(node) and level_root.is_entity_node(node):
			return node
	return null


## Fail closed before a dock action can silently filter the selection. Most
## actions accept any all-HammerForge selection, while brush/entity-specific
## handlers opt into a stricter all-members requirement. Scatter is the one
## dock workflow that intentionally consumes ordinary Node3D positions.
func _guard_selection_action(
	action_name: String,
	requirement: int = DockSelectionRequirement.MANAGED,
) -> bool:
	var scope := _current_selection_scope()
	if scope == DockSelectionScope.MIXED:
		var mixed_message := "%s: %s" % [action_name, MIXED_SELECTION_MESSAGE]
		show_toast(mixed_message, 1)
		return false
	if (
		scope == DockSelectionScope.NATIVE
		and requirement != DockSelectionRequirement.NATIVE_ALLOWED
	):
		var native_message := (
			"%s requires HammerForge brushes or entities; ordinary Godot nodes were left unchanged."
			% action_name
		)
		show_toast(native_message, 1)
		return false
	if scope == DockSelectionScope.MANAGED:
		var counts := _get_managed_selection_counts(_selection_nodes)
		if requirement == DockSelectionRequirement.BRUSHES_ONLY and int(counts["entities"]) > 0:
			show_toast(
				"%s requires a brush-only selection; entities were left unchanged." % action_name, 1
			)
			return false
		if requirement == DockSelectionRequirement.ENTITIES_ONLY and int(counts["brushes"]) > 0:
			show_toast(
				"%s requires an entity-only selection; brushes were left unchanged." % action_name,
				1
			)
			return false
	return true


func set_selection_nodes(nodes: Array) -> void:
	_selection_nodes = nodes
	var selection_scope := _current_selection_scope()
	var managed_counts := _get_managed_selection_counts(_selection_nodes)
	var has_brush_selection := (
		selection_scope == DockSelectionScope.MANAGED
		and int(managed_counts["brushes"]) > 0
		and int(managed_counts["entities"]) == 0
	)
	# Show/hide selection tools in Brush tab
	if _selection_tools_section:
		_selection_tools_section.visible = has_brush_selection
	# Keep specialist edit modes out of the primary toolbar until they can be used.
	if _edit_tools_separator:
		_edit_tools_separator.visible = has_brush_selection
	if tool_extrude_up:
		tool_extrude_up.visible = has_brush_selection
	if tool_extrude_down:
		tool_extrude_down.visible = has_brush_selection
	if _vertex_tool_separator:
		_vertex_tool_separator.visible = has_brush_selection
	if tool_vertex:
		tool_vertex.visible = has_brush_selection
	set_selection_count(nodes.size())
	# Mark hints dirty so selection-dependent buttons update
	_hints_dirty = true
	_update_context_hints()
	_update_disabled_hints()
	# Refresh Entity I/O list and property form when selection changes
	var selected_entity: Node = null
	var entity_only_selection := (
		selection_scope == DockSelectionScope.MANAGED
		and int(managed_counts["entities"]) > 0
		and int(managed_counts["brushes"]) == 0
	)
	if level_root and entity_only_selection:
		for node in nodes:
			if level_root.is_entity_node(node):
				selected_entity = node
				break
	if selected_entity:
		_refresh_io_list(selected_entity)
		_rebuild_entity_props(selected_entity)
		if _entity_io_section:
			_entity_io_section.visible = true
		if _io_wiring_section:
			_io_wiring_section.visible = true
		if _io_wiring_panel:
			_io_wiring_panel.set_source_entity(selected_entity)
	else:
		if io_list:
			io_list.clear()
		_clear_entity_props()
		if _entity_io_section:
			_entity_io_section.visible = false
		if _io_wiring_section:
			_io_wiring_section.visible = false
		if _io_wiring_panel:
			_io_wiring_panel.set_source_entity(null)


func _build_snap_mode_buttons() -> void:
	# Find the GridRow parent to add snap mode row after it
	var grid_row = grid_snap.get_parent() if grid_snap else null
	if not grid_row or not grid_row.get_parent():
		return
	var parent = grid_row.get_parent()
	var idx = grid_row.get_index() + 1
	var row = HBoxContainer.new()
	row.name = "SnapTargets"
	_snap_mode_row = row
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
	snap_edge_btn = Button.new()
	snap_edge_btn.text = "E"
	snap_edge_btn.tooltip_text = "Edge snap (brush edge midpoints)"
	snap_edge_btn.toggle_mode = true
	snap_edge_btn.custom_minimum_size.x = 32
	snap_edge_btn.toggled.connect(_on_snap_mode_toggled.bind(8))
	row.add_child(snap_edge_btn)
	snap_perp_btn = Button.new()
	snap_perp_btn.text = "P"
	snap_perp_btn.tooltip_text = "Perpendicular snap (drop onto brush edges)"
	snap_perp_btn.toggle_mode = true
	snap_perp_btn.custom_minimum_size.x = 32
	snap_perp_btn.toggled.connect(_on_snap_mode_toggled.bind(16))
	row.add_child(snap_perp_btn)
	parent.add_child(row)
	parent.move_child(row, idx)
	# Axis Lock row
	var axis_row = HBoxContainer.new()
	axis_row.name = "AxisLocks"
	_axis_lock_row = axis_row
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
	grid_snap_applied.emit(value)


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


func _on_power_user_overlays_toggled(pressed: bool) -> void:
	_save_user_pref("power_user_overlays", pressed)
	power_user_overlays_changed.emit(pressed)
	_log("Power-user overlays: %s" % ("on" if pressed else "off"))


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
	if not _guard_selection_action("Save Prefab"):
		return
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in _selection_nodes:
		if not is_instance_valid(node):
			continue
		if level_root.is_brush_node(node):
			brush_nodes.append(node)
		elif level_root.is_entity_node(node):
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
	if not _guard_selection_action("Save Linked Prefab"):
		return
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in _selection_nodes:
		if not is_instance_valid(node):
			continue
		if level_root.is_brush_node(node):
			brush_nodes.append(node)
		elif level_root.is_entity_node(node):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	var path: String = level_root.prefab_system.quick_save_prefab(
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
	if not _guard_selection_action("Add Prefab Variant"):
		return
	var prefab = HFPrefabType.load_from_file(prefab_path)
	if not prefab:
		return
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in _selection_nodes:
		if not is_instance_valid(node):
			continue
		if level_root.is_brush_node(node):
			brush_nodes.append(node)
		elif level_root.is_entity_node(node):
			entity_nodes.append(node)
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return
	prefab.add_variant_from_selection(
		variant_name, level_root.brush_system, level_root.entity_system, brush_nodes, entity_nodes
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
	HFConsoleLog.shared().debug(message, "dock")
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


func _commit_precomputed_state_action(
	action_name: String,
	before_state: Dictionary,
	after_state: Dictionary,
	before_baked: PackedScene,
	after_baked: PackedScene
) -> void:
	# Async work has already completed. Register two immutable synchronous
	# snapshots so Undo and Redo never resume a coroutine or consume transient
	# cutter references.
	if undo_redo:
		undo_redo.create_action(action_name, 0, null, false)
		undo_redo.add_do_method(
			level_root, "restore_state_with_baked_snapshot", after_state, after_baked
		)
		undo_redo.add_undo_method(
			level_root, "restore_state_with_baked_snapshot", before_state, before_baked
		)
		undo_redo.commit_action(false)
	record_history(action_name)


func _on_bake():
	await HFDockManageHandler.on_bake(self)


func _on_bake_dry_run() -> void:
	HFDockManageHandler.on_bake_dry_run(self)


func _get_bake_preview_mode() -> int:
	return HFDockManageHandler.get_bake_preview_mode(self)


func _on_bake_selected() -> void:
	await HFDockManageHandler.on_bake_selected(self)


func _on_bake_changed() -> void:
	await HFDockManageHandler.on_bake_changed(self)


func _on_bake_check_issues() -> void:
	HFDockManageHandler.on_bake_check_issues(self)


func _update_bake_estimate() -> void:
	HFDockManageHandler.update_bake_estimate(self)


func _on_validate_level() -> void:
	HFDockManageHandler.on_validate_level(self)


func _on_validate_fix() -> void:
	HFDockManageHandler.on_validate_fix(self)


func _on_clear():
	_log("Clear brushes requested")
	_commit_state_action("Clear Brushes", "clear_brushes")


func _on_new_level():
	_log("New HammerForge Level requested")
	_commit_state_action("New HammerForge Level", "create_new_level")
	show_toast("New level created — floor, sun, and player spawn added", 0)


func _on_create_level_root(create_starter: bool) -> void:
	if not _plugin or not _plugin.has_method("ensure_level_root"):
		show_toast("Open or create a 3D scene first", 2)
		return
	var root = _plugin.call("ensure_level_root")
	if not root:
		show_toast("Open or create a 3D scene first", 2)
		return
	level_root = root
	if create_starter:
		_on_new_level()
	else:
		show_toast("Empty LevelRoot created - Draw + Solid is ready", 0)
	_hints_dirty = true


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
	if not level_root or not _can_start_bake("Commit Cuts"):
		return
	var before_state: Dictionary = level_root.capture_state()
	var before_baked: PackedScene = level_root.capture_baked_geometry_snapshot()
	selection_clear_requested.emit()
	if editor_interface:
		var selection = editor_interface.get_selection()
		if selection:
			selection.clear()
	_set_bake_buttons_disabled(true)
	var succeeded: bool = await level_root.prepare_commit_cuts()
	_set_bake_buttons_disabled(false)
	if succeeded:
		# Finalize once, then snapshot the exact successful state. Redo restores
		# this snapshot; it never consumes _prepared_commit_cutters a second time.
		level_root.finalize_commit_cuts()
		var after_state: Dictionary = level_root.capture_state()
		var after_baked: PackedScene = level_root.capture_baked_geometry_snapshot()
		_commit_precomputed_state_action(
			"Commit Cuts", before_state, after_state, before_baked, after_baked
		)


func _on_restore_cuts():
	_log("Restore committed cuts requested")
	_commit_state_action("Restore Committed Cuts", "restore_committed_cuts")


func _on_hollow() -> void:
	HFDockBrushHandler.on_hollow(self)


func _on_move_to_floor() -> void:
	HFDockBrushHandler.on_move_to_floor(self)


func _on_move_to_ceiling() -> void:
	HFDockBrushHandler.on_move_to_ceiling(self)


func _on_create_duplicate_array() -> void:
	HFDockBrushHandler.on_create_duplicate_array(self)


func _on_remove_duplicate_array() -> void:
	HFDockBrushHandler.on_remove_duplicate_array(self)


func _on_tie_entity() -> void:
	HFDockBrushHandler.on_tie_entity(self)


func _on_untie_entity() -> void:
	HFDockBrushHandler.on_untie_entity(self)


func _on_justify(mode: String) -> void:
	if not level_root:
		return
	if not _guard_selection_action("Justify UV", DockSelectionRequirement.BRUSHES_ONLY):
		return
	var treat_as_one = justify_treat_as_one.button_pressed if justify_treat_as_one else false
	_commit_state_action("Justify UV (%s)" % mode, "justify_selected_faces", [mode, treat_as_one])


func get_hollow_thickness() -> float:
	return HFDockBrushHandler.get_hollow_thickness(self)


func _on_create_entity() -> void:
	HFDockEntityHandler.on_create_entity(self)


func _focus_entity_selection(entity: Node) -> void:
	HFDockEntityHandler.focus_entity_selection(self, entity)


func _get_default_entity_definition() -> Dictionary:
	return HFDockEntityHandler.get_default_entity_definition(self)


func _connect_root_signals() -> void:
	HFDockConnections.connect_root(self)


func _disconnect_root_signals() -> void:
	HFDockConnections.disconnect_root(self)


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
	grid_snap_applied.emit(value)


func _on_root_paint_layer_changed(_index: int) -> void:
	_sync_paint_layers_from_root()


func _on_root_material_list_changed() -> void:
	_sync_materials_from_root()


func _on_root_selection_for_surface(_brush_ids: Array) -> void:
	_sync_surface_paint_from_root()


func _on_root_face_selection_changed() -> void:
	_sync_surface_paint_from_root()
	set_selection_count(_selection_nodes.size())
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
	if bake_unwrap_uv0 and _root_has_property("bake_unwrap_uv0"):
		bake_unwrap_uv0.button_pressed = bool(connected_root.get("bake_unwrap_uv0"))
	if bake_lightmap_uv2 and _root_has_property("bake_lightmap_uv2"):
		bake_lightmap_uv2.button_pressed = bool(connected_root.get("bake_lightmap_uv2"))
	if bake_lightmap_texel and _root_has_property("bake_lightmap_texel_size"):
		bake_lightmap_texel.value = float(connected_root.get("bake_lightmap_texel_size"))
	if bake_visible_only_check and _root_has_property("bake_visible_only"):
		bake_visible_only_check.button_pressed = bool(connected_root.get("bake_visible_only"))
	if bake_use_multimesh_check and _root_has_property("bake_use_multimesh"):
		bake_use_multimesh_check.button_pressed = bool(connected_root.get("bake_use_multimesh"))
	if bake_use_atlas_check and _root_has_property("bake_use_atlas"):
		bake_use_atlas_check.button_pressed = bool(connected_root.get("bake_use_atlas"))
	if bake_auto_connectors_check and _root_has_property("bake_auto_connectors"):
		bake_auto_connectors_check.button_pressed = bool(connected_root.get("bake_auto_connectors"))
	if bake_generate_occluders_check and _root_has_property("bake_generate_occluders"):
		bake_generate_occluders_check.button_pressed = bool(
			connected_root.get("bake_generate_occluders")
		)
	if bake_occluder_min_area_spin and _root_has_property("bake_occluder_min_area"):
		bake_occluder_min_area_spin.value = float(connected_root.get("bake_occluder_min_area"))
	if bake_connector_mode_opt and _root_has_property("bake_connector_mode"):
		bake_connector_mode_opt.select(int(connected_root.get("bake_connector_mode")))
	if bake_connector_stair_height_spin and _root_has_property("bake_connector_stair_height"):
		bake_connector_stair_height_spin.value = float(
			connected_root.get("bake_connector_stair_height")
		)
	if bake_connector_width_spin and _root_has_property("bake_connector_width"):
		bake_connector_width_spin.value = int(connected_root.get("bake_connector_width"))
	if bake_chunk_size_spin and _root_has_property("bake_chunk_size"):
		bake_chunk_size_spin.value = float(connected_root.get("bake_chunk_size"))
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
	HFDockManageHandler.on_bake_started(self)


func _on_bake_progress(value: float, label: String) -> void:
	HFDockManageHandler.on_bake_progress(self, value, label)


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


func _on_hflevel_save_completed(path: String) -> void:
	_set_status("Saved .hflevel", false, 3.0)
	show_toast("Saved: %s" % path.get_file(), 0)
	if _user_prefs:
		_user_prefs.add_recent_file(path)
		_user_prefs.save()


func _on_hflevel_save_failed(path: String, error_message: String) -> void:
	push_warning("HammerForge save failed for %s: %s" % [path, error_message])
	_set_status("Failed to save .hflevel: %s" % path, true, 5.0)
	show_toast("Save failed: %s" % path, 2)


func _on_root_user_message(text: String, level: int) -> void:
	show_toast(text, level)
	# Toasts fade. The Console's log is where the same message stays readable
	# after the fact, which is the only place a failed bake can be reconstructed
	# from. LevelRoot's levels are 0 info / 1 warning / 2 error, matching
	# HFConsoleLog's first three.
	HFConsoleLog.shared().append(clampi(level, 0, 2), text, "level")


func _on_bake_finished(success: bool) -> void:
	HFDockManageHandler.on_bake_finished(self, success)


func _set_bake_buttons_disabled(disabled: bool) -> void:
	HFDockManageHandler.set_bake_buttons_disabled(self, disabled)


func _can_start_bake(action_label: String) -> bool:
	return HFDockManageHandler.can_start_bake(self, action_label)


func _on_quick_play() -> void:
	await HFDockManageHandler.on_quick_play(self)


func _on_quick_play_from_camera() -> void:
	await HFDockManageHandler.on_quick_play_from_camera(self)


func _on_quick_play_selected_area() -> void:
	await HFDockManageHandler.on_quick_play_selected_area(self)


func _restore_cordon_state(enabled: bool, bounds: AABB) -> void:
	HFDockManageHandler.restore_cordon_state(self, enabled, bounds)


func _on_export_playtest() -> void:
	await HFDockManageHandler.on_export_playtest(self)


func _show_spawn_fix_dialog(spawn: Node3D, validation: Dictionary, mask: int) -> void:
	HFDockManageHandler.show_spawn_fix_dialog(self, spawn, validation, mask)


func _record_spawn_create_undo(before_state: Dictionary) -> void:
	HFDockManageHandler.record_spawn_create_undo(self, before_state)


func _record_spawn_move_undo(spawn: Node3D, old_pos: Vector3, new_pos: Vector3) -> void:
	HFDockManageHandler.record_spawn_move_undo(self, spawn, old_pos, new_pos)


func _restore_spawn(spawn: Node3D, pos: Vector3, angle_deg: float) -> void:
	HFDockManageHandler.restore_spawn(spawn, pos, angle_deg)


func _on_spawn_validate() -> void:
	await HFDockManageHandler.on_spawn_validate(self)


func _on_spawn_auto_create() -> void:
	HFDockManageHandler.on_spawn_auto_create(self)


func _on_show_spawn_debug_toggled(enabled: bool) -> void:
	await HFDockManageHandler.on_show_spawn_debug_toggled(self, enabled)


func _notify_running_instances() -> void:
	HFDockManageHandler.notify_running_instances(self)


func _warn_missing_dependencies() -> void:
	HFDockManageHandler.warn_missing_dependencies(self)


func _run_validation(auto_fix: bool) -> void:
	HFDockManageHandler.run_validation(self, auto_fix)


func _update_perf_panel() -> void:
	if not perf_brushes_value or not perf_paint_mem_value or not perf_bake_chunks_value:
		return
	if not level_root:
		perf_brushes_value.text = "0"
		if perf_entity_value:
			perf_entity_value.text = "0"
		if perf_vertex_value:
			perf_vertex_value.text = "0"
		perf_paint_mem_value.text = "0 KB"
		perf_bake_chunks_value.text = "0"
		if perf_bake_time_value:
			perf_bake_time_value.text = "-"
		if perf_chunk_rec_value:
			perf_chunk_rec_value.text = "-"
		if perf_health_label:
			perf_health_label.text = "-"
			perf_health_label.remove_theme_color_override("font_color")
		if perf_brush_bar:
			perf_brush_bar.value = 0
		return

	var brush_count := int(level_root.get_live_brush_count())
	perf_brushes_value.text = str(brush_count)

	if perf_entity_value:
		perf_entity_value.text = str(level_root.get_entity_count())

	if perf_vertex_value:
		perf_vertex_value.text = str(level_root.get_total_vertex_estimate())

	var bytes = level_root.get_paint_memory_bytes()
	perf_paint_mem_value.text = _format_bytes(bytes)
	perf_bake_chunks_value.text = str(level_root.get_bake_chunk_count())

	if perf_bake_time_value:
		var ms = int(level_root.get_last_bake_duration_ms())
		perf_bake_time_value.text = ("%d ms" % ms) if ms > 0 else "-"

	if perf_chunk_rec_value:
		var rec: float = level_root.get_recommended_chunk_size()
		perf_chunk_rec_value.text = ("%.0f" % rec) if rec > 0.0 else "N/A"

	# Brush count progress bar
	if perf_brush_bar:
		perf_brush_bar.value = mini(brush_count, 200)

	# Health summary with color coding
	if perf_health_label:
		var health: Dictionary = level_root.get_level_health()
		perf_health_label.text = health.get("label", "-")
		var severity: int = health.get("severity", 0)
		var ok_color = _get_editor_color("success_color", Color(0.2, 0.85, 0.35))
		var warn_color = _get_editor_color("warning_color", Color(0.95, 0.8, 0.2))
		var danger_color = _get_editor_color("error_color", Color(0.95, 0.3, 0.3))
		match severity:
			0:
				perf_health_label.add_theme_color_override("font_color", ok_color)
			1:
				perf_health_label.add_theme_color_override("font_color", warn_color)
			_:
				perf_health_label.add_theme_color_override("font_color", danger_color)

	# Color-code brush count value
	var ok_c = _get_editor_color("success_color", Color(0.2, 0.85, 0.35))
	var warn_c = _get_editor_color("warning_color", Color(0.95, 0.8, 0.2))
	var danger_c = _get_editor_color("error_color", Color(0.95, 0.3, 0.3))
	if brush_count <= 50:
		perf_brushes_value.add_theme_color_override("font_color", ok_c)
	elif brush_count <= 100:
		perf_brushes_value.add_theme_color_override("font_color", warn_c)
	else:
		perf_brushes_value.add_theme_color_override("font_color", danger_c)


func _format_bytes(count: int) -> String:
	var value = float(count)
	if value >= 1024.0 * 1024.0:
		return "%.2f MB" % (value / (1024.0 * 1024.0))
	if value >= 1024.0:
		return "%.1f KB" % (value / 1024.0)
	return "%d B" % int(value)


func _update_disabled_hints() -> void:
	var has_root = level_root != null
	var need_root_hint = "Requires a LevelRoot — use Create Starter or Create Empty above"
	var quick_play_hint = (
		"Wait for the current bake to finish" if has_root and _bake_disabled else need_root_hint
	)
	_set_control_disabled_hint(
		primary_quick_play_btn, not has_root or _bake_disabled, quick_play_hint
	)
	_set_control_disabled_hint(quick_play_btn, not has_root or _bake_disabled, quick_play_hint)
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
	var selection_scope := _current_selection_scope()
	var mixed_selection := selection_scope == DockSelectionScope.MIXED
	var native_selection := selection_scope == DockSelectionScope.NATIVE
	var unsafe_managed_action := mixed_selection or native_selection
	var managed_counts := _get_managed_selection_counts(_selection_nodes)
	var managed_brushes := int(managed_counts["brushes"])
	var managed_entities := int(managed_counts["entities"])
	var managed_total := int(managed_counts["total"])
	var mixed_hint := MIXED_SELECTION_MESSAGE
	var unsafe_hint: String = (
		mixed_hint
		if mixed_selection
		else "Select HammerForge brushes/entities; ordinary Godot nodes are left unchanged."
	)
	var brush_scope_hint: String = (
		"Select only HammerForge brushes for this action." if managed_entities > 0 else unsafe_hint
	)
	var unsafe_brush_action := unsafe_managed_action or managed_entities > 0
	var unsafe_entity_action := unsafe_managed_action or managed_brushes > 0
	var face_hint: String = brush_scope_hint if unsafe_brush_action else "Requires a selected face"
	_set_control_disabled_hint(
		material_assign, not has_root or not has_face or unsafe_brush_action, face_hint
	)
	_set_control_disabled_hint(face_clear, not has_root or not has_face, face_hint)
	for face_control in [
		uv_reset,
		uv_reproject_btn,
		uv_projection_opt,
		uv_scale_x,
		uv_scale_y,
		uv_offset_x,
		uv_offset_y,
		uv_rotation_spin,
		surface_paint_layer_add,
		surface_paint_layer_remove,
		surface_paint_texture,
		justify_fit_btn,
		justify_center_btn,
		justify_left_btn,
		justify_right_btn,
		justify_top_btn,
		justify_bottom_btn,
		_disp_create_btn,
		_disp_destroy_btn,
		_disp_smooth_btn,
		_disp_noise_btn,
		_disp_elevation_spin,
		_disp_sew_group_spin,
		_bevel_inset_btn,
		_bevel_inset_dist_spin,
		_bevel_inset_height_spin,
	]:
		_set_control_disabled_hint(
			face_control, not has_root or not has_face or unsafe_brush_action, face_hint
		)
	var edge_hint: String = brush_scope_hint if unsafe_brush_action else need_root_hint
	for edge_control in [_bevel_edge_btn, _bevel_segments_spin, _bevel_radius_spin]:
		_set_control_disabled_hint(edge_control, not has_root or unsafe_brush_action, edge_hint)
	# Sewing all displacement boundaries is deliberately selection-independent.
	_set_control_disabled_hint(_disp_sew_btn, not has_root, need_root_hint)
	var baked_ready = has_root and level_root.baked_container != null
	_set_control_disabled_hint(export_glb_btn, not baked_ready, "Requires a successful bake")
	# Selection-dependent tools fail closed when ordinary Godot nodes are mixed
	# with HammerForge objects. This mirrors the handler guard, so stale button
	# callbacks cannot partially mutate the managed subset either.
	var has_selection := (
		selection_scope == DockSelectionScope.MANAGED
		and managed_brushes > 0
		and managed_entities == 0
	)
	var need_sel_hint: String = (
		brush_scope_hint if unsafe_brush_action else "Requires a selected brush"
	)
	for brush_control in [
		hollow_btn,
		clip_btn,
		move_floor_btn,
		move_ceiling_btn,
		tie_entity_btn,
		untie_entity_btn,
		heightmap_convert_btn,
	]:
		_set_control_disabled_hint(brush_control, not has_root or not has_selection, need_sel_hint)
	_set_control_disabled_hint(
		bake_selected_btn, not has_root or not has_selection or _bake_disabled, need_sel_hint
	)
	_set_control_disabled_hint(
		quick_play_area_btn, not has_root or not has_selection or _bake_disabled, need_sel_hint
	)
	var has_managed_selection := selection_scope == DockSelectionScope.MANAGED and managed_total > 0
	var managed_hint: String = (
		unsafe_hint if unsafe_managed_action else "Requires selected HammerForge objects"
	)
	var entity_scope_hint: String = (
		"Select only HammerForge entities for this action." if managed_brushes > 0 else managed_hint
	)
	_set_control_disabled_hint(
		visgroup_add_sel_btn, not has_root or not has_managed_selection, managed_hint
	)
	_set_control_disabled_hint(
		visgroup_rem_sel_btn, not has_root or not has_managed_selection, managed_hint
	)
	_set_control_disabled_hint(
		group_sel_btn,
		not has_root or selection_scope != DockSelectionScope.MANAGED or managed_total < 2,
		managed_hint
	)
	_set_control_disabled_hint(ungroup_btn, not has_root or not has_managed_selection, managed_hint)
	_set_control_disabled_hint(
		cordon_from_sel_btn, not has_root or not has_selection, need_sel_hint
	)
	_set_control_disabled_hint(
		io_add_btn,
		(
			not has_root
			or selection_scope != DockSelectionScope.MANAGED
			or managed_entities < 1
			or unsafe_entity_action
		),
		entity_scope_hint
	)
	_set_control_disabled_hint(
		io_remove_btn,
		(
			not has_root
			or selection_scope != DockSelectionScope.MANAGED
			or managed_entities < 1
			or unsafe_entity_action
		),
		entity_scope_hint
	)
	var scatter_mixed := selection_scope == DockSelectionScope.MIXED
	var scatter_hint: String = mixed_hint if scatter_mixed else need_root_hint
	_set_control_disabled_hint(scatter_preview_btn, not has_root or scatter_mixed, scatter_hint)
	_set_control_disabled_hint(scatter_commit_btn, not has_root or scatter_mixed, scatter_hint)
	# Inline hint labels
	if _sel_tools_hint_label:
		_sel_tools_hint_label.visible = not has_selection
		if unsafe_brush_action:
			_sel_tools_hint_label.text = brush_scope_hint
		else:
			_sel_tools_hint_label.text = "Select a brush to use these tools"
	if _uv_hint_label:
		_uv_hint_label.visible = not has_face or unsafe_brush_action


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
		# CUSTOM is generated by polygon/path tools, not a drawable primitive.
		if shape_key == "CUSTOM":
			continue
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
	if face:
		_sync_uv_params_to_face(face)


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
	HFDockPaintHandler.on_paint_layer_selected(self, index)


func _on_paint_layer_add() -> void:
	HFDockPaintHandler.on_paint_layer_add(self)


func _on_paint_layer_rename() -> void:
	HFDockPaintHandler.on_paint_layer_rename(self)


func _on_paint_layer_remove() -> void:
	HFDockPaintHandler.on_paint_layer_remove(self)


func _on_heightmap_import() -> void:
	HFDockPaintHandler.on_heightmap_import(self)


func _on_heightmap_import_selected(path: String) -> void:
	HFDockPaintHandler.on_heightmap_import_selected(self, path)


func _on_heightmap_generate() -> void:
	HFDockPaintHandler.on_heightmap_generate(self)


func _on_heightmap_convert() -> void:
	HFDockPaintHandler.on_heightmap_convert(self)


func _on_scatter_mesh_pick() -> void:
	HFDockPaintHandler.on_scatter_mesh_pick(self)


func _build_scatter_settings() -> HFScatterBrush.ScatterSettings:
	return HFDockPaintHandler.build_scatter_settings(self)


func _get_active_paint_layer() -> HFPaintLayer:
	return HFDockPaintHandler.get_active_paint_layer(self)


func _on_scatter_preview() -> void:
	HFDockPaintHandler.on_scatter_preview(self)


func _on_scatter_commit() -> void:
	HFDockPaintHandler.on_scatter_commit(self)


func _on_scatter_clear() -> void:
	HFDockPaintHandler.on_scatter_clear(self)


func _scatter_clear_preview() -> void:
	HFDockPaintHandler.scatter_clear_preview(self)


func _on_sculpt_tool_toggled(pressed: bool, tool_id: int) -> void:
	HFDockPaintHandler.on_sculpt_tool_toggled(self, pressed, tool_id)


func _on_sculpt_strength_changed(value: float) -> void:
	HFDockPaintHandler.on_sculpt_strength_changed(self, value)


func _on_sculpt_radius_changed(value: float) -> void:
	HFDockPaintHandler.on_sculpt_radius_changed(self, value)


func _on_sculpt_falloff_changed(value: float) -> void:
	HFDockPaintHandler.on_sculpt_falloff_changed(self, value)


func _on_height_scale_changed(value: float) -> void:
	HFDockPaintHandler.on_height_scale_changed(self, value)


func _on_layer_y_changed(value: float) -> void:
	HFDockPaintHandler.on_layer_y_changed(self, value)


func _on_blend_strength_changed(value: float) -> void:
	HFDockPaintHandler.on_blend_strength_changed(self, value)


func _on_region_enable_toggled(enabled: bool) -> void:
	HFDockPaintHandler.on_region_enable_toggled(self, enabled)


func _on_region_size_changed(value: float) -> void:
	HFDockPaintHandler.on_region_size_changed(self, value)


func _on_region_radius_changed(value: float) -> void:
	HFDockPaintHandler.on_region_radius_changed(self, value)


func _on_region_memory_changed(value: float) -> void:
	HFDockPaintHandler.on_region_memory_changed(self, value)


func _on_region_grid_toggled(enabled: bool) -> void:
	HFDockPaintHandler.on_region_grid_toggled(self, enabled)


func _on_blend_slot_selected(index: int) -> void:
	HFDockPaintHandler.on_blend_slot_selected(self, index)


func _on_terrain_slot_pressed(slot: int) -> void:
	HFDockPaintHandler.on_terrain_slot_pressed(self, slot)


func _on_terrain_slot_texture_selected(path: String) -> void:
	HFDockPaintHandler.on_terrain_slot_texture_selected(self, path)


func _on_terrain_slot_scale_changed(value: float, slot: int) -> void:
	HFDockPaintHandler.on_terrain_slot_scale_changed(self, value, slot)


func _refresh_terrain_slots() -> void:
	HFDockPaintHandler.refresh_terrain_slots(self)


func _terrain_slot_label(path: String) -> String:
	return HFDockPaintHandler.terrain_slot_label(path)


func _set_terrain_slot_controls_enabled(enabled: bool) -> void:
	HFDockPaintHandler.set_terrain_slot_controls_enabled(self, enabled)


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
## keys: action (String — empty on error), method (String), args (Array),
## toast (String).  Separated from side-effects so tests can exercise the
## face-vs-brush fallback without undo/redo infrastructure.
func resolve_material_assign_action(mat_index: int) -> Dictionary:
	var selection_scope := _current_selection_scope()
	if selection_scope == DockSelectionScope.MIXED:
		return {"action": "", "method": "", "args": [], "toast": MIXED_SELECTION_MESSAGE}
	if selection_scope == DockSelectionScope.NATIVE:
		return {
			"action": "",
			"method": "",
			"args": [],
			"toast": "Material assignment requires a HammerForge brush or selected face."
		}
	if selection_scope == DockSelectionScope.MANAGED:
		var managed_counts := _get_managed_selection_counts(_selection_nodes)
		if int(managed_counts["entities"]) > 0:
			return {
				"action": "",
				"method": "",
				"args": [],
				"toast": "Material assignment requires a brush-only selection."
			}
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
			if not _guard_selection_action(
				"Apply Face Material", DockSelectionRequirement.BRUSHES_ONLY
			):
				return
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
			if not _guard_selection_action(
				"Apply Brush Material", DockSelectionRequirement.BRUSHES_ONLY
			):
				return
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
		4:  # Apply + Re-project (Box UV)
			if not _guard_selection_action(
				"Apply and Re-project Material", DockSelectionRequirement.BRUSHES_ONLY
			):
				return
			_selected_material_index = idx
			var face_count := _count_selected_faces()
			if face_count == 0:
				show_toast("No faces selected — select faces first", 1)
				return
			_commit_state_action(
				"Assign + Re-project",
				"assign_material_and_reproject",
				[idx, FaceData.UVProjection.BOX_UV]
			)
			show_toast(
				(
					"Applied %s + Box UV to %d face%s"
					% [mat_name, face_count, "" if face_count == 1 else "s"]
				),
				0
			)


func _get_selected_brush_ids() -> Array:
	var ids: Array = []
	if not level_root or _current_selection_scope() != DockSelectionScope.MANAGED:
		return ids
	if int(_get_managed_selection_counts(_selection_nodes)["entities"]) > 0:
		return ids
	for node in _selection_nodes:
		if node is DraftBrush and is_instance_valid(node) and level_root.is_brush_node(node):
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
	if not _guard_selection_action("Reset UV", DockSelectionRequirement.BRUSHES_ONLY):
		return
	if _uv_active_brush.brush_id == "":
		level_root.get_brush_info_from_node(_uv_active_brush)
	var brush_id = _uv_active_brush.brush_id
	var face_idx = _uv_active_brush.faces.find(_uv_active_face)
	if brush_id == "" or face_idx < 0:
		return
	_commit_state_action("Reset UV", "reset_uv_on_face", [brush_id, face_idx])


func _on_uv_reproject() -> void:
	if _uv_active_face == null or _uv_active_brush == null:
		return
	if not level_root:
		return
	if not _guard_selection_action("Re-project UV", DockSelectionRequirement.BRUSHES_ONLY):
		return
	if _uv_active_brush.brush_id == "":
		level_root.get_brush_info_from_node(_uv_active_brush)
	var brush_id = _uv_active_brush.brush_id
	var face_idx = _uv_active_brush.faces.find(_uv_active_face)
	if brush_id == "" or face_idx < 0:
		return
	var proj: int = (
		uv_projection_opt.selected if uv_projection_opt else FaceData.UVProjection.BOX_UV
	)
	_commit_state_action("Re-project UV", "reproject_face_uvs", [brush_id, face_idx, proj])


var _uv_param_updating := false


func _on_uv_param_changed(_value: float, _param: String) -> void:
	if _uv_param_updating:
		return
	if _uv_active_face == null or _uv_active_brush == null:
		return
	if not level_root:
		return
	if not _guard_selection_action("Edit UV", DockSelectionRequirement.BRUSHES_ONLY):
		return
	if _uv_active_brush.brush_id == "":
		level_root.get_brush_info_from_node(_uv_active_brush)
	var brush_id: String = _uv_active_brush.brush_id
	var face_idx: int = _uv_active_brush.faces.find(_uv_active_face)
	if brush_id == "" or face_idx < 0:
		return
	var scale := Vector2(
		uv_scale_x.value if uv_scale_x else 1.0, uv_scale_y.value if uv_scale_y else 1.0
	)
	var offset := Vector2(
		uv_offset_x.value if uv_offset_x else 0.0, uv_offset_y.value if uv_offset_y else 0.0
	)
	var rotation: float = deg_to_rad(uv_rotation_spin.value) if uv_rotation_spin else 0.0
	# Route through undo system with collation so rapid spinbox changes merge
	HFUndoHelper.commit(
		undo_redo,
		level_root,
		"Set UV Params",
		"set_face_uv_params",
		[brush_id, face_idx, scale, offset, rotation],
		false,
		Callable(self, "record_history"),
		"uv_param_%s_%d" % [brush_id, face_idx]
	)


func _sync_uv_params_to_face(face: FaceData) -> void:
	_uv_param_updating = true
	if uv_projection_opt:
		uv_projection_opt.selected = face.uv_projection
	if uv_scale_x:
		uv_scale_x.value = face.uv_scale.x
	if uv_scale_y:
		uv_scale_y.value = face.uv_scale.y
	if uv_offset_x:
		uv_offset_x.value = face.uv_offset.x
	if uv_offset_y:
		uv_offset_y.value = face.uv_offset.y
	if uv_rotation_spin:
		uv_rotation_spin.value = rad_to_deg(face.uv_rotation)
	_uv_param_updating = false


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
	if not _guard_selection_action(
		"Add Surface Paint Layer", DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	if _surface_active_brush.brush_id == "":
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
	if not _guard_selection_action(
		"Remove Surface Paint Layer", DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	if _surface_active_brush.brush_id == "":
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
	if not level_root or _surface_active_face == null or not surface_paint_texture_dialog:
		return
	if not _guard_selection_action(
		"Set Surface Paint Texture", DockSelectionRequirement.BRUSHES_ONLY
	):
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
	if not _guard_selection_action(
		"Set Surface Paint Texture", DockSelectionRequirement.BRUSHES_ONLY
	):
		return
	if _surface_active_brush.brush_id == "":
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
	# Tri/Pent are intentionally fixed prism variants; only Pyramid is adjustable.
	return shape_value == LevelRootType.BrushShape.PYRAMID


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
	HFDockFileHandler.setup_storage_dialogs(self)


func _on_save_hflevel() -> void:
	HFDockFileHandler.show_dialog(hflevel_save_dialog)


func _on_load_hflevel() -> void:
	HFDockFileHandler.show_dialog(hflevel_load_dialog)


func _on_import_map() -> void:
	HFDockFileHandler.show_dialog(map_import_dialog)


func _on_export_map() -> void:
	HFDockFileHandler.show_dialog(map_export_dialog)


func _on_export_glb() -> void:
	HFDockFileHandler.show_dialog(glb_export_dialog)


func _on_set_autosave_path() -> void:
	HFDockFileHandler.show_dialog(autosave_path_dialog)


func _on_hflevel_save_selected(path: String) -> void:
	HFDockFileHandler.on_hflevel_save_selected(self, path)


func _on_hflevel_load_selected(path: String) -> void:
	HFDockFileHandler.on_hflevel_load_selected(self, path)


func _on_map_import_selected(path: String) -> void:
	HFDockFileHandler.on_map_import_selected(self, path)


func _on_map_export_selected(path: String) -> void:
	HFDockFileHandler.on_map_export_selected(self, path)


func _on_glb_export_selected(path: String) -> void:
	HFDockFileHandler.on_glb_export_selected(self, path)


func _on_autosave_path_selected(path: String) -> void:
	HFDockFileHandler.on_autosave_path_selected(self, path)


func _on_export_settings() -> void:
	HFDockFileHandler.show_dialog(settings_export_dialog)


func _on_import_settings() -> void:
	HFDockFileHandler.show_dialog(settings_import_dialog)


func _on_settings_export_selected(path: String) -> void:
	HFDockFileHandler.on_settings_export_selected(self, path)


func _on_settings_import_selected(path: String) -> void:
	HFDockFileHandler.on_settings_import_selected(self, path)


func _collect_editor_settings() -> Dictionary:
	var snap_values: Array = []
	for button in snap_buttons:
		if button and button.has_meta("snap_value"):
			snap_values.append(int(button.get_meta("snap_value")))
	var brush_size = {"x": size_x.value, "y": size_y.value, "z": size_z.value}
	var bake_settings: Dictionary = {
		"merge_meshes": bake_merge_meshes.button_pressed if bake_merge_meshes else false,
		"generate_lods": bake_generate_lods.button_pressed if bake_generate_lods else false,
		"unwrap_uv0": bake_unwrap_uv0.button_pressed if bake_unwrap_uv0 else false,
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
	if bake_visible_only_check:
		bake_settings["visible_only"] = bake_visible_only_check.button_pressed
	if bake_use_multimesh_check:
		bake_settings["use_multimesh"] = bake_use_multimesh_check.button_pressed
	if bake_use_atlas_check:
		bake_settings["use_atlas"] = bake_use_atlas_check.button_pressed
	if bake_auto_connectors_check:
		bake_settings["auto_connectors"] = bake_auto_connectors_check.button_pressed
	if bake_generate_occluders_check:
		bake_settings["generate_occluders"] = bake_generate_occluders_check.button_pressed
	if bake_occluder_min_area_spin:
		bake_settings["occluder_min_area"] = float(bake_occluder_min_area_spin.value)
	if bake_connector_mode_opt:
		bake_settings["connector_mode"] = bake_connector_mode_opt.get_selected_id()
	if bake_connector_stair_height_spin:
		bake_settings["connector_stair_height"] = float(bake_connector_stair_height_spin.value)
	if bake_connector_width_spin:
		bake_settings["connector_width"] = int(bake_connector_width_spin.value)
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
		if bake_unwrap_uv0:
			bake_unwrap_uv0.button_pressed = bool(
				bake.get("unwrap_uv0", bake_unwrap_uv0.button_pressed)
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
		if bake_chunk_size_spin and bake.has("chunk_size"):
			bake_chunk_size_spin.value = float(bake.get("chunk_size", 32.0))
		if bake_visible_only_check and bake.has("visible_only"):
			bake_visible_only_check.button_pressed = bool(bake.get("visible_only", false))
		if bake_use_multimesh_check and bake.has("use_multimesh"):
			bake_use_multimesh_check.button_pressed = bool(bake.get("use_multimesh", false))
		if bake_use_atlas_check and bake.has("use_atlas"):
			bake_use_atlas_check.button_pressed = bool(bake.get("use_atlas", false))
		if bake_auto_connectors_check and bake.has("auto_connectors"):
			bake_auto_connectors_check.button_pressed = bool(bake.get("auto_connectors", false))
		if bake_generate_occluders_check and bake.has("generate_occluders"):
			bake_generate_occluders_check.button_pressed = bool(
				bake.get("generate_occluders", false)
			)
		if bake_occluder_min_area_spin and bake.has("occluder_min_area"):
			bake_occluder_min_area_spin.value = float(bake.get("occluder_min_area", 4.0))
		if bake_connector_mode_opt and bake.has("connector_mode"):
			bake_connector_mode_opt.select(int(bake.get("connector_mode", 0)))
		if bake_connector_stair_height_spin and bake.has("connector_stair_height"):
			bake_connector_stair_height_spin.value = float(bake.get("connector_stair_height", 0.25))
		if bake_connector_width_spin and bake.has("connector_width"):
			bake_connector_width_spin.value = int(bake.get("connector_width", 2))
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
	var defs = HFEntityDef.load_merged_definitions(entity_defs_path)
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
	var target: Control = brush_vbox
	if _advanced_build_section and _advanced_build_section.get_content():
		target = _advanced_build_section.get_content()
	target.add_child(texture_lock_check)


func _on_texture_lock_toggled(pressed: bool) -> void:
	if syncing_grid:
		return
	if level_root and _root_has_property("texture_lock"):
		level_root.set("texture_lock", pressed)


# ===========================================================================
# Wave 1: Visgroups & Groups UI
# ===========================================================================


func _setup_visgroup_ui() -> void:
	HFDockVisgroupHandler.setup_visgroup_ui(self)


func refresh_visgroup_ui() -> void:
	HFDockVisgroupHandler.refresh_visgroup_ui(self)


func _get_selected_visgroup_name() -> String:
	return HFDockVisgroupHandler.get_selected_visgroup_name(self)


func _on_visgroup_add() -> void:
	HFDockVisgroupHandler.on_visgroup_add(self)


func _on_visgroup_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	HFDockVisgroupHandler.on_visgroup_item_clicked(self, index, _at_position, mouse_button_index)


func _on_visgroup_add_selection() -> void:
	HFDockVisgroupHandler.on_visgroup_add_selection(self)


func _on_visgroup_remove_selection() -> void:
	HFDockVisgroupHandler.on_visgroup_remove_selection(self)


func _on_visgroup_delete() -> void:
	HFDockVisgroupHandler.on_visgroup_delete(self)


func _on_group_selection() -> void:
	HFDockVisgroupHandler.on_group_selection(self)


func _on_ungroup_selection() -> void:
	HFDockVisgroupHandler.on_ungroup_selection(self)


# ===========================================================================
# Wave 1: Cordon (Partial Bake) UI
# ===========================================================================


func _setup_cordon_ui() -> void:
	HFDockVisgroupHandler.setup_cordon_ui(self)


func _make_cordon_spin(min_val: float, max_val: float, default_val: float) -> SpinBox:
	return HFDockVisgroupHandler.make_cordon_spin(self, min_val, max_val, default_val)


func _on_cordon_toggled(pressed: bool) -> void:
	HFDockVisgroupHandler.on_cordon_toggled(self, pressed)


func _on_cordon_value_changed(_value: float) -> void:
	HFDockVisgroupHandler.on_cordon_value_changed(self, _value)


func _on_cordon_from_selection() -> void:
	HFDockVisgroupHandler.on_cordon_from_selection(self)


func _on_clip() -> void:
	HFDockBrushHandler.on_clip(self)


func _on_io_add() -> void:
	HFDockEntityHandler.on_io_add(self)


func _on_io_remove() -> void:
	HFDockEntityHandler.on_io_remove(self)


func _refresh_io_list(entity: Node = null) -> void:
	HFDockEntityHandler.refresh_io_list(self, entity)


func _setup_io_wiring_panel() -> void:
	HFDockEntityHandler.setup_io_wiring_panel(self)


func _on_wiring_connection_added(
	source: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	_parameter: String,
	_delay: float,
	_fire_once: bool,
) -> void:
	HFDockEntityHandler.on_wiring_connection_added(
		self, source, output_name, target_name, input_name, _parameter, _delay, _fire_once
	)


func _on_wiring_preset_applied(source: Node, preset_name: String, count: int) -> void:
	HFDockEntityHandler.on_wiring_preset_applied(self, source, preset_name, count)


func _on_wiring_highlight_toggled(enabled: bool) -> void:
	HFDockEntityHandler.on_wiring_highlight_toggled(self, enabled)


func sync_wiring_highlight_state() -> void:
	HFDockEntityHandler.sync_wiring_highlight_state(self)


# ---------------------------------------------------------------------------
# Context toolbar helper methods
# ---------------------------------------------------------------------------


## Apply the currently selected material to ALL faces on selected brushes.
func _apply_material_to_whole_brush() -> void:
	if not level_root or _selected_material_index < 0:
		show_toast("No material selected", 1)
		return
	if not _guard_selection_action("Apply Brush Material", DockSelectionRequirement.BRUSHES_ONLY):
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


## Set the operation replay control (passed from plugin.gd).
func set_operation_replay(replay) -> void:
	_operation_replay = replay


## Handle example level load request from the example library.
func _on_example_load_requested(example_id: String) -> void:
	if not _example_library:
		return
	var data: Dictionary = _example_library.get_example_data(example_id)
	if data.is_empty():
		show_toast("Example not found: %s" % example_id, 2)
		return
	if not level_root:
		show_toast("No LevelRoot in scene — add one first", 1)
		return
	_load_example_data(data)


func _load_example_data(data: Dictionary) -> void:
	var brushes: Array = data.get("brushes", [])
	var entities: Array = data.get("entities", [])
	var title: String = data.get("title", "Example")

	# Clear existing content before loading
	if level_root.has_method("clear_brushes"):
		level_root.clear_brushes()
	if level_root.entity_system and level_root.entity_system.has_method("clear_entities"):
		level_root.entity_system.clear_entities()

	var loaded_count := 0
	for brush_data in brushes:
		var pos_arr: Array = brush_data.get("position", [0, 0, 0])
		var size_arr: Array = brush_data.get("size", [4, 4, 4])
		var shape: int = brush_data.get("shape", 0)
		var operation: int = brush_data.get("operation", 0)
		var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		var brush_size := Vector3(size_arr[0], size_arr[1], size_arr[2])

		# hf_brush_system reads "center" for position (not "position")
		var info := {
			"center": pos,
			"size": brush_size,
			"shape": shape,
			"operation": operation,
		}
		if level_root.has_method("create_brush_from_info"):
			level_root.create_brush_from_info(info)
			loaded_count += 1

	for entity_data in entities:
		var etype: String = entity_data.get("type", "point_light")
		var epos_arr: Array = entity_data.get("position", [0, 0, 0])
		var epos := Vector3(epos_arr[0], epos_arr[1], epos_arr[2])
		var entity = DraftEntity.new()
		entity.name = "DraftEntity"
		entity.entity_type = etype
		entity.entity_class = etype
		if level_root.has_method("add_entity"):
			level_root.add_entity(entity)
			entity.global_position = epos
			loaded_count += 1

	show_toast("Loaded '%s': %d objects" % [title, loaded_count], 0)
