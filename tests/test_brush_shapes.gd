extends GutTest

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const PrefabFactory = preload("res://addons/hammerforge/prefab_factory.gd")

var brush: DraftBrush


func before_each():
	brush = autoqfree(DraftBrush.new())
	# Don't add to tree — _build_box_faces doesn't need it


func after_each():
	brush = null


func _overlay_count(kind: StringName = &"") -> int:
	var count := 0
	for child in brush.get_children(true):
		var child_kind: StringName = brush._visual_overlay_kind(child)
		if child_kind != &"" and (kind == &"" or child_kind == kind):
			count += 1
	return count


func _make_legacy_additive_overlay() -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	overlay.name = "_AdditiveWireOverlay"
	overlay.mesh = brush.mesh_instance.mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = (
		"shader_type spatial;\n"
		+ "render_mode unshaded, cull_disabled, wireframe, depth_draw_never;\n"
		+ "uniform vec4 color : source_color = vec4(0.2, 0.8, 0.2, 0.5);\n"
		+ "void fragment() { ALBEDO = color.rgb; ALPHA = color.a; }\n"
	)
	var material := ShaderMaterial.new()
	material.shader = shader
	overlay.material_override = material
	return overlay


func _assert_base_mesh_matches_size(shape: int, requested_size: Vector3, tolerance := 0.05) -> void:
	brush.shape = shape
	brush.size = requested_size
	var build: Dictionary = brush._build_base_mesh()
	var mesh := build.get("mesh", null) as Mesh
	assert_not_null(mesh, "Shape %d should build a non-null mesh" % shape)
	if mesh == null:
		return

	var mesh_scale: Vector3 = build.get("scale", Vector3.ONE)
	var actual_size := mesh.get_aabb().size * mesh_scale.abs()
	assert_almost_eq(actual_size.x, requested_size.x, tolerance, "Mesh bounds should match size.x")
	assert_almost_eq(actual_size.y, requested_size.y, tolerance, "Mesh bounds should match size.y")
	assert_almost_eq(actual_size.z, requested_size.z, tolerance, "Mesh bounds should match size.z")


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
# Preview overlay lifecycle
# ===========================================================================


func test_additive_brush_has_no_topology_overlay_during_rapid_rebuilds():
	add_child(brush)
	assert_not_null(brush.mesh_instance.mesh)
	assert_eq(_overlay_count(), 0, "A normal additive brush should start without an overlay")

	for index in range(40):
		brush.size = Vector3(8.0 + index, 16.0 + index, 24.0 + index)
		assert_eq(
			_overlay_count(),
			0,
			"Additive rebuild %d should not create a triangle wireframe" % index
		)


func test_subtract_overlay_is_reused_and_removed_immediately_when_no_longer_needed():
	add_child(brush)
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var overlay := brush.get_node_or_null("_SubtractWireOverlay") as MeshInstance3D
	assert_not_null(overlay, "A subtract brush should retain a clear red wireframe")
	if overlay == null:
		return
	assert_false(
		brush.get_children().has(overlay),
		"Private semantic overlays should stay out of the user's scene tree",
	)
	assert_true(brush.get_children(true).has(overlay))
	assert_ne(
		overlay.mesh, brush.mesh_instance.mesh, "Subtract state should not expose render triangles"
	)
	assert_eq(overlay.transform, Transform3D.IDENTITY)
	assert_eq(overlay.mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINES)
	var initial_vertices: PackedVector3Array = overlay.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(initial_vertices, brush.get_editor_outline_lines())
	assert_eq(initial_vertices.size(), 24, "A subtract box should show only its twelve edges")
	var subtract_material := overlay.material_override as StandardMaterial3D
	assert_not_null(subtract_material)
	if subtract_material:
		assert_false(subtract_material.no_depth_test, "Subtract lines should remain depth-aware")
		assert_eq(subtract_material.albedo_color, Color(1.0, 0.25, 0.2, 0.7))
	var overlay_id := overlay.get_instance_id()

	for index in range(40):
		brush.size = Vector3(16.0 + index, 24.0, 32.0)
		var current := brush.get_node_or_null("_SubtractWireOverlay") as MeshInstance3D
		assert_not_null(current, "Subtract overlay should survive rebuild %d" % index)
		assert_eq(_overlay_count(brush.OVERLAY_KIND_SUBTRACT), 1)
		if current:
			assert_eq(current.get_instance_id(), overlay_id, "The overlay node should be reused")
			assert_ne(current.mesh, brush.mesh_instance.mesh)
			assert_eq(current.mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINES)
			var vertices: PackedVector3Array = current.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			assert_eq(vertices, brush.get_editor_outline_lines())
			assert_eq(vertices.size(), 24)

	brush.operation = CSGShape3D.OPERATION_UNION
	assert_null(brush.get_node_or_null("_SubtractWireOverlay"))
	assert_eq(_overlay_count(), 0, "Obsolete subtract overlays should detach synchronously")


func test_curved_subtract_overlays_are_sparse_semantic_lines_with_exact_bounds():
	add_child(brush)
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var requested_size := Vector3(12, 20, 28)
	for shape in [brush.BrushShape.ELLIPSOID, brush.BrushShape.TORUS]:
		brush.shape = shape
		brush.size = requested_size
		var overlay := brush.get_node_or_null("_SubtractWireOverlay") as MeshInstance3D
		assert_not_null(overlay)
		if overlay == null:
			continue
		assert_eq(overlay.transform, Transform3D.IDENTITY, "Semantic lines are already brush-local")
		assert_eq(overlay.mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINES)
		var vertices: PackedVector3Array = overlay.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_eq(vertices, brush.get_editor_outline_lines())
		assert_lt(
			vertices.size(),
			brush.mesh_instance.mesh.generate_triangle_mesh().get_faces().size(),
			"A curved semantic outline should be much quieter than its render cage",
		)
		var bounds := overlay.mesh.get_aabb()
		assert_almost_eq(bounds.size.x, requested_size.x, 0.01)
		assert_almost_eq(bounds.size.y, requested_size.y, 0.01)
		assert_almost_eq(bounds.size.z, requested_size.z, 0.01)


func test_brush_entity_and_subtract_semantics_each_keep_one_stable_overlay():
	brush.set_brush_entity_class("trigger_once")
	add_child(brush)
	var entity_overlay := brush.get_node_or_null("_BrushEntityOverlay") as MeshInstance3D
	assert_not_null(entity_overlay, "Brush entities should retain their blue semantic tint")
	if entity_overlay == null:
		return
	var entity_id := entity_overlay.get_instance_id()

	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var subtract_overlay := brush.get_node_or_null("_SubtractWireOverlay") as MeshInstance3D
	assert_not_null(subtract_overlay, "A subtract entity should also show subtraction semantics")
	assert_eq(_overlay_count(brush.OVERLAY_KIND_ENTITY), 1)
	assert_eq(_overlay_count(brush.OVERLAY_KIND_SUBTRACT), 1)

	for index in range(20):
		brush.size = Vector3(20.0 + index, 20.0, 20.0)
	assert_eq(
		(brush.get_node("_BrushEntityOverlay") as MeshInstance3D).get_instance_id(),
		entity_id,
		"Entity overlay should be reused across rebuilds"
	)
	assert_eq(_overlay_count(), 2, "Combined semantics should never accumulate duplicates")

	brush.set_brush_entity_class("")
	assert_null(brush.get_node_or_null("_BrushEntityOverlay"))
	assert_eq(_overlay_count(brush.OVERLAY_KIND_SUBTRACT), 1)


func test_legacy_auto_renamed_additive_overlays_are_all_cleaned_up():
	add_child(brush)
	for _index in range(24):
		# Adding the old canonical name repeatedly makes Godot generate the same
		# unreadable/suffixed names produced by the former rebuild lifecycle.
		brush.add_child(_make_legacy_additive_overlay())
	assert_eq(brush.get_child_count(), 25, "Fixture should contain the mesh plus leaked overlays")

	brush.rebuild_preview()
	assert_eq(_overlay_count(), 0)
	assert_eq(
		brush.get_child_count(),
		1,
		"Legacy overlay duplicates should stop rendering immediately, before queue_free flushes"
	)


func test_a_queued_subtract_overlay_is_not_reused_during_same_frame_rebuild():
	add_child(brush)
	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var queued := brush.get_node("_SubtractWireOverlay") as MeshInstance3D
	var queued_id := queued.get_instance_id()
	queued.queue_free()

	brush.rebuild_preview()
	var replacement := brush.get_node_or_null("_SubtractWireOverlay") as MeshInstance3D
	assert_not_null(replacement)
	if replacement:
		assert_ne(
			replacement.get_instance_id(),
			queued_id,
			"A node already queued for deletion must not be retained"
		)
	assert_eq(_overlay_count(brush.OVERLAY_KIND_SUBTRACT), 1)


func test_material_setters_refresh_immediately_and_preserve_semantic_overlay():
	add_child(brush)
	var custom := StandardMaterial3D.new()
	custom.albedo_color = Color(0.8, 0.3, 0.1)
	brush.material_override = custom
	assert_same(
		brush.mesh_instance.material_override,
		custom,
		"A whole-brush material should become visible immediately",
	)

	brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var overlay := brush.get_node_or_null("_SubtractWireOverlay") as MeshInstance3D
	assert_not_null(overlay)
	var overlay_id := overlay.get_instance_id() if overlay else 0

	brush.material_override = null
	var default_material := brush.mesh_instance.material_override as StandardMaterial3D
	assert_not_null(default_material, "Clearing an override should restore operation styling")
	if default_material:
		assert_eq(default_material.albedo_color, Color(1.0, 0.2, 0.2, 0.35))

	var editor_preview := StandardMaterial3D.new()
	editor_preview.albedo_color = Color(0.2, 0.4, 0.9)
	brush.set_editor_material(editor_preview)
	assert_same(brush.mesh_instance.material_override, editor_preview)
	brush.clear_editor_material()
	assert_not_null(brush.mesh_instance.material_override)
	assert_eq(_overlay_count(brush.OVERLAY_KIND_SUBTRACT), 1)
	if overlay_id != 0:
		assert_eq(
			brush.get_node("_SubtractWireOverlay").get_instance_id(),
			overlay_id,
			"Material changes should update, not replace, semantic overlays",
		)


func test_unmaterialed_custom_faces_render_their_real_geometry_not_a_fallback_box():
	brush.shape = brush.BrushShape.CUSTOM
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[
			Vector3(4, 0, -2),
			Vector3(4, 3, -2),
			Vector3(10, 3, -2),
			Vector3(10, 0, -2),
		]
	)
	face.ensure_geometry()
	brush.faces = [face]
	brush.geometry_dirty = false
	add_child(brush)

	assert_true(brush.mesh_instance.mesh is ArrayMesh)
	var bounds := brush.mesh_instance.get_aabb()
	assert_eq(bounds.position, Vector3(4, 0, -2))
	assert_almost_eq(bounds.size.x, 6.0, 0.0001)
	assert_almost_eq(bounds.size.y, 3.0, 0.0001)
	assert_almost_eq(bounds.size.z, 0.0, 0.0001)


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
# Winding migration: old-format (v0) face data loaded via apply_serialized_faces
# ===========================================================================


func test_v0_ccw_faces_migrated_to_cw_outward_normals():
	# Simulate old-format saved faces: CCW winding from outside, no
	# winding_version key.  After migration, normals should point outward.
	brush.size = Vector3(32, 32, 32)
	var half := brush.size * 0.5
	# Old CCW quads (the original _build_box_faces winding)
	var old_quads := [
		[
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, -half.y, half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, -half.y, -half.z)
		],
		[
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, half.y, -half.z)
		],
		[
			Vector3(-half.x, -half.y, half.z),
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, -half.y, half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z)
		],
		[
			Vector3(-half.x, half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, -half.z)
		]
	]
	# Build old-format dicts (no winding_version)
	var old_data: Array = []
	for quad in old_quads:
		var face := FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		var d := face.to_dict()
		d.erase("winding_version")  # Simulate v0
		old_data.append(d)
	brush.apply_serialized_faces(old_data)
	assert_eq(brush.faces.size(), 6, "Should load 6 faces")
	# All normals should point outward (away from origin for a centered box)
	var expected_dirs := [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
	]
	for i in range(brush.faces.size()):
		var face: FaceData = brush.faces[i]
		var face_center := Vector3.ZERO
		for v in face.local_verts:
			face_center += v
		face_center /= float(face.local_verts.size())
		var outward := face_center.normalized()
		assert_true(
			face.normal.dot(outward) > 0.5,
			(
				"Face %d normal should point outward, got %s vs expected ~%s"
				% [i, face.normal, outward]
			)
		)


func test_v1_faces_not_double_migrated():
	# New-format faces (winding_version=1) should pass through unchanged.
	brush.size = Vector3(32, 32, 32)
	var box_faces := brush._build_box_faces()
	brush.faces = box_faces
	var serialized := brush.serialize_faces()
	var normals_before: Array[Vector3] = []
	for face in brush.faces:
		normals_before.append(face.normal)
	brush.apply_serialized_faces(serialized)
	for i in range(brush.faces.size()):
		assert_true(
			brush.faces[i].normal.is_equal_approx(normals_before[i]),
			"Face %d normal should be unchanged after v1 round-trip" % i
		)


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


func test_odd_regular_polygon_profiles_fill_their_centered_requested_bounds():
	var half_extents := Vector2(7, 11)
	for side_count in [3, 5]:
		var points := PrefabFactory._regular_polygon_points(side_count, half_extents)
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		assert_eq(points.size(), side_count)
		assert_true(
			bounds.get_center().is_equal_approx(Vector2.ZERO),
			"A %d-sided profile should be centered on its brush" % side_count,
		)
		assert_true(
			bounds.size.is_equal_approx(half_extents * 2.0),
			"A %d-sided profile should fill both requested axes" % side_count,
		)


func test_odd_prism_preview_and_bake_bounds_match_the_requested_brush():
	var requested_size := Vector3(14, 22, 30)
	var cases := [
		{"shape": brush.BrushShape.PRISM_TRI, "sides": 3},
		{"shape": brush.BrushShape.PRISM_PENT, "sides": 5},
	]
	for entry in cases:
		brush.size = requested_size
		var mesh := brush._build_prism_mesh(entry["sides"] as int)
		assert_true(mesh.get_aabb().get_center().is_equal_approx(Vector3.ZERO))
		assert_true(mesh.get_aabb().size.is_equal_approx(requested_size))

		var baked := (
			PrefabFactory.create_prefab(entry["shape"] as int, requested_size) as CSGPolygon3D
		)
		assert_not_null(baked)
		if baked == null:
			continue
		autofree(baked)
		var profile_bounds := Rect2(baked.polygon[0], Vector2.ZERO)
		for point in baked.polygon:
			profile_bounds = profile_bounds.expand(point)
		assert_true(profile_bounds.get_center().is_equal_approx(Vector2.ZERO))
		assert_true(
			profile_bounds.size.is_equal_approx(Vector2(requested_size.x, requested_size.y))
		)
		assert_almost_eq(baked.depth, requested_size.z, 0.0001)


# ===========================================================================
# Wedge mesh generation
# ===========================================================================


func test_wedge_builds_a_centered_triangular_prism_instead_of_a_box():
	brush.shape = brush.BrushShape.WEDGE
	brush.size = Vector3(10, 20, 30)
	var build := brush._build_base_mesh()
	var mesh: Mesh = build.get("mesh")
	assert_true(mesh is ArrayMesh, "Wedge should use its own generated mesh")
	assert_eq(mesh.get_aabb().size, brush.size, "Wedge bounds should match the requested size")
	assert_eq(mesh.get_aabb().get_center(), Vector3.ZERO, "Wedge should be centered on the brush")

	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var unique_vertices: Dictionary = {}
	for vertex in vertices:
		unique_vertices[vertex] = true
	assert_eq(unique_vertices.size(), 6, "A wedge should have six unique corners")
	assert_eq(vertices.size(), 24, "A wedge should triangulate its five faces into eight triangles")


func test_wedge_wireframe_contains_all_nine_edges():
	brush.shape = brush.BrushShape.WEDGE
	brush.size = Vector3(10, 20, 30)
	var wire := brush._generate_wire_mesh()
	assert_not_null(wire, "Wedge should provide a selection wireframe")
	var arrays := wire.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), 18, "Nine wedge edges should produce eighteen line vertices")


# ===========================================================================
# Pyramid mesh generation
# ===========================================================================


func test_pyramid_is_centered_and_has_a_complete_base():
	var requested_size := Vector3(10, 20, 30)
	var mesh := PrefabFactory._pyramid_mesh(requested_size, 4)
	assert_not_null(mesh)
	assert_eq(mesh.get_aabb().size, requested_size)
	assert_eq(mesh.get_aabb().get_center(), Vector3.ZERO)

	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var base_area := 0.0
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		if (
			is_equal_approx(a.y, -10.0)
			and is_equal_approx(b.y, -10.0)
			and is_equal_approx(c.y, -10.0)
		):
			base_area += (b - a).cross(c - a).length() * 0.5
	var expected_base_area := (
		0.5 * 4.0 * (requested_size.x * 0.5) * (requested_size.z * 0.5) * sin(TAU / 4.0)
	)
	assert_almost_eq(base_area, expected_base_area, 0.001)
	assert_eq(vertices.size(), 24, "Four sides plus four base sectors produce eight triangles")


func test_adjustable_odd_pyramids_fill_centered_requested_bounds():
	var requested_size := Vector3(14, 22, 30)
	for side_count in [3, 5]:
		var mesh := PrefabFactory._pyramid_mesh(requested_size, side_count)
		assert_true(
			mesh.get_aabb().get_center().is_equal_approx(Vector3.ZERO),
			"A %d-sided pyramid should stay centered on its brush" % side_count,
		)
		assert_true(
			mesh.get_aabb().size.is_equal_approx(requested_size),
			"A %d-sided pyramid should fill all requested axes" % side_count,
		)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_eq(vertices.size(), side_count * 6, "Every side needs one wall and base triangle")


# ===========================================================================
# Curved primitive base-mesh bounds
# ===========================================================================


func test_sphere_base_mesh_matches_requested_uniform_bounds():
	_assert_base_mesh_matches_size(brush.BrushShape.SPHERE, Vector3(18, 18, 18))


func test_circular_primitive_sizes_normalize_to_their_visible_mesh_contract():
	for shape in [brush.BrushShape.CYLINDER, brush.BrushShape.CONE]:
		brush.shape = shape
		brush.size = Vector3(6, 12, 8)
		assert_eq(brush.size, Vector3(8, 12, 8))

	brush.shape = brush.BrushShape.CAPSULE
	brush.size = Vector3(10, 4, 6)
	assert_eq(brush.size, Vector3(10, 10, 10), "A capsule cannot be shorter than its diameter")

	brush.shape = brush.BrushShape.SPHERE
	brush.size = Vector3(6, 20, 8)
	assert_eq(
		brush.size,
		Vector3(8, 8, 8),
		"Sphere storage must match the X/Z diameter its mesh has always rendered",
	)


func test_ellipsoid_base_mesh_matches_requested_nonuniform_bounds():
	_assert_base_mesh_matches_size(brush.BrushShape.ELLIPSOID, Vector3(10, 24, 30))


func test_torus_base_mesh_matches_requested_nonuniform_bounds_without_property_errors():
	_assert_base_mesh_matches_size(brush.BrushShape.TORUS, Vector3(30, 8, 18))


func test_bake_factory_wedge_uses_the_same_centered_bounds_as_preview():
	var requested_size := Vector3(10, 20, 30)
	var wedge := PrefabFactory.create_prefab(brush.BrushShape.WEDGE, requested_size) as CSGPolygon3D
	assert_not_null(wedge, "Wedge should bake through a CSGPolygon3D")
	if wedge == null:
		return
	autofree(wedge)

	var bounds := Rect2(wedge.polygon[0], Vector2.ZERO)
	for point in wedge.polygon:
		bounds = bounds.expand(point)
	assert_eq(bounds.get_center(), Vector2.ZERO, "Baked wedge should remain brush-centered")
	assert_eq(bounds.size, Vector2(requested_size.x, requested_size.y))
	assert_almost_eq(wedge.depth, requested_size.z, 0.001)


func test_bake_factory_torus_uses_godot_4_radius_properties_and_requested_bounds():
	var requested_size := Vector3(30, 8, 18)
	var torus_shape := (
		PrefabFactory.create_prefab(brush.BrushShape.TORUS, requested_size) as CSGMesh3D
	)
	assert_not_null(torus_shape, "Torus should bake through a CSGMesh3D")
	if torus_shape == null:
		return
	autofree(torus_shape)
	assert_true(torus_shape.mesh is TorusMesh)
	var torus := torus_shape.mesh as TorusMesh
	assert_almost_eq(torus.outer_radius, 1.0, 0.001)
	assert_almost_eq(torus.inner_radius, 0.5, 0.001)
	var actual_size := torus.get_aabb().size * torus_shape.scale.abs()
	assert_almost_eq(actual_size.x, requested_size.x, 0.05)
	assert_almost_eq(actual_size.y, requested_size.y, 0.05)
	assert_almost_eq(actual_size.z, requested_size.z, 0.05)
