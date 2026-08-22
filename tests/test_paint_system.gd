extends GutTest
## Focused HFPaintSystem coverage for the core greybox loop.

const HFPaintSystem = preload("res://addons/hammerforge/systems/hf_paint_system.gd")
const HFPaintLayerManager = preload("res://addons/hammerforge/paint/hf_paint_layer_manager.gd")

var root: Node3D
var sys: HFPaintSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	root.paint_layers = autoqfree(HFPaintLayerManager.new())
	sys = HFPaintSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D
var paint_layers
var paint_tool
"""
	s.reload()
	return s


func test_layer_names_empty_without_manager():
	root.paint_layers = null
	assert_eq(sys.get_paint_layer_names(), [])


func test_layer_names_use_display_then_id():
	var floor_layer = root.paint_layers.create_layer(&"floor", 0.0)
	floor_layer.display_name = "Floor"
	var unnamed = root.paint_layers.create_layer(&"layer_1", 1.0)
	unnamed.display_name = ""
	var names: Array = sys.get_paint_layer_names()
	assert_eq(names.size(), 2)
	assert_eq(names[0], "Floor")
	assert_eq(str(names[1]), "layer_1")
