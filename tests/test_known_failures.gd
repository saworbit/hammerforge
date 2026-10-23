extends GutTest

## The sweeps' shared handling of their `KNOWN` maps (#1659), against a stand-in
## for the test it reports to.

const KnownFailures = preload("res://tests/support/known_failures.gd")


## Records what a sweep's case would have told GUT.
class Told:
	extends RefCounted
	var failed: Array = []
	var pended: Array = []
	var asserted: Array = []

	func fail_test(text: String) -> void:
		failed.append(text)

	func pending(text: String) -> void:
		pended.append(text)

	func assert_eq(got, want, text: String) -> void:
		asserted.append([got == want, text])

	func assert_not_null(got, text: String) -> void:
		asserted.append([got != null, text])


const KNOWN := {"hollow|pending_cut": "#1234: leaves the cut behind"}


func test_a_known_case_that_now_passes_fails_naming_the_entry_and_its_issue():
	var told := Told.new()
	KnownFailures.settle(told, KNOWN, "hollow|pending_cut", "hollow in pending_cut", [])
	assert_eq(told.failed, ["KNOWN entry 'hollow|pending_cut' (#1234) now passes. Remove it."])
	assert_eq(told.pended, [])


func test_a_known_case_that_still_fails_is_pending():
	var told := Told.new()
	KnownFailures.settle(told, KNOWN, "hollow|pending_cut", "hollow in pending_cut", ["a step"])
	assert_eq(told.failed, [])
	assert_eq(told.pended, ["hollow in pending_cut: #1234: leaves the cut behind"])


func test_any_other_case_must_find_nothing():
	var told := Told.new()
	KnownFailures.settle(told, KNOWN, "clip|nothing_selected", "clip", ["level changed"])
	assert_eq(told.asserted, [[false, "clip"]])
	told = Told.new()
	KnownFailures.settle(told, KNOWN, "clip|nothing_selected", "clip", [])
	assert_eq(told.asserted, [[true, "clip"]])


func test_an_entry_without_an_issue_number_fails_the_shape_check():
	var told := Told.new()
	var entries := {
		"a|b": "#12: fine",
		"c|d": "leaves the cut behind",
		"e|f": "#: no number",
		"g|h": "#12 no colon",
		"i|j": "#12: ",
	}
	KnownFailures.check_shape(told, entries)
	var passed: Array = told.asserted.map(func(entry): return entry[0])
	assert_eq(passed, [true, false, false, false, false])
	assert_string_contains(told.asserted[1][1], "'c|d'")
