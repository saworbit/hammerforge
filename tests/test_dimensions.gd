extends GutTest

## Dimensions that stay in the level and follow the brushes they measure (#1699).

const HFDimensions = preload("res://addons/hammerforge/hf_dimensions.gd")
const HFPluginDimensions = preload("res://addons/hammerforge/plugin_dimensions.gd")
const HFNotes = preload("res://addons/hammerforge/hf_notes.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const HFMcpTools = preload("res://addons/hammerforge/mcp/hf_mcp_tools.gd")
const UndoStandIn = preload("res://tests/test_undo_collation.gd").FakeUndoRedo

const LEVEL := "user://hf_test_dimensions.hflevel"
const SCENE := "user://hf_test_dimensions_playtest.tscn"

var root: LevelRoot
var undo


func before_each() -> void:
	root = _level()
	undo = UndoStandIn.new()


func after_each() -> void:
	for path in [LEVEL, SCENE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _box(id: String, center: Vector3, size := Vector3(1, 2, 1)) -> Node3D:
	return root.create_brush_from_info(
		{"shape": LevelRoot.BrushShape.BOX, "size": size, "center": center, "brush_id": id}
	)


## A doorway: two walls with a gap between them, and a dimension across the gap
## from a corner of one to a corner of the other at the same height.
func _doorway(gap: float) -> Node:
	_box("left", Vector3(-0.5 - gap * 0.5, 1, 0))
	_box("right", Vector3(0.5 + gap * 0.5, 1, 0))
	var dimension := HFPluginDimensions.keep(
		root, Vector3(-gap * 0.5, 0, 0.5), Vector3(gap * 0.5, 0, 0.5), undo
	)
	assert_not_null(dimension, "fixture: kept")
	return dimension


func test_each_end_is_attached_to_the_corner_it_lies_on():
	var dimension := _doorway(1.5)
	var data: Dictionary = dimension.entity_data
	assert_eq(str(data[HFDimensions.END_A]["brush_id"]), "left")
	assert_eq(str(data[HFDimensions.END_B]["brush_id"]), "right")
	assert_eq(str(data[HFDimensions.END_A]["kind"]), "vertex")
	assert_almost_eq(HFDimensions.measure(root, dimension)["length"], 1.5, 0.0001)


func test_a_kept_dimension_saves_with_the_level_and_comes_back():
	_doorway(1.5)
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	await _finish_saving(root)
	var other := _level()
	assert_true(other.load_hflevel(LEVEL))
	var found := HFDimensions.dimensions(other)
	assert_eq(found.size(), 1)
	if found.size() == 1:
		var measured := HFDimensions.measure(other, found[0])
		assert_almost_eq(measured["length"], 1.5, 0.0001, "the same length")
		assert_false(measured["detached"], "still on its corners")


func test_moving_a_brush_moves_the_dimension_in_the_same_step_and_undo_puts_both_back():
	var dimension := _doorway(1.5)
	var steps: int = undo.step_count() if undo.has_method("step_count") else -1
	HFUndoHelper.commit(
		undo,
		root,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[["right"], [], Vector3(0.5, 0, 0)],
		false,
		Callable(),
		"",
		true,
		["right"],
		[]
	)
	assert_almost_eq(HFDimensions.measure(root, dimension)["length"], 2.0, 0.0001, "it follows")
	if steps >= 0:
		assert_eq(undo.step_count(), steps + 1, "with no step of its own")
	undo.undo()
	await get_tree().process_frame
	assert_almost_eq(
		HFDimensions.measure(root, dimension)["length"], 1.5, 0.0001, "undo puts it back"
	)


func test_clipping_away_its_corner_detaches_that_end():
	var dimension := _doorway(1.5)
	var before: float = HFDimensions.measure(root, dimension)["length"]
	root.grid_snap = 0.25
	var cut: HFOpResult = root.clip_brush_by_id("right", 0, 1.25)
	assert_true(cut.ok, "fixture: the wall is cut: %s" % cut.user_text())
	await get_tree().process_frame
	var measured := HFDimensions.measure(root, dimension)
	assert_true(measured["detached"], "drawn amber")
	assert_almost_eq(measured["length"], before, 0.0001, "reading where the end was last")


func test_a_doorway_held_to_the_player_turns_red_when_narrowed_and_validate_names_it():
	var dimension := _doorway(1.5)
	dimension.entity_data["title"] = "front door"
	dimension.entity_data["check"] = "At least player width"
	assert_true(HFDimensions.measure(root, dimension)["passes"], "1.5 m lets the player through")
	root.nudge_managed_nodes(["right"], [], Vector3(-1.4, 0, 0))
	var measured := HFDimensions.measure(root, dimension)
	assert_false(measured["passes"], "0.1 m does not")
	var named: Array = (root.validate_level().get("issues", []) as Array).filter(
		func(issue): return str(issue).begins_with("Dimension front door")
	)
	assert_eq(named.size(), 1, "Validate lists it")


func test_a_dimension_never_reaches_a_bake_or_an_export():
	var dimension := _doorway(1.5)
	assert_true(HFNotes.is_editor_only(root, dimension), "its class is for the editor only")
	assert_true(root.export_playtest_scene(SCENE, false))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var found := false
	for node in scene.find_children("*", "", true, false):
		if HFDimensions.is_dimension(node):
			found = true
	scene.free()
	assert_false(found, "the exported scene has none")


func test_the_bridge_reports_its_length_and_check():
	var dimension := _doorway(1.5)
	dimension.entity_data["check"] = "At most"
	dimension.entity_data["value"] = 1.0
	var tools := HFMcpTools.new()
	var reported: Dictionary = tools.entity_dict(root, dimension)
	assert_true(reported.has("dimension"))
	assert_almost_eq(float(reported["dimension"]["length"]), 1.5, 0.0001)
	assert_false(reported["dimension"]["passes"], "1.5 m is more than 1 m")
	assert_eq(HFDimensions.summary(root), {"count": 1, "failing": 1, "detached": 0})


func test_a_free_end_moves_with_the_dimension():
	var dimension := HFPluginDimensions.keep(root, Vector3(0, 5, 0), Vector3(3, 5, 0), undo)
	assert_true(dimension.entity_data[HFDimensions.END_A].has("point"), "on nothing")
	(dimension as Node3D).global_position += Vector3(0, 1, 0)
	var measured := HFDimensions.measure(root, dimension)
	assert_almost_eq(measured["a"], Vector3(0, 6, 0), Vector3.ONE * 0.0001)
	assert_almost_eq(measured["length"], 3.0, 0.0001)


func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


func test_a_resize_that_moves_its_corner_detaches_that_end():
	var dimension := _doorway(1.5)
	root.set_brush_transform_by_id("right", Vector3(2, 2, 1), Vector3(1.75, 1, 0))
	assert_true(HFDimensions.measure(root, dimension)["detached"], "the corner it was on moved")
