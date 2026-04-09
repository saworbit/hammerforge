extends GutTest

const BakerScript = preload("res://addons/hammerforge/baker.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const MatMgrScript = preload("res://addons/hammerforge/material_manager.gd")

var baker: BakerScript


func before_each():
	baker = BakerScript.new()
	add_child_autoqfree(baker)


# ===========================================================================
# _merge_entries_worker: per-surface material preservation
# ===========================================================================


func _make_colored_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _make_simple_mesh(mat: Material = null) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0, 0, 0))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(1, 0, 0))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0, 0, 1))
	var mesh = st.commit()
	if mat and mesh:
		mesh.surface_set_material(0, mat)
	return mesh


func test_merge_preserves_single_material():
	var mat_red = _make_colored_material(Color.RED)
	var mesh = _make_simple_mesh(mat_red)
	var entries = [{"mesh": mesh, "transform": Transform3D.IDENTITY}]
	var merged = baker._merge_entries_worker(entries)
	assert_not_null(merged, "Merged mesh should not be null")
	assert_eq(merged.get_surface_count(), 1)
	var result_mat = merged.surface_get_material(0)
	assert_not_null(result_mat, "Material should be preserved on merged surface")
	assert_eq(
		(result_mat as StandardMaterial3D).albedo_color,
		Color.RED,
		"Material color should match"
	)


func test_merge_groups_by_material():
	var mat_a = _make_colored_material(Color.RED)
	var mat_b = _make_colored_material(Color.BLUE)
	var mesh_a1 = _make_simple_mesh(mat_a)
	var mesh_a2 = _make_simple_mesh(mat_a)
	var mesh_b = _make_simple_mesh(mat_b)
	var entries = [
		{"mesh": mesh_a1, "transform": Transform3D.IDENTITY},
		{"mesh": mesh_a2, "transform": Transform3D.IDENTITY},
		{"mesh": mesh_b, "transform": Transform3D.IDENTITY},
	]
	var merged = baker._merge_entries_worker(entries)
	assert_not_null(merged)
	assert_eq(merged.get_surface_count(), 2, "Two distinct materials = two surfaces")


func test_merge_null_material_grouped_separately():
	var mat = _make_colored_material(Color.GREEN)
	var mesh_with = _make_simple_mesh(mat)
	var mesh_without = _make_simple_mesh(null)
	var entries = [
		{"mesh": mesh_with, "transform": Transform3D.IDENTITY},
		{"mesh": mesh_without, "transform": Transform3D.IDENTITY},
	]
	var merged = baker._merge_entries_worker(entries)
	assert_not_null(merged)
	assert_eq(merged.get_surface_count(), 2, "Null and non-null materials are separate surfaces")


func test_merge_applies_transform():
	var mesh = _make_simple_mesh()
	var xform = Transform3D.IDENTITY.translated(Vector3(10, 0, 0))
	var entries = [{"mesh": mesh, "transform": xform}]
	var merged = baker._merge_entries_worker(entries)
	assert_not_null(merged)
	var arrays = merged.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Original verts are (0,0,0), (1,0,0), (0,0,1) — all should be offset by +10 in X
	for v in verts:
		assert_gte(v.x, 9.99, "Vertices should be translated by +10 in X")


# ===========================================================================
# bake_from_faces: single mesh with per-surface materials
# ===========================================================================


func _make_face(norm: Vector3 = Vector3.UP, mat_idx: int = 0) -> FaceData:
	var face = FaceData.new()
	face.normal = norm
	face.material_idx = mat_idx
	face.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1)
	])
	return face


func _make_brush_with_faces(
	parent: Node3D, face_list: Array, mat_override: Material = null
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = Vector3(4, 4, 4)
	if mat_override:
		b.material_override = mat_override
	parent.add_child(b)
	b.global_position = Vector3.ZERO
	# Overwrite faces after add_child (which triggers _rebuild_faces via
	# geometry_dirty=true). Set geometry_dirty=false to prevent re-overwrite.
	var typed: Array[FaceData] = []
	for f in face_list:
		typed.append(f)
	b.faces = typed
	b.geometry_dirty = false
	return b


func test_bake_from_faces_single_material_single_surface():
	var mat_mgr = MaterialManager.new()
	add_child_autoqfree(mat_mgr)
	var mat = _make_colored_material(Color.RED)
	mat_mgr.add_material(mat)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face = _make_face(Vector3.UP, 0)
	var brush = _make_brush_with_faces(parent, [face])

	var result = baker.bake_from_faces([brush], mat_mgr)
	assert_not_null(result, "Should produce baked geometry")
	add_child_autoqfree(result)

	# Should have a single MeshInstance3D child (plus the StaticBody)
	var mesh_instances := []
	for child in result.get_children():
		if child is MeshInstance3D:
			mesh_instances.append(child)
	assert_eq(mesh_instances.size(), 1, "Should produce exactly one MeshInstance3D")
	if mesh_instances.size() > 0:
		var mesh: Mesh = mesh_instances[0].mesh
		assert_eq(mesh.get_surface_count(), 1)
		var surface_mat = mesh.surface_get_material(0)
		assert_not_null(surface_mat, "Surface should have material assigned")


func test_bake_from_faces_multiple_materials_multiple_surfaces():
	var mat_mgr = MaterialManager.new()
	add_child_autoqfree(mat_mgr)
	var mat_a = _make_colored_material(Color.RED)
	var mat_b = _make_colored_material(Color.BLUE)
	mat_mgr.add_material(mat_a)
	mat_mgr.add_material(mat_b)

	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face_a = _make_face(Vector3.UP, 0)
	var face_b = _make_face(Vector3.DOWN, 1)
	var brush = _make_brush_with_faces(parent, [face_a, face_b])

	var result = baker.bake_from_faces([brush], mat_mgr)
	assert_not_null(result)
	add_child_autoqfree(result)

	var mesh_instances := []
	for child in result.get_children():
		if child is MeshInstance3D:
			mesh_instances.append(child)
	assert_eq(mesh_instances.size(), 1, "Should produce exactly one MeshInstance3D")
	if mesh_instances.size() > 0:
		var mesh: Mesh = mesh_instances[0].mesh
		assert_eq(
			mesh.get_surface_count(), 2,
			"Two different materials should produce two surfaces on single mesh"
		)
		# Both surfaces should have materials
		assert_not_null(mesh.surface_get_material(0))
		assert_not_null(mesh.surface_get_material(1))


# ===========================================================================
# _concat_surface_arrays
# ===========================================================================


func test_concat_surface_arrays_single():
	var mesh = _make_simple_mesh()
	var arrays = mesh.surface_get_arrays(0)
	var result = baker._concat_surface_arrays([arrays])
	assert_eq(
		(result[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		3,
		"Single entry should pass through unchanged"
	)


func test_concat_surface_arrays_two():
	var mesh_a = _make_simple_mesh()
	var mesh_b = _make_simple_mesh()
	var arrays_a = mesh_a.surface_get_arrays(0)
	var arrays_b = mesh_b.surface_get_arrays(0)
	var result = baker._concat_surface_arrays([arrays_a, arrays_b])
	assert_eq(
		(result[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		6,
		"Two 3-vert entries should concatenate to 6 verts"
	)


func test_concat_surface_arrays_empty():
	var result = baker._concat_surface_arrays([])
	assert_eq(result.size(), 0, "Empty input should return empty array")


# ===========================================================================
# _concat_surface_arrays: mixed indexed / non-indexed merging
# ===========================================================================


func _make_indexed_arrays(offset: Vector3 = Vector3.ZERO) -> Array:
	## Build a surface arrays Array with explicit ARRAY_INDEX.
	var verts := PackedVector3Array([
		Vector3(0, 0, 0) + offset,
		Vector3(1, 0, 0) + offset,
		Vector3(0, 0, 1) + offset,
		Vector3(1, 0, 1) + offset,
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 1, 2, 2, 1, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _make_non_indexed_arrays(offset: Vector3 = Vector3.ZERO) -> Array:
	## Build a surface arrays Array without ARRAY_INDEX (null).
	var verts := PackedVector3Array([
		Vector3(0, 0, 0) + offset,
		Vector3(1, 0, 0) + offset,
		Vector3(0, 0, 1) + offset,
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	# ARRAY_INDEX is null by default
	return arrays


func test_concat_indexed_rebases_second_surface():
	var a = _make_indexed_arrays()
	var b = _make_indexed_arrays(Vector3(10, 0, 0))
	var result = baker._concat_surface_arrays([a, b])
	var verts: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = result[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), 8, "4+4 verts merged")
	assert_eq(indices.size(), 12, "6+6 indices merged")
	# Second surface indices should be rebased by 4 (first surface vertex count)
	for i in range(6, 12):
		assert_gte(indices[i], 4, "Rebased index should be >= 4 (first surface vert count)")
	# Verify indices point at valid vertices
	for idx in indices:
		assert_lt(idx, verts.size(), "Index should be within merged vertex range")


func test_concat_nonindexed_first_indexed_second():
	## First surface is non-indexed (null ARRAY_INDEX), second has indices.
	## The merge should synthesize sequential indices for the first surface.
	var a = _make_non_indexed_arrays()
	var b = _make_indexed_arrays(Vector3(10, 0, 0))
	var result = baker._concat_surface_arrays([a, b])
	var verts: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = result[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), 7, "3 non-indexed + 4 indexed = 7 verts")
	assert_not_null(indices, "Should produce an index buffer even though first had none")
	# First 3 indices should be synthesized sequential: 0, 1, 2
	assert_eq(indices[0], 0)
	assert_eq(indices[1], 1)
	assert_eq(indices[2], 2)
	# Remaining indices should be rebased by 3 (first surface has 3 verts)
	for i in range(3, indices.size()):
		assert_gte(indices[i], 3, "Second surface indices should be rebased by 3")
	for idx in indices:
		assert_lt(idx, verts.size(), "All indices in valid range")


func test_concat_indexed_first_nonindexed_second():
	## First surface has indices, second is non-indexed.
	## The merge should synthesize sequential indices for the second surface.
	var a = _make_indexed_arrays()
	var b = _make_non_indexed_arrays(Vector3(10, 0, 0))
	var result = baker._concat_surface_arrays([a, b])
	var verts: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = result[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), 7, "4 indexed + 3 non-indexed = 7 verts")
	# First 6 indices from the indexed surface (original 0,1,2,2,1,3)
	assert_eq(indices[0], 0)
	assert_eq(indices[1], 1)
	assert_eq(indices[2], 2)
	# Synthesized indices for the second surface should be 4, 5, 6 (rebased by 4)
	assert_eq(indices[6], 4)
	assert_eq(indices[7], 5)
	assert_eq(indices[8], 6)
	for idx in indices:
		assert_lt(idx, verts.size(), "All indices in valid range")


func test_concat_both_nonindexed_stays_nonindexed():
	## When both surfaces are non-indexed, output should also have no index buffer.
	var a = _make_non_indexed_arrays()
	var b = _make_non_indexed_arrays(Vector3(10, 0, 0))
	var result = baker._concat_surface_arrays([a, b])
	var verts: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 6, "3+3 = 6 verts merged")
	assert_null(result[Mesh.ARRAY_INDEX], "Both non-indexed → output should have no indices")


# ===========================================================================
# build_convex_collision_shapes
# ===========================================================================


func _make_box_verts(center: Vector3 = Vector3.ZERO, half: float = 1.0) -> PackedVector3Array:
	return PackedVector3Array([
		center + Vector3(-half, -half, -half),
		center + Vector3( half, -half, -half),
		center + Vector3( half,  half, -half),
		center + Vector3(-half,  half, -half),
		center + Vector3(-half, -half,  half),
		center + Vector3( half, -half,  half),
		center + Vector3( half,  half,  half),
		center + Vector3(-half,  half,  half),
	])


func test_convex_shapes_single_brush():
	var verts = _make_box_verts()
	var shapes: Array = Baker.build_convex_collision_shapes([verts])
	assert_eq(shapes.size(), 1, "One brush → one convex shape")
	assert_true(shapes[0] is ConvexPolygonShape3D, "Shape should be ConvexPolygonShape3D")
	assert_gte(
		(shapes[0] as ConvexPolygonShape3D).points.size(), 4,
		"Convex hull should have at least 4 points"
	)


func test_convex_shapes_multiple_brushes():
	var verts_a = _make_box_verts(Vector3.ZERO)
	var verts_b = _make_box_verts(Vector3(10, 0, 0))
	var shapes: Array = Baker.build_convex_collision_shapes([verts_a, verts_b])
	assert_eq(shapes.size(), 2, "Two brushes → two convex shapes")


func test_convex_shapes_skip_degenerate():
	# Fewer than 4 unique verts should be skipped
	var flat := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var shapes: Array = Baker.build_convex_collision_shapes([flat])
	assert_eq(shapes.size(), 0, "Degenerate brush with <4 verts should be skipped")


func test_convex_shapes_dedup_vertices():
	# Duplicate vertices should be collapsed
	var verts := PackedVector3Array()
	for i in range(20):
		verts.append(Vector3.ZERO)
	var shapes: Array = Baker.build_convex_collision_shapes([verts])
	assert_eq(shapes.size(), 0, "All-duplicate verts collapse to 1 unique → skipped")


func test_convex_shapes_degenerate_rejected_even_without_clean():
	# convex_clean=false must still reject fully-degenerate input
	var verts := PackedVector3Array()
	for i in range(20):
		verts.append(Vector3.ZERO)
	var shapes: Array = Baker.build_convex_collision_shapes([verts], false, 0.0)
	assert_eq(shapes.size(), 0, "Degenerate input rejected even with convex_clean=false")


func test_convex_shapes_empty_input():
	var shapes: Array = Baker.build_convex_collision_shapes([])
	assert_eq(shapes.size(), 0, "Empty input → no shapes")


# ===========================================================================
# build_mesh_from_groups: collision_mode option
# ===========================================================================


func test_build_mesh_from_groups_trimesh_default():
	var mat_mgr = MaterialManager.new()
	add_child_autoqfree(mat_mgr)
	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face = _make_face(Vector3.UP, 0)
	var brush = _make_brush_with_faces(parent, [face])
	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {})
	assert_not_null(result)
	add_child_autoqfree(result)
	var body: StaticBody3D = result.get_node_or_null("FaceCollision")
	assert_not_null(body, "Should have FaceCollision body")
	var shape_count := 0
	for child in body.get_children():
		if child is CollisionShape3D:
			assert_true(
				child.shape is ConcavePolygonShape3D,
				"Default mode should use ConcavePolygonShape3D"
			)
			shape_count += 1
	assert_eq(shape_count, 1, "Trimesh mode should produce exactly 1 collision shape")


func test_bake_from_faces_convex_mode():
	# Exercise the public bake_from_faces() API with collision_mode=1.
	# bake_from_faces should auto-collect per-brush hull verts internally.
	var mat_mgr = MaterialManager.new()
	add_child_autoqfree(mat_mgr)
	var parent = Node3D.new()
	add_child_autoqfree(parent)
	# Use box verts so the brush has enough geometry for a valid convex hull
	var face_top = _make_face(Vector3.UP, 0)
	var face_bot = _make_face(Vector3.DOWN, 0)
	face_bot.local_verts = PackedVector3Array([
		Vector3(0, -2, 0), Vector3(1, -2, 0),
		Vector3(1, -2, 1), Vector3(0, -2, 1)
	])
	var face_front = _make_face(Vector3.FORWARD, 0)
	face_front.local_verts = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, -2, 0), Vector3(0, -2, 0)
	])
	var face_back = _make_face(Vector3.BACK, 0)
	face_back.local_verts = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(1, 0, 1),
		Vector3(1, -2, 1), Vector3(0, -2, 1)
	])
	var brush = _make_brush_with_faces(parent, [face_top, face_bot, face_front, face_back])
	var options: Dictionary = {"collision_mode": 1}
	var result = baker.bake_from_faces([brush], mat_mgr, null, 1, 1, options)
	assert_not_null(result, "bake_from_faces with collision_mode=1 should produce result")
	add_child_autoqfree(result)
	var body: StaticBody3D = result.get_node_or_null("FaceCollision")
	assert_not_null(body, "Should have FaceCollision body")
	var has_convex := false
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			has_convex = true
	assert_true(has_convex, "bake_from_faces collision_mode=1 should produce ConvexPolygonShape3D")


# ===========================================================================
# snapshot_brush_faces: hull_verts field
# ===========================================================================


func test_snapshot_includes_hull_verts():
	var mat_mgr = MaterialManager.new()
	add_child_autoqfree(mat_mgr)
	var parent = Node3D.new()
	add_child_autoqfree(parent)
	var face = _make_face(Vector3.UP, 0)
	var brush = _make_brush_with_faces(parent, [face])
	var snap = baker.snapshot_brush_faces(brush, mat_mgr, null, false)
	assert_true(snap.has("hull_verts"), "Snapshot should include hull_verts key")
	var hull: PackedVector3Array = snap["hull_verts"]
	assert_gt(hull.size(), 0, "hull_verts should contain vertices")


# ===========================================================================
# convex_clean and convex_simplify parameters
# ===========================================================================


func test_convex_clean_false_keeps_duplicates():
	# With convex_clean=false, duplicate vertices are kept in the shape
	var verts := PackedVector3Array()
	for _i in range(3):
		verts.append_array(_make_box_verts())  # 8 verts × 3 = 24 total, many dupes
	var shapes_clean: Array = Baker.build_convex_collision_shapes([verts], true, 0.0)
	var shapes_raw: Array = Baker.build_convex_collision_shapes([verts], false, 0.0)
	assert_eq(shapes_clean.size(), 1)
	assert_eq(shapes_raw.size(), 1)
	var clean_pts: int = (shapes_clean[0] as ConvexPolygonShape3D).points.size()
	var raw_pts: int = (shapes_raw[0] as ConvexPolygonShape3D).points.size()
	assert_lt(clean_pts, raw_pts, "convex_clean=true should produce fewer points than false")


func test_convex_simplify_reduces_points():
	# Build a dense point cloud around a box — simplify should reduce it
	var dense := PackedVector3Array()
	for x in range(10):
		for y in range(10):
			for z in range(10):
				dense.append(Vector3(float(x) * 0.1, float(y) * 0.1, float(z) * 0.1))
	var shapes_none: Array = Baker.build_convex_collision_shapes([dense], true, 0.0)
	var shapes_half: Array = Baker.build_convex_collision_shapes([dense], true, 0.5)
	assert_eq(shapes_none.size(), 1)
	assert_eq(shapes_half.size(), 1)
	var pts_none: int = (shapes_none[0] as ConvexPolygonShape3D).points.size()
	var pts_half: int = (shapes_half[0] as ConvexPolygonShape3D).points.size()
	assert_lt(pts_half, pts_none, "convex_simplify=0.5 should produce fewer points than 0.0")
