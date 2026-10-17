extends GutTest
## What the plugin sweeps share: the real plugin brought up and taken down, the
## awkward states each sweep runs in, and the files the developer's own editor
## uses set aside around them.
##
## `test_palette_action_sweep.gd` runs every dispatched action in these states,
## `test_undo_sweep.gd` undoes and redoes each one, and `test_keymap_sweep.gd`
## sends every key binding through the plugin's input path.
##
## Copy, paste and Quick Save Prefab write files the developer's own editor uses.
## The clipboard is set aside and put back, and every prefab an action saves is
## taken away again.

const PluginStandIn = preload("res://tests/support/plugin_stand_in.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFKeymapScript = preload("res://addons/hammerforge/hf_keymap.gd")
const HFPluginShortcutsScript = preload("res://addons/hammerforge/plugin_shortcuts.gd")
const HFPrefabSystemScript = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")
## Copy and paste go through this file, the one the developer's own editor uses.
const CLIPBOARD := HFPrefabSystemScript.CLIPBOARD_PATH
const CLIPBOARD_ASIDE := CLIPBOARD + ".sweep_aside"
## Quick Save Prefab writes here, inside the project.
const PREFAB_DIR := HFPrefabSystemScript.PREFAB_DIR

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

var scene_root: Node3D
var plugin: Node
var _keymap = HFKeymapScript.load_or_default("")
## A clipboard holding one box, made by a real copy, so paste always has
## something to put down.
var _clipboard_seed := PackedByteArray()
var _prefab_dir_existed := false
var _prefabs_before := PackedStringArray()


func before_all():
	if FileAccess.file_exists(CLIPBOARD_ASIDE):
		# A run that never finished left the developer's clipboard aside, and the
		# one in its place is the sweep's.
		DirAccess.remove_absolute(CLIPBOARD)
	elif FileAccess.file_exists(CLIPBOARD):
		DirAccess.rename_absolute(CLIPBOARD, CLIPBOARD_ASIDE)
	_prefab_dir_existed = DirAccess.dir_exists_absolute(PREFAB_DIR)
	if _prefab_dir_existed:
		_prefabs_before = DirAccess.get_files_at(PREFAB_DIR)
	var root = LevelRootScript.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child(root)
	var box = _box(root, "clip", Vector3(0, 2, -8))
	root.prefab_system.copy_to_clipboard([box], [])
	_clipboard_seed = FileAccess.get_file_as_bytes(CLIPBOARD)
	remove_child(root)
	root.free()


func before_each():
	var file := FileAccess.open(CLIPBOARD, FileAccess.WRITE)
	if file:
		file.store_buffer(_clipboard_seed)
		file.close()


func after_each():
	await _take_down()
	_remove_written_prefabs()


func after_all():
	DirAccess.remove_absolute(CLIPBOARD)
	if FileAccess.file_exists(CLIPBOARD_ASIDE):
		DirAccess.rename_absolute(CLIPBOARD_ASIDE, CLIPBOARD)
	_remove_written_prefabs()
	if not _prefab_dir_existed and DirAccess.dir_exists_absolute(PREFAB_DIR):
		DirAccess.remove_absolute(PREFAB_DIR)


## Take away the prefabs an action saved, and leave the developer's own.
func _remove_written_prefabs() -> void:
	if not DirAccess.dir_exists_absolute(PREFAB_DIR):
		return
	for file_name in DirAccess.get_files_at(PREFAB_DIR):
		if not _prefabs_before.has(file_name):
			DirAccess.remove_absolute(PREFAB_DIR.path_join(file_name))


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
	var root = LevelRootScript.new()
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
			# The editor's selection lets go of it at the end of the frame, before
			# the next key can reach the palette.
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
