extends GutTest

## Free transform against the systems it has to survive: the baker, the save
## format, the brush-info round trip undo uses, and the axis-aligned guards on
## hollow, clip and carve.
##
## The winding checks here are the point of the suite. A mirror is the one
## operation in the feature that can produce inside-out geometry, and inside-out
## geometry is invisible until something bakes it.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFTransformSystemScript = preload("res://addons/hammerforge/systems/hf_transform_system.gd")
const BakerScript = preload("res://addons/hammerforge/baker.gd")
const HFLevelIOScript = preload("res://addons/hammerforge/hflevel_io.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const MatMgrScript = preload("res://addons/hammerforge/material_manager.gd")

var root: Node3D
var brushes: HFBrushSystem
var sys
var baker


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
	sys = HFTransformSystemScript.new(root)
	baker = BakerScript.new()
	add_child_autoqfree(baker)


func after_each():
	root = null
	brushes = null
	sys = null
	baker = null


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


## Bake one brush and return every triangle as an array of three world vertices.
func _baked_triangles(brush: DraftBrush) -> Array:
	var mat_mgr = MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	var result = baker.bake_from_faces([brush], mat_mgr)
	assert_not_null(result, "bake produced no geometry")
	if result == null:
		return []
	add_child_autoqfree(result)
	var triangles: Array = []
	for child in result.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh: Mesh = (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		var node_xform: Transform3D = (child as MeshInstance3D).transform
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# An unindexed surface stores null here rather than an empty array.
			var raw_indices = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = (
				raw_indices if raw_indices is PackedInt32Array else PackedInt32Array()
			)
			if indices.is_empty():
				for i in range(0, verts.size() - 2, 3):
					(
						triangles
						. append(
							[
								node_xform * verts[i],
								node_xform * verts[i + 1],
								node_xform * verts[i + 2],
							]
						)
					)
			else:
				for i in range(0, indices.size() - 2, 3):
					(
						triangles
						. append(
							[
								node_xform * verts[indices[i]],
								node_xform * verts[indices[i + 1]],
								node_xform * verts[indices[i + 2]],
							]
						)
					)
	return triangles


## Every baked triangle of a convex brush should face away from its centre.
##
## `(c - a).cross(b - a)` is the same convention `FaceData._compute_normal()`
## uses, which is the outward normal for the clockwise winding Godot's
## `POLYGON_FRONT_FACE_CLOCKWISE` expects. A mirrored basis with a negative
## determinant would flip every one of these inward.
func _outward_triangle_ratio(brush: DraftBrush) -> float:
	var triangles := _baked_triangles(brush)
	if triangles.is_empty():
		return -1.0
	# Measure against the mesh's own vertex average, not the brush origin. For a
	# convex solid the vertex average is strictly interior, so every outward
	# normal must point away from it. A wedge's origin is the box centre, which
	# sits *on* the sloped face — using it would fail a correctly wound face.
	var centre := Vector3.ZERO
	var vertex_count := 0
	for tri in triangles:
		for v in tri:
			centre += v
			vertex_count += 1
	if vertex_count == 0:
		return -1.0
	centre /= float(vertex_count)
	var outward := 0
	var counted := 0
	for tri in triangles:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var normal: Vector3 = (c - a).cross(b - a)
		if normal.length() < 0.0001:
			continue
		var to_face: Vector3 = ((a + b + c) / 3.0) - centre
		if to_face.length() < 0.0001:
			continue
		counted += 1
		if normal.normalized().dot(to_face.normalized()) > 0.0:
			outward += 1
	return float(outward) / float(counted) if counted > 0 else -1.0


# ===========================================================================
# Bake: rotation
# ===========================================================================


func test_a_rotated_brush_bakes_to_rotated_world_geometry():
	var b := _make_brush(Vector3.ZERO, Vector3(64, 8, 8), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	var triangles := _baked_triangles(b)
	assert_gt(triangles.size(), 0, "rotated brush produced no triangles")
	var extent := AABB()
	var seeded := false
	for tri in triangles:
		for v in tri:
			if seeded:
				extent = extent.expand(v)
			else:
				extent = AABB(v, Vector3.ZERO)
				seeded = true
	# The long axis started along X and should now lie along Z.
	assert_almost_eq(extent.size.x, 8.0, 0.01, "long axis should have left X")
	assert_almost_eq(extent.size.z, 64.0, 0.01, "long axis should have arrived on Z")


func test_a_rotated_brush_still_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 16, 8), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	assert_almost_eq(
		_outward_triangle_ratio(b), 1.0, 0.0001, "rotation must not invert any triangle"
	)


# ===========================================================================
# Bake: the winding risk in flip
# ===========================================================================


func test_an_untouched_box_bakes_outward_facing_triangles():
	# The control. If this ever fails the winding check below proves nothing.
	var b := _make_brush(Vector3.ZERO, Vector3(32, 16, 8), "c1")
	assert_almost_eq(_outward_triangle_ratio(b), 1.0, 0.0001)


func test_a_flipped_box_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1")
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_almost_eq(
		_outward_triangle_ratio(b), 1.0, 0.0001, "a mirrored brush must not render inside out"
	)


func test_an_untouched_wedge_bakes_outward_facing_triangles():
	# The control for the wedge cases below. Without it a failure there cannot be
	# told apart from the measurement being wrong for this shape.
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "c2", DraftBrush.BrushShape.WEDGE)
	assert_almost_eq(_outward_triangle_ratio(b), 1.0, 0.0001)


func test_a_flipped_wedge_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_almost_eq(
		_outward_triangle_ratio(b), 1.0, 0.0001, "the baked-in mirror path must reverse winding too"
	)


func test_a_flipped_then_rotated_brush_bakes_outward_facing_triangles():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	sys.rotate(["f1"], [], 1, deg_to_rad(41.0), Vector3.ZERO)
	sys.flip(["f1"], [], 2, Vector3(10, 0, 0))
	assert_almost_eq(
		_outward_triangle_ratio(b),
		1.0,
		0.0001,
		"stacking transforms must not accumulate an inversion"
	)


func test_a_flipped_brush_keeps_a_positive_determinant_through_a_long_mixed_run():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1")
	for i in 12:
		sys.rotate(["f1"], [], i % 3, deg_to_rad(29.0), Vector3(5, 0, -5))
		sys.flip(["f1"], [], i % 3, Vector3(-3, 2, 1))
	var basis := b.global_transform.basis
	assert_gt(basis.determinant(), 0.0, "handedness must survive a long mixed run")
	assert_true(
		basis.orthonormalized().is_equal_approx(basis), "the basis must stay a pure rotation"
	)


# ===========================================================================
# Persistence
# ===========================================================================


func test_a_rotated_transform_survives_the_hflevel_encoding():
	var b := _make_brush(Vector3(48, 12, -7), Vector3(32, 16, 8), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	var before := b.global_transform
	var encoded = HFLevelIOScript.encode_variant(before)
	var decoded = HFLevelIOScript.decode_variant(encoded)
	assert_true(decoded is Transform3D, "a brush transform must survive the save format")
	assert_true((decoded as Transform3D).is_equal_approx(before))


func test_a_rotated_brush_survives_the_info_round_trip_undo_uses():
	var b := _make_brush(Vector3(48, 12, -7), Vector3(32, 16, 8), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	var before := b.global_transform
	var info: Dictionary = brushes.get_brush_info_from_node(b)
	assert_true(info.has("transform"), "brush info must carry the basis, not just a centre")
	brushes.delete_brush(b)
	info["brush_id"] = "r2"
	var restored = brushes.create_brush_from_info(info)
	assert_not_null(restored)
	assert_true(
		restored.global_transform.is_equal_approx(before), "undo would lose the rotation otherwise"
	)


func test_a_flipped_brush_survives_the_info_round_trip():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	var before := b.global_transform
	var before_verts: PackedVector3Array = b.get_faces()[0].local_verts
	var info: Dictionary = brushes.get_brush_info_from_node(b)
	brushes.delete_brush(b)
	info["brush_id"] = "f2"
	var restored = brushes.create_brush_from_info(info)
	assert_not_null(restored)
	assert_true(restored.global_transform.is_equal_approx(before))
	assert_eq(
		Array(restored.get_faces()[0].local_verts),
		Array(before_verts),
		"the baked-in mirror must round trip with the faces"
	)


# ===========================================================================
# What rotation costs the operations that used to refuse it
# ===========================================================================
#
# These once pinned `HFBrushSystem._check_axis_aligned_box()`, the guard that
# refused hollow, clip and carve on any rotated brush. Precision cutting removed
# it for clip and carve, and the generators wave removed it altogether — hollow
# now runs the same progressive remainder against the brush's own inset planes,
# so rotation costs it nothing either. The guard is gone, and what these check now
# is that nothing refuses a rotated brush any more.


func test_no_operation_refuses_a_rotated_brush_any_more():
	_make_brush(Vector3.ZERO, Vector3(64, 64, 64), "g1")
	sys.rotate(["g1"], [], 1, deg_to_rad(30.0), Vector3.ZERO)
	assert_true(brushes.can_hollow_brush("g1", 4.0).ok, "hollow works in the brush's own frame now")
	assert_true(brushes.can_clip_brush("g1", 0, 0.0).ok, "clip handles rotation")


func test_a_quarter_turned_box_can_still_be_hollowed():
	# The case the guard was strictest about: a quarter turn swaps which world
	# axis each extent belongs to, which used to matter because hollow read world
	# extents off `size`. It insets the brush's own faces now.
	_make_brush(Vector3.ZERO, Vector3(64, 32, 16), "g1")
	sys.rotate(["g1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_true(brushes.can_hollow_brush("g1", 4.0).ok)


func test_hollow_still_refuses_a_wall_that_would_leave_no_room():
	# The refusals that remain are about the numbers, not about the rotation.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "g1")
	sys.rotate(["g1"], [], 1, deg_to_rad(30.0), Vector3.ZERO)
	var result = brushes.can_hollow_brush("g1", 64.0)
	assert_false(result.ok, "a wall thicker than the brush has to be refused")
	assert_ne(result.fix_hint, "", "a refusal must tell the user what to do about it")


func test_reset_after_a_quarter_turn_keeps_the_geometry_and_permutes_the_size():
	var b := _make_brush(Vector3.ZERO, Vector3(64, 32, 16), "g1")
	sys.rotate(["g1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	var before := AABB()
	var seeded := false
	for tri in _baked_triangles(b):
		for v in tri:
			if seeded:
				before = before.expand(v)
			else:
				before = AABB(v, Vector3.ZERO)
				seeded = true
	sys.reset_rotation(["g1"])
	assert_true(
		b.global_transform.basis.is_equal_approx(Basis.IDENTITY),
		"a quarter turn must clear to an identity basis"
	)
	assert_almost_eq(b.size.x, 16.0, 0.001, "the 64-unit extent moved to Z, so X keeps 16")
	assert_almost_eq(b.size.y, 32.0, 0.001)
	assert_almost_eq(b.size.z, 64.0, 0.001)
	var after := AABB()
	seeded = false
	for tri in _baked_triangles(b):
		for v in tri:
			if seeded:
				after = after.expand(v)
			else:
				after = AABB(v, Vector3.ZERO)
				seeded = true
	assert_almost_eq(after.size.x, before.size.x, 0.01, "reset must not resize the brush")
	assert_almost_eq(after.size.y, before.size.y, 0.01)
	assert_almost_eq(after.size.z, before.size.z, 0.01)


func test_axis_permutation_is_empty_for_a_general_rotation():
	assert_eq(
		HFTransformSystemScript.axis_permutation(Basis(Vector3.UP, deg_to_rad(37.0))).size(), 0
	)


func test_axis_permutation_reads_a_quarter_turn():
	var mapping := HFTransformSystemScript.axis_permutation(Basis(Vector3.UP, deg_to_rad(90.0)))
	assert_eq(mapping.size(), 3)
	assert_eq(mapping[0], 2, "local X points down world Z after a yaw of 90 degrees")
	assert_eq(mapping[1], 1)
	assert_eq(mapping[2], 0)


func test_reset_on_a_general_rotation_clears_the_basis():
	var b := _make_brush(Vector3(5, 6, 7), Vector3(64, 32, 16), "g1")
	sys.rotate(["g1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	sys.reset_rotation(["g1"])
	assert_true(b.global_transform.basis.is_equal_approx(Basis.IDENTITY))
	assert_almost_eq(b.size.x, 64.0, 0.001, "a general rotation leaves the size alone")


# ===========================================================================
# Awkward inputs
# ===========================================================================


func test_rotation_preserves_a_scaled_basis():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "s1")
	b.global_transform = Transform3D(
		HFTransformSystemScript.with_scale(Basis.IDENTITY, Vector3(2.0, 3.0, 4.0)), Vector3.ZERO
	)
	sys.rotate(["s1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	var scale := b.global_transform.basis.get_scale()
	assert_almost_eq(scale.x, 2.0, 0.001, "rotate must not quietly resize a scaled brush")
	assert_almost_eq(scale.y, 3.0, 0.001)
	assert_almost_eq(scale.z, 4.0, 0.001)


func test_rotation_under_a_turned_parent_still_works_in_world_space():
	root.draft_brushes_node.rotation.y = deg_to_rad(45.0)
	var b := _make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "p1")
	sys.rotate(["p1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_almost_eq(b.global_position.x, 0.0, 0.01)
	assert_almost_eq(b.global_position.z, -100.0, 0.01)


func test_flip_across_each_axis_negates_only_that_coordinate():
	var expected := [Vector3(-40, 20, 10), Vector3(40, -20, 10), Vector3(40, 20, -10)]
	for axis in 3:
		var b := _make_brush(Vector3(40, 20, 10), Vector3(32, 32, 32), "a%d" % axis)
		sys.flip(["a%d" % axis], [], axis, Vector3.ZERO)
		assert_true(
			b.global_position.is_equal_approx(expected[axis]),
			"axis %d gave %s" % [axis, b.global_position]
		)


func test_flip_preserves_custom_uvs_on_a_custom_brush():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	var face = b.get_faces()[0]
	face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	)
	face.custom_uvs = PackedVector2Array(
		[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_eq(
		face.custom_uvs.size(),
		face.local_verts.size(),
		"UVs must stay paired with the vertices they belong to"
	)


func test_mirror_face_handles_a_triangle():
	var face = FaceDataScript.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 2)])
	HFTransformSystemScript.mirror_face(face, 0)
	assert_eq(face.local_verts.size(), 3)
	assert_true(face.local_verts[0].is_equal_approx(Vector3(0, 0, 2)))
	assert_true(face.local_verts[2].is_equal_approx(Vector3(0, 0, 0)))


func test_mirror_face_tolerates_an_empty_face():
	var face = FaceDataScript.new()
	HFTransformSystemScript.mirror_face(face, 0)
	assert_eq(face.local_verts.size(), 0)


func test_mirror_face_tolerates_a_null_entry():
	HFTransformSystemScript.mirror_faces([null], 0)
	pass_test("mirroring a face list with a hole in it must not crash")


func test_an_out_of_range_axis_is_refused():
	# It used to fall through to Z, so a caller with the wrong index mirrored the
	# selection about an axis it never asked for.
	var b := _make_brush(Vector3(40, 0, 10), Vector3(32, 32, 32), "z1")
	assert_eq(sys.flip(["z1"], [], 99, Vector3.ZERO), 0)
	assert_almost_eq(b.global_position.z, 10.0, 0.001)
	assert_almost_eq(b.global_position.x, 40.0, 0.001)


func test_an_entity_angle_stored_as_an_int_still_rotates():
	var e = DraftEntity.new()
	e.name = "IntAngle"
	root.add_child(e)
	e.entity_data = {"angle": 10}
	sys.rotate([], [str(root.get_path_to(e))], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_almost_eq(float(e.entity_data["angle"]), 100.0, 0.001)


func test_a_missing_entity_path_is_skipped():
	assert_eq(sys.rotate([], ["NoSuchNode"], 1, deg_to_rad(90.0), Vector3.ZERO), 0)
	assert_eq(sys.flip([], ["NoSuchNode"], 0, Vector3.ZERO), 0)


func test_a_transform_system_without_a_root_does_not_crash():
	var orphan = HFTransformSystemScript.new(null)
	assert_eq(orphan.rotate(["a"], ["b"], 1, deg_to_rad(90.0), Vector3.ZERO), 0)
	assert_eq(orphan.flip(["a"], ["b"], 0, Vector3.ZERO), 0)
	assert_eq(orphan.reset_rotation(["a"]), 0)
	assert_true(orphan.resolve_pivot(["a"], [], 0).is_equal_approx(Vector3.ZERO))


func test_a_degenerate_brush_flips_without_crashing():
	var b := _make_brush(Vector3.ZERO, Vector3(0.1, 0.1, 0.1), "d1")
	sys.flip(["d1"], [], 0, Vector3.ZERO)
	assert_gt(b.global_transform.basis.determinant(), 0.0)
