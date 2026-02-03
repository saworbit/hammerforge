@tool
extends EditorPlugin

class MarqueeControl:
    extends Control
    var rect := Rect2()
    var fill_color := Color(0.3, 0.6, 1.0, 0.15)
    var line_color := Color(0.3, 0.6, 1.0, 0.8)

    func _draw() -> void:
        if rect.size == Vector2.ZERO:
            return
        draw_rect(rect, fill_color, true)
        draw_rect(rect, line_color, false, 1.0)

var dock: Control
var hud: Control
var base_control: Control
var active_root: Node = null
var undo_redo_manager: EditorUndoRedoManager = null
var brush_gizmo_plugin: EditorNode3DGizmoPlugin = null
var hf_selection: Array = []
var select_drag_origin := Vector2.ZERO
var select_drag_active := false
var select_dragging := false
var select_click_pending := false
var select_click_consumed := false
var select_click_time := 0
var select_click_pos := Vector2.ZERO
var select_click_camera: Camera3D = null
var select_additive := false
var select_drag_threshold := 6.0
var marquee: MarqueeControl = null
var marquee_viewport: Viewport = null
const LevelRootType = preload("level_root.gd")

func _enter_tree():
    add_custom_type("LevelRoot", "Node3D", preload("level_root.gd"), preload("icon.png"))
    add_custom_type("DraftEntity", "Node3D", preload("draft_entity.gd"), preload("icon.png"))
    dock = preload("dock.tscn").instantiate()
    undo_redo_manager = get_undo_redo()
    brush_gizmo_plugin = preload("brush_gizmo_plugin.gd").new()
    if brush_gizmo_plugin and brush_gizmo_plugin.has_method("set_undo_redo"):
        brush_gizmo_plugin.call("set_undo_redo", undo_redo_manager)
    if brush_gizmo_plugin:
        add_node_3d_gizmo_plugin(brush_gizmo_plugin)
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
    set_process(true)


func _exit_tree():
    remove_custom_type("LevelRoot")
    remove_custom_type("DraftEntity")
    undo_redo_manager = null
    if brush_gizmo_plugin:
        remove_node_3d_gizmo_plugin(brush_gizmo_plugin)
        brush_gizmo_plugin.free()
        brush_gizmo_plugin = null
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
    if marquee:
        if marquee.get_parent():
            marquee.get_parent().remove_child(marquee)
        marquee.queue_free()
        marquee = null
    marquee_viewport = null
    set_process(false)

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

func _process(delta: float) -> void:
    if not select_click_pending or select_dragging:
        _sync_editor_selection()
        return
    if Time.get_ticks_msec() - select_click_time < 100:
        return
    select_click_pending = false
    select_click_consumed = true
    var root = active_root if active_root else _get_level_root()
    if not root or not select_click_camera:
        return
    var picked = root.pick_brush(select_click_camera, select_click_pos)
    _select_node(picked, select_additive)
    _sync_editor_selection()

func _sync_editor_selection() -> void:
    if hf_selection.is_empty():
        return
    var selection = get_editor_interface().get_selection()
    if not selection:
        return
    var current = selection.get_selected_nodes()
    if current.size() != hf_selection.size():
        _apply_hf_selection(selection)


func _handles(object: Object) -> bool:
    if not object or not (object is Node):
        return false
    return _get_level_root_from_node(object as Node) != null

func _edit(object: Object) -> void:
    if object and object is Node:
        var root = _get_level_root_from_node(object as Node)
        if root:
            active_root = root
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
                var deleted = _delete_selected(root)
                return EditorPlugin.AFTER_GUI_INPUT_STOP if deleted else EditorPlugin.AFTER_GUI_INPUT_PASS
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

    if event is InputEventMouseButton:
        root.set_shift_pressed(event.shift_pressed)
        root.set_alt_pressed(event.alt_pressed)
        if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            root.cancel_drag()
            select_drag_active = false
            select_dragging = false
            select_click_pending = false
            select_click_consumed = false
            if marquee:
                marquee.visible = false
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    if tool == 1:
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                var active_mat = dock.get_active_material() if dock.has_method("get_active_material") else null
                if paint_mode and active_mat:
                    var painted = root.pick_brush(target_camera, target_pos, false)
                    if painted:
                        _paint_brush_with_undo(root, painted, active_mat)
                        return EditorPlugin.AFTER_GUI_INPUT_STOP
                select_drag_origin = target_pos
                select_drag_active = true
                select_dragging = false
                select_click_pending = true
                select_click_consumed = false
                select_click_time = Time.get_ticks_msec()
                select_click_pos = target_pos
                select_click_camera = target_camera
                select_additive = event.shift_pressed or event.ctrl_pressed \
                    or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
                return EditorPlugin.AFTER_GUI_INPUT_STOP
            else:
                if select_drag_active:
                    if select_dragging:
                        _select_nodes_in_rect(root, target_camera, select_drag_origin, target_pos, select_additive)
                    elif select_click_pending and not select_click_consumed:
                        var picked = root.pick_brush(target_camera, target_pos)
                        _select_node(picked, select_additive)
                    if marquee:
                        marquee.visible = false
                select_drag_active = false
                select_dragging = false
                select_click_pending = false
                select_click_consumed = false
                return EditorPlugin.AFTER_GUI_INPUT_STOP
    else:
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
    if event is InputEventMouseMotion:
        root.set_shift_pressed(event.shift_pressed)
        root.set_alt_pressed(event.alt_pressed)
        if tool == 1 and select_drag_active and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
            if not select_dragging and select_drag_origin.distance_to(target_pos) >= select_drag_threshold:
                select_dragging = true
                select_click_pending = false
                select_click_consumed = false
                _ensure_marquee(target_camera)
                if marquee:
                    marquee.visible = true
            if select_dragging:
                _ensure_marquee(target_camera)
                if marquee:
                    marquee.rect = Rect2(select_drag_origin, target_pos - select_drag_origin).abs()
                    marquee.queue_redraw()
            return EditorPlugin.AFTER_GUI_INPUT_STOP
        if tool != 1 and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
            root.update_drag(target_camera, target_pos)
            return EditorPlugin.AFTER_GUI_INPUT_STOP
    return EditorPlugin.AFTER_GUI_INPUT_PASS

func _shortcut_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    if not event.pressed or event.echo:
        return
    if event.keycode == KEY_ESCAPE:
        var selection = get_editor_interface().get_selection()
        if selection:
            selection.clear()
        hf_selection.clear()
        event.accept()
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
    if not selection:
        return
    var toggle = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
    if not additive:
        hf_selection.clear()
        if node:
            hf_selection.append(node)
    else:
        _sync_hf_selection_if_empty()
        if node:
            if toggle and hf_selection.has(node):
                hf_selection.erase(node)
            elif not hf_selection.has(node):
                hf_selection.append(node)
    if not additive and node == null:
        hf_selection.clear()
    _apply_hf_selection(selection)

func _select_nodes_in_rect(root: Node, camera: Camera3D, from: Vector2, to: Vector2, additive: bool) -> void:
    if not root or not camera:
        return
    var rect = Rect2(from, to - from).abs()
    var nodes: Array = []
    if root.has_method("_iter_pick_nodes"):
        nodes = root.call("_iter_pick_nodes")
    var picked: Array = []
    for node in nodes:
        if not (node is Node3D):
            continue
        var include = false
        if root.has_method("is_brush_node") and root.is_brush_node(node):
            include = true
        elif root.has_method("is_entity_node") and root.is_entity_node(node):
            include = true
        if not include:
            continue
        var pos3 = (node as Node3D).global_transform.origin
        var screen_pos = _project_to_screen(camera, pos3)
        if screen_pos == null:
            continue
        if rect.has_point(screen_pos):
            picked.append(node)
    if not additive and picked.is_empty():
        hf_selection.clear()
        var selection = get_editor_interface().get_selection()
        if selection:
            selection.clear()
        return
    _apply_selection_list(picked, additive)

func _apply_selection_list(nodes: Array, additive: bool) -> void:
    var selection = get_editor_interface().get_selection()
    if not selection:
        return
    if not additive:
        hf_selection.clear()
    else:
        _sync_hf_selection_if_empty()
    for node in nodes:
        if node and not hf_selection.has(node):
            hf_selection.append(node)
    _apply_hf_selection(selection)

func _apply_hf_selection(selection: EditorSelection) -> void:
    selection.clear()
    for node in hf_selection:
        if is_instance_valid(node):
            selection.add_node(node)

func _sync_hf_selection_if_empty() -> void:
    if not hf_selection.is_empty():
        return
    var selection = get_editor_interface().get_selection()
    if selection:
        hf_selection = selection.get_selected_nodes()

func _project_to_screen(camera: Camera3D, position: Vector3) -> Variant:
    if camera.has_method("is_position_behind") and camera.is_position_behind(position):
        return null
    if camera.has_method("unproject_position"):
        return camera.unproject_position(position)
    return null

func _selection_has_brush(nodes: Array, root: Node) -> bool:
    if not root or not root.has_method("is_brush_node"):
        return false
    for node in nodes:
        if root.is_brush_node(node):
            return true
    return false

func _selection_has_entity(nodes: Array, root: Node) -> bool:
    if not root or not root.has_method("is_entity_node"):
        return false
    for node in nodes:
        if root.is_entity_node(node):
            return true
    return false

func _current_selection_nodes() -> Array:
    if not hf_selection.is_empty():
        return hf_selection.duplicate()
    var selection = get_editor_interface().get_selection()
    if selection:
        return selection.get_selected_nodes()
    return []

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

func _delete_selected(root: Node) -> bool:
    var selection = get_editor_interface().get_selection()
    var nodes = _current_selection_nodes()
    var deletable: Array = []
    for node in nodes:
        if root.has_method("is_brush_node") and root.is_brush_node(node):
            deletable.append(node)
    if deletable.is_empty():
        return false
    selection.clear()
    hf_selection.clear()
    var undo_redo = _get_undo_redo()
    if not undo_redo:
        for node in deletable:
            root.delete_brush(node)
        return true
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
    return true

func _duplicate_selected(root: Node) -> void:
    var selection = get_editor_interface().get_selection()
    var nodes = _current_selection_nodes()
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
        hf_selection.clear()
        for info in infos:
            var dup = root.create_brush_from_info(info)
            if dup:
                selection.add_node(dup)
                hf_selection.append(dup)
        return
    undo_redo.create_action("Duplicate Brushes")
    for info in infos:
        undo_redo.add_do_method(root, "create_brush_from_info", info)
        undo_redo.add_undo_method(root, "delete_brush_by_id", info.get("brush_id", ""))
    undo_redo.commit_action()
    _record_history("Duplicate Brushes")
    selection.clear()
    hf_selection.clear()
    if root.has_method("find_brush_by_id"):
        for info in infos:
            var dup = root.find_brush_by_id(info.get("brush_id", ""))
            if dup:
                selection.add_node(dup)
                hf_selection.append(dup)

func _nudge_selected(root: Node, dir: Vector3) -> void:
    var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
    var selection = get_editor_interface().get_selection()
    var nodes = _current_selection_nodes()
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

func _get_level_root_from_node(node: Node) -> Node:
    var current: Node = node
    while current:
        if current.get_script() == LevelRootType or current.name == "LevelRoot":
            return current
        current = current.get_parent()
    return null

func _ensure_marquee(camera: Camera3D) -> void:
    if not camera:
        return
    var vp = camera.get_viewport()
    if not vp:
        return
    if not marquee:
        marquee = MarqueeControl.new()
        marquee.name = "HFMarquee"
        marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
        marquee.anchor_left = 0.0
        marquee.anchor_top = 0.0
        marquee.anchor_right = 1.0
        marquee.anchor_bottom = 1.0
        marquee.offset_left = 0.0
        marquee.offset_top = 0.0
        marquee.offset_right = 0.0
        marquee.offset_bottom = 0.0
        marquee.visible = false
        marquee.z_index = 4096
    if marquee_viewport != vp:
        if marquee.get_parent():
            marquee.get_parent().remove_child(marquee)
        vp.add_child(marquee)
        marquee_viewport = vp
    # Anchors drive size; no manual resize needed.

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
    hf_selection.clear()
    hf_selection.append(root)
    return root
