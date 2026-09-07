extends GutTest

## Carve: boolean subtraction of one convex brush from every brush it overlaps.
##
## Carve had no dedicated suite before it was generalised off axis-aligned boxes.
## The assertions here are about what a carve has to leave behind — closed,
## outward-facing pieces that do not reach into the carved volume — rather than
## about specific slice coordinates, because the piece count now depends on the
## carver's shape.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFCarveSystemScript = preload("res://addons/hammerforge/systems/hf_carve_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var brushes: HFBrushSystem
var carve


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
	root._material_palette = []
	root.texture_lock = false
	brushes = HFBrushSystem.new(root)
	root.brush_system = brushes
	carve = HFCarveSystemScript.new(root)
	root.carve_system = carve


func after_each():
	root = null
	brushes = null
	carve = null


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
var brush_system = null
var carve_system = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var _material_palette: Array = []

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

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

func tag_brush_dirty(_id: String) -> void:
	pass

func add_material_to_palette(material: Material) -> int:
	_material_palette.append(material)
	return _material_palette.size() - 1
"""
	s.reload()
	return s


func _make_brush(
	pos: Vector3 = Vector3.ZERO,
	sz: Vector3 = Vector3(32, 32, 32),
	brush_id: String = "",
	shape: int = 0
) -> DraftBrush:
	var b = DraftBrush.new()
	b.shape = shape
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	b.rebuild_preview()
	brushes._register_brush_id(brush_id, b)
	return b


func _pieces() -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			out.append(child)
	return out


func _world_verts(draft: DraftBrush) -> Array:
	var out: Array = []
	var xform := draft.global_transform
	for face in draft.get_faces():
		if face == null:
			continue
		for v in face.local_verts:
			out.append(xform * v)
	return out


func _key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0)]


## Every edge of a closed solid is shared by exactly two faces.
func _open_edge_count(draft: DraftBrush) -> int:
	var counts := {}
	for face in draft.get_faces():
		if face == null:
			continue
		var verts: PackedVector3Array = face.local_verts
		var n := verts.size()
		for i in n:
			var a := _key(verts[i])
			var b := _key(verts[(i + 1) % n])
			var edge: String = a + "|" + b if a < b else b + "|" + a
			counts[edge] = int(counts.get(edge, 0)) + 1
	var open := 0
	for edge in counts:
		if counts[edge] != 2:
			open += 1
	return open


func _outward_ratio(draft: DraftBrush) -> float:
	var faces := draft.get_faces()
	if faces.is_empty():
		return -1.0
	var centre := Vector3.ZERO
	var count := 0
	for face in faces:
		for v in face.local_verts:
			centre += v
			count += 1
	if count == 0:
		return -1.0
	centre /= float(count)
	var outward := 0
	var counted := 0
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 3:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[2] - a).cross(verts[1] - a)
		if normal.length() < 0.000001:
			continue
		var face_centre := Vector3.ZERO
		for v in verts:
			face_centre += v
		face_centre /= float(verts.size())
		var to_face: Vector3 = face_centre - centre
		if to_face.length() < 0.000001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


# ===========================================================================
# Refusals that still apply
# ===========================================================================


func test_carve_with_no_id_is_refused():
	assert_false(carve.carve_with_brush("").ok)


func test_carve_with_a_missing_brush_is_refused():
	assert_false(carve.carve_with_brush("nope").ok)


func test_carve_with_nothing_overlapping_is_refused():
	_make_brush(Vector3.ZERO, Vector3(16, 16, 16), "carver")
	_make_brush(Vector3(500, 0, 0), Vector3(32, 32, 32), "far")
	var result = carve.carve_with_brush("carver")
	assert_false(result.ok, "a carver touching nothing has nothing to do")
	assert_not_null(brushes.find_brush_by_id("carver"), "the carver must survive a refusal")


func test_a_carver_that_only_touches_a_face_is_refused():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "target")
	# Sitting exactly against the +X face: contact, not a volume.
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "carver")
	assert_false(carve.carve_with_brush("carver").ok)
	assert_not_null(brushes.find_brush_by_id("target"), "the target must be untouched")


# ===========================================================================
# Carving a box with a box
# ===========================================================================


func test_a_corner_carve_replaces_the_target_with_pieces():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, result.message)
	assert_null(brushes.find_brush_by_id("target"), "the original target is replaced")
	assert_null(brushes.find_brush_by_id("carver"), "the carver is consumed")
	assert_gt(_pieces().size(), 0, "carving must leave something behind")


func test_carved_pieces_are_closed_solids():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	for piece in _pieces():
		assert_eq(_open_edge_count(piece), 0, "a carved piece has an open edge")


func test_carved_pieces_face_outward():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001, "a carved piece would bake inside out")


func test_no_carved_piece_reaches_into_the_carved_volume():
	# The point of a carve: nothing survives inside the carver.
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	var hole := AABB(Vector3(16, 16, 16), Vector3(32, 32, 32))
	for piece in _pieces():
		for v in _world_verts(piece):
			var inside: bool = (
				v.x > hole.position.x + 0.01
				and v.x < hole.position.x + hole.size.x - 0.01
				and v.y > hole.position.y + 0.01
				and v.y < hole.position.y + hole.size.y - 0.01
				and v.z > hole.position.z + 0.01
				and v.z < hole.position.z + hole.size.z - 0.01
			)
			assert_false(inside, "a vertex at %s is inside the carved volume" % v)


func test_carve_preserves_material_and_metadata():
	var target := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	var mat := StandardMaterial3D.new()
	target.material_override = mat
	target.set_meta("visgroups", PackedStringArray(["walls"]))
	target.set_meta("group_id", "group_7")
	target.set_brush_entity_class("func_detail")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	var pieces := _pieces()
	assert_gt(pieces.size(), 0)
	for piece in pieces:
		assert_eq(piece.material_override, mat, "each piece keeps the material")
		assert_eq(
			Array(piece.get_meta("visgroups", PackedStringArray())),
			["walls"],
			"each piece keeps its visgroups"
		)
		assert_eq(str(piece.get_meta("group_id", "")), "group_7")
		assert_eq(str(piece.get_meta("brush_entity_class", "")), "func_detail")


func test_carve_preserves_the_target_operation():
	var target := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	target.operation = CSGShape3D.OPERATION_UNION
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	for piece in _pieces():
		assert_eq(piece.operation, CSGShape3D.OPERATION_UNION)


func test_a_slot_carve_leaves_pieces_on_both_sides():
	# A thin carver driven right through the middle should leave two halves.
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3.ZERO, Vector3(8, 200, 200), "carver")
	assert_true(carve.carve_with_brush("carver").ok)
	var pieces := _pieces()
	assert_eq(pieces.size(), 2, "a through-cut leaves the two sides")
	var left := false
	var right := false
	for piece in pieces:
		if piece.global_position.x < 0.0:
			left = true
		else:
			right = true
	assert_true(left and right, "one piece each side of the slot")


# ===========================================================================
# What generalising the algorithm unlocked
# ===========================================================================


func test_a_rotated_carver_carves():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	var carver := _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "carver")
	carver.rotation_degrees = Vector3(0, 45, 0)
	carver.rebuild_preview()
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, "a turned carver used to be refused outright: %s" % result.message)
	for piece in _pieces():
		assert_eq(_open_edge_count(piece), 0)
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_a_rotated_target_is_carved():
	var target := _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	target.rotation_degrees = Vector3(0, 30, 0)
	target.rebuild_preview()
	_make_brush(Vector3(32, 32, 0), Vector3(32, 32, 200), "carver")
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, "a turned target used to refuse the whole carve: %s" % result.message)
	for piece in _pieces():
		assert_eq(_open_edge_count(piece), 0)


func test_a_cylinder_carver_carves():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(0, 0, 0), Vector3(24, 200, 24), "carver", DraftBrush.BrushShape.CYLINDER)
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, "a cylinder used to be refused: %s" % result.message)
	assert_gt(_pieces().size(), 0)
	for piece in _pieces():
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_a_wedge_carver_carves():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(24, 24, 0), Vector3(48, 48, 200), "carver", DraftBrush.BrushShape.WEDGE)
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok, result.message)
	for piece in _pieces():
		assert_eq(_open_edge_count(piece), 0)
		assert_almost_eq(_outward_ratio(piece), 1.0, 0.0001)


func test_a_carver_that_swallows_the_target_leaves_it_alone():
	# Faithful to the box carve: nothing disappears without a preview showing it.
	_make_brush(Vector3.ZERO, Vector3(16, 16, 16), "target")
	_make_brush(Vector3.ZERO, Vector3(200, 200, 200), "carver")
	var result = carve.carve_with_brush("carver")
	assert_false(result.ok, "a carve that would leave nothing is refused")
	assert_not_null(brushes.find_brush_by_id("target"), "the target survives")
	assert_not_null(brushes.find_brush_by_id("carver"), "so does the carver")


func test_carve_reports_what_it_did():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "carver")
	var result = carve.carve_with_brush("carver")
	assert_true(result.ok)
	assert_true(result.message.to_lower().contains("carve"), result.message)
