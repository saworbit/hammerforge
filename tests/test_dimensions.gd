extends GutTest

## Dimensions that stay in the level and follow the brushes they measure (#1699).

const HFDimensions = preload("res://addons/hammerforge/hf_dimensions.gd")
const HFPluginDimensions = preload("res://addons/hammerforge/plugin_dimensions.gd")
const HFNotes = preload("res://addons/hammerforge/hf_notes.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const HFMcpTools = preload("res://addons/hammerforge/mcp/hf_mcp_tools.gd")
const UndoStandIn = preload("res://tests/test_undo_collation.gd").FakeUndoRedo
const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")

const LEVEL := "user://hf_test_dimensions.hflevel"
const SCENE := "user://hf_test_dimensions_playtest.tscn"
const PREFAB := "user://hf_test_dimensions_doorway.hfprefab"

var root: LevelRoot
var undo


func before_each() -> void:
	root = _level()
	undo = UndoStandIn.new()


func after_each() -> void:
	for path in [LEVEL, SCENE, PREFAB]:
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


## The right wall runs from 0.75 to 1.75 with the end on its corner at 0.75. A cut
## at 1.25 keeps that corner on the 0.75 to 1.25 piece, and the end goes with it;
## it used to come loose, under a test named for a cut that took the corner away
## (#2003).
func test_a_clip_that_keeps_its_corner_hands_the_end_to_that_piece():
	var dimension := _doorway(1.5)
	root.grid_snap = 0.25
	HFUndoHelper.commit(
		undo, root, "Clip Brush", "clip_brush_by_id", ["right", 0, 1.25], false, Callable()
	)
	assert_null(root.find_brush_by_id("right"), "fixture: the wall is cut into pieces")
	await get_tree().process_frame
	var measured := HFDimensions.measure(root, dimension)
	assert_false(measured["detached"], "still on its corner")
	assert_almost_eq(measured["b"], Vector3(0.75, 0, 0.5), Vector3.ONE * 0.0001)
	var held: Node = root.find_brush_by_id(
		str(dimension.entity_data[HFDimensions.END_B]["brush_id"])
	)
	assert_not_null(held, "on a piece")
	if held:
		assert_almost_eq(
			root.brush_system.world_bounds_of(held).end.x, 1.25, 0.0001, "the doorway side"
		)
	# The piece follows a move, and the undo puts the end back on the wall.
	root.nudge_brushes_by_id([str(held.brush_id)] if held else [], Vector3(0.5, 0, 0))
	assert_almost_eq(HFDimensions.measure(root, dimension)["length"], 2.0, 0.0001)
	undo.undo()
	await get_tree().process_frame
	var back := HFDimensions.measure(root, HFDimensions.dimensions(root)[0])
	assert_false(back["detached"], "attached after the undo")
	assert_eq(
		str(HFDimensions.dimensions(root)[0].entity_data[HFDimensions.END_B]["brush_id"]), "right"
	)


func test_a_clip_that_cuts_its_corner_away_detaches_that_end():
	var dimension := _doorway(1.5)
	var before: float = HFDimensions.measure(root, dimension)["length"]
	# Only the far side of the cut is kept, so the corner at 0.75 goes.
	var cut: HFOpResult = root.brush_system.clip_brush_keeping(
		"right", Plane(Vector3.RIGHT, 1.25), 1
	)
	assert_true(cut.ok, "fixture: the wall is cut: %s" % cut.user_text())
	await get_tree().process_frame
	var measured := HFDimensions.measure(root, dimension)
	assert_true(measured["detached"], "drawn amber")
	assert_almost_eq(measured["length"], before, 0.0001, "reading where the end was last")


## A notch carved from the far top of the right wall leaves the doorway's bottom
## corner alone, and the end stays on it (#2003).
func test_a_carve_that_keeps_its_corner_hands_the_end_to_that_piece():
	var dimension := _doorway(1.5)
	_box("notch", Vector3(1.55, 1.9, 0), Vector3(0.4, 0.4, 2))
	var carve: HFOpResult = root.carve_with_brush("notch")
	assert_true(carve.ok, "fixture: carved: %s" % carve.user_text())
	assert_null(root.find_brush_by_id("right"), "fixture: the wall is in pieces")
	var measured := HFDimensions.measure(root, dimension)
	assert_false(measured["detached"], "still on its corner")
	assert_almost_eq(measured["length"], 1.5, 0.0001)


func test_a_hollow_hands_the_end_to_the_wall_that_keeps_its_corner():
	var dimension := _doorway(1.5)
	var hollow: HFOpResult = root.hollow_brush_by_id("right", 0.2)
	assert_true(hollow.ok, "fixture: hollowed: %s" % hollow.user_text())
	assert_null(root.find_brush_by_id("right"), "fixture: the wall is in walls")
	var measured := HFDimensions.measure(root, dimension)
	assert_false(measured["detached"], "still on its corner")
	assert_almost_eq(measured["b"], Vector3(0.75, 0, 0.5), Vector3.ONE * 0.0001)


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


## A resize moves a corner within its brush's own space. The end used to come
## loose there, drawn amber, the moment a wall was made thicker, which is when
## the measurement matters; it now finds its corner by the faces that meet at it
## (#1898).
func test_a_resize_keeps_each_end_on_its_corner_and_reads_the_new_length():
	var dimension := _doorway(1.5)
	# The right wall twice as thick, away from the gap: its corner stays put.
	root.set_brush_transform_by_id("right", Vector3(2, 2, 1), Vector3(1.75, 1, 0))
	var measured := HFDimensions.measure(root, dimension)
	assert_false(measured["detached"], "still on the corner")
	assert_almost_eq(measured["length"], 1.5, 0.0001, "the gap is as wide")
	# And into the gap: the corner moves with the face.
	root.set_brush_transform_by_id("right", Vector3(2, 2, 1), Vector3(0.75, 1, 0))
	measured = HFDimensions.measure(root, dimension)
	assert_false(measured["detached"], "still on the corner")
	assert_almost_eq(measured["length"], 0.5, 0.0001, "and reads the narrower gap")


func test_undo_of_a_resize_puts_the_old_length_back_with_the_ends_attached():
	var dimension := _doorway(1.5)
	HFUndoHelper.commit(
		undo,
		root,
		"Resize Brush",
		"set_brush_transform_by_id",
		["right", Vector3(2, 2, 1), Vector3(0.75, 1, 0)],
		false,
		Callable()
	)
	assert_almost_eq(HFDimensions.measure(root, dimension)["length"], 0.5, 0.0001, "resized")
	undo.undo()
	await get_tree().process_frame
	# The undo puts the level's entities back, the dimension among them.
	var measured := HFDimensions.measure(root, HFDimensions.dimensions(root)[0])
	assert_false(measured["detached"], "attached after the undo")
	assert_almost_eq(measured["length"], 1.5, 0.0001, "the old length")


func test_an_end_kept_before_faces_were_saved_reads_as_it_did():
	var dimension := _doorway(1.5)
	for key in [HFDimensions.END_A, HFDimensions.END_B]:
		dimension.entity_data[key].erase("faces")
	assert_false(HFDimensions.measure(root, dimension)["detached"], "attached where it was")
	root.set_brush_transform_by_id("right", Vector3(2, 2, 1), Vector3(0.75, 1, 0))
	assert_true(HFDimensions.measure(root, dimension)["detached"], "and comes loose on a resize")


func test_an_end_on_an_edge_or_a_face_follows_a_resize_too():
	_box("slab", Vector3(0, 0.5, 0), Vector3(4, 1, 4))
	var on_edge := HFDimensions.attach(root, Vector3(0, 1, 2), Transform3D.IDENTITY)
	var on_face := HFDimensions.attach(root, Vector3(0, 1, 0), Transform3D.IDENTITY)
	assert_eq(str(on_edge["kind"]), "edge")
	assert_eq(str(on_face["kind"]), "face")
	root.set_brush_transform_by_id("slab", Vector3(4, 3, 6), Vector3(0, 1.5, 0))
	var holder := Node3D.new()
	add_child_autoqfree(holder)
	assert_almost_eq(
		HFDimensions.resolve(root, on_edge, holder)["point"], Vector3(0, 3, 3), Vector3.ONE * 0.0001
	)
	assert_almost_eq(
		HFDimensions.resolve(root, on_face, holder)["point"], Vector3(0, 3, 0), Vector3.ONE * 0.0001
	)


## What Duplicate asks the plugin for: the entity a selected node belongs to.
class _DuplicatingPlugin:
	extends RefCounted

	func _managed_entity_owner(level: Node, node: Node) -> Node:
		return HFPluginSelectionState.managed_entity_owner(level, node)


## The dimension among the level's that is not `original`, or null.
func _copy_of(original: Node) -> Node:
	for found in HFDimensions.dimensions(root):
		if found != original:
			return found
	return null


func _end_ids(dimension: Node) -> Array:
	var data: Dictionary = dimension.entity_data
	return [str(data[HFDimensions.END_A]["brush_id"]), str(data[HFDimensions.END_B]["brush_id"])]


## Duplicate both walls of a doorway and its dimension, 5 along Z: the copy
## measures the copied doorway and follows it. It kept measuring the original, its
## ends still on the original walls (#2000).
func test_a_dimension_duplicated_with_its_walls_measures_the_copies():
	var dimension := _doorway(1.5)
	var nodes := [root.find_brush_by_id("left"), root.find_brush_by_id("right"), dimension]
	var infos: Array = HFPluginEditActions.duplicate_infos(
		_DuplicatingPlugin.new(), root, nodes, Vector3(0, 0, 5)
	)
	root.create_managed_duplicates(infos[0], infos[1], infos[2])
	var copy := _copy_of(dimension)
	assert_not_null(copy, "fixture: copied")
	if copy == null:
		return
	var copied_ids := [str(infos[0][0]["brush_id"]), str(infos[0][1]["brush_id"])]
	assert_eq(_end_ids(copy), copied_ids, "its ends on the copied walls")
	var measured := HFDimensions.measure(root, copy)
	assert_false(measured["detached"])
	assert_almost_eq(measured["a"], Vector3(-0.75, 0, 5.5), Vector3.ONE * 0.0001)
	assert_almost_eq(measured["b"], Vector3(0.75, 0, 5.5), Vector3.ONE * 0.0001)
	root.nudge_brushes_by_id([copied_ids[1]], Vector3(0.5, 0, 0))
	assert_almost_eq(HFDimensions.measure(root, copy)["length"], 2.0, 0.0001, "it follows")
	assert_almost_eq(
		HFDimensions.measure(root, dimension)["length"], 1.5, 0.0001, "the original does not"
	)
	assert_eq(_end_ids(dimension), ["left", "right"], "and keeps its own walls")


func test_a_dimension_duplicated_alone_still_measures_the_original_walls():
	var dimension := _doorway(1.5)
	var infos: Array = HFPluginEditActions.duplicate_infos(
		_DuplicatingPlugin.new(), root, [dimension], Vector3(0, 0, 5)
	)
	root.create_managed_duplicates(infos[0], infos[1], infos[2])
	var copy := _copy_of(dimension)
	assert_not_null(copy, "fixture: copied")
	if copy:
		assert_eq(_end_ids(copy), ["left", "right"])
		assert_almost_eq(
			HFDimensions.measure(root, copy)["a"], Vector3(-0.75, 0, 0.5), Vector3.ONE * 0.0001
		)


## Mirror Copy of the doorway and its dimension across z = 3: the copy measures
## the mirrored walls, on the mirror image of the corners the original is on, the
## face of each wall toward the plane (#2000).
func test_a_mirror_copy_of_a_doorway_measures_the_mirrored_walls():
	var dimension := _doorway(1.5)
	var made: Dictionary = root.mirror_copy_managed_nodes(
		["left", "right"], [root.get_path_to(dimension)], 4, Vector3(0, 0, 3)
	)
	var copy := _copy_of(dimension)
	assert_not_null(copy, "fixture: mirrored")
	if copy == null:
		return
	assert_eq(_end_ids(copy), made["brush_ids"], "its ends on the mirrored walls")
	var measured := HFDimensions.measure(root, copy)
	assert_false(measured["detached"])
	assert_almost_eq(measured["a"], Vector3(-0.75, 0, 5.5), Vector3.ONE * 0.0001)
	assert_almost_eq(measured["b"], Vector3(0.75, 0, 5.5), Vector3.ONE * 0.0001)
	root.nudge_brushes_by_id([made["brush_ids"][1]], Vector3(0.5, 0, 0))
	assert_almost_eq(HFDimensions.measure(root, copy)["length"], 2.0, 0.0001, "it follows")
	assert_almost_eq(HFDimensions.measure(root, dimension)["length"], 1.5, 0.0001)


## A free end is mirrored with the dimension it belongs to.
func test_a_flipped_dimension_mirrors_its_free_end():
	var dimension := HFPluginDimensions.keep(root, Vector3(1, 5, 0), Vector3(4, 5, 0), undo)
	root.flip_managed_nodes([], [root.get_path_to(dimension)], 0, Vector3.ZERO)
	var measured := HFDimensions.measure(root, dimension)
	assert_almost_eq(measured["a"], Vector3(-1, 5, 0), Vector3.ONE * 0.0001)
	assert_almost_eq(measured["b"], Vector3(-4, 5, 0), Vector3.ONE * 0.0001)


## Copy and Paste of the doorway and its dimension: the pasted dimension measures
## the pasted walls (#2000).
func test_a_pasted_dimension_measures_the_pasted_walls():
	var dimension := _doorway(1.5)
	assert_true(
		root.prefab_system.copy_to_clipboard(
			[root.find_brush_by_id("left"), root.find_brush_by_id("right")], [dimension]
		),
		"fixture: copied"
	)
	var pasted: Dictionary = root.prefab_system.paste_from_clipboard(Vector3(0, 0, 10))
	var copy := _copy_of(dimension)
	assert_not_null(copy, "fixture: pasted")
	if copy == null:
		return
	assert_eq(_end_ids(copy), pasted["brush_ids"], "its ends on the pasted walls")
	var measured := HFDimensions.measure(root, copy)
	assert_false(measured["detached"])
	assert_almost_eq(measured["length"], 1.5, 0.0001)
	assert_almost_eq(measured["a"].z, 10.5, 0.0001, "across the pasted doorway")
	root.nudge_brushes_by_id([pasted["brush_ids"][1]], Vector3(0.5, 0, 0))
	assert_almost_eq(HFDimensions.measure(root, copy)["length"], 2.0, 0.0001, "it follows")


## A doorway held to the player's width whose wall is deleted: Validate says the
## dimension came loose, before a save and after a load, and claims no length. It
## said nothing in the session, reading the last length seen, and after a load
## failed it at 0.0 m, a length it made up (#2004).
func test_validate_says_a_held_dimension_came_loose_rather_than_judge_its_length():
	var dimension := _doorway(1.5)
	dimension.entity_data["title"] = "front door"
	dimension.entity_data["check"] = "At least player width"
	root.delete_brush_by_id("right")
	var measured := HFDimensions.measure(root, dimension)
	assert_true(measured["detached"], "fixture: detached")
	assert_true(measured["passes"], "not judged, so drawn amber, not red")
	assert_eq(_dimension_issues(root), [HFDimensions.detached_text(dimension)])
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	await _finish_saving(root)
	var other := _level()
	assert_true(other.load_hflevel(LEVEL))
	var found := HFDimensions.dimensions(other)
	assert_eq(found.size(), 1)
	if found.size() == 1:
		assert_eq(_dimension_issues(other), [HFDimensions.detached_text(found[0])])
		assert_true(
			_dimension_issues(other)[0].begins_with(
				"Dimension front door has an end that came loose"
			)
		)


## A detached dimension held to nothing is not a finding: there is no check to
## judge.
func test_validate_says_nothing_of_a_detached_dimension_with_no_check():
	_doorway(1.5)
	root.delete_brush_by_id("right")
	assert_eq(_dimension_issues(root), [])


func _dimension_issues(level: LevelRoot) -> Array:
	return (level.validate_level().get("issues", []) as Array).filter(
		func(issue): return str(issue).begins_with("Dimension")
	)


## The drift diff reads a copy's dimension end by the place of its brush's record
## in the file, found by piece. A copy still holding a piece a Push dropped has its
## later brushes one place past their records, and an end on one read as a change
## (#2000, #1976).
func test_the_diff_names_a_copys_end_by_its_records_place_in_the_file():
	var rec := HFPrefabSystem.PrefabInstanceRecord.new()
	rec.brush_ids = ["kept_0", "wall_1", "wall_2"]
	rec.brush_pieces = [0, 1, 2]
	var file_brushes := [{HFPrefabType.PIECE: 1}, {HFPrefabType.PIECE: 2}]
	var data := {
		HFDimensions.END_A: {"brush_id": "wall_1"},
		HFDimensions.END_B: {"brush_id": "wall_2"},
	}
	var named: Dictionary = HFPrefabSystem._ends_as_pieces(rec, file_brushes, data)
	assert_eq(named[HFDimensions.END_A]["brush_id"], "#0", "wall_1's record is first in the file")
	assert_eq(named[HFDimensions.END_B]["brush_id"], "#1", "and wall_2's second")


## A doorway and its dimension saved as a prefab and placed twice, linked: each
## copy's dimension measures its own walls, a fresh copy reads as unchanged, and a
## Pull that builds the copies again keeps each on its own walls (#2000).
func test_each_copy_of_a_doorway_prefab_measures_its_own_walls():
	var dimension := _doorway(1.5)
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system,
		root.entity_system,
		[root.find_brush_by_id("left"), root.find_brush_by_id("right")],
		[dimension]
	)
	assert_eq(prefab.save_to_file(PREFAB), OK, "fixture: saved")
	var iids: Array = []
	for z in [10.0, 20.0]:
		var placed: Dictionary = prefab.instantiate(
			root.brush_system, root.entity_system, root, Vector3(0, 1, z)
		)
		iids.append(
			root.prefab_system.register_instance(
				PREFAB, placed["brush_ids"], placed["entity_nodes"], true
			)
		)
	for when in ["as placed", "after a Pull"]:
		var seen: Array = []
		for iid in iids:
			var rec = root.prefab_system.get_instance(iid)
			var copies: Array = root.prefab_system.pieces_of(rec).filter(
				func(node): return HFDimensions.is_dimension(node)
			)
			assert_eq(copies.size(), 1, "%s: one dimension a copy" % when)
			if copies.size() != 1:
				continue
			assert_eq(_end_ids(copies[0]), Array(rec.brush_ids), "%s: on its own walls" % when)
			var measured := HFDimensions.measure(root, copies[0])
			assert_false(measured["detached"], when)
			assert_almost_eq(measured["length"], 1.5, 0.0001, when)
			seen.append(snappedf((measured["a"] as Vector3).z, 0.001))
			assert_eq(root.prefab_system.compute_instance_diff(iid), [], "%s: unchanged" % when)
		assert_eq(seen.size(), 2)
		if seen.size() == 2:
			assert_almost_eq(float(seen[1]) - float(seen[0]), 10.0, 0.001, "each its own doorway")
		assert_eq(root.prefab_system.propagate_from_source(PREFAB), 2, "fixture: pulled")
