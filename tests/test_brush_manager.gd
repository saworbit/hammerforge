extends GutTest
## BrushManager is a legacy list mirror. It must not own brush lifetime.

const BrushManagerType = preload("res://addons/hammerforge/brush_manager.gd")


func test_clear_brushes_does_not_free_nodes():
	var manager = BrushManagerType.new()
	add_child_autoqfree(manager)
	var brush = Node3D.new()
	add_child_autoqfree(brush)
	manager.add_brush(brush)
	assert_eq(manager.brushes.size(), 1)
	manager.clear_brushes()
	assert_eq(manager.brushes.size(), 0)
	assert_true(is_instance_valid(brush), "HFBrushSystem owns node lifetime, not BrushManager")
	assert_true(brush.is_inside_tree())
