@tool
extends SceneTree

## Entry point for the exploratory ("vibe") scenarios. See `tools/vibe/README.md`.
##
##     godot --headless -s res://tools/vibe/hf_vibe_runner.gd --path . -- <ids...>
##
## With no ids it runs every scenario. Exits 1 if anything was flagged, 0
## otherwise -- a scenario that only reproduces already-reported defects still
## exits 0, so the exit code means "something new".
##
## Everything lives on a SceneTree rather than in the GUT suite on purpose: these
## want a real `LevelRoot` with its full subsystem graph, they run operations in
## sequences a unit test would not, and several of them are slow. They are a
## sweep you run deliberately, not a gate on every commit.

const SCENARIOS: Array[String] = [
	"res://tools/vibe/scenarios/geometry.gd",
	"res://tools/vibe/scenarios/round_trip.gd",
	"res://tools/vibe/scenarios/map_io.gd",
	"res://tools/vibe/scenarios/displacement.gd",
	"res://tools/vibe/scenarios/limits.gd",
	"res://tools/vibe/scenarios/chaos.gd",
	"res://tools/vibe/scenarios/cost.gd",
	"res://tools/vibe/scenarios/transform.gd",
	"res://tools/vibe/scenarios/structures.gd",
	"res://tools/vibe/scenarios/cutting.gd",
	"res://tools/vibe/scenarios/entities.gd",
	"res://tools/vibe/scenarios/appearance.gd",
	"res://tools/vibe/scenarios/persistence.gd",
	"res://tools/vibe/scenarios/housekeeping.gd",
	"res://tools/vibe/scenarios/terrain.gd",
	"res://tools/vibe/scenarios/vertex.gd",
	"res://tools/vibe/scenarios/prefabs.gd",
	"res://tools/vibe/scenarios/validation.gd",
	"res://tools/vibe/scenarios/settings.gd",
	"res://tools/vibe/scenarios/groups.gd",
	"res://tools/vibe/scenarios/materials.gd",
	"res://tools/vibe/scenarios/bake.gd",
	"res://tools/vibe/scenarios/previews.gd",
	"res://tools/vibe/scenarios/cordon.gd",
	"res://tools/vibe/scenarios/spawn.gd",
	"res://tools/vibe/scenarios/lifecycle.gd",
	"res://tools/vibe/scenarios/placement.gd",
	"res://tools/vibe/scenarios/definitions.gd",
	"res://tools/vibe/scenarios/operations.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var wanted := PackedStringArray(OS.get_cmdline_user_args())
	var selected: Array = []
	for path in SCENARIOS:
		var script = load(path)
		if script == null or not script.can_instantiate():
			# A scenario with a parse error loads as null, and calling new() on
			# that takes the whole sweep down with it. Say which one and carry on.
			print("could not load %s -- see the errors above" % path)
			continue
		var scenario = script.new(self)
		if wanted.is_empty() or wanted.has(scenario.id()):
			selected.append(scenario)

	if selected.is_empty():
		print("no scenarios matched %s" % wanted)
		print("available: %s" % _all_ids())
		quit(2)
		return

	var flagged := 0
	var known := 0
	for scenario in selected:
		print("")
		print("=== %s: %s" % [scenario.id(), scenario.summary()])
		await scenario.run()
		flagged += scenario.flags.size()
		known += scenario.knowns.size()

	print("")
	print("=== summary")
	for scenario in selected:
		print(
			(
				"  %-14s %2d flagged   %2d known"
				% [scenario.id(), scenario.flags.size(), scenario.knowns.size()]
			)
		)
	print("")
	if flagged > 0:
		print("%d observation(s) flagged for review, %d known defect(s) seen" % [flagged, known])
		for scenario in selected:
			for line in scenario.flags:
				print("  [%s] %s" % [scenario.id(), line])
	else:
		print("nothing new flagged; %d known defect(s) still reproduce" % known)
		for scenario in selected:
			for entry in scenario.knowns:
				print("  [%s] #%d %s" % [scenario.id(), entry[0], entry[1]])

	quit(1 if flagged > 0 else 0)


func _all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for path in SCENARIOS:
		var script = load(path)
		if script != null and script.can_instantiate():
			ids.append(script.new(self).id())
	return ids
