extends GutTest

## A primitive rebuilds its faces from its shape on every resize and hands each
## new face the old one's data. Custom UVs and a displacement grid are laid
## against the corners, and a face saved by an older build can start at a
## different corner from the one the generator starts it at. The rebuild has to
## relabel that data to its own corner order, or a sculpt turns under a resize
## that did not even change the size (#846).
##
## Every expectation here is measured from the geometry, never from the
## relabelling itself, so a relabelling that turns the wrong way cannot agree
## with itself. Turning by two is its own inverse, which is why every test goes
## through all four corner orders.

const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")

const SIZE := Vector3(32, 24, 40)
const RESIZED := Vector3(64, 48, 20)
## The +X, +Y and +Z faces, as `_build_box_faces()` orders them, with the axis
## each one faces along.
const FACE_AXES := {0: 0, 2: 1, 4: 2}

var holder: Node3D


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)


func after_each():
	holder = null


func _make_box(sz: Vector3 = SIZE, shape: int = DraftBrush.BrushShape.BOX) -> DraftBrush:
	var b := DraftBrush.new()
	holder.add_child(b)
	b.shape = shape
	b.size = sz
	return b


## Start a face `shift` corners further round, keeping its geometry and its
## custom UVs on their corners. That is what a flip made by an older build left
## in a saved level.
func _turn(face: FaceData, shift: int) -> void:
	var verts: PackedVector3Array = face.local_verts
	var uvs: PackedVector2Array = face.custom_uvs
	var count := verts.size()
	var turned := PackedVector3Array()
	var turned_uvs := PackedVector2Array()
	for i in count:
		turned.append(verts[(i + shift) % count])
		if uvs.size() == count:
			turned_uvs.append(uvs[(i + shift) % count])
	face.local_verts = turned
	face.custom_uvs = turned_uvs
	face.ensure_geometry()


## A sculpt that no symmetry of its grid maps onto itself, on cells that are not
## flat, so a grid laid the wrong way round or split along the wrong diagonal
## cannot pass by coincidence.
func _sculpt(face: FaceData) -> HFDisplacementData:
	var disp := HFDisplacementDataScript.new()
	disp.init_flat(2)
	var d: int = disp.get_dim()
	for row in d:
		for col in d:
			disp.set_distance(row, col, row * 1.0 + col * 0.25 + 0.5 * ((row * col) % 3))
	face.displacement = disp
	return disp


func _displaced_triangles(draft: DraftBrush) -> Array:
	var out: Array = []
	var xform := draft.global_transform
	for face in draft.get_faces():
		if face == null or face.displacement == null:
			continue
		var verts: PackedVector3Array = face.triangulate()["verts"]
		for t in range(0, verts.size(), 3):
			out.append([xform * verts[t], xform * verts[t + 1], xform * verts[t + 2]])
	return out


## Triangles as a sorted set of text keys. Each keeps its winding, starting from
## its smallest corner, so a triangle turned inside out does not compare equal.
func _triangle_keys(triangles: Array) -> Array:
	var out: Array = []
	for tri in triangles:
		var keys: Array = []
		for p in tri:
			keys.append("%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)])
		var first := 0
		for k in 3:
			if keys[k] < keys[first]:
				first = k
		out.append("%s|%s|%s" % [keys[first], keys[(first + 1) % 3], keys[(first + 2) % 3]])
	out.sort()
	return out


## Where a point on the positive face along `axis` lands when the box goes from
## `from` to `to`: scaled across the face, and carried along the normal with the
## face, so its height off the face is kept. That is what a sculpt staying on its
## corners means for a resize.
func _resized_point(p: Vector3, axis: int, from: Vector3, to: Vector3) -> Vector3:
	var out := p
	for k in 3:
		if k == axis:
			out[k] = p[k] + (to[k] - from[k]) * 0.5
		else:
			out[k] = p[k] * to[k] / from[k]
	return out


## A corner named by where it sits as a fraction of the box, which a resize keeps.
func _corner_key(p: Vector3, sz: Vector3) -> String:
	return (
		"%d,%d,%d"
		% [roundi(p.x / sz.x * 1000), roundi(p.y / sz.y * 1000), roundi(p.z / sz.z * 1000)]
	)


# ---------------------------------------------------------------------------
# Displacement
# ---------------------------------------------------------------------------


func test_a_same_size_resize_keeps_a_sculpt_on_a_face_saved_turned():
	for face_index in FACE_AXES:
		for shift in 4:
			var b := _make_box()
			var face: FaceData = b.get_faces()[face_index]
			_turn(face, shift)
			_sculpt(face)
			var before := _triangle_keys(_displaced_triangles(b))

			b.set_size(SIZE)

			assert_eq(
				_triangle_keys(_displaced_triangles(b)),
				before,
				"face %d saved turned by %d" % [face_index, shift]
			)


func test_a_resize_keeps_a_sculpt_where_it_was_on_its_face():
	for face_index in FACE_AXES:
		var axis: int = FACE_AXES[face_index]
		for shift in 4:
			var b := _make_box()
			var face: FaceData = b.get_faces()[face_index]
			_turn(face, shift)
			_sculpt(face)
			var expected: Array = []
			for tri in _displaced_triangles(b):
				var moved: Array = []
				for p in tri:
					moved.append(_resized_point(p, axis, SIZE, RESIZED))
				expected.append(moved)

			b.set_size(RESIZED)

			assert_eq(
				_triangle_keys(_displaced_triangles(b)),
				_triangle_keys(expected),
				"face %d saved turned by %d" % [face_index, shift]
			)


func test_a_rebuilt_face_starts_where_the_box_starts_it():
	# The relabelling goes to the data, not the corners: after one rebuild the
	# face is in the generator's order again, so nothing is left to match next time.
	var fresh := _make_box()
	var b := _make_box()
	_turn(b.get_faces()[2], 2)
	_sculpt(b.get_faces()[2])

	b.set_size(SIZE)

	var got: PackedVector3Array = b.get_faces()[2].local_verts
	var want: PackedVector3Array = fresh.get_faces()[2].local_verts
	for k in want.size():
		assert_true(got[k].is_equal_approx(want[k]), "corner %d: %s, not %s" % [k, got[k], want[k]])


func test_a_face_in_the_generators_order_hands_over_the_same_sculpt():
	var b := _make_box()
	var sculpt := _sculpt(b.get_faces()[2])
	var heights: PackedFloat32Array = sculpt.distances.duplicate()

	b.set_size(RESIZED)

	assert_true(b.get_faces()[2].displacement == sculpt, "the resource itself, as before")
	assert_eq(sculpt.distances, heights, "and untouched")
	assert_false(sculpt.flip_diagonals)


func test_a_turned_sculpt_is_replaced_and_not_rewritten():
	# An undo step or another face can hold the same resource, so the relabelling
	# makes a new one and leaves the old one as it was.
	var b := _make_box()
	_turn(b.get_faces()[2], 1)
	var sculpt := _sculpt(b.get_faces()[2])
	var heights: PackedFloat32Array = sculpt.distances.duplicate()

	b.set_size(SIZE)

	assert_false(b.get_faces()[2].displacement == sculpt, "a new resource")
	assert_eq(sculpt.distances, heights, "the old one is untouched")
	assert_false(sculpt.flip_diagonals, "the old one keeps its own split")


func test_a_resize_keeps_a_sculpt_on_a_turned_face_of_a_built_mesh():
	# Shapes other than the box build their faces from a mesh. The same matching
	# has to work there, against corners that carry float noise.
	var b := _make_box(Vector3(32, 32, 32), DraftBrush.BrushShape.WEDGE)
	var quad := -1
	for i in b.get_faces().size():
		if b.get_faces()[i].local_verts.size() == 4:
			quad = i
			break
	assert_gt(quad, -1, "a wedge has a four-cornered face to sculpt")
	if quad < 0:
		return
	for shift in [1, 2, 3]:
		_turn(b.get_faces()[quad], shift)
		_sculpt(b.get_faces()[quad])
		var before := _triangle_keys(_displaced_triangles(b))

		b.set_size(Vector3(32, 32, 32))

		assert_eq(_triangle_keys(_displaced_triangles(b)), before, "turned by %d" % shift)


func test_the_issue_846_reproduction_keeps_its_surface():
	# The steps in the issue, through a real LevelRoot: a box restored with its top
	# saved turned by two, sculpted afterwards, then resized to the same size.
	var root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	holder.add_child(root)
	var source = root.create_brush_from_info(
		{"shape": DraftBrush.BrushShape.BOX, "size": Vector3(32, 32, 32), "brush_id": "a"}
	)
	_turn(source.get_faces()[2], 2)
	var saved: Array = source.serialize_faces()
	var info := {
		"shape": DraftBrush.BrushShape.BOX,
		"size": Vector3(32, 32, 32),
		"brush_id": "b",
		"center": Vector3(100, 0, 0),
		"faces": saved,
	}
	var b = root.create_brush_from_info(info)
	# A box read from data is stored the way the box builds it since #878, as a
	# scene's box is by the rebuild it goes through on opening.
	assert_true(
		b.get_faces()[2].local_verts[0].is_equal_approx(Vector3(16, 16, -16)),
		"the top loads starting where the box starts it"
	)
	# Turned back the way the old Y flip left it, so the resize below still has a
	# sculpted face to match corners on.
	_turn(b.get_faces()[2], 2)
	assert_true(
		b.get_faces()[2].local_verts[0].is_equal_approx(Vector3(-16, 16, 16)),
		"the top starts where an old Y flip left it"
	)
	assert_true(root.create_displacement("b", 2, 2), "sculpt the top")
	var disp = b.get_faces()[2].displacement
	for row in disp.get_dim():
		for col in disp.get_dim():
			disp.set_distance(row, col, row + 0.25 * col)
	var before := _triangle_keys(_displaced_triangles(b))

	b.set_size(Vector3(32, 32, 32))

	assert_eq(_triangle_keys(_displaced_triangles(b)), before)
	assert_true(
		b.get_faces()[2].local_verts[0].is_equal_approx(Vector3(16, 16, -16)),
		"and the top starts where the box starts it"
	)


# ---------------------------------------------------------------------------
# Custom UVs
# ---------------------------------------------------------------------------


func test_a_resize_keeps_custom_uvs_on_their_corners():
	for face_index in FACE_AXES:
		for shift in 4:
			var b := _make_box()
			var face: FaceData = b.get_faces()[face_index]
			face.custom_uvs = PackedVector2Array(
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			)
			_turn(face, shift)
			var uv_at := {}
			for k in face.local_verts.size():
				uv_at[_corner_key(face.local_verts[k], SIZE)] = face.custom_uvs[k]

			b.set_size(RESIZED)

			var rebuilt: FaceData = b.get_faces()[face_index]
			assert_eq(rebuilt.custom_uvs.size(), 4, "face %d turned by %d" % [face_index, shift])
			for k in rebuilt.local_verts.size():
				var key := _corner_key(rebuilt.local_verts[k], RESIZED)
				assert_eq(
					rebuilt.custom_uvs[k],
					uv_at.get(key),
					"face %d turned by %d, corner %d" % [face_index, shift, k]
				)
