extends GutTest

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var sys: HFBrushSystem


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	sys = root.brush_system


func after_each():
	HFLog.end_test_capture()
	root = null
	sys = null


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


## Whether a face's middle lies on the outside of `box` rather than inside it.
func _on_shell(face, box: AABB) -> bool:
	var centre := Vector3.ZERO
	for v in face.local_verts:
		centre += v
	centre /= float(face.local_verts.size())
	for axis in 3:
		if absf(centre[axis] - box.position[axis]) < 0.001:
			return true
		if absf(centre[axis] - box.end[axis]) < 0.001:
			return true
	return false


## The face of `brush` whose normal points most nearly along `direction`.
func _face_towards(brush: DraftBrush, direction: Vector3):
	var best = null
	var best_dot := -2.0
	for face in brush.faces:
		var along: float = face.normal.dot(direction)
		if along > best_dot:
			best_dot = along
			best = face
	return best


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
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	b2.operation = CSGShape3D.OPERATION_SUBTRACTION
	var result = sys.can_merge_brushes(["b1", "b2"])
	assert_false(result.ok, "Merge should reject brushes with different operations")


func test_merge_accepts_two_valid_brushes():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	var result = sys.can_merge_brushes(["b1", "b2"])
	assert_true(result.ok, "Merge should accept two valid same-operation brushes")


# ===========================================================================
# Merge: basic operation
# ===========================================================================


func test_merge_creates_one_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 1, "Merge should produce exactly one brush")


func test_merge_deletes_originals():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	assert_null(sys.find_brush_by_id("b1"), "Original brush b1 should be deleted")
	assert_null(sys.find_brush_by_id("b2"), "Original brush b2 should be deleted")


func test_merge_result_is_custom_shape():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	assert_eq(merged.shape, root.BrushShape.CUSTOM, "Merged brush should be CUSTOM shape")


## Two boxes sharing a face are one box of six faces. The merge used to keep all
## twelve, two of them back to back inside the solid where the boxes touched (#1200).
func test_merge_of_two_boxes_sharing_a_face_is_the_box_they_make():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	assert_eq(merged.faces.size(), 6, "a box has six faces")
	var box := AABB(Vector3(-16, -16, -16), Vector3(64, 32, 32))
	for face in merged.faces:
		assert_true(_on_shell(face, box), "%s lies on the outside" % [face.local_verts])


func test_merge_registers_material_override_as_face_material():
	var mat_a = StandardMaterial3D.new()
	mat_a.albedo_color = Color.RED
	var mat_b = StandardMaterial3D.new()
	mat_b.albedo_color = Color.BLUE
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.material_override = mat_a
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
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
	assert_eq(root.material_manager.materials.size(), 2, "Both materials should be registered")


func test_merge_preserves_visgroups():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.set_meta("visgroups", PackedStringArray(["vg_walls"]))
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	var vgs: PackedStringArray = merged.get_meta("visgroups", PackedStringArray())
	assert_true(vgs.has("vg_walls"), "Merged brush should inherit visgroups from first brush")


func test_merge_preserves_group_id():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.set_meta("group_id", "grp_01")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
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
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	sys.merge_brushes_by_ids(["b1", "b2"])
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	# In the first brush's space, which is at the origin, the second brush's far
	# side is at x = 32 + 16. Taken without its offset it would be at 16.
	var far = _face_towards(merged, Vector3.RIGHT)
	for v in far.local_verts:
		assert_almost_eq(v.x, 48.0, 0.001, "the second brush's far side, offset by its position")


func test_merge_three_brushes():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b3")
	sys.merge_brushes_by_ids(["b1", "b2", "b3"])
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 1, "Merge of 3 brushes should produce 1 brush")
	var merged = children[0] as DraftBrush
	# Three boxes in a row are one box: no face where any two of them touched.
	assert_eq(merged.faces.size(), 6, "three boxes in a row merge into one box")
	var box := AABB(Vector3(-16, -16, -16), Vector3(96, 32, 32))
	for face in merged.faces:
		assert_true(_on_shell(face, box), "%s lies on the outside" % [face.local_verts])


## A merged brush keeps the default drag size whatever it holds, and the touch
## check read that rather than its faces, so a box against the far end of a brush
## just merged was refused as not touching it.
func test_a_box_against_the_far_end_of_a_merged_brush_merges_into_it():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "b3")
	var result = sys.merge_brushes_by_ids([str(merged.brush_id), "b3"])
	assert_true(result.ok, result.message)
	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 1, "one brush")
	assert_eq((children[0] as DraftBrush).faces.size(), 6, "and it is one box")


## The hull of an L of three boxes fills the corner the mapper left empty, so the
## merge refuses it and says why, and leaves the three boxes alone.
func test_merge_refuses_an_l_of_three_boxes():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	_make_brush(Vector3(0, 32, 0), Vector3(32, 32, 32), "b3")
	var check = sys.can_merge_brushes(["b1", "b2", "b3"])
	assert_false(check.ok, "an L is not convex")
	assert_string_contains(check.user_text(), "not be convex")
	var result = sys.merge_brushes_by_ids(["b1", "b2", "b3"])
	assert_false(result.ok, "refused on a redo as well")
	assert_eq(root.draft_brushes_node.get_child_count(), 3, "nothing was merged")


## Two posts and a lintel: every face of their hull lies on a face plane of one of
## them, so only checking the hull's planes would let it through, and the merge
## would fill the doorway.
func test_merge_refuses_a_doorway_its_hull_would_fill():
	_make_brush(Vector3(-32, 0, 0), Vector3(32, 64, 32), "post_a")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 64, 32), "post_b")
	_make_brush(Vector3(0, 48, 0), Vector3(96, 32, 32), "lintel")
	var check = sys.can_merge_brushes(["post_a", "post_b", "lintel"])
	assert_false(check.ok, "the doorway is empty, and a merged brush would fill it")
	assert_string_contains(check.user_text(), "not be convex")


func test_merge_of_overlapping_boxes_is_the_box_they_make():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "b2")
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok, "overlapping is the ordinary case")
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	assert_eq(merged.faces.size(), 6)
	var box := AABB(Vector3(-16, -16, -16), Vector3(48, 32, 32))
	for face in merged.faces:
		assert_true(_on_shell(face, box), "%s lies on the outside" % [face.local_verts])


## Brushes this close count as touching, and the merge closes the seam between
## them rather than calling the result a shape with a gap in it.
func test_merge_closes_a_seam_thinner_than_touching_allows():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32.0015, 0, 0), Vector3(32, 32, 32), "b2")
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	assert_eq(merged.faces.size(), 6)


# ===========================================================================
# Merge: return value
# ===========================================================================


func test_merge_returns_success():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	var result = sys.merge_brushes_by_ids(["b1", "b2"])
	assert_true(result.ok, "Merge should return success")


func test_merge_single_brush_returns_failure():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var result = sys.merge_brushes_by_ids(["b1"])
	assert_false(result.ok, "Merge of single brush should fail")


func test_merge_positioned_at_first_brush():
	_make_brush(Vector3(10, 20, 30), Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(42, 20, 30), Vector3(32, 32, 32), "b2")
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
	# Second brush twice as long in Z, turned 90 degrees around Y so that it lies
	# along X beside the first, and they make one 96 x 32 x 32 box.
	var b2 = _make_brush(Vector3(48, 0, 0), Vector3(32, 32, 64), "b2")
	b2.rebuild_preview()
	_face_towards(b2, Vector3.RIGHT).material_idx = 7
	b2.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(48, 0, 0))
	# Its local +X face turns to -Z, and is the larger part of the merged brush's
	# -Z face, so that face takes its look. Read through the wrong basis, it would
	# be some other side.
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	assert_eq(merged.faces.size(), 6)
	assert_eq(
		_face_towards(merged, Vector3.FORWARD).material_idx,
		7,
		"Rotated brush faces should be transformed into merged space"
	)


func test_merge_rotated_brush_transforms_verts():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	# b2 at origin, longer in X than the first, and rotated 90 degrees around Y
	var b2 = _make_brush(Vector3.ZERO, Vector3(64, 32, 32), "b2")
	b2.rebuild_preview()
	# Capture b2's +X face verts before rotation (should have x=32)
	var pre_max_x: float = -INF
	for face in b2.faces:
		for v in face.local_verts:
			pre_max_x = maxf(pre_max_x, v.x)
	b2.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	# After 90-deg Y rotation, local +X(32) → world -Z(32), and the first brush
	# lies inside the second. Merged local = world (first brush is identity at origin).
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	var max_abs_z: float = 0.0
	var max_abs_x: float = 0.0
	for face in merged.faces:
		for v in face.local_verts:
			max_abs_z = maxf(max_abs_z, absf(v.z))
			max_abs_x = maxf(max_abs_x, absf(v.x))
	assert_almost_eq(
		max_abs_z,
		pre_max_x,
		0.5,
		"Rotated brush verts should map X extent to Z extent in merged space"
	)
	assert_almost_eq(max_abs_x, 16.0, 0.5, "and its X extent is the first brush's")


func test_merge_preserves_transform_of_merged_brush():
	# First brush is rotated — merged brush should inherit that transform
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var rot_basis := Basis(Vector3.UP, deg_to_rad(45.0))
	b1.global_transform = Transform3D(rot_basis, Vector3(10, 20, 30))
	var b2 = _make_brush(Vector3(32, 20, 30), Vector3(32, 32, 32), "b2")
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
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
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
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	b2.material_override = mat  # Same material instance
	sys.merge_brushes_by_ids(["b1", "b2"])
	var children = root.draft_brushes_node.get_children()
	var merged = children[0] as DraftBrush
	# All faces should share the same material index
	var indices: Dictionary = {}
	for face in merged.faces:
		indices[face.material_idx] = true
	assert_eq(indices.size(), 1, "Same material should produce one index")
	assert_eq(root.material_manager.materials.size(), 1, "Same material should be registered once")


func test_merge_no_material_override_leaves_idx_unchanged():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
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


## A wedge stretched three times as tall, merged into a box. Its slope's normal
## comes out square to the slope's own corners in the merged brush (#884). The
## merge writes each face a normal carried by the basis alone, which leans on a
## stretched slope, but the merged brush recomputes every normal from its corners
## when it rebuilds, so the lean never survives. This pins that.
func test_merge_keeps_a_stretched_slope_normal_square_to_its_corners():
	# As tall as the stretched wedge, whose high side it stands against, so the
	# two make one convex solid and the merge accepts them.
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 96, 32), "b1")
	b1.rebuild_preview()
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	b2.shape = root.BrushShape.WEDGE
	b2.scale = Vector3(1, 3, 1)
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok, "the merge went through")
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	var slopes := 0
	for i in merged.faces.size():
		var face = merged.faces[i]
		var n: Vector3 = face.normal
		if absf(n.x) > 0.99 or absf(n.y) > 0.99 or absf(n.z) > 0.99:
			continue
		slopes += 1
		var corners: PackedVector3Array = face.local_verts
		for k in corners.size():
			var edge: Vector3 = (corners[(k + 1) % corners.size()] - corners[k]).normalized()
			assert_almost_eq(n.dot(edge), 0.0, 1e-4, "edge %d of the slope" % k)
	assert_eq(slopes, 1, "the wedge brought its slope into the merge")


# ===========================================================================
# Merge: what the rest of the plugin makes of the merged brush (#1200)
# ===========================================================================


func _merge_two_boxes() -> DraftBrush:
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	return root.draft_brushes_node.get_children()[0] as DraftBrush


func test_a_merged_box_draws_nothing_from_validate_or_check_issues():
	var merged := _merge_two_boxes()
	for issue in root.validate_level(false).get("issues", []):
		assert_false(str(issue).contains(merged.name), "Validate: %s" % str(issue))
	for issue in root.validation_system.check_bake_issues():
		assert_ne(issue.get("node"), merged, "Check Issues: %s" % str(issue.get("message")))


## To a Quake family tool a brush is the space behind all its planes, so a plane
## with some of the brush in front of it cuts the brush, and two facing opposite
## ways through its middle leave nothing.
func test_a_merged_box_exports_no_plane_through_its_inside():
	_merge_two_boxes()
	var path := "user://hf_test_merge_planes.map"
	assert_eq(root.export_map(path), OK)
	var text := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var number := RegEx.new()
	number.compile("\\(\\s*(\\S+)\\s+(\\S+)\\s+(\\S+)\\s*\\)")
	var planes: Array = []
	var points: Array = []
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("("):
			continue
		var corners: Array = []
		for found in number.search_all(line):
			corners.append(
				Vector3(
					float(found.get_string(1)),
					float(found.get_string(2)),
					float(found.get_string(3))
				)
			)
		points.append_array(corners)
		planes.append(Plane(corners[0], corners[1], corners[2]))
	assert_eq(planes.size(), 6, "one plane for each side of the box")
	for plane in planes:
		var ahead := 0
		var behind := 0
		for point in points:
			var distance: float = plane.distance_to(point)
			if distance > 0.01:
				ahead += 1
			elif distance < -0.01:
				behind += 1
		assert_true(ahead == 0 or behind == 0, "%s has the whole brush on one side" % plane)


func test_merge_keeps_the_look_of_each_outer_face():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	var b2 = _make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	b2.rebuild_preview()
	_face_towards(b1, Vector3.LEFT).material_idx = 1
	_face_towards(b2, Vector3.RIGHT).material_idx = 2
	_face_towards(b2, Vector3.RIGHT).map_texture = "AAATRIGGER"
	# The two tops are one face now, and as large as each other: the first
	# brush selected gives it its look.
	_face_towards(b1, Vector3.UP).material_idx = 3
	_face_towards(b2, Vector3.UP).material_idx = 4
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	assert_eq(_face_towards(merged, Vector3.LEFT).material_idx, 1)
	assert_eq(_face_towards(merged, Vector3.RIGHT).material_idx, 2)
	assert_eq(_face_towards(merged, Vector3.RIGHT).map_texture, "AAATRIGGER")
	assert_eq(_face_towards(merged, Vector3.UP).material_idx, 3)


## A face that grew keeps its texture where it was, and lays it on across the
## corners it gained the way it was laid on before.
func test_a_joined_face_carries_its_custom_uvs_across_its_new_corners():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	var top = _face_towards(b1, Vector3.UP)
	var uvs := PackedVector2Array()
	for v in top.local_verts:
		uvs.append(Vector2(v.x * 0.25 + 3.0, v.z * 0.5 - 1.0))
	top.custom_uvs = uvs
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	var joined = _face_towards(merged, Vector3.UP)
	assert_eq(joined.custom_uvs.size(), joined.local_verts.size(), "one UV for each corner")
	for i in joined.local_verts.size():
		var v: Vector3 = joined.local_verts[i]
		assert_almost_eq(
			joined.custom_uvs[i], Vector2(v.x * 0.25 + 3.0, v.z * 0.5 - 1.0), Vector2(0.001, 0.001)
		)


func test_a_face_left_whole_keeps_its_sculpt():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	var sculpt := HFDisplacementData.new()
	sculpt.init_flat(2)
	sculpt.set_distance(1, 2, 4.0)
	var end = _face_towards(b1, Vector3.LEFT)
	# Its corners start one along from where a box's own face starts them, so the
	# merge has to keep them as they were rather than happen to build them so.
	var at: PackedVector3Array = end.local_verts
	end.local_verts = PackedVector3Array([at[1], at[2], at[3], at[0]])
	end.displacement = sculpt
	var corners: PackedVector3Array = end.local_verts
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	var kept = _face_towards(merged, Vector3.LEFT)
	assert_eq(kept.local_verts, corners, "the same corners, in the order the sculpt is laid on")
	assert_not_null(kept.displacement)
	assert_almost_eq(kept.displacement.get_distance(1, 2), 4.0, 0.0001)


## The two tops are one face now, with corners the sculpt was not laid on, so the
## sculpt cannot follow, and the merge says so rather than dropping it quietly.
func test_a_sculpt_on_a_face_that_grew_is_dropped_and_said_so():
	HFLog.begin_test_capture(["could not keep"])
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b1.rebuild_preview()
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	var sculpt := HFDisplacementData.new()
	sculpt.init_flat(2)
	_face_towards(b1, Vector3.UP).displacement = sculpt
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	var merged = root.draft_brushes_node.get_children()[0] as DraftBrush
	assert_null(_face_towards(merged, Vector3.UP).displacement)
	var warnings := HFLog.get_captured_warnings()
	assert_eq(warnings.size(), 1, "one warning")
	if warnings.size() == 1:
		assert_string_contains(warnings[0], "Merge could not keep 1 sculpt(s)")


func test_undo_of_a_merge_puts_both_boxes_back():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	_make_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "b2")
	var before: Dictionary = root.state_system.capture_state()
	assert_true(sys.merge_brushes_by_ids(["b1", "b2"]).ok)
	root.state_system.restore_state(before)
	assert_eq(root.draft_brushes_node.get_child_count(), 2, "two brushes again")
	for pair in [["b1", Vector3.ZERO], ["b2", Vector3(32, 0, 0)]]:
		var brush = sys.find_brush_by_id(pair[0])
		assert_not_null(brush, "%s is back" % pair[0])
		assert_almost_eq(brush.global_position, pair[1], Vector3(0.001, 0.001, 0.001))
		assert_eq(brush.faces.size(), 6, "%s is a box again" % pair[0])
