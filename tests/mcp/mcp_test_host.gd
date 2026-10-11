extends "res://addons/hammerforge/mcp/hf_mcp_host.gd"

## The editor, as far as the MCP dispatcher can tell, for tests and the bridge
## smoke script: a scene root the test sets, an undo stand-in, and a history list
## to read back.

var scene: Node = null
var undo = null
var tree: SceneTree = null
var history: Array = []
## Where hf_bake writes, instead of beside the scene in the repository.
var artifact_path_override := ""
## How many frames a command waits after it commits. More than one makes a
## command slow enough for a test to act while it runs.
var wait_frames := 1


func edited_scene_root() -> Node:
	return scene if is_instance_valid(scene) else null


func undo_manager() -> Object:
	return undo


func record_history(action_name: String) -> void:
	history.append(action_name)


func artifact_path(root: Node) -> String:
	return artifact_path_override if artifact_path_override != "" else super.artifact_path(root)


func next_frame() -> void:
	for i in wait_frames:
		await tree.process_frame


## Create Starter the way the plugin does, through the factory's one-step path.
func create_starter(action_name: String) -> Node:
	return HFLevelFactory.create_starter_undoable(
		undo, scene, action_name, null, {"hflevel_autosave_enabled": false}
	)
