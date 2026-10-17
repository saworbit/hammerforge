extends GutTest
## A bake whose level leaves the tree part way through (#1290).
##
## Switching scene tabs takes the edited scene out of the tree (#928). A bake runs
## over frames, and its next wait used to ask the level for a tree it no longer
## had and stop on a script error. It now stops with a plain message instead, and
## leaves nothing behind that would refuse the next bake: the level is not still
## baking, the brushes it had to bake are still dirty, and a bake once the level
## is back works. A closed tab frees the level, and the bake stops with nothing to
## say.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const PATHS := ["faces", "csg", "chunked", "selection"]

var root: LevelRoot
var messages: Array = []


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	messages = []
	root.user_message.connect(func(text, _level): messages.append(str(text)))
	for i in 3:
		root.create_brush_from_info(
			{"size": Vector3(4, 4, 4), "center": Vector3(i * 8, 2, 0), "brush_id": "b%d" % i}
		)


func after_each():
	if is_instance_valid(root) and not root.is_inside_tree():
		add_child(root)
	root = null


func _start(path: String) -> void:
	match path:
		"faces":
			root.bake_use_face_materials = true
			root.bake()
		"csg":
			root.bake_use_face_materials = false
			root.bake()
		"chunked":
			root.bake_use_face_materials = false
			root.bake_chunk_size = 64.0
			root.bake()
		"selection":
			root.bake_selected(root.draft_brushes_node.get_children())


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _errors_since(before: int) -> Array:
	var out: Array = []
	for e in get_errors().slice(before):
		out.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	return out


func test_a_bake_stops_plainly_when_its_level_leaves_the_tree(path = use_parameters(PATHS)):
	var errors_before := get_errors().size()
	_start(path)
	assert_true(root.is_bake_in_flight(), "the %s bake is waiting on a frame" % path)
	remove_child(root)
	await _wait(6)
	assert_eq(_errors_since(errors_before), [], "it raised no error")
	assert_false(root.is_bake_in_flight(), "and is not still baking")
	assert_eq(root.get_last_bake_status(), LevelRoot.BakeStatus.FAILED, "it did not finish")
	assert_true(messages.any(func(text): return text.contains("switched away")), "and said why")
	add_child(root)
	await _wait(1)
	if path != "selection":
		assert_false(root._dirty_brush_ids.is_empty(), "what it had to bake is still dirty")
	assert_true(await root.bake(), "a bake with the level back works")


func test_a_bake_whose_level_is_freed_stops_without_a_word():
	var errors_before := get_errors().size()
	root.bake()
	assert_true(root.is_bake_in_flight(), "the bake is waiting on a frame")
	remove_child(root)
	root.free()
	await _wait(6)
	assert_eq(_errors_since(errors_before), [], "a closed tab raised nothing")


## The dock turns its bake buttons off when a bake starts and on when it
## finishes. A bake whose tab was closed never finished, so they stayed off for
## every level after it.
##
## The bake is started on the level, which the dock hears start as it does any
## bake, rather than from the dock's button. Whatever awaits the level's own bake
## method never resumes once the level is freed, as a coroutine whose object is
## gone is dropped, and a later reload of the level's script would cancel it with
## a warning in the next test that loads a scene.
func test_the_dock_bakes_again_after_a_level_closed_mid_bake():
	var rig = PluginRig.new()
	await rig.bring_up(self, true)
	var level = await rig.make_level()
	rig.box(level, "a", Vector3(0, 2, 0))
	level.bake()
	await _wait(1)
	assert_true(rig.plugin.dock._bake_disabled, "the bake buttons are off while it bakes")
	rig.scene_root.remove_child(level)
	level.free()
	await _wait(6)
	var next = await rig.make_level()
	assert_false(rig.plugin.dock._bake_disabled, "and on again for the next level")
	await rig.leave_level(next)
	await rig.take_down()
