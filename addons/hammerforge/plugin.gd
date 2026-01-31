@tool
extends EditorPlugin

var dock: Control
var hud: Control
var base_control: Control
var active_root: Node = null
var undo_redo_manager: EditorUndoRedoManager = null
const LevelRootType = preload("level_root.gd")

func _enter_tree():
    add_custom_type("LevelRoot", "Node3D", preload("level_root.gd"), preload("icon.png"))
    dock = preload("dock.tscn").instantiate()
    undo_redo_manager = get_undo_redo()
    base_control = get_editor_interface().get_base_control()
    if base_control:
        dock.theme = base_control.theme
        if dock.has_method("apply_editor_styles"):
            dock.call("apply_editor_styles", base_control)
        if not base_control.is_connected("theme_changed", Callable(self, "_on_editor_theme_changed")):
            base_control.connect("theme_changed", Callable(self, "_on_editor_theme_changed"))
    add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
    if dock and dock.has_method("set_editor_interface"):
        dock.call("set_editor_interface", get_editor_interface())
    if dock and dock.has_method("set_undo_redo"):
        dock.call("set_undo_redo", undo_redo_manager)
    if dock and dock.has_signal("hud_visibility_changed"):
        dock.connect("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed"))

    hud = preload("shortcut_hud.tscn").instantiate()
    if base_control:
        hud.theme = base_control.theme
    add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
    if dock and dock.has_method("get_show_hud"):
        hud.visible = dock.call("get_show_hud")


func _exit_tree():
    remove_custom_type("LevelRoot")
    undo_redo_manager = null
    if base_control and base_control.is_connected("theme_changed", Callable(self, "_on_editor_theme_changed")):
        base_control.disconnect("theme_changed", Callable(self, "_on_editor_theme_changed"))
    if dock:
        if dock.is_connected("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed")):
            dock.disconnect("hud_visibility_changed", Callable(self, "_on_hud_visibility_changed"))
        remove_control_from_docks(dock)
        dock.free()
    if hud:
        remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)
        hud.free()

func _on_editor_theme_changed() -> void:
    if not base_control:
        return
    if dock:
        dock.theme = base_control.theme
        if dock.has_method("apply_editor_styles"):
            dock.call("apply_editor_styles", base_control)
    if hud:
        hud.theme = base_control.theme

func _on_hud_visibility_changed(visible: bool) -> void:
    if hud:
        hud.visible = visible


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

    var target_camera = camera
    var target_pos = event.position if event is InputEventMouse else Vector2.ZERO

    if root.has_method("update_editor_grid"):
        if event is InputEventMouseMotion or event is InputEventMouseButton:
            root.call("update_editor_grid", target_camera, target_pos)

    var tool = dock.get_tool()
    var op = dock.get_operation()
    var size = dock.get_brush_size()
    var shape = dock.get_shape()
    var sides = dock.get_sides() if dock.has_method("get_sides") else 4
    var grid = dock.get_grid_snap()
    root.grid_snap = grid
    var paint_mode = dock.has_method("is_paint_mode_enabled") and dock.is_paint_mode_enabled()

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

    if tool == 1 and event is InputEventMouseMotion:
        if root.has_method("update_hover"):
            root.call("update_hover", target_camera, target_pos)
    elif tool != 1 and root.has_method("clear_hover"):
        root.call("clear_hover")

    var selection = get_editor_interface().get_selection()
    var selected_nodes: Array = []
    if selection:
        selected_nodes = selection.get_selected_nodes()
    if tool == 1 and not paint_mode and _selection_has_brush(selected_nodes, root):
        if event is InputEventMouseButton or event is InputEventMouseMotion:
            return EditorPlugin.AFTER_GUI_INPUT_PASS

    if event is InputEventMouseButton:
        root.set_shift_pressed(event.shift_pressed)
        root.set_alt_pressed(event.alt_pressed)
        if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            root.cancel_drag()
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    if tool == 1 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var active_mat = dock.get_active_material() if dock.has_method("get_active_material") else null
        if paint_mode and active_mat:
            var painted = root.pick_brush(target_camera, target_pos)
            if painted:
                _paint_brush_with_undo(root, painted, active_mat)
                return EditorPlugin.AFTER_GUI_INPUT_STOP
        var picked = root.pick_brush(target_camera, target_pos)
        _select_node(picked, event.shift_pressed)
        return EditorPlugin.AFTER_GUI_INPUT_STOP
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            var started = root.begin_drag(target_camera, target_pos, op, size, shape, sides)
            return EditorPlugin.AFTER_GUI_INPUT_STOP if started else EditorPlugin.AFTER_GUI_INPUT_PASS
        else:
            var result = root.end_drag_info(target_camera, target_pos, size)
            if result.get("handled", false):
                if result.get("placed", false):
                    _commit_brush_placement(root, result.get("info", {}))
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            return EditorPlugin.AFTER_GUI_INPUT_PASS
    elif event is InputEventMouseMotion:
        root.set_shift_pressed(event.shift_pressed)
        root.set_alt_pressed(event.alt_pressed)
        if event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
            root.update_drag(target_camera, target_pos)
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    return EditorPlugin.AFTER_GUI_INPUT_PASS

func _shortcut_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    if not event.pressed or event.echo:
        return
    if not event.ctrl_pressed:
        return
    var root = active_root if active_root else _get_level_root()
    if not root:
        return
    match event.keycode:
        KEY_UP:
            _nudge_selected(root, Vector3(0.0, 0.0, -1.0))
            event.accept()
        KEY_DOWN:
            _nudge_selected(root, Vector3(0.0, 0.0, 1.0))
            event.accept()
        KEY_LEFT:
            _nudge_selected(root, Vector3(-1.0, 0.0, 0.0))
            event.accept()
        KEY_RIGHT:
            _nudge_selected(root, Vector3(1.0, 0.0, 0.0))
            event.accept()
        KEY_PAGEUP:
            _nudge_selected(root, Vector3(0.0, 1.0, 0.0))
            event.accept()
        KEY_PAGEDOWN:
            _nudge_selected(root, Vector3(0.0, -1.0, 0.0))
            event.accept()

func _select_node(node: Node, additive: bool = false) -> void:
    var selection = get_editor_interface().get_selection()
    if not additive:
        selection.clear()
    if node:
        selection.add_node(node)

func _selection_has_brush(nodes: Array, root: Node) -> bool:
    if not root or not root.has_method("is_brush_node"):
        return false
    for node in nodes:
        if root.is_brush_node(node):
            return true
    return false

func _get_undo_redo() -> EditorUndoRedoManager:
    return undo_redo_manager if undo_redo_manager else get_undo_redo()

func _record_history(action_name: String) -> void:
    if dock and dock.has_method("record_history"):
        dock.call("record_history", action_name)

func _paint_brush_with_undo(root: Node, brush: Node, mat: Material) -> void:
    if not root or not brush:
        return
    var undo_redo = _get_undo_redo()
    if not undo_redo:
        root.apply_material_to_brush(brush, mat)
        return
    var prev = brush.get("material_override") if brush.get("material_override") else brush.get("material")
    if prev == mat:
        return
    undo_redo.create_action("Paint Brush")
    undo_redo.add_do_method(root, "apply_material_to_brush", brush, mat)
    undo_redo.add_undo_method(root, "apply_material_to_brush", brush, prev)
    undo_redo.commit_action()
    _record_history("Paint Brush")

func _commit_brush_placement(root: Node, info: Dictionary) -> void:
    if info.is_empty():
        return
    var undo_redo = _get_undo_redo()
    if not undo_redo:
        root.create_brush_from_info(info)
        return
    undo_redo.create_action("Place Brush")
    undo_redo.add_do_method(root, "create_brush_from_info", info)
    undo_redo.add_undo_method(root, "delete_brush_by_id", info.get("brush_id", ""))
    undo_redo.commit_action()
    _record_history("Place Brush")

func _delete_selected(root: Node) -> void:
    var selection = get_editor_interface().get_selection()
    var nodes = selection.get_selected_nodes()
    var deletable: Array = []
    for node in nodes:
        if root.has_method("is_brush_node") and root.is_brush_node(node):
            deletable.append(node)
    if deletable.is_empty():
        return
    selection.clear()
    var undo_redo = _get_undo_redo()
    if not undo_redo:
        for node in deletable:
            root.delete_brush(node)
        return
    undo_redo.create_action("Delete Brushes")
    for node in deletable:
        var parent = node.get_parent()
        var owner = node.owner
        var index = -1
        if parent:
            index = parent.get_children().find(node)
        undo_redo.add_do_method(root, "delete_brush", node, false)
        undo_redo.add_undo_method(root, "restore_brush", node, parent, owner, index)
    undo_redo.commit_action()
    _record_history("Delete Brushes")

func _duplicate_selected(root: Node) -> void:
    var selection = get_editor_interface().get_selection()
    var nodes = selection.get_selected_nodes()
    var infos: Array = []
    var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
    for node in nodes:
        if root.has_method("is_brush_node") and root.is_brush_node(node):
            var info = root.build_duplicate_info(node, Vector3(step, 0.0, 0.0))
            if not info.is_empty():
                infos.append(info)
    if infos.is_empty():
        return
    var undo_redo = _get_undo_redo()
    if not undo_redo:
        selection.clear()
        for info in infos:
            var dup = root.create_brush_from_info(info)
            if dup:
                selection.add_node(dup)
        return
    undo_redo.create_action("Duplicate Brushes")
    for info in infos:
        undo_redo.add_do_method(root, "create_brush_from_info", info)
        undo_redo.add_undo_method(root, "delete_brush_by_id", info.get("brush_id", ""))
    undo_redo.commit_action()
    _record_history("Duplicate Brushes")
    selection.clear()
    if root.has_method("find_brush_by_id"):
        for info in infos:
            var dup = root.find_brush_by_id(info.get("brush_id", ""))
            if dup:
                selection.add_node(dup)

func _nudge_selected(root: Node, dir: Vector3) -> void:
    var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
    var selection = get_editor_interface().get_selection()
    var nodes = selection.get_selected_nodes()
    var targets: Array = []
    for node in nodes:
        if node and node is Node3D and root.has_method("is_brush_node") and root.is_brush_node(node):
            targets.append(node)
    if targets.is_empty():
        return
    var offset = dir * step
    var undo_redo = _get_undo_redo()
    if not undo_redo:
        for node in targets:
            node.global_position += offset
        return
    undo_redo.create_action("Nudge Brushes")
    for node in targets:
        var start_pos = node.global_position
        undo_redo.add_do_property(node, "global_position", start_pos + offset)
        undo_redo.add_undo_property(node, "global_position", start_pos)
    undo_redo.commit_action()
    _record_history("Nudge Brushes")


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
