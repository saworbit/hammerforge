extends GutTest

## What a `.map` coordinate is worth (#713).
##
## The format carries bare numbers and never says what a unit is. Every editor
## that writes one is on Quake units, where a player is 56 to 72 tall and the
## grid steps in 16s. This project has been on Godot's metric scale since #625,
## where the playtest player is 1.6. `MapIO` copied the numbers through, so a
## corridor drawn two players high arrived seventy players high and a room
## exported from here was smaller than the other editor's smallest grid step.

const MapIO = preload("res://addons/hammerforge/map_io.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDockFileHandlerType = preload("res://addons/hammerforge/dock_file_handler.gd")

const _PATH := "user://hf_map_unit_scale.map"
const _OUT := "user://hf_map_unit_scale_out.map"

## A doorway as a Quake-family editor writes one: 128 wide, 32 deep, 112 high,
## with the spawn 24 off the floor.
const _QUAKE_DOOR := """{
"classname" "worldspawn"
{
( -64 -16 0 ) ( -64 -15 0 ) ( -64 -16 1 ) wall_a [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 64 -16 0 ) ( 64 -16 1 ) ( 64 -15 0 ) wall_a [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -64 -16 0 ) ( -64 -16 1 ) ( -63 -16 0 ) wall_a [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -64 16 0 ) ( -63 16 0 ) ( -64 16 1 ) wall_a [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -64 -16 0 ) ( -63 -16 0 ) ( -64 -15 0 ) floor1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -64 -16 112 ) ( -64 -15 112 ) ( -63 -16 112 ) ceil1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
}
}
{
"classname" "info_player_start"
"origin" "0 0 24"
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


func _imported(text: String, units_per_metre: float = MapIO.QUAKE_UNITS_PER_METRE) -> LevelRoot:
	_write(text)
	var root := _level()
	assert_eq(root.file_system.import_map(_PATH, units_per_metre), OK, "the map imports")
	return root


## The size of the first imported brush, in this project's units.
func _first_brush_size(root: LevelRoot) -> Vector3:
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			return child.size
	return Vector3.ZERO


## The plane coordinates an export wrote, as one box.
##
## Reads the numbers back out of the file rather than trusting a substring: a
## test that looks for "128" in the text passes on a coordinate of 1280.
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


## The two scale numbers on the first Valve 220 face line, which are its last two
## tokens in that format.
func _first_face_scales(text: String) -> Vector2:
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("("):
			continue
		var tokens := stripped.split(" ", false)
		if tokens.size() < 2:
			continue
		return Vector2(float(tokens[tokens.size() - 2]), float(tokens[tokens.size() - 1]))
	return Vector2.ZERO


# ===========================================================================
# Import
# ===========================================================================


func test_a_quake_corridor_arrives_at_a_size_a_person_fits_in():
	# The axes turn as well as the numbers (#733), so the source's 112, which is
	# its height, is the height here. This asserted 1 tall and 3.5 deep while the
	# import was still copying the axes across.
	var root := _imported(_QUAKE_DOOR)
	var size := _first_brush_size(root)
	assert_almost_eq(size.x, 4.0, 0.01, "128 map units is 4 metres at 32 per metre")
	assert_almost_eq(size.y, 3.5, 0.01, "and its 112 high is 3.5 high, which a 1.6 walks under")
	assert_almost_eq(size.z, 1.0, 0.01, "and its 32 deep is 1 deep")


func test_a_spawn_lands_where_the_file_put_it_rather_than_where_the_numbers_did():
	var root := _imported(_QUAKE_DOOR)
	var found: Node3D = null
	for child in root.entities_node.get_children():
		found = child
		break
	assert_not_null(found, "the point entity imported")
	assert_almost_eq(found.global_position.y, 0.75, 0.01, "24 map units up is 0.75 metres up")


func test_the_codec_on_its_own_converts_nothing():
	# `MapIO` reads and writes the format. What a unit means is the level's
	# business, so a caller that asks for the file's numbers gets the file's
	# numbers.
	var parsed := MapIO.parse_map_text(_QUAKE_DOOR)
	assert_eq(parsed.get("units_per_metre"), 1.0, "no conversion was asked for")
	var size: Vector3 = parsed["brushes"][0]["size"]
	assert_almost_eq(size.x, 128.0, 0.01, "the plane coordinates as written")


func test_the_figure_used_is_reported_back():
	var parsed := MapIO.parse_map_text(_QUAKE_DOOR, 32.0)
	assert_eq(parsed.get("units_per_metre"), 32.0, "so a caller can say what it did")


# ===========================================================================
# Export
# ===========================================================================


func _exported(root: LevelRoot, units_per_metre: float = MapIO.QUAKE_UNITS_PER_METRE) -> String:
	assert_eq(
		root.file_system.export_map(_OUT, "valve220", units_per_metre), OK, "the level exports"
	)
	return FileAccess.get_file_as_string(_OUT)


func _room(root: LevelRoot) -> void:
	root.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 1, 3.5), "center": Vector3.ZERO, "brush_id": "r1"}
	)


func test_an_export_writes_the_numbers_the_other_editor_expects():
	var root := _level()
	_room(root)
	var extent := _written_extent(_exported(root))
	# Turned on the way out too, so the room's 3.5 of height is written on the
	# file's own up axis, which is its z.
	assert_almost_eq(extent.x, 128.0, 0.1, "4 metres is 128 map units")
	assert_almost_eq(extent.y, 112.0, 0.1, "3.5 of depth here is 112 on their y")
	assert_almost_eq(extent.z, 32.0, 0.1, "and 1 of height here is 32 on their z")


func test_an_export_at_one_writes_the_level_as_it_stands():
	var root := _level()
	_room(root)
	var extent := _written_extent(_exported(root, 1.0))
	assert_almost_eq(extent.x, 4.0, 0.01, "asked for no conversion, given none")


func test_the_texture_keeps_its_size_across_the_conversion():
	# A `.map` reader computes `axis . point / scale`. Multiplying the point by 32
	# and leaving the scale at 1 tiles the texture thirty-two times more often,
	# which is a room that arrives the right size covered in dust.
	var root := _level()
	_room(root)
	var scales := _first_face_scales(_exported(root))
	assert_almost_eq(scales.x, 32.0, 0.01, "the scale takes the same factor as the points")
	assert_almost_eq(scales.y, 32.0, 0.01)


func test_a_spawn_is_written_at_the_same_scale_as_the_geometry():
	var root := _level()
	_room(root)
	var entity: Node3D = root._create_entity_from_map(
		{"classname": "info_player_start", "origin": Vector3(0, 0.75, 0)}
	)
	assert_not_null(entity, "the entity was made")
	var text := _exported(root)
	# An origin is written to three decimals where a plane point is written as a
	# whole number when it is one. Both parse; only the geometry is asserted on
	# here, because the spacing of that line is not what this fix is about.
	# 0.75 up here is 24 up there, which is their z (#733).
	assert_string_contains(text, '"origin" "0.0 0.0 24.0"', "0.75 metres up is 24 map units up")


# ===========================================================================
# The round trip
# ===========================================================================


func test_a_level_exported_and_imported_again_is_the_same_size():
	var source := _level()
	_room(source)
	var text := _exported(source)
	_write(text)
	var back := _level()
	assert_eq(back.file_system.import_map(_PATH), OK)
	var size := _first_brush_size(back)
	assert_almost_eq(size.x, 4.0, 0.01, "out and back at the same scale is the same room")
	assert_almost_eq(size.z, 3.5, 0.01)


func test_a_file_that_states_its_own_scale_is_read_at_that_scale():
	# Reopening your own export gives back the level you exported, however the
	# setting has moved since.
	var source := _level()
	_room(source)
	_write(_exported(source, 16.0))
	var back := _level()
	assert_eq(back.file_system.import_map(_PATH, 32.0), OK)
	assert_almost_eq(
		_first_brush_size(back).x, 4.0, 0.01, "the file said 16, so 16 is what was used"
	)


func test_the_scale_is_written_once_however_many_times_it_goes_round():
	# An import stores every worldspawn key it read, and the export writes the
	# key itself. Written from both places, the block would carry two of them and
	# the size would depend on which one the reader kept.
	var source := _level()
	_room(source)
	_write(_exported(source))
	var back := _level()
	assert_eq(back.file_system.import_map(_PATH), OK)
	var text := _exported(back)
	assert_eq(text.count(MapIO.SCALE_PROPERTY), 1, "one statement of the scale, not two")


# ===========================================================================
# Figures that would ruin a level
# ===========================================================================


func test_a_scale_that_would_collapse_the_level_is_refused():
	for bad in ["0", "-4", "banana", "nan"]:
		var text := _QUAKE_DOOR.replace(
			'"classname" "worldspawn"',
			'"classname" "worldspawn"\n"%s" "%s"' % [MapIO.SCALE_PROPERTY, bad]
		)
		var parsed := MapIO.parse_map_text(text, 32.0)
		assert_eq(
			parsed.get("units_per_metre"), 32.0, "'%s' is not a scale, so the caller's stands" % bad
		)


func test_an_argument_that_is_not_a_scale_falls_back_to_no_conversion():
	var parsed := MapIO.parse_map_text(_QUAKE_DOOR, 0.0)
	assert_eq(parsed.get("units_per_metre"), 1.0, "rather than dividing by zero")
	var size: Vector3 = parsed["brushes"][0]["size"]
	assert_almost_eq(size.x, 128.0, 0.01, "and the geometry is still there")


func test_an_export_refuses_the_same_figures():
	var root := _level()
	_room(root)
	var extent := _written_extent(_exported(root, -8.0))
	assert_almost_eq(extent.x, 4.0, 0.01, "a negative scale would turn the level inside out")


# ===========================================================================
# What the dock hands in
# ===========================================================================


func test_the_dock_falls_back_to_the_quake_figure_when_there_is_no_row():
	# A headless dock and a test shim have no controls. Reading that as "no
	# conversion" would be this defect back again, silently.
	assert_eq(HFDockFileHandlerType.map_units_per_metre(null), MapIO.QUAKE_UNITS_PER_METRE)


func test_the_dock_hands_over_what_the_row_says():
	var spin := SpinBox.new()
	spin.max_value = 4096.0
	spin.value = 16.0
	add_child_autoqfree(spin)
	var shim := _DockShim.new()
	shim.map_scale_spin = spin
	assert_eq(HFDockFileHandlerType.map_units_per_metre(shim), 16.0)


func test_a_row_set_to_nothing_falls_back_rather_than_flattening_the_level():
	var shim := _DockShim.new()
	shim.map_scale_spin = SpinBox.new()
	shim.map_scale_spin.min_value = 0.0
	shim.map_scale_spin.value = 0.0
	add_child_autoqfree(shim.map_scale_spin)
	assert_eq(HFDockFileHandlerType.map_units_per_metre(shim), MapIO.QUAKE_UNITS_PER_METRE)


class _DockShim:
	extends RefCounted

	var map_scale_spin: SpinBox = null
