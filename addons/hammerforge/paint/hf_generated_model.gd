@tool
class_name HFGeneratedModel
extends RefCounted


class FloorRect:
	var id: StringName
	var min_cell: Vector2i
	var size: Vector2i  # width, height in cells
	var layer_y: float
	var thickness: float


class WallSeg:
	var id: StringName
	var a: Vector2i  # grid-vertex coordinates (edge space)
	var b: Vector2i
	var layer_y: float
	var height: float
	var thickness: float
	var outward: Vector2i  # one of (1,0),(-1,0),(0,1),(0,-1)


var floors: Array[FloorRect] = []
var walls: Array[WallSeg] = []
