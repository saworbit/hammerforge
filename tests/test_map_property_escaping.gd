extends GutTest

## Entity property values that contain the characters the .map syntax is made of.
##
## The format has no escaping rule of its own, so the contract here is
## HammerForge's: what it writes, it reads back unchanged. Values written by a
## tool that does not escape still have to survive being read, which is why
## unescaping only recognises `\"` and `\\` and leaves every other backslash
## exactly where it is.

const HFMapQuake = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")

const BRUSH_FACES := """( -64 -64 -16 ) ( -64 -63 -16 ) ( -64 -64 -15 ) FLOOR 0 0 0 1 1
( -64 -64 -16 ) ( -64 -64 -15 ) ( -63 -64 -16 ) FLOOR 0 0 0 1 1
( -64 -64 -16 ) ( -63 -64 -16 ) ( -64 -63 -16 ) FLOOR 0 0 0 1 1
( 64 64 16 ) ( 64 65 16 ) ( 65 64 16 ) FLOOR 0 0 0 1 1
( 64 64 16 ) ( 65 64 16 ) ( 64 64 17 ) FLOOR 0 0 0 1 1
( 64 64 16 ) ( 64 64 17 ) ( 64 65 16 ) FLOOR 0 0 0 1 1"""


## One point entity carrying `value` on its `msg` property, written the way the
## exporter writes it and read back the way the importer reads it.
func _round_trip(value: String) -> Dictionary:
	var adapter := HFMapQuake.new()
	var lines: Array[String] = adapter.format_entity_properties(
		{"classname": "info_probe", "origin": "0 0 0", "msg": value}
	)
	var text := "{\n" + "\n".join(lines) + "\n}\n"
	var parsed: Dictionary = MapIO.parse_map_text(text)
	var entities: Array = parsed.get("entities", [])
	return {
		"errors": parsed.get("errors", []),
		"properties": entities[0].get("properties", {}) if not entities.is_empty() else {},
	}


func _assert_survives(value: String, why: String = "") -> void:
	var result := _round_trip(value)
	assert_eq(result["errors"], [], "%s parsed with errors" % value)
	assert_eq(
		str(result["properties"].get("msg", "<missing>")),
		value,
		why if why != "" else "%s did not survive the round trip" % value
	)


# ===========================================================================
# What HammerForge writes, it reads back
# ===========================================================================


func test_a_plain_value_still_survives():
	_assert_survives("a plain message")


func test_a_value_containing_a_quote_survives():
	# This used to come back as "he said " with no error at all, because four
	# quotes is exactly what a valid line has.
	_assert_survives('he said "hi"', "a quote used to truncate the value silently")


func test_a_value_that_is_only_quotes_survives():
	_assert_survives('""')


func test_a_value_containing_a_backslash_survives():
	_assert_survives("C:\\maps\\test")


func test_a_value_ending_in_a_backslash_survives():
	# Unescaped, the trailing backslash would escape the closing delimiter.
	_assert_survives("trailing\\")


func test_a_value_containing_both_survives():
	_assert_survives('path\\to\\"thing"')


func test_a_value_containing_a_comment_marker_survives():
	# A URL is the obvious case. Cutting the line at // left it with an odd
	# number of quotes and no way to parse.
	_assert_survives("http://example.com/x")


func test_a_key_containing_a_quote_survives():
	var adapter := HFMapQuake.new()
	var lines: Array[String] = adapter.format_entity_properties(
		{"classname": "info_probe", 'od"d': "value"}
	)
	var parsed: Dictionary = MapIO.parse_map_text("{\n" + "\n".join(lines) + "\n}\n")
	assert_eq(parsed.get("errors", []), [])
	assert_eq(str(parsed["entities"][0]["properties"].get('od"d', "<missing>")), "value")


# ===========================================================================
# Files written by tools that do not escape
# ===========================================================================


func test_an_unescaped_windows_path_is_read_as_written():
	# `\m` and `\t` are not escape sequences, so they stay exactly as they are.
	var parsed: Dictionary = MapIO.parse_map_text(
		"{\n" + '"classname" "info_probe"' + "\n" + '"model" "textures\\maps\\wall"' + "\n}\n"
	)
	assert_eq(parsed.get("errors", []), [])
	assert_eq(str(parsed["entities"][0]["properties"]["model"]), "textures\\maps\\wall")


func test_a_real_comment_is_still_stripped():
	var parsed: Dictionary = MapIO.parse_map_text(
		(
			"{\n"
			+ '"classname" "info_probe"  // a note'
			+ "\n"
			+ "// a whole line of note\n"
			+ '"msg" "kept"'
			+ "\n}\n"
		)
	)
	assert_eq(parsed.get("errors", []), [])
	var props: Dictionary = parsed["entities"][0]["properties"]
	assert_eq(str(props["classname"]), "info_probe", "the trailing comment came along")
	assert_eq(str(props["msg"]), "kept")


func test_a_line_that_is_not_a_pair_is_still_an_error():
	var parsed: Dictionary = MapIO.parse_map_text(
		"{\n" + '"classname" "info_probe"' + "\n" + '"dangling' + "\n}\n"
	)
	assert_gt((parsed.get("errors", []) as Array).size(), 0, "an unterminated key is still wrong")


# ===========================================================================
# Through a whole level, not just one line
# ===========================================================================


func test_a_brush_entity_class_with_a_quote_survives():
	var text := (
		"{\n"
		+ '"classname" "worldspawn"'
		+ "\n}\n{\n"
		+ '"classname" "func_od\\"d"'
		+ "\n{\n"
		+ BRUSH_FACES
		+ "\n}\n}\n"
	)
	var parsed: Dictionary = MapIO.parse_map_text(text)
	assert_eq(parsed.get("errors", []), [])
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1)
	assert_eq(str(brushes[0].get("brush_entity_class", "")), 'func_od"d')


func test_escape_property_is_the_inverse_of_reading_one():
	for value in ['a "quoted" word', "back\\slash", "trailing\\", '\\"', "plain"]:
		var line := '"k" "%s"' % MapIO.escape_property(value)
		assert_eq(MapIO._parse_key_value(line), ["k", value], "round trip failed for %s" % value)
