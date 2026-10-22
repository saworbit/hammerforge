extends GutTest

## A `.map` brush square to the axes came in as a BOX whatever its size, and a
## box under 0.1 on a side is widened to 0.1 with a warning. Trim two units thick
## at 32 units to the metre came in 0.1 thick, not 0.0625 (#1635). It is CUSTOM
## now, at its real thickness, as a cut piece that thin is since #1611.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const MapIOType = preload("res://addons/hammerforge/map_io.gd")
const QuakeAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")

const PATH := "user://hf_test_map_thin_brush.map"

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## A 64 unit cube written at 32 units to the metre, every map Z, which is the
## level's height, multiplied by `squash`.
func _cube_map(squash: float) -> String:
	root.create_brush_from_info({"size": Vector3(2, 2, 2), "center": Vector3.ZERO})
	var text := MapIOType.export_map_from_level(root, QuakeAdapter.new(), 32.0, true)
	root.clear_brushes()
	var point := RegEx.create_from_string("\\(\\s*(\\S+)\\s+(\\S+)\\s+(\\S+)\\s*\\)")
	var out := ""
	var at := 0
	for m in point.search_all(text):
		out += text.substr(at, m.get_start() - at)
		out += (
			"( %s %s %s )"
			% [m.get_string(1), m.get_string(2), str(float(m.get_string(3)) * squash)]
		)
		at = m.get_end()
	return out + text.substr(at)


func _import(text: String) -> DraftBrush:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	assert_eq(root.import_map(PATH), OK, "the file imports")
	var brushes: Array = root.get_all_draft_brushes()
	assert_eq(brushes.size(), 1, "one brush")
	return brushes[0] as DraftBrush if brushes.size() == 1 else null


func _height(brush: DraftBrush) -> float:
	return root.brush_system.world_bounds_of(brush).size.y


func test_a_thin_axis_aligned_brush_keeps_its_thickness():
	# 64 x 2 x 64 units: 2 x 0.0625 x 2 at 32 units to the metre.
	var brush := _import(_cube_map(1.0 / 32.0))
	if brush == null:
		return
	assert_eq(brush.shape, LevelRootType.BrushShape.CUSTOM, "too thin for a box")
	assert_almost_eq(_height(brush), 0.0625, 0.0001, "at its own thickness")
	assert_eq(brush.get_faces().size(), 6, "with its six faces")


func test_a_brush_a_box_can_hold_is_still_a_box():
	var brush := _import(_cube_map(1.0))
	if brush == null:
		return
	assert_eq(brush.shape, LevelRootType.BrushShape.BOX)
	assert_almost_eq(_height(brush), 2.0, 0.0001)
