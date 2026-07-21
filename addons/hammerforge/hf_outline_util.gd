@tool
extends RefCounted
## Builds editor outlines from semantic face boundaries rather than triangulated meshes.
## This keeps selection and hover feedback legible without exposing render topology.

const EDGE_KEY_SCALE := 10000.0
const CURVE_SEGMENTS := 16
const TRIANGLE_AREA_EPSILON_SQUARED := 0.0000000001
const COPLANAR_NORMAL_DOT := 0.9999
const SPRITE_PROXY_MIN_DIAMETER := 0.1
const BOX_EDGE_INDICES := [
	Vector2i(0, 1),
	Vector2i(1, 2),
	Vector2i(2, 3),
	Vector2i(3, 0),
	Vector2i(4, 5),
	Vector2i(5, 6),
	Vector2i(6, 7),
	Vector2i(7, 4),
	Vector2i(0, 4),
	Vector2i(1, 5),
	Vector2i(2, 6),
	Vector2i(3, 7),
]
const BOX_FACE_INDICES := [
	[0, 1, 2, 3],
	[4, 7, 6, 5],
	[0, 4, 5, 1],
	[1, 5, 6, 2],
	[2, 6, 7, 3],
	[3, 7, 4, 0],
]


static func box_lines(size: Vector3 = Vector3.ONE) -> PackedVector3Array:
	var half := size * 0.5
	var corners := PackedVector3Array(
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, -half.y, half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z),
		]
	)
	var lines := PackedVector3Array()
	for edge in BOX_EDGE_INDICES:
		lines.append(corners[edge.x])
		lines.append(corners[edge.y])
	return lines


## Transform the centered unit-box outline onto a mesh-local AABB. Composing
## this after the mesh instance's global transform preserves non-uniform mesh
## scale and offset/custom geometry bounds without rebuilding the line mesh.
static func aabb_box_transform(aabb: AABB) -> Transform3D:
	return Transform3D(Basis.from_scale(aabb.size), aabb.get_center())


static func face_boundary_lines(faces: Array) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var seen_edges: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		var vertices: PackedVector3Array = face.get("local_verts")
		if vertices.size() < 2:
			continue
		for index in range(vertices.size()):
			var from := vertices[index]
			var to := vertices[(index + 1) % vertices.size()]
			if from.is_equal_approx(to):
				continue
			var edge_key := _edge_key(from, to)
			if seen_edges.has(edge_key):
				continue
			seen_edges[edge_key] = true
			lines.append(from)
			lines.append(to)
	return lines


## Return open boundaries and genuine face creases, but not a shared edge
## between coplanar triangles. Generated angular brushes store render triangles
## rather than their original polygons, so this reconstructs the quiet semantic
## wire without exposing fan/quad triangulation.
static func semantic_face_lines(faces: Array) -> PackedVector3Array:
	var edge_data: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		var vertices: PackedVector3Array = face.get("local_verts")
		var normal := _polygon_normal(vertices)
		if vertices.size() < 2 or normal == Vector3.ZERO:
			continue
		for index in range(vertices.size()):
			var from := vertices[index]
			var to := vertices[(index + 1) % vertices.size()]
			if not from.is_finite() or not to.is_finite() or from.is_equal_approx(to):
				continue
			var edge_key := _edge_key(from, to)
			if not edge_data.has(edge_key):
				edge_data[edge_key] = {"from": from, "to": to, "normals": []}
			var normals: Array = edge_data[edge_key]["normals"]
			normals.append(normal)

	var lines := PackedVector3Array()
	for edge in edge_data.values():
		var normals: Array = edge["normals"]
		if normals.size() > 1 and not _normals_have_crease(normals):
			continue
		lines.append(edge["from"])
		lines.append(edge["to"])
	return lines


## Sparse, camera-independent profiles for smooth primitives. These follow the
## same size contract as DraftBrush's Godot primitive meshes while avoiding a
## dense render-triangle cage.
static func cylinder_lines(size: Vector3) -> PackedVector3Array:
	var safe_size := size.abs()
	var radius := maxf(safe_size.x, safe_size.z) * 0.5
	var half_height := safe_size.y * 0.5
	var lines := PackedVector3Array()
	lines.append_array(
		_ellipse_lines(Vector3(0, -half_height, 0), Vector3.RIGHT * radius, Vector3.BACK * radius)
	)
	lines.append_array(
		_ellipse_lines(Vector3(0, half_height, 0), Vector3.RIGHT * radius, Vector3.BACK * radius)
	)
	for radial in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		_append_segment(
			lines,
			radial * radius + Vector3.DOWN * half_height,
			radial * radius + Vector3.UP * half_height,
		)
	return lines


static func cone_lines(size: Vector3) -> PackedVector3Array:
	var safe_size := size.abs()
	var radius := maxf(safe_size.x, safe_size.z) * 0.5
	var half_height := safe_size.y * 0.5
	var base_center := Vector3(0, -half_height, 0)
	var apex := Vector3(0, half_height, 0)
	var lines := _ellipse_lines(base_center, Vector3.RIGHT * radius, Vector3.BACK * radius)
	for radial in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		_append_segment(lines, base_center + radial * radius, apex)
	return lines


static func sphere_lines(size: Vector3) -> PackedVector3Array:
	var safe_size := size.abs()
	var radius := maxf(safe_size.x, safe_size.z) * 0.5
	return ellipsoid_lines(Vector3.ONE * radius * 2.0)


static func ellipsoid_lines(size: Vector3) -> PackedVector3Array:
	var radius := size.abs() * 0.5
	var lines := PackedVector3Array()
	lines.append_array(
		_ellipse_lines(Vector3.ZERO, Vector3.RIGHT * radius.x, Vector3.UP * radius.y)
	)
	lines.append_array(
		_ellipse_lines(Vector3.ZERO, Vector3.RIGHT * radius.x, Vector3.BACK * radius.z)
	)
	lines.append_array(_ellipse_lines(Vector3.ZERO, Vector3.UP * radius.y, Vector3.BACK * radius.z))
	return lines


static func capsule_lines(size: Vector3) -> PackedVector3Array:
	var safe_size := size.abs()
	var total_height := maxf(0.1, safe_size.y)
	# CapsuleMesh keeps total height >= its diameter. HammerForge assigns height
	# after radius, so a short/wide request reduces the effective radius.
	var radius := minf(maxf(safe_size.x, safe_size.z) * 0.5, total_height * 0.5)
	var straight_half := total_height * 0.5 - radius
	var lines := PackedVector3Array()
	lines.append_array(_ellipse_lines(Vector3.ZERO, Vector3.RIGHT * radius, Vector3.BACK * radius))
	lines.append_array(_capsule_profile_lines(Vector3.RIGHT, radius, straight_half))
	lines.append_array(_capsule_profile_lines(Vector3.BACK, radius, straight_half))
	return lines


static func torus_lines(size: Vector3) -> PackedVector3Array:
	var safe_size := size.abs()
	var outer_x := safe_size.x * 0.5
	var outer_z := safe_size.z * 0.5
	var inner_x := safe_size.x * 0.25
	var inner_z := safe_size.z * 0.25
	var major_x := safe_size.x * 0.375
	var major_z := safe_size.z * 0.375
	var tube_x := safe_size.x * 0.125
	var tube_z := safe_size.z * 0.125
	var tube_y := safe_size.y * 0.5
	var lines := PackedVector3Array()
	lines.append_array(
		_ellipse_lines(Vector3.ZERO, Vector3.RIGHT * outer_x, Vector3.BACK * outer_z)
	)
	lines.append_array(
		_ellipse_lines(Vector3.ZERO, Vector3.RIGHT * inner_x, Vector3.BACK * inner_z)
	)
	lines.append_array(
		_ellipse_lines(Vector3.RIGHT * major_x, Vector3.RIGHT * tube_x, Vector3.UP * tube_y)
	)
	lines.append_array(
		_ellipse_lines(Vector3.LEFT * major_x, Vector3.RIGHT * tube_x, Vector3.UP * tube_y)
	)
	lines.append_array(
		_ellipse_lines(Vector3.BACK * major_z, Vector3.BACK * tube_z, Vector3.UP * tube_y)
	)
	lines.append_array(
		_ellipse_lines(Vector3.FORWARD * major_z, Vector3.BACK * tube_z, Vector3.UP * tube_y)
	)
	return lines


## Flatten FaceData triangulation into the exact local triangles used by the
## custom gizmo's filled picking proxy. Displacement faces are included because
## their own triangulate() implementation supplies the subdivided surface.
static func face_triangle_vertices(faces: Array) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for face in faces:
		if face == null or not face.has_method("triangulate"):
			continue
		var triangulation: Dictionary = face.triangulate()
		var vertices: PackedVector3Array = triangulation.get("verts", PackedVector3Array())
		_append_valid_triangles(triangles, vertices, Transform3D.IDENTITY)
	return triangles


static func triangle_mesh_from_faces(faces: Array) -> TriangleMesh:
	return triangle_mesh_from_vertices(face_triangle_vertices(faces))


static func triangle_mesh_from_vertices(vertices: PackedVector3Array) -> TriangleMesh:
	if vertices.is_empty():
		return null
	var triangle_mesh := TriangleMesh.new()
	if not triangle_mesh.create_from_faces(vertices):
		return null
	return triangle_mesh


## Gather visible internal MeshInstance3D descendants in coordinates local to
## their DraftEntity owner. The transformed triangles give native object and
## region selection an exact proxy even for nested preview hierarchies.
static func visible_mesh_triangle_vertices(root: Node3D) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	if not is_effectively_visible(root):
		return triangles
	_collect_visible_mesh_triangles(root, root, Transform3D.IDENTITY, triangles)
	return triangles


static func visible_mesh_triangle_mesh(root: Node3D) -> TriangleMesh:
	return triangle_mesh_from_vertices(visible_mesh_triangle_vertices(root))


## Gather Sprite3D preview geometry in DraftEntity-local coordinates. Ordinary
## sprites use Godot's configured quad exactly. Shader-billboarded/fixed-size
## sprites cannot have camera-facing native gizmo collision, so use the smallest
## simple camera-independent cube that encloses the nominal generated quad about
## its origin. This stays texture-, frame-, offset-, axis- and pixel-size-aware
## without pretending the proxy can follow the editor camera.
static func visible_sprite_proxy_triangle_vertices(root: Node3D) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	if not is_effectively_visible(root):
		return triangles
	_collect_visible_sprite_triangles(root, root, Transform3D.IDENTITY, triangles)
	return triangles


static func visible_preview_triangle_vertices(root: Node3D) -> PackedVector3Array:
	var triangles := visible_mesh_triangle_vertices(root)
	triangles.append_array(visible_sprite_proxy_triangle_vertices(root))
	return triangles


## Return every visible preview pick surface, including a restrained proxy for
## each broken or line-only visual. Keeping this collector combined matters for
## composite entities: one healthy child must not make an incomplete sibling
## impossible to select.
static func visible_preview_collision_triangle_vertices(
	root: Node3D, minimum_size: Vector3 = Vector3.ONE
) -> PackedVector3Array:
	var triangles := visible_preview_triangle_vertices(root)
	triangles.append_array(visible_empty_preview_marker_vertices(root, minimum_size))
	return triangles


## Keep a visible but incomplete preview selectable. A null mesh/texture or a
## line-only mesh cannot produce filled triangles, so give each such visual a
## small solid proxy at its actual nested transform. Hidden visuals deliberately
## produce nothing and therefore never leave an invisible click target.
static func visible_empty_preview_marker_vertices(
	root: Node3D, minimum_size: Vector3 = Vector3.ONE
) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	if not is_effectively_visible(root):
		return triangles
	_collect_visible_empty_preview_markers(
		root, root, Transform3D.IDENTITY, minimum_size, triangles
	)
	return triangles


## `.visible` alone misses a hidden managed parent. Detached nodes have no tree
## visibility state, so retain the local property behavior used by unit/tooling
## callers that build preview fixtures off-tree.
static func is_effectively_visible(node: Node3D) -> bool:
	if not node or not node.visible:
		return false
	return node.is_visible_in_tree() if node.is_inside_tree() else true


static func has_mesh_instance_descendant(root: Node) -> bool:
	if not root:
		return false
	for child in root.get_children(true):
		if child is MeshInstance3D or has_mesh_instance_descendant(child):
			return true
	return false


static func has_preview_geometry_descendant(root: Node) -> bool:
	if not root:
		return false
	for child in root.get_children(true):
		if child is MeshInstance3D or child is Sprite3D or has_preview_geometry_descendant(child):
			return true
	return false


static func box_triangle_vertices(
	size: Vector3 = Vector3.ONE, center: Vector3 = Vector3.ZERO
) -> PackedVector3Array:
	var half := size.abs() * 0.5
	var corners := PackedVector3Array(
		[
			center + Vector3(-half.x, -half.y, -half.z),
			center + Vector3(half.x, -half.y, -half.z),
			center + Vector3(half.x, half.y, -half.z),
			center + Vector3(-half.x, half.y, -half.z),
			center + Vector3(-half.x, -half.y, half.z),
			center + Vector3(half.x, -half.y, half.z),
			center + Vector3(half.x, half.y, half.z),
			center + Vector3(-half.x, half.y, half.z),
		]
	)
	var triangles := PackedVector3Array()
	for face in BOX_FACE_INDICES:
		triangles.append(corners[face[0]])
		triangles.append(corners[face[1]])
		triangles.append(corners[face[2]])
		triangles.append(corners[face[0]])
		triangles.append(corners[face[2]])
		triangles.append(corners[face[3]])
	return triangles


static func points_bounds_lines(points: PackedVector3Array) -> PackedVector3Array:
	if points.is_empty():
		return PackedVector3Array()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		if point.is_finite():
			bounds = bounds.expand(point)
	var raw_lines := box_lines(bounds.size)
	var lines := PackedVector3Array()
	var seen_edges: Dictionary = {}
	for index in range(0, raw_lines.size(), 2):
		var from := raw_lines[index] + bounds.get_center()
		var to := raw_lines[index + 1] + bounds.get_center()
		if from.is_equal_approx(to):
			continue
		var edge_key := _edge_key(from, to)
		if seen_edges.has(edge_key):
			continue
		seen_edges[edge_key] = true
		lines.append(from)
		lines.append(to)
	return lines


static func mesh_line_vertices(mesh: Mesh) -> PackedVector3Array:
	var lines := PackedVector3Array()
	if not mesh:
		return lines
	for surface in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_LINES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var indices := (
			raw_indices as PackedInt32Array
			if raw_indices is PackedInt32Array
			else PackedInt32Array()
		)
		if indices.is_empty():
			lines.append_array(vertices)
		else:
			for index in indices:
				if index >= 0 and index < vertices.size():
					lines.append(vertices[index])
	return lines


static func line_mesh(lines: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if lines.is_empty():
		return mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for vertex in lines:
		surface.add_vertex(vertex)
	return surface.commit()


static func _ellipse_lines(
	center: Vector3, axis_u: Vector3, axis_v: Vector3, segments: int = CURVE_SEGMENTS
) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var count := maxi(3, segments)
	for index in range(count):
		var angle_a := TAU * float(index) / float(count)
		var angle_b := TAU * float(index + 1) / float(count)
		var from := center + axis_u * cos(angle_a) + axis_v * sin(angle_a)
		var to := center + axis_u * cos(angle_b) + axis_v * sin(angle_b)
		_append_segment(lines, from, to)
	return lines


static func _capsule_profile_lines(
	radial_axis: Vector3, radius: float, straight_half: float
) -> PackedVector3Array:
	var points := PackedVector3Array()
	var half_segments := maxi(4, CURVE_SEGMENTS / 2)
	for index in range(half_segments + 1):
		var angle := PI * float(index) / float(half_segments)
		points.append(
			radial_axis * (cos(angle) * radius) + Vector3.UP * (straight_half + sin(angle) * radius)
		)
	for index in range(half_segments + 1):
		var angle := PI + PI * float(index) / float(half_segments)
		points.append(
			(
				radial_axis * (cos(angle) * radius)
				+ Vector3.UP * (-straight_half + sin(angle) * radius)
			)
		)
	var lines := PackedVector3Array()
	for index in range(points.size()):
		_append_segment(lines, points[index], points[(index + 1) % points.size()])
	return lines


static func _append_segment(lines: PackedVector3Array, from: Vector3, to: Vector3) -> void:
	if not from.is_finite() or not to.is_finite() or from.is_equal_approx(to):
		return
	lines.append(from)
	lines.append(to)


static func _polygon_normal(vertices: PackedVector3Array) -> Vector3:
	if vertices.size() < 3:
		return Vector3.ZERO
	var origin := vertices[0]
	for index in range(1, vertices.size() - 1):
		var normal := (vertices[index] - origin).cross(vertices[index + 1] - origin)
		if normal.length_squared() > TRIANGLE_AREA_EPSILON_SQUARED:
			return normal.normalized()
	return Vector3.ZERO


static func _normals_have_crease(normals: Array) -> bool:
	for first in range(normals.size()):
		var normal_a: Vector3 = normals[first]
		for second in range(first + 1, normals.size()):
			var normal_b: Vector3 = normals[second]
			if absf(normal_a.dot(normal_b)) < COPLANAR_NORMAL_DOT:
				return true
	return false


static func _append_valid_triangles(
	out: PackedVector3Array, vertices: PackedVector3Array, transform: Transform3D
) -> void:
	for index in range(0, vertices.size(), 3):
		if index + 2 >= vertices.size():
			break
		var a := transform * vertices[index]
		var b := transform * vertices[index + 1]
		var c := transform * vertices[index + 2]
		if not a.is_finite() or not b.is_finite() or not c.is_finite():
			continue
		if (b - a).cross(c - a).length_squared() <= TRIANGLE_AREA_EPSILON_SQUARED:
			continue
		out.append(a)
		out.append(b)
		out.append(c)


static func _collect_visible_mesh_triangles(
	root: Node3D,
	node: Node,
	relative_transform: Transform3D,
	out: PackedVector3Array,
) -> void:
	for child in node.get_children(true):
		var child_transform := relative_transform
		if child is Node3D:
			var child_3d := child as Node3D
			if not is_effectively_visible(child_3d):
				continue
			child_transform = _child_transform_in_root_space(root, relative_transform, child_3d)
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh:
				var source := mesh_instance.mesh.generate_triangle_mesh()
				if source:
					_append_valid_triangles(out, source.get_faces(), child_transform)
		_collect_visible_mesh_triangles(root, child, child_transform, out)


static func _collect_visible_sprite_triangles(
	root: Node3D,
	node: Node,
	relative_transform: Transform3D,
	out: PackedVector3Array,
) -> void:
	for child in node.get_children(true):
		var child_transform := relative_transform
		if child is Node3D:
			var child_3d := child as Node3D
			if not is_effectively_visible(child_3d):
				continue
			child_transform = _child_transform_in_root_space(root, relative_transform, child_3d)
		if child is Sprite3D:
			_append_sprite_proxy_triangles(out, child as Sprite3D, child_transform)
		_collect_visible_sprite_triangles(root, child, child_transform, out)


static func _collect_visible_empty_preview_markers(
	root: Node3D,
	node: Node,
	relative_transform: Transform3D,
	minimum_size: Vector3,
	out: PackedVector3Array,
) -> void:
	for child in node.get_children(true):
		var child_transform := relative_transform
		if child is Node3D:
			var child_3d := child as Node3D
			if not is_effectively_visible(child_3d):
				continue
			child_transform = _child_transform_in_root_space(root, relative_transform, child_3d)
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var source := (
				mesh_instance.mesh.generate_triangle_mesh() if mesh_instance.mesh else null
			)
			if not source or source.get_faces().is_empty():
				var marker_size := minimum_size.abs()
				var marker_center := Vector3.ZERO
				if mesh_instance.mesh:
					var bounds := mesh_instance.mesh.get_aabb()
					marker_center = bounds.get_center()
					marker_size = Vector3(
						maxf(marker_size.x, bounds.size.x),
						maxf(marker_size.y, bounds.size.y),
						maxf(marker_size.z, bounds.size.z),
					)
				_append_valid_triangles(
					out, box_triangle_vertices(marker_size, marker_center), child_transform
				)
		elif child is Sprite3D:
			var sprite := child as Sprite3D
			var source := sprite.generate_triangle_mesh()
			if not source or source.get_faces().is_empty():
				_append_valid_triangles(
					out, box_triangle_vertices(minimum_size.abs()), child_transform
				)
		_collect_visible_empty_preview_markers(root, child, child_transform, minimum_size, out)


static func _child_transform_in_root_space(
	root: Node3D, parent_transform: Transform3D, child: Node3D
) -> Transform3D:
	# A top-level preview ignores its Node3D parent transform. When both nodes are
	# live, derive the exact entity-local transform from their global transforms
	# instead of accidentally applying the entity transform twice.
	if child.top_level and root.is_inside_tree() and child.is_inside_tree():
		return root.global_transform.affine_inverse() * child.global_transform
	return parent_transform * child.transform


static func _append_sprite_proxy_triangles(
	out: PackedVector3Array, sprite: Sprite3D, transform: Transform3D
) -> void:
	var source := sprite.generate_triangle_mesh()
	if not source:
		return
	var vertices := source.get_faces()
	if vertices.is_empty():
		return
	if sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED and not sprite.fixed_size:
		_append_valid_triangles(out, vertices, transform)
		return

	var radius := 0.0
	for vertex in vertices:
		if vertex.is_finite():
			radius = maxf(radius, vertex.length())
	var diameter := maxf(SPRITE_PROXY_MIN_DIAMETER, radius * 2.0)
	_append_valid_triangles(out, box_triangle_vertices(Vector3.ONE * diameter), transform)


static func _edge_key(from: Vector3, to: Vector3) -> String:
	var from_key := _vertex_key(from)
	var to_key := _vertex_key(to)
	return from_key + "|" + to_key if from_key < to_key else to_key + "|" + from_key


static func _vertex_key(vertex: Vector3) -> String:
	return (
		"%d:%d:%d"
		% [
			roundi(vertex.x * EDGE_KEY_SCALE),
			roundi(vertex.y * EDGE_KEY_SCALE),
			roundi(vertex.z * EDGE_KEY_SCALE),
		]
	)
