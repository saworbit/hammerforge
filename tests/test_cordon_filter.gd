extends GutTest

const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var bake_sys: HFBakeSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child(root)
	# Setup containers
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	# Default: cordon disabled
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	bake_sys = HFBakeSystem.new(root)


func after_each():
	root.queue_free()
	bake_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))

func is_entity_node(_node: Node) -> bool:
	return false
"""
	s.reload()
	return s


func _make_brush_at(parent: Node3D, pos: Vector3, sz: Vector3 = Vector3(2, 2, 2)) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	parent.add_child(b)
	b.global_position = pos
	return b


# ===========================================================================
# _brush_in_cordon tests
# ===========================================================================


func test_brush_inside_cordon_returns_true():
	var b = _make_brush_at(root, Vector3(0, 0, 0))
	root.cordon_enabled = true
	assert_true(bake_sys._brush_in_cordon(b), "Brush at origin should be inside default cordon")


func test_brush_outside_cordon_returns_false():
	var b = _make_brush_at(root, Vector3(100, 100, 100))
	root.cordon_enabled = true
	assert_false(bake_sys._brush_in_cordon(b), "Brush far away should be outside cordon")


func test_brush_on_edge_intersects():
	# Cordon is -10 to +10. Brush at (9,0,0) size 2 → AABB (8,-1,-1) to (10,1,1) → intersects
	var b = _make_brush_at(root, Vector3(9, 0, 0))
	root.cordon_enabled = true
	assert_true(bake_sys._brush_in_cordon(b), "Brush overlapping edge should intersect")


func test_brush_just_outside_does_not_intersect():
	# Cordon is -10 to +10. Brush at (12,0,0) size 2 → AABB (11,-1,-1) to (13,1,1) → outside
	var b = _make_brush_at(root, Vector3(12, 0, 0))
	root.cordon_enabled = true
	assert_false(bake_sys._brush_in_cordon(b), "Brush just outside should not intersect")


# ===========================================================================
# collect_chunk_brushes with cordon
# ===========================================================================


func test_collect_without_cordon_gets_all():
	var draft = root.draft_brushes_node
	_make_brush_at(draft, Vector3(0, 0, 0))
	_make_brush_at(draft, Vector3(100, 0, 0))
	_make_brush_at(draft, Vector3(-200, 0, 0))
	root.cordon_enabled = false
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(draft, 32.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 3, "All brushes collected when cordon disabled")


func test_collect_with_cordon_filters():
	var draft = root.draft_brushes_node
	_make_brush_at(draft, Vector3(0, 0, 0))       # inside -10..10
	_make_brush_at(draft, Vector3(100, 0, 0))      # outside
	_make_brush_at(draft, Vector3(-200, 0, 0))     # outside
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(draft, 32.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "Only brush inside cordon should be collected")


func test_collect_with_large_cordon_gets_all():
	var draft = root.draft_brushes_node
	_make_brush_at(draft, Vector3(0, 0, 0))
	_make_brush_at(draft, Vector3(100, 0, 0))
	root.cordon_enabled = true
	root.cordon_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(draft, 32.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 2, "Large cordon should include all brushes")


# ===========================================================================
# chunk_coord utility
# ===========================================================================


func test_chunk_coord_positive():
	var coord = bake_sys.chunk_coord(Vector3(10, 5, 30), 16.0)
	assert_eq(coord, Vector3i(0, 0, 1))


func test_chunk_coord_negative():
	var coord = bake_sys.chunk_coord(Vector3(-10, -5, -30), 16.0)
	assert_eq(coord, Vector3i(-1, -1, -2))


func test_chunk_coord_exact_boundary():
	var coord = bake_sys.chunk_coord(Vector3(16, 0, 0), 16.0)
	assert_eq(coord, Vector3i(1, 0, 0))
