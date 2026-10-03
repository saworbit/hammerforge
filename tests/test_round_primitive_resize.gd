extends GutTest

## Resizing a sphere, ellipsoid or torus (#852).
##
## These used to turn a Godot mesh of a few thousand triangles back into faces on
## every resize, over 100 ms each, and a handle drag resizes on every motion
## event. Their corners scale with the brush axis by axis, so the faces are built
## once and scaled. Merging at the brush's own size had also let rounding decide
## whether a flat quad stayed one face, so the face count changed with the size.

const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")

const ROUND := [
	DraftBrush.BrushShape.SPHERE, DraftBrush.BrushShape.ELLIPSOID, DraftBrush.BrushShape.TORUS
]

var holder: Node3D


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)


func after_each():
	holder = null


func _make(shape: int, sz := Vector3(32, 32, 32)) -> DraftBrush:
	var b := DraftBrush.new()
	holder.add_child(b)
	b.shape = shape
	b.size = sz
	return b


## What turning the shape's mesh into faces at the brush's current size gives,
## which is how every resize used to build them.
func _merged_from_mesh(b: DraftBrush) -> Array:
	var build: Dictionary = b._build_base_mesh()
	return b._faces_from_mesh(build["mesh"], build.get("scale", Vector3.ONE))


func _corner_set(face_list: Array) -> Array:
	var keys := {}
	for face in face_list:
		for p in face.local_verts:
			keys["%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)]] = true
	var out := keys.keys()
	out.sort()
	return out


func _first_quad(b: DraftBrush) -> int:
	for i in b.get_faces().size():
		if b.get_faces()[i].local_verts.size() == 4:
			return i
	return -1


func test_the_faces_match_the_mesh_merged_at_that_size():
	for shape in ROUND:
		var b := _make(shape)
		for sz in [Vector3(1, 1, 1), Vector3(7.3, 7.3, 7.3), Vector3(100, 100, 100)]:
			b.size = sz
			var got := b.get_faces()
			var want := _merged_from_mesh(b)
			assert_eq(got.size(), want.size(), "shape %d at %s: face count" % [shape, sz])
			if got.size() != want.size():
				continue
			var worst := 0.0
			var uvs_differ := 0
			for i in want.size():
				var a: PackedVector3Array = got[i].local_verts
				var w: PackedVector3Array = want[i].local_verts
				if a.size() != w.size():
					worst = INF
					break
				for k in w.size():
					worst = maxf(worst, a[k].distance_to(w[k]))
				worst = maxf(worst, got[i].normal.distance_to(want[i].normal))
				if got[i].custom_uvs != want[i].custom_uvs:
					uvs_differ += 1
			assert_lt(worst, 0.0001, "shape %d at %s: corner for corner" % [shape, sz])
			assert_eq(uvs_differ, 0, "shape %d at %s: UVs" % [shape, sz])


func test_a_stretched_shape_has_every_corner_the_merged_mesh_has():
	# Stretched, the merge splits a few flat quads into triangles from rounding,
	# so the faces differ in count. The corners they are made of do not.
	for shape in [DraftBrush.BrushShape.ELLIPSOID, DraftBrush.BrushShape.TORUS]:
		for sz in [Vector3(64, 16, 40), Vector3(12, 30, 20)]:
			var b := _make(shape, sz)
			assert_eq(
				_corner_set(b.get_faces()),
				_corner_set(_merged_from_mesh(b)),
				"shape %d at %s" % [shape, sz]
			)


func test_a_round_shape_has_the_same_faces_at_every_size():
	var b := _make(DraftBrush.BrushShape.SPHERE)
	var small: Array = []
	for face in b.get_faces():
		small.append(face.local_verts)
	b.size = Vector3(1000, 1000, 1000)
	assert_eq(b.get_faces().size(), small.size(), "no face split or merged by the new size")
	if b.get_faces().size() != small.size():
		return
	var worst := 0.0
	for i in small.size():
		var big: PackedVector3Array = b.get_faces()[i].local_verts
		for k in big.size():
			worst = maxf(worst, (big[k] / 1000.0).distance_to(small[i][k] / 32.0))
	assert_lt(worst, 0.000001, "every face is the same face, scaled")


func test_a_resize_keeps_every_face_and_what_is_on_it():
	var b := _make(DraftBrush.BrushShape.ELLIPSOID)
	var quad := _first_quad(b)
	assert_gt(quad, -1, "an ellipsoid has a quad to sculpt")
	if quad < 0:
		return
	var sculpt := HFDisplacementDataScript.new()
	sculpt.init_flat(2)
	sculpt.set_distance(1, 1, 2.0)
	b.get_faces()[quad].displacement = sculpt
	b.get_faces()[0].material_idx = 4
	var before: Array = b.get_faces().duplicate()

	b.size = Vector3(48, 20, 36)

	var kept := 0
	for i in before.size():
		if b.get_faces()[i] == before[i]:
			kept += 1
	assert_eq(kept, before.size(), "every face is the one it was")
	assert_eq(b.get_faces()[0].material_idx, 4, "with its material")
	assert_true(b.get_faces()[quad].displacement == sculpt, "and its sculpt")
	assert_eq(_corner_set(b.get_faces()), _corner_set(_merged_from_mesh(b)), "at the new size")


func test_a_face_turned_since_it_was_built_keeps_its_sculpt_where_it_was():
	# Moving corners in place would put a turned face back in the order the shape
	# builds it, and leave its sculpt laid against the old order, turned.
	var b := _make(DraftBrush.BrushShape.SPHERE)
	var quad := _first_quad(b)
	assert_gt(quad, -1, "a sphere has a quad to sculpt")
	if quad < 0:
		return
	var face: FaceData = b.get_faces()[quad]
	var verts: PackedVector3Array = face.local_verts
	face.local_verts = PackedVector3Array([verts[1], verts[2], verts[3], verts[0]])
	face.ensure_geometry()
	var sculpt := HFDisplacementDataScript.new()
	sculpt.init_flat(2)
	var d: int = sculpt.get_dim()
	for row in d:
		for col in d:
			sculpt.set_distance(row, col, row * 1.0 + col * 0.25 + 0.5 * ((row * col) % 3))
	face.displacement = sculpt
	var before := _triangle_keys(b.get_faces()[quad])

	b.set_size(Vector3(32, 32, 32))

	assert_eq(_triangle_keys(b.get_faces()[quad]), before, "the surface is where it was")


func test_a_capsule_has_the_same_faces_at_every_size():
	# It still merges its mesh at its own size. Rounding the plane's distance at
	# a fixed step split flat quads on a large one: 2,432 faces at 32 units and
	# 2,500 at 1,000 (#858). A stretched one has a straight middle whose quads
	# stack into tall faces, so it is compared with itself at another scale.
	var b := _make(DraftBrush.BrushShape.CAPSULE)
	var expected := b.get_faces().size()
	for sz in [Vector3(1, 1, 1), Vector3(250.25, 250.25, 250.25), Vector3(1000, 1000, 1000)]:
		b.size = sz
		assert_eq(b.get_faces().size(), expected, "at %s" % b.size)
	b.size = Vector3(16, 64, 16)
	var stretched := b.get_faces().size()
	b.size = Vector3(160, 640, 160)
	assert_eq(b.get_faces().size(), stretched, "stretched, at ten times the size")


## A capsule is built once too, in two cases with different faces: no middle,
## and a straight middle between the caps (#860). Its caps are tied to its
## diameter, so its corners are placed from the radius and the middle's length
## rather than scaled, and have to land where a merge at that size puts them.
func test_a_capsule_matches_its_merged_mesh_corner_for_corner():
	var sizes := [
		Vector3(32, 32, 32),
		Vector3(7.3, 7.3, 7.3),
		Vector3(100, 100, 100),
		Vector3(16, 40, 16),
		Vector3(32, 33, 32),
		Vector3(8, 100, 8),
		Vector3(200, 201, 200),
	]
	var b := _make(DraftBrush.BrushShape.CAPSULE)
	for sz in sizes:
		b.size = sz
		var got := b.get_faces()
		var want := _merged_from_mesh(b)
		assert_eq(got.size(), want.size(), "at %s: face count" % sz)
		if got.size() != want.size():
			continue
		var worst := 0.0
		for i in want.size():
			var a: PackedVector3Array = got[i].local_verts
			var w: PackedVector3Array = want[i].local_verts
			if a.size() != w.size():
				worst = INF
				break
			for k in w.size():
				worst = maxf(worst, a[k].distance_to(w[k]))
			worst = maxf(worst, got[i].normal.distance_to(want[i].normal))
			worst = maxf(worst, got[i].bounds.position.distance_to(want[i].bounds.position))
			worst = maxf(worst, got[i].bounds.size.distance_to(want[i].bounds.size))
		assert_lt(worst, 0.0001, "at %s: corner for corner" % sz)


## A handle drag resizes on every motion event, and merging the capsule's mesh
## took 80 ms or more each time. Within a case the faces are kept and moved.
func test_a_capsule_resize_keeps_every_face_and_what_is_on_it():
	var b := _make(DraftBrush.BrushShape.CAPSULE, Vector3(16, 40, 16))
	var quad := _first_quad(b)
	assert_gt(quad, -1, "a capsule has a quad to sculpt")
	if quad < 0:
		return
	var sculpt := HFDisplacementDataScript.new()
	sculpt.init_flat(2)
	sculpt.set_distance(1, 1, 2.0)
	b.get_faces()[quad].displacement = sculpt
	b.get_faces()[0].material_idx = 4
	var before: Array = b.get_faces().duplicate()

	b.size = Vector3(24, 60, 24)

	var kept := 0
	for i in before.size():
		if b.get_faces()[i] == before[i]:
			kept += 1
	assert_eq(kept, before.size(), "every face is the one it was")
	assert_eq(b.get_faces()[0].material_idx, 4, "with its material")
	assert_true(b.get_faces()[quad].displacement == sculpt, "and its sculpt")


## Going from no middle to one changes the faces, so it takes the full rebuild,
## which hands data over by place, exactly as the merge did.
func test_a_capsule_that_grows_a_middle_hands_its_data_over_as_before():
	var b := _make(DraftBrush.BrushShape.CAPSULE, Vector3(32, 32, 32))
	for i in b.get_faces().size():
		b.get_faces()[i].material_idx = i % 7
	var old_faces: Array = b.get_faces().duplicate()

	b.size = Vector3(32, 48, 32)

	var merged := _merged_from_mesh(b)
	b._transfer_face_data(old_faces, merged)
	assert_eq(b.get_faces().size(), merged.size(), "the faces of a capsule with a middle")
	var differ := 0
	for i in mini(merged.size(), b.get_faces().size()):
		if b.get_faces()[i].material_idx != merged[i].material_idx:
			differ += 1
	assert_eq(differ, 0, "every face took the material the merge would have given it")


func _triangle_keys(face: FaceData) -> Array:
	var verts: PackedVector3Array = face.triangulate()["verts"]
	var out: Array = []
	for t in range(0, verts.size(), 3):
		var keys: Array = []
		for k in 3:
			var p: Vector3 = verts[t + k]
			keys.append("%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)])
		var first := 0
		for k in 3:
			if keys[k] < keys[first]:
				first = k
		out.append("%s|%s|%s" % [keys[first], keys[(first + 1) % 3], keys[(first + 2) % 3]])
	out.sort()
	return out
