extends "res://tests/mcp/mcp_dispatcher_case.gd"

## hf_validate: the level's problems as plain data, naming the brush or entity
## each is about. A read: it changes nothing, even when the level is a mess.


func _of_type(r: Dictionary, kind: String) -> Array:
	var found: Array = []
	for issue in r["result"]["issues"]:
		if issue["type"] == kind:
			found.append(issue)
	return found


func test_a_level_with_no_spawn_says_so_with_its_fix():
	var level := make_level()
	await place_box()
	var before := snapshot(level)
	var r := await call_tool("hf_validate")
	assert_true(r["ok"], str(r))
	var missing := _of_type(r, "missing_spawn")
	assert_eq(missing.size(), 1, str(r["result"]))
	assert_eq(missing[0]["severity"], "warning")
	assert_eq(missing[0]["fix"], "create_spawn")
	assert_eq_deep(snapshot(level), before)


func test_a_finding_names_its_brush():
	make_level()
	var big := await place_box([0, 1, 0], [3000, 2, 2])
	var r := await call_tool("hf_validate")
	var oversized := _of_type(r, "oversized")
	assert_eq(oversized.size(), 1, str(r["result"]["issues"]))
	assert_eq(oversized[0]["brush_id"], big)
	assert_eq(oversized[0]["severity"], "warning")


func test_an_error_is_counted_as_one():
	var level := make_level()
	var id := await place_box()
	brush_node(level, id).size = Vector3(0.005, 2, 2)
	var r := await call_tool("hf_validate")
	var degenerate := _of_type(r, "degenerate")
	assert_eq(degenerate.size(), 1, str(r["result"]["issues"]))
	assert_eq(degenerate[0]["severity"], "error")
	assert_eq(degenerate[0]["brush_id"], id)
	assert_gte(int(r["result"]["counts"]["error"]), 1)


func test_findings_are_not_repeated():
	make_level()
	await place_box()
	var r := await call_tool("hf_validate")
	var seen := {}
	for issue in r["result"]["issues"]:
		var key := "%s|%s|%s" % [issue["type"], issue["message"], issue.get("brush_id")]
		assert_false(seen.has(key), "listed twice: %s" % key)
		seen[key] = true


func test_status_carries_the_counts_for_this_revision():
	make_level()
	await place_box([0, 1, 0], [3000, 2, 2])
	var status := await call_tool("hf_get_status")
	var counts = status["result"]["validation"]
	assert_not_null(counts)
	assert_gte(int(counts["warning"]), 1)


func test_validate_needs_a_level():
	make_scene()
	assert_refused(await call_tool("hf_validate"), "no_level")


func test_the_same_problem_on_two_brushes_is_two_findings():
	var level := make_level()
	var one := await place_box([0, 1, 0], [3000, 2, 2])
	var two := await place_box([0, 1, 40], [3000, 2, 2])
	# One name under two parents, a brush and a committed cut: the same message
	# word for word.
	var moved := brush_node(level, two)
	moved.get_parent().remove_child(moved)
	level.committed_node.add_child(moved)
	brush_node(level, one).name = "Wall"
	moved.name = "Wall"
	var r := await call_tool("hf_validate")
	var named := []
	for issue in _of_type(r, "oversized"):
		named.append(issue["brush_id"])
	named.sort()
	var expected := [one, two]
	expected.sort()
	assert_eq(named, expected, str(r["result"]["issues"]))
