extends GutTest
## Brush-cache authority: DraftBrush lookup does not depend on BrushManager.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBrushSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.pending_node = null
	root.committed_node = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	root.drag_size_default = Vector3(32, 32, 32)
	sys = HFBrushSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var dirty_brush_ids: Array[String] = []

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(_msg: String) -> void:
	pass

func _assign_owner(_node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass

func tag_brush_dirty(brush_id: String) -> void:
	dirty_brush_ids.append(brush_id)
"""
	s.reload()
	return s


func test_create_from_info_caches_without_brush_manager():
	var brush = sys.create_brush_from_info(
		{"shape": 0, "size": Vector3(16, 16, 16), "center": Vector3(8, 8, 8), "brush_id": "box_1"}
	)
	assert_not_null(brush)
	assert_eq(sys.get_cached_brush_count(), 1)
	assert_eq(sys.find_brush_by_id("box_1"), brush)
	var cached: Array = sys.get_cached_brushes()
	assert_eq(cached.size(), 1)
	assert_eq(cached[0], brush)


func test_delete_removes_from_cache_without_brush_manager():
	sys.create_brush_from_info({"size": Vector3(8, 8, 8), "center": Vector3.ZERO, "brush_id": "a"})
	sys.create_brush_from_info({"size": Vector3(8, 8, 8), "center": Vector3.ONE, "brush_id": "b"})
	assert_eq(sys.get_cached_brush_count(), 2)
	var result = sys.delete_brush_by_id("a")
	assert_true(result.ok)
	assert_null(sys.find_brush_by_id("a"))
	assert_eq(sys.get_cached_brush_count(), 1)
	assert_not_null(sys.find_brush_by_id("b"))


func test_legacy_manager_mirror_stays_optional():
	# Cache remains usable even if a later restore never creates BrushManager.
	var brush = sys.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3.ZERO, "brush_id": "solo"}
	)
	assert_null(root.brush_manager)
	assert_eq(sys.get_cached_brushes(), [brush])
