@tool
extends Node3D
class_name LevelRoot

const BrushManager = preload("brush_manager.gd")
const Baker = preload("baker.gd")
const PrefabFactory = preload("prefab_factory.gd")
const DraftEntity = preload("draft_entity.gd")

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
@export var entity_definitions_path: String = "res://addons/hammerforge/entities.json"
@export var commit_freeze: bool = true
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
var baker: Baker
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

func _ready():
    _setup_draft_container()
    _setup_pending_container()
    _setup_committed()
    _setup_entities_container()
    _load_entity_definitions()
    _setup_manager()
    _setup_baker()
    _setup_editor_grid()
    _setup_highlight()
    _log("Ready (grid_visible=%s, follow_grid=%s)" % [_grid_visible, grid_follow_brush])

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

func _setup_baker() -> void:
    baker = get_node_or_null("Baker") as Baker
    if not baker:
        baker = Baker.new()
        baker.name = "Baker"
        add_child(baker)
        _assign_owner(baker)

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
    if bake_chunk_size > 0.0:
        baked = await _bake_chunked(bake_chunk_size, layer)
    else:
        baked = await _bake_single(layer)

    if baked:
        if baked_container:
            baked_container.queue_free()
        baked_container = baked
        add_child(baked_container)
        _assign_owner(baked_container)
        if hide_live:
            if draft_brushes_node:
                draft_brushes_node.visible = false
            if pending_node:
                pending_node.visible = false
        _log("Bake finished (success=true)")
        bake_finished.emit(true)
    else:
        _log("Bake failed")
        bake_finished.emit(false)

func _bake_single(layer: int) -> Node3D:
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

    await _await_csg_update()

    var baked = baker.bake_from_csg(temp_csg, bake_material_override, layer, layer)
    var collision_baked: Node3D = null
    if baked:
        collision_baked = baker.bake_from_csg(collision_csg, null, layer, layer)
        _apply_collision_from_bake(baked, collision_baked, layer)

    temp_csg.queue_free()
    collision_csg.queue_free()
    if collision_baked:
        collision_baked.free()
    return baked

func _bake_chunked(chunk_size: float, layer: int) -> Node3D:
    var size = max(0.001, chunk_size)
    var chunks: Dictionary = {}
    _collect_chunk_brushes(draft_brushes_node, size, chunks, "brushes")
    if commit_freeze and committed_node:
        _collect_chunk_brushes(committed_node, size, chunks, "committed")
    if chunks.is_empty():
        return null

    var container = Node3D.new()
    container.name = "BakedGeometry"
    var chunk_count = 0
    for coord in chunks:
        var entry: Dictionary = chunks[coord]
        var brushes: Array = entry.get("brushes", [])
        var committed: Array = entry.get("committed", [])
        if brushes.is_empty() and committed.is_empty():
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
        if commit_freeze:
            _append_brush_list_to_csg(committed, temp_csg, true)
        _append_brush_list_to_csg(brushes, collision_csg, false, true)

        await _await_csg_update()

        var baked_chunk = baker.bake_from_csg(temp_csg, bake_material_override, layer, layer)
        if baked_chunk:
            var collision_baked = baker.bake_from_csg(collision_csg, null, layer, layer)
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
            chunks[coord] = { "brushes": [], "committed": [] }
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

func clear_brushes() -> void:
    if brush_manager:
        brush_manager.clear_brushes()
    if draft_brushes_node:
        for child in draft_brushes_node.get_children():
            if child is DraftBrush:
                child.queue_free()
    _clear_preview()
    clear_pending_cuts()
    _clear_committed_cuts()
    if baked_container:
        baked_container.queue_free()
        baked_container = null

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

func restore_state(state: Dictionary) -> void:
    if state.is_empty():
        return
    clear_brushes()
    _clear_entities()
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
        if not (child is DraftBrush):
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
        if not (child is Node3D) or not _is_entity_node(child):
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
