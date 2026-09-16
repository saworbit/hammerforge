@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Randomised editing with the level pushed through a round trip at random
## points, and the two sides diffed.
##
## `chaos` checks structural invariants after each operation. `chaos-systems`
## does the same for the registries. This asks a different question: after an
## arbitrary sequence of edits, does the level still survive being saved and
## loaded, captured and restored, and exported and re-imported? Data loss is
## silent by construction -- every one of those reports success and the level is
## just poorer afterwards -- so the only way to see it is to diff.
##
## Each round trip starts from wherever the last one left off, so a defect that
## only shows up on a level that has been through one already has somewhere to
## appear.

const STEPS := 220
const SEED := 20260916
const ROUND_TRIP_EVERY := 20
const MAX_PROBLEMS := 10


func id() -> String:
	return "chaos-io"


func summary() -> String:
	return (
		"%d randomised edits with a save/load, a state round trip and a .map round trip along the way"
		% STEPS
	)


func run() -> void:
	var root: Node3D = await fresh_root()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var problems := 0
	var trips := 0

	var operations: Array[String] = [
		"create",
		"create_round",
		"delete",
		"duplicate",
		"nudge",
		"resize",
		"rotate",
		"material",
		"uv",
		"entity",
		"wire",
		"visgroup",
		"group",
		"paint",
		"generator",
	]

	for step in range(STEPS):
		var op: String = operations[rng.randi() % operations.size()]
		_apply(root, rng, op)
		if step % ROUND_TRIP_EVERY != ROUND_TRIP_EVERY - 1:
			continue
		if problems >= MAX_PROBLEMS:
			note("stopping the round trips", "%d problems already reported" % problems)
			break
		trips += 1
		await frame()
		var which := trips % 3
		if which == 0:
			problems += await _hflevel_trip(root, step)
		elif which == 1:
			problems += _state_trip(root, step)
		else:
			problems += await _map_trip(root, step)

	note("steps", STEPS)
	note("round trips run", trips)
	note("final level", HFVibe.describe_level(root))
	for problem in HFVibe.check_invariants(root):
		flag("invariant at the end of the run", problem)


## A save and a load, into a second root, diffed against the first.
func _hflevel_trip(root: Node3D, step: int) -> int:
	var before: Dictionary = HFVibe.describe_level(root)
	var path := "user://vibe_chaos_io.hflevel"
	root.save_hflevel(path)
	var settled: bool = await HFVibe.settle_save(_tree, root)
	if not settled:
		flag("step %d: the save never settled" % step)
		return 1
	var loaded: Node3D = await fresh_root("ChaosLoad%d" % step)
	var ok: bool = loaded.load_hflevel(path)
	await frame()
	if not ok:
		flag(
			"step %d: a level this run built will not load back" % step, "save_hflevel reported OK"
		)
		return 1
	var after: Dictionary = HFVibe.describe_level(loaded)
	var count_before: int = flags.size()
	# `materials` is #617: a material built in the session has no resource_path,
	# and the encoder writes a Resource as its path or as null.
	diff_levels(before, after, "step %d: .hflevel round trip" % step, {"materials": 617})
	var added: int = flags.size() - count_before
	if added == 0:
		note(
			"step %d: .hflevel round trip clean" % step,
			"%s brushes" % before.get("brush_count", "?")
		)
	loaded.queue_free()
	return added


## capture_state / restore_state, which is the undo path.
func _state_trip(root: Node3D, step: int) -> int:
	var before: Dictionary = HFVibe.describe_level(root)
	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	var after: Dictionary = HFVibe.describe_level(root)
	var count_before: int = flags.size()
	diff_levels(before, after, "step %d: capture/restore" % step)
	var added: int = flags.size() - count_before
	if added == 0:
		note("step %d: capture/restore clean" % step, "%s brushes" % before.get("brush_count", "?"))
	return added


## A `.map` export and re-import. Only the parts `.map` claims to carry are
## compared -- the format has no paint layers, no visgroups and no materials
## palette, and reporting those as losses every time would bury a real one.
func _map_trip(root: Node3D, step: int) -> int:
	var path := "user://vibe_chaos_io.map"
	var err: int = root.export_map(path, "valve220")
	if err != OK:
		flag("step %d: .map export failed" % step, err)
		return 1
	var before_brushes: int = root.draft_brushes_node.get_child_count()
	var before_entities: int = root.entities_node.get_child_count()
	var imported: Node3D = await fresh_root("ChaosMap%d" % step)
	var count: int = imported.import_map(path)
	await frame()
	var after_brushes: int = imported.draft_brushes_node.get_child_count()
	var after_entities: int = imported.entities_node.get_child_count()
	note(
		"step %d: .map round trip" % step,
		(
			"%d brushes -> %d, %d entities -> %d (import returned %s)"
			% [before_brushes, after_brushes, before_entities, after_entities, count]
		)
	)
	var added := 0
	if after_brushes < before_brushes:
		flag(
			(
				"step %d: the .map round trip lost %d brush(es)"
				% [step, before_brushes - after_brushes]
			),
			"%d out, %d back" % [before_brushes, after_brushes]
		)
		added += 1
	if after_entities < before_entities:
		flag(
			(
				"step %d: the .map round trip lost %d entit(y/ies)"
				% [step, before_entities - after_entities]
			),
			"%d out, %d back" % [before_entities, after_entities]
		)
		added += 1
	imported.queue_free()
	return added


func _brush_ids(root: Node3D) -> Array:
	var ids: Array = []
	if root.draft_brushes_node:
		for b in root.draft_brushes_node.get_children():
			var id := str(b.get_meta("brush_id", ""))
			if id != "":
				ids.append(id)
	return ids


func _apply(root: Node3D, rng: RandomNumberGenerator, op: String) -> void:
	var ids: Array = _brush_ids(root)
	match op:
		"create":
			box(
				root,
				Vector3(
					rng.randi_range(1, 4) * 32.0,
					rng.randi_range(1, 4) * 32.0,
					rng.randi_range(1, 4) * 32.0
				),
				Vector3(
					rng.randi_range(-8, 8) * 64.0,
					rng.randi_range(0, 4) * 64.0,
					rng.randi_range(-8, 8) * 64.0
				)
			)
		"create_round":
			(
				root
				. create_brush_from_info(
					{
						"shape": rng.randi_range(1, 3),
						"size": Vector3(64, 64, 64),
						"center":
						Vector3(rng.randi_range(-6, 6) * 64.0, 32, rng.randi_range(-6, 6) * 64.0),
						"sides": rng.randi_range(3, 12),
					}
				)
			)
		"delete":
			if not ids.is_empty():
				root.delete_brush_by_id(ids[rng.randi() % ids.size()])
		"duplicate":
			if not ids.is_empty():
				var src_b = root.find_brush_by_id(ids[rng.randi() % ids.size()])
				if src_b:
					root.duplicate_brush(src_b)
		"nudge":
			if not ids.is_empty():
				var b = root.find_brush_by_id(ids[rng.randi() % ids.size()])
				if b:
					b.global_position += Vector3(
						rng.randi_range(-2, 2) * 16.0, 0, rng.randi_range(-2, 2) * 16.0
					)
		"resize":
			if not ids.is_empty():
				var b = root.find_brush_by_id(ids[rng.randi() % ids.size()])
				if b:
					b.size = Vector3(
						rng.randi_range(1, 6) * 16.0,
						rng.randi_range(1, 6) * 16.0,
						rng.randi_range(1, 6) * 16.0
					)
		"rotate":
			if not ids.is_empty():
				root.rotate_managed_nodes(
					[ids[rng.randi() % ids.size()]],
					[],
					rng.randi_range(0, 2),
					float(rng.randi_range(1, 3)) * 90.0,
					Vector3.ZERO
				)
		"material":
			if root.material_manager and root.material_manager.materials.size() < 6:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(rng.randf(), rng.randf(), rng.randf())
				root.material_manager.add_material(mat)
			if not ids.is_empty() and root.material_manager.materials.size() > 0:
				var b = root.find_brush_by_id(ids[rng.randi() % ids.size()])
				if b and b.get("faces") is Array and not b.faces.is_empty():
					var f = b.faces[rng.randi() % b.faces.size()]
					f.material_idx = rng.randi() % root.material_manager.materials.size()
		"uv":
			if not ids.is_empty():
				var b = root.find_brush_by_id(ids[rng.randi() % ids.size()])
				if b and b.get("faces") is Array and not b.faces.is_empty():
					var f = b.faces[rng.randi() % b.faces.size()]
					f.uv_scale = Vector2(
						float(rng.randi_range(1, 8)) * 0.25, float(rng.randi_range(1, 8)) * 0.25
					)
					f.uv_offset = Vector2(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
					f.uv_rotation = float(rng.randi_range(0, 3)) * 45.0
		"entity":
			(
				root
				. _restore_entity_from_info(
					{
						"entity_type":
						["player_start", "light_point", "door_basic"][rng.randi() % 3],
						"entity_class":
						["player_start", "light_point", "door_basic"][rng.randi() % 3],
						"transform":
						Transform3D(
							Basis.IDENTITY,
							Vector3(rng.randi_range(-6, 6) * 64.0, 0, rng.randi_range(-6, 6) * 64.0)
						),
						"properties": {},
						"name": "ent_%d" % rng.randi_range(0, 9999),
						"entity_name": "ent_%d" % rng.randi_range(0, 9999),
					}
				)
			)
		"wire":
			var entities: Array = root.entities_node.get_children()
			if entities.size() >= 2:
				var src = entities[rng.randi() % entities.size()]
				var dst = entities[rng.randi() % entities.size()]
				root.add_entity_output(
					src,
					["OnTrigger", "OnPressed", "OnUse"][rng.randi() % 3],
					str(dst.get_meta("entity_name", dst.name)),
					["Open", "Toggle", "TurnOn"][rng.randi() % 3],
					"",
					float(rng.randi_range(0, 3)),
					rng.randi() % 2 == 0
				)
		"visgroup":
			var vg := "vg_%d" % rng.randi_range(0, 3)
			root.create_visgroup(vg)
			if not ids.is_empty():
				var b = root.find_brush_by_id(ids[rng.randi() % ids.size()])
				if b:
					root.add_selection_to_visgroup(vg, [b])
		"group":
			if ids.size() >= 2:
				var a = root.find_brush_by_id(ids[0])
				var b2 = root.find_brush_by_id(ids[1])
				if a and b2:
					root.group_selection("grp_%d" % rng.randi_range(0, 3), [a, b2])
		"paint":
			if root.paint_layers and root.paint_tool:
				var layer: int = root.paint_layers.active_layer_index
				if root.paint_layers.layers.size() > layer and layer >= 0:
					var l = root.paint_layers.layers[layer]
					if l and l.has_method("set_cell"):
						l.set_cell(Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8)), true)
		"generator":
			if root.generator_system:
				(
					root
					. create_generator(
						"stairs",
						{
							"steps": rng.randi_range(3, 10),
							"step_height": 16.0,
							"step_depth": 32.0,
							"width": 96.0,
						},
						Transform3D(
							Basis.IDENTITY,
							Vector3(
								rng.randi_range(-4, 4) * 128.0, 0, rng.randi_range(-4, 4) * 128.0
							)
						)
					)
				)
