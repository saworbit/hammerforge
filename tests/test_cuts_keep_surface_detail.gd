extends GutTest

## Surface paint and sculpts kept through Clip, Carve and Hollow (#863).
##
## Each piece face used to be built with the face's look and nothing else, so a
## cut wiped every painted face of the brush and every sculpt, and said nothing.
## A box piece then lost its textures as well, on its first resize or reopen:
## the rebuild handed data over by index, and a cut lists faces in its own order.
##
## The scene test writes the file and loads it with the cache ignored. A
## `PackedScene` held in memory hands back the same FaceData objects.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")

const SCENE_PATH := "user://test_cuts_keep_surface_detail.tscn"
const TOP := 2
const SURFACE_TOLERANCE := 0.001

## A name and a paint value per direction, so a face that took another face's
## data shows up as well as one that took none.
const BY_DIRECTION := {
	Vector3i(1, 0, 0): "east",
	Vector3i(-1, 0, 0): "west",
	Vector3i(0, 1, 0): "up",
	Vector3i(0, -1, 0): "down",
	Vector3i(0, 0, 1): "south",
	Vector3i(0, 0, -1): "north",
}

var holder: Node3D


func before_each():
	holder = Node3D.new()
	add_child_autoqfree(holder)


func after_each():
	holder = null
	HFLog.end_test_capture()
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


## A weight mask that says which face it was painted on.
static func _mask_for(direction: Vector3i) -> Image:
	var keys: Array = BY_DIRECTION.keys()
	var k := keys.find(direction)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1 * float(k + 1), 0.0, 0.0, 1.0))
	image.set_pixel(k, 7 - k, Color(1.0, 0.0, 0.0, 1.0))
	return image


## Name every face, and paint it with a mask of its own.
static func _paint_every_face(brush: DraftBrush) -> void:
	for face in brush.get_faces():
		var direction := _direction(face)
		face.map_texture = BY_DIRECTION[direction]
		var layer := FaceData.PaintLayer.new()
		layer.weight_image = _mask_for(direction)
		layer.opacity = 0.75
		layer.blend_mode = FaceData.PaintBlend.MULTIPLY
		face.paint_layers.clear()
		face.paint_layers.append(layer)


## Sculpt the top face into a surface with no two neighbouring heights alike.
func _sculpt_top(root: LevelRoot, brush: DraftBrush, flip := false) -> Resource:
	assert_true(root.create_displacement(brush.brush_id, TOP, 2), "the top face takes a sculpt")
	var sculpt: Resource = brush.faces[TOP].displacement
	var dim: int = sculpt.get_dim()
	for row in dim:
		for col in dim:
			sculpt.set_distance(row, col, float((row * 7 + col * 3) % 5) * 1.5 - 3.0)
			sculpt.set_alpha(row, col, float((row + 2 * col) % 4) / 3.0)
	sculpt.elevation = 1.5
	sculpt.sew_group = 4
	sculpt.flip_diagonals = flip
	return sculpt


## The sculpted surface a face draws, as world space triangles.
static func _surface_triangles(brush: DraftBrush, face: FaceData) -> PackedVector3Array:
	var xform := brush.global_transform
	var out := PackedVector3Array()
	for vertex in face.triangulate()["verts"]:
		out.append(xform * vertex)
	return out


## The height of a surface over (x, z). The sculpts here push straight up, so the
## surface has one height over any point.
static func _height_at(triangles: PackedVector3Array, x: float, z: float) -> float:
	for t in range(0, triangles.size(), 3):
		var a: Vector3 = triangles[t]
		var b: Vector3 = triangles[t + 1]
		var c: Vector3 = triangles[t + 2]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var ap := Vector2(x - a.x, z - a.z)
		var den := ab.x * ac.y - ac.x * ab.y
		if absf(den) < 0.000001:
			continue
		var s := (ap.x * ac.y - ac.x * ap.y) / den
		var t2 := (ab.x * ap.y - ap.x * ab.y) / den
		if s >= -0.0001 and t2 >= -0.0001 and s + t2 <= 1.0001:
			return a.y + s * (b.y - a.y) + t2 * (c.y - a.y)
	return NAN


## Every grid point of a piece's sculpt, in world space.
static func _sculpt_points(brush: DraftBrush, face: FaceData) -> PackedVector3Array:
	var verts := face.local_verts
	var corners: Array[Vector3] = [verts[0], verts[1], verts[3], verts[2]]
	var sculpt: Resource = face.displacement
	var out := PackedVector3Array()
	var dim: int = sculpt.get_dim()
	for row in dim:
		for col in dim:
			out.append(
				(
					brush.global_transform
					* sculpt.get_displaced_position(row, col, corners, face.normal)
				)
			)
	return out


## Faces of `brush` that lie on the top of the original 32 unit box.
static func _top_faces(brush: DraftBrush) -> Array:
	var out: Array = []
	for face in brush.get_faces():
		if _direction(face) == Vector3i(0, 1, 0) and _on_shell(brush, face, 16.0):
			out.append(face)
	return out


## True when every corner of `face` lies on the shell of a box centred on the
## origin, `half` on each side, on the side the face points to.
static func _on_shell(brush: DraftBrush, face: FaceData, half: float) -> bool:
	var axis := _direction(face)
	var outward := Vector3(axis)
	for vertex in face.local_verts:
		var world: Vector3 = brush.global_transform * vertex
		if absf(world.dot(outward) - half) > 0.001:
			return false
	return true


## Every point of every sculpted top piece that is off the original surface.
func _points_off_surface(pieces: Array, surface: PackedVector3Array) -> Array:
	var off: Array = []
	for piece in pieces:
		for face in _top_faces(piece):
			if face.displacement == null:
				continue
			for point in _sculpt_points(piece, face):
				var height := _height_at(surface, point.x, point.z)
				if is_nan(height) or absf(point.y - height) > SURFACE_TOLERANCE:
					off.append("%s is at %.4f, the surface at %.4f" % [point, point.y, height])
	return off


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


## Each face whose texture or paint is not the one painted on the side it faces.
## A face off the original shell is a cut surface, and has to carry no paint.
static func _misplaced_detail(brush: DraftBrush, half := 16.0) -> Array:
	var out: Array = []
	for face in brush.get_faces():
		var direction := _direction(face)
		var label := "%s face of %s" % [BY_DIRECTION.get(direction, "?"), brush.brush_id]
		if not _on_shell(brush, face, half):
			if not face.paint_layers.is_empty():
				out.append("the cut %s is painted" % label)
			continue
		if face.map_texture != BY_DIRECTION[direction]:
			out.append("the %s is named '%s'" % [label, face.map_texture])
		if face.paint_layers.size() != 1:
			out.append("the %s has %d paint layers" % [label, face.paint_layers.size()])
			continue
		var layer = face.paint_layers[0]
		if layer.weight_image == null:
			out.append("the %s has no weight mask" % label)
			continue
		if layer.weight_image.get_data() != _mask_for(direction).get_data():
			out.append("the %s has another face's paint" % label)
		if (
			not is_equal_approx(layer.opacity, 0.75)
			or layer.blend_mode != FaceData.PaintBlend.MULTIPLY
		):
			out.append("the %s lost its layer settings" % label)
	return out


# ===========================================================================
# HFConvexClip: which face a piece came from
# ===========================================================================


func _unit_box_faces() -> Array:
	var b := DraftBrush.new()
	holder.add_child(b)
	b.size = Vector3(32, 32, 32)
	return b.get_faces()


func test_split_names_the_face_each_piece_came_from():
	var faces := _unit_box_faces()
	var halves: Dictionary = HFConvexClip.split(faces, Plane(Vector3.RIGHT, 4.0))
	var origins: Dictionary = halves["origins"]
	var caps := 0
	for side in ["front", "back"]:
		for piece in halves[side]:
			if not origins.has(piece):
				caps += 1
				continue
			var source: FaceData = origins[piece]
			assert_true(faces.has(source), "a piece names a face of the solid it was cut from")
			assert_almost_eq(
				piece.normal.dot(source.normal), 1.0, 0.0001, "and lies in that face's plane"
			)
	assert_eq(caps, 2, "the two caps are pieces of nothing")


func test_progressive_remainder_names_the_first_face_however_often_it_was_cut():
	var faces := _unit_box_faces()
	# Two planes, so the top's corner piece is a piece of a piece.
	var result: Dictionary = HFConvexClip.progressive_remainder(
		faces, [Plane(Vector3.LEFT, -8.0), Plane(Vector3.FORWARD, -8.0)]
	)
	var origins: Dictionary = result["origins"]
	var named := 0
	for piece_set in result["pieces"] + [result["remainder"]]:
		for piece in piece_set:
			if origins.has(piece):
				assert_true(faces.has(origins[piece]), "every piece names a face of the solid")
				named += 1
	assert_gt(named, 0, "and the pieces were named at all")


func test_a_preview_split_carries_no_paint():
	# The clip preview splits on every mouse move. Copying weight masks there would
	# be paid for on each one.
	var faces := _unit_box_faces()
	var layer := FaceData.PaintLayer.new()
	layer.ensure_weight_image(Vector2i(8, 8))
	faces[0].paint_layers.append(layer)
	var halves: Dictionary = HFConvexClip.split(faces, Plane(Vector3.UP, 4.0))
	for side in ["front", "back"]:
		for piece in halves[side]:
			assert_true(piece.paint_layers.is_empty(), "a split alone hands over no paint")


func test_each_piece_face_gets_a_weight_mask_of_its_own():
	var faces := _unit_box_faces()
	var layer := FaceData.PaintLayer.new()
	layer.ensure_weight_image(Vector2i(8, 8))
	faces[0].paint_layers.append(layer)
	var halves: Dictionary = HFConvexClip.split(faces, Plane(Vector3.UP, 4.0))
	HFConvexClip.carry_surface_detail([halves["front"], halves["back"]], halves["origins"])
	var masks: Array = []
	for side in ["front", "back"]:
		for piece in halves[side]:
			if halves["origins"].get(piece) == faces[0]:
				assert_eq(piece.paint_layers.size(), 1, "each piece of the painted face is painted")
				masks.append(piece.paint_layers[0].weight_image)
	assert_eq(masks.size(), 2, "the painted face was cut in two")
	if masks.size() == 2:
		assert_ne(masks[0], masks[1], "the two pieces do not share a mask")
		assert_ne(masks[0], layer.weight_image, "and neither shares the original's")
		assert_eq(masks[0].get_data(), layer.weight_image.get_data(), "but both hold its paint")


# ===========================================================================
# HFDisplacementData.resampled_onto()
# ===========================================================================


func _bumpy_sculpt(flip: bool) -> Resource:
	var sculpt: Resource = HFDisplacementDataScript.new()
	sculpt.init_flat(3)
	var dim: int = sculpt.get_dim()
	for row in dim:
		for col in dim:
			sculpt.set_distance(row, col, float((row * 5 + col * 11) % 7) - 3.0)
			sculpt.set_alpha(row, col, float((row * 3 + col) % 5) / 4.0)
	sculpt.flip_diagonals = flip
	sculpt.elevation = 2.0
	sculpt.sew_group = 7
	return sculpt


func test_a_quad_with_the_face_s_own_corners_turned_round_resamples_to_the_relabelling():
	# The same quad started at another corner is a relabelling, which `remapped()`
	# already does exactly. Orientation and the diagonal flag both have to agree.
	var corners := PackedVector3Array(
		[Vector3(16, 16, -16), Vector3(16, 16, 16), Vector3(-16, 16, 16), Vector3(-16, 16, -16)]
	)
	for flip in [false, true]:
		var sculpt := _bumpy_sculpt(flip)
		for shift in [1, 2, 3]:
			var turned := PackedVector3Array()
			var corner_from := PackedInt32Array()
			for i in 4:
				turned.append(corners[(i + shift) % 4])
				corner_from.append((i + shift) % 4)
			var resampled: Resource = sculpt.resampled_onto(corners, turned)
			var relabelled: Resource = sculpt.remapped(corner_from)
			var label := "turned by %d, flip %s" % [shift, flip]
			assert_eq(resampled.flip_diagonals, relabelled.flip_diagonals, label + ": diagonal")
			for i in relabelled.distances.size():
				if absf(resampled.distances[i] - relabelled.distances[i]) > 0.0001:
					fail_test(
						(
							"%s: height %d is %f, not %f"
							% [label, i, resampled.distances[i], relabelled.distances[i]]
						)
					)
					break
				if absf(resampled.alphas[i] - relabelled.alphas[i]) > 0.0001:
					fail_test("%s: blend %d differs" % [label, i])
					break
			assert_eq(resampled.power, 3, label + ": power")
			assert_eq(resampled.elevation, 2.0, label + ": elevation")
			assert_eq(resampled.sew_group, 7, label + ": sew group")


func test_a_piece_off_the_grid_both_ways_sits_on_the_face_s_surface():
	# One straight cut leaves the piece's rows on the face's grid lines, where any
	# blend of a row's two ends is right. Inside a cell only the cell's own two
	# triangles are, and a piece cut twice has its points inside cells.
	var corners := PackedVector3Array(
		[Vector3(16, 16, -16), Vector3(16, 16, 16), Vector3(-16, 16, 16), Vector3(-16, 16, -16)]
	)
	var piece := PackedVector3Array(
		[Vector3(5, 16, -3), Vector3(5, 16, 13), Vector3(-11, 16, 13), Vector3(-11, 16, -3)]
	)
	for flip in [false, true]:
		var sculpt := _bumpy_sculpt(flip)
		var face_corners: Array[Vector3] = [corners[0], corners[1], corners[3], corners[2]]
		var uv_corners: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]
		var surface: PackedVector3Array = (
			sculpt.triangulate_displaced(face_corners, Vector3.UP, uv_corners)["verts"]
		)
		var resampled: Resource = sculpt.resampled_onto(corners, piece)
		var piece_corners: Array[Vector3] = [piece[0], piece[1], piece[3], piece[2]]
		var dim: int = resampled.get_dim()
		var off := 0
		for row in dim:
			for col in dim:
				var point: Vector3 = resampled.get_displaced_position(
					row, col, piece_corners, Vector3.UP
				)
				if absf(point.y - _height_at(surface, point.x, point.z)) > SURFACE_TOLERANCE:
					off += 1
		assert_eq(off, 0, "flip %s: every grid point on the surface" % flip)


func test_resampling_keeps_a_custom_offset_direction():
	var corners := PackedVector3Array(
		[Vector3(16, 16, -16), Vector3(16, 16, 16), Vector3(-16, 16, 16), Vector3(-16, 16, -16)]
	)
	var half := PackedVector3Array(
		[Vector3(16, 16, -16), Vector3(16, 16, 16), Vector3(0, 16, 16), Vector3(0, 16, -16)]
	)
	var sculpt := _bumpy_sculpt(false)
	var dim: int = sculpt.get_dim()
	for row in dim:
		for col in dim:
			sculpt.set_offset(row, col, Vector3(0.0, 0.6, 0.8))
	var resampled: Resource = sculpt.resampled_onto(corners, half)
	for offset in resampled.offsets:
		assert_almost_eq(offset, Vector3(0.0, 0.6, 0.8), Vector3.ONE * 0.0001)


func test_only_a_quad_can_take_a_sculpt():
	var corners := PackedVector3Array(
		[Vector3(16, 16, -16), Vector3(16, 16, 16), Vector3(-16, 16, 16), Vector3(-16, 16, -16)]
	)
	var triangle := PackedVector3Array([corners[0], corners[1], corners[2]])
	assert_null(_bumpy_sculpt(false).resampled_onto(corners, triangle))


# ===========================================================================
# Clip
# ===========================================================================


func test_a_clip_keeps_every_face_s_paint_on_both_pieces():
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok, "the clip cuts")
	var pieces := _brushes(root)
	assert_eq(pieces.size(), 2, "into two")
	for piece in pieces:
		assert_eq(_misplaced_detail(piece), [], "every face of %s" % piece.brush_id)


func test_paint_samples_the_same_at_the_same_world_point():
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	brush.sync_face_world_transform()
	# Points on four faces, either side of the cut at x = 4.
	var points := [
		Vector3(-9, 16, 5), Vector3(12, 16, -3), Vector3(-2, -7, 16), Vector3(11, 6, -16)
	]
	var before: Array = []
	for point in points:
		before.append(_uv_at(brush, point))
	assert_true(root.brush_system.clip_brush_by_plane(brush.brush_id, Plane(Vector3.RIGHT, 4.0)).ok)
	for i in points.size():
		var found := false
		for piece in _brushes(root):
			piece.sync_face_world_transform()
			var uv: Variant = _uv_at(piece, points[i])
			if uv != null:
				assert_almost_eq(
					uv, before[i], Vector2.ONE * 0.0001, "%s samples the same paint" % points[i]
				)
				found = true
		assert_true(found, "%s is on a piece" % points[i])


## The UV a painted face samples at `point`, or null when no painted face of
## `brush` holds it.
static func _uv_at(brush: DraftBrush, point: Vector3) -> Variant:
	var local: Vector3 = brush.global_transform.affine_inverse() * point
	for face in brush.get_faces():
		if face.paint_layers.is_empty():
			continue
		var plane := Plane(face.normal, face.normal.dot(face.local_verts[0]))
		if absf(plane.distance_to(local)) > 0.001:
			continue
		var bounds: AABB = face.bounds.grow(0.001)
		if not bounds.has_point(local):
			continue
		return face._project_uvs_for_vertices(PackedVector3Array([local]))[0]
	return null


func test_painting_one_piece_afterwards_leaves_the_other_alone():
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	var pieces := _brushes(root)
	var top_a: FaceData = _top_faces(pieces[0])[0]
	var top_b: FaceData = _top_faces(pieces[1])[0]
	top_a.paint_layers[0].weight_image.fill(Color(0.9, 0.0, 0.0, 1.0))
	assert_eq(
		top_b.paint_layers[0].weight_image.get_data(),
		_mask_for(Vector3i(0, 1, 0)).get_data(),
		"the other piece keeps the paint it had"
	)


func test_a_whole_face_keeps_its_sculpt_exactly():
	var root := _fresh_root()
	var brush := _box(root)
	var sculpt := _sculpt_top(root, brush, true)
	var distances: PackedFloat32Array = sculpt.distances.duplicate()
	var alphas: PackedFloat32Array = sculpt.alphas.duplicate()
	# Across Y, so the top face goes whole to the upper piece.
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 1, 4.0).ok)
	var tops: Array = []
	for piece in _brushes(root):
		tops.append_array(_top_faces(piece))
	assert_eq(tops.size(), 1, "one piece has the top")
	var kept: Resource = tops[0].displacement
	assert_not_null(kept, "and its sculpt")
	if kept == null:
		return
	assert_ne(kept, sculpt, "a copy of its own")
	assert_eq(kept.distances, distances, "every height, exactly")
	assert_eq(kept.alphas, alphas, "every blend value")
	assert_true(kept.flip_diagonals, "the diagonal")
	assert_eq(kept.elevation, 1.5, "elevation")
	assert_eq(kept.sew_group, 4, "sew group")


func test_a_cut_sculpt_follows_each_piece_on_the_same_surface():
	var cuts := {
		"on a grid line": Plane(Vector3.RIGHT, 0.0),
		"between grid lines": Plane(Vector3.RIGHT, 5.0),
		"at a slant": Plane(Vector3(1, 0, 0.5).normalized(), 0.0),
	}
	for flip in [false, true]:
		for name in cuts:
			var root := _fresh_root()
			var brush := _box(root)
			_sculpt_top(root, brush, flip)
			var surface := _surface_triangles(brush, brush.faces[TOP])
			assert_true(root.brush_system.clip_brush_by_plane(brush.brush_id, cuts[name]).ok)
			var pieces := _brushes(root)
			var sculpted := 0
			for piece in pieces:
				for face in _top_faces(piece):
					if face.displacement != null:
						sculpted += 1
			var label := "a cut %s, flip %s" % [name, flip]
			assert_eq(sculpted, 2, label + ": both pieces of the top are sculpted")
			assert_eq(_points_off_surface(pieces, surface), [], label + ": on the surface")


func test_a_cut_that_leaves_no_quad_drops_the_sculpt_and_says_so():
	HFLog.begin_test_capture(["could not keep"])
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	_sculpt_top(root, brush)
	var brush_id := brush.brush_id
	# Off one corner of the top: a triangle and a five-sided piece.
	var corner := Plane(Vector3(1, 0, 1).normalized(), 24.0 / sqrt(2.0))
	assert_true(root.brush_system.clip_brush_by_plane(brush_id, corner).ok, "the cut is made")
	var warnings := HFLog.get_captured_warnings()
	assert_eq(warnings.size(), 1, "one warning")
	if warnings.size() == 1:
		assert_string_contains(warnings[0], "Clip could not keep 1 sculpt(s)")
		assert_string_contains(warnings[0], "'%s'" % brush_id, "naming the brush")
	for piece in _brushes(root):
		for face in _top_faces(piece):
			assert_null(face.displacement, "neither piece of the top can hold the sculpt")
		assert_eq(_misplaced_detail(piece), [], "but the paint follows %s" % piece.brush_id)


func test_a_cut_that_keeps_every_sculpt_says_nothing():
	HFLog.begin_test_capture(["could not keep"])
	var root := _fresh_root()
	var brush := _box(root)
	_sculpt_top(root, brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	assert_eq(HFLog.get_captured_warnings(), [], "no warning")


func test_undoing_a_clip_puts_the_painted_sculpted_brush_back():
	# What `HFUndoHelper.commit()` registers for a clip: the level's state before
	# it, restored on undo.
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	var sculpt := _sculpt_top(root, brush)
	var distances: PackedFloat32Array = sculpt.distances.duplicate()
	var brush_id := brush.brush_id
	var before: Dictionary = root.capture_state()
	assert_true(root.brush_system.clip_brush_by_id(brush_id, 0, 0.0).ok)
	root.restore_state(before)
	var pieces := _brushes(root)
	assert_eq(pieces.size(), 1, "one brush again")
	var restored: DraftBrush = root.find_brush_by_id(brush_id) as DraftBrush
	assert_not_null(restored, "the original")
	if restored == null:
		return
	assert_eq(_misplaced_detail(restored), [], "with all its paint")
	var back: Resource = restored.faces[TOP].displacement
	assert_not_null(back, "and its sculpt")
	if back != null:
		assert_eq(back.distances, distances, "whole")


# ===========================================================================
# Carve and Hollow
# ===========================================================================


func test_a_carve_keeps_paint_and_resamples_the_sculpt_from_the_first_face():
	var root := _fresh_root()
	var target := _box(root)
	_paint_every_face(target)
	_sculpt_top(root, target)
	var surface := _surface_triangles(target, target.faces[TOP])
	# A column through the corner at (16, 16): the top is cut once for one piece
	# and twice for the other, so the second has to resample from the first face
	# and not from a resample.
	var carver := _box(root, Vector3(16, 0, 16), Vector3(8, 64, 8))
	assert_true(root.carve_system.carve_with_brush(carver.brush_id).ok, "the carve cuts")
	var pieces: Array = []
	for b in _brushes(root):
		if b.brush_id != carver.brush_id:
			pieces.append(b)
	assert_eq(pieces.size(), 2, "the target was cut into two pieces")
	var sculpted := 0
	for piece in pieces:
		assert_eq(_misplaced_detail(piece), [], "every face of %s" % piece.brush_id)
		for face in _top_faces(piece):
			if face.displacement != null:
				sculpted += 1
	assert_eq(sculpted, 2, "both pieces of the top are sculpted")
	assert_eq(_points_off_surface(pieces, surface), [], "on the surface the face showed")


func test_a_hollow_keeps_paint_and_sculpts_on_the_outside_of_its_walls():
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	_sculpt_top(root, brush)
	var surface := _surface_triangles(brush, brush.faces[TOP])
	assert_true(root.brush_system.hollow_brush_by_id(brush.brush_id, 4.0).ok, "the hollow shells")
	var walls := _brushes(root)
	assert_eq(walls.size(), 6, "six walls")
	var sculpted := 0
	for wall in walls:
		assert_eq(_misplaced_detail(wall), [], "every face of %s" % wall.brush_id)
		for face in _top_faces(wall):
			assert_not_null(face.displacement, "every piece of the top is sculpted")
			sculpted += 1
	assert_gt(sculpted, 0, "the top is on some wall")
	assert_eq(_points_off_surface(walls, surface), [], "on the surface the face showed")


# ===========================================================================
# A box piece keeps its faces' data through a rebuild
# ===========================================================================


func test_a_clipped_piece_keeps_each_face_s_data_through_a_resize():
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	for piece in _brushes(root):
		assert_eq(piece.shape, root.BrushShape.BOX, "the pieces are boxes, so they rebuild")
		piece.size = Vector3(16, 40, 32)
		piece.rebuild_preview()
		assert_eq(_detail_off_its_side(piece), [], "every face of %s" % piece.brush_id)


## Each face named or painted for another side than the one it faces. The cut
## face is named after the face it borrowed its texture from, which faces the
## same way, and is the one face with no paint.
static func _detail_off_its_side(brush: DraftBrush) -> Array:
	var out: Array = []
	var unpainted := 0
	for face in brush.get_faces():
		var direction := _direction(face)
		if face.map_texture != BY_DIRECTION[direction]:
			out.append("the %s face is named '%s'" % [BY_DIRECTION[direction], face.map_texture])
		if face.paint_layers.is_empty():
			unpainted += 1
		elif face.paint_layers[0].weight_image.get_data() != _mask_for(direction).get_data():
			out.append("the %s face has another face's paint" % BY_DIRECTION[direction])
	if unpainted != 1:
		out.append("%d faces are unpainted, not just the cut" % unpainted)
	return out


func test_a_clipped_piece_keeps_each_face_s_data_through_a_save_and_reopen():
	var root := _fresh_root()
	var brush := _box(root)
	_paint_every_face(brush)
	assert_true(root.brush_system.clip_brush_by_id(brush.brush_id, 0, 0.0).ok)
	var copy := _save_and_reopen(root)
	var pieces := _brushes(copy)
	assert_eq(pieces.size(), 2, "both pieces come back")
	for piece in pieces:
		assert_eq(_misplaced_detail(piece), [], "every face of %s" % piece.brush_id)


func test_a_box_stored_in_another_order_keeps_its_sculpt_on_its_face():
	var b := DraftBrush.new()
	b.brush_id = "b1"
	holder.add_child(b)
	b.size = Vector3(32, 32, 32)
	var sculpt: Resource = _bumpy_sculpt(false)
	b.faces[TOP].displacement = sculpt
	var reversed: Array[FaceData] = []
	for i in range(b.faces.size() - 1, -1, -1):
		reversed.append(b.faces[i])
	b.faces = reversed
	b.size = Vector3(32, 48, 32)
	b.rebuild_preview()
	var sculpted: Array = []
	for face in b.faces:
		if face.displacement != null:
			sculpted.append(_direction(face))
	assert_eq(sculpted, [Vector3i(0, 1, 0)], "the sculpt stays on the top")
