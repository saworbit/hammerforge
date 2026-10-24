extends GutTest

## A Color comes back from a level file as it went in, and an int entity
## property as an int (#1787).

const HFLevelIOType = preload("res://addons/hammerforge/hflevel_io.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")

const LEVEL := "user://hf_test_level_round_trip_types.hflevel"

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_all() -> void:
	if FileAccess.file_exists(LEVEL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL))


## Through the encoder and JSON and back, as a level file takes a value.
func _trip(value: Variant) -> Variant:
	var json := JSON.stringify(HFLevelIOType.encode_variant({"v": value}))
	return (HFLevelIOType.decode_variant(JSON.parse_string(json)) as Dictionary).get("v")


func test_a_colour_comes_back_exactly_even_above_one():
	for colour in [Color(0.25, 0.5, 0.75, 0.5), Color(2.0, 1.0, 0.5), Color(0.1, 0.2, 0.3)]:
		var back: Variant = _trip(colour)
		assert_true(back is Color, "%s is still a Color" % colour)
		if back is Color:
			assert_true((back as Color).is_equal_approx(colour), "%s came back %s" % [colour, back])


func test_a_file_written_before_still_reads_its_hex_colours():
	var old := {HFLevelIOType.TYPE_KEY: "Color", "value": "#ff8000"}
	var back: Variant = HFLevelIOType.decode_variant(old)
	assert_true(back is Color)
	if back is Color:
		assert_almost_eq((back as Color).r, 1.0, 0.01)
		assert_almost_eq((back as Color).g, 0.5, 0.01)


func test_a_clip_s_physics_layer_is_an_int_after_a_save_and_a_load():
	var clip = root.create_brush_from_info(
		{"brush_id": "c1", "size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)}
	)
	root.brush_system.tie_brushes_to_entity(["c1"], "func_clip")
	root.set_entity_property(clip, "layer", 3)
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	await _finish_saving(root)
	var again := LevelRoot.new()
	again.auto_spawn_player = false
	again.hflevel_autosave_enabled = false
	add_child_autoqfree(again)
	assert_true(again.load_hflevel(LEVEL), "fixture: the level loads")
	var loaded = again.find_brush_by_id("c1")
	assert_not_null(loaded)
	if loaded:
		var layer: Variant = HFEntityPropUtils.get_entity_data(loaded).get("layer")
		assert_eq(typeof(layer), TYPE_INT, "an int, not %s" % type_string(typeof(layer)))
		assert_eq(layer, 3)


## The write runs on a thread of its own, so wait for it as the file system's
## own test does.
func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return
