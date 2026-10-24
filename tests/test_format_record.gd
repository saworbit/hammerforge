extends GutTest

## Every change to what a level saves raises the format number (#1638). The
## number guarded only the safe direction: a build that does not know a key
## skips it on load and drops it on its next save, so a teammate on an older
## build saving a newer level threw away what the newer build added.

const HFFormatRecord = preload("res://addons/hammerforge/hf_format_record.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const FullLevel = preload("res://tests/support/full_feature_level.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")

const LEVEL := "user://hf_test_format_record.hflevel"


func after_each() -> void:
	for suffix in ["", ".previous", ".writing"]:
		if FileAccess.file_exists(LEVEL + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL + suffix))


func _level() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


## The key paths in `census` that neither the release nor a waiting fragment
## names.
static func _unknown(census: PackedStringArray) -> Array:
	var known := HFFormatRecord.known_keys()
	var out: Array = []
	for path in census:
		if not known.has(path):
			out.append(path)
	return out


func test_every_key_a_level_saves_is_released_or_in_a_fragment():
	var level := _level()
	await FullLevel.fill(level, get_tree())
	var census := HFFormatRecord.census(level.state_system.capture_hflevel_payload())
	assert_gt(census.size(), 200, "fixture: the level saves a lot")
	var unknown := _unknown(census)
	assert_eq(
		unknown,
		[],
		(
			(
				"Each of these is saved by this build and named nowhere: %s. Add a fragment to "
				+ "addons/hammerforge/data/format.d/ naming them, with what they hold and what an "
				+ "older build does without them, and raise HFLevelIO.FORMAT_VERSION to one past "
				+ "the released number if no fragment waits yet."
			)
			% str(unknown)
		)
	)


func test_a_new_key_would_be_named():
	var level := _level()
	var bundle: Dictionary = level.state_system.capture_hflevel_payload()
	bundle["settings"]["brand_new_setting"] = true
	assert_eq(_unknown(HFFormatRecord.census(bundle)), ["settings.brand_new_setting"])


func test_the_build_s_number_is_the_release_s_plus_one_while_fragments_wait():
	assert_eq(
		HFLevelIO.FORMAT_VERSION,
		HFFormatRecord.version_wanted(),
		(
			"format.json says format %d was released and %d fragments wait"
			% [HFFormatRecord.released(), HFFormatRecord.pending().size()]
		)
	)


func test_each_fragment_says_what_it_saves_and_what_older_builds_get():
	var released := {}
	for key in (
		JSON.parse_string(FileAccess.get_file_as_string(HFFormatRecord.RECORD)) as Dictionary
	)["keys"]:
		released[key] = true
	for fragment in HFFormatRecord.pending():
		for field in ["what", "older_builds", "keys"]:
			assert_false(
				str(fragment.get(field, "")).is_empty(), "%s has %s" % [fragment["name"], field]
			)
		for key in fragment.get("keys", []):
			assert_false(released.has(key), "%s: %s is released already" % [fragment["name"], key])


func test_a_file_this_build_writes_names_its_fragments():
	var bundle: Dictionary = _level().state_system.capture_hflevel_payload()
	assert_eq(int(bundle["version"]), HFLevelIO.FORMAT_VERSION)
	assert_eq(PackedStringArray(bundle["format_pending"]), HFFormatRecord.pending_names())


func _write(version: int, names: Array) -> void:
	var bundle: Dictionary = _level().state_system.capture_hflevel_payload()
	bundle["version"] = version
	bundle["format_pending"] = names
	assert_eq(HFLevelIO.save_to_path(LEVEL, HFLevelIO.encode_variant(bundle)), OK)


func test_a_file_naming_a_fragment_this_build_lacks_is_refused_and_the_level_kept():
	_write(HFLevelIO.FORMAT_VERSION, ["9999-from-another-branch"])
	var level := _level()
	level.create_brush_from_info({"shape": 0, "size": Vector3.ONE, "center": Vector3.ZERO})
	var before := level.draft_brushes_node.get_child_count()
	assert_false(level.load_hflevel(LEVEL), "refused")
	assert_eq(level.draft_brushes_node.get_child_count(), before, "the open level is untouched")
	var read: Dictionary = level.file_system.read_hflevel(LEVEL)
	assert_string_contains(str(read.get("error", "")), "9999-from-another-branch")


func test_a_file_with_the_fragments_this_build_has_loads():
	_write(HFLevelIO.FORMAT_VERSION, Array(HFFormatRecord.pending_names()))
	assert_true(_level().load_hflevel(LEVEL))


func test_an_older_file_loads_whatever_it_names():
	_write(HFLevelIO.FORMAT_VERSION - 1, ["whatever"])
	assert_true(_level().load_hflevel(LEVEL))


func test_a_newer_number_is_refused():
	_write(HFLevelIO.FORMAT_VERSION + 1, [])
	var level := _level()
	assert_false(level.load_hflevel(LEVEL))
	assert_string_contains(
		str(level.file_system.read_hflevel(LEVEL).get("error", "")), "written by a newer build"
	)


func test_saving_the_scene_stamps_it_with_this_build_s_number():
	var level := _level()
	level.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	assert_eq(level.format_stamp, HFLevelIO.FORMAT_VERSION)
	assert_eq(level.format_stamp_pending, HFFormatRecord.pending_names())
	assert_eq(level.format_refusal(), "")


func test_a_scene_a_newer_build_saved_is_read_only():
	var level := _level()
	level.format_stamp = HFLevelIO.FORMAT_VERSION + 1
	assert_string_contains(level.format_refusal(), "newer build")
	assert_eq(level.save_hflevel(LEVEL, true), ERR_UNAVAILABLE, "Save Level refuses")
	assert_eq(level.save_hflevel(LEVEL, true, true), ERR_UNAVAILABLE, "and so does autosave")
	assert_false(FileAccess.file_exists(LEVEL), "nothing is written")
	level.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	assert_eq(level.format_stamp, HFLevelIO.FORMAT_VERSION + 1, "a scene save keeps the stamp")
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = level
	dock._refresh_format_banner()
	assert_not_null(dock.format_banner, "the dock has the banner")
	if dock.format_banner:
		assert_true(dock.format_banner.visible, "and shows it")
		assert_string_contains(dock.format_banner.text, "Read only")
		assert_string_contains(
			dock.format_banner.text, "format %d" % (HFLevelIO.FORMAT_VERSION + 1)
		)
