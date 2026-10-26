@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether every path through a bake gives its meshes tangents that follow the UVs.
##
## #1883 found the face path wrote no tangents, so a normal map on a baked wall
## was lit from the wrong side, and #1902 put `generate_tangents()` into the face
## and atlas builders. The GUT test reads `bake_from_faces()` on one box. A level
## goes through more than that: a cut sends it down the CSG path, a displaced
## face builds its own grid, a smoothing group rewrites the normals, a hidden face
## is taken out of the mesh, a chunked bake, merged meshes and a lightmap unwrap
## each rebuild the arrays once more. This bakes one level per path through the
## real `bake()` and reads every corner's tangent against the way its
## triangle's U runs, and against its own normal.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")


func id() -> String:
	return "bake-tangents"


func summary() -> String:
	return "whether every bake path gives its meshes tangents that follow the UVs"


func run() -> void:
	await _case("face path, one textured box", func(root, b): pass)
	await _case(
		"a subtract brush, which sends the bake down the CSG path",
		func(root, b):
			var cut = root.create_brush_from_info(
				{"shape": 0, "size": Vector3(1, 1, 6), "center": Vector3(0, 0, 0), "operation": 2}
			)
			cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	)
	await _case("forced CSG", func(root, b): pass, {"force_csg": true})
	await _case(
		"a displaced top face, flat",
		func(root, b):
			var top := _face_facing(b, Vector3.UP)
			root.create_displacement(str(b.get_meta("brush_id", "")), top, 3)
	)
	# A sculpted face is curved, so a corner's tangent is the average of its
	# triangles' and can sit well off any one of them. Only one that points
	# against its U is wrong there.
	await _case(
		"a displaced top face, sculpted",
		func(root, b):
			var top := _face_facing(b, Vector3.UP)
			root.create_displacement(str(b.get_meta("brush_id", "")), top, 3)
			root.noise_displacement(str(b.get_meta("brush_id", "")), top, 0.5),
		{"curved": true}
	)
	await _case(
		"a cylinder in one smoothing group",
		func(root, b):
			var cyl = root.create_brush_from_info(
				{
					"shape": DraftBrush.BrushShape.CYLINDER,
					"size": Vector3(3, 3, 3),
					"center": Vector3(6, 0, 0)
				}
			)
			# The sides only: the caps meet them at a right angle, and a smoothing
			# group across that edge bends the normals there on purpose.
			for face in cyl.faces:
				face.material_idx = 0
				if absf(face.normal.y) < 0.5:
					face.smoothing_group = 1
			cyl.rebuild_preview()
	)
	await _case(
		"one hidden face",
		func(root, b): root.set_faces_hidden({str(b.get_meta("brush_id", "")): [0]}, true)
	)
	await _case(
		"turned and stretched texture",
		func(root, b):
			for face in b.faces:
				face.uv_rotation = 37.0
				face.uv_scale = Vector2(2.0, 0.5)
			b.rebuild_preview()
	)
	await _case(
		"chunked, six boxes",
		func(root, b):
			for i in range(1, 6):
				var other = box(root, Vector3(2, 2, 2), Vector3(i * 6, 0, 0))
				for face in other.faces:
					face.material_idx = 0
				other.rebuild_preview()
			root.bake_chunk_size = 8.0
	)
	await _case("merged meshes", func(root, b): root.bake_merge_meshes = true)
	await _case("lightmap UV2", func(root, b): root.bake_lightmap_uv2 = true)
	await _case("LODs", func(root, b): root.bake_generate_lods = true)


func _case(label: String, setup: Callable, opts: Dictionary = {}) -> void:
	var root: Node3D = await fresh_root("TangentLevel")
	var slot: int = root.add_material_to_palette(_textured())
	var b = box(root, Vector3(4, 4, 4))
	for face in b.faces:
		face.material_idx = slot
	b.rebuild_preview()
	await frame()
	setup.call(root, b)
	await frame()
	root.tag_full_reconcile()
	var ok = await root.bake(true, false, 0, 0, bool(opts.get("force_csg", false)))
	await frame()
	var meshes := _baked_meshes(root)
	var checked := 0
	var off_u := 0
	var off_normal := 0
	var no_tangents := 0
	for mesh in meshes:
		var check := _tangent_check(mesh, bool(opts.get("curved", false)))
		checked += check[0]
		off_u += check[1]
		off_normal += check[2]
		no_tangents += check[3]
	note(
		label,
		(
			"bake %s, %d meshes, %d corners read, %d off their U, %d not square to their normal, %d surfaces without tangents"
			% [ok, meshes.size(), checked, off_u, off_normal, no_tangents]
		)
	)
	if checked == 0:
		flag("%s: nothing baked to read" % label, "bake returned %s" % ok)
	elif off_u > 0 or off_normal > 0 or no_tangents > 0:
		flag(
			"%s: the baked mesh's tangents do not follow its UVs" % label,
			(
				"%d of %d corners carry a tangent more than 25 degrees off the way their U runs, %d are not square to their normal, %d surfaces have no tangent array. A normal map lights them from the wrong side (#1883)."
				% [off_u, checked, off_normal, no_tangents]
			)
		)
	await drop_root(root)


func _face_facing(brush: Node, dir: Vector3) -> int:
	for i in range(brush.faces.size()):
		if brush.faces[i].normal.dot(dir) > 0.9:
			return i
	return 0


func _textured() -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.normal_enabled = true
	return mat


func _baked_meshes(root: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [root.baked_container]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node == null or not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D and node.mesh != null:
			out.append(node.mesh)
		elif node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
			out.append(node.multimesh.mesh)
	return out


## [checked, off its U, not square to its normal, surfaces with no tangent array]
func _tangent_check(mesh: Mesh, curved := false) -> Array:
	var checked := 0
	var off := 0
	var skew := 0
	var missing := 0
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		if not (uvs is PackedVector2Array) or (uvs as PackedVector2Array).is_empty():
			continue
		if not (tangents is PackedFloat32Array) or (tangents as PackedFloat32Array).is_empty():
			missing += 1
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
			var tri_n := (verts[b] - verts[a]).cross(verts[c] - verts[a]).normalized()
			# The U direction in the triangle's own plane, as a tangent is.
			along_u = (along_u - tri_n * along_u.dot(tri_n)).normalized()
			for corner in [a, b, c]:
				checked += 1
				var stored := Vector3(
					tangents[corner * 4], tangents[corner * 4 + 1], tangents[corner * 4 + 2]
				)
				if stored.normalized().dot(along_u) < (0.0 if curved else 0.9):
					off += 1
				if normals is PackedVector3Array and normals.size() > corner:
					if absf(stored.normalized().dot(normals[corner])) > 0.1:
						skew += 1
	return [checked, off, skew, missing]
