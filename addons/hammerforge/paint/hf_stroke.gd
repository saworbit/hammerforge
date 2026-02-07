@tool
class_name HFStroke
extends RefCounted

enum Tool { PAINT, ERASE, RECT, LINE, BUCKET }
enum BrushShape { CIRCLE, SQUARE }

var tool: int = Tool.PAINT
var radius_cells: int = 1

var cells: Array[Vector2i] = []  # stamped cells in order
var times: PackedFloat64Array = PackedFloat64Array()

# derived
var bbox_min: Vector2i
var bbox_max: Vector2i
var is_closed: bool = false
var aspect_ratio: float = 1.0
var avg_speed: float = 0.0


func add_cell(c: Vector2i, t: float) -> void:
	cells.append(c)
	times.append(t)


func analyse() -> void:
	if cells.is_empty():
		return
	bbox_min = cells[0]
	bbox_max = cells[0]
	for c in cells:
		bbox_min.x = mini(bbox_min.x, c.x)
		bbox_min.y = mini(bbox_min.y, c.y)
		bbox_max.x = maxi(bbox_max.x, c.x)
		bbox_max.y = maxi(bbox_max.y, c.y)

	var w := float(bbox_max.x - bbox_min.x + 1)
	var h := float(bbox_max.y - bbox_min.y + 1)
	aspect_ratio = max(w, h) / max(1.0, min(w, h))

	var start := cells[0]
	var end := cells[cells.size() - 1]
	is_closed = start.distance_to(end) <= 1

	# crude speed estimate in cells/sec
	if times.size() >= 2:
		var dt := max(0.001, times[times.size() - 1] - times[0])
		avg_speed = float(cells.size()) / dt
