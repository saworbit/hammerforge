extends GutTest

const HFValidation = preload("res://addons/hammerforge/hf_validation.gd")

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func test_is_valid_root_returns_false_for_null():
	assert_false(HFValidation.is_valid_root(null))


func test_is_valid_root_true_for_real_node():
	assert_true(HFValidation.is_valid_root(root))


func test_has_draft_containers_true_when_present():
	assert_true(HFValidation.has_draft_containers(root))


func test_has_draft_containers_false_when_missing():
	root.draft_brushes_node = null
	assert_false(HFValidation.has_draft_containers(root))


func test_has_entity_container_false_when_missing():
	assert_true(HFValidation.has_entity_container(root), "a level has one")
	root.entities_node = null
	assert_false(HFValidation.has_entity_container(root))


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
