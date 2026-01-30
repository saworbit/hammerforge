@tool
extends Control

@onready var label: Label = $Panel/Margin/Label

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _apply_layout()
    _update_label()

func _apply_layout() -> void:
    set_anchors_preset(Control.PRESET_TOP_RIGHT)
    offset_left = -260.0
    offset_top = 8.0
    offset_right = -8.0
    offset_bottom = 136.0

func _update_label() -> void:
    if not label:
        return
    label.text = "Shift + Click: Place Brush\nAlt + Click: Select Brush\nX / Y / Z: Change Axis\nCtrl + Scroll: Adjust Brush Size"
