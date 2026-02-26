extends GutTest

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var brush_sys: HFBrushSystem
var bake_sys: HFBakeSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child(root)
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
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	brush_sys = HFBrushSystem.new(root)
	bake_sys = HFBakeSystem.new(root)


func after_each():
	root.queue_free()
	brush_sys = null
	bake_sys = null


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
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))

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


# ===========================================================================
# Tie / Untie
# ===========================================================================


func test_tie_sets_brush_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	brush_sys.tie_brushes_to_entity(["b1"], "func_detail")
	var bec = str(b.get_meta("brush_entity_class", ""))
	assert_eq(bec, "func_detail", "Tie should set brush_entity_class meta")


func test_tie_multiple_brushes():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	brush_sys.tie_brushes_to_entity(["b1", "b2"], "trigger_once")
	assert_eq(str(b1.get_meta("brush_entity_class", "")), "trigger_once")
	assert_eq(str(b2.get_meta("brush_entity_class", "")), "trigger_once")


func test_untie_removes_brush_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	brush_sys.tie_brushes_to_entity(["b1"], "func_detail")
	brush_sys.untie_brushes_from_entity(["b1"])
	assert_false(b.has_meta("brush_entity_class"), "Untie should remove brush_entity_class meta")


func test_untie_only_affects_specified_brushes():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	brush_sys.tie_brushes_to_entity(["b1", "b2"], "func_wall")
	brush_sys.untie_brushes_from_entity(["b1"])
	assert_false(b1.has_meta("brush_entity_class"), "b1 should be untied")
	assert_eq(str(b2.get_meta("brush_entity_class", "")), "func_wall", "b2 should remain tied")


func test_tie_all_entity_classes():
	var classes = ["func_detail", "func_wall", "trigger_once", "trigger_multiple"]
	for cls in classes:
		var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32))
		var bid = b.brush_id
		brush_sys.tie_brushes_to_entity([bid], cls)
		assert_eq(str(b.get_meta("brush_entity_class", "")), cls, "Should support class: " + cls)


func test_untie_nonexistent_brush_noop():
	# Should not crash
	brush_sys.untie_brushes_from_entity(["nonexistent_id"])
	assert_true(true, "Untie of nonexistent brush should not crash")


# ===========================================================================
# Structural brush filtering
# ===========================================================================


func test_structural_brush_no_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	assert_true(bake_sys._is_structural_brush(b), "Brush without entity class is structural")


func test_structural_brush_func_wall():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_wall")
	assert_true(bake_sys._is_structural_brush(b), "func_wall is structural")


func test_non_structural_func_detail():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_detail")
	assert_false(bake_sys._is_structural_brush(b), "func_detail is NOT structural")


func test_non_structural_trigger_once():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "trigger_once")
	assert_false(bake_sys._is_structural_brush(b), "trigger_once is NOT structural")


func test_non_structural_trigger_multiple():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "trigger_multiple")
	assert_false(bake_sys._is_structural_brush(b), "trigger_multiple is NOT structural")


# ===========================================================================
# Collect chunk brushes filters non-structural
# ===========================================================================


func test_collect_excludes_func_detail():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	b2.set_meta("brush_entity_class", "func_detail")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "func_detail brush should be excluded from structural collection")


func test_collect_includes_func_wall():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	b2.set_meta("brush_entity_class", "func_wall")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 2, "func_wall brushes should be included in structural collection")


func test_collect_excludes_triggers():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	b2.set_meta("brush_entity_class", "trigger_once")
	var b3 = _make_brush(Vector3(20, 0, 0), Vector3(32, 32, 32), "b3")
	b3.set_meta("brush_entity_class", "trigger_multiple")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "Trigger brushes should be excluded from structural collection")


# ===========================================================================
# Brush info round-trip with entity class
# ===========================================================================


func test_get_brush_info_includes_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_detail")
	var info = brush_sys.get_brush_info_from_node(b)
	assert_eq(str(info.get("brush_entity_class", "")), "func_detail")


func test_create_brush_from_info_restores_entity_class():
	var info = {
		"shape": 0,  # BOX
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
		"brush_entity_class": "trigger_once",
	}
	var brush = brush_sys.create_brush_from_info(info)
	assert_not_null(brush, "Should create brush from info")
	assert_eq(
		str(brush.get_meta("brush_entity_class", "")),
		"trigger_once",
		"Restored brush should have brush_entity_class"
	)
