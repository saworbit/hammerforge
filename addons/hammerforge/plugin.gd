@tool
extends EditorPlugin

var dock: Control
var active_root: Node = null
const LevelRootType = preload("level_root.gd")

func _enter_tree():
    add_custom_type("LevelRoot", "Node3D", preload("level_root.gd"), preload("icon.png"))
    dock = preload("dock.tscn").instantiate()
    add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
    if dock and dock.has_method("set_editor_interface"):
        dock.call("set_editor_interface", get_editor_interface())

func _exit_tree():
    remove_custom_type("LevelRoot")
    if dock:
        remove_control_from_docks(dock)
        dock.free()

func _handles(object: Object) -> bool:
    if not object:
        return false
    if object is Node and object.get_script() == LevelRootType:
        return true
    return object is Node and object.name == "LevelRoot"

func _edit(object: Object) -> void:
    if object and object is Node:
        if object.get_script() == LevelRootType or object.name == "LevelRoot":
            active_root = object
            return
    active_root = null

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
    var root = active_root if active_root else _get_level_root()
    if not root:
        root = _create_level_root()
    if not root or not dock:
        return EditorPlugin.AFTER_GUI_INPUT_PASS
    var tool = dock.get_tool()
    var op = dock.get_operation()
    var size = dock.get_brush_size()
    var shape = dock.get_shape()
    var grid = dock.get_grid_snap()
    root.grid_snap = grid

    if event is InputEventKey:
        if event.pressed and not event.echo:
            if event.keycode == KEY_DELETE:
                _delete_selected(root)
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.ctrl_pressed and event.keycode == KEY_D:
                _duplicate_selected(root)
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_UP:
                _nudge_selected(root, Vector3(0.0, 0.0, -1.0))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_DOWN:
                _nudge_selected(root, Vector3(0.0, 0.0, 1.0))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_LEFT:
                _nudge_selected(root, Vector3(-1.0, 0.0, 0.0))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_RIGHT:
                _nudge_selected(root, Vector3(1.0, 0.0, 0.0))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_PAGEUP:
                _nudge_selected(root, Vector3(0.0, 1.0, 0.0))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_PAGEDOWN:
                _nudge_selected(root, Vector3(0.0, -1.0, 0.0))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_X:
                root.set_axis_lock(LevelRootType.AxisLock.X, true)
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_Y:
                root.set_axis_lock(LevelRootType.AxisLock.Y, true)
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            if event.keycode == KEY_Z:
                root.set_axis_lock(LevelRootType.AxisLock.Z, true)
                return EditorPlugin.AFTER_GUI_INPUT_STOP

    if event is InputEventMouseButton:
        root.set_shift_pressed(event.shift_pressed)
        root.set_alt_pressed(event.alt_pressed)
        if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            root.cancel_drag()
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    if tool == 1 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var picked = root.pick_brush(camera, event.position)
        _select_node(picked, event.shift_pressed)
        return EditorPlugin.AFTER_GUI_INPUT_STOP
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            var started = root.begin_drag(camera, event.position, op, size, shape)
            return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
        else:
            var finished = root.end_drag(camera, event.position, size)
            return EditorPlugin.AFTER_GUI_INPUT_STOP if finished else EditorPlugin.AFTER_GUI_INPUT_PASS
    elif event is InputEventMouseMotion:
        root.set_shift_pressed(event.shift_pressed)
        root.set_alt_pressed(event.alt_pressed)
        if event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
            root.update_drag(camera, event.position)
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    return EditorPlugin.AFTER_GUI_INPUT_PASS

func _select_node(node: Node, additive: bool = false) -> void:
    var selection = get_editor_interface().get_selection()
    if not additive:
        selection.clear()
    if node:
        selection.add_node(node)

func _delete_selected(root: Node) -> void:
    var selection = get_editor_interface().get_selection()
    var nodes = selection.get_selected_nodes()
    for node in nodes:
        if node and node.get_parent() and node.get_parent().name == "BrushCSG":
            root.delete_brush(node)

func _duplicate_selected(root: Node) -> void:
    var selection = get_editor_interface().get_selection()
    var nodes = selection.get_selected_nodes()
    selection.clear()
    for node in nodes:
        if node and node.get_parent() and node.get_parent().name == "BrushCSG":
            var dup = root.duplicate_brush(node)
            if dup:
                selection.add_node(dup)

func _nudge_selected(root: Node, dir: Vector3) -> void:
    var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
    var selection = get_editor_interface().get_selection()
    var nodes = selection.get_selected_nodes()
    for node in nodes:
        if node and node is Node3D:
            node.global_position += dir * step


func _get_level_root() -> Node:
    var scene = get_editor_interface().get_edited_scene_root()
    if scene:
        if scene.get_script() == LevelRootType or scene.name == "LevelRoot":
            return scene
        var node = scene.get_node_or_null("LevelRoot")
        if node:
            return node
    var current = get_tree().get_current_scene()
    if current:
        return current.get_node_or_null("LevelRoot")
    return null

func _create_level_root() -> Node:
    var scene = get_editor_interface().get_edited_scene_root()
    if not scene:
        return null
    var root = LevelRootType.new()
    root.name = "LevelRoot"
    scene.add_child(root)
    root.owner = scene
    active_root = root
    var selection = get_editor_interface().get_selection()
    selection.clear()
    selection.add_node(root)
    return root
