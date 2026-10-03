extends GutTest

## A box piece stored the way the box builder makes it (#867, #873).
##
## Clip, Carve, Hollow and the stairs generator describe a piece that is still a
## box as a BOX, so it keeps its resize handles. A box rebuilds on every resize
## and every time its scene opens, and the rebuild lists the faces, and each
## face's corners, the way `_build_box_faces()` makes them. The pieces used to be
## stored the way the cut or the generator made them, so whatever held a face by
## its index read another face once the piece had rebuilt: a face selection, a
## `.map` export, a structure's Update, and the signatures a hollow and a
## structure keep to tell an edit from an untouched piece.
##
## The scene tests write the file and load it with the cache ignored. A
## `PackedScene` held in memory hands back the same FaceData objects.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const SCENE_PATH := "user://test_box_pieces_in_build_order.tscn"

## The builder's slots, in its order, each with a name a face can carry.
const SLOTS := [
	[Vector3i(1, 0, 0), "east"],
	[Vector3i(-1, 0, 0), "west"],
	[Vector3i(0, 1, 0), "up"],
	[Vector3i(0, -1, 0), "down"],
	[Vector3i(0, 0, 1), "south"],
	[Vector3i(0, 0, -1), "north"],
]

var holder: Node3D


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)


func after_each():
	holder = null
	if FileAccess.file_exists(SCENE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE_PATH))


# ===========================================================================
# Fixtures
# ===========================================================================


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, at := Vector3.ZERO, size := Vector3(32, 32, 32)) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": root.BrushShape.BOX,
					"size": size,
					"transform": Transform3D(Basis.IDENTITY, at),
					"operation": CSGShape3D.OPERATION_UNION,
				}
			)
		)
		as DraftBrush
	)


func _brushes(root: LevelRoot) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush:
			out.append(child)
	return out


static func _direction(face: FaceData) -> Vector3i:
	return Vector3i(face.normal.round())


static func _name_for(direction: Vector3i) -> String:
	for slot in SLOTS:
		if slot[0] == direction:
			return slot[1]
	return "?"


## Name every face after the side it faces, so a face that took another face's
## look shows up by name.
static func _name_every_face(brush: DraftBrush) -> void:
	for face in brush.get_faces():
		face.map_texture = _name_for(_direction(face))


## The faces the box builder makes at `size`.
func _built_at(size: Vector3) -> Array:
	var reference: DraftBrush = autofree(DraftBrush.new())
	reference.size = size
	return reference._build_box_faces()


## Each way a box piece differs from the faces the builder makes at its size: a
## face in another slot, or corners that are not exactly the builder's, in its
## order.
func _off_the_build(piece: DraftBrush) -> Array:
	var out: Array = []
	var built := _built_at(piece.size)
	if piece.faces.size() != built.size():
		return ["%s has %d faces" % [piece.brush_id, piece.faces.size()]]
	for i in built.size():
		var face: FaceData = piece.faces[i]
		var want: FaceData = built[i]
		if _direction(face) != _direction(want):
			out.append(
				(
					"%s face %d faces %s, the builder's faces %s"
					% [piece.brush_id, i, _name_for(_direction(face)), _name_for(_direction(want))]
				)
			)
		elif face.local_verts != want.local_verts:
			out.append(
				(
					"%s face %d has corners %s, the builder's are %s"
					% [piece.brush_id, i, face.local_verts, want.local_verts]
				)
			)
	return out


## Every face whose name is not the side it faces.
static func _misnamed(brush: DraftBrush) -> Array:
	var out: Array = []
	for i in brush.faces.size():
		var face: FaceData = brush.faces[i]
		var side := _name_for(_direction(face))
		if face.map_texture != side:
			out.append(
				(
					"%s face %d faces %s and is named '%s'"
					% [brush.brush_id, i, side, face.map_texture]
				)
			)
	return out


static func _index_facing(brush: DraftBrush, direction: Vector3i) -> int:
	for i in brush.faces.size():
		if _direction(brush.faces[i]) == direction:
			return i
	return -1


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


## Save the level the way Ctrl+S does, and open the file again.
func _save_and_reopen(root: LevelRoot) -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


func _stairs(root: LevelRoot) -> HFGenerator:
	var result: HFOpResult = root.create_generator(
		"stairs", HFGeneratorSystem.default_settings("stairs"), Transform3D.IDENTITY
	)
	assert_true(result.ok, "the fixture needs a flight: %s" % result.message)
	return root.generator_system.generators.values()[0]


func _steps(root: LevelRoot, generator_id: String) -> Array:
	var out: Array = []
	for brush_id in root.generator_system.generators[generator_id].brush_ids:
		var step = root.brush_system.find_brush_by_id(str(brush_id))
		assert_true(is_instance_valid(step), "step %s is in the level" % brush_id)
		out.append(step)
	return out


# ===========================================================================
# DraftBrush.faces_in_box_order()
# ===========================================================================


func _bumpy_sculpt() -> Resource:
	var sculpt: Resource = HFDisplacementData.new()
	sculpt.init_flat(2)
	var dim: int = sculpt.get_dim()
	for row in dim:
		for col in dim:
			sculpt.set_distance(row, col, float((row * 5 + col * 11) % 7) - 3.0)
	sculpt.elevation = 1.5
	return sculpt


## Where each point of a face's sculpt is, in no particular order.
static func _sculpt_points(face: FaceData) -> Array:
	var verts := face.local_verts
	var corners: Array[Vector3] = [verts[0], verts[1], verts[3], verts[2]]
	var out: Array = []
	var dim: int = face.displacement.get_dim()
	for row in dim:
		for col in dim:
			out.append(face.displacement.get_displaced_position(row, col, corners, face.normal))
	return out


## Each point of `want` that has no point of `got` within a hair of it.
static func _points_missing(got: Array, want: Array) -> Array:
	var out: Array = []
	for point in want:
		var found := false
		for other in got:
			if (other as Vector3).distance_to(point) < 0.0001:
				found = true
				break
		if not found:
			out.append(point)
	return out


## The custom UV at each corner, keyed by where the corner is.
static func _uv_at_corners(face: FaceData) -> Dictionary:
	var out: Dictionary = {}
	for i in face.local_verts.size():
		out[str(face.local_verts[i].snapped(Vector3.ONE * 0.001))] = face.custom_uvs[i]
	return out


static func _verts_of(face_list: Array) -> Array:
	var out: Array = []
	for face in face_list:
		out.append(face.local_verts)
	return out


func test_faces_turned_and_shuffled_come_back_the_way_a_box_builds():
	var size := Vector3(40, 24, 56)
	var faces := _built_at(size)
	var top: FaceData = faces[2]
	var east: FaceData = faces[0]
	top.displacement = _bumpy_sculpt()
	east.custom_uvs = PackedVector2Array(
		[Vector2(0, 0), Vector2(0.5, 0.1), Vector2(1, 1), Vector2(0.2, 0.9)]
	)
	# Started at another corner, as a cut leaves them. Nothing moves in the world.
	HFTransformSystem.start_face_at(top, top.local_verts[2])
	HFTransformSystem.start_face_at(east, east.local_verts[1])
	var surface := _sculpt_points(top)
	var uvs := _uv_at_corners(east)
	var shuffled: Array = faces.duplicate()
	shuffled.reverse()

	var ordered := DraftBrush.faces_in_box_order(shuffled, size)

	var built := _built_at(size)
	assert_eq(ordered.size(), built.size())
	for i in built.size():
		assert_eq(_direction(ordered[i]), _direction(built[i]), "slot %d" % i)
		assert_eq(ordered[i].local_verts, built[i].local_verts, "slot %d corners" % i)
	assert_same(ordered[2], top, "the face itself, with all its data")
	assert_eq(_points_missing(_sculpt_points(ordered[2]), surface), [], "the sculpt has not moved")
	assert_eq(_uv_at_corners(ordered[0]), uvs, "each custom UV is on its corner")


func test_faces_of_another_size_are_left_alone():
	var faces := _built_at(Vector3(32, 32, 32))
	var before := _verts_of(faces)
	var answer := DraftBrush.faces_in_box_order(faces, Vector3(48, 32, 32))
	assert_same(answer, faces)
	assert_eq(_verts_of(faces), before, "no corner moved")


func test_a_set_with_one_face_wound_the_other_way_is_left_alone():
	# All or nothing: the faces that do fit are not moved either.
	var faces := _built_at(Vector3(32, 32, 32))
	var inside_out: PackedVector3Array = faces[3].local_verts
	inside_out.reverse()
	faces[3].local_verts = inside_out
	faces.reverse()
	var before := _verts_of(faces)
	var answer := DraftBrush.faces_in_box_order(faces, Vector3(32, 32, 32))
	assert_same(answer, faces)
	assert_eq(_verts_of(faces), before, "no corner moved")


func test_a_set_with_a_face_missing_is_left_alone():
	var faces := _built_at(Vector3(32, 32, 32))
	faces.pop_back()
	assert_same(DraftBrush.faces_in_box_order(faces, Vector3(32, 32, 32)), faces)


# ===========================================================================
# Every cut and generator stores a box piece the way the builder makes it
# ===========================================================================


func test_a_clipped_piece_is_stored_the_way_a_box_builds():
	var root := _fresh_root()
	var brush := _box(root)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	var pieces := _brushes(root)
	assert_eq(pieces.size(), 2, "two pieces")
	for piece in pieces:
		assert_eq(piece.shape, root.BrushShape.BOX)
		assert_eq(_off_the_build(piece), [], "piece %s" % piece.brush_id)


func test_a_piece_clipped_off_centre_on_another_axis_is_stored_the_way_a_box_builds():
	var root := _fresh_root()
	var brush := _box(root, Vector3(5, -3, 7), Vector3(48, 24, 40))
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 2, 13.0).ok)
	for piece in _brushes(root):
		assert_eq(_off_the_build(piece), [], "piece %s" % piece.brush_id)


func test_carved_pieces_are_stored_the_way_a_box_builds():
	var root := _fresh_root()
	var target := _box(root)
	var carver := _box(root, Vector3.ZERO, Vector3(8, 64, 8))
	assert_true(root.carve_with_brush(carver.brush_id).ok)
	var pieces: Array = []
	for piece in _brushes(root):
		if piece.brush_id != carver.brush_id and piece.brush_id != target.brush_id:
			pieces.append(piece)
	assert_gt(pieces.size(), 1, "the carve left pieces around the hole")
	for piece in pieces:
		assert_eq(piece.shape, root.BrushShape.BOX, "a box carved by a box leaves boxes")
		assert_eq(_off_the_build(piece), [], "piece %s" % piece.brush_id)


func test_hollow_walls_are_stored_the_way_a_box_builds():
	var root := _fresh_root()
	var brush := _box(root, Vector3.ZERO, Vector3(64, 64, 64))
	assert_true(root.brush_system.hollow_brush_by_id(brush.brush_id, 4.0).ok)
	var walls := _brushes(root)
	assert_eq(walls.size(), 6, "a box shells into six walls")
	for wall in walls:
		assert_eq(_off_the_build(wall), [], "wall %s" % wall.brush_id)


func test_hollow_walls_off_the_grid_have_exactly_the_builder_s_corners():
	# Centring a piece on itself leaves float noise in every corner, and the
	# signature a hollow keeps rounds them: a corner on a rounding boundary would
	# read differently once the builder put it back exactly.
	var root := _fresh_root()
	var brush := _box(root, Vector3(13.3, 7.1, -5.7), Vector3(50.6, 30.2, 70.4))
	assert_true(root.brush_system.hollow_brush_by_id(brush.brush_id, 3.3).ok)
	for wall in _brushes(root):
		assert_eq(_off_the_build(wall), [], "wall %s" % wall.brush_id)


func test_stair_steps_are_stored_the_way_a_box_builds():
	var root := _fresh_root()
	var record := _stairs(root)
	var steps := _steps(root, record.generator_id)
	assert_gt(steps.size(), 1, "a flight has steps")
	for step in steps:
		assert_eq(step.shape, root.BrushShape.BOX, "a step is a box")
		assert_eq(_off_the_build(step), [], "step %s" % step.brush_id)


func test_a_rebuild_changes_nothing_a_clip_stored():
	var root := _fresh_root()
	var brush := _box(root)
	_name_every_face(brush)
	for face in brush.get_faces():
		root.surface_paint.paint_at_uv(face, 0, Vector2(0.25, 0.25), 0.1, 1.0)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	for piece in _brushes(root):
		var before := HFDuplicator.shape_signature(piece)
		piece.size = piece.size
		assert_eq(HFDuplicator.shape_signature(piece), before, "piece %s" % piece.brush_id)


# ===========================================================================
# A face index names the same face after the piece rebuilds
# ===========================================================================


func test_a_selected_face_is_the_same_face_after_a_resize():
	var root := _fresh_root()
	var brush := _box(root)
	_name_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	for piece in _brushes(root):
		root.toggle_face_selection(piece, _index_facing(piece, Vector3i(0, 1, 0)), false)
		piece.size = Vector3(16, 40, 32)
		var picked: Dictionary = root.get_primary_selected_face()
		assert_eq(picked.get("brush"), piece, "the selection is still on this piece")
		var face: FaceData = piece.faces[int(picked["face_idx"])]
		assert_eq(_direction(face), Vector3i(0, 1, 0), "the selection is still the top")
		assert_eq(face.map_texture, "up")


func test_a_face_index_names_the_same_face_after_a_save_and_reopen():
	var root := _fresh_root()
	var brush := _box(root)
	_name_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	var sides: Dictionary = {}
	for piece in _brushes(root):
		var listed: Array = []
		for face in piece.faces:
			listed.append(face.map_texture)
		sides[piece.brush_id] = listed
	var copy := _save_and_reopen(root)
	for piece in _brushes(copy):
		var listed: Array = []
		for face in piece.faces:
			listed.append(face.map_texture)
		assert_eq(listed, sides[piece.brush_id], "piece %s" % piece.brush_id)
		assert_eq(_misnamed(piece), [], "and each face is still on its own side")


# ===========================================================================
# The .map export writes each plane with its own face
# ===========================================================================


func test_a_clipped_piece_exports_each_plane_with_its_own_texture():
	var root := _fresh_root()
	var brush := _box(root)
	_name_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	for piece in _brushes(root):
		var lines: Array = MapIO._box_to_map_lines(piece)
		assert_eq(lines.size(), SLOTS.size())
		for i in lines.size():
			assert_string_contains(
				str(lines[i]),
				" %s " % SLOTS[i][1],
				"the %s plane of %s" % [SLOTS[i][1], piece.brush_id]
			)


func test_a_box_stored_in_another_order_exports_each_plane_with_its_own_texture():
	# A level saved as an .hflevel before the pieces were stored in build order
	# loads them as they were, and a load does not rebuild them.
	var b := DraftBrush.new()
	holder.add_child(b)
	b.size = Vector3(32, 32, 32)
	_name_every_face(b)
	var reversed: Array[FaceData] = b.faces.duplicate()
	reversed.reverse()
	b.faces = reversed
	var lines: Array = MapIO._box_to_map_lines(b)
	for i in lines.size():
		assert_string_contains(str(lines[i]), " %s " % SLOTS[i][1], "the %s plane" % SLOTS[i][1])


# ===========================================================================
# A flight of stairs through a save and reopen
# ===========================================================================


func test_an_untouched_flight_counts_no_step_edited_after_its_scene_is_reopened():
	var root := _fresh_root()
	var record := _stairs(root)
	assert_eq(root.edited_generator_pieces(record.generator_id), 0)
	var copy := _save_and_reopen(root)
	assert_eq(copy.edited_generator_pieces(record.generator_id), 0)


func test_update_after_a_reopen_keeps_every_step_face_s_look_on_its_side():
	var root := _fresh_root()
	var record := _stairs(root)
	for step in _steps(root, record.generator_id):
		_name_every_face(step)
	var copy := _save_and_reopen(root)
	var settings := HFGeneratorSystem.default_settings("stairs")
	assert_true(copy.regenerate_generator(record.generator_id, settings).ok)
	for step in _steps(copy, record.generator_id):
		assert_eq(_misnamed(step), [], "step %s" % step.brush_id)


func test_update_keeps_each_face_s_look_on_its_side_when_a_step_is_stored_in_another_order():
	# Steps loaded from an .hflevel written before this change are stored the way
	# the stairs builder made them, and a load does not rebuild them. Update makes
	# the new steps the way the box builder does.
	var root := _fresh_root()
	var record := _stairs(root)
	for step in _steps(root, record.generator_id):
		_name_every_face(step)
		var reversed: Array[FaceData] = step.faces.duplicate()
		reversed.reverse()
		step.faces = reversed
	var settings := HFGeneratorSystem.default_settings("stairs")
	assert_true(root.regenerate_generator(record.generator_id, settings).ok)
	for step in _steps(root, record.generator_id):
		assert_eq(_misnamed(step), [], "step %s" % step.brush_id)


# ===========================================================================
# Records written before the pieces were stored the way a box builds (#878)
# ===========================================================================

const OLD_LEVEL_PATH := "user://test_box_pieces_in_build_order.hflevel"


## Put a piece's faces back the way a cut or the stairs builder left them before
## #879: in another order, each starting at another corner. Nothing rebuilds it
## during the session, as nothing did then.
static func _store_the_old_way(piece: DraftBrush) -> void:
	var turned: Array[FaceData] = []
	for face in piece.faces:
		HFTransformSystem.start_face_at(face, face.local_verts[1])
		turned.append(face)
	turned.reverse()
	piece.faces = turned


## A hollow whose walls and record are the way a build before #879 wrote them.
func _old_hollow(root: LevelRoot) -> String:
	var solid := _box(root, Vector3.ZERO, Vector3(64, 64, 64))
	assert_true(root.brush_system.hollow_brush_by_id(solid.brush_id, 4.0).ok)
	var record: Dictionary = root.brush_system.capture_hollows()[0]
	var hollow_id := str(record["hollow_id"])
	var live: Dictionary = root.brush_system.hollow_for_id(hollow_id)
	var shapes: Array = live["wall_shapes"]
	for i in live["wall_ids"].size():
		var wall: DraftBrush = root.brush_system.find_brush_by_id(str(live["wall_ids"][i]))
		_store_the_old_way(wall)
		shapes[i] = HFDuplicator.shape_signature(wall)
	assert_eq(root.edited_hollow_walls(hollow_id), 0, "the old record matches its old walls")
	return hollow_id


## A flight whose steps and record are the way a build before #879 wrote them.
func _old_stairs(root: LevelRoot) -> HFGenerator:
	var record := _stairs(root)
	for step in _steps(root, record.generator_id):
		_store_the_old_way(step)
	root.generator_system._record_signatures(record)
	assert_eq(root.edited_generator_pieces(record.generator_id), 0, "the old record matches")
	return record


func _walls(root: LevelRoot, hollow_id: String) -> Array:
	var out: Array = []
	for wall_id in root.brush_system.hollow_for_id(hollow_id)["wall_ids"]:
		out.append(root.brush_system.find_brush_by_id(str(wall_id)))
	return out


func test_an_old_hollow_saved_untouched_counts_no_wall_after_a_reopen():
	var root := _fresh_root()
	var hollow_id := _old_hollow(root)
	var copy := _save_and_reopen(root)
	assert_eq(copy.edited_hollow_walls(hollow_id), 0, "every wall is the one it was")


func test_an_old_flight_saved_untouched_counts_no_step_after_a_reopen():
	var root := _fresh_root()
	var record := _old_stairs(root)
	var copy := _save_and_reopen(root)
	assert_eq(copy.edited_generator_pieces(record.generator_id), 0, "every step is the one it was")


func test_an_old_hollow_s_walls_edited_before_the_save_still_count():
	var root := _fresh_root()
	var hollow_id := _old_hollow(root)
	var walls := _walls(root, hollow_id)
	walls[0].faces[0].material_idx = 3
	walls[1].size = walls[1].size + Vector3(2, 0, 0)
	walls[2].global_position += Vector3(0, 8, 0)
	var layer := FaceData.PaintLayer.new()
	layer.ensure_weight_image(Vector2i(8, 8))
	walls[3].faces[0].paint_layers.append(layer)
	var before := root.edited_hollow_walls(hollow_id)
	assert_eq(before, 4, "retextured, resized, moved and painted")

	var copy := _save_and_reopen(root)

	assert_eq(copy.edited_hollow_walls(hollow_id), before, "and still after the reopen")


func test_an_old_flight_s_step_edited_before_the_save_still_counts():
	var root := _fresh_root()
	var record := _old_stairs(root)
	var steps := _steps(root, record.generator_id)
	steps[0].size = steps[0].size + Vector3(0, 0, 4)
	assert_eq(root.edited_generator_pieces(record.generator_id), 1, "the resized step")

	var copy := _save_and_reopen(root)

	assert_eq(copy.edited_generator_pieces(record.generator_id), 1, "and still after the reopen")


func test_the_faces_as_loaded_are_let_go_once_the_records_are_back():
	var root := _fresh_root()
	var hollow_id := _old_hollow(root)
	var copy := _save_and_reopen(root)
	for wall in _walls(copy, hollow_id):
		assert_eq(wall.faces_as_loaded, [], "%s keeps no copy of its old faces" % wall.brush_id)


## An .hflevel written before #879 holds a piece in the cut's order, and loading
## one does not rebuild it, so it stayed in that order until its first resize,
## which moved a face selection onto another face.
func _reload_hflevel(root: LevelRoot) -> void:
	assert_eq(HFLevelIO.save_to_path(OLD_LEVEL_PATH, root._capture_hflevel_state()), OK)
	assert_true(root.load_hflevel(OLD_LEVEL_PATH), "the level loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_LEVEL_PATH))


func test_a_face_of_a_piece_from_an_old_hflevel_is_the_same_face_after_a_resize():
	var root := _fresh_root()
	var brush := _box(root, Vector3.ZERO, Vector3(32, 32, 32))
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 1, 4.0).ok)
	for piece in _brushes(root):
		_name_every_face(piece)
		_store_the_old_way(piece)

	_reload_hflevel(root)

	for piece in _brushes(root):
		var top := _index_facing(piece, Vector3i(0, 1, 0))
		piece.size = piece.size + Vector3(4, 0, 0)
		assert_eq(_direction(piece.faces[top]), Vector3i(0, 1, 0), "face %d is still the top" % top)
		assert_eq(_misnamed(piece), [], "and every face kept its own look")


func test_an_old_hollow_read_from_an_old_hflevel_counts_no_wall():
	var root := _fresh_root()
	var hollow_id := _old_hollow(root)
	_reload_hflevel(root)
	assert_eq(root.edited_hollow_walls(hollow_id), 0, "every wall is the one it was")
