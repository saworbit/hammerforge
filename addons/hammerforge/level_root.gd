@tool
extends Node3D
class_name LevelRoot

const BrushManager = preload("brush_manager.gd")
const Baker = preload("baker.gd")
const PrefabFactory = preload("prefab_factory.gd")
const DraftEntity = preload("draft_entity.gd")
const PlaytestFPS = preload("playtest_fps.gd")
const HFLevelIO = preload("hflevel_io.gd")
const MapIO = preload("map_io.gd")
const FaceData = preload("face_data.gd")
const MaterialManager = preload("material_manager.gd")
const SurfacePaint = preload("surface_paint.gd")
const FaceSelector = preload("face_selector.gd")
const HFPaintGrid = preload("paint/hf_paint_grid.gd")
const HFPaintLayerManager = preload("paint/hf_paint_layer_manager.gd")
const HFPaintTool = preload("paint/hf_paint_tool.gd")
const HFInferenceEngine = preload("paint/hf_inference_engine.gd")
const HFGeometrySynth = preload("paint/hf_geometry_synth.gd")
const HFGeneratedReconciler = preload("paint/hf_reconciler.gd")
const HFStroke = preload("paint/hf_stroke.gd")
const HFHeightmapSynth = preload("paint/hf_heightmap_synth.gd")
const HFHeightmapIO = preload("paint/hf_heightmap_io.gd")
const HFExtrudeToolType = preload("hf_extrude_tool.gd")
const HFInputStateType = preload("input_state.gd")
const HFGridSystemType = preload("systems/hf_grid_system.gd")
const HFEntitySystemType = preload("systems/hf_entity_system.gd")
const HFBrushSystemType = preload("systems/hf_brush_system.gd")
const HFDragSystemType = preload("systems/hf_drag_system.gd")
const HFBakeSystemType = preload("systems/hf_bake_system.gd")
const HFPaintSystemType = preload("systems/hf_paint_system.gd")
const HFStateSystemType = preload("systems/hf_state_system.gd")
const HFFileSystemType = preload("systems/hf_file_system.gd")
const HFValidationSystemType = preload("systems/hf_validation_system.gd")

const RELOAD_LOCK_PATH := "res://.hammerforge/reload.lock"
const RELOAD_POLL_SECONDS := 0.5

enum BrushShape {
	BOX,
	CYLINDER,
	SPHERE,
	CONE,
	WEDGE,
	PYRAMID,
	PRISM_TRI,
	PRISM_PENT,
	ELLIPSOID,
	CAPSULE,
	TORUS,
	TETRAHEDRON,
	OCTAHEDRON,
	DODECAHEDRON,
	ICOSAHEDRON
}
enum AxisLock { NONE, X, Y, Z }

# ---------------------------------------------------------------------------
# Export vars
# ---------------------------------------------------------------------------

var _grid_snap: float = 16.0
@export var grid_snap: float = 16.0:
	set(value):
		_set_grid_snap(value)
	get:
		return _grid_snap
@export var brush_size_default: Vector3 = Vector3(32, 32, 32)
@export_range(1, 32, 1) var bake_collision_layer_index: int = 1
@export var bake_material_override: Material = null
@export var bake_chunk_size: float = 32.0
@export var bake_merge_meshes: bool = false
@export var bake_generate_lods: bool = false
@export var bake_lightmap_uv2: bool = false
@export var bake_lightmap_texel_size: float = 0.1
@export var bake_use_face_materials: bool = false
@export var bake_navmesh: bool = false
@export var bake_navmesh_cell_size: float = 0.3
@export var bake_navmesh_cell_height: float = 0.25
@export var bake_navmesh_agent_height: float = 2.0
@export var bake_navmesh_agent_radius: float = 0.4
@export var bake_use_thread_pool: bool = true
var _hflevel_autosave_enabled: bool = true
@export var hflevel_autosave_enabled: bool = true:
	set(value):
		_set_hflevel_autosave_enabled(value)
	get:
		return _hflevel_autosave_enabled
var _hflevel_autosave_minutes: int = 5
@export_range(1, 60, 1) var hflevel_autosave_minutes: int = 5:
	set(value):
		_set_hflevel_autosave_minutes(value)
	get:
		return _hflevel_autosave_minutes
var _hflevel_autosave_keep: int = 5
@export_range(1, 50, 1) var hflevel_autosave_keep: int = 5:
	set(value):
		_set_hflevel_autosave_keep(value)
	get:
		return _hflevel_autosave_keep
@export var hflevel_autosave_path: String = "res://.hammerforge/autosave.hflevel"
@export var hflevel_compress: bool = true
@export var entity_definitions_path: String = "res://addons/hammerforge/entities.json"
@export var commit_freeze: bool = true
@export var auto_spawn_player: bool = true
@export_range(1, 32, 1) var draft_pick_layer_index: int = 1
var _grid_visible: bool = false
@export var grid_visible: bool = false:
	set(value):
		_set_grid_visible(value)
	get:
		return _grid_visible
@export var grid_follow_brush: bool = false
@export var debug_logging: bool = false
@export var grid_plane_size: float = 500.0
@export var grid_color: Color = Color(0.85, 0.95, 1.0, 0.15)
@export_range(1, 16, 1) var grid_major_line_frequency: int = 4

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal bake_started
signal bake_finished(success: bool)
signal bake_progress(value: float, label: String)
signal grid_snap_changed(value: float)

# ---------------------------------------------------------------------------
# Container / manager nodes
# ---------------------------------------------------------------------------

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var entities_node: Node3D
var brush_manager: BrushManager
var material_manager: MaterialManager
var baker: Baker
var paint_layers: HFPaintLayerManager
var paint_tool: HFPaintTool
var surface_paint: SurfacePaint
var generated_node: Node3D
var generated_floors: Node3D
var generated_walls: Node3D
var generated_heightmap_floors: Node3D
var generated_region_overlay: MeshInstance3D
var baked_container: Node3D
var preview_brush: DraftBrush = null

# ---------------------------------------------------------------------------
# Subsystem instances
# ---------------------------------------------------------------------------

var grid_system: HFGridSystemType
var entity_system: HFEntitySystemType
var brush_system: HFBrushSystemType
var drag_system: HFDragSystemType
var bake_system: HFBakeSystemType
var paint_system: HFPaintSystemType
var state_system: HFStateSystemType
var file_system: HFFileSystemType
var validation_system: HFValidationSystemType
var extrude_tool: HFExtrudeToolType

# ---------------------------------------------------------------------------
# Input state (owned by drag_system, accessed via backward-compat accessors)
# ---------------------------------------------------------------------------

var input_state: HFInputStateType:
	get:
		return drag_system.input_state if drag_system else null
var height_pixels_per_unit := 4.0

var drag_active: bool:
	get:
		return drag_system.input_state.is_dragging() if drag_system else false
	set(value):
		if not value and drag_system:
			drag_system.input_state.cancel()
var drag_stage: int:
	get:
		return drag_system.input_state.get_drag_stage() if drag_system else 0
var drag_origin: Vector3:
	get:
		return drag_system.input_state.drag_origin if drag_system else Vector3.ZERO
	set(value):
		if drag_system:
			drag_system.input_state.drag_origin = value
var drag_end: Vector3:
	get:
		return drag_system.input_state.drag_end if drag_system else Vector3.ZERO
	set(value):
		if drag_system:
			drag_system.input_state.drag_end = value
var drag_operation: int:
	get:
		return drag_system.input_state.drag_operation if drag_system else 0
	set(value):
		if drag_system:
			drag_system.input_state.drag_operation = value
var drag_shape: int:
	get:
		return drag_system.input_state.drag_shape if drag_system else 0
	set(value):
		if drag_system:
			drag_system.input_state.drag_shape = value
var drag_sides: int:
	get:
		return drag_system.input_state.drag_sides if drag_system else 4
	set(value):
		if drag_system:
			drag_system.input_state.drag_sides = value
var drag_height: float:
	get:
		return drag_system.input_state.drag_height if drag_system else 32.0
	set(value):
		if drag_system:
			drag_system.input_state.drag_height = value
var drag_size_default: Vector3:
	get:
		return drag_system.input_state.drag_size_default if drag_system else Vector3(32, 32, 32)
	set(value):
		if drag_system:
			drag_system.input_state.drag_size_default = value
var axis_lock: int:
	get:
		return drag_system.input_state.axis_lock if drag_system else 0
	set(value):
		if drag_system:
			drag_system.input_state.axis_lock = value
var manual_axis_lock: bool:
	get:
		return drag_system.input_state.manual_axis_lock if drag_system else false
	set(value):
		if drag_system:
			drag_system.input_state.manual_axis_lock = value
var shift_pressed: bool:
	get:
		return drag_system.input_state.shift_pressed if drag_system else false
	set(value):
		if drag_system:
			drag_system.input_state.shift_pressed = value
var alt_pressed: bool:
	get:
		return drag_system.input_state.alt_pressed if drag_system else false
	set(value):
		if drag_system:
			drag_system.input_state.alt_pressed = value
var lock_axis_active: int:
	get:
		return drag_system.input_state.lock_axis_active if drag_system else 0
	set(value):
		if drag_system:
			drag_system.input_state.lock_axis_active = value
var locked_thickness: Vector3:
	get:
		return drag_system.input_state.locked_thickness if drag_system else Vector3.ZERO
	set(value):
		if drag_system:
			drag_system.input_state.locked_thickness = value
var height_stage_start_mouse: Vector2:
	get:
		return drag_system.input_state.height_stage_start_mouse if drag_system else Vector2.ZERO
	set(value):
		if drag_system:
			drag_system.input_state.height_stage_start_mouse = value
var height_stage_start_height: float:
	get:
		return drag_system.input_state.height_stage_start_height if drag_system else 32.0
	set(value):
		if drag_system:
			drag_system.input_state.height_stage_start_height = value

# ---------------------------------------------------------------------------
# Other state vars
# ---------------------------------------------------------------------------

var grid_mesh: MeshInstance3D = null
var grid_material: ShaderMaterial = null
var hover_highlight: MeshInstance3D = null
var grid_plane_axis := AxisLock.Y
var grid_plane_origin := Vector3.ZERO
var grid_axis_preference := AxisLock.Y
var last_brush_center := Vector3.ZERO
var _brush_id_counter: int = 0
var entity_definitions: Dictionary = {}
var _last_bake_time: int = 0
var _reload_timer: Timer = null
var _autosave_timer: Timer = null
var face_selection: Dictionary = {}
var _last_bake_duration_ms: int = 0

# ===========================================================================
# Lifecycle
# ===========================================================================


func _ready():
	_setup_draft_container()
	_setup_pending_container()
	_setup_committed()
	_setup_entities_container()
	_setup_manager()
	_setup_material_manager()
	_setup_baker()
	_setup_paint_system()
	_setup_surface_paint()
	_setup_highlight()
	# Instantiate subsystems (order matters: grid before drag, brush before bake)
	grid_system = HFGridSystemType.new(self)
	entity_system = HFEntitySystemType.new(self)
	brush_system = HFBrushSystemType.new(self)
	drag_system = HFDragSystemType.new(self)
	bake_system = HFBakeSystemType.new(self)
	paint_system = HFPaintSystemType.new(self)
	state_system = HFStateSystemType.new(self)
	file_system = HFFileSystemType.new(self)
	validation_system = HFValidationSystemType.new(self)
	extrude_tool = HFExtrudeToolType.new(self)
	entity_system.load_entity_definitions()
	grid_system.setup_editor_grid()
	if Engine.is_editor_hint():
		_set_hflevel_autosave_minutes(hflevel_autosave_minutes)
		_set_hflevel_autosave_enabled(hflevel_autosave_enabled)
		_set_hflevel_autosave_keep(hflevel_autosave_keep)
		_setup_autosave()
		set_process(true)
	_log("Ready (grid_visible=%s, follow_grid=%s)" % [_grid_visible, grid_follow_brush])
	if not Engine.is_editor_hint():
		_setup_runtime_reload()
		if auto_spawn_player:
			call_deferred("_start_playtest")


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	file_system.process_thread_queue()


# ===========================================================================
# Grid API (delegates to grid_system)
# ===========================================================================


func update_editor_grid(camera: Camera3D, mouse_pos: Vector2) -> void:
	grid_system.update_editor_grid(camera, mouse_pos)


func _refresh_grid_plane() -> void:
	grid_system.refresh_grid_plane()


func _record_last_brush(center: Vector3) -> void:
	grid_system.record_last_brush(center)


func _set_grid_visible(value: bool) -> void:
	if grid_system:
		grid_system.set_grid_visible(value)
	_log("Grid visible set to %s" % _grid_visible)


func _update_grid_material() -> void:
	if grid_system:
		grid_system.update_grid_material()


func _update_grid_transform(axis: int, origin: Vector3) -> void:
	if grid_system:
		grid_system.update_grid_transform(axis, origin)


func _effective_grid_axis() -> int:
	return grid_system.effective_grid_axis() if grid_system else AxisLock.Y


func _set_grid_plane_origin(origin: Vector3, axis: int) -> void:
	if grid_system:
		grid_system.set_grid_plane_origin(origin, axis)


func _intersect_axis_plane(
	camera: Camera3D, mouse_pos: Vector2, axis: int, origin: Vector3
) -> Variant:
	return (
		grid_system.intersect_axis_plane(camera, mouse_pos, axis, origin) if grid_system else null
	)


# ===========================================================================
# Entity API (delegates to entity_system)
# ===========================================================================


func add_entity(entity: Node3D) -> void:
	entity_system.add_entity(entity)


func _load_entity_definitions() -> void:
	entity_system.load_entity_definitions()


func get_entity_definition(entity_type: String) -> Dictionary:
	if not entity_system:
		return {}
	return entity_system.get_entity_definition(entity_type)


func get_entity_definitions() -> Dictionary:
	if not entity_system:
		return {}
	return entity_system.get_entity_definitions()


func place_entity_at_screen(
	camera: Camera3D, mouse_pos: Vector2, entity_type: String
) -> DraftEntity:
	return entity_system.place_entity_at_screen(camera, mouse_pos, entity_type)


func _create_entity_from_map(info: Dictionary) -> DraftEntity:
	return entity_system.create_entity_from_map(info)


func _is_entity_node(node: Node) -> bool:
	return entity_system.is_entity_node(node)


func is_entity_node(node: Node) -> bool:
	return entity_system.is_entity_node(node)


func _capture_entity_info(entity: DraftEntity) -> Dictionary:
	return entity_system.capture_entity_info(entity)


func _restore_entity_from_info(info: Dictionary) -> DraftEntity:
	return entity_system.restore_entity_from_info(info)


func _clear_entities() -> void:
	entity_system.clear_entities()


# ===========================================================================
# Brush API (delegates to brush_system)
# ===========================================================================


func _create_brush(shape: int, size: Vector3, operation: int, sides: int) -> DraftBrush:
	return brush_system._create_brush(shape, size, operation, sides)


func place_brush(
	mouse_pos: Vector2,
	operation: int,
	size: Vector3,
	camera: Camera3D = null,
	shape: int = BrushShape.BOX,
	sides: int = 4
) -> bool:
	return brush_system.place_brush(mouse_pos, operation, size, camera, shape, sides)


func create_brush_from_info(info: Dictionary) -> Node:
	return brush_system.create_brush_from_info(info)


func create_brushes_from_infos(infos: Array) -> void:
	for info in infos:
		if info is Dictionary:
			brush_system.create_brush_from_info(info)


func delete_brush(brush: Node, free: bool = true) -> void:
	brush_system.delete_brush(brush, free)


func delete_brush_by_id(brush_id: String) -> void:
	brush_system.delete_brush_by_id(brush_id)


func delete_brushes_by_id(brush_ids: Array) -> void:
	for brush_id in brush_ids:
		brush_system.delete_brush_by_id(str(brush_id))


func duplicate_brush(brush: Node) -> Node:
	return brush_system.duplicate_brush(brush)


func nudge_brushes_by_id(brush_ids: Array, offset: Vector3) -> void:
	brush_system.nudge_brushes_by_id(brush_ids, offset)


func apply_material_to_brush_by_id(brush_id: String, mat: Material) -> void:
	brush_system.apply_material_to_brush_by_id(brush_id, mat)


func set_brush_transform_by_id(brush_id: String, size: Vector3, position: Vector3) -> void:
	brush_system.set_brush_transform_by_id(brush_id, size, position)


func restore_brush(brush: Node, parent: Node, owner: Node, index: int) -> void:
	brush_system.restore_brush(brush, parent, owner, index)


func _find_brush_by_id(brush_id: String) -> Node:
	return brush_system._find_brush_by_id(brush_id)


func find_brush_by_id(brush_id: String) -> Node:
	return brush_system.find_brush_by_id(brush_id)


func get_brush_info_from_node(brush: Node) -> Dictionary:
	return brush_system.get_brush_info_from_node(brush)


func build_duplicate_info(brush: Node, offset: Vector3) -> Dictionary:
	return brush_system.build_duplicate_info(brush, offset)


func is_brush_node(node: Node) -> bool:
	return brush_system.is_brush_node(node)


func _is_subtract_brush(node: Node) -> bool:
	return brush_system._is_subtract_brush(node)


func get_live_brush_count() -> int:
	return brush_system.get_live_brush_count()


func _next_brush_id() -> String:
	return brush_system._next_brush_id()


func _register_brush_id(brush_id: String) -> void:
	brush_system._register_brush_id(brush_id)


func _shape_uses_sides(shape: int) -> bool:
	return brush_system._shape_uses_sides(shape)


func apply_pending_cuts() -> void:
	brush_system.apply_pending_cuts()


func clear_pending_cuts() -> void:
	brush_system.clear_pending_cuts()


func commit_cuts() -> void:
	await brush_system.commit_cuts()


func restore_committed_cuts() -> void:
	brush_system.restore_committed_cuts()


func clear_brushes() -> void:
	brush_system.clear_brushes()


func _clear_generated() -> void:
	brush_system._clear_generated()


func _make_brush_material(operation: int, solid: bool = false, unshaded: bool = false) -> Material:
	return brush_system._make_brush_material(operation, solid, unshaded)


func _make_pending_cut_material() -> Material:
	return brush_system._make_pending_cut_material()


func _apply_brush_material(brush: Node, mat: Material) -> void:
	brush_system._apply_brush_material(brush, mat)


func apply_material_to_brush(brush: Node, mat: Material) -> void:
	brush_system.apply_material_to_brush(brush, mat)


func _refresh_brush_previews() -> void:
	brush_system._refresh_brush_previews()


func rebuild_brush_preview(brush: DraftBrush) -> void:
	brush_system.rebuild_brush_preview(brush)


func reset_uv_on_face(brush_id: String, face_idx: int) -> void:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return
	var face: FaceData = draft.faces[face_idx]
	face.custom_uvs = PackedVector2Array()
	face.ensure_custom_uvs()
	draft.rebuild_preview()


func add_surface_paint_layer(brush_id: String, face_idx: int) -> void:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return
	draft.faces[face_idx].paint_layers.append(FaceData.PaintLayer.new())
	draft.rebuild_preview()


func remove_surface_paint_layer(brush_id: String, face_idx: int, layer_idx: int) -> void:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return
	var layers = draft.faces[face_idx].paint_layers
	if layer_idx < 0 or layer_idx >= layers.size():
		return
	layers.remove_at(layer_idx)
	draft.rebuild_preview()


func set_surface_paint_layer_texture(
	brush_id: String, indices: Vector2i, texture: Texture2D
) -> void:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	var face_idx = indices.x
	var layer_idx = indices.y
	if face_idx < 0 or face_idx >= draft.faces.size():
		return
	var layers = draft.faces[face_idx].paint_layers
	if layer_idx < 0 or layer_idx >= layers.size():
		return
	layers[layer_idx].texture = texture
	draft.rebuild_preview()


func _clear_preview() -> void:
	brush_system._clear_preview()


func pick_brush(camera: Camera3D, mouse_pos: Vector2, include_entities: bool = true) -> Node:
	return brush_system.pick_brush(camera, mouse_pos, include_entities)


func update_hover(camera: Camera3D, mouse_pos: Vector2) -> void:
	brush_system.update_hover(camera, mouse_pos)


func clear_hover() -> void:
	brush_system.clear_hover()


func pick_face(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	return brush_system.pick_face(camera, mouse_pos)


func select_face_at_screen(camera: Camera3D, mouse_pos: Vector2, additive: bool) -> bool:
	return brush_system.select_face_at_screen(camera, mouse_pos, additive)


func toggle_face_selection(brush: DraftBrush, face_idx: int, additive: bool) -> void:
	brush_system.toggle_face_selection(brush, face_idx, additive)


func clear_face_selection() -> void:
	brush_system.clear_face_selection()


func get_face_selection() -> Dictionary:
	return brush_system.get_face_selection()


func get_primary_selected_face() -> Dictionary:
	return brush_system.get_primary_selected_face()


func assign_material_to_selected_faces(material_index: int) -> void:
	brush_system.assign_material_to_selected_faces(material_index)


func _apply_face_selection() -> void:
	brush_system._apply_face_selection()


func _face_key(brush: DraftBrush) -> String:
	return brush_system._face_key(brush)


func _find_brush_by_key(key: String) -> DraftBrush:
	return brush_system._find_brush_by_key(key)


# ===========================================================================
# Drag API (delegates to drag_system)
# ===========================================================================


func begin_drag(
	camera: Camera3D, mouse_pos: Vector2, operation: int, size: Vector3, shape: int, sides: int = 4
) -> bool:
	return drag_system.begin_drag(camera, mouse_pos, operation, size, shape, sides)


func update_drag(camera: Camera3D, mouse_pos: Vector2) -> void:
	drag_system.update_drag(camera, mouse_pos)


func end_drag_info(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> Dictionary:
	return drag_system.end_drag_info(camera, mouse_pos, size_default)


func end_drag(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> bool:
	return drag_system.end_drag(camera, mouse_pos, size_default)


func cancel_drag() -> void:
	drag_system.cancel_drag()


func set_axis_lock(lock: int, manual: bool = true) -> void:
	drag_system.set_axis_lock(lock, manual)


func set_shift_pressed(pressed: bool) -> void:
	drag_system.set_shift_pressed(pressed)


func set_alt_pressed(pressed: bool) -> void:
	drag_system.set_alt_pressed(pressed)


# ===========================================================================
# Extrude API (delegates to extrude_tool)
# ===========================================================================


func begin_extrude(camera: Camera3D, mouse_pos: Vector2, extrude_direction: int) -> bool:
	var started := extrude_tool.begin_extrude(camera, mouse_pos, extrude_direction)
	if started and drag_system:
		drag_system.input_state.begin_extrude()
	return started


func update_extrude(camera: Camera3D, mouse_pos: Vector2) -> void:
	extrude_tool.update_extrude(camera, mouse_pos)


func end_extrude_info() -> Dictionary:
	var info := extrude_tool.end_extrude_info()
	if drag_system:
		drag_system.input_state.end_extrude()
	return info


func cancel_extrude() -> void:
	extrude_tool.cancel_extrude()
	if drag_system:
		drag_system.input_state.end_extrude()


# ===========================================================================
# Bake API (delegates to bake_system)
# ===========================================================================


func bake(apply_cuts: bool = true, hide_live: bool = false, collision_layer_mask: int = 0) -> void:
	await bake_system.bake(apply_cuts, hide_live, collision_layer_mask)


func bake_dry_run() -> Dictionary:
	return bake_system.bake_dry_run() if bake_system else {}


# ===========================================================================
# Paint API (delegates to paint_system)
# ===========================================================================


func handle_paint_input(
	camera: Camera3D,
	event: InputEvent,
	screen_pos: Vector2,
	operation: int,
	size: Vector3,
	paint_tool_id: int = -1,
	paint_radius_cells: int = -1,
	paint_brush_shape: int = 1
) -> bool:
	return paint_system.handle_paint_input(
		camera,
		event,
		screen_pos,
		operation,
		size,
		paint_tool_id,
		paint_radius_cells,
		paint_brush_shape
	)


func get_paint_layer_names() -> Array:
	return paint_system.get_paint_layer_names()


func get_active_paint_layer_index() -> int:
	return paint_system.get_active_paint_layer_index()


func set_active_paint_layer(index: int) -> void:
	paint_system.set_active_paint_layer(index)


func add_paint_layer() -> void:
	paint_system.add_paint_layer()


func remove_active_paint_layer() -> void:
	paint_system.remove_active_paint_layer()


func handle_surface_paint_input(
	camera: Camera3D,
	event: InputEvent,
	mouse_pos: Vector2,
	radius_uv: float,
	strength: float,
	layer_idx: int
) -> bool:
	return paint_system.handle_surface_paint_input(
		camera, event, mouse_pos, radius_uv, strength, layer_idx
	)


func _regenerate_paint_layers() -> void:
	paint_system.regenerate_paint_layers()


func import_heightmap(path: String) -> void:
	paint_system.import_heightmap(path)


func generate_heightmap_noise(settings: Dictionary = {}) -> void:
	paint_system.generate_heightmap_noise(settings)


func set_heightmap_scale(value: float) -> void:
	paint_system.set_heightmap_scale(value)


func set_layer_y(value: float) -> void:
	paint_system.set_layer_y(value)


func set_region_streaming_enabled(value: bool) -> void:
	if paint_system:
		paint_system.set_region_streaming_enabled(value)


func set_region_size_cells(value: int) -> void:
	if paint_system:
		paint_system.set_region_size_cells(value)


func set_region_streaming_radius(value: int) -> void:
	if paint_system:
		paint_system.set_region_streaming_radius(value)


func set_region_memory_budget_mb(value: int) -> void:
	if paint_system:
		paint_system.set_region_memory_budget_mb(value)


func set_region_show_grid(value: bool) -> void:
	if paint_system:
		paint_system.set_region_show_grid(value)


func get_region_settings() -> Dictionary:
	return paint_system.get_region_settings() if paint_system else {}


func get_loaded_regions() -> Array:
	return paint_system.get_loaded_regions() if paint_system else []


# ===========================================================================
# State API (delegates to state_system)
# ===========================================================================


func capture_state(include_transient: bool = true) -> Dictionary:
	return state_system.capture_state(include_transient)


func restore_state(state: Dictionary) -> void:
	state_system.restore_state(state)


func capture_full_state() -> Dictionary:
	return state_system.capture_full_state()


func restore_full_state(bundle: Dictionary) -> void:
	state_system.restore_full_state(bundle)


func _capture_hflevel_state() -> Dictionary:
	return state_system.capture_hflevel_state()


func _capture_hflevel_settings() -> Dictionary:
	return state_system.capture_hflevel_settings()


func _apply_hflevel_settings(settings: Dictionary) -> void:
	state_system.apply_hflevel_settings(settings)


# ===========================================================================
# File API (delegates to file_system)
# ===========================================================================


func save_hflevel(path: String = "", force: bool = false) -> int:
	return file_system.save_hflevel(path, force)


func load_hflevel(path: String = "") -> bool:
	return file_system.load_hflevel(path)


func import_map(path: String) -> int:
	return file_system.import_map(path)


func export_map(path: String) -> int:
	return file_system.export_map(path)


func export_baked_gltf(path: String) -> int:
	return file_system.export_baked_gltf(path)


func check_missing_dependencies() -> Array:
	return validation_system.check_missing_dependencies() if validation_system else []


func validate_level(auto_fix: bool = false) -> Dictionary:
	return validation_system.validate(auto_fix) if validation_system else {"issues": [], "fixed": 0}


func get_paint_memory_bytes() -> int:
	return paint_system.get_paint_memory_bytes() if paint_system else 0


func get_bake_chunk_count() -> int:
	return bake_system.get_bake_chunk_count() if bake_system else 0


func get_last_bake_duration_ms() -> int:
	return _last_bake_duration_ms


# ===========================================================================
# Material manager API (stays on root — thin wrappers over material_manager)
# ===========================================================================


func get_material_manager() -> MaterialManager:
	return material_manager


func get_materials() -> Array:
	return material_manager.materials if material_manager else []


func set_materials(materials: Array) -> void:
	if not material_manager:
		_setup_material_manager()
	material_manager.materials = materials.duplicate()
	_refresh_brush_previews()


func add_material_to_palette(material: Material) -> int:
	if not material_manager:
		_setup_material_manager()
	var idx = material_manager.add_material(material)
	_refresh_brush_previews()
	return idx


func remove_material_from_palette(index: int) -> void:
	if not material_manager:
		return
	material_manager.remove_material(index)
	_refresh_brush_previews()


func get_material_names() -> Array:
	if not material_manager:
		return []
	return material_manager.get_material_names()


# ===========================================================================
# Setup methods (stay on root — run once during _ready)
# ===========================================================================


func _setup_draft_container() -> void:
	draft_brushes_node = get_node_or_null("DraftBrushes") as Node3D
	if not draft_brushes_node:
		draft_brushes_node = Node3D.new()
		draft_brushes_node.name = "DraftBrushes"
		add_child(draft_brushes_node)
		_assign_owner(draft_brushes_node)
	if Engine.is_editor_hint() and not draft_brushes_node.visible:
		draft_brushes_node.visible = true


func _setup_pending_container() -> void:
	pending_node = get_node_or_null("PendingCuts") as Node3D
	if not pending_node:
		pending_node = Node3D.new()
		pending_node.name = "PendingCuts"
		add_child(pending_node)
		_assign_owner(pending_node)
	pending_node.visible = Engine.is_editor_hint()


func _setup_committed() -> void:
	committed_node = get_node_or_null("CommittedCuts") as Node3D
	if not committed_node:
		committed_node = Node3D.new()
		committed_node.name = "CommittedCuts"
		committed_node.visible = false
		add_child(committed_node)
		_assign_owner(committed_node)


func _setup_entities_container() -> void:
	entities_node = get_node_or_null("Entities") as Node3D
	if not entities_node:
		entities_node = Node3D.new()
		entities_node.name = "Entities"
		add_child(entities_node)
		_assign_owner(entities_node)


func _setup_manager() -> void:
	brush_manager = get_node_or_null("BrushManager") as BrushManager
	if not brush_manager:
		brush_manager = BrushManager.new()
		brush_manager.name = "BrushManager"
		add_child(brush_manager)
		_assign_owner(brush_manager)


func _setup_material_manager() -> void:
	material_manager = get_node_or_null("MaterialManager") as MaterialManager
	if not material_manager:
		material_manager = MaterialManager.new()
		material_manager.name = "MaterialManager"
		add_child(material_manager)
		_assign_owner(material_manager)


func _setup_baker() -> void:
	baker = get_node_or_null("Baker") as Baker
	if not baker:
		baker = Baker.new()
		baker.name = "Baker"
		add_child(baker)
		_assign_owner(baker)


func _setup_surface_paint() -> void:
	surface_paint = get_node_or_null("SurfacePaint") as SurfacePaint
	if not surface_paint:
		surface_paint = SurfacePaint.new()
		surface_paint.name = "SurfacePaint"
		add_child(surface_paint)
		_assign_owner(surface_paint)


func _setup_paint_system() -> void:
	paint_layers = get_node_or_null("PaintLayers") as HFPaintLayerManager
	if not paint_layers:
		paint_layers = HFPaintLayerManager.new()
		paint_layers.name = "PaintLayers"
		add_child(paint_layers)
		_assign_owner(paint_layers)
	_sync_paint_grid_from_root()
	if paint_layers.layers.is_empty():
		paint_layers.create_layer(&"layer_0", grid_plane_origin.y)

	generated_node = get_node_or_null("Generated") as Node3D
	if not generated_node:
		generated_node = Node3D.new()
		generated_node.name = "Generated"
		add_child(generated_node)
		_assign_owner(generated_node)
	generated_floors = generated_node.get_node_or_null("Floors") as Node3D
	if not generated_floors:
		generated_floors = Node3D.new()
		generated_floors.name = "Floors"
		generated_node.add_child(generated_floors)
		_assign_owner(generated_floors)
	generated_walls = generated_node.get_node_or_null("Walls") as Node3D
	if not generated_walls:
		generated_walls = Node3D.new()
		generated_walls.name = "Walls"
		generated_node.add_child(generated_walls)
		_assign_owner(generated_walls)
	generated_heightmap_floors = generated_node.get_node_or_null("HeightmapFloors") as Node3D
	if not generated_heightmap_floors:
		generated_heightmap_floors = Node3D.new()
		generated_heightmap_floors.name = "HeightmapFloors"
		generated_node.add_child(generated_heightmap_floors)
		_assign_owner(generated_heightmap_floors)
	generated_region_overlay = generated_node.get_node_or_null("RegionOverlay") as MeshInstance3D
	if not generated_region_overlay:
		generated_region_overlay = MeshInstance3D.new()
		generated_region_overlay.name = "RegionOverlay"
		generated_region_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		generated_node.add_child(generated_region_overlay)
		_assign_owner(generated_region_overlay)

	paint_tool = get_node_or_null("PaintTool") as HFPaintTool
	if not paint_tool:
		paint_tool = HFPaintTool.new()
		paint_tool.name = "PaintTool"
		add_child(paint_tool)
		_assign_owner(paint_tool)
	paint_tool.layer_manager = paint_layers
	if not paint_tool.inference:
		paint_tool.inference = HFInferenceEngine.new()
	if not paint_tool.geometry:
		paint_tool.geometry = HFGeometrySynth.new()
	if not paint_tool.reconciler:
		paint_tool.reconciler = HFGeneratedReconciler.new()
	if not paint_tool.heightmap_synth:
		paint_tool.heightmap_synth = HFHeightmapSynth.new()
	paint_tool.reconciler.floors_root = generated_floors
	paint_tool.reconciler.walls_root = generated_walls
	paint_tool.reconciler.heightmap_floors_root = generated_heightmap_floors
	paint_tool.reconciler.owner = _get_editor_owner()


func _sync_paint_grid_from_root() -> void:
	if not paint_layers:
		return
	if not paint_layers.base_grid:
		paint_layers.base_grid = HFPaintGrid.new()
	paint_layers.base_grid.cell_size = max(_grid_snap, 0.1)
	paint_layers.base_grid.origin = global_position
	paint_layers.base_grid.basis = Basis.IDENTITY
	paint_layers.base_grid.layer_y = grid_plane_origin.y


func _setup_highlight() -> void:
	if not Engine.is_editor_hint():
		return
	hover_highlight = get_node_or_null("SelectionHighlight") as MeshInstance3D
	if not hover_highlight:
		hover_highlight = MeshInstance3D.new()
		hover_highlight.name = "SelectionHighlight"
		add_child(hover_highlight)
	hover_highlight.owner = null
	hover_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	hover_highlight.mesh = mesh
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, wireframe, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 1.0, 0.0, 0.5);

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""
	mat.shader = shader
	hover_highlight.material_override = mat
	hover_highlight.visible = false


func _set_grid_snap(value: float) -> void:
	var clamped = max(value, 0.0)
	if is_equal_approx(_grid_snap, clamped):
		return
	_grid_snap = clamped
	grid_snap_changed.emit(_grid_snap)
	_update_grid_material()
	_sync_paint_grid_from_root()
	if paint_layers:
		for layer in paint_layers.layers:
			if layer and layer.grid:
				layer.grid.cell_size = max(_grid_snap, 0.1)
	_log("Grid snap set to %s" % _grid_snap)


# ===========================================================================
# Autosave / reload (stay on root — timer management)
# ===========================================================================


func _setup_runtime_reload() -> void:
	if _reload_timer:
		return
	_last_bake_time = _read_reload_timestamp()
	_reload_timer = Timer.new()
	_reload_timer.name = "RemoteReloadTimer"
	_reload_timer.wait_time = RELOAD_POLL_SECONDS
	_reload_timer.one_shot = false
	_reload_timer.autostart = true
	_reload_timer.timeout.connect(_check_remote_reload)
	add_child(_reload_timer)


func _setup_autosave() -> void:
	if not hflevel_autosave_enabled:
		return
	if not _autosave_timer:
		_autosave_timer = Timer.new()
		_autosave_timer.name = "HFLevelAutosave"
		_autosave_timer.one_shot = false
		_autosave_timer.timeout.connect(_on_autosave_timeout)
		add_child(_autosave_timer)
	_autosave_timer.wait_time = max(60.0, float(hflevel_autosave_minutes) * 60.0)
	if not _autosave_timer.autostart:
		_autosave_timer.autostart = true
	if not _autosave_timer.is_stopped():
		return
	_autosave_timer.start()


func _on_autosave_timeout() -> void:
	if not hflevel_autosave_enabled:
		return
	save_hflevel(hflevel_autosave_path, true)


func _set_hflevel_autosave_enabled(value: bool) -> void:
	if _hflevel_autosave_enabled == value:
		return
	_hflevel_autosave_enabled = value
	if not Engine.is_editor_hint():
		return
	if value:
		_setup_autosave()
	elif _autosave_timer:
		_autosave_timer.stop()
		_autosave_timer.queue_free()
		_autosave_timer = null


func _set_hflevel_autosave_minutes(value: int) -> void:
	var clamped = max(1, value)
	if _hflevel_autosave_minutes == clamped:
		return
	_hflevel_autosave_minutes = clamped
	if _autosave_timer:
		_autosave_timer.wait_time = max(60.0, float(_hflevel_autosave_minutes) * 60.0)


func _set_hflevel_autosave_keep(value: int) -> void:
	var clamped = clamp(value, 1, 50)
	if _hflevel_autosave_keep == clamped:
		return
	_hflevel_autosave_keep = clamped


func _read_reload_timestamp() -> int:
	if not FileAccess.file_exists(RELOAD_LOCK_PATH):
		return 0
	var file = FileAccess.open(RELOAD_LOCK_PATH, FileAccess.READ)
	if not file:
		return 0
	var text = file.get_as_text().strip_edges()
	if text == "":
		return 0
	return text.to_int()


func _check_remote_reload() -> void:
	var stamp = _read_reload_timestamp()
	if stamp <= 0:
		return
	if stamp > _last_bake_time:
		_last_bake_time = stamp
		request_remote_reload()


func request_remote_reload() -> void:
	if Engine.is_editor_hint():
		return
	_log("Remote Reload Requested")
	bake(true, true)


# ===========================================================================
# Playtest (stays on root — one-time runtime bootstrap)
# ===========================================================================


func _start_playtest() -> void:
	_log("Starting Playtest...")

	if draft_brushes_node:
		draft_brushes_node.visible = true
	if pending_node:
		pending_node.visible = true
	if entities_node:
		for entity in entities_node.get_children():
			if entity.has_method("_clear_preview"):
				entity.call("_clear_preview")

	await bake(true, true)
	if baked_container:
		if draft_brushes_node:
			draft_brushes_node.visible = false
		if pending_node:
			pending_node.visible = false

	var spawn_pos := Vector3(0, 2, 0)
	var found_spawn := false
	for node in _iter_pick_nodes():
		if node is DraftEntity:
			var draft_entity := node as DraftEntity
			var entity_class := draft_entity.entity_class
			if entity_class == "":
				entity_class = draft_entity.entity_type
			if entity_class == "player_start":
				spawn_pos = (
					draft_entity.global_position
					if draft_entity.is_inside_tree()
					else draft_entity.position
				)
				found_spawn = true
				break

	var player = CharacterBody3D.new()
	player.name = "PlaytestPlayer"
	player.set_script(PlaytestFPS)
	var offset = Vector3(0, 1.0, 0) if found_spawn else Vector3.ZERO
	add_child(player)
	player.global_position = spawn_pos + offset


# ===========================================================================
# Misc public API (stays on root)
# ===========================================================================


func create_floor() -> void:
	var floor = get_node_or_null("TempFloor") as CSGBox3D
	if not floor:
		floor = CSGBox3D.new()
		floor.name = "TempFloor"
		add_child(floor)
		_assign_owner(floor)
	floor.size = Vector3(1024, 16, 1024)
	floor.position = Vector3(0, -8, 0)
	floor.use_collision = true


# ===========================================================================
# Shared utilities (stay on root — used by multiple subsystems)
# ===========================================================================


func _get_editor_owner() -> Node:
	var scene = get_tree().edited_scene_root
	if scene:
		return scene
	return get_owner()


func _assign_owner(node: Node) -> void:
	if not node:
		return
	var owner = _get_editor_owner()
	if owner:
		node.owner = owner


func _assign_owner_recursive(node: Node) -> void:
	if not node:
		return
	var owner = _get_editor_owner()
	if not owner:
		return
	node.owner = owner
	for child in node.get_children():
		_assign_owner_recursive(child)


func _iter_pick_nodes() -> Array:
	var nodes: Array = []
	if draft_brushes_node:
		nodes.append_array(draft_brushes_node.get_children())
	if pending_node:
		nodes.append_array(pending_node.get_children())
	if entities_node:
		nodes.append_array(entities_node.get_children())
	return nodes


func _gather_visual_instances(node: Node, out: Array) -> void:
	if not node:
		return
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		_gather_visual_instances(child, out)


func _snap_point(point: Vector3) -> Vector3:
	if grid_snap <= 0.0:
		return point
	return point.snapped(Vector3(grid_snap, grid_snap, grid_snap))


func _layer_from_index(index: int) -> int:
	var clamped = clamp(index, 1, 32)
	return 1 << (clamped - 1)


func _raycast(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 2000.0
	var ray_dir = (to - from).normalized()
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = _layer_from_index(draft_pick_layer_index)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		return hit
	var best_t = INF
	var best_hit: Dictionary = {}
	for node in _iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var mesh_inst: MeshInstance3D = node.mesh_instance
		if not mesh_inst:
			continue
		var inv = mesh_inst.global_transform.affine_inverse()
		var local_origin = inv * from
		var local_dir = (inv.basis * ray_dir).normalized()
		var aabb = mesh_inst.get_aabb()
		var t = _ray_intersect_aabb(local_origin, local_dir, aabb)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_hit = {"position": from + ray_dir * t}
	if not best_hit.is_empty():
		return best_hit
	var plane = Plane(Vector3.UP, 0.0)
	var denom = plane.normal.dot(to - from)
	if abs(denom) > 0.0001:
		var t = plane.distance_to(from) / denom
		if t >= 0.0 and t <= 1.0:
			return {"position": from.lerp(to, t)}
	return {}


func _entity_pick_distance(entity: Node3D, ray_origin: Vector3, ray_dir: Vector3) -> float:
	if not entity:
		return -1.0
	var visuals: Array = []
	_gather_visual_instances(entity, visuals)
	var best_t = INF
	for visual in visuals:
		var vis = visual as VisualInstance3D
		if not vis:
			continue
		var inv = vis.global_transform.affine_inverse()
		var local_origin = inv * ray_origin
		var local_dir = (inv.basis * ray_dir).normalized()
		var aabb = vis.get_aabb()
		var t = _ray_intersect_aabb(local_origin, local_dir, aabb)
		if t >= 0.0 and t < best_t:
			best_t = t
	if best_t < INF:
		return best_t
	var radius = max(0.5, grid_snap * 0.25)
	return _ray_intersect_sphere(ray_origin, ray_dir, entity.global_position, radius)


func _ray_intersect_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc = origin - center
	var b = oc.dot(dir)
	var c = oc.dot(oc) - radius * radius
	var h = b * b - c
	if h < 0.0:
		return -1.0
	var sqrt_h = sqrt(h)
	var t = -b - sqrt_h
	if t < 0.0:
		t = -b + sqrt_h
	return t if t >= 0.0 else -1.0


func _ray_intersect_aabb(origin: Vector3, dir: Vector3, aabb: AABB) -> float:
	var tmin = -INF
	var tmax = INF
	var min = aabb.position
	var max = aabb.position + aabb.size
	for i in range(3):
		var o = origin[i]
		var d = dir[i]
		if abs(d) < 0.00001:
			if o < min[i] or o > max[i]:
				return -1.0
		else:
			var inv = 1.0 / d
			var t1 = (min[i] - o) * inv
			var t2 = (max[i] - o) * inv
			if t1 > t2:
				var tmp = t1
				t1 = t2
				t2 = tmp
			tmin = max(tmin, t1)
			tmax = min(tmax, t2)
			if tmin > tmax:
				return -1.0
	if tmin < 0.0:
		return tmax
	return tmin


func _log(message: String) -> void:
	if not debug_logging:
		return
	print("[HammerForge LevelRoot] %s" % message)
