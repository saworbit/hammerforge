extends GutTest
## Regression coverage for quiet, semantic viewport outlines.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFOutlineUtil = preload("res://addons/hammerforge/hf_outline_util.gd")
const BrushGizmoPlugin = preload("res://addons/hammerforge/brush_gizmo_plugin.gd")
const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")


class ResizeTransactionRoot:
	extends Node3D
	var draft_brushes_node := Node3D.new()
	var brush_system := HFBrushSystem.new(self)
	var texture_lock := true
	var dirty_brush_ids: Array[String] = []
	var transform_call_count := 0

	func _init() -> void:
		draft_brushes_node.name = "DraftBrushes"
		add_child(draft_brushes_node)

	func _iter_pick_nodes() -> Array[Node]:
		var nodes: Array[Node] = []
		for child in draft_brushes_node.get_children():
			nodes.append(child)
		return nodes

	func tag_brush_dirty(brush_id: String) -> void:
		if not dirty_brush_ids.has(brush_id):
			dirty_brush_ids.append(brush_id)

	func set_brush_transform_by_id(brush_id: String, size: Vector3, position: Vector3) -> void:
		transform_call_count += 1
		brush_system.set_brush_transform_by_id(brush_id, size, position)


func test_box_outline_contains_only_twelve_structural_edges() -> void:
	var lines := HFOutlineUtil.box_lines(Vector3(2, 2, 2))
	assert_eq(lines.size(), 24, "A box outline should contain exactly twelve line segments")
	assert_false(
		_has_segment(lines, Vector3(-1, -1, -1), Vector3(1, 1, -1)),
		"The outline must not expose a triangulation diagonal",
	)
	assert_false(
		_has_segment(lines, Vector3(-1, -1, 1), Vector3(1, 1, 1)),
		"Neither side of the box should expose a triangulation diagonal",
	)


func test_line_mesh_uses_line_primitives_instead_of_wireframe_triangles() -> void:
	var mesh := HFOutlineUtil.line_mesh(HFOutlineUtil.box_lines())
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINES)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), 24)


func test_aabb_outline_transform_preserves_offset_and_mesh_scale() -> void:
	var aabb := AABB(Vector3(2, 4, -6), Vector3(10, 20, 30))
	var local_box := HFOutlineUtil.aabb_box_transform(aabb)
	assert_eq(local_box.origin, aabb.get_center())
	assert_eq(local_box.basis.get_scale(), aabb.size)

	var mesh_transform := Transform3D(Basis.from_scale(Vector3(2, 0.5, 3)), Vector3(100, 50, -25))
	var outline_transform := mesh_transform * local_box
	assert_eq(
		outline_transform * Vector3(-0.5, -0.5, -0.5),
		mesh_transform * aabb.position,
		"The outline minimum should match an offset mesh AABB after mesh scaling",
	)
	assert_eq(
		outline_transform * Vector3(0.5, 0.5, 0.5),
		mesh_transform * aabb.end,
		"The outline maximum should match an offset mesh AABB after mesh scaling",
	)


func test_degenerate_bounds_emit_only_distinct_nonzero_outline_segments() -> void:
	var planar := (
		HFOutlineUtil
		. points_bounds_lines(
			PackedVector3Array(
				[
					Vector3(-2, -1, 3),
					Vector3(2, -1, 3),
					Vector3(2, 1, 3),
					Vector3(-2, 1, 3),
				]
			)
		)
	)
	assert_eq(planar.size(), 8, "A planar preview should have four perimeter edges")
	_assert_valid_lines(planar)

	var linear := HFOutlineUtil.points_bounds_lines(
		PackedVector3Array([Vector3(-3, 4, 5), Vector3(3, 4, 5)])
	)
	assert_eq(linear.size(), 2, "A linear preview should have one distinct segment")
	_assert_valid_lines(linear)


func test_selected_brush_suppresses_redundant_hover_outline() -> void:
	var brush := Node3D.new()
	autofree(brush)
	var other := Node3D.new()
	autofree(other)
	assert_true(HFBrushSystem.should_suppress_hover(brush, [brush]))
	assert_false(HFBrushSystem.should_suppress_hover(brush, [other]))
	assert_false(HFBrushSystem.should_suppress_hover(null, [brush]))


func test_face_outline_deduplicates_shared_edges_without_adding_diagonals() -> void:
	var faces := _make_box_faces()
	var lines := HFOutlineUtil.face_boundary_lines(faces)
	assert_eq(lines.size(), 24, "Six quad boundaries should collapse to twelve unique edges")
	assert_false(
		_has_segment(lines, Vector3(-1, -1, -1), Vector3(1, 1, -1)),
		"Face triangulation must not leak into custom-brush outlines",
	)


func test_semantic_face_outline_removes_coplanar_diagonal_but_keeps_folded_crease() -> void:
	var a := Vector3(-1, -1, 0)
	var b := Vector3(1, -1, 0)
	var c := Vector3(1, 1, 0)
	var d := Vector3(-1, 1, 0)
	var flat_lines := HFOutlineUtil.semantic_face_lines(
		[_make_face([a, b, c]), _make_face([a, c, d])]
	)
	assert_eq(flat_lines.size(), 8, "A triangulated quad should expose only four boundaries")
	assert_false(_has_segment(flat_lines, a, c), "The coplanar shared diagonal must disappear")

	var folded := Vector3(0, -1, 2)
	var folded_lines := HFOutlineUtil.semantic_face_lines(
		[_make_face([a, b, c]), _make_face([b, a, folded])]
	)
	assert_eq(folded_lines.size(), 10, "Two folded triangles have four boundaries and one crease")
	assert_true(_has_segment(folded_lines, a, b), "A genuine shared crease must remain visible")


func test_custom_brush_uses_face_outline_and_hides_box_resize_handles() -> void:
	var brush := DraftBrush.new()
	autofree(brush)
	brush.shape = brush.BrushShape.CUSTOM
	brush.faces = _make_box_faces()

	var lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
	assert_eq(lines.size(), 24)
	assert_false(BrushGizmoPlugin.supports_resize_handles(brush))


func test_custom_brush_drops_flat_triangulation_but_preserves_real_creases() -> void:
	var brush := DraftBrush.new()
	autofree(brush)
	brush.shape = brush.BrushShape.CUSTOM
	var a := Vector3(-1, -1, 0)
	var b := Vector3(1, -1, 0)
	var c := Vector3(1, 1, 0)
	var d := Vector3(-1, 1, 0)
	brush.faces = [_make_face([a, b, c]), _make_face([a, c, d])]

	var flat_lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
	assert_eq(flat_lines.size(), 8)
	assert_false(_has_segment(flat_lines, a, c), "A merged quad must not show its old diagonal")

	var folded := Vector3(0, -1, 2)
	brush.faces = [_make_face([a, b, c]), _make_face([b, a, folded])]
	var folded_lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
	assert_eq(folded_lines.size(), 10)
	assert_true(_has_segment(folded_lines, a, b), "A genuine folded edge must stay visible")


func test_regular_box_keeps_simple_outline_and_resize_handles() -> void:
	var brush := DraftBrush.new()
	autofree(brush)
	brush.shape = brush.BrushShape.BOX
	brush.size = Vector3(4, 6, 8)

	var lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
	assert_eq(lines.size(), 24)
	assert_true(BrushGizmoPlugin.supports_resize_handles(brush))


func test_empty_custom_brush_keeps_a_fallback_outline_without_resize_handles() -> void:
	var brush := DraftBrush.new()
	autofree(brush)
	brush.shape = brush.BrushShape.CUSTOM
	brush.faces.clear()

	assert_eq(BrushGizmoPlugin.outline_lines_for_brush(brush).size(), 24)
	assert_false(BrushGizmoPlugin.supports_resize_handles(brush))


func test_angular_brushes_use_exact_structural_edges_without_triangle_fans() -> void:
	var cases := [
		{"shape": DraftBrush.BrushShape.WEDGE, "sides": 4, "vertices": 18},
		{"shape": DraftBrush.BrushShape.PYRAMID, "sides": 4, "vertices": 16},
		{"shape": DraftBrush.BrushShape.PRISM_PENT, "sides": 5, "vertices": 30},
		{"shape": DraftBrush.BrushShape.DODECAHEDRON, "sides": 4, "vertices": 60},
	]
	for entry in cases:
		var brush := _make_builtin_shape_brush(entry["shape"], Vector3(10, 20, 30), entry["sides"])
		var lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
		assert_eq(
			lines.size(),
			entry["vertices"],
			"Shape %d should expose only its structural edges" % entry["shape"],
		)
		_assert_valid_lines(lines)

	var wedge := _make_builtin_shape_brush(DraftBrush.BrushShape.WEDGE, Vector3(10, 20, 30))
	var wedge_lines := BrushGizmoPlugin.outline_lines_for_brush(wedge)
	assert_false(
		_has_segment(wedge_lines, Vector3(-5, -10, -15), Vector3(5, -10, 15)),
		"The wedge's bottom quad diagonal must not leak into its outline",
	)


func test_pyramid_outline_matches_centered_prefab_bounds() -> void:
	var requested_size := Vector3(10, 20, 30)
	var brush := _make_builtin_shape_brush(DraftBrush.BrushShape.PYRAMID, requested_size, 4)
	var lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
	var bounds := _points_aabb(lines)

	assert_eq(lines.size(), 16, "A four-sided pyramid should have four base and four rise edges")
	_assert_vector_near(bounds.get_center(), Vector3.ZERO)
	_assert_vector_near(bounds.size, requested_size)
	var apex := Vector3(0, requested_size.y * 0.5, 0)
	var apex_occurrences := 0
	for point in lines:
		if point.is_equal_approx(apex):
			apex_occurrences += 1
		else:
			assert_almost_eq(
				point.y,
				-requested_size.y * 0.5,
				0.0001,
				"Every non-apex outline point should lie on the centered base plane",
			)
	assert_eq(apex_occurrences, 4, "Each rise edge should terminate at the centered apex")


func test_odd_polygon_outlines_match_mesh_bounds_and_resize_handle_planes() -> void:
	var requested_size := Vector3(14, 22, 30)
	var cases := [
		{"shape": DraftBrush.BrushShape.PYRAMID, "sides": 3, "line_vertices": 12},
		{"shape": DraftBrush.BrushShape.PYRAMID, "sides": 5, "line_vertices": 20},
		{"shape": DraftBrush.BrushShape.PRISM_TRI, "sides": 3, "line_vertices": 18},
		{"shape": DraftBrush.BrushShape.PRISM_PENT, "sides": 5, "line_vertices": 30},
	]
	for entry in cases:
		var brush := _make_builtin_shape_brush(
			int(entry["shape"]), requested_size, int(entry["sides"])
		)
		var lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
		var outline_bounds := _points_aabb(lines)
		var build := brush._build_base_mesh()
		var mesh := build.get("mesh", null) as Mesh
		assert_not_null(mesh)
		if mesh == null:
			continue
		var mesh_scale: Vector3 = build.get("scale", Vector3.ONE)
		var mesh_bounds := mesh.get_aabb()
		mesh_bounds.position *= mesh_scale
		mesh_bounds.size *= mesh_scale.abs()

		assert_eq(lines.size(), int(entry["line_vertices"]))
		_assert_vector_near(outline_bounds.get_center(), Vector3.ZERO)
		_assert_vector_near(outline_bounds.size, requested_size)
		_assert_vector_near(mesh_bounds.get_center(), outline_bounds.get_center())
		_assert_vector_near(mesh_bounds.size, outline_bounds.size)
		assert_true(
			BrushGizmoPlugin.supports_resize_handles(brush),
			"An adjustable polygon brush should keep its six AABB resize handles",
		)

		var mesh_vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point in lines:
			assert_true(
				_contains_approx_point(mesh_vertices, point),
				"Every semantic outline endpoint should lie on the rendered mesh",
			)


func test_curved_brushes_use_sparse_semantic_profiles_instead_of_render_wireframes() -> void:
	var cases := [
		{"shape": DraftBrush.BrushShape.CYLINDER, "size": Vector3(20, 30, 20), "count": 72},
		{"shape": DraftBrush.BrushShape.CONE, "size": Vector3(20, 30, 20), "count": 40},
		{"shape": DraftBrush.BrushShape.SPHERE, "size": Vector3(20, 20, 20), "count": 96},
		{"shape": DraftBrush.BrushShape.ELLIPSOID, "size": Vector3(10, 20, 30), "count": 96},
		{"shape": DraftBrush.BrushShape.CAPSULE, "size": Vector3(10, 30, 10), "count": 104},
		{"shape": DraftBrush.BrushShape.TORUS, "size": Vector3(30, 8, 18), "count": 192},
	]
	for entry in cases:
		var brush := _make_builtin_shape_brush(entry["shape"], entry["size"])
		var lines := BrushGizmoPlugin.outline_lines_for_brush(brush)
		assert_eq(
			lines.size(),
			entry["count"],
			"Shape %d should use a deterministic sparse profile" % entry["shape"],
		)
		assert_ne(lines.size(), 24, "A curved primitive must never fall back to a box outline")
		_assert_valid_lines(lines)


func test_sphere_resize_keeps_all_local_dimensions_uniform_and_anchors_dragged_face() -> void:
	var result := (
		BrushGizmoPlugin
		. calculate_brush_axis_resize(
			DraftBrush.BrushShape.SPHERE,
			Basis.from_scale(Vector3(2, 3, 4)),
			Vector3(4, 4, 4),
			Vector3.ZERO,
			Vector3.RIGHT,
			1,
			9.2,
			2.0,
		)
	)
	assert_eq(result["size"], Vector3(5, 5, 5))
	assert_almost_eq(result["world_extent"], 10.0, 0.0001)
	_assert_vector_near(result["position"], Vector3(1, 0, 0))
	var anchored_opposite := (result["position"] as Vector3) - Vector3.RIGHT * 5.0
	_assert_vector_near(anchored_opposite, Vector3(-4, 0, 0))


func test_nonuniform_sphere_uses_visible_diameter_for_handles_and_anchor() -> void:
	var result := (
		BrushGizmoPlugin
		. calculate_brush_axis_resize(
			DraftBrush.BrushShape.SPHERE,
			Basis.IDENTITY,
			Vector3(6, 20, 8),
			Vector3.ZERO,
			Vector3.UP,
			1,
			10.2,
			2.0,
		)
	)
	assert_eq(result["size"], Vector3(10, 10, 10))
	_assert_vector_near(result["opposite_face"], Vector3(0, -4, 0))
	_assert_vector_near(result["position"], Vector3(0, 1, 0))


func test_radial_shapes_couple_xz_but_leave_height_independent() -> void:
	for shape in [
		DraftBrush.BrushShape.CYLINDER,
		DraftBrush.BrushShape.CONE,
		DraftBrush.BrushShape.CAPSULE,
	]:
		var radial := (
			BrushGizmoPlugin
			. calculate_brush_axis_resize(
				shape,
				Basis.IDENTITY,
				Vector3(6, 12, 8),
				Vector3.ZERO,
				Vector3.BACK,
				1,
				10.2,
				2.0,
			)
		)
		assert_eq(radial["size"], Vector3(10, 12, 10))
		_assert_vector_near(radial["position"], Vector3(0, 0, 1))

		var cross_axis := (
			BrushGizmoPlugin
			. calculate_brush_axis_resize(
				shape,
				Basis.IDENTITY,
				Vector3(6, 12, 8),
				Vector3.ZERO,
				Vector3.RIGHT,
				1,
				10.2,
				2.0,
			)
		)
		assert_eq(cross_axis["size"], Vector3(10, 12, 10))
		_assert_vector_near(cross_axis["opposite_face"], Vector3(-4, 0, 0))
		_assert_vector_near(cross_axis["position"], Vector3(1, 0, 0))

		var height := (
			BrushGizmoPlugin
			. calculate_brush_axis_resize(
				shape,
				Basis.IDENTITY,
				Vector3(6, 12, 8),
				Vector3.ZERO,
				Vector3.UP,
				1,
				14.2,
				2.0,
			)
		)
		assert_eq(height["size"], Vector3(8, 14, 8))
		_assert_vector_near(height["position"], Vector3(0, 1, 0))


func test_capsule_resize_preserves_valid_height_and_the_dragged_face_anchor() -> void:
	var height := (
		BrushGizmoPlugin
		. calculate_brush_axis_resize(
			DraftBrush.BrushShape.CAPSULE,
			Basis.IDENTITY,
			Vector3(10, 12, 10),
			Vector3.ZERO,
			Vector3.UP,
			1,
			4.0,
			0.0,
		)
	)
	assert_eq(height["size"], Vector3(10, 10, 10))
	_assert_vector_near(height["opposite_face"], Vector3(0, -6, 0))
	_assert_vector_near(height["position"], Vector3(0, -1, 0))
	_assert_vector_near(
		(height["position"] as Vector3) - Vector3.UP * (height["size"] as Vector3).y * 0.5,
		Vector3(0, -6, 0),
	)

	var diameter := (
		BrushGizmoPlugin
		. calculate_brush_axis_resize(
			DraftBrush.BrushShape.CAPSULE,
			Basis.IDENTITY,
			Vector3(10, 12, 10),
			Vector3.ZERO,
			Vector3.RIGHT,
			1,
			20.0,
			0.0,
		)
	)
	assert_eq(diameter["size"], Vector3(20, 20, 20))
	_assert_vector_near(diameter["opposite_face"], Vector3(-5, 0, 0))
	_assert_vector_near(diameter["position"], Vector3(5, 0, 0))


func test_non_radial_shapes_keep_independent_axis_resize() -> void:
	for shape in [
		DraftBrush.BrushShape.ELLIPSOID,
		DraftBrush.BrushShape.TORUS,
		DraftBrush.BrushShape.PRISM_PENT,
	]:
		var result := (
			BrushGizmoPlugin
			. calculate_brush_axis_resize(
				shape,
				Basis.IDENTITY,
				Vector3(6, 12, 8),
				Vector3.ZERO,
				Vector3.RIGHT,
				1,
				10.2,
				2.0,
			)
		)
		assert_eq(result["size"], Vector3(10, 12, 8))


func test_brush_face_triangles_supply_a_filled_native_gizmo_collision_proxy() -> void:
	var vertices := HFOutlineUtil.face_triangle_vertices(_make_box_faces())
	assert_eq(vertices.size(), 36, "Six quads should triangulate into twelve filled triangles")
	var collision := HFOutlineUtil.triangle_mesh_from_vertices(vertices)
	assert_not_null(collision)
	if collision:
		assert_eq(collision.get_faces().size(), 36)

	var degenerate := _make_face([Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0])
	assert_true(HFOutlineUtil.face_triangle_vertices([degenerate]).is_empty())


func test_draft_entity_gizmo_uses_visible_nested_mesh_triangles_without_resize_handles() -> void:
	var entity := DraftEntity.new()
	add_child_autoqfree(entity)
	var preview_root := Node3D.new()
	preview_root.position = Vector3(3, 2, -1)
	entity.add_child(preview_root, false, Node.INTERNAL_MODE_BACK)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 4, 6)
	visual.mesh = mesh
	visual.scale = Vector3(2, 0.5, 1)
	preview_root.add_child(visual, false, Node.INTERNAL_MODE_BACK)

	var triangles := HFOutlineUtil.visible_mesh_triangle_vertices(entity)
	assert_eq(triangles.size(), 36)
	var lines := BrushGizmoPlugin.outline_lines_for_entity(entity)
	assert_eq(lines.size(), 24, "Entity previews should use one restrained local bounds outline")
	assert_true(
		_has_segment(lines, Vector3(1, 1, -4), Vector3(5, 1, -4)),
		"Nested preview transforms must be preserved in entity-local gizmo geometry",
	)
	assert_not_null(HFOutlineUtil.visible_mesh_triangle_mesh(entity))
	assert_false(BrushGizmoPlugin.supports_resize_handles(entity))

	preview_root.visible = false
	assert_true(HFOutlineUtil.visible_mesh_triangle_vertices(entity).is_empty())
	assert_true(BrushGizmoPlugin.outline_lines_for_entity(entity).is_empty())


func test_billboard_entity_uses_a_texture_sized_camera_independent_pick_proxy() -> void:
	var entity := DraftEntity.new()
	add_child_autoqfree(entity)
	var sprite := Sprite3D.new()
	var image := Image.create(80, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = 0.05
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = Vector3(3, 2, -1)
	entity.add_child(sprite, false, Node.INTERNAL_MODE_BACK)

	var sprite_triangles := HFOutlineUtil.visible_sprite_proxy_triangle_vertices(entity)
	var collision_triangles := BrushGizmoPlugin.collision_vertices_for_entity(entity)
	var bounds := _points_aabb(collision_triangles)
	var expected_diameter := sqrt(20.0)  # Diagonal of the nominal 4 x 2 world-unit quad.
	assert_eq(sprite_triangles.size(), 36, "A billboard should use one restrained solid proxy")
	assert_eq(collision_triangles.size(), 36, "A visible sprite must not use the generic marker")
	_assert_vector_near(bounds.get_center(), sprite.position)
	_assert_vector_near(bounds.size, Vector3.ONE * expected_diameter)
	assert_eq(BrushGizmoPlugin.outline_lines_for_entity(entity).size(), 24)

	# Hidden preview geometry is intentional and must not be confused with an
	# entity that has no preview node at all (which receives the generic marker).
	sprite.visible = false
	assert_true(HFOutlineUtil.visible_sprite_proxy_triangle_vertices(entity).is_empty())
	assert_true(BrushGizmoPlugin.collision_vertices_for_entity(entity).is_empty())
	assert_true(BrushGizmoPlugin.outline_lines_for_entity(entity).is_empty())


func test_geometryless_draft_entity_gets_a_small_native_pick_marker() -> void:
	var entity := DraftEntity.new()
	add_child_autoqfree(entity)
	var triangles := BrushGizmoPlugin.collision_vertices_for_entity(entity)
	assert_eq(triangles.size(), 36)
	assert_eq(BrushGizmoPlugin.outline_lines_for_entity(entity).size(), 24)
	assert_not_null(HFOutlineUtil.triangle_mesh_from_vertices(triangles))
	assert_false(BrushGizmoPlugin.supports_resize_handles(entity))


func test_visible_broken_or_line_only_entity_preview_remains_selectable() -> void:
	var null_entity := DraftEntity.new()
	add_child_autoqfree(null_entity)
	var null_visual := MeshInstance3D.new()
	null_visual.position = Vector3(3, 2, -1)
	null_entity.add_child(null_visual, false, Node.INTERNAL_MODE_BACK)
	var null_triangles := BrushGizmoPlugin.collision_vertices_for_entity(null_entity)
	assert_eq(null_triangles.size(), 36)
	_assert_vector_near(_points_aabb(null_triangles).get_center(), null_visual.position)

	null_visual.visible = false
	assert_true(
		BrushGizmoPlugin.collision_vertices_for_entity(null_entity).is_empty(),
		"A hidden broken preview must not leave an invisible marker",
	)

	var line_entity := DraftEntity.new()
	add_child_autoqfree(line_entity)
	var line_visual := MeshInstance3D.new()
	line_visual.position = Vector3(-2, 1, 4)
	line_visual.mesh = HFOutlineUtil.line_mesh(
		PackedVector3Array([Vector3(-3, 0, 0), Vector3(3, 0, 0)])
	)
	line_entity.add_child(line_visual, false, Node.INTERNAL_MODE_BACK)
	var line_triangles := BrushGizmoPlugin.collision_vertices_for_entity(line_entity)
	var line_bounds := _points_aabb(line_triangles)
	assert_eq(line_triangles.size(), 36)
	_assert_vector_near(line_bounds.get_center(), line_visual.position)
	_assert_vector_near(line_bounds.size, Vector3(6, 1, 1))


func test_composite_entity_keeps_incomplete_siblings_in_its_pick_surface() -> void:
	var null_entity := DraftEntity.new()
	add_child_autoqfree(null_entity)
	var valid_mesh := MeshInstance3D.new()
	valid_mesh.mesh = BoxMesh.new()
	(valid_mesh.mesh as BoxMesh).size = Vector3(2, 2, 2)
	valid_mesh.position = Vector3(-4, 0, 0)
	null_entity.add_child(valid_mesh, false, Node.INTERNAL_MODE_BACK)
	var null_visual := MeshInstance3D.new()
	null_visual.position = Vector3(4, 0, 0)
	null_entity.add_child(null_visual, false, Node.INTERNAL_MODE_BACK)

	var null_composite := BrushGizmoPlugin.collision_vertices_for_entity(null_entity)
	assert_eq(null_composite.size(), 72, "Valid and missing visual proxies must both be retained")
	assert_gt(_points_aabb(null_composite).end.x, 4.0)

	var line_entity := DraftEntity.new()
	add_child_autoqfree(line_entity)
	var second_valid := MeshInstance3D.new()
	second_valid.mesh = BoxMesh.new()
	second_valid.position = Vector3(-4, 0, 0)
	line_entity.add_child(second_valid, false, Node.INTERNAL_MODE_BACK)
	var line_visual := MeshInstance3D.new()
	line_visual.mesh = HFOutlineUtil.line_mesh(
		PackedVector3Array([Vector3(-3, 0, 0), Vector3(3, 0, 0)])
	)
	line_visual.position = Vector3(4, 0, 0)
	line_entity.add_child(line_visual, false, Node.INTERNAL_MODE_BACK)

	var line_composite := BrushGizmoPlugin.collision_vertices_for_entity(line_entity)
	assert_eq(line_composite.size(), 72, "Valid and line-only visual proxies must both be retained")
	assert_gt(_points_aabb(line_composite).end.x, 6.9)


func test_entity_collision_respects_top_level_visuals_and_hidden_ancestors() -> void:
	var entity := DraftEntity.new()
	add_child_autoqfree(entity)
	entity.position = Vector3(10, 3, -7)
	entity.rotation.y = 0.65
	entity.force_update_transform()
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	(visual.mesh as BoxMesh).size = Vector3(2, 4, 6)
	entity.add_child(visual, false, Node.INTERNAL_MODE_BACK)
	visual.top_level = true
	visual.global_transform = (
		entity.global_transform * Transform3D(Basis.IDENTITY, Vector3(3, 2, -1))
	)
	visual.force_update_transform()

	var bounds := _points_aabb(BrushGizmoPlugin.collision_vertices_for_entity(entity))
	_assert_vector_near(bounds.get_center(), Vector3(3, 2, -1))
	_assert_vector_near(bounds.size, Vector3(2, 4, 6))

	var hidden_parent := Node3D.new()
	add_child_autoqfree(hidden_parent)
	var hidden_entity := DraftEntity.new()
	hidden_parent.add_child(hidden_entity)
	hidden_parent.visible = false
	assert_false(hidden_entity.is_visible_in_tree())
	assert_true(
		BrushGizmoPlugin.collision_vertices_for_entity(hidden_entity).is_empty(),
		"A hidden managed parent must suppress even the geometry-less fallback marker",
	)


func test_gizmo_registers_filled_and_semantic_collision_for_brushes_and_entities() -> void:
	var source := (
		FileAccess
		. get_file_as_string("res://addons/hammerforge/brush_gizmo_plugin.gd")
		. replace("\r\n", "\n")
	)
	assert_true(source.contains("return node is DraftBrush or node is DraftEntity"))
	assert_true(source.contains("gizmo.add_collision_triangles(collision_triangles)"))
	assert_true(source.contains("gizmo.add_collision_segments(lines)"))
	assert_true(source.contains("func _redraw_entity("))


func test_handle_action_lifecycle_finishes_clicks_noops_and_cancels() -> void:
	var lifecycle := BrushGizmoPlugin.HandleActionLifecycle.new()
	autofree(lifecycle)
	watch_signals(lifecycle)

	assert_false(lifecycle.active)
	assert_true(lifecycle.begin())
	assert_false(lifecycle.begin())
	assert_true(lifecycle.active)
	assert_signal_emit_count(lifecycle, "started", 1, "Begin should be idempotent")

	# A click/no-op can have no usable gizmo node, but it must still release
	# pointer ownership and emit a matching completion.
	assert_true(lifecycle.finish(false))
	assert_false(lifecycle.active)
	assert_signal_emit_count(lifecycle, "finished", 1)
	assert_signal_emitted_with_parameters(lifecycle, "finished", [false])
	assert_false(lifecycle.finish(false), "Finishing an idle action should be harmless")
	assert_signal_emit_count(lifecycle, "finished", 1)

	assert_true(lifecycle.begin())
	assert_true(lifecycle.finish(true))
	assert_false(lifecycle.active)
	assert_signal_emit_count(lifecycle, "started", 2)
	assert_signal_emit_count(lifecycle, "finished", 2)
	assert_signal_emitted_with_parameters(lifecycle, "finished", [true])


func test_late_retired_commit_cannot_mutate_or_finish_a_new_identical_action() -> void:
	var identity := BrushGizmoPlugin.HandleCommitIdentity.new()
	autofree(identity)
	var original_restore := {"size": Vector3.ONE, "position": Vector3.ZERO}
	var token_a := identity.begin(101, 202, 0, false, 1)
	var restore_a := identity.decorate_restore(original_restore.duplicate(), 101, 202, 0, false)

	assert_eq(
		identity.classify_commit(restore_a, 101, 202, 0, false),
		BrushGizmoPlugin.HandleCommitIdentity.COMMIT_ACTIVE,
	)
	assert_true(identity.retire_active(token_a))

	# Reusing the exact gizmo, node, handle and original transform is the hard
	# case: only the opaque action token can distinguish these callbacks.
	var token_b := identity.begin(101, 202, 0, false, 2)
	var restore_b := identity.decorate_restore(original_restore.duplicate(), 101, 202, 0, false)
	assert_ne(token_a, token_b)
	assert_eq(
		identity.classify_commit(restore_a, 101, 202, 0, false),
		BrushGizmoPlugin.HandleCommitIdentity.COMMIT_RETIRED,
	)
	assert_true(identity.consume_retired(restore_a, 101, 202, 0, false))
	assert_eq(identity.active_token, token_b, "Consuming A must leave B active")
	assert_eq(
		identity.classify_commit(restore_b, 101, 202, 0, false),
		BrushGizmoPlugin.HandleCommitIdentity.COMMIT_ACTIVE,
	)
	assert_false(
		identity.consume_retired(restore_a, 101, 202, 0, false),
		"A duplicate stale callback should fail closed",
	)
	assert_true(identity.finish_active(token_b))
	assert_null(identity.active_token)


func test_handle_commit_identity_rejects_unknown_fields_and_stale_force_tokens() -> void:
	var identity := BrushGizmoPlugin.HandleCommitIdentity.new()
	autofree(identity)
	var token_a := identity.begin(11, 22, 3, true, 7)
	var restore_a := identity.decorate_restore({}, 11, 22, 3, true)
	assert_true(identity.finish_active(token_a))

	var token_b := identity.begin(11, 22, 3, true, 8)
	var restore_b := identity.decorate_restore({}, 11, 22, 3, true)
	assert_false(
		identity.retire_active(token_a),
		"A deferred recovery for A must never retire the newer action B",
	)
	assert_eq(identity.active_token, token_b)
	assert_eq(
		identity.classify_commit({}, 11, 22, 3, true),
		BrushGizmoPlugin.HandleCommitIdentity.COMMIT_UNKNOWN,
	)
	assert_eq(
		identity.classify_commit(restore_b, 11, 22, 4, true),
		BrushGizmoPlugin.HandleCommitIdentity.COMMIT_UNKNOWN,
	)
	assert_eq(
		identity.classify_commit(restore_b, 11, 22, 3, false),
		BrushGizmoPlugin.HandleCommitIdentity.COMMIT_UNKNOWN,
	)
	assert_eq(identity.active_token, token_b, "Malformed callbacks must not clear B")
	assert_true(identity.finish_active(token_b))


func test_scaled_parent_resize_snaps_in_world_space_and_preserves_opposite_face() -> void:
	var basis := Basis.from_scale(Vector3(2, 3, 4))
	var original_size := Vector3(4, 6, 8)
	var original_center := Vector3(10, 20, 30)
	var result := BrushGizmoPlugin.calculate_axis_resize(
		basis, original_size, original_center, Vector3.RIGHT, 1, 9.2, 2.0
	)

	assert_false(result.is_empty())
	assert_almost_eq(result["world_extent"], 10.0, 0.0001)
	assert_almost_eq((result["size"] as Vector3).x, 5.0, 0.0001)
	_assert_vector_near(result["position"], Vector3(11, 20, 30))
	var old_opposite := original_center - Vector3.RIGHT * original_size.x
	var new_opposite := (result["position"] as Vector3) - Vector3.RIGHT * 5.0
	_assert_vector_near(new_opposite, old_opposite)


func test_rotated_scaled_parent_resize_preserves_world_opposite_face() -> void:
	var parent_basis := (
		Basis.from_euler(Vector3(0.25, -0.55, 0.15)) * Basis.from_scale(Vector3(2, 3, 0.5))
	)
	var local_basis := Basis.from_euler(Vector3(-0.2, 0.4, 0.1))
	var global_basis := parent_basis * local_basis
	var axis := Vector3.BACK
	var original_size := Vector3(5, 7, 6)
	var original_center := Vector3(-12, 8, 21)
	var axis_vector := global_basis * axis
	var axis_scale := axis_vector.length()
	var axis_world := axis_vector / axis_scale
	var old_opposite := original_center + axis_world * original_size.z * axis_scale * 0.5

	var result := BrushGizmoPlugin.calculate_axis_resize(
		global_basis, original_size, original_center, axis, -1, 13.1, 2.0
	)

	assert_false(result.is_empty())
	assert_almost_eq(result["world_extent"], 14.0, 0.0001)
	assert_almost_eq((result["size"] as Vector3).z, 14.0 / axis_scale, 0.0001)
	var new_opposite := (
		(result["position"] as Vector3)
		+ axis_world * (result["size"] as Vector3).z * axis_scale * 0.5
	)
	_assert_vector_near(new_opposite, old_opposite)


func test_axis_resize_rejects_collapsed_or_invalid_transform_axes() -> void:
	assert_true(
		(
			BrushGizmoPlugin
			. calculate_axis_resize(
				Basis.from_scale(Vector3(0.000001, 1, 1)),
				Vector3.ONE,
				Vector3.ZERO,
				Vector3.RIGHT,
				1,
				4.0,
				1.0,
			)
			. is_empty()
		)
	)
	assert_true(
		(
			BrushGizmoPlugin
			. calculate_axis_resize(
				Basis.IDENTITY,
				Vector3.ONE,
				Vector3.ZERO,
				Vector3.RIGHT,
				0,
				4.0,
				1.0,
			)
			. is_empty()
		)
	)


func test_recovered_handle_action_freezes_preview_until_engine_commit() -> void:
	var source := (
		FileAccess
		. get_file_as_string("res://addons/hammerforge/brush_gizmo_plugin.gd")
		. replace("\r\n", "\n")
	)
	var cancel_start := source.find("func cancel_active_handle_action() -> bool:")
	var cancel_end := source.find("\n\nfunc _has_gizmo", cancel_start)
	var cancel_block := source.substr(cancel_start, cancel_end - cancel_start)
	assert_true(cancel_block.contains("_handle_action_frozen = true"))
	assert_false(
		cancel_block.contains("_finish_handle_action("),
		"Recovery must leave ownership active for Godot's eventual commit callback",
	)

	var set_start := source.find("func _set_handle(")
	var set_end := source.find("\n\nfunc _resolve_grid_snap", set_start)
	var set_block := source.substr(set_start, set_end - set_start)
	var frozen_guard := set_block.find(
		"if not _ensure_handle_action().active or _handle_action_frozen:"
	)
	assert_gte(frozen_guard, 0)
	assert_lt(frozen_guard, set_block.find("var brush"))

	var finish_start := source.find("func _finish_handle_action(")
	var finish_end := source.find("\n\n## Recover", finish_start)
	var finish_block := source.substr(finish_start, finish_end - finish_start)
	assert_true(finish_block.contains("_handle_action_frozen = false"))
	assert_true(
		(
			cancel_block.contains('"_force_finish_frozen_handle_action"')
			and cancel_block.contains("_ensure_handle_commit_identity().active_token")
		),
		"A genuinely lost native commit must not leave exclusive input latched forever",
	)

	var force_start := source.find("func _force_finish_frozen_handle_action(")
	var force_end := source.find("\n\nfunc _redraw(", force_start)
	var force_block := source.substr(force_start, force_end - force_start)
	var retire_index := force_block.find("retire_active(expected_token)")
	var complete_index := force_block.find("_complete_handle_action(true)")
	assert_gte(retire_index, 0)
	assert_gt(
		complete_index, retire_index, "The old identity must be retired before ownership ends"
	)

	var commit_start := source.find("func _commit_handle(")
	var commit_end := source.find("\n\n## Complete a live resize", commit_start)
	var commit_block := source.substr(commit_start, commit_end - commit_start)
	var classify_index := commit_block.find("classify_commit(")
	var transaction_index := commit_block.find("apply_resize_transaction")
	assert_gte(classify_index, 0)
	assert_lt(classify_index, transaction_index, "A callback must be identified before mutation")
	assert_true(commit_block.contains("consume_retired("))
	assert_true(commit_block.contains("cancel or _handle_action_frozen"))
	assert_true(commit_block.contains("_finish_handle_action(effective_cancel, expected_token)"))
	assert_false(source.contains("_suppress_late_handle_commit"))

	var value_block := _source_function_block(source, "func _get_handle_value(")
	assert_true(value_block.contains("decorate_restore("))


func test_geometry_and_preview_rebuilds_queue_one_deferred_gizmo_refresh() -> void:
	var brush_source := (
		FileAccess
		. get_file_as_string("res://addons/hammerforge/brush_instance.gd")
		. replace("\r\n", "\n")
	)
	assert_true(brush_source.contains("@export var faces: Array[FaceData] = []:"))
	var faces_setter_start := brush_source.find("@export var faces: Array[FaceData] = []:")
	var faces_setter_end := brush_source.find("\n\nvar editor_material", faces_setter_start)
	assert_true(
		brush_source.substr(faces_setter_start, faces_setter_end - faces_setter_start).contains(
			"_queue_gizmo_update()"
		)
	)
	for signature in [
		"func set_shape(", "func set_size(", "func set_sides(", "func rebuild_preview("
	]:
		assert_true(
			_source_function_block(brush_source, signature).contains("_queue_gizmo_update()"),
			"%s should invalidate native gizmos" % signature,
		)
	assert_true(
		_source_function_block(brush_source, "func apply_serialized_faces(").contains(
			"rebuild_preview()"
		)
	)
	var brush_queue := _source_function_block(brush_source, "func _queue_gizmo_update(")
	assert_true(brush_queue.contains("_gizmo_update_queued"))
	assert_true(brush_queue.contains('call_deferred("_flush_gizmo_update")'))
	assert_true(
		_source_function_block(brush_source, "func _flush_gizmo_update(").contains(
			"update_gizmos()"
		)
	)
	assert_true(
		_source_function_block(brush_source, "func _flush_gizmo_update(").contains(
			"if not _gizmo_update_queued:"
		),
		"An immediate handle redraw should make its pending deferred callback a no-op",
	)

	var entity_source := (
		FileAccess
		. get_file_as_string("res://addons/hammerforge/draft_entity.gd")
		. replace("\r\n", "\n")
	)
	for signature in ["func _update_preview(", "func _assign_preview(", "func _clear_preview("]:
		assert_true(
			_source_function_block(entity_source, signature).contains("_queue_gizmo_update()"),
			"%s should invalidate entity outline and collision" % signature,
		)
	assert_true(
		_source_function_block(entity_source, "func _queue_gizmo_update(").contains(
			'call_deferred("_flush_gizmo_update")'
		)
	)
	assert_true(
		_source_function_block(entity_source, "func _flush_gizmo_update(").contains(
			"update_gizmos()"
		)
	)

	var gizmo_source := (
		FileAccess
		. get_file_as_string("res://addons/hammerforge/brush_gizmo_plugin.gd")
		. replace("\r\n", "\n")
	)
	assert_true(
		_source_function_block(gizmo_source, "func _request_gizmo_redraw(").contains(
			"_refresh_editor_gizmo_now"
		),
		"Immediate drag feedback should consume a queued deferred redraw",
	)


func test_resize_noop_creates_no_transaction_or_dirty_tag() -> void:
	var fixture := _make_resize_fixture()
	var root: ResizeTransactionRoot = fixture.root
	var brush: DraftBrush = fixture.brush
	var original_uv_scale := brush.faces[0].uv_scale
	var original_uv_offset := brush.faces[0].uv_offset
	var restore := {"size": brush.size, "position": brush.global_position}

	assert_false(BrushGizmoPlugin.apply_resize_transaction(brush, restore, false, null, root))
	assert_eq(root.transform_call_count, 0)
	assert_true(root.dirty_brush_ids.is_empty())
	assert_eq(brush.faces[0].uv_scale, original_uv_scale)
	assert_eq(brush.faces[0].uv_offset, original_uv_offset)


func test_resize_cancel_restores_preview_without_touching_texture_lock() -> void:
	var fixture := _make_resize_fixture()
	var root: ResizeTransactionRoot = fixture.root
	var brush: DraftBrush = fixture.brush
	var previous_size := brush.size
	var previous_position := brush.global_position
	var original_uv_scale := brush.faces[0].uv_scale
	var original_uv_offset := brush.faces[0].uv_offset
	var restore := {"size": previous_size, "position": previous_position}

	brush.size = Vector3(64, 32, 32)
	brush.global_position = Vector3(16, 0, 0)
	assert_false(BrushGizmoPlugin.apply_resize_transaction(brush, restore, true, null, root))
	assert_eq(brush.size, previous_size)
	assert_eq(brush.global_position, previous_position)
	assert_eq(root.transform_call_count, 0)
	assert_true(root.dirty_brush_ids.is_empty())
	assert_eq(brush.faces[0].uv_scale, original_uv_scale)
	assert_eq(brush.faces[0].uv_offset, original_uv_offset)


func test_resize_commit_replays_original_to_final_for_one_texture_lock_adjustment() -> void:
	var fixture := _make_resize_fixture()
	var root: ResizeTransactionRoot = fixture.root
	var brush: DraftBrush = fixture.brush
	var previous_size := brush.size
	var previous_position := brush.global_position
	var original_uv_scale := brush.faces[0].uv_scale
	var original_uv_offset := brush.faces[0].uv_offset
	var final_size := Vector3(64, 32, 32)
	var final_position := Vector3(16, 0, 0)

	# Match _set_handle(): preview changes geometry only and leaves UVs alone.
	brush.size = final_size
	brush.global_position = final_position
	assert_eq(brush.faces[0].uv_scale, original_uv_scale)
	assert_eq(brush.faces[0].uv_offset, original_uv_offset)

	assert_true(
		(
			BrushGizmoPlugin
			. apply_resize_transaction(
				brush,
				{"size": previous_size, "position": previous_position},
				false,
				null,
				root,
			)
		)
	)
	assert_eq(brush.size, final_size)
	assert_eq(brush.global_position, final_position)
	assert_eq(root.transform_call_count, 1)
	assert_true(root.dirty_brush_ids.has(brush.brush_id))
	# PLANAR_Y maps world X/Z. Doubling X size halves U scale, while
	# moving the center +16 subtracts 16 * the original U scale once.
	assert_eq(brush.faces[0].uv_scale, Vector2(original_uv_scale.x * 0.5, original_uv_scale.y))
	assert_eq(
		brush.faces[0].uv_offset,
		Vector2(original_uv_offset.x - 16.0 * original_uv_scale.x, original_uv_offset.y),
	)


func _make_resize_fixture() -> Dictionary:
	var root := ResizeTransactionRoot.new()
	add_child_autoqfree(root)

	var brush := DraftBrush.new()
	brush.brush_id = "gizmo_resize_test"
	brush.set_meta("brush_id", brush.brush_id)
	brush.size = Vector3(32, 32, 32)
	brush.position = Vector3.ZERO
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[
			Vector3(-16, 0, -16),
			Vector3(16, 0, -16),
			Vector3(16, 0, 16),
			Vector3(-16, 0, 16),
		]
	)
	face.uv_projection = FaceData.UVProjection.PLANAR_Y
	face.uv_scale = Vector2(2, 3)
	face.uv_offset = Vector2(5, 7)
	face.ensure_geometry()
	brush.faces = [face]
	root.draft_brushes_node.add_child(brush)
	root.dirty_brush_ids.clear()
	return {"root": root, "brush": brush}


func _make_builtin_shape_brush(shape: int, size: Vector3, sides: int = 4) -> DraftBrush:
	var brush := DraftBrush.new()
	autofree(brush)
	brush.shape = shape
	brush.size = size
	brush.sides = sides
	var build: Dictionary = brush._build_base_mesh()
	var mesh: Mesh = build.get("mesh", null)
	var mesh_scale: Vector3 = build.get("scale", Vector3.ONE)
	brush.faces = brush._faces_from_mesh(mesh, mesh_scale)
	return brush


func _make_face(vertices: Array) -> FaceData:
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(vertices)
	face.ensure_geometry()
	return face


func _make_box_faces() -> Array[FaceData]:
	var corners := [
		Vector3(-1, -1, -1),
		Vector3(1, -1, -1),
		Vector3(1, 1, -1),
		Vector3(-1, 1, -1),
		Vector3(-1, -1, 1),
		Vector3(1, -1, 1),
		Vector3(1, 1, 1),
		Vector3(-1, 1, 1),
	]
	var indices := [
		[0, 1, 2, 3],
		[4, 7, 6, 5],
		[0, 4, 5, 1],
		[1, 5, 6, 2],
		[2, 6, 7, 3],
		[3, 7, 4, 0],
	]
	var faces: Array[FaceData] = []
	for face_indices in indices:
		var face := FaceData.new()
		var vertices := PackedVector3Array()
		for index in face_indices:
			vertices.append(corners[index])
		face.local_verts = vertices
		faces.append(face)
	return faces


func _has_segment(lines: PackedVector3Array, expected_a: Vector3, expected_b: Vector3) -> bool:
	for index in range(0, lines.size(), 2):
		var actual_a := lines[index]
		var actual_b := lines[index + 1]
		if (
			(actual_a.is_equal_approx(expected_a) and actual_b.is_equal_approx(expected_b))
			or (actual_a.is_equal_approx(expected_b) and actual_b.is_equal_approx(expected_a))
		):
			return true
	return false


func _points_aabb(points: PackedVector3Array) -> AABB:
	assert_false(points.is_empty())
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func _contains_approx_point(points: PackedVector3Array, expected: Vector3) -> bool:
	for point in points:
		if point.is_equal_approx(expected):
			return true
	return false


func _source_function_block(source: String, signature: String) -> String:
	var start := source.find(signature)
	assert_gte(start, 0, "Missing source function: %s" % signature)
	if start < 0:
		return ""
	var finish := source.find("\n\nfunc ", start + signature.length())
	if finish < 0:
		finish = source.length()
	return source.substr(start, finish - start)


func _assert_vector_near(actual: Vector3, expected: Vector3, tolerance: float = 0.0001) -> void:
	assert_almost_eq(actual.x, expected.x, tolerance)
	assert_almost_eq(actual.y, expected.y, tolerance)
	assert_almost_eq(actual.z, expected.z, tolerance)


func _assert_valid_lines(lines: PackedVector3Array) -> void:
	assert_eq(lines.size() % 2, 0)
	for index in range(0, lines.size(), 2):
		assert_true(lines[index].is_finite())
		assert_true(lines[index + 1].is_finite())
		assert_false(lines[index].is_equal_approx(lines[index + 1]))
