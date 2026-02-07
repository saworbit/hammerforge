@tool
class_name HFPaintLayerManager
extends Node

@export var chunk_size: int = 32
@export var base_grid: HFPaintGrid

var layers: Array[HFPaintLayer] = []
var active_layer_index: int = 0


func _ready() -> void:
	if layers.is_empty():
		create_layer(&"layer_0", 0.0)


func get_active_layer() -> HFPaintLayer:
	if active_layer_index < 0 or active_layer_index >= layers.size():
		return null
	return layers[active_layer_index]


func set_active_layer(index: int) -> void:
	if index < 0 or index >= layers.size():
		return
	active_layer_index = index


func clear_layers() -> void:
	for layer in layers:
		if layer and layer.get_parent():
			layer.get_parent().remove_child(layer)
			layer.queue_free()
	layers.clear()
	active_layer_index = 0


func remove_layer(index: int) -> void:
	if index < 0 or index >= layers.size():
		return
	var layer = layers[index]
	if layer and layer.get_parent():
		layer.get_parent().remove_child(layer)
		layer.queue_free()
	layers.remove_at(index)
	if layers.is_empty():
		active_layer_index = 0
	else:
		active_layer_index = clamp(active_layer_index, 0, layers.size() - 1)


func create_layer(layer_id: StringName, layer_y: float) -> HFPaintLayer:
	if not base_grid:
		base_grid = HFPaintGrid.new()
	var grid = base_grid.duplicate() as HFPaintGrid
	if not grid:
		grid = HFPaintGrid.new()
	grid.layer_y = layer_y
	var layer := HFPaintLayer.new()
	layer.name = "Layer_%s" % str(layer_id)
	layer.layer_id = layer_id
	layer.grid = grid
	layer.chunk_size = chunk_size
	add_child(layer)
	layers.append(layer)
	active_layer_index = layers.size() - 1
	return layer
