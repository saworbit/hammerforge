@tool
class_name HFLevelFactory
extends RefCounted

## Builds HammerForge level roots from code.
##
## The dock's empty-state banner is one caller of this, not the definition of
## it. Tests, headless tools and editor bridges get the same starter level
## without constructing a dock or an EditorPlugin. `LevelRoot` already exposes
## the level's own behaviour (`create_new_level`, the `bake` family); this is
## the missing step in front of that, which is making the node itself.


## A detached `LevelRoot`, named but not parented.
##
## For callers that add the node themselves, which is what the editor plugin
## does so the add is one undo entry, and what anyone who needs to set exported
## properties before `_ready` runs does.
static func make_level_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.name = "LevelRoot"
	return root


## Add an empty `LevelRoot` under `parent` and return it.
##
## `scene_owner` decides whether the node survives a scene save. It defaults to
## whatever owns `parent`, falling back to `parent` itself, which is the right
## answer when `parent` is the scene root.
##
## `properties` is applied before the node enters the tree, because `LevelRoot`
## reads its exports in `_ready` and there is no later chance. Outside the
## editor that is the only way to stop a fresh root starting a playtest:
## `{"auto_spawn_player": false}`. Inside the editor the defaults are correct
## and this can be left empty.
##
## `parent` must already be inside a `SceneTree`, because the root builds its
## subsystems in `_ready`. Returns null if it is not.
static func create_level_root(
	parent: Node, scene_owner: Node = null, properties: Dictionary = {}
) -> LevelRoot:
	if parent == null:
		push_error("HFLevelFactory: parent is null")
		return null
	if not parent.is_inside_tree():
		push_error("HFLevelFactory: parent must be inside the scene tree")
		return null
	var root := make_level_root()
	for key in properties:
		if not key in root:
			push_error("HFLevelFactory: LevelRoot has no property '%s'" % key)
			continue
		root.set(key, properties[key])
	parent.add_child(root)
	root.owner = _resolve_owner(parent, scene_owner)
	return root


## Add a `LevelRoot` under `parent` and fill it with the starter level: a floor,
## an angled sun light and a player spawn.
##
## Same result as Create Starter in the dock's empty-state banner. Returns null
## if the root could not be made.
static func create_starter(
	parent: Node, scene_owner: Node = null, properties: Dictionary = {}
) -> LevelRoot:
	var root := create_level_root(parent, scene_owner, properties)
	if root == null:
		return null
	root.create_new_level()
	return root


static func _resolve_owner(parent: Node, scene_owner: Node) -> Node:
	if scene_owner != null:
		return scene_owner
	if parent.owner != null:
		return parent.owner
	return parent
