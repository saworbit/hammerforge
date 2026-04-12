extends GutTest
## Dock-level integration tests for terrain/scatter/heightmap handlers.
## These test the dock handler methods (_on_heightmap_convert, _on_scatter_*,
## _build_scatter_settings, _get_active_paint_layer) that wire lower-level
## helpers through the real paint_layers and paint_system APIs.
##
## Uses a real LevelRoot (not a shim) because dock.level_root is typed as
## LevelRootType and GDScript enforces this at runtime.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var dock: HammerForgeDock
var _paint_layer_changed_idx: int = -1


func before_each():
	# Real LevelRoot — _ready builds all subsystems, containers, paint manager.
	# Disable runtime startup so headless tests don't trigger bake/playtest orphans.
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)

	# Track paint_layer_changed signal
	_paint_layer_changed_idx = -1
	root.paint_layer_changed.connect(_on_paint_layer_changed_test)

	# Dock instance — do NOT add_child (triggers _ready → scene node lookups).
	dock = HammerForgeDock.new()
	dock.level_root = root
	dock._selection_nodes = []


func after_each():
	if (
		is_instance_valid(root)
		and root.paint_layer_changed.is_connected(_on_paint_layer_changed_test)
	):
		root.paint_layer_changed.disconnect(_on_paint_layer_changed_test)
	if dock and is_instance_valid(dock):
		dock.free()
	dock = null
	root = null


func _on_paint_layer_changed_test(index: int) -> void:
	_paint_layer_changed_idx = index


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_brush(pos: Vector3, sz: Vector3) -> DraftBrush:
	var b := DraftBrush.new()
	b.size = sz
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	return b


func _get_mgr() -> HFPaintLayerManager:
	return root.paint_layers


func _make_spin(min_val: float, max_val: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_val
	s.max_value = max_val
	s.step = 0.01
	s.value = val
	add_child_autoqfree(s)
	return s


func _setup_scatter_ui() -> void:
	# Create minimal UI controls the scatter handlers read.
	# Must set min_value/max_value before value — raw SpinBox defaults to [0,100]
	# and clamps assigned values outside that range.
	dock.scatter_density_spin = _make_spin(0.01, 100.0, 1.0)
	dock.scatter_radius_spin = _make_spin(0.1, 1000.0, 3.0)
	dock.scatter_min_height_spin = _make_spin(-10000.0, 10000.0, -1000.0)
	dock.scatter_max_height_spin = _make_spin(-10000.0, 10000.0, 1000.0)
	dock.scatter_max_slope_spin = _make_spin(0.0, 90.0, 45.0)
	dock.scatter_scale_min_spin = _make_spin(0.01, 10.0, 0.8)
	dock.scatter_scale_max_spin = _make_spin(0.01, 10.0, 1.2)

	dock.scatter_align_normal = CheckBox.new()
	dock.scatter_align_normal.button_pressed = false
	add_child_autoqfree(dock.scatter_align_normal)

	dock.scatter_random_rotation = CheckBox.new()
	dock.scatter_random_rotation.button_pressed = true
	add_child_autoqfree(dock.scatter_random_rotation)

	dock.scatter_shape_select = OptionButton.new()
	dock.scatter_shape_select.add_item("Circle", 0)
	dock.scatter_shape_select.add_item("Spline", 1)
	dock.scatter_shape_select.selected = 0
	add_child_autoqfree(dock.scatter_shape_select)

	dock.scatter_spline_width_spin = _make_spin(0.1, 1000.0, 3.0)

	dock.scatter_preview_select = OptionButton.new()
	dock.scatter_preview_select.add_item("Dots", 0)
	dock.scatter_preview_select.add_item("Wireframe", 1)
	dock.scatter_preview_select.add_item("Full", 2)
	dock.scatter_preview_select.selected = 0
	add_child_autoqfree(dock.scatter_preview_select)


# ===========================================================================
# _get_active_paint_layer
# ===========================================================================


func test_get_active_paint_layer_returns_layer():
	var layer := dock._get_active_paint_layer()
	assert_not_null(layer, "Should return the active layer from paint_layers")


func test_get_active_paint_layer_null_without_root():
	dock.level_root = null
	var layer := dock._get_active_paint_layer()
	assert_null(layer, "Should return null when level_root is null")


func test_get_active_paint_layer_null_without_layers():
	var mgr := _get_mgr()
	mgr.clear_layers()
	var layer := dock._get_active_paint_layer()
	assert_null(layer, "Should return null when no layers exist")


# ===========================================================================
# _on_heightmap_convert
# ===========================================================================


func test_heightmap_convert_no_selection():
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()
	dock._selection_nodes = []
	dock._on_heightmap_convert()
	assert_eq(mgr.layers.size(), initial_count, "Should not add layer without selection")


func test_heightmap_convert_basic():
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()
	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	assert_eq(mgr.layers.size(), initial_count + 1, "Should add a converted layer")
	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_not_null(converted, "Converted layer should exist")
	assert_eq(converted.display_name, "Converted Terrain")
	assert_not_null(converted.heightmap, "Converted layer should have a heightmap")


func test_heightmap_convert_inherits_base_grid():
	var mgr := _get_mgr()
	# Set a distinctive origin on base_grid
	if mgr.base_grid:
		mgr.base_grid.origin = Vector3(42, 0, 42)
	var initial_count := mgr.layers.size()

	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_not_null(converted.grid, "Converted layer should have a grid")
	assert_eq(
		converted.grid.origin,
		Vector3(42, 0, 42),
		"Converted grid origin should match base_grid origin"
	)


func test_heightmap_convert_inherits_chunk_size():
	var mgr := _get_mgr()
	mgr.chunk_size = 64
	var initial_count := mgr.layers.size()

	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_eq(
		converted.chunk_size, 64, "Converted layer chunk_size should match manager chunk_size"
	)


func test_heightmap_convert_emits_paint_layer_changed():
	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	assert_gt(_paint_layer_changed_idx, -1, "Should emit paint_layer_changed signal")


func test_heightmap_convert_sets_active_layer():
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()

	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	assert_eq(
		mgr.active_layer_index,
		initial_count,
		"Active layer should be set to the newly converted layer"
	)


func test_heightmap_convert_multiple_brushes():
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()
	var b1 := _make_brush(Vector3(2, 1, 2), Vector3(2, 2, 2))
	var b2 := _make_brush(Vector3(8, 3, 8), Vector3(3, 6, 3))
	dock._selection_nodes = [b1, b2]
	dock._on_heightmap_convert()

	assert_eq(mgr.layers.size(), initial_count + 1)
	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_not_null(converted.heightmap)


func test_heightmap_convert_with_grid_snap():
	root.grid_snap = 2.0
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()

	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_eq(converted.grid.cell_size, 2.0, "cell_size should match grid_snap when > 0")


func test_heightmap_convert_with_height_scale_spin():
	dock.height_scale_spin = SpinBox.new()
	dock.height_scale_spin.value = 25.0
	add_child_autoqfree(dock.height_scale_spin)

	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()

	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_eq(converted.height_scale, 25.0, "height_scale should come from height_scale_spin")


func test_heightmap_convert_layer_is_child_of_manager():
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()

	var b := _make_brush(Vector3(5, 2, 5), Vector3(4, 4, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_eq(
		converted.get_parent(), mgr, "Converted layer should be a child of the paint layer manager"
	)


func test_heightmap_convert_produces_readable_height():
	# Force cell_size=1.0 so the brush footprint maps to predictable cells.
	# Real LevelRoot defaults grid_snap to 16.0, which would collapse the
	# whole brush into a single cell and make per-cell assertions meaningless.
	root.grid_snap = 1.0
	var mgr := _get_mgr()
	var initial_count := mgr.layers.size()

	# Brush at pos=(5,3,5), size=(4,6,4) → AABB x:[3..7], z:[3..7], top Y=6
	var b := _make_brush(Vector3(5, 3, 5), Vector3(4, 6, 4))
	dock._selection_nodes = [b]
	dock._on_heightmap_convert()

	var converted: HFPaintLayer = mgr.layers[initial_count]
	assert_not_null(converted.heightmap, "Layer should have a heightmap")
	assert_true(converted.has_heightmap(), "has_heightmap() should return true")

	# Validate through the public get_height_at() API — the same path the
	# paint system uses to build geometry.  With cell_size=1.0 the brush
	# footprint covers cells roughly in x:[3..7], z:[3..7].
	# Derive sample range from the converted grid to stay robust if the
	# converter adjusts margins or rounding.
	var cell_sz: float = converted.grid.cell_size if converted.grid else 1.0
	var half_x := int(ceil(2.0 / cell_sz))  # brush half-width in X = 2
	var half_z := int(ceil(2.0 / cell_sz))  # brush half-width in Z = 2
	var center_cx := int(floor(5.0 / cell_sz))
	var center_cz := int(floor(5.0 / cell_sz))

	var has_nonzero := false
	for cx in range(center_cx - half_x, center_cx + half_x + 1):
		for cz in range(center_cz - half_z, center_cz + half_z + 1):
			var h: float = converted.get_height_at(Vector2i(cx, cz))
			if h > 0.001:
				has_nonzero = true
				break
		if has_nonzero:
			break
	assert_true(has_nonzero, "get_height_at should return non-zero within the brush footprint")


# ===========================================================================
# _build_scatter_settings
# ===========================================================================


func test_build_scatter_settings_defaults():
	_setup_scatter_ui()
	var s: HFScatterBrush.ScatterSettings = dock._build_scatter_settings()
	assert_eq(s.density, 1.0)
	assert_eq(s.radius, 3.0)
	assert_eq(s.min_height, -1000.0)
	assert_eq(s.max_height, 1000.0)
	assert_eq(s.max_slope, 45.0)
	assert_eq(s.scale_range, Vector2(0.8, 1.2))
	assert_true(s.random_rotation)
	assert_false(s.align_to_normal)
	assert_eq(s.shape, HFScatterBrush.BrushShape.CIRCLE)
	assert_eq(s.spline_width, 3.0)
	assert_eq(s.preview_mode, HFScatterBrush.PreviewMode.DOTS)


func test_build_scatter_settings_spline_populates_points():
	_setup_scatter_ui()
	dock.scatter_shape_select.selected = 1  # Spline

	var n1 = Node3D.new()
	add_child_autoqfree(n1)
	n1.global_position = Vector3(0, 0, 0)
	var n2 = Node3D.new()
	add_child_autoqfree(n2)
	n2.global_position = Vector3(10, 0, 10)
	var n3 = Node3D.new()
	add_child_autoqfree(n3)
	n3.global_position = Vector3(20, 0, 0)

	dock._selection_nodes = [n1, n2, n3]

	var s: HFScatterBrush.ScatterSettings = dock._build_scatter_settings()
	assert_eq(s.shape, HFScatterBrush.BrushShape.SPLINE)
	assert_eq(s.spline_points.size(), 3, "Should populate spline points from selection")
	assert_eq(s.spline_points[0], Vector3(0, 0, 0))
	assert_eq(s.spline_points[1], Vector3(10, 0, 10))
	assert_eq(s.spline_points[2], Vector3(20, 0, 0))


func test_build_scatter_settings_circle_no_spline_points():
	_setup_scatter_ui()
	dock.scatter_shape_select.selected = 0  # Circle

	var n1 = Node3D.new()
	add_child_autoqfree(n1)
	dock._selection_nodes = [n1]

	var s: HFScatterBrush.ScatterSettings = dock._build_scatter_settings()
	assert_eq(s.spline_points.size(), 0, "Circle mode should not populate spline_points")


func test_build_scatter_settings_null_controls():
	# All scatter controls are null by default — should not crash
	var s: HFScatterBrush.ScatterSettings = dock._build_scatter_settings()
	assert_not_null(s, "Should return settings even with null controls")


# ===========================================================================
# _on_scatter_preview (circle mode)
# ===========================================================================


func test_scatter_preview_circle():
	_setup_scatter_ui()
	var center_node = Node3D.new()
	add_child_autoqfree(center_node)
	center_node.global_position = Vector3(5, 0, 5)
	dock._selection_nodes = [center_node]

	dock._on_scatter_preview()

	# _scatter_last_result should be set (may be empty if no filled cells)
	assert_true(dock._scatter_last_result is Array, "Should have set _scatter_last_result")


func test_scatter_preview_no_layer():
	_setup_scatter_ui()
	# Remove all layers so _get_active_paint_layer returns null
	_get_mgr().clear_layers()

	dock._on_scatter_preview()

	assert_null(dock._scatter_preview_node, "No preview without active layer")


# ===========================================================================
# _on_scatter_preview (spline mode)
# ===========================================================================


func test_scatter_preview_spline_too_few_points():
	_setup_scatter_ui()
	dock.scatter_shape_select.selected = 1  # Spline

	# Only 1 selection node — insufficient for spline
	var n1 = Node3D.new()
	add_child_autoqfree(n1)
	dock._selection_nodes = [n1]

	dock._on_scatter_preview()

	assert_null(dock._scatter_preview_node, "Should clear preview on insufficient spline points")
	assert_eq(
		dock._scatter_last_result.size(), 0, "Should reset _scatter_last_result on invalid spline"
	)


func test_scatter_preview_spline_clears_stale_state():
	_setup_scatter_ui()

	# First, do a circle preview to create some state
	var center_node = Node3D.new()
	add_child_autoqfree(center_node)
	center_node.global_position = Vector3(5, 0, 5)
	dock._selection_nodes = [center_node]
	dock._on_scatter_preview()

	# Now switch to spline with too few points
	dock.scatter_shape_select.selected = 1  # Spline
	dock._selection_nodes = [center_node]  # Only 1 node

	dock._on_scatter_preview()

	assert_null(dock._scatter_preview_node, "Should clear stale preview on invalid spline")
	assert_eq(dock._scatter_last_result.size(), 0, "Should clear stale result on invalid spline")


func test_scatter_preview_spline_valid():
	_setup_scatter_ui()
	dock.scatter_shape_select.selected = 1  # Spline

	var n1 = Node3D.new()
	add_child_autoqfree(n1)
	n1.global_position = Vector3(0, 0, 0)
	var n2 = Node3D.new()
	add_child_autoqfree(n2)
	n2.global_position = Vector3(10, 0, 0)
	dock._selection_nodes = [n1, n2]

	dock._on_scatter_preview()

	assert_true(
		dock._scatter_last_result is Array, "Should produce scatter result for valid spline"
	)


# ===========================================================================
# _on_scatter_commit
# ===========================================================================


func test_scatter_commit_empty_runs_preview_first():
	_setup_scatter_ui()
	dock._scatter_last_result = []
	var center_node = Node3D.new()
	add_child_autoqfree(center_node)
	center_node.global_position = Vector3(5, 0, 5)
	dock._selection_nodes = [center_node]

	# Commit with empty result triggers an auto-preview pass first.
	# Without filled cells, the auto-preview produces nothing → early return
	# with "No scatter instances" message.  Should not crash.
	dock._on_scatter_commit()
	pass_test("Commit with empty results did not crash")


func test_scatter_commit_no_mesh_returns_early():
	_setup_scatter_ui()

	# Pre-fill transforms but leave mesh unset (_scatter_mesh_path empty)
	dock._scatter_last_result = [Transform3D.IDENTITY]

	# Set up a preview node — should NOT be cleared because the method
	# returns before reaching _scatter_clear_preview() when mesh is missing.
	var fake_preview := MultiMeshInstance3D.new()
	fake_preview.name = "_FakePreview"
	root.add_child(fake_preview)
	dock._scatter_preview_node = fake_preview

	dock._on_scatter_commit()

	# Production code: no mesh → emit warning → return (preview not cleared)
	assert_not_null(dock._scatter_preview_node, "No-mesh early return should leave preview intact")
	# Clean up manually since the test owns this node
	dock._scatter_clear_preview()


func test_scatter_commit_no_mesh_preserves_last_result():
	_setup_scatter_ui()

	# Pre-fill transforms but leave mesh unset.  The no-mesh early return
	# happens AFTER the is_empty check, so _scatter_last_result should be
	# preserved (not cleared) since the commit never actually executes.
	dock._scatter_last_result = [Transform3D.IDENTITY, Transform3D.IDENTITY]

	dock._on_scatter_commit()

	assert_eq(
		dock._scatter_last_result.size(),
		2,
		"No-mesh early return should not clear _scatter_last_result"
	)


# ===========================================================================
# _on_scatter_clear
# ===========================================================================


func test_scatter_clear_removes_preview():
	var preview := MultiMeshInstance3D.new()
	preview.name = "_TestPreview"
	root.add_child(preview)
	dock._scatter_preview_node = preview
	dock._scatter_last_result = [Transform3D.IDENTITY, Transform3D.IDENTITY]

	dock._on_scatter_clear()

	assert_null(dock._scatter_preview_node, "Clear should null the preview node")
	assert_eq(dock._scatter_last_result.size(), 0, "Clear should reset results")


func test_scatter_clear_safe_when_no_preview():
	dock._scatter_preview_node = null
	dock._scatter_last_result = []

	dock._on_scatter_clear()
	assert_null(dock._scatter_preview_node)


# ===========================================================================
# _scatter_clear_preview
# ===========================================================================


func test_scatter_clear_preview_removes_from_tree():
	var preview := MultiMeshInstance3D.new()
	preview.name = "_ClearTest"
	root.add_child(preview)
	dock._scatter_preview_node = preview

	dock._scatter_clear_preview()

	assert_null(dock._scatter_preview_node, "Should null the reference after clearing")
	assert_false(preview.is_inside_tree(), "Preview should be removed from tree")


func test_scatter_clear_preview_already_freed():
	var preview := MultiMeshInstance3D.new()
	preview.name = "_FreedTest"
	root.add_child(preview)
	dock._scatter_preview_node = preview

	# Free it externally
	root.remove_child(preview)
	preview.free()

	# Should handle already-freed node gracefully
	dock._scatter_clear_preview()
	assert_null(dock._scatter_preview_node)
