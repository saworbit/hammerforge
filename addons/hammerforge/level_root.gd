@tool
extends Node3D
class_name LevelRoot

const BrushManager = preload("brush_manager.gd")
const Baker = preload("baker.gd")

enum BrushShape { BOX, CYLINDER }
enum AxisLock { NONE, X, Y, Z }

@export var grid_snap: float = 16.0
@export var brush_size_default: Vector3 = Vector3(32, 32, 32)

var csg_node: CSGCombiner3D
var pending_node: CSGCombiner3D
var brush_manager: BrushManager
var baker: Baker
var baked_container: Node3D
var preview_brush: CSGShape3D = null
var drag_active := false
var drag_origin := Vector3.ZERO
var drag_end := Vector3.ZERO
var drag_operation := CSGShape3D.OPERATION_UNION
var drag_shape := BrushShape.BOX
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

func _ready():
    _setup_csg()
    _setup_pending()
    _setup_manager()
    _setup_baker()

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

func _setup_pending() -> void:
    pending_node = get_node_or_null("PendingCuts") as CSGCombiner3D
    if not pending_node:
        pending_node = CSGCombiner3D.new()
        pending_node.name = "PendingCuts"
        pending_node.use_collision = false
        add_child(pending_node)
        _assign_owner(pending_node)

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

func place_brush(mouse_pos: Vector2, operation: int, size: Vector3, camera: Camera3D = null, shape: int = BrushShape.BOX) -> bool:
    if not csg_node:
        return false

    var active_camera = camera if camera else get_viewport().get_camera_3d()
    if not active_camera:
        return false

    var hit = _raycast(active_camera, mouse_pos)
    if not hit:
        return false

    var snapped = _snap_point(hit.position)
    var brush = _create_brush(shape, size, operation)
    brush.global_position = snapped + Vector3(0, size.y * 0.5, 0)
    if operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node:
        _add_pending_cut(brush)
    else:
        csg_node.add_child(brush)
        _assign_owner(brush)
    brush_manager.add_brush(brush)
    return true

func bake() -> void:
    if not baker or not csg_node:
        return
    apply_pending_cuts()
    var baked = baker.bake_from_csg(csg_node)
    if not baked:
        return
    if baked_container:
        baked_container.queue_free()
    baked_container = baked
    add_child(baked_container)
    _assign_owner(baked_container)

func clear_brushes() -> void:
    if brush_manager:
        brush_manager.clear_brushes()
    for child in csg_node.get_children():
        if child is CSGShape3D:
            child.queue_free()
    _clear_preview()
    clear_pending_cuts()

func apply_pending_cuts() -> void:
    if not pending_node or not csg_node:
        return
    for child in pending_node.get_children():
        if child is CSGShape3D:
            pending_node.remove_child(child)
            csg_node.add_child(child)
            child.operation = CSGShape3D.OPERATION_SUBTRACTION
            child.use_collision = true
            _apply_brush_material(child, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
            child.set_meta("pending_subtract", false)
            _assign_owner(child)

func commit_cuts() -> void:
    apply_pending_cuts()
    bake()
    _clear_applied_cuts()

func _clear_applied_cuts() -> void:
    if not csg_node:
        return
    for child in csg_node.get_children():
        if child is CSGShape3D and child.operation == CSGShape3D.OPERATION_SUBTRACTION:
            if brush_manager:
                brush_manager.remove_brush(child)
            child.queue_free()

func clear_pending_cuts() -> void:
    if not pending_node:
        return
    for child in pending_node.get_children():
        if child is CSGShape3D:
            child.queue_free()

func delete_brush(brush: Node) -> void:
    if not brush or not brush.is_inside_tree():
        return
    if brush_manager:
        brush_manager.remove_brush(brush)
    brush.queue_free()

func duplicate_brush(brush: Node) -> Node:
    if not brush:
        return null
    var dup: CSGShape3D = null
    if brush is CSGBox3D:
        var box = CSGBox3D.new()
        box.size = brush.size
        dup = box
    elif brush is CSGCylinder3D:
        var cyl = CSGCylinder3D.new()
        cyl.height = brush.height
        cyl.radius = brush.radius
        cyl.sides = brush.sides
        dup = cyl
    if not dup:
        return null
    dup.operation = brush.operation
    dup.use_collision = true
    var source_mat = brush.material_override if brush.material_override else brush.get("material")
    _apply_brush_material(dup, source_mat)
    dup.global_transform = brush.global_transform
    dup.global_position += Vector3(grid_snap if grid_snap > 0.0 else 1.0, 0.0, 0.0)
    var parent = csg_node
    if pending_node and brush.get_parent() == pending_node:
        parent = pending_node
        _add_pending_cut(dup)
        brush_manager.add_brush(dup)
        return dup
    parent.add_child(dup)
    _assign_owner(dup)
    brush_manager.add_brush(dup)
    return dup

func _create_brush(shape: int, size: Vector3, operation: int) -> CSGShape3D:
    var brush: CSGShape3D
    if shape == BrushShape.CYLINDER:
        var cylinder = CSGCylinder3D.new()
        cylinder.height = size.y
        cylinder.radius = max(size.x, size.z) * 0.5
        cylinder.sides = 16
        brush = cylinder
    else:
        var box = CSGBox3D.new()
        box.size = size
        brush = box
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

func _add_pending_cut(brush: CSGShape3D) -> void:
    if not pending_node:
        return
    brush.operation = CSGShape3D.OPERATION_UNION
    _apply_brush_material(brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
    brush.set_meta("pending_subtract", true)
    pending_node.add_child(brush)
    _assign_owner(brush)

func begin_drag(camera: Camera3D, mouse_pos: Vector2, operation: int, size: Vector3, shape: int) -> bool:
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
    drag_height = grid_snap if grid_snap > 0.0 else size.y
    drag_size_default = size
    drag_stage = 1
    if not manual_axis_lock:
        axis_lock = AxisLock.NONE
    lock_axis_active = AxisLock.NONE
    locked_thickness = Vector3.ZERO
    height_stage_start_mouse = mouse_pos
    height_stage_start_height = drag_height
    _ensure_preview(shape, operation)
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

func end_drag(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> bool:
    if not drag_active:
        return false
    if drag_stage == 1:
        drag_stage = 2
        height_stage_start_mouse = mouse_pos
        height_stage_start_height = drag_height
        return true
    drag_active = false
    drag_stage = 0
    lock_axis_active = AxisLock.NONE
    var info = _compute_brush_info(drag_origin, drag_end, drag_height, drag_shape, size_default, _current_axis_lock(), shift_pressed and not alt_pressed, shift_pressed and alt_pressed)
    var brush = _create_brush(drag_shape, info.size, drag_operation)
    brush.global_position = info.center
    if drag_operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node:
        _add_pending_cut(brush)
    else:
        csg_node.add_child(brush)
        _assign_owner(brush)
    brush_manager.add_brush(brush)
    _clear_preview()
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
            return
        axis_lock = lock
        manual_axis_lock = true
        return
    axis_lock = lock

func set_shift_pressed(pressed: bool) -> void:
    shift_pressed = pressed
    if not pressed and not manual_axis_lock:
        axis_lock = AxisLock.NONE

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

func _ensure_preview(shape: int, operation: int) -> void:
    if preview_brush:
        var needs_replace = (shape == BrushShape.CYLINDER and not (preview_brush is CSGCylinder3D)) \
            or (shape == BrushShape.BOX and not (preview_brush is CSGBox3D))
        if not needs_replace:
            if operation == CSGShape3D.OPERATION_SUBTRACTION:
                preview_brush.operation = CSGShape3D.OPERATION_UNION
                _apply_brush_material(preview_brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
            else:
                preview_brush.operation = operation
                _apply_brush_material(preview_brush, _make_brush_material(operation))
            return
        _clear_preview()
    preview_brush = _create_brush(shape, Vector3(1, 1, 1), operation)
    preview_brush.name = "PreviewBrush"
    preview_brush.use_collision = false
    if operation == CSGShape3D.OPERATION_SUBTRACTION and pending_node:
        preview_brush.operation = CSGShape3D.OPERATION_UNION
        _apply_brush_material(preview_brush, _make_brush_material(CSGShape3D.OPERATION_SUBTRACTION, true, true))
        pending_node.add_child(preview_brush)
    else:
        csg_node.add_child(preview_brush)

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

func _iter_pick_nodes() -> Array:
    var nodes: Array = []
    if csg_node:
        nodes.append_array(csg_node.get_children())
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
