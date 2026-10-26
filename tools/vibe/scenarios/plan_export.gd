@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Export Plan draws the level it was given, at the size it says.
##
## `HFLevelPlan` draws a top down plan from the brushes, so it works headless and
## in CI: solids filled, cuts hatched, a scale bar and an arrow to -Z. The guide's
## own example takes one floor of several with `--y-min=3 --y-max=6`. Each case
## here measures what came back against what was built: the footprint's corners
## and area worked out by hand, the PNG's filled pixels counted, and the scale bar
## and arrow measured in the pixels a reader sees.
##
## Brush entity wires are #1959.

const HFLevelPlan = preload("res://addons/hammerforge/hf_level_plan.gd")


func id() -> String:
	return "plan-export"


func summary() -> String:
	return "the plan's bands, bounds and scale with storeys, turned brushes, far levels, empty levels and one tiny brush"


func expected_issues() -> Array[int]:
	return [1983, 1990]


func run() -> void:
	await _storeys()
	await _turned()
	await _far_and_tiny()
	await _empty()
	await _big_level_furniture()


func _area(outline: PackedVector2Array) -> float:
	var twice := 0.0
	for i in outline.size():
		twice += outline[i].cross(outline[(i + 1) % outline.size()])
	return absf(twice) * 0.5


## Two storeys on a 3 m grid, the guide's own band for the upper one.
func _storeys() -> void:
	var root: Node3D = await fresh_root("PlanStoreys")
	# Ground floor: four walls 0..3 m. Upper floor: a smaller room 3..6 m,
	# standing on a slab whose top is at 3 m.
	box(root, Vector3(10, 3, 0.25), Vector3(0, 1.5, -5))
	box(root, Vector3(10, 3, 0.25), Vector3(0, 1.5, 5))
	box(root, Vector3(0.25, 3, 10), Vector3(-5, 1.5, 0))
	box(root, Vector3(0.25, 3, 10), Vector3(5, 1.5, 0))
	box(root, Vector3(4, 3, 0.25), Vector3(0, 4.5, -2))
	box(root, Vector3(4, 3, 0.25), Vector3(0, 4.5, 2))
	await frame()
	var upper: Dictionary = HFLevelPlan.shapes(root, 3.0, 6.0)
	var lower: Dictionary = HFLevelPlan.shapes(root, 0.0, 3.0)
	note("upper band 3..6: solids", upper["solids"].size())
	note("lower band 0..3: solids", lower["solids"].size())
	var flat_upper := 0
	for outline in upper["solids"]:
		if _area(outline) > 0.0:
			flat_upper += 1
	if upper["solids"].size() != 2:
		known(
			1983,
			(
				"the upper floor's plan (--y-min=3 --y-max=6, the guide's example) draws %d solids where the floor has 2"
				% upper["solids"].size()
			),
			(
				"the four ground floor walls end at y=3, so footprint() takes their top corners as 'in the band' (a.y >= y_min) and draws a wall that has no height in the band; the bounds grow to %s"
				% upper["bounds"]
			)
		)
	if lower["solids"].size() != 4:
		known(
			1983,
			(
				"the ground floor's plan (0..3) draws %d solids where the floor has 4"
				% lower["solids"].size()
			),
			"the upper walls begin at y=3 and their bottom corners touch the band"
		)
	# The same band one millimetre in from each side: what a mapper means.
	var inside: Dictionary = HFLevelPlan.shapes(root, 3.001, 5.999)
	note("upper band 3.001..5.999: solids", inside["solids"].size())
	await drop_root(root)


## A 4 x 2 box turned 30 degrees about Y: its footprint is the turned rectangle,
## of area 8, and its bounds the turned corners'.
func _turned() -> void:
	var root: Node3D = await fresh_root("PlanTurned")
	var b = box(root, Vector3(4, 3, 2), Vector3(20, 1.5, 0))
	root.rotate_managed_nodes([str(b.brush_id)], [], 1, 30.0, Vector3(20, 1.5, 0))
	await frame()
	var data: Dictionary = HFLevelPlan.shapes(root)
	var outline: PackedVector2Array = data["solids"][0]
	var area := _area(outline)
	var c := cos(deg_to_rad(30.0))
	var s := sin(deg_to_rad(30.0))
	var half := Vector2(2.0 * c + 1.0 * s, 2.0 * s + 1.0 * c)
	var bounds: Rect2 = data["bounds"]
	note("turned footprint", "%d corners, area %.4f, bounds %s" % [outline.size(), area, bounds])
	if absf(area - 8.0) > 0.01:
		flag("a turned 4 x 2 box's footprint is not 8 m2", area)
	if not bounds.size.is_equal_approx(half * 2.0):
		flag(
			"a turned box's plan bounds are not its turned corners'",
			"%s against %s" % [bounds.size, half * 2.0]
		)
	await drop_root(root)


## A brush 9 km out, and a brush 5 cm across.
func _far_and_tiny() -> void:
	var root: Node3D = await fresh_root("PlanFar")
	box(root, Vector3(2, 2, 2), Vector3(9000, 1, -9000))
	await frame()
	var data: Dictionary = HFLevelPlan.shapes(root)
	var picture: Image = HFLevelPlan.image(data, 256)
	var filled := _count(picture, HFLevelPlan.COLORS["solid"])
	var per_metre := float(picture.get_width()) / 4.0
	var expected := int(4.0 * per_metre * per_metre)
	note("9 km out: bounds", data["bounds"])
	note(
		"9 km out: PNG size and solid pixels",
		(
			"%dx%d, %d filled of about %d"
			% [picture.get_width(), picture.get_height(), filled, expected]
		)
	)
	if filled < expected * 0.8:
		flag("a 2 m brush 9 km out fills %d pixels of about %d" % [filled, expected])
	await drop_root(root)

	root = await fresh_root("PlanTiny")
	var tiny = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(0.1, 0.1, 0.1), "center": Vector3(0, 0.05, 0)}
	)
	await frame()
	data = HFLevelPlan.shapes(root)
	picture = HFLevelPlan.image(data, 512)
	filled = _count(picture, HFLevelPlan.COLORS["solid"])
	var svg: String = HFLevelPlan.svg(data)
	note("tiny: size asked / built", "0.1 / %s" % tiny.size)
	note(
		"tiny: PNG %dx%d" % [picture.get_width(), picture.get_height()], "%d solid pixels" % filled
	)
	if not svg.contains('<polygon class="solid"'):
		flag("a 0.1 m brush is not drawn in the SVG")
	await drop_root(root)


## No brushes, no entities.
func _empty() -> void:
	var root: Node3D = await fresh_root("PlanEmpty")
	var data: Dictionary = HFLevelPlan.shapes(root)
	var svg: String = HFLevelPlan.svg(data)
	var picture: Image = HFLevelPlan.image(data, 128)
	note("empty: bounds", data["bounds"])
	note("empty: PNG", "%dx%d" % [picture.get_width(), picture.get_height()])
	if not svg.begins_with("<svg") or not svg.strip_edges().ends_with("</svg>"):
		flag("an empty level's SVG is not one svg element")
	var dir := "user://vibe_plan_export"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err: int = HFLevelPlan.write_files(root, dir + "/empty")
	note("empty: write_files", error_string(err))
	if err != OK:
		flag("an empty level's plan does not write", error_string(err))
	for ext in [".svg", ".png"]:
		if FileAccess.file_exists(dir + "/empty" + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/empty" + ext))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	await drop_root(root)


## The scale bar's label and the arrow to -Z are sized off a fixed 1 m margin.
## Measured on levels 10, 60 and 200 m across: the arrow's pixels counted in the
## PNG's top right corner, as `test_level_plan.gd` counts them on a 10 m level,
## and the SVG label's height when the SVG is drawn 1024 wide.
func _big_level_furniture() -> void:
	var seen := {}
	for width in [10.0, 60.0, 200.0]:
		var root: Node3D = await fresh_root("PlanBig")
		box(root, Vector3(width, 3, width * 0.5), Vector3(0, 1.5, 0))
		await frame()
		var data: Dictionary = HFLevelPlan.shapes(root)
		var view: Rect2 = (data["bounds"] as Rect2).grow(HFLevelPlan.MARGIN)
		var picture: Image = HFLevelPlan.image(data, 1024)
		var per_metre := float(picture.get_width()) / view.size.x
		var corner := ceili(HFLevelPlan.MARGIN * per_metre)
		var arrow := 0
		for y in mini(corner, picture.get_height()):
			for x in range(maxi(0, picture.get_width() - corner), picture.get_width()):
				var p := picture.get_pixel(x, y)
				var c: Color = HFLevelPlan.COLORS["outline"]
				if absf(p.r - c.r) < 0.01 and absf(p.g - c.g) < 0.01 and absf(p.b - c.b) < 0.01:
					arrow += 1
		var label_px := HFLevelPlan.MARGIN * 0.3 * per_metre
		seen[int(width)] = [arrow, label_px]
		note(
			"%d m level, 1024 px" % int(width),
			(
				"arrow to -Z: %d outline pixels in the top right margin; SVG scale label %.1f px tall at 1024 wide"
				% [arrow, label_px]
			)
		)
		await drop_root(root)
	var big: Array = seen[200]
	if int(big[0]) < 20 or float(big[1]) < 4.0:
		known(
			1990,
			(
				"on a 200 m level the arrow to -Z is %d pixels of the 1024 PNG and the scale bar's label %.1f px tall"
				% [big[0], big[1]]
			),
			(
				"%d pixels on a 10 m level. The arrow (0.6 m), its wings and ticks (0.15 m) and both labels (0.3 m, 0.25 m) are sized off MARGIN in metres, while the line width grows with the view, so the arrow and the scale's number shrink with the level; hf_level_plan.gd _svg_scale_and_arrow / _png_scale_and_arrow"
				% seen[10][0]
			)
		)


func _count(picture: Image, colour: Color) -> int:
	var many := 0
	for y in picture.get_height():
		for x in picture.get_width():
			var p := picture.get_pixel(x, y)
			if (
				absf(p.r - colour.r) < 0.01
				and absf(p.g - colour.g) < 0.01
				and absf(p.b - colour.b) < 0.01
			):
				many += 1
	return many
