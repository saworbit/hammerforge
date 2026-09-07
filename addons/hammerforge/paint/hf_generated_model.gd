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


class HeightmapFloor:
	var id: StringName
	var mesh: ArrayMesh
	var transform: Transform3D
	var blend_image: Image = null
	var blend_texture: ImageTexture = null
	var slot_textures: Array = []
	var slot_uv_scales: Array[float] = []
	var slot_tints: Array[Color] = []


var floors: Array[FloorRect] = []
var walls: Array[WallSeg] = []
var heightmap_floors: Array[HeightmapFloor] = []
