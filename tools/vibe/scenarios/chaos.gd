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
##
## Each step is drawn as data first and then done (#1644): the operation, the
## brushes it picks by their place in the brush list, and its numbers. `taken`
## keeps the list, `replay()` does a list again from a fresh level with no
## random generator, and `tools/vibe/chaos_shrink.gd` cuts a failing list down
## to the steps that matter.

const STEPS := 300
const SEED := 1337

## Stop after this many, so a systemic break does not fill the log with the same
## line three hundred times.
const MAX_PROBLEMS := 8

const OPERATIONS: Array[String] = [
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
const GENERATOR_TYPES: Array[String] = ["stairs", "spiral_stairs", "arch", "dome"]

## The run's length and seed. The vibe run keeps the defaults; the seed tests
## set their own (#1643).
var steps := STEPS
var seed_value := SEED
## What the run ended with, from `HFVibe.outcome()`, plus how many steps
## changed nothing. Empty until the run ends.
var outcome: Dictionary = {}
## Every step the run took, as data, in order.
var taken: Array = []
## The first problem a step found: `{"step": index, "op": name, "problem": text}`,
## or empty.
var first_failure: Dictionary = {}

var _solids_seen := {}


func id() -> String:
	return "chaos"


func summary() -> String:
	return "%d randomised operations, invariants checked after each one" % STEPS


func run() -> void:
	var root: Node3D = await fresh_root()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	taken = []
	first_failure = {}
	_begin()
	var seen := 0
	var unchanged := 0

	for step in range(steps):
		var op: String = OPERATIONS[rng.randi() % OPERATIONS.size()]
		var data := draw(rng, op, _brush_ids(root).size())
		taken.append(data)
		var before := HFVibe.signature(root)
		perform(root, data)
		if HFVibe.signature(root) == before:
			unchanged += 1

		for problem in step_problems(root):
			if first_failure.is_empty():
				first_failure = {"step": step, "op": op, "problem": problem}
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


## Do `list` from a fresh level, checking after each step as a run does, and
## drop the level after. Returns the first problem as `run()` records it, or
## empty when nothing broke.
func replay(list: Array) -> Dictionary:
	var root: Node3D = await fresh_root()
	_begin()
	var found := {}
	for index in list.size():
		var data: Dictionary = list[index]
		perform(root, data)
		var problems := step_problems(root)
		if not problems.is_empty():
			found = {"step": index, "op": str(data.get("op", "")), "problem": problems[0]}
			break
		if index % 40 == 0:
			await frame()
	await drop_root(root)
	return found


## What the checks find after a step. A run or a replay starts with `_begin()`,
## which forgets the solids already read.
func step_problems(root: Node3D) -> Array:
	var problems := HFVibe.check_invariants(root)
	problems.append_array(HFVibe.check_solids(root, _solids_seen))
	return problems


func _begin() -> void:
	_solids_seen = {}


## One step as data: what to do, which brushes by their place in a list of
## `count`, and its numbers. The draws are made in the order the operation
## always made them, so a seed walks the path it always walked.
func draw(rng: RandomNumberGenerator, op: String, count: int) -> Dictionary:
	var data := {"op": op}
	match op:
		"create":
			data["shape"] = rng.randi() % 6
			data["size"] = [rng.randf_range(8, 96), rng.randf_range(8, 96), rng.randf_range(8, 96)]
			data["center"] = [
				rng.randf_range(-300, 300), rng.randf_range(-100, 100), rng.randf_range(-300, 300)
			]
			data["sides"] = 3 + rng.randi() % 12
		"delete", "duplicate", "to_floor":
			if count > 0:
				data["pick"] = rng.randi() % count
		"nudge":
			if count > 0:
				data["pick"] = rng.randi() % count
				data["offset"] = [rng.randf_range(-32, 32), 0.0, rng.randf_range(-32, 32)]
		"hollow":
			if count > 0:
				data["pick"] = rng.randi() % count
				data["thickness"] = rng.randf_range(1, 20)
		"clip":
			if count > 0:
				var normal := [
					rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)
				]
				data["normal"] = normal
				if _vector(normal).length() > 0.01:
					data["pick"] = rng.randi() % count
					data["distance"] = rng.randf_range(-50, 50)
		"merge":
			if count > 2:
				data["picks"] = [0, 1]
		"generate":
			data["type"] = GENERATOR_TYPES[rng.randi() % GENERATOR_TYPES.size()]
			data["position"] = [rng.randf_range(-400, 400), 0.0, rng.randf_range(-400, 400)]
		"rotate", "flip":
			if count > 0:
				data["pick"] = rng.randi() % count
				data["axis"] = rng.randi() % 3
	return data


## Do one step. A pick is a place in the brush list, wrapped round when a replay
## has fewer brushes than the run had.
func perform(root: Node3D, data: Dictionary) -> void:
	var ids := _brush_ids(root)
	var picked := ""
	if data.has("pick"):
		if ids.is_empty():
			return
		picked = str(ids[int(data["pick"]) % ids.size()])
	match str(data.get("op", "")):
		"create":
			(
				root
				. create_brush_from_info(
					{
						"shape": int(data["shape"]),
						"size": _vector(data["size"]),
						"center": _vector(data["center"]),
						"sides": int(data["sides"]),
					}
				)
			)
		"delete":
			if picked != "":
				root.delete_brushes_by_id([picked])
		"duplicate":
			if picked != "":
				var node = root.brush_system.find_brush_by_id(picked)
				if node:
					root.duplicate_brush(node)
		"nudge":
			if picked != "":
				root.nudge_brushes_by_id([picked], _vector(data["offset"]))
		"hollow":
			if picked != "":
				root.hollow_brush_by_id(picked, float(data["thickness"]))
		"clip":
			if picked != "":
				root.brush_system.clip_brush_by_plane(
					picked, Plane(_vector(data["normal"]).normalized(), float(data["distance"]))
				)
		"merge":
			if data.has("picks") and ids.size() > 2:
				root.brush_system.merge_brushes_by_ids([ids[0], ids[1]])
		"generate":
			root.create_generator(
				str(data["type"]), {}, Transform3D(Basis(), _vector(data["position"]))
			)
		"rotate":
			if picked != "":
				root.rotate_managed_nodes([picked], [], int(data["axis"]), 90.0, Vector3.ZERO)
		"flip":
			if picked != "":
				root.flip_managed_nodes([picked], [], int(data["axis"]), Vector3.ZERO)
		"to_floor":
			if picked != "":
				root.brush_system.move_brushes_to_floor([picked])
		"snapshot":
			root.restore_state(root.capture_state())


func _brush_ids(root: Node3D) -> Array:
	var ids: Array = []
	for b in root.draft_brushes_node.get_children():
		ids.append(str(b.get_meta("brush_id", "")))
	return ids


static func _vector(values: Variant) -> Vector3:
	var list: Array = values if values is Array else [0, 0, 0]
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
