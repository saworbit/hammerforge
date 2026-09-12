extends GutTest

const HFScatterBrushScript = preload("res://addons/hammerforge/paint/hf_scatter_brush.gd")
const HFPaintLayerScript = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGridScript = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

var layer: HFPaintLayerScript


func before_each():
	layer = HFPaintLayerScript.new()
	layer.grid = HFPaintGridScript.new()
	layer.grid.cell_size = 1.0
	layer.chunk_size = 8
	add_child_autoqfree(layer)
	# Fill a 10x10 area
	for y in range(10):
		for x in range(10):
			layer.set_cell(Vector2i(x, y), true)


func after_each():
	layer = null


# ===========================================================================
# ScatterSettings defaults
# ===========================================================================


func test_default_settings():
	var s := HFScatterBrushScript.ScatterSettings.new()
	assert_eq(s.density, 0.5)
	assert_eq(s.radius, 5.0)
	assert_eq(s.shape, HFScatterBrushScript.BrushShape.CIRCLE)
	assert_eq(s.max_slope, 45.0)
	assert_eq(s.random_rotation, true)
	assert_eq(s.align_to_normal, false)


# ===========================================================================
# Circle scatter
# ===========================================================================


func test_scatter_circle_produces_transforms():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.density = 1.0
	settings.radius = 3.0
	settings.seed = 42
	var result := brush.scatter_circle(Vector3(5, 0, 5), layer, settings)
	assert_gt(result.transforms.size(), 0, "Should produce scatter instances")
	assert_gt(result.total_candidates, 0)


func test_scatter_circle_empty_layer():
	var empty_layer := HFPaintLayerScript.new()
	empty_layer.grid = HFPaintGridScript.new()
	empty_layer.chunk_size = 8
	add_child_autoqfree(empty_layer)
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.seed = 42
	var result := brush.scatter_circle(Vector3.ZERO, empty_layer, settings)
	# May produce transforms (height filter doesn't require filled cells in circle mode)
	assert_eq(result.total_candidates > 0, true)


func test_scatter_circle_null_layer():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	var result := brush.scatter_circle(Vector3.ZERO, null, settings)
	assert_eq(result.transforms.size(), 0)


func test_scatter_circle_deterministic():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.density = 0.5
	settings.radius = 3.0
	settings.seed = 123
	var r1 := brush.scatter_circle(Vector3(5, 0, 5), layer, settings)
	var r2 := brush.scatter_circle(Vector3(5, 0, 5), layer, settings)
	assert_eq(r1.transforms.size(), r2.transforms.size(), "Same seed should produce same count")
	if r1.transforms.size() > 0:
		assert_eq(
			r1.transforms[0].origin,
			r2.transforms[0].origin,
			"Same seed should produce same positions"
		)


# ===========================================================================
# Height filtering
# ===========================================================================


func test_scatter_height_filter():
	# Create a heightmap that lifts some cells high
	var img := Image.create(16, 16, false, Image.FORMAT_RF)
	for y in range(16):
		for x in range(16):
			img.set_pixel(x, y, Color(0.5, 0, 0, 1))  # height = 0.5 * scale
	layer.heightmap = img
	layer.height_scale = 10.0  # effective height = 5.0

	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.density = 2.0
	settings.radius = 3.0
	settings.seed = 42
	settings.min_height = 10.0  # Filter out all (height is 5.0)
	settings.max_height = 20.0
	var result := brush.scatter_circle(Vector3(5, 0, 5), layer, settings)
	assert_eq(result.transforms.size(), 0, "All should be filtered by min_height")
	assert_gt(result.rejected_count, 0, "Should have rejections")


# ===========================================================================
# Slope filtering
# ===========================================================================


func test_scatter_slope_filter():
	# Create a steep heightmap
	var img := Image.create(16, 16, false, Image.FORMAT_RF)
	for y in range(16):
		for x in range(16):
			img.set_pixel(x, y, Color(float(x) / 16.0, 0, 0, 1))
	layer.heightmap = img
	layer.height_scale = 100.0  # very steep

	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.density = 2.0
	settings.radius = 3.0
	settings.seed = 42
	settings.max_slope = 1.0  # Very restrictive
	var result := brush.scatter_circle(Vector3(5, 0, 5), layer, settings)
	# Most or all should be rejected due to steep slope
	assert_gt(result.rejected_count, 0, "Should reject steep areas")


# ===========================================================================
# Spline scatter
# ===========================================================================


func test_scatter_spline_basic():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.density = 1.0
	settings.spline_width = 2.0
	settings.seed = 42
	settings.spline_points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)]
	)
	var result := brush.scatter_spline(layer, settings)
	assert_gt(result.transforms.size(), 0, "Spline scatter should produce instances")


func test_scatter_spline_too_few_points():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.spline_points = PackedVector3Array([Vector3.ZERO])
	var result := brush.scatter_spline(layer, settings)
	assert_eq(result.transforms.size(), 0, "Need at least 2 spline points")


# ===========================================================================
# Preview MultiMesh
# ===========================================================================


func test_build_preview_dots():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.preview_mode = HFScatterBrushScript.PreviewMode.DOTS
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3.ZERO)]
	var mm := brush.build_preview(transforms, settings)
	assert_not_null(mm)
	assert_eq(mm.instance_count, 1)


func test_build_preview_empty():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	var transforms: Array[Transform3D] = []
	var mm := brush.build_preview(transforms, settings)
	assert_null(mm, "Should return null for empty transforms")


func test_build_preview_wireframe():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.preview_mode = HFScatterBrushScript.PreviewMode.WIREFRAME
	# No mesh set — should fallback to dot
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3.ZERO)]
	var mm := brush.build_preview(transforms, settings)
	assert_not_null(mm)
	assert_not_null(mm.mesh)


# ===========================================================================
# Commit
# ===========================================================================


func test_commit_creates_mmi():
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.mesh = BoxMesh.new()
	var transforms: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1, 0, 1)),
		Transform3D(Basis.IDENTITY, Vector3(3, 0, 3)),
	]
	var mmi := brush.commit(transforms, settings, parent)
	assert_not_null(mmi)
	assert_eq(mmi.multimesh.instance_count, 2)
	assert_eq(mmi.get_parent(), parent)
	mmi.free()


func test_commit_no_mesh_returns_null():
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	# No mesh
	var transforms: Array[Transform3D] = [Transform3D.IDENTITY]
	var mmi := brush.commit(transforms, settings, parent)
	assert_null(mmi)


# ===========================================================================
# Scale range
# ===========================================================================


func test_scatter_scale_variation():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.density = 5.0
	settings.radius = 3.0
	settings.seed = 42
	settings.scale_range = Vector2(0.5, 2.0)
	var result := brush.scatter_circle(Vector3(5, 0, 5), layer, settings)
	if result.transforms.size() >= 2:
		# With wide scale range, scales should vary
		var s1 := result.transforms[0].basis.get_scale()
		var s2 := result.transforms[1].basis.get_scale()
		# At least one should differ (probabilistic but with wide range + seed 42)
		var differs := not s1.is_equal_approx(s2)
		assert_true(differs or result.transforms.size() < 2, "Scales should vary with range")


# ===========================================================================
# Align to normal (#429)
# ===========================================================================


func test_align_to_normal_points_up_on_flat_ground():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.seed = 4242
	settings.radius = 3.0
	settings.density = 1.0
	settings.align_to_normal = true
	settings.random_rotation = false
	var result = brush.scatter_circle(Vector3(4, 0, 4), layer, settings)
	assert_gt(result.transforms.size(), 0, "Flat ground should place instances")
	for xform in result.transforms:
		assert_gt(xform.basis.y.normalized().y, 0.9, "Instance up vector points up, not down")


# ===========================================================================
# Instance cap (#430)
# ===========================================================================


func test_scatter_circle_refuses_an_oversized_stroke():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.radius = 1000.0
	settings.density = 1.0
	settings.max_slope = 90.0
	var result = brush.scatter_circle(Vector3.ZERO, layer, settings)
	assert_not_null(result.refusal, "A three million instance stroke is refused")
	assert_false(result.refusal.ok)
	assert_eq(result.transforms.size(), 0, "Nothing is laid out when the stroke is refused")
	assert_string_contains(result.refusal.fix_hint, str(HFScatterBrushScript.MAX_SCATTER_INSTANCES))


func test_scatter_spline_refuses_an_oversized_stroke():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.shape = HFScatterBrushScript.BrushShape.SPLINE
	settings.spline_points = PackedVector3Array([Vector3.ZERO, Vector3(100000, 0, 0)])
	settings.spline_width = 10.0
	settings.density = 1.0
	var result = brush.scatter_spline(layer, settings)
	assert_not_null(result.refusal, "A million instance path is refused")
	assert_eq(result.transforms.size(), 0)


func test_scatter_circle_allows_a_normal_stroke():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.radius = 5.0
	settings.density = 0.5
	var result = brush.scatter_circle(Vector3(4, 0, 4), layer, settings)
	assert_null(result.refusal, "A normal stroke is not refused")


# ===========================================================================
# Ownership (#431)
# ===========================================================================


func test_commit_owns_the_node_so_the_scene_keeps_it():
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	parent.owner = self
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.mesh = BoxMesh.new()
	var transforms: Array[Transform3D] = [Transform3D.IDENTITY]
	var mmi := brush.commit(transforms, settings, parent)
	assert_not_null(mmi)
	assert_eq(mmi.owner, parent.owner, "Committed node inherits the level's owner")
	mmi.free()


func test_build_instance_leaves_the_node_unparented():
	var brush := HFScatterBrushScript.new()
	var settings := HFScatterBrushScript.ScatterSettings.new()
	settings.mesh = BoxMesh.new()
	var transforms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
	var mmi := brush.build_instance(transforms, settings)
	assert_not_null(mmi)
	assert_null(mmi.get_parent(), "The caller parents it, inside an undo action")
	assert_eq(mmi.multimesh.instance_count, 2)
	mmi.free()
