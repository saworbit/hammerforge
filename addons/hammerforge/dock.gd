@tool
extends Control
class_name HammerForgeDock

const LevelRootType = preload("level_root.gd")

@onready var tool_draw: Button = $VBox/ToolRow/ToolDraw
@onready var tool_select: Button = $VBox/ToolRow/ToolSelect
@onready var mode_add: Button = $VBox/ModeRow/ModeAdd
@onready var mode_subtract: Button = $VBox/ModeRow/ModeSubtract
@onready var shape_box: Button = $VBox/ShapeRow/ShapeBox
@onready var shape_cylinder: Button = $VBox/ShapeRow/ShapeCylinder
@onready var size_x: SpinBox = $VBox/SizeX
@onready var size_y: SpinBox = $VBox/SizeY
@onready var size_z: SpinBox = $VBox/SizeZ
@onready var grid_snap: SpinBox = $VBox/GridSnap
@onready var floor_btn: Button = $VBox/CreateFloor
@onready var apply_cuts_btn: Button = $VBox/ApplyCuts
@onready var clear_cuts_btn: Button = $VBox/ClearCuts
@onready var commit_cuts_btn: Button = $VBox/CommitCuts
@onready var bake_btn: Button = $VBox/Bake
@onready var clear_btn: Button = $VBox/Clear

var level_root: Node = null
var editor_interface: EditorInterface = null

func set_editor_interface(iface: EditorInterface) -> void:
    editor_interface = iface

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
    bake_btn.pressed.connect(_on_bake)
    clear_btn.pressed.connect(_on_clear)
    floor_btn.pressed.connect(_on_floor)
    apply_cuts_btn.pressed.connect(_on_apply_cuts)
    clear_cuts_btn.pressed.connect(_on_clear_cuts)
    commit_cuts_btn.pressed.connect(_on_commit_cuts)
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

func _on_bake():
    if level_root and level_root.has_method("bake"):
        level_root.call("bake")

func _on_clear():
    if level_root and level_root.has_method("clear_brushes"):
        level_root.call("clear_brushes")

func _on_floor():
    if level_root and level_root.has_method("create_floor"):
        level_root.call("create_floor")

func _on_apply_cuts():
    if level_root and level_root.has_method("apply_pending_cuts"):
        level_root.call("apply_pending_cuts")

func _on_clear_cuts():
    if level_root and level_root.has_method("clear_pending_cuts"):
        level_root.call("clear_pending_cuts")

func _on_commit_cuts():
    if editor_interface:
        var selection = editor_interface.get_selection()
        if selection:
            selection.clear()
    if level_root and level_root.has_method("commit_cuts"):
        level_root.call("commit_cuts")
