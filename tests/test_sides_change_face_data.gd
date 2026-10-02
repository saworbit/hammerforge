extends GutTest

## A primitive rebuilt with a different number of faces (#851).
##
## `sides` is in the Inspector, so a placed cylinder, cone or pyramid can have it
## changed after it is textured. The rebuild handed face data over by index and
## gave up when the counts differed, so every face came back with nothing, and
## setting `sides` back did not bring it back. Faces are paired by the way they
## face now, and a sculpt or custom UVs follow only to a face with the same
## corners.

const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")

var holder: Node3D


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)
	HFLog.begin_test_capture(["HammerForge: "])


func after_each():
	HFLog.end_test_capture()
	holder = null


func _make(shape: int, sides: int, brush_id := "b1") -> DraftBrush:
	var b := DraftBrush.new()
	b.brush_id = brush_id
	holder.add_child(b)
	b.shape = shape
	b.sides = sides
	b.size = Vector3(32, 32, 32)
	return b


func _materials(b: DraftBrush) -> Array:
	var out: Array = []
	for face in b.get_faces():
		out.append(face.material_idx)
	return out


## The face whose normal is closest to `direction`.
func _nearest(b: DraftBrush, direction: Vector3) -> FaceData:
	var best: FaceData = null
	var best_dot := -2.0
	for face in b.get_faces():
		var d: float = face.normal.dot(direction.normalized())
		if d > best_dot:
			best_dot = d
			best = face
	return best


func _warnings_naming(brush_id: String) -> Array:
	var out: Array = []
	for message in HFLog.get_captured_warnings():
		if str(message).contains("'%s'" % brush_id):
			out.append(message)
	return out


func test_a_material_survives_a_sides_change_and_back():
	var b := _make(DraftBrush.BrushShape.CYLINDER, 16)
	assert_eq(b.get_faces().size(), 18, "16 sides and two caps")
	for face in b.get_faces():
		face.material_idx = 7

	b.sides = 24
	assert_eq(b.get_faces().size(), 26, "24 sides and two caps")
	assert_false(_materials(b).has(-1), "every face keeps the material")
	assert_eq(_materials(b).count(7), 26)

	b.sides = 16
	assert_eq(_materials(b).count(7), 18, "and keeps it on the way back")


func test_a_pyramid_keeps_its_material_through_a_sides_change():
	var b := _make(DraftBrush.BrushShape.PYRAMID, 4)
	assert_eq(b.get_faces().size(), 5)
	for face in b.get_faces():
		face.material_idx = 3
		face.uv_scale = Vector2(2, 2)
	b.sides = 6
	assert_eq(b.get_faces().size(), 7)
	for face in b.get_faces():
		assert_eq(face.material_idx, 3, "material")
		assert_eq(face.uv_scale, Vector2(2, 2), "and UV scale")


func test_each_face_takes_the_appearance_of_the_face_that_faced_its_way():
	var b := _make(DraftBrush.BrushShape.CYLINDER, 16)
	for face in b.get_faces():
		face.material_idx = 1
	_nearest(b, Vector3.UP).material_idx = 5
	var painted := _nearest(b, Vector3(1, 0, 0.2))
	painted.material_idx = 9
	painted.uv_rotation = 0.5
	var painted_normal := painted.normal

	b.sides = 24

	assert_eq(_nearest(b, Vector3.UP).material_idx, 5, "the top cap keeps its own")
	assert_eq(_nearest(b, Vector3.DOWN).material_idx, 1, "the bottom cap keeps its own")
	var side := _nearest(b, painted_normal)
	assert_eq(side.material_idx, 9, "the side that faces the painted side's way takes it")
	assert_almost_eq(side.uv_rotation, 0.5, 0.0001, "with its UV rotation")
	assert_eq(_nearest(b, -painted_normal).material_idx, 1, "the far side does not")
	var nines := _materials(b).count(9)
	assert_between(nines, 1, 2, "one old side spreads over the new sides nearest it")


func test_a_sculpt_that_cannot_follow_is_dropped_with_a_warning():
	var b := _make(DraftBrush.BrushShape.CYLINDER, 16, "drum")
	var side := _nearest(b, Vector3(1, 0, 0.2))
	assert_eq(side.local_verts.size(), 4, "a cylinder's side is a quad")
	var disp := HFDisplacementDataScript.new()
	disp.init_flat(2)
	disp.set_distance(1, 1, 3.0)
	side.displacement = disp

	b.sides = 24

	for face in b.get_faces():
		assert_null(face.displacement, "no new side has the old one's corners")
	var warned := _warnings_naming("drum")
	assert_eq(warned.size(), 1, "one warning, naming the brush")
	if warned.size() == 1:
		assert_string_contains(warned[0], "sculpt")


func test_custom_uvs_that_cannot_follow_are_dropped_with_a_warning():
	# A pyramid's faces come with no UVs of their own, so custom UVs on one were
	# set by hand.
	var b := _make(DraftBrush.BrushShape.PYRAMID, 4, "spire")
	var base := _nearest(b, Vector3.DOWN)
	assert_true(base.custom_uvs.is_empty(), "the generator gives the base no UVs")
	var uvs := PackedVector2Array()
	for i in base.local_verts.size():
		uvs.append(Vector2(i * 0.25, 1.0 - i * 0.25))
	base.custom_uvs = uvs

	b.sides = 6

	assert_true(_nearest(b, Vector3.DOWN).custom_uvs.is_empty(), "a hexagon cannot take them")
	var warned := _warnings_naming("spire")
	assert_eq(warned.size(), 1, "one warning, naming the brush")
	if warned.size() == 1:
		assert_string_contains(warned[0], "custom UVs")


func test_nothing_to_drop_warns_nothing():
	var b := _make(DraftBrush.BrushShape.CYLINDER, 16, "plain")
	b.sides = 24
	b.sides = 16
	assert_eq(_warnings_naming("plain"), [], "generated UVs are not something to lose")


## A face whose corners all sit where an old face's did still takes its sculpt,
## relabelled to its own corner order. A box turned into a wedge keeps its
## bottom, and the sculpt on it lands where it was.
func test_a_sculpt_on_a_face_that_stays_put_follows_it():
	var b := _make(DraftBrush.BrushShape.BOX, 4, "slab")
	b.size = Vector3(32, 24, 40)
	var bottom := _nearest(b, Vector3.DOWN)
	var disp := HFDisplacementDataScript.new()
	disp.init_flat(2)
	var d: int = disp.get_dim()
	for row in d:
		for col in d:
			disp.set_distance(row, col, row * 1.0 + col * 0.25 + 0.5 * ((row * col) % 3))
	bottom.displacement = disp
	var expected := _triangle_keys(bottom)

	b.shape = DraftBrush.BrushShape.WEDGE

	var after := _nearest(b, Vector3.DOWN)
	assert_not_null(after.displacement, "the wedge's bottom is the box's bottom")
	assert_eq(_triangle_keys(after), expected, "and the sculpt is where it was")
	assert_eq(_warnings_naming("slab"), [], "nothing was dropped")


## A displaced face's triangles as a sorted set of text keys, each keeping its
## winding, so a sculpt laid the wrong way round does not compare equal.
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
