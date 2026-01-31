@tool
extends EditorNode3DGizmoPlugin

const DraftBrush = preload("brush_instance.gd")
const MIN_SIZE := 0.1

var undo_redo: EditorUndoRedoManager = null

const HANDLE_DATA = [
    {"axis": Vector3(1, 0, 0), "dir": 1},
    {"axis": Vector3(1, 0, 0), "dir": -1},
    {"axis": Vector3(0, 1, 0), "dir": 1},
    {"axis": Vector3(0, 1, 0), "dir": -1},
    {"axis": Vector3(0, 0, 1), "dir": 1},
    {"axis": Vector3(0, 0, 1), "dir": -1}
]

func _init() -> void:
    create_handle_material("handles")
    create_material("main", Color(1, 1, 0, 0.1))

func set_undo_redo(manager: EditorUndoRedoManager) -> void:
    undo_redo = manager

func _get_gizmo_name() -> String:
    return "HammerForgeBrush"

func _has_gizmo(node: Node) -> bool:
    return node is DraftBrush

func _redraw(gizmo: EditorNode3DGizmo) -> void:
    gizmo.clear()
    var brush = gizmo.get_node_3d() as DraftBrush
    if not brush:
        return
    var size = brush.size
    var half = size * 0.5
    var corners = [
        Vector3(-half.x, -half.y, -half.z),
        Vector3(half.x, -half.y, -half.z),
        Vector3(half.x, half.y, -half.z),
        Vector3(-half.x, half.y, -half.z),
        Vector3(-half.x, -half.y, half.z),
        Vector3(half.x, -half.y, half.z),
        Vector3(half.x, half.y, half.z),
        Vector3(-half.x, half.y, half.z)
    ]
    var lines = PackedVector3Array([
        corners[0], corners[1],
        corners[1], corners[2],
        corners[2], corners[3],
        corners[3], corners[0],
        corners[4], corners[5],
        corners[5], corners[6],
        corners[6], corners[7],
        corners[7], corners[4],
        corners[0], corners[4],
        corners[1], corners[5],
        corners[2], corners[6],
        corners[3], corners[7]
    ])
    gizmo.add_lines(lines, get_material("main", gizmo))

    var handles = PackedVector3Array([
        Vector3(half.x, 0, 0),
        Vector3(-half.x, 0, 0),
        Vector3(0, half.y, 0),
        Vector3(0, -half.y, 0),
        Vector3(0, 0, half.z),
        Vector3(0, 0, -half.z)
    ])
    var ids = PackedInt32Array([0, 1, 2, 3, 4, 5])
    gizmo.add_handles(handles, get_material("handles", gizmo), ids)

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
    match handle_id:
        0:
            return "+X"
        1:
            return "-X"
        2:
            return "+Y"
        3:
            return "-Y"
        4:
            return "+Z"
        5:
            return "-Z"
        _:
            return ""

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
    var brush = gizmo.get_node_3d() as DraftBrush
    if not brush:
        return {}
    return {
        "size": brush.size,
        "position": brush.global_position
    }

func _set_handle(
    gizmo: EditorNode3DGizmo,
    handle_id: int,
    secondary: bool,
    camera: Camera3D,
    screen_pos: Vector2
) -> void:
    var brush = gizmo.get_node_3d() as DraftBrush
    if not brush or handle_id < 0 or handle_id >= HANDLE_DATA.size():
        return
    var handle_info = HANDLE_DATA[handle_id]
    var axis: Vector3 = handle_info["axis"]
    var dir: int = handle_info["dir"]
    var axis_index = _axis_index(axis)
    var axis_world = (brush.global_transform.basis * axis).normalized()
    if axis_world.length() <= 0.001:
        return
    var half_size = brush.size[axis_index] * 0.5
    var opposite_face = brush.global_position - axis_world * float(dir) * half_size

    var ray_origin = camera.project_ray_origin(screen_pos)
    var ray_dir = camera.project_ray_normal(screen_pos).normalized()
    var line_dir = axis_world * float(dir)

    var w0 = opposite_face - ray_origin
    var b = line_dir.dot(ray_dir)
    var denom = 1.0 - b * b
    if abs(denom) < 0.00001:
        return
    var d = line_dir.dot(w0)
    var e = ray_dir.dot(w0)
    var t = (b * e - d) / denom
    var new_size_axis = max(MIN_SIZE, t)
    var new_center = opposite_face + line_dir * (new_size_axis * 0.5)

    var new_size = brush.size
    new_size[axis_index] = new_size_axis
    brush.size = new_size
    brush.global_position = new_center
    gizmo.redraw()

func _commit_handle(
    gizmo: EditorNode3DGizmo,
    handle_id: int,
    secondary: bool,
    restore: Variant,
    cancel: bool
) -> void:
    var brush = gizmo.get_node_3d() as DraftBrush
    if not brush:
        return
    if cancel:
        if restore is Dictionary:
            var data: Dictionary = restore
            if data.has("size"):
                brush.size = data["size"]
            if data.has("position"):
                brush.global_position = data["position"]
        gizmo.redraw()
        return
    if not (restore is Dictionary):
        return
    var data: Dictionary = restore
    var prev_size = data.get("size", brush.size)
    var prev_pos = data.get("position", brush.global_position)
    var next_size = brush.size
    var next_pos = brush.global_position

    if undo_redo:
        undo_redo.create_action("Resize Brush")
        undo_redo.add_do_property(brush, "size", next_size)
        undo_redo.add_do_property(brush, "global_position", next_pos)
        undo_redo.add_undo_property(brush, "size", prev_size)
        undo_redo.add_undo_property(brush, "global_position", prev_pos)
        undo_redo.commit_action()
    else:
        brush.size = next_size
        brush.global_position = next_pos
    gizmo.redraw()

func _axis_index(axis: Vector3) -> int:
    if abs(axis.x) > 0.0:
        return 0
    if abs(axis.y) > 0.0:
        return 1
    return 2
