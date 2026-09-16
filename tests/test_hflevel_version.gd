extends GutTest

## A `.hflevel` carries a format version and nothing read it.
##
## That protects new code reading old files, because every key defaults, and does
## nothing for old code reading new ones - which is the case a version number
## exists for. The first format change that is not purely additive is the one
## that finds out, and by then the load has already cleared the open level and
## restored what it could parse.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

var root: LevelRoot
var messages: Array = []


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	messages = []
	root.user_message.connect(func(text: String, level: int): messages.append([text, level]))


func _path() -> String:
	return "user://hf_version_test_%d.hflevel" % Time.get_ticks_usec()


# ===========================================================================
# What the write thread is handed (#601)
# ===========================================================================


func test_the_payload_handed_to_the_write_thread_holds_nothing_live():
	# The encode moved onto the write thread, which is only safe because the
	# Resources are resolved before the handoff. Everything left is a value, so
	# the worker never reads a property off an object the editor owns. This is
	# asserted rather than the list of places a Resource can appear being trusted,
	# because that list grows every time the format does.
	var mat := StandardMaterial3D.new()
	# A path of its own: two live Resources claiming one path is a cyclic
	# inclusion error, and both of these tests run in the same session.
	mat.resource_path = "res://hf_payload_test_%d.tres" % Time.get_ticks_usec()
	root.set_materials([mat])
	(
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D.IDENTITY,
				"operation": CSGShape3D.OPERATION_UNION,
				"material": mat,
			}
		)
	)
	var payload: Dictionary = root._capture_hflevel_payload()
	assert_false(payload.is_empty(), "there is a level to save")
	assert_false(HFLevelIO.holds_resource(payload), "no live Resource crosses to the write thread")


func test_the_payload_still_encodes_to_the_same_level():
	# Splitting capture from encode must not change the file. The one-call
	# version is the reference.
	var mat := StandardMaterial3D.new()
	# A path of its own: two live Resources claiming one path is a cyclic
	# inclusion error, and both of these tests run in the same session.
	mat.resource_path = "res://hf_payload_test_%d.tres" % Time.get_ticks_usec()
	root.set_materials([mat])
	(
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D.IDENTITY,
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)
	var in_one_go: Dictionary = root._capture_hflevel_state()
	var in_two_steps: Variant = HFLevelIO.encode_variant(root._capture_hflevel_payload())
	# `saved_at` is a clock reading and differs between the two calls.
	in_one_go.erase("saved_at")
	(in_two_steps as Dictionary).erase("saved_at")
	assert_eq(JSON.stringify(in_two_steps), JSON.stringify(in_one_go), "the same level either way")


## Write a bundle at a chosen version, the way capture_hflevel_state() writes one.
func _write_bundle(path: String, version: int) -> void:
	var bundle := {
		"version": version,
		"saved_at": "now",
		"settings": root._capture_hflevel_settings(),
		"state": root.capture_state(),
	}
	HFLevelIO.save_to_path(path, HFLevelIO.encode_variant(bundle), false)


func test_a_bundle_at_this_build_s_version_loads():
	var path := _path()
	root.create_brush_from_info({"size": Vector3(32, 32, 32), "brush_id": "b1"})
	_write_bundle(path, HFLevelIO.FORMAT_VERSION)
	root.clear_brushes()

	assert_true(root.file_system.load_hflevel(path))
	assert_eq(root.brush_system.get_live_brush_count(), 1)
	DirAccess.remove_absolute(path)


## Every reader already defaults a missing key, so an older file is the direction
## that has always been safe.
func test_a_bundle_with_no_version_still_loads():
	var path := _path()
	root.create_brush_from_info({"size": Vector3(32, 32, 32), "brush_id": "b1"})
	_write_bundle(path, 0)
	root.clear_brushes()

	assert_true(root.file_system.load_hflevel(path))
	assert_eq(root.brush_system.get_live_brush_count(), 1)
	DirAccess.remove_absolute(path)


func test_a_bundle_from_a_newer_build_is_refused():
	var path := _path()
	_write_bundle(path, HFLevelIO.FORMAT_VERSION + 1)

	assert_false(root.file_system.load_hflevel(path), "this build cannot read it correctly")
	DirAccess.remove_absolute(path)


## The point of refusing before anything is applied: `restore_state()` clears the
## brushes first, so a file this build cannot read must not cost the open level.
func test_a_refused_bundle_leaves_the_open_level_alone():
	var path := _path()
	# The bundle is captured from an empty level, so applying it would clear the
	# brush made afterwards. That is exactly what used to happen.
	_write_bundle(path, HFLevelIO.FORMAT_VERSION + 5)
	root.create_brush_from_info({"size": Vector3(64, 64, 64), "brush_id": "keep_me"})

	root.file_system.load_hflevel(path)

	assert_eq(root.brush_system.get_live_brush_count(), 1, "the level that was open is still open")
	DirAccess.remove_absolute(path)


func test_a_refused_bundle_says_so():
	var path := _path()
	_write_bundle(path, HFLevelIO.FORMAT_VERSION + 1)

	root.file_system.load_hflevel(path)

	assert_eq(messages.size(), 1, "a silent refusal is the thing being fixed")
	assert_string_contains(str(messages[0][0]), "newer build")
	assert_eq(messages[0][1], 2, "reported as an error, the way a bad state is")
	DirAccess.remove_absolute(path)


## One constant, so a format change has one place to bump.
func test_the_stamp_written_is_the_version_this_build_reads():
	var captured = HFLevelIO.decode_variant(root._capture_hflevel_state())
	assert_eq(int(captured.get("version", -1)), HFLevelIO.FORMAT_VERSION)
