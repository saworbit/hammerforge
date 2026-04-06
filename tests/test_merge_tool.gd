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
	root._material_palette = []
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
# Merge: validation
# ===========================================================================


func test_merge_rejects_single_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var result = sys.can_merge_brushes(["b1"])
	assert_false(result.ok, "Merge should reject a single brush")


func test_merge_rejects_empty_list():
	var result = sys.can_merge_brushes([])
	assert_false(result.ok, "Merge should reject empty list")


func test_merge_rejects_missing_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var result = sys.can_merge_brushes(["b1", "nonexistent"])
	assert_false(result.ok, "Merge should reject if any brush ID is invalid")


func test_merge_rejects_mixed_operations():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.operation = CSGShape3D.OPERATION_UNION
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.operation = CSGShape3D.OPERATION_SUBTRACTION
	var result = sys.can_merge_brushes(["b1", "b2"])
	assert_false(result.ok, "Merge should reject brushes with different operations")


func test_merge_accepts_two_valid_brushes():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	var result = sys.can_merge_brushes(["b1", "b2"])
	assert_true(result.ok, "Merge should accept two valid same-operation brushes")


# ===========================================================================
# Merge: basic operation
# ===========================================================================


func test_merge_creates_one_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 1, "Merge should produce exactly one brush")


func test_merge_deletes_originals():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	assert_null(sys.find_brush_by_id("b1"), "Original brush b1 should be deleted")
	assert_null(sys.find_brush_by_id("b2"), "Original brush b2 should be deleted")


func test_merge_result_is_custom_shape():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	assert_eq(merged.shape, root.BrushShape.CUSTOM, "Merged brush should be CUSTOM shape")


func test_merge_combines_faces():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	var b1_face_count = b1.faces.size()
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.rebuild_preview()
	var b2_face_count = b2.faces.size()
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	assert_eq(
		merged.faces.size(),
		b1_face_count + b2_face_count,
		"Merged brush should have faces from both source brushes"
	)


func test_merge_registers_material_override_as_face_material():
	var mat_a = StandardMaterial3D.new()
	mat_a.albedo_color = Color.RED
	var mat_b = StandardMaterial3D.new()
	mat_b.albedo_color = Color.BLUE
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.material_override = mat_a
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.material_override = mat_b
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# All faces should have material_idx >= 0 (registered in palette)
	var all_have_mat := true
	for face in merged.faces:
		if face.material_idx < 0:
			all_have_mat = false
			break
	assert_true(all_have_mat, "All faces should have per-face material_idx after merge")
	# Palette should contain both materials
	assert_eq(root._material_palette.size(), 2, "Both materials should be registered")


func test_merge_preserves_visgroups():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.set_meta("visgroups", PackedStringArray(["vg_walls"]))
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	var vgs: PackedStringArray = merged.get_meta("visgroups", PackedStringArray())
	assert_true(vgs.has("vg_walls"), "Merged brush should inherit visgroups from first brush")


func test_merge_preserves_group_id():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.set_meta("group_id", "grp_01")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	assert_eq(
		str(merged.get_meta("group_id", "")),
		"grp_01",
		"Merged brush should inherit group_id from first brush"
	)


# ===========================================================================
# Merge: vertex offset
# ===========================================================================


func test_merge_offsets_verts_for_second_brush():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.rebuild_preview()
	var b2_face_count = b2.faces.size()

	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush

	# The first brush's faces should be near origin (no offset).
	# The second brush's faces should be offset by (64, 0, 0).
	# Check that at least one face from the second brush has verts near x=64.
	var found_offset_face := false
	# Faces from the second brush start after the first brush's faces
	var b1_face_count = 6  # box has 6 faces
	for i in range(b1_face_count, merged.faces.size()):
		var face = merged.faces[i]
		for v in face.local_verts:
			if absf(v.x - 64.0) < 20.0:  # Within half-size of offset brush
				found_offset_face = true
				break
		if found_offset_face:
			break
	assert_true(found_offset_face, "Second brush faces should be offset by brush position delta")


func test_merge_three_brushes():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	_make_brush(Vector3(0, 64, 0), Vector3(32, 32, 32), "b3")
	sys.merge_brushes_by_ids(["b1", "b2", "b3"])
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 1, "Merge of 3 brushes should produce 1 brush")
	var merged = children[0] as DraftBrush
	# 3 boxes x 6 faces = 18 faces
	assert_eq(merged.faces.size(), 18, "Merged brush should have 18 faces (3 x 6)")


# ===========================================================================
# Merge: return value
# ===========================================================================


func test_merge_returns_success():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	var result = sys.merge_brushes_by_ids(["b1", "b2"])
	assert_true(result.ok, "Merge should return success")


func test_merge_single_brush_returns_failure():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var result = sys.merge_brushes_by_ids(["b1"])
	assert_false(result.ok, "Merge of single brush should fail")


func test_merge_positioned_at_first_brush():
	_make_brush(Vector3(10, 20, 30), Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(74, 20, 30), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	assert_almost_eq(
		merged.global_position,
		Vector3(10, 20, 30),
		Vector3(0.1, 0.1, 0.1),
		"Merged brush should be positioned at first brush's location"
	)


# ===========================================================================
# Merge: full transform (rotation/scale)
# ===========================================================================


func test_merge_rotated_brush_applies_basis():
	# First brush at origin, unrotated
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	# Second brush rotated 90 degrees around Y
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.rebuild_preview()
	b2.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(64, 0, 0))
	# Before merge, b2 has a face with +X normal in local space (right face).
	# After 90-deg Y rotation, that should become +Z in world space,
	# then mapped back into merged brush local space (identity basis) → +Z.
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# Find faces from the second brush (indices 6..11) and check that
	# a face that was +X normal in local space has been rotated.
	var found_rotated_normal := false
	for i in range(6, merged.faces.size()):
		var n: Vector3 = merged.faces[i].normal
		# A +X normal rotated 90 deg around Y → approximately +Z
		if n.dot(Vector3.BACK) > 0.9:
			found_rotated_normal = true
			break
	assert_true(
		found_rotated_normal, "Rotated brush normals should be transformed into merged space"
	)


func test_merge_rotated_brush_transforms_verts():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	# b2 at origin but rotated 90 degrees around Y
	var b2 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b2")
	b2.rebuild_preview()
	# Capture b2's +X face verts before rotation (should have x=16)
	var pre_max_x: float = -INF
	for face in b2.faces:
		for v in face.local_verts:
			pre_max_x = maxf(pre_max_x, v.x)
	b2.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	# After 90-deg Y rotation, local +X(16) → world -Z(16).
	# Merged local = world (first brush is identity at origin).
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# Collect max |z| from b2's faces (indices 6..11) — should reach ~16
	var max_abs_z: float = 0.0
	for i in range(6, merged.faces.size()):
		for v in merged.faces[i].local_verts:
			max_abs_z = maxf(max_abs_z, absf(v.z))
	assert_almost_eq(
		max_abs_z,
		pre_max_x,
		0.5,
		"Rotated brush verts should map X extent to Z extent in merged space"
	)


func test_merge_preserves_transform_of_merged_brush():
	# First brush is rotated — merged brush should inherit that transform
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var rot_basis := Basis(Vector3.UP, deg_to_rad(45.0))
	b1.global_transform = Transform3D(rot_basis, Vector3(10, 20, 30))
	var b2 = _make_brush(Vector3(50, 20, 30), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# Merged should have same basis as first brush
	var merged_basis: Basis = merged.global_transform.basis
	assert_almost_eq(
		merged_basis.x,
		rot_basis.x,
		Vector3(0.01, 0.01, 0.01),
		"Merged brush should inherit first brush's rotation"
	)


# ===========================================================================
# Merge: multi-material
# ===========================================================================


func test_merge_different_materials_get_distinct_indices():
	var mat_a = StandardMaterial3D.new()
	mat_a.albedo_color = Color.RED
	var mat_b = StandardMaterial3D.new()
	mat_b.albedo_color = Color.GREEN
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.material_override = mat_a
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.material_override = mat_b
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# Collect distinct material indices
	var indices: Dictionary = {}
	for face in merged.faces:
		indices[face.material_idx] = true
	assert_eq(indices.size(), 2, "Merged brush should have 2 distinct material indices")


func test_merge_same_material_reuses_index():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.material_override = mat
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	b2.material_override = mat  # Same material instance
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# All faces should share the same material index
	var indices: Dictionary = {}
	for face in merged.faces:
		indices[face.material_idx] = true
	assert_eq(indices.size(), 1, "Same material should produce one index")
	assert_eq(root._material_palette.size(), 1, "Same material should be registered once")


func test_merge_no_material_override_leaves_idx_unchanged():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b2")
	# Neither brush has material_override
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# All faces should keep material_idx == -1
	var all_default := true
	for face in merged.faces:
		if face.material_idx != -1:
			all_default = false
			break
	assert_true(all_default, "Faces with no material override should keep material_idx -1")
