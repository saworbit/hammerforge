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

	var roots: Array = []
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
		roots.append(lr)
		note(
			"copy %d" % i,
			"brushes=%s ids=%s" % [lr.brush_system.get_live_brush_count(), _brush_ids(lr)]
		)

	var ids0: Array = _brush_ids(copies[0])
	var ids1: Array = _brush_ids(copies[1])
	var shared: Array = ids0.filter(func(i: String) -> bool: return ids1.has(i))
	note("brush ids the two copies share", shared)
	note(
		"what that means",
		(
			"an id is unique within one level, not within a scene (#696). A saved piece "
			+ "freezes the ids it had, so two instances carry the same set on purpose."
		)
	)

	# The rule only holds up if a lookup never leaves its own root. That is the
	# thing worth checking, rather than the sharing itself.
	var crossed: Array = []
	if roots.size() >= 2:
		for brush_id in shared:
			# The LevelRoot inside each copy, not the instantiated scene root: the
			# lookup is the root's, and asking the Node3D above it is a nonexistent
			# function rather than a different answer.
			var from_first = roots[0].find_brush_by_id(brush_id)
			var from_second = roots[1].find_brush_by_id(brush_id)
			if from_first == null or from_second == null or from_first == from_second:
				crossed.append(brush_id)
	note("shared ids each copy resolves to its own brush", shared.size() - crossed.size())
	if not crossed.is_empty():
		flag(
			"a lookup by id does not stay inside its own level",
			(
				(
					"Two instances of a saved piece carry the same ids, which is supported "
					+ "because each root resolves its own children. %d of %d shared ids did "
					+ "not: one copy answered with the other's brush, or with nothing. Every "
					+ "visgroup, group, hollow, array and I/O wire is written against an id, "
					+ "so a lookup that crosses roots edits the wrong copy. The ids are %s."
				)
				% [crossed.size(), shared.size(), crossed.slice(0, 4)]
			)
		)

	# And the case that is a real corruption rather than an arrangement: one
	# level holding two brushes with the same id. The cache is keyed by id, so
	# one of the two becomes unreachable.
	for i in roots.size():
		var own: Array = _brush_ids(roots[i])
		var seen: Dictionary = {}
		var twice: Array = []
		for brush_id in own:
			if seen.has(brush_id) and not (brush_id in twice):
				twice.append(brush_id)
			seen[brush_id] = true
		note("copy %d, ids it holds more than once" % i, twice)
		if not twice.is_empty():
			flag(
				"one level holds two brushes with the same id",
				(
					(
						"The brush cache is keyed by id, so the second to register overwrites "
						+ "the first and one of the two cannot be addressed at all. Validate "
						+ "reports this since #696; seeing it here means it was made rather "
						+ "than loaded. The ids are %s."
					)
					% str(twice)
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
