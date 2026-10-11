@tool
class_name HFMcpHost
extends RefCounted
## What the MCP dispatcher asks of the editor, in one place.
##
## The dispatcher never reaches for `EditorInterface` or the plugin itself. The
## plugin hands it an `HFPluginMcp.EditorHost`, and the tests and the bridge smoke
## script hand it one of their own, with an undo stand-in in place of the
## `EditorUndoRedoManager` that cannot be built outside the editor. The defaults
## here are what a host with no editor behind it would answer.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const LevelRoot = preload("../level_root.gd")
@warning_ignore_restore("shadowed_global_identifier")

const PLUGIN_CFG := "res://addons/hammerforge/plugin.cfg"


## The scene open in the editor, or null when none is.
func edited_scene_root() -> Node:
	return null


## The LevelRoot the bridge works on in `scene_root`: the root itself if it is
## one, else the first one inside it. Null for a scene with no level.
func level_root_in(scene_root: Node) -> Node:
	if scene_root == null:
		return null
	if scene_root is LevelRoot:
		return scene_root
	var found := scene_root.find_children("*", "", true, false)
	for node in found:
		if node is LevelRoot:
			return node
	return null


## The `EditorUndoRedoManager`, or something with its call shape.
func undo_manager() -> Object:
	return null


## Put a committed step in the dock's History list and the replay timeline.
func record_history(_action_name: String) -> void:
	pass


func editor_pid() -> int:
	return OS.get_process_id()


func project_path() -> String:
	return ProjectSettings.globalize_path("res://")


func hammerforge_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PLUGIN_CFG) != OK:
		return ""
	return str(cfg.get_value("plugin", "version", ""))


## `{position, rotation_degrees, fov}` of the editor's 3D camera, or null.
func camera_pose() -> Variant:
	return null


## Make a starter level (LevelRoot, floor, sun, spawn) in the edited scene as one
## undo step named `action_name`, and give back the LevelRoot. Null if it could
## not be made.
func create_starter(_action_name: String) -> Node:
	return null


## Wait one process frame, so work a commit deferred has run before the
## dispatcher reads the revision.
func next_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame
