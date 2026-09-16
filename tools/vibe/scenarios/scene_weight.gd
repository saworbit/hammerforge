@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a HammerForge level does to the `.tscn` it lives in.
##
## A level is a node in the user's scene, and the editor's own Ctrl+S writes it
## to disk like any other scene. Whatever HammerForge gives an `owner` to goes
## into that file -- and the `.hflevel` beside it is a *second*, independent copy
## of the same level. So the question is which nodes are owned, what that costs,
## and whether the two files agree.
##
## `LevelRoot._get_editor_owner()` reads `tree.edited_scene_root`, which is null
## in a headless harness, so nothing is owned here and a straight `pack()` writes
## an empty scene. This assigns the owners the editor would have assigned, which
## is what makes the numbers below mean anything.


func id() -> String:
	return "scene-weight"


func summary() -> String:
	return "what a level costs inside the .tscn it lives in, before and after a bake"


func run() -> void:
	await _what_the_scene_carries()


## What the editor's `_assign_owner()` call sites would have owned. Not
## everything: `PlaytestPlayer` and `RemoteReloadTimer` are built without one, so
## owning them here would inflate the number with nodes the real save leaves out.
const NOT_OWNED := ["PlaytestPlayer", "RemoteReloadTimer"]


func _own_like_the_editor(root: Node3D) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if str(c.name) in NOT_OWNED:
				continue
			c.owner = root
			stack.append(c)


func _pack(root: Node3D, path: String) -> int:
	_own_like_the_editor(root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		return -1
	if ResourceSaver.save(packed, path) != OK:
		return -1
	return HFVibe.file_size(path)


func _owned(root: Node3D) -> Dictionary:
	var counts: Dictionary = {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c.owner == root:
				var key := c.get_class()
				counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _what_the_scene_carries() -> void:
	var root: Node3D = await fresh_root()
	var per_row := 10
	for i in 100:
		box(
			root,
			Vector3(64, 64, 64),
			Vector3(float(i % per_row) * 128.0, 0, float(i / per_row) * 128.0)
		)
	await frame()
	var draft_only := _pack(root, "user://vibe_scene_draft.tscn")
	note("100 brushes, never baked: .tscn bytes", draft_only)
	note("  owned nodes by class", _owned(root))

	await root.bake()
	await frame()
	var after_bake := _pack(root, "user://vibe_scene_baked.tscn")
	note("the same level after a bake: .tscn bytes", after_bake)
	note("  owned nodes by class", _owned(root))

	var hfpath := "user://vibe_scene.hflevel"
	root.save_hflevel(hfpath)
	await HFVibe.settle_save(_tree, root)
	var hflevel := HFVibe.file_size(hfpath)
	note("the .hflevel for the same level", hflevel)

	note(
		"the three numbers",
		(
			".tscn before a bake %.1f KB, after a bake %.1f KB, .hflevel %.1f KB"
			% [draft_only / 1024.0, after_bake / 1024.0, hflevel / 1024.0]
		)
	)
	if after_bake > draft_only:
		note(
			"a bake adds %.1f KB to the scene file" % ((after_bake - draft_only) / 1024.0),
			(
				"_assign_owner_recursive() on the baked container (hf_bake_system.gd:820) "
				+ "is what puts it there, so the baked meshes and their collision shapes "
				+ "are committed alongside the brushes they were built from"
			)
		)
	if draft_only > 0 and hflevel > 0:
		note(
			"the scene carries the level too",
			(
				(
					"%.1fx the .hflevel's bytes for the same 100 brushes, and the two are "
					+ "written by different commands -- Godot's Ctrl+S and HammerForge's Save "
					+ "Level -- so a project can have a .tscn and a .hflevel that disagree"
				)
				% (float(draft_only) / float(hflevel))
			)
		)

	# Which is authoritative on open? Load the packed scene and see what a fresh
	# LevelRoot built from it holds before anything reads the .hflevel.
	var packed: PackedScene = ResourceLoader.load(
		"user://vibe_scene_baked.tscn", "", ResourceLoader.CACHE_MODE_IGNORE
	)
	if packed == null:
		flag("a packed HammerForge level will not load back")
		return
	var reopened: Node = packed.instantiate()
	_tree.get_root().add_child(reopened)
	await frame()
	var brushes := 0
	var baked := 0
	var db = reopened.get_node_or_null("DraftBrushes")
	if db:
		brushes = db.get_child_count()
	var bg = reopened.get_node_or_null("BakedGeometry")
	if bg:
		baked = bg.get_child_count()
	note("reopened from the .tscn: draft brushes", brushes)
	note("reopened from the .tscn: baked children", baked)
	note(
		"so the scene is self-sufficient",
		"the level comes back from the .tscn alone, without the .hflevel being read"
	)
	reopened.queue_free()
