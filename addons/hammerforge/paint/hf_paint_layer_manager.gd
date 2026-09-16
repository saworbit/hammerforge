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
		# Removing a layer below the active one shifts every later layer down by
		# one, so the same index names a different layer. Clamping alone moved
		# the paint target to a layer the mapper did not choose, silently.
		if index < active_layer_index:
			active_layer_index -= 1
		active_layer_index = clamp(active_layer_index, 0, layers.size() - 1)


func rename_layer(index: int, new_name: String) -> void:
	if index < 0 or index >= layers.size():
		return
	var layer = layers[index]
	if layer:
		layer.display_name = new_name


## Whether a layer with this id is already in the list.
func has_layer_id(layer_id: StringName) -> bool:
	for layer in layers:
		if layer and layer.layer_id == layer_id:
			return true
	return false


## `layer_id` with every character Godot strips from a node name replaced.
##
## The id goes into the node name and into the middle of every generated brush
## id (`hf:floor:v1:<layer_id>:<chunk>:...`). A ":" in it shifted every field of
## the generated id, so the reconciler read the wrong one as the chunk tag, and
## any of the other characters made the node name and the id disagree.
## `validate_node_name()` is the engine's own rule for what a node name may
## hold, so running the id through it keeps the two in step.
static func safe_layer_id(layer_id: StringName) -> StringName:
	var safe := str(layer_id).validate_node_name()
	if safe.strip_edges() == "":
		return &"layer_0"
	return StringName(safe)


## A free id based on `layer_id`, adding _2, _3 ... until one is free.
##
## The id is identity rather than a label - anything resolving a layer by id
## takes whichever it finds first, so two layers must not share one.
func unique_layer_id(layer_id: StringName) -> StringName:
	if not has_layer_id(layer_id):
		return layer_id
	var base := str(layer_id)
	var suffix := 2
	while has_layer_id(StringName("%s_%d" % [base, suffix])):
		suffix += 1
	return StringName("%s_%d" % [base, suffix])


func create_layer(layer_id: StringName, layer_y: float) -> HFPaintLayer:
	if not base_grid:
		base_grid = HFPaintGrid.new()
	var grid = base_grid.duplicate() as HFPaintGrid
	if not grid:
		grid = HFPaintGrid.new()
	grid.layer_y = layer_y
	var requested := safe_layer_id(layer_id)
	if requested != layer_id:
		HFLog.warn(
			(
				"HammerForge: paint layer id '%s' holds characters a node name cannot, using '%s'"
				% [layer_id, requested]
			)
		)
	var unique_id := unique_layer_id(requested)
	if unique_id != requested:
		HFLog.warn("HammerForge: paint layer id '%s' is taken, using '%s'" % [requested, unique_id])
	var layer := HFPaintLayer.new()
	layer.name = "Layer_%s" % str(unique_id)
	layer.layer_id = unique_id
	layer.grid = grid
	layer.chunk_size = chunk_size
	add_child(layer)
	layers.append(layer)
	active_layer_index = layers.size() - 1
	return layer
