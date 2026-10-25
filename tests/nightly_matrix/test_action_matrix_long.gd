extends "res://tests/support/action_matrix_case.gd"
## Every try of the action matrix (#1648), against the baseline. With
## HF_MATRIX_BLESS=1 it writes the baseline instead, from every level.

## Where a blessing run says why each failing try failed, for whoever files them.
const FAILURES := "user://action_matrix_failures.txt"

var _blessed := {}
var _failed: Array = []


func after_all() -> void:
	if blessing() and not _blessed.is_empty():
		write_golden(_blessed)
		var file := FileAccess.open(FAILURES, FileAccess.WRITE)
		file.store_string("\n".join(_failed) + "\n")
		file.close()
		gut.p("Wrote %s, %d lines" % [GOLDEN, _blessed.size()])


func test_every_try_does_no_worse_than_the_baseline(folder = use_parameters(folders())):
	var run: Dictionary = await run_matrix(folder, false)
	if blessing():
		_blessed.merge(run["results"], true)
		_failed.append_array(run["failed"])
		pass_test("%s: blessed" % folder)
		return
	assert_eq(run["worse"] as Array, [], "%s: worse than the baseline" % folder)
	say_better(run["better"])
