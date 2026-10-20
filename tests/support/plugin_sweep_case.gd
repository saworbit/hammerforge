extends GutTest
## What the plugin sweeps share: the real plugin brought up and taken down, the
## awkward states each sweep runs in, and the files the developer's own editor
## uses set aside around them.
##
## `test_palette_action_sweep.gd` runs every dispatched action in these states,
## `test_undo_sweep.gd` undoes and redoes each one, and `test_keymap_sweep.gd`
## sends every key binding through the plugin's input path.
##
## Copy, paste and Quick Save Prefab write the run's own clipboard and prefab
## folder (`gut_pre_run.gd`). The clipboard is seeded before each action so paste
## has something to put down, and every prefab an action saves is taken away
## again, so the next script finds the folder as it was. Quick Play writes the
## playtest request and the reload lock under `res://.hammerforge/`, which the
## developer's editor on this checkout uses: both are set aside and put back.

const PluginStandIn = preload("res://tests/support/plugin_stand_in.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFKeymapScript = preload("res://addons/hammerforge/hf_keymap.gd")
const HFPluginShortcutsScript = preload("res://addons/hammerforge/plugin_shortcuts.gd")
const HFPlaytestRequestScript = preload("res://addons/hammerforge/hf_playtest_request.gd")
const HFPrefabSystemScript = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
## What a Quick Play leaves for the run it launches, in the project.
const PLAYTEST_FILES := [HFPlaytestRequestScript.PATH, LevelRootScript.RELOAD_LOCK_PATH]
const ASIDE_SUFFIX := ".sweep_aside"

const STATES := [
	"no_level",
	"nothing_selected",
	"box_selected",
	"two_boxes",
	"entity_only",
	"pending_cut",
	"generator_piece",
	"brush_entity",
	"displaced_brush",
	"freed_brush",
]


## The level as the editor holds it. Headless, `Engine.is_editor_hint()` is off,
## so a plain level comes up as a running game: it collects the playtest request
## and polls the reload lock, both of which Quick Play writes for the game it
## launches, not for the level it was pressed in. An editor's level does neither,
## so this one does neither.
class EditorLevel:
	extends LevelRoot

	func _start_playtest(_request: Dictionary = {}) -> void:
		pass

	func request_remote_reload() -> void:
		pass


var scene_root: Node3D
var plugin: Node
var _keymap = HFKeymapScript.load_or_default("")
## A clipboard holding one box, made by a real copy, so paste always has
## something to put down.
var _clipboard_seed := PackedByteArray()
var _prefabs_before := PackedStringArray()
var _hammerforge_dir_existed := false
var _hammerforge_files_before := PackedStringArray()


func before_all():
	var prefab_dir: String = HFPrefabSystemScript.prefab_dir
	if DirAccess.dir_exists_absolute(prefab_dir):
		_prefabs_before = DirAccess.get_files_at(prefab_dir)
	_set_playtest_files_aside()
	var root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child(root)
	var box = _box(root, "clip", Vector3(0, 2, -8))
	root.prefab_system.copy_to_clipboard([box], [])
	_clipboard_seed = FileAccess.get_file_as_bytes(HFPrefabSystemScript.clipboard_path)
	remove_child(root)
	root.free()


func before_each():
	var file := FileAccess.open(HFPrefabSystemScript.clipboard_path, FileAccess.WRITE)
	if file:
		file.store_buffer(_clipboard_seed)
		file.close()


func after_each():
	await _take_down()
	_remove_written_prefabs()
	_remove_playtest_files()


func after_all():
	DirAccess.remove_absolute(HFPrefabSystemScript.clipboard_path)
	_remove_written_prefabs()
	_put_playtest_files_back()


## Take away the prefabs an action saved, and leave what an earlier script left.
func _remove_written_prefabs() -> void:
	var prefab_dir: String = HFPrefabSystemScript.prefab_dir
	if not DirAccess.dir_exists_absolute(prefab_dir):
		return
	for file_name in DirAccess.get_files_at(prefab_dir):
		if not _prefabs_before.has(file_name):
			DirAccess.remove_absolute(prefab_dir.path_join(file_name))


## The developer's own playtest files go aside, so a Quick Play here neither
## replaces a request their editor just left nor restarts a run polling the lock.
func _set_playtest_files_aside() -> void:
	var dir: String = str(PLAYTEST_FILES[0]).get_base_dir()
	_hammerforge_dir_existed = DirAccess.dir_exists_absolute(dir)
	for path in PLAYTEST_FILES:
		var aside := str(path) + ASIDE_SUFFIX
		if FileAccess.file_exists(aside):
			# A run that never finished left the developer's file aside, and the
			# one in its place is a sweep's.
			DirAccess.remove_absolute(path)
	if _hammerforge_dir_existed:
		_hammerforge_files_before = _sorted_files_at(dir)
	for path in PLAYTEST_FILES:
		if FileAccess.file_exists(path):
			DirAccess.rename_absolute(path, str(path) + ASIDE_SUFFIX)


func _remove_playtest_files() -> void:
	for path in PLAYTEST_FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Everything back as it was, and the folder itself gone if the sweep made it.
## Whatever a sweep leaves under `res://.hammerforge/` is the developer's next
## surprise, so the folder is checked, not just tidied.
func _put_playtest_files_back() -> void:
	_remove_playtest_files()
	for path in PLAYTEST_FILES:
		var aside := str(path) + ASIDE_SUFFIX
		if FileAccess.file_exists(aside):
			DirAccess.rename_absolute(aside, path)
	var dir: String = str(PLAYTEST_FILES[0]).get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	var files_now := _sorted_files_at(dir)
	assert_eq(files_now, _hammerforge_files_before, "no sweep leaves a file under %s" % dir)
	var empty := files_now.is_empty() and DirAccess.get_directories_at(dir).is_empty()
	if not _hammerforge_dir_existed and empty:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


static func _sorted_files_at(dir: String) -> PackedStringArray:
	var files := DirAccess.get_files_at(dir)
	files.sort()
	return files


func _describe(errors: Array) -> Array:
	var out: Array = []
	for e in errors:
		out.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	return out


## With `with_undo` the plugin commits through the undo manager stand-in. It goes
## under `parent`, or under the test.
func _bring_up(with_undo: bool = false, parent: Node = null) -> void:
	scene_root = Node3D.new()
	scene_root.name = "EditedScene"
	add_child(scene_root)
	plugin = PluginStandIn.build(parent if parent else self, scene_root, with_undo)
	await get_tree().process_frame


func _take_down() -> void:
	PluginStandIn.teardown(plugin)
	plugin = null
	if is_instance_valid(scene_root):
		remove_child(scene_root)
		scene_root.free()
	scene_root = null
	# What `_exit_tree` queued goes before GUT counts orphans.
	await get_tree().process_frame
	await get_tree().process_frame


## Wait for a bake the action started, so what it does once the bake lands is
## in the check. Quick Play, Bake and Commit Cuts run over frames, and Commit
## Cuts registers its undo step only once its bake has finished.
func _settle(root: Node) -> void:
	for _i in 600:
		if root == null or not is_instance_valid(root) or not root.is_bake_in_flight():
			break
		await get_tree().process_frame
	await get_tree().process_frame


## Press OK on every dialog the action opened, as a user who says yes to
## everything, so what a confirmation commits runs too. Returns how many.
func _accept_dialogs() -> int:
	var pressed := 0
	for node in plugin.stand_in_editor.base_control.find_children("*", "AcceptDialog", true, false):
		if node.visible:
			node.get_ok_button().pressed.emit()
			pressed += 1
	if pressed > 0:
		await get_tree().process_frame
	return pressed


## Close the level the way a scene tab closes: out of the selection, out of the
## scene, freed, with the frame's deferred work done first.
func _leave_level(root: Node) -> void:
	await get_tree().process_frame
	# Before the next level is built: a plain level, as every other script
	# builds, collects a request left lying and plays it.
	_remove_playtest_files()
	_select([])
	if root != null and is_instance_valid(root):
		scene_root.remove_child(root)
		root.free()
	await get_tree().process_frame


## Escape until nothing is left to cancel, the way a user clears the decks.
func _escape_to_idle(root: Node) -> void:
	var live_root: Node = root if is_instance_valid(root) else null
	for _i in 12:
		if not HFPluginShortcutsScript.cancel_escape_step(plugin, live_root):
			return


func _select(nodes: Array) -> void:
	var selection = plugin.stand_in_editor.selection
	selection.clear()
	for node in nodes:
		selection.add_node(node)


func _box(root: Node, id: String, center: Vector3) -> Node:
	return root.create_brush_from_info({"size": Vector3(4, 4, 4), "center": center, "brush_id": id})


## Build `state` in the edited scene and select what it selects. Returns the
## level, or null for `no_level`.
func _enter_state(state: String) -> Node:
	if state == "no_level":
		return null
	var root = EditorLevel.new()
	root.name = "LevelRoot"
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	scene_root.add_child(root)
	root.owner = scene_root
	# The editor adopts a level when it is selected.
	_select([root])
	var a = _box(root, "a", Vector3(0, 2, 0))
	var b = _box(root, "b", Vector3(8, 2, 0))
	match state:
		"nothing_selected":
			_select([])
		"box_selected":
			_select([a])
		"two_boxes":
			# Side by side, so together they are one box and Merge can take them.
			b.global_position = Vector3(4, 2, 0)
			_select([a, b])
		"entity_only":
			var entity = DraftEntityScript.new()
			entity.name = "lamp"
			entity.entity_type = "light_point"
			entity.entity_class = "light_point"
			root.add_entity(entity)
			entity.global_position = Vector3(0, 6, 0)
			_select([entity])
		"pending_cut":
			var cut_info := {
				"size": Vector3(2, 2, 2),
				"center": Vector3(0, 2, 0),
				"brush_id": "cut",
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"pending": true,
			}
			_select([a, root.create_brush_from_info(cut_info)])
		"generator_piece":
			var before: Array = root.draft_brushes_node.get_children()
			var settings: Dictionary = HFGeneratorSystemScript.default_settings("stairs")
			settings["steps"] = 4
			root.create_generator("stairs", settings, Transform3D(Basis(), Vector3(-10, 0, 0)))
			var piece = null
			for node in root.draft_brushes_node.get_children():
				if not before.has(node):
					piece = node
					break
			assert_not_null(piece, "the generator made a piece to select")
			_select([piece] if piece else [])
		"brush_entity":
			root.tie_brushes_to_entity(["a"], "func_door", "door_1")
			_select([a])
		"displaced_brush":
			var displaced := false
			var faces: Array = a.get_faces()
			for i in faces.size():
				if faces[i].normal.y > 0.9:
					displaced = root.create_displacement("a", i, 2)
					break
			assert_true(displaced, "the box took a displacement")
			_select([a])
		"freed_brush":
			_select([a, b])
			root.delete_brush(b)
	# A frame: the dock's `_process` adopts the level, as it has by the time a
	# mapper reaches for an action, and the editor's selection lets go of a freed
	# brush at the end of the frame, before the next key can reach the palette.
	await get_tree().process_frame
	return root


func _snapshot(root: Node) -> String:
	if root == null or not is_instance_valid(root):
		return ""
	return var_to_str(root.capture_state(false))


func _level_roots() -> int:
	var count := 0
	for child in scene_root.get_children():
		if child.get_script() == LevelRootScript:
			count += 1
	return count
