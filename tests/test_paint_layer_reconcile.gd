extends GutTest

## The generated-brush reconciler sweeps by chunk, and every paint layer shares
## one Generated/Floors and one Generated/Walls. These pin the scoping that
## keeps one layer's pass from freeing another layer's geometry.

var floors_root: Node3D
var walls_root: Node3D
var reconciler: HFGeneratedReconciler
var grid: HFPaintGrid
var settings: HFGeometrySynth.SynthSettings


func before_each() -> void:
	floors_root = Node3D.new()
	walls_root = Node3D.new()
	add_child_autofree(floors_root)
	add_child_autofree(walls_root)
	reconciler = HFGeneratedReconciler.new()
	reconciler.floors_root = floors_root
	reconciler.walls_root = walls_root
	grid = HFPaintGrid.new()
	settings = HFGeometrySynth.SynthSettings.new()


func _floor_model(layer_id: StringName, chunk: Vector2i, cell: Vector2i) -> HFGeneratedModel:
	var model := HFGeneratedModel.new()
	var fr := HFGeneratedModel.FloorRect.new()
	fr.id = HFHash.floor_id(layer_id, chunk, cell, Vector2i.ONE)
	fr.min_cell = cell
	fr.size = Vector2i.ONE
	fr.layer_y = 0.0
	fr.thickness = 0.2
	model.floors.append(fr)
	return model


func test_reconciling_one_layer_leaves_another_layers_geometry_in_the_chunk() -> void:
	var chunk := Vector2i(0, 0)
	reconciler.reconcile(
		_floor_model(&"layer_0", chunk, Vector2i(1, 1)), grid, settings, [chunk], &"layer_0"
	)
	reconciler.reconcile(
		_floor_model(&"layer_1", chunk, Vector2i(2, 2)), grid, settings, [chunk], &"layer_1"
	)
	assert_eq(
		floors_root.get_child_count(),
		2,
		"Reconciling layer_1 must not free the floor layer_0 generated in the same chunk"
	)
	var layers := []
	for child in floors_root.get_children():
		layers.append(str(child.get_meta("hf_layer", "")))
	layers.sort()
	assert_eq(layers, ["layer_0", "layer_1"], "One node per layer, each tagged with its own")


func test_a_layers_own_stale_geometry_is_still_swept() -> void:
	var chunk := Vector2i(0, 0)
	reconciler.reconcile(
		_floor_model(&"layer_0", chunk, Vector2i(1, 1)), grid, settings, [chunk], &"layer_0"
	)
	reconciler.reconcile(
		_floor_model(&"layer_0", chunk, Vector2i(5, 5)), grid, settings, [chunk], &"layer_0"
	)
	assert_eq(floors_root.get_child_count(), 1, "The layer's own superseded floor is removed")


func test_a_node_from_an_older_build_is_matched_by_its_id() -> void:
	var chunk := Vector2i(0, 0)
	reconciler.reconcile(
		_floor_model(&"layer_0", chunk, Vector2i(1, 1)), grid, settings, [chunk], &"layer_0"
	)
	var node := floors_root.get_child(0)
	node.remove_meta("hf_layer")
	reconciler.reconcile(
		_floor_model(&"layer_0", chunk, Vector2i(1, 1)), grid, settings, [chunk], &"layer_0"
	)
	assert_eq(
		floors_root.get_child_count(),
		1,
		"A node left without the meta is still found, rather than built a second time"
	)


func test_chunk_tag_survives_a_layer_id_that_held_a_colon() -> void:
	var mgr := HFPaintLayerManager.new()
	add_child_autofree(mgr)
	var layer := mgr.create_layer(&"a:b:c", 0.0)
	assert_eq(layer.layer_id, &"a_b_c", "The colons are gone before the id is stored")
	assert_eq(str(layer.name), "Layer_a_b_c", "The node name and the id agree")
	var gid := HFHash.floor_id(layer.layer_id, Vector2i(1, 2), Vector2i.ZERO, Vector2i(4, 4))
	assert_eq(HFHash.chunk_tag_from_id(gid), "1,2", "Field 4 is still the chunk")
	assert_eq(HFHash.layer_tag_from_id(gid), "a_b_c", "Field 3 is still the layer")
