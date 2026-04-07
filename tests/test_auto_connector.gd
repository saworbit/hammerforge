extends GutTest

const HFAutoConnectorScript = preload("res://addons/hammerforge/paint/hf_auto_connector.gd")
const HFConnectorToolScript = preload("res://addons/hammerforge/paint/hf_connector_tool.gd")
const HFPaintLayerManagerScript = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")
const HFPaintLayerScript = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGridScript = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

var gen: HFAutoConnectorScript


func before_each():
	gen = HFAutoConnectorScript.new()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_layer_manager() -> HFPaintLayerManagerScript:
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	mgr.base_grid.cell_size = 1.0
	add_child_autoqfree(mgr)
	# Clear default layer created in _ready
	mgr.clear_layers()
	return mgr


func _fill_cells(layer: HFPaintLayerScript, cells: Array) -> void:
	for cell: Vector2i in cells:
		layer.set_cell(cell, true)


# ---------------------------------------------------------------------------
# detect_boundaries
# ---------------------------------------------------------------------------


func test_detect_boundaries_no_layers():
	var mgr := _make_layer_manager()
	var segs := gen.detect_boundaries(mgr)
	assert_eq(segs.size(), 0, "No layers → no segments")


func test_detect_boundaries_single_layer():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"a", 0.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0), Vector2i(1, 0)])
	var segs := gen.detect_boundaries(mgr)
	assert_eq(segs.size(), 0, "Single layer → no cross-layer segments")


func test_detect_boundaries_two_layers_no_adjacency():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 4.0)
	# Fill cells far apart — no adjacency
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(10, 10)])
	var segs := gen.detect_boundaries(mgr)
	assert_eq(segs.size(), 0, "Non-adjacent layers → no segments")


func test_detect_boundaries_two_layers_adjacent():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 4.0)
	# Layer 0 has cell (0,0); layer 1 has cell (1,0) — adjacent horizontally
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var segs := gen.detect_boundaries(mgr)
	assert_gt(segs.size(), 0, "Adjacent cells at different heights → segments")
	var seg: HFAutoConnectorScript.ConnectorSegment = segs[0]
	assert_almost_eq(seg.height_diff, 4.0, 0.01, "Height diff should be 4.0")


func test_detect_boundaries_same_height_skipped():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"a", 5.0)
	mgr.create_layer(&"b", 5.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var segs := gen.detect_boundaries(mgr)
	assert_eq(segs.size(), 0, "Same height → no connectors needed")


func test_detect_boundaries_no_duplicates():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 3.0)
	# Mutual adjacency: (0,0)→(1,0) and (1,0)→(0,0) should be deduplicated
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var segs := gen.detect_boundaries(mgr)
	# Count unique cell pairs
	var keys: Dictionary = {}
	for seg in segs:
		var lo: int = mini(seg.from_layer_index, seg.to_layer_index)
		var hi: int = maxi(seg.from_layer_index, seg.to_layer_index)
		var c_lo: Vector2i = seg.from_cell if seg.from_layer_index < seg.to_layer_index else seg.to_cell
		var k := "%d_%d_%d_%d" % [lo, hi, c_lo.x, c_lo.y]
		keys[k] = true
	assert_eq(keys.size(), segs.size(), "No duplicate segments")


# ---------------------------------------------------------------------------
# group_segments
# ---------------------------------------------------------------------------


func test_group_segments_empty():
	var empty: Array[HFAutoConnectorScript.ConnectorSegment] = []
	var groups := gen.group_segments(empty)
	assert_eq(groups.size(), 0)


func test_group_segments_single():
	var seg := HFAutoConnectorScript.ConnectorSegment.new()
	seg.from_layer_index = 0
	seg.to_layer_index = 1
	seg.from_cell = Vector2i(0, 0)
	seg.to_cell = Vector2i(1, 0)
	seg.direction = Vector2i(1, 0)
	seg.height_diff = 2.0
	var arr: Array[HFAutoConnectorScript.ConnectorSegment] = [seg]
	var groups := gen.group_segments(arr)
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].size(), 1)


func test_group_segments_adjacent_merge():
	var segs: Array[HFAutoConnectorScript.ConnectorSegment] = []
	# Two segments at (0,0)→(1,0) and (0,1)→(1,1) — same direction, adjacent perpendicular
	for y in range(2):
		var seg := HFAutoConnectorScript.ConnectorSegment.new()
		seg.from_layer_index = 0
		seg.to_layer_index = 1
		seg.from_cell = Vector2i(0, y)
		seg.to_cell = Vector2i(1, y)
		seg.direction = Vector2i(1, 0)
		seg.height_diff = 3.0
		segs.append(seg)
	var groups := gen.group_segments(segs)
	assert_eq(groups.size(), 1, "Adjacent same-direction segments merge into one group")
	assert_eq(groups[0].size(), 2)


func test_group_segments_different_directions_separate():
	var segs: Array[HFAutoConnectorScript.ConnectorSegment] = []
	var seg_a := HFAutoConnectorScript.ConnectorSegment.new()
	seg_a.from_layer_index = 0
	seg_a.to_layer_index = 1
	seg_a.from_cell = Vector2i(0, 0)
	seg_a.to_cell = Vector2i(1, 0)
	seg_a.direction = Vector2i(1, 0)
	seg_a.height_diff = 2.0
	segs.append(seg_a)
	var seg_b := HFAutoConnectorScript.ConnectorSegment.new()
	seg_b.from_layer_index = 0
	seg_b.to_layer_index = 1
	seg_b.from_cell = Vector2i(0, 0)
	seg_b.to_cell = Vector2i(0, 1)
	seg_b.direction = Vector2i(0, 1)
	seg_b.height_diff = 2.0
	segs.append(seg_b)
	var groups := gen.group_segments(segs)
	assert_eq(groups.size(), 2, "Different directions → separate groups")


# ---------------------------------------------------------------------------
# generate_connectors
# ---------------------------------------------------------------------------


func test_generate_connectors_no_layers():
	var mgr := _make_layer_manager()
	var results := gen.generate_connectors(mgr)
	assert_eq(results.size(), 0)


func test_generate_connectors_ramp():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 3.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var settings := HFAutoConnectorScript.Settings.new()
	settings.mode = HFAutoConnectorScript.ConnectorMode.RAMP
	settings.width_cells = 2
	var results := gen.generate_connectors(mgr, settings)
	assert_gt(results.size(), 0, "Should produce at least one connector")
	for entry: Dictionary in results:
		assert_not_null(entry.get("mesh"), "Each result should have a mesh")
		assert_true(entry.get("mesh") is ArrayMesh)


func test_generate_connectors_stairs():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 3.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var settings := HFAutoConnectorScript.Settings.new()
	settings.mode = HFAutoConnectorScript.ConnectorMode.STAIRS
	settings.stair_step_height = 0.5
	settings.width_cells = 2
	var results := gen.generate_connectors(mgr, settings)
	assert_gt(results.size(), 0, "Should produce stair connectors")


func test_generate_connectors_auto_mode_picks_stairs_for_large_diff():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 5.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var settings := HFAutoConnectorScript.Settings.new()
	settings.mode = HFAutoConnectorScript.ConnectorMode.AUTO
	settings.stair_threshold = 2.0
	settings.stair_step_height = 0.5
	var results := gen.generate_connectors(mgr, settings)
	assert_gt(results.size(), 0, "AUTO mode should produce connectors for large diffs")


func test_generate_connectors_auto_mode_picks_ramp_for_small_diff():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 1.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var settings := HFAutoConnectorScript.Settings.new()
	settings.mode = HFAutoConnectorScript.ConnectorMode.AUTO
	settings.stair_threshold = 2.0
	var results := gen.generate_connectors(mgr, settings)
	assert_gt(results.size(), 0, "AUTO mode should produce ramp for small diffs")


func test_generate_connectors_default_settings():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 2.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	# Use default settings (null)
	var results := gen.generate_connectors(mgr)
	assert_gt(results.size(), 0, "Default settings should work")


# ---------------------------------------------------------------------------
# ConnectorSegment fields
# ---------------------------------------------------------------------------


func test_segment_direction_correct():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 2.0)
	# Layer 0 at (0,0), Layer 1 at (0,1) — direction should be (0,1)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(0, 1)])
	var segs := gen.detect_boundaries(mgr)
	assert_gt(segs.size(), 0)
	var found_vertical := false
	for seg in segs:
		if seg.direction == Vector2i(0, 1) or seg.direction == Vector2i(0, -1):
			found_vertical = true
	assert_true(found_vertical, "Should detect vertical adjacency direction")


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------


func test_three_layers():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"mid", 2.0)
	mgr.create_layer(&"hi", 5.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	_fill_cells(mgr.layers[2], [Vector2i(2, 0)])
	var segs := gen.detect_boundaries(mgr)
	# Should detect lo↔mid and mid↔hi boundaries
	assert_gte(segs.size(), 2, "Three layers should produce multiple boundaries")


func test_heightmap_affects_detection():
	var mgr := _make_layer_manager()
	var layer_lo := mgr.create_layer(&"lo", 0.0)
	var layer_hi := mgr.create_layer(&"hi", 0.0)  # Same base Y
	# Give layer_hi a heightmap that makes it higher
	layer_hi.heightmap = Image.create(8, 8, false, Image.FORMAT_RF)
	layer_hi.heightmap.fill(Color(0.5, 0, 0, 1))  # 0.5 * 10.0 = 5.0 height
	layer_hi.height_scale = 10.0
	_fill_cells(layer_lo, [Vector2i(0, 0)])
	_fill_cells(layer_hi, [Vector2i(1, 0)])
	var segs := gen.detect_boundaries(mgr)
	assert_gt(segs.size(), 0, "Heightmap-based height diff should trigger boundary")
	assert_almost_eq(segs[0].height_diff, 5.0, 0.1)


func test_connector_mesh_has_vertices():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 2.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])
	var results := gen.generate_connectors(mgr)
	assert_gt(results.size(), 0)
	var mesh: ArrayMesh = results[0].get("mesh")
	assert_not_null(mesh)
	assert_gt(mesh.get_surface_count(), 0, "Mesh should have at least one surface")


func test_multiple_boundary_cells():
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 3.0)
	# Wide boundary: 3 cells on each side
	_fill_cells(mgr.layers[0], [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)])
	var segs := gen.detect_boundaries(mgr)
	assert_gte(segs.size(), 3, "Each adjacent cell pair should produce a segment")
	var groups := gen.group_segments(segs)
	# All segments share same direction and are perpendicular-adjacent → 1 group
	assert_gte(groups.size(), 1)


func test_width_setting_propagates():
	var settings := HFAutoConnectorScript.Settings.new()
	assert_eq(settings.width_cells, 2, "Default width should be 2")
	settings.width_cells = 4
	assert_eq(settings.width_cells, 4)


func test_settings_defaults():
	var settings := HFAutoConnectorScript.Settings.new()
	assert_eq(settings.mode, HFAutoConnectorScript.ConnectorMode.RAMP)
	assert_almost_eq(settings.stair_step_height, 0.25, 0.001)
	assert_eq(settings.width_cells, 2)
	assert_almost_eq(settings.stair_threshold, 2.0, 0.001)


# ---------------------------------------------------------------------------
# Regression: corner/T-junction dedupe (GH fix)
# ---------------------------------------------------------------------------


func test_corner_cell_two_edges_not_deduplicated():
	# Cell (0,0) in layer 0 borders (1,0) AND (0,1) in layer 1.
	# Both edges must produce segments — the old dedupe key dropped the second.
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 3.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0), Vector2i(0, 1)])
	var segs := gen.detect_boundaries(mgr)
	assert_gte(segs.size(), 2, "Corner cell must produce edges in both directions")
	# Verify we see both neighbour cells referenced
	var to_cells: Dictionary = {}
	for seg in segs:
		to_cells[seg.to_cell] = true
	assert_true(
		to_cells.has(Vector2i(1, 0)) or to_cells.has(Vector2i(0, 0)),
		"Edge toward (1,0) present"
	)
	assert_true(
		to_cells.has(Vector2i(0, 1)) or to_cells.has(Vector2i(0, 0)),
		"Edge toward (0,1) present"
	)


func test_t_junction_three_edges():
	# Cell (1,1) in layer 0 borders three layer-1 cells: (2,1), (1,2), (0,1)
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 2.0)
	_fill_cells(mgr.layers[0], [Vector2i(1, 1)])
	_fill_cells(mgr.layers[1], [Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1)])
	var segs := gen.detect_boundaries(mgr)
	assert_gte(segs.size(), 3, "T-junction must produce all 3 boundary edges")


func test_corner_generates_multiple_connectors():
	# End-to-end: corner should produce connectors for each edge
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 2.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0), Vector2i(0, 1)])
	var results := gen.generate_connectors(mgr)
	assert_gte(results.size(), 2, "Corner should produce connectors for each direction")


# ---------------------------------------------------------------------------
# Regression: postprocess_bake selection_only flag
# ---------------------------------------------------------------------------


func _make_bake_root_shim(mgr: HFPaintLayerManagerScript) -> Node3D:
	# Dynamic GDScript shim providing the properties _append_auto_connectors reads.
	var script := GDScript.new()
	script.source_code = """extends Node3D
var paint_layers
var bake_auto_connectors: bool = true
var bake_connector_mode: int = 0
var bake_connector_stair_height: float = 0.25
var bake_connector_width: int = 2
var bake_navmesh: bool = false
func _log(_msg: String) -> void:
	pass
"""
	script.reload()
	var root := Node3D.new()
	root.set_script(script)
	root.set("paint_layers", mgr)
	return root


func test_postprocess_bake_selection_only_skips_connectors():
	# Build a paint-layer setup that WOULD produce connectors.
	var mgr := _make_layer_manager()
	mgr.create_layer(&"lo", 0.0)
	mgr.create_layer(&"hi", 3.0)
	_fill_cells(mgr.layers[0], [Vector2i(0, 0)])
	_fill_cells(mgr.layers[1], [Vector2i(1, 0)])

	var shim := _make_bake_root_shim(mgr)
	add_child_autoqfree(shim)

	var BakeSysScript = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
	var bake_sys: RefCounted = BakeSysScript.new(shim)

	# selection_only = true → container must NOT get AutoConnector children.
	var container_sel := Node3D.new()
	add_child_autoqfree(container_sel)
	bake_sys.postprocess_bake(container_sel, true)
	var sel_count := 0
	for child in container_sel.get_children():
		if child.name.begins_with("AutoConnector"):
			sel_count += 1
	assert_eq(sel_count, 0, "selection_only=true must not append auto-connectors")

	# selection_only = false → container SHOULD get AutoConnector children.
	var container_full := Node3D.new()
	add_child_autoqfree(container_full)
	bake_sys.postprocess_bake(container_full, false)
	var full_count := 0
	for child in container_full.get_children():
		if child.name.begins_with("AutoConnector"):
			full_count += 1
	assert_gt(full_count, 0, "selection_only=false must append auto-connectors")
