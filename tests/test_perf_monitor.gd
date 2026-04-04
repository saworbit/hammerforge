extends GutTest

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")

var root: Node3D


func before_each():
	root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.grid_snap = 1.0
	add_child(root)


func after_each():
	root.free()
	root = null


func test_get_entity_count_zero():
	assert_eq(root.get_entity_count(), 0)


func test_get_entity_count_with_entities():
	if root.entities_node:
		var e1 = Node3D.new()
		root.entities_node.add_child(e1)
		var e2 = Node3D.new()
		root.entities_node.add_child(e2)
		assert_eq(root.get_entity_count(), 2)


func test_get_total_vertex_estimate_zero():
	assert_eq(root.get_total_vertex_estimate(), 0)


func test_get_recommended_chunk_size_small_level():
	# With < 30 brushes, should return 0 (no chunking needed)
	var rec: float = root.get_recommended_chunk_size()
	assert_eq(rec, 0.0, "Small levels need no chunking")


func test_get_level_health_empty():
	var health: Dictionary = root.get_level_health()
	assert_eq(health["label"], "Healthy")
	assert_eq(health["severity"], 0)


func test_compute_level_aabb_empty():
	var aabb: AABB = root._compute_level_aabb()
	assert_eq(aabb.size, Vector3.ZERO)
