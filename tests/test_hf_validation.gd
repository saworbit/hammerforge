extends GutTest

const HFValidation = preload("res://addons/hammerforge/hf_validation.gd")

var root: Node3D


func before_each():
	root = Node3D.new()
	add_child_autoqfree(root)
	root.set_script(_root_shim_script())
	# Set the named container properties as Node3D children
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft

	var pending = Node3D.new()
	pending.name = "Pending"
	root.add_child(pending)
	root.pending_node = pending


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = (
		"extends Node3D\n"
		+ "var draft_brushes_node: Node3D\n"
		+ "var pending_node: Node3D\n"
		+ "var entities_node: Node3D\n"
		+ "var baked_container: Node3D\n"
	)
	s.reload()
	return s


func test_is_valid_root_returns_false_for_null():
	assert_false(HFValidation.is_valid_root(null))


func test_is_valid_root_true_for_real_node():
	assert_true(HFValidation.is_valid_root(root))


func test_has_draft_containers_true_when_present():
	assert_true(HFValidation.has_draft_containers(root))


func test_has_draft_containers_false_when_missing():
	root.draft_brushes_node = null
	assert_false(HFValidation.has_draft_containers(root))


func test_has_entity_container_false_until_set():
	assert_false(HFValidation.has_entity_container(root))
	var ent = Node3D.new()
	root.add_child(ent)
	root.entities_node = ent
	assert_true(HFValidation.has_entity_container(root))


func test_has_node_by_name():
	assert_true(HFValidation.has_node(root, "draft_brushes_node"))
	assert_false(HFValidation.has_node(root, "nonexistent_node"))


func test_has_nodes_array():
	assert_true(HFValidation.has_nodes(root, ["draft_brushes_node", "pending_node"]), "all present")
	assert_false(
		HFValidation.has_nodes(root, ["draft_brushes_node", "missing_node"]), "one missing"
	)


func test_has_baked_container_false_when_missing():
	assert_false(HFValidation.has_baked_container(root))
	var b = Node3D.new()
	root.add_child(b)
	root.baked_container = b
	assert_true(HFValidation.has_baked_container(root))


func test_require_nodes_logs_missing():
	# Just verifies it returns false without throwing
	var ok = HFValidation.require_nodes(root, ["draft_brushes_node", "missing"], "test_ctx")
	assert_false(ok)


func test_require_nodes_returns_true_when_all_present():
	assert_true(HFValidation.require_nodes(root, ["draft_brushes_node", "pending_node"], "ctx"))
