@tool
class_name HFPaintGrid
extends Resource

@export var cell_size: float = 1.0
@export var origin: Vector3 = Vector3.ZERO
@export var basis: Basis = Basis.IDENTITY  # plane orientation, default XZ
@export var layer_y: float = 0.0


func world_to_uv(p: Vector3) -> Vector2:
	# project to grid plane (basis), return local uv in plane coordinates
	var local := basis.inverse() * (p - origin)
	# default: local.x maps U, local.z maps V
	return Vector2(local.x, local.z)


func uv_to_world(uv: Vector2, y: float = layer_y) -> Vector3:
	# default: U->x, V->z, y is vertical
	var local := Vector3(uv.x, y, uv.y)
	return origin + (basis * local)


func world_to_cell(p: Vector3) -> Vector2i:
	var uv := world_to_uv(p)
	return Vector2i(floor(uv.x / cell_size), floor(uv.y / cell_size))


func cell_to_uv(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size, cell.y * cell_size)


func cell_center_uv(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
