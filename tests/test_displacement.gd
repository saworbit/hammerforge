extends GutTest

const HFDisplacementData = preload("res://addons/hammerforge/displacement_data.gd")
const HFDisplacementSystem = preload("res://addons/hammerforge/systems/hf_displacement_system.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFDisplacementSystem


func before_each():
	HFLog.end_test_capture()
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	sys = HFDisplacementSystem.new(root)


func after_each():
	HFLog.end_test_capture()
	root = null
	sys = null


func _capture_warning(pattern: String) -> void:
	HFLog.begin_test_capture([pattern])


func _assert_captured_warning(pattern: String) -> void:
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1, "Should capture exactly one warning")
	if warnings.size() > 0:
		assert_string_contains(warnings[0], pattern, "Should capture expected warning text")


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
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 16), Vector3(0, 0, 16)]
	)
	face.normal = Vector3.UP
	face.ensure_geometry()
	var face_arr: Array[FaceData] = [face]
	brush.faces = face_arr
	brush.geometry_dirty = false
	root.draft_brushes_node.add_child(brush)
	return brush


## A real six-face box, built by DraftBrush itself, so a later set_size() takes
## the production _rebuild_faces() path with matching old and new face counts.
func _make_solid_box_brush(brush_id: String = "box_brush") -> DraftBrush:
	var brush = DraftBrush.new()
	brush.brush_id = brush_id
	root.draft_brushes_node.add_child(brush)
	brush.size = Vector3(32, 32, 32)
	return brush


func _make_tri_brush(brush_id: String = "tri_brush") -> Node3D:
	var brush = DraftBrush.new()
	brush.brush_id = brush_id
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(8, 0, 16)])
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
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
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
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
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
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var pos: Vector3 = disp.get_displaced_position(0, 0, corners, Vector3.UP)
	assert_almost_eq(pos.y, 5.0, 0.01)


func test_triangulate_displaced_flat():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var uv_corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
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
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var uv_corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var result: Dictionary = disp.triangulate_displaced(corners, Vector3.UP, uv_corners)
	# 8x8 grid → 64 cells → 128 triangles → 384 vertices
	assert_eq(result["verts"].size(), 384)


func test_triangulate_displaced_smooths_shared_vertex_normals():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_distance(2, 2, 8.0)
	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var uv_corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var result: Dictionary = disp.triangulate_displaced(corners, Vector3.UP, uv_corners)
	var verts: PackedVector3Array = result["verts"]
	var normals: PackedVector3Array = result["normals"]
	var peak: Vector3 = disp.get_displaced_position(2, 2, corners, Vector3.UP)
	var peak_normals: Array[Vector3] = []
	for i in range(verts.size()):
		if verts[i].distance_to(peak) < 0.001:
			peak_normals.append(normals[i])
	assert_gt(peak_normals.size(), 1, "Center vertex is shared by multiple triangles")
	var first: Vector3 = peak_normals[0]
	for n in peak_normals:
		assert_true(first.dot(n) > 0.99, "Shared vertex should reuse one averaged normal")


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
		Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, 16), Vector3(16, 0, 16)
	]
	var pos: Vector3 = disp.get_displaced_position(0, 0, corners, Vector3.UP)
	assert_almost_eq(pos.x, 5.0, 0.01)  # Displaced along X
	assert_almost_eq(pos.y, 0.0, 0.01)  # Not along Y (normal)


# ---------------------------------------------------------------------------
# FaceData displacement integration tests
# ---------------------------------------------------------------------------


func test_face_triangulate_with_displacement():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 16), Vector3(0, 0, 16)]
	)
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
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 16), Vector3(0, 0, 16)]
	)
	face.normal = Vector3.UP
	face.ensure_geometry()
	var tri: Dictionary = face.triangulate()
	# Standard fan: 2 triangles = 6 verts
	assert_eq(tri["verts"].size(), 6)


func test_face_displacement_only_on_quads():
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(8, 0, 16)])
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
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 16), Vector3(0, 0, 16)]
	)
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
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 16), Vector3(0, 0, 16)]
	)
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
	_capture_warning("HFDisplacementSystem: displacement requires a quad face")
	var ok: bool = sys.create_displacement("tri_brush", 0, 3)
	assert_false(ok, "Should fail on non-quad face")
	_assert_captured_warning("HFDisplacementSystem: displacement requires a quad face")


func test_create_displacement_fails_on_bad_brush():
	_capture_warning("HFDisplacementSystem: brush not found")
	var ok: bool = sys.create_displacement("nonexistent", 0, 3)
	assert_false(ok)
	_assert_captured_warning("HFDisplacementSystem: brush not found")


func test_create_displacement_fails_on_bad_face_index():
	_make_quad_brush()
	_capture_warning("HFDisplacementSystem: face index out of range")
	var ok: bool = sys.create_displacement("test_brush", 5, 3)
	assert_false(ok)
	_assert_captured_warning("HFDisplacementSystem: face index out of range")


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
		"test_brush", 0, Vector3(8, 0, 8), 10.0, 1.0, HFDisplacementSystem.PaintMode.RAISE
	)
	assert_true(ok)
	# Center vertex should be raised
	var val: float = brush.faces[0].displacement.get_distance(2, 2)
	assert_true(val > 0.0, "Center should be raised")


func test_paint_lower():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	brush.faces[0].displacement.set_distance(2, 2, 5.0)
	sys.paint("test_brush", 0, Vector3(8, 0, 8), 10.0, 1.0, HFDisplacementSystem.PaintMode.LOWER)
	var val: float = brush.faces[0].displacement.get_distance(2, 2)
	assert_true(val < 5.0, "Center should be lowered")


func test_paint_outside_radius():
	var brush = _make_quad_brush()
	sys.create_displacement("test_brush", 0, 2)
	# Paint far away from the face
	var ok: bool = sys.paint(
		"test_brush", 0, Vector3(1000, 0, 1000), 1.0, 1.0, HFDisplacementSystem.PaintMode.RAISE
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
	var first := _make_quad_brush()
	sys.create_displacement("test_brush", 0)
	# No sew groups set, should return 0.
	var count: int = sys.sew_all()
	assert_eq(count, 0)
	var second := _make_quad_brush("test_brush_b")
	sys.create_displacement("test_brush_b", 0)
	first.faces[0].displacement.sew_group = 4
	second.faces[0].displacement.sew_group = 4
	assert_gt(sys.sew_all(), 0, "Sew All must collect both editable brushes")
	var level_root_source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")
	assert_true(
		level_root_source.contains("func get_all_draft_brushes() -> Array:"),
		"Production LevelRoot must expose the same editable brush collection",
	)


# ---------------------------------------------------------------------------
# Displacement survives a face rebuild
# ---------------------------------------------------------------------------


func test_displacement_survives_brush_resize():
	var brush := _make_solid_box_brush()
	assert_eq(brush.faces.size(), 6, "The fixture must be a real six-face box")
	assert_true(sys.create_displacement("box_brush", 0, 3), "Displacement should be created")
	var disp = brush.faces[0].displacement
	assert_not_null(disp)
	disp.set_distance(1, 1, 12.0)

	brush.set_size(Vector3(64, 64, 64))

	assert_eq(brush.faces.size(), 6, "Resize still rebuilds a box")
	assert_not_null(
		brush.faces[0].displacement, "Resize must not drop the displacement on a rebuilt face"
	)
	assert_eq(
		brush.faces[0].displacement.get_distance(1, 1),
		12.0,
		"The sculpted elevation must come across with the resource"
	)


func test_displacement_is_not_smeared_onto_other_faces_by_resize():
	var brush := _make_solid_box_brush()
	assert_true(sys.create_displacement("box_brush", 0, 3))

	brush.set_size(Vector3(64, 64, 64))

	var carrying := 0
	for face in brush.faces:
		if face.displacement != null:
			carrying += 1
	assert_eq(carrying, 1, "Only the displaced face should carry displacement after a rebuild")


# ---------------------------------------------------------------------------
# Create refuses to overwrite a sculpt (#319)
# ---------------------------------------------------------------------------


func test_create_refuses_a_face_that_already_has_a_displacement():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3), "First create should succeed")
	assert_true(sys.set_elevation("test_brush", 0, 5.0), "Elevation should be settable")
	sys.paint("test_brush", 0, Vector3(8, 0, 8), 20.0, 3.0)
	var before: PackedFloat32Array = brush.faces[0].displacement.distances.duplicate()
	_capture_warning("already has a displacement")
	assert_false(sys.create_displacement("test_brush", 0, 3), "Second create should be refused")
	_assert_captured_warning("already has a displacement")
	assert_eq(brush.faces[0].displacement.elevation, 5.0, "Elevation should survive")
	assert_eq(brush.faces[0].displacement.distances, before, "The sculpt should survive")


func test_destroy_then_create_still_starts_over():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3))
	assert_true(sys.set_elevation("test_brush", 0, 5.0))
	assert_true(sys.destroy_displacement("test_brush", 0), "Destroy should succeed")
	assert_true(sys.create_displacement("test_brush", 0, 3), "Create should work after a destroy")
	assert_eq(brush.faces[0].displacement.elevation, 1.0, "A fresh displacement is flat")


# ---------------------------------------------------------------------------
# Paint and elevation reject what they cannot use (#320)
# ---------------------------------------------------------------------------


func test_paint_refuses_a_non_finite_centre_and_leaves_the_grid_alone():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 4))
	var before: PackedFloat32Array = brush.faces[0].displacement.distances.duplicate()
	_capture_warning("finite")
	assert_false(sys.paint("test_brush", 0, Vector3(NAN, NAN, NAN), 10.0, 1.0))
	_assert_captured_warning("finite")
	assert_eq(brush.faces[0].displacement.distances, before, "The grid should be untouched")


func test_paint_refuses_a_non_finite_radius_or_strength():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3))
	var before: PackedFloat32Array = brush.faces[0].displacement.distances.duplicate()
	assert_false(sys.paint("test_brush", 0, Vector3(8, 0, 8), NAN, 1.0), "NaN radius")
	assert_false(sys.paint("test_brush", 0, Vector3(8, 0, 8), 10.0, INF), "Infinite strength")
	assert_eq(brush.faces[0].displacement.distances, before, "The grid should be untouched")


func test_paint_still_works_on_finite_input():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3))
	assert_true(sys.paint("test_brush", 0, Vector3(8, 0, 8), 20.0, 4.0), "A normal stroke")
	var raised := 0
	for distance in brush.faces[0].displacement.distances:
		if distance > 0.0:
			raised += 1
	assert_gt(raised, 0, "A normal stroke should raise something")


func test_set_elevation_refuses_a_non_finite_value():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3))
	assert_true(sys.set_elevation("test_brush", 0, 3.0))
	_capture_warning("finite")
	assert_false(sys.set_elevation("test_brush", 0, NAN))
	_assert_captured_warning("finite")
	assert_eq(brush.faces[0].displacement.elevation, 3.0, "The old elevation should stand")


func test_set_elevation_is_bounded_by_the_face_it_sits_on():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3))
	# The quad is 16 x 16, so its longest diagonal is a little over 22.
	_capture_warning("beyond the face")
	assert_true(sys.set_elevation("test_brush", 0, 1e9), "An over-large value is clamped, not lost")
	_assert_captured_warning("beyond the face")
	var elevation: float = brush.faces[0].displacement.elevation
	assert_lt(elevation, 23.0, "Elevation should be capped near the face diagonal")
	assert_gt(elevation, 22.0, "The cap should be the face diagonal, not an arbitrary number")


func test_an_ordinary_elevation_is_left_alone():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 3))
	assert_true(sys.set_elevation("test_brush", 0, 8.0))
	assert_eq(brush.faces[0].displacement.elevation, 8.0, "8 fits inside a 16 unit face")
	assert_true(sys.set_elevation("test_brush", 0, -8.0), "A negative elevation is a valid dip")
	assert_eq(brush.faces[0].displacement.elevation, -8.0)


# ---------------------------------------------------------------------------
# Winding: a displaced face faces the way its face does
# ---------------------------------------------------------------------------


func test_a_displaced_face_is_wound_the_way_its_face_is():
	# Clockwise from outside, measured the way FaceData measures its own normal.
	# Every displaced triangle was once wound the other way, so a sculpt faced
	# into its brush and was culled from outside in the viewport and the bake.
	var brush := _make_solid_box_brush()
	for fi in brush.faces.size():
		var face: FaceData = brush.faces[fi]
		assert_true(sys.create_displacement("box_brush", fi, 2))
		var verts: PackedVector3Array = face.triangulate()["verts"]
		assert_eq(verts.size(), 96, "face %d: sixteen cells, two triangles each" % fi)
		var outward := 0
		for t in range(0, verts.size(), 3):
			var n: Vector3 = (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
			if n.dot(face.normal) > 0.0:
				outward += 1
		assert_eq(outward, 32, "face %d: every triangle faces out" % fi)


func test_cells_split_along_the_old_diagonal_unless_flipped():
	# Off, a cell is split from (row, col + 1) to (row + 1, col), the split every
	# saved sculpt was drawn with. On, from (row, col) to (row + 1, col + 1).
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	var d: int = disp.get_dim()
	var off: PackedInt32Array = disp.cell_triangles()
	assert_eq(Array(off.slice(0, 6)), [0, 1, d, 1, d + 1, d])
	disp.flip_diagonals = true
	var on: PackedInt32Array = disp.cell_triangles()
	assert_eq(Array(on.slice(0, 6)), [0, 1, d + 1, 0, d + 1, d])


# ---------------------------------------------------------------------------
# Relabelling a grid against new corners (used by flip)
# ---------------------------------------------------------------------------

## The eight ways to relabel a square's corners without tearing it: four turns,
## then the four mirrors.
const SQUARE_SYMMETRIES := [
	[0, 1, 2, 3],
	[1, 2, 3, 0],
	[2, 3, 0, 1],
	[3, 0, 1, 2],
	[3, 2, 1, 0],
	[0, 3, 2, 1],
	[1, 0, 3, 2],
	[2, 1, 0, 3],
]


## A sculpt that no symmetry of the grid maps onto itself, with cells that are
## not flat, so a wrong relabelling or a wrong diagonal cannot pass by luck.
func _lopsided_sculpt(with_offsets: bool = false) -> HFDisplacementData:
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	var d: int = disp.get_dim()
	for row in d:
		for col in d:
			disp.set_distance(row, col, row * 1.0 + col * 0.25 + 0.5 * ((row * col) % 3))
			disp.set_alpha(row, col, fposmod(row * 0.13 + col * 0.29, 1.0))
			if with_offsets and (row + col) % 4 == 1:
				disp.set_offset(row, col, Vector3(0.3 * col, 1.0, -0.2 * row))
	return disp


## A displaced surface as a set of triangles. With `oriented` each triangle keeps
## its winding, starting from its smallest corner. Without, its corners are
## sorted, so a triangle and its reverse compare equal.
func _surface(
	disp: HFDisplacementData, corners_in_face_order: Array, oriented: bool = true
) -> Array:
	var c: Array = corners_in_face_order
	var corners: Array[Vector3] = [c[0], c[1], c[3], c[2]]
	var uv_corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var result: Dictionary = disp.triangulate_displaced(corners, Vector3.UP, uv_corners)
	var verts: PackedVector3Array = result["verts"]
	var out: Array = []
	for t in range(0, verts.size(), 3):
		var keys: Array = []
		for k in 3:
			var p: Vector3 = verts[t + k]
			keys.append("%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)])
		if oriented:
			var first := 0
			for k in 3:
				if keys[k] < keys[first]:
					first = k
			keys = [keys[first], keys[(first + 1) % 3], keys[(first + 2) % 3]]
		else:
			keys.sort()
		out.append("|".join(keys))
	out.sort()
	return out


func test_a_relabelled_grid_describes_the_same_surface_for_every_symmetry():
	var disp := _lopsided_sculpt(true)
	# A rectangle, so a relabelling that confused rows with columns stretches it.
	var corners := [Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 24), Vector3(0, 0, 24)]
	var expected := _surface(disp, corners, false)
	for symmetry in SQUARE_SYMMETRIES:
		var corner_from := PackedInt32Array(symmetry)
		var moved: Array = []
		for k in 4:
			moved.append(corners[corner_from[k]])
		var relabelled = disp.remapped(corner_from)
		assert_not_null(relabelled, "%s is a symmetry" % str(symmetry))
		if relabelled == null:
			continue
		assert_eq(
			_surface(relabelled, moved, false),
			expected,
			"%s: the same triangles over the same points" % str(symmetry)
		)


func test_a_turned_grid_keeps_every_triangle_wound_the_same_way():
	# A turn of the corners keeps the face's winding, so the triangles have to
	# come out the same way round, not merely over the same points.
	var disp := _lopsided_sculpt()
	var corners := [Vector3(0, 0, 0), Vector3(16, 0, 0), Vector3(16, 0, 24), Vector3(0, 0, 24)]
	var expected := _surface(disp, corners)
	for i in 4:
		var corner_from := PackedInt32Array(SQUARE_SYMMETRIES[i])
		var moved: Array = []
		for k in 4:
			moved.append(corners[corner_from[k]])
		assert_eq(_surface(disp.remapped(corner_from), moved), expected, "turn %d" % i)


func test_a_relabelling_that_tears_the_grid_is_refused():
	var disp := _lopsided_sculpt()
	for corner_from in [[0, 2, 1, 3], [0, 1, 2], [0, 0, 1, 2], [0, 1, 2, 4], [1, 3, 2, 0]]:
		assert_null(disp.remapped(PackedInt32Array(corner_from)), "%s" % str(corner_from))


func test_relabelling_leaves_the_original_alone():
	# A duplicate can share the resource with another face, and an undo snapshot
	# can hold it, so the relabelled grid has to be a new one.
	var disp := _lopsided_sculpt(true)
	var distances := disp.distances.duplicate()
	var alphas := disp.alphas.duplicate()
	var offsets := disp.offsets.duplicate()
	var relabelled = disp.remapped(PackedInt32Array([3, 2, 1, 0]), 0)
	assert_false(relabelled == disp, "a new resource")
	assert_eq(disp.distances, distances)
	assert_eq(disp.alphas, alphas)
	assert_eq(disp.offsets, offsets)
	assert_false(disp.flip_diagonals)


func test_relabelling_carries_power_elevation_and_sew_group():
	var disp := _lopsided_sculpt()
	disp.elevation = 2.5
	disp.sew_group = 7
	var relabelled = disp.remapped(PackedInt32Array([1, 2, 3, 0]))
	assert_eq(relabelled.power, 2)
	assert_eq(relabelled.elevation, 2.5)
	assert_eq(relabelled.sew_group, 7)


func test_a_reflection_turns_the_custom_offsets_with_it():
	var disp = HFDisplacementData.new()
	disp.init_flat(2)
	disp.set_offset(0, 0, Vector3(1, 2, 3))
	var relabelled = disp.remapped(PackedInt32Array([0, 1, 2, 3]), 0)
	assert_eq(relabelled.offsets[0], Vector3(-1, 2, 3))
	relabelled = disp.remapped(PackedInt32Array([0, 1, 2, 3]), 2)
	assert_eq(relabelled.offsets[0], Vector3(1, 2, -3))


func test_mirroring_a_grid_twice_gives_it_back_exactly():
	var disp := _lopsided_sculpt(true)
	var once = disp.remapped(PackedInt32Array([3, 2, 1, 0]), 1)
	assert_true(once.flip_diagonals, "a single mirror of the grid swaps the diagonals")
	var twice = once.remapped(PackedInt32Array([3, 2, 1, 0]), 1)
	assert_eq(twice.distances, disp.distances)
	assert_eq(twice.alphas, disp.alphas)
	assert_eq(twice.offsets, disp.offsets)
	assert_false(twice.flip_diagonals)


func test_flipped_diagonals_survive_a_save():
	var disp := _lopsided_sculpt()
	disp.flip_diagonals = true
	var restored = HFDisplacementData.from_dict(disp.to_dict())
	assert_true(restored.flip_diagonals)


func test_an_unmirrored_sculpt_saves_exactly_as_it_did():
	# Written only when on, so no level that never mirrored a sculpt changes on
	# disk, and a build from before the flag reads every file it wrote.
	var data: Dictionary = _lopsided_sculpt().to_dict()
	assert_false(data.has("flip_diagonals"))
	assert_false(HFDisplacementData.from_dict(data).flip_diagonals)


func test_changing_power_keeps_the_diagonals_a_mirror_chose():
	var brush = _make_quad_brush()
	assert_true(sys.create_displacement("test_brush", 0, 2))
	brush.faces[0].displacement.flip_diagonals = true
	assert_true(sys.set_power("test_brush", 0, 3))
	assert_true(brush.faces[0].displacement.flip_diagonals)
