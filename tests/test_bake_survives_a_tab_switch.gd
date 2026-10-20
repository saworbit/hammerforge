extends GutTest
## A bake whose level leaves the tree part way through (#1290).
##
## Switching scene tabs takes the edited scene out of the tree (#928). A bake runs
## over frames, and its next wait used to ask the level for a tree it no longer
## had and stop on a script error. It now stops with a plain message instead, and
## leaves nothing behind that would refuse the next bake: the level is not still
## baking, the brushes it had to bake are still dirty, and a bake once the level
## is back works. A closed tab frees the level, and the bake stops with nothing to
## say, and whoever awaited the level's bake gets false (#1294).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const PATHS := ["faces", "csg", "chunked", "selection"]
## Every way a caller asks the level for a bake.
const ENTRIES := ["bake", "bake_dirty", "bake_selected", "bake_whole_level", "cordoned"]
## The two halves of Commit Cuts, which bake inside the level as the bake
## wrappers did (#1357).
const COMMIT_ENTRIES := ["prepare_commit_cuts", "commit_cuts"]

var root: LevelRoot
var messages: Array = []
## What a caller got back from the level's bake, or null while it still waits.
var _answer: Variant = null


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


## A caller awaiting the level's bake, from a coroutine that is not the level's:
## the dock's bake actions, Quick Play, the exports and the bridge all await it
## this way. Not awaited by the test, so the test can free the level meanwhile.
func _ask(entry: String) -> void:
	match entry:
		"bake":
			_answer = await root.bake()
		"bake_dirty":
			_answer = await root.bake_dirty()
		"bake_selected":
			_answer = await root.bake_selected(root.draft_brushes_node.get_children())
		"bake_whole_level":
			_answer = await root.bake_whole_level()
		"cordoned":
			root.cordon_enabled = true
			_answer = await root.bake_whole_level()


## A closed tab frees the level with its bake part way through. Whoever awaited
## the level's bake never resumed, since a coroutine suspended inside a node is
## dropped with it, and a later reload of the level's script cancelled it with a
## warning (#1294). The caller now gets false a frame later, from the answer the
## level gives as it goes. The run leaves no coroutine behind for that reload to
## cancel, which is what the next test that reloads a script would see.
func test_a_caller_gets_false_when_the_level_is_freed_mid_bake(entry = use_parameters(ENTRIES)):
	var errors_before := get_errors().size()
	_answer = null
	_ask(entry)
	assert_true(root.is_bake_in_flight(), "the %s bake is waiting on a frame" % entry)
	remove_child(root)
	root.free()
	await _wait(6)
	assert_eq(_answer, false, "the caller of %s got false" % entry)
	assert_eq(_errors_since(errors_before), [], "and nothing raised an error")


## The same callers, with the level kept: what the bake answers is what they get,
## and a whole-level bake has the cordons back before its caller carries on.
func test_a_caller_gets_the_bake_answer_when_the_level_stays(entry = use_parameters(ENTRIES)):
	_answer = null
	var cordons: Dictionary = root.capture_cordons()
	if entry == "cordoned":
		cordons["enabled"] = true
	_ask(entry)
	assert_true(root.is_bake_in_flight(), "the %s bake is waiting on a frame" % entry)
	for _i in 120:
		if _answer != null:
			break
		await get_tree().process_frame
	assert_eq(_answer, true, "the caller of %s got the bake's answer" % entry)
	assert_eq(root.capture_cordons(), cordons, "with the cordons as they were")


## A cut through the first box, waiting in PendingCuts.
func _pending_cut() -> void:
	var cut := {
		"size": Vector3(2, 2, 2),
		"center": Vector3(0, 2, 0),
		"brush_id": "cut",
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
		"pending": true,
	}
	root.create_brush_from_info(cut)


func _ask_commit(entry: String) -> void:
	match entry:
		"prepare_commit_cuts":
			_answer = await root.prepare_commit_cuts()
		"commit_cuts":
			_answer = await root.commit_cuts()


## The dock's Commit Cuts awaits the level's `prepare_commit_cuts()`, and a test
## its `commit_cuts()`: coroutines that awaited the commit's bake inside the
## level, so a closed tab left the caller suspended for good, as the bake
## wrappers did before #1294 (#1357). They answer as the wrappers do now: false
## a frame after the level is freed, and no error from the commit's own clean-up
## on a level that is gone.
func test_a_caller_gets_false_when_the_level_is_freed_mid_commit(
	entry = use_parameters(COMMIT_ENTRIES)
):
	_pending_cut()
	var errors_before := get_errors().size()
	_answer = null
	_ask_commit(entry)
	assert_true(root.is_bake_in_flight(), "the commit's bake is waiting on a frame")
	remove_child(root)
	root.free()
	await _wait(6)
	assert_eq(_answer, false, "the caller of %s got false" % entry)
	assert_eq(_errors_since(errors_before), [], "and nothing raised an error")


func test_a_caller_gets_the_commit_answer_when_the_level_stays(
	entry = use_parameters(COMMIT_ENTRIES)
):
	_pending_cut()
	_answer = null
	_ask_commit(entry)
	assert_true(root.is_bake_in_flight(), "the commit's bake is waiting on a frame")
	for _i in 120:
		if _answer != null:
			break
		await get_tree().process_frame
	assert_eq(_answer, true, "the caller of %s got the commit's answer" % entry)
	if entry == "prepare_commit_cuts":
		root.finalize_commit_cuts()
	assert_eq(root.pending_node.get_child_count(), 0, "the cut is no longer pending")
	assert_eq(root.committed_node.get_child_count(), 1, "it is committed")


## The dock turns its bake buttons off when a bake starts and on when it
## finishes. A bake whose tab was closed never finished, so they stayed off for
## every level after it.
##
## The bake is started on the level, which the dock hears start as it does any
## bake, rather than from the dock's button: what the button's own await gets
## back once the level is freed is the caller tests' concern (#1294).
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
