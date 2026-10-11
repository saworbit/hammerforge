extends "res://addons/hammerforge/mcp/hf_mcp_host.gd"

## The editor, as far as the MCP dispatcher can tell, for tests and the bridge
## smoke script: a scene root the test sets, an undo stand-in, and a history list
## to read back.

var scene: Node = null
var undo = null
var tree: SceneTree = null
var history: Array = []
## How many frames a command waits after it commits. More than one makes a
## command slow enough for a test to act while it runs.
var wait_frames := 1


func edited_scene_root() -> Node:
	return scene if is_instance_valid(scene) else null


func undo_manager() -> Object:
	return undo


func record_history(action_name: String) -> void:
	history.append(action_name)


func next_frame() -> void:
	for i in wait_frames:
		await tree.process_frame
