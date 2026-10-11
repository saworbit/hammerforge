@tool
extends EditorPlugin
## Stands in for the user at the editor during an MCP vibe run.
##
## `tools/vibe/mcp/run_mcp_vibe.py` copies this folder to `addons/hf_mcp_vibe/`,
## enables it in a backed-up `project.godot`, and takes both away again when the
## run ends. It is never committed under `addons/`. It ticks Allow agent
## connections through the real panel, and runs the orders the driver writes to
## `res://.godot/mcp_vibe_cmd.json`, answering in `res://.godot/mcp_vibe_out.json`:
## the things a person does in the editor while an agent works, such as a Ctrl+Z,
## an edit of their own, opening another scene tab, or saving.

const CMD := "res://.godot/mcp_vibe_cmd.json"
const OUT := "res://.godot/mcp_vibe_out.json"
const HAMMERFORGE_PLUGIN := "res://addons/hammerforge/plugin.gd"

var _hf: EditorPlugin = null
var _last_id := -1


func _enter_tree() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	if _hf == null:
		for node in get_tree().root.find_children("*", "EditorPlugin", true, false):
			var script: Script = node.get_script()
			if script and script.resource_path == HAMMERFORGE_PLUGIN:
				_hf = node
				_write({"id": -1, "ready": true})
		return
	if not FileAccess.file_exists(CMD):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CMD)) != OK or not (json.data is Dictionary):
		return
	var cmd: Dictionary = json.data
	var id := int(cmd.get("id", -1))
	if id == _last_id:
		return
	_last_id = id
	_write({"id": id, "result": _run(cmd)})


func _run(cmd: Dictionary) -> Variant:
	var op := str(cmd.get("op", ""))
	var panel = _hf.dock.mcp_panel
	match op:
		"enable":
			panel.enable_check.button_pressed = true
			return panel.status_label.text
		"disable":
			panel.enable_check.button_pressed = false
			return panel.status_label.text
		"panel":
			return {
				"text": panel.status_label.text,
				"last": panel.last_label.text,
				"ticked": panel.is_enabled(),
				"lamp": panel.lamp.severity,
			}
		"scene":
			var edited := EditorInterface.get_edited_scene_root()
			return str(edited.name) if edited else null
		"open":
			EditorInterface.open_scene_from_path(str(cmd["path"]))
			var opened := EditorInterface.get_edited_scene_root()
			return str(opened.name) if opened else null
		"save_as":
			EditorInterface.save_scene_as(str(cmd["path"]))
			return EditorInterface.get_edited_scene_root().scene_file_path
		"reload":
			EditorInterface.reload_scene_from_path(str(cmd["path"]))
			return str(EditorInterface.get_edited_scene_root().name)
		"history":
			return _history()
		"dock_history":
			return _dock_history()
		"brushes":
			return _brushes()
		"undo":
			# The scene history stepped directly, the way the dock's Undo button does.
			var scene_ur := _scene_history()
			if scene_ur == null:
				return "no history"
			scene_ur.undo()
			return _history()
		"manager_undo":
			# What Ctrl+Z does: the editor's own Undo, through the undo manager.
			_send_key(KEY_Z, false)
			return "sent"
		"manager_redo":
			_send_key(KEY_Z, true)
			return "sent"
		"human_nudge":
			return _human_nudge()
		"human_hide_floor":
			return _human_hide_floor()
		"dock_create_starter":
			_hf.dock._on_create_level_root(true)
			return _history()
		"close_on_bake":
			# The user closes the scene tab once the next bake has started.
			var baking = _hf._get_level_root()
			if baking == null:
				return "no level"
			baking.bake_started.connect(
				func(): EditorInterface.close_scene.call_deferred(), CONNECT_ONE_SHOT
			)
			return "armed"
		"quit":
			get_tree().quit()
			return "bye"
	return "unknown op %s" % op


func _send_key(keycode: Key, shift: bool) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.ctrl_pressed = true
	press.shift_pressed = shift
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)


## A person moves the first brush a metre, as one step of their own.
func _human_nudge() -> Variant:
	var level = _hf._get_level_root()
	if level == null:
		return "no level"
	var found: Array = level._iter_managed_brush_nodes()
	if found.is_empty():
		return "no brush"
	var brush: Node3D = found[0]
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Human nudge")
	ur.add_do_property(brush, "position", brush.position + Vector3(1, 0, 0))
	ur.add_undo_property(brush, "position", brush.position)
	ur.commit_action()
	return _history()


## A person hides the starter's floor, as one step of their own.
func _human_hide_floor() -> Variant:
	var level = _hf._get_level_root()
	var floor_node = level.get_node_or_null("TempFloor") if level else null
	if floor_node == null:
		return "no floor"
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Human hide floor")
	ur.add_do_property(floor_node, "visible", false)
	ur.add_undo_property(floor_node, "visible", true)
	ur.commit_action()
	return _history()


func _brushes() -> Variant:
	var level = _hf._get_level_root()
	if level == null:
		return null
	var out := []
	for brush in level._iter_managed_brush_nodes():
		var at: Vector3 = brush.global_position
		out.append({"id": brush.brush_id, "position": [at.x, at.y, at.z]})
	return out


func _dock_history() -> Variant:
	var entries = _hf.dock.get("history_entries")
	if entries == null:
		return null
	var names := []
	for entry in entries:
		names.append(str(entry.get("name", "")))
	return names


func _scene_history() -> UndoRedo:
	var ur := EditorInterface.get_editor_undo_redo()
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null:
		return null
	return ur.get_history_undo_redo(ur.get_object_history_id(scene))


func _history() -> Dictionary:
	var history := _scene_history()
	if history == null:
		return {}
	var names := []
	for i in history.get_history_count():
		names.append(history.get_action_name(i))
	return {
		"current": history.get_current_action(),
		"current_name": history.get_current_action_name(),
		"names": names,
		"version": history.get_version(),
	}


func _write(data: Dictionary) -> void:
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
