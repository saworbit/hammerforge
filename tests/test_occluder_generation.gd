extends GutTest

const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFValidationSystem = preload("res://addons/hammerforge/systems/hf_validation_system.gd")

var root: Node3D
var bake_sys: HFBakeSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	var pending = Node3D.new()
	pending.name = "Pending"
	root.add_child(pending)
	root.pending_node = pending
	var committed = Node3D.new()
	committed.name = "Committed"
	root.add_child(committed)
	root.committed_node = committed
	var gen_floors = Node3D.new()
	gen_floors.name = "GeneratedFloors"
	root.add_child(gen_floors)
	root.generated_floors = gen_floors
	var gen_walls = Node3D.new()
	gen_walls.name = "GeneratedWalls"
	root.add_child(gen_walls)
	root.generated_walls = gen_walls
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	root.bake_generate_occluders = true
	bake_sys = HFBakeSystem.new(root)


func after_each():
	root = null
	bake_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text, level)
signal bake_started()
signal bake_progress(progress, message)
signal bake_finished(success)

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var generated_floors: Node3D
var generated_walls: Node3D
var generated_heightmap_floors: Node3D
var entities_node: Node3D
var baked_container: Node3D
var bake_generate_occluders: bool = true
var bake_occluder_min_area: float = 4.0
var bake_auto_connectors: bool = false
var bake_navmesh: bool = false
var bake_wire_io: bool = false

var _log_messages: Array = []

func _assign_owner_recursive(node: Node) -> void:
	pass

func _log(msg: String) -> void:
	_log_messages.append(msg)
"""
	s.reload()
	return s


func _make_quad_mesh(size: Vector2 = Vector2(10, 10), normal: Vector3 = Vector3.UP) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts = PackedVector3Array()
	var normals_arr = PackedVector3Array()
	var indices = PackedInt32Array()
	# Build a quad on the plane defined by the normal.
	var tangent: Vector3
	var bitangent: Vector3
	if abs(normal.dot(Vector3.UP)) < 0.99:
		tangent = normal.cross(Vector3.UP).normalized()
	else:
		tangent = normal.cross(Vector3.FORWARD).normalized()
	bitangent = tangent.cross(normal).normalized()
	var half := Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	# Vertices at corners in the plane.
	verts.append(-tangent * half.x - bitangent * half.z)
	verts.append(tangent * half.x - bitangent * half.z)
	verts.append(tangent * half.x + bitangent * half.z)
	verts.append(-tangent * half.x + bitangent * half.z)
	for _i in 4:
		normals_arr.append(normal)
	# Two triangles (CW from outside).
	indices.append(0)
	indices.append(2)
	indices.append(1)
	indices.append(0)
	indices.append(3)
	indices.append(2)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals_arr
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_baked_container_with_mesh(
	mesh: ArrayMesh, xform: Transform3D = Transform3D.IDENTITY
) -> Node3D:
	var container = Node3D.new()
	container.name = "BakedGeometry"
	root.add_child(container)
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	mi.name = "BakedMesh_0"
	container.add_child(mi)
	return container


## Build a baked container that mirrors the chunked bake hierarchy:
## BakedGeometry → BakedChunk_0_0_0 → MeshInstance3D
func _make_chunked_container(meshes: Array, chunk_names: Array = []) -> Node3D:
	var container = Node3D.new()
	container.name = "BakedGeometry"
	root.add_child(container)
	for idx in meshes.size():
		var chunk = Node3D.new()
		var cname: String = (
			chunk_names[idx] if idx < chunk_names.size() else "BakedChunk_%d_0_0" % idx
		)
		chunk.name = cname
		container.add_child(chunk)
		var mi = MeshInstance3D.new()
		mi.mesh = meshes[idx]
		mi.name = "BakedMesh_0"
		chunk.add_child(mi)
	return container


# ---------------------------------------------------------------------------
# Tests: _generate_occluders
# ---------------------------------------------------------------------------


func test_generate_occluders_creates_nodes():
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders, "Occluders container should be created")
	assert_gt(occluders.get_child_count(), 0, "Should have at least one occluder")
	var inst = occluders.get_child(0) as OccluderInstance3D
	assert_not_null(inst, "Child should be OccluderInstance3D")
	assert_not_null(inst.occluder, "Occluder resource should be set")


func test_generate_occluders_skips_small_surfaces():
	var mesh = _make_quad_mesh(Vector2(1, 1))  # area = 1.0
	var container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 10.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_null(occluders, "No occluders should be created for tiny surfaces")


func test_generate_occluders_idempotent():
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	bake_sys._generate_occluders(container)
	var count := 0
	for child in container.get_children():
		if child.name == "Occluders":
			count += 1
	assert_eq(count, 1, "Re-running should replace, not duplicate Occluders node")


func test_generate_occluders_groups_coplanar_tris():
	# Two quads on the same plane should merge into one occluder group.
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts = PackedVector3Array()
	var normals_arr = PackedVector3Array()
	var indices = PackedInt32Array()
	# Quad 1 at y=0
	verts.append(Vector3(0, 0, 0))
	verts.append(Vector3(5, 0, 0))
	verts.append(Vector3(5, 0, 5))
	verts.append(Vector3(0, 0, 5))
	# Quad 2 at y=0, adjacent
	verts.append(Vector3(5, 0, 0))
	verts.append(Vector3(10, 0, 0))
	verts.append(Vector3(10, 0, 5))
	verts.append(Vector3(5, 0, 5))
	for _i in 8:
		normals_arr.append(Vector3.UP)
	# Quad 1: two tris
	indices.append_array([0, 2, 1, 0, 3, 2])
	# Quad 2: two tris
	indices.append_array([4, 6, 5, 4, 7, 6])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals_arr
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders)
	# Both quads on the same plane → should merge into 1 occluder.
	assert_eq(occluders.get_child_count(), 1, "Coplanar quads should merge into one occluder")


func test_generate_occluders_separates_different_planes():
	# Two quads on different planes → two occluders.
	var mesh1 = _make_quad_mesh(Vector2(5, 5), Vector3.UP)
	var mesh2 = _make_quad_mesh(Vector2(5, 5), Vector3.LEFT)
	var container = Node3D.new()
	container.name = "BakedGeometry"
	root.add_child(container)
	var mi1 = MeshInstance3D.new()
	mi1.mesh = mesh1
	mi1.name = "BakedMesh_0"
	container.add_child(mi1)
	var mi2 = MeshInstance3D.new()
	mi2.mesh = mesh2
	mi2.name = "BakedMesh_1"
	mi2.transform.origin = Vector3(0, 5, 0)
	container.add_child(mi2)
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders)
	assert_gte(occluders.get_child_count(), 2, "Different planes should produce separate occluders")


# ---------------------------------------------------------------------------
# Tests: postprocess_bake integration
# ---------------------------------------------------------------------------


func test_postprocess_skips_occluders_when_disabled():
	root.bake_generate_occluders = false
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 1.0
	bake_sys.postprocess_bake(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_null(occluders, "No occluders when disabled")


func test_postprocess_generates_occluders_when_enabled():
	root.bake_generate_occluders = true
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 1.0
	bake_sys.postprocess_bake(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders, "Occluders should be created when enabled")


# ---------------------------------------------------------------------------
# Tests: validation
# ---------------------------------------------------------------------------


func test_validation_reports_missing_occluders():
	root.bake_generate_occluders = true
	# Create a baked container with a mesh but no occluders.
	var mesh = _make_quad_mesh(Vector2(10, 10))
	root.baked_container = _make_baked_container_with_mesh(mesh)
	root.bake_occluder_min_area = 10000.0  # too high → no occluders
	var val_sys = HFValidationSystem.new(root)
	var issues = val_sys.check_occlusion_coverage()
	var found := false
	for issue in issues:
		if issue["type"] == "OcclusionMissing":
			found = true
	assert_true(found, "Should warn when occluder generation produced nothing")


func test_validation_reports_coverage():
	root.bake_generate_occluders = true
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_baked_container_with_mesh(mesh)
	root.baked_container = container
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var val_sys = HFValidationSystem.new(root)
	var issues = val_sys.check_occlusion_coverage()
	var found := false
	for issue in issues:
		if issue["type"] == "OcclusionCoverage":
			found = true
	assert_true(found, "Should report coverage info when occluders exist")


# ---------------------------------------------------------------------------
# Tests: chunked bake hierarchy (BakedChunk_* intermediary nodes)
# ---------------------------------------------------------------------------


func test_generate_occluders_finds_meshes_in_chunks():
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_chunked_container([mesh], ["BakedChunk_0_0_0"])
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders, "Should find meshes inside BakedChunk_* nodes")
	assert_gt(occluders.get_child_count(), 0, "Should create occluders from chunked meshes")


func test_generate_occluders_multiple_chunks():
	var mesh1 = _make_quad_mesh(Vector2(8, 8), Vector3.UP)
	var mesh2 = _make_quad_mesh(Vector2(8, 8), Vector3.LEFT)
	var container = _make_chunked_container(
		[mesh1, mesh2], ["BakedChunk_0_0_0", "BakedChunk_1_0_0"]
	)
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders)
	assert_gte(
		occluders.get_child_count(),
		2,
		"Meshes in separate chunks on different planes should produce separate occluders"
	)


func test_generate_occluders_coplanar_across_chunks():
	# Two chunks, both containing a floor quad at y=0 → should merge into one occluder.
	var mesh1 = _make_quad_mesh(Vector2(5, 5), Vector3.UP)
	var mesh2 = _make_quad_mesh(Vector2(5, 5), Vector3.UP)
	var container = _make_chunked_container(
		[mesh1, mesh2], ["BakedChunk_0_0_0", "BakedChunk_1_0_0"]
	)
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var occluders = container.find_child("Occluders", false, false)
	assert_not_null(occluders)
	assert_eq(
		occluders.get_child_count(),
		1,
		"Coplanar faces across chunks should merge into one occluder"
	)


func test_validation_coverage_with_chunked_container():
	root.bake_generate_occluders = true
	var mesh = _make_quad_mesh(Vector2(10, 10))
	var container = _make_chunked_container([mesh], ["BakedChunk_0_0_0"])
	root.baked_container = container
	root.bake_occluder_min_area = 1.0
	bake_sys._generate_occluders(container)
	var val_sys = HFValidationSystem.new(root)
	var issues = val_sys.check_occlusion_coverage()
	var found := false
	for issue in issues:
		if issue["type"] == "OcclusionCoverage":
			found = true
	assert_true(found, "Validation should find meshes in chunked hierarchy")
