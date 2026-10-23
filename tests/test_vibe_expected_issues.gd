extends GutTest

## A vibe scenario declares the issues it expects to reproduce, and one it did
## not see in a run is named as no longer reproducing (#1659).

const Scenario = preload("res://tools/vibe/hf_vibe_scenario.gd")


class Expects:
	extends "res://tools/vibe/hf_vibe_scenario.gd"

	func expected_issues() -> Array[int]:
		return [12, 34]


func test_a_declared_issue_that_did_not_show_is_named():
	var scenario := Expects.new()
	scenario.known(12, "still here")
	assert_eq(scenario.stale_issues(), [34] as Array[int])


func test_every_declared_issue_seen_names_none():
	var scenario := Expects.new()
	scenario.known(34, "here")
	scenario.known(12, "and here")
	assert_eq(scenario.stale_issues(), [] as Array[int])


func test_a_scenario_that_declares_nothing_names_nothing():
	var scenario := Scenario.new()
	scenario.known(99, "seen, never declared")
	assert_eq(scenario.stale_issues(), [] as Array[int])
