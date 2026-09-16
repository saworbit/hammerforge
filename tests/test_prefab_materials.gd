extends GutTest

## A prefab is the one path that carries geometry *between* levels, and a face's
## material is a slot number into the level's palette. Carrying the numbers
## without the materials meant every reuse silently re-textured (#621).

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")

const RED := "res://addons/hammerforge/textures/prototypes/brick_red.tres"


func before_each():
	HFLog.end_test_capture()


func after_each():
	HFLog.end_test_capture()


func _a_level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## A material that lives on disk, so it has a `resource_path` to record.
func _saved_material(name_part: String) -> StandardMaterial3D:
	var path := "user://hf_prefab_mat_%s.tres" % name_part
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(randf(), randf(), randf())
	mat.resource_name = name_part
	ResourceSaver.save(mat, path)
	return ResourceLoader.load(path) as StandardMaterial3D


func _box_in(level: LevelRoot, brush_id: String, slot: int) -> DraftBrush:
	var brush: DraftBrush = level.create_brush_from_info(
		{"size": Vector3(64, 64, 64), "center": Vector3.ZERO, "brush_id": brush_id}
	)
	for face in brush.faces:
		face.material_idx = slot
	return brush


func _face_slots(brush: Node) -> Array:
	var out: Array = []
	for face in (brush as DraftBrush).faces:
		out.append(face.material_idx)
	return out


func _placed_brushes(level: LevelRoot, ids: Array) -> Array:
	var out: Array = []
	for brush_id in ids:
		var node = level.brush_system._brush_cache.get(str(brush_id))
		if node:
			out.append(node)
	return out


# ===========================================================================
# What the capture records
# ===========================================================================


func test_capture_records_what_each_referenced_slot_meant():
	var level := _a_level()
	level.material_manager.add_material(_saved_material("a"))
	level.material_manager.add_material(_saved_material("b"))
	var brush := _box_in(level, "b1", 1)
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [brush], []
	)
	assert_true(prefab.material_slots.has(1), "slot 1 is the one the faces reference")
	assert_string_contains(str(prefab.material_slots[1]), "hf_prefab_mat_b")
	assert_false(prefab.material_slots.has(0), "slot 0 is not referenced, so it is not recorded")


func test_a_material_with_no_resource_path_cannot_be_recorded():
	# That is #617 from the other side. The slot is left out rather than recorded
	# as something the load cannot resolve.
	var level := _a_level()
	var runtime := StandardMaterial3D.new()
	runtime.resource_name = "made_in_session"
	level.material_manager.add_material(runtime)
	var brush := _box_in(level, "b1", 0)
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [brush], []
	)
	assert_true(prefab.material_slots.is_empty(), "nothing to point at, so nothing recorded")


func test_capture_without_a_palette_records_nothing_and_does_not_fail():
	var prefab = HFPrefabType.capture_from_selection(null, null, [], [])
	assert_true(prefab.material_slots.is_empty())


# ===========================================================================
# What the placement does with it
# ===========================================================================


func test_a_prefab_keeps_its_materials_in_another_level():
	var source := _a_level()
	source.material_manager.add_material(_saved_material("p"))
	source.material_manager.add_material(_saved_material("q"))
	var doorframe := _box_in(source, "d1", 1)
	var wanted: String = source.material_manager.get_material(1).resource_path
	var prefab = HFPrefabType.capture_from_selection(
		source.brush_system, source.entity_system, [doorframe], []
	)

	# A different level, with a different palette, where slot 1 means something else.
	var other := _a_level()
	other.material_manager.add_material(_saved_material("x"))
	other.material_manager.add_material(_saved_material("y"))
	var result: Dictionary = prefab.instantiate(
		other.brush_system, other.entity_system, other, Vector3.ZERO
	)
	var placed := _placed_brushes(other, result.get("brush_ids", []))
	assert_eq(placed.size(), 1, "the doorframe was placed")
	if placed.size() == 1:
		var slots := _face_slots(placed[0])
		var landed: int = int(slots[0])
		assert_eq(
			other.material_manager.get_material(landed).resource_path,
			wanted,
			"every face of the doorframe was 'p'; it must still be 'p' here"
		)
		assert_ne(landed, 1, "slot 1 already meant something else in this level")


func test_a_material_the_destination_already_holds_is_not_added_twice():
	var shared := _saved_material("shared")
	var source := _a_level()
	source.material_manager.add_material(_saved_material("filler"))
	source.material_manager.add_material(shared)
	var brush := _box_in(source, "b1", 1)
	var prefab = HFPrefabType.capture_from_selection(
		source.brush_system, source.entity_system, [brush], []
	)

	var other := _a_level()
	other.material_manager.add_material(shared)
	var before: int = other.material_manager.materials.size()
	var result: Dictionary = prefab.instantiate(
		other.brush_system, other.entity_system, other, Vector3.ZERO
	)
	assert_eq(other.material_manager.materials.size(), before, "it is already in the palette")
	var placed := _placed_brushes(other, result.get("brush_ids", []))
	if placed.size() == 1:
		assert_eq(int(_face_slots(placed[0])[0]), 0, "and the faces point at where it sits")


func test_placing_the_same_prefab_twice_does_not_grow_the_palette_twice():
	var source := _a_level()
	source.material_manager.add_material(_saved_material("once"))
	var brush := _box_in(source, "b1", 0)
	var prefab = HFPrefabType.capture_from_selection(
		source.brush_system, source.entity_system, [brush], []
	)

	var other := _a_level()
	prefab.instantiate(other.brush_system, other.entity_system, other, Vector3.ZERO)
	var after_first: int = other.material_manager.materials.size()
	prefab.instantiate(other.brush_system, other.entity_system, other, Vector3(128, 0, 0))
	assert_eq(other.material_manager.materials.size(), after_first, "the second finds it by path")


func test_a_slot_above_the_destination_palette_no_longer_points_out_of_range():
	# A prefab built against an eight-slot palette, placed in a level with one.
	var source := _a_level()
	for i in 8:
		source.material_manager.add_material(_saved_material("s%d" % i))
	var brush := _box_in(source, "b1", 7)
	var prefab = HFPrefabType.capture_from_selection(
		source.brush_system, source.entity_system, [brush], []
	)

	var other := _a_level()
	other.material_manager.add_material(_saved_material("only"))
	var result: Dictionary = prefab.instantiate(
		other.brush_system, other.entity_system, other, Vector3.ZERO
	)
	var placed := _placed_brushes(other, result.get("brush_ids", []))
	if placed.size() == 1:
		var landed: int = int(_face_slots(placed[0])[0])
		assert_lt(landed, other.material_manager.materials.size(), "in range now")
		assert_not_null(other.material_manager.get_material(landed))


func test_a_recorded_material_the_project_cannot_load_warns_and_leaves_the_face_alone():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "doorframe"
	prefab.material_slots = {1: "res://materials/gone.tres"}
	prefab.brush_infos = [
		{
			"shape": 0,
			"size": Vector3(64, 64, 64),
			"transform": Transform3D.IDENTITY,
			"faces": [{"material_idx": 1}],
		}
	]
	var other := _a_level()
	HFLog.begin_test_capture(["cannot load"])
	prefab.instantiate(other.brush_system, other.entity_system, other, Vector3.ZERO)
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1, "a silent re-texture is what this issue is about")
	if warnings.size() == 1:
		assert_string_contains(warnings[0], "doorframe")


func test_a_prefab_written_before_this_key_existed_is_placed_exactly_as_before():
	var prefab = HFPrefabType.new()
	prefab.brush_infos = [
		{
			"shape": 0,
			"size": Vector3(64, 64, 64),
			"transform": Transform3D.IDENTITY,
			"faces": [{"material_idx": 2}],
		}
	]
	assert_true(prefab.material_slots.is_empty(), "no record, so nothing to remap")
	var other := _a_level()
	for i in 4:
		other.material_manager.add_material(_saved_material("old%d" % i))
	var result: Dictionary = prefab.instantiate(
		other.brush_system, other.entity_system, other, Vector3.ZERO
	)
	var placed := _placed_brushes(other, result.get("brush_ids", []))
	if placed.size() == 1:
		assert_eq(int(_face_slots(placed[0])[0]), 2, "the number it had is the number it keeps")


# ===========================================================================
# The file
# ===========================================================================


func test_the_record_round_trips_through_the_file_format():
	var prefab = HFPrefabType.new()
	prefab.prefab_name = "pillar"
	prefab.material_slots = {0: "res://a.tres", 3: "res://b.tres"}
	var data: Dictionary = prefab.to_dict()
	assert_true(data.has("materials"), "the file has to carry what the slots meant")
	var back = HFPrefabType.from_dict(data)
	assert_eq(back.material_slots.size(), 2)
	assert_eq(str(back.material_slots[0]), "res://a.tres")
	assert_eq(str(back.material_slots[3]), "res://b.tres")


func test_a_prefab_with_no_recorded_materials_writes_no_key():
	var prefab = HFPrefabType.new()
	assert_false(prefab.to_dict().has("materials"), "nothing to say, nothing written")


func test_a_malformed_materials_block_is_ignored_rather_than_fatal():
	var back = HFPrefabType.from_dict({"prefab_name": "x", "materials": "not a list"})
	assert_true(back.material_slots.is_empty())
	var partial = HFPrefabType.from_dict(
		{"prefab_name": "x", "materials": [{"slot": 1}, {"path": "res://a.tres"}, {"slot": -1}]}
	)
	assert_true(partial.material_slots.is_empty(), "a record needs both halves to mean anything")


func test_a_variant_adds_its_slots_to_the_same_record():
	var level := _a_level()
	level.material_manager.add_material(_saved_material("base_mat"))
	level.material_manager.add_material(_saved_material("variant_mat"))
	var base_brush := _box_in(level, "b1", 0)
	var prefab = HFPrefabType.capture_from_selection(
		level.brush_system, level.entity_system, [base_brush], []
	)
	var variant_brush := _box_in(level, "b2", 1)
	prefab.add_variant_from_selection(
		"tall", level.brush_system, level.entity_system, [variant_brush], []
	)
	assert_true(prefab.material_slots.has(0), "the base slot is still recorded")
	assert_true(prefab.material_slots.has(1), "and the variant indexes the same palette")
