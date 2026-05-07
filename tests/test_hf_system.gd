extends GutTest

const HFSystem = preload("res://addons/hammerforge/systems/hf_system.gd")

var root: Node3D


func before_each():
	root = Node3D.new()
	add_child_autoqfree(root)


func test_init_assigns_root():
	var sys = HFSystem.new(root)
	assert_eq(sys.root, root)


func test_default_enabled_is_true():
	var sys = HFSystem.new(root)
	assert_true(sys.is_enabled())


func test_set_enabled_toggles():
	var sys = HFSystem.new(root)
	sys.set_enabled(false)
	assert_false(sys.is_enabled())
	sys.set_enabled(true)
	assert_true(sys.is_enabled())


func test_destroy_is_safe_to_call():
	var sys = HFSystem.new(root)
	sys.destroy()  # default impl is no-op; must not error


func test_clear_is_safe_to_call():
	var sys = HFSystem.new(root)
	sys.clear()


func test_has_nodes_with_missing_property():
	var sys = HFSystem.new(root)
	# Plain Node3D doesn't have these named props, so should return false
	assert_false(sys._has_nodes(["draft_brushes_node"]))


func test_has_nodes_with_null_root():
	var sys = HFSystem.new(null)
	assert_false(sys._has_nodes(["anything"]))


func test_subclass_can_extend_and_override():
	var script = GDScript.new()
	script.source_code = (
		'extends "res://addons/hammerforge/systems/hf_system.gd"\n'
		+ "var clear_called := false\n"
		+ "func clear() -> void:\n"
		+ "    clear_called = true\n"
	)
	script.reload()
	var sub = script.new(root)
	assert_eq(sub.root, root, "inherited root assignment works")
	sub.clear()
	assert_true(sub.clear_called, "override invoked")
