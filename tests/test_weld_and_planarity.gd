extends GutTest

const HFValidationSystem = preload("res://addons/hammerforge/systems/hf_validation_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const MapIO = preload("res://addons/hammerforge/map_io.gd")
const HFVertexWeld = preload("res://addons/hammerforge/hf_vertex_weld.gd")

var root: LevelRoot
var val_sys: HFValidationSystem


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	val_sys = root.validation_system


func after_each():
	root = null
	val_sys = null


func _make_brush(
	parent: Node3D, pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(4, 4, 4)
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.operation = CSGShape3D.OPERATION_UNION
	parent.add_child(b)
	b.global_position = pos
	return b


func _make_quad_face(verts: PackedVector3Array) -> FaceData:
	var f = FaceData.new()
	f.local_verts = verts
	f.ensure_geometry()
	return f


## Assign face list to brush using typed Array[FaceData] to satisfy Godot 4's
## typed property enforcement.  Also sets geometry_dirty = false to prevent
## _rebuild_faces from overwriting the faces on the next frame.
func _set_faces(brush: DraftBrush, face_list: Array) -> void:
	var typed: Array[FaceData] = []
	for f in face_list:
		typed.append(f)
	brush.faces = typed
	brush.geometry_dirty = false


# ===========================================================================
# Non-planar face detection
# ===========================================================================


func test_planar_quad_no_issue():
	var b = _make_brush(root.draft_brushes_node)
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "non_planar":
			found = true
	assert_false(found, "Perfectly planar quad should not be flagged")


func test_non_planar_quad_detected():
	var b = _make_brush(root.draft_brushes_node)
	# Fourth vertex drifts 0.05 units off the XZ plane
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0.05, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "non_planar":
			found = true
	assert_true(found, "Non-planar quad should be flagged")


func test_non_planar_respects_tolerance():
	var b = _make_brush(root.draft_brushes_node)
	# Drift within default tolerance (0.01)
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0.005, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "non_planar":
			found = true
	assert_false(found, "Drift within tolerance should not be flagged")


func test_non_planar_custom_tolerance():
	var b = _make_brush(root.draft_brushes_node)
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0.05, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	# Increase tolerance so 0.05 drift is accepted
	val_sys.planarity_tolerance = 0.1
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "non_planar":
			found = true
	assert_false(found, "Drift within custom tolerance should not be flagged")


func test_triangle_always_planar():
	var b = _make_brush(root.draft_brushes_node)
	var verts := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 2, 0), Vector3(2, 5, 3)])
	_set_faces(b, [_make_quad_face(verts)])
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "non_planar":
			found = true
	assert_false(found, "Triangles are always planar")


# ===========================================================================
# Vertex welding auto-fix
# ===========================================================================


func test_weld_snaps_near_vertices():
	var b = _make_brush(root.draft_brushes_node)
	val_sys.weld_tolerance = 0.01
	# Two faces sharing an edge where vertices are offset by ~0.005
	var f1 = _make_quad_face(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)])
	)
	var f2 = _make_quad_face(
		PackedVector3Array(
			[Vector3(4.005, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(4.005, 4, 0)]
		)
	)
	_set_faces(b, [f1, f2])
	var count = val_sys.weld_brush_vertices(b)
	assert_gt(count, 0, "Should weld near-coincident vertices")
	# After welding, the shared edge vertices should be identical
	assert_almost_eq(
		b.faces[0].local_verts[1].x,
		b.faces[1].local_verts[0].x,
		0.001,
		"Welded vertices should match"
	)


func test_weld_no_change_when_exact():
	var b = _make_brush(root.draft_brushes_node)
	val_sys.weld_tolerance = 0.01
	var f1 = _make_quad_face(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)])
	)
	_set_faces(b, [f1])
	var count = val_sys.weld_brush_vertices(b)
	assert_eq(count, 0, "Already-exact vertices should not be modified")


func test_weld_refreshes_face_geometry():
	var b = _make_brush(root.draft_brushes_node)
	val_sys.weld_tolerance = 0.01
	var f1 = _make_quad_face(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)])
	)
	var f2 = _make_quad_face(
		PackedVector3Array(
			[Vector3(4.005, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(4.005, 4, 0)]
		)
	)
	_set_faces(b, [f1, f2])
	# Corrupt f2's bounds AFTER _set_faces so only a post-weld ensure_geometry()
	# call can restore them.  If the refresh loop at hf_validation_system.gd:520
	# were removed, bounds would still be zeroed out after the weld.
	f2.bounds = AABB()
	assert_eq(f2.bounds.size, Vector3.ZERO, "Pre-weld: bounds must be zeroed for this test")
	val_sys.weld_brush_vertices(b)
	# After welding, ensure_geometry() should have recomputed bounds from the
	# modified local_verts.  f2 spans x=[~4.0025, 8] y=[0, 4] z=0, so bounds
	# size must be non-zero on at least two axes.
	var bounds_after: AABB = b.faces[1].bounds
	assert_gt(
		bounds_after.size.length(),
		0.0,
		"Post-weld bounds must be recomputed — proves ensure_geometry() was called"
	)


# ===========================================================================
# Planarity auto-fix
# ===========================================================================


func test_fix_non_planar_projects_vertex():
	var b = _make_brush(root.draft_brushes_node)
	val_sys.planarity_tolerance = 0.01
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0.05, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	var fixed = val_sys.fix_non_planar_faces(b)
	assert_gt(fixed, 0, "Should fix drifting vertex")
	# The fourth vertex should now be on the Y=0 plane
	assert_almost_eq(b.faces[0].local_verts[3].y, 0.0, 0.001, "Vertex should be projected to plane")


func test_fix_non_planar_preserves_xy():
	var b = _make_brush(root.draft_brushes_node)
	val_sys.planarity_tolerance = 0.01
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0.05, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	val_sys.fix_non_planar_faces(b)
	# X and Z should be unchanged
	assert_almost_eq(b.faces[0].local_verts[3].x, 0.0, 0.001, "X should be preserved")
	assert_almost_eq(b.faces[0].local_verts[3].z, 4.0, 0.001, "Z should be preserved")


func test_fix_non_planar_no_change_when_ok():
	var b = _make_brush(root.draft_brushes_node)
	val_sys.planarity_tolerance = 0.01
	var verts := PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	)
	_set_faces(b, [_make_quad_face(verts)])
	var fixed = val_sys.fix_non_planar_faces(b)
	assert_eq(fixed, 0, "Already-planar face should not be modified")


# ===========================================================================
# Micro-gap detection
# ===========================================================================


func test_micro_gap_detected():
	val_sys.weld_tolerance = 0.01
	var b1 = _make_brush(root.draft_brushes_node)
	var b2 = _make_brush(root.draft_brushes_node)
	# b1 has a face edge at x=4, b2 at x=4.005 — within tolerance
	_set_faces(
		b1,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)]
				)
			)
		]
	)
	_set_faces(
		b2,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(4.005, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(4.005, 4, 0)]
				)
			)
		]
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "micro_gap":
			found = true
	assert_true(found, "Should detect micro-gap between brushes")


func test_no_micro_gap_when_exact():
	val_sys.weld_tolerance = 0.01
	var b1 = _make_brush(root.draft_brushes_node)
	var b2 = _make_brush(root.draft_brushes_node)
	_set_faces(
		b1,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)]
				)
			)
		]
	)
	_set_faces(
		b2,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(4, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(4, 4, 0)]
				)
			)
		]
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "micro_gap":
			found = true
	assert_false(found, "Exactly coincident vertices should not be flagged")


func _micro_gaps() -> Array:
	var found: Array = []
	for issue in val_sys.check_bake_issues():
		if issue["type"] == "micro_gap":
			found.append(issue)
	return found


func _touching_pair(gap: float) -> Array:
	var b1 = _make_brush(root.draft_brushes_node)
	var b2 = _make_brush(root.draft_brushes_node)
	_set_faces(
		b1,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)]
				)
			)
		]
	)
	_set_faces(
		b2,
		[
			_make_quad_face(
				PackedVector3Array(
					[
						Vector3(4 + gap, 0, 0),
						Vector3(8, 0, 0),
						Vector3(8, 4, 0),
						Vector3(4 + gap, 4, 0)
					]
				)
			)
		]
	)
	return [b1, b2]


func test_faces_that_touch_but_for_float_rounding_are_not_a_gap():
	# 4.0000005 is stored as the float after 4.0, 4.8e-7 away: the stair steps of
	# #1058 were that far apart, and nothing a bake or a player sees is there.
	_touching_pair(0.0000005)
	assert_eq(_micro_gaps().size(), 0, "rounding is touching, not a gap")


func test_a_half_millimetre_gap_is_still_a_gap():
	assert_eq(val_sys.weld_tolerance, 0.001, "fixture: the default tolerance")
	_touching_pair(0.0005)
	assert_eq(_micro_gaps().size(), 1, "a real gap under the weld tolerance is still reported")


func test_a_micro_gap_names_both_brushes():
	# The finding is about a pair, so Select and hf_validate need both (#1037).
	var pair := _touching_pair(0.0005)
	var gaps := _micro_gaps()
	assert_eq(gaps.size(), 1)
	if gaps.size() != 1:
		return
	var named := [gaps[0].get("node"), gaps[0].get("other_node")]
	assert_true(named.has(pair[0]), "one of the pair")
	assert_true(named.has(pair[1]), "and the other")


# ===========================================================================
# Edge key is independent of weld_tolerance
# ===========================================================================


func test_edge_key_ignores_weld_tolerance():
	# _edge_key uses fixed 0.001 precision — raising weld_tolerance must NOT
	# collapse distinct edges, which would hide real non-manifold issues.
	val_sys.weld_tolerance = 0.1
	var key_a = val_sys._edge_key(Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0))
	var key_b = val_sys._edge_key(Vector3(1.05, 2.0, 3.0), Vector3(4.0, 5.0, 6.0))
	assert_ne(key_a, key_b, "Edge key must use fixed precision, not weld_tolerance")


# ===========================================================================
# Boundary-straddling pairs must still be caught
# ===========================================================================


func test_micro_gap_across_bucket_boundary():
	# 4.004 and 4.011 are 0.007 apart (within tol=0.01) but straddle the
	# 0.01-grid boundary at 4.01.  A naive single-bucket check would miss them.
	val_sys.weld_tolerance = 0.01
	var b1 = _make_brush(root.draft_brushes_node)
	var b2 = _make_brush(root.draft_brushes_node)
	_set_faces(
		b1,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(0, 0, 0), Vector3(4.004, 0, 0), Vector3(4.004, 4, 0), Vector3(0, 4, 0)]
				)
			)
		]
	)
	_set_faces(
		b2,
		[
			_make_quad_face(
				PackedVector3Array(
					[Vector3(4.011, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(4.011, 4, 0)]
				)
			)
		]
	)
	var issues = val_sys.check_bake_issues()
	var found := false
	for issue in issues:
		if issue["type"] == "micro_gap":
			found = true
	assert_true(found, "Must detect micro-gap even when vertices straddle a bucket boundary")


func test_weld_across_bucket_boundary():
	# Same boundary-straddling scenario but for the weld auto-fix
	val_sys.weld_tolerance = 0.01
	var b = _make_brush(root.draft_brushes_node)
	var f1 = _make_quad_face(
		PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(4.004, 0, 0), Vector3(4.004, 4, 0), Vector3(0, 4, 0)]
		)
	)
	var f2 = _make_quad_face(
		PackedVector3Array(
			[Vector3(4.011, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(4.011, 4, 0)]
		)
	)
	_set_faces(b, [f1, f2])
	var count = val_sys.weld_brush_vertices(b)
	assert_gt(count, 0, "Should weld vertices that straddle a bucket boundary")
	assert_almost_eq(
		b.faces[0].local_verts[1].x,
		b.faces[1].local_verts[0].x,
		0.0001,
		"Boundary-straddling vertices should converge after weld"
	)


func test_snap_parsed_vertices_across_boundary():
	# MapIO must also handle boundary-straddling
	var faces: Array = [
		{"points": [Vector3(4.004, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0)]},
		{"points": [Vector3(4.011, 0, 0), Vector3(0, 0, 0), Vector3(0, 4, 0)]}
	]
	MapIO._snap_parsed_vertices(faces, 0.01)
	var v1: Vector3 = faces[0]["points"][0]
	var v2: Vector3 = faces[1]["points"][0]
	assert_almost_eq(v1.x, v2.x, 0.0001, "Boundary-straddling parse vertices should be welded")


# ===========================================================================
# MapIO integration: parse_map_text actually invokes welding
# ===========================================================================


func test_parse_map_text_welding_changes_brush_center():
	# To prove parse_map_text's weld hook at map_io.gd:78 actually runs, we
	# construct a brush where the drifting vertex is the SOLE min_x contributor.
	# Every other point has x >= 2, so when the drift vertex (1.992) gets welded
	# to avg(1.992, 2.0) = 1.996, the bounding-box min_x shifts from 1.992 to
	# 1.996, changing the center.  Without welding, min_x stays at 1.992.
	#
	# Face 1 plane points: (2,0,0) (2,4,0) (2,0,4) — all at x=2
	# Face 2 plane points: (1.992,0,0) (6,0,0) (6,4,0) — 1.992 is sole min_x
	# The 1.992 is within 0.01 of the 2.0 vertices on face 1.
	var map_text := '{\n"classname" "worldspawn"\n{\n'
	map_text += "( 2 0 0 ) ( 2 4 0 ) ( 2 0 4 ) __default 0 0 0 1 1\n"
	map_text += "( 1.992 0 0 ) ( 6 0 0 ) ( 6 4 0 ) __default 0 0 0 1 1\n"
	map_text += "}\n}\n"

	# Parse with welding enabled
	MapIO.import_weld_tolerance = 0.01
	var result_on = MapIO.parse_map_text(map_text)

	# Parse with welding disabled
	MapIO.import_weld_tolerance = 0.0
	var result_off = MapIO.parse_map_text(map_text)

	# Reset
	MapIO.import_weld_tolerance = 0.01

	assert_eq(result_on["brushes"].size(), 1, "Should parse one brush (weld on)")
	assert_eq(result_off["brushes"].size(), 1, "Should parse one brush (weld off)")

	var center_on: Vector3 = result_on["brushes"][0]["center"]
	var center_off: Vector3 = result_off["brushes"][0]["center"]
	# Without welding: min_x = 1.992, center_x = (1.992 + 6) / 2 = 3.996
	# With welding:    min_x ~ 1.996, center_x = (1.996 + 6) / 2 = 3.998
	# The x-components must differ, proving the weld hook ran.
	assert_ne(
		center_on,
		center_off,
		"Brush center must differ between weld-on and weld-off, proving welding ran"
	)


func test_parse_map_text_no_weld_when_disabled():
	var map_text := '{\n"classname" "worldspawn"\n{\n'
	map_text += "( 0 0 0 ) ( 4 0 0 ) ( 4 4 0 ) __default 0 0 0 1 1\n"
	map_text += "( 4.005 0 0 ) ( 8 0 0 ) ( 8 4 0 ) __default 0 0 0 1 1\n"
	map_text += "}\n}\n"

	MapIO.import_weld_tolerance = 0.0
	var result = MapIO.parse_map_text(map_text)
	MapIO.import_weld_tolerance = 0.01

	assert_false(result.is_empty(), "Should parse successfully even without welding")
	assert_true(result.has("brushes"), "Should have brushes key")


# ===========================================================================
# MapIO unit: _snap_parsed_vertices
# ===========================================================================


func test_snap_parsed_vertices_averages_cluster():
	var faces: Array = [
		{"points": [Vector3(4.0, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0)]},
		{"points": [Vector3(4.008, 0, 0), Vector3(0, 0, 0), Vector3(0, 4, 0)]}
	]
	MapIO._snap_parsed_vertices(faces, 0.01)
	# Both references to ~4.0 should now be identical
	var v1: Vector3 = faces[0]["points"][0]
	var v2: Vector3 = faces[1]["points"][0]
	assert_almost_eq(v1.x, v2.x, 0.0001, "Snapped vertices should be equal")
	# Average of 4.0 and 4.008 = 4.004
	assert_almost_eq(v1.x, 4.004, 0.001, "Should be averaged to midpoint")


func test_snap_parsed_vertices_no_change_for_distant():
	var faces: Array = [
		{"points": [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0)]},
		{"points": [Vector3(8, 0, 0), Vector3(12, 0, 0), Vector3(12, 4, 0)]}
	]
	MapIO._snap_parsed_vertices(faces, 0.01)
	# Distant vertices should be unchanged
	assert_eq(faces[0]["points"][1], Vector3(4, 0, 0), "Distant vertex should not move")
	assert_eq(faces[1]["points"][0], Vector3(8, 0, 0), "Distant vertex should not move")


# ===========================================================================
# One weld for the import and the fix (#1454)
# ===========================================================================


## A brush whose only near pair is face 1's first point and face 2's first
## point, on x, so a weld shows up as the brush moving.
func _straddle_map(face_one_x: String, face_two_x: String) -> String:
	var text := '{\n"classname" "worldspawn"\n{\n'
	text += (
		"( %s 0 0 ) ( %s 4 0 ) ( %s 0 4 ) __default 0 0 0 1 1\n"
		% [face_one_x, face_one_x, face_one_x]
	)
	text += "( %s 0 0 ) ( 6 0 0 ) ( 6 4 0 ) __default 0 0 0 1 1\n" % face_two_x
	text += "}\n}\n"
	return text


func test_import_welds_a_pair_straddling_a_cell_at_a_tenth():
	# A tenth is not a binary fraction, so the cells are not exact in a float.
	# 2.04 and 2.06 fall either side of the 2.05 boundary, 0.02 apart, which is
	# well inside the tolerance and has to weld like any other pair.
	var before := MapIO.import_weld_tolerance
	MapIO.import_weld_tolerance = 0.1
	var welded = MapIO.parse_map_text(_straddle_map("2.06", "2.04"))
	var joined = MapIO.parse_map_text(_straddle_map("2.05", "2.05"))
	MapIO.import_weld_tolerance = 0.0
	var unwelded = MapIO.parse_map_text(_straddle_map("2.06", "2.04"))
	MapIO.import_weld_tolerance = before
	assert_eq(welded["brushes"].size(), 1, "One brush with the weld on")
	assert_eq(joined["brushes"].size(), 1, "One brush already joined")
	assert_eq(unwelded["brushes"].size(), 1, "One brush with the weld off")
	var at: Vector3 = welded["brushes"][0]["center"]
	assert_almost_eq(
		at,
		joined["brushes"][0]["center"] as Vector3,
		Vector3(1e-4, 1e-4, 1e-4),
		"The straddling pair imports as the pair already joined at its middle"
	)
	assert_almost_ne(
		at,
		unwelded["brushes"][0]["center"] as Vector3,
		Vector3(1e-4, 1e-4, 1e-4),
		"and not as the pair left apart, so this tells the two cases apart"
	)


func test_weld_fix_welds_a_pair_straddling_a_cell_at_a_tenth():
	val_sys.weld_tolerance = 0.1
	var b = _make_brush(root.draft_brushes_node)
	var f1 = _make_quad_face(
		PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(2.04, 0, 0), Vector3(2.04, 4, 0), Vector3(0, 4, 0)]
		)
	)
	var f2 = _make_quad_face(
		PackedVector3Array(
			[Vector3(2.06, 0, 0), Vector3(8, 0, 0), Vector3(8, 4, 0), Vector3(2.06, 4, 0)]
		)
	)
	_set_faces(b, [f1, f2])
	assert_eq(val_sys.weld_brush_vertices(b), 4, "Both straddling pairs weld")
	for v in [b.faces[0].local_verts[1], b.faces[1].local_verts[0]]:
		assert_almost_eq((v as Vector3).x, 2.05, 1e-5, "and meet at their middle")


func test_import_and_weld_fix_join_the_same_points():
	# The user's job: import a file or run the fix, and the same corners join in
	# the same places. A chain (each link inside the tolerance, the ends not), a
	# pair straddling a cell boundary, a pair across zero and a lone point.
	var tol := 0.1
	var rings: Array = [
		[Vector3(0, 0, 0), Vector3(0.08, 0, 0), Vector3(0.16, 0, 0)],
		[Vector3(2.04, 1, 1), Vector3(2.06, 1, 1), Vector3(5, 5, 5)],
		[Vector3(-0.06, 3, 0), Vector3(0.02, 3, 0), Vector3(-7, 2, 9)],
	]
	var parsed: Array = []
	var faces: Array = []
	for ring in rings:
		parsed.append({"points": (ring as Array).duplicate()})
		var face := FaceData.new()
		face.local_verts = PackedVector3Array(ring)
		faces.append(face)
	MapIO._snap_parsed_vertices(parsed, tol)
	val_sys.weld_tolerance = tol
	var b = _make_brush(root.draft_brushes_node)
	_set_faces(b, faces)
	val_sys.weld_brush_vertices(b)
	for fi in rings.size():
		for pi in (rings[fi] as Array).size():
			assert_eq(
				b.faces[fi].local_verts[pi],
				parsed[fi]["points"][pi] as Vector3,
				"Face %d corner %d lands in the same place both ways" % [fi, pi]
			)
	assert_almost_eq(
		parsed[0]["points"][2] as Vector3,
		Vector3(0.08, 0, 0),
		Vector3(1e-5, 1e-5, 1e-5),
		"The chain joins end to end through its middle link"
	)
	assert_eq(parsed[1]["points"][2], Vector3(5, 5, 5), "A lone point stays put")


# ===========================================================================
# HFVertexWeld: the clustering both of them use
# ===========================================================================


func test_cluster_chains_points_through_their_neighbours():
	var points := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.08, 0, 0), Vector3(0.16, 0, 0)])
	var groups: Array = HFVertexWeld.cluster(points, 0.1)
	assert_eq(groups.size(), 1, "The ends are 0.16 apart but join through the middle")
	assert_eq(groups[0], PackedInt32Array([0, 1, 2]), "lowest index first, then as reached")


func test_cluster_leaves_out_points_with_nothing_in_reach():
	var points := PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5.05, 0, 0)])
	var groups: Array = HFVertexWeld.cluster(points, 0.1)
	assert_eq(groups.size(), 1, "Only the near pair is a group")
	assert_eq(groups[0], PackedInt32Array([1, 2]), "and the lone point is in none")


func test_cluster_joins_a_pair_straddling_a_cell_on_every_axis():
	# 2.04 and 2.06 fall in different cells at 0.1, on all three axes at once, so
	# only a look into the corner neighbour finds the other one.
	var a := Vector3(2.04, -2.04, 2.04)
	var b := Vector3(2.06, -2.06, 2.06)
	assert_ne(HFVertexWeld.cell(a, 0.1), HFVertexWeld.cell(b, 0.1), "They straddle a corner")
	var groups: Array = HFVertexWeld.cluster(PackedVector3Array([a, b]), 0.1)
	assert_eq(groups.size(), 1, "and still join")


func test_cluster_with_no_tolerance_joins_nothing():
	var points := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	assert_eq(HFVertexWeld.cluster(points, 0.0).size(), 0, "Zero joins nothing")
	assert_eq(HFVertexWeld.cluster(points, -1.0).size(), 0, "nor does a negative")
	assert_eq(HFVertexWeld.cluster(points, NAN).size(), 0, "nor a number that is not one")


func test_average_is_the_mean_of_the_group():
	var points := PackedVector3Array([Vector3(9, 9, 9), Vector3(1, 0, 0), Vector3(3, 0, 0)])
	assert_eq(
		HFVertexWeld.average(points, PackedInt32Array([1, 2])),
		Vector3(2, 0, 0),
		"Only the group's points count"
	)
