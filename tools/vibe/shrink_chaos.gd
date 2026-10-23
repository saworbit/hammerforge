extends SceneTree
## Run `chaos` from one seed, and when a step breaks something, cut the run down
## to the steps that matter and write it to `tests/regressions/` (#1644).
##
## Usage:
##   godot --headless -s res://tools/vibe/shrink_chaos.gd --path . -- <seed> [steps] [budget seconds]
##
## The file replays in every GUT run from then on. While the bug it shows is
## open, add `"known": "#<issue>: <why>"` to it.

const ChaosScenario = preload("res://tools/vibe/scenarios/chaos.gd")
const ChaosShrink = preload("res://tools/vibe/chaos_shrink.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].is_valid_int():
		print(
			"Usage: godot --headless -s res://tools/vibe/shrink_chaos.gd --path . -- <seed> [steps] [budget seconds]"
		)
		quit(2)
		return
	var scenario = ChaosScenario.new(self)
	scenario.seed_value = int(args[0])
	if args.size() > 1:
		scenario.steps = int(args[1])
	await scenario.run()
	if scenario.first_failure.is_empty():
		print("Seed %d ran %d steps with nothing broken." % [scenario.seed_value, scenario.steps])
		quit(0)
		return
	var failure: Dictionary = scenario.first_failure
	print("Step %d after '%s': %s" % [failure["step"], failure["op"], failure["problem"]])
	var budget := int(args[2]) * 1000 if args.size() > 2 else ChaosShrink.BUDGET_MS
	var shrinker = ChaosShrink.new(scenario, budget)
	var shrunk: Array = await shrinker.shrink(
		scenario.taken, str(failure["problem"]), int(failure["step"])
	)
	var path: String = ChaosShrink.record(
		scenario.seed_value, int(failure["step"]), str(failure["problem"]), shrunk, shrinker.capped
	)
	print(
		(
			"Shrunk to %d step%s in %d replays%s. Wrote %s"
			% [
				shrunk.size(),
				"" if shrunk.size() == 1 else "s",
				shrinker.tries,
				", stopped at the time cap" if shrinker.capped else "",
				path
			]
		)
	)
	quit(1)
