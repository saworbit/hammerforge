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
## at this build's format number with the same counts, and edits each one: a
## nudge undone and redone, a whole level step undone with every brush kept, and
## a compare with its own file that finds nothing (#1870).
##
## A folder needs no code here: a new release's level is a new folder.

const Census = preload("res://tests/levels/level_census.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const UndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const HFLevelCompare = preload("res://addons/hammerforge/hf_level_compare.gd")
const UndoStandIn = preload("res://tests/test_undo_collation.gd").FakeUndoRedo

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


## Nudge one brush of an old level, undo, and redo (#1870). Every test that edits
## starts from a level this build made, and an old file reaches this build
## through its loader: winding repaired, new keys filled in. The first undo step
## captures the level as this build sees it, so a brush that captures other than
## it loaded changes on the first Ctrl+Z.
func test_each_release_level_nudged_undoes_and_redoes(folder = use_parameters(_folders())):
	var level: LevelRoot = await _loaded(folder)
	var loaded := Census.of(level)
	var records := _records(level)
	var brush: Node3D = _first_draft_brush(level)
	assert_not_null(brush, "%s: a brush to nudge" % folder)
	if brush == null:
		return
	var brush_id := str(brush.brush_id)
	var home := brush.global_position
	var undo := UndoStandIn.new()
	UndoHelper.commit(
		undo,
		level,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[[brush_id], [], Vector3.RIGHT],
		false,
		Callable(),
		"",
		true,
		[brush_id],
		[]
	)
	await get_tree().process_frame
	var nudged := Census.of(level)
	var moved: Node3D = level.find_brush_by_id(brush_id)
	assert_almost_eq(moved.global_position, home + Vector3.RIGHT, Vector3.ONE * 0.001)
	undo.undo()
	await get_tree().process_frame
	_compare_census(folder, Census.of(level), loaded, "after a nudge and its undo")
	_compare_records(folder, _records(level), records, "after a nudge and its undo")
	undo.redo()
	await get_tree().process_frame
	_compare_census(folder, Census.of(level), nudged, "after the nudge's redo")


## Place a brush on an old level and undo it, a step that records the whole
## level. The census comes back, and every brush from the file is the node it
## was: the undo kept it rather than rebuilding it (#600). A brush that captures
## other than it loaded matches no record and is rebuilt on every undo.
## Saved after the undo, the level loads as it was loaded.
func test_each_release_level_keeps_its_brushes_through_a_whole_level_undo(
	folder = use_parameters(_folders())
):
	var level: LevelRoot = await _loaded(folder)
	var loaded := Census.of(level)
	var records := _records(level)
	var nodes := {}
	for brush_id in records:
		nodes[brush_id] = level.find_brush_by_id(brush_id).get_instance_id()
	var undo := UndoStandIn.new()
	var info := {
		"shape": LevelRootType.BrushShape.BOX,
		"size": Vector3.ONE,
		"center": Vector3(0.0, 500.0, 0.0),
	}
	UndoHelper.commit(undo, level, "Place Brush", "create_brush_from_info", [info])
	await get_tree().process_frame
	assert_eq(level.get_live_brush_count(), int(loaded["brushes"]) + 1, "%s: placed" % folder)
	undo.undo()
	await get_tree().process_frame
	_compare_census(folder, Census.of(level), loaded, "after a placement and its undo")
	_compare_records(folder, _records(level), records, "after a placement and its undo")
	var rebuilt: Array = []
	for brush_id in nodes:
		var now: Node = level.find_brush_by_id(brush_id)
		if now == null or now.get_instance_id() != nodes[brush_id]:
			rebuilt.append(brush_id)
	assert_eq(rebuilt, [], "%s: brushes the undo rebuilt instead of keeping" % folder)
	assert_eq(HFLevelIO.save_to_path(RESAVED, level.state_system.capture_hflevel_state()), OK)
	var again := _new_level()
	assert_true(again.load_hflevel(RESAVED), "%s: saved after the undo, it loads" % folder)
	await get_tree().process_frame
	_compare_census(folder, Census.of(again), loaded, "saved after the undo")


## Compare with File between an old level and its own file finds nothing: the
## loader's repairs are not changes the mapper made (#1701).
func test_each_release_level_compared_with_its_own_file_has_no_changes(
	folder = use_parameters(_folders())
):
	var level: LevelRoot = await _loaded(folder)
	var read: Dictionary = level.file_system.read_hflevel(_level_file(folder))
	assert_true(bool(read.get("ok", false)), "%s: the file reads" % folder)
	if not bool(read.get("ok", false)):
		return
	var result := HFLevelCompare.compare(
		read["bundle"], level.state_system.capture_hflevel_payload()
	)
	var changed: Array = []
	for kind in result["counts"]:
		if int(result["counts"][kind]) != 0:
			changed.append(kind)
	assert_eq(changed, [], "%s: %s" % [folder, "; ".join(result["lines"])])


func _loaded(folder: String) -> LevelRoot:
	var level := _new_level()
	assert_true(level.load_hflevel(_level_file(folder)), "%s loads" % folder)
	await get_tree().process_frame
	return level


## Each brush's record, by id, as an undo step captures it.
func _records(level: LevelRoot) -> Dictionary:
	var out := {}
	var state: Dictionary = level.capture_state(false)
	for key in ["brushes", "pending", "committed"]:
		for info in state.get(key, []):
			out[str(info.get("brush_id", ""))] = info
	return out


func _first_draft_brush(level: LevelRoot) -> Node3D:
	for child in level.draft_brushes_node.get_children():
		if child is DraftBrush:
			return child
	return null


## Every brush whose record is not the one it had, named.
func _compare_records(folder: String, got: Dictionary, want: Dictionary, how: String) -> void:
	var differ: Array = []
	for brush_id in want:
		if not got.has(brush_id):
			differ.append("%s gone" % brush_id)
		elif not (got[brush_id] as Dictionary).recursive_equal(want[brush_id], 32):
			differ.append(brush_id)
	for brush_id in got:
		if not want.has(brush_id):
			differ.append("%s new" % brush_id)
	assert_eq(differ, [], "%s: brushes whose record changed %s" % [folder, how])


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
