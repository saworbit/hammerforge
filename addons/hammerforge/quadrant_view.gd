@tool
extends SubViewportContainer
class_name QuadrantView

enum ViewType { TOP, FRONT, SIDE, PERSPECTIVE }

@export var view_type: ViewType = ViewType.PERSPECTIVE
@export var ortho_size: float = 512.0

@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/Camera3D
var pending_world: World3D = null

func _ready() -> void:
    if viewport:
        viewport.own_world_3d = true
        viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        viewport.transparent_bg = true
        viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
        if viewport.has_method("set_disable_3d"):
            viewport.set_disable_3d(false)
        else:
            viewport.disable_3d = false
    if camera:
        camera.current = true
    _setup_view()
    if pending_world and viewport:
        viewport.world_3d = pending_world
        pending_world = null

func _setup_view() -> void:
    if not camera:
        return
    match view_type:
        ViewType.TOP:
            camera.projection = Camera3D.PROJECTION_ORTHOGONAL
            camera.size = ortho_size
            camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
            camera.position = Vector3(0.0, ortho_size, 0.0)
        ViewType.FRONT:
            camera.projection = Camera3D.PROJECTION_ORTHOGONAL
            camera.size = ortho_size
            camera.rotation_degrees = Vector3(0.0, 0.0, 0.0)
            camera.position = Vector3(0.0, 0.0, ortho_size)
        ViewType.SIDE:
            camera.projection = Camera3D.PROJECTION_ORTHOGONAL
            camera.size = ortho_size
            camera.rotation_degrees = Vector3(0.0, -90.0, 0.0)
            camera.position = Vector3(ortho_size, 0.0, 0.0)
        ViewType.PERSPECTIVE:
            camera.projection = Camera3D.PROJECTION_PERSPECTIVE
            camera.position = Vector3(ortho_size, ortho_size * 0.75, ortho_size)
            camera.look_at(Vector3.ZERO, Vector3.UP)

func set_world_3d(world: World3D) -> void:
    if not world:
        return
    if viewport:
        viewport.world_3d = world
        pending_world = null
    else:
        pending_world = world

func get_camera() -> Camera3D:
    return camera
