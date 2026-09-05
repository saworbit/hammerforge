extends GutTest
## HFStatusBoard — the red / amber / green evaluation behind the Console.
## evaluate() is pure, so every threshold is checked here without an editor.

const HFStatusBoardType = preload("res://addons/hammerforge/hf_status_board.gd")
const HFConsoleLogType = preload("res://addons/hammerforge/hf_console_log.gd")

const OK := HFStatusBoardType.Severity.OK
const WARN := HFStatusBoardType.Severity.WARN
const PROBLEM := HFStatusBoardType.Severity.PROBLEM
const UNKNOWN := HFStatusBoardType.Severity.UNKNOWN


## A context describing a healthy, ordinary level. Individual tests override
## only the key under test, so a threshold change fails one test, not twenty.
func _healthy_context() -> Dictionary:
	return {
		"has_root": true,
		"root_name": "Arena",
		"brush_count": 12,
		"entity_count": 3,
		"baked_count": 4,
		"dirty_brush_count": 0,
		"last_bake_ms": 120,
		"recommended_chunk_size": 0.0,
		"chunk_size": 32.0,
		"material_count": 6,
		"bake_use_face_materials": false,
		"spawn_count": 1,
		"auto_spawn_player": true,
		"autosave_enabled": true,
		"autosave_minutes": 5,
		"autosave_path": "res://.hammerforge/autosave.hflevel",
		"autosave_exists": true,
		"autosave_age_sec": 30,
		"log_warn": 0,
		"log_error": 0,
		"validation_run": true,
		"validation_issues": [],
		"validation_stamp": "10:04:11",
	}


func _find(checks: Array, id: String) -> Dictionary:
	for check in checks:
		if check["id"] == id:
			return check
	return {}


func _severity_of(ctx: Dictionary, id: String) -> int:
	return int(_find(HFStatusBoardType.evaluate(ctx), id).get("severity", -1))


# --- shape --------------------------------------------------------------


func test_every_check_carries_the_fields_the_panel_draws():
	for check in HFStatusBoardType.evaluate(_healthy_context()):
		for key in ["id", "title", "severity", "value", "detail", "help", "action_id"]:
			assert_true(check.has(key), "Check %s is missing %s" % [check.get("id", "?"), key])
		assert_ne(check["detail"], "", "Every light needs a practical sentence beside it")
		assert_ne(check["help"], "", "Every light needs a tooltip explaining its thresholds")


func test_a_check_with_an_action_always_labels_the_button():
	for check in HFStatusBoardType.evaluate({}):
		if check["action_id"] != "":
			assert_ne(check["action_label"], "", "%s has an action with no label" % check["id"])


func test_check_ids_are_unique():
	var seen := {}
	for check in HFStatusBoardType.evaluate(_healthy_context()):
		assert_false(seen.has(check["id"]), "Duplicate check id %s" % check["id"])
		seen[check["id"]] = true


func test_evaluate_survives_an_empty_context():
	var checks := HFStatusBoardType.evaluate({})
	assert_gt(checks.size(), 0, "An unopened editor still draws the board")


# --- level root ---------------------------------------------------------


func test_missing_level_root_is_red_and_offers_to_create_one():
	var check := _find(HFStatusBoardType.evaluate({}), "level_root")
	assert_eq(check["severity"], PROBLEM)
	assert_eq(check["action_id"], "create_starter")


func test_present_level_root_is_green_and_names_the_node():
	var check := _find(HFStatusBoardType.evaluate(_healthy_context()), "level_root")
	assert_eq(check["severity"], OK)
	assert_eq(check["value"], "Arena")


# --- geometry budget ----------------------------------------------------


func test_geometry_is_green_below_the_warn_threshold():
	assert_eq(_severity_of(_healthy_context(), "geometry"), OK)


func test_geometry_turns_amber_above_the_warn_threshold():
	var ctx := _healthy_context()
	ctx["brush_count"] = HFStatusBoardType.GEOMETRY_WARN + 1
	ctx["entity_count"] = 0
	assert_eq(_severity_of(ctx, "geometry"), WARN)


func test_geometry_turns_red_above_the_problem_threshold():
	var ctx := _healthy_context()
	ctx["brush_count"] = HFStatusBoardType.GEOMETRY_PROBLEM + 1
	ctx["entity_count"] = 0
	assert_eq(_severity_of(ctx, "geometry"), PROBLEM)


func test_geometry_counts_entities_towards_the_budget():
	var ctx := _healthy_context()
	ctx["brush_count"] = HFStatusBoardType.GEOMETRY_WARN
	ctx["entity_count"] = 1
	assert_eq(_severity_of(ctx, "geometry"), WARN, "Entities reconcile too, so they count")


func test_geometry_offers_the_recommended_chunk_size_when_it_differs():
	var ctx := _healthy_context()
	ctx["recommended_chunk_size"] = 64.0
	ctx["chunk_size"] = 32.0
	var check := _find(HFStatusBoardType.evaluate(ctx), "geometry")
	assert_eq(check["action_id"], "apply_chunk_size")
	assert_string_contains(check["action_label"], "64")


func test_geometry_offers_nothing_when_chunk_size_already_matches():
	var ctx := _healthy_context()
	ctx["recommended_chunk_size"] = 64.0
	ctx["chunk_size"] = 64.0
	assert_eq(_find(HFStatusBoardType.evaluate(ctx), "geometry")["action_id"], "")


func test_geometry_is_grey_without_a_level():
	assert_eq(_severity_of({}, "geometry"), UNKNOWN)


# --- bake ---------------------------------------------------------------


func test_empty_level_does_not_nag_about_baking():
	var ctx := _healthy_context()
	ctx["brush_count"] = 0
	ctx["baked_count"] = 0
	assert_eq(_severity_of(ctx, "bake"), UNKNOWN, "A brand new level is not a fault")


func test_unbaked_level_with_brushes_is_amber():
	var ctx := _healthy_context()
	ctx["baked_count"] = 0
	var check := _find(HFStatusBoardType.evaluate(ctx), "bake")
	assert_eq(check["severity"], WARN)
	assert_eq(check["action_id"], "bake")


func test_edits_since_the_last_bake_are_amber():
	var ctx := _healthy_context()
	ctx["dirty_brush_count"] = 7
	var check := _find(HFStatusBoardType.evaluate(ctx), "bake")
	assert_eq(check["severity"], WARN)
	assert_string_contains(check["value"], "7")


func test_clean_bake_reports_the_last_duration():
	var check := _find(HFStatusBoardType.evaluate(_healthy_context()), "bake")
	assert_eq(check["severity"], OK)
	assert_string_contains(check["detail"], "120 ms")


# --- validation ---------------------------------------------------------


func test_validation_not_yet_run_is_grey_and_offers_to_run():
	var ctx := _healthy_context()
	ctx["validation_run"] = false
	var check := _find(HFStatusBoardType.evaluate(ctx), "validation")
	assert_eq(check["severity"], UNKNOWN, "Never run is not the same as clean")
	assert_eq(check["action_id"], "validate")


func test_clean_validation_is_green_and_stamps_the_time():
	var check := _find(HFStatusBoardType.evaluate(_healthy_context()), "validation")
	assert_eq(check["severity"], OK)
	assert_string_contains(check["detail"], "10:04:11")


func test_a_few_validation_issues_are_amber_and_name_the_first():
	var ctx := _healthy_context()
	ctx["validation_issues"] = ["Brush 3 is zero-size", "Brush 9 is non-planar"]
	var check := _find(HFStatusBoardType.evaluate(ctx), "validation")
	assert_eq(check["severity"], WARN)
	assert_string_contains(check["detail"], "zero-size")
	assert_string_contains(check["detail"], "+1 more")


func test_many_validation_issues_are_red():
	var ctx := _healthy_context()
	var issues := []
	for i in range(HFStatusBoardType.VALIDATION_PROBLEM):
		issues.append("issue %d" % i)
	ctx["validation_issues"] = issues
	assert_eq(_severity_of(ctx, "validation"), PROBLEM)


# --- materials ----------------------------------------------------------


func test_empty_palette_is_amber_while_greyboxing():
	var ctx := _healthy_context()
	ctx["material_count"] = 0
	assert_eq(_severity_of(ctx, "materials"), WARN)


func test_empty_palette_is_red_when_face_materials_bake_is_on():
	var ctx := _healthy_context()
	ctx["material_count"] = 0
	ctx["bake_use_face_materials"] = true
	assert_eq(_severity_of(ctx, "materials"), PROBLEM, "That combination cannot bake correctly")


func test_loaded_palette_is_green():
	assert_eq(_severity_of(_healthy_context(), "materials"), OK)


# --- spawn --------------------------------------------------------------


func test_a_spawn_point_is_green():
	assert_eq(_severity_of(_healthy_context(), "spawn"), OK)


func test_no_spawn_with_auto_spawn_on_is_amber():
	var ctx := _healthy_context()
	ctx["spawn_count"] = 0
	assert_eq(_severity_of(ctx, "spawn"), WARN)


func test_no_spawn_with_auto_spawn_off_is_red():
	var ctx := _healthy_context()
	ctx["spawn_count"] = 0
	ctx["auto_spawn_player"] = false
	assert_eq(_severity_of(ctx, "spawn"), PROBLEM)


# --- autosave -----------------------------------------------------------


func test_autosave_off_is_amber_not_red():
	var ctx := _healthy_context()
	ctx["autosave_enabled"] = false
	var check := _find(HFStatusBoardType.evaluate(ctx), "autosave")
	assert_eq(check["severity"], WARN, "Turning autosave off is a choice, not a fault")
	assert_eq(check["action_id"], "enable_autosave")


func test_autosave_on_with_no_file_yet_is_amber():
	var ctx := _healthy_context()
	ctx["autosave_exists"] = false
	assert_eq(_severity_of(ctx, "autosave"), WARN)


func test_healthy_autosave_reports_age_and_path():
	var check := _find(HFStatusBoardType.evaluate(_healthy_context()), "autosave")
	assert_eq(check["severity"], OK)
	assert_string_contains(check["detail"], "30s")
	assert_string_contains(check["detail"], "autosave.hflevel")


# --- session log --------------------------------------------------------


func test_quiet_log_is_green():
	assert_eq(_severity_of(_healthy_context(), "log"), OK)


func test_warnings_make_the_log_amber():
	var ctx := _healthy_context()
	ctx["log_warn"] = 3
	assert_eq(_severity_of(ctx, "log"), WARN)


func test_errors_make_the_log_red_and_win_over_warnings():
	var ctx := _healthy_context()
	ctx["log_warn"] = 3
	ctx["log_error"] = 1
	var check := _find(HFStatusBoardType.evaluate(ctx), "log")
	assert_eq(check["severity"], PROBLEM)
	assert_string_contains(check["value"], "1 error")


# --- summary ------------------------------------------------------------


func test_summary_of_a_healthy_level_is_all_clear():
	var summary := HFStatusBoardType.summarise(HFStatusBoardType.evaluate(_healthy_context()))
	assert_eq(summary["severity"], OK)
	assert_eq(summary["label"], "All clear")


func test_summary_takes_the_worst_severity():
	var checks := [{"severity": OK}, {"severity": WARN}, {"severity": PROBLEM}]
	assert_eq(HFStatusBoardType.summarise(checks)["severity"], PROBLEM)


func test_summary_ignores_unknown_when_ranking():
	var checks := [{"severity": OK}, {"severity": UNKNOWN}]
	var summary := HFStatusBoardType.summarise(checks)
	assert_eq(summary["severity"], OK, "Not-measured must not read as a fault")
	assert_eq(summary["unknown"], 1)


func test_summary_of_nothing_measurable_is_unknown():
	var summary := HFStatusBoardType.summarise([{"severity": UNKNOWN}, {"severity": UNKNOWN}])
	assert_eq(summary["severity"], UNKNOWN)
	assert_eq(summary["label"], "Nothing to check yet")


func test_summary_counts_both_problems_and_warnings_in_its_label():
	var checks := [{"severity": PROBLEM}, {"severity": WARN}, {"severity": WARN}]
	var summary := HFStatusBoardType.summarise(checks)
	assert_string_contains(summary["label"], "1 problem")
	assert_string_contains(summary["label"], "2 to review")


func test_summary_of_an_empty_board_does_not_divide_by_zero():
	var summary := HFStatusBoardType.summarise([])
	assert_eq(summary["severity"], UNKNOWN)
	assert_eq(summary["total"], 0)


# --- helpers ------------------------------------------------------------


func test_format_duration_scales_with_the_gap():
	assert_eq(HFStatusBoardType.format_duration(0), "0s")
	assert_eq(HFStatusBoardType.format_duration(45), "45s")
	assert_eq(HFStatusBoardType.format_duration(600), "10m")
	assert_eq(HFStatusBoardType.format_duration(7200), "2h")
	assert_eq(HFStatusBoardType.format_duration(9000), "2h 30m")
	assert_eq(HFStatusBoardType.format_duration(172800), "2d")


func test_format_duration_of_a_negative_gap_is_not_negative():
	assert_eq(HFStatusBoardType.format_duration(-5), "0s")


func test_collect_context_without_a_level_root_is_safe():
	var ctx := HFStatusBoardType.collect_context(null, null)
	assert_false(ctx["has_root"])
	assert_eq(ctx["brush_count"], 0)


func test_collect_context_reads_log_counts():
	var buffer = HFConsoleLogType.new()
	buffer.warn("something")
	buffer.error("worse")
	var ctx := HFStatusBoardType.collect_context(null, buffer)
	assert_eq(ctx["log_warn"], 1)
	assert_eq(ctx["log_error"], 1)


func test_collect_context_lets_cached_results_through():
	var ctx := HFStatusBoardType.collect_context(
		null, null, {"validation_run": true, "validation_issues": ["cached issue"]}
	)
	assert_true(ctx["validation_run"])
	assert_eq(ctx["validation_issues"].size(), 1)


func test_geometry_thresholds_match_level_root_health():
	# The board recomputes the budget from raw counts so it can name the number
	# in the detail line, while LevelRoot keeps its own get_level_health(). If
	# one moves without the other, the dock and the console disagree on screen.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")
	assert_string_contains(
		source,
		"if total <= %d:" % HFStatusBoardType.GEOMETRY_WARN,
		"LevelRoot's healthy threshold drifted from HFStatusBoard.GEOMETRY_WARN"
	)
	assert_string_contains(
		source,
		"if total <= %d:" % HFStatusBoardType.GEOMETRY_PROBLEM,
		"LevelRoot's chunking threshold drifted from HFStatusBoard.GEOMETRY_PROBLEM"
	)


func test_shallow_collection_skips_the_whole_level_walks():
	# Both of these walk every brush and every face, so the once-a-second poll
	# must not pay for them.
	var probe := StatusProbe.new()
	autofree(probe)
	HFStatusBoardType.collect_context(probe, null, {}, false)
	assert_eq(probe.vertex_calls, 0, "Shallow collection must not estimate vertices")
	assert_eq(probe.chunk_calls, 0, "Shallow collection must not recompute the level AABB")
	HFStatusBoardType.collect_context(probe, null, {}, true)
	assert_eq(probe.vertex_calls, 1)
	assert_eq(probe.chunk_calls, 1)


class StatusProbe:
	extends Node

	var vertex_calls := 0
	var chunk_calls := 0

	func get_total_vertex_estimate() -> int:
		vertex_calls += 1
		return 0

	func get_recommended_chunk_size() -> float:
		chunk_calls += 1
		return 0.0
