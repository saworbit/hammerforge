extends GutTest

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


func test_clip_splits_a_non_box_shape():
	# Clip used to rebuild the brush as two axis-aligned boxes and so refused
	# anything else. It now splits the real geometry, so a wedge cuts.
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.shape = root.BrushShape.WEDGE
	b.rebuild_preview()
	var result = sys.clip_brush_by_id("brush_1", 1, 0.0)
	assert_true(result.ok, "Clip should split a wedge: %s" % result.message)
	assert_eq(root.draft_brushes_node.get_child_count(), 2, "A wedge clips into two pieces")


func test_can_clip_brush_accepts_a_non_box_shape():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.shape = root.BrushShape.CAPSULE
	b.rebuild_preview()
	assert_true(sys.can_clip_brush("brush_1", 1, 0.0).ok, "Pre-check should accept a capsule")


func test_clip_splits_a_rotated_box():
	# The plane is taken into the brush's own frame, so a turned box cuts along the
	# world plane the user asked for and both pieces keep the rotation.
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.rotation_degrees = Vector3(0, 30, 0)
	b.rebuild_preview()
	var result = sys.clip_brush_by_id("brush_1", 1, 0.0)
	assert_true(result.ok, "Clip should split a rotated box: %s" % result.message)
	assert_eq(root.draft_brushes_node.get_child_count(), 2)
	for child in root.draft_brushes_node.get_children():
		assert_almost_eq(
			child.rotation_degrees.y, 30.0, 0.01, "each piece keeps the original rotation"
		)


func test_clip_rejects_a_plane_that_misses_the_brush():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	var result = sys.clip_brush_by_plane("brush_1", Plane(Vector3.UP, 500.0))
	assert_false(result.ok, "a plane clear of the brush cuts nothing")
	assert_true(is_instance_valid(b), "the brush must survive a rejected clip")
	assert_eq(root.draft_brushes_node.get_child_count(), 1)


func test_clip_by_plane_cuts_on_a_diagonal():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	var result = sys.clip_brush_by_plane("brush_1", Plane(Vector3(1, 1, 0).normalized(), 0.0))
	assert_true(result.ok, "a diagonal plane should cut: %s" % result.message)
	assert_eq(root.draft_brushes_node.get_child_count(), 2)


func test_clip_to_face_plane_cuts_along_the_chosen_face():
	var target = _make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	var reference = _make_brush(Vector3(8, 0, 0), Vector3(32, 32, 32), "ref")
	reference.rotation_degrees = Vector3(0, 0, 45)
	reference.rebuild_preview()
	var result = sys.clip_brush_to_face_plane("target", "ref", 0)
	assert_true(result.ok, "clipping along a face plane should cut: %s" % result.message)
	assert_null(sys.find_brush_by_id("target"), "the original target is replaced")
	assert_not_null(sys.find_brush_by_id("ref"), "the reference brush is untouched")


func test_clip_to_face_plane_rejects_a_missing_face():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "target")
	_make_brush(Vector3(8, 0, 0), Vector3(32, 32, 32), "ref")
	var result = sys.clip_brush_to_face_plane("target", "ref", 99)
	assert_false(result.ok)
	assert_ne(result.fix_hint, "", "a refusal must say what to do instead")


func test_clip_keeps_an_axis_aligned_box_a_box():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	assert_true(sys.clip_brush_by_id("brush_1", 1, 0.0).ok)
	for child in root.draft_brushes_node.get_children():
		assert_eq(
			child.shape,
			root.BrushShape.BOX,
			"half a box is still a box, so it must keep its resize handles"
		)


func test_clip_makes_a_diagonal_piece_custom():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	assert_true(sys.clip_brush_by_plane("brush_1", Plane(Vector3(1, 1, 0).normalized(), 0.0)).ok)
	for child in root.draft_brushes_node.get_children():
		assert_eq(
			child.shape, root.BrushShape.CUSTOM, "an angled piece is no longer a box primitive"
		)


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
