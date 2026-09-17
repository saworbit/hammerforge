@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Which physics layer the world ends up on, and who can still stand on it.
##
## The Brush tab has a Physics Layer dropdown with three entries, and a level
## root has `bake_collision_layer_index` beside it. Both end up on the same
## `StaticBody3D`, and nothing in the sweep has ever picked anything but the
## default. A layer is the sort of setting that looks harmless until the player
## drops through the floor -- the level is there, the collision is there, and
## the character controller is simply not looking at that layer.
##
## `spawn` measures the validator against the layer the bake used. This looks at
## the other side: what the bake writes, and what a body with stock settings
## makes of it.


func id() -> String:
	return "collision-layers"


func summary() -> String:
	return "what layer and mask the bake puts world collision on, and who still collides with it"


func run() -> void:
	await _what_the_default_bake_writes()
	await _each_dropdown_entry()
	await _can_a_stock_body_stand_on_it()


## The baked world's collision body, wherever in the container it ended up.
func _first_static_body(node: Node) -> StaticBody3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is StaticBody3D:
			return child
		var found := _first_static_body(child)
		if found:
			return found
	return null


## Whether `validate_spawn()` finds the floor with no mask handed to it, which is
## the case where it has to work the layer out from the level itself.
func _spawn_validator_sees_the_floor(root: Node3D, layer_id: int) -> bool:
	if not root.spawn_system:
		return true
	root.bake_collision_layer_index = _index_of_layer(layer_id)
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	if spawn == null:
		return true
	spawn.global_position = Vector3(0, 1.0, 0)
	var report: Dictionary = root.spawn_system.validate_spawn(spawn, 0)
	var issues: PackedStringArray = report.get("issues", PackedStringArray())
	for line in issues:
		if str(line).to_lower().contains("floating"):
			return false
	return true


## The 1-based index behind a layer bit, which is what the level stores.
func _index_of_layer(layer_id: int) -> int:
	for i in range(1, 33):
		if (1 << (i - 1)) == layer_id:
			return i
	return 1


func _bodies(node: Node, out: Array) -> Array:
	if node is StaticBody3D or node is Area3D or node is CharacterBody3D:
		out.append(node)
	for c in node.get_children():
		_bodies(c, out)
	return out


func _describe(container: Node) -> Array:
	var out: Array = []
	for b in _bodies(container, []):
		(
			out
			. append(
				{
					"node": b.name,
					"class": b.get_class(),
					"layer": b.collision_layer,
					"mask": b.collision_mask,
				}
			)
		)
	return out


func _room(root: Node3D) -> void:
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, -6))
	box(root, Vector3(0.3, 3, 12), Vector3(-6, 1.5, 0))


func _what_the_default_bake_writes() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		flag("collision-layers: nothing baked")
		return
	var rows := _describe(container)
	note("bake_collision_layer_index default", root.bake_collision_layer_index)
	note("bodies in the default baked container", rows)
	for r in rows:
		if r["class"] == "StaticBody3D" and r["mask"] == r["layer"] and r["mask"] != 0:
			note(
				"world collision is on layer %s and also masks layer %s" % [r["layer"], r["mask"]],
				(
					"a StaticBody3D never moves, so its mask buys nothing and only widens the "
					+ "broadphase; the value matters because it is copied from the layer"
				)
			)


## The Brush tab offers Static World (1), Debris/Prop (2) and Trigger Only (4).
## Each one is handed to `bake()` as `collision_layer_mask` and lands on both
## properties of the body.
func _each_dropdown_entry() -> void:
	for entry in [[1, "Static World"], [2, "Debris/Prop"], [4, "Trigger Only"]]:
		var root: Node3D = await fresh_root()
		root.auto_spawn_player = false
		_room(root)
		await root.bake(false, false, int(entry[0]), 0)
		await frame()
		var container := root.get_node_or_null("BakedGeometry")
		note(
			"dropdown '%s' (mask %s)" % [entry[1], entry[0]],
			_describe(container) if container else "nothing baked"
		)


func _can_a_stock_body_stand_on_it() -> void:
	# The check that matters: a CharacterBody3D straight out of Godot has
	# collision_mask = 1. Does it land on the floor the mapper baked?
	#
	# Each case gets its own root *and* frees it before the next one, because a
	# root left in the tree leaves its collision in the shared physics space: the
	# first run of this read "the floor is there" three times over, and what the
	# ray had actually found was the previous case's floor sitting in the same
	# place on layer 1.
	var slot := 0
	for entry in [[1, "Static World"], [2, "Debris/Prop"], [4, "Trigger Only"]]:
		# Each case sits 100 units from the last. A freed root's collision does not
		# leave the physics space on the frame `queue_free()` is called, so three
		# floors at the origin read as one floor on layer 1 whatever the bake did.
		var here := Vector3(slot * 100.0, 0, 0)
		slot += 1
		var root: Node3D = await fresh_root()
		box(root, Vector3(12, 0.4, 12), here + Vector3(0, -0.2, 0))
		await root.bake(false, false, int(entry[0]), 0)
		await frame()
		# The live draft brushes keep their own picking collision on layer 1, and a
		# game never sees them -- drop them, or the ray measures the editor.
		if root.draft_brushes_node:
			for child in root.draft_brushes_node.get_children():
				root.draft_brushes_node.remove_child(child)
				child.queue_free()
		await frame()
		await frame()
		note("'%s': the baked body" % entry[1], _describe(root.get_node_or_null("BakedGeometry")))
		var space := root.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.new()
		q.from = here + Vector3(0, 4, 0)
		q.to = here + Vector3(0, -4, 0)
		q.collision_mask = 1  # what a stock CharacterBody3D looks for
		var hit: Dictionary = space.intersect_ray(q)
		q.collision_mask = 0xFFFFFFFF
		var any: Dictionary = space.intersect_ray(q)
		note(
			"  a ray with the stock mask of 1 finds it",
			(
				"%s (%s)"
				% [not hit.is_empty(), hit.get("collider").name if hit.has("collider") else "-"]
			)
		)
		note(
			"  the same ray against every layer finds it",
			(
				"%s (%s, layer %s)"
				% [
					not any.is_empty(),
					any.get("collider").name if any.has("collider") else "-",
					any.get("collider").collision_layer if any.has("collider") else "-",
				]
			)
		)
		# Layer 2 and layer 4 really are layers nothing stock looks at - that is what
		# a layer is, and the mapper is allowed to choose one. What is worth
		# checking is whether they are left to find out on their own: a baked body
		# should not be masked against itself, and the spawn validator should look
		# at the layer the level actually baked onto rather than assuming layer 1.
		var baked_body: StaticBody3D = _first_static_body(root.get_node_or_null("BakedGeometry"))
		if baked_body and baked_body.collision_mask != 0:
			flag(
				"a baked static body masks against layer %d" % baked_body.collision_mask,
				(
					"It never moves, so a mask buys it nothing and only widens the "
					+ "broadphase. Copying the layer into it also means the Physics Layer "
					+ "dropdown moves two things at once."
				)
			)
		if not _spawn_validator_sees_the_floor(root, int(entry[0])):
			flag(
				"the spawn validator cannot see a floor baked onto the '%s' layer" % entry[1],
				(
					(
						"It falls back to mask 1 when the caller does not say, so a level "
						+ "baked onto layer %d reports its spawn as floating in space rather "
						+ "than naming the layer it is actually on."
					)
					% int(entry[0])
				)
			)
		root.get_parent().remove_child(root)
		root.queue_free()
		await frame()
