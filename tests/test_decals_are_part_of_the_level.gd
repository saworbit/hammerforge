extends GutTest
## Decals placed with the decal tool belong to the level.
##
## They used to be scene decoration: nothing in `capture_state()` knew about
## them, so a `.hflevel` save dropped them, and placing one registered no undo
## action, so Ctrl+Z undid whatever the user did before the decal and left the
## decal where it was.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFDecalTool = preload("res://addons/hammerforge/hf_decal_tool.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

var root: LevelRoot
var tool


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	tool = HFDecalTool.new()
	tool.root = root


func after_each() -> void:
	tool = null
	root = null


func test_a_placed_decal_is_in_the_level_state() -> void:
	tool._place_decal(Vector3(16, 0, 32), Vector3.UP)
	var state: Dictionary = root.capture_state(true)
	assert_true(state.has("decals"), "The level state has a decals key")
	assert_eq(state["decals"].size(), 1, "and the decal is in it")
	var entry: Dictionary = state["decals"][0]
	assert_almost_eq(entry["transform"].origin.x, 16.0, 0.01, "with where it was put")
	assert_almost_eq(entry["transform"].origin.z, 32.0, 0.01)


func test_a_decal_survives_a_capture_and_restore() -> void:
	tool._place_decal(Vector3(64, 8, -12), Vector3.UP)
	var state: Dictionary = root.capture_state(true)
	root.state_system.restore_decals([])
	assert_eq(root.decals_node.get_child_count(), 0, "Cleared")
	root.state_system.restore_state(state)
	assert_eq(root.decals_node.get_child_count(), 1, "The decal comes back")
	var decal: Decal = root.decals_node.get_child(0) as Decal
	assert_not_null(decal)
	assert_almost_eq(decal.global_position.x, 64.0, 0.01, "in the same place")
	assert_almost_eq(decal.global_position.z, -12.0, 0.01)


func test_a_decal_survives_the_hflevel_encoding() -> void:
	# A `.hflevel` is `capture_full_state()` put through `HFLevelIO`, so this is
	# the round trip the file makes. The decal used to be absent from the capture
	# and so was simply not in the file.
	tool._place_decal(Vector3(24, 0, 0), Vector3.UP)
	var bundle: Dictionary = root.capture_full_state()
	var written = HFLevelIO.decode_variant(
		JSON.parse_string(JSON.stringify(HFLevelIO.encode_variant(bundle)))
	)
	assert_true(written is Dictionary, "The bundle survives the file encoding")
	root.state_system.restore_decals([])
	assert_eq(root.decals_node.get_child_count(), 0, "Cleared before the load")
	root.state_system.restore_full_state(written)
	assert_eq(root.decals_node.get_child_count(), 1, "The decal came back with the level")
	var decal: Decal = root.decals_node.get_child(0) as Decal
	assert_almost_eq(decal.global_position.x, 24.0, 0.01, "in the same place")


func test_restoring_the_state_from_before_the_decal_removes_it() -> void:
	# This is what Ctrl+Z does. Without the decal in the state there was nothing
	# for undo to go back to, so it undid the action before instead.
	var before: Dictionary = root.capture_state(true)
	tool._place_decal(Vector3.ZERO, Vector3.UP)
	var after: Dictionary = root.capture_state(true)
	assert_eq(root.decals_node.get_child_count(), 1, "The decal is placed")
	root.state_system.restore_state(before)
	assert_eq(root.decals_node.get_child_count(), 0, "Undo takes it away")
	root.state_system.restore_state(after)
	assert_eq(root.decals_node.get_child_count(), 1, "and redo puts it back")


func test_a_second_decal_gets_a_name_of_its_own() -> void:
	tool._place_decal(Vector3.ZERO, Vector3.UP)
	tool._place_decal(Vector3(32, 0, 0), Vector3.UP)
	var names: Array = []
	for child in root.decals_node.get_children():
		names.append(str(child.name))
	assert_eq(names.size(), 2, "Two decals")
	assert_false(
		names.any(func(n: String) -> bool: return n.begins_with("@")),
		"Neither is a name Godot had to invent: %s" % str(names)
	)
	assert_ne(names[0], names[1], "and they are not the same name")


func test_the_ghost_under_the_cursor_is_not_one_of_them() -> void:
	tool._update_preview(Vector3(8, 0, 8), Vector3.UP)
	assert_not_null(tool._preview_decal, "There is a preview")
	assert_eq(root.capture_state(true)["decals"].size(), 0, "and it is not part of the level")
	tool._remove_preview()
