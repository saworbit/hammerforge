extends GutTest

const HFDisplacementData = preload("res://addons/hammerforge/displacement_data.gd")
const HFDisplacementSystem = preload("res://addons/hammerforge/systems/hf_displacement_system.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFDisplacementSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	sys = HFDisplacementSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var _brush_id_counter: int = 0

func find_brush_by_id(brush_id: String) -> Node3D:
	if not draft_brushes_node:
		return null
	for child in draft_brushes_node.get_children():
		if child.get("brush_id") == brush_id:
			return child
	return null

func get_all_draft_brushes() -> Array:
	if not draft_brushes_node:
		return []
	return Array(draft_brushes_node.get_children())

func mark_dirty(_brush: Node3D) -> void:
	pass
"""
	s.reload()
	return s


func _make_quad_brush(brush_id: String = "test_brush") -> Node3D:
	var brush = DraftBrush.new()
	brush.brush_id = brush_id
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(16, 0, 16), Vector3(0, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var face_arr: Array[FaceData] = [face]
	brush.faces = face_arr
	brush.geometry_dirty = false
	root.draft_brushes_node.add_child(brush)
	return brush


func _make_tri_brush(brush_id: String = "tri_brush") -> Node3D:
	var brush = DraftBrush.new()
	brush.brush_id = brush_id
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(8, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var face_arr: Array[FaceData] = [face]
	brush.faces = face_arr
	brush.geometry_dirty = false
	root.draft_brushes_node.add_child(brush)
	return brush


# ---------------------------------------------------------------------------
# HFDisplacementData unit tests
# ---------------------------------------------------------------------------


func test_init_flat_default():
	var disp = HFDisplacementData.new()
	disp.init_flat(3)
	assert_eq(disp.power, 3)
	assert_eq(disp.get_dim(), 9)
	assert_eq(disp.get_vertex_count(), 81)
	assert_eq(disp.distances.size(), 81)
	assert_eq(disp.elevation, 1.0)
	assert_eq(disp.sew_group, -1)


func test_init_flat_power_2():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	assert_eq(disp.get_dim(), 5)
	assert_eq(disp.get_vertex_count(), 25)


func test_init_flat_power_4():
	var disp = HFDisplacementData.new()
	disp.init_flat(4)
	assert_eq(disp.get_dim(), 17)
	assert_eq(disp.get_vertex_count(), 289)


func test_init_flat_clamps_power():
	var disp = HFDisplacementData.new()
	disp.init_flat(0)
	assert_eq(disp.power, 2)
	disp.init_flat(10)
	assert_eq(disp.power, 4)


func test_set_get_distance():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(2, 3, 5.0)
	assert_almost_eq(disp.get_distance(2, 3), 5.0, 0.001)
	assert_almost_eq(disp.get_distance(0, 0), 0.0, 0.001)


func test_set_get_alpha():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_alpha(1, 1, 0.75)
	assert_almost_eq(disp.get_alpha(1, 1), 0.75, 0.001)
	# Alpha clamps to [0, 1]
	disp.set_alpha(0, 0, 2.0)
	assert_almost_eq(disp.get_alpha(0, 0), 1.0, 0.001)


func test_get_displaced_position_flat():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	# Center vertex at (2,2) out of 5x5 → u=0.5, v=0.5
	var pos: Vector3 = disp.get_displaced_position(2, 2, corners, Vector3.UP)
	assert_almost_eq(pos.x, 8.0, 0.01)
	assert_almost_eq(pos.y, 0.0, 0.01)
	assert_almost_eq(pos.z, 8.0, 0.01)


func test_get_displaced_position_with_offset():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(2, 2, 3.0)
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var pos: Vector3 = disp.get_displaced_position(2, 2, corners, Vector3.UP)
	assert_almost_eq(pos.x, 8.0, 0.01)
	assert_almost_eq(pos.y, 3.0, 0.01)  # Displaced upward
	assert_almost_eq(pos.z, 8.0, 0.01)


func test_get_displaced_position_with_elevation():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(0, 0, 1.0)
	disp.elevation = 5.0
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var pos: Vector3 = disp.get_displaced_position(0, 0, corners, Vector3.UP)
	assert_almost_eq(pos.y, 5.0, 0.01)


func test_triangulate_displaced_flat():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var uv_corners: Array[Vector2] = [
		Vector2(0, 0), Vector2(1, 0),
		Vector2(0, 1), Vector2(1, 1)
	]
	var result: Dictionary = disp.triangulate_displaced(corners, Vector3.UP, uv_corners)
	var verts: PackedVector3Array = result["verts"]
	var uvs: PackedVector2Array = result["uvs"]
	var normals: PackedVector3Array = result["normals"]
	# 4x4 grid cells → 16 cells → 32 triangles → 96 vertices
	assert_eq(verts.size(), 96)
	assert_eq(uvs.size(), 96)
	assert_eq(normals.size(), 96)


func test_triangulate_displaced_power_3():
	var disp = HFDisplacementData.new()
	disp.init_flat(3)
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var uv_corners: Array[Vector2] = [
		Vector2(0, 0), Vector2(1, 0),
		Vector2(0, 1), Vector2(1, 1)
	]
	var result: Dictionary = disp.triangulate_displaced(corners, Vector3.UP, uv_corners)
	# 8x8 grid → 64 cells → 128 triangles → 384 vertices
	assert_eq(result["verts"].size(), 384)


func test_smooth():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(2, 2, 10.0)  # Spike in center
	disp.smooth(1.0)
	# After full smoothing, center should be pulled toward neighbors (all 0)
	var center: float = disp.get_distance(2, 2)
	assert_true(center < 10.0, "Center should be smoothed down")
	assert_true(center > 0.0, "Center should still be positive")


func test_smooth_no_crash_on_empty():
	var disp = HFDisplacementData.new()
	# Don't init — distances is empty
	disp.smooth(0.5)
	assert_eq(disp.distances.size(), 0, "Should remain empty without crashing")


func test_apply_noise():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 42
	disp.apply_noise(noise, 5.0)
	# At least some vertices should be non-zero
	var has_nonzero := false
	for i in range(disp.distances.size()):
		if abs(disp.distances[i]) > 0.001:
			has_nonzero = true
			break
	assert_true(has_nonzero, "Noise should produce non-zero displacements")


func test_serialization_roundtrip():
	var disp = HFDisplacementData.new()
	disp.init_flat(3)
	disp.set_distance(4, 4, 7.5)
	disp.set_alpha(0, 0, 0.3)
	disp.elevation = 2.5
	disp.sew_group = 3
	var data: Dictionary = disp.to_dict()
	var restored: HFDisplacementData = HFDisplacementData.from_dict(data)
	assert_eq(restored.power, 3)
	assert_almost_eq(restored.elevation, 2.5, 0.001)
	assert_eq(restored.sew_group, 3)
	assert_almost_eq(restored.get_distance(4, 4), 7.5, 0.001)
	assert_almost_eq(restored.get_alpha(0, 0), 0.3, 0.001)


func test_serialization_with_offsets():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_offset(1, 1, Vector3(1, 0, 0))
	var data: Dictionary = disp.to_dict()
	var restored: HFDisplacementData = HFDisplacementData.from_dict(data)
	assert_true(restored.offsets.size() > 0, "Offsets should be preserved")
	var idx: int = 1 * 5 + 1
	assert_almost_eq(restored.offsets[idx].x, 1.0, 0.001)


func test_custom_offset_direction():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(0, 0, 5.0)
	disp.set_offset(0, 0, Vector3(1, 0, 0))  # Displace along X instead of normal
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var pos: Vector3 = disp.get_displaced_position(0, 0, corners, Vector3.UP)
	assert_almost_eq(pos.x, 5.0, 0.01)  # Displaced along X
	assert_almost_eq(pos.y, 0.0, 0.01)  # Not along Y (normal)


# ---------------------------------------------------------------------------
# FaceData displacement integration tests
# ---------------------------------------------------------------------------


func test_face_triangulate_with_displacement():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(16, 0, 16), Vector3(0, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	face.displacement = disp
	var tri: Dictionary = face.triangulate()
	# Should use displaced triangulation (96 verts for power=2)
	assert_eq(tri["verts"].size(), 96)
	assert_true(tri.has("normals"), "Displaced triangulation should include normals")


func test_face_triangulate_without_displacement():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(16, 0, 16), Vector3(0, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var tri: Dictionary = face.triangulate()
	# Standard fan: 2 triangles = 6 verts
	assert_eq(tri["verts"].size(), 6)


func test_face_displacement_only_on_quads():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(8, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	face.displacement = disp
	var tri: Dictionary = face.triangulate()
	# Triangle face: displacement ignored (count != 4), falls through to fan
	assert_eq(tri["verts"].size(), 3)


func test_face_displacement_serialization_roundtrip():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(16, 0, 16), Vector3(0, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(1, 1, 3.0)
	face.displacement = disp
	var data: Dictionary = face.to_dict()
	assert_true(data.has("displacement"), "Serialized face should have displacement")
	assert_true(data["displacement"] is Dictionary)
	var restored: FaceData = FaceData.from_dict(data)
	assert_not_null(restored.displacement, "Restored face should have displacement")
	assert_almost_eq(restored.displacement.get_distance(1, 1), 3.0, 0.001)


func test_face_null_displacement_serialization():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(16, 0, 0),
		Vector3(16, 0, 16), Vector3(0, 0, 16)
	])
	face.normal = Vector3.UP
	face.ensure_geometry()
	var data: Dictionary = face.to_dict()
	assert_null(data["displacement"])
	var restored: FaceData = FaceData.from_dict(data)
	assert_null(restored.displacement)


# ---------------------------------------------------------------------------
# HFDisplacementSystem tests
# ---------------------------------------------------------------------------


func test_create_displacement_on_quad():
	var brush = _make_quad_brush()
	var ok: bool = sys.create_displacement("test_brush", 0, 3)
	assert_true(ok)
	assert_not_null(brush.faces[0].displacement)
	assert_eq(brush.faces[0].displacement.power, 3)


func test_create_displacement_fails_on_triangle():
	_make_tri_brush()
	var ok: bool = sys.create_displacement("tri_brush", 0, 3)
	assert_false(ok, "Should fail on non-quad face")


func test_create_displacement_fails_on_bad_brush():
	var ok: bool = sys.create_displacement("nonexistent", 0, 3)
	assert_false(ok)


func test_create_displacement_fails_on_bad_face_index():
	_make_quad_brush()
	var ok: bool = sys.create_displacement("test_brush", 5, 3)
	assert_false(ok)


func test_destroy_displacement():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0)
	assert_not_null(brush.faces[0].displacement)
	var ok: bool = sys.destroy_displacement("test_brush", 0)
	assert_true(ok)
	assert_null(brush.faces[0].displacement)


func test_destroy_displacement_when_none():
	_make_quad_brush()
	var ok: bool = sys.destroy_displacement("test_brush", 0)
	assert_false(ok)


func test_has_displacement():
	_make_quad_brush()
	assert_false(sys.has_displacement("test_brush", 0))
	sys.create_displacement("test_brush", 0)
	assert_true(sys.has_displacement("test_brush", 0))


func test_set_power_resamples():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	brush.faces[0].displacement.set_distance(2, 2, 10.0)
	var ok: bool = sys.set_power("test_brush", 0, 3)
	assert_true(ok)
	assert_eq(brush.faces[0].displacement.power, 3)
	# Center of new grid should have interpolated value near 10
	var center_val: float = brush.faces[0].displacement.get_distance(4, 4)
	assert_true(center_val > 5.0, "Center should preserve approximate value after resample")


func test_set_elevation():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0)
	sys.set_elevation("test_brush", 0, 3.5)
	assert_almost_eq(brush.faces[0].displacement.elevation, 3.5, 0.001)


func test_smooth_all():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	brush.faces[0].displacement.set_distance(2, 2, 10.0)
	var ok: bool = sys.smooth_all("test_brush", 0, 0.5)
	assert_true(ok)
	var val: float = brush.faces[0].displacement.get_distance(2, 2)
	assert_true(val < 10.0, "Smoothing should reduce spike")


func test_paint_raise():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	# Paint at the center of the face (world pos = face center since brush at origin)
	var ok: bool = sys.paint(
		"test_brush", 0,
		Vector3(8, 0, 8), 10.0, 1.0,
		HFDisplacementSystem.PaintMode.RAISE
	)
	assert_true(ok)
	# Center vertex should be raised
	var val: float = brush.faces[0].displacement.get_distance(2, 2)
	assert_true(val > 0.0, "Center should be raised")


func test_paint_lower():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	brush.faces[0].displacement.set_distance(2, 2, 5.0)
	sys.paint(
		"test_brush", 0,
		Vector3(8, 0, 8), 10.0, 1.0,
		HFDisplacementSystem.PaintMode.LOWER
	)
	var val: float = brush.faces[0].displacement.get_distance(2, 2)
	assert_true(val < 5.0, "Center should be lowered")


func test_paint_outside_radius():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	# Paint far away from the face
	var ok: bool = sys.paint(
		"test_brush", 0,
		Vector3(1000, 0, 1000), 1.0, 1.0,
		HFDisplacementSystem.PaintMode.RAISE
	)
	assert_false(ok, "Paint outside radius should not modify anything")


func test_apply_noise_via_system():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var ok: bool = sys.apply_noise("test_brush", 0, noise, 2.0)
	assert_true(ok)


func test_sew_all_no_crash():
	_make_quad_brush()
	sys.create_displacement("test_brush", 0)
	# No sew groups set, should return 0
	var count: int = sys.sew_all()
	assert_eq(count, 0)
