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
# Hollow: basic creation
# ===========================================================================


func test_hollow_creates_six_wall_brushes():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.hollow_brush_by_id("brush_1", 2.0)
	# Original brush should be deleted, 6 walls created
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 6, "Hollow should create 6 wall brushes")


func test_hollow_deletes_original_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.hollow_brush_by_id("brush_1", 2.0)
	var found = sys.find_brush_by_id("brush_1")
	assert_null(found, "Original brush should be deleted after hollow")


func test_every_wall_is_one_thickness_thick():
	# Hollow shells the brush by pushing each of its own faces inward, so which
	# wall gets the full span and which gets the remainder depends on the order the
	# faces come in. What has to hold for every wall, in every order, is that it is
	# exactly one wall thickness deep in one direction.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.hollow_brush_by_id("brush_1", 4.0)
	for child in root.draft_brushes_node.get_children():
		if not (child is DraftBrush):
			continue
		var size: Vector3 = (child as DraftBrush).size
		var thin := (
			is_equal_approx(size.x, 4.0)
			or is_equal_approx(size.y, 4.0)
			or is_equal_approx(size.z, 4.0)
		)
		assert_true(thin, "wall %s is not one thickness deep in any direction" % size)


func test_the_walls_tile_the_original_volume():
	# The walls plus the void they surround are the brush they came from.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	var thickness := 4.0
	sys.hollow_brush_by_id("brush_1", thickness)
	var wall_volume := 0.0
	for child in root.draft_brushes_node.get_children():
		if not (child is DraftBrush):
			continue
		var size: Vector3 = (child as DraftBrush).size
		wall_volume += size.x * size.y * size.z
	var inner := 32.0 - 2.0 * thickness
	assert_almost_eq(
		wall_volume,
		32.0 * 32.0 * 32.0 - inner * inner * inner,
		1.0,
		"the walls must tile the brush"
	)


func test_hollow_preserves_material():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.material_override = mat
	sys.hollow_brush_by_id("brush_1", 2.0)
	var children = root.draft_brushes_node.get_children()
	var all_have_material := true
	for child in children:
		if child is DraftBrush:
			if (child as DraftBrush).material_override != mat:
				all_have_material = false
	assert_true(all_have_material, "All wall brushes should inherit original material")


# ===========================================================================
# Hollow: wall thickness validation
# ===========================================================================


func test_hollow_rejects_thickness_too_large():
	# The insets would cross each other, leaving no interior to hollow out.
	_make_brush(Vector3.ZERO, Vector3(10, 20, 30), "brush_1")
	sys.hollow_brush_by_id("brush_1", 6.0)
	# Original brush should still exist
	var found = sys.find_brush_by_id("brush_1")
	assert_not_null(found, "Original brush should remain when thickness too large")


func test_hollow_accepts_valid_thickness():
	# The insets still bound a volume, so there is something to hollow out.
	_make_brush(Vector3.ZERO, Vector3(10, 20, 30), "brush_1")
	sys.hollow_brush_by_id("brush_1", 4.0)
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 6, "Should accept valid thickness")


func test_hollowing_a_cylinder_makes_a_tube():
	# Hollow used to rebuild every brush as six axis-aligned slabs and so refused
	# anything else. It shells the real geometry now, which means a hollow cylinder
	# is a pipe: one wall per side facet, plus a top and a bottom.
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.shape = root.BrushShape.CYLINDER
	b.rebuild_preview()
	# The brush stores triangles, so a cylinder has hundreds of faces describing
	# far fewer distinct planes. One wall per distinct plane is the real rule.
	var result = sys.hollow_brush_by_id("brush_1", 4.0)
	assert_true(result.ok, "Hollow should shell a cylinder: %s" % result.message)
	var walls: int = root.draft_brushes_node.get_child_count()
	assert_gt(walls, 6, "a cylinder shells into more walls than a box")
	assert_lt(walls, b.get_faces().size(), "and far fewer than it has triangles")


func test_can_hollow_brush_accepts_a_non_box_shape():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.shape = root.BrushShape.SPHERE
	b.rebuild_preview()
	var check = sys.can_hollow_brush("brush_1", 2.0)
	assert_true(check.ok, "Pre-check should accept a sphere: %s" % check.user_text())


func test_hollowing_a_rotated_box_keeps_the_rotation():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	b.rotation_degrees = Vector3(0, 45, 0)
	b.rebuild_preview()
	var result = sys.hollow_brush_by_id("brush_1", 4.0)
	assert_true(result.ok, "Hollow should shell a rotated box: %s" % result.message)
	assert_eq(root.draft_brushes_node.get_child_count(), 6)
	for child in root.draft_brushes_node.get_children():
		assert_almost_eq(
			child.rotation_degrees.y, 45.0, 0.01, "each wall keeps the brush's rotation"
		)


func test_hollow_refuses_a_thickness_with_no_room_inside():
	_make_brush(Vector3.ZERO, Vector3(20, 20, 20), "brush_1")
	var result = sys.hollow_brush_by_id("brush_1", 12.0)
	assert_false(result.ok, "a thickness past the halfway point leaves no interior")
	assert_ne(result.fix_hint, "", "a refusal must say what thickness would work")
	assert_not_null(sys.find_brush_by_id("brush_1"), "the brush must survive")


func test_hollow_refuses_a_thickness_of_zero():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	assert_false(sys.hollow_brush_by_id("brush_1", 0.0).ok)
	assert_not_null(sys.find_brush_by_id("brush_1"))


func test_hollow_empty_id_noop():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.hollow_brush_by_id("", 2.0)
	# Original should still be there
	assert_not_null(sys.find_brush_by_id("brush_1"), "Empty ID should be a no-op")


func test_hollow_nonexistent_id_noop():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.hollow_brush_by_id("nonexistent", 2.0)
	assert_not_null(sys.find_brush_by_id("brush_1"), "Nonexistent ID should be a no-op")


# ===========================================================================
# Hollow: wall positions and operations
# ===========================================================================


func test_hollow_walls_are_union_operation():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "brush_1")
	sys.hollow_brush_by_id("brush_1", 2.0)
	var children = root.draft_brushes_node.get_children()
	for child in children:
		if child is DraftBrush:
			assert_eq(
				(child as DraftBrush).operation,
				CSGShape3D.OPERATION_UNION,
				"Wall brushes should be union operations"
			)


func test_hollow_different_thickness():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "brush_1")
	sys.hollow_brush_by_id("brush_1", 8.0)
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 6, "Should create 6 walls with different thickness")
	# Left/right walls should be thickness 8 in X, reduced height and depth
	var found_lr := 0
	for child in children:
		if child is DraftBrush:
			var draft := child as DraftBrush
			if is_equal_approx(draft.size.x, 8.0):
				found_lr += 1
	assert_eq(found_lr, 2, "Should have 2 left/right walls with thickness as X size")
