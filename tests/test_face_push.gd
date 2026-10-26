extends GutTest

## Push or pull any face of any brush along its own normal (#1712). After the
## first clip or carve a brush is CUSTOM and has no resize handles, and a sloped
## face never had one, so "make this wall thicker" was a vertex edit or a typed
## number.

const HFFacePush = preload("res://addons/hammerforge/hf_face_push.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	while root.get_materials().size() < 8:
		root.add_material_to_palette(StandardMaterial3D.new())


func after_each() -> void:
	root = null


func _box(size: Vector3, center: Vector3) -> DraftBrush:
	return root.create_brush_from_info({"shape": 0, "size": size, "center": center})


## A 2 m box with its top front edge clipped off at 45 degrees: a CUSTOM brush
## with a sloped face, each face painted its own slot.
func _clipped() -> Array:
	var brush := _box(Vector3(2, 2, 2), Vector3(0, 1, 0))
	for i in brush.faces.size():
		brush.faces[i].material_idx = i
	var slope := Plane(
		Vector3(0, 1, 1).normalized(), Vector3(0, 1, 1).normalized().dot(Vector3(0, 1, 0.5))
	)
	var halves: Dictionary = HFConvexClip.split(brush.faces, slope)
	var faces: Array[FaceData] = []
	for face in halves["back"]:
		faces.append(face)
	brush.shape = DraftBrush.BrushShape.CUSTOM
	brush.faces = faces
	brush.rebuild_preview()
	var sloped := -1
	for i in brush.faces.size():
		var n: Vector3 = HFConvexClip.face_plane(brush.faces[i]).normal
		if n.dot(Vector3(0, 1, 1).normalized()) > 0.999:
			sloped = i
	return [brush, sloped]


func test_a_box_face_grows_the_box_and_keeps_it_a_box():
	var brush := _box(Vector3(2, 2, 2), Vector3(0, 1, 0))
	var east := -1
	for i in brush.faces.size():
		if HFConvexClip.face_plane(brush.faces[i]).normal.is_equal_approx(Vector3.RIGHT):
			east = i
	var result := HFFacePush.pushed(brush, east, 0.5)
	assert_true(result["ok"], str(result))
	HFFacePush.apply(brush, result)
	assert_eq(brush.shape, DraftBrush.BrushShape.BOX, "a box stays a box, with its handles")
	assert_almost_eq(brush.size, Vector3(2.5, 2, 2), Vector3.ONE * 0.001)
	assert_almost_eq(brush.global_position, Vector3(0.25, 1, 0), Vector3.ONE * 0.001)


func test_a_sloped_face_moves_along_its_normal_and_the_brush_stays_convex():
	var made := _clipped()
	var brush: DraftBrush = made[0]
	var sloped: int = made[1]
	assert_gt(sloped, -1, "fixture: the clip made a sloped face")
	var before := HFFacePush.world_plane(brush, sloped)
	var slots: Array = []
	for face in brush.faces:
		slots.append(face.material_idx)
	var count := brush.faces.size()
	var result := HFFacePush.pushed(brush, sloped, 0.25)
	assert_true(result["ok"], str(result))
	HFFacePush.apply(brush, result)
	assert_eq(brush.faces.size(), count, "the same faces")
	var after := HFFacePush.world_plane(brush, sloped)
	assert_almost_eq(after.normal.dot(before.normal), 1.0, 0.0001, "the face keeps its slope")
	assert_almost_eq(after.d - before.d, 0.25, 0.001, "and is 0.25 further out")
	var now: Array = []
	for face in brush.faces:
		now.append(face.material_idx)
	assert_eq(now, slots, "each face keeps its material, in its place")
	assert_eq(SolidChecks.open_edge_count(brush.faces), 0, "closed")
	assert_true(SolidChecks.is_convex(brush.faces), "convex")
	assert_gt(SolidChecks.outward_ratio(brush.faces), 0.99, "turned out")


func test_a_push_that_would_turn_the_brush_inside_out_stops_short():
	var made := _clipped()
	var brush: DraftBrush = made[0]
	var sloped: int = made[1]
	var result := HFFacePush.pushed(brush, sloped, -10.0)
	assert_false(result["ok"], "ten metres in is through the brush")
	assert_ne(str(result["reason"]), "", "and says why")
	var stop := HFFacePush.farthest(brush, sloped, -10.0)
	assert_lt(stop, 0.0, "it still moves in")
	assert_gt(stop, -10.0, "but stops short")
	assert_true(HFFacePush.pushed(brush, sloped, stop)["ok"], "where it stops holds")
	var box := _box(Vector3(2, 2, 2), Vector3(5, 1, 0))
	assert_false(HFFacePush.pushed(box, 0, -2.5)["ok"], "a box refuses too")


func test_a_push_that_would_squeeze_a_face_out_is_refused():
	# A wedge's top shrinks as it rises; pushed far enough it is gone.
	var made := _clipped()
	var brush: DraftBrush = made[0]
	var top := -1
	for i in brush.faces.size():
		if HFConvexClip.face_plane(brush.faces[i]).normal.is_equal_approx(Vector3.UP):
			top = i
	assert_gt(top, -1, "fixture: the clipped box still has a top")
	assert_false(
		HFFacePush.pushed(brush, top, 5.0)["ok"], "the top would be pushed out of the slope"
	)


func test_the_distance_snaps_to_the_grid_or_to_a_corner_on_a_grid_plane():
	assert_almost_eq(
		HFFacePush.snapped_distance(0.6, PackedVector3Array(), Vector3.UP, 0.5), 0.5, 0.0001
	)
	# A sloped face: its corner at y 1.9 lands on y 2.0 after 0.1 along the up part of the normal.
	var normal := Vector3(0, 1, 1).normalized()
	var corner := PackedVector3Array([Vector3(0, 1.9, 0.0)])
	var landed := HFFacePush.snapped_distance(0.15, corner, normal, 0.5)
	assert_almost_eq(1.9 + normal.y * landed, 2.0, 0.0001, "the corner lands on the grid plane")


func test_coplanar_faces_of_a_wall_of_three_are_found():
	var a := _box(Vector3(2, 3, 0.5), Vector3(0, 1.5, 0))
	var b := _box(Vector3(2, 3, 0.5), Vector3(2, 1.5, 0))
	var c := _box(Vector3(2, 3, 0.5), Vector3(4, 1.5, 0))
	var front := -1
	for i in a.faces.size():
		if HFConvexClip.face_plane(a.faces[i]).normal.is_equal_approx(Vector3.BACK):
			front = i
	var partners := HFFacePush.coplanar_faces(a, front, [a, b, c])
	assert_eq(partners.size(), 2, "the two others")
	var off := _box(Vector3(2, 3, 0.5), Vector3(6, 1.5, 1))
	assert_eq(HFFacePush.coplanar_faces(a, front, [off]).size(), 0, "one out of line is not")


func test_a_push_on_a_scaled_wedge_moves_its_face_the_distance_asked():
	# A push is asked in metres in the level. A wedge the gizmo scaled 1.5 moved
	# its face 1.5 m for 1 m asked, and a snapped drag left it off the grid (#1998).
	var wedge: DraftBrush = root.create_brush_from_info(
		{"shape": DraftBrush.BrushShape.WEDGE, "size": Vector3(2, 2, 2), "center": Vector3(5, 1, 0)}
	)
	wedge.scale = Vector3(1.5, 1.5, 1.5)
	var bottom := -1
	for i in wedge.faces.size():
		if HFFacePush.world_plane(wedge, i).normal.dot(Vector3.DOWN) > 0.99:
			bottom = i
	assert_gt(bottom, -1, "fixture: the wedge has a bottom")
	var before := HFFacePush.world_plane(wedge, bottom)
	var result := HFFacePush.pushed(wedge, bottom, 1.0)
	assert_true(result["ok"], str(result))
	HFFacePush.apply(wedge, result)
	var moved := HFFacePush.world_plane(wedge, bottom).d - before.d
	assert_almost_eq(moved, 1.0, 0.001, "1 m asked, 1 m moved")
	var corners := HFFacePush.world_corners(wedge, bottom)
	var normal := HFFacePush.world_plane(wedge, bottom).normal
	var snapped := HFFacePush.snapped_distance(-0.3, corners, normal, 0.5)
	HFFacePush.apply(wedge, HFFacePush.pushed(wedge, bottom, snapped))
	var y: float = HFFacePush.world_corners(wedge, bottom)[0].y
	assert_almost_eq(y, snappedf(y, 0.5), 0.001, "a snapped drag puts the face on the grid")
