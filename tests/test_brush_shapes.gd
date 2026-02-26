extends GutTest

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

var brush: DraftBrush


func before_each():
	brush = DraftBrush.new()
	# Don't add to tree — _build_box_faces doesn't need it


func after_each():
	if brush and is_instance_valid(brush):
		if brush.is_inside_tree():
			brush.queue_free()
		else:
			brush.free()
	brush = null


# ===========================================================================
# Box faces: count and structure
# ===========================================================================


func test_box_faces_count():
	brush.size = Vector3(32, 32, 32)
	var box_faces = brush._build_box_faces()
	assert_eq(box_faces.size(), 6, "Box should have exactly 6 faces")


func test_box_faces_all_quads():
	brush.size = Vector3(16, 24, 32)
	var box_faces = brush._build_box_faces()
	for i in range(box_faces.size()):
		var face: FaceData = box_faces[i]
		assert_eq(face.local_verts.size(), 4, "Face %d should be a quad (4 verts)" % i)


func test_box_faces_have_geometry():
	brush.size = Vector3(32, 32, 32)
	var box_faces = brush._build_box_faces()
	for i in range(box_faces.size()):
		var face: FaceData = box_faces[i]
		assert_true(face.normal.length() > 0.5, "Face %d should have a computed normal" % i)


# ===========================================================================
# Box faces: normals cover all 6 directions
# ===========================================================================


func test_box_faces_normals_all_axes():
	brush.size = Vector3(32, 32, 32)
	var box_faces = brush._build_box_faces()
	var has_pos_x := false
	var has_neg_x := false
	var has_pos_y := false
	var has_neg_y := false
	var has_pos_z := false
	var has_neg_z := false
	for face in box_faces:
		var n: Vector3 = face.normal
		if n.x > 0.5:
			has_pos_x = true
		if n.x < -0.5:
			has_neg_x = true
		if n.y > 0.5:
			has_pos_y = true
		if n.y < -0.5:
			has_neg_y = true
		if n.z > 0.5:
			has_pos_z = true
		if n.z < -0.5:
			has_neg_z = true
	assert_true(has_pos_x, "Should have +X face")
	assert_true(has_neg_x, "Should have -X face")
	assert_true(has_pos_y, "Should have +Y face")
	assert_true(has_neg_y, "Should have -Y face")
	assert_true(has_pos_z, "Should have +Z face")
	assert_true(has_neg_z, "Should have -Z face")


# ===========================================================================
# Box faces: vertex positions match half-size
# ===========================================================================


func test_box_faces_vertex_bounds():
	brush.size = Vector3(10, 20, 30)
	var box_faces = brush._build_box_faces()
	var min_v = Vector3(INF, INF, INF)
	var max_v = Vector3(-INF, -INF, -INF)
	for face in box_faces:
		for vert in face.local_verts:
			min_v.x = min(min_v.x, vert.x)
			min_v.y = min(min_v.y, vert.y)
			min_v.z = min(min_v.z, vert.z)
			max_v.x = max(max_v.x, vert.x)
			max_v.y = max(max_v.y, vert.y)
			max_v.z = max(max_v.z, vert.z)
	assert_almost_eq(max_v.x - min_v.x, 10.0, 0.01, "Vertex span X = size.x")
	assert_almost_eq(max_v.y - min_v.y, 20.0, 0.01, "Vertex span Y = size.y")
	assert_almost_eq(max_v.z - min_v.z, 30.0, 0.01, "Vertex span Z = size.z")


func test_box_faces_centered_at_origin():
	brush.size = Vector3(16, 16, 16)
	var box_faces = brush._build_box_faces()
	var center = Vector3.ZERO
	var count := 0
	for face in box_faces:
		for vert in face.local_verts:
			center += vert
			count += 1
	center /= float(count)
	assert_almost_eq(center.x, 0.0, 0.01, "Verts centered at X=0")
	assert_almost_eq(center.y, 0.0, 0.01, "Verts centered at Y=0")
	assert_almost_eq(center.z, 0.0, 0.01, "Verts centered at Z=0")


# ===========================================================================
# Box faces: different sizes
# ===========================================================================


func test_box_faces_non_uniform_size():
	brush.size = Vector3(8, 64, 4)
	var box_faces = brush._build_box_faces()
	assert_eq(box_faces.size(), 6, "Non-uniform box still has 6 faces")
	# Check that largest face spans 64 in Y
	var max_y_span := 0.0
	for face in box_faces:
		var min_y := INF
		var max_y := -INF
		for vert in face.local_verts:
			min_y = min(min_y, vert.y)
			max_y = max(max_y, vert.y)
		max_y_span = max(max_y_span, max_y - min_y)
	assert_almost_eq(max_y_span, 64.0, 0.01, "Largest Y span = 64")


func test_box_faces_small_size():
	brush.size = Vector3(1, 1, 1)
	var box_faces = brush._build_box_faces()
	assert_eq(box_faces.size(), 6, "Unit box has 6 faces")
	# Half-size = 0.5
	for face in box_faces:
		for vert in face.local_verts:
			assert_true(
				abs(vert.x) <= 0.51 and abs(vert.y) <= 0.51 and abs(vert.z) <= 0.51,
				"Unit box verts within half-size"
			)


# ===========================================================================
# Box faces: triangulation
# ===========================================================================


func test_box_face_triangulates_to_six_verts():
	brush.size = Vector3(32, 32, 32)
	var box_faces = brush._build_box_faces()
	for i in range(box_faces.size()):
		var tri = box_faces[i].triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		assert_eq(verts.size(), 6, "Quad face %d should triangulate to 6 verts" % i)


func test_box_total_triangle_count():
	brush.size = Vector3(32, 32, 32)
	var box_faces = brush._build_box_faces()
	var total_verts := 0
	for face in box_faces:
		var tri = face.triangulate()
		total_verts += tri.get("verts", PackedVector3Array()).size()
	# 6 faces * 2 triangles * 3 verts = 36
	assert_eq(total_verts, 36, "Box should produce 36 triangle verts total")


# ===========================================================================
# Face serialization round-trip via DraftBrush
# ===========================================================================


func test_serialize_faces_round_trip():
	brush.size = Vector3(32, 32, 32)
	var box_faces = brush._build_box_faces()
	brush.faces = box_faces
	# Set a material on face 0
	brush.faces[0].material_idx = 3
	brush.faces[0].uv_scale = Vector2(2.0, 0.5)
	var serialized = brush.serialize_faces()
	assert_eq(serialized.size(), 6, "Serialized should have 6 entries")
	# Clear and restore
	brush.faces.clear()
	brush.apply_serialized_faces(serialized)
	assert_eq(brush.faces.size(), 6, "Restored should have 6 faces")
	assert_eq(brush.faces[0].material_idx, 3, "Material idx preserved")
	assert_almost_eq(brush.faces[0].uv_scale.x, 2.0, 0.001, "UV scale.x preserved")


func test_serialize_empty_faces():
	brush.faces.clear()
	var serialized = brush.serialize_faces()
	assert_eq(serialized.size(), 0, "Empty faces serialize to empty array")


# ===========================================================================
# Prism mesh generation (needs tree for full test, but we can test output)
# ===========================================================================


func test_build_prism_mesh_triangle():
	add_child(brush)
	brush.size = Vector3(16, 16, 16)
	var mesh = brush._build_prism_mesh(3)
	assert_not_null(mesh, "Triangle prism mesh should not be null")
	assert_true(mesh.get_surface_count() > 0, "Prism mesh should have surfaces")


func test_build_prism_mesh_pentagon():
	add_child(brush)
	brush.size = Vector3(16, 16, 16)
	var mesh = brush._build_prism_mesh(5)
	assert_not_null(mesh, "Pentagon prism mesh should not be null")
	assert_true(mesh.get_surface_count() > 0, "Pentagon mesh should have surfaces")


func test_build_prism_mesh_clamps_sides():
	add_child(brush)
	brush.size = Vector3(16, 16, 16)
	# Even with 1 side requested, should clamp to 3
	var mesh = brush._build_prism_mesh(1)
	assert_not_null(mesh, "Clamped prism mesh should not be null")
