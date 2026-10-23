extends RefCounted
## The `KNOWN` map a sweep keeps of the cases it found failing that are filed and
## not fixed yet, as `"case": "#N: reason"` (#1659).
##
## A known case still runs every check. One whose checks all pass fails the
## sweep, naming the entry and its issue, so a fixed bug comes off the list and
## its checks guard it again; one that still fails is pending. The keymap,
## palette, undo and bridge sweeps all settle their cases here, so the four
## cannot drift apart again, and the next sweep gets the same for nothing.

## What an entry's value must read like: an issue number, then why.
const SHAPE := "^#[0-9]+: [^ ]"


## Settle one case. `failures` describe what its checks found wrong, and are
## empty when it passed. `label` names the case for a person.
static func settle(
	test: Object, known: Dictionary, case: String, label: String, failures: Array
) -> void:
	if not known.has(case):
		test.assert_eq(failures, [], label)
		return
	if failures.is_empty():
		test.fail_test("KNOWN entry '%s' (%s) now passes. Remove it." % [case, issue(known[case])])
	else:
		test.pending("%s: %s" % [label, known[case]])


## The issue an entry names, "#N".
static func issue(value: Variant) -> String:
	return str(value).get_slice(":", 0)


## Fail every entry whose value is not "#N: reason".
static func check_shape(test: Object, known: Dictionary) -> void:
	var shape := RegEx.create_from_string(SHAPE)
	for case in known:
		test.assert_not_null(
			shape.search(str(known[case])),
			'KNOWN entry \'%s\' reads "#N: reason", not "%s"' % [case, known[case]]
		)
