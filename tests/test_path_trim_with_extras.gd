extends GutTest

## Trim with Stairs or Railings on one path (#1629): Auto-Generate picked one of
## the three, so a corridor with a skirting and a stair took two paths drawn over
## the same points.

const HFPathTool = preload("res://addons/hammerforge/hf_path_tool.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const CUSTOM: int = LevelRootType.BrushShape.CUSTOM


## A tool on a path that climbs 2 m over 10 and turns, with `settings`.
func _tool(settings: Dictionary) -> Object:
	var tool = HFPathTool.new()
	for key in settings:
		tool.set_setting(key, settings[key])
	tool._waypoints = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 2, 0), Vector3(10, 2, 8)])
	return tool


## The box round an info's corners in the level.
static func _bounds(info: Dictionary) -> AABB:
	var centre: Vector3 = info.get("center", Vector3.ZERO)
	var bounds := AABB()
	var first := true
	for face_dict in info.get("faces", []):
		for corner in FaceData.from_dict(face_dict).local_verts:
			if first:
				bounds = AABB(corner + centre, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(corner + centre)
	return bounds


## Whether any of `a` takes up space any of `b` does.
static func _overlap(a: Array, b: Array) -> bool:
	for one in a:
		var box_a := _bounds(one).grow(-0.001)
		for other in b:
			if box_a.intersects(_bounds(other).grow(-0.001)):
				return true
	return false


func test_stairs_and_trim_on_one_path_neither_overlapping():
	var settings := {"path_extra": HFPathTool.PathExtra.STAIRS, "path_add_trim": true}
	var tool = _tool(settings)
	var stairs: Array = tool._build_stairs(4.0, 4.0, "grp", CUSTOM)
	var trim: Array = tool._build_trim(4.0, "grp", CUSTOM)
	assert_gt(stairs.size(), 0, "fixture: the climb makes steps")
	assert_gt(trim.size(), 0, "fixture: the trim makes strips")
	var built: Array = tool._extras(4.0, 4.0, "grp", CUSTOM)
	assert_eq(built.size(), stairs.size() + trim.size(), "both are built")
	assert_false(_overlap(stairs, trim), "and neither stands in the other")
	assert_string_contains("\n".join(tool.get_shortcut_hud_lines()), "Auto: Stairs and Trim")


func test_railings_and_trim_on_one_path_neither_overlapping():
	var settings := {"path_extra": HFPathTool.PathExtra.RAILING, "path_add_trim": true}
	var tool = _tool(settings)
	var rails: Array = tool._build_railings(4.0, "grp", CUSTOM)
	var trim: Array = tool._build_trim(4.0, "grp", CUSTOM)
	var built: Array = tool._extras(4.0, 4.0, "grp", CUSTOM)
	assert_eq(built.size(), rails.size() + trim.size())
	assert_false(_overlap(rails, trim))


func test_each_keeps_its_own_settings_and_off_builds_as_before():
	var tool = _tool({"path_extra": HFPathTool.PathExtra.STAIRS})
	var alone: Array = tool._extras(4.0, 4.0, "grp", CUSTOM)
	assert_eq(alone.size(), tool._build_stairs(4.0, 4.0, "grp", CUSTOM).size(), "off: stairs only")
	tool.set_setting("path_add_trim", true)
	tool.set_setting("trim_width", 0.5)
	tool.set_setting("stair_step_height", 0.5)
	var trim: Array = tool._build_trim(4.0, "grp", CUSTOM)
	var stairs: Array = tool._build_stairs(4.0, 4.0, "grp", CUSTOM)
	assert_eq(tool._extras(4.0, 4.0, "grp", CUSTOM).size(), trim.size() + stairs.size())
	assert_almost_eq(_bounds(trim[0]).size.z, 0.5, 0.001, "the trim at its own width")
	tool.set_setting("path_extra", HFPathTool.PathExtra.TRIM)
	assert_eq(
		tool._extras(4.0, 4.0, "grp", CUSTOM).size(), trim.size(), "Trim picked builds it once"
	)
