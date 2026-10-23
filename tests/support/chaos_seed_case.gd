extends GutTest
## One chaos scenario from one seed, checked after every step and against the
## line recorded for that seed (#1643).
##
## The scenario flags any invariant a step breaks, naming the step and the
## operation, and each flag fails the seed. At the end its outcome is compared
## with `tests/goldens/chaos.json`. Any change fails, better or worse, since a
## run that breaks nothing can still end somewhere new.
##
## To accept a change, set HF_GOLDENS_BLESS to why it changed and run the seeds
## again. That rewrites only the seeds that moved and adds the reason to the
## file's notes. A blank reason is refused.

const HFChaosGoldens = preload("res://tests/support/chaos_goldens.gd")

## Steps a seed runs in pull request CI. The recorded lines are for this many.
const STEPS := 60
const BLESS_ENV := "HF_GOLDENS_BLESS"
const ACCEPT := (
	"If the change is right, set HF_GOLDENS_BLESS to why it changed and run"
	+ " godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gselect=chaos -gexit"
)


## Run one seed and drop what it built. Returns its flags and its outcome.
func run_seed(scenario_path: String, seed_value: int, steps: int = STEPS) -> Dictionary:
	var tree := get_tree()
	var before: Array = tree.root.get_children()
	var scenario = load(scenario_path).new(tree)
	scenario.steps = steps
	scenario.seed_value = seed_value
	await scenario.run()
	for child in tree.root.get_children():
		if not before.has(child):
			tree.root.remove_child(child)
			child.queue_free()
	await tree.process_frame
	return {"flags": scenario.flags, "outcome": scenario.outcome}


func check_seed(scenario_path: String, scenario: String, seed_value: int) -> void:
	var run := await run_seed(scenario_path, seed_value)
	for line in run["flags"]:
		fail_test("%s seed %d: %s" % [scenario, seed_value, line])
	var line := HFChaosGoldens.rounded(run["outcome"])
	var goldens := HFChaosGoldens.new()
	if OS.has_environment(BLESS_ENV):
		var reason := OS.get_environment(BLESS_ENV).strip_edges()
		if reason == "":
			fail_test("%s is set but empty. Say why the seeds changed." % BLESS_ENV)
			return
		goldens.bless(scenario, seed_value, line, reason)
		pass_test("%s seed %d recorded" % [scenario, seed_value])
		return
	var recorded := goldens.recorded(scenario, seed_value)
	if recorded.is_empty():
		fail_test("%s seed %d has no recorded line. %s" % [scenario, seed_value, ACCEPT])
		return
	var moved := HFChaosGoldens.differences(recorded, line)
	assert_true(
		moved.is_empty(),
		"%s seed %d ended somewhere new: %s. %s" % [scenario, seed_value, ", ".join(moved), ACCEPT]
	)
