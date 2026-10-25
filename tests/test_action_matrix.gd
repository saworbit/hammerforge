extends "res://tests/support/action_matrix_case.gd"
## The pull request's share of the action matrix (#1648): one try in `SAMPLE`,
## the same ones every time, against `tests/goldens/action_matrix.txt`. The
## nightly run tries the lot (`tests/nightly_matrix/test_action_matrix_long.gd`).


func test_the_baseline_covers_every_brush_and_face(folder = use_parameters(folders())):
	var level := await load_level(folder)
	var golden := read_golden()
	var missing: Array = []
	for item in items(level):
		if not golden.has("%s/%s" % [folder, item["key"]]):
			missing.append(item["key"])
	assert_eq(
		missing.slice(0, 5),
		[],
		(
			"%d items not in the baseline. Write it with %s=1 on tests/nightly_matrix"
			% [missing.size(), BLESS_ENV]
		)
	)
	await _drop(level)


func test_the_sampled_tries_do_no_worse_than_the_baseline(folder = use_parameters(folders())):
	var run: Dictionary = await run_matrix(folder, true)
	assert_gt((run["results"] as Dictionary).size(), 0, "fixture: the sample tries something")
	assert_eq(run["worse"] as Array, [], "%s: worse than the baseline" % folder)
	say_better(run["better"])
