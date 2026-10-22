extends GutTest

## The Face projection (#1419): a texture laid in the face's own plane, U level
## along the face and V down its slope, so a ramp or a chamfer repeats over the
## same length a wall does. Box UV takes a slope as the wall or floor it leans
## towards and stretches it along the lean by 1 / cos of the angle.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const MapIOType = preload("res://addons/hammerforge/map_io.gd")
const QuakeAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")
const Valve220Adapter = preload("res://addons/hammerforge/map_adapters/hf_map_valve220.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const CollationTests = preload("res://tests/test_undo_collation.gd")
const HFUserPrefsType = preload("res://addons/hammerforge/hf_user_prefs.gd")

const FACE := FaceDataScript.UVProjection.FACE
const BOX := FaceDataScript.UVProjection.BOX_UV
const EPS := 0.001
## The slope of a wedge, which leans towards +X.
const SLOPE := Vector3(0.70710678, 0.70710678, 0.0)


## The stand-in, answering the two calls the dock's history list makes of the
## editor's manager. With no scene history the list counts its own entries.
class DockUndo:
	extends CollationTests.FakeUndoRedo

	func get_object_history_id(_object: Object) -> int:
		return 0

	func get_history_undo_redo(_id: int) -> UndoRedo:
		return null


var root: LevelRoot


func before_each():
	HFUndoHelper._reset_collation()
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.material_manager.clear()


func after_each():
	HFUndoHelper._reset_collation()
	root = null


# ===========================================================================
# Fixtures
# ===========================================================================


func _brush(
	brush_id: String, shape: int, center: Vector3, size := Vector3(32, 32, 32)
) -> DraftBrush:
	var b := (
		root.create_brush_from_info(
			{"shape": shape, "size": size, "center": center, "brush_id": brush_id}
		)
		as DraftBrush
	)
	if b.get_faces().is_empty():
		b.rebuild_preview()
	return b


## A 32 unit wedge, whose slope is a 45 degree chamfer.
func _wedge(brush_id: String, center: Vector3) -> DraftBrush:
	return _brush(brush_id, LevelRootType.BrushShape.WEDGE, center)


func _box(brush_id: String, center: Vector3, size := Vector3(32, 32, 32)) -> DraftBrush:
	return _brush(brush_id, LevelRootType.BrushShape.BOX, center, size)


static func _face_facing(brush: DraftBrush, direction: Vector3) -> FaceData:
	var basis := brush.global_transform.basis
	for face in brush.get_faces():
		if face != null and face.normal_through(basis).dot(direction.normalized()) > 0.99:
			return face
	return null


## The UV `face` of `brush` shows at a point in the level that lies on it.
static func _uv_at(brush: DraftBrush, face: FaceData, world: Vector3) -> Vector2:
	brush.sync_face_world_transform()
	var local: Vector3 = brush.global_transform.affine_inverse() * world
	return face.shown_uvs_at(PackedVector3Array([local]))[0]


## The direction in the level along which `face`'s U grows, read off the UVs it
## shows at three of its corners.
static func _u_direction(brush: DraftBrush, face: FaceData) -> Vector3:
	brush.sync_face_world_transform()
	var xform := brush.global_transform
	var p0: Vector3 = xform * face.local_verts[0]
	var p1: Vector3 = xform * face.local_verts[1]
	var p2: Vector3 = xform * face.local_verts[2]
	var uvs := face.shown_uvs_at(
		PackedVector3Array([face.local_verts[0], face.local_verts[1], face.local_verts[2]])
	)
	var e1 := p1 - p0
	var e2 := p2 - p0
	var n := e1.cross(e2)
	var m := Basis(Vector3(e1.x, e2.x, n.x), Vector3(e1.y, e2.y, n.y), Vector3(e1.z, e2.z, n.z))
	return (m.inverse() * Vector3(uvs[1].x - uvs[0].x, uvs[2].x - uvs[0].x, 0.0)).normalized()


static func _dress(face: FaceData, offset: Vector2, scale: Vector2, rotation: float) -> void:
	face.uv_projection = FaceDataScript.UVProjection.FACE
	face.uv_offset = offset
	face.uv_scale = scale
	face.uv_rotation = rotation
	face.custom_uvs = PackedVector2Array()


# ===========================================================================
# The projection
# ===========================================================================


func test_a_45_degree_chamfer_repeats_over_the_length_a_wall_does():
	var wedge := _wedge("w", Vector3(40, 8, -24))
	var slope := _face_facing(wedge, SLOPE)
	assert_not_null(slope, "the wedge has a slope")
	slope.uv_projection = FACE
	var xform := wedge.global_transform
	var top: Vector3 = xform * Vector3(-16, 16, 4)
	var bottom: Vector3 = xform * Vector3(16, -16, 4)
	var along: Vector3 = xform * Vector3(-16, 16, -6)
	var length := top.distance_to(bottom)
	var uv_top := _uv_at(wedge, slope, top)
	var uv_bottom := _uv_at(wedge, slope, bottom)
	assert_almost_eq(uv_bottom.y - uv_top.y, length, EPS, "V runs down the slope, a unit a unit")
	assert_almost_eq(uv_bottom.x, uv_top.x, EPS, "and U is level, so it does not move down it")
	assert_almost_eq(
		uv_top.distance_to(_uv_at(wedge, slope, along)), 10.0, EPS, "along the level edge as well"
	)
	# The wall beside it, for the length a texture repeats over on a wall.
	var wall := _box("b", Vector3(40, 8, 40))
	var side := _face_facing(wall, Vector3.RIGHT)
	var wall_top := wall.global_transform * Vector3(16, 16, 0)
	var wall_bottom := wall.global_transform * Vector3(16, -16, 0)
	assert_almost_eq(
		_uv_at(wall, side, wall_top).distance_to(_uv_at(wall, side, wall_bottom)),
		wall_top.distance_to(wall_bottom),
		EPS,
		"a wall repeats every unit"
	)
	slope.uv_projection = BOX
	assert_almost_eq(
		_uv_at(wedge, slope, top).distance_to(_uv_at(wedge, slope, bottom)),
		32.0,
		EPS,
		"Box UV reads the slope as the wall it leans towards, 1.41 times too short"
	)


func test_u_runs_level_and_v_down_the_slope_in_the_face_s_plane():
	for raw in [
		SLOPE,
		Vector3(-1, 1, 0),
		Vector3(0, 1, 2),
		Vector3(3, -1, -2),
		Vector3(1, 0, 0),
		Vector3(0, 0, -1),
		Vector3(0.3, 0.9, -0.4)
	]:
		var n: Vector3 = raw.normalized()
		var axes: Array = FaceDataScript.face_axes_for(n)
		var u: Vector3 = axes[0]
		var v: Vector3 = axes[1]
		assert_almost_eq(u.length(), 1.0, EPS, "%s: U is a unit" % raw)
		assert_almost_eq(v.length(), 1.0, EPS, "%s: V is a unit" % raw)
		assert_almost_eq(u.dot(n), 0.0, EPS, "%s: U lies in the face" % raw)
		assert_almost_eq(v.dot(n), 0.0, EPS, "%s: V lies in the face" % raw)
		assert_almost_eq(u.y, 0.0, EPS, "%s: U is level" % raw)
		assert_lt(v.y, 0.0, "%s: V runs downhill" % raw)
		# Seen from outside, U to the right and V down, as an image reads.
		assert_almost_eq(u.cross(v).dot(n), -1.0, EPS, "%s: not mirrored" % raw)


func test_coplanar_slopes_on_two_brushes_show_one_texture():
	# Side by side along the slope's level edge, sharing the plane at z = 16.
	var near := _wedge("a", Vector3(0, 0, 0))
	var far := _wedge("b", Vector3(0, 0, 32))
	var near_slope := _face_facing(near, SLOPE)
	var far_slope := _face_facing(far, SLOPE)
	for face in [near_slope, far_slope]:
		_dress(face, Vector2(0.3, -0.2), Vector2(0.125, 0.25), 0.4)
	for seam in [Vector3(-16, 16, 16), Vector3(16, -16, 16), Vector3(0, 0, 16)]:
		assert_almost_eq(
			_uv_at(near, near_slope, seam),
			_uv_at(far, far_slope, seam),
			Vector2(EPS, EPS),
			"the two sides of the seam at %s" % seam
		)


func test_a_floor_and_a_ceiling_read_planar_y():
	var box := _box("b", Vector3(24, 4, -40))
	for direction in [Vector3.UP, Vector3.DOWN]:
		var face := _face_facing(box, direction)
		face.uv_projection = FaceDataScript.UVProjection.PLANAR_Y
		var planar := face._project_uvs_for_vertices(face.local_verts)
		face.uv_projection = FACE
		_assert_uvs(
			face._project_uvs_for_vertices(face.local_verts),
			planar,
			"%s reads as Planar Y" % direction
		)


func test_a_wall_reads_the_world_axes_without_a_mirror():
	var box := _box("b", Vector3(24, 4, -40))
	var east := _face_facing(box, Vector3.RIGHT)
	east.uv_projection = FaceDataScript.UVProjection.PLANAR_X
	var planar := east._project_uvs_for_vertices(east.local_verts)
	east.uv_projection = FACE
	_assert_uvs(
		east._project_uvs_for_vertices(east.local_verts), planar, "a wall facing +X reads Planar X"
	)
	# Planar X reads the same U on the wall facing -X, so text there reads
	# backwards from outside. The Face projection reads it forwards.
	var west := _face_facing(box, Vector3.LEFT)
	west.uv_projection = FaceDataScript.UVProjection.PLANAR_X
	var mirrored := west._project_uvs_for_vertices(west.local_verts)
	west.uv_projection = FACE
	var own := west._project_uvs_for_vertices(west.local_verts)
	for i in own.size():
		assert_almost_eq(own[i].x, -mirrored[i].x, EPS, "U the other way along the west wall")
		assert_almost_eq(own[i].y, mirrored[i].y, EPS, "V down it as before")


func _assert_uvs(got: PackedVector2Array, want: PackedVector2Array, what: String) -> void:
	assert_eq(got.size(), want.size(), "%s: as many UVs" % what)
	for i in mini(got.size(), want.size()):
		assert_almost_eq(got[i], want[i], Vector2(EPS, EPS), "%s: corner %d" % [what, i])


# ===========================================================================
# Texture Lock
# ===========================================================================


func test_texture_lock_keeps_a_face_projected_slope_on_its_brush_through_a_move():
	root.texture_lock = true
	var wedge := _wedge("w", Vector3(40, 8, -24))
	var slope := _face_facing(wedge, SLOPE)
	_dress(slope, Vector2(0.3, 0.1), Vector2(0.5, -0.25), 0.4)
	wedge.rebuild_preview()
	var points := PackedVector3Array(
		[Vector3(0, 0, 5), Vector3(-16, 16, -16), Vector3(16, -16, 16)]
	)
	var before := slope.shown_uvs_at(points)

	root.set_brush_transform_by_id("w", wedge.size, wedge.global_position + Vector3(7, 3, -5))

	# Asked of the brush again, which may have built its faces afresh.
	slope = _face_facing(wedge, SLOPE)
	_assert_uvs(slope.shown_uvs_at(points), before, "the texture moved with it")
	root.texture_lock = false
	root.set_brush_transform_by_id("w", wedge.size, wedge.global_position + Vector3(7, 3, -5))
	slope = _face_facing(wedge, SLOPE)
	assert_ne(slope.shown_uvs_at(points)[0], before[0], "without the lock it stays in the level")


func test_texture_lock_resizes_a_face_projected_wall_as_planar_x_does():
	root.texture_lock = true
	var planar := _box("p", Vector3(0, 0, 0))
	var own := _box("f", Vector3(100, 0, 0))
	_face_facing(planar, Vector3.RIGHT).uv_projection = FaceDataScript.UVProjection.PLANAR_X
	_face_facing(own, Vector3.RIGHT).uv_projection = FACE
	for id in ["p", "f"]:
		var b := root.find_brush_by_id(id) as DraftBrush
		root.set_brush_transform_by_id(id, Vector3(32, 64, 16), b.global_position)
	assert_almost_eq(
		_face_facing(own, Vector3.RIGHT).uv_scale,
		_face_facing(planar, Vector3.RIGHT).uv_scale,
		Vector2(EPS, EPS),
		"the same stretch"
	)


func test_texture_lock_carries_a_face_projected_texture_through_a_turn():
	root.texture_lock = true
	for axis in [0, 1, 2]:
		root.clear_brushes()
		var wedge := _wedge("w", Vector3.ZERO)
		for face in wedge.get_faces():
			_dress(face, Vector2.ZERO, Vector2.ONE, 0.25)
		wedge.rebuild_preview()
		var before: Array = []
		for face in wedge.get_faces():
			before.append(_u_direction(wedge, face))
		var turn := Basis(_axis(axis), deg_to_rad(90.0))

		root.rotate_managed_nodes(["w"], [], axis, 90.0, Vector3.ZERO)

		for i in wedge.get_faces().size():
			var now := _u_direction(wedge, wedge.get_faces()[i])
			assert_almost_eq(
				now.dot(turn * (before[i] as Vector3)),
				1.0,
				EPS,
				"axis %d, face %d: the texture went round with the brush" % [axis, i]
			)


static func _axis(index: int) -> Vector3:
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][index]


func test_align_to_world_after_a_turn_under_the_face_projection_does_not_mirror():
	# Box UV keeps a face's handedness across a turn by remembering the brush's
	# orientation. A face turned while on another projection is laid against where
	# it now stands, or Align to World reads the old turn and flips a scale.
	var box := _box("b", Vector3.ZERO)
	box.sync_face_world_transform()
	var scales: Array = []
	for face in box.get_faces():
		face.uv_projection = FACE
		scales.append(face.uv_scale)
	box.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	box.sync_face_world_transform()
	for face in box.get_faces():
		face.uv_projection = BOX
	box.sync_face_world_transform()
	for i in box.get_faces().size():
		assert_eq(box.get_faces()[i].uv_scale, scales[i], "face %d keeps its scale" % i)


# ===========================================================================
# The .map formats
# ===========================================================================


func _export_and_import(format: String, file_name: String) -> Array:
	var path := "user://%s" % file_name
	assert_eq(root.export_map(path, format), OK, "%s export" % format)
	assert_eq(root.import_map(path), OK, "%s import" % format)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return root.get_all_draft_brushes()


func test_a_valve_220_round_trip_gives_back_a_face_projected_slope():
	for look in [
		[Vector2(0.25, -0.125), Vector2(0.5, 0.25), deg_to_rad(30.0)],
		[Vector2(-0.5, 0.375), Vector2(-0.5, 2.0), deg_to_rad(-60.0)],
		[Vector2.ZERO, Vector2.ONE, 0.0],
	]:
		root.clear_brushes()
		var wedge := _wedge("w", Vector3(40, 8, -24))
		_dress(_face_facing(wedge, SLOPE), look[0], look[1], look[2])
		wedge.rebuild_preview()

		var brushes := _export_and_import("valve220", "hf_test_face_projection.map")

		assert_eq(brushes.size(), 1, "the wedge comes back")
		var slope := _face_facing(brushes[0], SLOPE)
		assert_not_null(slope, "with its slope")
		if slope == null:
			continue
		assert_eq(slope.uv_projection, FACE, "%s: on the Face projection" % [look])
		assert_almost_eq(slope.uv_offset, look[0], Vector2(EPS, EPS), "%s: offset" % [look])
		assert_almost_eq(slope.uv_scale, look[1], Vector2(EPS, EPS), "%s: scale" % [look])
		assert_almost_eq(slope.uv_rotation, look[2], EPS, "%s: rotation" % [look])


func test_a_valve_220_export_writes_the_face_s_own_axes_on_a_slope():
	var wedge := _wedge("w", Vector3(40, 8, -24))
	var slope := _face_facing(wedge, SLOPE)
	_dress(slope, Vector2.ZERO, Vector2.ONE, deg_to_rad(20.0))
	var text := MapIOType.export_map_from_level(root, Valve220Adapter.new(), 1.0, false)
	var written := false
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if not line.begins_with("("):
			continue
		var axes := _valve_axes(line)
		var turned: Array = FaceDataScript.turned_axes(
			slope.face_axes_in(slope.world_transform), slope.uv_rotation
		)
		if (axes[0] as Vector3).distance_to(turned[0]) < EPS:
			written = true
			assert_almost_eq((axes[1] as Vector3).distance_to(turned[1]), 0.0, EPS, "and V")
			assert_almost_eq((axes[0] as Vector3).dot(SLOPE), 0.0, EPS, "U lies in the slope")
			assert_almost_eq((axes[1] as Vector3).dot(SLOPE), 0.0, EPS, "V lies in the slope")
	assert_true(written, "a line carries the slope's own axes, turned by its rotation")


static func _valve_axes(line: String) -> Array:
	var out: Array = []
	var bracket := RegEx.new()
	bracket.compile("\\[([^\\]]+)\\]")
	for found in bracket.search_all(line):
		var parts := found.get_string(1).split(" ", false)
		out.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return out


func test_a_box_uv_box_comes_back_on_box_uv():
	var box := _box("b", Vector3(40, 8, -24))
	for face in box.get_faces():
		face.uv_projection = BOX
		face.uv_rotation = 0.5
		face.uv_offset = Vector2(0.25, 0.5)
	box.rebuild_preview()
	var brushes := _export_and_import("valve220", "hf_test_face_projection_box.map")
	for face in brushes[0].get_faces():
		assert_eq(face.uv_projection, BOX, "the world pair is read as Box UV (%s)" % face.normal)


func test_a_face_projected_box_keeps_its_look_through_classic_quake():
	# Classic Quake has no axes, so a reader takes the world ones. On a box every
	# face's own axes are those, one perhaps reversed, so the numbers are written
	# against the world's and the look comes back whole on Box UV.
	var box := _box("b", Vector3(40, 8, -24))
	for face in box.get_faces():
		_dress(face, Vector2(0.25, -0.5), Vector2(0.5, 0.25), deg_to_rad(30.0))
	box.rebuild_preview()
	var wanted := {}
	for face in box.get_faces():
		for pair in _corner_uvs(box, face):
			wanted[_key(pair[0], face.normal)] = pair[1]
	var brushes := _export_and_import("quake", "hf_test_face_projection_quake.map")
	var compared := 0
	for face in brushes[0].get_faces():
		for pair in _corner_uvs(brushes[0], face):
			var key := _key(pair[0], face.normal)
			if wanted.has(key):
				compared += 1
				assert_almost_eq(pair[1], wanted[key], Vector2(EPS, EPS), "corner %s" % key)
	assert_eq(compared, 24, "every corner of every face was compared")


static func _corner_uvs(brush: DraftBrush, face: FaceData) -> Array:
	brush.sync_face_world_transform()
	var out: Array = []
	var uvs := face.shown_uvs()
	for i in face.local_verts.size():
		out.append([brush.global_transform * face.local_verts[i], uvs[i]])
	return out


static func _key(p: Vector3, n: Vector3) -> String:
	return (
		"%d,%d,%d/%d,%d,%d"
		% [
			roundi(p.x * 100),
			roundi(p.y * 100),
			roundi(p.z * 100),
			roundi(n.x),
			roundi(n.y),
			roundi(n.z)
		]
	)


## A slope with no offset, as another editor might lay it on.
func _slope_face() -> FaceData:
	var wedge := _wedge("w", Vector3.ZERO)
	return _face_facing(wedge, SLOPE)


func test_another_editor_s_axes_in_the_plane_read_as_the_face_projection_turned():
	var face := _slope_face()
	face.uv_projection = BOX
	face.uv_scale = Vector2(0.5, 0.25)
	face.uv_offset = Vector2(0.125, 0.0)
	face.uv_rotation = 0.0  # what the line's rotation field said
	var own: Array = face.face_axes_in(face.world_transform)
	var line_axes: Array = FaceDataScript.turned_axes(own, deg_to_rad(35.0))
	var points := PackedVector3Array([Vector3(0, 0, 5), Vector3(-16, 16, -16), Vector3(8, -8, 3)])

	assert_true(face.read_map_axes(line_axes[0], line_axes[1]), "taken as the Face projection")

	assert_eq(face.uv_projection, FACE)
	var shown := face.shown_uvs_at(points)
	for i in points.size():
		var p: Vector3 = face.world_transform * points[i]
		var read := Vector2(p.dot(line_axes[0]), p.dot(line_axes[1])) * Vector2(0.5, 0.25)
		assert_almost_eq(
			shown[i], read + Vector2(0.125, 0.0), Vector2(EPS, EPS), "as a reader reads it"
		)


func test_a_mirrored_pair_lands_on_the_sign_of_a_scale():
	var face := _slope_face()
	var own: Array = face.face_axes_in(face.world_transform)
	assert_true(face.read_map_axes(-(own[0] as Vector3), own[1]), "a pair reading U backwards")
	assert_eq(face.uv_projection, FACE)
	assert_almost_eq(face.uv_scale, Vector2(-1, 1), Vector2(EPS, EPS), "is U mirrored")
	assert_almost_eq(face.uv_rotation, 0.0, EPS, "and no turn")


func test_a_world_pair_or_a_pair_out_of_the_plane_is_not_the_face_projection():
	var box := _box("b", Vector3.ZERO)
	var east := _face_facing(box, Vector3.RIGHT)
	east.uv_projection = BOX
	var world: Array = east.axes_for(FaceDataScript.UVProjection.PLANAR_X)
	assert_false(east.read_map_axes(world[0], world[1]), "Box UV's own pair on a wall")
	assert_eq(east.uv_projection, BOX)
	var slope := _slope_face()
	slope.uv_projection = BOX
	assert_false(slope.read_map_axes(Vector3.FORWARD, Vector3.DOWN), "a pair off the slope")
	assert_eq(slope.uv_projection, BOX)


func test_a_level_saved_with_the_face_projection_reads_in_an_older_build():
	var face := _slope_face()
	_dress(face, Vector2(0.25, 0.5), Vector2(2, 2), 0.1)
	var record := face.to_dict()
	assert_eq(record["uv_projection"], 5, "the same key, holding the enum's next value")
	assert_eq(record["uv_format_version"], 3, "and no new format an older build would refuse")
	assert_eq(FaceDataScript.from_dict(record).uv_projection, FACE, "this build reads it back")
	assert_true(FaceDataScript.is_valid_projection(FACE))
	assert_false(FaceDataScript.is_valid_projection(FACE + 1), "and nothing past it")


# ===========================================================================
# Align to Face and Align to World
# ===========================================================================


func _make_dock() -> Node:
	var prefs := HFUserPrefsType.new()
	prefs.persistence_enabled = false
	prefs.data = HFUserPrefsType._defaults()
	prefs.data["show_welcome"] = false
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.set_user_prefs(prefs)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	dock.undo_redo = DockUndo.new()
	return dock


## The slope of wedge `w` and the west wall of box `b`, both selected, each with a
## look of its own and one of them laid out by hand.
func _two_selected_faces() -> void:
	var wedge := _wedge("w", Vector3(8, 0, 0))
	var box := _box("b", Vector3(-40, 0, 0))
	var slope := _face_facing(wedge, SLOPE)
	slope.uv_offset = Vector2(0.25, 0.5)
	slope.uv_scale = Vector2(0.5, 2.0)
	slope.uv_rotation = 0.3
	var west := _face_facing(box, Vector3.LEFT)
	west.uv_offset = Vector2(-0.75, 0.0)
	west.ensure_custom_uvs()
	for i in west.custom_uvs.size():
		west.custom_uvs[i] += Vector2(0.37, -0.21)
	root.toggle_face_selection(wedge, wedge.faces.find(slope), true)
	root.toggle_face_selection(box, box.faces.find(west), true)


func _selected_faces() -> Array:
	return [
		_face_facing(root.find_brush_by_id("w") as DraftBrush, SLOPE),
		_face_facing(root.find_brush_by_id("b") as DraftBrush, Vector3.LEFT),
	]


func test_align_to_face_and_to_world_change_every_selected_face_as_one_step():
	_two_selected_faces()
	var dock := _make_dock()
	var undo = dock.undo_redo
	var steps: int = undo.entries.size()

	dock.uv_align_face_btn.pressed.emit()

	assert_eq(undo.entries.size(), steps + 1, "Align to Face is one step")
	var faces := _selected_faces()
	for face in faces:
		assert_eq(face.uv_projection, FACE, "on the Face projection (%s)" % face.normal)
		assert_false(face.has_uv_layout(), "with no hand layout hiding it")
	assert_eq(faces[0].uv_offset, Vector2(0.25, 0.5), "the offset kept")
	assert_eq(faces[0].uv_scale, Vector2(0.5, 2.0), "the scale kept")
	assert_almost_eq(faces[0].uv_rotation, 0.3, EPS, "the rotation kept")
	assert_eq(faces[1].uv_offset, Vector2(-0.75, 0.0), "the other face's offset kept")

	dock.uv_align_face_btn.pressed.emit()
	assert_eq(undo.entries.size(), steps + 1, "a second press changes nothing and leaves no step")

	undo.undo()
	for face in _selected_faces():
		assert_eq(face.uv_projection, BOX, "undone (%s)" % face.normal)
	assert_true(_selected_faces()[1].has_uv_layout(), "with the hand layout back")
	undo.redo()
	for face in _selected_faces():
		assert_eq(face.uv_projection, FACE, "redone (%s)" % face.normal)

	dock.uv_align_world_btn.pressed.emit()

	assert_eq(undo.entries.size(), steps + 2, "Align to World is one step")
	for face in _selected_faces():
		assert_eq(face.uv_projection, BOX, "back on Box UV (%s)" % face.normal)
	await get_tree().process_frame


func test_align_with_no_face_selected_says_so_and_leaves_no_step():
	_wedge("w", Vector3.ZERO)
	var dock := _make_dock()
	var undo = dock.undo_redo
	var steps: int = undo.entries.size()
	dock.uv_align_face_btn.pressed.emit()
	dock.uv_align_world_btn.pressed.emit()
	assert_eq(undo.entries.size(), steps, "nothing to align")
	await get_tree().process_frame


func test_align_to_face_and_to_world_are_commands():
	for id in ["uv_align_face", "uv_align_world"]:
		assert_true(HFCommandRegistry.has(id), "%s is in the registry" % id)
		assert_true(HFCommandRegistry.dispatches(id), "and runs")
