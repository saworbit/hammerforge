extends GutTest

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
# Clip: basic splitting
# ===========================================================================


func test_clip_y_axis_creates_two_pieces():
	_make_brush(Vector3(0, 16, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 1, 16.0)  # Y axis, split at center
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2, "Clip should create 2 pieces")


func test_clip_x_axis_creates_two_pieces():
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 0, 0.0)  # X axis, split at center
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2, "X-axis clip should create 2 pieces")


func test_clip_z_axis_creates_two_pieces():
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 2, 0.0)  # Z axis, split at center
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2, "Z-axis clip should create 2 pieces")


func test_clip_deletes_original():
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var found = sys.find_brush_by_id("brush_1")
	assert_null(found, "Original brush should be deleted after clip")


# ===========================================================================
# Clip: size correctness
# ===========================================================================


func test_clip_y_sizes_sum_to_original():
	# Brush at Y=0, size 32 → spans Y=-16 to Y=16. Split at Y=0
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2)
	var total_y := 0.0
	for child in children:
		if child is DraftBrush:
			total_y += (child as DraftBrush).size.y
	assert_almost_eq(total_y, 32.0, 0.01, "Piece sizes should sum to original")


func test_clip_preserves_non_split_dimensions():
	_make_brush(Vector3(0, 0, 0), Vector3(32, 64, 48), "brush_1")
	sys.clip_brush_by_id("brush_1", 1, 0.0)  # Split along Y
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			var draft := child as DraftBrush
			assert_almost_eq(draft.size.x, 32.0, 0.01, "X should be unchanged")
			assert_almost_eq(draft.size.z, 48.0, 0.01, "Z should be unchanged")


func test_clip_x_sizes_correct():
	# Brush at X=0, size.x=40 → spans -20 to 20. Split at X=10
	_make_brush(Vector3(0, 0, 0), Vector3(40, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 0, 10.0)
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2)
	var sizes: Array = []
	for child in children:
		if child is DraftBrush:
			sizes.append((child as DraftBrush).size.x)
	sizes.sort()
	# Piece A: -20 to 10 → size 30. Piece B: 10 to 20 → size 10
	assert_almost_eq(sizes[0], 10.0, 0.01, "Smaller piece should be 10")
	assert_almost_eq(sizes[1], 30.0, 0.01, "Larger piece should be 30")


# ===========================================================================
# Clip: edge cases and rejection
# ===========================================================================


func test_clip_outside_brush_is_rejected():
	# Brush at Y=0, size 32 → spans -16 to 16. Split at Y=100 → outside
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 1, 100.0)
	# Original should still be there
	assert_not_null(sys.find_brush_by_id("brush_1"), "Clip outside bounds should be rejected")


func test_clip_on_edge_is_rejected():
	# Brush at Y=0, size 32 → spans -16 to 16. Split at Y=16 → on edge
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("brush_1", 1, 16.0)
	assert_not_null(sys.find_brush_by_id("brush_1"), "Clip on brush edge should be rejected")


func test_clip_empty_id_noop():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("", 1, 0.0)
	assert_not_null(sys.find_brush_by_id("brush_1"), "Empty ID should be a no-op")


func test_clip_nonexistent_id_noop():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.clip_brush_by_id("nonexistent", 1, 0.0)
	assert_not_null(sys.find_brush_by_id("brush_1"), "Nonexistent ID should be a no-op")


# ===========================================================================
# Clip: property preservation
# ===========================================================================


func test_clip_preserves_operation():
	var b = _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	b.operation = CSGShape3D.OPERATION_SUBTRACTION
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			assert_eq(
				(child as DraftBrush).operation,
				CSGShape3D.OPERATION_SUBTRACTION,
				"Clipped pieces should preserve operation"
			)


func test_clip_preserves_material():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.BLUE
	var b = _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	b.material_override = mat
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			assert_eq(
				(child as DraftBrush).material_override,
				mat,
				"Clipped pieces should preserve material"
			)


func test_clip_preserves_brush_entity_class():
	var b = _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	b.set_meta("brush_entity_class", "func_detail")
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			assert_eq(
				str(child.get_meta("brush_entity_class", "")),
				"func_detail",
				"Clipped pieces should preserve brush entity class"
			)


func test_clip_preserves_visgroups():
	var b = _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	b.set_meta("visgroups", PackedStringArray(["walls", "detail"]))
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			var vgs = child.get_meta("visgroups", PackedStringArray())
			assert_true(vgs.has("walls"), "Should preserve 'walls' visgroup")
			assert_true(vgs.has("detail"), "Should preserve 'detail' visgroup")


func test_clip_preserves_group_id():
	var b = _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "brush_1")
	b.set_meta("group_id", "group_42")
	sys.clip_brush_by_id("brush_1", 1, 0.0)
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			assert_eq(
				str(child.get_meta("group_id", "")),
				"group_42",
				"Clipped pieces should preserve group_id"
			)
