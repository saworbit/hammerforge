extends "res://tests/mcp/mcp_dispatcher_case.gd"

## `hf_validate` leaves out what was accepted for the level and counts it
## instead (#1731), so an agent does not "fix" what a mapper said was meant.

const HFAcceptedFindings = preload("res://addons/hammerforge/hf_accepted_findings.gd")


func _messages(reply: Dictionary) -> Array:
	var out: Array = []
	for issue in reply["result"]["issues"]:
		out.append(issue["message"])
	return out


func test_an_accepted_finding_is_counted_not_listed():
	var level := make_level()
	level.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 1, 4), "center": Vector3(0, -0.5, 0)}
	)
	var cut: DraftBrush = (
		level
		. create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(1, 1, 1),
				"center": Vector3(10, 3, 10),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
			}
		)
	)
	var first := await call_tool("hf_validate")
	assert_true(first.get("ok", false), str(first).left(200))
	assert_eq(int(first["result"].get("accepted", -1)), 0, "nothing accepted yet")
	var message := ""
	for finding in level.validate_level().get("findings", []):
		if finding.get("node") == cut:
			message = finding["message"]
			HFAcceptedFindings.accept(level, finding, "a cut for the next room")
	assert_ne(message, "", "fixture: the stray cut is found")
	assert_has(_messages(first), message, "and the bridge listed it")
	var second := await call_tool("hf_validate")
	assert_does_not_have(_messages(second), message, "accepted, it is not listed")
	assert_eq(int(second["result"]["accepted"]), 1, "it is counted")
	cut.global_position += Vector3(1, 0, 0)
	var third := await call_tool("hf_validate")
	var back := {}
	for issue in third["result"]["issues"]:
		if issue["message"] == message:
			back = issue
	assert_true(back.get("changed_since_accepted", false), "an edit brings it back, marked")
	assert_eq(str(back.get("check", "")), "overlap", "with the kind of check that found it")
