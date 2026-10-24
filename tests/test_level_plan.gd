extends "res://tests/mcp/mcp_dispatcher_case.gd"

## A top down plan of the level drawn from its brushes, as SVG and PNG, from a
## headless editor (#1705).

const HFLevelPlan = preload("res://addons/hammerforge/hf_level_plan.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

const DIR := "user://test_level_plan"
const REFERENCE := "res://addons/hammerforge/data/reference_map.hflevel"
## The reference map's plan as this build draws it. `.txt`, so Godot does not
## import it as a texture. `HF_WRITE_PLAN=1` writes it again after a change to
## the drawing that is meant.
const REFERENCE_PLAN := "res://tests/support/reference_plan.svg.txt"


func _box(level: LevelRoot, id: String, size: Vector3, center: Vector3, cut := false) -> Node:
	return (
		level
		. create_brush_from_info(
			{
				"brush_id": id,
				"size": size,
				"center": center,
				"operation":
				CSGShape3D.OPERATION_SUBTRACTION if cut else CSGShape3D.OPERATION_UNION,
			}
		)
	)


## The corners of each `<polygon class="...">` in an SVG, as sets of "x,y".
static func _polygons(svg: String, kind: String) -> Array:
	var out: Array = []
	var pattern := RegEx.create_from_string('<polygon class="%s" points="([^"]+)"' % kind)
	for found in pattern.search_all(svg):
		var corners := {}
		for pair in found.get_string(1).split(" "):
			corners[pair] = true
		out.append(corners)
	return out


func test_a_4_by_2_box_is_a_4_by_2_rectangle_centred_on_the_origin_in_metres():
	var level := make_level()
	_box(level, "box", Vector3(4, 3, 2), Vector3(0, 1.5, 0))
	var svg := HFLevelPlan.svg(HFLevelPlan.shapes(level))
	assert_eq(_polygons(svg, "solid"), [{"-2,-1": true, "2,-1": true, "2,1": true, "-2,1": true}])


func test_two_floors_give_two_plans():
	var level := make_level()
	_box(level, "ground", Vector3(8, 3, 8), Vector3(0, 1.5, 0))
	_box(level, "upper", Vector3(4, 3, 4), Vector3(2, 4.5, 2))
	var ground := HFLevelPlan.shapes(level, 0.5, 2.5)
	var upper := HFLevelPlan.shapes(level, 3.5, 5.5)
	assert_eq(ground["solids"].size(), 1)
	assert_eq(upper["solids"].size(), 1)
	assert_ne(HFLevelPlan.svg(ground), HFLevelPlan.svg(upper))
	assert_eq(
		_polygons(HFLevelPlan.svg(upper), "solid"),
		[{"0,0": true, "4,0": true, "4,4": true, "0,4": true}]
	)


func test_a_turned_brush_crossing_the_band_is_cut_at_its_edges():
	var level := make_level()
	var ramp := _box(level, "ramp", Vector3(4, 0.5, 2), Vector3(0, 1, 0))
	ramp.rotation = Vector3(0, 0, deg_to_rad(45))
	var whole := HFLevelPlan.shapes(level)["solids"][0] as PackedVector2Array
	var sliced := HFLevelPlan.shapes(level, 0.9, 1.1)["solids"][0] as PackedVector2Array
	var width := func(outline: PackedVector2Array) -> float:
		var low := INF
		var high := -INF
		for corner in outline:
			low = minf(low, corner.x)
			high = maxf(high, corner.x)
		return high - low
	assert_lt(width.call(sliced), width.call(whole), "only the part in the band")


func test_cuts_are_hatched_and_entities_drawn_by_kind():
	var level := make_level()
	_box(level, "wall", Vector3(8, 3, 0.5), Vector3(0, 1.5, 0))
	_box(level, "door", Vector3(2, 2.5, 1), Vector3(0, 1.25, 0), true)
	level._create_entity_from_map({"classname": "light_point", "origin": Vector3(0, 2, 3)})
	level._create_entity_from_map({"classname": "player_start", "origin": Vector3(2, 0, 3)})
	var svg := HFLevelPlan.svg(HFLevelPlan.shapes(level))
	assert_true(svg.contains('<polygon class="cut"'), "the cut is drawn")
	assert_true(svg.contains('fill="url(#hatch)"'), "hatched")
	assert_true(svg.contains('class="entity light"'), "a light")
	assert_true(svg.contains('class="entity spawn"'), "a spawn")
	assert_true(svg.contains('class="north"') and svg.contains('class="scale"'))


## Within a step of eight bits a channel, which is what the image keeps.
static func _near(pixel: Color, color: Color) -> bool:
	return (
		absf(pixel.r - color.r) < 0.006
		and absf(pixel.g - color.g) < 0.006
		and absf(pixel.b - color.b) < 0.006
	)


func test_the_png_has_each_part_in_its_colour():
	var level := make_level()
	_box(level, "wall", Vector3(8, 3, 4), Vector3(0, 1.5, 0))
	_box(level, "hole", Vector3(2, 2.5, 2), Vector3(6, 1.25, 0), true)
	var picture := HFLevelPlan.image(HFLevelPlan.shapes(level), 256)
	var counts := {"solid": 0, "cut": 0, "background": 0}
	for y in picture.get_height():
		for x in picture.get_width():
			var pixel := picture.get_pixel(x, y)
			for kind in counts:
				if _near(pixel, HFLevelPlan.COLORS[kind]):
					counts[kind] += 1
	assert_gt(picture.get_width(), 200, "the long side is the size asked for")
	assert_gt(counts["solid"], counts["cut"], "the wall is filled and larger")
	assert_gt(counts["cut"], 0, "the cut is hatched")
	assert_gt(counts["background"], 0)


func test_the_png_has_the_scale_bar_and_the_arrow_in_the_margin():
	var level := make_level()
	_box(level, "wall", Vector3(8, 3, 4), Vector3(0, 1.5, 0))
	var picture := HFLevelPlan.image(HFLevelPlan.shapes(level), 400)
	var per_metre := float(picture.get_width()) / (8.0 + HFLevelPlan.MARGIN * 2.0)
	var margin := floori(HFLevelPlan.MARGIN * per_metre * 0.8)
	var marks := {"bottom left": 0, "top right": 0}
	for y in picture.get_height():
		for x in picture.get_width():
			if not _near(picture.get_pixel(x, y), HFLevelPlan.COLORS["outline"]):
				continue
			if y > picture.get_height() - margin and x < picture.get_width() / 2:
				marks["bottom left"] += 1
			elif y < margin and x > picture.get_width() / 2:
				marks["top right"] += 1
	# A 2 m bar on a 10 m wide plan, two pixels thick.
	assert_gt(marks["bottom left"], int(2.0 * per_metre), "the scale bar")
	assert_gt(marks["top right"], int(0.6 * per_metre), "the arrow to -Z")


func test_cordons_are_drawn_only_while_they_are_on():
	var level := make_level()
	_box(level, "box", Vector3(4, 3, 2), Vector3(0, 1.5, 0))
	level.cordon_aabb = AABB(Vector3(-10, 0, -10), Vector3(20, 5, 20))
	var off := HFLevelPlan.shapes(level)
	assert_eq(off["cordons"], [], "a level always has a cordon box, off by default")
	assert_eq(off["bounds"], Rect2(-2, -1, 4, 2), "the plan is the size of the level")
	level.cordon_enabled = true
	var on := HFLevelPlan.shapes(level)
	assert_eq(on["cordons"], [Rect2(-10, -10, 20, 20)])
	assert_eq(on["bounds"], Rect2(-10, -10, 20, 20))


func test_hf_plan_answers_a_png_and_svg_from_a_headless_editor():
	var level := make_level()
	_box(level, "box", Vector3(4, 3, 2), Vector3(0, 1.5, 0))
	var png := await call_tool("hf_plan", {"size": 128})
	assert_true(png.get("ok", false), str(png).left(200))
	if png.get("ok", false):
		assert_eq(png["result"]["image"]["mime_type"], "image/png")
		var bytes := Marshalls.base64_to_raw(png["result"]["image"]["data"])
		assert_eq(bytes.slice(1, 4).get_string_from_ascii(), "PNG")
		assert_eq(png["result"]["counts"]["solids"], 1)
		# A 4 m box and a metre round it: a 6 m wide plan, a 1 m bar.
		assert_eq(png["result"]["scale_bar_metres"], 1.0)
	var svg := await call_tool("hf_plan", {"format": "svg"})
	assert_true(str(svg.get("result", {}).get("svg", "")).begins_with("<svg"))
	var bad := await call_tool("hf_plan", {"y_min": 5, "y_max": 1})
	assert_refused(bad, HFMcpProtocol.E_INVALID_ARGUMENT)


func test_export_plan_writes_both_files():
	var level := make_level()
	_box(level, "box", Vector3(4, 3, 2), Vector3(0, 1.5, 0))
	var dock: Node = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = level
	DirAccess.make_dir_recursive_absolute(DIR)
	assert_eq(dock.export_plan_to(DIR.path_join("plan.svg")), OK)
	assert_true(FileAccess.file_exists(DIR.path_join("plan.svg")))
	assert_true(FileAccess.file_exists(DIR.path_join("plan.png")))
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))
	DirAccess.remove_absolute(DIR)


func test_the_reference_map_s_plan_is_pinned_by_its_svg_text():
	var level := make_level()
	assert_true(level.load_hflevel(REFERENCE), "fixture: the reference map loads")
	var svg := HFLevelPlan.svg(HFLevelPlan.shapes(level))
	if OS.get_environment("HF_WRITE_PLAN") == "1":
		var out := FileAccess.open(REFERENCE_PLAN, FileAccess.WRITE)
		out.store_string(svg)
		out.close()
	var pinned := FileAccess.get_file_as_string(REFERENCE_PLAN)
	assert_false(pinned.is_empty(), "the pinned plan is there")
	assert_eq(svg.length(), pinned.length(), "the same size as the pinned plan")
	assert_true(svg == pinned, "the same text; HF_WRITE_PLAN=1 writes it again")
