extends GutTest

## Which way up a `.map` coordinate is (#733).
##
## `.map` is a Z-up format across the whole Quake family. Godot is Y-up. Nothing
## converted, in either direction, so a corridor drawn 112 units high arrived
## 3.5 metres deep and one metre high, and an exported floor opened in
## TrenchBroom as a wall. It went unnoticed because it is symmetric: out of here
## and back came home, and only the crossing was wrong.
##
## The companion to [test_map_unit_scale.gd], which is the other half of the same
## question.

const MapIO = preload("res://addons/hammerforge/map_io.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFMapValve220Type = preload("res://addons/hammerforge/map_adapters/hf_map_valve220.gd")

const _PATH := "user://hf_map_axes.map"
const _OUT := "user://hf_map_axes_out.map"

## A floor slab, as an editor in that family writes one: wide in x and y, thin in
## z, which is their up.
const _QUAKE_FLOOR := """{
"classname" "worldspawn"
{
( -64 -64 -8 ) ( -64 -63 -8 ) ( -63 -64 -8 ) floor1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -64 -64 0 ) ( -63 -64 0 ) ( -64 -63 0 ) floor1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -64 -64 -8 ) ( -64 -64 -7 ) ( -64 -63 -8 ) floor1 [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 64 -64 -8 ) ( 64 -63 -8 ) ( 64 -64 -7 ) floor1 [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -64 -64 -8 ) ( -63 -64 -8 ) ( -64 -64 -7 ) floor1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -64 64 -8 ) ( -64 64 -7 ) ( -63 64 -8 ) floor1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
"""


func after_each():
	for path in [_PATH, _OUT]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	var f := FileAccess.open(_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _level() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _first_brush_size(root: LevelRoot) -> Vector3:
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			return child.size
	return Vector3.ZERO


func _written_extent(text: String) -> Vector3:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var re := RegEx.new()
	re.compile("\\(([^\\)]+)\\)")
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("("):
			continue
		for m in re.search_all(stripped):
			var parts := m.get_string(1).strip_edges().split(" ", false)
			if parts.size() < 3:
				continue
			var p := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	if lo == Vector3.INF:
		return Vector3.ZERO
	return hi - lo


# ===========================================================================
# The turn itself
# ===========================================================================


func test_the_turn_puts_their_up_on_ours():
	assert_eq(MapIO.from_map_axes(Vector3(0, 0, 1)), Vector3.UP, "their z is our y")
	assert_eq(MapIO.to_map_axes(Vector3.UP), Vector3(0, 0, 1), "and back again")


func test_the_turn_is_its_own_inverse_both_ways_round():
	for v in [Vector3(1, 2, 3), Vector3(-7, 0.5, 11), Vector3.ZERO, Vector3(0, -3, 0)]:
		assert_eq(MapIO.to_map_axes(MapIO.from_map_axes(v)), v, "out and back is where it started")
		assert_eq(MapIO.from_map_axes(MapIO.to_map_axes(v)), v)


func test_the_turn_is_a_rotation_rather_than_a_mirror():
	# A mirror would invert every face's winding, and the winding reversal on the
	# way out is a separate conversion that assumes it does not have to.
	var x := MapIO.from_map_axes(Vector3.RIGHT)
	var y := MapIO.from_map_axes(Vector3.UP)
	var z := MapIO.from_map_axes(Vector3.BACK)
	assert_almost_eq(x.cross(y).dot(z), 1.0, 0.0001, "right-handed in, right-handed out")
	for axis in [x, y, z]:
		assert_almost_eq(axis.length(), 1.0, 0.0001, "and nothing was stretched")


func test_the_turn_keeps_the_level_the_same_way_round_seen_from_above():
	# The reason for this turn rather than Func_Godot's cyclic one. Looking down,
	# their x is still our x and their y is still our forward, so a piece imported
	# next to existing geometry lines up instead of arriving at ninety degrees.
	assert_eq(MapIO.from_map_axes(Vector3(1, 0, 0)), Vector3.RIGHT, "their x is our x")
	assert_eq(MapIO.from_map_axes(Vector3(0, 1, 0)), Vector3.FORWARD, "their y is our forward")


# ===========================================================================
# Import
# ===========================================================================


func test_a_floor_imports_as_a_floor():
	_write(_QUAKE_FLOOR)
	var root := _level()
	assert_eq(root.file_system.import_map(_PATH), OK)
	var size := _first_brush_size(root)
	# 128 x 128 x 8 in the file, thin on their z. Thin on our y is a floor; thin
	# on our z was a wall, which is what this used to import as.
	assert_almost_eq(size.x, 4.0, 0.01)
	assert_almost_eq(size.y, 0.25, 0.01, "8 units thick on their up axis is 0.25 on ours")
	assert_almost_eq(size.z, 4.0, 0.01)


func test_the_codec_on_its_own_turns_nothing():
	var parsed := MapIO.parse_map_text(_QUAKE_FLOOR)
	assert_false(bool(parsed.get("axes_converted")), "no turn was asked for")
	var size: Vector3 = parsed["brushes"][0]["size"]
	assert_almost_eq(size.z, 8.0, 0.01, "thin on z, as the file has it")


func test_the_turn_is_reported_back():
	var parsed := MapIO.parse_map_text(_QUAKE_FLOOR, 1.0, true)
	assert_true(bool(parsed.get("axes_converted")), "so a caller can say what it did")


func test_an_origin_on_the_turned_axis_is_not_written_as_a_negative_zero():
	# The turn negates one component, and `String.num(-0.0, 3)` is "-0.0". An
	# entity anywhere on that axis, which is most of them, wrote `0.0 -0.0 24.0`.
	var root := _level()
	var entity: Node3D = root._create_entity_from_map(
		{"classname": "info_player_start", "origin": Vector3(0, 0.75, 0)}
	)
	assert_not_null(entity)
	var text := _exported(root)
	assert_false(text.contains("-0.0"), "nothing in the file is a negative zero")
	assert_string_contains(text, '"origin" "0.0 0.0 24.0"')


# ===========================================================================
# Export
# ===========================================================================


func _exported(root: LevelRoot, convert_axes: bool = true) -> String:
	assert_eq(
		root.file_system.export_map(_OUT, "valve220", MapIO.QUAKE_UNITS_PER_METRE, convert_axes),
		OK,
		"the level exports"
	)
	return FileAccess.get_file_as_string(_OUT)


func _slab(root: LevelRoot) -> void:
	# Thin on y: a floor, here.
	root.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 0.25, 4), "center": Vector3.ZERO, "brush_id": "f1"}
	)


func test_a_floor_exports_as_a_floor():
	var root := _level()
	_slab(root)
	var extent := _written_extent(_exported(root))
	assert_almost_eq(extent.x, 128.0, 0.1)
	assert_almost_eq(extent.y, 128.0, 0.1)
	assert_almost_eq(
		extent.z, 8.0, 0.1, "thin on their up axis, so it opens flat rather than upright"
	)


func test_an_export_asked_for_no_turn_writes_this_projects_axes():
	var root := _level()
	_slab(root)
	var extent := _written_extent(_exported(root, false))
	assert_almost_eq(extent.y, 8.0, 0.1, "thin on our y, untouched")


# ===========================================================================
# What the texture does across the turn
# ===========================================================================


## The two bracketed axis vectors on the first Valve 220 face line.
func _first_face_axes(text: String) -> Array:
	var re := RegEx.new()
	re.compile("\\[([^\\]]+)\\]")
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("("):
			continue
		var found := re.search_all(stripped)
		if found.size() < 2:
			continue
		var out: Array = []
		for m in found:
			var parts := m.get_string(1).strip_edges().split(" ", false)
			if parts.size() < 3:
				return []
			out.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
		return out
	return []


func test_the_texture_axes_turn_with_the_points():
	# Valve 220 computes the texture coordinate as the point projected onto these
	# axes. Turning the points and leaving the axes alone slides every texture
	# onto a different part of the face.
	var root := _level()
	_slab(root)
	var turned := _first_face_axes(_exported(root))
	var untouched := _first_face_axes(_exported(root, false))
	assert_eq(turned.size(), 2, "the face line carries a u and a v axis")
	assert_eq(untouched.size(), 2)
	assert_ne(turned[0], untouched[0], "the axis moved with the geometry")
	assert_eq(turned[0], MapIO.to_map_axes(untouched[0]), "by exactly the same turn")
	assert_eq(turned[1], MapIO.to_map_axes(untouched[1]))


func test_a_face_keeps_its_texture_coordinate_across_the_turn():
	# The property that matters, stated directly: a rotation applied to both the
	# point and the axis leaves the dot product between them alone, so the
	# coordinate the reader computes is the one it would have computed before.
	var point := Vector3(3.0, -1.5, 7.25)
	var axis := Vector3.RIGHT
	assert_almost_eq(
		MapIO.to_map_axes(point).dot(MapIO.to_map_axes(axis)),
		point.dot(axis),
		0.0001,
		"the projection survives the turn"
	)
	var v_axis := Vector3.UP
	assert_almost_eq(
		MapIO.to_map_axes(point).dot(MapIO.to_map_axes(v_axis)), point.dot(v_axis), 0.0001
	)


# ===========================================================================
# What the file records
# ===========================================================================


func test_an_export_says_which_way_up_it_is():
	var root := _level()
	_slab(root)
	assert_string_contains(
		_exported(root), '"%s" "%s"' % [MapIO.AXIS_PROPERTY, MapIO.AXES_QUAKE], "turned"
	)
	assert_string_contains(
		_exported(root, false), '"%s" "%s"' % [MapIO.AXIS_PROPERTY, MapIO.AXES_GODOT], "not turned"
	)


func test_a_file_that_says_it_is_already_the_right_way_up_is_left_alone():
	# What an export asked for no turn produces, and what every HammerForge
	# export before this change was. Turning it again would stand the level up.
	var root := _level()
	_slab(root)
	_write(_exported(root, false))
	var back := _level()
	assert_eq(back.file_system.import_map(_PATH), OK)
	assert_almost_eq(
		_first_brush_size(back).y, 0.25, 0.01, "it said godot, so it came back as it went"
	)


func test_a_file_from_another_editor_says_nothing_and_is_turned():
	_write(_QUAKE_FLOOR)
	var root := _level()
	assert_eq(root.file_system.import_map(_PATH), OK)
	assert_almost_eq(
		_first_brush_size(root).y, 0.25, 0.01, "absent means the format's own axes, which it is"
	)


func test_a_convention_this_build_does_not_know_falls_back_rather_than_guessing():
	var text := _QUAKE_FLOOR.replace(
		'"classname" "worldspawn"',
		'"classname" "worldspawn"\n"%s" "sideways"' % MapIO.AXIS_PROPERTY
	)
	var parsed := MapIO.parse_map_text(text, 1.0, true)
	assert_true(bool(parsed.get("axes_converted")), "the caller's answer stands")


func test_the_convention_is_written_once_however_many_times_it_goes_round():
	var root := _level()
	_slab(root)
	_write(_exported(root))
	var back := _level()
	assert_eq(back.file_system.import_map(_PATH), OK)
	var text := _exported(back)
	assert_eq(text.count(MapIO.AXIS_PROPERTY), 1, "one statement of it, not two")


# ===========================================================================
# The round trip
# ===========================================================================


func test_a_level_out_to_map_and_back_is_the_same_way_up():
	var root := _level()
	_slab(root)
	_write(_exported(root))
	var back := _level()
	assert_eq(back.file_system.import_map(_PATH), OK)
	var size := _first_brush_size(back)
	assert_almost_eq(size.x, 4.0, 0.01)
	assert_almost_eq(size.y, 0.25, 0.01, "still a floor")
	assert_almost_eq(size.z, 4.0, 0.01)
