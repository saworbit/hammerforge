extends GutTest
## Shape-palette icon regressions. Every palette entry must use a real,
## HammerForge-owned shape icon instead of Godot's iconless fallback dot.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const SHAPE_ICON_DIR := "res://addons/hammerforge/icons/shapes/"
const SUPPORTED_PALETTE_SHAPES := [
	LevelRootType.BrushShape.BOX,
	LevelRootType.BrushShape.CYLINDER,
	LevelRootType.BrushShape.SPHERE,
	LevelRootType.BrushShape.CONE,
	LevelRootType.BrushShape.WEDGE,
	LevelRootType.BrushShape.PYRAMID,
	LevelRootType.BrushShape.PRISM_TRI,
	LevelRootType.BrushShape.PRISM_PENT,
	LevelRootType.BrushShape.ELLIPSOID,
	LevelRootType.BrushShape.CAPSULE,
	LevelRootType.BrushShape.TORUS,
	LevelRootType.BrushShape.TETRAHEDRON,
	LevelRootType.BrushShape.OCTAHEDRON,
	LevelRootType.BrushShape.DODECAHEDRON,
	LevelRootType.BrushShape.ICOSAHEDRON,
]

var dock: HammerForgeDock


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)


func after_each() -> void:
	dock = null


func test_shape_palette_exposes_only_supported_drawable_shapes() -> void:
	var palette_shape_ids: Array[int] = []
	for item_index in range(dock.shape_select.get_item_count()):
		palette_shape_ids.append(dock.shape_select.get_item_id(item_index))

	assert_eq(
		palette_shape_ids,
		SUPPORTED_PALETTE_SHAPES,
		"The palette should expose every drawable BrushShape in enum order",
	)
	assert_does_not_have(
		palette_shape_ids,
		LevelRootType.BrushShape.CUSTOM,
		"CUSTOM is produced by Polygon/Path tools and must not appear as a primitive",
	)


func test_sides_row_is_visible_only_for_pyramid() -> void:
	for shape_id in SUPPORTED_PALETTE_SHAPES:
		dock._set_active_shape(shape_id)
		assert_eq(
			dock.sides_row.visible,
			shape_id == LevelRootType.BrushShape.PYRAMID,
			"Sides should only be configurable for Pyramid (shape %d)" % shape_id,
		)


func test_every_brush_shape_used_by_palette_has_a_real_icon() -> void:
	var palette_count := dock.shape_select.get_item_count()
	assert_gt(palette_count, 0, "The shape palette should not be empty")

	for item_index in range(palette_count):
		var shape_id := dock.shape_select.get_item_id(item_index)
		assert_has(
			SUPPORTED_PALETTE_SHAPES,
			shape_id,
			"Palette item %d should map to a supported drawable shape" % item_index,
		)
		var shape_key := str(dock.shape_id_to_key.get(shape_id, ""))
		assert_ne(shape_key, "", "Palette item %d should map back to a shape key" % item_index)
		if shape_key.is_empty():
			continue

		var resolved_icon := dock._resolve_shape_icon(shape_key)
		assert_not_null(resolved_icon, "%s should resolve to a texture" % shape_key)
		if not resolved_icon:
			continue

		assert_gt(resolved_icon.get_width(), 0, "%s icon should have width" % shape_key)
		assert_gt(resolved_icon.get_height(), 0, "%s icon should have height" % shape_key)
		assert_true(
			resolved_icon.resource_path.begins_with(SHAPE_ICON_DIR),
			"%s should use a HammerForge shape icon, not a fallback dot" % shape_key,
		)
		assert_false(
			resolved_icon.resource_path.to_lower().contains("dot"),
			"%s should not resolve to a dot placeholder" % shape_key,
		)

		var palette_icon := dock.shape_select.get_item_icon(item_index)
		assert_not_null(palette_icon, "%s palette entry should display its icon" % shape_key)
		assert_eq(
			palette_icon,
			resolved_icon,
			"%s palette entry should use the resolved shape icon" % shape_key,
		)
