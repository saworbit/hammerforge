extends GutTest

## Every level a release saved loads with this build as that build counted it
## (#1640).
##
## The round trip and persistence checks save a level and load it straight back,
## so they read a file the same build just wrote, and nothing saw a change that
## stopped last release's file loading. `tests/levels/<version>/` holds a level
## each release saved, with what that build counted in it in `expected.json`
## (see the folder's README). This loads each one, counts it with the same
## census, and compares. It also saves each one again and checks that copy loads
## at this build's format number with the same counts.
##
## A folder needs no code here: a new release's level is a new folder.

const Census = preload("res://tests/levels/level_census.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const LEVELS := "res://tests/levels"
const RESAVED := "user://hf_release_level_resaved.hflevel"
## Counts a build changes on purpose, as "folder|key": "reason, #issue".
const KNOWN := {}


func after_all() -> void:
	for suffix in ["", ".previous", ".writing"]:
		if FileAccess.file_exists(RESAVED + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESAVED + suffix))


## Each folder under tests/levels that holds an expected.json.
static func _folders() -> Array:
	var out: Array = []
	for name in DirAccess.get_directories_at(LEVELS):
		if FileAccess.file_exists(LEVELS.path_join(name).path_join("expected.json")):
			out.append(name)
	out.sort()
	return out


static func _expected(folder: String) -> Dictionary:
	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(LEVELS.path_join(folder).path_join("expected.json"))
	)
	return parsed if parsed is Dictionary else {}


## The level file a folder's census is of: its own `level.hflevel`, or the one
## its expected.json names, as the reference map's does.
static func _level_file(folder: String) -> String:
	return str(_expected(folder).get("level", LEVELS.path_join(folder).path_join("level.hflevel")))


func _new_level() -> LevelRoot:
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autofree(level)
	return level


func test_the_releases_and_the_reference_map_are_all_here():
	var folders := _folders()
	for wanted in ["0.3.2", "0.4.0", "reference_map"]:
		assert_has(folders, wanted, "tests/levels/%s" % wanted)


func test_each_release_level_loads_as_its_build_counted_it(folder = use_parameters(_folders())):
	var expected: Dictionary = _expected(folder).get("census", {})
	assert_false(expected.is_empty(), "%s: expected.json holds a census" % folder)
	var level := _new_level()
	var path := _level_file(folder)
	assert_true(level.load_hflevel(path), "%s: %s loads" % [folder, path])
	await get_tree().process_frame
	_compare_census(folder, Census.of(level), expected, "as that build counted it")


func test_each_release_level_saved_again_loads_at_this_format(folder = use_parameters(_folders())):
	var first := _new_level()
	assert_true(first.load_hflevel(_level_file(folder)), "%s loads" % folder)
	await get_tree().process_frame
	var counted := Census.of(first)
	assert_eq(HFLevelIO.save_to_path(RESAVED, first.state_system.capture_hflevel_state()), OK)
	var written := HFLevelIO.load_from_path(RESAVED)
	assert_eq(
		int(written.get("version", -1)), HFLevelIO.FORMAT_VERSION, "%s: at this format" % folder
	)
	var second := _new_level()
	assert_true(second.load_hflevel(RESAVED), "%s: the copy loads" % folder)
	await get_tree().process_frame
	_compare_census(folder, Census.of(second), counted, "saved again")


func test_each_release_scene_opens(folder = use_parameters(_folders())):
	var path := LEVELS.path_join(folder).path_join("level.tscn")
	if not FileAccess.file_exists(path):
		pass_test("%s keeps no scene" % folder)
		return
	var errors_before := get_errors().size()
	var packed := load(path) as PackedScene
	assert_not_null(packed, "%s: the scene loads" % folder)
	if packed == null:
		return
	var scene := packed.instantiate()
	assert_true(scene is LevelRoot, "%s: its root is a LevelRoot" % folder)
	scene.set("auto_spawn_player", false)
	scene.set("hflevel_autosave_enabled", false)
	add_child_autofree(scene)
	await get_tree().process_frame
	var raised: Array = []
	for e in get_errors().slice(errors_before):
		if not e.is_push_warning():
			raised.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	assert_eq(raised, [], "%s: the scene opens with no error" % folder)


## Each key the census took, the same now. A number may drift by a millimetre.
func _compare_census(folder: String, got: Dictionary, want: Dictionary, how: String) -> void:
	for key in want:
		var label := "%s|%s" % [folder, key]
		if KNOWN.has(label):
			pending("%s: %s" % [label, KNOWN[label]])
			continue
		assert_true(got.has(key), "%s: the census still takes %s" % [folder, key])
		if not got.has(key):
			continue
		var a: Variant = got[key]
		var b: Variant = want[key]
		if (a is float or a is int) and (b is float or b is int):
			assert_almost_eq(float(a), float(b), 0.001, "%s: %s %s" % [folder, key, how])
		else:
			assert_eq(JSON.stringify(a), JSON.stringify(b), "%s: %s %s" % [folder, key, how])
