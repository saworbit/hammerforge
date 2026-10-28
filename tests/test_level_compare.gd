extends GutTest

## What changed between two versions of a level (#1701).

const FullLevel = preload("res://tests/support/full_feature_level.gd")
const HFLevelCompare = preload("res://addons/hammerforge/hf_level_compare.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")

const PATH := "user://test_level_compare.hflevel"
const BRICK := "user://test_level_compare_brick.tres"


func after_each() -> void:
	for path in [PATH, BRICK]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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


## A brush's own Cast Shadows and Lightmap Scale and the material it wears whole
## each show as a line, on a brush counted as changed, against the saved file. A
## bake reads all three and Compare said "No changes" (#2023).
func test_cast_shadows_lightmap_scale_and_a_whole_material_each_show():
	var level := _level()
	_box(level, Vector3(0, 1, 0), "box")
	var saved := await _saved(level)
	level.set_brush_cast_shadow(["box"], GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	level.set_brush_lightmap_scale(["box"], 4.0)
	# A material with a file of its own, as a level's are: one with none is not
	# kept by the save, and Compare rightly reads it as gone.
	var made := StandardMaterial3D.new()
	made.resource_name = "brick"
	assert_eq(ResourceSaver.save(made, BRICK), OK, "fixture: the material is a file")
	level.find_brush_by_id("box").material_override = load(BRICK)
	var result := HFLevelCompare.compare(saved, _now(level))
	var told := "\n".join(result["lines"])
	assert_eq(result["brushes"]["changed"].size(), 1, told)
	var changes: PackedStringArray = result["brushes"]["changed"][0]["changes"]
	assert_has(changes, "cast shadows changed from level default to off", told)
	assert_has(changes, "lightmap scale changed from 1 to 4", told)
	assert_true(
		Array(changes).any(
			func(l): return l.begins_with("material changed from none to ") and l.contains("brick")
		),
		told
	)
	assert_eq(result["counts"]["brushes"], 1)
	var again := await _saved(level)
	var same := HFLevelCompare.compare(again, _now(level))
	assert_eq(same["lines"], PackedStringArray(["No changes"]), "\n".join(same["lines"]))


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


## A file an older build saved keeps a box's faces in another order, each begun
## at another corner. Loading it puts them in this build's order, each face's
## texture turned with its corners, so the file and the level hold the same box
## (#1870). Paired by index, every face read as changed.
func test_a_box_whose_faces_a_file_keeps_in_another_order_shows_no_change():
	var level := _level()
	var box := _box(level, Vector3(0, 1, 0), "box")
	var corners: int = box.faces[0].local_verts.size()
	var uvs := PackedVector2Array()
	for i in corners:
		uvs.append(Vector2(i, i * 2))
	box.faces[0].custom_uvs = uvs
	var saved := await _saved(level)
	var record: Dictionary = saved["state"]["brushes"][0]
	var faces: Array = record["faces"]
	for face in faces:
		for key in ["local_verts", "custom_uvs"]:
			var values: Array = Array(face.get(key, []))
			if values.size() == corners:
				values.push_front(values.pop_back())
				face[key] = values
	faces.push_front(faces.pop_back())
	var result := HFLevelCompare.compare(saved, _now(level))
	assert_eq(result["lines"], PackedStringArray(["No changes"]), "\n".join(result["lines"]))
	(faces[3] as Dictionary)["uv_rotation"] = 45.0
	result = HFLevelCompare.compare(saved, _now(level))
	assert_eq(result["counts"]["faces"], 1, "a face that did change still shows")


## A visgroup and the cordons as a file saved before the keys added to them
## since: a load reads each missing key at its default, so a compare does too.
## A brush the file has no name for is one a load names, which is not a rename
## (#1982).
func test_keys_a_file_is_older_than_show_no_change():
	var level := _level()
	_box(level, Vector3(0, 1, 0), "box")
	level.visgroup_system.create_visgroup("west")
	level.cordon_enabled = true
	var saved := await _saved(level)
	saved["state"]["visgroups"]["west"] = {"visible": true}
	saved["settings"].erase("cordon_aabb_active")
	saved["settings"].erase("cordon_extra_aabbs")
	saved["state"]["brushes"][0].erase("name")
	var result := HFLevelCompare.compare(saved, _now(level))
	assert_eq(result["lines"], PackedStringArray(["No changes"]), "\n".join(result["lines"]))


## A wire added to a point entity, and a brush entity's class, setting and wire,
## each show. Point entities keep their wires under `io_outputs`, which the
## compare never read, and a brush entity's class, settings and wires were not
## compared at all, so all of this read as no change (#1941).
func test_wires_and_settings_on_point_and_brush_entities_show():
	var level := _level()
	var button: Node3D = (
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "button",
				"entity_type": "func_button",
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 1, 4)),
			}
		)
	)
	var door := _box(level, Vector3(0, 1, 0), "door")
	HFBrushEntity.give(
		door, {"brush_entity_class": "func_door", "brush_entity_data": {"speed": 100}}
	)
	var plain := _box(level, Vector3(6, 1, 0), "plain")
	await get_tree().process_frame
	var saved := await _saved(level)

	level.add_entity_output(button, "OnPressed", "door", "Open")
	level.add_entity_output(door, "OnOpen", "button", "Lock")
	door.set_meta("brush_entity_data", {"speed": 200})
	HFBrushEntity.give(plain, {"brush_entity_class": "trigger_once"})
	var result := HFLevelCompare.compare(saved, _now(level))
	var told := "\n".join(result["lines"])
	assert_has(result["lines"], "entity 'button': wires: 1 added, 0 removed", told)
	var changed := {}
	for entry in result["brushes"]["changed"]:
		changed[entry["id"]] = Array(entry["changes"])
	assert_has(changed.get("door", []), "speed changed", told)
	assert_has(changed.get("door", []), "wires: 1 added, 0 removed", told)
	assert_has(changed.get("plain", []), "brush entity changed from none to trigger_once", told)
	assert_eq(result["counts"]["wires"], 2, "two wires")


## Compare `before` with the level as it is now, and the lines it gives. What the
## lines name is counted as well: `tools/compare_levels.gd` exits 1 on a count
## and 0 on none.
func _lines_since(level: LevelRoot, before: Dictionary) -> PackedStringArray:
	var result := HFLevelCompare.compare(before, _now(level))
	var lines: PackedStringArray = result["lines"]
	var counted: bool = (result["counts"] as Dictionary).values().any(func(n): return int(n) > 0)
	assert_eq(counted, lines.size() > 1, "counted as listed:\n%s" % "\n".join(lines))
	return lines


## A rename, a visgroup and a group each change what the level does: a wire is
## aimed by name, a visgroup can leave a brush out of every bake, and a group
## decides what a click selects. Each read as "No changes" (#1982).
func test_renames_visgroups_and_groups_each_show():
	var level := _level()
	var wall := _box(level, Vector3(0, 1, 0), "wall")
	var crate := _box(level, Vector3(4, 1, 2), "crate")
	var door := _box(level, Vector3(-4, 1, 0), "door")
	level.tie_brushes_to_entity(["door"], "func_door", "door_1")
	var lamp: Node3D = (
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "lamp",
				"entity_type": "light_point",
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 3, 3)),
			}
		)
	)
	var button: Node3D = (
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "button",
				"entity_type": "func_button",
				"properties": {},
				"transform": Transform3D(Basis.IDENTITY, Vector3(2, 1, 3)),
			}
		)
	)
	level.add_entity_output(button, "OnPressed", "door_1", "Open")
	level.create_visgroup("detail")
	level.set_visgroup_bakes("detail", false)
	await get_tree().process_frame
	var saved := await _saved(level)
	assert_eq(_lines_since(level, saved), PackedStringArray(["No changes"]), "as saved")

	var before := _now(level)
	level.tie_brushes_to_entity(["door"], "func_door", "vault_door")
	var lines := _lines_since(level, before)
	assert_has(lines, "brush '%s': brush entity renamed from door_1 to vault_door" % door.name)
	assert_has(lines, "entity 'button': wire OnPressed to door_1 reaches nothing now")

	before = _now(level)
	lamp.set_meta("entity_name", "hall_lamp")
	assert_has(
		_lines_since(level, before), "entity 'lamp': authored name changed from none to hall_lamp"
	)

	before = _now(level)
	lamp.name = "ceiling_lamp"
	assert_has(
		_lines_since(level, before), "entity 'ceiling_lamp': renamed from lamp to ceiling_lamp"
	)

	before = _now(level)
	var was_named := str(wall.name)
	wall.name = "north_wall"
	assert_has(
		_lines_since(level, before), "brush 'north_wall': renamed from %s to north_wall" % was_named
	)

	before = _now(level)
	level.add_selection_to_visgroup("detail", [wall])
	lines = _lines_since(level, before)
	assert_has(lines, "brush 'north_wall': visgroups changed from none to detail")
	assert_eq(lines[0], "1 brush changed")

	before = _now(level)
	level.group_selection("room", [wall, crate])
	lines = _lines_since(level, before)
	assert_has(lines, "brush 'north_wall': group changed from none to room")
	assert_has(lines, "group 'room': added")
	assert_eq(lines[0], "2 brushes, 1 group changed")

	assert_eq(
		HFLevelCompare.compare(_now(level), _now(level))["lines"],
		PackedStringArray(["No changes"]),
		"the level against itself"
	)


## Texture Lock, on by default, keeps a texture where it is on a brush through a
## move or a turn by rewriting each face's offset and rotation. Those rewrites
## read as "texture moved" on four faces (#1989). A texture slid by hand after the
## move still shows.
func test_a_move_and_a_turn_with_texture_lock_are_not_texture_edits():
	var level := _level()
	var crate := _box(level, Vector3(4, 1, 2), "crate")
	assert_true(level.texture_lock, "Texture Lock is on by default")
	var saved := await _saved(level)
	level.nudge_brushes_by_id(["crate"], Vector3(0, 0.5, 0))
	await get_tree().process_frame
	var result := HFLevelCompare.compare(saved, _now(level))
	assert_eq(
		result["lines"],
		PackedStringArray(["1 brush changed", "brush '%s': moved 0.5 m up" % crate.name]),
		"\n".join(result["lines"])
	)

	var before := _now(level)
	level.rotate_managed_nodes(["crate"], [], 1, 90.0, crate.global_position)
	await get_tree().process_frame
	result = HFLevelCompare.compare(before, _now(level))
	assert_eq(result["counts"]["faces"], 0, "\n".join(result["lines"]))
	assert_has(result["lines"], "brush '%s': turned" % crate.name)

	before = _now(level)
	crate.faces[1].uv_offset += Vector2(0.25, 0)
	result = HFLevelCompare.compare(before, _now(level))
	assert_eq(result["counts"]["faces"], 1, "a texture slid by hand still shows")
	assert_true(
		Array(result["lines"]).any(func(l): return l.ends_with("texture moved")),
		"\n".join(result["lines"])
	)


## A removed paint layer is named as an added one is, by the name the mapper gave
## it and not its id (#1992).
func test_a_removed_paint_layer_is_named_by_its_name():
	var level := _level()
	level.add_paint_layer()
	var last := level.get_paint_layer_names().size() - 1
	assert_true(level.rename_paint_layer(last, "Upper Floor"), "renamed")
	var before := _now(level)
	level.set_active_paint_layer(last)
	level.remove_active_paint_layer()
	assert_has(_lines_since(level, before), "paint layer 'Upper Floor': removed")


## A point entity scaled, not turned, is not "turned". The compare held its whole
## basis to the old one, scale and all (#1941).
func test_a_scaled_point_entity_is_not_turned():
	var level := _level()
	var lamp: Node3D = (
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
	var saved := await _saved(level)
	lamp.scale = Vector3(2, 2, 2)
	var result := HFLevelCompare.compare(saved, _now(level))
	assert_false(
		Array(result["lines"]).any(func(l): return l.contains("turned")), "\n".join(result["lines"])
	)
