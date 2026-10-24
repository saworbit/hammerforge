extends GutTest

## What changed between two versions of a level (#1701).

const FullLevel = preload("res://tests/support/full_feature_level.gd")
const HFLevelCompare = preload("res://addons/hammerforge/hf_level_compare.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const PATH := "user://test_level_compare.hflevel"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _level() -> LevelRoot:
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return
		await get_tree().process_frame


## The level as it is now, and as the file `PATH` holds it once saved.
func _saved(level: LevelRoot) -> Dictionary:
	assert_eq(level.save_hflevel(PATH, true), OK, "the level saves")
	await _finish_saving(level)
	var read: Dictionary = level.file_system.read_hflevel(PATH)
	assert_true(read.get("ok", false), "the file reads: %s" % read.get("error", ""))
	return read.get("bundle", {})


func _now(level: LevelRoot) -> Dictionary:
	return level.state_system.capture_hflevel_payload()


func _box(level: LevelRoot, centre: Vector3, brush_id := "") -> Node:
	var info := {"shape": 0, "size": Vector3(2, 2, 2), "center": centre}
	if brush_id != "":
		info["brush_id"] = brush_id
	return level.create_brush_from_info(info)


func test_a_level_against_its_own_saved_copy_shows_no_change():
	var level := _level()
	await FullLevel.fill(level, get_tree())
	var saved := await _saved(level)
	var result := HFLevelCompare.compare(saved, _now(level))
	assert_eq(result["lines"], PackedStringArray(["No changes"]), "\n".join(result["lines"]))


func test_a_move_a_deletion_an_added_entity_and_a_material_each_show():
	var level := _level()
	var moved := _box(level, Vector3(0, 1, 0), "moved")
	var gone := _box(level, Vector3(5, 1, 0), "gone")
	var painted := _box(level, Vector3(10, 1, 0), "painted")
	level.material_manager.add_material(StandardMaterial3D.new())
	var brick := StandardMaterial3D.new()
	brick.resource_name = "brick"
	level.material_manager.add_material(brick)
	var saved := await _saved(level)

	moved.global_position += Vector3(0, 0.5, 0)
	level.delete_brush_by_id("gone")
	painted.faces[0].material_idx = 1
	(
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "lamp",
				"entity_type": "light_point",
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)),
			}
		)
	)
	await get_tree().process_frame
	var result := HFLevelCompare.compare(saved, _now(level))
	var lines: PackedStringArray = result["lines"]
	var told := "\n".join(lines)
	var changed := {}
	for entry in result["brushes"]["changed"]:
		changed[entry["id"]] = entry["changes"]
	assert_eq(changed.get("moved"), PackedStringArray(["moved 0.5 m up"]), told)
	assert_true(
		Array(changed.get("painted", [])).any(
			func(l): return l.ends_with("material changed from none to brick")
		),
		"the material change, face by face: %s" % told
	)
	assert_true(Array(lines).any(func(l): return l.ends_with(": removed")), told)
	assert_has(lines, "entity 'lamp' (light_point): added")
	assert_eq(result["brushes"]["removed"].size(), 1)
	assert_eq(
		result["brushes"]["removed"][0]["brush_id"], "gone", "the removed brush's record, to draw"
	)
	assert_eq(result["counts"]["brushes"], 3)
	assert_eq(result["counts"]["entities"], 1)
	assert_eq(lines[0], "3 brushes, 1 face, 1 entity changed")


func test_a_brush_whose_id_changed_in_the_same_place_is_the_same_brush():
	var level := _level()
	_box(level, Vector3(0, 1, 0), "first")
	var saved := await _saved(level)
	var state: Dictionary = saved["state"]
	state["brushes"][0]["brush_id"] = "renamed"
	var result := HFLevelCompare.compare(saved, _now(level))
	assert_eq(result["brushes"]["added"], [], "not added")
	assert_eq(result["brushes"]["removed"], [], "nor removed")
	assert_eq(result["lines"], PackedStringArray(["No changes"]))
