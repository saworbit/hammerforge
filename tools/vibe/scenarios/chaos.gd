@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## A long randomised sequence of ordinary operations, with the structural
## invariants checked after every single step.
##
## The value is in the sequences nobody writes a test for: hollow a brush that
## was already clipped, flip a piece of a carve, restore a state captured
## mid-array. The seed is fixed so a break is reproducible; change it (or pass a
## different one) to explore elsewhere.
##
## Checking invariants after *every* step rather than at the end is deliberate --
## it names the operation that broke them, which is most of the debugging.

const STEPS := 300
const SEED := 1337

## Stop after this many, so a systemic break does not fill the log with the same
## line three hundred times.
const MAX_PROBLEMS := 8

## The run's length and seed. The vibe run keeps the defaults; the seed tests
## set their own (#1643).
var steps := STEPS
var seed_value := SEED
## What the run ended with, from `HFVibe.outcome()`, plus how many steps
## changed nothing. Empty until the run ends.
var outcome: Dictionary = {}


func id() -> String:
	return "chaos"


func summary() -> String:
	return "%d randomised operations, invariants checked after each one" % STEPS


func run() -> void:
	var root: Node3D = await fresh_root()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var operations: Array[String] = [
		"create",
		"delete",
		"duplicate",
		"nudge",
		"hollow",
		"clip",
		"merge",
		"generate",
		"rotate",
		"flip",
		"to_floor",
		"snapshot",
	]
	var seen := 0
	var unchanged := 0
	var solids_seen := {}

	for step in range(steps):
		var op: String = operations[rng.randi() % operations.size()]
		var ids := _brush_ids(root)
		var before := HFVibe.signature(root)
		_apply(root, rng, op, ids)
		if HFVibe.signature(root) == before:
			unchanged += 1

		var problems := HFVibe.check_invariants(root)
		problems.append_array(HFVibe.check_solids(root, solids_seen))
		for problem in problems:
			flag("step %d after '%s'" % [step, op], problem)
			seen += 1
		if seen >= MAX_PROBLEMS:
			note("stopping early", "%d invariant breaks is enough to act on" % seen)
			break
		if step % 40 == 0:
			await frame()

	note("brushes at the end", root.brush_system.get_live_brush_count())
	outcome = HFVibe.outcome(root)
	outcome["unchanged_steps"] = unchanged
	if seen == 0:
		note("no invariant broke across %d operations" % steps)


func _brush_ids(root: Node3D) -> Array:
	var ids: Array = []
	for b in root.draft_brushes_node.get_children():
		ids.append(str(b.get_meta("brush_id", "")))
	return ids


func _pick(rng: RandomNumberGenerator, ids: Array) -> String:
	return str(ids[rng.randi() % ids.size()])


func _apply(root: Node3D, rng: RandomNumberGenerator, op: String, ids: Array) -> void:
	match op:
		"create":
			(
				root
				. create_brush_from_info(
					{
						"shape": rng.randi() % 6,
						"size":
						Vector3(
							rng.randf_range(8, 96), rng.randf_range(8, 96), rng.randf_range(8, 96)
						),
						"center":
						Vector3(
							rng.randf_range(-300, 300),
							rng.randf_range(-100, 100),
							rng.randf_range(-300, 300)
						),
						"sides": 3 + rng.randi() % 12,
					}
				)
			)
		"delete":
			if not ids.is_empty():
				root.delete_brushes_by_id([_pick(rng, ids)])
		"duplicate":
			if not ids.is_empty():
				var node = root.brush_system.find_brush_by_id(_pick(rng, ids))
				if node:
					root.duplicate_brush(node)
		"nudge":
			if not ids.is_empty():
				root.nudge_brushes_by_id(
					[_pick(rng, ids)],
					Vector3(rng.randf_range(-32, 32), 0, rng.randf_range(-32, 32))
				)
		"hollow":
			if not ids.is_empty():
				root.hollow_brush_by_id(_pick(rng, ids), rng.randf_range(1, 20))
		"clip":
			if not ids.is_empty():
				var normal := Vector3(
					rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)
				)
				if normal.length() > 0.01:
					root.brush_system.clip_brush_by_plane(
						_pick(rng, ids), Plane(normal.normalized(), rng.randf_range(-50, 50))
					)
		"merge":
			if ids.size() > 2:
				root.brush_system.merge_brushes_by_ids([ids[0], ids[1]])
		"generate":
			var types: Array[String] = ["stairs", "spiral_stairs", "arch", "dome"]
			root.create_generator(
				types[rng.randi() % types.size()],
				{},
				Transform3D(
					Basis(), Vector3(rng.randf_range(-400, 400), 0, rng.randf_range(-400, 400))
				)
			)
		"rotate":
			if not ids.is_empty():
				root.rotate_managed_nodes(
					[_pick(rng, ids)], [], rng.randi() % 3, 90.0, Vector3.ZERO
				)
		"flip":
			if not ids.is_empty():
				root.flip_managed_nodes([_pick(rng, ids)], [], rng.randi() % 3, Vector3.ZERO)
		"to_floor":
			if not ids.is_empty():
				root.brush_system.move_brushes_to_floor([_pick(rng, ids)])
		"snapshot":
			root.restore_state(root.capture_state())
