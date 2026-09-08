extends GutTest

## Free transform: rotate, flip, reset rotation, and the pivots they use.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFTransformSystemScript = preload("res://addons/hammerforge/systems/hf_transform_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")

const EPS := 0.0001

var root: Node3D
var brushes: HFBrushSystem
var sys


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


func after_each():
	root = null
	brushes = null
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


func _make_entity(pos: Vector3 = Vector3.ZERO, name_hint: String = "Ent") -> DraftEntity:
	var e = DraftEntity.new()
	e.name = name_hint
	root.add_child(e)
	e.global_position = pos
	return e


func _entity_path(e: Node) -> String:
	return str(root.get_path_to(e))


## Every face vertex of a brush, in world space.
func _world_verts(draft: DraftBrush) -> Array:
	var out: Array = []
	var xform := draft.global_transform
	for face in draft.get_faces():
		if face == null:
			continue
		for v in face.local_verts:
			out.append(xform * v)
	return out


## Compare two transforms at a tolerance that means something for a level editor.
##
## Exact equality is not available: a 90-degree turn goes through sin and cos, so
## composing four of them at a 64-unit radius leaves about 1e-5 of float error —
## just past what `is_equal_approx` allows. A thousandth of a unit is far below
## the smallest grid the editor offers.
func assert_transform_close(actual: Transform3D, expected: Transform3D, msg: String) -> void:
	assert_almost_eq(actual.origin.x, expected.origin.x, 0.001, msg + " (origin x)")
	assert_almost_eq(actual.origin.y, expected.origin.y, 0.001, msg + " (origin y)")
	assert_almost_eq(actual.origin.z, expected.origin.z, 0.001, msg + " (origin z)")
	for i in 3:
		var a: Vector3 = HFTransformSystemScript.basis_axis(actual.basis, i)
		var b: Vector3 = HFTransformSystemScript.basis_axis(expected.basis, i)
		assert_almost_eq(a.dot(b), 1.0, 0.001, msg + " (basis axis %d)" % i)


func _sorted_points(points: Array) -> Array:
	var keys: Array = []
	for p in points:
		keys.append("%.3f,%.3f,%.3f" % [p.x, p.y, p.z])
	keys.sort()
	return keys


# ===========================================================================
# Pure geometry
# ===========================================================================


func test_axis_vector_maps_indices():
	assert_eq(HFTransformSystemScript.axis_vector(0), Vector3.RIGHT)
	assert_eq(HFTransformSystemScript.axis_vector(1), Vector3.UP)
	assert_eq(HFTransformSystemScript.axis_vector(2), Vector3.BACK)


func test_rotation_basis_stays_orthonormal_and_right_handed():
	for axis in 3:
		var b: Basis = HFTransformSystemScript.rotation_basis(axis, deg_to_rad(37.0))
		assert_almost_eq(b.determinant(), 1.0, EPS, "axis %d determinant" % axis)
		assert_true(
			b.orthonormalized().is_equal_approx(b), "axis %d basis should already be orthonormal"
		)


func test_reflection_basis_has_negative_determinant():
	for axis in 3:
		var b: Basis = HFTransformSystemScript.reflection_basis(axis)
		assert_almost_eq(b.determinant(), -1.0, EPS, "axis %d determinant" % axis)


func test_rotated_transform_about_pivot_moves_offset_origin():
	var xform := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var rot: Basis = HFTransformSystemScript.rotation_basis(1, deg_to_rad(90.0))
	var out: Transform3D = HFTransformSystemScript.rotated_transform(xform, rot, Vector3.ZERO)
	# +X rotated 90 degrees about +Y lands on -Z in Godot's right-handed frame.
	assert_almost_eq(out.origin.x, 0.0, 0.001)
	assert_almost_eq(out.origin.z, -10.0, 0.001)


func test_rotated_transform_about_own_origin_leaves_origin():
	var xform := Transform3D(Basis.IDENTITY, Vector3(10, 5, -3))
	var rot: Basis = HFTransformSystemScript.rotation_basis(1, deg_to_rad(90.0))
	var out: Transform3D = HFTransformSystemScript.rotated_transform(xform, rot, xform.origin)
	assert_true(out.origin.is_equal_approx(xform.origin))


func test_flipped_transform_keeps_determinant_positive():
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(4, 0, 0))
	for axis in 3:
		var local_axis: int = HFTransformSystemScript.local_mirror_axis(xform.basis, axis)
		var out: Transform3D = HFTransformSystemScript.flipped_transform(
			xform, axis, Vector3.ZERO, local_axis
		)
		assert_true(out.basis.determinant() > 0.0, "axis %d must not leave a mirrored basis" % axis)


func test_local_mirror_axis_picks_the_aligned_axis():
	var basis := Basis.IDENTITY
	assert_eq(HFTransformSystemScript.local_mirror_axis(basis, 0), 0)
	assert_eq(HFTransformSystemScript.local_mirror_axis(basis, 1), 1)
	assert_eq(HFTransformSystemScript.local_mirror_axis(basis, 2), 2)
	# Turn the brush 90 degrees about Y: its local X now points down world Z.
	var turned := Basis(Vector3.UP, deg_to_rad(90.0))
	assert_eq(HFTransformSystemScript.local_mirror_axis(turned, 2), 0)


func test_mirror_face_applied_twice_is_identity():
	var face = FaceDataScript.new()
	face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(2, 0, 1), Vector3(2, 0, -1)]
	)
	face.custom_uvs = PackedVector2Array(
		[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	)
	var original: PackedVector3Array = face.local_verts.duplicate()
	var original_uvs: PackedVector2Array = face.custom_uvs.duplicate()
	HFTransformSystemScript.mirror_face(face, 0)
	HFTransformSystemScript.mirror_face(face, 0)
	assert_eq(Array(face.local_verts), Array(original))
	assert_eq(Array(face.custom_uvs), Array(original_uvs))


func test_mirror_face_reverses_vertex_order():
	var face = FaceDataScript.new()
	face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1)]
	)
	HFTransformSystemScript.mirror_face(face, 0)
	# Last vertex mirrored along X becomes the first.
	assert_true(face.local_verts[0].is_equal_approx(Vector3(-1, 0, -1)))
	assert_true(face.local_verts[1].is_equal_approx(Vector3(-1, 0, 1)))


func test_rotated_angle_wraps():
	assert_almost_eq(HFTransformSystemScript.rotated_angle(350.0, 20.0), 10.0, EPS)
	assert_almost_eq(HFTransformSystemScript.rotated_angle(10.0, -20.0), 350.0, EPS)


func test_mirrored_angle_per_axis():
	assert_almost_eq(HFTransformSystemScript.mirrored_angle(30.0, 0), 330.0, EPS)
	assert_almost_eq(HFTransformSystemScript.mirrored_angle(30.0, 1), 30.0, EPS)
	assert_almost_eq(HFTransformSystemScript.mirrored_angle(30.0, 2), 150.0, EPS)


# ===========================================================================
# Rotate
# ===========================================================================


func test_four_quarter_turns_return_the_original_transform():
	for axis in 3:
		var b := _make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "spin_%d" % axis)
		var before := b.global_transform
		for _i in 4:
			sys.rotate(["spin_%d" % axis], [], axis, deg_to_rad(90.0), Vector3.ZERO)
		assert_transform_close(
			b.global_transform, before, "axis %d: four quarter turns should come home" % axis
		)


func test_rotate_keeps_basis_orthonormal():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "r1")
	for _i in 200:
		sys.rotate(["r1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	var basis := b.global_transform.basis
	assert_almost_eq(
		basis.determinant(), 1.0, 0.0001, "compounding float error must not creep in as scale"
	)
	assert_true(
		basis.orthonormalized().is_equal_approx(basis),
		"a rotated brush must never come out sheared"
	)


func test_rotate_about_selection_pivot_swings_an_offset_brush():
	var b := _make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_almost_eq(b.global_position.x, 0.0, 0.001)
	assert_almost_eq(b.global_position.z, -100.0, 0.001)


func test_rotate_reports_changed_count():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "r1")
	_make_brush(Vector3(64, 0, 0), Vector3(32, 32, 32), "r2")
	var changed: int = sys.rotate(["r1", "r2", "missing"], [], 1, deg_to_rad(45.0), Vector3.ZERO)
	assert_eq(changed, 2, "missing brushes must not be counted")


func test_rotate_by_zero_is_a_no_op():
	var b := _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "r1")
	var before := b.global_transform
	var changed: int = sys.rotate(["r1"], [], 1, 0.0, Vector3.ZERO)
	assert_eq(changed, 0)
	assert_true(b.global_transform.is_equal_approx(before))


func test_rotate_on_empty_selection_is_a_no_op():
	assert_eq(sys.rotate([], [], 1, deg_to_rad(90.0), Vector3.ZERO), 0)


func test_rotate_moves_entity_position_and_yaw():
	var e := _make_entity(Vector3(100, 0, 0), "Rotor")
	e.entity_data = {"angle": 10.0}
	var changed: int = sys.rotate([], [_entity_path(e)], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_eq(changed, 1)
	assert_almost_eq(e.global_position.z, -100.0, 0.001)
	assert_almost_eq(float(e.entity_data["angle"]), 100.0, 0.001)


func test_rotate_leaves_entity_angle_alone_off_the_y_axis():
	var e := _make_entity(Vector3(100, 0, 0), "Rotor")
	e.entity_data = {"angle": 10.0}
	sys.rotate([], [_entity_path(e)], 0, deg_to_rad(90.0), Vector3.ZERO)
	assert_almost_eq(float(e.entity_data["angle"]), 10.0, 0.001)


func test_rotate_ignores_entities_without_an_angle_key():
	var e := _make_entity(Vector3(100, 0, 0), "Rotor")
	e.entity_data = {"other": 3}
	sys.rotate([], [_entity_path(e)], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_false(e.entity_data.has("angle"), "rotate must not invent an angle property")


# ===========================================================================
# Texture lock
# ===========================================================================


func test_texture_lock_on_compensates_uv_rotation():
	root.texture_lock = true
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "t1")
	var face = b.get_faces()[0]
	face.uv_rotation = 0.0
	sys.rotate(["t1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_almost_eq(face.uv_rotation, -deg_to_rad(90.0), 0.001)


func test_texture_lock_off_leaves_uv_rotation():
	root.texture_lock = false
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "t1")
	var face = b.get_faces()[0]
	face.uv_rotation = 0.0
	sys.rotate(["t1"], [], 1, deg_to_rad(90.0), Vector3.ZERO)
	assert_almost_eq(face.uv_rotation, 0.0, 0.001)


# ===========================================================================
# Flip
# ===========================================================================


func test_flip_keeps_the_basis_right_handed():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1")
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_true(
		b.global_transform.basis.determinant() > 0.0,
		"a mirrored basis would render every face inside out"
	)


func test_flip_mirrors_the_world_position():
	var b := _make_brush(Vector3(48, 10, -6), Vector3(32, 32, 32), "f1")
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_almost_eq(b.global_position.x, -48.0, 0.001)
	assert_almost_eq(b.global_position.y, 10.0, 0.001)
	assert_almost_eq(b.global_position.z, -6.0, 0.001)


func test_flip_mirrors_every_world_vertex():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1")
	var expected: Array = []
	for v in _world_verts(b):
		expected.append(Vector3(-v.x, v.y, v.z))
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_eq(_sorted_points(_world_verts(b)), _sorted_points(expected))


func test_flip_twice_restores_a_box_exactly():
	var b := _make_brush(Vector3(48, 12, -7), Vector3(32, 16, 8), "f1")
	var before := b.global_transform
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_true(b.global_transform.is_equal_approx(before))


func test_flip_twice_restores_a_rotated_brush_exactly():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1")
	sys.rotate(["f1"], [], 1, deg_to_rad(30.0), Vector3.ZERO)
	var before := b.global_transform
	sys.flip(["f1"], [], 2, Vector3(10, 0, 0))
	sys.flip(["f1"], [], 2, Vector3(10, 0, 0))
	assert_true(b.global_transform.is_equal_approx(before))


func test_flip_keeps_a_box_parametric():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1")
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_eq(
		b.shape,
		DraftBrush.BrushShape.BOX,
		"a mirrored box is still a box, so it should keep its resize handles"
	)


func test_flip_promotes_an_asymmetric_shape_to_custom():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_eq(
		b.shape,
		DraftBrush.BrushShape.CUSTOM,
		"a wedge is not symmetric about its slope axis, so the mirror has to be baked in"
	)


func test_flip_mirrors_every_world_vertex_of_an_asymmetric_shape():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	var expected: Array = []
	for v in _world_verts(b):
		expected.append(Vector3(-v.x, v.y, v.z))
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_eq(_sorted_points(_world_verts(b)), _sorted_points(expected))


func test_flip_twice_restores_an_asymmetric_shape_exactly():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	var before_verts := _sorted_points(_world_verts(b))
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	assert_eq(_sorted_points(_world_verts(b)), before_verts)


func test_flip_keeps_faces_wound_clockwise_from_outside():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	var basis := b.global_transform.basis
	var centre := b.global_position
	for face in b.get_faces():
		if face == null or face.local_verts.size() < 3:
			continue
		var a: Vector3 = basis * face.local_verts[0]
		var second: Vector3 = basis * face.local_verts[1]
		var third: Vector3 = basis * face.local_verts[2]
		# Same cross-product convention as FaceData._compute_normal().
		var normal := (third - a).cross(second - a).normalized()
		var face_centre := (a + second + third) / 3.0 + centre
		var outward := (face_centre - centre).normalized()
		if outward.length() < 0.001:
			continue
		assert_true(
			normal.dot(outward) > -0.001,
			"face normal should point away from the brush centre after a flip"
		)


func test_flip_preserves_per_face_materials():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 16, 8), "f1", DraftBrush.BrushShape.WEDGE)
	var faces = b.get_faces()
	for i in faces.size():
		faces[i].material_idx = i
	sys.flip(["f1"], [], 0, Vector3.ZERO)
	var after = b.get_faces()
	assert_eq(after.size(), faces.size())
	for i in after.size():
		assert_eq(after[i].material_idx, i, "face %d kept its material" % i)


func test_flip_mirrors_entity_position_and_yaw():
	var e := _make_entity(Vector3(100, 0, 0), "Mirror")
	e.entity_data = {"angle": 30.0}
	var changed: int = sys.flip([], [_entity_path(e)], 0, Vector3.ZERO)
	assert_eq(changed, 1)
	assert_almost_eq(e.global_position.x, -100.0, 0.001)
	assert_almost_eq(float(e.entity_data["angle"]), 330.0, 0.001)


func test_flip_on_empty_selection_is_a_no_op():
	assert_eq(sys.flip([], [], 0, Vector3.ZERO), 0)


# ===========================================================================
# Flip pre-validation
# ===========================================================================


func test_can_flip_accepts_a_plain_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "f1")
	assert_true(sys.can_flip_brushes(["f1"]).ok)


func test_can_flip_refuses_a_displaced_brush():
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "f1")
	b.get_faces()[0].displacement = Resource.new()
	var result = sys.can_flip_brushes(["f1"])
	assert_false(result.ok)
	assert_true(result.message.contains("displacement"))
	assert_ne(result.fix_hint, "")


func test_flip_skips_a_displaced_brush():
	var b := _make_brush(Vector3(48, 0, 0), Vector3(32, 32, 32), "f1")
	b.get_faces()[0].displacement = Resource.new()
	var before := b.global_transform
	assert_eq(sys.flip(["f1"], [], 0, Vector3.ZERO), 0)
	assert_true(b.global_transform.is_equal_approx(before))


# ===========================================================================
# Reset rotation
# ===========================================================================


func test_reset_rotation_clears_the_basis_and_keeps_the_origin():
	var b := _make_brush(Vector3(48, 12, -7), Vector3(32, 32, 32), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(37.0), b.global_position)
	var origin := b.global_position
	assert_eq(sys.reset_rotation(["r1"]), 1)
	assert_true(b.global_transform.basis.is_equal_approx(Basis.IDENTITY))
	assert_true(b.global_position.is_equal_approx(origin))


func test_reset_rotation_skips_an_unrotated_brush():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "r1")
	assert_eq(sys.reset_rotation(["r1"]), 0)


func test_reset_rotation_clears_the_basis_a_rotation_put_there():
	# This once checked `HFBrushSystem._check_axis_aligned_box()`, the guard that
	# refused hollow, clip and carve on a rotated brush. That guard is gone — those
	# operations work in the brush's own frame now — so what reset rotation is for
	# is squaring a brush up, and that is what is checked.
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "r1")
	sys.rotate(["r1"], [], 1, deg_to_rad(37.0), Vector3.ZERO)
	assert_false(b.global_transform.basis.is_equal_approx(Basis.IDENTITY))
	assert_eq(sys.reset_rotation(["r1"]), 1)
	assert_true(b.global_transform.basis.is_equal_approx(Basis.IDENTITY))


# ===========================================================================
# Pivots and bounds
# ===========================================================================


func test_selection_centroid_is_the_midpoint_of_the_origins():
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "p1")
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "p2")
	var centre: Vector3 = sys.selection_origin_centroid(["p1", "p2"], [])
	assert_true(centre.is_equal_approx(Vector3(50, 0, 0)))


func test_selection_centroid_survives_rotation_about_itself():
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "p1")
	_make_brush(Vector3(100, 0, 40), Vector3(64, 32, 8), "p2")
	_make_brush(Vector3(-30, 20, 0), Vector3(8, 8, 8), "p3")
	var ids := ["p1", "p2", "p3"]
	var before: Vector3 = sys.selection_origin_centroid(ids, [])
	for _i in 5:
		var pivot: Vector3 = sys.selection_origin_centroid(ids, [])
		sys.rotate(ids, [], 1, deg_to_rad(23.0), pivot)
	var after: Vector3 = sys.selection_origin_centroid(ids, [])
	assert_almost_eq(
		after.distance_to(before),
		0.0,
		0.001,
		"an unstable pivot would walk the selection across the level"
	)


func test_repeated_quarter_turns_about_the_resolved_pivot_return_home():
	var b1 := _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "p1")
	var b2 := _make_brush(Vector3(100, 0, 40), Vector3(64, 32, 8), "p2")
	var ids := ["p1", "p2"]
	var before1 := b1.global_transform
	var before2 := b2.global_transform
	for _i in 4:
		var pivot: Vector3 = sys.resolve_pivot(ids, [], 0)
		sys.rotate(ids, [], 1, deg_to_rad(90.0), pivot)
	assert_transform_close(b1.global_transform, before1, "first brush came home")
	assert_transform_close(b2.global_transform, before2, "second brush came home")


func test_pivot_mode_world_origin():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "p1")
	assert_true(sys.resolve_pivot(["p1"], [], 1).is_equal_approx(Vector3.ZERO))


func test_pivot_mode_active_uses_the_first_brush():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "p1")
	_make_brush(Vector3(-100, 0, 0), Vector3(32, 32, 32), "p2")
	assert_true(sys.resolve_pivot(["p1", "p2"], [], 2).is_equal_approx(Vector3(100, 0, 0)))


func test_pivot_mode_custom_passes_the_point_through():
	assert_true(sys.resolve_pivot([], [], 3, Vector3(7, 8, 9)).is_equal_approx(Vector3(7, 8, 9)))


func test_pivot_on_empty_selection_is_the_origin():
	assert_true(sys.resolve_pivot([], [], 0).is_equal_approx(Vector3.ZERO))


func test_selection_bounds_covers_the_brush_extent():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var bounds: AABB = sys.selection_bounds(["b1"], [])
	assert_almost_eq(bounds.size.x, 32.0, 0.001)
	assert_almost_eq(bounds.size.y, 32.0, 0.001)
	assert_true(bounds.get_center().is_equal_approx(Vector3.ZERO))


func test_selection_bounds_grows_when_a_brush_is_turned():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var before: AABB = sys.selection_bounds(["b1"], [])
	sys.rotate(["b1"], [], 1, deg_to_rad(45.0), Vector3.ZERO)
	var after: AABB = sys.selection_bounds(["b1"], [])
	assert_gt(after.size.x, before.size.x, "a box turned 45 degrees has a wider footprint")


func test_selection_bounds_on_empty_selection_is_degenerate():
	var bounds: AABB = sys.selection_bounds([], [])
	assert_true(bounds.size.is_equal_approx(Vector3.ZERO))
