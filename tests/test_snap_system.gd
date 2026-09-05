extends GutTest

const HFSnapSystem = preload("res://addons/hammerforge/hf_snap_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var snap: HFSnapSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	snap = HFSnapSystem.new(root)


func after_each():
	root = null
	snap = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var preview_brush: Node3D

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out
"""
	s.reload()
	return s


func _make_brush(pos: Vector3, sz: Vector3, brush_id: String) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.brush_id = brush_id
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	return b


# ===========================================================================
# Mode toggle
# ===========================================================================


func test_default_mode_is_grid():
	assert_true(snap.is_mode_on(HFSnapSystem.SnapMode.GRID))
	assert_false(snap.is_mode_on(HFSnapSystem.SnapMode.VERTEX))
	assert_false(snap.is_mode_on(HFSnapSystem.SnapMode.CENTER))
	assert_false(snap.is_mode_on(HFSnapSystem.SnapMode.EDGE))
	assert_false(snap.is_mode_on(HFSnapSystem.SnapMode.PERPENDICULAR))


func test_set_mode_on_off():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	assert_true(snap.is_mode_on(HFSnapSystem.SnapMode.VERTEX))
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, false)
	assert_false(snap.is_mode_on(HFSnapSystem.SnapMode.VERTEX))


# ===========================================================================
# Grid snap (backwards compat)
# ===========================================================================


func test_grid_snap_default():
	var result = snap.snap_point(Vector3(17, 5, 23), 16.0)
	assert_eq(result, Vector3(16, 0, 16))


func test_no_modes_passthrough():
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var point = Vector3(17.3, 5.7, 23.1)
	var result = snap.snap_point(point, 16.0)
	assert_eq(result, point)


func test_grid_snap_zero_passthrough():
	var point = Vector3(17.3, 5.7, 23.1)
	var result = snap.snap_point(point, 0.0)
	assert_eq(result, point)


# ===========================================================================
# Vertex snap
# ===========================================================================


func test_vertex_snap_to_corner():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	# Brush at origin, size 32 — corner at (16, 16, 16)
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var result = snap.snap_point(Vector3(15.5, 15.5, 15.5), 0.0)
	assert_eq(result, Vector3(16, 16, 16))


func test_vertex_snap_threshold():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	snap.snap_threshold = 1.0
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b2")
	# Point is 10+ units from any corner — should not snap
	var point = Vector3(5, 5, 5)
	var result = snap.snap_point(point, 0.0)
	assert_eq(result, point)


# ===========================================================================
# Center snap
# ===========================================================================


func test_edge_snap_to_midpoint():
	snap.set_mode(HFSnapSystem.SnapMode.EDGE, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	# Brush at origin, size 32 — +X face vertical edge midpoint at (16, 0, 16)
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "e1")
	var result = snap.snap_point(Vector3(16.4, 0.3, 16.2), 0.0)
	assert_eq(result, Vector3(16, 0, 16))


func test_perp_snaps_onto_edge_segment_not_midpoint():
	snap.set_mode(HFSnapSystem.SnapMode.PERPENDICULAR, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	# Box at origin, size 32. +X/+Y edge runs along Z at (16, 16, -16..16).
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "perp1")
	# Midpoint of that edge is (16, 16, 0). A point at z=8 should drop onto
	# the segment at (16, 16, 8), not the midpoint.
	var result = snap.snap_point(Vector3(16.3, 16.2, 8.0), 0.0)
	assert_eq(result, Vector3(16, 16, 8))


func test_perp_and_grid_perp_wins_inside_threshold():
	snap.set_mode(HFSnapSystem.SnapMode.GRID, true)
	snap.set_mode(HFSnapSystem.SnapMode.PERPENDICULAR, true)
	snap.snap_threshold = 2.0
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "perp2")
	# Grid-16 would pull (16.4, 16.3, 8) toward (16, 16, 16) or (16, 16, 0).
	# Perp drop onto the Z-edge is closer.
	var result = snap.snap_point(Vector3(16.4, 16.3, 8.0), 16.0)
	assert_eq(result, Vector3(16, 16, 8))


func test_center_snap():
	snap.set_mode(HFSnapSystem.SnapMode.CENTER, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	_make_brush(Vector3(100, 0, 100), Vector3(32, 32, 32), "c1")
	var result = snap.snap_point(Vector3(100.5, 0.5, 100.5), 0.0)
	assert_eq(result, Vector3(100, 0, 100))


# ===========================================================================
# Exclude list
# ===========================================================================


func test_exclude_brush():
	snap.set_mode(HFSnapSystem.SnapMode.CENTER, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	_make_brush(Vector3(10, 0, 10), Vector3(32, 32, 32), "ex1")
	# Exclude the only brush — should passthrough
	var point = Vector3(10.5, 0.5, 10.5)
	var result = snap.snap_point(point, 0.0, ["ex1"])
	assert_eq(result, point)


# ===========================================================================
# Priority: closer geometry wins over grid
# ===========================================================================


func test_vertex_beats_grid_when_closer():
	snap.set_mode(HFSnapSystem.SnapMode.GRID, true)
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	# Brush corner at (16, 16, 16)
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "p1")
	# Point at (15.9, 15.9, 15.9) — closer to corner (16,16,16) than grid (16,16,16)
	# Both snap to same point in this case, so let's use a non-grid-aligned brush
	_make_brush(Vector3(3, 3, 3), Vector3(10, 10, 10), "p2")
	# Corner at (3+5, 3+5, 3+5) = (8, 8, 8) — not on 16-grid
	var result = snap.snap_point(Vector3(7.5, 7.5, 7.5), 16.0)
	# (8,8,8) is 0.87 away, grid (0,0,0) is 13 away — vertex wins
	assert_eq(result, Vector3(8, 8, 8))


func test_empty_scene_grid_only():
	# No brushes — vertex/center enabled but no candidates, grid still works
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.CENTER, true)
	var result = snap.snap_point(Vector3(17, 5, 23), 16.0)
	assert_eq(result, Vector3(16, 0, 16))


# ===========================================================================
# Preview brush exclusion
# ===========================================================================


func test_preview_brush_excluded_from_vertex_snap():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	# Create a brush and mark it as the preview
	var preview = _make_brush(Vector3(10, 0, 10), Vector3(4, 4, 4), "preview1")
	root.preview_brush = preview
	# Point near preview corner — should NOT snap to it
	var point = Vector3(11.5, 1.5, 11.5)
	var result = snap.snap_point(point, 0.0)
	assert_eq(result, point, "Should not snap to preview brush corners")


func test_preview_brush_excluded_from_center_snap():
	snap.set_mode(HFSnapSystem.SnapMode.CENTER, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var preview = _make_brush(Vector3(10, 0, 10), Vector3(4, 4, 4), "preview2")
	root.preview_brush = preview
	var point = Vector3(10.5, 0.5, 10.5)
	var result = snap.snap_point(point, 0.0)
	assert_eq(result, point, "Should not snap to preview brush center")


func test_non_preview_brush_still_snaps_with_preview_present():
	snap.set_mode(HFSnapSystem.SnapMode.CENTER, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var preview = _make_brush(Vector3(50, 0, 50), Vector3(4, 4, 4), "preview3")
	root.preview_brush = preview
	# A real brush should still be snappable
	_make_brush(Vector3(10, 0, 10), Vector3(4, 4, 4), "real1")
	var result = snap.snap_point(Vector3(10.5, 0.5, 10.5), 0.0)
	assert_eq(result, Vector3(10, 0, 10), "Should still snap to non-preview brushes")


# ===========================================================================
# Brush rotation and brush shape
# ===========================================================================


func _assert_vector_near(actual: Vector3, expected: Vector3, msg: String) -> void:
	assert_almost_eq(actual.x, expected.x, 0.01, msg)
	assert_almost_eq(actual.y, expected.y, 0.01, msg)
	assert_almost_eq(actual.z, expected.z, 0.01, msg)


func test_vertex_snap_follows_brush_rotation():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "rot")
	b.rotation = Vector3(0, deg_to_rad(45.0), 0)
	# The (16, 16, 16) corner turns 45 degrees about Y onto the X axis.
	var rotated_corner: Vector3 = b.global_transform * Vector3(16, 16, 16)
	_assert_vector_near(rotated_corner, Vector3(22.627, 16, 0), "Fixture sanity")

	var result: Vector3 = snap.snap_point(rotated_corner + Vector3(0.4, 0, 0.3), 0.0)

	_assert_vector_near(result, rotated_corner, "Vertex snap should track the rotated corner")


func test_vertex_snap_ignores_the_unrotated_corner_position():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "rot2")
	b.rotation = Vector3(0, deg_to_rad(45.0), 0)
	# Nothing sits near (16, 16, 16) once the brush is turned. A query just off
	# that spot used to be pulled onto a corner in empty air.
	var query := Vector3(15.5, 15.5, 15.5)

	assert_eq(snap.snap_point(query, 0.0), query, "There is no corner left at the world offset")


func test_edge_snap_follows_brush_rotation():
	snap.set_mode(HFSnapSystem.SnapMode.EDGE, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "rot3")
	b.rotation = Vector3(0, deg_to_rad(45.0), 0)
	var midpoint: Vector3 = b.global_transform * Vector3(16, 0, 16)

	var result: Vector3 = snap.snap_point(midpoint + Vector3(0.3, 0.2, 0.1), 0.0)

	_assert_vector_near(result, midpoint, "Edge midpoints should turn with the brush")


func test_vertex_snap_uses_face_vertices_not_the_size_box():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "dented")
	# A CUSTOM brush is described by its faces, the way a polygon, path or merged
	# brush is. Pull one corner in: the brush still reports size 32, but no
	# geometry reaches the old corner any more.
	b.shape = DraftBrush.BrushShape.CUSTOM
	for face in b.faces:
		var updated := PackedVector3Array()
		for v in face.local_verts:
			updated.append(Vector3(4, 4, 4) if v.is_equal_approx(Vector3(16, 16, 16)) else v)
		face.local_verts = updated
		face.ensure_geometry()

	_assert_vector_near(
		snap.snap_point(Vector3(4.4, 4.2, 4.1), 0.0),
		Vector3(4, 4, 4),
		"The moved corner is a real vertex and should be a snap target"
	)
	assert_eq(
		snap.snap_point(Vector3(16, 16, 16), 0.0),
		Vector3(16, 16, 16),
		"The corner the brush no longer has should not be a snap target"
	)


func test_tessellated_primitive_falls_back_to_its_bounding_box():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "cyl")
	b.shape = DraftBrush.BrushShape.CYLINDER
	assert_gt(
		b.faces.size(),
		HFSnapSystem.MAX_SNAP_FACES,
		"A cylinder carries one face per triangle, which is what the cap is for"
	)

	assert_eq(
		snap.snap_point(Vector3(15.6, 15.6, 15.6), 0.0),
		Vector3(16, 16, 16),
		"Tessellated primitives keep the bounding box corners they always had"
	)


func test_bounding_box_fallback_still_follows_rotation():
	snap.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap.set_mode(HFSnapSystem.SnapMode.GRID, false)
	var b := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "cyl_rot")
	b.shape = DraftBrush.BrushShape.CYLINDER
	b.rotation = Vector3(0, deg_to_rad(45.0), 0)
	var rotated_corner: Vector3 = b.global_transform * Vector3(16, 16, 16)

	_assert_vector_near(
		snap.snap_point(rotated_corner + Vector3(0.3, 0, 0.2), 0.0),
		rotated_corner,
		"The fallback box should be oriented, not world aligned"
	)
