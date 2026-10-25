extends GutTest

## A face mesh must carry tangents that follow its UVs, or a normal map on it is
## lit from the wrong side (#1883). Godot stores a tangent on every vertex even
## when none was generated, made up from the normal alone, so these tests read
## each corner's tangent against the way its triangle's U runs. A check that
## the tangent array is not empty would pass on the broken mesh.

const BakerScript = preload("res://addons/hammerforge/baker.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const MatMgrScript = preload("res://addons/hammerforge/material_manager.gd")

var baker: BakerScript


func before_each():
	baker = BakerScript.new()
	add_child_autoqfree(baker)


func _textured(color: Color) -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.normal_enabled = true
	return mat


func _box(material_idx: int = -1) -> DraftBrush:
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	var brush := DraftBrush.new()
	brush.size = Vector3(4, 4, 4)
	parent.add_child(brush)
	for face in brush.faces:
		face.material_idx = material_idx
	return brush


## A unit square on the floor, so its UVs sit inside 0..1 and the atlas takes it.
func _square(normal: Vector3, material_idx: int) -> FaceData:
	var face := FaceData.new()
	face.normal = normal
	face.material_idx = material_idx
	face.local_verts = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	)
	return face


func _baked_mesh(result: Node3D) -> Mesh:
	for child in result.get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh
	return null


## [checked, off]: how many triangle corners were read, and how many of them
## carry a tangent that does not run the way the triangle's U does.
func _tangent_check(mesh: Mesh) -> Array:
	var checked := 0
	var off := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		if not (uvs is PackedVector2Array) or (uvs as PackedVector2Array).is_empty():
			continue
		var raw = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw if raw is PackedInt32Array else PackedInt32Array()
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		for t in range(0, idx.size() - 2, 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			var d1: Vector2 = uvs[b] - uvs[a]
			var d2: Vector2 = uvs[c] - uvs[a]
			var det := d1.x * d2.y - d2.x * d1.y
			if absf(det) < 0.000001:
				continue
			var along_u := ((verts[b] - verts[a]) * d2.y - (verts[c] - verts[a]) * d1.y) / det
			along_u = along_u.normalized()
			for corner in [a, b, c]:
				checked += 1
				if not (tangents is PackedFloat32Array) or tangents.size() < corner * 4 + 3:
					off += 1
					continue
				var stored := Vector3(
					tangents[corner * 4], tangents[corner * 4 + 1], tangents[corner * 4 + 2]
				)
				if stored.normalized().dot(along_u) < 0.9:
					off += 1
	return [checked, off]


func test_face_material_bake_tangents_follow_the_uvs():
	var mat_mgr := MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	mat_mgr.add_material(_textured(Color.RED))
	var brush := _box(0)
	var result := baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {})
	assert_not_null(result)
	add_child_autoqfree(result)
	var check := _tangent_check(_baked_mesh(result))
	assert_eq(check[0], 36, "all 12 triangles of the box were read")
	assert_eq(check[1], 0, "every corner's tangent runs the way its U does")


func test_atlas_bake_tangents_follow_the_uvs():
	var mat_mgr := MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	mat_mgr.add_material(_textured(Color.RED))
	mat_mgr.add_material(_textured(Color.BLUE))
	var parent := Node3D.new()
	add_child_autoqfree(parent)
	var brush := DraftBrush.new()
	brush.size = Vector3(4, 4, 4)
	parent.add_child(brush)
	var typed: Array[FaceData] = [_square(Vector3.UP, 0), _square(Vector3.DOWN, 1)]
	brush.faces = typed
	brush.geometry_dirty = false
	var result := baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"use_atlas": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var mesh := _baked_mesh(result)
	assert_eq(mesh.get_surface_count(), 1, "the two materials went into one atlas")
	var check := _tangent_check(mesh)
	assert_eq(check[0], 12, "both squares' triangles were read")
	assert_eq(check[1], 0, "every corner's tangent runs the way its atlas U does")


func test_unwrapped_uv0_bake_tangents_follow_the_new_uvs():
	var mat_mgr := MatMgrScript.new()
	add_child_autoqfree(mat_mgr)
	mat_mgr.add_material(_textured(Color.RED))
	var brush := _box(0)
	# Turned so the unwrap's projection runs another way than the face's own.
	for face in brush.faces:
		face.uv_rotation = 90.0
	brush.rebuild_preview()
	var result := baker.bake_from_faces([brush], mat_mgr, null, 1, 1, {"unwrap_uv0": true})
	assert_not_null(result)
	add_child_autoqfree(result)
	var check := _tangent_check(_baked_mesh(result))
	assert_eq(check[0], 36, "all 12 triangles of the box were read")
	assert_eq(check[1], 0, "the tangents follow the UVs the unwrap wrote, not the old ones")


func test_face_material_preview_tangents_follow_the_uvs():
	var brush := _box(0)
	brush.rebuild_preview()
	var mesh: Mesh = brush.mesh_instance.mesh
	assert_true(mesh is ArrayMesh, "the brush shows its faces, not the plain box")
	var check := _tangent_check(mesh)
	assert_eq(check[0], 36, "all 12 triangles of the box were read")
	assert_eq(check[1], 0, "every corner's tangent runs the way its U does")
