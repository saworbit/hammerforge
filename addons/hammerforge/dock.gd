@tool
extends Control
class_name HammerForgeDock

signal hud_visibility_changed(visible: bool)

const LevelRootType = preload("level_root.gd")
const BrushPreset = preload("brush_preset.gd")

const PRESET_MENU_RENAME := 0
const PRESET_MENU_DELETE := 1

@onready var settings_panel: PanelContainer = $Margin/VBox/SettingsPanel
@onready var presets_panel: PanelContainer = $Margin/VBox/PresetsPanel
@onready var actions_panel: PanelContainer = $Margin/VBox/ActionsPanel

@onready var tool_draw: Button = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ToolRow/ToolDraw
@onready var tool_select: Button = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ToolRow/ToolSelect
@onready var mode_add: Button = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ModeRow/ModeAdd
@onready var mode_subtract: Button = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ModeRow/ModeSubtract
@onready var shape_box: Button = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ShapeRow/ShapeBox
@onready var shape_cylinder: Button = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ShapeRow/ShapeCylinder
@onready var size_x: SpinBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/SizeRow/SizeX
@onready var size_y: SpinBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/SizeRow/SizeY
@onready var size_z: SpinBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/SizeRow/SizeZ
@onready var grid_snap: SpinBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/GridRow/GridSnap
@onready var bake_layer: SpinBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/BakeLayerRow/BakeLayer
@onready var commit_freeze: CheckBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/CommitFreeze
@onready var show_hud: CheckBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ShowHUD
@onready var show_grid: CheckBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/ShowGrid
@onready var follow_grid: CheckBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/FollowGrid
@onready var debug_logs: CheckBox = $Margin/VBox/SettingsPanel/SettingsMargin/SettingsVBox/DebugLogs
@onready var floor_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/CreateFloor
@onready var apply_cuts_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/ApplyCuts
@onready var clear_cuts_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/ClearCuts
@onready var commit_cuts_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/CommitCuts
@onready var restore_cuts_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/RestoreCuts
@onready var bake_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/Bake
@onready var clear_btn: Button = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/Clear
@onready var status_label: Label = $Margin/VBox/ActionsPanel/ActionsMargin/ActionsVBox/Status
@onready var quick_play_btn: Button = $Margin/VBox/QuickPlay

@onready var save_preset_btn: Button = $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/SavePreset
@onready var preset_grid: GridContainer = $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/PresetGrid
@onready var preset_menu: PopupMenu = $PresetMenu
@onready var preset_rename_dialog: AcceptDialog = $PresetRenameDialog
@onready var preset_rename_line: LineEdit = $PresetRenameDialog/PresetRenameLine

@onready var snap_buttons: Array[Button] = [
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap1,
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap2,
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap4,
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap8,
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap16,
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap32,
    $Margin/VBox/PresetsPanel/PresetsMargin/PresetsVBox/QuickSnapRow/Snap64
]

var level_root: Node = null
var editor_interface: EditorInterface = null
var connected_root: Node = null
var snap_button_group: ButtonGroup
var syncing_snap := false
var debug_enabled := false
var syncing_grid := false
var presets_dir := "res://addons/hammerforge/presets"
var preset_buttons: Array[Button] = []
var preset_context_button: Button = null

func set_editor_interface(iface: EditorInterface) -> void:
    editor_interface = iface

func apply_editor_styles(base_control: Control) -> void:
    if not base_control:
        return
    if not settings_panel:
        settings_panel = get_node_or_null("Margin/VBox/SettingsPanel")
    if not presets_panel:
        presets_panel = get_node_or_null("Margin/VBox/PresetsPanel")
    if not actions_panel:
        actions_panel = get_node_or_null("Margin/VBox/ActionsPanel")
    var panel_style = _resolve_stylebox(base_control, "panel", "PanelContainer")
    var inspector_style = _resolve_stylebox(base_control, "panel", "EditorInspector")
    var group_style = _resolve_stylebox(base_control, "panel", "Group")
    if inspector_style:
        add_theme_stylebox_override("panel", inspector_style)
    elif panel_style:
        add_theme_stylebox_override("panel", panel_style)
    if group_style or panel_style:
        var section_style = group_style if group_style else panel_style
        if settings_panel:
            settings_panel.add_theme_stylebox_override("panel", section_style)
        if presets_panel:
            presets_panel.add_theme_stylebox_override("panel", section_style)
        if actions_panel:
            actions_panel.add_theme_stylebox_override("panel", section_style)

func _resolve_stylebox(base_control: Control, name: String, type_name: String) -> StyleBox:
    if base_control.has_theme_stylebox(name, type_name):
        return base_control.get_theme_stylebox(name, type_name)
    if base_control.theme and base_control.theme.has_stylebox(name, type_name):
        return base_control.theme.get_stylebox(name, type_name)
    return null

func _ready():
    var tool_group = ButtonGroup.new()
    tool_draw.toggle_mode = true
    tool_select.toggle_mode = true
    tool_draw.button_group = tool_group
    tool_select.button_group = tool_group
    tool_draw.button_pressed = true

    var mode_group = ButtonGroup.new()
    mode_add.toggle_mode = true
    mode_subtract.toggle_mode = true
    mode_add.button_group = mode_group
    mode_subtract.button_group = mode_group
    mode_add.button_pressed = true

    var shape_group = ButtonGroup.new()
    shape_box.toggle_mode = true
    shape_cylinder.toggle_mode = true
    shape_box.button_group = shape_group
    shape_cylinder.button_group = shape_group
    shape_box.button_pressed = true

    snap_button_group = ButtonGroup.new()
    var snap_values = [1, 2, 4, 8, 16, 32, 64]
    for index in range(snap_buttons.size()):
        var button = snap_buttons[index]
        if not button:
            continue
        button.toggle_mode = true
        button.flat = false
        button.button_group = snap_button_group
        button.set_meta("snap_value", snap_values[index])
        button.toggled.connect(_on_snap_button_toggled.bind(button))

    grid_snap.value_changed.connect(_on_grid_snap_value_changed)
    show_hud.toggled.connect(_on_show_hud_toggled)
    if show_grid:
        show_grid.toggled.connect(_on_show_grid_toggled)
    if follow_grid:
        follow_grid.toggled.connect(_on_follow_grid_toggled)
    if debug_logs:
        debug_logs.toggled.connect(_on_debug_logs_toggled)

    bake_btn.pressed.connect(_on_bake)
    clear_btn.pressed.connect(_on_clear)
    floor_btn.pressed.connect(_on_floor)
    apply_cuts_btn.pressed.connect(_on_apply_cuts)
    clear_cuts_btn.pressed.connect(_on_clear_cuts)
    commit_cuts_btn.pressed.connect(_on_commit_cuts)
    restore_cuts_btn.pressed.connect(_on_restore_cuts)
    if save_preset_btn:
        save_preset_btn.pressed.connect(_on_save_preset)
    if quick_play_btn:
        quick_play_btn.pressed.connect(_on_quick_play)
    if preset_menu:
        preset_menu.clear()
        preset_menu.add_item("Rename", PRESET_MENU_RENAME)
        preset_menu.add_item("Delete", PRESET_MENU_DELETE)
        preset_menu.id_pressed.connect(_on_preset_menu_id_pressed)
    if preset_rename_dialog:
        preset_rename_dialog.confirmed.connect(_on_preset_rename_confirmed)
    status_label.text = "Status: Idle"
    _sync_snap_buttons(grid_snap.value)
    _ensure_presets_dir()
    _load_presets()
    set_process(true)

func _process(delta):
    var scene = get_tree().edited_scene_root
    if not scene:
        scene = get_tree().get_current_scene()
    if scene:
        if scene.get_script() == LevelRootType or scene.name == "LevelRoot":
            level_root = scene
        else:
            var candidate = scene.get_node_or_null("LevelRoot")
            if candidate:
                level_root = candidate
            else:
                level_root = null
    else:
        level_root = null
    if level_root != connected_root:
        _disconnect_root_signals()
        connected_root = level_root
        _connect_root_signals()
    if level_root and level_root.get_script() == LevelRootType:
        level_root.bake_collision_layer_index = int(bake_layer.value)
        level_root.commit_freeze = commit_freeze.button_pressed
        if show_grid:
            level_root.grid_visible = show_grid.button_pressed
        if follow_grid:
            level_root.grid_follow_brush = follow_grid.button_pressed
        level_root.debug_logging = debug_enabled

func get_operation() -> int:
    return CSGShape3D.OPERATION_UNION if mode_add.button_pressed else CSGShape3D.OPERATION_SUBTRACTION

func get_tool() -> int:
    return 0 if tool_draw.button_pressed else 1

func get_brush_size() -> Vector3:
    return Vector3(size_x.value, size_y.value, size_z.value)

func get_shape() -> int:
    return 0 if shape_box.button_pressed else 1

func get_grid_snap() -> float:
    return grid_snap.value

func get_show_hud() -> bool:
    return show_hud.button_pressed

func set_show_hud(visible: bool) -> void:
    if show_hud.button_pressed == visible:
        return
    show_hud.button_pressed = visible

func _on_grid_snap_value_changed(value: float) -> void:
    if syncing_snap:
        return
    _apply_grid_snap(value)

func _on_snap_button_toggled(pressed: bool, button: Button) -> void:
    if syncing_snap:
        return
    if not pressed:
        return
    var snap_value = float(button.get_meta("snap_value"))
    _apply_grid_snap(snap_value)

func _apply_grid_snap(value: float) -> void:
    syncing_snap = true
    grid_snap.value = value
    syncing_snap = false
    _sync_snap_buttons(value)
    if level_root and level_root.get_script() == LevelRootType:
        level_root.grid_snap = value

func _sync_snap_buttons(value: float) -> void:
    syncing_snap = true
    var matched = false
    for button in snap_buttons:
        if not button:
            continue
        var snap_value = float(button.get_meta("snap_value"))
        var is_match = is_equal_approx(value, snap_value)
        button.button_pressed = is_match
        if is_match:
            matched = true
    if not matched:
        for button in snap_buttons:
            if button:
                button.button_pressed = false
    syncing_snap = false

func _on_show_hud_toggled(pressed: bool) -> void:
    hud_visibility_changed.emit(pressed)
    _log("HUD visibility: %s" % ("on" if pressed else "off"))

func _on_follow_grid_toggled(pressed: bool) -> void:
    if syncing_grid:
        return
    if level_root and level_root.get_script() == LevelRootType:
        level_root.grid_follow_brush = pressed
    _log("Grid follow: %s" % ("on" if pressed else "off"))

func _on_show_grid_toggled(pressed: bool) -> void:
    if syncing_grid:
        return
    if level_root and level_root.get_script() == LevelRootType:
        level_root.grid_visible = pressed
    _log("Grid visible: %s" % ("on" if pressed else "off"))

func _on_debug_logs_toggled(pressed: bool) -> void:
    if syncing_grid:
        return
    debug_enabled = pressed
    if level_root and level_root.get_script() == LevelRootType:
        level_root.debug_logging = pressed
    _log("Debug logs: %s" % ("on" if pressed else "off"), true)

func _log(message: String, force: bool = false) -> void:
    if not debug_enabled and not force:
        return
    print("[HammerForge Dock] %s" % message)

func _on_bake():
    _log("Bake requested")
    if level_root and level_root.has_method("bake"):
        level_root.call("bake")

func _on_clear():
    _log("Clear brushes requested")
    if level_root and level_root.has_method("clear_brushes"):
        level_root.call("clear_brushes")

func _on_floor():
    _log("Create floor requested")
    if level_root and level_root.has_method("create_floor"):
        level_root.call("create_floor")

func _on_apply_cuts():
    _log("Apply cuts requested")
    if level_root and level_root.has_method("apply_pending_cuts"):
        level_root.call("apply_pending_cuts")

func _on_clear_cuts():
    _log("Clear pending cuts requested")
    if level_root and level_root.has_method("clear_pending_cuts"):
        level_root.call("clear_pending_cuts")

func _on_commit_cuts():
    _log("Commit cuts requested (freeze=%s)" % (commit_freeze.button_pressed))
    if editor_interface:
        var selection = editor_interface.get_selection()
        if selection:
            selection.clear()
    if level_root and level_root.has_method("commit_cuts"):
        level_root.call("commit_cuts")

func _on_restore_cuts():
    _log("Restore committed cuts requested")
    if level_root and level_root.has_method("restore_committed_cuts"):
        level_root.call("restore_committed_cuts")

func _connect_root_signals() -> void:
    if not connected_root:
        return
    if connected_root.has_signal("bake_started"):
        if not connected_root.is_connected("bake_started", Callable(self, "_on_bake_started")):
            connected_root.connect("bake_started", Callable(self, "_on_bake_started"))
    if connected_root.has_signal("bake_finished"):
        if not connected_root.is_connected("bake_finished", Callable(self, "_on_bake_finished")):
            connected_root.connect("bake_finished", Callable(self, "_on_bake_finished"))
    if connected_root.has_signal("grid_snap_changed"):
        if not connected_root.is_connected("grid_snap_changed", Callable(self, "_on_root_grid_snap_changed")):
            connected_root.connect("grid_snap_changed", Callable(self, "_on_root_grid_snap_changed"))
    _sync_grid_snap_from_root()
    _sync_grid_settings_from_root()

func _disconnect_root_signals() -> void:
    if not connected_root:
        return
    if connected_root.has_signal("bake_started"):
        if connected_root.is_connected("bake_started", Callable(self, "_on_bake_started")):
            connected_root.disconnect("bake_started", Callable(self, "_on_bake_started"))
    if connected_root.has_signal("bake_finished"):
        if connected_root.is_connected("bake_finished", Callable(self, "_on_bake_finished")):
            connected_root.disconnect("bake_finished", Callable(self, "_on_bake_finished"))
    if connected_root.has_signal("grid_snap_changed"):
        if connected_root.is_connected("grid_snap_changed", Callable(self, "_on_root_grid_snap_changed")):
            connected_root.disconnect("grid_snap_changed", Callable(self, "_on_root_grid_snap_changed"))

func _sync_grid_snap_from_root() -> void:
    if connected_root and connected_root.get_script() == LevelRootType:
        var value = float(connected_root.grid_snap)
        syncing_snap = true
        grid_snap.value = value
        syncing_snap = false
        _sync_snap_buttons(value)

func _on_root_grid_snap_changed(value: float) -> void:
    syncing_snap = true
    grid_snap.value = value
    syncing_snap = false
    _sync_snap_buttons(value)

func _sync_grid_settings_from_root() -> void:
    if not connected_root or connected_root.get_script() != LevelRootType:
        return
    syncing_grid = true
    if show_grid:
        show_grid.button_pressed = connected_root.grid_visible
    if follow_grid:
        follow_grid.button_pressed = connected_root.grid_follow_brush
    if debug_logs:
        debug_enabled = connected_root.debug_logging
        debug_logs.button_pressed = debug_enabled
    syncing_grid = false

func _on_bake_started() -> void:
    status_label.text = "Status: Baking..."
    _set_bake_buttons_disabled(true)

func _on_bake_finished(success: bool) -> void:
    status_label.text = "Status: Ready" if success else "Status: Bake failed"
    _set_bake_buttons_disabled(false)

func _set_bake_buttons_disabled(disabled: bool) -> void:
    bake_btn.disabled = disabled
    commit_cuts_btn.disabled = disabled
    apply_cuts_btn.disabled = disabled
    if quick_play_btn:
        quick_play_btn.disabled = disabled

func _on_quick_play() -> void:
    _log("Quick play requested")
    if level_root and level_root.has_method("bake"):
        await level_root.bake(true, true)
    if editor_interface:
        editor_interface.play_current_scene()

func _ensure_presets_dir() -> void:
    var abs_path = ProjectSettings.globalize_path(presets_dir)
    if not DirAccess.dir_exists_absolute(abs_path):
        DirAccess.make_dir_recursive_absolute(abs_path)

func _load_presets() -> void:
    _clear_preset_buttons()
    var dir = DirAccess.open(presets_dir)
    if not dir:
        return
    var files: Array[String] = []
    dir.list_dir_begin()
    var file_name = dir.get_next()
    while file_name != "":
        if not dir.current_is_dir() and file_name.ends_with(".tres"):
            files.append(file_name)
        file_name = dir.get_next()
    dir.list_dir_end()
    files.sort()
    for file in files:
        var path = "%s/%s" % [presets_dir, file]
        var preset = load(path)
        if preset and preset is BrushPreset:
            _create_preset_button(preset, path)

func _clear_preset_buttons() -> void:
    for button in preset_buttons:
        if button and button.get_parent():
            button.get_parent().remove_child(button)
            button.queue_free()
    preset_buttons.clear()

func _create_preset_button(preset: BrushPreset, path: String) -> void:
    if not preset_grid:
        return
    var button := Button.new()
    button.text = _preset_display_name(preset, path)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.set_meta("preset_path", path)
    button.pressed.connect(_on_preset_button_pressed.bind(button))
    button.gui_input.connect(_on_preset_button_gui_input.bind(button))
    preset_grid.add_child(button)
    preset_buttons.append(button)

func _preset_display_name(preset: BrushPreset, path: String) -> String:
    if preset and preset.resource_name != "":
        return preset.resource_name
    var file_name = path.get_file().get_basename()
    return file_name.replace("_", " ")

func _on_save_preset() -> void:
    _ensure_presets_dir()
    var preset = BrushPreset.new()
    preset.shape = get_shape()
    preset.size = get_brush_size()
    preset.operation = get_operation()
    var display_name = _suggest_preset_name()
    var path = _unique_preset_path(display_name)
    preset.resource_name = display_name
    var err = ResourceSaver.save(preset, path)
    if err != OK:
        _log("Failed to save preset (%s)" % err, true)
        return
    _load_presets()

func _suggest_preset_name() -> String:
    var base = "Preset"
    var index = preset_buttons.size() + 1
    return "%s %s" % [base, index]

func _sanitize_preset_name(name: String) -> String:
    var safe = name.strip_edges()
    safe = safe.replace("/", "_")
    safe = safe.replace("\\", "_")
    safe = safe.replace(":", "_")
    safe = safe.replace("*", "_")
    safe = safe.replace("?", "_")
    safe = safe.replace("\"", "_")
    safe = safe.replace("<", "_")
    safe = safe.replace(">", "_")
    safe = safe.replace("|", "_")
    if safe == "":
        safe = "Preset"
    return safe

func _unique_preset_path(display_name: String) -> String:
    var safe = _sanitize_preset_name(display_name)
    var base = safe.replace(" ", "_")
    var path = "%s/%s.tres" % [presets_dir, base]
    var index = 1
    while ResourceLoader.exists(path):
        path = "%s/%s_%s.tres" % [presets_dir, base, index]
        index += 1
    return path

func _on_preset_button_pressed(button: Button) -> void:
    if not button:
        return
    var path = button.get_meta("preset_path", "")
    if path == "":
        return
    var preset = load(path)
    if preset and preset is BrushPreset:
        _apply_preset(preset)

func _apply_preset(preset: BrushPreset) -> void:
    if not preset:
        return
    size_x.value = preset.size.x
    size_y.value = preset.size.y
    size_z.value = preset.size.z
    if preset.shape == BrushPreset.BrushShape.CYLINDER:
        shape_cylinder.button_pressed = true
    else:
        shape_box.button_pressed = true
    if preset.operation == CSGShape3D.OPERATION_SUBTRACTION:
        mode_subtract.button_pressed = true
    else:
        mode_add.button_pressed = true

func _on_preset_button_gui_input(event: InputEvent, button: Button) -> void:
    if not (event is InputEventMouseButton):
        return
    var mouse_event := event as InputEventMouseButton
    if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
        preset_context_button = button
        if preset_menu:
            preset_menu.position = get_global_mouse_position()
            preset_menu.popup()
        button.accept_event()

func _on_preset_menu_id_pressed(id: int) -> void:
    if not preset_context_button:
        return
    match id:
        PRESET_MENU_RENAME:
            _show_preset_rename_dialog(preset_context_button)
        PRESET_MENU_DELETE:
            _delete_preset(preset_context_button)

func _show_preset_rename_dialog(button: Button) -> void:
    if not preset_rename_dialog or not preset_rename_line:
        return
    preset_rename_line.text = button.text
    preset_rename_line.select_all()
    preset_rename_dialog.popup_centered()

func _on_preset_rename_confirmed() -> void:
    if not preset_context_button:
        return
    var new_name = preset_rename_line.text
    _rename_preset(preset_context_button, new_name)
    preset_context_button = null

func _rename_preset(button: Button, new_name: String) -> void:
    var current_path = button.get_meta("preset_path", "")
    if current_path == "":
        return
    var display_name = _sanitize_preset_name(new_name)
    var base = display_name.replace(" ", "_")
    var candidate_path = "%s/%s.tres" % [presets_dir, base]
    var target_path = candidate_path if candidate_path == current_path else _unique_preset_path(display_name)
    var abs_current = ProjectSettings.globalize_path(current_path)
    var abs_target = ProjectSettings.globalize_path(target_path)
    if abs_current != abs_target:
        var rename_err = DirAccess.rename_absolute(abs_current, abs_target)
        if rename_err != OK:
            _log("Failed to rename preset (%s)" % rename_err, true)
            return
    var preset = load(target_path)
    if preset and preset is BrushPreset:
        preset.resource_name = display_name
        ResourceSaver.save(preset, target_path)
    _load_presets()
    preset_context_button = null

func _delete_preset(button: Button) -> void:
    var path = button.get_meta("preset_path", "")
    if path == "":
        return
    var abs_path = ProjectSettings.globalize_path(path)
    var remove_err = DirAccess.remove_absolute(abs_path)
    if remove_err != OK:
        _log("Failed to delete preset (%s)" % remove_err, true)
        return
    _load_presets()
    preset_context_button = null
