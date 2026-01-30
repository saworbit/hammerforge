@tool
extends SubViewportContainer
class_name QuadrantView

enum ViewType { TOP, FRONT, SIDE, PERSPECTIVE }

@export var view_type: ViewType = ViewType.PERSPECTIVE
@export var ortho_size: float = 512.0

@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/Camera3D

func _ready() -> void:
    if viewport:
        viewport.own_world_3d = false
        viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    if camera:
        camera.current = true
    _setup_view()

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
    if viewport and world:
        viewport.world_3d = world

func get_camera() -> Camera3D:
    return camera
