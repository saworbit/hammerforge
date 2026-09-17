extends GutTest

## What survives a `.map` in and back out again (#662, #663).
##
## `parse_map_text()` keeps every key it reads. The level only took some of them,
## so a map imported and exported came back with every texture called `__default`,
## no WAD list to compile against, no name, and a `func_door` with nothing saying
## how fast it moves. The geometry arrived perfectly the whole time, which is what
## made it look like the format was supported.

const MapIO = preload("res://addons/hammerforge/map_io.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFFileSystemType = preload("res://addons/hammerforge/systems/hf_file_system.gd")

const _PATH := "user://hf_roundtrip_fidelity.map"

## worldspawn with keys, a world brush, a named brush entity with behaviour, and
## a trigger that points at it. The shape another editor writes.
const _SOURCE := """{
"classname" "worldspawn"
"wad" "/textures/base.wad;/textures/liquids.wad"
"message" "The Slipgate"
"mapversion" "220"
{
( 0 0 0 ) ( 64 0 0 ) ( 64 64 0 ) floor1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 0 0 16 ) ( 64 64 16 ) ( 64 0 16 ) ceil1 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 0 0 0 ) ( 0 64 0 ) ( 0 64 16 ) wall_a [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 64 0 0 ) ( 64 0 16 ) ( 64 64 16 ) wall_b [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 0 0 0 ) ( 0 0 16 ) ( 64 0 16 ) sky1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 0 64 0 ) ( 64 64 0 ) ( 64 64 16 ) *water1 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
{
"classname" "func_door"
"targetname" "gate"
"speed" "100"
"wait" "3"
"angle" "90"
{
( 0 0 0 ) ( 8 0 0 ) ( 8 8 0 ) +0button [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 0 0 8 ) ( 8 8 8 ) ( 8 0 8 ) +0button [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 0 0 0 ) ( 0 8 0 ) ( 0 8 8 ) +0button [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 8 0 0 ) ( 8 0 8 ) ( 8 8 8 ) +0button [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 0 0 0 ) ( 0 0 8 ) ( 8 0 8 ) +0button [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 0 8 0 ) ( 8 8 0 ) ( 8 8 8 ) +0button [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
{
"classname" "trigger_once"
"target" "gate"
{
( 16 0 0 ) ( 24 0 0 ) ( 24 8 0 ) AAATRIGGER [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 16 0 8 ) ( 24 8 8 ) ( 24 0 8 ) AAATRIGGER [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 16 0 0 ) ( 16 8 0 ) ( 16 8 8 ) AAATRIGGER [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 24 0 0 ) ( 24 0 8 ) ( 24 8 8 ) AAATRIGGER [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 16 0 0 ) ( 16 0 8 ) ( 24 0 8 ) AAATRIGGER [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 16 8 0 ) ( 24 8 0 ) ( 24 8 8 ) AAATRIGGER [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
"""


func before_each():
	var f := FileAccess.open(_PATH, FileAccess.WRITE)
	f.store_string(_SOURCE)
	f.close()


func after_each():
	if FileAccess.file_exists(_PATH):
		DirAccess.remove_absolute(_PATH)


func _imported_level() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	assert_eq(root.file_system.import_map(_PATH), OK, "the map imports")
	return root


func _exported_text(root: LevelRoot) -> String:
	var out := "user://hf_roundtrip_fidelity_out.map"
	assert_eq(root.file_system.export_map(out, "valve220"), OK, "the level exports")
	var text := FileAccess.get_file_as_string(out)
	DirAccess.remove_absolute(out)
	return text


# ===========================================================================
# Texture names (#662)
# ===========================================================================


func test_an_import_into_an_empty_palette_keeps_every_texture_name():
	var root := _imported_level()
	var names: Array = root.get_material_names()
	for expected in ["floor1", "ceil1", "wall_a", "wall_b", "sky1", "*water1"]:
		assert_has(names, expected, "the palette mirrors the file")
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			assert_ne(str(face.map_texture), "", "and every face knows what it was called")


func test_the_export_writes_the_names_back_rather_than_the_default():
	var text := _exported_text(_imported_level())
	for expected in ["floor1", "*water1", "AAATRIGGER", "sky1", "+0button"]:
		assert_string_contains(text, expected, "a name the source had")
	assert_false(
		text.contains(MapIO.DEFAULT_TEXTURE), "and no face fell back to the default texture"
	)


func test_a_name_survives_even_with_no_palette_at_all():
	# The face carries the name itself, so a round trip is lossless in a project
	# that has loaded no materials. Without it the palette was the only record.
	var root := _imported_level()
	root.material_manager.clear()
	var text := _exported_text(root)
	assert_string_contains(text, "*water1", "the face still knows the texture it came in as")
	assert_false(text.contains(MapIO.DEFAULT_TEXTURE), "nothing fell back to the default")


# ===========================================================================
# worldspawn and brush entity keys (#663)
# ===========================================================================


func test_worldspawn_keys_come_back_out():
	var root := _imported_level()
	assert_eq(
		str(root.map_worldspawn_properties.get("message", "")),
		"The Slipgate",
		"the level has a name for the first time"
	)
	var text := _exported_text(root)
	assert_string_contains(text, "base.wad", "the WAD list the textures compile against")
	assert_string_contains(text, "The Slipgate", "the level's name")
	assert_string_contains(text, "mapversion", "the format marker")


func test_worldspawn_is_written_once():
	var text := _exported_text(_imported_level())
	assert_eq(
		text.count('"classname" "worldspawn"'),
		1,
		"a block with two classnames is a block whose class depends on which one wins"
	)


func test_a_brush_entity_keeps_the_keys_that_make_it_one():
	var text := _exported_text(_imported_level())
	assert_string_contains(text, '"speed" "100"', "a door that does not move is not a door")
	assert_string_contains(text, '"wait" "3"')
	assert_string_contains(text, '"angle" "90"')


func test_the_trigger_still_points_at_the_door():
	# In this lineage a trigger addresses a door with "target" against the door's
	# "targetname". Losing the pair loses the only logic a three entity map has.
	var text := _exported_text(_imported_level())
	assert_string_contains(text, '"target" "gate"', "the trigger's end of the wire")
	assert_string_contains(text, '"targetname" "gate"', "and the door's end")


func test_the_name_is_not_written_twice():
	var text := _exported_text(_imported_level())
	assert_eq(text.count('"targetname" "gate"'), 1, "a round trip must not grow a second copy")


func test_worldspawn_properties_travel_in_a_level_snapshot():
	# They describe the level and are not a node, so the `.hflevel` carries them.
	var root := _imported_level()
	var state: Dictionary = root.state_system.capture_state()
	root.map_worldspawn_properties = {}
	root.state_system.restore_state(state)
	assert_eq(
		str(root.map_worldspawn_properties.get("message", "")),
		"The Slipgate",
		"a saved and reloaded level still knows its own name"
	)
