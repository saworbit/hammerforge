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


## Where `hf_bake` writes the scene a runtime test loads: beside the level's own
## scene, named after it with `_mcp`, so it never overwrites the `_game.tscn`
## Export Game Scene writes. A scene never saved gets one file at the project root.
static func artifact_path_for(scene_path: String) -> String:
	if scene_path == "" or not scene_path.begins_with("res://"):
		return "res://hammerforge_mcp_bake.tscn"
	var name := "%s_mcp.tscn" % scene_path.get_file().get_basename()
	return scene_path.get_base_dir().path_join(name)


func artifact_path(root: Node) -> String:
	return artifact_path_for(str(root.scene_source_path()))


## A file was written under res:// behind the editor's back. Tell its file system,
## so the FileSystem dock shows it.
func notify_file_written(_path: String) -> void:
	pass


## The editor's 3D viewport, or null where there is none to read, as in a test.
func viewport_3d() -> Viewport:
	return null


## Where a screenshot's temporary viewport goes while it renders.
func screenshot_parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null


## Draw a frame now, so a viewport's image is current, and say whether one was
## drawn. A coroutine.
##
## Forced rather than waited for. A headless editor never draws, so a wait for
## `frame_post_draw` never ends; it held the command queue, and every request
## behind a screenshot timed out. And an editor with nothing changing on screen
## draws rarely, so a wait there could be long. `tools/capture_showcase.gd`
## forces its frame the same way.
func frame_drawn() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	RenderingServer.force_draw(false)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame
	return true


## A history was stepped directly rather than through the editor's undo manager,
## which therefore told nobody. Let the editor react as it does to its own steps.
func after_history_step() -> void:
	pass


## Wait one process frame, so work a commit deferred has run before the
## dispatcher reads the revision.
func next_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame
