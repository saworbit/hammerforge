@tool
extends Node3D
class_name LevelRoot

const BrushManager = preload("brush_manager.gd")
const Baker = preload("baker.gd")
const PrefabFactory = preload("prefab_factory.gd")

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

var csg_node: CSGCombiner3D
var add_brushes_node: CSGCombiner3D
var subtract_brushes_node: CSGCombiner3D
var pending_node: CSGCombiner3D
var committed_node: Node3D
var brush_manager: BrushManager
var baker: Baker
var baked_container: Node3D
var preview_brush: CSGShape3D = null
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

func _ready():
    _setup_csg()
    _setup_pending()
    _setup_committed()
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
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(1.0, 1.0, 0.0, 0.5)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.no_depth_test = true
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.wireframe = true
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
    var owner = _get_editor_owner()
    if owner:
        node.owner = owner

func _setup_csg() -> void:
    csg_node = get_node_or_null("BrushCSG") as CSGCombiner3D
    if not csg_node:
        csg_node = CSGCombiner3D.new()
        csg_node.name = "BrushCSG"
        csg_node.use_collision = true
        add_child(csg_node)
        _assign_owner(csg_node)
    _setup_brush_folders()
    if Engine.is_editor_hint() and not csg_node.visible:
        csg_node.visible = true

func _setup_brush_folders() -> void:
    if not csg_node:
        return
    add_brushes_node = csg_node.get_node_or_null("Add_Brushes") as CSGCombiner3D
    if not add_brushes_node:
        add_brushes_node = CSGCombiner3D.new()
        add_brushes_node.name = "Add_Brushes"
        add_brushes_node.use_collision = true
        add_brushes_node.operation = CSGShape3D.OPERATION_UNION
        csg_node.add_child(add_brushes_node)
        _assign_owner(add_brushes_node)
    subtract_brushes_node = csg_node.get_node_or_null("Subtract_Brushes") as CSGCombiner3D
    if not subtract_brushes_node:
        subtract_brushes_node = CSGCombiner3D.new()
        subtract_brushes_node.name = "Subtract_Brushes"
        subtract_brushes_node.use_collision = true
        subtract_brushes_node.operation = CSGShape3D.OPERATION_SUBTRACTION
        csg_node.add_child(subtract_brushes_node)
        _assign_owner(subtract_brushes_node)
    else:
        subtract_brushes_node.operation = CSGShape3D.OPERATION_SUBTRACTION

func _setup_pending() -> void:
    pending_node = get_node_or_null("PendingCuts") as CSGCombiner3D
    if not pending_node:
        pending_node = CSGCombiner3D.new()
        pending_node.name = "PendingCuts"
        pending_node.use_collision = false
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
    if not csg_node:
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
        _add_brush_to_csg(brush, operation)
    brush_manager.add_brush(brush)
    _record_last_brush(brush.global_position)
    return true

func _get_live_brush_parent(operation: int, staged: bool) -> Node:
    if staged and pending_node:
        return pending_node
    if operation == CSGShape3D.OPERATION_SUBTRACTION:
        return subtract_brushes_node if subtract_brushes_node else csg_node
    return add_brushes_node if add_brushes_node else csg_node

func _is_subtract_brush(node: Node) -> bool:
    if not (node is CSGShape3D):
        return false
    if node.operation == CSGShape3D.OPERATION_SUBTRACTION:
        return true
    return subtract_brushes_node and node.get_parent() == subtract_brushes_node

func _set_brush_operation_for_parent(brush: CSGShape3D, parent: Node, operation: int) -> void:
    if not brush:
        return
    if parent == subtract_brushes_node:
        brush.operation = CSGShape3D.OPERATION_UNION
    else:
        brush.operation = operation

func _add_brush_to_csg(brush: CSGShape3D, operation: int) -> void:
    var parent = _get_live_brush_parent(operation, false)
    if not parent:
        return
    if operation == CSGShape3D.OPERATION_SUBTRACTION:
        _set_brush_operation_for_parent(brush, parent, operation)
    parent.add_child(brush)
    _assign_owner(brush)

func bake(apply_cuts: bool = true, hide_live: bool = false, collision_layer_mask: int = 0) -> void:
    if not baker or not csg_node:
        return
    if apply_cuts:
        apply_pending_cuts()
    var prev_csg_visible = csg_node.visible
    var prev_pending_visible = pending_node.visible if pending_node else true
    csg_node.visible = true
    if pending_node:
        pending_node.visible = true
    var borrowed_cuts := _borrow_committed_cuts_for_bake()
    _log("Bake start (apply_cuts=%s, hide_live=%s, borrowed_cuts=%s)" % [apply_cuts, hide_live, borrowed_cuts.size()])
    bake_started.emit()
    await _await_csg_update()
    var restore_map := _neutralize_subtract_materials()
    var override = bake_material_override
    if not override and csg_node.material_override:
        override = csg_node.material_override
    var layer = collision_layer_mask if collision_layer_mask > 0 else _layer_from_index(bake_collision_layer_index)
    var baked = baker.bake_from_csg(csg_node, override, layer, layer)
    _restore_subtract_materials(restore_map)
    _restore_borrowed_committed_cuts(borrowed_cuts)
    if not baked:
        _log("Bake failed")
        csg_node.visible = prev_csg_visible
        if pending_node:
            pending_node.visible = prev_pending_visible
        bake_finished.emit(false)
        return
    if baked_container:
        baked_container.queue_free()
    baked_container = baked
    add_child(baked_container)
    _assign_owner(baked_container)
    if hide_live:
        csg_node.visible = false
        if pending_node:
            pending_node.visible = false
    else:
        csg_node.visible = prev_csg_visible
        if pending_node:
            pending_node.visible = prev_pending_visible
    _log("Bake finished (success=true)")
    bake_finished.emit(true)

func _borrow_committed_cuts_for_bake() -> Array:
    var borrowed: Array = []
    if not commit_freeze or not committed_node or not csg_node:
        return borrowed
    var target_parent = _get_live_brush_parent(CSGShape3D.OPERATION_SUBTRACTION, false)
    for child in committed_node.get_children():
        if child is CSGShape3D:
            borrowed.append({ "node": child, "visible": child.visible })
    for entry in borrowed:
        var node = entry["node"]
        committed_node.remove_child(node)
        if target_parent:
            target_parent.add_child(node)
        _set_brush_operation_for_parent(node, target_parent, CSGShape3D.OPERATION_SUBTRACTION)
        node.visible = true
        _assign_owner(node)
    if borrowed.size() > 0:
        _log("Borrowed committed cuts for bake (%s)" % borrowed.size())
    return borrowed

func _restore_borrowed_committed_cuts(borrowed: Array) -> void:
    if borrowed.is_empty():
        return
    if not committed_node or not csg_node:
        return
    for entry in borrowed:
        var node = entry.get("node", null)
        if node and node.get_parent() != committed_node:
            node.get_parent().remove_child(node)
            committed_node.add_child(node)
            node.visible = entry.get("visible", false)
    if borrowed.size() > 0:
        _log("Restored committed cuts after bake (%s)" % borrowed.size())

func _neutralize_subtract_materials() -> Dictionary:
    var restore := {}
    if not csg_node:
        return restore
    var targets: Array = []
    if subtract_brushes_node:
        targets.append_array(subtract_brushes_node.get_children())
    for child in csg_node.get_children():
        if child is CSGShape3D and child != add_brushes_node and child != subtract_brushes_node:
            targets.append(child)
    for child in targets:
        if _is_subtract_brush(child):
            restore[child] = {
                "material": child.get("material"),
                "material_override": child.get("material_override")
            }
            child.set("material", null)
            child.set("material_override", null)
    return restore

func _restore_subtract_materials(restore: Dictionary) -> void:
    for brush in restore.keys():
        if brush and brush is Node:
            var data = restore[brush]
            brush.set("material", data.get("material", null))
            brush.set("material_override", data.get("material_override", null))

func clear_brushes() -> void:
    if brush_manager:
        brush_manager.clear_brushes()
    if add_brushes_node:
        for child in add_brushes_node.get_children():
            if child is CSGShape3D:
                child.queue_free()
    if subtract_brushes_node:
        for child in subtract_brushes_node.get_children():
            if child is CSGShape3D:
                child.queue_free()
    _clear_preview()
    clear_pending_cuts()
    _clear_committed_cuts()

func _clear_committed_cuts() -> void:
    if not committed_node:
        return
    for child in committed_node.get_children():
        if child is CSGShape3D:
            child.queue_free()

func apply_pending_cuts() -> void:
    if not pending_node or not csg_node:
        return
    var pending_count = pending_node.get_child_count()
    var target_parent = _get_live_brush_parent(CSGShape3D.OPERATION_SUBTRACTION, false)
    var use_union = target_parent == subtract_brushes_node
    for child in pending_node.get_children():
        if child is CSGShape3D:
            pending_node.remove_child(child)
            if target_parent:
                target_parent.add_child(child)
            child.operation = CSGShape3D.OPERATION_UNION if use_union else CSGShape3D.OPERATION_SUBTRACTION
            child.use_collision = true
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
    if not csg_node:
        return
    var targets: Array = []
    if subtract_brushes_node:
        targets = subtract_brushes_node.get_children()
    else:
        targets = csg_node.get_children()
    for child in targets:
        if _is_subtract_brush(child):
            if commit_freeze:
                _stash_committed_cut(child)
            else:
                if brush_manager:
                    brush_manager.remove_brush(child)
                child.call_deferred("queue_free")

func _stash_committed_cut(brush: CSGShape3D) -> void:
    if not committed_node or not csg_node:
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
    if not committed_node or not csg_node:
        return
    var restored = 0
    for child in committed_node.get_children():
        if child is CSGShape3D:
            committed_node.remove_child(child)
            var target_parent = _get_live_brush_parent(CSGShape3D.OPERATION_SUBTRACTION, false)
            if target_parent:
                target_parent.add_child(child)
            child.visible = true
            _set_brush_operation_for_parent(child, target_parent, CSGShape3D.OPERATION_SUBTRACTION)
            _apply_brush_material(child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
            child.set_meta("committed_cut", false)
            _assign_owner(child)
            if brush_manager:
                brush_manager.add_brush(child)
            restored += 1
    csg_node.visible = true
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
        if child is CSGShape3D:
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

func _create_brush(shape: int, size: Vector3, operation: int, sides: int) -> CSGShape3D:
    var brush = PrefabFactory.create_prefab(shape, size, sides)
    brush.operation = operation
    brush.use_collision = true
    _apply_brush_material(brush, _make_brush_material(operation))
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
    brush.set("material", mat)
    brush.set("material_override", mat)

func apply_material_to_brush(brush: Node, mat: Material) -> void:
    if not brush or not mat:
        return
    brush.set("material_override", mat)
    brush.set("material", mat)

func _add_pending_cut(brush: CSGShape3D) -> void:
    if not pending_node:
        return
    brush.operation = CSGShape3D.OPERATION_UNION
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

func create_brush_from_info(info: Dictionary) -> Node:
    if info.is_empty():
        return null
    var shape = info.get("shape", BrushShape.BOX)
    var size = info.get("size", drag_size_default)
    var sides = int(info.get("sides", 4))
    var operation = info.get("operation", CSGShape3D.OPERATION_UNION)
    var brush = _create_brush(shape, size, operation, sides)
    if brush is CSGCylinder3D and info.has("sides"):
        brush.sides = int(info["sides"])
    var pending = bool(info.get("pending", false))
    if operation == CSGShape3D.OPERATION_SUBTRACTION and pending:
        _add_pending_cut(brush)
    else:
        _add_brush_to_csg(brush, operation)
    if info.has("transform"):
        brush.global_transform = info["transform"]
    else:
        brush.global_position = info.get("center", Vector3.ZERO)
    if info.has("material") and not (operation == CSGShape3D.OPERATION_SUBTRACTION and pending):
        _apply_brush_material(brush, info["material"])
    if brush_manager:
        brush_manager.add_brush(brush)
    _record_last_brush(brush.global_position)
    var brush_id = info.get("brush_id", _next_brush_id())
    brush.set_meta("brush_id", brush_id)
    return brush

func delete_brush_by_id(brush_id: String) -> void:
    if brush_id == "":
        return
    var brush = _find_brush_by_id(brush_id)
    if brush:
        delete_brush(brush)

func _find_brush_by_id(brush_id: String) -> Node:
    for node in _iter_pick_nodes():
        if node and node.has_meta("brush_id") and str(node.get_meta("brush_id")) == brush_id:
            return node
    return null

func find_brush_by_id(brush_id: String) -> Node:
    return _find_brush_by_id(brush_id)

func get_brush_info_from_node(brush: Node) -> Dictionary:
    if not brush or not (brush is CSGShape3D):
        return {}
    var info: Dictionary = {}
    if brush is CSGBox3D:
        info["shape"] = BrushShape.BOX
        info["size"] = brush.size
    elif brush is CSGCylinder3D:
        info["shape"] = BrushShape.CYLINDER
        info["size"] = Vector3(brush.radius * 2.0, brush.height, brush.radius * 2.0)
        info["sides"] = brush.sides
    elif brush.has_meta("prefab_shape"):
        info["shape"] = int(brush.get_meta("prefab_shape"))
        if brush.has_meta("prefab_size"):
            var base_size: Vector3 = brush.get_meta("prefab_size")
            var scale := brush.scale
            info["size"] = Vector3(
                base_size.x * scale.x,
                base_size.y * scale.y,
                base_size.z * scale.z
            )
        else:
            info["size"] = drag_size_default
    else:
        return {}
    var pending = brush.get_parent() == pending_node or bool(brush.get_meta("pending_subtract", false))
    var is_subtract = _is_subtract_brush(brush)
    info["operation"] = CSGShape3D.OPERATION_SUBTRACTION if (pending or is_subtract) else brush.operation
    info["pending"] = pending
    info["transform"] = brush.global_transform
    var source_mat = brush.material_override if brush.material_override else brush.get("material")
    if source_mat:
        info["material"] = source_mat
    if brush.has_meta("sides"):
        info["sides"] = int(brush.get_meta("sides"))
    return info

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

func is_brush_node(node: Node) -> bool:
    if not node or not (node is CSGShape3D):
        return false
    if node == add_brushes_node or node == subtract_brushes_node or node == pending_node:
        return false
    var parent = node.get_parent()
    if parent == pending_node:
        return true
    if parent == add_brushes_node or parent == subtract_brushes_node:
        return true
    return parent == csg_node

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
    var query = PhysicsRayQueryParameters3D.new()
    query.from = from
    query.to = to
    query.collide_with_areas = true
    query.collide_with_bodies = true
    var hit = get_world_3d().direct_space_state.intersect_ray(query)
    if hit:
        return hit
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
        var current_shape = int(preview_brush.get_meta("prefab_shape", BrushShape.BOX))
        var needs_replace = current_shape != shape
        if not needs_replace:
            if operation == CSGShape3D.OPERATION_SUBTRACTION:
                preview_brush.operation = CSGShape3D.OPERATION_UNION
                _apply_brush_material(preview_brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
            else:
                preview_brush.operation = operation
                _apply_brush_material(preview_brush, _make_brush_material(operation))
            return
        _clear_preview()
    preview_brush = _create_brush(shape, size_default, operation, sides)
    preview_brush.name = "PreviewBrush"
    preview_brush.use_collision = false
    if operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node:
        preview_brush.operation = CSGShape3D.OPERATION_UNION
        _apply_brush_material(preview_brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
        pending_node.add_child(preview_brush)
    else:
        _add_brush_to_csg(preview_brush, operation)

func _update_preview(origin: Vector3, current: Vector3, height: float, shape: int, size_default: Vector3, lock_axis: int, equal_base: bool, equal_all: bool) -> void:
    if not preview_brush:
        return
    var info = _compute_brush_info(origin, current, height, shape, size_default, lock_axis, equal_base, equal_all)
    preview_brush.global_position = info.center
    if preview_brush is CSGBox3D:
        preview_brush.size = info.size
    elif preview_brush is CSGCylinder3D:
        preview_brush.height = info.size.y
        preview_brush.radius = max(info.size.x, info.size.z) * 0.5
    elif preview_brush is CSGSphere3D:
        var radius = max(info.size.x, info.size.z) * 0.5
        preview_brush.radius = radius
        if bool(preview_brush.get_meta("prefab_ellipsoid", false)):
            preview_brush.scale = Vector3(
                info.size.x / max(0.1, radius * 2.0),
                info.size.y / max(0.1, radius * 2.0),
                info.size.z / max(0.1, radius * 2.0)
            )
        else:
            preview_brush.scale = Vector3.ONE
    else:
        preview_brush.scale = Vector3(
            info.size.x / max(0.1, size_default.x),
            info.size.y / max(0.1, size_default.y),
            info.size.z / max(0.1, size_default.z)
        )

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

func pick_brush(camera: Camera3D, mouse_pos: Vector2) -> Node:
    if not csg_node or not camera:
        return null
    var ray_origin = camera.project_ray_origin(mouse_pos)
    var ray_dir = camera.project_ray_normal(mouse_pos).normalized()
    var closest = null
    var best_t = INF
    for child in _iter_pick_nodes():
        if not (child is CSGShape3D):
            continue
        var inv = child.global_transform.affine_inverse()
        var local_origin = inv * ray_origin
        var local_dir = (inv.basis * ray_dir).normalized()
        var aabb = child.get_aabb()
        var t = _ray_intersect_aabb(local_origin, local_dir, aabb)
        if t >= 0.0 and t < best_t:
            best_t = t
            closest = child
    return closest

func get_live_brush_count() -> int:
    var count = 0
    for node in _iter_pick_nodes():
        if node and node is CSGShape3D:
            count += 1
    return count

func update_hover(camera: Camera3D, mouse_pos: Vector2) -> void:
    if not hover_highlight or not camera:
        return
    var brush = pick_brush(camera, mouse_pos)
    if brush and brush is CSGShape3D:
        var aabb = brush.get_aabb()
        hover_highlight.visible = true
        hover_highlight.global_transform = brush.global_transform
        hover_highlight.scale = aabb.size
    else:
        hover_highlight.visible = false

func clear_hover() -> void:
    if hover_highlight:
        hover_highlight.visible = false

func _iter_pick_nodes() -> Array:
    var nodes: Array = []
    if add_brushes_node:
        nodes.append_array(add_brushes_node.get_children())
    if subtract_brushes_node:
        nodes.append_array(subtract_brushes_node.get_children())
    if csg_node:
        for child in csg_node.get_children():
            if child is CSGShape3D and child != add_brushes_node and child != subtract_brushes_node:
                nodes.append(child)
    if pending_node:
        nodes.append_array(pending_node.get_children())
    return nodes

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
