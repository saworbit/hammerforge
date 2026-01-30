@tool
extends GridContainer
class_name QuadrantContainer

@onready var views := {
    "Top": $TopView,
    "Front": $FrontView,
    "Side": $SideView,
    "Perspective": $PerspectiveView
}

func _ready() -> void:
    call_deferred("_sync_world")

func _sync_world() -> void:
    var world = _resolve_editor_world()
    if world:
        set_world_3d(world)

func _resolve_editor_world() -> World3D:
    var scene = get_tree().edited_scene_root
    if scene and scene.is_inside_tree():
        return scene.get_viewport().world_3d
    var current = get_tree().get_current_scene()
    if current and current.is_inside_tree():
        return current.get_viewport().world_3d
    return null

func set_world_3d(world: World3D) -> void:
    if not world:
        return
    for view in views.values():
        if view and view.has_method("set_world_3d"):
            view.call("set_world_3d", world)

func get_camera_at_screen_pos(screen_pos: Vector2) -> Dictionary:
    var local = to_local(screen_pos)
    for view in views.values():
        if not view:
            continue
        var rect := view.get_rect()
        if rect.has_point(local):
            var local_pos = local - rect.position
            var cam = view.call("get_camera")
            return { "camera": cam, "pos": local_pos }
    return {}
