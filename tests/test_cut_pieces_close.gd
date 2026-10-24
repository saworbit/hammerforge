extends GutTest

## Hull and carve made brushes that were not closed solids (#1843). They drew,
## but a level restore leaves out a custom brush whose faces do not close
## (#1769), so a redo of the step, or a save and a reload, dropped them.
##
## The hull took a corner 0.008 off a long thin face's plane as on it, and came
## out with faces that were not flat and overlapped. A carve whose cutter face
## lined up with a ring of the brush's edges left a corner out of its cap, since
## no face around that corner crossed the cut.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFHull = preload("res://addons/hammerforge/hf_hull.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, brush_id: String, size: Vector3, at: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
			}
		)
	)


static func _corners_of_box(center: Vector3, size: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				out.append(center + size * Vector3(x, y, z))
	return out


static func _open_edges(faces: Array) -> int:
	var rings: Array = []
	for face in faces:
		rings.append(face.local_verts)
	return HFSolidMeasure.open_edge_count(rings)


## The farthest any face's corner sits off that face's own plane.
static func _worst_off_plane(faces: Array) -> float:
	var worst := 0.0
	for face in faces:
		var plane := Plane(face.normal, face.local_verts[0])
		for corner in face.local_verts:
			worst = maxf(worst, absf(plane.distance_to(corner)))
	return worst


func test_the_hull_of_a_small_box_far_from_a_big_one_is_closed_and_flat():
	var points := _corners_of_box(Vector3(-6.5, 1.5, 8.125), Vector3(0.5, 0.5, 0.25))
	points.append_array(_corners_of_box(Vector3(0.5, 1.5, 3.5), Vector3.ONE))
	var hull: Dictionary = HFHull.of(points)
	assert_true(hull["ok"])
	assert_eq(_open_edges(hull["faces"]), 0, "every edge on two faces")
	assert_lt(_worst_off_plane(hull["faces"]), HFHull.ON_FACE, "every face flat")
	assert_eq(hull["faces"].size(), 12)


## Four roof faces a fraction of a degree off level, all through the one peak:
## each has the same distance from the origin, so comparing normals and distances
## took them for one face and left three holes.
func test_a_low_peak_over_a_wide_box_gives_four_roof_faces():
	var points := _corners_of_box(Vector3(0, 0.5, 0), Vector3(10, 1, 10))
	points.append(Vector3(0, 1.02, 0))
	var hull: Dictionary = HFHull.of(points)
	assert_true(hull["ok"])
	assert_eq(hull["faces"].size(), 9, "the bottom, four sides and four roof faces")
	assert_eq(_open_edges(hull["faces"]), 0, "every edge on two faces")


## A cut at x = -5.5 of the hull of a 2 x 3 x 4 box and a 2 x 2 x 1 box. The tall
## box's top and far side end on that plane and the slope down to the small box
## begins there, so the corner where the three meet is on the cut and no face
## around it crosses.
func test_a_cut_lined_up_with_a_ring_of_edges_keeps_every_corner():
	var points := _corners_of_box(Vector3(-6.5, 0, -0.5), Vector3(2, 3, 4))
	points.append_array(_corners_of_box(Vector3(6.5, -0.5, 2), Vector3(2, 2, 1)))
	var faces: Array = HFHull.of(points)["faces"]
	var halves: Dictionary = HFConvexClip.split(faces, Plane(Vector3.RIGHT, -5.5))
	assert_false(halves["front"].is_empty())
	assert_false(halves["back"].is_empty())
	assert_eq(_open_edges(halves["front"]), 0, "the slope side closes")
	assert_eq(_open_edges(halves["back"]), 0, "the box side closes")


func test_carving_a_hull_gives_pieces_a_restore_keeps():
	var root := _fresh_root()
	_box(root, "tall", Vector3(2, 3, 4), Vector3(-7, 1.5, -1))
	_box(root, "small", Vector3(2, 2, 1), Vector3(6, 1, 1.5))
	var hulled: HFOpResult = root.hull_brushes_by_ids(["tall", "small"])
	assert_true(hulled.ok, hulled.message)
	_box(root, "cutter", Vector3(4, 1, 4), Vector3(-8, 3, -1))
	var carved: HFOpResult = root.carve_with_brush("cutter")
	assert_true(carved.ok, carved.message)
	var ids: Array = []
	for brush in root._iter_managed_brush_nodes():
		ids.append(str(brush.brush_id))
		assert_eq(_open_edges(brush.faces), 0, "%s closes" % brush.brush_id)
	ids.sort()
	assert_gt(ids.size(), 2, "the hull came apart in pieces")
	# What a redo of the carve does: the level put back from a capture of it.
	root.restore_state(root.capture_state())
	var kept: Array = []
	for brush in root._iter_managed_brush_nodes():
		kept.append(str(brush.brush_id))
	kept.sort()
	assert_eq(kept, ids, "a restore leaves none of the pieces out")
