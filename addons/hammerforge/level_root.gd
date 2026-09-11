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
const HFGeometrySynth = preload("paint/hf_geometry_synth.gd")
const HFGeneratedReconciler = preload("paint/hf_reconciler.gd")
const HFStroke = preload("paint/hf_stroke.gd")
const HFHeightmapSynth = preload("paint/hf_heightmap_synth.gd")
const HFAutoConnectorType = preload("paint/hf_auto_connector.gd")
const HFHeightmapIO = preload("paint/hf_heightmap_io.gd")
const HFInputStateType = preload("input_state.gd")
const HFEntitySystemType = preload("systems/hf_entity_system.gd")
const HFBrushSystemType = preload("systems/hf_brush_system.gd")
const HFBakeSystemType = preload("systems/hf_bake_system.gd")
const BakeStatus = HFBakeSystemType.BakeStatus
const HFPaintSystemType = preload("systems/hf_paint_system.gd")
const HFFileSystemType = preload("systems/hf_file_system.gd")
const HFPrototypeTextures = preload("hf_prototype_textures.gd")
const HFIORuntime = preload("hf_io_runtime.gd")
const HFOutlineUtil = preload("hf_outline_util.gd")

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
	ICOSAHEDRON,
	CUSTOM  # Polygon/path tool brushes with custom face data (not axis-aligned)
}
enum AxisLock { NONE, X, Y, Z }

# ---------------------------------------------------------------------------
# Export vars
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Bounds for the settings that take a number
#
# #361 did this for the terrain settings. These are the same list and were not
# touched. The dock SpinBoxes have ranges, so the editor UI cannot produce a
# value outside them, but the `.hflevel` can: it is JSON, it is hand-editable, it
# gets merged, and it gets written by older builds with different defaults. An
# `@export_range` constrains the inspector widget only. It does not clamp an
# assignment and it is not enforced on load.
#
# Finiteness is checked first, because `clampf()` and `maxf()` both pass NaN
# through. `grid_snap` is the subtle one: every consumer is written
# `grid_snap if grid_snap > 0.0 else <fallback>`, and `NAN > 0.0` is false, so a
# NaN read as "snapping is off" everywhere while the dock still showed a number.
# ---------------------------------------------------------------------------

const MIN_GRID_PLANE_SIZE := 1.0
const MAX_GRID_PLANE_SIZE := 100000.0
const MIN_ROTATE_SNAP_DEGREES := 1.0
const MAX_ROTATE_SNAP_DEGREES := 180.0
const MIN_BAKE_CHUNK_SIZE := 1.0
const MAX_BAKE_CHUNK_SIZE := 16384.0
const MIN_LIGHTMAP_TEXEL_SIZE := 0.001
const MAX_LIGHTMAP_TEXEL_SIZE := 16.0
const MIN_NAVMESH_CELL := 0.01
const MAX_NAVMESH_CELL := 16.0
const MIN_NAVMESH_AGENT := 0.01
const MAX_NAVMESH_AGENT := 256.0
const MIN_CONNECTOR_STAIR_HEIGHT := 0.01
const MAX_CONNECTOR_STAIR_HEIGHT := 256.0
const MIN_CONNECTOR_WIDTH := 1
const MAX_CONNECTOR_WIDTH := 64


## A value inside the range, or the one already there when it is not a number.
##
## Refusing rather than substituting is deliberate: there is no nearest value to
## a NaN, and a setting that silently became a number nobody chose is the same
## class of surprise as one that stayed NaN.
static func _bounded(value: float, low: float, high: float, current: float) -> float:
	if not is_finite(value):
		HFLog.warn("HammerForge: %s is not a setting value, keeping %s" % [value, current])
		return current
	return clampf(value, low, high)


var _grid_snap: float = 16.0
@export var grid_snap: float = 16.0:
	set(value):
		_set_grid_snap(value)
	get:
		return _grid_snap
@export var brush_size_default: Vector3 = Vector3(32, 32, 32)
@export_range(1, 32, 1) var bake_collision_layer_index: int = 1
@export var bake_material_override: Material = null
var _bake_chunk_size: float = 32.0
@export var bake_chunk_size: float = 32.0:
	set(value):
		_bake_chunk_size = _bounded(
			value, MIN_BAKE_CHUNK_SIZE, MAX_BAKE_CHUNK_SIZE, _bake_chunk_size
		)
	get:
		return _bake_chunk_size
@export var bake_merge_meshes: bool = false
@export var bake_generate_lods: bool = false
@export var bake_unwrap_uv0: bool = false
@export var bake_lightmap_uv2: bool = false
var _bake_lightmap_texel_size: float = 0.1
@export var bake_lightmap_texel_size: float = 0.1:
	set(value):
		_bake_lightmap_texel_size = _bounded(
			value, MIN_LIGHTMAP_TEXEL_SIZE, MAX_LIGHTMAP_TEXEL_SIZE, _bake_lightmap_texel_size
		)
	get:
		return _bake_lightmap_texel_size
@export var bake_use_face_materials: bool = false
@export var bake_navmesh: bool = false
var _bake_navmesh_cell_size: float = 0.3
@export var bake_navmesh_cell_size: float = 0.3:
	set(value):
		_bake_navmesh_cell_size = _bounded(
			value, MIN_NAVMESH_CELL, MAX_NAVMESH_CELL, _bake_navmesh_cell_size
		)
	get:
		return _bake_navmesh_cell_size
var _bake_navmesh_cell_height: float = 0.25
@export var bake_navmesh_cell_height: float = 0.25:
	set(value):
		_bake_navmesh_cell_height = _bounded(
			value, MIN_NAVMESH_CELL, MAX_NAVMESH_CELL, _bake_navmesh_cell_height
		)
	get:
		return _bake_navmesh_cell_height
var _bake_navmesh_agent_height: float = 2.0
@export var bake_navmesh_agent_height: float = 2.0:
	set(value):
		_bake_navmesh_agent_height = _bounded(
			value, MIN_NAVMESH_AGENT, MAX_NAVMESH_AGENT, _bake_navmesh_agent_height
		)
	get:
		return _bake_navmesh_agent_height
var _bake_navmesh_agent_radius: float = 0.4
@export var bake_navmesh_agent_radius: float = 0.4:
	set(value):
		_bake_navmesh_agent_radius = _bounded(
			value, MIN_NAVMESH_AGENT, MAX_NAVMESH_AGENT, _bake_navmesh_agent_radius
		)
	get:
		return _bake_navmesh_agent_radius
@export var bake_visible_only: bool = false
@export var bake_use_multimesh: bool = false
@export var bake_use_atlas: bool = false
@export var bake_auto_connectors: bool = false
@export var bake_wire_io: bool = true
@export var bake_generate_occluders: bool = false
## Minimum face-group area (world units²) to generate an occluder.  Smaller
## surfaces rarely block enough pixels to justify the culling overhead.
@export var bake_occluder_min_area: float = 4.0
@export var bake_connector_mode: int = 0  # HFAutoConnector.ConnectorMode (RAMP=0, STAIRS=1, AUTO=2)
var _bake_connector_stair_height: float = 0.25
@export var bake_connector_stair_height: float = 0.25:
	set(value):
		_bake_connector_stair_height = _bounded(
			value,
			MIN_CONNECTOR_STAIR_HEIGHT,
			MAX_CONNECTOR_STAIR_HEIGHT,
			_bake_connector_stair_height
		)
	get:
		return _bake_connector_stair_height
var _bake_connector_width: int = 2
@export var bake_connector_width: int = 2:
	set(value):
		_bake_connector_width = clampi(value, MIN_CONNECTOR_WIDTH, MAX_CONNECTOR_WIDTH)
	get:
		return _bake_connector_width
@export var bake_use_thread_pool: bool = true
## Collision shape strategy: 0 = single trimesh (legacy), 1 = per-brush convex hulls,
## 2 = per-visgroup partitioned bodies.
@export_range(0, 2, 1) var bake_collision_mode: int = 0
## When bake_collision_mode >= 1, generate a convex hull per brush instead of one
## monolithic ConcavePolygonShape3D.  Per-brush convex shapes are faster for physics
## broadphase and produce better navigation meshes.
@export var bake_convex_clean: bool = true
## Simplification threshold for convex hull generation (0 = no simplification).
var _bake_convex_simplify: float = 0.0
@export_range(0.0, 1.0, 0.01) var bake_convex_simplify: float = 0.0:
	set(value):
		_bake_convex_simplify = _bounded(value, 0.0, 1.0, _bake_convex_simplify)
	get:
		return _bake_convex_simplify
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
var _grid_plane_size: float = 500.0
@export var grid_plane_size: float = 500.0:
	set(value):
		_grid_plane_size = _bounded(
			value, MIN_GRID_PLANE_SIZE, MAX_GRID_PLANE_SIZE, _grid_plane_size
		)
	get:
		return _grid_plane_size
@export var grid_color: Color = Color(0.85, 0.95, 1.0, 0.15)
@export_range(1, 16, 1) var grid_major_line_frequency: int = 4
@export var texture_lock: bool = true
## Step, in degrees, used by the rotate hotkeys and the dock's rotate buttons.
var _rotate_snap_degrees: float = 15.0
@export_range(1.0, 180.0, 1.0) var rotate_snap_degrees: float = 15.0:
	set(value):
		_rotate_snap_degrees = _bounded(
			value, MIN_ROTATE_SNAP_DEGREES, MAX_ROTATE_SNAP_DEGREES, _rotate_snap_degrees
		)
	get:
		return _rotate_snap_degrees
## Where rotate and flip pivot: 0 selection centre, 1 world origin, 2 active object.
@export_enum("Selection Center", "World Origin", "Active Object") var transform_pivot_mode: int = 0
@export var cordon_enabled: bool = false
var _cordon_aabb: AABB = AABB(Vector3(-128, -128, -128), Vector3(256, 256, 256))
@export var cordon_aabb: AABB = AABB(Vector3(-128, -128, -128), Vector3(256, 256, 256)):
	set(value):
		_set_cordon_aabb(value)
	get:
		return _cordon_aabb

# ---------------------------------------------------------------------------
# Signals — Central registry.  Subsystems and UI should subscribe to these
# rather than polling.  Emit via root.<signal>.emit(...) from subsystems.
# ---------------------------------------------------------------------------

# Bake lifecycle
signal bake_started
signal bake_finished(success: bool)
signal bake_progress(value: float, label: String)

# Settings
signal grid_snap_changed(value: float)

# Brush lifecycle
signal brush_added(brush_id: String)
signal brush_removed(brush_id: String)
signal brush_changed(brush_id: String)

# Entity lifecycle
signal entity_added(node: Node)
signal entity_removed(node: Node)

# Selection
signal selection_changed(brush_ids: Array)

# Paint
signal paint_layer_changed(layer_index: int)
signal paint_stroke_committed(changed_cell_count: int)
signal material_list_changed
signal face_selection_changed

# I/O
signal state_saved
signal state_loaded
signal autosave_failed(error_message: String)
signal hflevel_save_completed(path: String)
signal hflevel_save_failed(path: String, error_message: String)
signal user_message(text: String, level: int)

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

var grid_system
var entity_system: HFEntitySystemType
var brush_system: HFBrushSystemType
var drag_system
var bake_system: HFBakeSystemType
var paint_system: HFPaintSystemType
var state_system
var file_system: HFFileSystemType
var validation_system
var visgroup_system
var snap_system
var extrude_tool
var io_visualizer
var vertex_system
var carve_system
var subtract_preview
var carve_preview
var clip_preview
var hollow_preview
var spawn_system
var prefab_system
var prefab_overlay
var io_presets
var displacement_system
var bevel_system
var transform_system
var generator_system
var structure_preview
var array_preview

@export var show_subtract_preview: bool = false:
	set(value):
		show_subtract_preview = value
		if subtract_preview:
			subtract_preview.set_enabled(value)

# ---------------------------------------------------------------------------
# Dirty-tag system for selective reconciliation
# ---------------------------------------------------------------------------

var _dirty_brush_ids: Dictionary = {}  # brush_id -> true
var _dirty_paint_chunks: Array[Vector2i] = []
var _full_reconcile_needed := false


## Mark a specific brush as needing reconciliation.
func tag_brush_dirty(brush_id: String) -> void:
	_dirty_brush_ids[brush_id] = true
	# This is the one call every transform, material, UV, paint and vertex
	# mutation already makes, so it is where brush_changed belongs. Emit on
	# every tag rather than only the first: the dirty set is not cleared until
	# a bake, and a listener watching a drag needs each step, not just the one
	# that happened to arrive first.
	brush_changed.emit(brush_id)


## Mark a specific paint chunk as needing reconciliation.
func tag_paint_dirty(chunk_coord: Vector2i) -> void:
	if not _dirty_paint_chunks.has(chunk_coord):
		_dirty_paint_chunks.append(chunk_coord)


## Mark the entire scene as needing full reconciliation (structural changes).
func tag_full_reconcile() -> void:
	_full_reconcile_needed = true


## Consume and clear all dirty tags. Returns dict with keys:
## "brush_ids" (Array[String]), "paint_chunks" (Array[Vector2i]), "full" (bool).
func consume_dirty_tags() -> Dictionary:
	var result := {
		"brush_ids": _dirty_brush_ids.keys(),
		"paint_chunks": _dirty_paint_chunks.duplicate(),
		"full": _full_reconcile_needed,
	}
	_dirty_brush_ids.clear()
	_dirty_paint_chunks.clear()
	_full_reconcile_needed = false
	return result


# ---------------------------------------------------------------------------
# Signal batching — coalesce rapid signal emissions (e.g. multi-brush delete)
# ---------------------------------------------------------------------------

var _signal_batch_depth := 0
var _batched_signals: Array = []  # Array of {name: String, args: Array}
var _signal_batch_opened_msec := -1
var _signal_batch_stuck_reported := false

## How long an open batch may survive before it is treated as
## abandoned. Every batch in the plugin is opened and closed inside one
## synchronous operation, so a batch still open this long afterwards is one whose
## `end_signal_batch()` was skipped — which GDScript makes easy, since a runtime
## error unwinds the function and there is no `finally` to put the depth back.
## The consequence was invisible and permanent: `_emit_or_batch()` queued every
## level signal for the rest of the editor session, so the brush list, the entity
## list, the visgroup panel and the validation badge froze while editing carried
## on working, with nothing pointing at the operation that failed.
const SIGNAL_BATCH_STUCK_MSEC := 1000


## Begin batching signals. Nested calls are supported (depth-counted).
func begin_signal_batch() -> void:
	if _signal_batch_depth == 0:
		_signal_batch_opened_msec = Time.get_ticks_msec()
		_signal_batch_stuck_reported = false
	_signal_batch_depth += 1


## End batching. When depth returns to 0, flush coalesced signals.
func end_signal_batch() -> void:
	_signal_batch_depth -= 1
	if _signal_batch_depth <= 0:
		_signal_batch_depth = 0
		_signal_batch_opened_msec = -1
		_flush_batched_signals()


## Flush and clear a batch nothing closed. Called once per frame from _process.
func _release_stuck_signal_batch() -> void:
	if _signal_batch_depth <= 0 or _signal_batch_opened_msec < 0:
		return
	if Time.get_ticks_msec() - _signal_batch_opened_msec < SIGNAL_BATCH_STUCK_MSEC:
		return
	if not _signal_batch_stuck_reported:
		_signal_batch_stuck_reported = true
		push_warning(
			(
				(
					"HammerForge: a signal batch was left open (depth %d, %d queued). "
					+ "Releasing it so the dock keeps updating."
				)
				% [_signal_batch_depth, _batched_signals.size()]
			)
		)
	_signal_batch_depth = 0
	_signal_batch_opened_msec = -1
	_flush_batched_signals()


## Queue a signal for emission, or emit immediately if not batching.
func _emit_or_batch(signal_name: String, args: Array = []) -> void:
	if _signal_batch_depth > 0:
		_batched_signals.append({"name": signal_name, "args": args})
	else:
		_emit_signal_by_name(signal_name, args)


## Flush all queued signals in order, dropping exact repeats. Lifecycle events
## are emitted as themselves: a batch that removes brushes has to say so, and it
## has no business reporting dead ids as a selection.
func _flush_batched_signals() -> void:
	var pending: Array = _batched_signals
	_batched_signals = []
	var seen: Dictionary = {}
	for entry in pending:
		var sname: String = entry.get("name", "")
		if sname == "":
			continue
		var args: Array = entry.get("args", [])
		var key: Array = [sname, args]
		if seen.has(key):
			continue
		seen[key] = true
		_emit_signal_by_name(sname, args)


## Discard all queued signals without emitting (used on rollback).
func discard_signal_batch() -> void:
	_batched_signals.clear()
	_signal_batch_depth = 0
	_signal_batch_opened_msec = -1


func _emit_signal_by_name(signal_name: String, args: Array) -> void:
	match args.size():
		0:
			emit_signal(signal_name)
		1:
			emit_signal(signal_name, args[0])
		2:
			emit_signal(signal_name, args[0], args[1])
		3:
			emit_signal(signal_name, args[0], args[1], args[2])


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
var _face_hover_highlight: MeshInstance3D = null
var _face_hover_material: StandardMaterial3D = null
var _face_hover_st: SurfaceTool = null
var _face_hover_last_brush: Node3D = null
var _face_hover_last_face_idx: int = -1
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
var _last_bake_preview_mode: int = 0  # 0 = FULL, 1 = WIREFRAME, 2 = PROXY

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
	# Runtime baking and reload keep this small core. Editor tools are loaded below.
	entity_system = HFEntitySystemType.new(self)
	brush_system = HFBrushSystemType.new(self)
	# Serialized scenes already contain brushes before subsystem construction.
	# Build the live index once so counts, lookups, and the manager are correct
	# immediately rather than only after the first HammerForge-created brush.
	var repaired_brush_index := brush_system.reconcile_external_structure()
	# Dirty tags are intentionally transient. A reopened scene may therefore
	# contain source edits newer than its serialized BakedGeometry even when all
	# IDs are valid. Conservatively offer Bake Changed whenever editable source
	# or an existing bake is present; the first successful bake clears the flag.
	if (
		repaired_brush_index
		or brush_system.get_live_brush_count() > 0
		or get_node_or_null("BakedGeometry") != null
	):
		tag_full_reconcile()
	bake_system = HFBakeSystemType.new(self)
	bake_system.reconcile_baked_containers()
	paint_system = HFPaintSystemType.new(self)
	file_system = HFFileSystemType.new(self)
	if _should_initialize_editor_systems():
		_initialize_editor_systems()
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


func _should_initialize_editor_systems() -> bool:
	# Editor binaries keep these available to headless editor tests and tool scripts.
	# Export templates do not carry the editor feature and skip the whole graph.
	return Engine.is_editor_hint() or OS.has_feature("editor")


func _initialize_editor_systems() -> void:
	_setup_highlight()
	grid_system = load("res://addons/hammerforge/systems/hf_grid_system.gd").new(self)
	drag_system = load("res://addons/hammerforge/systems/hf_drag_system.gd").new(self)
	drag_system.input_state.on_force_reset = _on_input_state_force_reset
	state_system = load("res://addons/hammerforge/systems/hf_state_system.gd").new(self)
	validation_system = load("res://addons/hammerforge/systems/hf_validation_system.gd").new(self)
	visgroup_system = load("res://addons/hammerforge/systems/hf_visgroup_system.gd").new(self)
	snap_system = load("res://addons/hammerforge/hf_snap_system.gd").new(self)
	extrude_tool = load("res://addons/hammerforge/hf_extrude_tool.gd").new(self)
	io_visualizer = load("res://addons/hammerforge/systems/hf_io_visualizer.gd").new(self)
	vertex_system = load("res://addons/hammerforge/systems/hf_vertex_system.gd").new(self)
	carve_system = load("res://addons/hammerforge/systems/hf_carve_system.gd").new(self)
	subtract_preview = load("res://addons/hammerforge/systems/hf_subtract_preview.gd").new(self)
	carve_preview = load("res://addons/hammerforge/systems/hf_carve_preview.gd").new(self)
	clip_preview = load("res://addons/hammerforge/systems/hf_clip_preview.gd").new(self)
	hollow_preview = load("res://addons/hammerforge/systems/hf_hollow_preview.gd").new(self)
	spawn_system = load("res://addons/hammerforge/systems/hf_spawn_system.gd").new(self)
	prefab_system = load("res://addons/hammerforge/systems/hf_prefab_system.gd").new(self)
	prefab_overlay = load("res://addons/hammerforge/ui/hf_prefab_overlay.gd").new(self)
	io_presets = load("res://addons/hammerforge/systems/hf_io_presets.gd").new(self)
	io_presets.load_presets()
	displacement_system = load("res://addons/hammerforge/systems/hf_displacement_system.gd").new(
		self
	)
	bevel_system = load("res://addons/hammerforge/systems/hf_bevel_system.gd").new(self)
	transform_system = load("res://addons/hammerforge/systems/hf_transform_system.gd").new(self)
	generator_system = load("res://addons/hammerforge/systems/hf_generator_system.gd").new(self)
	structure_preview = load("res://addons/hammerforge/systems/hf_structure_preview.gd").new(self)
	array_preview = load("res://addons/hammerforge/systems/hf_array_preview.gd").new(self)
	if show_subtract_preview:
		subtract_preview.set_enabled(true)
	entity_system.load_entity_definitions()
	grid_system.setup_editor_grid()


func _exit_tree() -> void:
	if _autosave_timer:
		_autosave_timer.stop()
		if _autosave_timer.timeout.is_connected(_on_autosave_timeout):
			_autosave_timer.timeout.disconnect(_on_autosave_timeout)
		_autosave_timer.queue_free()
		_autosave_timer = null
	if _reload_timer:
		_reload_timer.stop()
		if _reload_timer.timeout.is_connected(_check_remote_reload):
			_reload_timer.timeout.disconnect(_check_remote_reload)
		_reload_timer.queue_free()
		_reload_timer = null
	if subtract_preview:
		subtract_preview.destroy()
	if carve_preview:
		carve_preview.destroy()
	if clip_preview:
		clip_preview.destroy()
	if hollow_preview:
		hollow_preview.destroy()
	if structure_preview:
		structure_preview.destroy()
	if array_preview:
		array_preview.destroy()
	if io_visualizer:
		io_visualizer.cleanup()
	# Cancel any in-flight tool previews so their nodes don't outlive the tree
	if extrude_tool:
		extrude_tool.cancel_extrude()
	if drag_system:
		drag_system._clear_preview()
	if file_system:
		file_system.shutdown()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_process_hflevel_saves()
	_release_stuck_signal_batch()
	if io_visualizer:
		io_visualizer.process(_delta)
	if subtract_preview and subtract_preview.is_enabled():
		subtract_preview.process(_delta)


func _process_hflevel_saves() -> void:
	file_system.process_thread_queue()
	for result in file_system.take_completed_saves():
		var write_error := str(result.get("error", ""))
		var save_path := str(result.get("path", ""))
		var is_autosave := bool(result.get("autosave", false))
		if write_error != "":
			if is_autosave:
				autosave_failed.emit(write_error)
			else:
				hflevel_save_failed.emit(save_path, write_error)
			continue
		state_saved.emit()
		if not is_autosave:
			hflevel_save_completed.emit(save_path)


# ===========================================================================
# Grid API (delegates to grid_system)
# ===========================================================================


func update_editor_grid(camera: Camera3D, mouse_pos: Vector2) -> void:
	if grid_system:
		grid_system.update_editor_grid(camera, mouse_pos)


func _refresh_grid_plane() -> void:
	if grid_system:
		grid_system.refresh_grid_plane()


# Reached from HFBrushSystem, which stays alive at runtime while grid_system does
# not, so this one has to tolerate a missing grid.
func _record_last_brush(center: Vector3) -> void:
	if grid_system:
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
# Visgroup / Group API (delegates to visgroup_system)
# ===========================================================================


func create_visgroup(vg_name: String, color: Color = Color.WHITE) -> void:
	if visgroup_system:
		visgroup_system.create_visgroup(vg_name, color)


func remove_visgroup(vg_name: String) -> void:
	if visgroup_system:
		visgroup_system.remove_visgroup(vg_name)


func set_visgroup_visible(vg_name: String, visible: bool) -> void:
	if visgroup_system:
		visgroup_system.set_visgroup_visible(vg_name, visible)


func add_selection_to_visgroup(vg_name: String, nodes: Array) -> void:
	if not visgroup_system:
		return
	for node in nodes:
		visgroup_system.add_to_visgroup(node, vg_name)
	visgroup_system.refresh_visibility()


func remove_selection_from_visgroup(vg_name: String, nodes: Array) -> void:
	if not visgroup_system:
		return
	for node in nodes:
		visgroup_system.remove_from_visgroup(node, vg_name)
	visgroup_system.refresh_visibility()


func get_visgroup_names() -> PackedStringArray:
	return visgroup_system.get_visgroup_names() if visgroup_system else PackedStringArray()


func refresh_visgroup_visibility() -> void:
	if visgroup_system:
		visgroup_system.refresh_visibility()


func group_selection(group_name: String, nodes: Array) -> void:
	if visgroup_system:
		visgroup_system.group_selection(group_name, nodes)


func ungroup_nodes(nodes: Array) -> void:
	if visgroup_system:
		visgroup_system.ungroup_nodes(nodes)


func get_group_members(group_name: String) -> Array:
	return visgroup_system.get_group_members(group_name) if visgroup_system else []


# ===========================================================================
# Cordon API
# ===========================================================================

var cordon_wireframe: MeshInstance3D = null
var _cordon_mesh: ImmediateMesh = null


func set_cordon_from_selection(nodes: Array) -> void:
	if nodes.is_empty():
		return
	var combined = AABB()
	var first := true
	for node in nodes:
		if not (node is Node3D):
			continue
		var n3d := node as Node3D
		var brush_aabb := AABB(n3d.global_position - Vector3.ONE, Vector3.ONE * 2.0)
		if n3d is DraftBrush:
			var brush := n3d as DraftBrush
			if brush.mesh_instance and brush.mesh_instance.mesh:
				brush_aabb = (
					brush.mesh_instance.global_transform * brush.mesh_instance.mesh.get_aabb()
				)
		if first:
			combined = brush_aabb
			first = false
		else:
			combined = combined.merge(brush_aabb)
	if not first:
		combined = combined.grow(1.0)
		cordon_aabb = combined
		cordon_enabled = true
		tag_full_reconcile()
		update_cordon_visual()


func update_cordon_visual() -> void:
	if not cordon_wireframe:
		cordon_wireframe = MeshInstance3D.new()
		cordon_wireframe.name = "CordonWireframe"
		cordon_wireframe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cordon_wireframe)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.0, 0.6)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		cordon_wireframe.material_override = mat
	cordon_wireframe.visible = cordon_enabled
	if not cordon_enabled:
		return
	# The corners below are world coordinates and this hangs off the LevelRoot, so
	# it has to be pinned to world space. Without this, a level whose root has been
	# moved or turned drew its cordon box a root transform away from the region the
	# box actually names — and that box is what says which part of the level a
	# partial bake will take.
	cordon_wireframe.global_transform = Transform3D.IDENTITY
	if not _cordon_mesh:
		_cordon_mesh = ImmediateMesh.new()
	else:
		_cordon_mesh.clear_surfaces()
	var im = _cordon_mesh
	var min_pt = cordon_aabb.position
	var max_pt = cordon_aabb.position + cordon_aabb.size
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners = [
		Vector3(min_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, min_pt.y, min_pt.z),
		Vector3(max_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, max_pt.y, min_pt.z),
		Vector3(min_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, min_pt.y, max_pt.z),
		Vector3(max_pt.x, max_pt.y, max_pt.z),
		Vector3(min_pt.x, max_pt.y, max_pt.z)
	]
	var edges = [
		[0, 1],
		[1, 2],
		[2, 3],
		[3, 0],
		[4, 5],
		[5, 6],
		[6, 7],
		[7, 4],
		[0, 4],
		[1, 5],
		[2, 6],
		[3, 7]
	]
	for edge in edges:
		im.surface_add_vertex(corners[edge[0]])
		im.surface_add_vertex(corners[edge[1]])
	im.surface_end()
	cordon_wireframe.mesh = im


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


func is_entity_node(node: Node) -> bool:
	return entity_system.is_entity_node(node)


## Backward-compat alias — prefer is_entity_node().
func _is_entity_node(node: Node) -> bool:
	return is_entity_node(node)


func _capture_entity_info(entity: DraftEntity) -> Dictionary:
	return entity_system.capture_entity_info(entity)


func _restore_entity_from_info(info: Dictionary) -> DraftEntity:
	return entity_system.restore_entity_from_info(info)


func build_duplicate_entity_info(entity: DraftEntity, offset: Vector3) -> Dictionary:
	return entity_system.build_duplicate_info(entity, offset)


func create_entities_from_infos(infos: Array) -> void:
	entity_system.create_entities_from_infos(infos)


func delete_entities_by_paths(entity_paths: Array) -> void:
	entity_system.delete_entities_by_paths(entity_paths)


func nudge_entities_by_paths(entity_paths: Array, offset: Vector3) -> void:
	entity_system.nudge_entities_by_paths(entity_paths, offset)


func _clear_entities() -> void:
	entity_system.clear_entities()


func add_entity_output(
	entity: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String = "",
	delay: float = 0.0,
	fire_once: bool = false
) -> void:
	entity_system.add_entity_output(
		entity, output_name, target_name, input_name, parameter, delay, fire_once
	)


func remove_entity_output(entity: Node, index: int) -> void:
	entity_system.remove_entity_output(entity, index)


func get_entity_outputs(entity: Node) -> Array:
	return entity_system.get_entity_outputs(entity)


func find_entities_by_name(entity_name: String) -> Array:
	return entity_system.find_entities_by_name(entity_name)


func cleanup_dangling_connections(deleted_name: String) -> int:
	return entity_system.cleanup_dangling_connections(deleted_name)


func get_all_entity_connections() -> Array:
	return entity_system.get_all_connections()


func set_highlight_connected(value: bool) -> void:
	if io_visualizer:
		io_visualizer.set_highlight_connected(value)


func set_io_visualizer_selection(nodes: Array) -> void:
	if io_visualizer:
		io_visualizer.set_selected_entities(nodes)


func get_connection_summary(entity_name: String) -> Dictionary:
	if io_visualizer:
		return io_visualizer.get_connection_summary(entity_name)
	return {}


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
	begin_signal_batch()
	for info in infos:
		if info is Dictionary:
			brush_system.create_brush_from_info(info)
	end_signal_batch()


func delete_brush(brush: Node, free: bool = true) -> void:
	brush_system.delete_brush(brush, free)


func delete_brush_by_id(brush_id: String) -> HFOpResult:
	return brush_system.delete_brush_by_id(brush_id)


func delete_brushes_by_id(brush_ids: Array) -> void:
	begin_signal_batch()
	for brush_id in brush_ids:
		brush_system.delete_brush_by_id(str(brush_id))
	end_signal_batch()


func duplicate_brush(brush: Node) -> Node:
	return brush_system.duplicate_brush(brush)


func nudge_brushes_by_id(brush_ids: Array, offset: Vector3) -> void:
	begin_signal_batch()
	brush_system.nudge_brushes_by_id(brush_ids, offset)
	end_signal_batch()


func delete_managed_nodes(brush_ids: Array, entity_paths: Array) -> void:
	begin_signal_batch()
	delete_brushes_by_id(brush_ids)
	delete_entities_by_paths(entity_paths)
	end_signal_batch()


func create_managed_duplicates(brush_infos: Array, entity_infos: Array) -> void:
	create_brushes_from_infos(brush_infos)
	create_entities_from_infos(entity_infos)


func nudge_managed_nodes(brush_ids: Array, entity_paths: Array, offset: Vector3) -> void:
	nudge_brushes_by_id(brush_ids, offset)
	nudge_entities_by_paths(entity_paths, offset)


# ---------------------------------------------------------------------------
# Transform API (delegates to transform_system)
#
# These are the method names HFUndoHelper dispatches by, so their signatures are
# what undo replays. Each stays at five arguments or fewer to keep off the
# helper's direct-call fallback path.
# ---------------------------------------------------------------------------


func rotate_managed_nodes(
	brush_ids: Array, entity_paths: Array, axis_index: int, angle_degrees: float, pivot: Vector3
) -> void:
	if not transform_system:
		return
	begin_signal_batch()
	transform_system.rotate(brush_ids, entity_paths, axis_index, deg_to_rad(angle_degrees), pivot)
	end_signal_batch()


func flip_managed_nodes(
	brush_ids: Array, entity_paths: Array, axis_index: int, pivot: Vector3
) -> void:
	if not transform_system:
		return
	begin_signal_batch()
	transform_system.flip(brush_ids, entity_paths, axis_index, pivot)
	end_signal_batch()


func reset_managed_rotation(brush_ids: Array) -> void:
	if not transform_system:
		return
	begin_signal_batch()
	transform_system.reset_rotation(brush_ids)
	end_signal_batch()


## Axis the transform commands act on: the active axis lock when the user has set
## one, and otherwise the caller's default — yaw for rotate, left-right for flip.
func transform_axis_index(fallback: int) -> int:
	var lock: int = int(axis_lock)
	return lock - 1 if lock >= 1 and lock <= 3 else fallback


## Pivot for a selection under the current `transform_pivot_mode`.
func resolve_transform_pivot(brush_ids: Array, entity_paths: Array) -> Vector3:
	if not transform_system:
		return Vector3.ZERO
	return transform_system.resolve_pivot(brush_ids, entity_paths, transform_pivot_mode)


## The way the selection is facing, when every part of it faces the same way.
## Identity otherwise, and for a selection that has been mirrored or scaled.
func resolve_selection_basis(brush_ids: Array, entity_paths: Array) -> Basis:
	if not transform_system:
		return Basis.IDENTITY
	return transform_system.resolve_selection_basis(brush_ids, entity_paths)


func can_flip_brushes(brush_ids: Array) -> HFOpResult:
	if not transform_system:
		return HFOpResult.fail("Flip: transform system unavailable")
	return transform_system.can_flip_brushes(brush_ids)


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


func reconcile_external_brush_structure() -> bool:
	if brush_system:
		return brush_system.reconcile_external_structure()
	return false


func reconcile_external_entity_names(previous_names: Dictionary, current_names: Dictionary) -> void:
	if entity_system:
		entity_system.reconcile_external_names(previous_names, current_names)


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


func prepare_commit_cuts() -> bool:
	return await brush_system.prepare_commit_cuts()


func finalize_commit_cuts() -> void:
	brush_system.finalize_commit_cuts()


func commit_cuts() -> bool:
	return await brush_system.commit_cuts()


func restore_committed_cuts() -> void:
	brush_system.restore_committed_cuts()


func clear_brushes() -> void:
	brush_system.clear_brushes()


func _clear_generated() -> void:
	brush_system._clear_generated()


func can_hollow_brush(brush_id: String, wall_thickness: float) -> HFOpResult:
	return brush_system.can_hollow_brush(brush_id, wall_thickness)


func can_clip_brush(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	return brush_system.can_clip_brush(brush_id, axis, split_pos)


func hollow_brush_by_id(brush_id: String, wall_thickness: float) -> HFOpResult:
	return brush_system.hollow_brush_by_id(brush_id, wall_thickness)


func can_merge_brushes(brush_ids: Array) -> HFOpResult:
	return brush_system.can_merge_brushes(brush_ids)


func merge_brushes_by_ids(brush_ids: Array) -> HFOpResult:
	return brush_system.merge_brushes_by_ids(brush_ids)


func move_brushes_to_floor(brush_ids: Array) -> void:
	brush_system.move_brushes_to_floor(brush_ids)


func move_brushes_to_ceiling(brush_ids: Array) -> void:
	brush_system.move_brushes_to_ceiling(brush_ids)


## Build an arch centred on `centre`, one brush per segment.
##
## Undo dispatches by these names, so their signatures are what undo replays.
func create_arch(settings: Dictionary, centre: Vector3) -> HFOpResult:
	return create_generator("arch", settings, Transform3D(Basis.IDENTITY, centre))


## Build a structure and keep a record of it, so it can be rebuilt differently.
func create_generator(type: String, settings: Dictionary, placement: Transform3D) -> HFOpResult:
	if not generator_system:
		return HFOpResult.fail("Generator: system unavailable")
	begin_signal_batch()
	var result: HFOpResult = generator_system.create(type, settings, placement)
	end_signal_batch()
	if not result.ok:
		user_message.emit(result.user_text(), 1)
	return result


## Rebuild an existing structure from new settings, in place.
func regenerate_generator(generator_id: String, settings: Dictionary) -> HFOpResult:
	if not generator_system:
		return HFOpResult.fail("Generator: system unavailable")
	begin_signal_batch()
	var result: HFOpResult = generator_system.regenerate(generator_id, settings)
	end_signal_batch()
	if not result.ok:
		user_message.emit(result.user_text(), 1)
	return result


## Forget a structure's record, leaving its brushes as ordinary geometry.
func detach_generator(generator_id: String) -> bool:
	return generator_system.detach(generator_id) if generator_system else false


func generator_for_selection(brush_ids: Array):
	return generator_system.generator_for_selection(brush_ids) if generator_system else null


## How many pieces of a structure are no longer the shape they were generated as.
## What the dock says out loud before a rebuild overwrites them.
func edited_generator_pieces(generator_id: String) -> int:
	return generator_system.edited_piece_count(generator_id) if generator_system else 0


## Whether these settings would build. Asked before an undo action is opened.
func can_build_generator(type: String, settings: Dictionary) -> HFOpResult:
	return HFGeneratorSystem.can_build(type, settings)


## How many live structures the level holds. The dock reads this either side of a
## build to tell a real one from a refused one.
func generator_count() -> int:
	return generator_system.generators.size() if generator_system else 0


func has_generator(generator_id: String) -> bool:
	return generator_system != null and generator_system.generators.has(generator_id)


func generator_for_id(generator_id: String):
	return generator_system.generator_for_id(generator_id) if generator_system else null


## The generated pieces whose painted faces a rebuild with these settings could
## not put back.
func generator_appearance_at_risk(generator_id: String, settings: Dictionary) -> PackedStringArray:
	if not generator_system:
		return PackedStringArray()
	return generator_system.appearance_at_risk(generator_id, settings)


## Whether the pieces of this structure no longer agree on where it is. A rebuild
## then has nowhere to put it but the placement it was created at.
func generator_pieces_disagree(generator_id: String) -> bool:
	if not generator_system:
		return false
	return generator_system.pieces_disagree_about_placement(generator_id)


## Where a rebuild of this structure would stand, so a preview of it can stand
## there too.
func generator_rebuild_placement(generator_id: String) -> Transform3D:
	if not generator_system:
		return Transform3D.IDENTITY
	return generator_system.rebuild_placement(generator_id)


## Draw a wireframe of what these settings would build, without building it.
## Returns the number of pieces shown; zero means the settings do not build.
func preview_structure(type: String, settings: Dictionary, placement: Transform3D) -> int:
	if not structure_preview:
		return 0
	return structure_preview.show_preview(type, settings, placement)


func clear_structure_preview() -> void:
	if structure_preview:
		structure_preview.clear()


## Draw a wireframe of the copies an array would make, without making them.
## Returns the number of copies shown; zero means the array will not be built.
func preview_array(brush_ids: Array, placements: Array) -> int:
	if not array_preview:
		return 0
	return array_preview.show_preview(brush_ids, placements)


func clear_array_preview() -> void:
	if array_preview:
		array_preview.clear()


## How many copies the array ghost is currently showing.
func array_preview_copies() -> int:
	return array_preview.copy_count() if array_preview else 0


## How many pieces the structure ghost is currently showing.
func structure_preview_pieces() -> int:
	return structure_preview.piece_count() if structure_preview else 0


func clip_brush_by_plane(brush_id: String, plane: Plane) -> HFOpResult:
	return brush_system.clip_brush_by_plane(brush_id, plane)


func clip_brush_to_face_plane(
	brush_id: String, source_brush_id: String, face_index: int
) -> HFOpResult:
	return brush_system.clip_brush_to_face_plane(brush_id, source_brush_id, face_index)


func face_world_plane(source_brush_id: String, face_index: int) -> Plane:
	return brush_system.face_world_plane(source_brush_id, face_index)


func plane_splits_brush(brush_id: String, plane: Plane) -> bool:
	return brush_system.plane_splits_brush(brush_id, plane)


## Named for the undo helper, which resolves the do method on LevelRoot by name.
func clip_brushes_by_plane(brush_ids: Array, plane: Plane) -> int:
	return brush_system.clip_brushes_by_plane(brush_ids, plane)


func clip_brush_by_id(brush_id: String, axis: int, split_pos: float) -> HFOpResult:
	return brush_system.clip_brush_by_id(brush_id, axis, split_pos)


func carve_with_brush(brush_id: String) -> HFOpResult:
	return carve_system.carve_with_brush(brush_id)


func clip_brush_at_point(brush_id: String, face_idx: int, hit_position: Vector3) -> void:
	brush_system.clip_brush_at_point(brush_id, face_idx, hit_position)


func tie_brushes_to_entity(brush_ids: Array, entity_class: String) -> void:
	brush_system.tie_brushes_to_entity(brush_ids, entity_class)


func untie_brushes_from_entity(brush_ids: Array) -> void:
	brush_system.untie_brushes_from_entity(brush_ids)


# ===========================================================================
# Displacement API (delegates to displacement_system)
# ===========================================================================


func create_displacement(brush_id: String, face_index: int, power: int = 3) -> bool:
	var ok: bool = displacement_system.create_displacement(brush_id, face_index, power)
	if ok:
		tag_brush_dirty(brush_id)
	return ok


func destroy_displacement(brush_id: String, face_index: int) -> bool:
	var ok: bool = displacement_system.destroy_displacement(brush_id, face_index)
	if ok:
		tag_brush_dirty(brush_id)
	return ok


func set_displacement_elevation(brush_id: String, face_index: int, elevation: float) -> bool:
	return displacement_system.set_elevation(brush_id, face_index, elevation)


func set_displacement_power(brush_id: String, face_index: int, power: int) -> bool:
	var ok: bool = displacement_system.set_power(brush_id, face_index, power)
	if ok:
		tag_brush_dirty(brush_id)
	return ok


func smooth_displacement(brush_id: String, face_index: int, strength: float) -> bool:
	return displacement_system.smooth_all(brush_id, face_index, strength)


func noise_displacement(brush_id: String, face_index: int, scale: float) -> bool:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.1
	return displacement_system.apply_noise(brush_id, face_index, noise, scale)


func set_displacement_sew_group(brush_id: String, face_index: int, sew_group_id: int) -> bool:
	var brush: Node3D = find_brush_by_id(brush_id)
	if not brush:
		return false
	var faces: Array = brush.faces
	if face_index < 0 or face_index >= faces.size():
		return false
	if faces[face_index].displacement == null:
		return false
	faces[face_index].displacement.sew_group = sew_group_id
	tag_brush_dirty(brush_id)
	return true


func sew_all_displacements() -> int:
	return displacement_system.sew_all()


func paint_displacement(
	brush_id: String, face_index: int, world_pos: Vector3, radius: float, strength: float, mode: int
) -> bool:
	return displacement_system.paint(brush_id, face_index, world_pos, radius, strength, mode)


# ===========================================================================
# Bevel API (delegates to bevel_system)
# ===========================================================================


func bevel_edge(brush_id: String, edge: Array, segments: int, radius: float) -> bool:
	var ok: bool = bevel_system.bevel_edge(brush_id, edge, segments, radius)
	if ok:
		tag_brush_dirty(brush_id)
	return ok


func inset_face(brush_id: String, face_index: int, inset_distance: float, height: float) -> bool:
	var ok: bool = bevel_system.inset_face(brush_id, face_index, inset_distance, height)
	if ok:
		tag_brush_dirty(brush_id)
	return ok


func justify_selected_faces(mode: String, treat_as_one: bool) -> void:
	brush_system.justify_selected_faces(mode, treat_as_one)


func create_duplicate_array(brush_ids: PackedStringArray, count: int, p_offset: Vector3) -> Variant:
	return brush_system.create_duplicate_array(brush_ids, count, p_offset)


func create_radial_array(
	brush_ids: PackedStringArray,
	count: int,
	axis_index: int,
	step_degrees: float,
	pivot: Vector3,
	rise: float = 0.0
) -> Variant:
	return brush_system.create_radial_array(brush_ids, count, axis_index, step_degrees, pivot, rise)


func create_grid_array(brush_ids: PackedStringArray, counts: Vector3i, spacing: Vector3) -> Variant:
	return brush_system.create_grid_array(brush_ids, counts, spacing)


func remove_duplicate_array(duplicator_id: String) -> void:
	brush_system.remove_duplicate_array(duplicator_id)


## Rebuild an existing array from new numbers, keeping the same array.
##
## A rebuild deletes and re-creates every copy, so the signals it would emit one
## brush at a time are batched the way every other multi-brush operation batches
## them.
func update_duplicate_array(duplicator_id: String, mode: int, params: Dictionary) -> bool:
	begin_signal_batch()
	var ok: bool = brush_system.update_duplicate_array(duplicator_id, mode, params)
	end_signal_batch()
	return ok


## Forget an array's record, leaving its copies as ordinary brushes.
func detach_duplicate_array(duplicator_id: String) -> bool:
	return brush_system.detach_duplicate_array(duplicator_id)


func duplicator_for_id(duplicator_id: String) -> Variant:
	return brush_system.duplicator_for_id(duplicator_id)


func duplicator_for_selection(brush_ids: Array) -> Variant:
	return brush_system.duplicator_for_selection(brush_ids)


## Shell the same solid again at a different wall thickness, keeping the hollow.
func update_hollow(hollow_id: String, thickness: float) -> HFOpResult:
	begin_signal_batch()
	var result: HFOpResult = brush_system.update_hollow(hollow_id, thickness)
	end_signal_batch()
	if not result.ok:
		user_message.emit(result.user_text(), 1)
	return result


## Forget a hollow's record, leaving its walls as ordinary brushes.
func detach_hollow(hollow_id: String) -> bool:
	return brush_system.detach_hollow(hollow_id)


func hollow_for_id(hollow_id: String) -> Variant:
	return brush_system.hollow_for_id(hollow_id)


func hollow_for_selection(brush_ids: Array) -> Variant:
	return brush_system.hollow_for_selection(brush_ids)


## How many walls of a hollow have been reworked by hand: moved off the placement
## the shell put them at, or resized, retextured or painted since. What the dock
## says out loud before a Re-hollow rebuilds over them.
func edited_hollow_walls(hollow_id: String) -> int:
	return brush_system.edited_hollow_walls(hollow_id)


## How many copies of an array have been edited by hand: dragged off the
## placement it puts them at, or reshaped or repainted since it made them. What
## the dock says out loud before an Update rebuilds over them.
func edited_array_copies(duplicator_id: String) -> int:
	var dup = brush_system.duplicator_for_id(duplicator_id)
	if dup == null:
		return 0
	return dup.edited_copy_ids(brush_system).size()


## Whether an array's copies have all been left behind by a source that moved,
## rather than dragged about one at a time.
func array_copies_follow_a_moved_source(duplicator_id: String) -> bool:
	var dup = brush_system.duplicator_for_id(duplicator_id)
	if dup == null:
		return false
	return dup.copies_follow_a_moved_source(brush_system)


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
	var before := face.to_dict()
	face.custom_uvs = PackedVector2Array()
	face.ensure_custom_uvs()
	draft.rebuild_preview()
	if face.to_dict() != before:
		tag_brush_dirty(brush_id)


## Whether a UV scale, offset and rotation can be written onto a face.
##
## A non-finite value here reaches the mesh's UV channel, where the vertex is
## discarded or drawn undefined depending on the driver, and it survives the save
## — so reopening the level does not clear it, and the geometry still looks
## right, which is why nobody thinks to look at the UVs. A scale component of
## zero collapses every vertex of the face onto one texel and cannot be undone by
## scaling back up. A negative scale is allowed on purpose: it mirrors the
## texture, which is a thing to want.
func is_usable_uv_transform(scale: Vector2, offset: Vector2, rotation: float) -> bool:
	if not scale.is_finite() or not offset.is_finite() or not is_finite(rotation):
		HFLog.warn("LevelRoot: a UV transform needs finite numbers")
		return false
	if is_zero_approx(scale.x) or is_zero_approx(scale.y):
		HFLog.warn("LevelRoot: a UV scale of zero is not a scale")
		return false
	return true


## Whether a material slot names something in the palette.
##
## `-1` is the default slot and means no material. Anything else has to be an
## index into the palette: the bake, the `.map` exporter and the UV editor all
## resolve the slot, and each of their fallbacks for a slot that is not there
## gives the face something other than what the mapper picked.
func is_usable_material_slot(material_index: int) -> bool:
	if material_index == -1:
		return true
	if material_index < 0 or material_index >= get_materials().size():
		HFLog.warn(
			(
				"LevelRoot: material slot %d is not in a palette of %d"
				% [material_index, get_materials().size()]
			)
		)
		return false
	return true


func reproject_face_uvs(brush_id: String, face_idx: int, projection: int) -> void:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return
	if not FaceData.is_valid_projection(projection):
		HFLog.warn("LevelRoot: %d is not a UV projection" % projection)
		return
	var face: FaceData = draft.faces[face_idx]
	var before := face.to_dict()
	face.uv_projection = projection
	face.uv_scale = Vector2.ONE
	face.uv_offset = Vector2.ZERO
	face.uv_rotation = 0.0
	face.custom_uvs = PackedVector2Array()
	face.ensure_custom_uvs()
	draft.rebuild_preview()
	if face.to_dict() != before:
		tag_brush_dirty(brush_id)


## Set UV transform params on a specific face. Used by undo-capable state actions.
func set_face_uv_params(
	brush_id: String, face_idx: int, scale: Vector2, offset: Vector2, rotation: float
) -> void:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return
	if not is_usable_uv_transform(scale, offset, rotation):
		return
	var face: FaceData = draft.faces[face_idx]
	var before := face.to_dict()
	face.uv_scale = scale
	face.uv_offset = offset
	# Stored wrapped so two faces that look the same compare the same, and so a
	# run of turns cannot walk the angle off to where a float has no fraction left.
	face.uv_rotation = wrapf(rotation, -PI, PI)
	face.custom_uvs = PackedVector2Array()
	face.ensure_custom_uvs()
	draft.rebuild_preview()
	if face.to_dict() != before:
		tag_brush_dirty(brush_id)


func clip_brush_to_convex(brush_id: String) -> bool:
	if not vertex_system:
		return false
	return vertex_system.clip_to_convex(brush_id)


## How many textures may be blended over one face.
##
## `get_painted_albedo()` composites the layers into one image by walking every
## layer at every texel, and that runs on each `rebuild_preview()` and again at
## bake. Past a handful the result is not visibly different and each extra layer
## is preview time, save size and load time for nothing. Nothing in the dock
## stopped a mapper clicking Add, because there was no limit to stop them at.
const MAX_SURFACE_PAINT_LAYERS := 8


## Returns whether a layer was added.
func add_surface_paint_layer(brush_id: String, face_idx: int) -> bool:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return false
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return false
	var face: FaceData = draft.faces[face_idx]
	if face.paint_layers.size() >= MAX_SURFACE_PAINT_LAYERS:
		HFLog.warn(
			"LevelRoot: a face blends at most %d surface paint layers" % MAX_SURFACE_PAINT_LAYERS
		)
		return false
	face.paint_layers.append(FaceData.PaintLayer.new())
	draft.rebuild_preview()
	tag_brush_dirty(brush_id)
	return true


## Returns whether a layer was removed, so a caller can tell a removal from a
## no-op — an index out of range used to do nothing and say nothing.
func remove_surface_paint_layer(brush_id: String, face_idx: int, layer_idx: int) -> bool:
	var brush = brush_system.find_brush_by_id(brush_id)
	if not brush or not (brush is DraftBrush):
		return false
	var draft := brush as DraftBrush
	if face_idx < 0 or face_idx >= draft.faces.size():
		return false
	var layers = draft.faces[face_idx].paint_layers
	if layer_idx < 0 or layer_idx >= layers.size():
		return false
	layers.remove_at(layer_idx)
	draft.rebuild_preview()
	tag_brush_dirty(brush_id)
	return true


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
	if layers[layer_idx].texture == texture:
		return
	layers[layer_idx].texture = texture
	draft.rebuild_preview()
	tag_brush_dirty(brush_id)


func _clear_preview() -> void:
	brush_system._clear_preview()


func pick_brush(camera: Camera3D, mouse_pos: Vector2, include_entities: bool = true) -> Node:
	return brush_system.pick_brush(camera, mouse_pos, include_entities)


func update_hover(camera: Camera3D, mouse_pos: Vector2, selected_nodes: Array = []) -> void:
	brush_system.update_hover(camera, mouse_pos, selected_nodes)


func clear_hover() -> void:
	brush_system.clear_hover()


func pick_face(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	return brush_system.pick_face(camera, mouse_pos)


func select_face_at_screen(
	camera: Camera3D, mouse_pos: Vector2, additive: bool, toggle: bool = false
) -> bool:
	var old_sel := face_selection.duplicate(true)
	var result := brush_system.select_face_at_screen(camera, mouse_pos, additive, toggle)
	if face_selection != old_sel:
		face_selection_changed.emit()
	return result


func toggle_face_selection(
	brush: DraftBrush, face_idx: int, additive: bool, toggle: bool = true
) -> void:
	brush_system.toggle_face_selection(brush, face_idx, additive, toggle)
	face_selection_changed.emit()


func clear_face_selection() -> void:
	brush_system.clear_face_selection()
	face_selection_changed.emit()


func get_face_selection() -> Dictionary:
	return brush_system.get_face_selection()


func get_primary_selected_face() -> Dictionary:
	return brush_system.get_primary_selected_face()


func assign_material_to_selected_faces(material_index: int) -> int:
	if not is_usable_material_slot(material_index):
		return 0
	return brush_system.assign_material_to_selected_faces(material_index)


func assign_material_to_faces_by_id(
	brush_key: String, face_indices: Array, material_index: int
) -> void:
	var brush: DraftBrush = brush_system.find_brush_by_id(brush_key)
	if not brush or not is_instance_valid(brush):
		return
	if not is_usable_material_slot(material_index):
		return
	var typed_indices: Array[int] = []
	var changed := false
	for fi in face_indices:
		var face_idx := int(fi)
		typed_indices.append(face_idx)
		if (
			face_idx >= 0
			and face_idx < brush.faces.size()
			and brush.faces[face_idx].material_idx != material_index
		):
			changed = true
	brush.assign_material_to_faces(material_index, typed_indices)
	if changed:
		tag_brush_dirty(brush_key)


func assign_material_to_whole_brushes(material_index: int, brush_ids: Array) -> int:
	if not is_usable_material_slot(material_index):
		return 0
	var count := 0
	for bid in brush_ids:
		var brush: DraftBrush = brush_system._find_brush_by_key(str(bid))
		if not brush or not is_instance_valid(brush):
			continue
		var all_indices: Array[int] = []
		var changed := false
		for i in range(brush.faces.size()):
			all_indices.append(i)
			if brush.faces[i].material_idx != material_index:
				changed = true
		brush.assign_material_to_faces(material_index, all_indices)
		if changed:
			tag_brush_dirty(str(bid))
		count += all_indices.size()
	return count


func assign_material_and_reproject(material_index: int, projection: int) -> int:
	if not is_usable_material_slot(material_index):
		return 0
	if not FaceData.is_valid_projection(projection):
		HFLog.warn("LevelRoot: %d is not a UV projection" % projection)
		return 0
	var sel = get_face_selection()
	var count := 0
	for brush_key in sel.keys():
		var brush: DraftBrush = brush_system.find_brush_by_id(brush_key)
		if not brush or not is_instance_valid(brush):
			continue
		var face_indices: Array = sel[brush_key]
		var typed_indices: Array[int] = []
		var before_by_index: Dictionary = {}
		for fi in face_indices:
			var face_idx := int(fi)
			typed_indices.append(face_idx)
			if face_idx >= 0 and face_idx < brush.faces.size():
				before_by_index[face_idx] = brush.faces[face_idx].to_dict()
		brush.assign_material_to_faces(material_index, typed_indices)
		for fi in typed_indices:
			if fi >= 0 and fi < brush.faces.size():
				var face: FaceData = brush.faces[fi]
				face.uv_projection = projection
				face.uv_scale = Vector2.ONE
				face.uv_offset = Vector2.ZERO
				face.uv_rotation = 0.0
				face.custom_uvs = PackedVector2Array()
				face.ensure_custom_uvs()
		brush.rebuild_preview()
		var changed := false
		for fi in before_by_index:
			if brush.faces[int(fi)].to_dict() != before_by_index[fi]:
				changed = true
				break
		if changed:
			tag_brush_dirty(str(brush_key))
		count += typed_indices.size()
	return count


func _apply_face_selection() -> void:
	brush_system._apply_face_selection()


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


## Called by HFInputState when a begin_* guard fires from a non-IDLE mode.
## Tears down whatever tool implementation was active for the old mode so
## the state machine and tool objects stay in sync.
func _on_input_state_force_reset(old_mode: int) -> void:
	if old_mode == HFInputStateType.Mode.DRAG_BASE or old_mode == HFInputStateType.Mode.DRAG_HEIGHT:
		drag_system._clear_preview()
	elif old_mode == HFInputStateType.Mode.EXTRUDE:
		extrude_tool.cancel_extrude()
	elif old_mode == HFInputStateType.Mode.VERTEX_EDIT:
		if vertex_system:
			vertex_system.clear_selection()


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
	var started: bool = extrude_tool.begin_extrude(camera, mouse_pos, extrude_direction)
	if started and drag_system:
		drag_system.input_state.begin_extrude()
	return started


func update_extrude(camera: Camera3D, mouse_pos: Vector2) -> void:
	extrude_tool.update_extrude(camera, mouse_pos)
	# If the tool self-cancelled (e.g. source brush deleted), sync input_state
	if not extrude_tool.active and drag_system and drag_system.input_state.is_extruding():
		drag_system.input_state.end_extrude()


func end_extrude_info() -> Dictionary:
	var info: Dictionary = extrude_tool.end_extrude_info()
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


## Bake the level. Returns true only when geometry was produced.
##
## false is ambiguous on its own: the bake may have been refused because one was
## already running (LevelRoot starts its own when a level loads), or it may have
## genuinely failed. Call get_last_bake_status() immediately afterwards to tell
## them apart, or wait for is_bake_in_flight() to clear before calling.
func bake(
	apply_cuts: bool = true,
	hide_live: bool = false,
	collision_layer_mask: int = 0,
	preview_mode: int = 0,
	force_csg: bool = false
) -> bool:
	return await bake_system.bake(
		apply_cuts, hide_live, collision_layer_mask, preview_mode, force_csg
	)


func bake_selected(
	brush_nodes: Array, collision_layer_mask: int = 0, preview_mode: int = 0
) -> bool:
	if bake_system:
		return await bake_system.bake_selected(brush_nodes, collision_layer_mask, preview_mode)
	return false


func bake_dirty(collision_layer_mask: int = 0, preview_mode: int = 0) -> bool:
	if bake_system:
		return await bake_system.bake_dirty(collision_layer_mask, preview_mode)
	return false


func is_bake_in_flight() -> bool:
	return bake_system != null and bake_system.is_bake_in_flight()


func was_last_bake_successful() -> bool:
	return bake_system != null and bake_system._last_bake_success


## Why the most recent bake call returned what it did, as a BakeStatus. Read it
## immediately after the call: the next one overwrites it.
func get_last_bake_status() -> int:
	if bake_system == null:
		return BakeStatus.NOT_RUN
	return bake_system.get_last_bake_status()


func estimate_bake_time(brush_ids: Array = []) -> Dictionary:
	return bake_system.estimate_bake_time(brush_ids) if bake_system else {}


func bake_dry_run() -> Dictionary:
	return bake_system.bake_dry_run() if bake_system else {}


func clear_baked_geometry() -> void:
	if bake_system:
		bake_system.clear_baked_containers()


func capture_baked_geometry_snapshot() -> PackedScene:
	return bake_system.capture_baked_geometry_snapshot() if bake_system else null


func restore_state_with_baked_snapshot(state: Dictionary, baked_snapshot: PackedScene) -> void:
	var preview_mode := int(state.get("bake_preview_mode", 0))
	restore_state(state)
	if bake_system:
		# Snapshot metadata is authoritative for current actions. The state value
		# keeps snapshots created before preview-mode metadata backward compatible.
		bake_system.restore_baked_geometry_snapshot(baked_snapshot, preview_mode)


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
	paint_brush_shape: int = 1,
	paint_options: Dictionary = {}
) -> bool:
	return paint_system.handle_paint_input(
		camera,
		event,
		screen_pos,
		operation,
		size,
		paint_tool_id,
		paint_radius_cells,
		paint_brush_shape,
		paint_options
	)


func prepare_paint_stroke(camera: Camera3D, screen_pos: Vector2) -> void:
	paint_system.prepare_paint_stroke(camera, screen_pos)


func get_paint_layer_names() -> Array:
	return paint_system.get_paint_layer_names()


func get_active_paint_layer_index() -> int:
	return paint_system.get_active_paint_layer_index()


func set_active_paint_layer(index: int) -> void:
	paint_system.set_active_paint_layer(index)
	paint_layer_changed.emit(index)


func add_paint_layer() -> void:
	paint_system.add_paint_layer()
	paint_layer_changed.emit(paint_system.get_active_paint_layer_index())


func rename_paint_layer(index: int, new_name: String) -> bool:
	if not paint_system.rename_paint_layer(index, new_name):
		return false
	paint_layer_changed.emit(paint_system.get_active_paint_layer_index())
	return true


func remove_active_paint_layer() -> void:
	paint_system.remove_active_paint_layer()
	paint_layer_changed.emit(paint_system.get_active_paint_layer_index())


## Apply serialized face data to brushes (used by vertex edit undo/redo).
func _apply_vertex_faces(face_map: Dictionary) -> void:
	for brush_id in face_map:
		var brush = brush_system.find_brush_by_id(brush_id)
		if brush and brush.has_method("apply_serialized_faces"):
			brush.apply_serialized_faces(face_map[brush_id])
			tag_brush_dirty(str(brush_id))


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


func save_hflevel(path: String = "", force: bool = false, autosave: bool = false) -> int:
	return file_system.save_hflevel(path, force, autosave)


func load_hflevel(path: String = "") -> bool:
	var ok = file_system.load_hflevel(path)
	if ok:
		state_loaded.emit()
	return ok


func validate_map(path: String) -> Dictionary:
	return file_system.validate_map(path)


func import_map(path: String) -> int:
	return file_system.import_map(path)


func export_map(path: String, format: String = "quake") -> int:
	return file_system.export_map(path, format)


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


func get_entity_count() -> int:
	if entities_node:
		return entities_node.get_child_count()
	return 0


func get_total_vertex_estimate() -> int:
	var total := 0
	if not draft_brushes_node:
		return 0
	for child in draft_brushes_node.get_children():
		if child.has_method("get_faces"):
			var faces: Array = child.get_faces()
			for face in faces:
				if face and face.has_method("get_vertex_count"):
					total += face.get_vertex_count()
				elif face:
					total += 4  # default quad estimate
	return total


func get_recommended_chunk_size() -> float:
	var brush_count := get_live_brush_count()
	if brush_count < 30:
		return 0.0
	var aabb := _compute_level_aabb()
	var extent: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if extent < 128.0:
		return 0.0
	return snappedf(extent / 4.0, grid_snap)


func get_level_health() -> Dictionary:
	var brush_count := get_live_brush_count()
	var entity_count := get_entity_count()
	var total := brush_count + entity_count
	if total <= 50:
		return {"label": "Healthy", "severity": 0}
	if total <= 100:
		return {"label": "Consider Chunking", "severity": 1}
	return {"label": "Optimize Brush Count", "severity": 2}


func _compute_level_aabb() -> AABB:
	var result := AABB()
	if not draft_brushes_node:
		return result
	var first := true
	for child in draft_brushes_node.get_children():
		if child is Node3D:
			var pos: Vector3 = child.global_position
			var sz: Vector3 = child.get("size") if child.get("size") else Vector3.ONE
			var brush_aabb := AABB(pos - sz * 0.5, sz)
			if first:
				result = brush_aabb
				first = false
			else:
				result = result.merge(brush_aabb)
	return result


func export_playtest_scene(path: String) -> bool:
	var scene_root := Node3D.new()
	scene_root.name = "PlaytestScene"

	# Copy baked geometry
	if baked_container:
		for child in baked_container.get_children():
			if child is Node3D:
				var dup = child.duplicate()
				scene_root.add_child(dup)
				dup.transform = child.global_transform
				_own_tree(dup, scene_root)

	# Copy entities (spawn points, lights, etc.)
	if entities_node:
		for child in entities_node.get_children():
			if child is Node3D:
				var dup = child.duplicate()
				scene_root.add_child(dup)
				dup.transform = child.global_transform
				_own_tree(dup, scene_root)

	# Copy DefaultSun if it exists (created by New HammerForge Level)
	var default_sun = get_node_or_null("DefaultSun") as DirectionalLight3D
	if default_sun:
		var sun_dup = default_sun.duplicate()
		scene_root.add_child(sun_dup)
		sun_dup.transform = default_sun.global_transform
		_own_tree(sun_dup, scene_root)

	# Add fallback light only if nothing provides one
	var has_light := false
	for child in scene_root.get_children():
		if child is Light3D:
			has_light = true
			break
	if not has_light:
		var light := DirectionalLight3D.new()
		light.name = "PlaytestSun"
		light.rotation_degrees = Vector3(-45, 30, 0)
		scene_root.add_child(light)
		light.owner = scene_root

	var env := WorldEnvironment.new()
	env.name = "PlaytestEnv"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.3, 0.35, 0.45)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	environment.ambient_light_energy = 0.5
	env.environment = environment
	scene_root.add_child(env)
	env.owner = scene_root

	# Wire entity I/O connections into Godot signals. Trigger volumes sit
	# under a Nonstructural holder, so scan the packed tree, not only roots.
	var has_io := _node_tree_has_io(scene_root)
	if has_io:
		var io_dispatcher := HFIORuntime.new()
		io_dispatcher.name = "HFIODispatcher"
		scene_root.add_child(io_dispatcher)
		_own_tree(io_dispatcher, scene_root)

	var player := _make_playtest_player()
	scene_root.add_child(player)
	var pose := _resolve_playtest_spawn()
	player.position = pose["position"]
	player.rotation.y = pose["yaw"]
	_own_tree(player, scene_root)

	# Pack and save
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	scene_root.free()
	if err != OK:
		push_error("HammerForge: Failed to pack playtest scene: %s" % error_string(err))
		return false

	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("HammerForge: Failed to save playtest scene: %s" % error_string(err))
		return false

	return true


func _node_tree_has_io(node: Node) -> bool:
	if not node.get_meta("entity_io_outputs", []).is_empty():
		return true
	for child in node.get_children():
		if _node_tree_has_io(child):
			return true
	return false


func _own_tree(node: Node, scene_owner: Node) -> void:
	if not node:
		return
	node.owner = scene_owner
	for child in node.get_children():
		_own_tree(child, scene_owner)


func _resolve_playtest_spawn() -> Dictionary:
	var spawn: Node3D = null
	var spawn_yaw := 0.0
	if spawn_system:
		spawn = spawn_system.get_active_spawn()
	if not spawn:
		for node in _iter_pick_nodes():
			if node is DraftEntity:
				var draft_entity := node as DraftEntity
				var ec := draft_entity.entity_class
				if ec == "":
					ec = draft_entity.entity_type
				if ec == "player_start":
					spawn = draft_entity
					break
	var spawn_pos := Vector3(0, 2, 0)
	var found_spawn := spawn != null
	var height_offset := 1.0
	if found_spawn:
		spawn_pos = (spawn.global_position if spawn.is_inside_tree() else spawn.position)
		if spawn is DraftEntity:
			spawn_yaw = deg_to_rad(float(spawn.entity_data.get("angle", 0.0)))
			height_offset = float(spawn.entity_data.get("height_offset", 1.0))
	var offset := Vector3(0, height_offset, 0) if found_spawn else Vector3.ZERO
	return {"position": spawn_pos + offset, "yaw": spawn_yaw if found_spawn else 0.0}


func _make_playtest_player() -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.name = "PlaytestPlayer"
	player.set_script(PlaytestFPS)
	return player


# ===========================================================================
# Material manager API (stays on root — thin wrappers over material_manager)
# ===========================================================================


func get_material_manager() -> MaterialManager:
	return material_manager


func get_materials() -> Array:
	return material_manager.materials if material_manager else []


## Replaces the palette. Accepts an untyped Array, which is what a decoded
## .hflevel payload is, and converts it to the Array[Material] the manager
## exports. Assigning an untyped array straight into that property is rejected
## by the engine and the write is silently skipped, so the conversion is the
## whole point of this function.
##
## Slot positions are preserved. A slot that does not hold a Material comes back
## as null rather than being dropped, because face material_idx values are plain
## indices into this array and compacting it would repoint every face above the
## bad slot.
func set_materials(materials: Array) -> void:
	if not material_manager:
		_setup_material_manager()
	var typed: Array[Material] = []
	typed.resize(materials.size())
	for i in materials.size():
		var entry = materials[i]
		if entry == null or entry is Material:
			typed[i] = entry
		else:
			HFLog.warn(
				(
					"set_materials: palette slot %d is a %s, not a Material. Slot kept empty."
					% [i, type_string(typeof(entry))]
				)
			)
	material_manager.materials = typed
	_refresh_brush_previews()


func add_material_to_palette(material: Material) -> int:
	if not material_manager:
		_setup_material_manager()
	var idx = material_manager.add_material(material)
	_refresh_brush_previews()
	material_list_changed.emit()
	return idx


## Removes a palette slot and repoints every face that referenced a later one.
##
## FaceData.material_idx is a plain index into MaterialManager.materials, so
## compacting the array without a remap repaints every brush that used a slot
## above the removed one. Faces that used the removed slot fall back to unset.
func remove_material_from_palette(index: int) -> void:
	if not material_manager:
		return
	if index < 0 or index >= material_manager.materials.size():
		return
	material_manager.remove_material(index)
	_remap_face_material_indices(index)
	_refresh_brush_previews()
	material_list_changed.emit()


## Shifts face material indices down over a removed palette slot. Faces that
## pointed at the removed slot become -1, which is the unset value.
func _remap_face_material_indices(removed_index: int) -> void:
	for node in _iter_managed_brush_nodes():
		var brush := node as DraftBrush
		if not brush or not is_instance_valid(brush):
			continue
		var changed := false
		for face in brush.faces:
			if face == null:
				continue
			if face.material_idx == removed_index:
				face.material_idx = -1
				changed = true
			elif face.material_idx > removed_index:
				face.material_idx -= 1
				changed = true
		if changed:
			tag_brush_dirty(brush.brush_id)


## Batch-loads all built-in prototype textures into the material palette.
## Uses signal batching and a single preview refresh for performance.
## Returns the number actually added, so a second call returns 0 rather than
## putting a second copy of all 150 into the palette.
func add_prototype_materials() -> int:
	if not material_manager:
		_setup_material_manager()
	begin_signal_batch()
	var count := HFPrototypeTextures.load_all_into(material_manager)
	_refresh_brush_previews()
	end_signal_batch()
	material_list_changed.emit()
	return count


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
	if Engine.is_editor_hint() and material_manager.materials.is_empty():
		HFPrototypeTextures.load_all_into(material_manager)


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
	if not paint_tool.stroke_committed.is_connected(_on_paint_stroke_committed):
		paint_tool.stroke_committed.connect(_on_paint_stroke_committed)
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


func _on_paint_stroke_committed(changed_cell_count: int) -> void:
	paint_stroke_committed.emit(changed_cell_count)


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
		add_child(hover_highlight, false, Node.INTERNAL_MODE_BACK)
	hover_highlight.owner = null
	hover_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A wireframe BoxMesh reveals the two render triangles on every quad. Draw
	# the twelve semantic box edges explicitly so hover remains a quiet outline.
	hover_highlight.mesh = HFOutlineUtil.line_mesh(HFOutlineUtil.box_lines())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	hover_highlight.material_override = mat
	hover_highlight.visible = false


## Highlight the face under the cursor for extrude preview.
## Returns true if a face was found and highlighted.
func highlight_hovered_face(camera: Camera3D, mouse_pos: Vector2, color: Color) -> bool:
	if not camera:
		clear_face_hover_highlight()
		return false
	# Use the same eligibility, visibility, broad phase, and exact face test as
	# click selection so hover never promises a face that cannot be selected.
	var hit := brush_system.pick_face(camera, mouse_pos) if brush_system else {}
	if hit.is_empty():
		clear_face_hover_highlight()
		return false

	var brush: DraftBrush = hit.get("brush", null) as DraftBrush
	var face_idx: int = int(hit.get("face_idx", -1))
	if not brush or face_idx < 0 or face_idx >= brush.faces.size():
		clear_face_hover_highlight()
		return false

	var face: FaceData = brush.faces[face_idx]
	if not face:
		clear_face_hover_highlight()
		return false

	# Build or reuse the highlight node
	if not _face_hover_highlight:
		_face_hover_highlight = MeshInstance3D.new()
		_face_hover_highlight.name = "_FaceHoverHighlight"
		_face_hover_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_face_hover_highlight, false, Node.INTERNAL_MODE_BACK)
		_face_hover_highlight.owner = null

	# Reuse cached material — only update color if changed
	if not _face_hover_material:
		_face_hover_material = StandardMaterial3D.new()
		_face_hover_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_face_hover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_face_hover_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_face_hover_material.no_depth_test = true
		_face_hover_highlight.material_override = _face_hover_material
	if _face_hover_material.albedo_color != color:
		_face_hover_material.albedo_color = color

	# Skip mesh rebuild if same brush + face (avoids SurfaceTool churn)
	if brush == _face_hover_last_brush and face_idx == _face_hover_last_face_idx:
		_face_hover_highlight.visible = true
		return true
	_face_hover_last_brush = brush
	_face_hover_last_face_idx = face_idx

	# Rebuild mesh from face vertices
	face.ensure_geometry()
	if not _face_hover_st:
		_face_hover_st = SurfaceTool.new()
	_face_hover_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_data = face.triangulate()
	var verts: PackedVector3Array = tri_data.get("verts", PackedVector3Array())
	for i in range(verts.size()):
		_face_hover_st.add_vertex(brush.global_transform * verts[i])
	_face_hover_highlight.mesh = _face_hover_st.commit()
	_face_hover_highlight.global_transform = Transform3D.IDENTITY
	_face_hover_highlight.visible = true
	return true


## Hide the face hover highlight.
func clear_face_hover_highlight() -> void:
	if _face_hover_highlight:
		_face_hover_highlight.visible = false
	_face_hover_last_brush = null
	_face_hover_last_face_idx = -1


## Normalise a cordon into a region.
##
## An AABB with a negative size is a constructible value of the type and is not a
## region: Godot own intersects() errors on it and returns false for everything,
## so every brush read as outside the cordon and the bake produced an empty level
## and reported success. The cordon wireframe draws the same box either way, so
## there was nothing on screen to go on. abs() is the fix Godot own error message
## names, and it makes a min/max pair entered in either order mean the same
## region, which is what the dock six SpinBoxes make easy to get backwards.
func _set_cordon_aabb(value: AABB) -> void:
	if not value.position.is_finite() or not value.size.is_finite():
		HFLog.warn("HammerForge: cordon %s is not a region, keeping %s" % [value, _cordon_aabb])
		return
	_cordon_aabb = value.abs()


func _set_grid_snap(value: float) -> void:
	if not is_finite(value):
		# max() passes NaN through, which is how the one setter that already
		# refused a negative snap let a NaN past.
		HFLog.warn("HammerForge: grid snap %s is not a snap, keeping %s" % [value, _grid_snap])
		return
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
	save_hflevel(hflevel_autosave_path, true, true)


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
		if _autosave_timer.timeout.is_connected(_on_autosave_timeout):
			_autosave_timer.timeout.disconnect(_on_autosave_timeout)
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

	var pose := _resolve_playtest_spawn()
	var player := _make_playtest_player()
	add_child(player)
	player.global_position = pose["position"]
	player.rotation.y = pose["yaw"]


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


## Create a starter level with floor, directional light, and player spawn.
## Intended for brand-new scenes so users can immediately draw.
func create_new_level() -> void:
	# Floor
	create_floor()

	# Directional light (sun-like, angled down)
	var light = get_node_or_null("DefaultSun") as DirectionalLight3D
	if not light:
		light = DirectionalLight3D.new()
		light.name = "DefaultSun"
		add_child(light)
		_assign_owner(light)
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	light.light_energy = 1.0

	# Player spawn
	if spawn_system:
		var existing: Node3D = spawn_system.get_active_spawn()
		if not existing:
			spawn_system.create_default_spawn()


# ===========================================================================
# Shared utilities (stay on root — used by multiple subsystems)
# ===========================================================================


func _get_editor_owner() -> Node:
	# A root built in code and not yet parented has no tree to ask.
	var tree := get_tree()
	var scene = tree.edited_scene_root if tree else null
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


## Authoritative managed-brush traversal for identity/index integrity. Unlike
## picking, this intentionally includes hidden committed cutters.
func _iter_managed_brush_nodes() -> Array:
	var nodes: Array = []
	for container in [draft_brushes_node, pending_node, committed_node]:
		if container:
			for child in container.get_children():
				if child is DraftBrush:
					nodes.append(child)
	return nodes


## Editable displacement sources exclude frozen committed cutters.
func get_all_draft_brushes() -> Array:
	var nodes: Array = []
	for container in [draft_brushes_node, pending_node]:
		if container:
			for child in container.get_children():
				if child is DraftBrush:
					nodes.append(child)
	return nodes


func _gather_visual_instances(node: Node, out: Array) -> void:
	if not node:
		return
	if node is VisualInstance3D:
		out.append(node)
	# Entity previews are intentionally internal editor children. The default
	# get_children() view excludes them, which made otherwise visible entities
	# fall back to an imprecise point-sized pick sphere.
	for child in node.get_children(true):
		_gather_visual_instances(child, out)


## Whether a 3D node is actually visible to the editor camera. Visgroups hide
## their members through Node3D.visible, so `is_visible_in_tree()` also catches
## a hidden managed parent while still respecting a visual's own visibility.
func _is_pick_visible(node: Node) -> bool:
	return (
		node != null
		and is_instance_valid(node)
		and node is Node3D
		and (node as Node3D).is_visible_in_tree()
	)


## Intersect a normalized world-space ray with a visual's local AABB and return
## the ray parameter in world units. Do not normalize the transformed direction:
## keeping its scale makes `t` invariant across non-uniform local transforms.
func _visual_pick_distance(
	visual: VisualInstance3D, ray_origin: Vector3, ray_dir: Vector3
) -> float:
	if not _is_pick_visible(visual):
		return -1.0
	var inv := visual.global_transform.affine_inverse()
	var local_origin := inv * ray_origin
	var local_dir := inv.basis * ray_dir
	if local_dir.length_squared() <= 0.0000000001:
		return -1.0
	return _ray_intersect_aabb(local_origin, local_dir, visual.get_aabb())


func _snap_point(point: Vector3, exclude_ids: Array = []) -> Vector3:
	if snap_system:
		return snap_system.snap_point(point, grid_snap, exclude_ids)
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
	# Draft brushes do not always have physics bodies in the editor. Use their
	# actual face triangles, never the empty portion of a cone/wedge/custom AABB,
	# for surface placement and drag/drop fallback hits.
	if brush_system:
		var face_hit: Dictionary = brush_system.pick_face_from_ray(from, ray_dir)
		if not face_hit.is_empty():
			return face_hit
	var plane_hit = construction_plane_hit(camera, mouse_pos, from, to)
	if plane_hit is Vector3:
		return {"position": plane_hit}
	return {}


## Where a screen ray meets the plane the editor is building on.
##
## Which is the plane the grid is drawn on: `record_last_brush()` moves the grid
## to the last brush you made, and an axis lock stands it up on X or Z. Before
## this, a ray that missed every brush was answered by the horizontal plane
## through the world origin instead — so drawing a brush at y=128 moved the grid
## up to meet it and then put the next brush back down on zero, a hundred and
## twenty-eight units below the grid being looked at. At the world origin, in the
## ordinary way of working.
##
## The static below stays as the answer when there is no grid system, which is
## every exported game: the editor systems are not loaded there.
func construction_plane_hit(
	camera: Camera3D, mouse_pos: Vector2, from: Vector3, to: Vector3
) -> Variant:
	if grid_system and camera:
		return grid_system.intersect_axis_plane(
			camera, mouse_pos, grid_system.effective_grid_axis(), grid_plane_origin
		)
	return construction_plane_intersection(from, to)


## The horizontal plane through the world origin. The fallback, and what the
## editor used for everything before the grid plane was consulted.
static func construction_plane_intersection(from: Vector3, to: Vector3) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_segment(from, to)


## Where a screen ray meets the horizontal plane at `y`. Unlike a plane
## intersection this always answers: a ray parallel to the plane drops straight
## down from the camera, and the hit is clamped in front of it. Viewport tools
## place points with this, so a null would leave the cursor with nowhere to go.
static func screen_ray_to_y_plane(camera: Camera3D, mouse_pos: Vector2, y: float) -> Vector3:
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, y, origin.z)
	var t := maxf((y - origin.y) / dir.y, 0.0)
	return origin + dir * t


func _entity_pick_distance(entity: Node3D, ray_origin: Vector3, ray_dir: Vector3) -> float:
	if not _is_pick_visible(entity):
		return -1.0
	# Use the same exact preview triangles as the native gizmo. AABB picking lets
	# empty cone/custom/concave bounds steal clicks from real geometry behind it.
	var triangles := HFOutlineUtil.visible_preview_collision_triangle_vertices(entity, Vector3.ONE)
	if not triangles.is_empty():
		return _local_triangle_pick_distance(
			triangles, entity.global_transform, ray_origin, ray_dir
		)
	# A deliberately hidden preview must not leave an invisible target. Truly
	# geometry-less entities keep the same small marker used by the native gizmo.
	if HFOutlineUtil.has_preview_geometry_descendant(entity):
		return -1.0
	return _local_triangle_pick_distance(
		HFOutlineUtil.box_triangle_vertices(Vector3.ONE),
		entity.global_transform,
		ray_origin,
		ray_dir
	)


static func _local_triangle_pick_distance(
	triangles: PackedVector3Array,
	local_to_world: Transform3D,
	ray_origin: Vector3,
	ray_dir: Vector3,
) -> float:
	if triangles.size() < 3 or ray_dir.is_zero_approx():
		return -1.0
	var world_to_local := local_to_world.affine_inverse()
	var local_origin := world_to_local * ray_origin
	# Do not normalize after transforming: preserving the scale keeps t in the
	# normalized world ray's distance units under non-uniform transforms.
	var local_dir := world_to_local.basis * ray_dir.normalized()
	if local_dir.length_squared() <= 0.0000000001:
		return -1.0
	var best_t := INF
	for index in range(0, triangles.size() - 2, 3):
		var t := FaceSelector._ray_triangle(
			local_origin, local_dir, triangles[index], triangles[index + 1], triangles[index + 2]
		)
		if t >= 0.0 and t < best_t:
			best_t = t
	return best_t if best_t < INF else -1.0


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
