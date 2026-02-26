extends GutTest
## Tests for brush info capture/restore round-trips, including Wave 2 properties
## (visgroups, group_id, brush_entity_class, material, operation).
## Also covers move_brushes_to_floor/ceiling argument handling.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBrushSystem


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
	sys = HFBrushSystem.new(root)


func after_each():
	root.queue_free()
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
	sys._register_brush_id(brush_id, b)
	return b


# ===========================================================================
# Brush info capture
# ===========================================================================


func test_capture_basic_info():
	var b = _make_brush(Vector3(10, 20, 30), Vector3(16, 32, 48), "brush_1")
	var info = sys.get_brush_info_from_node(b)
	assert_eq(info["brush_id"], "brush_1")
	assert_eq(info["size"], Vector3(16, 32, 48))
	assert_eq(info["shape"], 0)  # BOX


func test_capture_includes_visgroups():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.set_meta("visgroups", PackedStringArray(["walls", "detail"]))
	var info = sys.get_brush_info_from_node(b)
	var vgs = info.get("visgroups", [])
	assert_eq(vgs.size(), 2)
	assert_true("walls" in vgs)
	assert_true("detail" in vgs)


func test_capture_includes_group_id():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.set_meta("group_id", "group_42")
	var info = sys.get_brush_info_from_node(b)
	assert_eq(str(info.get("group_id", "")), "group_42")


func test_capture_includes_brush_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.set_meta("brush_entity_class", "trigger_once")
	var info = sys.get_brush_info_from_node(b)
	assert_eq(str(info.get("brush_entity_class", "")), "trigger_once")


func test_capture_includes_material():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.material_override = mat
	var info = sys.get_brush_info_from_node(b)
	assert_eq(info.get("material", null), mat)


func test_capture_omits_empty_visgroups():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	var info = sys.get_brush_info_from_node(b)
	assert_false(info.has("visgroups"), "Empty visgroups should not be in info")


func test_capture_omits_empty_group_id():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	var info = sys.get_brush_info_from_node(b)
	assert_false(info.has("group_id"), "Empty group_id should not be in info")


func test_capture_omits_empty_brush_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	var info = sys.get_brush_info_from_node(b)
	assert_false(info.has("brush_entity_class"), "Empty entity class should not be in info")


# ===========================================================================
# Brush info restore
# ===========================================================================


func test_restore_basic_info():
	var info = {
		"shape": 0,
		"size": Vector3(16, 32, 48),
		"center": Vector3(10, 20, 30),
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
	}
	var brush = sys.create_brush_from_info(info)
	assert_not_null(brush)
	assert_eq(brush.size, Vector3(16, 32, 48))
	assert_eq(str(brush.brush_id), "restored_1")


func test_restore_with_visgroups():
	var info = {
		"shape": 0,
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
		"visgroups": ["walls", "ceiling"],
	}
	var brush = sys.create_brush_from_info(info)
	assert_not_null(brush)
	var vgs = brush.get_meta("visgroups", PackedStringArray())
	assert_eq(vgs.size(), 2)
	assert_true(vgs.has("walls"))
	assert_true(vgs.has("ceiling"))


func test_restore_with_group_id():
	var info = {
		"shape": 0,
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
		"group_id": "group_99",
	}
	var brush = sys.create_brush_from_info(info)
	assert_not_null(brush)
	assert_eq(str(brush.get_meta("group_id", "")), "group_99")


func test_restore_with_brush_entity_class():
	var info = {
		"shape": 0,
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
		"brush_entity_class": "func_detail",
	}
	var brush = sys.create_brush_from_info(info)
	assert_not_null(brush)
	assert_eq(str(brush.get_meta("brush_entity_class", "")), "func_detail")


func test_restore_with_material():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW
	var info = {
		"shape": 0,
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
		"material": mat,
	}
	var brush = sys.create_brush_from_info(info)
	assert_not_null(brush)
	assert_eq((brush as DraftBrush).material_override, mat)


func test_restore_subtraction_operation():
	var info = {
		"shape": 0,
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
		"brush_id": "restored_1",
	}
	var brush = sys.create_brush_from_info(info)
	assert_not_null(brush)
	assert_eq((brush as DraftBrush).operation, CSGShape3D.OPERATION_SUBTRACTION)


# ===========================================================================
# Round-trip: capture → restore → verify
# ===========================================================================


func test_full_round_trip():
	var mat = StandardMaterial3D.new()
	var b = _make_brush(Vector3(5, 10, 15), Vector3(16, 24, 32), "round_trip_1")
	b.material_override = mat
	b.set_meta("visgroups", PackedStringArray(["walls"]))
	b.set_meta("group_id", "grp_1")
	b.set_meta("brush_entity_class", "func_wall")

	# Capture
	var info = sys.get_brush_info_from_node(b)

	# Delete original
	sys.delete_brush(b)

	# Restore with new ID
	info["brush_id"] = "round_trip_restored"
	var restored = sys.create_brush_from_info(info)

	assert_not_null(restored)
	assert_eq(restored.size, Vector3(16, 24, 32))
	assert_eq((restored as DraftBrush).material_override, mat)
	var vgs = restored.get_meta("visgroups", PackedStringArray())
	assert_true(vgs.has("walls"))
	assert_eq(str(restored.get_meta("group_id", "")), "grp_1")
	assert_eq(str(restored.get_meta("brush_entity_class", "")), "func_wall")


# ===========================================================================
# Move floor/ceiling: argument validation
# ===========================================================================


func test_move_to_floor_empty_ids_noop():
	# Should not crash
	sys.move_brushes_to_floor([])
	assert_true(true, "Empty IDs should not crash")


func test_move_to_ceiling_empty_ids_noop():
	# Should not crash
	sys.move_brushes_to_ceiling([])
	assert_true(true, "Empty IDs should not crash")


func test_move_to_floor_nonexistent_id_noop():
	# Should not crash
	sys.move_brushes_to_floor(["nonexistent"])
	assert_true(true, "Nonexistent ID should not crash")


func test_move_to_ceiling_nonexistent_id_noop():
	# Should not crash
	sys.move_brushes_to_ceiling(["nonexistent"])
	assert_true(true, "Nonexistent ID should not crash")
