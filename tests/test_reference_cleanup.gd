extends GutTest

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFVisgroupSystem = preload("res://addons/hammerforge/systems/hf_visgroup_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

var root: Node3D
var brush_sys: HFBrushSystem
var entity_sys: HFEntitySystem
var visgroup_sys: HFVisgroupSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	root.pending_node = null
	root.committed_node = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	visgroup_sys = HFVisgroupSystem.new(root)
	root.visgroup_system = visgroup_sys
	entity_sys = HFEntitySystem.new(root)
	root.entity_system = entity_sys
	brush_sys = HFBrushSystem.new(root)


func after_each():
	root = null
	brush_sys = null
	entity_sys = null
	visgroup_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text: String, level: int)

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var entities_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var visgroup_system = null
var entity_system = null

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, ICOSAHEDRON, DODECAHEDRON }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(msg: String) -> void:
	pass

func _assign_owner(node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass

func tag_full_reconcile() -> void:
	pass
"""
	s.reload()
	return s


func _make_brush(
	pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(32, 32, 32), brush_id: String = ""
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	brush_sys._register_brush_id(brush_id, b)
	return b


func _make_entity(entity_name: String) -> DraftEntity:
	var e = DraftEntity.new()
	e.name = entity_name
	e.set_meta("entity_name", entity_name)
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	return e


# ===========================================================================
# Group cleanup
# ===========================================================================


func test_delete_brush_cleans_group_membership():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "g1")
	visgroup_sys.group_selection("mygroup", [b])
	assert_eq(visgroup_sys.get_group_members("mygroup").size(), 1)
	brush_sys.delete_brush(b)
	assert_eq(visgroup_sys.get_group_members("mygroup").size(), 0)


func test_delete_brush_cleans_empty_group():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "g2")
	visgroup_sys.group_selection("tempgroup", [b])
	assert_true(visgroup_sys.groups.has("tempgroup"))
	brush_sys.delete_brush(b)
	assert_false(visgroup_sys.groups.has("tempgroup"), "Empty group should be removed")


# ===========================================================================
# Visgroup cleanup
# ===========================================================================


func test_delete_brush_clears_visgroup_meta():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "v1")
	visgroup_sys.create_visgroup("lights")
	visgroup_sys.add_to_visgroup(b, "lights")
	assert_eq(visgroup_sys.get_members_of("lights").size(), 1)
	brush_sys.delete_brush(b)
	# After deletion, the visgroup should have no members
	assert_eq(visgroup_sys.get_members_of("lights").size(), 0)


# ===========================================================================
# Entity I/O cleanup
# ===========================================================================


func test_delete_entity_cleans_io_connections():
	var src = _make_entity("trigger1")
	var tgt = _make_entity("door1")
	entity_sys.add_entity_output(src, "OnTrigger", "door1", "Open")
	assert_eq(entity_sys.get_entity_outputs(src).size(), 1)
	var removed = entity_sys.cleanup_dangling_connections("door1")
	assert_eq(removed, 1)
	assert_eq(entity_sys.get_entity_outputs(src).size(), 0)


func test_cleanup_preserves_unrelated_connections():
	var src = _make_entity("trigger2")
	_make_entity("door2")
	_make_entity("light1")
	entity_sys.add_entity_output(src, "OnTrigger", "door2", "Open")
	entity_sys.add_entity_output(src, "OnTrigger", "light1", "TurnOn")
	assert_eq(entity_sys.get_entity_outputs(src).size(), 2)
	entity_sys.cleanup_dangling_connections("door2")
	assert_eq(entity_sys.get_entity_outputs(src).size(), 1)
	assert_eq(entity_sys.get_entity_outputs(src)[0]["target_name"], "light1")


func test_cleanup_returns_accurate_count():
	var src1 = _make_entity("t1")
	var src2 = _make_entity("t2")
	_make_entity("target")
	entity_sys.add_entity_output(src1, "OnUse", "target", "Open")
	entity_sys.add_entity_output(src2, "OnTouch", "target", "Close")
	var removed = entity_sys.cleanup_dangling_connections("target")
	assert_eq(removed, 2)


func test_cleanup_no_connections_returns_zero():
	_make_entity("lonely")
	var removed = entity_sys.cleanup_dangling_connections("lonely")
	assert_eq(removed, 0)


func test_delete_with_no_references_no_crash():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "plain")
	brush_sys.delete_brush(b)
	# No crash, no error — just works
	assert_true(true)
