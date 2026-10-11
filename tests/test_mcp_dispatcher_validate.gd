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


func test_a_micro_gap_names_both_brushes():
	# Two boxes half a millimetre apart: the finding is about the pair (#1037).
	var level := make_level()
	var one := await place_box([0, 1, 0], [2, 2, 2])
	var two := await place_box([2, 1, 0], [2, 2, 2])
	brush_node(level, two).global_position.x += 0.0005
	var r := await call_tool("hf_validate")
	var gaps := _of_type(r, "micro_gap")
	assert_eq(gaps.size(), 1, str(r["result"]["issues"]))
	if gaps.size() != 1:
		return
	var named := [gaps[0].get("brush_id"), gaps[0].get("other_brush_id")]
	named.sort()
	var expected := [one, two]
	expected.sort()
	assert_eq(named, expected, "both brush ids, so an agent can find the pair")


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


func test_status_carries_the_counts_of_the_last_validate():
	make_level()
	await place_box([0, 1, 0], [3000, 2, 2])
	await call_tool("hf_validate")
	var status := await call_tool("hf_get_status")
	var counts = status["result"]["validation"]
	assert_not_null(counts)
	assert_gte(int(counts["warning"]), 1)
	assert_eq(
		status["result"]["validation_revision"], status["result"]["revision"], "taken just now"
	)


func test_status_does_not_run_validate_after_a_change():
	# Status ran the whole Validate pass on the first call after any change, 650
	# ms on a 121-brush level (#1048). It says how old its counts are instead.
	make_level()
	await place_box([0, 1, 0], [3000, 2, 2])
	await call_tool("hf_validate")
	var taken := int((await call_tool("hf_get_status"))["result"]["validation_revision"])
	await place_box([0, 1, 40], [2, 2, 2])
	var status := await call_tool("hf_get_status")
	assert_eq(int(status["result"]["validation_revision"]), taken, "not worked out again")
	assert_gt(int(status["result"]["revision"]), taken, "and the agent can see they are older")


func test_status_has_no_counts_before_a_validate():
	make_level()
	await place_box()
	var status := await call_tool("hf_get_status")
	assert_null(status["result"]["validation"])
	assert_null(status["result"]["validation_revision"])


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
