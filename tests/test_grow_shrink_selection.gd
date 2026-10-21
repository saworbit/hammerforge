extends GutTest
## Grow Selection (Ctrl+]) and Shrink Selection (Ctrl+[) (#1433).
##
## Faces grow across every edge a selected face shares with another face, on its
## own brush or on a brush laid beside it, within Same plane only and Max angle.
## Brushes grow to every brush whose solid touches theirs, which a bounds sweep
## alone cannot say for a turned brush. Shrink takes back what a Grow adds. A
## hidden brush is never reached, the face mark follows, and selecting is no
## undo step, so neither is a grow.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFSelectionGrow = preload("res://addons/hammerforge/hf_selection_grow.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


func after_each() -> void:
	var popup = rig.plugin._selection_filter
	popup._grow_same_plane.button_pressed = false
	popup._grow_max_angle.value = HFSelectionGrow.DEFAULT_MAX_ANGLE


# ---------------------------------------------------------------------------
# Scenes and helpers
# ---------------------------------------------------------------------------


func _face_toward(brush: Node, direction: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(direction) > 0.99:
			return i
	return -1


func _faces_with_normal_y(brush: Node, low: float, high: float) -> Array:
	var out: Array = []
	for i in brush.faces.size():
		var y: float = brush.faces[i].normal.y
		if y >= low and y <= high:
			out.append(i)
	return out


func _grow() -> int:
	return rig.forward(PluginRig.key_for("grow_selection"))


func _shrink() -> int:
	return rig.forward(PluginRig.key_for("shrink_selection"))


func _options(same_plane: bool, max_angle: float) -> void:
	var popup = rig.plugin._selection_filter
	popup._grow_same_plane.button_pressed = same_plane
	popup._grow_max_angle.value = max_angle


## Four 4 m floor tiles in a row along X, their tops at y 0, and a wall standing
## on them along their back edge, flush with it.
func _floor_row(level: Node) -> Array:
	var tiles: Array = []
	for i in 4:
		tiles.append(rig.box(level, "floor%d" % i, Vector3(i * 4, -0.5, 0), Vector3(4, 1, 4)))
	rig.box(level, "wall", Vector3(6, 2, -1.75), Vector3(16, 4, 0.5))
	return tiles


## A floor of `count` by `count` 2 m tiles, tops at y 0, keyed "t<x>_<z>".
func _floor_grid(level: Node, count: int) -> Dictionary:
	var tiles: Dictionary = {}
	for x in count:
		for z in count:
			var id := "t%d_%d" % [x, z]
			tiles[id] = rig.box(level, id, Vector3(x * 2, -0.5, z * 2), Vector3(2, 1, 2))
	return tiles


func _start_faces(level: Node, picks: Dictionary) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_select")
	rig.plugin.dock.face_select_mode.button_pressed = true
	level.face_selection = picks.duplicate(true)
	level.face_selection_changed.emit()


func _leave(level: Node) -> void:
	rig.plugin.dock.face_select_mode.button_pressed = false
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)


## Three steps 4 m wide, each 1 m deep and one step higher, filled to the
## ground, so each shares a face with the next.
func _stairs(level: Node) -> Array:
	return [
		rig.box(level, "step0", Vector3(0, 0.5, 0.5), Vector3(4, 1, 1)),
		rig.box(level, "step1", Vector3(0, 1, 1.5), Vector3(4, 2, 1)),
		rig.box(level, "step2", Vector3(0, 1.5, 2.5), Vector3(4, 3, 1)),
	]


func _turned_box(level: Node, id: String, center: Vector3, size: Vector3, basis: Basis) -> Node:
	return level.create_brush_from_info(
		{"size": size, "brush_id": id, "transform": Transform3D(basis, center)}
	)


# ---------------------------------------------------------------------------
# Faces
# ---------------------------------------------------------------------------


func test_same_plane_grows_along_the_floor_tops_and_never_up_a_wall() -> void:
	var level = await rig.make_level()
	var tiles := _floor_row(level)
	var top := _face_toward(tiles[0], Vector3.UP)
	_start_faces(level, {"floor0": [top]})
	_options(true, HFSelectionGrow.DEFAULT_MAX_ANGLE)
	for step in range(1, 4):
		assert_eq(_grow(), STOP, "Ctrl+] is taken")
		var expected := {}
		for i in step + 1:
			expected["floor%d" % i] = [_face_toward(tiles[i], Vector3.UP)]
		assert_eq(level.face_selection, expected, "grow %d reaches the next top, no wall" % step)
	_grow()
	assert_eq(level.face_selection.size(), 4, "with every top taken there is nowhere to go")
	assert_false(level.face_selection.has("wall"), "the wall is never reached")
	await _leave(level)


func test_without_same_plane_the_wall_standing_on_the_edge_is_reached() -> void:
	# The control for the case above: the wall's faces do share the floor's
	# back edge, so Same plane only is what keeps them out.
	var level = await rig.make_level()
	var tiles := _floor_row(level)
	_start_faces(level, {"floor0": [_face_toward(tiles[0], Vector3.UP)]})
	_grow()
	assert_true(level.face_selection.has("wall"), "a plain grow climbs the wall")
	assert_true(level.face_selection.has("floor1"), "and takes the next tile's faces")
	assert_eq(
		(level.face_selection["floor0"] as Array).size(),
		5,
		"and the four sides of its own tile, edge to edge with its top"
	)
	await _leave(level)


func test_max_angle_30_grows_round_a_cylinder_and_stops_at_its_caps() -> void:
	var level = await rig.make_level()
	var cylinder = (
		level
		. create_brush_from_info(
			{
				"shape": LevelRootType.BrushShape.CYLINDER,
				"sides": 16,
				"size": Vector3(8, 4, 8),
				"center": Vector3.ZERO,
				"brush_id": "drum",
			}
		)
	)
	var sides := _faces_with_normal_y(cylinder, -0.01, 0.01)
	assert_eq(sides.size(), 16, "a 16-sided cylinder has 16 sides")
	_start_faces(level, {"drum": [sides[0]]})
	_options(false, 20.0)
	_grow()
	assert_eq(level.face_selection["drum"], [sides[0]], "22.5 degrees is past a Max angle of 20")
	_options(false, 30.0)
	for i in 8:
		_grow()
	var picked: Array = level.face_selection["drum"].duplicate()
	picked.sort()
	assert_eq(picked, sides, "eight grows go all the way round")
	_grow()
	assert_eq(level.face_selection["drum"].size(), 16, "and never onto a cap")
	_options(false, HFSelectionGrow.DEFAULT_MAX_ANGLE)
	_grow()
	assert_eq(level.face_selection["drum"].size(), 18, "the caps are 90 degrees off")
	await _leave(level)


func test_grow_then_shrink_gives_a_floor_patch_back() -> void:
	var level = await rig.make_level()
	var tiles := _floor_grid(level, 5)
	var patch := {
		"t2_2": [_face_toward(tiles["t2_2"], Vector3.UP)],
		"t3_2": [_face_toward(tiles["t3_2"], Vector3.UP)],
	}
	for same_plane in [true, false]:
		_options(same_plane, HFSelectionGrow.DEFAULT_MAX_ANGLE)
		_start_faces(level, patch)
		_grow()
		assert_gt(
			HFSelectionGrow.face_count(level.face_selection),
			HFSelectionGrow.face_count(patch),
			"the grow added faces (same plane %s)" % same_plane
		)
		assert_eq(_shrink(), STOP, "Ctrl+[ is taken")
		assert_eq(level.face_selection, patch, "and Shrink gives the patch back")
	await _leave(level)


func test_shrink_drops_the_faces_on_the_edge_and_refuses_to_drop_all() -> void:
	var level = await rig.make_level()
	var tiles := _floor_grid(level, 5)
	_options(true, HFSelectionGrow.DEFAULT_MAX_ANGLE)
	var tops := func(ids: Array) -> Dictionary:
		var out := {}
		for id in ids:
			out[id] = [_face_toward(tiles[id], Vector3.UP)]
		return out
	var block: Dictionary = tops.call(
		["t1_1", "t1_2", "t1_3", "t2_1", "t2_2", "t2_3", "t3_1", "t3_2", "t3_3"]
	)
	_start_faces(level, block)
	_shrink()
	assert_eq(level.face_selection.keys(), ["t2_2"], "a 3 by 3 block shrinks to its middle")
	var row: Dictionary = tops.call(["t1_2", "t2_2", "t3_2"])
	_start_faces(level, row)
	_shrink()
	assert_eq(level.face_selection, row, "every tile of a row borders a free top")
	assert_true(
		rig.toasts().has("Shrink would leave nothing selected"), "so Shrink says so and keeps it"
	)
	var whole: Dictionary = tops.call(tiles.keys())
	_start_faces(level, whole)
	_shrink()
	assert_eq(level.face_selection, whole, "in its own plane the whole floor has no edge")
	# Without Same plane only, each top meets its own tile's sides.
	_options(false, HFSelectionGrow.DEFAULT_MAX_ANGLE)
	_shrink()
	assert_eq(level.face_selection, whole, "and every top is on an edge, so none can go")
	await _leave(level)


func test_a_tile_a_visgroup_hides_is_never_grown_onto() -> void:
	var level = await rig.make_level()
	var tiles := _floor_row(level)
	level.visgroup_system.create_visgroup("off")
	level.visgroup_system.add_to_visgroup(tiles[1], "off")
	level.visgroup_system.set_visgroup_visible("off", false)
	_options(true, HFSelectionGrow.DEFAULT_MAX_ANGLE)
	_start_faces(level, {"floor0": [_face_toward(tiles[0], Vector3.UP)]})
	_grow()
	assert_eq(level.face_selection.keys(), ["floor0"], "the hidden next tile is not reached")
	await _leave(level)


func test_the_face_mark_follows_a_grow_and_neither_is_an_undo_step() -> void:
	var level = await rig.make_level()
	var tiles := _floor_grid(level, 5)
	_options(true, HFSelectionGrow.DEFAULT_MAX_ANGLE)
	_start_faces(level, {"t2_2": [_face_toward(tiles["t2_2"], Vector3.UP)]})
	await rig.frame()
	var steps: int = rig.undo().step_count()
	_grow()
	await rig.frame()
	assert_eq(rig.plugin._face_selection_overlay.get_entries().size(), 5, "five faces marked")
	_shrink()
	await rig.frame()
	assert_eq(rig.plugin._face_selection_overlay.get_entries().size(), 1, "and one again")
	assert_eq(rig.undo().step_count(), steps, "selecting records no step")
	await _leave(level)


func test_the_selection_filters_row_grows_with_its_own_options() -> void:
	var level = await rig.make_level()
	var tiles := _floor_row(level)
	var popup = rig.plugin._selection_filter
	_start_faces(level, {"floor0": [_face_toward(tiles[0], Vector3.UP)]})
	popup.show_for(level, rig.plugin.hf_selection)
	popup._grow_same_plane.button_pressed = true
	popup._filter_grow()
	assert_eq(
		level.face_selection,
		{
			"floor0": [_face_toward(tiles[0], Vector3.UP)],
			"floor1": [_face_toward(tiles[1], Vector3.UP)]
		},
		"the row's Grow takes the next top"
	)
	_grow()
	assert_false(level.face_selection.has("wall"), "and Ctrl+] keeps to Same plane only too")
	popup._filter_shrink()
	assert_eq(level.face_selection.size(), 2, "the row's Shrink drops the newest top")
	await _leave(level)


# ---------------------------------------------------------------------------
# Brushes
# ---------------------------------------------------------------------------


func test_brush_grow_adds_the_touching_steps_and_not_a_turned_brush_beside_them() -> void:
	var level = await rig.make_level()
	var steps := _stairs(level)
	# Turned 45 degrees and set off the steps' corner: its box meets theirs along
	# a line, and the brush itself stays a metre clear.
	var turned = _turned_box(
		level,
		"turned",
		Vector3(2 + sqrt(2.0), 0.5, 1 + sqrt(2.0)),
		Vector3(2, 1, 2),
		Basis(Vector3.UP, PI / 4)
	)
	var bounds: Callable = func(brush): return level.brush_system.world_bounds_of(brush)
	assert_true(
		bounds.call(turned).grow(0.001).intersects(bounds.call(steps[0])),
		"the turned brush's box touches the bottom step's box"
	)
	assert_false(HFSelectionGrow.brushes_touch(turned, steps[0]), "its shape does not")
	rig.select([steps[1]])
	assert_eq(_grow(), STOP, "Ctrl+] is taken for a brush")
	assert_eq(rig.plugin.hf_selection, [steps[1], steps[0], steps[2]], "both neighbours come")
	rig.select([steps[0]])
	_grow()
	assert_eq(rig.plugin.hf_selection, [steps[0], steps[1]], "the bottom step meets one step")
	assert_false(rig.plugin.hf_selection.has(turned), "and not the turned brush")
	await rig.leave_level(level)


func test_a_turned_brush_whose_corner_meets_a_step_is_grown_onto() -> void:
	var level = await rig.make_level()
	var steps := _stairs(level)
	# A corner of the turned box rests on the bottom step's end face.
	var turned = _turned_box(
		level,
		"turned",
		Vector3(2 + sqrt(2.0), 0.5, 0.5),
		Vector3(2, 1, 2),
		Basis(Vector3.UP, PI / 4)
	)
	assert_true(HFSelectionGrow.brushes_touch(turned, steps[0]), "a corner on a face touches")
	rig.select([steps[0]])
	_grow()
	assert_true(rig.plugin.hf_selection.has(turned), "so a grow reaches it")
	await rig.leave_level(level)


func test_brush_shrink_drops_the_brushes_touching_unselected_ones() -> void:
	var level = await rig.make_level()
	var steps := _stairs(level)
	rig.select([steps[0], steps[1]])
	assert_eq(_shrink(), STOP, "Ctrl+[ is taken for a brush")
	assert_eq(rig.plugin.hf_selection, [steps[0]], "the step touching the free one goes")
	_shrink()
	assert_eq(rig.plugin.hf_selection, [steps[0]], "a last step touching others stays")
	assert_true(rig.toasts().has("Shrink would leave nothing selected"), "and Shrink says why")
	await rig.leave_level(level)


func test_a_brush_a_visgroup_hides_is_never_grown_onto() -> void:
	var level = await rig.make_level()
	var steps := _stairs(level)
	level.visgroup_system.create_visgroup("off")
	level.visgroup_system.add_to_visgroup(steps[2], "off")
	level.visgroup_system.set_visgroup_visible("off", false)
	rig.select([steps[1]])
	_grow()
	assert_eq(rig.plugin.hf_selection, [steps[1], steps[0]], "the hidden step stays out")
	await rig.leave_level(level)


func test_a_brush_grow_records_no_undo_step() -> void:
	var level = await rig.make_level()
	var steps := _stairs(level)
	rig.select([steps[1]])
	await rig.frame()
	var before: int = rig.undo().step_count()
	_grow()
	_shrink()
	await rig.frame()
	assert_eq(rig.undo().step_count(), before, "selecting brushes records no step")
	await rig.leave_level(level)


## Two cubes that pass each other ridge across ridge, a hair apart: one turned
## 45 degrees about Z, the other about X above it, and the pair turned 30 degrees
## about X so their boxes overlap. No face of either separates them; only the
## cross product of the two ridges does.
func test_the_separating_test_reaches_the_axis_two_edges_make() -> void:
	var level = await rig.make_level()
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(30.0))
	var size := Vector3(2, 2, 2)
	var lower = _turned_box(level, "lower", Vector3.ZERO, size, tilt * Basis(Vector3.BACK, PI / 4))
	var rise := 2.0 * sqrt(2.0)
	var apart = _turned_box(
		level, "apart", tilt * Vector3(0, rise + 0.1, 0), size, tilt * Basis(Vector3.RIGHT, PI / 4)
	)
	var bounds: Callable = func(brush): return level.brush_system.world_bounds_of(brush)
	assert_true(bounds.call(lower).intersects(bounds.call(apart)), "their boxes overlap")
	var faces_only_a: Dictionary = HFSelectionGrow.hull_of(lower)
	var faces_only_b: Dictionary = HFSelectionGrow.hull_of(apart)
	faces_only_a["edges"] = []
	faces_only_b["edges"] = []
	assert_true(
		HFSelectionGrow.hulls_touch(faces_only_a, faces_only_b),
		"the face normals alone find no gap"
	)
	assert_false(HFSelectionGrow.brushes_touch(lower, apart), "the edge axis does")
	var crossing = _turned_box(
		level,
		"crossing",
		tilt * Vector3(0, rise - 0.05, 0),
		size,
		tilt * Basis(Vector3.RIGHT, PI / 4)
	)
	assert_true(HFSelectionGrow.brushes_touch(lower, crossing), "ridges that cross do touch")
	await rig.leave_level(level)


func test_edges_overlap_only_along_a_shared_run() -> void:
	var o := Vector3.ZERO
	var x4 := Vector3(4, 0, 0)
	assert_true(HFSelectionGrow.edges_overlap(o, x4, Vector3(2, 0, 0), Vector3(6, 0, 0)))
	assert_true(HFSelectionGrow.edges_overlap(o, x4, x4, o), "either way round")
	assert_false(
		HFSelectionGrow.edges_overlap(o, x4, x4, Vector3(8, 0, 0)), "end to end is a corner"
	)
	assert_false(
		HFSelectionGrow.edges_overlap(o, x4, Vector3(2, 0, -1), Vector3(2, 0, 1)), "crossing"
	)
	assert_false(
		HFSelectionGrow.edges_overlap(o, x4, Vector3(0, 0.1, 0), Vector3(4, 0.1, 0)), "parallel"
	)
