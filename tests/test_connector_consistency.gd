extends GutTest
## Ghosts, confirmation, validation and bake share the same connector rules.

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.paint_layers.clear_layers()
	root.paint_layers.chunk_size = 8
	root.paint_layers.base_grid.cell_size = 1.0
	var lo := root.paint_layers.create_layer(&"lo", 0.0)
	var hi := root.paint_layers.create_layer(&"hi", 3.0)
	lo.set_cell(Vector2i.ZERO, true)
	hi.set_cell(Vector2i.RIGHT, true)


func test_ghost_confirm_validation_and_bake_use_the_level_threshold():
	root.bake_auto_connectors = true
	root.bake_connector_mode = HFAutoConnector.ConnectorMode.AUTO
	root.bake_connector_stair_threshold = 4.0
	var found: Dictionary = root.paint_system.connector_candidates(0, Vector2i.ZERO, Vector2i.ZERO)
	assert_true(found["ok"], str(found))
	if not found["ok"]:
		return
	var ghost: HFConnectorTool.ConnectorDef = found["new"][0]
	assert_eq(ghost.connector_type, HFConnectorTool.ConnectorType.RAMP, "3 m is below 4 m")
	var checked: Array = root.validation_system._pending_connector_definitions(root.paint_layers)
	assert_eq(checked[0].connector_type, ghost.connector_type, "Check Issues agrees")
	var confirmed: Dictionary = root.paint_system.confirm_connectors(
		0, Vector2i.ZERO, Vector2i.ZERO
	)
	assert_eq(confirmed["connectors"][0]["type"], "ramp")
	var container := Node3D.new()
	root.add_child(container)
	root.bake_system._append_auto_connectors(container)
	assert_not_null(container.get_node_or_null("AutoConnector_0"))
	container.free()


func test_bake_skips_malformed_confirmed_connectors_as_validation_does():
	root.bake_auto_connectors = false
	var definition := HFConnectorTool.ConnectorDef.new()
	definition.from_layer_index = 0
	definition.to_layer_index = 1
	definition.from_cell = Vector2i.ZERO
	definition.to_cell = Vector2i.RIGHT
	root.paint_tool.connector_defs = [null, definition]
	root.bake_system.connector_defs_signature()
	var checked: Array = root.validation_system._pending_connector_definitions(root.paint_layers)
	assert_eq(checked.size(), 1)
	var container := Node3D.new()
	root.add_child(container)
	root.bake_system._append_auto_connectors(container)
	assert_not_null(container.get_node_or_null("AutoConnector_0"), "valid connector still bakes")
	assert_null(container.get_node_or_null("AutoConnector_1"))
	container.free()
	root.paint_tool.connector_defs.clear()


func test_layers_of_two_cell_sizes_are_not_joined_by_index():
	# A painted layer keeps its cell size when the snap changes (#2011), so two
	# layers can differ. Cell [1, 0] of 0.5 m is not beside cell [0, 0] of 1 m.
	var hi: HFPaintLayer = root.paint_layers.layers[1]
	hi.grid.cell_size = 0.5
	var found: Dictionary = root.paint_system.connector_candidates(0, Vector2i.ZERO, Vector2i.ZERO)
	assert_false(found["ok"], "no ghost")
	assert_eq(HFAutoConnector.new().detect_boundaries(root.paint_layers).size(), 0, "nor in a bake")
	var definition := HFConnectorTool.ConnectorDef.new()
	definition.from_layer_index = 0
	definition.to_layer_index = 1
	definition.from_cell = Vector2i.ZERO
	definition.to_cell = Vector2i.RIGHT
	assert_null(HFConnectorTool.new().generate_connector(definition, root.paint_layers))
	assert_false(
		root.validation_system._connector_builds(definition, root.paint_layers.layers),
		"Check Issues agrees it builds nothing"
	)
	hi.grid.cell_size = 1.0
	assert_not_null(HFConnectorTool.new().generate_connector(definition, root.paint_layers))


func test_full_scan_skips_null_layers_and_agrees_with_touched_cells():
	root.paint_layers.layers.insert(1, null)
	var gen := HFAutoConnector.new()
	var full := gen.detect_boundaries(root.paint_layers)
	var touched := gen.boundaries_for_cells(root.paint_layers, 0, {Vector2i.ZERO: true})
	assert_eq(full.size(), 1)
	assert_eq(touched.size(), full.size())
	if not full.is_empty():
		assert_eq(full[0].to_layer_index, 2, "null slots do not renumber layers")
		assert_eq(touched[0].to_layer_index, full[0].to_layer_index)
	root.paint_layers.layers.remove_at(1)
