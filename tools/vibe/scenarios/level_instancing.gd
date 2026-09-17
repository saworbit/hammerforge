@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Building a game out of level pieces, rather than one level per game.
##
## `two-levels` puts a second `LevelRoot` beside the first in one scene.
## `scene-reopen` packs one root and opens it again. Neither one does the thing
## a real project does, which is save a piece of level as its own scene and then
## **instance that scene** -- twice, three times, rotated, at an offset -- to
## build a bigger map out of modules. That is how corridors, rooms and prop
## clusters get reused, and it is the first thing anyone tries once a level
## takes longer than an evening.
##
## The question is what an instanced level piece is: whether the two copies keep
## separate brushes, whether their ids collide, whether each one bakes its own
## geometry, and whether the copy in the parent scene is editable at all.


func id() -> String:
	return "level-instancing"


func summary() -> String:
	return "what a level saved as a scene and instanced twice into a parent is"


const PIECE_PATH := "user://vibe_level_piece.tscn"


func run() -> void:
	await _save_a_piece_and_instance_it_twice()
	await _what_a_second_copy_does_to_the_first()


func _walk(node: Node, out: Array) -> Array:
	out.append(node)
	for c in node.get_children():
		_walk(c, out)
	return out


func _brush_ids(root: Node) -> Array:
	var out: Array = []
	for n in _walk(root, []):
		if n.has_meta("brush_id"):
			out.append(str(n.get_meta("brush_id")))
		elif "brush_id" in n:
			out.append(str(n.get("brush_id")))
	return out


## A corridor piece: floor, two walls, a light and a name, saved as its own scene
## the way `PackedScene.pack()` saves the edited scene on Ctrl+S.
func _make_piece() -> PackedScene:
	var holder := Node3D.new()
	holder.name = "CorridorPiece"
	_tree.get_root().add_child(holder)
	var root := HFVibe.make_root(_tree, "Corridor")
	# make_root parents to the scene root; move it under the holder so the holder
	# is what gets packed.
	root.get_parent().remove_child(root)
	holder.add_child(root)
	await _tree.process_frame
	root.auto_spawn_player = false
	box(root, Vector3(3, 0.2, 8), Vector3(0, -0.1, 0))
	box(root, Vector3(0.3, 3, 8), Vector3(-1.5, 1.5, 0))
	box(root, Vector3(0.3, 3, 8), Vector3(1.5, 1.5, 0))
	await _tree.process_frame
	note("piece brushes", root.brush_system.get_live_brush_count())
	note("piece brush ids", _brush_ids(root))
	# The editor gives everything an owner on save; headless does not (#664's trap).
	for n in _walk(root, []):
		if n != holder:
			n.owner = holder
	var packed := PackedScene.new()
	var err := packed.pack(holder)
	note("pack()", err)
	if err == OK:
		ResourceSaver.save(packed, PIECE_PATH)
		note("saved to", PIECE_PATH)
	holder.queue_free()
	await _tree.process_frame
	return packed if err == OK else null


func _save_a_piece_and_instance_it_twice() -> void:
	var packed: PackedScene = await _make_piece()
	if packed == null:
		flag("could not pack a level piece at all")
		return
	var stored: PackedScene = load(PIECE_PATH)
	if stored == null:
		flag("a packed level piece would not load back off disk", PIECE_PATH)
		return

	var parent := Node3D.new()
	parent.name = "GameMap"
	_tree.get_root().add_child(parent)
	var copies: Array = []
	for i in 2:
		var inst := stored.instantiate()
		inst.name = "Piece_%d" % i
		parent.add_child(inst)
		(inst as Node3D).position = Vector3(0, 0, i * 8.0)
		copies.append(inst)
	for _i in 3:
		await frame()

	for i in copies.size():
		var inst: Node = copies[i]
		var lr: Node = null
		for n in _walk(inst, []):
			if n.get_script() and str(n.get_script().resource_path).ends_with("level_root.gd"):
				lr = n
				break
		if lr == null:
			flag("an instanced level piece has no LevelRoot in it", "copy %d" % i)
			continue
		note(
			"copy %d" % i,
			"brushes=%s ids=%s" % [lr.brush_system.get_live_brush_count(), _brush_ids(lr)]
		)

	var ids0: Array = _brush_ids(copies[0])
	var ids1: Array = _brush_ids(copies[1])
	var shared: Array = ids0.filter(func(i: String) -> bool: return ids1.has(i))
	note("brush ids the two copies share", shared)
	if not shared.is_empty():
		flag(
			"two instances of the same level piece carry the same brush ids",
			(
				(
					"brush_id is the address every visgroup, group, hollow, array and I/O wire is "
					+ "written against, and the plugin's own id minting is per-session. Instancing "
					+ "a saved piece twice -- the way any project reuses a corridor -- puts %d "
					+ "duplicate ids in one scene tree, so any lookup by id in the parent scene is "
					+ "ambiguous. The ids are %s."
				)
				% [shared.size(), shared.slice(0, 4)]
			)
		)
	parent.queue_free()
	await frame()


func _what_a_second_copy_does_to_the_first() -> void:
	var stored: PackedScene = load(PIECE_PATH) if ResourceLoader.exists(PIECE_PATH) else null
	if stored == null:
		return
	var parent := Node3D.new()
	parent.name = "GameMap2"
	_tree.get_root().add_child(parent)
	var a := stored.instantiate()
	parent.add_child(a)
	for _i in 3:
		await frame()
	var lr_a: Node = null
	for n in _walk(a, []):
		if n.get_script() and str(n.get_script().resource_path).ends_with("level_root.gd"):
			lr_a = n
	var before: int = lr_a.brush_system.get_live_brush_count() if lr_a else -1

	var b := stored.instantiate()
	(b as Node3D).position = Vector3(20, 0, 0)
	parent.add_child(b)
	for _i in 3:
		await frame()
	var after: int = lr_a.brush_system.get_live_brush_count() if lr_a else -1
	note("first copy's brush count before the second was added", before)
	note("first copy's brush count after", after)
	if before != after:
		flag(
			"adding a second instance of a level piece changed the first one's brush count",
			"%d -> %d" % [before, after]
		)
	# Each copy should bake its own geometry, in its own place.
	if lr_a:
		await lr_a.bake(false, false)
		await frame()
		var c := lr_a.get_node_or_null("BakedGeometry")
		note("the first copy baked", c != null)
	parent.queue_free()
	await frame()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PIECE_PATH))
