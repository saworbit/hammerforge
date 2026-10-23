extends RefCounted
## Cut a failing `chaos` run down to the steps that matter (#1644).
##
## Delta debugging: drop halves of the list, then quarters, and so on down to
## single steps, replaying each shorter list from a fresh level, and keep a cut
## whenever the same problem still happens. Numbers are masked when problems are
## compared, so "brush 41" and "brush 7" read alike. It stops when no single
## step can go, or when `budget_ms` runs out, and either way hands back the
## shortest list it found.
##
## `tools/vibe/shrink_chaos.gd` runs it from the command line and writes the
## result to `tests/regressions/`, which `tests/test_chaos_regressions.gd`
## replays in every run.

const REGRESSIONS_DIR := "res://tests/regressions"
const BUDGET_MS := 300000

## A chaos scenario, which does the replays.
var scenario = null
var budget_ms := BUDGET_MS
## The time in milliseconds. Tests set their own.
var clock := Callable()
## True when the last shrink stopped at its budget.
var capped := false
## How many replays the last shrink made.
var tries := 0


func _init(chaos_scenario = null, budget: int = BUDGET_MS) -> void:
	scenario = chaos_scenario
	budget_ms = budget


## A problem with every number masked.
static func masked(problem: String) -> String:
	return RegEx.create_from_string("[0-9]+(\\.[0-9]+)?").sub(problem, "N", true)


## The shortest list found that still fails as `problem` does. Steps after the
## one that failed are dropped first; they cannot matter.
func shrink(list: Array, problem: String, failed_at: int = -1) -> Array:
	var started := _now()
	capped = false
	tries = 0
	var current := list.slice(0, failed_at + 1) if failed_at >= 0 else list.duplicate()
	var parts := 2
	while current.size() >= 2:
		var chunk := ceili(float(current.size()) / parts)
		var cut := false
		var start := 0
		while start < current.size():
			if _now() - started >= budget_ms:
				capped = true
				return current
			var candidate := current.slice(0, start) + current.slice(start + chunk)
			if await _fails_the_same(candidate, problem):
				current = candidate
				parts = maxi(parts - 1, 2)
				cut = true
				break
			start += chunk
		if cut:
			continue
		if parts >= current.size():
			break
		parts = mini(parts * 2, current.size())
	return current


func _fails_the_same(list: Array, problem: String) -> bool:
	tries += 1
	var found: Dictionary = await scenario.replay(list)
	return not found.is_empty() and masked(str(found["problem"])) == masked(problem)


## Write a shrunk case where the regression test replays it. Returns its path.
static func record(
	seed_value: int, step: int, problem: String, list: Array, was_capped: bool, folder := ""
) -> String:
	var dir := folder if folder != "" else REGRESSIONS_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join("chaos_%d_%d.json" % [seed_value, step])
	var data := {
		"scenario": "chaos",
		"seed": seed_value,
		"step": step,
		"problem": masked(problem),
		"capped": was_capped,
		"steps": list,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t", false, true) + "\n")
		file.close()
	return path


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()
