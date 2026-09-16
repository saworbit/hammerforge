@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The other half of `chaos`: a long randomised sequence over the registries
## rather than over the brushes, with the bookkeeping checked after every step.
##
## `chaos` moves geometry about and checks that the brushes stay coherent. This
## one adds and removes the things that *point at* brushes -- visgroups, groups,
## prefab instances, generators, entities, paint layers and the face selection --
## and checks after each step that nothing is left pointing at something that is
## no longer there. That is where a registry leak shows up: not when the entry
## is made, but two operations later when its subject has gone.

const STEPS := 260
const SEED := 20260916
const MAX_PROBLEMS := 10


func id() -> String:
	return "chaos-systems"


func summary() -> String:
	return "%d randomised registry operations, with dangling references checked after each" % STEPS


func run() -> void:
	var root: Node3D = await fresh_root("ChaosSystems")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# Something to point at before anything starts pointing.
	for i in range(6):
		box(root, Vector3(32, 32, 32), Vector3(float(i) * 64.0, 0, 0))
	await frame()

	var operations: Array[String] = [
		"create_brush",
		"delete_brush",
		"visgroup_create",
		"visgroup_assign",
		"visgroup_delete",
		"group_create",
		"group_delete",
		"entity_add",
		"entity_delete",
		"paint_layer_add",
		"paint_layer_remove",
		"face_select",
		"generate",
		"snapshot",
		"restore",
	]
	var seen := 0
	var snapshot: Dictionary = {}

	for step in range(STEPS):
		var op: String = operations[rng.randi() % operations.size()]
		snapshot = await _apply(root, rng, op, snapshot)
		var problems: Array = HFVibe.check_invariants(root)
		problems.append_array(_registry_problems(root))
		for problem in problems:
			flag("step %d after '%s'" % [step, op], problem)
			seen += 1
		if seen >= MAX_PROBLEMS:
			note("stopping early", "%d problems is enough to act on" % seen)
			break
		if step % 30 == 0:
			await frame()

	note("brushes at the end", root.brush_system.get_live_brush_count())
	note("visgroups at the end", root.get_visgroup_names().size())
	note("entities at the end", root.get_entity_count())
	note("paint layers at the end", root.paint_layers.layers.size() if root.paint_layers else 0)
	if seen == 0:
		note("no registry pointed at anything missing across %d operations" % STEPS)


func _live_ids(root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	if root.draft_brushes_node:
		for b in root.draft_brushes_node.get_children():
			out[str(b.get_meta("brush_id", ""))] = true
	return out


## Every registry entry whose subject is no longer in the level.
func _registry_problems(root: Node3D) -> Array:
	var problems: Array = []
	var live: Dictionary = _live_ids(root)

	# Face selection is keyed by brush id and outlives nothing.
	var selection = root.get("face_selection")
	if selection is Dictionary:
		for key in (selection as Dictionary).keys():
			if not live.has(str(key)):
				problems.append("face_selection holds %s, which is not a live brush" % str(key))

	# A generator record naming brushes that have gone is documented as a hint
	# rather than a guarantee, so only a record with *no* surviving piece counts.
	if root.generator_system:
		for gid in root.generator_system.generators.keys():
			var record = root.generator_system.generators[gid]
			var alive := 0
			for bid in record.brush_ids:
				if live.has(str(bid)):
					alive += 1
			if alive == 0 and not record.brush_ids.is_empty():
				problems.append("generator %s has no surviving piece and is still on file" % gid)

	# Paint layer ids must stay unique: the id is identity, not a label.
	if root.paint_layers:
		var ids: Dictionary = {}
		for layer in root.paint_layers.layers:
			if layer == null:
				problems.append("paint layer list holds a null")
				continue
			var lid := str(layer.layer_id)
			if ids.has(lid):
				problems.append("two paint layers share the id %s" % lid)
			ids[lid] = true
		var idx: int = root.paint_layers.active_layer_index
		var count: int = root.paint_layers.layers.size()
		if count > 0 and (idx < 0 or idx >= count):
			problems.append("active paint layer index %d is outside a list of %d" % [idx, count])

	# Entities: the node name and the authored name are two addresses for one
	# node, and both have to resolve to something that is still in the tree.
	if root.entity_system:
		var index: Dictionary = root.entity_system.build_name_index()
		for name_str in index.keys():
			for node in index[name_str]:
				if node == null or not is_instance_valid(node) or not node.is_inside_tree():
					problems.append("name index still answers %s with a freed node" % name_str)
	return problems


func _pick(rng: RandomNumberGenerator, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[rng.randi() % items.size()]


func _apply(
	root: Node3D, rng: RandomNumberGenerator, op: String, snapshot: Dictionary
) -> Dictionary:
	var ids: Array = _live_ids(root).keys()
	match op:
		"create_brush":
			(
				root
				. create_brush_from_info(
					{
						"shape": rng.randi() % 6,
						"size":
						Vector3(
							rng.randf_range(8, 64), rng.randf_range(8, 64), rng.randf_range(8, 64)
						),
						"center":
						Vector3(
							rng.randf_range(-256, 256),
							rng.randf_range(-64, 64),
							rng.randf_range(-256, 256)
						),
					}
				)
			)
		"delete_brush":
			var victim = _pick(rng, ids)
			if victim != null:
				root.delete_brushes_by_id([str(victim)])
		"visgroup_create":
			root.create_visgroup("vg_%d" % (rng.randi() % 5))
		"visgroup_assign":
			var names: Array = Array(root.get_visgroup_names())
			var target = _pick(rng, names)
			var brush = _pick(rng, ids)
			if target != null and brush != null:
				var node2 = root.find_brush_by_id(str(brush))
				if node2:
					root.add_selection_to_visgroup(str(target), [node2])
		"visgroup_delete":
			var names2: Array = Array(root.get_visgroup_names())
			var doomed = _pick(rng, names2)
			if doomed != null:
				root.remove_visgroup(str(doomed))
		"group_create":
			if ids.size() >= 2:
				var a2 = root.find_brush_by_id(str(ids[0]))
				var b2 = root.find_brush_by_id(str(ids[1]))
				if a2 and b2:
					root.group_selection("grp_%d" % (rng.randi() % 4), [a2, b2])
		"group_delete":
			var brush2 = _pick(rng, ids)
			if brush2 != null:
				var node3 = root.find_brush_by_id(str(brush2))
				if node3:
					root.ungroup_nodes([node3])
		"entity_add":
			var authored := "ent_%d" % (rng.randi() % 6)
			(
				root
				. _restore_entity_from_info(
					{
						"entity_type": "func_button",
						"entity_class": "func_button",
						"transform":
						Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-128, 128), 0, 0)),
						"properties": {},
						"name": authored,
						"entity_name": authored,
					}
				)
			)
		"entity_delete":
			var entities: Array = root.entities_node.get_children() if root.entities_node else []
			var doomed_entity = _pick(rng, entities)
			if doomed_entity != null:
				root.delete_entities_by_paths([doomed_entity.get_path()])
		"paint_layer_add":
			root.paint_system.add_paint_layer()
		"paint_layer_remove":
			root.paint_system.remove_active_paint_layer()
		"face_select":
			var brush3 = _pick(rng, ids)
			if brush3 != null:
				var node = root.find_brush_by_id(str(brush3))
				if node and node.faces.size() > 0:
					root.toggle_face_selection(node, rng.randi() % node.faces.size(), true, false)
		"generate":
			root.generator_system.create(
				"stairs",
				{"steps": 4, "step_height": 8.0, "step_depth": 16.0, "width": 48.0},
				Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-128, 128), 0, 0))
			)
		"snapshot":
			return root.capture_state()
		"restore":
			if not snapshot.is_empty():
				root.restore_state(snapshot)
				await frame()
	return snapshot
