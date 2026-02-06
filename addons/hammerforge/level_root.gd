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
@export var bake_navmesh_cell_height: float = 0.2
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

signal bake_started
signal bake_finished(success: bool)
signal grid_snap_changed(value: float)

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
var baked_container: Node3D
var preview_brush: DraftBrush = null
var drag_active := false
var drag_origin := Vector3.ZERO
var drag_end := Vector3.ZERO
var drag_operation := CSGShape3D.OPERATION_UNION
var drag_shape := BrushShape.BOX
var drag_sides := 4
var drag_height := 32.0
var drag_stage := 0
var drag_size_default := Vector3(32, 32, 32)
var axis_lock := AxisLock.NONE
var manual_axis_lock := false
var shift_pressed := false
var alt_pressed := false
var lock_axis_active := AxisLock.NONE
var locked_thickness := Vector3.ZERO
var height_stage_start_mouse := Vector2.ZERO
var height_stage_start_height := 32.0
var height_pixels_per_unit := 4.0
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
var _hflevel_thread: Thread = null
var _hflevel_pending: Dictionary = {}
var _hflevel_last_hash: int = 0
var face_selection: Dictionary = {}
var _surface_painting := false

func _ready():
	_setup_draft_container()
	_setup_pending_container()
	_setup_committed()
	_setup_entities_container()
	_load_entity_definitions()
	_setup_manager()
	_setup_material_manager()
	_setup_baker()
	_setup_paint_system()
	_setup_surface_paint()
	_setup_editor_grid()
	_setup_highlight()
	if Engine.is_editor_hint():
		_set_hflevel_autosave_minutes(hflevel_autosave_minutes)
		_set_hflevel_autosave_enabled(hflevel_autosave_enabled)
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
	if _hflevel_thread and not _hflevel_thread.is_alive():
		_hflevel_thread.wait_to_finish()
		_hflevel_thread = null
		if not _hflevel_pending.is_empty():
			var next = _hflevel_pending.duplicate(true)
			_hflevel_pending.clear()
			_start_hflevel_thread(next.get("path", ""), next.get("payload", PackedByteArray()))

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
				spawn_pos = draft_entity.global_position if draft_entity.is_inside_tree() else draft_entity.position
				found_spawn = true
				break

	var player = CharacterBody3D.new()
	player.name = "PlaytestPlayer"
	player.set_script(PlaytestFPS)
	var offset = Vector3(0, 1.0, 0) if found_spawn else Vector3.ZERO
	add_child(player)
	player.global_position = spawn_pos + offset

func request_remote_reload() -> void:
	if Engine.is_editor_hint():
		return
	_log("Remote Reload Requested")
	bake(true, true)

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

func add_entity(entity: Node3D) -> void:
	if not entity:
		return
	if not entities_node:
		_setup_entities_container()
	entity.set_meta("is_entity", true)
	entities_node.add_child(entity)
	_assign_owner(entity)

func _load_entity_definitions() -> void:
	entity_definitions.clear()
	if entity_definitions_path == "" or not ResourceLoader.exists(entity_definitions_path):
		return
	var file = FileAccess.open(entity_definitions_path, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	var data = JSON.parse_string(text)
	if data == null:
		return
	if data is Dictionary:
		var entries = data.get("entities", null)
		if entries is Array:
			for entry in entries:
				if entry is Dictionary:
					var key = str(entry.get("id", entry.get("class", "")))
					if key != "":
						entity_definitions[key] = entry
			return
		entity_definitions = data
		return
	if data is Array:
		# Back-compat: array entries with "class" become keyed by class name.
		for entry in data:
			if entry is Dictionary:
				var key = str(entry.get("class", ""))
				if key != "":
					entity_definitions[key] = entry

func get_entity_definition(entity_type: String) -> Dictionary:
	if entity_type == "":
		return {}
	return entity_definitions.get(entity_type, {})

func get_entity_definitions() -> Dictionary:
	return entity_definitions

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
	paint_tool.reconciler.floors_root = generated_floors
	paint_tool.reconciler.walls_root = generated_walls
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

func _refresh_brush_previews() -> void:
	for node in _iter_pick_nodes():
		if node is DraftBrush:
			node.rebuild_preview()

func pick_face(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	if not camera:
		return {}
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos).normalized()
	var brushes: Array = []
	for node in _iter_pick_nodes():
		if node is DraftBrush and is_brush_node(node):
			brushes.append(node)
	return FaceSelector.intersect_brushes(brushes, ray_origin, ray_dir)

func select_face_at_screen(camera: Camera3D, mouse_pos: Vector2, additive: bool) -> bool:
	var hit = pick_face(camera, mouse_pos)
	if hit.is_empty():
		if not additive:
			clear_face_selection()
		return false
	var brush = hit.get("brush", null)
	var face_idx = int(hit.get("face_idx", -1))
	if brush and face_idx >= 0:
		toggle_face_selection(brush, face_idx, additive)
		return true
	return false

func toggle_face_selection(brush: DraftBrush, face_idx: int, additive: bool) -> void:
	if not brush:
		return
	if not additive:
		face_selection.clear()
	var key = _face_key(brush)
	var indices: Array = face_selection.get(key, [])
	var idx = indices.find(face_idx)
	if idx >= 0:
		indices.remove_at(idx)
	else:
		indices.append(face_idx)
	face_selection[key] = indices
	_apply_face_selection()

func clear_face_selection() -> void:
	face_selection.clear()
	_apply_face_selection()

func get_face_selection() -> Dictionary:
	return face_selection.duplicate(true)

func get_primary_selected_face() -> Dictionary:
	for key in face_selection.keys():
		var indices: Array = face_selection.get(key, [])
		if indices.is_empty():
			continue
		var brush = _find_brush_by_key(str(key))
		if brush and indices[0] != null:
			return { "brush": brush, "face_idx": int(indices[0]) }
	return {}

func assign_material_to_selected_faces(material_index: int) -> void:
	for key in face_selection.keys():
		var brush = _find_brush_by_key(str(key))
		if not brush:
			continue
		var indices: Array = face_selection.get(key, [])
		var typed: Array[int] = []
		for idx in indices:
			typed.append(int(idx))
		brush.assign_material_to_faces(material_index, typed)

func handle_surface_paint_input(
	camera: Camera3D,
	event: InputEvent,
	mouse_pos: Vector2,
	radius_uv: float,
	strength: float,
	layer_idx: int
) -> bool:
	if not surface_paint:
		_setup_surface_paint()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_surface_painting = true
			_paint_surface_at(camera, mouse_pos, radius_uv, strength, layer_idx)
			return true
		if _surface_painting:
			_surface_painting = false
			return true
	if event is InputEventMouseMotion:
		if _surface_painting and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			_paint_surface_at(camera, mouse_pos, radius_uv, strength, layer_idx)
			return true
	return false

func rebuild_brush_preview(brush: DraftBrush) -> void:
	if brush:
		brush.rebuild_preview()

func _paint_surface_at(camera: Camera3D, mouse_pos: Vector2, radius_uv: float, strength: float, layer_idx: int) -> void:
	if not camera:
		return
	var hit = pick_face(camera, mouse_pos)
	if hit.is_empty():
		return
	var brush = hit.get("brush", null)
	var face_idx = int(hit.get("face_idx", -1))
	var uv = hit.get("uv", Vector2.ZERO)
	if not brush or face_idx < 0 or face_idx >= brush.faces.size():
		return
	uv.x = clamp(uv.x, 0.0, 1.0)
	uv.y = clamp(uv.y, 0.0, 1.0)
	var face: FaceData = brush.faces[face_idx]
	surface_paint.paint_at_uv(face, layer_idx, uv, radius_uv, strength)
	brush.rebuild_preview()

func _apply_face_selection() -> void:
	for node in _iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var key = _face_key(brush)
		var indices: Array = face_selection.get(key, [])
		brush.set_selected_faces(PackedInt32Array(indices))

func _face_key(brush: DraftBrush) -> String:
	if brush == null:
		return ""
	if brush.brush_id != "":
		return brush.brush_id
	return str(brush.get_instance_id())

func _find_brush_by_key(key: String) -> DraftBrush:
	if key == "":
		return null
	var brush = _find_brush_by_id(key)
	if brush and brush is DraftBrush:
		return brush as DraftBrush
	if not key.is_valid_int():
		return null
	var target_id = int(key)
	for node in _iter_pick_nodes():
		if node is DraftBrush and node.get_instance_id() == target_id:
			return node as DraftBrush
	return null

func _setup_editor_grid() -> void:
	if not Engine.is_editor_hint():
		var existing = get_node_or_null("EditorGrid") as MeshInstance3D
		if existing:
			existing.queue_free()
		return
	grid_mesh = get_node_or_null("EditorGrid") as MeshInstance3D
	if not grid_mesh:
		grid_mesh = MeshInstance3D.new()
		grid_mesh.name = "EditorGrid"
		add_child(grid_mesh)
	grid_mesh.owner = null
	var plane := PlaneMesh.new()
	plane.size = Vector2(grid_plane_size, grid_plane_size)
	grid_mesh.mesh = plane
	grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not grid_material:
		grid_material = ShaderMaterial.new()
		grid_material.shader = preload("editor_grid.gdshader")
	grid_mesh.material_override = grid_material
	grid_mesh.visible = _grid_visible
	grid_plane_origin = global_position
	grid_axis_preference = AxisLock.Y
	_update_grid_material()
	_update_grid_transform(grid_axis_preference, grid_plane_origin)
	_log("Editor grid setup (visible=%s)" % _grid_visible)

func _set_grid_visible(value: bool) -> void:
	if _grid_visible == value:
		return
	_grid_visible = value
	if grid_mesh and grid_mesh.is_inside_tree():
		grid_mesh.visible = _grid_visible
	_log("Grid visible set to %s" % _grid_visible)

func _update_grid_material() -> void:
	if not grid_material:
		return
	var size = max(_grid_snap, 0.001)
	grid_material.set_shader_parameter("snap_size", size)
	grid_material.set_shader_parameter("grid_color", grid_color)
	grid_material.set_shader_parameter("major_line_frequency", float(grid_major_line_frequency))

func _update_grid_transform(axis: int, origin: Vector3) -> void:
	if not grid_mesh or not grid_mesh.is_inside_tree():
		return
	grid_plane_axis = axis
	grid_plane_origin = origin
	var rot = Vector3.ZERO
	match axis:
		AxisLock.X:
			rot = Vector3(0.0, 0.0, -90.0)
		AxisLock.Z:
			rot = Vector3(90.0, 0.0, 0.0)
		_:
			rot = Vector3.ZERO
	grid_mesh.rotation_degrees = rot
	grid_mesh.global_position = origin

func _effective_grid_axis() -> int:
	if manual_axis_lock and axis_lock != AxisLock.NONE:
		return axis_lock
	return grid_axis_preference

func _set_grid_plane_origin(origin: Vector3, axis: int) -> void:
	_update_grid_transform(axis, origin)

func _refresh_grid_plane() -> void:
	if not Engine.is_editor_hint():
		return
	var axis = _effective_grid_axis()
	var origin = grid_plane_origin
	if origin == Vector3.ZERO and last_brush_center != Vector3.ZERO:
		origin = last_brush_center
	_update_grid_transform(axis, origin)

func _record_last_brush(center: Vector3) -> void:
	last_brush_center = center
	grid_axis_preference = _effective_grid_axis()
	_set_grid_plane_origin(center, grid_axis_preference)

func _intersect_axis_plane(camera: Camera3D, mouse_pos: Vector2, axis: int, origin: Vector3) -> Variant:
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var normal = Vector3.UP
	var distance = origin.y
	match axis:
		AxisLock.X:
			normal = Vector3.RIGHT
			distance = origin.x
		AxisLock.Z:
			normal = Vector3.BACK
			distance = origin.z
		_:
			normal = Vector3.UP
			distance = origin.y
	var denom = normal.dot(dir)
	if abs(denom) < 0.0001:
		return null
	var t = (distance - normal.dot(from)) / denom
	if t < 0.0:
		return null
	return from + dir * t

func update_editor_grid(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not Engine.is_editor_hint():
		return
	if not _grid_visible:
		return
	if not grid_mesh or not grid_mesh.is_inside_tree() or not camera:
		return
	var axis = _effective_grid_axis()
	if grid_follow_brush:
		var hit = _intersect_axis_plane(camera, mouse_pos, axis, grid_plane_origin)
		if hit != null:
			var snapped = _snap_point(hit)
			_set_grid_plane_origin(snapped, axis)
			return
	_update_grid_transform(axis, grid_plane_origin)

func handle_paint_input(
	camera: Camera3D,
	event: InputEvent,
	screen_pos: Vector2,
	operation: int,
	size: Vector3,
	paint_tool_id: int = -1,
	paint_radius_cells: int = -1
) -> bool:
	if not Engine.is_editor_hint():
		return false
	if not paint_tool:
		_setup_paint_system()
	if not paint_tool or not paint_layers:
		return false
	var layer = paint_layers.get_active_layer()
	if paint_radius_cells > 0:
		paint_tool.brush_radius_cells = paint_radius_cells
	elif layer and layer.grid:
		var cell_size = max(layer.grid.cell_size, 0.1)
		var radius_cells = max(1, int(round(size.x / cell_size)))
		paint_tool.brush_radius_cells = radius_cells
	if paint_tool_id >= 0:
		paint_tool.tool = paint_tool_id
	else:
		paint_tool.tool = HFStroke.Tool.PAINT if operation == CSGShape3D.OPERATION_UNION else HFStroke.Tool.ERASE
	return paint_tool.handle_input(camera, event, screen_pos)

func get_paint_layer_names() -> Array:
	var names: Array = []
	if not paint_layers:
		return names
	for layer in paint_layers.layers:
		if layer:
			names.append(str(layer.layer_id))
	return names

func get_active_paint_layer_index() -> int:
	return paint_layers.active_layer_index if paint_layers else 0

func set_active_paint_layer(index: int) -> void:
	if not paint_layers:
		_setup_paint_system()
	if not paint_layers:
		return
	paint_layers.set_active_layer(index)

func add_paint_layer() -> void:
	if not paint_layers:
		_setup_paint_system()
	if not paint_layers:
		return
	var new_id = _next_paint_layer_id()
	paint_layers.create_layer(StringName(new_id), grid_plane_origin.y)
	paint_layers.active_layer_index = paint_layers.layers.size() - 1

func remove_active_paint_layer() -> void:
	if not paint_layers:
		return
	if paint_layers.layers.size() <= 1:
		return
	var idx = paint_layers.active_layer_index
	paint_layers.remove_layer(idx)
	_regenerate_paint_layers()

func _next_paint_layer_id() -> String:
	var base = "layer_"
	var index = paint_layers.layers.size() if paint_layers else 0
	var seen: Dictionary = {}
	if paint_layers:
		for layer in paint_layers.layers:
			if layer:
				seen[str(layer.layer_id)] = true
	while true:
		var candidate = "%s%d" % [base, index]
		if not seen.has(candidate):
			return candidate
		index += 1
	return "%s0" % base

func place_brush(
	mouse_pos: Vector2,
	operation: int,
	size: Vector3,
	camera: Camera3D = null,
	shape: int = BrushShape.BOX,
	sides: int = 4
) -> bool:
	if not draft_brushes_node:
		return false

	var active_camera = camera if camera else get_viewport().get_camera_3d()
	if not active_camera:
		return false

	var hit = _raycast(active_camera, mouse_pos)
	if not hit:
		return false

	var snapped = _snap_point(hit.position)
	var brush = _create_brush(shape, size, operation, sides)
	brush.global_position = snapped + Vector3(0, size.y * 0.5, 0)
	if operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node:
		_add_pending_cut(brush)
	else:
		_add_brush_to_draft(brush)
	brush_manager.add_brush(brush)
	_record_last_brush(brush.global_position)
	return true

func _is_subtract_brush(node: Node) -> bool:
	return node is DraftBrush and node.operation == CSGShape3D.OPERATION_SUBTRACTION

func _add_brush_to_draft(brush: DraftBrush) -> void:
	if not draft_brushes_node:
		return
	draft_brushes_node.add_child(brush)
	_assign_owner(brush)

func bake(apply_cuts: bool = true, hide_live: bool = false, collision_layer_mask: int = 0) -> void:
	if not baker:
		return
	if apply_cuts:
		apply_pending_cuts()
	_log("Virtual Bake Started (apply_cuts=%s, hide_live=%s)" % [apply_cuts, hide_live])
	bake_started.emit()

	var layer = collision_layer_mask if collision_layer_mask > 0 else _layer_from_index(bake_collision_layer_index)
	var baked: Node3D = null
	var bake_options = _build_bake_options()
	if bake_use_face_materials:
		var face_brushes = _collect_face_bake_brushes()
		baked = baker.bake_from_faces(face_brushes, material_manager, bake_material_override, layer, layer, bake_options)
	else:
		if bake_chunk_size > 0.0:
			baked = await _bake_chunked(bake_chunk_size, layer, bake_options)
		else:
			baked = await _bake_single(layer, bake_options)

	if baked:
		if baked_container:
			baked_container.queue_free()
		baked_container = baked
		add_child(baked_container)
		_assign_owner(baked_container)
		_postprocess_bake(baked_container)
		if hide_live:
			if draft_brushes_node:
				draft_brushes_node.visible = false
			if pending_node:
				pending_node.visible = false
		_log("Bake finished (success=true)")
		bake_finished.emit(true)
	else:
		_log("Bake failed")
		_warn_bake_failure()
		bake_finished.emit(false)

func _warn_bake_failure() -> void:
	var draft_count = _count_brushes_in(draft_brushes_node)
	var pending_count = _count_brushes_in(pending_node)
	var committed_count = _count_brushes_in(committed_node)
	var entities_count = entities_node.get_child_count() if entities_node else 0
	push_warning("Bake failed: no baked geometry (draft=%s, pending=%s, committed=%s, entities=%s)" % [
		draft_count, pending_count, committed_count, entities_count
	])

func _build_bake_options() -> Dictionary:
	return {
		"merge_meshes": bake_merge_meshes,
		"generate_lods": bake_generate_lods,
		"unwrap_uv2": bake_lightmap_uv2,
		"uv2_texel_size": bake_lightmap_texel_size,
		"use_thread_pool": bake_use_thread_pool,
		"use_face_materials": bake_use_face_materials
	}

func _postprocess_bake(container: Node3D) -> void:
	if not container:
		return
	if bake_navmesh:
		_bake_navmesh(container)

func _count_brushes_in(container: Node3D) -> int:
	if not container:
		return 0
	var count := 0
	for child in container.get_children():
		if child is DraftBrush and not _is_entity_node(child):
			count += 1
	return count

func _bake_single(layer: int, options: Dictionary) -> Node3D:
	var temp_csg = CSGCombiner3D.new()
	temp_csg.hide()
	temp_csg.use_collision = false
	add_child(temp_csg)

	var collision_csg = CSGCombiner3D.new()
	collision_csg.hide()
	collision_csg.use_collision = false
	add_child(collision_csg)

	_append_draft_brushes_to_csg(draft_brushes_node, temp_csg)
	if commit_freeze and committed_node:
		_append_draft_brushes_to_csg(committed_node, temp_csg, true)
	_append_draft_brushes_to_csg(draft_brushes_node, collision_csg, false, true)
	_append_generated_brushes_to_csg(temp_csg)
	_append_generated_brushes_to_csg(collision_csg, true)

	await _await_csg_update()

	var baked = baker.bake_from_csg(temp_csg, bake_material_override, layer, layer, options)
	var collision_baked: Node3D = null
	if baked:
		collision_baked = baker.bake_from_csg(collision_csg, null, layer, layer, options)
		_apply_collision_from_bake(baked, collision_baked, layer)

	temp_csg.queue_free()
	collision_csg.queue_free()
	if collision_baked:
		collision_baked.free()
	return baked

func _bake_chunked(chunk_size: float, layer: int, options: Dictionary) -> Node3D:
	var size = max(0.001, chunk_size)
	var chunks: Dictionary = {}
	_collect_chunk_brushes(draft_brushes_node, size, chunks, "brushes")
	if commit_freeze and committed_node:
		_collect_chunk_brushes(committed_node, size, chunks, "committed")
	_collect_chunk_brushes(generated_floors, size, chunks, "generated")
	_collect_chunk_brushes(generated_walls, size, chunks, "generated")
	if chunks.is_empty():
		return null

	var container = Node3D.new()
	container.name = "BakedGeometry"
	var chunk_count = 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue

		var temp_csg = CSGCombiner3D.new()
		temp_csg.hide()
		temp_csg.use_collision = false
		add_child(temp_csg)

		var collision_csg = CSGCombiner3D.new()
		collision_csg.hide()
		collision_csg.use_collision = false
		add_child(collision_csg)

		_append_brush_list_to_csg(brushes, temp_csg)
		_append_brush_list_to_csg(generated, temp_csg)
		if commit_freeze:
			_append_brush_list_to_csg(committed, temp_csg, true)
		_append_brush_list_to_csg(brushes, collision_csg, false, true)
		_append_brush_list_to_csg(generated, collision_csg, false, true)

		await _await_csg_update()

		var baked_chunk = baker.bake_from_csg(temp_csg, bake_material_override, layer, layer, options)
		if baked_chunk:
			var collision_baked = baker.bake_from_csg(collision_csg, null, layer, layer, options)
			_apply_collision_from_bake(baked_chunk, collision_baked, layer)
			baked_chunk.name = "BakedChunk_%s_%s_%s" % [coord.x, coord.y, coord.z]
			container.add_child(baked_chunk)
			_assign_owner(baked_chunk)
			chunk_count += 1
			if collision_baked:
				collision_baked.free()

		temp_csg.queue_free()
		collision_csg.queue_free()

	return container if chunk_count > 0 else null

func _collect_chunk_brushes(source: Node3D, chunk_size: float, chunks: Dictionary, key: String) -> void:
	if not source:
		return
	for child in source.get_children():
		if not (child is DraftBrush):
			continue
		if _is_entity_node(child):
			continue
		var coord = _chunk_coord((child as Node3D).global_position, chunk_size)
		if not chunks.has(coord):
			chunks[coord] = { "brushes": [], "committed": [], "generated": [] }
		if not chunks[coord].has(key):
			chunks[coord][key] = []
		chunks[coord][key].append(child)

func _chunk_coord(position: Vector3, chunk_size: float) -> Vector3i:
	var size = max(0.001, chunk_size)
	return Vector3i(
		int(floor(position.x / size)),
		int(floor(position.y / size)),
		int(floor(position.z / size))
	)

func _append_draft_brushes_to_csg(
	source: Node3D,
	target: CSGCombiner3D,
	force_subtract: bool = false,
	only_additive: bool = false
) -> void:
	if not source or not target:
		return
	_append_brush_list_to_csg(source.get_children(), target, force_subtract, only_additive)

func _append_generated_brushes_to_csg(target: CSGCombiner3D, only_additive: bool = false) -> void:
	if not target:
		return
	if generated_floors:
		_append_brush_list_to_csg(generated_floors.get_children(), target, false, only_additive)
	if generated_walls:
		_append_brush_list_to_csg(generated_walls.get_children(), target, false, only_additive)

func _collect_face_bake_brushes() -> Array:
	var out: Array = []
	_append_face_bake_container(draft_brushes_node, out)
	_append_face_bake_container(generated_floors, out)
	_append_face_bake_container(generated_walls, out)
	return out

func _append_face_bake_container(container: Node3D, out: Array) -> void:
	if not container:
		return
	for child in container.get_children():
		if child is DraftBrush and not _is_subtract_brush(child):
			out.append(child)

func _append_brush_list_to_csg(
	brushes: Array,
	target: CSGCombiner3D,
	force_subtract: bool = false,
	only_additive: bool = false
) -> void:
	if not target:
		return
	for child in brushes:
		if not (child is DraftBrush):
			continue
		if _is_entity_node(child):
			continue
		var draft: DraftBrush = child
		if only_additive and (force_subtract or draft.operation == CSGShape3D.OPERATION_SUBTRACTION):
			continue
		var csg_shape = PrefabFactory.create_prefab(draft.shape, draft.size, max(3, draft.sides))
		csg_shape.operation = CSGShape3D.OPERATION_SUBTRACTION if force_subtract else draft.operation
		csg_shape.global_transform = draft.global_transform
		if csg_shape.operation != CSGShape3D.OPERATION_SUBTRACTION:
			var mat = draft.material_override
			if not mat:
				mat = _make_brush_material(csg_shape.operation)
			if mat:
				csg_shape.set("material", mat)
				csg_shape.set("material_override", mat)
		target.add_child(csg_shape)

func _apply_collision_from_bake(target: Node3D, source: Node3D, layer: int) -> void:
	if not target:
		return
	var target_body = target.get_node_or_null("FloorCollision") as StaticBody3D
	if not target_body:
		target_body = StaticBody3D.new()
		target_body.name = "FloorCollision"
		target.add_child(target_body)
	target_body.collision_layer = layer
	target_body.collision_mask = layer
	for child in target_body.get_children():
		child.queue_free()
	if not source:
		return
	var source_body = source.get_node_or_null("FloorCollision") as StaticBody3D
	if not source_body:
		return
	for child in source_body.get_children():
		if child is CollisionShape3D:
			var dup = child.duplicate()
			target_body.add_child(dup)

func _bake_navmesh(container: Node3D) -> void:
	if not container:
		return
	var nav_region = container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	if not nav_region:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "BakedNavmesh"
		container.add_child(nav_region)
		_assign_owner(nav_region)
	var nav_mesh = nav_region.navigation_mesh
	if not nav_mesh:
		nav_mesh = NavigationMesh.new()
		nav_region.navigation_mesh = nav_mesh
	nav_mesh.cell_size = bake_navmesh_cell_size
	nav_mesh.cell_height = bake_navmesh_cell_height
	nav_mesh.agent_height = bake_navmesh_agent_height
	nav_mesh.agent_radius = bake_navmesh_agent_radius
	if ClassDB.class_has_method("NavigationServer3D", "parse_source_geometry_data") \
			and ClassDB.class_has_method("NavigationServer3D", "bake_from_source_geometry_data") \
			and ClassDB.class_exists("NavigationMeshSourceGeometryData3D"):
		var source = NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source, container)
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	elif nav_region.has_method("bake_navigation_mesh"):
		nav_region.call("bake_navigation_mesh")

func clear_brushes() -> void:
	clear_face_selection()
	if brush_manager:
		brush_manager.clear_brushes()
	if draft_brushes_node:
		for child in draft_brushes_node.get_children():
			if child is DraftBrush:
				child.queue_free()
	_clear_generated()
	_clear_preview()
	clear_pending_cuts()
	_clear_committed_cuts()
	if baked_container:
		baked_container.queue_free()
		baked_container = null

func _clear_generated() -> void:
	if generated_floors:
		for child in generated_floors.get_children():
			if child is DraftBrush:
				child.queue_free()
	if generated_walls:
		for child in generated_walls.get_children():
			if child is DraftBrush:
				child.queue_free()

func _clear_entities() -> void:
	if not entities_node:
		return
	for child in entities_node.get_children():
		child.queue_free()

func _clear_committed_cuts() -> void:
	if not committed_node:
		return
	for child in committed_node.get_children():
		if child is DraftBrush:
			child.queue_free()

func apply_pending_cuts() -> void:
	if not pending_node or not draft_brushes_node:
		return
	var pending_count = pending_node.get_child_count()
	for child in pending_node.get_children():
		if child is DraftBrush:
			pending_node.remove_child(child)
			draft_brushes_node.add_child(child)
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
			_apply_brush_material(child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
			child.set_meta("pending_subtract", false)
			_assign_owner(child)
	_log("Applied pending cuts (%s)" % pending_count)

func commit_cuts() -> void:
	_log("Commit cuts (freeze=%s)" % commit_freeze)
	apply_pending_cuts()
	await bake(false, true)
	_clear_applied_cuts()

func _clear_applied_cuts() -> void:
	if not draft_brushes_node:
		return
	var targets: Array = draft_brushes_node.get_children()
	for child in targets:
		if child is DraftBrush and _is_subtract_brush(child):
			if commit_freeze:
				_stash_committed_cut(child)
			else:
				if brush_manager:
					brush_manager.remove_brush(child)
				child.call_deferred("queue_free")

func _stash_committed_cut(brush: DraftBrush) -> void:
	if not committed_node:
		return
	if brush_manager:
		brush_manager.remove_brush(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	committed_node.add_child(brush)
	brush.visible = false
	brush.set_meta("committed_cut", true)
	_assign_owner(brush)

func restore_committed_cuts() -> void:
	if not committed_node or not draft_brushes_node:
		return
	var restored = 0
	for child in committed_node.get_children():
		if child is DraftBrush:
			committed_node.remove_child(child)
			draft_brushes_node.add_child(child)
			child.visible = true
			child.operation = CSGShape3D.OPERATION_SUBTRACTION
			_apply_brush_material(child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
			child.set_meta("committed_cut", false)
			_assign_owner(child)
			if brush_manager:
				brush_manager.add_brush(child)
			restored += 1
	if draft_brushes_node:
		draft_brushes_node.visible = true
	if pending_node:
		pending_node.visible = true
	if restored > 0:
		_log("Restored committed cuts (%s)" % restored)

func _await_csg_update() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _layer_from_index(index: int) -> int:
	var clamped = clamp(index, 1, 32)
	return 1 << (clamped - 1)

func clear_pending_cuts() -> void:
	if not pending_node:
		return
	var cleared = pending_node.get_child_count()
	for child in pending_node.get_children():
		if child is DraftBrush:
			child.queue_free()
	if cleared > 0:
		_log("Cleared pending cuts (%s)" % cleared)

func delete_brush(brush: Node, free: bool = true) -> void:
	if not brush:
		return
	if brush is DraftBrush:
		var key = _face_key(brush as DraftBrush)
		if face_selection.has(key):
			face_selection.erase(key)
			_apply_face_selection()
	if brush_manager:
		brush_manager.remove_brush(brush)
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	if free:
		brush.queue_free()

func duplicate_brush(brush: Node) -> Node:
	if not brush:
		return null
	var offset = Vector3(grid_snap if grid_snap > 0.0 else 1.0, 0.0, 0.0)
	var info = build_duplicate_info(brush, offset)
	return create_brush_from_info(info)

func _create_brush(shape: int, size: Vector3, operation: int, sides: int) -> DraftBrush:
	var brush = DraftBrush.new()
	brush.shape = shape
	brush.size = size
	brush.operation = operation
	brush.sides = sides
	return brush

func _make_brush_material(operation: int, solid: bool = false, unshaded: bool = false) -> Material:
	var mat = StandardMaterial3D.new()
	if operation == CSGShape3D.OPERATION_SUBTRACTION:
		var alpha = 0.85 if solid else 0.35
		mat.albedo_color = Color(1.0, 0.2, 0.2, alpha)
		mat.emission = Color(1.0, 0.2, 0.2)
		mat.emission_energy = 0.6 if solid else 0.2
		if unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	return mat

func _apply_brush_material(brush: Node, mat: Material) -> void:
	if not brush or not mat:
		return
	if brush is DraftBrush:
		(brush as DraftBrush).set_editor_material(mat)
		return
	brush.set("material", mat)
	brush.set("material_override", mat)

func apply_material_to_brush(brush: Node, mat: Material) -> void:
	if not brush:
		return
	if brush is DraftBrush:
		(brush as DraftBrush).material_override = mat
		return
	brush.set("material_override", mat)
	brush.set("material", mat)

func _add_pending_cut(brush: DraftBrush) -> void:
	if not pending_node:
		return
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	_apply_brush_material(brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
	brush.set_meta("pending_subtract", true)
	pending_node.add_child(brush)
	_assign_owner(brush)

func _build_brush_info(origin: Vector3, current: Vector3, height: float, shape: int, size_default: Vector3, operation: int, equal_base: bool, equal_all: bool) -> Dictionary:
	var computed = _compute_brush_info(origin, current, height, shape, size_default, _current_axis_lock(), equal_base, equal_all)
	var info = {
		"shape": shape,
		"size": computed.size,
		"center": computed.center,
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node != null,
		"brush_id": _next_brush_id()
	}
	if _shape_uses_sides(shape):
		info["sides"] = drag_sides
	return info

func _shape_uses_sides(shape: int) -> bool:
	return shape == BrushShape.PYRAMID \
		or shape == BrushShape.PRISM_TRI \
		or shape == BrushShape.PRISM_PENT

func _next_brush_id() -> String:
	_brush_id_counter += 1
	return "%s_%s" % [str(Time.get_ticks_usec()), str(_brush_id_counter)]

func _register_brush_id(brush_id: String) -> void:
	if brush_id == "":
		return
	var parts = brush_id.split("_")
	if parts.size() == 0:
		return
	var tail = parts[parts.size() - 1]
	if not tail.is_valid_int():
		return
	var value = int(tail)
	if value > _brush_id_counter:
		_brush_id_counter = value

func create_brush_from_info(info: Dictionary) -> Node:
	if info.is_empty():
		return null
	var shape = info.get("shape", BrushShape.BOX)
	var size = info.get("size", drag_size_default)
	var sides = int(info.get("sides", 4))
	var operation = info.get("operation", CSGShape3D.OPERATION_UNION)
	var committed = bool(info.get("committed", false))
	var brush = _create_brush(shape, size, operation, sides)
	if not brush:
		return null
	var pending = bool(info.get("pending", false))
	if committed:
		if committed_node:
			committed_node.add_child(brush)
		brush.visible = false
		brush.operation = CSGShape3D.OPERATION_SUBTRACTION
		brush.set_meta("committed_cut", true)
		brush.set_meta("pending_subtract", false)
		_assign_owner(brush)
	elif operation == CSGShape3D.OPERATION_SUBTRACTION and pending:
		_add_pending_cut(brush)
	else:
		_add_brush_to_draft(brush)
	if info.has("transform"):
		brush.global_transform = info["transform"]
	else:
		brush.global_position = info.get("center", Vector3.ZERO)
	if info.has("material") and not committed and not (operation == CSGShape3D.OPERATION_SUBTRACTION and pending):
		brush.material_override = info["material"]
	if brush_manager and not committed:
		brush_manager.add_brush(brush)
	_record_last_brush(brush.global_position)
	var brush_id = info.get("brush_id", _next_brush_id())
	brush.brush_id = str(brush_id)
	brush.set_meta("brush_id", brush_id)
	_register_brush_id(str(brush_id))
	if info.has("faces"):
		brush.apply_serialized_faces(info.get("faces", []))
	return brush

func delete_brush_by_id(brush_id: String) -> void:
	if brush_id == "":
		return
	var brush = _find_brush_by_id(brush_id)
	if brush:
		delete_brush(brush)

func _find_brush_by_id(brush_id: String) -> Node:
	for node in _iter_pick_nodes():
		if node and node is DraftBrush:
			if node.has_meta("brush_id") and str(node.get_meta("brush_id")) == brush_id:
				return node
			if str((node as DraftBrush).brush_id) == brush_id:
				return node
	return null

func find_brush_by_id(brush_id: String) -> Node:
	return _find_brush_by_id(brush_id)

func get_brush_info_from_node(brush: Node) -> Dictionary:
	if not brush or not (brush is DraftBrush):
		return {}
	var draft := brush as DraftBrush
	var info: Dictionary = {}
	info["shape"] = draft.shape
	info["size"] = draft.size
	if _shape_uses_sides(draft.shape):
		info["sides"] = draft.sides
	var pending = draft.get_parent() == pending_node or bool(draft.get_meta("pending_subtract", false))
	var committed = draft.get_parent() == committed_node or bool(draft.get_meta("committed_cut", false))
	if committed:
		pending = false
	var is_subtract = _is_subtract_brush(draft) or committed
	info["operation"] = CSGShape3D.OPERATION_SUBTRACTION if (pending or is_subtract) else draft.operation
	info["pending"] = pending
	if committed:
		info["committed"] = true
	info["transform"] = draft.global_transform
	if draft.material_override:
		info["material"] = draft.material_override
	if draft.faces.size() > 0:
		info["faces"] = draft.serialize_faces()
	return info

func _capture_entity_info(entity: DraftEntity) -> Dictionary:
	if not entity:
		return {}
	var info: Dictionary = {}
	info["entity_type"] = entity.entity_type
	info["entity_class"] = entity.entity_class
	info["transform"] = entity.global_transform
	info["properties"] = entity.entity_data.duplicate(true)
	info["name"] = entity.name
	return info

func _restore_entity_from_info(info: Dictionary) -> DraftEntity:
	if info.is_empty():
		return null
	if not entities_node:
		_setup_entities_container()
	var entity = DraftEntity.new()
	entity.name = str(info.get("name", "Entity"))
	var type_value = str(info.get("entity_type", info.get("entity_class", "")))
	entity.entity_type = type_value
	entity.entity_class = type_value
	var props = info.get("properties", {})
	if props is Dictionary:
		entity.entity_data = props.duplicate(true)
	if info.has("transform"):
		entity.global_transform = info["transform"]
	entity.set_meta("is_entity", true)
	entities_node.add_child(entity)
	_assign_owner(entity)
	return entity

func build_duplicate_info(brush: Node, offset: Vector3) -> Dictionary:
	var info = get_brush_info_from_node(brush)
	if info.is_empty():
		return {}
	info["brush_id"] = _next_brush_id()
	if info.has("transform"):
		var transform: Transform3D = info["transform"]
		transform.origin += offset
		info["transform"] = transform
	else:
		info["center"] = info.get("center", Vector3.ZERO) + offset
	return info

func _capture_floor_info() -> Dictionary:
	var floor = get_node_or_null("TempFloor") as CSGBox3D
	if not floor:
		return { "exists": false }
	return {
		"exists": true,
		"size": floor.size,
		"transform": floor.global_transform,
		"use_collision": floor.use_collision
	}

func _restore_floor_info(info: Dictionary) -> void:
	if info.is_empty():
		return
	var should_exist = bool(info.get("exists", false))
	var floor = get_node_or_null("TempFloor") as CSGBox3D
	if not should_exist:
		if floor:
			floor.queue_free()
		return
	if not floor:
		floor = CSGBox3D.new()
		floor.name = "TempFloor"
		add_child(floor)
		_assign_owner(floor)
	floor.size = info.get("size", Vector3(1024, 16, 1024))
	if info.has("transform"):
		floor.global_transform = info["transform"]
	floor.use_collision = bool(info.get("use_collision", true))

func capture_state() -> Dictionary:
	var state: Dictionary = {}
	state["brushes"] = []
	state["pending"] = []
	state["committed"] = []
	state["entities"] = []
	state["floor"] = _capture_floor_info()
	state["id_counter"] = _brush_id_counter
	state["csg_visible"] = draft_brushes_node.visible if draft_brushes_node else true
	state["pending_visible"] = pending_node.visible if pending_node else true
	state["baked_present"] = baked_container != null
	state["paint_layers"] = _capture_paint_layers()
	state["paint_active_layer"] = paint_layers.active_layer_index if paint_layers else 0
	if material_manager:
		state["materials"] = material_manager.materials
	for node in _iter_pick_nodes():
		var info = get_brush_info_from_node(node)
		if info.is_empty():
			continue
		if info.get("pending", false):
			state["pending"].append(info)
		else:
			state["brushes"].append(info)
	if committed_node:
		for child in committed_node.get_children():
			if child is DraftBrush:
				var info = get_brush_info_from_node(child)
				if info.is_empty():
					continue
				info["committed"] = true
				state["committed"].append(info)
	if entities_node:
		for child in entities_node.get_children():
			if child is DraftEntity:
				var info = _capture_entity_info(child as DraftEntity)
				if not info.is_empty():
					state["entities"].append(info)
	return state

func _capture_paint_layers() -> Array:
	var out: Array = []
	if not paint_layers:
		return out
	for layer in paint_layers.layers:
		if not layer:
			continue
		var grid = layer.grid
		var entry: Dictionary = {
			"id": str(layer.layer_id),
			"chunk_size": layer.chunk_size,
			"grid": {
				"cell_size": grid.cell_size if grid else 1.0,
				"origin": grid.origin if grid else Vector3.ZERO,
				"basis": grid.basis if grid else Basis.IDENTITY,
				"layer_y": grid.layer_y if grid else 0.0
			},
			"chunks": []
		}
		for cid in layer.get_chunk_ids():
			var bits = layer.get_chunk_bits(cid)
			var bytes: Array = []
			for b in bits:
				bytes.append(int(b))
			entry["chunks"].append({
				"cx": cid.x,
				"cy": cid.y,
				"bits": bytes
			})
		out.append(entry)
	return out

func restore_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	clear_brushes()
	_clear_entities()
	_restore_paint_layers(state.get("paint_layers", []), int(state.get("paint_active_layer", 0)))
	if state.has("materials"):
		set_materials(state.get("materials", []))
	_brush_id_counter = int(state.get("id_counter", 0))
	var brushes: Array = state.get("brushes", [])
	for info in brushes:
		create_brush_from_info(info)
	var pending: Array = state.get("pending", [])
	for info in pending:
		info["pending"] = true
		create_brush_from_info(info)
	var committed: Array = state.get("committed", [])
	for info in committed:
		info["committed"] = true
		create_brush_from_info(info)
	var entities: Array = state.get("entities", [])
	for info in entities:
		_restore_entity_from_info(info)
	_restore_floor_info(state.get("floor", {}))
	if draft_brushes_node:
		draft_brushes_node.visible = bool(state.get("csg_visible", true))
	if pending_node:
		pending_node.visible = bool(state.get("pending_visible", true))
	if not bool(state.get("baked_present", false)) and baked_container:
		baked_container.queue_free()
		baked_container = null

func _restore_paint_layers(data: Array, active_index: int) -> void:
	if not paint_layers:
		_setup_paint_system()
	if not paint_layers:
		return
	paint_layers.clear_layers()
	_clear_generated()
	if data.is_empty():
		paint_layers.create_layer(&"layer_0", grid_plane_origin.y)
		paint_layers.active_layer_index = 0
		return
	for entry in data:
		if not (entry is Dictionary):
			continue
		var layer_id = StringName(str(entry.get("id", "layer_0")))
		var chunk_size = int(entry.get("chunk_size", paint_layers.chunk_size))
		var grid_data = entry.get("grid", {})
		var layer_y = float(grid_data.get("layer_y", grid_plane_origin.y)) if grid_data is Dictionary else grid_plane_origin.y
		var layer = paint_layers.create_layer(layer_id, layer_y)
		layer.chunk_size = chunk_size
		if grid_data is Dictionary and layer.grid:
			layer.grid.cell_size = float(grid_data.get("cell_size", layer.grid.cell_size))
			layer.grid.origin = grid_data.get("origin", layer.grid.origin)
			layer.grid.basis = grid_data.get("basis", layer.grid.basis)
			layer.grid.layer_y = float(grid_data.get("layer_y", layer.grid.layer_y))
		var chunks = entry.get("chunks", [])
		if chunks is Array:
			for chunk in chunks:
				if not (chunk is Dictionary):
					continue
				var cx = int(chunk.get("cx", 0))
				var cy = int(chunk.get("cy", 0))
				var bytes = chunk.get("bits", [])
				var bits = PackedByteArray()
				if bytes is Array:
					bits.resize(bytes.size())
					for i in range(bytes.size()):
						bits[i] = int(bytes[i])
				layer.set_chunk_bits(Vector2i(cx, cy), bits)
	if paint_layers.layers.size() > 0:
		paint_layers.active_layer_index = clamp(active_index, 0, paint_layers.layers.size() - 1)
	_regenerate_paint_layers()

func _regenerate_paint_layers() -> void:
	if not paint_tool or not paint_layers:
		return
	if not paint_tool.geometry or not paint_tool.reconciler:
		return
	_clear_generated()
	for layer in paint_layers.layers:
		if not layer:
			continue
		var chunk_ids = layer.get_chunk_ids()
		if chunk_ids.is_empty():
			continue
		var model = paint_tool.geometry.build_for_chunks(layer, chunk_ids, paint_tool.synth_settings)
		paint_tool.reconciler.reconcile(model, layer.grid, paint_tool.synth_settings, chunk_ids)

func capture_full_state() -> Dictionary:
	return {
		"settings": _capture_hflevel_settings(),
		"state": capture_state()
	}

func restore_full_state(bundle: Dictionary) -> void:
	if bundle.is_empty():
		return
	var settings = bundle.get("settings", {})
	var state = bundle.get("state", {})
	_apply_hflevel_settings(settings if settings is Dictionary else {})
	restore_state(state if state is Dictionary else {})

func _capture_hflevel_settings() -> Dictionary:
	return {
		"grid_snap": grid_snap,
		"bake_chunk_size": bake_chunk_size,
		"bake_collision_layer_index": bake_collision_layer_index,
		"bake_material_override": bake_material_override,
		"bake_use_face_materials": bake_use_face_materials,
		"commit_freeze": commit_freeze,
		"grid_visible": grid_visible,
		"grid_follow_brush": grid_follow_brush,
		"debug_logging": debug_logging,
		"auto_spawn_player": auto_spawn_player,
		"draft_pick_layer_index": draft_pick_layer_index,
		"bake_merge_meshes": bake_merge_meshes,
		"bake_generate_lods": bake_generate_lods,
		"bake_lightmap_uv2": bake_lightmap_uv2,
		"bake_lightmap_texel_size": bake_lightmap_texel_size,
		"bake_navmesh": bake_navmesh,
		"bake_navmesh_cell_size": bake_navmesh_cell_size,
		"bake_navmesh_cell_height": bake_navmesh_cell_height,
		"bake_navmesh_agent_height": bake_navmesh_agent_height,
		"bake_navmesh_agent_radius": bake_navmesh_agent_radius,
		"bake_use_thread_pool": bake_use_thread_pool
	}

func _apply_hflevel_settings(settings: Dictionary) -> void:
	if settings.is_empty():
		return
	if settings.has("grid_snap"):
		grid_snap = float(settings.get("grid_snap", grid_snap))
	if settings.has("bake_chunk_size"):
		bake_chunk_size = float(settings.get("bake_chunk_size", bake_chunk_size))
	if settings.has("bake_collision_layer_index"):
		bake_collision_layer_index = int(settings.get("bake_collision_layer_index", bake_collision_layer_index))
	if settings.has("bake_material_override"):
		bake_material_override = settings.get("bake_material_override", bake_material_override)
	if settings.has("bake_use_face_materials"):
		bake_use_face_materials = bool(settings.get("bake_use_face_materials", bake_use_face_materials))
	if settings.has("commit_freeze"):
		commit_freeze = bool(settings.get("commit_freeze", commit_freeze))
	if settings.has("grid_visible"):
		grid_visible = bool(settings.get("grid_visible", grid_visible))
	if settings.has("grid_follow_brush"):
		grid_follow_brush = bool(settings.get("grid_follow_brush", grid_follow_brush))
	if settings.has("debug_logging"):
		debug_logging = bool(settings.get("debug_logging", debug_logging))
	if settings.has("auto_spawn_player"):
		auto_spawn_player = bool(settings.get("auto_spawn_player", auto_spawn_player))
	if settings.has("draft_pick_layer_index"):
		draft_pick_layer_index = int(settings.get("draft_pick_layer_index", draft_pick_layer_index))
	if settings.has("bake_merge_meshes"):
		bake_merge_meshes = bool(settings.get("bake_merge_meshes", bake_merge_meshes))
	if settings.has("bake_generate_lods"):
		bake_generate_lods = bool(settings.get("bake_generate_lods", bake_generate_lods))
	if settings.has("bake_lightmap_uv2"):
		bake_lightmap_uv2 = bool(settings.get("bake_lightmap_uv2", bake_lightmap_uv2))
	if settings.has("bake_lightmap_texel_size"):
		bake_lightmap_texel_size = float(settings.get("bake_lightmap_texel_size", bake_lightmap_texel_size))
	if settings.has("bake_navmesh"):
		bake_navmesh = bool(settings.get("bake_navmesh", bake_navmesh))
	if settings.has("bake_navmesh_cell_size"):
		bake_navmesh_cell_size = float(settings.get("bake_navmesh_cell_size", bake_navmesh_cell_size))
	if settings.has("bake_navmesh_cell_height"):
		bake_navmesh_cell_height = float(settings.get("bake_navmesh_cell_height", bake_navmesh_cell_height))
	if settings.has("bake_navmesh_agent_height"):
		bake_navmesh_agent_height = float(settings.get("bake_navmesh_agent_height", bake_navmesh_agent_height))
	if settings.has("bake_navmesh_agent_radius"):
		bake_navmesh_agent_radius = float(settings.get("bake_navmesh_agent_radius", bake_navmesh_agent_radius))
	if settings.has("bake_use_thread_pool"):
		bake_use_thread_pool = bool(settings.get("bake_use_thread_pool", bake_use_thread_pool))

func _capture_hflevel_state() -> Dictionary:
	var state = capture_state()
	var data: Dictionary = {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"settings": _capture_hflevel_settings(),
		"state": state
	}
	return HFLevelIO.encode_variant(data)

func save_hflevel(path: String = "", force: bool = false) -> int:
	var target = path if path != "" else hflevel_autosave_path
	if target == "":
		return ERR_INVALID_PARAMETER
	_ensure_dir_for_path(target)
	var encoded = _capture_hflevel_state()
	var json = JSON.stringify(encoded)
	var hash_value = json.hash()
	if not force and hash_value == _hflevel_last_hash:
		return OK
	_hflevel_last_hash = hash_value
	var payload = HFLevelIO.build_payload_from_json(json, hflevel_compress)
	_start_hflevel_thread(target, payload)
	return OK

func load_hflevel(path: String = "") -> bool:
	var target = path if path != "" else hflevel_autosave_path
	if target == "":
		return false
	var data = HFLevelIO.load_from_path(target)
	if data.is_empty():
		return false
	var decoded = HFLevelIO.decode_variant(data)
	if not (decoded is Dictionary):
		return false
	var settings = decoded.get("settings", {})
	var state = decoded.get("state", {})
	_apply_hflevel_settings(settings if settings is Dictionary else {})
	restore_state(state if state is Dictionary else {})
	return true

func _ensure_dir_for_path(path: String) -> void:
	var abs_path = path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	var dir_path = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

func _start_hflevel_thread(path: String, payload: PackedByteArray) -> void:
	if path == "" or payload.is_empty():
		return
	var abs_path = ProjectSettings.globalize_path(path)
	_ensure_dir_for_path(abs_path)
	if _hflevel_thread and _hflevel_thread.is_alive():
		_hflevel_pending = {
			"path": abs_path,
			"payload": payload
		}
		return
	_hflevel_thread = Thread.new()
	_hflevel_thread.start(Callable(self, "_hflevel_thread_write").bind(abs_path, payload))

func _hflevel_thread_write(path: String, payload: PackedByteArray) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return
	file.store_buffer(payload)

func import_map(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	var map_data = MapIO.load_map(path)
	if map_data.is_empty():
		return ERR_INVALID_DATA
	clear_brushes()
	_clear_entities()
	for info in map_data.get("brushes", []):
		if info is Dictionary:
			create_brush_from_info(info)
	for entity_info in map_data.get("entities", []):
		if entity_info is Dictionary:
			_create_entity_from_map(entity_info)
	return OK

func export_map(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	_ensure_dir_for_path(path)
	var text = MapIO.export_map_from_level(self)
	if text == "":
		return ERR_INVALID_DATA
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return ERR_CANT_OPEN
	file.store_string(text)
	return OK

func export_baked_gltf(path: String) -> int:
	if path == "":
		return ERR_INVALID_PARAMETER
	if not baked_container:
		return ERR_DOES_NOT_EXIST
	if not ClassDB.class_exists("GLTFDocument"):
		return ERR_UNAVAILABLE
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = ERR_CANT_CREATE
	if doc.has_method("append_from_scene"):
		err = doc.call("append_from_scene", baked_container, state)
	elif doc.has_method("append_from_node"):
		err = doc.call("append_from_node", baked_container, state)
	if err != OK:
		return err
	if doc.has_method("write_to_filesystem"):
		return doc.call("write_to_filesystem", state, path)
	return ERR_UNAVAILABLE

func place_entity_at_screen(camera: Camera3D, mouse_pos: Vector2, entity_type: String) -> DraftEntity:
	if not camera:
		return null
	var hit = _raycast(camera, mouse_pos)
	if not hit:
		return null
	var snapped = _snap_point(hit.position)
	var entity = DraftEntity.new()
	entity.name = "DraftEntity"
	if entity_type != "":
		entity.entity_type = entity_type
		entity.entity_class = entity_type
	add_entity(entity)
	entity.global_position = snapped
	return entity

func _create_entity_from_map(info: Dictionary) -> DraftEntity:
	if info.is_empty():
		return null
	var entity_class = str(info.get("classname", ""))
	if entity_class == "":
		return null
	var entity = DraftEntity.new()
	entity.name = "DraftEntity"
	entity.entity_type = entity_class
	entity.entity_class = entity_class
	var props = info.get("properties", {})
	if props is Dictionary:
		var data = props.duplicate(true)
		data.erase("classname")
		data.erase("origin")
		entity.entity_data = data
	var origin = info.get("origin", Vector3.ZERO)
	if origin is Vector3:
		entity.global_position = origin
	add_entity(entity)
	return entity

func _is_entity_node(node: Node) -> bool:
	if not node or not (node is Node3D):
		return false
	if bool(node.get_meta("is_entity", false)):
		return true
	if not entities_node:
		return false
	var current: Node = node
	while current:
		if current == entities_node:
			return true
		current = current.get_parent()
	return false

func is_brush_node(node: Node) -> bool:
	if not node or not (node is DraftBrush):
		return false
	if _is_entity_node(node):
		return false
	if node == pending_node:
		return false
	var parent = node.get_parent()
	if parent == pending_node:
		return true
	return parent == draft_brushes_node

func is_entity_node(node: Node) -> bool:
	return _is_entity_node(node)

func restore_brush(brush: Node, parent: Node, owner: Node, index: int) -> void:
	if not brush or not parent:
		return
	if brush.get_parent():
		brush.get_parent().remove_child(brush)
	parent.add_child(brush)
	if index >= 0 and index < parent.get_child_count():
		parent.move_child(brush, index)
	if owner:
		brush.owner = owner
	if brush_manager and brush is Node3D:
		brush_manager.add_brush(brush)

func begin_drag(
	camera: Camera3D,
	mouse_pos: Vector2,
	operation: int,
	size: Vector3,
	shape: int,
	sides: int = 4
) -> bool:
	if drag_stage != 0:
		return false
	var hit = _raycast(camera, mouse_pos)
	if not hit:
		return false
	drag_active = true
	drag_origin = _snap_point(hit.position)
	drag_end = drag_origin
	drag_operation = operation
	drag_shape = shape
	drag_sides = sides
	drag_height = grid_snap if grid_snap > 0.0 else size.y
	drag_size_default = size
	drag_stage = 1
	if not manual_axis_lock:
		axis_lock = AxisLock.NONE
	lock_axis_active = AxisLock.NONE
	locked_thickness = Vector3.ZERO
	height_stage_start_mouse = mouse_pos
	height_stage_start_height = drag_height
	_ensure_preview(shape, operation, drag_size_default, drag_sides)
	_update_preview(drag_origin, drag_origin, drag_height, drag_shape, drag_size_default, _current_axis_lock(), shift_pressed and not alt_pressed, shift_pressed and alt_pressed)
	return true

func update_drag(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not drag_active:
		return
	if drag_stage == 1:
		var hit = _raycast(camera, mouse_pos)
		if not hit:
			return
		if not alt_pressed or shift_pressed:
			drag_end = _snap_point(hit.position)
			_apply_axis_lock(drag_origin, drag_end)
			_update_lock_state(drag_origin, drag_end)
		if alt_pressed:
			drag_height = _height_from_mouse(mouse_pos, height_stage_start_mouse, height_stage_start_height)
		_update_preview(drag_origin, drag_end, drag_height, drag_shape, drag_size_default, _current_axis_lock(), shift_pressed and not alt_pressed, shift_pressed and alt_pressed)
	elif drag_stage == 2:
		drag_height = _height_from_mouse(mouse_pos, height_stage_start_mouse, height_stage_start_height)
		_update_preview(drag_origin, drag_end, drag_height, drag_shape, drag_size_default, _current_axis_lock(), shift_pressed and not alt_pressed, shift_pressed and alt_pressed)

func end_drag_info(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> Dictionary:
	if not drag_active:
		return { "handled": false }
	if drag_stage == 1:
		drag_stage = 2
		height_stage_start_mouse = mouse_pos
		height_stage_start_height = drag_height
		return { "handled": true, "placed": false }
	drag_active = false
	drag_stage = 0
	lock_axis_active = AxisLock.NONE
	var info = _build_brush_info(drag_origin, drag_end, drag_height, drag_shape, size_default, drag_operation, shift_pressed and not alt_pressed, shift_pressed and alt_pressed)
	_clear_preview()
	return { "handled": true, "placed": true, "info": info }

func end_drag(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> bool:
	var result = end_drag_info(camera, mouse_pos, size_default)
	if not result.get("handled", false):
		return false
	if result.get("placed", false):
		create_brush_from_info(result.get("info", {}))
	return true

func cancel_drag() -> void:
	drag_active = false
	drag_stage = 0
	lock_axis_active = AxisLock.NONE
	_clear_preview()

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
			best_hit = { "position": from + ray_dir * t }
	if not best_hit.is_empty():
		return best_hit
	var plane = Plane(Vector3.UP, 0.0)
	var denom = plane.normal.dot(to - from)
	if abs(denom) > 0.0001:
		var t = plane.distance_to(from) / denom
		if t >= 0.0 and t <= 1.0:
			return { "position": from.lerp(to, t) }
	return {}

func _height_from_mouse(current: Vector2, start: Vector2, start_height: float) -> float:
	var delta = current.y - start.y
	var raw_height = start_height + (-delta / max(1.0, height_pixels_per_unit))
	if grid_snap > 0.0:
		raw_height = max(grid_snap, snappedf(raw_height, grid_snap))
	return max(0.1, raw_height)

func set_axis_lock(lock: int, manual: bool = true) -> void:
	if manual:
		if manual_axis_lock and axis_lock == lock:
			axis_lock = AxisLock.NONE
			manual_axis_lock = false
			_refresh_grid_plane()
			return
		axis_lock = lock
		manual_axis_lock = true
		_refresh_grid_plane()
		return
	axis_lock = lock
	_refresh_grid_plane()

func set_shift_pressed(pressed: bool) -> void:
	shift_pressed = pressed
	if not pressed and not manual_axis_lock:
		axis_lock = AxisLock.NONE
	_refresh_grid_plane()

func set_alt_pressed(pressed: bool) -> void:
	alt_pressed = pressed

func _current_axis_lock() -> int:
	if manual_axis_lock:
		return axis_lock
	return AxisLock.NONE

func _apply_axis_lock(origin: Vector3, current: Vector3) -> Vector3:
	return current

func _update_lock_state(origin: Vector3, current: Vector3) -> void:
	var lock = _current_axis_lock()
	if lock == AxisLock.NONE:
		lock_axis_active = AxisLock.NONE
		locked_thickness = Vector3.ZERO
		return
	if lock != lock_axis_active:
		lock_axis_active = lock
		if lock == AxisLock.X:
			locked_thickness.z = abs(current.z - origin.z)
		elif lock == AxisLock.Z:
			locked_thickness.x = abs(current.x - origin.x)
		elif lock == AxisLock.Y:
			locked_thickness.x = abs(current.x - origin.x)
			locked_thickness.z = abs(current.z - origin.z)

func _pick_axis(origin: Vector3, current: Vector3) -> int:
	var dx = abs(current.x - origin.x)
	var dz = abs(current.z - origin.z)
	return AxisLock.X if dx >= dz else AxisLock.Z

func _snap_point(point: Vector3) -> Vector3:
	if grid_snap <= 0.0:
		return point
	return point.snapped(Vector3(grid_snap, grid_snap, grid_snap))

func _ensure_preview(shape: int, operation: int, size_default: Vector3, sides: int) -> void:
	if preview_brush:
		var needs_replace = preview_brush.shape != shape
		if not needs_replace:
			preview_brush.sides = sides
			if operation == CSGShape3D.OPERATION_SUBTRACTION:
				preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
				_apply_brush_material(preview_brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
			else:
				preview_brush.operation = operation
				_apply_brush_material(preview_brush, _make_brush_material(operation))
			return
		_clear_preview()
	preview_brush = _create_brush(shape, size_default, operation, sides)
	if not preview_brush:
		return
	preview_brush.name = "PreviewBrush"
	if operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node:
		preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
		_apply_brush_material(preview_brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
		pending_node.add_child(preview_brush)
	else:
		if draft_brushes_node:
			draft_brushes_node.add_child(preview_brush)

func _update_preview(origin: Vector3, current: Vector3, height: float, shape: int, size_default: Vector3, lock_axis: int, equal_base: bool, equal_all: bool) -> void:
	if not preview_brush:
		return
	var info = _compute_brush_info(origin, current, height, shape, size_default, lock_axis, equal_base, equal_all)
	preview_brush.global_position = info.center
	preview_brush.size = info.size

func _clear_preview() -> void:
	if preview_brush and preview_brush.is_inside_tree():
		preview_brush.queue_free()
	preview_brush = null

func _compute_brush_info(origin: Vector3, current: Vector3, height: float, shape: int, size_default: Vector3, lock_axis: int, equal_base: bool, equal_all: bool) -> Dictionary:
	var min_x = min(origin.x, current.x)
	var max_x = max(origin.x, current.x)
	var min_z = min(origin.z, current.z)
	var max_z = max(origin.z, current.z)
	if lock_axis == AxisLock.X:
		var thickness_z = locked_thickness.z if locked_thickness.z > 0.0 else max(grid_snap, size_default.z * 0.25)
		var half_z = max(0.1, thickness_z * 0.5)
		min_z = origin.z - half_z
		max_z = origin.z + half_z
	elif lock_axis == AxisLock.Z:
		var thickness_x = locked_thickness.x if locked_thickness.x > 0.0 else max(grid_snap, size_default.x * 0.25)
		var half_x = max(0.1, thickness_x * 0.5)
		min_x = origin.x - half_x
		max_x = origin.x + half_x
	elif lock_axis == AxisLock.Y:
		var thickness_x = locked_thickness.x if locked_thickness.x > 0.0 else max(grid_snap, size_default.x * 0.25)
		var thickness_z = locked_thickness.z if locked_thickness.z > 0.0 else max(grid_snap, size_default.z * 0.25)
		var half_x = max(0.1, thickness_x * 0.5)
		var half_z = max(0.1, thickness_z * 0.5)
		min_x = origin.x - half_x
		max_x = origin.x + half_x
		min_z = origin.z - half_z
		max_z = origin.z + half_z
	var size_x = max_x - min_x
	var size_z = max_z - min_z
	if equal_base:
		var side = max(size_x, size_z)
		size_x = side
		size_z = side
		min_x = origin.x - side * 0.5
		max_x = origin.x + side * 0.5
		min_z = origin.z - side * 0.5
		max_z = origin.z + side * 0.5
	if equal_all:
		var side_all = max(size_x, size_z)
		size_x = side_all
		size_z = side_all
		height = side_all
		min_x = origin.x - side_all * 0.5
		max_x = origin.x + side_all * 0.5
		min_z = origin.z - side_all * 0.5
		max_z = origin.z + side_all * 0.5
	var extent = max(size_x, size_z)
	var min_extent = max(0.1, grid_snap * 0.5)
	var final_size = Vector3(size_x, height, size_z)
	if extent < min_extent:
		final_size = Vector3(size_default.x, height, size_default.z)
		min_x = origin.x - final_size.x * 0.5
		max_x = origin.x + final_size.x * 0.5
		min_z = origin.z - final_size.z * 0.5
		max_z = origin.z + final_size.z * 0.5
	var center = Vector3((min_x + max_x) * 0.5, origin.y + height * 0.5, (min_z + max_z) * 0.5)
	if shape == BrushShape.CYLINDER:
		var radius = max(final_size.x, final_size.z) * 0.5
		final_size = Vector3(radius * 2.0, height, radius * 2.0)
	return { "center": center, "size": final_size }

func pick_brush(camera: Camera3D, mouse_pos: Vector2, include_entities: bool = true) -> Node:
	if not draft_brushes_node or not camera:
		return null
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos).normalized()
	var closest = null
	var best_t = INF
	var nodes = _iter_pick_nodes()
	for child in nodes:
		if not (child is DraftBrush) or not is_brush_node(child):
			continue
		var mesh_inst: MeshInstance3D = child.mesh_instance
		if not mesh_inst:
			continue
		var inv = mesh_inst.global_transform.affine_inverse()
		var local_origin = inv * ray_origin
		var local_dir = (inv.basis * ray_dir).normalized()
		var aabb = mesh_inst.get_aabb()
		var t = _ray_intersect_aabb(local_origin, local_dir, aabb)
		if t >= 0.0 and t < best_t:
			best_t = t
			closest = child
	if closest or not include_entities:
		return closest
	var closest_entity: Node = null
	var best_entity_t = INF
	for child in nodes:
		if not (child is Node3D) or not is_entity_node(child):
			continue
		var t_entity = _entity_pick_distance(child as Node3D, ray_origin, ray_dir)
		if t_entity >= 0.0 and t_entity < best_entity_t:
			best_entity_t = t_entity
			closest_entity = child
	return closest_entity

func get_live_brush_count() -> int:
	var count = 0
	for node in _iter_pick_nodes():
		if node and node is DraftBrush:
			count += 1
	return count

func update_hover(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not hover_highlight or not camera:
		return
	var brush = pick_brush(camera, mouse_pos, false)
	if brush and brush is DraftBrush:
		var mesh_inst: MeshInstance3D = brush.mesh_instance
		if not mesh_inst:
			hover_highlight.visible = false
			return
		var aabb = mesh_inst.get_aabb()
		hover_highlight.visible = true
		hover_highlight.global_transform = mesh_inst.global_transform
		hover_highlight.scale = aabb.size
	else:
		hover_highlight.visible = false

func clear_hover() -> void:
	if hover_highlight:
		hover_highlight.visible = false

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

func _log(message: String) -> void:
	if not debug_logging:
		return
	print("[HammerForge LevelRoot] %s" % message)
