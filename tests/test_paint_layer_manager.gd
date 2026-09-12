extends GutTest

const HFPaintLayerManagerScript = preload(
	"res://addons/hammerforge/paint/hf_paint_layer_manager.gd"
)

var mgr


func before_each():
	mgr = HFPaintLayerManagerScript.new()
	add_child_autoqfree(mgr)
	mgr.clear_layers()


func after_each():
	mgr = null


# ===========================================================================
# The active layer survives a removal below it (#432)
# ===========================================================================


func test_removing_a_layer_below_the_active_one_keeps_the_active_layer():
	mgr.create_layer(&"layer_0", 0.0)
	mgr.create_layer(&"upper", 32.0)
	mgr.create_layer(&"roof", 64.0)
	mgr.set_active_layer(1)
	assert_eq(mgr.get_active_layer().layer_id, &"upper")
	mgr.remove_layer(0)
	assert_eq(mgr.get_active_layer().layer_id, &"upper", "Paint target does not move")


func test_removing_a_layer_above_the_active_one_keeps_the_active_layer():
	mgr.create_layer(&"layer_0", 0.0)
	mgr.create_layer(&"upper", 32.0)
	mgr.create_layer(&"roof", 64.0)
	mgr.set_active_layer(1)
	mgr.remove_layer(2)
	assert_eq(mgr.get_active_layer().layer_id, &"upper", "Paint target does not move")


func test_removing_the_active_layer_falls_back_inside_the_list():
	mgr.create_layer(&"layer_0", 0.0)
	mgr.create_layer(&"upper", 32.0)
	mgr.set_active_layer(1)
	mgr.remove_layer(1)
	assert_eq(mgr.active_layer_index, 0)
	assert_eq(mgr.get_active_layer().layer_id, &"layer_0")


func test_removing_the_last_layer_leaves_no_active_layer():
	mgr.create_layer(&"layer_0", 0.0)
	mgr.remove_layer(0)
	assert_eq(mgr.layers.size(), 0)
	assert_null(mgr.get_active_layer())


# ===========================================================================
# Layer ids are unique (#433)
# ===========================================================================


func test_a_repeated_layer_id_is_uniquified():
	mgr.create_layer(&"roof", 0.0)
	var second = mgr.create_layer(&"roof", 32.0)
	assert_eq(second.layer_id, &"roof_2", "The second layer gets its own id")
	assert_eq(second.name, "Layer_roof_2", "The node name follows the id and stays readable")
	assert_push_warning("is taken")


func test_a_third_repeat_keeps_counting():
	mgr.create_layer(&"roof", 0.0)
	mgr.create_layer(&"roof", 32.0)
	var third = mgr.create_layer(&"roof", 64.0)
	assert_eq(third.layer_id, &"roof_3")
	var ids := {}
	for layer in mgr.layers:
		ids[layer.layer_id] = true
	assert_eq(ids.size(), 3, "Three layers, three ids")


func test_a_free_layer_id_is_used_as_given():
	mgr.create_layer(&"roof", 0.0)
	var other = mgr.create_layer(&"basement", 32.0)
	assert_eq(other.layer_id, &"basement")
	assert_eq(other.name, "Layer_basement")


func test_has_layer_id_answers_for_both():
	mgr.create_layer(&"roof", 0.0)
	assert_true(mgr.has_layer_id(&"roof"))
	assert_false(mgr.has_layer_id(&"cellar"))
