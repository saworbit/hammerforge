extends GutTest

const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const PathSweep = preload("res://addons/hammerforge/hf_path_sweep.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")

## How near two positions in metres have to be to count as the same.
const EPS := 0.0001


class PlacementRoot:
	extends Node3D

	var raycast_result: Dictionary = {}
	var snap_calls := 0
	var raycast_calls := 0
	var y_plane_calls := 0

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		snap_calls += 1
		return point.snapped(Vector3(4, 4, 4))

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		raycast_calls += 1
		return raycast_result

	func screen_ray_to_y_plane(_camera: Camera3D, _mouse_pos: Vector2, y: float) -> Vector3:
		y_plane_calls += 1
		return Vector3(0, y, 0)


func test_placement_uses_level_root_snap_and_raycast():
	# The tool has no raycast of its own any more. A click has to reach
	# LevelRoot for picking, and LevelRoot for snapping.
	var tool = HFPathTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(3, 7, 9)}
	assert_eq(tool.snap_point(Vector3(3, 7, 9)), Vector3(4, 8, 8))
	assert_eq(tool._handle_click(camera, Vector2(20, 30)), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(root.raycast_calls, 1, "LevelRoot owns visual and physics picking")
	assert_eq(tool._waypoints.size(), 1, "The picked point becomes the first point")
	assert_eq(tool._waypoints[0], Vector3(4, 8, 8), "and it is snapped by LevelRoot")
	root.free()
	camera.free()


func test_a_raycast_miss_places_nothing():
	var tool = HFPathTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {}
	assert_eq(tool._handle_click(camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(root.raycast_calls, 1, "a shared raycast miss stays a miss")
	assert_eq(tool._waypoints.size(), 0, "and nothing is placed")
	root.free()
	camera.free()


func test_later_points_come_off_the_shared_y_plane_projection():
	var tool = HFPathTool.new()
	var root := PlacementRoot.new()
	var camera := Camera3D.new()
	tool.root = root
	root.raycast_result = {"position": Vector3(3, 7, 9)}
	tool._handle_click(camera, Vector2(20, 30))
	tool._handle_click(camera, Vector2(40, 50))
	assert_eq(root.raycast_calls, 1, "Only the first point is picked against geometry")
	assert_eq(root.y_plane_calls, 1, "The rest come off LevelRoot's y plane projection")
	root.free()
	camera.free()


# ===========================================================================
# Tool metadata
# ===========================================================================


func test_tool_id():
	var tool = HFPathTool.new()
	assert_eq(tool.tool_id(), 103)


func test_tool_name():
	var tool = HFPathTool.new()
	assert_eq(tool.tool_name(), "Path")


func test_shortcut_key():
	var tool = HFPathTool.new()
	assert_eq(tool.tool_shortcut_key(), KEY_SEMICOLON)


func test_settings_schema():
	var tool = HFPathTool.new()
	var schema = tool.get_settings_schema()
	assert_gte(schema.size(), 3, "Should have width, height, miter + extra settings")
	var names = []
	for s in schema:
		names.append(s.name)
	assert_has(names, "path_width")
	assert_has(names, "path_height")
	assert_has(names, "miter_joints")
	assert_has(names, "path_side")


# ===========================================================================
# Segment brush construction
# ===========================================================================


func test_build_segment_brush_straight():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "grp1")
	assert_false(info.is_empty(), "Should produce a brush info dict")
	assert_eq(info.group_id, "grp1")
	assert_true(info.has("faces"), "Should have face data")
	assert_eq(info.faces.size(), 6, "Segment brush should have 6 faces (box)")


func test_build_segment_brush_diagonal():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 10), 4.0, 4.0, "grp2")
	assert_false(info.is_empty(), "Diagonal segment should produce a brush")
	assert_eq(info.faces.size(), 6)


func test_build_segment_brush_zero_length():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(0, 0, 0), 4.0, 4.0, "grp3")
	assert_true(info.is_empty(), "Zero-length segment should return empty")


func test_segment_center_is_midpoint():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(20, 0, 0), 4.0, 8.0, "grp4")
	assert_almost_eq(info.center.x, 10.0, 0.01, "Center X should be midpoint")
	assert_almost_eq(info.center.y, 4.0, 0.01, "Center Y should be ground + half_h")
	assert_almost_eq(info.center.z, 0.0, 0.01, "Center Z should be midpoint")


func test_segment_size():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(20, 0, 0), 6.0, 8.0, "grp5")
	assert_almost_eq(info.size.x, 20.0, 0.01, "Size X should be segment length")
	assert_almost_eq(info.size.y, 8.0, 0.01, "Size Y should be height")
	assert_almost_eq(info.size.z, 6.0, 0.01, "Size Z should be width")


# ===========================================================================
# Mitred corners (#1412): each segment one piece, cut on its corners' bisectors
# ===========================================================================


## The wall piece each segment of `points` builds, as brush infos, without a
## level: the geometry `_build_path()` hands over.
func _pieces(points: Array, settings: Dictionary = {}, closed := false) -> Array:
	var tool = HFPathTool.new()
	for key in settings:
		tool.set_setting(key, settings[key])
	tool._waypoints = PackedVector3Array(points)
	tool._closed = closed
	var width: float = tool.get_setting("path_width")
	var height: float = tool.get_setting("path_height")
	return tool._band_pieces(tool._band_for(width), height, width, "grp")


## An info's faces with their corners in world space.
func _world_faces(info: Dictionary) -> Array:
	var out: Array = []
	for face_dict in info.faces:
		var face = FaceData.from_dict(face_dict)
		var verts := PackedVector3Array()
		for v in face.local_verts:
			verts.append(v + info.center)
		face.local_verts = verts
		face.ensure_geometry()
		out.append(face)
	return out


## The faces lying wholly in the vertical plane through `point` facing `normal`
## either way.
func _faces_on(faces: Array, point: Vector3, normal: Vector3) -> Array:
	var out: Array = []
	for face: FaceData in faces:
		var on := true
		for v in face.local_verts:
			if absf(normal.dot(v - point)) > EPS:
				on = false
				break
		if on:
			out.append(face)
	return out


## Whether two faces have the same corners, in any order.
func _same_corners(a: FaceData, b: FaceData) -> bool:
	if a.local_verts.size() != b.local_verts.size():
		return false
	for v in a.local_verts:
		var found := false
		for w in b.local_verts:
			if v.distance_to(w) < EPS:
				found = true
				break
		if not found:
			return false
	return true


## The top face's corners in X and Z.
func _top_ring(faces: Array) -> PackedVector2Array:
	for face: FaceData in faces:
		if face.normal.y > 0.9:
			var ring := PackedVector2Array()
			for v in face.local_verts:
				ring.append(Vector2(v.x, v.z))
			return ring
	return PackedVector2Array()


static func _area(ring: PackedVector2Array) -> float:
	var twice := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		twice += a.x * b.y - b.x * a.y
	return absf(twice) * 0.5


## How much of one footprint lies over another, summed over every pair.
func _overlap(face_sets: Array) -> float:
	var total := 0.0
	for i in face_sets.size():
		for j in range(i + 1, face_sets.size()):
			var a := _top_ring(face_sets[i])
			var b := _top_ring(face_sets[j])
			for piece in Geometry2D.intersect_polygons(a, b):
				total += _area(piece)
	return total


## Convex, and every face wound clockwise from outside, which is what its normal
## is read from.
func _assert_convex_and_outward(faces: Array, note: String) -> void:
	var interior := HFConvexClip.interior_point(faces)
	assert_true(HFConvexClip.is_convex_solid(faces, interior), "%s: convex" % note)
	for face: FaceData in faces:
		var centre := Vector3.ZERO
		for v in face.local_verts:
			centre += v
		centre /= float(face.local_verts.size())
		assert_gt(face.normal.dot(centre - interior), 0.0, "%s: every face points out" % note)


## Two segments 10 long meeting at (10, 0, 0) with `angle` degrees between them.
func _corner_path(angle: float) -> Array:
	var turn := deg_to_rad(180.0 - angle)
	var corner := Vector3(10, 0, 0)
	return [Vector3.ZERO, corner, corner + Vector3(cos(turn), 0, sin(turn)) * 10.0]


func test_a_right_angle_bend_is_two_mitred_pieces_and_no_wedge():
	var pieces := _pieces([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])
	assert_eq(pieces.size(), 2, "one piece per segment, nothing between them")
	for info in pieces:
		assert_eq(info.faces.size(), 6, "two sides, two cut ends, a top and a bottom")
		assert_eq(info.shape, LevelRoot.BrushShape.CUSTOM)
	var bisector := Vector3(1, 0, 1).normalized()
	var ends: Array = []
	for info in pieces:
		ends.append_array(_faces_on(_world_faces(info), Vector3(10, 0, 0), bisector))
	assert_eq(ends.size(), 2, "each ends on the corner's bisector plane")
	assert_true(_same_corners(ends[0], ends[1]), "on the one face")


func test_a_straight_through_point_cuts_both_pieces_square():
	var pieces := _pieces([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)])
	assert_eq(pieces.size(), 2)
	for info in pieces:
		assert_almost_eq(info.size.x, 10.0, EPS, "each is its own segment's length")
	var ends: Array = []
	for info in pieces:
		ends.append_array(_faces_on(_world_faces(info), Vector3(10, 0, 0), Vector3.RIGHT))
	assert_eq(ends.size(), 2, "they meet square across the path")
	assert_true(_same_corners(ends[0], ends[1]))


func test_an_acute_corner_is_mitred_and_its_tip_cut_flat_past_the_limit():
	# A corner sharper than 60 degrees used to get no joint at all: a notch.
	var width := 1.0
	var path := _corner_path(20.0)
	var pieces := _pieces(path, {"path_width": width})
	assert_eq(pieces.size(), 2, "still two pieces")
	var d_in: Vector3 = (path[1] - path[0]).normalized()
	var d_out: Vector3 = (path[2] - path[1]).normalized()
	var outward := (d_in - d_out).normalized()
	var flats: Array = []
	var ends: Array = []
	for info in pieces:
		var faces := _world_faces(info)
		_assert_convex_and_outward(faces, "20 degrees")
		assert_eq(faces.size(), 7, "one face more than a plain mitre")
		for face: FaceData in faces:
			if face.normal.dot(outward) > 1.0 - EPS:
				flats.append(face)
		ends.append_array(_faces_on(faces, path[1], (d_in + d_out).normalized()))
	assert_eq(flats.size(), 2, "each piece has its tip cut flat, square to the bisector")
	assert_eq(ends.size(), 2, "and still ends on the bisector plane")
	assert_true(_same_corners(ends[0], ends[1]), "on the one face")
	var plane_at: float = outward.dot(flats[0].local_verts[0])
	assert_almost_eq(outward.dot(flats[1].local_verts[0]), plane_at, EPS, "both on one plane")
	var reach := 0.0
	for v in ends[0].local_verts:
		reach = maxf(reach, plane_at - outward.dot(v))
	assert_almost_eq(
		reach, PathSweep.MITRE_LIMIT * width, EPS, "the limit's widths out from the inside corner"
	)


func test_a_path_that_turns_straight_back_is_refused_by_name():
	var level := _fresh_level()
	var built := _built(level, [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, 0.01)])
	assert_false(built.built, "a corner with no bisector has no plane to cut on")
	assert_eq(built.toasts.size(), 1)
	assert_string_contains(str(built.toasts[0]), "turns straight back on itself at point 2")
	assert_eq(level._iter_managed_brush_nodes().size(), 0, "nothing is built")
	built.undo.free_histories()
	built.tool.deactivate()
	await get_tree().process_frame


func test_every_piece_carries_the_group_id():
	var pieces := _pieces([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])
	for info in pieces:
		assert_eq(info.group_id, "grp")


func test_side_sets_which_side_of_the_line_the_cross_section_stands_on():
	# Seen from above X runs right and Z down the screen, so the left of a path
	# running along +X is -Z.
	var expected := {
		HFPathTool.PathSide.CENTRE: Vector2(-1, 1),
		HFPathTool.PathSide.LEFT: Vector2(-2, 0),
		HFPathTool.PathSide.RIGHT: Vector2(0, 2),
	}
	for side in expected:
		var pieces := _pieces(
			[Vector3(0, 0, 0), Vector3(10, 0, 0)], {"path_width": 2.0, "path_side": side}
		)
		var low := INF
		var high := -INF
		for face: FaceData in _world_faces(pieces[0]):
			for v in face.local_verts:
				low = minf(low, v.z)
				high = maxf(high, v.z)
		assert_almost_eq(Vector2(low, high), expected[side], Vector2(EPS, EPS), "side %d" % side)


# ===========================================================================
# Face data validation
# ===========================================================================


func test_segment_faces_are_valid_dicts():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "test")
	for face_dict in info.faces:
		assert_true(face_dict is Dictionary, "Each face should be a dict")
		assert_true(face_dict.has("local_verts"), "Face should have local_verts")
		assert_true(face_dict.has("normal"), "Face should have normal")


func test_segment_faces_reconstruct_as_face_data():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 4.0, "test")
	for face_dict in info.faces:
		var face = FaceData.from_dict(face_dict)
		assert_not_null(face, "Face should deserialize")
		assert_true(face.local_verts.size() >= 3, "Face should have 3+ verts")


func test_rmb_passes_when_idle_and_only_steps_back_active_path_work():
	var tool = HFPathTool.new()
	var root := Node3D.new()
	var camera := Camera3D.new()
	tool.root = root
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	assert_eq(tool.handle_input(press, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(tool.handle_input(motion, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert_eq(tool.handle_input(release, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)

	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	assert_eq(tool.handle_input(press, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_STOP)
	assert_eq(tool._waypoints.size(), 1, "Active RMB should remove exactly one waypoint")
	assert_eq(tool.handle_input(release, camera, Vector2.ZERO), EditorPlugin.AFTER_GUI_INPUT_PASS)
	root.free()
	camera.free()


func _outward_face_count(info: Dictionary) -> int:
	# Face verts are local to the brush centre, so a face points outward when
	# its normal agrees with the direction from the centre to the face.
	var outward := 0
	for face_dict in info.faces:
		var face = FaceData.from_dict(face_dict)
		var centroid := Vector3.ZERO
		for v in face.local_verts:
			centroid += v
		centroid /= float(face.local_verts.size())
		if face.normal.dot(centroid) > 0.0:
			outward += 1
	return outward


func test_segment_brush_faces_point_outward():
	# Every face of a path segment used to point at the brush centre, so a
	# corridor baked inside out.
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(256, 0, 0), 4.0, 4.0, "test")
	assert_eq(info.faces.size(), 6, "A segment is a box")
	assert_eq(_outward_face_count(info), 6, "Every face of a segment points out of the solid")


func test_diagonal_segment_brush_faces_point_outward():
	var tool = HFPathTool.new()
	tool._ground_y = 0.0
	var info = tool._build_segment_brush(Vector3(0, 0, 0), Vector3(64, 0, 64), 8.0, 6.0, "test")
	assert_eq(_outward_face_count(info), 6, "Winding does not depend on the segment direction")


func test_mitred_pieces_face_outward_at_any_corner():
	for angle in [135.0, 90.0, 45.0, 20.0]:
		var pieces := _pieces(_corner_path(angle), {"path_width": 1.0, "path_height": 8.0})
		assert_eq(pieces.size(), 2, "%d degrees: both segments built" % angle)
		for info in pieces:
			assert_eq(
				_outward_face_count(info), info.faces.size(), "%d degrees: every face" % angle
			)


# ===========================================================================
# Segment lengths and the Shift axis lock (#1408)
# ===========================================================================


## A level stand-in that answers every pick with `aim` and snaps to half a metre.
class AimRoot:
	extends Node3D

	var aim := Vector3.ZERO

	func _snap_point(point: Vector3, _exclude_ids: Array = []) -> Vector3:
		return point.snapped(Vector3(0.5, 0.5, 0.5))

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		return {"position": aim}

	func screen_ray_to_y_plane(_camera: Camera3D, _mouse_pos: Vector2, y: float) -> Vector3:
		return Vector3(aim.x, y, aim.z)


func _click_at(tool, root: AimRoot, camera: Camera3D, at: Vector3, shift := false) -> int:
	root.aim = at
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = shift
	return tool.handle_input(press, camera, Vector2.ZERO)


func _move_to(tool, root: AimRoot, camera: Camera3D, at: Vector3, shift := false) -> void:
	root.aim = at
	var motion := InputEventMouseMotion.new()
	motion.shift_pressed = shift
	tool.handle_input(motion, camera, Vector2.ZERO)


## [tool, root, camera], the root and camera freed with the test.
func _aimed_tool(tool = null) -> Array:
	if tool == null:
		tool = HFPathTool.new()
	var root := AimRoot.new()
	add_child_autofree(root)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	tool.root = root
	return [tool, root, camera]


func _labels_in(level: Node) -> Array:
	return level.find_children("SegmentLength*", "Label3D", true, false)


func _label_texts(tool) -> Array:
	var texts: Array = []
	for label: Label3D in tool._length_labels:
		texts.append(label.text)
	texts.sort()
	return texts


func test_shift_locks_a_waypoint_to_the_axis_nearer_its_direction():
	# A corridor meant to run along X used to pick up a step of Z when a click
	# landed a cell off, and the path then built a joint nobody asked for.
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(3, 0, 0.4), true)
	assert_eq(tool._waypoints[1], Vector3(3, 0, 0), "X is nearer, so Z stays the last point's")
	_click_at(tool, parts[1], parts[2], Vector3(2.7, 0, 6.2), true)
	assert_eq(tool._waypoints[2], Vector3(3, 0, 6), "Z is nearer, and it snaps along Z")
	tool.deactivate()
	await get_tree().process_frame


func test_without_shift_a_waypoint_lands_where_it_snaps():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(3, 0, 0.4))
	assert_eq(tool._waypoints[1], Vector3(3, 0, 0.5), "placement is unchanged")
	tool.deactivate()
	await get_tree().process_frame


func test_shift_locks_the_live_segment_while_the_mouse_moves():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(2, 0, 2))
	_move_to(tool, parts[1], parts[2], Vector3(-6.2, 0, 2.6), true)
	assert_eq(tool._cursor_pos, Vector3(-6, 0, 2), "the cursor runs along X from the last point")
	tool.deactivate()
	await get_tree().process_frame


func test_the_hud_names_the_axis_lock_while_placing():
	var parts := _aimed_tool()
	var tool = parts[0]
	assert_false(tool.get_shortcut_hud_lines().has("Shift: Lock to axis"), "not before a point")
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	assert_true(tool.get_shortcut_hud_lines().has("Shift: Lock to axis"))
	tool.deactivate()
	await get_tree().process_frame


func _fresh_level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func test_placed_and_live_segments_show_their_lengths():
	var level := _fresh_level()
	level.grid_snap = 0.5
	var tool = HFPathTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(12, 0, 0)])
	tool._cursor_pos = Vector3(12, 0, 5)
	tool._update_preview()
	assert_eq(_label_texts(tool), ["12", "5"], "placed 12, live 5, whole lengths as whole numbers")
	var placed: Label3D = tool._length_labels[0]
	assert_eq(
		placed.position, Vector3(6, 0.5, 0), "at its segment's middle, lifted as a ruler's is"
	)
	level.grid_snap = 1.0
	tool._update_preview()
	assert_eq(_label_texts(tool), ["12", "5"], "the places follow the grid")
	assert_eq(_labels_in(level).size(), 2, "and the labels are reused, not added to")
	tool.deactivate()
	await get_tree().process_frame


func test_building_the_path_takes_the_labels_away():
	var level := _fresh_level()
	var tool = HFPathTool.new()
	tool.root = level
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0)])
	tool._cursor_pos = Vector3(8, 0, 8)
	tool._update_preview()
	assert_eq(_labels_in(level).size(), 2)
	tool._build_path()
	assert_true(tool._length_labels.is_empty(), "the tool lets them go")
	assert_eq(_labels_in(level).size(), 0, "and none stays in the scene tree")
	await get_tree().process_frame


func test_cancelling_takes_the_labels_away():
	var parts := _aimed_tool()
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(4, 0, 0))
	_move_to(tool, parts[1], parts[2], Vector3(4, 0, 4))
	assert_eq(_labels_in(parts[1]).size(), 2, "the placed and live segments are labelled")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	tool.handle_input(escape, parts[2], Vector2.ZERO)
	tool.handle_input(escape, parts[2], Vector2.ZERO)
	assert_eq(_labels_in(parts[1]).size(), 0, "Esc down to nothing takes them all")
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_move_to(tool, parts[1], parts[2], Vector3(4, 0, 0))
	tool.deactivate()
	assert_eq(_labels_in(parts[1]).size(), 0, "and so does leaving the tool")
	await get_tree().process_frame


# ===========================================================================
# Closing a room, Side, and refusing what does not fit (#1412)
# ===========================================================================

## A square clicked clockwise as seen from above, where X runs right and Z runs
## down the screen.
const CLOCKWISE_SQUARE := [Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 8), Vector3(0, 0, 8)]


## A tool on `level` with an undo manager, placing `points`, and the toasts the
## level shows. Returns {tool, undo, toasts}.
func _placing(level: LevelRoot, points: Array, settings: Dictionary = {}) -> Dictionary:
	var toasts: Array = []
	level.user_message.connect(func(text: String, _level: int) -> void: toasts.append(text))
	var undo = UndoStandIn.new()
	var tool = HFPathTool.new()
	tool.root = level
	tool.undo_redo = undo
	for key in settings:
		tool.set_setting(key, settings[key])
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array(points)
	return {"tool": tool, "undo": undo, "toasts": toasts}


## Build `points` on `level`, as Enter or the closing click does. Returns what
## `_placing()` does and whether it "built".
func _built(
	level: LevelRoot, points: Array, settings: Dictionary = {}, closed := false
) -> Dictionary:
	var placing := _placing(level, points, settings)
	placing.tool._closed = closed
	placing["built"] = placing.tool._build_path()
	return placing


## A brush's faces with their corners in world space.
func _brush_world_faces(brush: Node3D) -> Array:
	var out: Array = []
	for face: FaceData in brush.faces:
		var world := FaceData.new()
		var verts := PackedVector3Array()
		for v in face.local_verts:
			verts.append(brush.global_transform * v)
		world.local_verts = verts
		world.ensure_geometry()
		out.append(world)
	return out


## Every brush convex, wound clockwise from outside and not mirrored.
func _assert_sound(brushes: Array, note: String) -> void:
	for brush in brushes:
		_assert_convex_and_outward(_brush_world_faces(brush), "%s, %s" % [note, brush.name])
		assert_gt(brush.global_transform.basis.determinant(), 0.0, "%s: not mirrored" % note)


## The faces on the bisector plane at `points[i]` of a closed path, near it: the
## opposite corner of a square lies on the same plane.
func _faces_at_corner(face_sets: Array, points: Array, i: int) -> Array:
	var n := points.size()
	var d_in: Vector3 = (points[i] - points[(i + n - 1) % n]).normalized()
	var d_out: Vector3 = (points[(i + 1) % n] - points[i]).normalized()
	var on: Array = []
	for faces in face_sets:
		for face: FaceData in _faces_on(faces, points[i], (d_in + d_out).normalized()):
			if face.local_verts[0].distance_to(points[i]) < 4.0:
				on.append(face)
	return on


func test_a_closed_square_is_four_walls_mitred_at_every_corner_and_no_wedge():
	var level := _fresh_level()
	var built := _built(level, CLOCKWISE_SQUARE, {"path_width": 1.0, "path_height": 3.0}, true)
	assert_true(built.built)
	var brushes: Array = level._iter_managed_brush_nodes()
	assert_eq(brushes.size(), 4, "four walls and no wedge pieces")
	_assert_sound(brushes, "square")
	var face_sets: Array = []
	for brush in brushes:
		assert_eq(brush.faces.size(), 6, "two sides, two cut ends, a top and a bottom")
		face_sets.append(_brush_world_faces(brush))
	for i in 4:
		var on := _faces_at_corner(face_sets, CLOCKWISE_SQUARE, i)
		assert_eq(on.size(), 2, "corner %d, the first included: two pieces end on it" % (i + 1))
		if on.size() == 2:
			assert_true(_same_corners(on[0], on[1]), "corner %d: on one face" % (i + 1))
	assert_almost_eq(_overlap(face_sets), 0.0, EPS, "no two walls overlap")
	assert_eq(built.undo.scene_history.get_history_count(), 1, "one undo step")
	built.undo.free_histories()
	built.tool.deactivate()
	await get_tree().process_frame


func test_side_left_on_a_clockwise_square_keeps_every_inside_face_on_the_clicked_line():
	# A wall straddling the line stood half off the floor it was traced round and
	# made the room half a wall smaller on every side than drawn.
	var level := _fresh_level()
	var settings := {"path_width": 1.0, "path_height": 3.0, "path_side": HFPathTool.PathSide.LEFT}
	var built := _built(level, CLOCKWISE_SQUARE, settings, true)
	var brushes: Array = level._iter_managed_brush_nodes()
	assert_eq(brushes.size(), 4)
	_assert_sound(brushes, "left walls")
	var faces: Array = []
	for brush in brushes:
		faces.append_array(_brush_world_faces(brush))
	for i in 4:
		var a: Vector3 = CLOCKWISE_SQUARE[i]
		var b: Vector3 = CLOCKWISE_SQUARE[(i + 1) % 4]
		var along := (b - a).normalized()
		# Clockwise, the room is on the right of travel.
		var into_room := Vector3(-along.z, 0, along.x)
		# The wall across the room faces the same way from outside it, so only
		# a face on this side's own line counts.
		var inside: Array = []
		for face: FaceData in _faces_on(faces, a, into_room):
			if face.normal.dot(into_room) > 1.0 - EPS:
				inside.append(face)
		assert_eq(inside.size(), 1, "side %d: its face into the room is on its line" % (i + 1))
		if inside.size() != 1:
			continue
		var from := INF
		var to := -INF
		for v: Vector3 in inside[0].local_verts:
			from = minf(from, along.dot(v - a))
			to = maxf(to, along.dot(v - a))
		assert_almost_eq(from, 0.0, EPS, "side %d: from its first point" % (i + 1))
		assert_almost_eq(to, a.distance_to(b), EPS, "side %d: to its last" % (i + 1))
	for face: FaceData in faces:
		for v in face.local_verts:
			var in_room: bool = v.x > EPS and v.x < 8.0 - EPS and v.z > EPS and v.z < 8.0 - EPS
			assert_false(in_room, "no wall stands in the room drawn: %s" % v)
	built.undo.free_histories()
	built.tool.deactivate()
	await get_tree().process_frame


func test_neighbours_share_their_end_plane_and_do_not_overlap_at_90_45_and_20_degrees():
	for angle in [90.0, 45.0, 20.0]:
		var level := _fresh_level()
		var path := _corner_path(angle)
		var built := _built(level, path, {"path_width": 1.0, "path_height": 2.0})
		var brushes: Array = level._iter_managed_brush_nodes()
		assert_eq(brushes.size(), 2, "%d degrees: two pieces and no wedge" % angle)
		_assert_sound(brushes, "%d degrees" % angle)
		var face_sets: Array = []
		for brush in brushes:
			face_sets.append(_brush_world_faces(brush))
		var d_in: Vector3 = (path[1] - path[0]).normalized()
		var d_out: Vector3 = (path[2] - path[1]).normalized()
		var on: Array = []
		for faces in face_sets:
			on.append_array(_faces_on(faces, path[1], (d_in + d_out).normalized()))
		assert_eq(on.size(), 2, "%d degrees: both end on the bisector plane" % angle)
		if on.size() == 2:
			assert_true(_same_corners(on[0], on[1]), "%d degrees: on one face" % angle)
			assert_almost_eq(
				on[0].normal.dot(on[1].normal), -1.0, EPS, "%d degrees: back to back" % angle
			)
		assert_almost_eq(_overlap(face_sets), 0.0, EPS, "%d degrees: no overlap" % angle)
		built.undo.free_histories()
		built.tool.deactivate()
	await get_tree().process_frame


func test_a_segment_too_short_for_its_mitres_is_refused_by_name_and_nothing_is_built():
	# A U turn: a wall 2 wide pulls the inside of the middle segment back 1 at
	# each end, so on a segment 1 long its two cuts cross.
	var level := _fresh_level()
	level.grid_snap = 1.0
	var u_turn := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 1), Vector3(0, 0, 1)]
	var built := _built(level, u_turn, {"path_width": 2.0})
	assert_false(built.built, "it is refused")
	assert_eq(built.toasts.size(), 1, "and the mapper is told")
	assert_string_contains(str(built.toasts[0]), "segment 2 is 1 long")
	assert_string_contains(str(built.toasts[0]), "need more than 2")
	assert_eq(level._iter_managed_brush_nodes().size(), 0, "nothing is built")
	assert_eq(built.undo.scene_history.get_history_count(), 0, "and no undo step")
	assert_eq(built.tool._waypoints, PackedVector3Array(u_turn), "the points stay to change")
	assert_eq(built.tool._phase, built.tool.Phase.PLACING_WAYPOINTS)
	built.tool.set_setting("path_width", 0.5)
	assert_true(built.tool._build_path(), "a narrower wall fits")
	assert_eq(level._iter_managed_brush_nodes().size(), 3)
	built.undo.free_histories()
	built.tool.deactivate()
	await get_tree().process_frame


func test_a_loop_too_small_to_close_stays_open_with_its_points():
	var level := _fresh_level()
	var small := [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 2), Vector3(0, 0, 2)]
	var placing := _placing(level, small, {"path_width": 4.0})
	var tool = placing.tool
	tool._close_loop()
	assert_eq(placing.toasts.size(), 1, "a wall 4 wide has no room on sides 2 long")
	assert_string_contains(str(placing.toasts[0]), "segment 1")
	assert_false(tool._closed, "the loop stays open")
	assert_eq(tool._waypoints, PackedVector3Array(small), "with no point added for the click")
	assert_eq(tool._phase, tool.Phase.PLACING_WAYPOINTS)
	assert_eq(level._iter_managed_brush_nodes().size(), 0, "nothing is built")
	assert_eq(placing.undo.scene_history.get_history_count(), 0, "and no undo step")
	placing.undo.free_histories()
	tool.deactivate()
	await get_tree().process_frame


## A path tool that notes what it was asked to build and builds it.
class RecordingPathTool:
	extends "res://addons/hammerforge/hf_path_tool.gd"

	var built_closed := false
	var built_segments := 0

	func _build_path() -> bool:
		built_closed = _closed
		built_segments = _segment_ends().size()
		return super()


func test_clicking_the_first_point_closes_the_loop_and_builds_it():
	var parts := _aimed_tool(RecordingPathTool.new())
	var tool = parts[0]
	for corner in CLOCKWISE_SQUARE:
		_click_at(tool, parts[1], parts[2], corner)
	assert_eq(tool._waypoints.size(), 4)
	assert_true(tool.get_shortcut_hud_lines().has("Click first point: Close and build"))
	_move_to(tool, parts[1], parts[2], Vector3(0.2, 0, -0.1))
	assert_eq(tool._cursor_pos, Vector3(0, 0, 0), "the cursor settles on the first point")
	_click_at(tool, parts[1], parts[2], Vector3(0.2, 0, -0.1))
	assert_true(tool.built_closed, "a click there closes the loop")
	assert_eq(tool.built_segments, 4, "four walls, the last back to the start")
	assert_eq(tool._phase, tool.Phase.IDLE, "and builds it")
	tool.deactivate()
	await get_tree().process_frame


func test_a_click_on_the_first_point_with_two_down_is_only_a_point():
	var parts := _aimed_tool(RecordingPathTool.new())
	var tool = parts[0]
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	_click_at(tool, parts[1], parts[2], Vector3(8, 0, 0))
	assert_false(tool.get_shortcut_hud_lines().has("Click first point: Close and build"))
	_click_at(tool, parts[1], parts[2], Vector3(0, 0, 0))
	assert_false(tool.built_closed, "two points make no loop")
	assert_eq(tool._waypoints.size(), 3)
	tool.deactivate()
	await get_tree().process_frame


func test_the_preview_outlines_the_walls_to_the_side_chosen_and_round_the_corner():
	var tool = HFPathTool.new()
	tool.set_setting("path_width", 2.0)
	tool.set_setting("path_side", HFPathTool.PathSide.RIGHT)
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	tool._cursor_pos = Vector3(10, 0, 10)
	var outline: Dictionary = tool._preview_footprints(2.0)
	assert_false(outline.refused)
	assert_eq(outline.rings.size(), 2, "the segment placed and the one to the cursor")
	var first: PackedVector3Array = outline.rings[0]
	for corner in [Vector3(0, 0, 0), Vector3(0, 0, 2), Vector3(8, 0, 2), Vector3(10, 0, 0)]:
		var found := false
		for v in first:
			found = found or v.is_equal_approx(corner)
		assert_true(found, "right of the line, mitred where it turns: %s" % corner)
	tool._cursor_pos = Vector3(10, 0, 1)
	outline = tool._preview_footprints(2.0)
	assert_true(outline.refused, "a turn the wall has no room for shows before Enter")


func test_hovering_the_first_point_previews_the_closed_loop():
	var tool = HFPathTool.new()
	tool._phase = tool.Phase.PLACING_WAYPOINTS
	tool._waypoints = PackedVector3Array(CLOCKWISE_SQUARE)
	tool._cursor_pos = Vector3(0, 0, 0)
	assert_eq(tool._preview_footprints(1.0).rings.size(), 4, "four walls, closed")
	tool._cursor_pos = Vector3(-4, 0, 0)
	assert_eq(tool._preview_footprints(1.0).rings.size(), 4, "open, on to the cursor")
