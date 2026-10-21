extends GutTest

## Mirror Copy (#1434): the selection stays where it is and gains a mirrored copy
## across each ticked axis and each combination of them. Each copy is a duplicate
## put through Flip's fold, so it has to keep a positive determinant, stay one
## convex brush and carry its faces' look to the faces the mirror sends them to.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const FaceDataScript = preload("res://addons/hammerforge/face_data.gd")
const HFDisplacementDataScript = preload("res://addons/hammerforge/displacement_data.gd")
const HFTransformSystemScript = preload("res://addons/hammerforge/systems/hf_transform_system.gd")
const HFBrushEntityScript = preload("res://addons/hammerforge/hf_brush_entity.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

const X := 1
const Y := 2
const Z := 4
const EPS := 0.001
const V_EPS := Vector3(0.001, 0.001, 0.001)
const DIRECTIONS := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
]

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


# ===========================================================================
# Helpers
# ===========================================================================


func _box(
	brush_id: String,
	center: Vector3,
	size := Vector3(32, 16, 8),
	shape: int = DraftBrush.BrushShape.BOX
) -> DraftBrush:
	var info := {"size": size, "center": center, "brush_id": brush_id, "shape": shape}
	var b := root.create_brush_from_info(info) as DraftBrush
	if b.get_faces().is_empty():
		b.rebuild_preview()
	return b


## A box whose six faces each look different, on every part of the look.
func _dressed_box(brush_id: String, center: Vector3) -> DraftBrush:
	var b := _box(brush_id, center)
	for i in DIRECTIONS.size():
		var face = _face_facing(b, DIRECTIONS[i])
		face.material_idx = i
		face.uv_scale = Vector2(1.0 + i * 0.5, 2.0 - i * 0.25)
		face.uv_offset = Vector2(3.0 * i + 1.0, -2.0 * i + 0.5)
		face.uv_rotation = 0.1 + 0.2 * i
	b.rebuild_preview()
	return b


func _mirror(ids: Array, paths: Array, axes: int, pivot := Vector3.ZERO) -> Dictionary:
	return root.mirror_copy_managed_nodes(ids, paths, axes, pivot)


func _copy(id: Variant) -> DraftBrush:
	return root.find_brush_by_id(str(id)) as DraftBrush


## The combinations of `axes` a Mirror Copy makes a copy for, as bits.
static func _combinations(axes: int) -> Array:
	var out: Array = []
	for combination in range(1, 8):
		if (combination & ~axes) == 0:
			out.append(combination)
	return out


static func _mirrored(point: Vector3, combination: int, pivot: Vector3) -> Vector3:
	var out := point
	for axis in 3:
		if (combination & (1 << axis)) != 0:
			out[axis] = 2.0 * pivot[axis] - out[axis]
	return out


static func _reflected(direction: Vector3, combination: int) -> Vector3:
	return _mirrored(direction, combination, Vector3.ZERO)


static func _world_verts(draft: DraftBrush) -> Array:
	var out: Array = []
	var xform := draft.global_transform
	for face in draft.get_faces():
		if face == null:
			continue
		for v in face.local_verts:
			out.append(xform * v)
	return out


static func _keys(points: Array) -> Array:
	var keys: Array = []
	for p in points:
		keys.append(_key(p))
	keys.sort()
	return keys


static func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)]


static func _face_facing(draft: DraftBrush, direction: Vector3):
	var basis := draft.global_transform.basis
	for face in draft.get_faces():
		if face == null:
			continue
		if face.normal_through(basis).dot(direction.normalized()) > 0.99:
			return face
	return null


## The UV a face shows at each of its corners, as `[world point, uv]` pairs.
static func _corner_uvs(draft: DraftBrush, face) -> Array:
	draft.sync_face_world_transform()
	var out: Array = []
	var uvs: PackedVector2Array = face._project_uvs_for_vertices(face.local_verts)
	for i in face.local_verts.size():
		out.append([draft.global_transform * face.local_verts[i], uvs[i]])
	return out


## The same, keyed by where each corner is.
static func _uvs_by_corner(draft: DraftBrush, face) -> Dictionary:
	var out := {}
	for pair in _corner_uvs(draft, face):
		out[_key(pair[0])] = pair[1]
	return out


static func _bounds(draft: DraftBrush) -> AABB:
	var points := _world_verts(draft)
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


## Every displaced triangle of a brush, as three world points.
static func _displaced_triangles(draft: DraftBrush) -> Array:
	var out: Array = []
	var xform := draft.global_transform
	for face in draft.get_faces():
		if face == null or face.displacement == null:
			continue
		var verts: PackedVector3Array = face.triangulate()["verts"]
		for t in range(0, verts.size(), 3):
			out.append([xform * verts[t], xform * verts[t + 1], xform * verts[t + 2]])
	return out


## Triangles mirrored through `combination` at `pivot`, each reversed once per
## mirror so a mirrored solid still winds clockwise from outside.
static func _mirrored_triangles(triangles: Array, combination: int, pivot: Vector3) -> Array:
	var mirrors := 0
	for axis in 3:
		if (combination & (1 << axis)) != 0:
			mirrors += 1
	var out: Array = []
	for tri in triangles:
		var points: Array = []
		for p in tri:
			points.append(_mirrored(p, combination, pivot))
		out.append(points if mirrors % 2 == 0 else [points[0], points[2], points[1]])
	return out


## Triangles as a sorted set of keys, each starting from its smallest corner and
## keeping its winding, so a triangle turned inside out does not compare equal.
static func _triangle_keys(triangles: Array) -> Array:
	var out: Array = []
	for tri in triangles:
		var keys: Array = [_key(tri[0]), _key(tri[1]), _key(tri[2])]
		var first := 0
		for k in 3:
			if keys[k] < keys[first]:
				first = k
		out.append("%s|%s|%s" % [keys[first], keys[(first + 1) % 3], keys[(first + 2) % 3]])
	out.sort()
	return out


func _sculpt(face) -> void:
	var disp = HFDisplacementDataScript.new()
	disp.init_flat(2)
	var d: int = disp.get_dim()
	for row in d:
		for col in d:
			disp.set_distance(row, col, row * 1.0 + col * 0.25 + 0.5 * ((row * col) % 3))
			disp.set_alpha(row, col, fposmod(row * 0.13 + col * 0.29, 1.0))
	face.displacement = disp


func _entity(entity_name: String, at: Vector3, angle: float) -> DraftEntity:
	var e := DraftEntity.new()
	e.name = entity_name
	e.entity_data = {"angle": angle}
	root.entities_node.add_child(e)
	e.global_position = at
	return e


# ===========================================================================
# Where the copies go
# ===========================================================================


func test_x_through_the_world_origin_makes_one_copy_at_the_mirrored_place():
	var b := _box("a", Vector3(48, 4, -6))
	var original_verts := _world_verts(b)

	var made := _mirror(["a"], [], X)

	var ids: Array = made["brush_ids"]
	assert_eq(ids.size(), 1, "one copy")
	assert_ne(str(ids[0]), "a", "under an id of its own")
	var copy := _copy(ids[0])
	assert_not_null(copy, "the copy is in the level")
	assert_almost_eq(copy.global_position, Vector3(-48, 4, -6), V_EPS, "across X")
	assert_gt(copy.global_transform.basis.determinant(), 0.0, "right-handed")
	var expected: Array = []
	for p in original_verts:
		expected.append(_mirrored(p, X, Vector3.ZERO))
	assert_eq(_keys(_world_verts(copy)), _keys(expected), "every corner mirrored")
	assert_eq(_keys(_world_verts(b)), _keys(original_verts), "the original stays as it was")
	assert_almost_eq(b.global_position, Vector3(48, 4, -6), V_EPS)


func test_x_and_z_make_three_copies_of_each_brush_at_the_three_mirrored_places():
	_box("a", Vector3(48, 4, 20))
	_box("b", Vector3(10, 0, 6), Vector3(4, 4, 4))
	var brushes_before: int = root.draft_brushes_node.get_child_count()

	var made := _mirror(["a", "b"], [], X | Z)

	var ids: Array = made["brush_ids"]
	assert_eq(ids.size(), 6, "three copies of each of two brushes")
	assert_eq(root.draft_brushes_node.get_child_count(), brushes_before + 6)
	var at: Array = []
	for id in ids:
		at.append(_copy(id).global_position)
	var expected: Array = []
	for origin in [Vector3(48, 4, 20), Vector3(10, 0, 6)]:
		for combination in [X, Z, X | Z]:
			expected.append(_mirrored(origin, combination, Vector3.ZERO))
	assert_eq(_keys(at), _keys(expected), "across X, across Z, and across both")


## The acceptance pin: every combination of the three axes, its count, where
## each copy stands, its determinant, and the look each face of it carries.
## Texture Lock is off, so the look is carried exactly as Flip carries it.
func test_every_axis_combination_pins_positions_determinants_and_looks():
	root.texture_lock = false
	var origin := Vector3(48, 12, -20)
	var pivot := Vector3(4, -2, 6)
	var b := _dressed_box("a", origin)
	for axes in range(1, 8):
		var combinations := _combinations(axes)
		var made := _mirror(["a"], [], axes, pivot)
		var ids: Array = made["brush_ids"]
		assert_eq(ids.size(), combinations.size(), "axes %d: 2^n - 1 copies" % axes)
		for id in ids:
			var copy := _copy(id)
			var combination := -1
			for candidate in combinations:
				if copy.global_position.is_equal_approx(_mirrored(origin, candidate, pivot)):
					combination = candidate
			assert_gt(combination, 0, "axes %d: a copy stands at a mirrored place" % axes)
			combinations.erase(combination)
			var basis := copy.global_transform.basis
			assert_almost_eq(basis.determinant(), 1.0, EPS, "axes %d: determinant +1" % axes)
			assert_true(HFTransformSystemScript.is_rotation_basis(basis), "axes %d" % axes)
			assert_eq(copy.shape, DraftBrush.BrushShape.BOX, "axes %d: still a box" % axes)
			for direction in DIRECTIONS:
				var source = _face_facing(b, direction)
				var landed = _face_facing(copy, _reflected(direction, combination))
				var where := "axes %d, %s face" % [axes, str(direction)]
				assert_not_null(landed, where)
				if landed == null:
					continue
				assert_eq(landed.material_idx, source.material_idx, where + ": material")
				assert_almost_eq(landed.uv_scale, source.uv_scale, Vector2(EPS, EPS), where)
				assert_almost_eq(landed.uv_offset, source.uv_offset, Vector2(EPS, EPS), where)
				assert_almost_eq(landed.uv_rotation, source.uv_rotation, EPS, where)
		assert_eq(combinations, [], "axes %d: one copy at each mirrored place" % axes)


func test_selection_edge_puts_each_copy_flush_against_the_original():
	# A half of something, two brushes wide: the copy of the whole half lands
	# beside it, touching it and overlapping nothing.
	var a := _box("a", Vector3(4, 2, 0), Vector3(8, 4, 8))
	var b := _box("b", Vector3(10, 2, 0), Vector3(4, 4, 8))
	root.mirror_copy_at_edge = true
	var pivot := root.resolve_mirror_copy_pivot(["a", "b"], [])
	assert_almost_eq(pivot, Vector3(12, 4, 4), V_EPS, "the far side of the bounds")

	var made := _mirror(["a", "b"], [], X | Z, pivot)

	var originals := _bounds(a).merge(_bounds(b))
	var copies: Array = []
	for id in made["brush_ids"]:
		copies.append(_bounds(_copy(id)))
	assert_eq(copies.size(), 6)
	var x_copies := AABB()
	for i in copies.size():
		var box: AABB = copies[i]
		for other in [_bounds(a), _bounds(b)]:
			assert_false(box.intersects(other), "copy %d overlaps no original" % i)
		for j in copies.size():
			if j != i:
				assert_false(box.intersects(copies[j]), "copy %d overlaps no other copy" % i)
	for id in made["brush_ids"].slice(0, 2):
		var box := _bounds(_copy(id))
		x_copies = box if not x_copies.has_volume() else x_copies.merge(box)
	assert_almost_eq(x_copies.position.x, originals.end.x, EPS, "the X copy starts where it ends")
	assert_almost_eq(x_copies.size, originals.size, V_EPS, "and is the same size")
	assert_almost_eq(x_copies.position.z, originals.position.z, EPS, "beside it, not behind it")


func test_without_the_edge_the_planes_go_through_the_transform_pivot():
	_box("a", Vector3(10, 0, 0))
	root.mirror_copy_at_edge = false
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.WORLD_ORIGIN
	assert_eq(root.resolve_mirror_copy_pivot(["a"], []), Vector3.ZERO)
	root.transform_pivot_mode = HFTransformSystemScript.PivotMode.ACTIVE
	assert_eq(root.resolve_mirror_copy_pivot(["a"], []), Vector3(10, 0, 0))


# ===========================================================================
# What a copy is
# ===========================================================================


func test_every_copy_of_a_turned_wedge_is_right_handed_wound_outward_and_valid():
	# A wedge is a shape a mirror changes, so each copy takes Flip's exact path,
	# and a turned one tests the fold off the world axes. Faces built through a
	# negative determinant would look right here and bake inside out (#749).
	var b := _box("w", Vector3(30, 6, -12), Vector3(16, 8, 12), DraftBrush.BrushShape.WEDGE)
	b.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), b.global_position)
	b.rebuild_preview()
	var issues_before: Array = root.validate_level()["issues"]
	var original_verts := _world_verts(b)
	var pivot := Vector3(2, 1, 3)

	var made := _mirror(["w"], [], X | Y | Z, pivot)

	var ids: Array = made["brush_ids"]
	assert_eq(ids.size(), 7)
	var expected_sets: Array = []
	for combination in _combinations(X | Y | Z):
		var points: Array = []
		for p in original_verts:
			points.append(_mirrored(p, combination, pivot))
		expected_sets.append(_keys(points))
	for id in ids:
		var copy := _copy(id)
		var basis := copy.global_transform.basis
		assert_gt(basis.determinant(), 0.0, "%s is right-handed" % id)
		assert_has(expected_sets, _keys(_world_verts(copy)), "%s is a mirror of the wedge" % id)
		var centre := Vector3.ZERO
		var points := _world_verts(copy)
		for p in points:
			centre += p
		centre /= float(points.size())
		for face in copy.get_faces():
			var a: Vector3 = copy.global_transform * face.local_verts[0]
			var second: Vector3 = copy.global_transform * face.local_verts[1]
			var third: Vector3 = copy.global_transform * face.local_verts[2]
			# Clockwise from outside, the same cross product FaceData uses.
			var normal := (third - a).cross(second - a).normalized()
			var face_centre := (a + second + third) / 3.0
			assert_gt(normal.dot(face_centre - centre), 0.0, "%s faces point out" % id)
	assert_eq(root.validate_level()["issues"], issues_before, "the copies add no issue")


func test_a_sculpt_and_paint_are_mirrored_with_their_faces():
	var pivot := Vector3(10, -4, 6)
	for combination in [X, Y, Z, X | Z]:
		var id := "s%d" % combination
		var b := _box(id, Vector3(48, 8, -16), Vector3(32, 24, 40))
		_sculpt(_face_facing(b, Vector3.RIGHT))
		var layer := FaceDataScript.PaintLayer.new()
		layer.opacity = 0.25
		_face_facing(b, Vector3.UP).paint_layers.append(layer)
		b.rebuild_preview()
		var expected := _triangle_keys(
			_mirrored_triangles(_displaced_triangles(b), combination, pivot)
		)

		var made := _mirror([id], [], combination, pivot)

		# The copy across every axis asked for is made last; X and Z make one
		# across each of them first.
		var copy := _copy(made["brush_ids"][-1])
		assert_eq(_triangle_keys(_displaced_triangles(copy)), expected, "%d: sculpt" % combination)
		var painted = _face_facing(copy, _reflected(Vector3.UP, combination))
		assert_eq(painted.paint_layers.size(), 1, "%d: the paint went with its face" % combination)
		assert_almost_eq(float(painted.paint_layers[0].opacity), 0.25, EPS)
		assert_not_null(_face_facing(b, Vector3.RIGHT).displacement, "the original keeps its own")


func test_point_entities_are_copied_with_mirrored_angles():
	var lamp := _entity("Lamp", Vector3(100, 0, 30), 30.0)
	lamp.set_meta("entity_name", "lamp")
	var path := root.get_path_to(lamp)

	var made := _mirror([], [path], X | Z)

	var paths: Array = made["entity_paths"]
	assert_eq(paths.size(), 3, "a copy across X, across Z and across both")
	var found := {}
	var names := {str(lamp.name): true}
	var authored := {"lamp": true}
	for copy_path in paths:
		var copy := root.get_node_or_null(NodePath(str(copy_path))) as DraftEntity
		assert_not_null(copy)
		found[_key(copy.global_position)] = float(copy.entity_data["angle"])
		assert_false(names.has(str(copy.name)), "a node name of its own: %s" % copy.name)
		names[str(copy.name)] = true
		var address := str(copy.get_meta("entity_name", ""))
		assert_false(authored.has(address), "an authored name of its own: %s" % address)
		authored[address] = true
	# Godot's forward is -Z: across X a yaw is -θ, across Z 180 - θ, and across
	# both a half turn.
	assert_eq(
		found,
		{
			_key(Vector3(-100, 0, 30)): 330.0,
			_key(Vector3(100, 0, -30)): 150.0,
			_key(Vector3(-100, 0, -30)): 210.0,
		}
	)
	assert_almost_eq(lamp.global_position, Vector3(100, 0, 30), V_EPS, "the original stays")
	assert_eq(float(lamp.entity_data["angle"]), 30.0)


func test_a_door_copy_is_a_door_of_its_own_with_its_angle_mirrored():
	var door := _box("d", Vector3(20, 1, 6), Vector3(0.2, 2, 1.6))
	root.tie_brushes_to_entity(["d"], "func_door", "gate")
	door.set_meta(HFBrushEntityScript.DATA_META, {"angle": 0.0})

	var made := _mirror(["d"], [], X | Z)

	var names := {"gate": true}
	var angles := {}
	for id in made["brush_ids"]:
		var copy := _copy(id)
		assert_eq(str(copy.get_meta(HFBrushEntityScript.CLASS_META, "")), "func_door", "a door")
		var address := str(copy.get_meta(HFBrushEntityScript.NAME_META, ""))
		assert_false(names.has(address), "answering to a name of its own: %s" % address)
		names[address] = true
		var data: Dictionary = copy.get_meta(HFBrushEntityScript.DATA_META, {})
		angles[_key(copy.global_position)] = float(data.get("angle", -1.0))
	# A bearing starts at +X: across X it is 180 - θ, across Z -θ.
	assert_eq(
		angles,
		{
			_key(Vector3(-20, 1, 6)): 180.0,
			_key(Vector3(20, 1, -6)): 0.0,
			_key(Vector3(-20, 1, -6)): 180.0,
		}
	)
	assert_eq(str(door.get_meta(HFBrushEntityScript.NAME_META, "")), "gate", "the original")


func test_a_copy_of_a_structure_is_plain_brushes_and_the_structure_is_left_alone():
	# A copy is what Duplicate makes, and a duplicate of a piece is no piece of the
	# structure: a rebuild must neither take the copies over nor read them as edits.
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("stairs")
	settings["steps"] = 4
	assert_true(root.create_generator("stairs", settings, Transform3D.IDENTITY).ok, "built")
	var record = root.generator_system.generators.values()[0]
	var pieces: Array = Array(record.brush_ids)

	var made := _mirror(pieces, [], X, Vector3(8, 0, 0))

	assert_eq((made["brush_ids"] as Array).size(), pieces.size(), "a copy of every piece")
	for id in made["brush_ids"]:
		assert_null(root.generator_system.generator_for_brush(str(id)), "%s is its own" % id)
	assert_eq(Array(record.brush_ids), pieces, "the structure keeps only its own pieces")
	assert_eq(Array(root.generator_system.edited_brush_ids(record.generator_id)), [], "unedited")


# ===========================================================================
# Texture Lock
# ===========================================================================


## On, every face of every copy shows the mirror image of the original: the point
## the mirror sends a corner to reads the UV that corner read.
func test_texture_lock_on_mirrors_the_texture_with_each_copy():
	root.texture_lock = true
	var pivot := Vector3(4, -2, 6)
	var b := _dressed_box("a", Vector3(48, 12, -20))
	var made := _mirror(["a"], [], X | Y | Z, pivot)
	for id in made["brush_ids"]:
		var copy := _copy(id)
		var combination := 0
		for candidate in _combinations(X | Y | Z):
			if copy.global_position.is_equal_approx(_mirrored(b.global_position, candidate, pivot)):
				combination = candidate
		assert_gt(combination, 0, "the copy stands at a mirrored place")
		for direction in DIRECTIONS:
			var where := "%d, %s face" % [combination, direction]
			var copied := _uvs_by_corner(
				copy, _face_facing(copy, _reflected(direction, combination))
			)
			for pair in _corner_uvs(b, _face_facing(b, direction)):
				var landed := _key(_mirrored(pair[0], combination, pivot))
				assert_true(copied.has(landed), where + ": the corner is there")
				if copied.has(landed):
					assert_almost_eq(
						copied[landed], pair[1], Vector2(EPS, EPS), where + ": the mirror image"
					)


## Off, the copy keeps the original's settings and reads the level's projection
## where it lands, as Flip leaves a brush: the top of a copy across X shows the
## patch of texture that is there, not the original's patch reversed.
func test_texture_lock_off_leaves_the_copy_reading_the_level():
	root.texture_lock = false
	var b := _dressed_box("a", Vector3(48, 12, -20))
	var made := _mirror(["a"], [], X)
	var copy := _copy(made["brush_ids"][0])
	var top = _face_facing(copy, Vector3.UP)
	var source = _face_facing(b, Vector3.UP)
	assert_almost_eq(top.uv_offset, source.uv_offset, Vector2(EPS, EPS), "settings kept")
	assert_almost_eq(top.uv_scale, source.uv_scale, Vector2(EPS, EPS))
	var copied := _uvs_by_corner(copy, top)
	var differs := false
	for pair in _corner_uvs(b, source):
		var landed := _key(_mirrored(pair[0], X, Vector3.ZERO))
		assert_true(copied.has(landed), "the corner is there")
		if copied.has(landed) and not (copied[landed] as Vector2).is_equal_approx(pair[1]):
			differs = true
	assert_true(differs, "the texture stayed in the level rather than going with the copy")


# ===========================================================================
# Refusals
# ===========================================================================


func test_no_axis_and_a_plane_that_is_not_a_number_make_nothing():
	_box("a", Vector3(10, 0, 0))
	var brushes: int = root.draft_brushes_node.get_child_count()
	for axes in [0, 8, -1]:
		assert_eq(_mirror(["a"], [], axes)["brush_ids"], [], "axes %d" % axes)
	assert_eq(_mirror(["a"], [], X, Vector3(NAN, 0, 0))["brush_ids"], [], "a NaN plane")
	assert_eq(root.draft_brushes_node.get_child_count(), brushes, "and the level has no copy")
